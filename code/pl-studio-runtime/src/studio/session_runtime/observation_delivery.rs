//! Saved report acknowledgements and parent product routing.
use super::*;
use crate::thread_assembler::observation::{
    ParentMessageDelivery, ParentMessageSkip, ParentReportAcknowledgement,
};
use anyhow::Context as _;
impl SessionRuntime {
    pub(crate) async fn acknowledge_parent_reports(
        &self,
        child: &crate::Thread,
    ) -> Result<ParentReportAcknowledgement, ThreadAssemblyError> {
        if let Some(parent) = child.parent_thread_id.as_deref()
            && self.parent_is_acp(parent)
        {
            // The child's own history is still durable. ACP has no Native inbox whose
            // acknowledgement could authorize or delay this child's retirement.
            return Ok(ParentReportAcknowledgement::Absent);
        }
        let failure = |source: anyhow::Error| ThreadAssemblyError::Resource {
            operation: "acknowledge terminal parent reports",
            source: source.into_boxed_dyn_error(),
        };
        let parent = child
            .parent_thread_id
            .as_deref()
            .context("terminal child has no parent")
            .map_err(failure)?;
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        let parent_record = services.record(parent).await.map_err(failure)?;
        let had_pending = self
            .pending_native_deliveries(&parent_record)
            .await
            .map_err(failure)?
            .iter()
            .any(|pending| {
                matches!(
                    pending.source(),
                    super::pending_delivery::PendingNativeDeliverySource::Terminal {
                        child_id,
                        ..
                    } if child_id == &child.id
                )
            });
        Box::pin(self.recover_saved_review_deliveries(child))
            .await
            .map_err(failure)?;
        self.join_review_delivery(&child.id)
            .await
            .map_err(failure)?;
        let remaining = self
            .pending_native_deliveries(&parent_record)
            .await
            .map_err(failure)?
            .into_iter()
            .filter(|pending| {
                matches!(
                    pending.source(),
                    super::pending_delivery::PendingNativeDeliverySource::Terminal {
                        child_id,
                        ..
                    } if child_id == &child.id
                )
            })
            .map(|pending| pending.message().id.clone())
            .collect::<Vec<_>>();
        if !remaining.is_empty() {
            return Err(failure(anyhow::anyhow!(
                "parent reports were not settled: {}",
                remaining.join(", ")
            )));
        }
        Ok(if had_pending {
            ParentReportAcknowledgement::Proven
        } else {
            ParentReportAcknowledgement::Absent
        })
    }
    pub(crate) async fn notify_parent(
        &self,
        id: &str,
        message: pl_core::thread::inbox::ThreadMessage,
        wake: bool,
    ) -> Result<ParentMessageDelivery, ThreadAssemblyError> {
        if self.parent_is_acp(id) {
            return Ok(ParentMessageDelivery::Skipped(
                ParentMessageSkip::TargetUnavailable,
            ));
        }
        let target = {
            let state = self.0.state();
            if state.close.closing {
                return Ok(ParentMessageDelivery::Skipped(ParentMessageSkip::Closing));
            }
            Some(
                state
                    .members
                    .entries
                    .get(id)
                    .ok_or_else(|| ThreadAssemblyError::Identity(id.into()))?,
            )
            .filter(|entry| {
                entry.native().is_ok_and(|native| {
                    native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
                })
            })
            .and_then(|entry| {
                let native = entry.native().ok()?;
                Some((native.thread.clone(), native.execution))
            })
        };
        let Some((thread, execution)) = target else {
            return Ok(ParentMessageDelivery::Skipped(
                ParentMessageSkip::TargetUnavailable,
            ));
        };
        // The committed inbox already owns this immutable terminal watermark. In particular,
        // replay must not resend a migrated, previously consumed notification with a new body.
        let snapshot = thread.snapshot();
        let message = match snapshot
            .inbox
            .iter()
            .find(|record| record.message.id == message.id)
        {
            Some(record) if record.sequence <= snapshot.consumed_messages => {
                return Ok(ParentMessageDelivery::Accepted {
                    message_id: message.id.clone(),
                    sequence: record.sequence,
                });
            }
            Some(record) => record.message.clone(),
            None => message,
        };
        let message_id = message.id.clone();
        let result = if wake {
            thread.send_message_and_resume(message, execution).await
        } else {
            // History projection can repair an inbox but cannot start a model call.
            thread.send_message(message).await
        };
        match result {
            Ok(sequence) => Ok(ParentMessageDelivery::Accepted {
                message_id,
                sequence,
            }),
            Err(ThreadError::Closed) if thread.snapshot().lifecycle != ThreadLifecycle::Open => Ok(
                ParentMessageDelivery::Skipped(ParentMessageSkip::ClosedDuringAdmission),
            ),
            Err(error) => Err(error.into()),
        }
    }

    pub(crate) fn parent_is_acp(&self, parent: &str) -> bool {
        let state = self.0.state();
        state
            .members
            .entries
            .get(parent)
            .is_some_and(|entry| matches!(entry.runtime, crate::session::AgentRuntime::Acp(_)))
            || state.agent_services.as_ref().is_some_and(|services| {
                services
                    .events
                    .agent_execution_identity(parent)
                    .is_some_and(|(_, binding, _)| matches!(binding, crate::AgentBinding::Acp(_)))
            })
    }
}
