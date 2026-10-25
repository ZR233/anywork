use super::*;
use pl_protocol::studio::StudioErrorCode;

impl StudioRuntime {
    pub fn open_todo_read(
        &self,
        thread_id: String,
        reference: TodoReadRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioTodoRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.authoring_read_lease(&thread_id, &origin)?;
            let fact = lease.source().authoring.material_at(
                reference.entry,
                reference.revision,
                &origin,
            )?;
            let Material::Todo(value) = &*fact else {
                return Err(wrong().into());
            };
            let value = value.clone();
            let scope = Scope::open(&runtime, lease, reference.revision, fact, |identity| {
                TodoMaterial::new(identity, value)
            })?;
            Ok(StudioTodoRead { scope })
        })
    }
    pub fn open_workflow_read(
        &self,
        thread_id: String,
        reference: WorkflowReadRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioWorkflowRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.authoring_read_lease(&thread_id, &origin)?;
            let fact = lease.source().authoring.material_at(
                reference.entry,
                reference.revision,
                &origin,
            )?;
            let Material::Workflow(value) = &*fact else {
                return Err(wrong().into());
            };
            let value = value.clone();
            let scope = Scope::open(&runtime, lease, reference.revision, fact, |identity| {
                WorkflowMaterial::new(identity, value)
            })?;
            Ok(StudioWorkflowRead { scope })
        })
    }
    pub fn open_plan_document_read(
        &self,
        thread_id: String,
        reference: PlanDocumentRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioPlanDocumentRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            let lease = runtime.authoring_read_lease(&thread_id, &origin)?;
            let fact = lease.source().authoring.document_at(&reference, &origin)?;
            let Material::Document(value) = &*fact else {
                return Err(wrong().into());
            };
            let value = value.clone();
            let scope = Scope::open(&runtime, lease, origin.revision, fact, |identity| {
                PlanDocumentMaterial::new(identity, &reference, value)
            })?;
            Ok(StudioPlanDocumentRead { scope })
        })
    }
    fn authoring_read_lease(
        &self,
        thread_id: &str,
        origin: &ThreadFacetStamp,
    ) -> Result<ThreadFacetLease> {
        if self.shutdown_committed() {
            return Err(StudioError::new(
                StudioErrorCode::Cancelled,
                "Authoring reads are closed",
                false,
            )
            .into());
        }
        self.thread_observations
            .authoring_sources_at(thread_id, origin)?
            .ok_or_else(|| wrong().into())
    }
}
fn wrong() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The exact requested Authoring source/ref is not available",
        false,
    )
}
