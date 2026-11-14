use std::fs::{File, OpenOptions};
use std::io::{Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use fs4::{FileExt, TryLockError};
use pl_protocol::studio::{StudioError, StudioResult};
use serde::Serialize;

use crate::host_mcp_assets::HostMcpSource;
use crate::worker_assets::RemoteHelperSource;

use super::paths::StudioPaths;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StudioHostKind {
    Desktop,
    HttpServer,
    Cli,
    Test,
}

impl StudioHostKind {
    const fn as_str(self) -> &'static str {
        match self {
            Self::Desktop => "desktop",
            Self::HttpServer => "httpServer",
            Self::Cli => "cli",
            Self::Test => "test",
        }
    }
}

/// Startup recovery belongs to the host and is never persisted in config.toml.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum StudioStartupPolicy {
    #[default]
    InteractiveRecovery,
    Strict,
}

#[derive(Debug, Clone)]
pub struct StudioRuntimeOptions {
    pub studio_home: Option<PathBuf>,
    pub host: StudioHostKind,
    pub startup_policy: StudioStartupPolicy,
    pub skill_search: pl_tool::skill::SkillSearchOptions,
    pub helper_source: RemoteHelperSource,
    pub host_mcp_source: HostMcpSource,
    /// Optional host-selected SSH configuration; explicit handles also reach OpenSSH via `-F`.
    pub ssh_config: Option<crate::SshConfigFile>,
    /// Optional bounded run export handle attached before runtime assembly.
    pub run_export: Option<crate::RunExporter>,
}

impl StudioRuntimeOptions {
    pub fn desktop() -> Self {
        Self {
            studio_home: None,
            host: StudioHostKind::Desktop,
            startup_policy: StudioStartupPolicy::InteractiveRecovery,
            skill_search: Default::default(),
            helper_source: RemoteHelperSource::External,
            host_mcp_source: HostMcpSource::External,
            ssh_config: None,
            run_export: None,
        }
    }

    pub fn http_server(studio_home: Option<PathBuf>) -> Self {
        Self {
            studio_home,
            host: StudioHostKind::HttpServer,
            startup_policy: StudioStartupPolicy::InteractiveRecovery,
            skill_search: Default::default(),
            helper_source: RemoteHelperSource::External,
            host_mcp_source: HostMcpSource::External,
            ssh_config: None,
            run_export: None,
        }
    }

    /// Production noninteractive host: explicit home, strict startup and environment-only credentials.
    pub fn cli(studio_home: impl Into<PathBuf>) -> Self {
        Self {
            studio_home: Some(studio_home.into()),
            host: StudioHostKind::Cli,
            startup_policy: StudioStartupPolicy::Strict,
            ..Self::desktop()
        }
    }

    /// Sets the explicit origin of `pl-remote-helper` bytes.
    ///
    /// Packaged desktop bridges pass the bundled resource root; every other host
    /// keeps the external installation mode of the constructors above.
    pub fn with_remote_helper_source(mut self, source: RemoteHelperSource) -> Self {
        self.helper_source = source;
        self
    }

    pub fn with_host_mcp_source(mut self, source: HostMcpSource) -> Self {
        self.host_mcp_source = source;
        self
    }

    /// Attaches a host-owned run exporter for trace, usage, and shutdown result export.
    pub fn with_run_export(mut self, exporter: crate::RunExporter) -> Self {
        self.run_export = Some(exporter);
        self
    }
}

#[derive(Debug)]
pub(super) struct RuntimeLock {
    file: File,
}

#[derive(Clone, Default)]
pub(super) struct RuntimeLockOwner {
    lock: Arc<Mutex<Option<Arc<RuntimeLock>>>>,
}

impl RuntimeLockOwner {
    pub(super) fn new(lock: Option<Arc<RuntimeLock>>) -> Self {
        Self {
            lock: Arc::new(Mutex::new(lock)),
        }
    }

    pub(super) fn release(&self) {
        let mut lock = match self.lock.lock() {
            Ok(lock) => lock,
            Err(poisoned) => poisoned.into_inner(),
        };
        lock.take();
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RuntimeLockMetadata<'a> {
    pid: u32,
    host: &'a str,
    started_at: u64,
}

impl RuntimeLock {
    pub(super) fn acquire(path: &Path, host: StudioHostKind) -> StudioResult<Self> {
        let parent = path.parent().ok_or_else(|| {
            StudioError::invalid_argument("Studio runtime lock path has no parent directory")
        })?;
        std::fs::create_dir_all(parent).map_err(|error| {
            tracing::error!(error = %error, "failed to create Studio runtime directory");
            StudioError::storage()
        })?;
        let mut file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(path)
            .map_err(|error| {
                tracing::error!(error = %error, "failed to open Studio runtime lock");
                StudioError::storage()
            })?;
        match FileExt::try_lock(&file) {
            Ok(()) => {}
            Err(TryLockError::WouldBlock) => return Err(StudioError::instance_busy()),
            Err(TryLockError::Error(error)) => {
                tracing::error!(error = %error, "failed to acquire Studio runtime lock");
                return Err(StudioError::storage());
            }
        }
        let metadata = RuntimeLockMetadata {
            pid: std::process::id(),
            host: host.as_str(),
            started_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |duration| duration.as_secs()),
        };
        let encoded = serde_json::to_vec(&metadata).map_err(|error| {
            tracing::error!(error = %error, "failed to encode Studio runtime lock metadata");
            StudioError::internal()
        })?;
        // The OS lock is the exclusive-owner authority. These bytes only describe the
        // live holder; they must be visible to local readers, not durable after a crash.
        // Forcing this diagnostic write to disk stalls startup behind unrelated IO.
        file.set_len(0)
            .and_then(|()| file.seek(SeekFrom::Start(0)))
            .and_then(|_| file.write_all(&encoded))
            .map_err(|error| {
                tracing::error!(error = %error, "failed to write Studio runtime lock metadata");
                StudioError::storage()
            })?;
        Ok(Self { file })
    }
}

impl Drop for RuntimeLock {
    fn drop(&mut self) {
        if let Err(error) = FileExt::unlock(&self.file) {
            tracing::warn!(error = %error, "failed to release Studio runtime lock explicitly");
        }
    }
}

#[derive(Debug)]
pub(super) struct ResolvedRuntimeOptions {
    pub paths: StudioPaths,
    pub host: StudioHostKind,
    pub startup_policy: StudioStartupPolicy,
    pub skill_search: pl_tool::skill::SkillSearchOptions,
    pub helper_source: RemoteHelperSource,
    pub host_mcp_source: HostMcpSource,
    pub ssh_config: Option<crate::SshConfigFile>,
    pub run_export: Option<Arc<super::runtime::run_export::RunExportCoordinator>>,
}

impl StudioRuntimeOptions {
    pub(super) fn resolve(self) -> StudioResult<ResolvedRuntimeOptions> {
        if self.host == StudioHostKind::Cli && self.studio_home.is_none() {
            return Err(StudioError::invalid_argument(
                "CLI requires an explicit Studio home",
            ));
        }
        let paths = StudioPaths::resolve(self.studio_home)
            .map_err(|error| StudioError::invalid_argument(error.to_string()))?;
        Ok(ResolvedRuntimeOptions {
            paths,
            host: self.host,
            startup_policy: if self.host == StudioHostKind::Cli {
                StudioStartupPolicy::Strict
            } else {
                self.startup_policy
            },
            skill_search: self.skill_search,
            helper_source: self.helper_source,
            host_mcp_source: self.host_mcp_source,
            ssh_config: self.ssh_config,
            run_export: self.run_export.map(|exporter| exporter.coordinator()),
        })
    }
}
