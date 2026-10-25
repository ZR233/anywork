use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::products::identity::{ProductReadVersion, ProductResource};

use super::super::StudioRuntime;
use super::scope::WorkspaceReadScope;
use super::source::DirectorySnapshot;
use super::*;

pub struct StudioProjectDirectoryRead {
    scope: WorkspaceReadScope<Arc<DirectorySnapshot>>,
}
pub struct StudioAgentDirectoryRead {
    scope: WorkspaceReadScope<Arc<DirectorySnapshot>>,
}
/// Query windows and a single Thread use the same typed immutable read, with distinct budgets.
pub struct StudioThreadDirectoryRead {
    scope: WorkspaceReadScope<Arc<DirectorySnapshot>>,
}

impl StudioRuntime {
    /// Pins only the original exposed origin/ref; opening participates in the same 64-call owner.
    pub fn open_project_directory_read(
        &self,
        reference: ProjectDirectoryReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioProjectDirectoryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.workspace_source.pin(
                &origin,
                reference.entry,
                reference.revision,
                ProductResource::ProjectDirectory,
            )?;
            let scope = WorkspaceReadScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                &material.binding,
                material.clone(),
            )?;
            Ok(StudioProjectDirectoryRead { scope })
        })
    }
    pub fn open_agent_directory_read(
        &self,
        reference: AgentDirectoryReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioAgentDirectoryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.workspace_source.pin(
                &origin,
                reference.entry,
                reference.revision,
                ProductResource::AgentDirectory,
            )?;
            let scope = WorkspaceReadScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                &material.binding,
                material.clone(),
            )?;
            Ok(StudioAgentDirectoryRead { scope })
        })
    }
    /// Single-Thread metadata is opened with the ref issued by ThreadDirectoryScope::Thread,
    /// not by activating/reconstructing a Thread or converting a current command target.
    pub fn open_thread_directory_read(
        &self,
        reference: ThreadDirectoryReadRef,
        origin: ProductReadOrigin,
    ) -> impl Future<Output = Result<StudioThreadDirectoryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let material = runtime.workspace_source.pin(
                &origin,
                reference.entry,
                reference.revision,
                ProductResource::ThreadDirectory,
            )?;
            let scope = WorkspaceReadScope::open(
                &runtime,
                origin,
                ProductReadVersion::Value {
                    entry: reference.entry,
                    revision: reference.revision,
                },
                &material.binding,
                material.clone(),
            )?;
            Ok(StudioThreadDirectoryRead { scope })
        })
    }
}

impl StudioProjectDirectoryRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ProjectDirectoryReadHeader>> + Send + 'static + use<> {
        self.scope.query(|value| value.project_header())
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ProjectDirectoryEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.project_entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<ProjectDirectoryEntityRead>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.project_entity(reference))
    }
    pub fn lookup_project(
        &self,
        project_id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |value| Ok(value.lookup(&project_id)))
    }
    pub fn projects(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ProjectRecordReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.projects(list_id, offset, limit))
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.text(field_id, offset, max_bytes))
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}

impl StudioAgentDirectoryRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<AgentDirectoryReadHeader>> + Send + 'static + use<> {
        self.scope.query(|value| value.agent_header())
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AgentDirectoryEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.agent_entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<AgentDirectoryEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |value| value.agent_entity(reference))
    }
    pub fn lookup_agent(
        &self,
        agent_id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |value| Ok(value.lookup(&agent_id)))
    }
    pub fn agents(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AgentDirectoryEntryReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.agents(list_id, offset, limit))
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.text(field_id, offset, max_bytes))
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}

impl StudioThreadDirectoryRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ThreadDirectoryReadHeader>> + Send + 'static + use<> {
        self.scope.query(|value| value.thread_header())
    }
    pub fn entries(
        &self,
        cursor: Option<String>,
        limit: u32,
    ) -> impl Future<Output = Result<ThreadDirectoryEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.thread_entries(cursor, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<ThreadDirectoryEntityRead>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.thread_entity(reference))
    }
    pub fn lookup_thread(
        &self,
        thread_id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |value| Ok(value.lookup(&thread_id)))
    }
    pub fn threads(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<WorkspaceThreadRecordReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.threads(list_id, offset, limit))
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.text(field_id, offset, max_bytes))
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}
