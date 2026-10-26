//! 交互读取、收束与重启后的 pending 交互恢复。

use anyhow::{Context, Result};

use crate::{InteractionRequest, InteractionResolution, InteractionStatus};

use super::super::{StudioResolveInteractionResponse, StudioRuntime};
use super::{UserThreadAction, ensure_thread_not_archived};

/// Keeps the source's durability when the same projected facts are used for validation and replies.
pub(in crate::studio::runtime) struct InteractionForResolve {
    pub(in crate::studio::runtime) interaction: InteractionRequest,
    durable: bool,
}

impl StudioRuntime {
    /// Resolves one interaction decision under a durable, idempotent operation identity.
    ///
    /// The order is fixed so that nothing observable happens before the request is proven legitimate:
    /// validate the request, read the original interaction, prove the host, exclude a child Plan
    /// record, compare the observed revision, prove the operation identity is not used elsewhere, and
    /// only then commit the decision on its own Thread. A terminal repeat is answered from the stored
    /// decision, never by re-admitting work.
    ///
    /// # Errors
    /// Rejects a missing or non-root host, an interaction that is not hosted by it, a stale revision,
    /// a reused operation id, a conflicting terminal decision and a child Plan record.
    pub async fn resolve_interaction(
        &self,
        operation_id: String,
        host_thread_id: String,
        expected_revision: u64,
        interaction_id: String,
        resolution: InteractionResolution,
    ) -> Result<StudioResolveInteractionResponse> {
        Self::validate_operation_id(&operation_id)?;
        if host_thread_id.trim().is_empty() {
            return Err(anyhow::Error::new(
                pl_protocol::studio::StudioError::invalid_argument("hostThreadId is required"),
            ));
        }
        let lifecycle_guard = self.lifecycle_lock.lock().await;
        let current = match self.read_interaction_for_resolve(&interaction_id).await? {
            Some(current) => current,
            None => {
                return Err(anyhow::Error::new(
                    pl_protocol::studio::StudioError::not_found("interaction"),
                ));
            }
        };
        let interaction = current.interaction;
        // Hosting is decided from the directory association of both sessions, never from the caller's
        // claim: the host must be the main session and the request must come from that session or one
        // of its direct children.
        let owner = self
            .ensure_interaction_host(&host_thread_id, &interaction)
            .await?;
        // An archived Thread is read-only. The check runs before every bypass below, so a stored
        // terminal decision cannot be replayed into a Thread the user has archived.
        ensure_thread_not_archived(&owner, UserThreadAction::Respond)?;
        // A Plan confirmation is a main-session capability. A child record stays a diagnostic and is
        // rejected here, before every bypass below — a terminal child Plan record must not be able to
        // notify the host either.
        let local_id = crate::thread_assembler::decode_interaction_key(&interaction_id)?.1;
        let thread_id = interaction.scope.thread_id.clone();
        if self.is_child_plan_record(&owner, local_id).await? {
            return Err(anyhow::Error::new(
                pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::PermissionDenied,
                    "A child Plan confirmation stays a diagnostic and is not decidable",
                    false,
                )
                .with_reason(
                    pl_protocol::studio::StudioErrorReason::InteractionNotHosted,
                    serde_json::json!({
                        "interactionId": interaction.interaction_id,
                        "interactionThreadId": thread_id,
                    }),
                ),
            ));
        }
        // The observed revision is a compare-and-swap against a still-pending interaction. A terminal
        // one already moved past it, and only its stored decision can prove a repeat; comparing the
        // revision there would answer a legitimate retry with a false conflict.
        if interaction.status() == InteractionStatus::Pending
            && interaction.revision != expected_revision
        {
            return Err(anyhow::Error::new(
                pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::StaleRevision,
                    "The interaction changed since it was observed; reload before deciding",
                    true,
                )
                .with_reason(
                    pl_protocol::studio::StudioErrorReason::StaleInteraction,
                    serde_json::json!({
                        "interactionId": interaction.interaction_id,
                        "expectedRevision": expected_revision,
                        "currentRevision": interaction.revision,
                    }),
                ),
            ));
        }
        // One operation identity belongs to one interaction: reusing it for another target is an
        // identity conflict, not a second decision.
        self.ensure_operation_not_reused(&thread_id, local_id, &operation_id)
            .await?;
        // A durable receipt can only acknowledge a terminal decision, never admit new work from
        // an old pending revision that has already left the owner and its checkpoint.
        if current.durable || interaction.status() != InteractionStatus::Pending {
            if interaction.resolution().as_ref() != Some(&resolution) {
                return Err(anyhow::Error::new(
                    pl_protocol::studio::StudioError::new(
                        pl_protocol::studio::StudioErrorCode::Conflict,
                        "The interaction already has a different terminal decision",
                        false,
                    )
                    .with_reason(
                        pl_protocol::studio::StudioErrorReason::StaleInteraction,
                        serde_json::json!({
                            "interactionId": interaction.interaction_id,
                            "currentRevision": interaction.revision,
                        }),
                    ),
                ));
            }
            // The replay answers with the identity the decision was really accepted under: a client
            // that retries with a fresh operation id must not receive a receipt naming that id.
            let Some(accepted_operation_id) = self
                .stored_decision_operation_id(&thread_id, local_id)
                .await?
            else {
                // A decision written before operation identities existed cannot prove which operation
                // produced it, so answering with the caller's own identity would claim an acceptance
                // this command never had. The stored decision stays readable; only the replay is
                // refused.
                return Err(decision_identity_unrecorded(&interaction));
            };
            // The repeat reproduces the receipt of the acceptance that really happened: the decision
            // is applied fact, so it stays `Applied` instead of looking like a no-op every time. Its
            // durability flag is reproduced too: a main session's own decision answered
            // "not yet durable" the first time, and reading the same fact back later must not upgrade
            // what that receipt said (design/18 §18.2). Only a child decision waited for its own
            // commit, so only a child receipt carries `durable`.
            let durable = owner.parent_thread_id.is_some();
            {
                // The commit is already durable fact; the wait and the notice must not run under the
                // lifecycle lock, or a slow child save would hold up closing this session.
                drop(lifecycle_guard);
                // A terminal repeat is the only retry the decision notice gets; the notice is still
                // only delivered once the decision itself is durable.
                self.await_child_decision_durable(&thread_id, local_id, &interaction)
                    .await?;
                self.notify_host_interaction_decided(&interaction).await?;
            }
            return Ok(self.interaction_command_reply(
                accepted_operation_id,
                interaction,
                true,
                durable,
            ));
        }
        self.ensure_thread_owner(&thread_id).await?;
        // 到达这里的决议一定来自 Pending 交互，真实受理路径只有 UserInput 决议：
        // 权限决议（ToolApproval）不是用户消息，重复决议在上方已终结短路或持久回执
        // 路径返回，不产生新的受理事实（design/17 §17.1）。
        let user_answered = matches!(resolution, InteractionResolution::UserInput(_));
        let interaction = self
            .threads
            .resolve_product_interaction(&interaction_id, &operation_id, resolution)
            .await
            .map_err(interaction_error)?;
        if user_answered {
            self.agent_facility
                .product_events
                .record_user_message(&thread_id, crate::studio::unix_seconds());
        }
        // 先让子决议可靠保存到它自己的固定水位，再投递给主会话：两个会话不在同一个事务里，
        // 因此顺序必须是「先保存、后投递」。投递失败上报给调用方（同一命令可重试），由既有
        // 对账补投，绝不静默丢弃。
        let durable = {
            // Both the decision and its own receipt are committed by now; the durability wait and the
            // notice delivery are post-commit steps, so they run outside the lifecycle lock.
            drop(lifecycle_guard);
            let durable = self
                .await_child_decision_durable(&thread_id, local_id, &interaction)
                .await?;
            self.notify_host_interaction_decided(&interaction).await?;
            durable
        };
        Ok(self.interaction_command_reply(operation_id, interaction, true, durable))
    }

    /// Waits until the decision this command produced is saved, for a child Thread.
    ///
    /// A main session's own decision is saved by the same owner that answered the command, so there is
    /// nothing to wait for. A child decision is committed on the child, and its notice must not be
    /// delivered before that commit is durable.
    async fn await_child_decision_durable(
        &self,
        thread_id: &str,
        local_id: &str,
        interaction: &InteractionRequest,
    ) -> Result<bool> {
        let owner = self.read_owned_thread(thread_id).await?;
        if owner.parent_thread_id.is_none() {
            return Ok(false);
        }
        let deadline = tokio::time::Instant::now() + CHILD_DECISION_WAIT;
        loop {
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            if remaining.is_zero() {
                return Err(child_decision_not_saved(interaction));
            }
            // The read itself is bounded by the remaining budget: a slow store must not extend the
            // wait past the deadline this command promised.
            match tokio::time::timeout(
                remaining,
                self.stored_decision_is_durable(thread_id, local_id, interaction.revision),
            )
            .await
            {
                Ok(saved) => {
                    if saved? {
                        return Ok(true);
                    }
                }
                // A read that cannot finish inside the budget is the same retryable condition as an
                // unsaved decision.
                Err(_) => return Err(child_decision_not_saved(interaction)),
            }
            let remaining = deadline.saturating_duration_since(tokio::time::Instant::now());
            if !remaining.is_zero() {
                tokio::time::sleep(CHILD_DECISION_POLL.min(remaining)).await;
            }
        }
    }

    /// Whether `local_id` already reached a terminal state in its own durable receipts.
    ///
    /// A question and a permission request are two families of decision with two receipt kinds, and
    /// either of them may be the record a command decided, so both are checked. Only a saved
    /// terminal state counts: the in-memory projection alone cannot prove the outcome survives a
    /// restart, and a notice delivered for it could describe a decision that never persisted.
    pub(super) async fn stored_decision_is_durable(
        &self,
        thread_id: &str,
        local_id: &str,
        revision: u64,
    ) -> Result<bool> {
        let history = self.read_timeline_history(thread_id).await?;
        if let Some(receipt) = history
            .latest_fact_receipt(&crate::studio::thread_projection::order::receipt_id(
                "interaction",
                local_id,
            ))
            .await?
        {
            let record: pl_core::thread::interactions::InteractionRecord =
                serde_json::from_str(&receipt.payload)?;
            if !matches!(
                record.state,
                pl_core::thread::interactions::InteractionState::Pending
            ) && record.revision >= revision
            {
                return Ok(true);
            }
        }
        let Some(receipt) = history
            .latest_fact_receipt(&crate::studio::thread_projection::order::receipt_id(
                "permission",
                local_id,
            ))
            .await?
        else {
            return Ok(false);
        };
        let record: pl_core::thread::permissions::PermissionRecord =
            serde_json::from_str(&receipt.payload)?;
        Ok(!matches!(
            record.state,
            pl_core::thread::permissions::PermissionState::Pending
        ) && record.revision >= revision)
    }

    /// Every decision fact this Thread can still prove, settled ones included.
    ///
    /// The canonical snapshot keeps only pending decisions and a saved checkpoint may already have
    /// dropped a settled one, while the durable receipt of that same identity still proves it. One
    /// union of both — newest revision per identity, receipt winning a tie — is the single read-only
    /// source every identity question reads, so operation reuse, terminal replay, the child Plan
    /// exclusion and the notice reconciliation can never disagree. Nothing here activates an owner,
    /// migrates storage or cleans a legacy file.
    ///
    /// Three conditions are kept apart, because each one has a different correct answer:
    ///
    /// - a **legacy** record is complete and simply predates operation identities;
    /// - a **damaged** record is present but undecodable, so it becomes [`DecisionRecord::Unreadable`]
    ///   and every caller can report it (the reconciliation) or refuse to act on an unprovable fact
    ///   (the identity checks) instead of mistaking it for old history. Its revision is unknown, so a
    ///   newer snapshot record never displaces it: an unknown revision cannot prove it was replaced;
    /// - a **storage read failure** — the checkpoint, the durable fence or the receipt query itself —
    ///   is propagated as the typed storage fault it is, so a command fails retryably rather than
    ///   deciding on an empty set of facts. This is the same boundary every other read path in this
    ///   runtime already uses, and it is why an unreadable store blocks a submission instead of
    ///   silently reconciling nothing.
    async fn decision_records(&self, thread_id: &str) -> Result<Vec<DecisionRecord>> {
        let mut facts = std::collections::BTreeMap::new();
        if let Some(thread) = self.threads.thread(thread_id) {
            collect_decision_records(&thread.snapshot(), &mut facts);
        } else {
            // A read failure is propagated, never read as "this Thread has no decisions": identity
            // checks that silently lost the saved facts would allow a reused operation id and would
            // stop recognising a child Plan record.
            let thread = self.read_owned_thread(thread_id).await?;
            let thread: pl_protocol::Thread = thread.into();
            if let Some(checkpoint) =
                crate::studio::thread_factory::recovery::load_checkpoint_read_only(
                    &self.store,
                    &thread,
                )
                .await?
            {
                collect_decision_records(&checkpoint.state, &mut facts);
            }
        }
        // A storage fault or an unreached durable fence is propagated: only a reliable answer may
        // become "this identity does not exist".
        let history = self.read_timeline_history(thread_id).await?;
        for receipt in history.decision_receipts().await? {
            // A saved row that cannot be decoded is a corrupted decision, not a missing one: its
            // identity is still known from the receipt key, so callers can fail closed on it and the
            // reconciliation can report it, instead of mistaking it for old history.
            let record = match decode_decision_receipt(&receipt) {
                Ok(record) => record,
                Err(error) => {
                    let local_id = decision_receipt_local_id(&receipt.item_id);
                    tracing::warn!(
                                thread_id,
                                receipt = receipt.item_id,
                                %error,
                                "a saved decision cannot be decoded"
                    );
                    DecisionRecord::Unreadable { local_id }
                }
            };
            // A damaged row cannot prove it was replaced: its revision is unknown, so a newer snapshot
            // record must not silently drop it. It replaces what the snapshot said for that identity,
            // and the reconciliation reports it instead of losing it.
            let superseded = match facts.get(record.local_id()) {
                Some(existing)
                    if !matches!(existing, DecisionRecord::Unreadable { .. })
                        && !matches!(record, DecisionRecord::Unreadable { .. }) =>
                {
                    existing.revision() > record.revision()
                }
                _ => false,
            };
            if !superseded {
                facts.insert(record.local_id().to_owned(), record);
            }
        }
        Ok(facts.into_values().collect())
    }

    /// One decision fact by its local identity.
    async fn decision_record(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<Option<DecisionRecord>> {
        Ok(self
            .decision_records(thread_id)
            .await?
            .into_iter()
            .find(|record| record.local_id() == local_id))
    }

    /// Whether this record is a child Plan interaction, which is a main-session capability.
    ///
    /// The caller passes the owner it already verified, so this never re-reads (and never has to
    /// tolerate a failure of) the directory association: a failed lookup must not be read as "this is
    /// a main session" and silently drop the Plan exclusion. A storage fault while reading the record
    /// itself is propagated for the same reason.
    pub(super) async fn is_child_plan_record(
        &self,
        owner: &crate::studio::ThreadRecord,
        local_id: &str,
    ) -> Result<bool> {
        if owner.parent_thread_id.is_none() {
            return Ok(false);
        }
        // The record may live only in the durable receipt of a settled decision: a cold Plan decision
        // must be recognised exactly like a resident one, otherwise replaying it could write a host
        // notice.
        let Some(record) = self.decision_record(&owner.id, local_id).await? else {
            return Ok(false);
        };
        // An unreadable record cannot prove it is not a Plan confirmation, so the exclusion fails
        // closed instead of letting a damaged child record look like an ordinary question.
        if matches!(record.identity(), DecisionIdentity::Unreadable) {
            return Err(unreadable_decision(&owner.id, local_id));
        }
        Ok(record.is_plan())
    }

    /// Rejects an operation id that already decided a different interaction of this Thread.
    async fn ensure_operation_not_reused(
        &self,
        thread_id: &str,
        local_id: &str,
        operation_id: &str,
    ) -> Result<()> {
        // Questions and permission requests are both decisions of this Thread, and a settled decision
        // counts exactly like a pending one.
        let mut holder = None;
        for record in self.decision_records(thread_id).await? {
            if record.local_id() == local_id {
                continue;
            }
            // A damaged record makes uniqueness unprovable: refusing the decision is the only answer
            // that cannot silently accept a reused operation identity.
            if matches!(record.identity(), DecisionIdentity::Unreadable) {
                return Err(unreadable_decision(thread_id, record.local_id()));
            }
            if matches!(record.identity(), DecisionIdentity::Recorded(identity) if identity == operation_id)
            {
                holder = Some(record.local_id().to_owned());
                break;
            }
        }
        let Some(other) = holder else {
            return Ok(());
        };
        Err(anyhow::Error::new(
            pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Conflict,
                "This operation id already decided another interaction",
                false,
            )
            .with_reason(
                pl_protocol::studio::StudioErrorReason::StaleInteraction,
                serde_json::json!({
                    "operationId": operation_id,
                    "interactionId": format!("{thread_id}:{other}"),
                }),
            ),
        ))
    }

    /// The operation identity the stored decision of `local_id` was accepted under.
    ///
    /// The receipt of a settled decision survives the snapshot that dropped it, so this answers after
    /// a restart and after the record left every in-memory projection.
    async fn stored_decision_operation_id(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<Option<String>> {
        let Some(record) = self.decision_record(thread_id, local_id).await? else {
            return Ok(None);
        };
        if record.pending() {
            return Ok(None);
        }
        match record.identity() {
            DecisionIdentity::Recorded(identity) => Ok(Some(identity)),
            DecisionIdentity::Legacy => Ok(None),
            // A damaged record must never be answered as "this decision recorded no identity".
            DecisionIdentity::Unreadable => Err(unreadable_decision(thread_id, local_id)),
        }
    }

    /// Every settled decision of this Thread that this runtime accepted, projected like a live record.
    ///
    /// Discovery comes from the durable receipts, so a decision the canonical snapshot already dropped
    /// — exactly what a crash between the commit and the notice leaves behind — is still found after a
    /// restart. Only a decision accepted under an operation identity is returned: those always owed a
    /// main-session notice, while rows written before this capability existed never did, so an
    /// upgrade does not announce old history. A Plan record is excluded here as everywhere else.
    ///
    /// A decision whose saved row cannot be projected is returned separately: its notice cannot be
    /// built, so the caller must publish that as observable state instead of counting it as
    /// reconciled.
    pub(in crate::studio::runtime) async fn settled_decisions(
        &self,
        thread_id: &str,
    ) -> Result<SettledDecisions> {
        let mut settled = SettledDecisions::default();
        for record in self.decision_records(thread_id).await? {
            // Damage is classified before any other exclusion: an unreadable row owes a report even
            // when the record it shadows looked like a pending or a Plan record, so it can never be
            // dropped by a skip that assumes a readable decision.
            let identity = record.identity();
            if matches!(identity, DecisionIdentity::Unreadable) {
                tracing::warn!(
                    thread_id,
                    interaction_id = record.local_id(),
                    "a saved decision has no readable outcome"
                );
                settled.unprojectable.push(record.local_id().to_owned());
                continue;
            }
            if record.pending() || record.is_plan() {
                continue;
            }
            // A decision this runtime accepted recorded its operation identity, so it always owed a
            // notice; rows from before that capability never did and are not announced on upgrade. A
            // cancellation carries no identity in either version, and cancellations are part of what
            // the main session must be told (design/12 §12.2.1), so they are announced as well.
            if matches!(identity, DecisionIdentity::Legacy) && !record.is_cancelled() {
                continue;
            }
            let local_id = record.local_id().to_owned();
            let snapshot = record.into_snapshot(&local_id);
            match crate::thread_assembler::project_thread_interaction(
                thread_id, &local_id, &snapshot,
            ) {
                Ok(Some(interaction)) => settled.deliverable.push(interaction),
                // Nothing to project: the identity is not a product interaction.
                Ok(None) => {}
                // A saved row this runtime cannot project is a decision whose notice cannot be built.
                // It must not block the main session's own turn the way a permanently unprojectable
                // row would, so it is handed back instead of being swallowed.
                Err(error) => {
                    tracing::warn!(
                        thread_id,
                        interaction_id = local_id,
                        %error,
                        "a saved child decision cannot be projected into a notice"
                    );
                    settled.unprojectable.push(local_id);
                }
            }
        }
        Ok(settled)
    }

    /// Requires `host_thread_id` to be a main session the user may access.
    ///
    /// The child interaction projection and the decision entry share this single check, so a child id
    /// can neither decide nor list interactions of its own subtree.
    pub(in crate::studio::runtime) async fn ensure_root_host(
        &self,
        host_thread_id: &str,
    ) -> Result<crate::studio::ThreadRecord> {
        use pl_protocol::studio::{StudioError, StudioErrorCode, StudioErrorReason};
        if host_thread_id.trim().is_empty() {
            return Err(anyhow::Error::new(StudioError::invalid_argument(
                "hostThreadId is required",
            )));
        }
        let host = self.read_owned_thread(host_thread_id).await?;
        if host.parent_thread_id.is_some() {
            return Err(anyhow::Error::new(
                StudioError::new(
                    StudioErrorCode::PermissionDenied,
                    "A child session cannot host interaction decisions",
                    false,
                )
                .with_reason(
                    StudioErrorReason::InteractionNotHosted,
                    serde_json::json!({ "hostThreadId": host.id, "hostIsChild": true }),
                ),
            ));
        }
        Ok(host)
    }

    /// Verifies that `host_thread_id` may act for the interaction's owning session.
    /// Returns the owning Thread's record, which the caller also needs for its own checks.
    async fn ensure_interaction_host(
        &self,
        host_thread_id: &str,
        interaction: &InteractionRequest,
    ) -> Result<crate::studio::ThreadRecord> {
        use pl_protocol::studio::{StudioError, StudioErrorCode, StudioErrorReason};
        let host = self.ensure_root_host(host_thread_id).await?;
        let owner = self.read_owned_thread(&interaction.scope.thread_id).await?;
        if owner.id != host.id && owner.parent_thread_id.as_deref() != Some(host.id.as_str()) {
            return Err(anyhow::Error::new(
                StudioError::new(
                    StudioErrorCode::PermissionDenied,
                    "The interaction does not belong to this session or its direct children",
                    false,
                )
                .with_reason(
                    StudioErrorReason::InteractionNotHosted,
                    serde_json::json!({
                        "hostThreadId": host.id,
                        "interactionThreadId": owner.id,
                    }),
                ),
            ));
        }
        Ok(owner)
    }

    fn interaction_command_reply(
        &self,
        operation_id: String,
        interaction: InteractionRequest,
        changed: bool,
        durable: bool,
    ) -> StudioResolveInteractionResponse {
        let mut receipt = self.command_receipt(
            operation_id,
            changed,
            vec![self.resource_stamp(
                format!("interaction:{}", interaction.interaction_id),
                interaction.revision,
            )],
            pl_protocol::studio::CommandEffectPoint::Immediate,
            durable,
        );
        receipt.requires_identity_observation = true;
        StudioResolveInteractionResponse {
            thread_id: interaction.scope.thread_id.clone(),
            interaction,
            receipt,
        }
    }

    /// Reads the original interaction and decision from the exact committed core receipt.
    ///
    /// The same product projection supplies the original questions/request to callers and the
    /// terminal resolution to the canonical decision boundary, without activating an owner.
    async fn read_durable_interaction_for_resolve(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<Option<InteractionForResolve>> {
        let history = self.store.history(thread_id).await?;
        for kind in ["interaction", "permission"] {
            let Some(receipt) = history
                .latest_fact_receipt(&crate::studio::thread_projection::order::receipt_id(
                    kind, local_id,
                ))
                .await?
            else {
                continue;
            };
            let mut state = pl_core::thread::ThreadSnapshot::default();
            match receipt.kind.as_str() {
                "interaction" => {
                    state
                        .interactions
                        .insert(local_id.to_owned(), serde_json::from_str(&receipt.payload)?);
                }
                "permission" => {
                    state
                        .permissions
                        .insert(local_id.to_owned(), serde_json::from_str(&receipt.payload)?);
                }
                _ => continue,
            }
            let projected =
                crate::thread_assembler::project_thread_interaction(thread_id, local_id, &state)?
                    .context("durable interaction receipt cannot be projected")?;
            return Ok(Some(InteractionForResolve {
                interaction: projected,
                durable: true,
            }));
        }
        Ok(None)
    }

    /// 内存优先读取交互：pending 交互必须来自驻留 actor 的权威快照；
    /// 冷 checkpoint 也已不再保留时，读取 durable 原始交互与决定供终态重放核对。
    pub(in crate::studio::runtime) async fn read_interaction_for_resolve(
        &self,
        interaction_id: &str,
    ) -> Result<Option<InteractionForResolve>> {
        if let Some(interaction) = self.threads.read_product_interaction(interaction_id)? {
            return Ok(Some(InteractionForResolve {
                interaction,
                durable: false,
            }));
        }
        let (thread_id, local_id) =
            crate::thread_assembler::decode_interaction_key(interaction_id)?;
        let thread = self.read_protocol_thread(thread_id).await?;
        // Reading a pending interaction is a projection: it never imports or deletes storage. A
        // legacy checkpoint that still needs migration appears only after its owner's own writer
        // prepared it (design/17).
        if let Some(checkpoint) =
            crate::studio::thread_factory::recovery::load_checkpoint_read_only(&self.store, &thread)
                .await?
            && let Some(interaction) = crate::thread_assembler::project_thread_interaction(
                thread_id,
                local_id,
                &checkpoint.state,
            )?
        {
            return Ok(Some(InteractionForResolve {
                interaction,
                durable: false,
            }));
        }
        self.read_durable_interaction_for_resolve(thread_id, local_id)
            .await
    }
}

/// How long a child decision may take to reach its own durable commitment.
const CHILD_DECISION_WAIT: std::time::Duration = std::time::Duration::from_secs(5);

/// Poll interval while waiting for that commitment.
const CHILD_DECISION_POLL: std::time::Duration = std::time::Duration::from_millis(10);

/// The settled decisions of one child Thread that still owe the main session a notice.
///
/// The two halves are what a reconciliation must do differently: deliver the ones that project, and
/// publish the ones that cannot be projected instead of counting them as reconciled.
#[derive(Default)]
pub(in crate::studio::runtime) struct SettledDecisions {
    /// Every settled decision that projects into a deliverable notice.
    pub deliverable: Vec<InteractionRequest>,
    /// Local identities whose saved decision cannot be projected, so no notice can be built for them.
    pub unprojectable: Vec<String>,
}

/// One decision fact of a Thread, from the single read-only source that can still prove it.
///
/// A settled decision leaves the canonical snapshot, so a caller that only read live state would see
/// no record at all. Carrying the decoded core record keeps every caller on the same facts instead of
/// re-deriving them per path. A saved row that cannot be decoded is kept too, with the identity its
/// receipt key still proves: a corrupted decision is not a missing one, and callers must be able to
/// fail closed on it and report it.
enum DecisionRecord {
    Question(pl_core::thread::interactions::InteractionRecord),
    Approval(pl_core::thread::permissions::PermissionRecord),
    /// A saved decision whose stored payload cannot be decoded; only its identity is known.
    Unreadable {
        local_id: String,
    },
}

/// What a saved decision can prove about the operation that produced it.
enum DecisionIdentity {
    /// The decision recorded the operation identity it was accepted under.
    Recorded(String),
    /// The decision predates operation identities and never recorded one.
    Legacy,
    /// The decision exists but its stored facts cannot be read, so nothing can be proven about it.
    Unreadable,
}

impl DecisionRecord {
    fn local_id(&self) -> &str {
        match self {
            Self::Question(record) => &record.request.id,
            Self::Approval(record) => &record.id,
            Self::Unreadable { local_id } => local_id,
        }
    }

    fn revision(&self) -> u64 {
        match self {
            Self::Question(record) => record.revision,
            Self::Approval(record) => record.revision,
            // An undecodable row cannot prove a revision, so it never supersedes a decodable one.
            Self::Unreadable { .. } => 0,
        }
    }

    fn pending(&self) -> bool {
        match self {
            Self::Question(record) => {
                matches!(
                    record.state,
                    pl_core::thread::interactions::InteractionState::Pending
                )
            }
            Self::Approval(record) => {
                matches!(
                    record.state,
                    pl_core::thread::permissions::PermissionState::Pending
                )
            }
            Self::Unreadable { .. } => false,
        }
    }

    fn identity(&self) -> DecisionIdentity {
        match self {
            Self::Question(record) => decided_operation_identity(&record.state),
            Self::Approval(record) => permission_operation_identity(record.response.as_ref()),
            Self::Unreadable { .. } => DecisionIdentity::Unreadable,
        }
    }

    /// Whether this decision was cancelled rather than decided.
    fn is_cancelled(&self) -> bool {
        match self {
            Self::Question(record) => matches!(
                record.state,
                pl_core::thread::interactions::InteractionState::Cancelled
            ),
            Self::Approval(record) => matches!(
                record.state,
                pl_core::thread::permissions::PermissionState::Cancelled
            ),
            Self::Unreadable { .. } => false,
        }
    }

    /// Whether this is a Plan confirmation, a main-session-only capability.
    fn is_plan(&self) -> bool {
        match self {
            Self::Question(record) => {
                record.request.payload.format() == crate::plan_tool::PLAN_CONFIRMATION_FORMAT
            }
            Self::Approval(_) | Self::Unreadable { .. } => false,
        }
    }

    /// This record as the single-entry snapshot the shared projection expects.
    fn into_snapshot(self, local_id: &str) -> pl_core::thread::ThreadSnapshot {
        let mut snapshot = pl_core::thread::ThreadSnapshot::default();
        match self {
            Self::Question(record) => {
                snapshot.interactions.insert(local_id.to_owned(), record);
            }
            Self::Approval(record) => {
                snapshot.permissions.insert(local_id.to_owned(), record);
            }
            Self::Unreadable { .. } => {}
        }
        snapshot
    }
}

/// Decodes one durable decision receipt and proves its key matches the payload's own identity.
fn decode_decision_receipt(
    receipt: &crate::studio::storage::history::DecisionReceipt,
) -> anyhow::Result<DecisionRecord> {
    let record = match receipt.kind.as_str() {
        "interaction" => DecisionRecord::Question(serde_json::from_str(&receipt.payload)?),
        "permission" => DecisionRecord::Approval(serde_json::from_str(&receipt.payload)?),
        other => anyhow::bail!("unsupported durable decision receipt kind {other}"),
    };
    // The receipt key is a function of the kind and the local identity: one whose payload names a
    // different record would let an identity answer for another one.
    anyhow::ensure!(
        receipt.item_id
            == crate::studio::thread_projection::order::receipt_id(
                receipt.kind.as_str(),
                record.local_id()
            ),
        "durable decision receipt identity conflicts with its payload"
    );
    Ok(record)
}

/// The local identity a receipt key encodes: `receipt_id(kind, local_id)` is `"<kind>:<len>:<id>"`.
fn decision_receipt_local_id(item_id: &str) -> String {
    let Some((_, rest)) = item_id.split_once(':') else {
        return item_id.to_owned();
    };
    let Some((length, local)) = rest.split_once(':') else {
        return item_id.to_owned();
    };
    match length.parse::<usize>() {
        Ok(length) if length == local.len() => local.to_owned(),
        _ => item_id.to_owned(),
    }
}

/// Adds the decision records of one canonical snapshot, keeping the newest revision per identity.
fn collect_decision_records(
    snapshot: &pl_core::thread::ThreadSnapshot,
    facts: &mut std::collections::BTreeMap<String, DecisionRecord>,
) {
    for (id, record) in snapshot.interactions.iter() {
        facts.insert(id.clone(), DecisionRecord::Question(record.clone()));
    }
    for (id, record) in snapshot.permissions.iter() {
        facts.insert(id.clone(), DecisionRecord::Approval(record.clone()));
    }
}

/// The retryable answer for "the decision is accepted but not saved yet".
pub(super) fn child_decision_not_saved(interaction: &InteractionRequest) -> anyhow::Error {
    anyhow::Error::new(
        pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Busy,
            "The decision is accepted but not saved yet; retry to deliver it to the main session",
            true,
        )
        .with_reason(
            pl_protocol::studio::StudioErrorReason::InteractionNotHosted,
            serde_json::json!({
                "interactionId": interaction.interaction_id,
                "decisionSaved": false,
            }),
        ),
    )
}

/// The refusal for a command that needs a saved decision whose stored facts cannot be read.
///
/// A damaged record makes operation uniqueness, terminal replay and hosting unprovable, so the
/// command fails closed with a typed rejection instead of acting as if the record were absent or were
/// merely old. It is deliberately not the "legacy" answer: old rows are complete, they simply predate
/// the identity.
fn unreadable_decision(thread_id: &str, local_id: &str) -> anyhow::Error {
    anyhow::Error::new(
        pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Protocol,
            "A saved decision of this session cannot be read; reload before deciding",
            false,
        )
        .with_reason(
            pl_protocol::studio::StudioErrorReason::StaleInteraction,
            serde_json::json!({
                "threadId": thread_id,
                "interactionId": local_id,
            }),
        ),
    )
}

/// The refusal for replaying a stored decision that recorded no operation identity.
///
/// Rows written before the identity existed are still valid decisions; they simply cannot prove which
/// operation produced them, so no caller may be answered with its own identity as the accepted one.
fn decision_identity_unrecorded(interaction: &InteractionRequest) -> anyhow::Error {
    anyhow::Error::new(
        pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Conflict,
            "The stored decision predates operation identities and cannot be replayed under this one",
            false,
        )
        .with_reason(
            pl_protocol::studio::StudioErrorReason::StaleInteraction,
            serde_json::json!({
                "interactionId": interaction.interaction_id,
                "currentRevision": interaction.revision,
                "operationIdentityRecorded": false,
            }),
        ),
    )
}

/// The legacy response document a decision family used before operation identities existed.
///
/// A document only counts as legacy when it really is that shape: a complete old response. Anything
/// else in the same field is a damaged record, not an old one.
#[derive(Clone, Copy)]
enum DecisionFamily {
    Question,
    Approval,
}

/// What the stored response of a question proves about the operation that produced it.
///
/// Three states are kept apart on purpose: a row that really predates operation identities must stay
/// silent, a row that is present but unreadable must be reported, and neither may be treated as the
/// other.
fn decided_operation_identity(
    state: &pl_core::thread::interactions::InteractionState,
) -> DecisionIdentity {
    let pl_core::thread::interactions::InteractionState::Resolved(response) = state else {
        // Pending and cancelled records never carry a decision identity.
        return DecisionIdentity::Legacy;
    };
    operation_identity_of(response.payload.content(), DecisionFamily::Question)
}

/// What the stored response of an approval proves about the operation that produced it.
///
/// An approval is a decision of its Thread exactly like a question, so its operation identity takes
/// part in the same uniqueness check and the same three-state distinction.
fn permission_operation_identity(
    response: Option<&pl_core::context::OpaquePayload>,
) -> DecisionIdentity {
    let Some(response) = response else {
        // A decision stored without any response payload recorded no identity; it is not corrupt.
        return DecisionIdentity::Legacy;
    };
    operation_identity_of(response.content(), DecisionFamily::Approval)
}

/// Reads the operation identity a frozen decision payload records.
///
/// Only a document that passes the family's legacy response schema and really has no identity field is
/// [`DecisionIdentity::Legacy`]. Array/scalar documents, objects that are not that response, missing
/// required fields, and a blank or non-string `operationId` are all [`DecisionIdentity::Unreadable`]:
/// they are present but prove nothing, and answering "no identity recorded" would silently drop them.
fn operation_identity_of(content: &str, family: DecisionFamily) -> DecisionIdentity {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(content) else {
        return DecisionIdentity::Unreadable;
    };
    match value.get("operationId") {
        // A blank identity is not an identity: the command layer rejects one exactly like this.
        Some(serde_json::Value::String(identity)) if identity.trim().is_empty() => {
            DecisionIdentity::Unreadable
        }
        Some(serde_json::Value::String(identity)) => DecisionIdentity::Recorded(identity.clone()),
        // The field exists but is not a readable identity: the row is damaged, not legacy.
        Some(_) => DecisionIdentity::Unreadable,
        None if is_complete_legacy_response(&value, family) => DecisionIdentity::Legacy,
        None => DecisionIdentity::Unreadable,
    }
}

/// Whether `value` really is the complete response document of the given family.
fn is_complete_legacy_response(value: &serde_json::Value, family: DecisionFamily) -> bool {
    match family {
        DecisionFamily::Question => {
            serde_json::from_value::<pl_protocol::UserInputResolution>(value.clone()).is_ok()
        }
        DecisionFamily::Approval => {
            serde_json::from_value::<pl_protocol::ToolApprovalResolutionPayload>(value.clone())
                .is_ok()
        }
    }
}

/// Maps a product interaction failure onto the typed Studio error the transports expose.
///
/// Every rejection a caller can provoke becomes a 4xx-worthy typed reason instead of a redacted
/// internal failure: a missing owner, a stale record, a wrong kind and a child Plan record are
/// distinct, actionable outcomes.
fn interaction_error(error: crate::thread_assembler::StudioInteractionError) -> anyhow::Error {
    use crate::thread_assembler::StudioInteractionError as Source;
    use pl_protocol::studio::{StudioError, StudioErrorCode, StudioErrorReason};
    match error {
        Source::Identity => anyhow::Error::new(
            StudioError::new(
                StudioErrorCode::Conflict,
                "The interaction identity, revision or kind does not match its record",
                false,
            )
            .with_reason(StudioErrorReason::StaleInteraction, serde_json::json!({})),
        ),
        Source::Plan(crate::thread_assembler::PlanInteractionError::NotRoot) => anyhow::Error::new(
            StudioError::new(
                StudioErrorCode::PermissionDenied,
                "A child Plan confirmation stays a diagnostic and is not decidable",
                false,
            )
            .with_reason(
                StudioErrorReason::InteractionNotHosted,
                serde_json::json!({}),
            ),
        ),
        other => anyhow::Error::new(other),
    }
}
