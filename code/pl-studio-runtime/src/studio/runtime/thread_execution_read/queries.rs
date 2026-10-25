use super::*;
use crate::studio::runtime::thread_reads::{
    activity::ActivityMaterial, index::InteractionIndexMaterial, interaction::InteractionMaterial,
    scalar::StorageMaterial, turn::TurnMaterial,
};

pub struct StudioTurnRead {
    pub(super) scope: Scope<TurnMaterial>,
}
pub struct StudioInteractionIndexRead {
    pub(super) scope: Scope<InteractionIndexMaterial>,
}
pub struct StudioInteractionRead {
    pub(super) scope: Scope<InteractionMaterial>,
}
pub struct StudioActivityRead {
    pub(super) scope: Scope<ActivityMaterial>,
}
pub struct StudioStorageRead {
    pub(super) scope: Scope<StorageMaterial>,
}

impl StudioTurnRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(&self) -> impl Future<Output = Result<TurnReadHeader>> + Send + 'static + use<> {
        self.scope.query(TurnMaterial::header)
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
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}

impl StudioInteractionIndexRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<InteractionIndexReadHeader>> + Send + 'static + use<> {
        self.scope.query(InteractionIndexMaterial::header)
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<InteractionBriefPage>> + Send + 'static + use<> {
        self.scope.query(move |value| value.entries(offset, limit))
    }
    pub fn text(
        &self,
        _field_id: u64,
        _offset: u64,
        _max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope.query(|_| {
            Err(StudioError::invalid_argument(
                "Interaction index has no text fields",
            ))
        })
    }
    pub fn request_close(&self) {
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}

impl StudioInteractionRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<InteractionReadHeader>> + Send + 'static + use<> {
        self.scope.query(InteractionMaterial::header)
    }
    pub fn questions(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<QuestionPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.questions(offset, limit))
    }
    pub fn options(
        &self,
        question_index: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<OptionPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.options(question_index, offset, limit))
    }
    pub fn answer_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AnswerEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.answer_entries(offset, limit))
    }
    pub fn answer_values(
        &self,
        entry_index: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AnswerValuePage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.answer_values(entry_index, offset, limit))
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
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}

impl StudioActivityRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ActivityReadHeader>> + Send + 'static + use<> {
        self.scope.query(ActivityMaterial::header)
    }
    pub fn tools(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ActivityToolPage>> + Send + 'static + use<> {
        self.scope.query(move |value| value.tools(offset, limit))
    }
    pub fn wait_targets(
        &self,
        tool_index: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<WaitTargetPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.wait_targets(tool_index, offset, limit))
    }
    pub fn latest_wait_targets(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<WaitTargetPage>> + Send + 'static + use<> {
        self.scope
            .query(move |value| value.latest_wait_targets(offset, limit))
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
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}

impl StudioStorageRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.scope.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.owner.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<StorageReadHeader>> + Send + 'static + use<> {
        self.scope.query(StorageMaterial::header)
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
        self.scope.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.close().await
    }
}
