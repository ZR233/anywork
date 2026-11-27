use std::sync::Arc;

use tokio_util::sync::CancellationToken;

use crate::config::{ConfigRuntime, ConfigStore};
use crate::studio::runtime_lock::{RuntimeLock, RuntimeLockOwner};
use crate::studio::runtime_options::ResolvedRuntimeOptions;
use crate::studio::startup::{StartupBackup, input_error};
use crate::{StudioStartupError, StudioStartupErrorKind, StudioStartupStage, StudioStore};

use super::super::StudioRuntime;
use super::super::observation_lifecycle::{
    ObservationCloseError, ObserverOpenResult, ObserverTask, RuntimeObserver,
};

type Observer = Arc<dyn Fn(StudioStartupStage) + Send + Sync>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum StartupPurpose {
    Standard,
    AcpCli,
}

enum StartupSource {
    Options(crate::StudioRuntimeOptions, StartupPurpose),
    Lease(crate::StudioInstanceLease),
}

impl StudioRuntime {
    /// Initializes all global state before returning a usable runtime.
    pub async fn initialize(
        options: crate::StudioRuntimeOptions,
    ) -> Result<Self, StudioStartupError> {
        Self::initialize_with_observer(options, Arc::new(|_| {})).await
    }

    /// Initializes for noninteractive ACP with CLI options and an existing Studio home.
    /// Native online catalog discovery is deferred and Native credentials are checked on use.
    pub async fn initialize_acp_cli(
        options: crate::StudioRuntimeOptions,
    ) -> Result<Self, StudioStartupError> {
        Self::initialize_source(
            StartupSource::Options(options, StartupPurpose::AcpCli),
            Arc::new(|_| {}),
        )
        .await
    }

    /// The observer is nonblocking and must not reenter initialization.
    /// Cancellation requests cleanup; the owned task retains the process lock until cleanup ends.
    pub async fn initialize_with_observer(
        options: crate::StudioRuntimeOptions,
        observer: Observer,
    ) -> Result<Self, StudioStartupError> {
        Self::initialize_source(
            StartupSource::Options(options, StartupPurpose::Standard),
            observer,
        )
        .await
    }

    /// Initializes with a lease already acquired by the native desktop host, without relocking.
    /// The host must retain its own lease until its process ends. Observer and cancellation
    /// semantics are the same as `initialize_with_observer`.
    pub async fn initialize_with_lease(
        lease: crate::StudioInstanceLease,
        observer: Observer,
    ) -> Result<Self, StudioStartupError> {
        Self::initialize_source(StartupSource::Lease(lease), observer).await
    }

    async fn initialize_source(
        source: StartupSource,
        observer: Observer,
    ) -> Result<Self, StudioStartupError> {
        let cancellation = CancellationToken::new();
        let guard = cancellation.clone().drop_guard();
        let (sender, receiver) = tokio::sync::oneshot::channel();
        let (accepted, acceptance) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            let result = Self::initialize_owned(source, observer.clone(), cancellation).await;
            if result.is_err() {
                observer(StudioStartupStage::Failed);
            }
            let retained = result.as_ref().ok().cloned();
            let delivered = sender.send(result).is_ok();
            if let Some(runtime) = retained {
                if delivered && acceptance.await.is_ok() {
                    observer(StudioStartupStage::Ready);
                    return;
                }
                if let Err(error) = runtime.dispose_startup().await {
                    tracing::error!(step = error.step, kind = ?error.kind, "cancelled startup cleanup failed");
                }
                observer(StudioStartupStage::Failed);
            }
        });
        let result = receiver
            .await
            .map_err(|error| internal("startup_owner", error))?;
        let _ = accepted.send(());
        guard.disarm();
        result
    }

    async fn initialize_owned(
        source: StartupSource,
        observer: Observer,
        cancellation: CancellationToken,
    ) -> Result<Self, StudioStartupError> {
        let _timing = crate::startup_timing::Stage::new("initialize_studio");
        let (resolved, lock, purpose) = match source {
            StartupSource::Lease(lease) => (lease.resolved, lease.lock, StartupPurpose::Standard),
            StartupSource::Options(options, purpose) => {
                if purpose == StartupPurpose::AcpCli && options.host != crate::StudioHostKind::Cli {
                    return Err(StudioStartupError::new(
                        "resolve_paths",
                        StudioStartupErrorKind::Configuration,
                        anyhow::anyhow!("ACP CLI startup requires CLI host options"),
                    ));
                }
                let resolved = options
                    .resolve()
                    .map_err(|error| environment("resolve_paths", error))?;
                let lock_path = resolved.paths.runtime_lock();
                let host = resolved.host;
                let lock =
                    tokio::task::spawn_blocking(move || RuntimeLock::acquire(&lock_path, host))
                        .await
                        .map_err(|error| internal("acquire_lock", error))?
                        .map_err(|error| environment("acquire_lock", error))?;
                (Arc::new(resolved), Arc::new(lock), purpose)
            }
        };
        let home = resolved.paths.home().to_owned();
        let policy = resolved.startup_policy;
        let mut backup = tokio::task::spawn_blocking(move || match policy {
            crate::StudioStartupPolicy::Strict => {
                if StartupBackup::recovery_required(&home)
                    .map_err(|error| environment("inspect_recovery", error))?
                {
                    return Err(StudioStartupError::new(
                        "inspect_recovery",
                        StudioStartupErrorKind::RecoveryRequired,
                        anyhow::anyhow!(
                            "recoveryRequired: unfinished startup recovery; original materials preserved"
                        ),
                    ));
                }
                Ok(None)
            }
            crate::StudioStartupPolicy::InteractiveRecovery => {
                StartupBackup::resume(&home).map_err(|error| environment("resume_backup", error))
            }
        })
        .await
        .map_err(|error| internal("resume_backup", error))??;
        if backup.is_some() {
            observer(StudioStartupStage::Resetting);
        }
        loop {
            check_cancelled(&cancellation)?;
            let attempt =
                match crate::studio::startup::storage_layout::prepare(&resolved.paths).await {
                    Ok(()) => {
                        Self::prepare_attempt(
                            &resolved,
                            purpose,
                            &observer,
                            &cancellation,
                            backup.is_some(),
                        )
                        .await
                    }
                    Err(error) => Err(StudioStartupError::input("prepare_layout", error)),
                };
            match attempt {
                Ok(mut runtime) => {
                    if let Err(error) = check_cancelled(&cancellation) {
                        runtime.dispose_startup().await?;
                        return Err(error);
                    }
                    runtime.startup_recovery = backup.as_ref().map(StartupBackup::report);
                    if let Some(mut completed) = backup.take() {
                        let completion =
                            tokio::task::spawn_blocking(move || completed.complete()).await;
                        if let Err(error) = completion
                            .map_err(|error| internal("complete_backup", error))
                            .and_then(|result| {
                                result.map_err(|error| environment("complete_backup", error))
                            })
                        {
                            runtime.dispose_startup().await?;
                            return Err(error);
                        }
                    }
                    runtime.instance_lock = RuntimeLockOwner::new(Some(lock));
                    if let Err(error) = check_cancelled(&cancellation) {
                        runtime.dispose_startup().await?;
                        return Err(error);
                    }
                    return Ok(runtime);
                }
                Err(error)
                    if matches!(
                        error.kind,
                        StudioStartupErrorKind::PersistentData | StudioStartupErrorKind::Migration
                    ) && backup.is_none()
                        && resolved.startup_policy
                            == crate::StudioStartupPolicy::InteractiveRecovery =>
                {
                    check_cancelled(&cancellation)?;
                    observer(StudioStartupStage::BackingUp);
                    let home = resolved.paths.home().to_owned();
                    let reason = match error.step {
                        "prepare_layout" => "本地数据布局不受支持或迁移数据无效",
                        "prepare_configuration" => "配置数据损坏、版本不受支持或引用无效",
                        "prepare_storage" => "本地存储或调用日志数据损坏、版本不受支持",
                        "directories" => "产品目录数据损坏或引用无效",
                        "worktree_leases" => "资源归属记录损坏或引用无效",
                        _ => "持久化缓存数据损坏或版本不受支持",
                    }
                    .to_owned();
                    backup = Some(
                        tokio::task::spawn_blocking(move || StartupBackup::begin(&home, reason))
                            .await
                            .map_err(|error| internal("backup", error))?
                            .map_err(|error| environment("backup", error))?,
                    );
                    observer(StudioStartupStage::Resetting);
                }
                Err(error) => return Err(error),
            }
        }
    }

    async fn prepare_attempt(
        resolved: &ResolvedRuntimeOptions,
        purpose: StartupPurpose,
        observer: &Observer,
        cancellation: &CancellationToken,
        recovering: bool,
    ) -> Result<Self, StudioStartupError> {
        observer(StudioStartupStage::Preparing);
        let config_store = match resolved.host {
            crate::StudioHostKind::Test => ConfigStore::new(resolved.paths.config_paths()),
            crate::StudioHostKind::Cli if purpose == StartupPurpose::AcpCli => {
                ConfigStore::for_acp_cli(resolved.paths.home().to_owned())
            }
            crate::StudioHostKind::Cli => ConfigStore::for_cli(resolved.paths.home().to_owned()),
            crate::StudioHostKind::Desktop | crate::StudioHostKind::HttpServer => {
                ConfigStore::for_studio_home(resolved.paths.home().to_owned())
            }
        };
        let config_store = if resolved.startup_policy == crate::StudioStartupPolicy::Strict {
            config_store.require_existing()
        } else {
            config_store
        };
        observer(StudioStartupStage::WaitingForSteps);
        // join! deliberately waits for both results: a failing config cannot detach a database open.
        let (store, config) = tokio::join!(
            async {
                let _timing = crate::startup_timing::Stage::new("prepare_storage");
                StudioStore::prepare_database(&resolved.paths.database())
                    .await
                    .map_err(|error| StudioStartupError::input("prepare_storage", error))
            },
            async {
                let _timing = crate::startup_timing::Stage::new("prepare_configuration");
                tokio::task::spawn_blocking(move || {
                    let runtime = ConfigRuntime::initialize(config_store.clone())?;
                    if recovering {
                        config_store.save(runtime.read()?.canonical_config())?;
                    }
                    Ok::<_, crate::ConfigRuntimeError>(runtime)
                })
                .await
                .map_err(|error| internal("prepare_configuration", error))?
                .map_err(|error| {
                    StudioStartupError::input("prepare_configuration", input_error(error))
                })
            }
        );
        let (store, config) = match (store, config) {
            (Ok(store), Ok(config)) => (store, config),
            (Ok(store), Err(error)) => {
                observer(StudioStartupStage::ClosingResources);
                store
                    .close()
                    .await
                    .map_err(|error| environment("close_storage", error))?;
                return Err(error);
            }
            (Err(storage), Err(config)) => return Err(prefer_environment(storage, config)),
            (Err(error), Ok(_)) => return Err(error),
        };
        let assembled = Self::assemble(super::builder::RuntimeAssemblyParts {
            store: store.clone(),
            config_runtime: config,
            system_skills_dir: resolved.paths.system_skills_dir(),
            helper_source: resolved.helper_source.clone(),
            host_mcp_source: resolved.host_mcp_source.clone(),
            ssh_config: resolved.ssh_config.clone(),
            skill_search: resolved.skill_search.clone(),
            run_export: resolved.run_export.clone(),
        })
        .await;
        let runtime = match assembled {
            Ok(runtime) => runtime,
            Err(error) => {
                store
                    .close()
                    .await
                    .map_err(|error| environment("close_storage", error))?;
                return Err(StudioStartupError::input("assemble", error));
            }
        };
        let allow_remote_acp_check = !matches!(resolved.host, crate::StudioHostKind::Test);
        let prepared = runtime
            .prepare_global(observer, cancellation, allow_remote_acp_check, purpose)
            .await;
        if let Err(error) = prepared {
            observer(StudioStartupStage::ClosingResources);
            runtime.dispose_startup().await?;
            return Err(error);
        }
        Ok(runtime)
    }

    async fn prepare_global(
        &self,
        observer: &Observer,
        cancellation: &CancellationToken,
        allow_remote_acp_check: bool,
        purpose: StartupPurpose,
    ) -> Result<(), StudioStartupError> {
        self.runtime_state
            .apply(crate::studio::StudioRuntimeCommand::BeginInitialize {
                expected_revision: self.runtime_state.snapshot().revision,
                at: crate::studio::unix_seconds(),
            })
            .map_err(|error| internal("begin_initialize", error))?;
        observer(StudioStartupStage::ReadingProjects);
        let (usage, performance, directory, leases, ssh, skills) = tokio::join!(
            timed_step("prepare_account_usage", self.account_usage.load_cache()),
            timed_step(
                "prepare_model_performance",
                self.model_performance.load_cache()
            ),
            timed_step(
                "prepare_directories",
                self.agent_facility.product_events.initialize_directories()
            ),
            timed_step(
                "prepare_resource_ownership",
                crate::studio::worktree::worktree_lease::load_leases(&self.store)
            ),
            timed_step("prepare_remote_configuration", self.hydrate_ssh_servers()),
            timed_step("prepare_system_skills", self.skills.refresh_system_skills())
        );
        let mut failures = Vec::new();
        for (step, result) in [
            ("account_usage", usage),
            ("model_performance", performance),
            ("directories", directory),
            ("system_skills", skills),
        ] {
            if let Err(error) = result {
                failures.push(StudioStartupError::input(step, error));
            }
        }
        match leases {
            Ok(leases) => self
                .thread_factory
                .restore_workspace_admission(leases)
                .await
                .map_err(|error| StudioStartupError::input("restore_workspace_admission", error))?,
            Err(error) => failures.push(StudioStartupError::input("worktree_leases", error)),
        }
        // Global SSH config is outside the product backup boundary; its diagnostic is independent.
        if let Err(error) = ssh {
            failures.push(environment("remote_configuration", error));
        }
        if let Some(error) = failures.into_iter().reduce(prefer_environment) {
            return Err(error);
        }
        // 有界展示投影在启动时显式建立一次：已有调用的统计/费用立即成为最新首帧；
        // 查询路径只读该投影，不再承担建立/写盘职责。
        self.model_performance.initialize_projection().await;
        check_cancelled(cancellation)?;
        self.publish_settings_state()
            .map_err(|error| internal("publish_settings", error))?;
        observer(StudioStartupStage::StartingServices);
        // Mode catalog 只在真实注册变化时发布；内置注册是第一次装载事实。
        let _ = self
            .agent_facility
            .product_events
            .emit_thread_mode_catalog(self.thread_modes.snapshot().catalog().clone());
        // Agent Profiles 资源由配置 owner 持有；先发布已装载事实，再转发后续命令变更。
        // 首帧发布失败不让启动失败：订阅者仍可通过查询基线取得当前事实。
        match self.read_agent_profiles_state() {
            Ok(state) => {
                let _ = self
                    .agent_facility
                    .product_events
                    .emit_agent_profiles_state(state);
            }
            Err(error) => {
                tracing::warn!(%error, "Agent Profiles initial publication failed");
            }
        }
        // 配置 watch 转发由 runtime 持有；失败路径由 `dispose_startup` 取消并等待。
        self.start_agent_profiles_forwarder()
            .await
            .map_err(|error| observer_start_error("start_agent_profiles", error))?;
        self.store.calls().start().await;
        let writer = self
            .agent_facility
            .persistence
            .lock()
            .await
            .clone()
            .ok_or_else(|| {
                internal(
                    "start_persistence",
                    anyhow::anyhow!("missing persistence owner"),
                )
            })?;
        self.start_persistence_observer(writer)
            .await
            .map_err(|error| {
                observer_start_error(
                    "start_persistence_observer",
                    super::super::observation_lifecycle::ObservationStartError(error).into(),
                )
            })?;
        self.start_model_refresh()
            .await
            .map_err(|error| observer_start_error("start_model_refresh", error))?;
        if purpose == StartupPurpose::Standard {
            self.start_model_catalog_probes()
                .await
                .map_err(|error| internal("start_model_catalogs", error))?;
        }
        self.start_tool_refresh().await;
        self.acp_install
            .start_background_check(allow_remote_acp_check);
        self.start_lsp_state_watcher()
            .await
            .map_err(|error| observer_start_error("start_lsp_state", error))?;
        check_cancelled(cancellation)?;
        self.runtime_state
            .apply(crate::studio::StudioRuntimeCommand::FinishInitialize {
                expected_revision: self.runtime_state.snapshot().revision,
                at: crate::studio::unix_seconds(),
            })
            .map_err(|error| internal("finish_initialize", error))?;
        self.bots
            .load()
            .await
            .map_err(|error| internal("prepare_bots", anyhow::Error::from(error.studio_error())))?;
        self.start_recovery_scan().await;
        Ok(())
    }

    fn start_persistence_observer(
        &self,
        writer: crate::studio::storage::write_behind::ThreadWriteBehindWriter,
    ) -> impl std::future::Future<Output = ObserverOpenResult> + Send + 'static {
        let bus = self.agent_facility.product_events.clone();
        let threads = self.store.thread_persistence().clone();
        self.observations.start(
            RuntimeObserver::Persistence,
            move |cancellation| async move {
                // 两个通知接收者都在作用域登记后创建；未启动的 future 不持观察需求。
                let task = bus.observe_persistence(
                    writer.subscribe_state(),
                    threads.subscribe(),
                    cancellation.clone(),
                );
                Ok(ObserverTask::new(cancellation, task))
            },
        )
    }

    pub(super) async fn dispose_startup(&self) -> Result<(), StudioStartupError> {
        // 在任何 join 前通知所有独立 owner；投影的当前迭代只能自然收束。
        self.broadcast_cancel().await;
        // All independent cleanup runs even when one task reports an error.
        let (usage, catalogs, results, acp_cleanup, observers, sessions) = tokio::join!(
            self.account_usage.close(),
            self.stop_model_catalog_probes(),
            async {
                tokio::join!(
                    self.stop_recovery_scan(),
                    self.stop_model_refresh(),
                    self.stop_tool_refresh(),
                )
            },
            async {
                tokio::join!(
                    self.acp_accounts.cancel_and_join(),
                    self.acp_install.cancel_and_join(),
                )
            },
            async {
                tokio::join!(
                    self.observations.close(RuntimeObserver::Lsp, None),
                    self.observations.close(RuntimeObserver::Profiles, None),
                    self.observations.close(RuntimeObserver::Persistence, None),
                )
            },
            self.shutdown_agent_framework(),
        );
        let lsp = if sessions.is_ok() && observers.0.is_clean() {
            self.start_lsp_stop()
                .await
                .join()
                .await
                .map_err(anyhow::Error::from)
        } else {
            Err(anyhow::anyhow!(
                "Session or LSP projection resources have not closed; shared LSP retained"
            ))
        };
        let ssh = if sessions.is_ok() && lsp.is_ok() {
            self.start_ssh_stop()
                .await
                .join()
                .await
                .map_err(anyhow::Error::from)
        } else {
            Err(anyhow::anyhow!(
                "Session or LSP resources have not closed; shared SSH retained"
            ))
        };
        // Clone (never `take`) the retained writer first, then stop it, and only drop the retained
        // owner once the writer actually stopped; a failed stop keeps the owner out of circulation.
        let writer = self.agent_facility.persistence.lock().await.clone();
        let persistence = match writer {
            Some(writer) if sessions.is_ok() => {
                let result = writer.shutdown().await;
                if result.is_ok() {
                    self.agent_facility.persistence.lock().await.take();
                }
                result.map_err(anyhow::Error::from)
            }
            Some(_) => Err(anyhow::anyhow!(
                "Session resources have not closed; shared writer retained"
            )),
            None => Ok(()),
        };
        let bots = self.bots.shutdown().await;
        let storage = if sessions.is_ok() {
            self.store.close().await
        } else {
            Err(anyhow::anyhow!(
                "Session resources have not closed; storage retained"
            ))
        };
        catalogs.map_err(|error| internal("stop_model_catalogs", error))?;
        usage.map_err(|error| internal("stop_account_usage", error))?;
        for result in [
            results.0,
            results.1,
            results.2,
            acp_cleanup.0,
            acp_cleanup.1,
        ] {
            result.map_err(|error| internal("stop_services", error))?;
        }
        // 保留原有失败优先级：服务（LSP、Profiles）先于 persistence observer。
        for (step, report) in [
            ("stop_services", observers.0),
            ("stop_services", observers.1),
            ("stop_persistence_observer", observers.2),
        ] {
            if !report.is_clean() {
                return Err(internal(step, ObservationCloseError(report)));
            }
        }
        sessions.map_err(|error| internal("close_sessions", error))?;
        lsp.map_err(|error| internal("close_lsp", error))?;
        ssh.map_err(|error| environment("close_ssh", error))?;
        persistence.map_err(|error| environment("close_writer", error))?;
        bots.map_err(|error| environment("close_bots", anyhow::Error::from(error.studio_error())))?;
        storage.map_err(|error| environment("close_storage", error))?;
        self.instance_lock.release();
        Ok(())
    }
}

fn prefer_environment(first: StudioStartupError, second: StudioStartupError) -> StudioStartupError {
    tracing::error!(step = second.step, kind = ?second.kind, "additional startup step failed");
    if matches!(
        first.kind,
        StudioStartupErrorKind::PersistentData | StudioStartupErrorKind::Migration
    ) && !matches!(
        second.kind,
        StudioStartupErrorKind::PersistentData | StudioStartupErrorKind::Migration
    ) {
        second
    } else {
        first
    }
}

fn internal(step: &'static str, source: impl Into<anyhow::Error>) -> StudioStartupError {
    StudioStartupError::new(step, StudioStartupErrorKind::Internal, source)
}

fn observer_start_error(step: &'static str, source: anyhow::Error) -> StudioStartupError {
    let cancelled = source
        .downcast_ref::<super::super::observation_lifecycle::ObservationStartError>()
        .is_some_and(|error| {
            matches!(
                error.0.as_ref(),
                pl_lifecycle::OpenError::Cancelled | pl_lifecycle::OpenError::ScopeClosed
            )
        });
    StudioStartupError::new(
        step,
        if cancelled {
            StudioStartupErrorKind::Cancelled
        } else {
            StudioStartupErrorKind::Internal
        },
        source,
    )
}

fn environment(step: &'static str, source: impl Into<anyhow::Error>) -> StudioStartupError {
    StudioStartupError::new(step, StudioStartupErrorKind::Environment, source)
}

fn check_cancelled(cancellation: &CancellationToken) -> Result<(), StudioStartupError> {
    if cancellation.is_cancelled() {
        Err(StudioStartupError::new(
            "cancelled",
            StudioStartupErrorKind::Cancelled,
            anyhow::anyhow!("startup cancelled"),
        ))
    } else {
        Ok(())
    }
}

async fn timed_step<F: std::future::Future>(name: &'static str, future: F) -> F::Output {
    let _timing = crate::startup_timing::Stage::new(name);
    future.await
}

#[cfg(test)]
mod observer_start_tests {
    use super::*;
    use crate::studio::runtime::observation_lifecycle::{
        ObservationStartError, RuntimeObservationOwner,
    };

    #[tokio::test]
    async fn acp_cli_rejects_desktop_options_before_preparing_paths() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let options = crate::StudioRuntimeOptions {
            studio_home: Some(directory.path().join("desktop")),
            ..crate::StudioRuntimeOptions::desktop()
        };
        let error = match StudioRuntime::initialize_acp_cli(options).await {
            Ok(runtime) => {
                runtime.shutdown_runtime().await?;
                anyhow::bail!("ACP CLI accepted desktop host options");
            }
            Err(error) => error,
        };
        assert_eq!(error.kind, StudioStartupErrorKind::Configuration);
        assert!(std::fs::read_dir(directory.path())?.next().is_none());
        Ok(())
    }

    #[tokio::test]
    async fn persistence_receivers_are_created_only_after_scope_admission() -> anyhow::Result<()> {
        use crate::studio::runtime::bot_archive_test_host::BotArchiveTestHost;

        let temp = tempfile::tempdir()?;
        let host = BotArchiveTestHost::new(temp.path()).await?;
        let writer = host
            .runtime
            .agent_facility
            .persistence
            .lock()
            .await
            .clone()
            .expect("initialized persistence owner");
        let threads = host.runtime.store.thread_persistence().clone();
        let counts = || {
            (
                writer.state_subscriber_count_for_test(),
                threads.state_subscriber_count_for_test(),
            )
        };
        let baseline = counts();
        let mut runtime = host.runtime.as_ref().clone();
        runtime.observations = Arc::new(RuntimeObservationOwner::new());

        let unpolled = runtime.start_persistence_observer(writer.clone());
        assert_eq!(counts(), baseline);
        runtime.observations.request_close();
        assert!(
            runtime
                .observations
                .close(RuntimeObserver::Persistence, None)
                .await
                .is_clean()
        );
        assert!(matches!(
            unpolled.await,
            Err(error) if matches!(error.as_ref(), pl_lifecycle::OpenError::ScopeClosed)
        ));
        assert_eq!(counts(), baseline);

        runtime.observations = Arc::new(RuntimeObservationOwner::new());
        let started = runtime
            .start_persistence_observer(writer.clone())
            .await
            .map_err(ObservationStartError)?;
        assert_eq!(counts(), (baseline.0 + 1, baseline.1 + 1));
        runtime.observations.request_close();
        assert!(
            runtime
                .observations
                .close(RuntimeObserver::Persistence, None)
                .await
                .is_clean()
        );
        assert_eq!(counts(), baseline);
        drop(started);
        drop(runtime);
        host.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[test]
    fn startup_observer_errors_keep_original_source_and_cancel_classification() {
        for (source, kind) in [
            (
                pl_lifecycle::OpenError::ScopeClosed,
                StudioStartupErrorKind::Cancelled,
            ),
            (
                pl_lifecycle::OpenError::Cancelled,
                StudioStartupErrorKind::Cancelled,
            ),
            (
                pl_lifecycle::OpenError::Panicked,
                StudioStartupErrorKind::Internal,
            ),
            (
                pl_lifecycle::OpenError::WorkerStopped,
                StudioStartupErrorKind::Internal,
            ),
        ] {
            let source = Arc::new(source);
            let error = observer_start_error(
                "start_lsp_state",
                ObservationStartError(source.clone()).into(),
            );
            assert_eq!(error.kind, kind);
            assert_eq!(error.step, "start_lsp_state");
            let retained = std::error::Error::source(&error)
                .unwrap()
                .downcast_ref::<ObservationStartError>()
                .expect("original typed startup error");
            assert!(Arc::ptr_eq(&source, &retained.0));
        }
    }
}

#[cfg(test)]
mod startup_fault_tests;
