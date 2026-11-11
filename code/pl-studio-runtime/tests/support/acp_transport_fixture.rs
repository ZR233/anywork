//! Shared Linux-only ACP transport fixture. The peer is the sole protocol implementation.
//!
//! Runtime unit tests share the crate-root module; external test binaries may
//! include this file with `#[cfg(test)] #[path = "..."] mod acp_transport_fixture;`.
//! Keep the fixture alive through real close/shutdown; dropping an observer is not owner cleanup.
#![cfg(test)]

use anyhow::{Context, Result};
use pl_protocol::studio::*;
use pl_studio_runtime::{
    AcpSessionOpen, StudioHostKind, StudioRuntime, StudioRuntimeOptions, WorkspaceRecord,
};
use std::time::Duration;
use tokio::time::timeout;

pub const PEER: &str = include_str!("acp_business_peer.py");

pub struct AcpTransportFixture {
    pub runtime: StudioRuntime,
    pub home: tempfile::TempDir,
    pub workspace: WorkspaceRecord,
    pub revision: u64,
}

impl AcpTransportFixture {
    pub async fn new(mode: &str) -> Result<Self> {
        let home = tempfile::tempdir()?;
        let program = home.path().join("peer.py");
        std::fs::write(&program, PEER)?;
        std::fs::write(home.path().join("mode"), mode)?;
        let workspace = home.path().join("workspace");
        std::fs::create_dir(&workspace)?;
        let isolated_home = home.path().join("peer-home");
        std::fs::create_dir(&isolated_home)?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home.path().join("studio")),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        let workspace = runtime.open_project(&workspace).await?;
        runtime.save_acp_account(UpdateAcpAccountRequest {
            operation_id: "save-business-peer".into(),
            expected_revision: runtime.read_settings()?.config.revision,
            expected_document_revision: None,
            account: AcpAccountUpdate {
                account_id: "business-peer".into(),
                name: "Fixture peer".into(),
                enabled: true,
                command: Some("/usr/bin/python3".into()),
                args: Some(vec![program.to_string_lossy().into_owned()]),
                template: None,
                env: std::collections::BTreeMap::from([
                    (
                        "ACP_FIXTURE_ROOT".into(),
                        home.path().to_string_lossy().into_owned(),
                    ),
                    ("HOME".into(), isolated_home.to_string_lossy().into_owned()),
                    ("PYTHONNOUSERSITE".into(), "1".into()),
                    (
                        "XDG_CONFIG_HOME".into(),
                        isolated_home.join("config").to_string_lossy().into_owned(),
                    ),
                    (
                        "XDG_DATA_HOME".into(),
                        isolated_home.join("data").to_string_lossy().into_owned(),
                    ),
                    (
                        "XDG_CACHE_HOME".into(),
                        isolated_home.join("cache").to_string_lossy().into_owned(),
                    ),
                    (
                        "XDG_STATE_HOME".into(),
                        isolated_home.join("state").to_string_lossy().into_owned(),
                    ),
                ]),
            },
        })?;
        let revision = runtime
            .read_settings()?
            .config
            .settings
            .acp_accounts
            .into_iter()
            .find(|account| account.account_id == "business-peer")
            .context("saved fixture ACP account is missing from public settings")?
            .connection_revision;
        Ok(Self {
            runtime,
            home,
            workspace,
            revision,
        })
    }

    pub async fn open(&self) -> Result<AcpSessionOpen> {
        self.open_intent(AcpOpenIntent::New).await
    }

    pub async fn open_intent(&self, intent: AcpOpenIntent) -> Result<AcpSessionOpen> {
        self.runtime
            .open_acp_session(OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: self.revision,
                workspace_id: self.workspace.id.clone(),
                thread_id: None,
                intent,
            })
            .await
    }

    pub async fn ready(open: &mut AcpSessionOpen) -> Result<()> {
        let observer = open.observation.as_mut().context("original observation")?;
        timeout(Duration::from_secs(15), async {
            loop {
                match observer.recv().await.context("stream ended before ready")? {
                    AcpSessionEvent::Ready { .. } => return Ok::<_, anyhow::Error>(()),
                    AcpSessionEvent::Failed { error } => anyhow::bail!("ACP failed: {error:?}"),
                    _ => {}
                }
            }
        })
        .await?
    }

    pub fn pid(&self, name: &str) -> Result<u32> {
        Ok(std::fs::read_to_string(self.home.path().join(name))?
            .trim()
            .parse()?)
    }
}
