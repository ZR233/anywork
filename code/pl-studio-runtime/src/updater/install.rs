use super::client::StudioUpdater;
use super::error::{StudioUpdateError, StudioUpdateErrorCode};
use super::manifest::validate_update;
use super::types::{StudioUpdate, StudioUpdateEvent};
use minisign_verify::{PublicKey, Signature};
use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::Ordering;

use tokio::io::AsyncWriteExt;
use tokio::sync::mpsc::Sender;
use tokio_util::sync::CancellationToken;
use url::Url;

const MAX_SIGNATURE_BYTES: u64 = 16 * 1024;

/// 已验证的安装包及只读租约；Windows 上拒绝其他进程写入或删除该文件。
/// 租约必须保持至安装器真正派生，不能从持久化状态或路径重新构造。
pub struct PreparedStudioUpdate {
    path: PathBuf,
    lease: Option<std::fs::File>,
}

struct CachedInstaller {
    path: PathBuf,
    lock: std::fs::File,
}

#[derive(Clone, Copy)]
pub enum StudioUpdateLaunch {
    Restart,
    OnExit,
}

impl PreparedStudioUpdate {
    /// 交接给独立安装器；安装器等待当前进程退出后才开始安装。
    ///
    /// # Errors
    /// 当前平台不支持安装，或操作系统拒绝创建安装器进程。
    pub fn launch(&mut self, mode: StudioUpdateLaunch) -> Result<(), StudioUpdateError> {
        if self.lease.is_none() {
            return Err(StudioUpdateError::new(
                StudioUpdateErrorCode::CancellationTooLate,
                "the verified installer has already been handed off",
            ));
        }
        launch_installer(&self.path, mode)?;
        self.lease.take();
        Ok(())
    }
}

/// 只负责准备阶段的取消；安装交接属于已完成准备后的退出流程。
#[derive(Clone, Default)]
pub struct StudioUpdateCancellation {
    token: CancellationToken,
}

impl StudioUpdateCancellation {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn cancel(&self) {
        self.token.cancel();
    }

    /// 等待取消广播，不转移操作的完成与回收责任。
    pub async fn cancelled(&self) {
        self.token.cancelled().await;
    }

    fn check(&self) -> Result<(), StudioUpdateError> {
        if self.token.is_cancelled() {
            return Err(cancelled_error());
        }
        Ok(())
    }
}

pub(super) async fn download(
    updater: &StudioUpdater,
    update: StudioUpdate,
    progress: Sender<StudioUpdateEvent>,
    cancellation: StudioUpdateCancellation,
) -> Result<PreparedStudioUpdate, StudioUpdateError> {
    let _guard = InstallGuard::acquire(updater)?;
    let result: Result<PreparedStudioUpdate, StudioUpdateError> = async {
        validate_update(&update)?;
        cancellation.check()?;
        send_event(
            &progress,
            StudioUpdateEvent::Started {
                total: update.installer.size,
            },
        )
        .await?;
        let cached = prepare_installer(updater, &update, &progress, &cancellation).await?;
        let prepared = lease_verified_installer(updater, &update, cached).await?;
        cancellation.check()?;
        Ok(prepared)
    }
    .await;
    if let Err(error) = &result {
        send_event(
            &progress,
            StudioUpdateEvent::Failed {
                code: error.code().as_str().to_string(),
                message: error.to_string(),
            },
        )
        .await?;
    }
    result
}

async fn lease_verified_installer(
    updater: &StudioUpdater,
    update: &StudioUpdate,
    cached: CachedInstaller,
) -> Result<PreparedStudioUpdate, StudioUpdateError> {
    let public_key = updater.public_key;
    let asset = update.installer.clone();
    tokio::task::spawn_blocking(move || {
        let CachedInstaller {
            path,
            lock: _cache_lock,
        } = cached;
        let mut options = std::fs::OpenOptions::new();
        options.read(true);
        #[cfg(windows)]
        {
            use std::os::windows::fs::OpenOptionsExt;
            options.share_mode(1); // FILE_SHARE_READ：校验与派生之间不能修改安装包。
        }
        let mut lease = options.open(&path).map_err(io_error)?;
        if lease.metadata().map_err(io_error)?.len() != asset.size {
            return Err(StudioUpdateError::new(
                StudioUpdateErrorCode::DownloadIncomplete,
                "cached installer size changed",
            ));
        }
        let signature_text =
            std::fs::read_to_string(format!("{}.minisig", path.display())).map_err(io_error)?;
        let signature = Signature::decode(&signature_text).map_err(signature_error)?;
        let key = PublicKey::decode(public_key).map_err(signature_error)?;
        let mut verifier = key.verify_stream(&signature).map_err(signature_error)?;
        let mut hasher = Sha256::new();
        let mut buffer = [0_u8; 64 * 1024];
        loop {
            let count = lease.read(&mut buffer).map_err(io_error)?;
            if count == 0 {
                break;
            }
            hasher.update(&buffer[..count]);
            verifier.update(&buffer[..count]);
        }
        if hex::encode(hasher.finalize()) != asset.sha256 {
            return Err(StudioUpdateError::new(
                StudioUpdateErrorCode::HashMismatch,
                "leased installer SHA-256 does not match the manifest",
            ));
        }
        verifier.finalize().map_err(signature_error)?;
        Ok(PreparedStudioUpdate {
            path,
            lease: Some(lease),
        })
    })
    .await
    .map_err(|error| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::Io,
            format!("installer lease verification failed: {error}"),
        )
    })?
}

async fn prepare_installer(
    updater: &StudioUpdater,
    update: &StudioUpdate,
    progress: &Sender<StudioUpdateEvent>,
    cancellation: &StudioUpdateCancellation,
) -> Result<CachedInstaller, StudioUpdateError> {
    cancellation.check()?;
    let version_dir = updater.cache_dir.join(&update.version);
    tokio::fs::create_dir_all(&version_dir)
        .await
        .map_err(io_error)?;
    let lock = lock_cache(version_dir.join("download.lock")).await?;
    let filename = asset_filename(&update.installer.url)?;
    let installer = version_dir.join(&filename);
    let signature = version_dir.join(format!("{filename}.minisig"));

    if installer.is_file()
        && signature.is_file()
        && verify_cached(
            updater,
            update,
            &installer,
            &signature,
            progress,
            cancellation,
        )
        .await?
    {
        return Ok(CachedInstaller {
            path: installer,
            lock,
        });
    }
    remove_if_exists(&installer).await?;
    remove_if_exists(&signature).await?;

    let signature_url = Url::parse(&update.installer.signature).map_err(|error| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::InvalidManifest,
            format!("invalid signature URL: {error}"),
        )
    })?;
    let signature_bytes = tokio::select! {
        _ = cancellation.token.cancelled() => return Err(cancelled_error()),
        result = updater.request_bytes(signature_url, MAX_SIGNATURE_BYTES) => result?,
    };
    cancellation.check()?;
    let signature_partial = PathBuf::from(format!("{}.partial", signature.display()));
    remove_if_exists(&signature_partial).await?;
    let signature_result = async {
        write_partial(&signature_partial, &signature_bytes).await?;
        rename_replacing(&signature_partial, &signature).await
    }
    .await;
    if let Err(error) = signature_result {
        let _ = remove_if_exists(&signature_partial).await;
        return Err(error);
    }

    // The content address binds the library's partial/checkpoint files to this manifest even
    // if a Release asset was replaced under the same version/filename.
    let partial = version_dir.join(format!("{filename}.{}.partial", update.installer.sha256));
    let prepare_result = async {
        super::transfer::download(
            &updater.downloader,
            update.installer.clone(),
            partial.clone(),
            progress.clone(),
            cancellation.token.clone(),
        )
        .await?;
        cancellation.check()?;
        send_event(progress, StudioUpdateEvent::Verifying).await?;
        if hash_file(&partial).await? != update.installer.sha256 {
            return Err(StudioUpdateError::new(
                StudioUpdateErrorCode::HashMismatch,
                "installer SHA-256 does not match the manifest",
            ));
        }
        cancellation.check()?;
        verify_file(updater.public_key, &signature, &partial).await
    }
    .await;
    if let Err(error) = prepare_result {
        if matches!(
            error.code(),
            StudioUpdateErrorCode::HashMismatch
                | StudioUpdateErrorCode::SignatureInvalid
                | StudioUpdateErrorCode::DownloadTooLarge
        ) {
            remove_download(&partial).await?;
        }
        return Err(error);
    }
    rename_replacing(&partial, &installer).await?;
    Ok(CachedInstaller {
        path: installer,
        lock,
    })
}

async fn remove_download(destination: &Path) -> Result<(), StudioUpdateError> {
    remove_if_exists(destination).await?;
    for extension in ["part", "downloadinfo"] {
        let mut path = destination.as_os_str().to_owned();
        path.push(format!(".{extension}"));
        remove_if_exists(Path::new(&path)).await?;
    }
    Ok(())
}

async fn lock_cache(path: PathBuf) -> Result<std::fs::File, StudioUpdateError> {
    tokio::task::spawn_blocking(move || {
        let file = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(&path)
            .map_err(io_error)?;
        match fs4::FileExt::try_lock(&file) {
            Ok(()) => Ok(file),
            Err(fs4::TryLockError::WouldBlock) => Err(StudioUpdateError::new(
                StudioUpdateErrorCode::InstallInProgress,
                "another process owns this update cache",
            )),
            Err(fs4::TryLockError::Error(error)) => Err(io_error(error)),
        }
    })
    .await
    .map_err(|error| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::Io,
            format!("update cache lock task failed: {error}"),
        )
    })?
}

async fn verify_cached(
    updater: &StudioUpdater,
    update: &StudioUpdate,
    installer: &Path,
    signature: &Path,
    progress: &Sender<StudioUpdateEvent>,
    cancellation: &StudioUpdateCancellation,
) -> Result<bool, StudioUpdateError> {
    cancellation.check()?;
    if tokio::fs::metadata(installer)
        .await
        .map_err(io_error)?
        .len()
        != update.installer.size
    {
        return Ok(false);
    }
    let actual_hash = hash_file(installer).await?;
    cancellation.check()?;
    if actual_hash != update.installer.sha256 {
        return Ok(false);
    }
    match verify_file(updater.public_key, signature, installer).await {
        Ok(()) => {
            send_event(
                progress,
                StudioUpdateEvent::Progress {
                    downloaded: update.installer.size,
                    total: update.installer.size,
                },
            )
            .await?;
            send_event(progress, StudioUpdateEvent::Verifying).await?;
            Ok(true)
        }
        Err(_) => Ok(false),
    }
}

fn cancelled_error() -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::Cancelled,
        "Studio update installation was cancelled",
    )
}

pub(super) async fn send_event(
    progress: &Sender<StudioUpdateEvent>,
    event: StudioUpdateEvent,
) -> Result<(), StudioUpdateError> {
    progress.send(event).await.map_err(|_| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::Io,
            "the update progress owner stopped before accepting a required stage",
        )
    })
}

async fn verify_file(
    public_key: &'static str,
    signature_path: &Path,
    message_path: &Path,
) -> Result<(), StudioUpdateError> {
    let signature_path = signature_path.to_path_buf();
    let message_path = message_path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        let public_key = PublicKey::decode(public_key).map_err(signature_error)?;
        let signature_text = std::fs::read_to_string(&signature_path).map_err(io_error)?;
        let signature = Signature::decode(&signature_text).map_err(signature_error)?;
        let mut verifier = public_key
            .verify_stream(&signature)
            .map_err(signature_error)?;
        let mut file = std::fs::File::open(&message_path).map_err(io_error)?;
        let mut buffer = [0_u8; 64 * 1024];
        loop {
            let count = file.read(&mut buffer).map_err(io_error)?;
            if count == 0 {
                break;
            }
            verifier.update(&buffer[..count]);
        }
        verifier.finalize().map_err(signature_error)
    })
    .await
    .map_err(|error| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::SignatureInvalid,
            format!("signature verification task failed: {error}"),
        )
    })?
}

async fn hash_file(path: &Path) -> Result<String, StudioUpdateError> {
    let path = path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        let mut file = std::fs::File::open(path).map_err(io_error)?;
        let mut hasher = Sha256::new();
        let mut buffer = [0_u8; 64 * 1024];
        loop {
            let count = file.read(&mut buffer).map_err(io_error)?;
            if count == 0 {
                break;
            }
            hasher.update(&buffer[..count]);
        }
        Ok(hex::encode(hasher.finalize()))
    })
    .await
    .map_err(|error| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::Io,
            format!("hash task failed: {error}"),
        )
    })?
}

fn launch_installer(path: &Path, mode: StudioUpdateLaunch) -> Result<(), StudioUpdateError> {
    if !cfg!(target_os = "windows") {
        return Err(StudioUpdateError::new(
            StudioUpdateErrorCode::UnsupportedPlatform,
            "anywork in-app installation currently supports Windows only",
        ));
    }
    let mut command = Command::new(path);
    command.args(installer_arguments(mode));
    command.arg(format!("/ANYWORKWAITPID={}", std::process::id()));
    pl_remote_helper::process::configure_handoff_std_command(&mut command);
    command.spawn().map(|_| ()).map_err(|error| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::InstallerLaunchFailed,
            format!("failed to launch verified installer: {error}"),
        )
    })
}

fn installer_arguments(mode: StudioUpdateLaunch) -> [&'static str; 5] {
    [
        "/SILENT",
        "/NORESTART",
        "/NORESTARTAPPLICATIONS",
        "/NOCLOSEAPPLICATIONS",
        match mode {
            StudioUpdateLaunch::Restart => "/ANYWORKUPDATE=1",
            StudioUpdateLaunch::OnExit => "/ANYWORKUPDATE=exit",
        },
    ]
}

fn asset_filename(raw: &str) -> Result<String, StudioUpdateError> {
    Url::parse(raw)
        .ok()
        .and_then(|url| url.path_segments()?.next_back().map(str::to_string))
        .filter(|name| !name.is_empty())
        .ok_or_else(|| {
            StudioUpdateError::new(
                StudioUpdateErrorCode::InvalidManifest,
                "installer URL has no filename",
            )
        })
}

async fn write_partial(path: &Path, bytes: &[u8]) -> Result<(), StudioUpdateError> {
    let mut file = tokio::fs::File::create(path).await.map_err(io_error)?;
    file.write_all(bytes).await.map_err(io_error)?;
    file.flush().await.map_err(io_error)
}

async fn rename_replacing(from: &Path, to: &Path) -> Result<(), StudioUpdateError> {
    remove_if_exists(to).await?;
    tokio::fs::rename(from, to).await.map_err(io_error)
}

async fn remove_if_exists(path: &Path) -> Result<(), StudioUpdateError> {
    match tokio::fs::remove_file(path).await {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(io_error(error)),
    }
}

fn io_error(error: std::io::Error) -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::Io,
        format!("update file operation failed: {error}"),
    )
}

fn signature_error(error: minisign_verify::Error) -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::SignatureInvalid,
        format!("Minisign verification failed: {error}"),
    )
}

struct InstallGuard<'a> {
    updater: &'a StudioUpdater,
}

impl<'a> InstallGuard<'a> {
    fn acquire(updater: &'a StudioUpdater) -> Result<Self, StudioUpdateError> {
        updater
            .install_active
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .map_err(|_| {
                StudioUpdateError::new(
                    StudioUpdateErrorCode::InstallInProgress,
                    "another Studio update installation is already running",
                )
            })?;
        Ok(Self { updater })
    }
}

impl Drop for InstallGuard<'_> {
    fn drop(&mut self) {
        self.updater.install_active.store(false, Ordering::Release);
    }
}
