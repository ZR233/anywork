//! Host-selected runtime options and their resolution, independent of OS lock ownership.
use std::path::PathBuf;
use std::sync::Arc;

use crate::host_mcp_assets::HostMcpSource;
use crate::worker_assets::RemoteHelperSource;
use crate::{StudioError, StudioResult};

use super::paths::StudioPaths;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StudioHostKind {
    Desktop,
    HttpServer,
    Cli,
    Test,
}

impl StudioHostKind {
    pub(super) const fn as_str(self) -> &'static str {
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
