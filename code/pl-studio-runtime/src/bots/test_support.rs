use super::config::BotConfigFile;
use super::owner::{BotRuntime, ManagedBot};
use super::protocol::error::FeishuError;
use super::storage::{FrozenInbound, InboundAdmit};
use crate::studio::bot_archive_test_host::BotArchiveTestHost;
use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
use crate::{BotSecretUpdate, SaveBotRequest};
use anyhow::Result;
use sea_orm::{Database, DatabaseConnection};
use std::sync::Arc;

pub(in crate::bots) struct Fixture {
    pub(in crate::bots) host: BotArchiveTestHost,
    pub(in crate::bots) bots: BotRuntime,
    pub(super) managed: Arc<ManagedBot>,
    pub(super) workspace_id: String,
    _temp: tempfile::TempDir,
}

impl Fixture {
    pub(in crate::bots) async fn new() -> Result<Self> {
        Self::new_with_optional_file_input(false).await
    }

    pub(in crate::bots) async fn new_with_file_input() -> Result<Self> {
        Self::new_with_optional_file_input(true).await
    }

    async fn new_with_optional_file_input(file_input: bool) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let host = if file_input {
            BotArchiveTestHost::new_with_file_input(&home).await?
        } else {
            BotArchiveTestHost::new(&home).await?
        };
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let project = host.runtime.open_project(&workspace).await?;
        let bots = host.bots();
        // Keep the periodic recovery worker out of controlled interleavings.
        // All tested recovery calls below use the real enqueue implementation.
        if let Some(recovery) = bots.inner.reply_work.recovery.lock().await.take() {
            recovery.abort();
            assert!(recovery.await.unwrap_err().is_cancelled());
        }
        host.runtime
            .save_bot(SaveBotRequest {
                operation_id: "archive-fixture-save".into(),
                bot_id: Some("archive-fixture".into()),
                expected_config_revision: 0,
                name: "Archive fixture".into(),
                workspace_id: project.id.clone(),
                app_id: "cli_archive_fixture".into(),
                secret: BotSecretUpdate::Clear,
                enabled: false,
                tools_enabled: false,
                model_route: None,
            })
            .await?;
        let managed = bots.managed("archive-fixture").await?;
        Ok(Self {
            host,
            bots,
            managed,
            workspace_id: project.id,
            _temp: temp,
        })
    }

    pub(in crate::bots) async fn inbound(
        &self,
        chat_id: &str,
        bound: bool,
    ) -> Result<FrozenInbound> {
        self.inbound_with_attachments(chat_id, bound, Vec::new())
            .await
    }

    pub(in crate::bots) async fn inbound_with_attachments(
        &self,
        chat_id: &str,
        bound: bool,
        attachments: Vec<crate::bots::inbound::InboundAttachment>,
    ) -> Result<FrozenInbound> {
        let creation_id = format!("archive-thread-{chat_id}");
        self.managed
            .store
            .claim_thread_binding(chat_id, &creation_id, &self.workspace_id)
            .await?;
        if bound {
            let thread = self
                .host
                .runtime
                .create_thread_with_id(creation_id.clone(), &self.workspace_id, "Archive")
                .await?;
            self.managed
                .store
                .bind_thread(chat_id, &thread.id, &creation_id, &self.workspace_id)
                .await?;
        }
        let projection = self
            .managed
            .store
            .binding_for_chat(chat_id, "archive-fixture", &self.workspace_id)
            .await?;
        let inbound = FrozenInbound {
            bot_id: "archive-fixture".into(),
            message_id: format!("message-{chat_id}"),
            chat_id: chat_id.into(),
            content_hash: format!("hash-{chat_id}"),
            text: format!("original frozen text for {chat_id}"),
            attachments,
            open_id: "fixture-user".into(),
            chat_kind: "direct".into(),
            app_id: "cli_archive_fixture".into(),
            workspace_id: self.workspace_id.clone(),
            creation_id,
            binding_revision: projection.revision,
            watch_input: String::new(),
        };
        assert!(matches!(
            self.managed.store.admit_inbound(inbound.clone()).await?,
            InboundAdmit::Fresh(_)
        ));
        Ok(inbound)
    }

    pub(in crate::bots) async fn ledger_probe(&self) -> Result<DatabaseConnection> {
        let path = self
            .bots
            .inner
            .paths
            .bot_dir("archive-fixture")
            .join("state.sqlite");
        Ok(Database::connect(
            sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
        )
        .await?)
    }

    pub(super) async fn attach_transport(
        &mut self,
        http: super::protocol::http::FeishuHttp,
    ) -> Result<()> {
        let mut bots = BotRuntime::new(
            self.bots.inner.paths.clone(),
            self.bots.inner.config.clone(),
            self.bots.inner.events.clone(),
        )?;
        Arc::get_mut(&mut bots.inner)
            .expect("unpublished runtime")
            .http = http;
        bots.attach_host(Arc::downgrade(&self.host.runtime));
        bots.recover_bot_dir("archive-fixture").await?;
        self.managed = bots.managed("archive-fixture").await?;
        self.bots = bots;
        Ok(())
    }

    pub(in crate::bots) async fn shutdown(&self) -> Result<()> {
        if !Arc::ptr_eq(&self.bots.inner, &self.host.bots().inner) {
            self.bots.shutdown().await?;
        }
        self.host.runtime.shutdown_runtime().await?;
        Ok(())
    }

    pub(in crate::bots) async fn enqueue(&self, inbound: FrozenInbound) -> Result<()> {
        Ok(self.bots.enqueue_inbound(inbound).await?)
    }
}

impl BotRuntime {
    pub(crate) async fn install_workspace_migration_fixture(
        &self,
        bot_id: &str,
        root_id: &str,
        workspace_id: &str,
    ) -> Result<(), FeishuError> {
        let mut config = BotConfigFile::new(
            bot_id.into(),
            "Workspace migration".into(),
            workspace_id.into(),
            "cli_workspace_fixture".into(),
        )?;
        config.enabled = false;
        config.model_route = Some(self.default_model_route()?);
        let dir = self.inner.paths.bot_dir(bot_id);
        super::config::save_config(&dir.join("config.toml"), &config)?;
        let store = super::storage::BotStateStore::new(dir.join("state.sqlite"));
        store
            .claim_thread_binding("workspace-chat", "workspace-creation", workspace_id)
            .await?;
        store
            .bind_thread(
                "workspace-chat",
                root_id,
                "workspace-creation",
                workspace_id,
            )
            .await?;
        self.load().await
    }
}
