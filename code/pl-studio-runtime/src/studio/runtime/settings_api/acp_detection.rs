//! Explicit local CLI probe commands. Reads never discover or start a process.

use anyhow::Result;
use pl_protocol::studio::{
    AcpLocalDetectionCommandReply, AcpLocalDetectionSnapshot, CancelAcpLocalDetectionRequest,
    CommandEffectPoint, StartAcpLocalDetectionRequest,
};

use super::StudioRuntime;

impl StudioRuntime {
    pub fn read_acp_local_detection_state(&self) -> AcpLocalDetectionSnapshot {
        self.acp_detection.read_state()
    }

    pub fn start_acp_local_detection(
        &self,
        request: StartAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let operation_id = request.operation_id.clone();
        let acceptance = self.acp_detection.start(request)?;
        Ok(AcpLocalDetectionCommandReply {
            receipt: self.command_receipt(
                operation_id,
                acceptance.changed,
                vec![self.resource_stamp("acp-local-detection", acceptance.snapshot.revision)],
                CommandEffectPoint::Immediate,
                false,
            ),
            snapshot: acceptance.snapshot,
        })
    }

    pub fn cancel_acp_local_detection(
        &self,
        request: CancelAcpLocalDetectionRequest,
    ) -> Result<AcpLocalDetectionCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        Self::validate_operation_id(&request.target_operation_id)?;
        let operation_id = request.operation_id.clone();
        let acceptance = self.acp_detection.cancel(request)?;
        Ok(AcpLocalDetectionCommandReply {
            receipt: self.command_receipt(
                operation_id,
                acceptance.changed,
                vec![self.resource_stamp("acp-local-detection", acceptance.snapshot.revision)],
                CommandEffectPoint::Immediate,
                false,
            ),
            snapshot: acceptance.snapshot,
        })
    }
}
