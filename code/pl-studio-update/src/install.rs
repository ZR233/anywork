use super::client::StudioUpdater;
use super::error::{StudioUpdateError, StudioUpdateErrorCode};
use super::manifest::validate_update;
use super::types::{StudioUpdate, StudioUpdateEvent};
use std::path::{Path, PathBuf};
use std::process::Command;

use tokio::io::AsyncWriteExt;
use tokio::sync::mpsc::UnboundedSender;
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
    progress: UnboundedSender<StudioUpdateEvent>,
    cancellation: StudioUpdateCancellation,
) -> Result<PreparedStudioUpdate, StudioUpdateError> {
    let _guard = updater.install_active.try_lock().map_err(|_| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::InstallInProgress,
            "another Studio update installation is already running",
        )
    })?;
    let result: Result<PreparedStudioUpdate, StudioUpdateError> = async {
        validate_update(&update)?;
        cancellation.check()?;
        let _ = progress.send(StudioUpdateEvent::Started {
            total: update.installer.size,
        });
        let cached = prepare_installer(updater, &update, &progress, &cancellation).await?;
        let prepared = lease_verified_installer(updater, &update, cached).await?;
        cancellation.check()?;
        Ok(prepared)
    }
    .await;
    if let Err(error) = &result {
        let _ = progress.send(StudioUpdateEvent::Failed {
            code: error.code().as_str().to_string(),
            message: error.to_string(),
        });
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
        let signature_text = std::fs::read_to_string(signature_path(&path)).map_err(io_error)?;
        super::verification::verify(&mut lease, &asset, public_key, &signature_text)?;
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
    progress: &UnboundedSender<StudioUpdateEvent>,
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

    if tokio::fs::try_exists(&installer).await.map_err(io_error)?
        && tokio::fs::try_exists(&signature).await.map_err(io_error)?
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
        let _ = progress.send(StudioUpdateEvent::Verifying);
        verify_file(updater.public_key, &update.installer, &signature, &partial).await?;
        cancellation.check()
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
    progress: &UnboundedSender<StudioUpdateEvent>,
    cancellation: &StudioUpdateCancellation,
) -> Result<bool, StudioUpdateError> {
    cancellation.check()?;
    let result = verify_file(updater.public_key, &update.installer, signature, installer).await;
    cancellation.check()?;
    match result {
        Ok(()) => {
            let _ = progress.send(StudioUpdateEvent::Progress {
                downloaded: update.installer.size,
                total: update.installer.size,
            });
            let _ = progress.send(StudioUpdateEvent::Verifying);
            Ok(true)
        }
        Err(error)
            if matches!(
                error.code(),
                StudioUpdateErrorCode::DownloadIncomplete
                    | StudioUpdateErrorCode::HashMismatch
                    | StudioUpdateErrorCode::SignatureInvalid
            ) =>
        {
            Ok(false)
        }
        Err(error) => Err(error),
    }
}

fn cancelled_error() -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::Cancelled,
        "Studio update installation was cancelled",
    )
}

async fn verify_file(
    public_key: &'static str,
    asset: &super::StudioUpdateAsset,
    signature_path: &Path,
    message_path: &Path,
) -> Result<(), StudioUpdateError> {
    let asset = asset.clone();
    let signature_path = signature_path.to_path_buf();
    let message_path = message_path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        let signature_text = std::fs::read_to_string(signature_path).map_err(io_error)?;
        let file = std::fs::File::open(message_path).map_err(io_error)?;
        super::verification::verify(file, &asset, public_key, &signature_text)
    })
    .await
    .map_err(|error| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::Io,
            format!("installer verification task failed: {error}"),
        )
    })?
}

fn signature_path(path: &Path) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(".minisig");
    PathBuf::from(name)
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

pub(super) fn io_error(error: std::io::Error) -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::Io,
        format!("update file operation failed: {error}"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{PUBLIC_KEY, SIGNATURE, update};

    #[tokio::test]
    async fn cached_signature_io_failure_is_not_treated_as_corruption() {
        let directory = tempfile::tempdir().unwrap();
        let update = update(b"abc");
        let version_dir = directory.path().join(&update.version);
        std::fs::create_dir(&version_dir).unwrap();
        let installer = version_dir.join(asset_filename(&update.installer.url).unwrap());
        std::fs::write(&installer, b"abc").unwrap();
        // A non-readable signature must fail before any existing installer is removed.
        std::fs::create_dir(signature_path(&installer)).unwrap();
        let mut updater = StudioUpdater::new_default().unwrap();
        updater.cache_dir = directory.path().to_path_buf();
        let (progress, _) = tokio::sync::mpsc::unbounded_channel();
        let result = prepare_installer(
            &updater,
            &update,
            &progress,
            &StudioUpdateCancellation::new(),
        )
        .await;
        assert_eq!(result.err().unwrap().code(), StudioUpdateErrorCode::Io);
        assert_eq!(std::fs::read(&installer).unwrap(), b"abc");
    }

    #[tokio::test]
    async fn valid_cache_is_reverified_on_the_final_lease_and_corruption_is_rejected() {
        let directory = tempfile::tempdir().unwrap();
        let installer = directory.path().join("installer.exe");
        let signature = signature_path(&installer);
        std::fs::write(&installer, b"test").unwrap();
        std::fs::write(&signature, SIGNATURE).unwrap();
        let mut updater = StudioUpdater::new_default().unwrap();
        updater.public_key = PUBLIC_KEY;
        let update = update(b"test");
        let (progress, _) = tokio::sync::mpsc::unbounded_channel();
        let cancellation = StudioUpdateCancellation::new();
        assert!(
            verify_cached(
                &updater,
                &update,
                &installer,
                &signature,
                &progress,
                &cancellation
            )
            .await
            .unwrap()
        );

        std::fs::write(&installer, b"Test").unwrap();
        assert!(
            !verify_cached(
                &updater,
                &update,
                &installer,
                &signature,
                &progress,
                &cancellation
            )
            .await
            .unwrap()
        );
        let cached = CachedInstaller {
            path: installer.clone(),
            lock: lock_cache(directory.path().join("download.lock"))
                .await
                .unwrap(),
        };
        let Err(error) = lease_verified_installer(&updater, &update, cached).await else {
            panic!("a mutation after cache verification must reject the final lease");
        };
        assert_eq!(error.code(), StudioUpdateErrorCode::HashMismatch);
        std::fs::write(&installer, b"test").unwrap();
        let cached = CachedInstaller {
            path: installer,
            lock: lock_cache(directory.path().join("download.lock"))
                .await
                .unwrap(),
        };
        let prepared = lease_verified_installer(&updater, &update, cached)
            .await
            .unwrap();
        assert_eq!(prepared.lease.unwrap().metadata().unwrap().len(), 4);
    }

    #[tokio::test]
    async fn clones_share_install_admission_and_cancelled_download_releases_the_guard() {
        let updater = StudioUpdater::new_default().unwrap();
        let other = updater.clone();
        let guard = updater.install_active.try_lock().unwrap();
        let (progress, _) = tokio::sync::mpsc::unbounded_channel();
        let cancellation = StudioUpdateCancellation::new();
        let result = other
            .download(update(b"test"), progress.clone(), cancellation.clone())
            .await;
        assert_eq!(
            result.err().unwrap().code(),
            StudioUpdateErrorCode::InstallInProgress
        );
        drop(guard);
        cancellation.clone().cancel();
        let result = other
            .download(update(b"test"), progress, cancellation)
            .await;
        assert_eq!(
            result.err().unwrap().code(),
            StudioUpdateErrorCode::Cancelled
        );
        assert!(updater.install_active.try_lock().is_ok());
    }
}
