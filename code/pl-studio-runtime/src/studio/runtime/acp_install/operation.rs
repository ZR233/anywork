//! 单次安装操作的 supervisor：解析来源 → 等待资产锁 → 复用或下载 → 校验 → 解压 → 原子发布。
//!
//! 终态只在物理工作结束（下载库返回、阻塞阶段 join 完成、发布提交结果确定）之后发布；取消在每段
//! 协作点检查。进入发布提交必须通过 owner 锁内的 [`AcpInstallInner::try_enter_publish`]：任何先
//! 被接受的取消或关闭都会阻止 `rename`。每个阻塞阶段先登记到本操作的资源 owner 再等待，因此
//! supervisor 即使在 panic 后也能取回并 join 子任务、清理自有暂存后才释放 busy
//! （见 design/28 §28.6、§28.7）。

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, PoisonError};
use std::time::{Duration, Instant};

use pl_protocol::studio::{
    AcpInstallFailure, AcpInstallFailureCode, AcpInstallProgress, AcpInstallRelease,
    AcpInstallStage, AcpInstallState, AcpInstalledServer, AcpProvider,
};
use pl_tool::workspace::path_safety;
use tokio_util::sync::CancellationToken;

use super::archive::{self, ExpectedInstall, PublishOutcome};
use super::download::{self, ProgressSink};
use super::mapping::failure;
use super::paths::{self, ManagedRoot};
use super::registry::{
    AcpInstallInner, BusinessOutcome, Operation, PublishRejection, ResidueHold, begin_stage,
    register_lock_file, take_stage,
};
use super::source::{self, ResolvedRelease};

/// 资产锁轮询间隔；等待可取消，不删除锁文件。
const LOCK_POLL: Duration = Duration::from_millis(100);
/// 关闭时等待当前 supervisor 收束的预算。
pub(super) const JOIN_BUDGET: Duration = Duration::from_secs(5);
/// 进度合并间隔。
const PROGRESS_INTERVAL: Duration = Duration::from_millis(250);

/// 一次操作的启动意图。
pub(super) struct OperationPlan {
    pub(super) provider: AcpProvider,
}

/// supervisor 主体；终态与资源收尾在同一顺序里完成。
///
/// 只有清理**真正成功**才发布终态并释放准入；清理未收束时把整个 `Operation`（含未删除的暂存
/// 路径）与已算出的业务结果交给 owner 保管，槽位保持 `Closing` 非终态、准入继续占用，关闭阶段
/// 可以用同一份资源责任做有界重试（design/28 §28.6）。
pub(super) async fn run(
    inner: Arc<AcpInstallInner>,
    operation: Arc<Operation>,
    plan: OperationPlan,
) {
    let provider = operation.provider;
    let generation = operation.generation;
    let operation_id = operation.operation_id.clone();
    let outcome = execute(&inner, &operation, plan).await;
    match release_staging(&inner, &operation).await {
        Ok(()) => {
            let terminal = match outcome {
                Ok(server) => AcpInstallState::Ready {
                    operation_id,
                    server,
                },
                Err(failure) => AcpInstallState::Failed {
                    operation_id,
                    failure,
                },
            };
            inner.complete_operation(provider, generation, terminal);
        }
        Err(cleanup_failure) => {
            // 两种失败互不覆盖：业务结果原样保管、清理失败作为 typed 摘要保管，两者都等清理
            // 成功后才转入对外终态（业务失败不会被 ResourceClose 覆盖，反之亦然）。
            inner.hold_residue(
                provider,
                ResidueHold {
                    operation: Arc::clone(&operation),
                    operation_id,
                    business: match outcome {
                        Ok(server) => BusinessOutcome::Ready(server),
                        Err(failure) => BusinessOutcome::Failed(failure),
                    },
                    cleanup_failure,
                },
            );
        }
    }
}

async fn execute(
    inner: &Arc<AcpInstallInner>,
    operation: &Arc<Operation>,
    plan: OperationPlan,
) -> Result<AcpInstalledServer, AcpInstallFailure> {
    let provider = plan.provider;
    let generation = operation.generation;
    let operation_id = operation.operation_id.clone();
    let cancel = operation.cancel.clone();
    let context = StageContext {
        inner,
        operation,
        provider,
        generation,
        cancel: &cancel,
    };
    let publish_state =
        |state: AcpInstallState| inner.publish_progress(provider, generation, state);

    publish_state(AcpInstallState::Resolving {
        operation_id: operation_id.clone(),
    });
    // 客户端构造失败即 typed 失败传播，不回退到更弱的默认 client。
    // 产品固定清单：纯本地解析，不联网、不接受任意版本或地址。
    let resolved = source::resolve(provider)?;
    let installation_id = source::installation_id(provider, &resolved);
    // 存储键必须是 `sha256:` + 64 位小写十六进制；不合格身份不参与任何路径拼接。
    // 存储键必须是 `sha256:` + 64 位小写十六进制；不合格身份不参与任何路径拼接。
    // installation id 由本模块的 canonical 摘要产生，正常情况必然合格：该分支是不变量护栏，
    // 因此按"存储身份不可用"归类为不可重试失败。
    let storage_key = source::storage_key(&installation_id).ok_or_else(|| {
        failure(
            AcpInstallFailureCode::CacheCorrupt,
            AcpInstallStage::Resolve,
            false,
        )
    })?;
    publish_state(AcpInstallState::Waiting {
        operation_id: operation_id.clone(),
        release: resolved.release.clone(),
    });

    let home = inner.store.paths().home().to_path_buf();
    let root_path = inner.store.acp_servers_root();
    let root = blocking(&context, AcpInstallStage::WaitForLock, move || {
        ManagedRoot::open(&home, root_path, AcpInstallStage::WaitForLock)
    })
    .await?;
    // 跨进程同一资产互斥；等待可取消，锁文件永久保留。
    // 资产锁纳入本操作的资源 owner：worker panic 时不会随栈帧先释放，另进程无法提前进入；
    // 只有在所有阶段任务 join 且 cleanup 结果确认之后（终态发布或残留收束完成）才随之释放。
    let asset_lock = wait_for_lock(&root, provider, &resolved.release.target, &cancel).await?;
    register_lock_file(operation, asset_lock, AcpInstallStage::WaitForLock)?;

    let installed = installed_dir(&root, provider, &resolved, &storage_key)?;
    if root.probe(&installed, AcpInstallStage::Verify)?.is_some() {
        return reuse_installed(
            inner,
            &root,
            &installed,
            &resolved,
            &installation_id,
            operation,
        )
        .await;
    }

    publish_state(AcpInstallState::Downloading {
        operation_id: operation_id.clone(),
        release: resolved.release.clone(),
        progress: AcpInstallProgress::empty(),
        retry_count: 0,
    });
    let downloads = root.ensure_dir(
        &["downloads", provider.as_str(), &resolved.release.target],
        AcpInstallStage::Download,
    )?;
    let archive_path = downloads.join(format!("{storage_key}.zip"));
    validate_download_paths(&root, &archive_path)?;
    let sink = download_sink(inner, operation, &resolved.release);
    let client = downlowd::Client::builder()
        .reqwest_client(source::archive_client()?)
        .max_retries(Some(3))
        .build()
        .map_err(|_| {
            failure(
                AcpInstallFailureCode::Network,
                AcpInstallStage::Download,
                true,
            )
        })?;
    let download_url = resolved.release.archive_url.clone();
    let download_path = archive_path.clone();
    let download_cancel = cancel.clone();
    // sidecar 重建闭包：路径与权限核对复用本模块的产品边界（缺失则 0600 新建，随后再核验）。
    let sidecar_root = root.clone();
    let sidecar_path = download_paths(&archive_path)[2].clone();
    let ensure_sidecar: download::SidecarEnsure = std::sync::Arc::new(move || {
        let stage = AcpInstallStage::Download;
        if sidecar_root.require_private_file(&sidecar_path, stage)? {
            return Ok(());
        }
        create_private_download_file(&sidecar_path, stage)?;
        sidecar_root.require_private_file(&sidecar_path, stage)?;
        Ok(())
    });
    let downloaded = stage_task(&context, AcpInstallStage::Download, async move {
        download::download(
            &client,
            &download_url,
            &download_path,
            sink,
            ensure_sidecar,
            &download_cancel,
        )
        .await
    })
    .await?;
    let total_bytes = downloaded.total;
    // 下载库写出的目标与同名 sidecar 必须仍是安装根内的真实普通文件。
    let archive_metadata = root
        .probe(&archive_path, AcpInstallStage::Verify)?
        .filter(|metadata| metadata.is_file())
        .ok_or_else(|| failure(AcpInstallFailureCode::Io, AcpInstallStage::Verify, true))?;
    verify_download_sidecars(&root, &archive_path)?;

    publish_state(AcpInstallState::Verifying {
        operation_id: operation_id.clone(),
        release: resolved.release.clone(),
        progress: AcpInstallProgress {
            completed_bytes: 0,
            total_bytes: Some(archive_metadata.len()),
            bytes_per_second: None,
        },
    });
    let verify_progress = progress_emitter(
        inner,
        provider,
        generation,
        operation_id.clone(),
        resolved.release.clone(),
        ProgressState::Verifying,
    );
    let hash_path = archive_path.clone();
    let hash_cancel = cancel.clone();
    let archive_sha256 = blocking(&context, AcpInstallStage::Verify, move || {
        archive::sha256_file(&hash_path, &hash_cancel, verify_progress.as_ref())
    })
    .await?;
    if let Some(expected) = resolved.release.sha256.as_ref()
        && expected != &archive_sha256
    {
        return Err(failure(
            AcpInstallFailureCode::ChecksumMismatch,
            AcpInstallStage::Verify,
            false,
        ));
    }

    publish_state(AcpInstallState::Extracting {
        operation_id: operation_id.clone(),
        release: resolved.release.clone(),
        progress: AcpInstallProgress {
            completed_bytes: 0,
            total_bytes,
            bytes_per_second: None,
        },
    });
    let staging_root = root.ensure_dir(&["staging"], AcpInstallStage::Extract)?;
    // 私有暂存：用 tempfile 官方 Builder 权限 API 在**创建时**就设成 Unix 0700（不依赖 umask、
    // 不先宽后收），Windows 走继承 ACL；创建后立刻用同一私有性核验收口，失败即失败。
    let mut staging_builder = tempfile::Builder::new();
    staging_builder.prefix("acp-server-");
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        staging_builder.permissions(std::fs::Permissions::from_mode(0o700));
    }
    let staging = staging_builder
        .tempdir_in(&staging_root)
        .map_err(|_| failure(AcpInstallFailureCode::Io, AcpInstallStage::Extract, true))?;
    let staging_path = staging.path().to_path_buf();
    root.require_private_directory(&staging_path, AcpInstallStage::Extract)?;
    register_staging(operation, &staging_path);

    let extract_progress = progress_emitter(
        inner,
        provider,
        generation,
        operation_id.clone(),
        resolved.release.clone(),
        ProgressState::Extracting,
    );
    let extract_root = root.clone();
    let archive_for_extract = archive_path.clone();
    let staging_for_extract = staging_path.clone();
    let installation_for_extract = installation_id.clone();
    let release_for_extract = resolved.release.clone();
    let resolved_for_extract = resolved.clone();
    let sha_for_extract = archive_sha256.clone();
    let cancel_for_extract = cancel.clone();
    let receipt = blocking(&context, AcpInstallStage::Extract, move || {
        let receipt = archive::extract(
            archive::ExtractInput {
                archive: &archive_for_extract,
                staging: &staging_for_extract,
                installation_id: &installation_for_extract,
                release: &release_for_extract,
                command: &resolved_for_extract.command,
                args: &resolved_for_extract.args,
                archive_sha256: &sha_for_extract,
                cancellation: &cancel_for_extract,
            },
            &extract_root,
            extract_progress.as_ref(),
        )?;
        archive::write_receipt(&extract_root, &staging_for_extract, &receipt)?;
        Ok(receipt)
    })
    .await?;

    // 发布提交点：owner 锁内裁决；被接受的取消/关闭先线性化，绝不 rename。
    match inner.try_enter_publish(provider, generation, &resolved.release) {
        Ok(_) => {}
        Err(PublishRejection::Cancelled) => {
            return Err(failure(
                AcpInstallFailureCode::Cancelled,
                AcpInstallStage::Publish,
                true,
            ));
        }
        Err(PublishRejection::Superseded) => {
            return Err(failure(
                AcpInstallFailureCode::StaleOperation,
                AcpInstallStage::Publish,
                false,
            ));
        }
    }
    let publish_root = root.clone();
    let publish_target = installed.clone();
    let staging_for_publish = staging_path.clone();
    let outcome = blocking(&context, AcpInstallStage::Publish, move || {
        archive::publish(&publish_root, &staging_for_publish, &publish_target)
    })
    .await?;

    match outcome {
        PublishOutcome::Confirmed => mark_committed(operation),
        PublishOutcome::CommittedButUnconfirmed => {
            // 移动已提交：暂存已不存在，资源 owner 不再持有可清理的暂存。
            mark_committed(operation);
            // 安装已是既成事实：不删、不覆盖、不谎称回滚；失败摘要明确"可能已发布"。
            return Err(archive::unconfirmed_publish_failure());
        }
    }

    let program = installed.join(&receipt.command);
    Ok(AcpInstalledServer {
        installation_id,
        release: resolved.release,
        program: program.to_string_lossy().into_owned(),
        ready_at: crate::studio::unix_seconds(),
        reused: false,
    })
}

/// 复用既有完整安装：冻结描述符、完整树集合、mode/size/hash 与入口全部复核，损坏保留现场。
async fn reuse_installed(
    inner: &Arc<AcpInstallInner>,
    root: &ManagedRoot,
    installed: &Path,
    resolved: &ResolvedRelease,
    installation_id: &str,
    operation: &Arc<Operation>,
) -> Result<AcpInstalledServer, AcpInstallFailure> {
    let cancel = operation.cancel.clone();
    let context = StageContext {
        inner,
        operation,
        provider: operation.provider,
        generation: operation.generation,
        cancel: &cancel,
    };
    let verify_progress = progress_emitter(
        inner,
        operation.provider,
        operation.generation,
        operation.operation_id.clone(),
        resolved.release.clone(),
        ProgressState::Verifying,
    );
    let verify_root = root.clone();
    let installed_for_verify = installed.to_path_buf();
    let release_for_verify = resolved.release.clone();
    let command_for_verify = resolved.command.clone();
    let args_for_verify = resolved.args.clone();
    let id_for_verify = installation_id.to_string();
    let cancel_for_verify = cancel.clone();
    let receipt = blocking(&context, AcpInstallStage::Verify, move || {
        archive::verify_installed(
            &verify_root,
            &installed_for_verify,
            ExpectedInstall {
                installation_id: &id_for_verify,
                release: &release_for_verify,
                command: &command_for_verify,
                args: &args_for_verify,
            },
            &cancel_for_verify,
            verify_progress.as_ref(),
        )
    })
    .await?;

    let durable_root = root.clone();
    let installed_for_durable = installed.to_path_buf();
    let receipt_for_durable = receipt.clone();
    let durable = blocking(&context, AcpInstallStage::Verify, move || {
        Ok(archive::confirm_durable(
            &durable_root,
            &installed_for_durable,
            &receipt_for_durable,
        ))
    })
    .await?;
    if !durable {
        // 复用补齐持久化屏障失败：与首次发布未确认同语义，保留现场供下次重试。
        return Err(archive::unconfirmed_publish_failure());
    }

    let program = installed.join(&receipt.command);
    Ok(AcpInstalledServer {
        installation_id: receipt.installation_id,
        release: receipt.release,
        program: program.to_string_lossy().into_owned(),
        ready_at: crate::studio::unix_seconds(),
        reused: true,
    })
}

/// 阻塞阶段的操作身份：取消时用于发布收束中状态，并把子任务登记到资源 owner。
struct StageContext<'a> {
    inner: &'a Arc<AcpInstallInner>,
    operation: &'a Arc<Operation>,
    provider: AcpProvider,
    generation: u64,
    cancel: &'a CancellationToken,
}

/// 在 owner 的受管阶段里执行一段工作：任务句柄先登记到资源 owner、再等待结果。
///
/// 结果通过 oneshot 送回，句柄本身留在 [`Operation`] 的资源 owner 里；因此 `run` 即使 panic，
/// supervisor 仍能取回并 join 它。取消只发布 `Closing` 并继续等待真实 join，绝不以丢弃句柄冒充
/// 收束。网络阶段（下载）与阻塞阶段（校验/解压/发布）共用这一个出口，所以两者的回收责任形状
/// 完全一致（design/28 §28.6 "安装 owner 持有下载、校验/解压任务、文件和锁的回收责任"）。
async fn stage_task<T, F>(
    context: &StageContext<'_>,
    stage: AcpInstallStage,
    work: F,
) -> Result<T, AcpInstallFailure>
where
    T: Send + 'static,
    F: std::future::Future<Output = Result<T, AcpInstallFailure>> + Send + 'static,
{
    // 先占槽（同步、无 await、不可取消），再 spawn，最后装填：句柄一旦创建就必然进入 owner，
    // 既没有"创建后登记失败"的窗口，也不会让局部变量成为最后的 owner。
    let reservation = begin_stage(context.operation, stage)?;
    let (sender, mut receiver) = tokio::sync::oneshot::channel();
    let task = tokio::spawn(async move {
        let result = work.await;
        let _ = sender.send(result);
    });
    reservation.install(task);
    let joined = tokio::select! {
        received = &mut receiver => received.unwrap_or_else(|_| Err(failure(
            AcpInstallFailureCode::ResourceClose,
            stage,
            true,
        ))),
        _ = context.cancel.cancelled() => {
            context.inner.publish_closing(
                context.provider,
                context.generation,
                Some(failure(AcpInstallFailureCode::Cancelled, stage, true)),
            );
            (&mut receiver).await.unwrap_or_else(|_| Err(failure(
                AcpInstallFailureCode::ResourceClose,
                stage,
                true,
            )))
        }
    };
    // 结果已到：经租约取回并 join 已完成的阶段任务；中途被丢弃则句柄回到 owner。
    match take_stage(context.operation, stage)? {
        Some(mut lease) => {
            let _ = lease.handle_mut().await;
            lease.disarm();
        }
        // 刚装填过的槽不可能是空闲：这是不变式破坏，按资源问题如实失败，不当作已完成。
        None => {
            return Err(failure(AcpInstallFailureCode::ResourceClose, stage, false));
        }
    }
    joined
}

/// 阻塞阶段：把同步工作放进阻塞池，但仍登记同一个 join 出口。
async fn blocking<T: Send + 'static>(
    context: &StageContext<'_>,
    stage: AcpInstallStage,
    work: impl FnOnce() -> Result<T, AcpInstallFailure> + Send + 'static,
) -> Result<T, AcpInstallFailure> {
    stage_task(context, stage, async move {
        match tokio::task::spawn_blocking(work).await {
            Ok(result) => result,
            // 阻塞任务 panic 视为本地资源问题；不伪造成功，也不泄露 panic 文本。
            Err(_) => Err(failure(AcpInstallFailureCode::Io, stage, true)),
        }
    })
    .await
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ProgressState {
    Verifying,
    Extracting,
}

/// 有界合并的阶段进度发布器：约 250ms 一次，最后一个字节必发。
fn progress_emitter(
    inner: &Arc<AcpInstallInner>,
    provider: AcpProvider,
    generation: u64,
    operation_id: String,
    release: AcpInstallRelease,
    state: ProgressState,
) -> Arc<dyn Fn(u64, Option<u64>) + Send + Sync> {
    let inner = Arc::clone(inner);
    let last = Mutex::new(None::<Instant>);
    Arc::new(move |completed: u64, total: Option<u64>| {
        let due = {
            let mut last = last.lock().unwrap_or_else(PoisonError::into_inner);
            let due = last.is_none_or(|previous| previous.elapsed() >= PROGRESS_INTERVAL)
                || total.is_some_and(|total| completed >= total);
            if due {
                *last = Some(Instant::now());
            }
            due
        };
        if !due {
            return;
        }
        let progress = AcpInstallProgress {
            completed_bytes: completed,
            total_bytes: total,
            bytes_per_second: None,
        };
        let next = match state {
            ProgressState::Verifying => AcpInstallState::Verifying {
                operation_id: operation_id.clone(),
                release: release.clone(),
                progress,
            },
            ProgressState::Extracting => AcpInstallState::Extracting {
                operation_id: operation_id.clone(),
                release: release.clone(),
                progress,
            },
        };
        inner.publish_progress(provider, generation, next);
    })
}

fn installed_dir(
    root: &ManagedRoot,
    provider: AcpProvider,
    resolved: &ResolvedRelease,
    storage_key: &str,
) -> Result<PathBuf, AcpInstallFailure> {
    root.ensure_dir(
        &["installed", provider.as_str(), &resolved.release.target],
        AcpInstallStage::Publish,
    )?;
    Ok(paths::installed_path(
        root,
        provider.as_str(),
        &resolved.release.target,
        storage_key,
    ))
}

fn download_sink(
    inner: &Arc<AcpInstallInner>,
    operation: &Arc<Operation>,
    release: &AcpInstallRelease,
) -> ProgressSink {
    let inner = Arc::clone(inner);
    let operation_id = operation.operation_id.clone();
    let provider = operation.provider;
    let generation = operation.generation;
    let release = release.clone();
    Arc::new(move |progress: AcpInstallProgress, retry_count: u32| {
        inner.publish_progress(
            provider,
            generation,
            AcpInstallState::Downloading {
                operation_id: operation_id.clone(),
                release: release.clone(),
                progress,
                retry_count,
            },
        );
    })
}

fn register_staging(operation: &Operation, staging: &Path) {
    operation
        .resources
        .lock()
        .unwrap_or_else(PoisonError::into_inner)
        .staging = Some(staging.to_path_buf());
}

fn mark_committed(operation: &Operation) {
    let mut resources = operation
        .resources
        .lock()
        .unwrap_or_else(PoisonError::into_inner);
    resources.committed = true;
    resources.staging = None;
}

/// 自有暂存的最终收尾（supervisor 的 panic 路径也复用它）。
///
/// 已提交时不触碰已发布目录；清理任务同样登记到资源 owner 并 join，因此等待期间即使调用方被
/// panic 打断，删除任务也不会脱管。
pub(super) async fn release_staging(
    inner: &Arc<AcpInstallInner>,
    operation: &Arc<Operation>,
) -> Result<(), AcpInstallFailure> {
    // 上一轮（例如外层预算取消而中途返回）可能留下已登记/借用中的阶段任务：先接续并 join 它，
    // 绝不重建覆盖，也不在它仍可能写盘时开始删除。
    join_stage(operation, AcpInstallStage::Close).await?;
    // 先按引用取路径，删除**成功之后**才清槽：失败时责任仍留在 owner 手里，不会因为一次 take
    // 就把"还在磁盘上的暂存"变成无人负责的孤儿。
    let staging = {
        let resources = operation
            .resources
            .lock()
            .unwrap_or_else(PoisonError::into_inner);
        if resources.committed {
            None
        } else {
            resources.staging.clone()
        }
    };
    let Some(staging) = staging else {
        return Ok(());
    };
    let home = inner.store.paths().home().to_path_buf();
    let root = inner.store.acp_servers_root();
    // 清理同样是 owner 登记的阶段任务：**先占槽**（同步、无 await），再 spawn，再装填；`run` 在
    // 等待期间 panic 时 supervisor 仍能 join 它，不会留下无人负责的删除任务。
    let reservation = begin_stage(operation, AcpInstallStage::Close)?;
    let removal_target = staging.clone();
    let (sender, receiver) = tokio::sync::oneshot::channel();
    let task = tokio::spawn(async move {
        let result = tokio::task::spawn_blocking(move || {
            let managed = ManagedRoot::open(&home, root, AcpInstallStage::Extract)?;
            managed.remove_owned_tree(&removal_target, AcpInstallStage::Extract)
        })
        .await
        .unwrap_or_else(|_| {
            Err(failure(
                AcpInstallFailureCode::ResourceClose,
                AcpInstallStage::Close,
                true,
            ))
        });
        let _ = sender.send(result);
    });
    reservation.install(task);
    let result = receiver.await.unwrap_or_else(|_| {
        Err(failure(
            AcpInstallFailureCode::ResourceClose,
            AcpInstallStage::Close,
            true,
        ))
    });
    match take_stage(operation, AcpInstallStage::Close) {
        Ok(Some(mut lease)) => {
            let _ = lease.handle_mut().await;
            lease.disarm();
        }
        // 刚装填的槽不可能空闲：不变式破坏按资源问题失败，不当作删除已完成。
        Ok(None) => {
            return Err(failure(
                AcpInstallFailureCode::ResourceClose,
                AcpInstallStage::Close,
                false,
            ));
        }
        Err(failure) => return Err(failure),
    }
    match result {
        Ok(()) => {
            let mut resources = operation
                .resources
                .lock()
                .unwrap_or_else(PoisonError::into_inner);
            if resources.staging.as_deref() == Some(staging.as_path()) {
                resources.staging = None;
            }
            Ok(())
        }
        Err(cleanup_failure) => {
            // 清理未确认收束：暂存路径仍留在 `resources.staging`，由调用方把**真实 Operation**
            // 交给 owner 保管（而不是只留一份摘要）。
            Err(cleanup_failure)
        }
    }
}

/// 接续并 join 本操作已登记的阶段任务（若有）。
///
/// - `Ok`：槽空闲（无需接续）或取到句柄并已 join 完成；
/// - `Err(ResourceClose)`：槽正被另一个租约借用（不变式破坏），fail-closed 且不动槽。
pub(super) async fn join_stage(
    operation: &Arc<Operation>,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    match take_stage(operation, stage)? {
        Some(mut lease) => {
            let _ = lease.handle_mut().await;
            lease.disarm();
            Ok(())
        }
        None => Ok(()),
    }
}

/// 下载目标及其 `.part`/`.downloadinfo` sidecar 都必须是安装根内的普通文件路径。
fn validate_download_paths(root: &ManagedRoot, archive: &Path) -> Result<(), AcpInstallFailure> {
    let stage = AcpInstallStage::Download;
    let [final_path, part_path, sidecar_path] = download_paths(archive);
    root.validate_write(&final_path, stage)?;
    // final 由库用 rename 生成（继承 part 的权限），不预创建，避免影响 resume 判定。
    root.require_private_file(&final_path, stage)?;
    for path in [&part_path, &sidecar_path] {
        root.validate_write(path, stage)?;
        if root.require_private_file(path, stage)? {
            continue;
        }
        // `downlowd` 0.1.4 用 `OpenOptions::create(true).write(true)` 打开 part 与 sidecar，没有
        // 公开的权限配置项；两处都是"存在则复用、打开后 truncate/seek"，因此在私有父目录内
        // 预创建空文件既不改 resume 语义，也不破坏 sidecar 语义，只是把权限固定成 0600。
        create_private_download_file(path, stage)?;
        root.require_private_file(path, stage)?;
    }
    Ok(())
}

/// 以显式 0600 创建一个空的下载辅助文件；已存在时由调用方处理。
fn create_private_download_file(
    path: &Path,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    let mut options = std::fs::OpenOptions::new();
    options.create_new(true).write(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options
        .open(path)
        .map(|_| ())
        .map_err(|_| failure(AcpInstallFailureCode::Io, stage, true))
}

/// 下载完成后再次确认 sidecar 没有变成链接/特殊文件。
fn verify_download_sidecars(root: &ManagedRoot, archive: &Path) -> Result<(), AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    for path in download_paths(archive) {
        root.validate_existing_or_missing(&path, stage)?;
        root.require_private_file(&path, stage)?;
    }
    Ok(())
}

/// `downlowd` 0.1.4 的 `Destination`：final、`.part`、`.downloadinfo`（同目录）。
fn download_paths(archive: &Path) -> [PathBuf; 3] {
    let mut part = archive.as_os_str().to_os_string();
    part.push(".part");
    let mut sidecar = archive.as_os_str().to_os_string();
    sidecar.push(".downloadinfo");
    [
        archive.to_path_buf(),
        PathBuf::from(part),
        PathBuf::from(sidecar),
    ]
}

/// 等待该资产的跨进程锁；等待期间可取消，锁文件永久保留且绝不跟随链接。
async fn wait_for_lock(
    root: &ManagedRoot,
    provider: AcpProvider,
    target: &str,
    cancel: &CancellationToken,
) -> Result<std::fs::File, AcpInstallFailure> {
    let stage = AcpInstallStage::WaitForLock;
    let directory = root.ensure_dir(&["locks", provider.as_str()], stage)?;
    let path = directory.join(format!("{target}.lock"));
    root.validate_write(&path, stage)?;
    let file = open_lock_file(&path, stage)?;
    root.probe(&path, stage)?;
    loop {
        if cancel.is_cancelled() {
            return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
        }
        // 显式走 fs4 的跨进程文件锁；std 的同名固有方法不参与判断。
        match fs4::FileExt::try_lock(&file) {
            Ok(()) => return Ok(file),
            Err(fs4::TryLockError::WouldBlock) => {
                tokio::select! {
                    _ = cancel.cancelled() => {
                        return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
                    }
                    _ = tokio::time::sleep(LOCK_POLL) => {}
                }
            }
            Err(fs4::TryLockError::Error(_)) => {
                return Err(failure(AcpInstallFailureCode::Io, stage, true));
            }
        }
    }
}

/// 打开（必要时独占创建）锁文件；既有的链接/reparse 一律拒绝。
fn open_lock_file(path: &Path, stage: AcpInstallStage) -> Result<std::fs::File, AcpInstallFailure> {
    match std::fs::symlink_metadata(path) {
        Ok(metadata) => {
            if path_safety::is_link_or_reparse(&metadata) || !metadata.is_file() {
                return Err(failure(AcpInstallFailureCode::Io, stage, false));
            }
            // 既有锁文件同样要满足私有性（Windows：真实 owner+DACL），再交给跨进程锁。
            super::private_acl::verify_private_object(path, false, stage)?;
            std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(path)
                .map_err(|_| failure(AcpInstallFailureCode::Io, stage, true))
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            // 显式 0600：不依赖进程 umask（实测宿主机 umask=0002 时默认 0666 会变成 0664，
            // 被私有性检查正确拒绝）。只在创建时设置，不改既有文件、不改全局 umask。
            let mut options = std::fs::OpenOptions::new();
            options.create_new(true).read(true).write(true);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                options.mode(0o600);
            }
            let file = options
                .open(path)
                .map_err(|_| failure(AcpInstallFailureCode::Io, stage, true))?;
            // 新建锁文件在交给跨进程锁之前核验私有性（Unix：无宽写/特殊位；Windows：真实 owner+DACL）。
            super::private_acl::verify_private_object(path, false, stage)?;
            Ok(file)
        }
        Err(_) => Err(failure(AcpInstallFailureCode::Io, stage, true)),
    }
}
