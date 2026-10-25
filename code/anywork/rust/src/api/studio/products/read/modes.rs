//! Opaque native reads. Transport admission and cleanup stay in the original bridge registry.
use super::super::identity::*;
use super::super::references::*;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use crate::api::studio::types::{BridgeStudioCommandReceipt, BridgeThreadModeDefinitionSnapshot};
use pl_protocol::products::read::modes as protocol;
use pl_studio_runtime::modes::StudioModeCatalogRead;
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeModeDefinitionCommandReply {
    pub catalog: BridgeModeCatalogReadTarget,
    pub definition: Option<BridgeThreadModeDefinitionSnapshot>,
    pub receipt: BridgeStudioCommandReceipt,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeCatalogReadHeader {
    pub revision: u64,
    pub modes: BridgeTypedListRef,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadModeDescriptorRead {
    pub id: String,
    pub display_name: BridgeReadText,
    pub description: BridgeReadText,
    pub order: u32,
    pub has_workflow: bool,
    pub read_only: bool,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeCatalogEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeCatalogEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeThreadModeDescriptorRead,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadModeDescriptorReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeThreadModeDescriptorRead>,
    pub next_offset: Option<u64>,
}
impl From<protocol::ModeDefinitionCommandReply> for BridgeModeDefinitionCommandReply {
    fn from(value: protocol::ModeDefinitionCommandReply) -> Self {
        Self {
            catalog: value.catalog.into(),
            definition: value.definition.map(
                crate::api::studio::convert::mode_editor::bridge_thread_mode_definition_snapshot,
            ),
            receipt: crate::api::studio::convert::commands::command_receipt(value.receipt),
        }
    }
}

impl From<protocol::ModeCatalogReadHeader> for BridgeModeCatalogReadHeader {
    fn from(value: protocol::ModeCatalogReadHeader) -> Self {
        Self {
            revision: value.revision,
            modes: value.modes.into(),
        }
    }
}

impl From<protocol::ThreadModeDescriptorRead> for BridgeThreadModeDescriptorRead {
    fn from(value: protocol::ThreadModeDescriptorRead) -> Self {
        Self {
            id: value.id.to_string(),
            display_name: value.display_name.into(),
            description: value.description.into(),
            order: value.order,
            has_workflow: value.has_workflow,
            read_only: value.read_only,
        }
    }
}

impl From<protocol::ModeCatalogEntryPage> for BridgeModeCatalogEntryPage {
    fn from(value: protocol::ModeCatalogEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl From<protocol::ModeCatalogEntityRead> for BridgeModeCatalogEntityRead {
    fn from(value: protocol::ModeCatalogEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

impl From<protocol::ThreadModeDescriptorReadPage> for BridgeThreadModeDescriptorReadPage {
    fn from(value: protocol::ThreadModeDescriptorReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

impl ModelsRead for StudioModeCatalogRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeModeCatalogReadConnection {
    read: ModelsReadHandle<StudioModeCatalogRead>,
}
pub async fn open_mode_catalog_read(
    reference: BridgeModeCatalogReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeModeCatalogReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeModeCatalogReadConnection {
        read: open_read(move |runtime| runtime.open_mode_catalog_read(reference, origin)).await?,
    })
}
impl BridgeModeCatalogReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeModeCatalogReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioModeCatalogRead::header)?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModeCatalogEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeModeCatalogEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_mode(
        &self,
        mode: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        let mode = pl_protocol::ThreadModeId::new(mode).map_err(|error| {
            BridgeError::from(pl_protocol::studio::StudioError::invalid_argument(
                error.to_string(),
            ))
        })?;
        Ok(self
            .read
            .query(move |source| source.lookup_mode(mode))?
            .await?
            .map(Into::into))
    }
    pub async fn modes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeThreadModeDescriptorReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |source| source.modes(list_id, offset, limit))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}

pub async fn read_mode_definition(
    mode_id: String,
) -> Result<BridgeThreadModeDefinitionSnapshot, BridgeError> {
    let mode = pl_protocol::ThreadModeId::new(mode_id).map_err(|error| {
        BridgeError::from(pl_protocol::studio::StudioError::invalid_argument(
            error.to_string(),
        ))
    })?;
    let value = crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .read_mode_definition(mode)
        .await?;
    Ok(crate::api::studio::convert::mode_editor::bridge_thread_mode_definition_snapshot(value))
}
pub async fn validate_mode_definition(
    raw_json: String,
) -> Result<crate::api::studio::types::BridgeThreadModeValidationResult, BridgeError> {
    let value = crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .validate_mode_definition(raw_json)
        .await?;
    Ok(crate::api::studio::convert::mode_editor::bridge_thread_mode_validation_result(value))
}
pub async fn mode_definition_schema() -> Result<String, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .mode_definition_schema()
        .await?)
}
pub async fn preview_mode_workflow(
    request: crate::api::studio::types::BridgeWorkflowPreviewRequest,
) -> Result<crate::api::studio::types::BridgeWorkflowPreviewSnapshot, BridgeError> {
    let value = crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .preview_mode_workflow(request.try_into()?)
        .await?;
    Ok(crate::api::studio::convert::mode_editor::bridge_workflow_preview_snapshot(value))
}
pub async fn save_mode_definition(
    document: crate::api::studio::types::BridgeThreadModeDocument,
    expected_revision: u64,
    operation_id: String,
) -> Result<BridgeModeDefinitionCommandReply, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .save_mode_definition(document.try_into()?, expected_revision, operation_id)
        .await?
        .into())
}
pub async fn delete_mode_definition(
    mode_id: String,
    expected_revision: u64,
    operation_id: String,
) -> Result<BridgeModeDefinitionCommandReply, BridgeError> {
    let mode = pl_protocol::ThreadModeId::new(mode_id).map_err(|error| {
        BridgeError::from(pl_protocol::studio::StudioError::invalid_argument(
            error.to_string(),
        ))
    })?;
    Ok(crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .delete_mode_definition(mode, expected_revision, operation_id)
        .await?
        .into())
}
pub async fn reload_mode_definitions(
    expected_revision: u64,
    operation_id: String,
) -> Result<BridgeModeDefinitionCommandReply, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .reload_mode_definitions(expected_revision, operation_id)
        .await?
        .into())
}
