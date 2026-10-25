use super::*;

pub struct StudioTodoRead {
    pub(super) scope: Scope<TodoMaterial>,
}
pub struct StudioWorkflowRead {
    pub(super) scope: Scope<WorkflowMaterial>,
}
pub struct StudioPlanDocumentRead {
    pub(super) scope: Scope<PlanDocumentMaterial>,
}

impl StudioTodoRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(&self) -> impl Future<Output = Result<TodoReadHeader>> + Send + 'static + use<> {
        self.scope.query(TodoMaterial::header)
    }
    pub fn items(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<TodoItemPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.items(offset, limit))
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.text(field_id, offset, max_bytes))
    }
    pub fn request_close(&self) {
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
}
impl StudioWorkflowRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<WorkflowReadHeader>> + Send + 'static + use<> {
        self.scope.query(WorkflowMaterial::header)
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.text(field_id, offset, max_bytes))
    }
    pub fn request_close(&self) {
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
}
impl StudioPlanDocumentRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<PlanDocumentReadHeader>> + Send + 'static + use<> {
        self.scope.query(PlanDocumentMaterial::header)
    }
    pub fn document(
        &self,
    ) -> impl Future<Output = Result<PlanDocumentValue>> + Send + 'static + use<> {
        self.scope.query(PlanDocumentMaterial::document)
    }
    pub fn request_close(&self) {
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
}
