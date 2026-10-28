//! Shared test environment for real creation/close owners; no close state is synthesized here.
use super::StudioRuntime;
use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
use crate::studio::StudioThreadFactory;
use anyhow::{Context, Result};
use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
use pl_model::model::ModelInfo;
use pl_model::protocol::ProtocolEndpoint;
use std::path::Path;

pub(crate) struct RuntimeFixture {
    pub(crate) runtime: StudioRuntime,
    pub(crate) project: crate::studio::ProjectRecord,
    pub(crate) route: pl_protocol::studio::NewThreadModelRoute,
    endpoint: std::net::TcpListener,
    _directory: tempfile::TempDir,
}

impl RuntimeFixture {
    pub(crate) async fn new() -> Result<Self> {
        let directory = tempfile::tempdir()?;
        let home = directory.path().join("home");
        let workspace = directory.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        git(&workspace, &["init"]).await?;
        git(
            &workspace,
            &[
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "--allow-empty",
                "-m",
                "fixture",
            ],
        )
        .await?;
        let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
        let account = AccountId::new("resource-owner-fixture")?;
        let route = ModelRouteConfig {
            account_id: account.clone(),
            model_id: "fixture-model".into(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(
                    "Resource owner fixture",
                    format!("http://{}", endpoint.local_addr()?),
                ),
                vec![ModelInfo::compatible(&route.model_id)],
            ),
        );
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        let paths = ConfigPaths::from_config_dir(&home);
        ConfigStore::new(paths.clone()).save(&config)?;
        tokio::fs::create_dir_all(paths.agents_dir()).await?;
        let profile = crate::config::UserAgentProfile {
            enabled: true,
            display_name: "Resource owner fixture".into(),
            description: "Resource owner fixture".into(),
            when_to_use: "Only deterministic owner tests".into(),
            system_instructions: "Never execute model work in this fixture".into(),
            account_id: route.account_id.clone(),
            model_id: route.model_id.clone(),
            effort: None,
            workspace_mode: pl_protocol::AgentWorkspaceMode::Worktree,
        };
        tokio::fs::write(
            paths.agents_dir().join("resource-owner-fixture.toml"),
            toml::to_string(&profile)?,
        )
        .await?;
        let runtime = StudioRuntime::initialize(crate::StudioRuntimeOptions {
            studio_home: Some(home),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        })
        .await?;
        let project = runtime.open_project(&workspace).await?;
        Ok(Self {
            runtime,
            project,
            route: pl_protocol::studio::NewThreadModelRoute {
                account_id: route.account_id.as_str().to_owned(),
                model_id: route.model_id,
                effort: None,
            },
            endpoint,
            _directory: directory,
        })
    }

    pub(crate) fn assembler(&self) -> crate::thread_assembler::StudioThreadAssembler {
        self.runtime.threads.clone()
    }

    pub(crate) fn factory(&self) -> StudioThreadFactory {
        self.runtime.thread_factory.clone()
    }

    pub(crate) fn config(&self) -> crate::config::ConfigRuntime {
        self.runtime.config_runtime.clone()
    }

    pub(crate) fn store(&self) -> crate::studio::StudioStore {
        self.runtime.store.clone()
    }

    pub(crate) fn lease_revision(&self, id: &str) -> Result<u64> {
        Ok(self
            .runtime
            .agent_facility
            .worktrees
            .get(id)
            .context("fixture lease")?
            .revision)
    }

    pub(crate) async fn child(
        &self,
    ) -> Result<(pl_protocol::Thread, pl_core::thread::ThreadHandle)> {
        use crate::thread_assembler::StudioChildResources;
        let root = self
            .runtime
            .create_thread(&self.project.id, "close fixture")
            .await?;
        let profile = self
            .runtime
            .config_runtime
            .agent_profiles()?
            .profiles
            .into_iter()
            .find(|profile| profile.display_name == "Resource owner fixture")
            .context("explicit fixture worktree profile")?;
        let profile = self
            .runtime
            .config_runtime
            .resolve_agent_profile(&profile.profile_id)?;
        let request = crate::thread_assembler::ChildThreadRequest {
            id: crate::studio::new_id("thread"),
            cancellation: Default::default(),
            caller: root.id,
            call_id: "close-fixture".into(),
            profile_id: profile.profile.profile_id.clone(),
            model_selection: None,
            delegation: Default::default(),
            task_summary: "resource close fixture".to_owned().try_into()?,
            writable_paths: None,
            review_target_agent_id: None,
            metadata: pl_core::context::OpaquePayload::new("pl.studio.agent-metadata", 1, "{}")?,
        };
        let spec = self
            .runtime
            .thread_factory
            .prepare(&request, &profile)
            .await?;
        let thread = self.runtime.threads.assemble(spec).await?;
        thread.flush().await?;
        self.runtime
            .store
            .thread_persistence()
            .wait_for_drain()
            .await?;
        let repository = self.runtime.agent_facility.persistence.lock().await.clone();
        if let Some(repository) = repository {
            repository.flush().await?;
        }
        let record = self
            .runtime
            .agent_facility
            .product_events
            .thread_snapshot(&request.id)
            .context("published child")?;
        Ok((record, thread))
    }

    /// A retry request is not its durable ACK. Observe the original blocked writer's next
    /// result, then verify the fixed admitted ticket through that same repository handle.
    pub(crate) async fn retry_persistence_and_wait(&self) -> Result<()> {
        let repository = self
            .runtime
            .agent_facility
            .persistence
            .lock()
            .await
            .clone()
            .context("fixture persistence owner")?;
        let through = repository.admitted_ticket();
        let mut health = repository.subscribe_state();
        let blocked = matches!(
            &health.borrow_and_update().snapshot.state,
            crate::studio::PersistenceState::Blocked(_)
        );
        self.runtime.retry_persistence().await?;
        if blocked {
            health
                .changed()
                .await
                .context("original repository retry result")?;
        }
        repository.flush_through(through).await?;
        Ok(())
    }

    pub(crate) async fn finish(self) -> Result<()> {
        anyhow::ensure!(
            self.runtime.shutdown_runtime().await?.state.is_stopped(),
            "fixture runtime did not stop"
        );
        self.endpoint.set_nonblocking(true)?;
        anyhow::ensure!(
            matches!(self.endpoint.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock),
            "resource-only operation opened a model request"
        );
        Ok(())
    }
}

pub(crate) async fn git(path: &Path, arguments: &[&str]) -> Result<Vec<u8>> {
    let output = tokio::process::Command::new("git")
        .arg("-C")
        .arg(path)
        .args(arguments)
        .output()
        .await?;
    anyhow::ensure!(
        output.status.success(),
        "fixture Git failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(output.stdout)
}

pub(crate) async fn sqlite(path: &Path) -> Result<sea_orm::DatabaseConnection> {
    Ok(sea_orm::Database::connect(
        crate::studio::paths::sqlite_file_options(
            path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| options,
        )
        .await?,
    )
    .await?)
}
