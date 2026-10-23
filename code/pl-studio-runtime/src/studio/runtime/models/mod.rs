//! Models-specific immutable reads over the original canonical Catalog and builtin Templates.
//! Query admission/completion is shared with Thread; no payload erasure or second fact store.
mod catalog;
mod catalog_api;
mod descriptor;
mod fields;
mod material;
mod page_budget;
mod pages;
mod scope;
mod templates;
mod templates_api;
mod templates_feed;
mod templates_source;

pub use scope::{StudioAccountTemplatesRead, StudioModelCatalogRead};
pub use templates_feed::StudioAccountTemplatesFeed;
pub(super) use templates_source::TemplatesSource;

pub use pl_protocol::products::identity::{ProductEntityRef, ProductFeedIdentity, ProductReadOrigin, ProductReadScopeIdentity};
pub use pl_protocol::products::feed::account_templates::AccountTemplatesFrame;
pub use pl_protocol::products::references::{AccountTemplatesReadRef, ModelCatalogReadRef};
pub use pl_protocol::products::models::ModelSelection;
pub use pl_protocol::products::read::model_pages::{AccountCatalogEntryReadPage, AccountTemplateReadPage,
    AccountTemplatesEntityRead, AccountTemplatesEntryPage, ConnectionModeReadPage, ModelCatalogEntityRead,
    ModelCatalogEntryPage, ModelDescriptorReadPage, ModelInputCapabilityReadPage, ModelInputSourceReadPage,
    ModelModalityReadPage, ModelPriceTierReadPage, ModelTypeExclusionReadPage, ModelTypeSupportReadPage,
    NamedModelCatalogReadPage};
pub use pl_protocol::products::read::models::{AccountCatalogEntryRead, ConnectionModeRead, EffectiveDeepSeekSearchRead,
    EffectiveWebSearchRead, ModelCapabilitiesRead, ModelCatalogReadHeader, ModelCatalogStatusRead,
    ModelContextResolutionRead, ModelDescriptorRead, ModelInputCapabilityRead, ModelInputSourceReadItem,
    ModelModalityReadItem, ModelPriceTierRead, ModelPricingRead, ModelReasoningDescriptorRead,
    ModelTransportDescriptorRead, ModelTypeExclusionReadItem, ModelTypeSupportRead};
pub use pl_protocol::products::read::templates::{AccountServiceCapabilitiesRead, AccountTemplateRead,
    AccountTemplatesReadHeader, CredentialDescriptorRead, NamedModelCatalogRead, NamedModelCatalogReadItem,
    WebSearchServiceCapabilitiesRead};
pub use pl_protocol::products::read::primitives::{TextReadItem, TextReadPage, TypedListRef};
pub use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
