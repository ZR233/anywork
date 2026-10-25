//! Models-specific typed feeds and immutable reads over original Catalog and builtin Templates.
//! Query admission/completion is shared with Thread; no payload erasure or second fact store.
mod catalog;
mod catalog_api;
mod catalog_feed;
mod catalog_frames;
mod delegation_api;
mod delegation_material;
mod delegation_reads;
mod delegation_scope;
pub(super) mod delivery_window;
mod descriptor;
mod fields;
mod material;
pub(super) mod page_budget;
mod pages;
mod scope;
mod source_status_material;
mod source_status_scope;
mod templates;
mod templates_api;
mod templates_feed;
mod templates_source;

pub use catalog_feed::StudioModelCatalogFeed;
pub use delegation_scope::StudioDelegationModelRead;
pub use scope::{StudioAccountTemplatesRead, StudioModelCatalogRead};
pub use source_status_scope::StudioModelCatalogSourceStatusRead;
pub use templates_feed::StudioAccountTemplatesFeed;
pub(super) use templates_source::TemplatesSource;

pub use pl_protocol::products::feed::account_templates::AccountTemplatesFrame;
pub use pl_protocol::products::feed::model_catalog::ModelCatalogFrame;
pub use pl_protocol::products::identity::{
    ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity,
    ProductSourceStatusRef,
};
pub use pl_protocol::products::models::{AccountModelKey, ModelSelection};
pub use pl_protocol::products::read::delegation_models::{
    AgentEvaluationRead, AgentEvaluationReadPage, DelegationModelReadHeader,
    DelegationModelReadTarget, ModelSelectionGuideRead, ModelSelectionMeasurementRead,
    ModelSelectionSourceRead, ModelSelectionSourceReadPage,
};
pub use pl_protocol::products::read::model_pages::{
    AccountCatalogEntryReadPage, AccountTemplateReadPage, AccountTemplatesEntityRead,
    AccountTemplatesEntryPage, ConnectionModeReadPage, ModelCatalogEntityRead,
    ModelCatalogEntryPage, ModelDescriptorReadPage, ModelInputCapabilityReadPage,
    ModelInputSourceReadPage, ModelModalityReadPage, ModelPriceTierReadPage,
    ModelTypeExclusionReadPage, ModelTypeSupportReadPage, NamedModelCatalogReadPage,
};
pub use pl_protocol::products::read::models::{
    AccountCatalogEntryRead, ConnectionModeRead, EffectiveDeepSeekSearchRead,
    EffectiveWebSearchRead, ModelCapabilitiesRead, ModelCatalogReadHeader, ModelCatalogStatusRead,
    ModelContextResolutionRead, ModelDescriptorRead, ModelInputCapabilityRead,
    ModelInputSourceReadItem, ModelModalityReadItem, ModelPriceTierRead, ModelPricingRead,
    ModelReasoningDescriptorRead, ModelTransportDescriptorRead, ModelTypeExclusionReadItem,
    ModelTypeSupportRead,
};
pub use pl_protocol::products::read::primitives::{TextReadItem, TextReadPage, TypedListRef};
pub use pl_protocol::products::read::templates::{
    AccountServiceCapabilitiesRead, AccountTemplateRead, AccountTemplatesReadHeader,
    CredentialDescriptorRead, NamedModelCatalogRead, NamedModelCatalogReadItem,
    WebSearchServiceCapabilitiesRead,
};
pub use pl_protocol::products::references::{AccountTemplatesReadRef, ModelCatalogReadRef};
pub use pl_protocol::products::source::ProductSourceStatusReadHeader;
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
