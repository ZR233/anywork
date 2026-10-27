//! 子任务交互的主会话投影与决议通知。
//!
//! 事实归属不变：原交互只在它所属的子会话中保存与决议。主会话得到的是同一事实的只读摘要，
//! 以及一条稳定的「子交互已决议」消息；它不会因此自动再启动子会话，也不会改写旧轮次报告。

use anyhow::Result;

use pl_core::thread::ThreadSnapshot;
use pl_protocol::{ChildInteractionSummary, InteractionKind, InteractionResolution};

use super::super::StudioRuntime;

impl StudioRuntime {
    /// The session authorized to decide the interactions of `thread_id`.
    ///
    /// A main session decides its own questions; a child's questions are decided through its direct
    /// parent. Callers use this to name the hosting session instead of guessing it from a chat body.
    pub async fn interaction_host_thread(&self, thread_id: &str) -> Result<String> {
        let record = self.read_owned_thread(thread_id).await?;
        Ok(record.parent_thread_id.unwrap_or(record.id))
    }

    /// Lists the pending interactions raised by the direct children of one main session.
    ///
    /// A loaded child answers from its live owner snapshot; a child that is not resident is read
    /// from its saved checkpoint only, so reopening the application still surfaces questions the
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
            for local_id in snapshot
                .interactions
                .keys()
                .chain(snapshot.permissions.keys())
            {
                let Some(interaction) = crate::thread_assembler::project_thread_interaction(
                    &child_id, local_id, &snapshot,
                )?
                else {
                    continue;
                };
                if interaction.status() != pl_protocol::InteractionStatus::Pending {
                    continue;
                }
                if is_child_plan_diagnostic(&snapshot, local_id) {
                    continue;
                }
                summaries.push(ChildInteractionSummary::new(interaction));
            }
        }
        Ok(summaries)
    }

    /// Re-delivers every child decision notice the main session may not have received yet.
    ///
    /// Discovery is the child's own durable decision receipts, so a decision the child's snapshot has
    /// already dropped — the case a crash between the commit and the notice leaves behind — is still
    /// found. Delivery is idempotent by identity: the message identity is derived from the child, the
    /// interaction and the decision revision, and the parent inbox answers an already accepted
    /// identity with its original receipt. It therefore never duplicates a notice, never replays
    /// child work and never wakes a paused main session.
    ///
    /// Returns how many notice identities were reconciled, which is not the number of newly written
    /// messages.
    ///
    /// # Errors
    /// Enumerating a child, reading its durable facts and delivering one notice can all fail. A
    /// delivery failure is returned instead of being counted as success, and the next explicit
    /// main-session turn reconciles it again.
    pub(in crate::studio::runtime) async fn reconcile_child_interaction_notices(
        &self,
        host_thread_id: &str,
    ) -> Result<usize> {
        let mut delivered = 0;
        for child_id in self.child_thread_ids(host_thread_id).await? {
            // Discovery is the child's own durable receipts, never its in-memory snapshot: a snapshot
            // drops settled decisions, so a crash between the commit and the notice would otherwise
            // lose the notice for good. Every discovered decision is therefore already saved.
            let settled = self.settled_decisions(&child_id).await?;
            // The Recovery state comes first: a decision that cannot be projected produces no notice at
            // all, so it must be observable even when delivering the *other* notices fails below. Doing
            // it after the delivery loop would skip it on exactly the failure paths that need it, and
            // would also leave a stale entry behind.
            self.publish_decision_notice_state(&child_id, settled.unprojectable.len())
                .await;
            for interaction in settled.deliverable {
                // A delivery failure is returned to the caller: reconciliation is explicitly
                // retryable and must not be silent. An already accepted identity answers with its
                // original receipt, so a repeated pass never duplicates a notice.
                self.deliver_child_interaction_notice(&child_id, host_thread_id, &interaction)
                    .await?;
                delivered += 1;
            }
        }
        Ok(delivered)
    }

    /// Publishes (or clears) the Recovery state of a child whose saved decisions owe an unbuildable
    /// notice.
    ///
    /// The message never carries content: only the fact and its count. Nothing is published when the
    /// state is unchanged, so a repeated reconciliation does not churn the observed resource.
    async fn publish_decision_notice_state(&self, child_id: &str, unprojectable: usize) {
        let issue_id = format!("interaction-notice:{child_id}");
        let next = (unprojectable > 0).then(|| crate::studio::StudioRecoveryIssue {
            id: issue_id.clone(),
            scope: crate::studio::StudioRecoveryIssueScope::Thread,
            category: crate::studio::StudioRecoveryIssueCategory::Storage,
            impact: crate::studio::StudioRecoveryImpact::ExecutionBlocked,
            action: crate::studio::StudioRecoveryIssueAction::Retry,
            project_id: None,
            thread_id: Some(child_id.to_owned()),
            worktree: None,
            message: format!(
                "{unprojectable} saved decision(s) of this session cannot be presented to the main \
                 session, so their notices were not delivered"
            ),
        });
        let current = self
            .recovery
            .snapshot()
            .into_iter()
            .find(|issue| issue.id == issue_id);
        if current == next {
            return;
        }
        self.recovery.update_if_current(
            &issue_id,
            next,
            || true,
            |issues| {
                self.agent_facility
                    .product_events
                    .emit_recovery_state(issues);
            },
        );
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
                    && record.visibility == crate::studio::ThreadVisibility::Active
            })
            .map(|record| record.id)
            .collect())
    }

    /// Loaded or saved state of every direct child of `host_thread_id`, never activating one.
    async fn child_states(&self, host_thread_id: &str) -> Result<Vec<(String, ThreadSnapshot)>> {
        let mut states = Vec::new();
        for child_id in self.child_thread_ids(host_thread_id).await? {
            if let Some(thread) = self.threads.thread(&child_id) {
                states.push((child_id, thread.snapshot()));
                continue;
            }
            let Some(record) = self.store.read_thread(&child_id).await? else {
                continue;
            };
            let thread = pl_protocol::Thread::from(record);
            // Strictly read-only: a projection never imports a legacy checkpoint, never deletes
            // the files migration replaced and never touches the state directory, so listing
            // child questions cannot modify storage.
            let Some(checkpoint) =
                crate::studio::thread_factory::recovery::load_checkpoint_read_only(
                    &self.store,
                    &thread,
                )
                .await?
            else {
                continue;
            };
            states.push((child_id, checkpoint.state));
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
        if interaction.status() == pl_protocol::InteractionStatus::Pending {
            return Ok(());
        }
        let owner = self.read_owned_thread(&interaction.scope.thread_id).await?;
        let Some(parent) = owner.parent_thread_id.clone() else {
            // A main session answers its own question in place; nothing is handed over.
            return Ok(());
        };
        // A child Plan record is a diagnostic: replaying its terminal state must not write anything
        // into the main session's inbox.
        let local_id = interaction_local_id(interaction)?;
        if self.is_child_plan_record(&owner, &local_id).await? {
            return Ok(());
        }
        // Only a saved outcome may be announced. The decision path waits for the child's own commit
        // first (`await_child_decision_durable`), and reconciliation discovers decisions from those
        // same receipts, so an unsaved decision is a retryable condition here instead of a silent
        // success the caller could mistake for a delivered notice.
        if !self
            .stored_decision_is_durable(&owner.id, &local_id, interaction.revision)
            .await?
        {
            return Err(super::interaction::child_decision_not_saved(interaction));
        }
        // A delivery failure is reported to the caller (the same command is retryable) and reconciled
        // by the next explicit main-session turn; it is never silently dropped.
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
        self.threads
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
        (pl_protocol::InteractionStatus::Cancelled, _) => ("cancelled", serde_json::Value::Null),
        (pl_protocol::InteractionStatus::Expired, _) => ("expired", serde_json::Value::Null),
        (pl_protocol::InteractionStatus::Pending, _) => ("pending", serde_json::Value::Null),
        (
            pl_protocol::InteractionStatus::Resolved,
            Some(InteractionResolution::UserInput(resolution)),
        ) => {
            let questions = match &interaction.content {
                pl_protocol::InteractionContent::UserInput(value) => value.questions(),
                pl_protocol::InteractionContent::ToolApproval(_) => &[],
            };
            let answers = questions
                .iter()
                .filter_map(|question| {
                    let answer = resolution.answers.get(&question.id)?;
                    if answer.answers.is_empty() {
                        return None;
                    }
                    let projected = if question.is_secret {
                        pl_protocol::ThreadToolUserInputAnswer::redacted(question.id.clone())
                    } else {
                        pl_protocol::ThreadToolUserInputAnswer::new(
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
            pl_protocol::InteractionStatus::Resolved,
            Some(InteractionResolution::ToolApproval(resolution)),
        ) => (
            "resolved",
            serde_json::json!({
                "decision": match resolution.decision {
                    pl_protocol::ToolApprovalResolution::Approved => "approved",
                    pl_protocol::ToolApprovalResolution::Denied => "denied",
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

/// Whether this record is a Plan interaction, which is a main-session capability.
fn is_child_plan_diagnostic(snapshot: &ThreadSnapshot, local_id: &str) -> bool {
    snapshot.interactions.get(local_id).is_some_and(|record| {
        record.request.payload.format() == crate::plan_tool::PLAN_CONFIRMATION_FORMAT
    })
}

/// The local interaction identity inside its owning Thread.
fn interaction_local_id(interaction: &crate::InteractionRequest) -> anyhow::Result<String> {
    let (_thread, local) =
        crate::thread_assembler::decode_interaction_key(&interaction.interaction_id)?;
    Ok(local.to_owned())
}
