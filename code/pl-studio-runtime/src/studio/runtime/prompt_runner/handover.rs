//! 子任务交互的主会话投影与决议通知。
//!
//! 事实归属不变：原交互只在它所属的子会话中保存与决议。主会话得到的是同一事实的只读摘要，
//! 以及一条稳定的「子交互已决议」消息；它不会因此自动再启动子会话，也不会改写旧轮次报告。

use anyhow::Result;

use crate::{ChildInteractionSummary, InteractionKind, InteractionResolution};
use pl_core::thread::ThreadSnapshot;

use super::super::StudioRuntime;

impl StudioRuntime {
    /// The session authorized to decide the interactions of `thread_id`.
    ///
    /// A main session decides its own questions; a child's questions are decided through its direct
    /// parent. Callers use this to name the hosting session instead of guessing it from a chat body.
    pub(crate) async fn interaction_host_thread(&self, thread_id: &str) -> Result<String> {
        let record = self.read_owned_thread(thread_id).await?;
        Ok(record.parent_thread_id.unwrap_or(record.id))
    }

    /// Lists the pending interactions raised by the direct children of one main session.
    ///
    /// A loaded child answers from its live owner snapshot; a child that is not resident is read
    /// from its saved current only, so reopening the application still surfaces questions the
    /// user has to decide, without activating a child, starting a model call or touching its
    /// workspace. A child Plan interaction is main-session-only and stays a diagnostic: it is not
    /// offered here, and its resolution entry rejects it too.
    pub async fn read_child_interactions(
        &self,
        host_thread_id: &str,
    ) -> Result<Vec<ChildInteractionSummary>> {
        // Opening publishes the parent owner before cold-child preparation finishes. A composer
        // read must await that lifecycle boundary while remaining strictly read-only itself.
        let _lifecycle_guard = self.lifecycle_lock.lock().await;
        // Listing shares the decision entry's host check: a child id cannot read the interactions of
        // its own subtree, so "main session projection, child read-only" holds for reads too.
        self.ensure_root_host(host_thread_id).await?;
        let mut summaries = Vec::new();
        for (child_id, snapshot) in self.child_states(host_thread_id).await? {
            summaries.extend(crate::thread_assembler::project_pending_child_interactions(
                &child_id, &snapshot,
            )?);
        }
        Ok(summaries)
    }

    /// The Thread ids of every active direct child of `host_thread_id`, never activating one.
    async fn child_thread_ids(&self, host_thread_id: &str) -> Result<Vec<String>> {
        Ok(self
            .store
            .read_directory_tree(host_thread_id)
            .await?
            .into_iter()
            .filter(|record| {
                record.parent_thread_id.as_deref() == Some(host_thread_id)
                    && !record.session.archived
            })
            .map(|record| record.agent.thread_id)
            .collect())
    }

    /// Loaded or saved state of every direct child of `host_thread_id`, never activating one.
    async fn child_states(&self, host_thread_id: &str) -> Result<Vec<(String, ThreadSnapshot)>> {
        let mut states = Vec::new();
        for child_id in self.child_thread_ids(host_thread_id).await? {
            if let Some(thread) = self
                .session_of(&child_id)
                .and_then(|session| session.thread(&child_id))
            {
                states.push((child_id, thread.snapshot()));
                continue;
            }
            let Some(record) = self.store.read_thread(&child_id).await? else {
                continue;
            };
            let thread = crate::Thread::from(record);
            let Some(current) = self.store.load_current_read_only(&thread).await? else {
                continue;
            };
            states.push((child_id, current.state.to_paused_snapshot()));
        }
        Ok(states)
    }

    /// Tells the main session that a child interaction reached a decision.
    ///
    /// The decision itself stays the child's only decision fact; this is a durable message under an
    /// identity derived from the child, the interaction and the decision revision. Delivery never
    /// wakes a paused main session: the notice is a fact consumed by the next explicit turn.
    pub(super) async fn notify_host_interaction_decided(
        &self,
        interaction: &crate::InteractionRequest,
    ) -> anyhow::Result<()> {
        if interaction.status() == crate::InteractionStatus::Pending {
            return Ok(());
        }
        let owner = self.read_owned_thread(&interaction.scope.thread_id).await?;
        let Some(parent) = owner.parent_thread_id.clone() else {
            // A main session answers its own question in place; nothing is handed over.
            return Ok(());
        };
        if matches!(
            interaction.scope.purpose,
            crate::InteractionPurpose::AgentSessionPlanConfirmation(_)
        ) {
            return Ok(());
        }
        self.deliver_child_interaction_notice(&owner.id, &parent, interaction)
            .await
    }

    async fn deliver_child_interaction_notice(
        &self,
        child_thread_id: &str,
        host_thread_id: &str,
        interaction: &crate::InteractionRequest,
    ) -> Result<()> {
        let (status, decision) = redacted_outcome(interaction);
        let body = serde_json::json!({
            "childThreadId": child_thread_id,
            "interactionId": interaction.interaction_id,
            "kind": interaction.kind().as_str(),
            "revision": interaction.revision,
            "status": status,
            "decision": decision,
        });
        let message_id = format!(
            "studio.child.interaction.{}:{}:{}:{}",
            child_thread_id.len(),
            child_thread_id,
            interaction.interaction_id,
            interaction.revision
        );
        let content = serde_json::to_string(&body)?;
        self.require_session(host_thread_id)?
            .notify_parent(
                host_thread_id,
                pl_core::thread::inbox::ThreadMessage {
                    kind: pl_core::context::AgentMessageKind::Report,
                    id: message_id,
                    source_id: format!("studio.child-interaction:{child_thread_id}"),
                    payload: pl_core::context::OpaquePayload::new(
                        "pl.studio.child-interaction-decision",
                        1,
                        content.clone(),
                    )?,
                    context: vec![pl_core::context::ContextContent::Text {
                        text: notice_text(child_thread_id, interaction, status, &content).into(),
                    }],
                },
                // A paused main session consumes this fact only on its next explicit turn.
                false,
            )
            .await?;
        Ok(())
    }
}

/// The main-session-facing summary of a decision, with secret answers withheld.
///
/// The child keeps the accepted values; only the notice is redacted, exactly like the existing
/// timeline projection of a secret question.
fn redacted_outcome(interaction: &crate::InteractionRequest) -> (&'static str, serde_json::Value) {
    match (interaction.status(), interaction.resolution()) {
        // A cancelled or expired request produced no user decision at all; the notice must not imply
        // that the child has an answer or a permission it never received.
        (crate::InteractionStatus::Cancelled, _) => ("cancelled", serde_json::Value::Null),
        (crate::InteractionStatus::Expired, _) => ("expired", serde_json::Value::Null),
        (crate::InteractionStatus::Pending, _) => ("pending", serde_json::Value::Null),
        (
            crate::InteractionStatus::Resolved,
            Some(InteractionResolution::UserInput(resolution)),
        ) => {
            let questions = match &interaction.content {
                crate::InteractionContent::UserInput(value) => value.questions(),
                crate::InteractionContent::ToolApproval(_) => &[],
            };
            let answers = questions
                .iter()
                .filter_map(|question| {
                    let answer = resolution.answers.get(&question.id)?;
                    if answer.answers.is_empty() {
                        return None;
                    }
                    let projected = if question.is_secret {
                        crate::ThreadToolUserInputAnswer::redacted(question.id.clone())
                    } else {
                        crate::ThreadToolUserInputAnswer::new(
                            question.id.clone(),
                            answer.answers.clone(),
                        )
                    };
                    serde_json::to_value(projected).ok()
                })
                .collect::<Vec<_>>();
            (
                "resolved",
                serde_json::json!({
                    "answers": answers,
                    "answered": !answers.is_empty(),
                }),
            )
        }
        // A permission decision carries no user content of its own; the decision itself is the fact
        // the main session needs, never the tool arguments.
        (
            crate::InteractionStatus::Resolved,
            Some(InteractionResolution::ToolApproval(resolution)),
        ) => (
            "resolved",
            serde_json::json!({
                "decision": match resolution.decision {
                    crate::ToolApprovalResolution::Approved => "approved",
                    crate::ToolApprovalResolution::Denied => "denied",
                },
            }),
        ),
        // A terminal record without a stored resolution cannot claim any decision.
        (_, None) => ("unrecorded", serde_json::Value::Null),
    }
}

/// Wording that matches what the decision actually means for the child.
fn notice_text(
    child_thread_id: &str,
    interaction: &crate::InteractionRequest,
    status: &str,
    content: &str,
) -> String {
    let id = &interaction.interaction_id;
    let revision = interaction.revision;
    match (status, interaction.kind()) {
        // A cancelled or expired request never produced a user decision; saying "answered" would make
        // the main session believe a question or a permission was settled.
        ("cancelled", _) => format!(
            "The child session {child_thread_id} had its pending request cancelled \
             (interaction {id}, revision {revision}); no user decision was recorded. Decide whether \
             and how to schedule that member again.\n{content}"
        ),
        ("expired", _) => format!(
            "The pending request of the child session {child_thread_id} expired without a user \
             decision (interaction {id}, revision {revision}). Decide whether and how to schedule \
             that member again.\n{content}"
        ),
        (_, InteractionKind::ToolApproval) => format!(
            "The child session {child_thread_id} recorded the user's permission decision for its \
             pending call (interaction {id}, revision {revision}). The decision only releases that \
             exact call while it is still live; an approval never revives a call that was stopped, \
             cancelled, revoked or lost with an earlier process.\n{content}"
        ),
        _ => format!(
            "The child session {child_thread_id} answered its pending question \
             (interaction {id}, revision {revision}). Its own execution did not resume: decide \
             whether and how to schedule that member again.\n{content}"
        ),
    }
}
