//! Transport-neutral account reads, commands and bounded observations over the original owners.

mod observation;
mod projection;

pub use crate::{
    AccountDomainFrame, AccountIdentity, AccountObservationTarget, CreateAccountRequest,
    PatchAccountRequest, SetAccountModelAutoCompactRequest, SetAccountModelConnectionRequest,
    SyncAccountModelsReply, SyncAccountModelsRequest,
};
pub use observation::AccountObservation;

use super::StudioRuntime;
use anyhow::Result;

impl StudioRuntime {
    /// Opens one independent display demand. Registration precedes every possible baseline read.
    /// No query, read, open or resynchronization contacts a provider or mutates settings.
    pub fn open_account_observation(
        &self,
        target: AccountObservationTarget,
    ) -> Result<AccountObservation> {
        observation::open(self.clone(), target)
    }

    /// Reads precisely one domain/target. A stamp can only satisfy that domain's observation barrier.
    pub fn read_account_domain(
        &self,
        target: &AccountObservationTarget,
    ) -> Result<AccountDomainFrame> {
        projection::read(self, target)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::AccountSummary;
    use crate::{StudioHostKind, StudioRuntimeOptions};

    #[tokio::test]
    async fn acp_service_directory_summaries_project_published_safe_diagnostics() -> Result<()> {
        let home = tempfile::tempdir()?;
        let definitions = home.path().join("acp");
        std::fs::create_dir(&definitions)?;
        for (id, enabled) in [("enabled", true), ("disabled", false)] {
            std::fs::write(
                definitions.join(format!("{id}.toml")),
                format!(
                    "schema_version=1\nid='{id}'\ndisplay_name='{id}'\nenabled={enabled}\ncommand='missing-acp-command'\nenv={{ TOKEN='private-valid-env' }}"
                ),
            )?;
        }
        std::fs::write(
            definitions.join("bad.toml"),
            "schema_version=1\nid='bad'\ncommand='agent'\nenv={ TOKEN = [ 'private-invalid-env' ] }",
        )?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home.path().to_owned()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        let baseline = runtime.read_account_domain(&AccountObservationTarget::Summaries)?;
        let AccountDomainFrame::Summaries {
            accounts,
            acp_diagnostics,
            ..
        } = &baseline
        else {
            panic!("expected summaries");
        };
        let acp: Vec<&AccountSummary> = accounts
            .iter()
            .filter(|account| matches!(account.identity, AccountIdentity::Acp { .. }))
            .collect();
        assert_eq!(acp.len(), 2, "bad definitions must not hide valid services");
        for (id, enabled) in [("enabled", true), ("disabled", false)] {
            let summary = acp
                .iter()
                .find(|account| {
                    account.identity
                        == AccountIdentity::Acp {
                            account_id: id.into(),
                        }
                })
                .expect("valid ACP service");
            assert_eq!(summary.acp_enabled, Some(enabled));
            assert!(summary.acp_connection_revision.is_some());
            assert_eq!(summary.credential_ready, None);
        }
        assert_eq!(acp_diagnostics.len(), 1);
        assert_eq!(acp_diagnostics[0].file_name, "bad.toml");
        assert_eq!(
            acp_diagnostics[0].message,
            "ACP定义无法加载，请检查文件格式和必填字段。"
        );
        let wire = serde_json::to_string(&baseline)?;
        for private in [
            "private-valid-env",
            "private-invalid-env",
            "TOKEN",
            "schema_version",
            &*home.path().to_string_lossy(),
        ] {
            assert!(
                !wire.contains(private),
                "summaries leaked private definition data"
            );
        }
        // Read only the published owner snapshot, never rescan files on a list read.
        std::fs::remove_file(definitions.join("bad.toml"))?;
        std::fs::remove_file(definitions.join("disabled.toml"))?;
        assert_eq!(
            runtime.read_account_domain(&AccountObservationTarget::Summaries)?,
            baseline
        );
        runtime.config_runtime.reload_acp_definitions()?;
        let AccountDomainFrame::Summaries {
            accounts,
            acp_diagnostics,
            ..
        } = runtime.read_account_domain(&AccountObservationTarget::Summaries)?
        else {
            panic!("expected summaries");
        };
        assert!(acp_diagnostics.is_empty());
        assert_eq!(
            accounts
                .iter()
                .filter(|account| matches!(account.identity, AccountIdentity::Acp { .. }))
                .count(),
            1
        );
        runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn acp_summaries_project_query_usage_capability_from_strategy_and_enabled_state()
    -> Result<()> {
        let home = tempfile::tempdir()?;
        let definitions = home.path().join("acp");
        std::fs::create_dir(&definitions)?;
        std::fs::write(
            definitions.join("template-enabled.toml"),
            crate::config::AcpServiceDefinition::template(
                "template-enabled".into(),
                "Antigravity Enabled".into(),
                crate::config::AcpProvider::Antigravity,
            )
            .encode()?,
        )?;
        let mut template_disabled = crate::config::AcpServiceDefinition::template(
            "template-disabled".into(),
            "Antigravity Disabled".into(),
            crate::config::AcpProvider::Antigravity,
        );
        template_disabled.enabled = false;
        std::fs::write(
            definitions.join("template-disabled.toml"),
            template_disabled.encode()?,
        )?;
        let generic_enabled = crate::config::AcpServiceDefinition {
            id: "generic-enabled".into(),
            display_name: "agy".into(),
            enabled: true,
            launch: crate::config::AcpLaunch::Command {
                command: "missing-acp-command".into(),
                args: vec!["acp".into()],
            },
            env: Default::default(),
        };
        std::fs::write(
            definitions.join("generic-enabled.toml"),
            generic_enabled.encode()?,
        )?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home.path().to_owned()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        let AccountDomainFrame::Summaries { accounts, .. } =
            runtime.read_account_domain(&AccountObservationTarget::Summaries)?
        else {
            panic!("expected summaries");
        };
        let query_usage_for = |id: &str| {
            accounts
                .iter()
                .find(|account| {
                    account.identity
                        == AccountIdentity::Acp {
                            account_id: id.into(),
                        }
                })
                .unwrap_or_else(|| panic!("missing summary for {id}"))
                .capabilities
                .query_usage
        };
        assert!(query_usage_for("template-enabled"));
        assert!(!query_usage_for("template-disabled"));
        assert!(!query_usage_for("generic-enabled"));
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}
