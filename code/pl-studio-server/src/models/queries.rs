//! Named field dispatch still constructs the original synchronous native query admission.
use super::{native::NativeRead, tasks};
use futures::future::BoxFuture;
use pl_protocol::{
    products::read::{model_pages::*, primitives::TextReadPage},
    studio::{StudioError, TextChunk},
};
impl NativeRead {
    pub(super) fn text(
        &self,
        field: u64,
        offset: u64,
        maximum: u32,
    ) -> BoxFuture<'static, anyhow::Result<TextChunk>> {
        match self {
            Self::Catalog(v) => Box::pin(v.text(field, offset, maximum)),
            Self::Delegation(v) => Box::pin(v.text(field, offset, maximum)),
            Self::SourceStatus(v) => Box::pin(v.text(field, offset, maximum)),
        }
    }
    pub(super) fn strings(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<TextReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.strings(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.strings(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
    pub(super) fn type_support(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<ModelTypeSupportReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.type_support(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.type_support(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
    pub(super) fn type_exclusions(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<ModelTypeExclusionReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.type_exclusions(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.type_exclusions(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
    pub(super) fn connection_modes(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<ConnectionModeReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.connection_modes(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.connection_modes(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
    pub(super) fn input_capabilities(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<ModelInputCapabilityReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.input_capabilities(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.input_capabilities(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
    pub(super) fn input_sources(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<ModelInputSourceReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.input_sources(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.input_sources(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
    pub(super) fn modalities(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<ModelModalityReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.modalities(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.modalities(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
    pub(super) fn price_tiers(
        &self,
        list: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BoxFuture<'static, anyhow::Result<ModelPriceTierReadPage>>, StudioError> {
        match self {
            Self::Catalog(v) => Ok(Box::pin(v.price_tiers(list, offset, limit))),
            Self::Delegation(v) => Ok(Box::pin(v.price_tiers(list, offset, limit))),
            Self::SourceStatus(_) => Err(tasks::wrong()),
        }
    }
}
