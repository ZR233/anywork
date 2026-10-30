//! Test-only Studio-private fixture, registered by studio::runtime.
use std::path::Path;
use std::sync::Arc;

use anyhow::Result;
use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
use pl_model::model::ModelInfo;
use pl_model::protocol::ProtocolEndpoint;

use super::StudioRuntime;
use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
use crate::studio::store::thread_archive::{ArchivePhase, ArchiveScope, ThreadArchiveOperation};
use crate::{StudioHostKind, StudioRuntimeOptions};

pub(crate) struct BotArchiveTestHost {
    pub(crate) runtime: Arc<StudioRuntime>,
    // Retained without accepting: no test is expected to submit model work.
    _endpoint: std::net::TcpListener,
}

impl BotArchiveTestHost {
    pub(crate) async fn new(home: &Path) -> Result<Self> {
        Self::new_with_optional_file_input(home, false).await
    }

    pub(crate) async fn new_with_file_input(home: &Path) -> Result<Self> {
        Self::new_with_optional_file_input(home, true).await
    }

    async fn new_with_optional_file_input(home: &Path, file_input: bool) -> Result<Self> {
        let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
        let account_id = AccountId::new("bot-archive-fixture")?;
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: "archive-model".into(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        let mut model = ModelInfo::compatible(&route.model_id);
        if file_input {
            use pl_model::model::{
                MediaRepresentation, MediaWireFormat, ModelInputCapability, ModelInputSource,
                ModelMediaInputProfile, ModelModality,
            };
            model.capabilities.input.push(ModelInputCapability::media(
                ModelModality::File,
                vec![ModelInputSource::Local],
            ));
            model.binding.request.media.push(ModelMediaInputProfile {
                modality: ModelModality::File,
                wire: MediaWireFormat::ChatFileUrl,
                first_send: vec![MediaRepresentation::DataUrl],
                replay: vec![MediaRepresentation::DataUrl],
            });
        }
        config.models.accounts.insert(
            account_id,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(
                    "Bot archive fixture",
                    format!("http://{}", endpoint.local_addr()?),
                ),
                vec![model],
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
        ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(home.to_owned()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        Ok(Self {
            runtime: Arc::new(runtime),
            _endpoint: endpoint,
        })
    }

    pub(crate) fn bots(&self) -> crate::bots::BotRuntime {
        self.runtime.bots.clone()
    }

    pub(crate) fn lifecycle_lock(&self) -> &tokio::sync::Mutex<()> {
        &self.runtime.lifecycle_lock
    }

    pub(crate) fn resources_dir(
        &self,
        workspace_id: &str,
        thread_id: &str,
    ) -> Result<std::path::PathBuf> {
        Ok(self
            .runtime
            .store
            .session_paths(workspace_id, thread_id)?
            .resources_dir())
    }

    pub(crate) fn drafts_dir(&self) -> std::path::PathBuf {
        self.runtime.store.attachment_drafts_dir()
    }

    pub(crate) async fn seal_thread(&self, thread_id: &str) -> Result<()> {
        // A durable scope seal alone must reject dispatch, independently of
        // resident producers and even before member cleanup has completed.
        self.runtime
            .store
            .save_thread_archive(&ThreadArchiveOperation {
                scope: ArchiveScope::Thread(thread_id.into()),
                revision: 1,
                members: Vec::new(),
                private_members: Vec::new(),
                phase: ArchivePhase::Sealed,
            })
            .await
    }
}
