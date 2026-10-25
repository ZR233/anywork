//! Opaque Skills scopes share the original runtime scope/call budgets and bridge owner.
use super::super::identity::{
    BridgeProductCollectionRef, BridgeProductEntityRef, BridgeProductReadOrigin,
    BridgeProductReadScopeIdentity, BridgeProductSourceStatusRef,
};
use super::super::references::{BridgeSkillsReadRef, BridgeSkillsReadTarget};
use super::super::source::BridgeProductSourceStatusReadHeader;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::primitives::BridgeTextReadPage;
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk, BridgeTypedListRef};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::skills as protocol;
use pl_studio_runtime::skills::{StudioSkillsRead, StudioSkillsSourceStatusRead};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillCatalogRead {
    pub project_dir: BridgeReadText,
    pub skills: BridgeTypedListRef,
    pub warnings: BridgeTypedListRef,
    pub complete: bool,
}
impl From<protocol::SkillCatalogRead> for BridgeSkillCatalogRead {
    fn from(value: protocol::SkillCatalogRead) -> Self {
        Self {
            project_dir: value.project_dir.into(),
            skills: value.skills.into(),
            warnings: value.warnings.into(),
            complete: value.complete,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsReadHeader {
    pub project_id: BridgeReadText,
    pub config_fingerprint: BridgeReadText,
    pub catalog_revision: u64,
    pub catalog: BridgeSkillCatalogRead,
}
impl From<protocol::SkillsReadHeader> for BridgeSkillsReadHeader {
    fn from(value: protocol::SkillsReadHeader) -> Self {
        Self {
            project_id: value.project_id.into(),
            config_fingerprint: value.config_fingerprint.into(),
            catalog_revision: value.catalog_revision,
            catalog: value.catalog.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSkillSource {
    Project,
    User,
    System,
    External,
}
impl From<protocol::SkillSource> for BridgeSkillSource {
    fn from(value: protocol::SkillSource) -> Self {
        match value {
            protocol::SkillSource::Project => Self::Project,
            protocol::SkillSource::User => Self::User,
            protocol::SkillSource::System => Self::System,
            protocol::SkillSource::External => Self::External,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillInvocationPolicyRead {
    pub model_invocable: bool,
    pub user_invocable: bool,
}
impl From<protocol::SkillInvocationPolicyRead> for BridgeSkillInvocationPolicyRead {
    fn from(value: protocol::SkillInvocationPolicyRead) -> Self {
        Self {
            model_invocable: value.model_invocable,
            user_invocable: value.user_invocable,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSkillResourceBaseRead {
    Directory { path: BridgeReadText },
    Url { url: BridgeReadText },
    Opaque { description: BridgeReadText },
}
impl From<protocol::SkillResourceBaseRead> for BridgeSkillResourceBaseRead {
    fn from(value: protocol::SkillResourceBaseRead) -> Self {
        match value {
            protocol::SkillResourceBaseRead::Directory { path } => {
                Self::Directory { path: path.into() }
            }
            protocol::SkillResourceBaseRead::Url { url } => Self::Url { url: url.into() },
            protocol::SkillResourceBaseRead::Opaque { description } => Self::Opaque {
                description: description.into(),
            },
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillSummaryRead {
    pub name: BridgeReadText,
    pub description: BridgeReadText,
    pub category: Option<BridgeReadText>,
    pub platforms: BridgeTypedListRef,
    pub source: BridgeSkillSource,
    pub provider_id: BridgeReadText,
    pub invocation: BridgeSkillInvocationPolicyRead,
    pub resource_base: BridgeSkillResourceBaseRead,
}
impl From<protocol::SkillSummaryRead> for BridgeSkillSummaryRead {
    fn from(value: protocol::SkillSummaryRead) -> Self {
        Self {
            name: value.name.into(),
            description: value.description.into(),
            category: value.category.map(Into::into),
            platforms: value.platforms.into(),
            source: value.source.into(),
            provider_id: value.provider_id.into(),
            invocation: value.invocation.into(),
            resource_base: value.resource_base.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsEntityRead {
    pub reference: BridgeProductEntityRef,
    pub value: BridgeSkillSummaryRead,
}
impl From<protocol::SkillsEntityRead> for BridgeSkillsEntityRead {
    fn from(value: protocol::SkillsEntityRead) -> Self {
        Self {
            reference: value.reference.into(),
            value: value.value.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsEntryPage {
    pub collection: BridgeProductCollectionRef,
    pub offset: u64,
    pub items: Vec<BridgeProductEntityRef>,
    pub next_offset: Option<u64>,
}
impl From<protocol::SkillsEntryPage> for BridgeSkillsEntryPage {
    fn from(value: protocol::SkillsEntryPage) -> Self {
        Self {
            collection: value.collection.into(),
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillSummaryReadPage {
    pub list_id: u64,
    pub offset: u64,
    pub total: u64,
    pub items: Vec<BridgeSkillSummaryRead>,
    pub next_offset: Option<u64>,
}
impl From<protocol::SkillSummaryReadPage> for BridgeSkillSummaryReadPage {
    fn from(value: protocol::SkillSummaryReadPage) -> Self {
        Self {
            list_id: value.list_id,
            offset: value.offset,
            total: value.total,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillSearchInvocationPolicy {
    pub model_invocable: bool,
    pub user_invocable: bool,
}
impl From<protocol::SkillSearchInvocationPolicy> for BridgeSkillSearchInvocationPolicy {
    fn from(value: protocol::SkillSearchInvocationPolicy) -> Self {
        Self {
            model_invocable: value.model_invocable,
            user_invocable: value.user_invocable,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSkillSearchResourceBase {
    Directory { path: String },
    Url { url: String },
    Opaque { description: String },
}
impl From<protocol::SkillSearchResourceBase> for BridgeSkillSearchResourceBase {
    fn from(value: protocol::SkillSearchResourceBase) -> Self {
        match value {
            protocol::SkillSearchResourceBase::Directory { path } => Self::Directory { path },
            protocol::SkillSearchResourceBase::Url { url } => Self::Url { url },
            protocol::SkillSearchResourceBase::Opaque { description } => {
                Self::Opaque { description }
            }
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillSearchSummary {
    pub name: String,
    pub description: String,
    pub category: Option<String>,
    pub platforms: Vec<String>,
    pub source: BridgeSkillSource,
    pub provider_id: String,
    pub invocation: BridgeSkillSearchInvocationPolicy,
    pub resource_base: BridgeSkillSearchResourceBase,
}
impl From<protocol::SkillSearchSummary> for BridgeSkillSearchSummary {
    fn from(value: protocol::SkillSearchSummary) -> Self {
        Self {
            name: value.name,
            description: value.description,
            category: value.category,
            platforms: value.platforms,
            source: value.source.into(),
            provider_id: value.provider_id,
            invocation: value.invocation.into(),
            resource_base: value.resource_base.into(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsSearchResult {
    pub project_id: String,
    pub catalog_revision: u64,
    pub matches: Vec<BridgeSkillSearchSummary>,
    pub truncated: bool,
}
impl From<protocol::SkillsSearchResult> for BridgeSkillsSearchResult {
    fn from(value: protocol::SkillsSearchResult) -> Self {
        Self {
            project_id: value.project_id,
            catalog_revision: value.catalog_revision,
            matches: value.matches.into_iter().map(Into::into).collect(),
            truncated: value.truncated,
        }
    }
}

macro_rules! native_read {
    ($source:ty) => {
        impl ModelsRead for $source {
            fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
                <$source>::identity(self)
            }
            fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
                <$source>::ensure_open(self)
            }
            fn request_close(&self) {
                <$source>::request_close(self);
            }
            fn close(
                &self,
            ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send
            {
                <$source>::close(self)
            }
        }
    };
}
native_read!(StudioSkillsRead);
native_read!(StudioSkillsSourceStatusRead);
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeSkillsReadConnection {
    read: ModelsReadHandle<StudioSkillsRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeSkillsSourceStatusReadConnection {
    read: ModelsReadHandle<StudioSkillsSourceStatusRead>,
}
pub async fn open_skills_read(
    reference: BridgeSkillsReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeSkillsReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeSkillsReadConnection {
        read: open_read(move |runtime| runtime.open_skills_read(reference, origin)).await?,
    })
}
pub async fn open_skills_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeSkillsSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeSkillsSourceStatusReadConnection {
        read: open_read(move |runtime| runtime.open_skills_source_status_read(reference, origin))
            .await?,
    })
}
impl BridgeSkillsReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeSkillsReadHeader, BridgeError> {
        Ok(self.read.query(StudioSkillsRead::header)?.await?.into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeSkillsEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeSkillsEntityRead, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.entity(reference.into()))?
            .await?
            .into())
    }
    pub async fn lookup_skill(
        &self,
        key: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.lookup_skill(key))?
            .await?
            .map(Into::into))
    }
    pub async fn skills(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeSkillSummaryReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.skills(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeTextReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.strings(list_id, offset, limit))?
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
impl BridgeSkillsSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioSkillsSourceStatusRead::header)?
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
            .query(move |read| read.text(field_id, offset, max_bytes))?
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
pub async fn skills_discover(project_id: String) -> Result<BridgeSkillsReadTarget, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge.studio.skills_discover(project_id).await?.into())
}
pub async fn skills_search(
    project_id: String,
    query: String,
    limit: u32,
) -> Result<BridgeSkillsSearchResult, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge
        .studio
        .skills_search(project_id, query, limit)
        .await?
        .into())
}
