//! Persisted provenance and local capabilities for auxiliary inbound notices.
//! Stored identity never grants sending authority; the existing ledger owns sends.
mod admission;
mod authority;
mod operation;
mod prune;
mod settlement;
mod transaction;

pub(super) use admission::{FreshNotice, freeze_admission_in, insert_frozen_notice_in};
pub(super) use operation::{apply_message_progress, validate_stored_notice_record};
pub(super) use settlement::finish_notice_pause_in;

use super::{
    BotStateStore, INBOUND_CLAIM_TTL_SECONDS, SendRecord, inbound_identity, statement, storage,
    strict_text, strict_watermark,
};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::send::SendSource;
use crate::studio::audience_start::AudienceStartReceipt;
use pl_protocol::BotAuthorizationRef;
use pl_protocol::studio::BotDiagnostic;
use sea_orm::ConnectionTrait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum ReplyBinding {
    /// An explicit no-row expectation, never a wildcard for the current binding.
    Absent,
    Creating,
    Bound,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum NoticeAuthorization {
    NoHead {},
    Bound { start: Box<AudienceStartReceipt> },
}

/// Immutable provenance, not a deserializable sending capability.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct InboundNoticeIdentity {
    /// Version 1 is required; admission and record verification validate it without defaulting.
    version: u32,
    source: SendSource,
    binding: ReplyBinding,
    authorization: NoticeAuthorization,
}

impl InboundNoticeIdentity {
    pub(in crate::bots) fn version(&self) -> u32 {
        self.version
    }

    pub(in crate::bots) fn source(&self) -> &SendSource {
        &self.source
    }

    pub(in crate::bots) fn binding(&self) -> ReplyBinding {
        self.binding
    }

    pub(in crate::bots) fn authorization(&self) -> &NoticeAuthorization {
        &self.authorization
    }
}

/// Short-lived proof created only after checking the original stored notice and current fence.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct InboundNoticeReady {
    identity: InboundNoticeIdentity,
    worker_id: String,
    control: NoticeControl,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots::storage) enum NoticeControl {
    NoHead,
    Bound { reference: BotAuthorizationRef },
}

impl InboundNoticeReady {
    pub(in crate::bots) fn identity(&self) -> &InboundNoticeIdentity {
        &self.identity
    }

    pub(in crate::bots) fn source(&self) -> &SendSource {
        self.identity.source()
    }
}

/// The observed control is evidence of a pause, not a fixed CAS for the later finisher.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct InboundNoticePaused {
    identity: InboundNoticeIdentity,
    worker_id: String,
    observed_control: BotAuthorizationRef,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::bots) enum InboundNoticeUnavailable {
    NoFrozenNotice,
    LostClaim,
    OriginalScopeClosed,
    SupersededAttempt,
}

pub(in crate::bots) enum InboundNoticeRead {
    Receipt(SendRecord),
    Ready {
        record: SendRecord,
        proof: InboundNoticeReady,
    },
    Paused(InboundNoticePaused),
    Unavailable(InboundNoticeUnavailable),
}

/// Local responsibility for one exact attempt; it cannot expose or start a request.
#[derive(Debug)]
pub(in crate::bots) struct InboundNoticeRetirement {
    proof: InboundNoticeReady,
    record: SendRecord,
    request_started: bool,
    consumed: bool,
}

/// Only a successfully committed begin may wrap a retirement capability for request startup.
#[derive(Debug)]
pub(in crate::bots) struct ConfirmedInboundNoticeAttempt {
    retirement: InboundNoticeRetirement,
}

impl ConfirmedInboundNoticeAttempt {
    pub(in crate::bots) fn record(&self) -> &SendRecord {
        &self.retirement.record
    }

    pub(in crate::bots) fn mark_request_started(&mut self) {
        self.retirement.request_started = true;
    }

    /// Irreversibly relinquish startup capability and retain only local retirement responsibility.
    pub(in crate::bots) fn into_retirement(self) -> InboundNoticeRetirement {
        self.retirement
    }
}

pub(in crate::bots) enum InboundNoticeAdmission {
    Confirmed(ConfirmedInboundNoticeAttempt),
    Unconfirmed {
        retirement: InboundNoticeRetirement,
        error: FeishuError,
    },
    Receipt(SendRecord),
    Paused(InboundNoticePaused),
    Unavailable(InboundNoticeUnavailable),
}

pub(in crate::bots) enum InboundNoticeStartCheck {
    Ready,
    Paused(InboundNoticePaused),
    Unavailable(InboundNoticeUnavailable),
}

pub(in crate::bots) enum InboundNoticeSettlement {
    Applied(SendRecord),
    AlreadySettled(SendRecord),
    Superseded,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) enum InboundNoticeProgress {
    Sent { message_id: String },
    Rejected { diagnostic: BotDiagnostic },
    Unknown { diagnostic: Option<BotDiagnostic> },
}

#[derive(Debug, Clone)]
pub(in crate::bots) struct InboundReply {
    pub source: SendSource,
    pub worker_id: String,
    pub watch_input: String,
    pub admitted_binding_revision: u64,
    pub binding: ReplyBinding,
}

impl InboundReply {
    pub(in crate::bots) fn freeze_bytes(&self, copies: usize) -> Result<usize, FeishuError> {
        let source = serde_json::to_vec(&self.source)
            .map_err(|_| crate::bots::occupancy::freeze_budget_error())?;
        crate::bots::occupancy::counted_extra_bytes(
            0,
            [
                (source.len(), copies),
                (self.worker_id.len(), copies),
                (self.watch_input.len(), copies),
            ],
        )
    }
}

impl BotStateStore {
    /// Read-only check for an existing receipt. New send claims/stage intents
    /// call the same predicate inside their actual write transaction instead.
    pub(in crate::bots) async fn verify_reply(
        &self,
        reply: &InboundReply,
    ) -> Result<(), FeishuError> {
        check(self.db().await?, reply).await
    }
}

pub(super) async fn check<C: ConnectionTrait>(
    db: &C,
    reply: &InboundReply,
) -> Result<(), FeishuError> {
    let s = &reply.source;
    let original = format!("bot:{}:{}:{}", s.bot_id, s.chat_id, s.message_id);
    if reply.worker_id.is_empty() || reply.watch_input.is_empty() || s.original_input_id != original
    {
        return Err(denied());
    }
    let claim = db.query_one_raw(statement(
        "SELECT 1 AS held FROM inbound_work WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
         AND app_id=? AND project_id=? AND open_id=? AND chat_kind=? AND creation_id=? AND binding_revision=?
         AND status='claimed' AND claimed_by=? AND claimed_at>?
         AND (watch_input=? OR (watch_input='' AND ?=?))",
        vec![inbound_identity(&s.bot_id,&s.chat_id,&s.message_id).into(),s.bot_id.clone().into(),s.chat_id.clone().into(),s.message_id.clone().into(),
             s.app_id.clone().into(),s.project_id.clone().into(),s.open_id.clone().into(),s.chat_kind.clone().into(),s.creation_id.clone().into(),
             i64::try_from(reply.admitted_binding_revision).map_err(|_| denied())?.into(),reply.worker_id.clone().into(),
             crate::studio::unix_seconds().saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into(),reply.watch_input.clone().into(),reply.watch_input.clone().into(),original.into()],
    )).await.map_err(storage)?;
    if claim.is_none() {
        return Err(denied());
    }
    let row = db.query_one_raw(statement(
        "SELECT chat_id,thread_id,status,creation_id,project_id,revision,generation FROM thread_bindings WHERE chat_id=?",
        vec![s.chat_id.clone().into()],
    )).await.map_err(storage)?;
    let Some(row) = row else {
        return if matches!(reply.binding, ReplyBinding::Absent)
            && s.creation_id.is_empty()
            && s.thread_id.is_empty()
            && s.binding_revision == 0
            && reply.admitted_binding_revision == 0
        {
            Ok(())
        } else {
            Err(denied())
        };
    };
    // Bad columns/unknown state are not absence. Decode the existing row even
    // when the caller expected no row, preserving corruption versus revocation.
    let chat = strict_text(&row, "chat_id")?;
    let thread = strict_text(&row, "thread_id")?;
    let status = strict_text(&row, "status")?;
    let creation = strict_text(&row, "creation_id")?;
    let project = strict_text(&row, "project_id")?;
    let revision = strict_watermark(&row, "revision")?;
    let _generation = strict_watermark(&row, "generation")?;
    let state_matches = match reply.binding {
        ReplyBinding::Absent => false,
        ReplyBinding::Creating => {
            status == "creating" && thread.is_empty() && s.thread_id.is_empty()
        }
        ReplyBinding::Bound => status == "bound" && !thread.is_empty() && thread == s.thread_id,
    };
    if !state_matches
        || chat != s.chat_id
        || creation.is_empty()
        || creation != s.creation_id
        || project != s.project_id
        || revision != s.binding_revision
    {
        return Err(denied());
    }
    Ok(())
}

pub(in crate::bots) fn denied() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Permission,
        "original inbound reply claim or binding is no longer valid",
        false,
        None,
    )
}

#[cfg(test)]
mod tests {
    //! Real SQLite admission/attempt preservation. Direct phase edits below are fault injection,
    //! not evidence that runtime admission permits a control change between begin and first poll.
    use super::*;
    use crate::bots::config::{
        BOT_CONFIG_SCHEMA_VERSION, BotConfigFile, BotPlatformConfig, FeishuBotConfig,
    };
    use crate::bots::inbound::InboundAttachment;
    use crate::bots::occupancy::{OCCUPANCY_TEXT_BYTES, OccupancyTasks};
    use crate::bots::send::{
        SendIdentity, inbound_notice_operation_id, verify_inbound_notice_record,
    };
    use crate::bots::storage::{
        BindingOperation, FirstStart, FrozenInbound, InboundAdmit, InboundClaim, MarkOutcome,
        MessageStage, SendRecordStatus, WorkFinish, audience,
    };
    use pl_protocol::studio::BotAuthorizationPhase;

    const BOT: &str = "noticebot";
    const CHAT: &str = "notice-chat";
    const APP: &str = "notice-app";
    const PROJECT: &str = "notice-project";
    const THREAD: &str = "notice-thread";

    fn inbound(message: &str) -> FrozenInbound {
        FrozenInbound {
            bot_id: BOT.into(),
            chat_id: CHAT.into(),
            message_id: message.into(),
            content_hash: format!("hash-{message}"),
            text: String::new(),
            attachments: vec![InboundAttachment::Unsupported {
                message_type: "sticker".into(),
            }],
            open_id: String::new(),
            chat_kind: "group".into(),
            app_id: APP.into(),
            project_id: PROJECT.into(),
            creation_id: String::new(),
            binding_revision: 0,
            watch_input: String::new(),
        }
    }

    fn config() -> BotConfigFile {
        BotConfigFile {
            schema_version: BOT_CONFIG_SCHEMA_VERSION,
            id: BOT.into(),
            name: "Notice".into(),
            project_id: PROJECT.into(),
            platform: BotPlatformConfig::FeishuChina(FeishuBotConfig {
                app_id: APP.into(),
                trusted_open_ids: Default::default(),
                trusted_chat_ids: [CHAT.into()].into_iter().collect(),
            }),
            enabled: true,
            tools_enabled: false,
            model_route: None,
            config_revision: 1,
            selected_ref: None,
            created_at: 1,
            updated_at: 1,
        }
    }

    async fn fresh(store: &BotStateStore, input: &FrozenInbound) -> anyhow::Result<()> {
        let tasks = OccupancyTasks::new();
        let mut budget = tasks.text_budget(0)?;
        assert!(matches!(
            store.admit_inbound(input.clone(), &mut budget).await?,
            InboundAdmit::Fresh(_)
        ));
        Ok(())
    }

    async fn ready(
        store: &BotStateStore,
        input: &FrozenInbound,
        worker: &str,
    ) -> anyhow::Result<InboundNoticeReady> {
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, &input.message_id, worker)
                .await?,
            InboundClaim::Claimed
        );
        let InboundNoticeRead::Ready { record, proof } =
            store.read_inbound_notice(input, worker).await?
        else {
            anyhow::bail!("the original live claim should be ready")
        };
        verify_inbound_notice_record(&record, proof.identity())?;
        Ok(proof)
    }

    async fn begin(
        store: &BotStateStore,
        proof: &InboundNoticeReady,
    ) -> anyhow::Result<ConfirmedInboundNoticeAttempt> {
        let InboundNoticeAdmission::Confirmed(attempt) = store.begin_inbound_notice(proof).await?
        else {
            anyhow::bail!("a committed new attempt must be confirmed")
        };
        Ok(attempt)
    }

    async fn record(store: &BotStateStore, message: &str) -> anyhow::Result<SendRecord> {
        Ok(store
            .load_send(&inbound_notice_operation_id(BOT, CHAT, message)?)
            .await?
            .unwrap())
    }

    async fn count(store: &BotStateStore, table: &str) -> anyhow::Result<i64> {
        let row = store
            .db()
            .await?
            .query_one_raw(statement(
                &format!("SELECT count(*) AS n FROM {table}"),
                vec![],
            ))
            .await?
            .unwrap();
        Ok(super::super::stored_i64(&row, "n")?)
    }

    async fn bound(
        store: &BotStateStore,
        message: &str,
        active: bool,
    ) -> anyhow::Result<FrozenInbound> {
        use crate::bots::storage::target::{TargetClaim, TargetKind};
        let creation = format!("botthread:{BOT}:{CHAT}:initial");
        store.binding_for_chat(CHAT, BOT, PROJECT).await?;
        let claim = TargetClaim::from_operation(
            BOT,
            APP,
            PROJECT,
            CHAT,
            &creation,
            "initial",
            TargetKind::Group,
        );
        let operation = BindingOperation {
            operation_id: "initial".into(),
            bot_id: BOT.into(),
            chat_id: CHAT.into(),
            content_hash: "binding-hash".into(),
            expected_revision: 0,
            creation_id: creation.clone(),
            thread_id: None,
            target: claim.freeze(1),
        };
        store
            .begin_binding_operation(CHAT, 0, PROJECT, &operation)
            .await?;
        store
            .bind_thread(
                CHAT,
                THREAD,
                &creation,
                PROJECT,
                Some(&FirstStart {
                    bot_id: BOT.into(),
                    app_id: APP.into(),
                    operation_id: "initial".into(),
                }),
            )
            .await?;
        let head = audience::head(store.db().await?, CHAT).await?.unwrap();
        if active {
            let saved = AudienceStartReceipt {
                version: 1,
                intent: head.intent.clone(),
                extension_revision: 1,
                sequence: 7,
                excluded_turn_id: Some("already-started".into()),
            };
            assert!(store.activate_sync(&saved).await?.changed);
        }
        let mut input = inbound(message);
        input.creation_id = creation;
        input.binding_revision = head.intent.binding_revision;
        Ok(input)
    }

    async fn phase_fault(
        store: &BotStateStore,
        phase: BotAuthorizationPhase,
    ) -> anyhow::Result<()> {
        let db = store.db().await?;
        let mut head = audience::head(db, CHAT).await?.unwrap();
        head.phase = phase;
        head.revision += 1;
        head.closed = if phase == BotAuthorizationPhase::Closed {
            Some((
                pl_protocol::BotAudienceCloseReason::LocalClose,
                crate::studio::unix_seconds(),
            ))
        } else {
            None
        };
        let label = match phase {
            BotAuthorizationPhase::Active => "active",
            BotAuthorizationPhase::Paused => "paused",
            BotAuthorizationPhase::Closed => "closed",
            BotAuthorizationPhase::PendingStart => "pending",
        };
        db.execute_raw(statement("UPDATE bot_authorizations SET phase=?,control_revision=?,state_json=? WHERE chat_id=? AND generation=?",
            vec![label.into(),i64::try_from(head.revision)?.into(),serde_json::to_string(&head)?.into(),CHAT.into(),i64::try_from(head.intent.authorization.generation)?.into()])).await?;
        Ok(())
    }

    #[tokio::test]
    async fn notice_admission_is_atomic_budgeted_and_duplicates_never_backfill()
    -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let store = BotStateStore::new(directory.path().join("notice.sqlite"));
        let tasks = OccupancyTasks::new();
        let all = tasks.text_budget(OCCUPANCY_TEXT_BYTES)?;
        let mut budget = tasks.text_budget(0)?;
        let input = inbound("atomic");
        assert!(
            store
                .admit_inbound(input.clone(), &mut budget)
                .await
                .is_err()
        );
        for table in ["inbound_identities", "inbound_work", "send_operations"] {
            assert_eq!(count(&store, table).await?, 0);
        }
        drop(all);
        store.db().await?.execute_unprepared("CREATE TRIGGER fail_notice_admit BEFORE INSERT ON send_operations BEGIN SELECT RAISE(ABORT,'controlled notice insert failure'); END").await?;
        assert!(
            store
                .admit_inbound(input.clone(), &mut budget)
                .await
                .is_err()
        );
        for table in ["inbound_identities", "inbound_work", "send_operations"] {
            assert_eq!(count(&store, table).await?, 0);
        }
        store
            .db()
            .await?
            .execute_unprepared("DROP TRIGGER fail_notice_admit")
            .await?;
        fresh(&store, &input).await?;
        let before = record(&store, "atomic").await?;
        assert_eq!(operation::counter(&before)?, 0);
        assert!(
            matches!(&before.identity,SendIdentity::InboundNotice { identity,.. } if matches!(identity.authorization(),NoticeAuthorization::NoHead {}))
        );
        assert!(store.claim_send(&before).await.is_err());
        assert!(store.save_send(&before).await.is_err());
        let mut disabled = config();
        disabled.enabled = false;
        assert!(store.prune_inbound_notice_page(&disabled, None).await?.0);
        assert!(!store.prune_inbound_notice_page(&config(), None).await?.0);
        assert!(matches!(
            store.admit_inbound(input.clone(), &mut budget).await?,
            InboundAdmit::DuplicateCompleted
        ));
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, "atomic", "next-worker")
                .await?,
            InboundClaim::NeedsAttention
        );
        assert_eq!(record(&store, "atomic").await?.segments, before.segments);
        assert_eq!(count(&store, "send_operations").await?, 1);

        // More than one page of no-head obligations must be sealed before regrant; keyset
        // progress is the original operation, not a status that this sweep changes itself.
        for index in 0..33 {
            fresh(&store, &inbound(&format!("page-{index:02}"))).await?;
        }
        let (changed, next) = store.prune_inbound_notice_page(&disabled, None).await?;
        assert!(changed && next.is_some());
        let (changed, next) = store.prune_inbound_notice_page(&disabled, next.as_deref()).await?;
        assert!(changed && next.is_none());
        assert!(!store.prune_inbound_notice_page(&config(), None).await?.0);
        assert_eq!(count(&store, "send_operations").await?, 34);

        // PendingStart has no Saved proof: the original admission is terminal and a later
        // activation/duplicate cannot turn it into a newly authorized notice.
        let other = tempfile::tempdir()?;
        let store = BotStateStore::new(other.path().join("pending.sqlite"));
        let input = bound(&store, "no-saved", false).await?;
        fresh(&store, &input).await?;
        assert_eq!(count(&store, "send_operations").await?, 0);
        let head = audience::head(store.db().await?, CHAT).await?.unwrap();
        store
            .activate_sync(&AudienceStartReceipt {
                version: 1,
                intent: head.intent,
                extension_revision: 1,
                sequence: 8,
                excluded_turn_id: None,
            })
            .await?;
        assert!(matches!(
            store.admit_inbound(input, &mut budget).await?,
            InboundAdmit::DuplicateCompleted
        ));
        assert_eq!(count(&store, "send_operations").await?, 0);
        Ok(())
    }

    #[tokio::test]
    async fn notice_attempts_retire_exactly_and_started_results_survive_sealing()
    -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let store = BotStateStore::new(directory.path().join("attempt.sqlite"));
        let input = inbound("attempt");
        fresh(&store, &input).await?;
        let proof = ready(&store, &input, "worker").await?;
        let first = begin(&store, &proof).await?;
        let uuid = first.record().segments[0].uuid.clone();
        assert_eq!(operation::counter(first.record())?, 1);
        assert!(matches!(
            store.read_inbound_notice(&input, "worker").await?,
            InboundNoticeRead::Receipt(_)
        ));
        assert!(matches!(
            store.begin_inbound_notice(&proof).await?,
            InboundNoticeAdmission::Receipt(_)
        ));
        let cold = BotStateStore::new(directory.path().join("attempt.sqlite"));
        cold.db().await?;
        assert!(matches!(
            cold.read_inbound_notice(&input, "worker").await?,
            InboundNoticeRead::Receipt(_)
        ));
        let mut retired = first.into_retirement();
        assert!(matches!(
            store.retire_inbound_notice(&mut retired).await?,
            InboundNoticeSettlement::Applied(_)
        ));
        store
            .db()
            .await?
            .execute_unprepared("UPDATE inbound_work SET claimed_at=0")
            .await?;
        assert!(matches!(
            store.retire_inbound_notice(&mut retired).await?,
            InboundNoticeSettlement::AlreadySettled(_)
        ));
        store
            .db()
            .await?
            .execute_raw(statement(
                "UPDATE inbound_work SET claimed_at=?",
                vec![crate::studio::unix_seconds().into()],
            ))
            .await?;
        let mut second = begin(&store, &proof).await?;
        assert_eq!(operation::counter(second.record())?, 2);
        assert_eq!(second.record().segments[0].uuid, uuid);
        assert!(matches!(
            store.retire_inbound_notice(&mut retired).await?,
            InboundNoticeSettlement::Superseded
        ));
        assert!(matches!(
            store.verify_inbound_notice_start(&second).await?,
            InboundNoticeStartCheck::Ready
        ));
        second.mark_request_started();
        let before = record(&store, "attempt").await?;
        assert!(
            store
                .settle_inbound_notice(
                    &mut second,
                    &InboundNoticeProgress::Sent {
                        message_id: " \t\n".into()
                    }
                )
                .await
                .is_err()
        );
        assert_eq!(record(&store, "attempt").await?.segments, before.segments);
        assert!(matches!(
            store
                .settle_inbound_notice(
                    &mut second,
                    &InboundNoticeProgress::Unknown { diagnostic: None }
                )
                .await?,
            InboundNoticeSettlement::Applied(_)
        ));
        let mut disabled = config();
        disabled.enabled = false;
        store.prune_inbound_notice_page(&disabled, None).await?;
        let sent = InboundNoticeProgress::Sent {
            message_id: "  om_notice  ".into(),
        };
        assert!(matches!(
            store.settle_inbound_notice(&mut second, &sent).await?,
            InboundNoticeSettlement::Applied(_)
        ));
        let accepted = record(&store, "attempt").await?;
        assert_eq!(accepted.status, SendRecordStatus::Succeeded);
        assert_eq!(
            accepted.platform_message_ids,
            vec!["  om_notice  ".to_string()]
        );
        assert_eq!(accepted.segments[0].upload, None);
        assert!(matches!(
            store.settle_inbound_notice(&mut second, &sent).await?,
            InboundNoticeSettlement::AlreadySettled(_)
        ));
        assert!(matches!(
            store
                .settle_inbound_notice(
                    &mut second,
                    &InboundNoticeProgress::Unknown { diagnostic: None }
                )
                .await?,
            InboundNoticeSettlement::AlreadySettled(_)
        ));
        assert!(
            store
                .settle_inbound_notice(
                    &mut second,
                    &InboundNoticeProgress::Rejected {
                        diagnostic: BotDiagnostic {
                            code: "rejected".into(),
                            message: "different terminal result".into(),
                            retryable: false,
                            platform_code: None,
                            guidance: None
                        }
                    }
                )
                .await
                .is_err()
        );
        assert_eq!(record(&store, "attempt").await?.segments, accepted.segments);

        let rejected_input = inbound("rejected");
        fresh(&store, &rejected_input).await?;
        let rejected_proof = ready(&store, &rejected_input, "rejected-worker").await?;
        let mut rejected_attempt = begin(&store, &rejected_proof).await?;
        rejected_attempt.mark_request_started();
        let diagnostic = BotDiagnostic {
            code: "platformRejected".into(), message: "original rejection".into(),
            retryable: false, platform_code: Some(400), guidance: None,
        };
        let rejected_progress = InboundNoticeProgress::Rejected { diagnostic: diagnostic.clone() };
        assert!(matches!(store.settle_inbound_notice(&mut rejected_attempt, &rejected_progress).await?, InboundNoticeSettlement::Applied(_)));
        assert!(matches!(store.settle_inbound_notice(&mut rejected_attempt, &rejected_progress).await?, InboundNoticeSettlement::AlreadySettled(_)));
        assert!(matches!(store.settle_inbound_notice(&mut rejected_attempt, &InboundNoticeProgress::Unknown { diagnostic: None }).await?, InboundNoticeSettlement::AlreadySettled(_)));
        let rejected = record(&store, "rejected").await?;
        assert_eq!(rejected.status, SendRecordStatus::Rejected);
        assert_eq!(rejected.segments[0].diagnostic.as_deref(), Some(diagnostic.message.as_str()));
        assert_eq!(rejected.segments[0].platform_diagnostic, Some(diagnostic));
        assert!(store.settle_inbound_notice(&mut rejected_attempt, &sent).await.is_err());
        Ok(())
    }

    #[tokio::test]
    async fn notice_commit_failure_and_overflow_never_mint_a_replayable_attempt()
    -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let store = BotStateStore::new(directory.path().join("commit.sqlite"));
        let input = inbound("commit");
        fresh(&store, &input).await?;
        let proof = ready(&store, &input, "worker").await?;
        let before = record(&store, "commit").await?;
        store.db().await?.execute_unprepared(
            "CREATE TABLE notice_commit_parent(id INTEGER PRIMARY KEY);
             CREATE TABLE notice_commit_probe(parent_id INTEGER REFERENCES notice_commit_parent(id) DEFERRABLE INITIALLY DEFERRED);
             CREATE TRIGGER fail_notice_commit AFTER UPDATE OF segment_facts ON send_operations
             BEGIN INSERT INTO notice_commit_probe(parent_id) VALUES(1); END;"
        ).await?;
        let InboundNoticeAdmission::Unconfirmed {
            mut retirement,
            error,
        } = store.begin_inbound_notice(&proof).await?
        else {
            anyhow::bail!("commit failure must return only retirement")
        };
        assert_eq!(error.kind(), FeishuErrorKind::Unavailable);
        assert_eq!(operation::counter(&retirement.record)?, 1);
        assert!(matches!(
            store.retire_inbound_notice(&mut retirement).await?,
            InboundNoticeSettlement::Superseded
        ));
        assert_eq!(record(&store, "commit").await?.segments, before.segments);
        store.db().await?.execute_unprepared("DROP TRIGGER fail_notice_commit;DROP TABLE notice_commit_probe;DROP TABLE notice_commit_parent;").await?;
        let mut overflow = before.clone();
        overflow.segments[0].notice_attempt = Some(u64::MAX);
        store
            .db()
            .await?
            .execute_raw(statement(
                "UPDATE send_operations SET segment_facts=?",
                vec![serde_json::to_string(&overflow.segments)?.into()],
            ))
            .await?;
        assert!(store.begin_inbound_notice(&proof).await.is_err());
        assert_eq!(record(&store, "commit").await?.segments, overflow.segments);
        // A notice without its counter is corrupt, not a zero-attempt grant.
        overflow.segments[0].notice_attempt = None;
        store
            .db()
            .await?
            .execute_raw(statement(
                "UPDATE send_operations SET segment_facts=?",
                vec![serde_json::to_string(&overflow.segments)?.into()],
            ))
            .await?;
        assert!(store.read_inbound_notice(&input, "worker").await.is_err());

        let lost_directory = tempfile::tempdir()?;
        let lost_store = BotStateStore::new(lost_directory.path().join("lost.sqlite"));
        let lost_input = inbound("lost");
        fresh(&lost_store, &lost_input).await?;
        let proof = ready(&lost_store, &lost_input, "old-worker").await?;
        let lost_attempt = begin(&lost_store, &proof).await?;
        let before = record(&lost_store, "lost").await?;
        lost_store.db().await?.execute_unprepared("UPDATE inbound_work SET claimed_at=0").await?;
        assert!(matches!(lost_store.verify_inbound_notice_start(&lost_attempt).await?, InboundNoticeStartCheck::Unavailable(InboundNoticeUnavailable::LostClaim)));
        assert_eq!(lost_store.claim_inbound_work(BOT, CHAT, "lost", "successor").await?, InboundClaim::Claimed);
        let mut lost_retirement = lost_attempt.into_retirement();
        assert!(matches!(lost_store.retire_inbound_notice(&mut lost_retirement).await?, InboundNoticeSettlement::Superseded));
        assert_eq!(record(&lost_store, "lost").await?.segments, before.segments);
        Ok(())
    }

    #[tokio::test]
    async fn notice_pause_uses_current_saved_scope_without_failure_budget_or_control_cas()
    -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let store = BotStateStore::new(directory.path().join("pause.sqlite"));
        let input = bound(&store, "pause", true).await?;
        fresh(&store, &input).await?;
        let proof = ready(&store, &input, "worker").await?;
        phase_fault(&store, BotAuthorizationPhase::Paused).await?;
        assert!(matches!(
            store.read_inbound_notice(&input, "worker").await?,
            InboundNoticeRead::Paused(_)
        ));
        let InboundNoticeAdmission::Paused(paused) = store.begin_inbound_notice(&proof).await?
        else {
            anyhow::bail!("begin must preserve pause")
        };
        assert_eq!(operation::counter(&record(&store, "pause").await?)?, 0);
        assert!(!store.prune_inbound_notice_page(&config(), None).await?.0);
        store.db().await?.execute_unprepared("UPDATE inbound_identities SET content_hash='damaged-admission'").await?;
        assert!(store.finish_inbound_work(BOT, CHAT, "pause", "worker", WorkFinish::NoticePaused(&paused)).await.is_err());
        assert_eq!(operation::counter(&record(&store, "pause").await?)?, 0);
        store.db().await?.execute_raw(statement("UPDATE inbound_identities SET content_hash=?", vec![input.content_hash.clone().into()])).await?;
        // Old admission is deliberately beyond readiness's 900s deadline; typed Pause must
        // neither consume attempts nor collapse its bound route.
        store
            .db()
            .await?
            .execute_raw(statement(
                "UPDATE inbound_identities SET admitted_at=?",
                vec![crate::studio::unix_seconds().saturating_sub(1800).into()],
            ))
            .await?;
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "pause",
                    "worker",
                    WorkFinish::NoticePaused(&paused)
                )
                .await?,
            MarkOutcome::Applied
        );
        let row = store
            .db()
            .await?
            .query_one_raw(statement(
                "SELECT attempt_count,next_attempt_at,status FROM inbound_work",
                vec![],
            ))
            .await?
            .unwrap();
        assert_eq!(super::super::stored_i64(&row, "attempt_count")?, 0);
        assert!(super::super::stored_i64(&row, "next_attempt_at")? > crate::studio::unix_seconds());
        store
            .db()
            .await?
            .execute_unprepared("UPDATE inbound_work SET next_attempt_at=0")
            .await?;
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, "pause", "worker-2")
                .await?,
            InboundClaim::Claimed
        );
        let InboundNoticeRead::Paused(paused) =
            store.read_inbound_notice(&input, "worker-2").await?
        else {
            anyhow::bail!("still paused")
        };
        phase_fault(&store, BotAuthorizationPhase::Active).await?;
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "pause",
                    "worker-2",
                    WorkFinish::NoticePaused(&paused)
                )
                .await?,
            MarkOutcome::Applied
        );
        let fresh_proof = ready(&store, &input, "worker-3").await?;
        phase_fault(&store, BotAuthorizationPhase::Paused).await?;
        phase_fault(&store, BotAuthorizationPhase::Active).await?;
        let attempt = begin(&store, &fresh_proof).await?;
        phase_fault(&store, BotAuthorizationPhase::Paused).await?;
        phase_fault(&store, BotAuthorizationPhase::Active).await?;
        assert!(matches!(store.verify_inbound_notice_start(&attempt).await?, InboundNoticeStartCheck::Ready));
        phase_fault(&store, BotAuthorizationPhase::Paused).await?;
        let InboundNoticeStartCheck::Paused(paused) =
            store.verify_inbound_notice_start(&attempt).await?
        else {
            anyhow::bail!("pre-poll must return pause")
        };
        let mut retirement = attempt.into_retirement();
        assert!(matches!(
            store.retire_inbound_notice(&mut retirement).await?,
            InboundNoticeSettlement::Applied(_)
        ));
        phase_fault(&store, BotAuthorizationPhase::Closed).await?;
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "pause",
                    "worker-3",
                    WorkFinish::NoticePaused(&paused)
                )
                .await?,
            MarkOutcome::Applied
        );
        assert_eq!(
            store
                .claim_inbound_work(BOT, CHAT, "pause", "worker-4")
                .await?,
            InboundClaim::NeedsAttention
        );
        assert_eq!(
            operation::stage(&record(&store, "pause").await?)?,
            MessageStage::NotStarted
        );
        assert_eq!(
            store
                .finish_inbound_work(
                    BOT,
                    CHAT,
                    "pause",
                    "worker-3",
                    WorkFinish::NoticePaused(&paused)
                )
                .await?,
            MarkOutcome::LostClaim
        );
        Ok(())
    }
}
