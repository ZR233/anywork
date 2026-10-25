//! Opaque observers of the original native jobs and their captured execution source.
use super::owner::{Native, Owner};
use super::types::*;
use crate::api::studio::types::{
    BridgeError, BridgeFeedCloseReport, BridgeThreadPreparationProgress,
};
use crate::frb_generated::StreamSink;
use std::sync::Arc;

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAttachmentAdmission {
    owner: Arc<Owner>,
    identity: BridgeAttachmentAdmissionIdentity,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeThreadCreation {
    owner: Arc<Owner>,
    identity: BridgeThreadCreationIdentity,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeCreatedInputExecutionSource {
    source: Arc<pl_studio_runtime::draft_commands::StudioCreatedInputExecutionSource>,
}

pub(super) fn wrap_admission(
    job: pl_studio_runtime::draft_commands::StudioAttachmentAdmission,
) -> Result<BridgeAttachmentAdmission, BridgeError> {
    let identity = BridgeAttachmentAdmissionIdentity {
        operation_id: job.identity().operation_id,
    };
    Ok(BridgeAttachmentAdmission {
        owner: Owner::new(Native::Admission(job))?,
        identity,
    })
}

pub(super) fn wrap_creation(
    job: pl_studio_runtime::draft_commands::StudioThreadCreation,
) -> Result<BridgeThreadCreation, BridgeError> {
    let id = job.identity();
    Ok(BridgeThreadCreation {
        owner: Owner::new(Native::Creation(job))?,
        identity: BridgeThreadCreationIdentity {
            operation_id: id.operation_id,
            project_id: id.project_id,
            input_id: id.input_id,
        },
    })
}

impl BridgeAttachmentAdmission {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeAttachmentAdmissionIdentity {
        self.identity.clone()
    }
    pub async fn result(&self) -> Result<BridgeAttachmentAdmissionOutcome, BridgeError> {
        let Native::Admission(job) = &self.owner.native else {
            return Err(pl_protocol::studio::StudioError::internal().into());
        };
        Ok(job.result().await.into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner
            .close(self.identity.operation_id.clone(), false)
            .await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner
            .close(self.identity.operation_id.clone(), true)
            .await
    }
}
impl Drop for BridgeAttachmentAdmission {
    fn drop(&mut self) {
        self.owner.detach();
    }
}

impl BridgeThreadCreation {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeThreadCreationIdentity {
        self.identity.clone()
    }
    pub async fn result(&self) -> Result<BridgeThreadCreationOutcome, BridgeError> {
        let Native::Creation(job) = &self.owner.native else {
            return Err(pl_protocol::studio::StudioError::internal().into());
        };
        Ok(job.result().await.into())
    }
    pub async fn progress(
        &self,
        sink: StreamSink<BridgeThreadPreparationProgress>,
    ) -> Result<(), BridgeError> {
        self.owner.stream(sink)
    }
    pub async fn execution_source(&self) -> Result<BridgeCreatedInputExecutionSource, BridgeError> {
        let Native::Creation(job) = &self.owner.native else {
            return Err(pl_protocol::studio::StudioError::internal().into());
        };
        Ok(BridgeCreatedInputExecutionSource {
            source: Arc::new(job.execution_source().await?),
        })
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner
            .close(self.identity.operation_id.clone(), false)
            .await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.owner
            .close(self.identity.operation_id.clone(), true)
            .await
    }
}
impl Drop for BridgeThreadCreation {
    fn drop(&mut self) {
        self.owner.detach();
    }
}

impl BridgeCreatedInputExecutionSource {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeCreatedInputExecutionIdentity {
        BridgeCreatedInputExecutionIdentity {
            thread_id: self.source.thread_id(),
            input_id: self.source.input_id(),
            runtime_epoch: self.source.runtime_epoch(),
            incarnation: self.source.incarnation(),
        }
    }
    pub async fn open_execution(
        &self,
    ) -> Result<crate::api::studio::conversation::execution_feed::BridgeThreadExecution, BridgeError>
    {
        let source = self.source.clone();
        crate::api::studio::conversation::execution_feed::open_original_execution(move || {
            source.open_execution()
        })
        .await
    }
}
