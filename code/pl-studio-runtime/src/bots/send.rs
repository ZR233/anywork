//! Immutable send plans. Paths are request identities, never deferred byte sources.
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::im::markdown_request_len;
use super::protocol::{FILE_UPLOAD_LIMIT_BYTES, POST_CONTENT_LIMIT_BYTES};
use super::storage::reply::{InboundNoticeIdentity, NoticeAuthorization, ReplyBinding};
use super::storage::{MessageStage, SendRecord, SendRecordStatus};
use crate::resource_store::{DirectorySyncOutcome, ResourceRetention};
use pl_core::context::ResourceReference;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::time::Duration;
use tokio::time::Instant;

/// Same per-bot dispatch gate for CardKit and explicit typed sends; never held across HTTP.
pub(crate) struct SendRate(tokio::sync::Mutex<Instant>);
pub(crate) struct SendPermit<'a>(tokio::sync::MutexGuard<'a, Instant>);

impl SendRate {
    pub(crate) fn new() -> Self {
        Self(tokio::sync::Mutex::new(Instant::now()))
    }
    pub(crate) async fn acquire(&self) -> SendPermit<'_> {
        let next = self.0.lock().await;
        tokio::time::sleep_until(*next).await;
        SendPermit(next)
    }
}

impl SendPermit<'_> {
    pub(crate) fn start(mut self) {
        *self.0 = Instant::now() + Duration::from_millis(200);
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind"
)]
pub enum SendContent {
    Markdown {
        text: String,
    },
    File {
        filename: String,
        /// A missing extension gets `.bin` only for the platform's display requirement. This
        /// is not a conversion; the original filename and exact byte identity stay frozen.
        upload_filename: String,
        resource: ResourceReference,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind"
)]
pub(in crate::bots) enum SendIdentity {
    /// Only records decoded by the version migration may use the pre-Markdown text hash.
    LegacyText,
    Markdown {
        request_hash: String,
    },
    File {
        request_hash: String,
    },
    InboundNotice {
        request_hash: String,
        identity: Box<InboundNoticeIdentity>,
    },
}

/// Host-created source grant, not a deserializable tool argument. The stored copy only provides
/// provenance; every tool invocation must prove it again from canonical Thread facts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SendSource {
    pub bot_id: String,
    pub chat_id: String,
    pub app_id: String,
    pub project_id: String,
    pub thread_id: String,
    pub input_id: String,
    pub original_input_id: String,
    pub message_id: String,
    pub open_id: String,
    pub chat_kind: String,
    pub creation_id: String,
    pub binding_revision: u64,
}

pub(in crate::bots) struct SendPlan {
    pub content_hash: String,
    pub identity: SendIdentity,
    pub source: Option<SendSource>,
    pub segments: Vec<SendContent>,
    pub uuids: Vec<String>,
    /// Ephemeral proof from this production pass, not a new persistent reference source.
    pub(super) retention: Option<DirectorySyncOutcome>,
}

pub fn markdown_hash(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    text: &str,
) -> Result<String, FeishuError> {
    fingerprint(&("markdown", operation_id, bot_id, chat_id, text))
}

pub(in crate::bots) fn plan_markdown(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    text: String,
) -> Result<SendPlan, FeishuError> {
    if text.trim().is_empty() {
        return Err(rejected("message Markdown is required"));
    }
    let request_hash = markdown_hash(operation_id, bot_id, chat_id, &text)?;
    // Explicit proactive posts keep main's bounded text segmentation. Normal replies use
    // CardKit; neither path silently archives a transcript or exports reply.md.
    let segments = split_text(chat_id, &text)?
        .into_iter()
        .map(|text| SendContent::Markdown { text })
        .collect::<Vec<_>>();
    let content_hash = fingerprint(&(
        "markdown-plan",
        operation_id,
        bot_id,
        chat_id,
        &request_hash,
        &segments,
    ))?;
    plan(
        operation_id,
        bot_id,
        chat_id,
        content_hash,
        SendIdentity::Markdown { request_hash },
        None,
        segments,
    )
}

const INBOUND_NOTICE_TEXT: &str = "此消息类型或富文本元素暂不支持原件接收。可接收文字、富文本、图片、文件及可下载音视频；贴纸和云文档分享没有对应原件下载接口，请直接发送原文件。";

/// Locates the original notice even before a typed identity is available. IDs are preserved
/// verbatim: this adds neither character restrictions nor trimming/normalization to admission.
pub(in crate::bots) fn inbound_notice_operation_id(
    bot_id: &str,
    chat_id: &str,
    message_id: &str,
) -> Result<String, FeishuError> {
    let fields = ["botunsupported:", bot_id, ":", chat_id, ":", message_id];
    let capacity = fields.iter().try_fold(0_usize, |total, field| {
        total
            .checked_add(field.len())
            .ok_or_else(super::occupancy::freeze_budget_error)
    })?;
    let mut operation = String::new();
    operation
        .try_reserve_exact(capacity)
        .map_err(|error| super::occupancy::freeze_budget_error().with_source(error))?;
    for field in fields {
        operation.push_str(field);
    }
    Ok(operation)
}

/// Pure initial plan for the Fresh inbound transaction. The immutable provenance is not a
/// current authorization: this helper does not read a head, claim an operation or start HTTP.
pub(in crate::bots) fn plan_inbound_notice(
    identity: &InboundNoticeIdentity,
) -> Result<SendPlan, FeishuError> {
    validate_notice_identity(identity)?;
    let source = identity.source();
    let operation =
        inbound_notice_operation_id(&source.bot_id, &source.chat_id, &source.message_id)?;
    let request_hash = fingerprint(&(
        "inbound-notice-request",
        1_u32,
        &operation,
        identity,
        INBOUND_NOTICE_TEXT,
    ))?;
    let send_identity = SendIdentity::InboundNotice {
        request_hash,
        identity: Box::new(identity.clone()),
    };
    let send_source = Some(source.clone());
    let segments = vec![SendContent::Markdown {
        text: INBOUND_NOTICE_TEXT.into(),
    }];
    let content_hash = fingerprint(&(
        "inbound-notice-plan",
        1_u32,
        &operation,
        &source.bot_id,
        &source.chat_id,
        &send_source,
        &send_identity,
        &segments,
    ))?;
    // Deliberately bypass plan_markdown/split_text: the fixed notice is exactly one original
    // UUID and the existing IM serializer checks the complete JSON envelope, without fallback.
    plan(
        &operation,
        &source.bot_id,
        &source.chat_id,
        content_hash,
        send_identity,
        send_source,
        segments,
    )
}

fn validate_notice_identity(identity: &InboundNoticeIdentity) -> Result<(), FeishuError> {
    let source = identity.source();
    let original_input = format!(
        "bot:{}:{}:{}",
        source.bot_id, source.chat_id, source.message_id
    );
    if identity.version() != 1
        || [
            &source.bot_id,
            &source.chat_id,
            &source.message_id,
            &source.app_id,
            &source.project_id,
        ]
        .iter()
        .any(|field| field.is_empty())
        || source.input_id != original_input
        || source.original_input_id != original_input
        || !matches!(source.chat_kind.as_str(), "direct" | "group")
        || (source.chat_kind == "direct" && source.open_id.is_empty())
    {
        return Err(rejected(
            "inbound notice has an invalid version or original source identity",
        ));
    }
    let consistent = match (identity.binding(), identity.authorization()) {
        (ReplyBinding::Absent, NoticeAuthorization::NoHead {}) => {
            source.thread_id.is_empty()
                && source.creation_id.is_empty()
                && source.binding_revision == 0
        }
        (ReplyBinding::Creating, NoticeAuthorization::NoHead {}) => {
            source.thread_id.is_empty()
                && !source.creation_id.is_empty()
                && source.binding_revision > 0
        }
        (ReplyBinding::Bound, NoticeAuthorization::Bound { start }) => {
            !source.thread_id.is_empty()
                && !source.creation_id.is_empty()
                && source.binding_revision > 0
                && start.version == 1
                && start.extension_revision > 0
                && start.sequence > 0
                && !start.intent.operation_id.is_empty()
                && start.intent.thread_id == source.thread_id
                && start.intent.binding_revision == source.binding_revision
                && start.intent.authorization.bot_id == source.bot_id
                && start.intent.authorization.chat_id == source.chat_id
                && start.intent.authorization.generation > 0
                && start
                    .excluded_turn_id
                    .as_ref()
                    .is_none_or(|id| !id.is_empty())
        }
        _ => false,
    };
    if !consistent {
        return Err(rejected(
            "inbound notice binding and immutable Saved provenance conflict",
        ));
    }
    Ok(())
}

/// Checks immutable request materials and the real mutable message facts separately. This
/// neither upgrades a legacy row nor grants a new attempt from InFlight/Unknown/receipt data.
pub(in crate::bots) fn verify_inbound_notice_record(
    record: &SendRecord,
    expected: &InboundNoticeIdentity,
) -> Result<(), FeishuError> {
    let plan = plan_inbound_notice(expected)?;
    let source = expected.source();
    let operation =
        inbound_notice_operation_id(&source.bot_id, &source.chat_id, &source.message_id)?;
    let [fact] = record.segments.as_slice() else {
        return Err(rejected(
            "inbound notice must retain exactly one Markdown segment",
        ));
    };
    if record.operation_id != operation
        || record.bot_id != source.bot_id
        || record.chat_id != source.chat_id
        || record.content_hash != plan.content_hash
        || record.identity != plan.identity
        || record.source != plan.source
        || !record.facts_complete
        || fact.index != 0
        || fact.uuid != plan.uuids[0]
        || fact.content.as_ref() != plan.segments.first()
        || fact.upload.is_some()
        || fact.stop_reason.is_some()
    {
        return Err(rejected(
            "inbound notice immutable request or source materials conflict",
        ));
    }
    let counter = fact
        .notice_attempt
        .ok_or_else(|| rejected("inbound notice attempt counter is missing"))?;
    let stage = fact
        .message_stage
        .ok_or_else(|| rejected("inbound notice message stage is missing"))?;
    if stage != MessageStage::NotStarted && counter == 0 {
        return Err(rejected(
            "a started inbound notice requires a positive attempt counter",
        ));
    }
    let no_ids = fact.platform_message_id.is_none() && record.platform_message_ids.is_empty();
    let diagnostic_matches = match (&fact.platform_diagnostic, &fact.diagnostic) {
        (Some(platform), Some(message)) => platform.message == *message,
        (None, None) => true,
        _ => false,
    };
    let valid = match stage {
        MessageStage::NotStarted | MessageStage::InFlight => {
            no_ids
                && record.status == SendRecordStatus::Unknown
                && fact.status == SendRecordStatus::Unknown
                && fact.diagnostic.is_none()
                && fact.platform_diagnostic.is_none()
        }
        MessageStage::Accepted => {
            fact.platform_message_id.as_ref().is_some_and(|id| {
                !id.trim().is_empty()
                    && record.platform_message_ids.as_slice() == std::slice::from_ref(id)
            }) && record.status == SendRecordStatus::Succeeded
                && fact.status == SendRecordStatus::Succeeded
                && fact.diagnostic.is_none()
                && fact.platform_diagnostic.is_none()
        }
        MessageStage::Rejected => {
            no_ids
                && record.status == SendRecordStatus::Rejected
                && fact.status == SendRecordStatus::Rejected
                && fact.platform_diagnostic.is_some()
                && diagnostic_matches
        }
        MessageStage::Unknown => {
            no_ids
                && record.status == SendRecordStatus::Unknown
                && fact.status == SendRecordStatus::Unknown
                && diagnostic_matches
        }
    };
    if !valid {
        return Err(rejected(
            "inbound notice stage, diagnostic or platform message identity is inconsistent",
        ));
    }
    Ok(())
}

/// Checked UTF-8 freeze peak for this complete record, not a new permit or task owner.
///
/// Owned record fields: four copies (caller/frozen row, Delivery, cap, writer/readback),
/// plus one SQL parameter copy of scalar keys. Message IDs have two SQL/join/readback copies.
/// Standalone provenance: three more identities (Ready, transient authority, cap proof),
/// with their Bound control references' bot/chat strings counted separately.
/// Metadata JSON: three encoded/SQL/readback copies via send_metadata_bytes; segment JSON
/// likewise has three copies. Encoded identity/source/proof lengths also conservatively bound
/// their owned UTF-8 fields, including both stored sources and every Saved receipt field.
/// Two full IM envelopes cover serializer content and the PreparedPost body at preparation.
/// External inbound/worker/credential strings and newly received progress are the caller's
/// actual-length responsibility before it makes additional owned copies.
pub(in crate::bots) fn inbound_notice_freeze_bytes(
    record: &SendRecord,
) -> Result<usize, FeishuError> {
    let SendIdentity::InboundNotice { identity, .. } = &record.identity else {
        return Err(rejected(
            "notice freeze budget requires a typed inbound notice record",
        ));
    };
    verify_inbound_notice_record(record, identity)?;
    let fact = &record.segments[0];
    let mut fields = vec![
        (record.operation_id.as_str(), 5),
        (record.bot_id.as_str(), 5),
        (record.chat_id.as_str(), 5),
        (record.content_hash.as_str(), 5),
        (fact.uuid.as_str(), 4),
        (INBOUND_NOTICE_TEXT, 4),
    ];
    if matches!(identity.authorization(), NoticeAuthorization::Bound { .. }) {
        fields.push((record.bot_id.as_str(), 3));
        fields.push((record.chat_id.as_str(), 3));
    }
    for id in &record.platform_message_ids {
        fields.push((id.as_str(), 6));
    }
    if let Some(id) = &fact.platform_message_id {
        fields.push((id.as_str(), 4));
    }
    if let Some(message) = &fact.diagnostic {
        fields.push((message.as_str(), 4));
    }
    if let Some(diagnostic) = &fact.platform_diagnostic {
        fields.push((diagnostic.code.as_str(), 4));
        fields.push((diagnostic.message.as_str(), 4));
        if let Some(code) = &diagnostic.platform_code {
            fields.push((code.as_str(), 4));
        }
        if let Some(guidance) = &diagnostic.guidance {
            fields.push((guidance.as_str(), 4));
        }
    }
    let base = super::occupancy::counted_text_bytes(fields)?;
    let identity_bytes = notice_encoded_len(&record.identity)?;
    let source_bytes = notice_encoded_len(&record.source)?;
    let proof_bytes = notice_encoded_len(identity.as_ref())?;
    let status_bound = [
        SendRecordStatus::Succeeded,
        SendRecordStatus::Partial,
        SendRecordStatus::Rejected,
        SendRecordStatus::Unknown,
    ]
    .iter()
    .try_fold(0_usize, |maximum, status| {
        notice_encoded_len(status).map(|length| maximum.max(length))
    })?;
    let stage_bound = [
        MessageStage::NotStarted,
        MessageStage::InFlight,
        MessageStage::Accepted,
        MessageStage::Rejected,
        MessageStage::Unknown,
    ]
    .iter()
    .try_fold(0_usize, |maximum, stage| {
        notice_encoded_len(stage).map(|length| maximum.max(length))
    })?;
    // A later stage/counter changes the JSON width but never the immutable hash. Reserve the
    // serializer-derived integer/enum maxima, not an arbitrary per-operation padding constant.
    let counter_growth = notice_encoded_len(&u64::MAX)?
        .checked_sub(notice_encoded_len(&fact.notice_attempt)?)
        .ok_or_else(super::occupancy::freeze_budget_error)?;
    let status_growth = status_bound
        .checked_sub(notice_encoded_len(&fact.status)?)
        .ok_or_else(super::occupancy::freeze_budget_error)?;
    let stage_growth = stage_bound
        .checked_sub(notice_encoded_len(&fact.message_stage)?)
        .ok_or_else(super::occupancy::freeze_budget_error)?;
    let growth = counter_growth
        .checked_add(status_growth)
        .and_then(|extra| extra.checked_add(stage_growth))
        .ok_or_else(super::occupancy::freeze_budget_error)?;
    let facts_bytes = super::storage::segment_facts_bytes(&record.segments)?
        .checked_add(growth)
        .ok_or_else(super::occupancy::freeze_budget_error)?;
    let request_bytes = markdown_request_len(&record.chat_id, INBOUND_NOTICE_TEXT, &fact.uuid)?;
    let total = super::occupancy::counted_extra_bytes(
        base,
        [
            (identity_bytes, 4),
            (source_bytes, 4),
            (proof_bytes, 3),
            (facts_bytes, 3),
            (request_bytes, 2),
            (status_bound, 2),
        ],
    )?;
    total
        .checked_add(super::storage::send_metadata_bytes(record)?)
        .ok_or_else(super::occupancy::freeze_budget_error)
}

fn notice_encoded_len(value: &impl Serialize) -> Result<usize, FeishuError> {
    serde_json::to_vec(value)
        .map(|bytes| bytes.len())
        .map_err(|error| super::occupancy::freeze_budget_error().with_source(error))
}

/// An automatic frontend file uses the Saved producer identity, never an inbound/tool grant.
pub(super) fn plan_public_artifact(
    operation_id: &str,
    scope: &super::storage::publication::DeliveryScope,
    artifact: &super::storage::publication::SavedArtifact,
    retained: ResourceRetention,
) -> Result<SendPlan, FeishuError> {
    use super::storage::publication::{delivery_file_plan_hash, delivery_file_request_hash};
    let (resource, outcome) = retained.into_parts();
    if resource.byte_len() == 0 || resource.byte_len() > FILE_UPLOAD_LIMIT_BYTES as u64 {
        return Err(rejected("file upload requires 1..=30,000,000 bytes"));
    }
    if resource.content_digest() != artifact.resource().content_digest
        || resource.byte_len() != artifact.resource().byte_len
        || resource.media_type() != artifact.resource().media_type
    {
        return Err(rejected(
            "retained public artifact differs from its Saved original",
        ));
    }
    let filename = artifact.display_name().to_owned();
    let upload_filename = if std::path::Path::new(&filename).extension().is_none() {
        format!("{filename}.bin")
    } else {
        filename.clone()
    };
    let segments = vec![SendContent::File {
        filename,
        upload_filename,
        resource,
    }];
    let entity = artifact.entity_key();
    let request_hash = delivery_file_request_hash(scope, &entity, artifact)?;
    let content_hash = delivery_file_plan_hash(scope, &entity, artifact, operation_id, &segments)?;
    let mut plan = plan(
        operation_id,
        &scope.bot_id,
        &scope.chat_id,
        content_hash,
        SendIdentity::File { request_hash },
        None,
        segments,
    )?;
    plan.retention = Some(outcome);
    Ok(plan)
}

/// Receipt reads verify the same complete identity as the transactional binding, without reading
/// the Thread original or retaining another copy. The database separately checks the binding.
pub(super) fn verify_public_artifact_record(
    record: &super::storage::SendRecord,
    operation_id: &str,
    authority: &super::PublicationSendAuthority,
) -> Result<(), FeishuError> {
    use super::send_service::conflict;
    use super::storage::publication::{delivery_file_plan_hash, delivery_file_request_hash};
    let scope = &authority.scope;
    let permit = &authority.permit;
    let artifact = &permit.artifact;
    let [segment] = record.segments.as_slice() else {
        return Err(conflict());
    };
    let Some(
        content @ SendContent::File {
            filename,
            upload_filename,
            resource,
        },
    ) = &segment.content
    else {
        return Err(conflict());
    };
    let expected_upload = if std::path::Path::new(artifact.display_name())
        .extension()
        .is_none()
    {
        format!("{}.bin", artifact.display_name())
    } else {
        artifact.display_name().to_owned()
    };
    if record.operation_id != operation_id
        || record.bot_id != scope.bot_id
        || record.chat_id != scope.chat_id
        || record.source.is_some()
        || !record.facts_complete
        || record.identity
            != (SendIdentity::File {
                request_hash: delivery_file_request_hash(scope, &permit.entity, artifact)?,
            })
        || segment.index != 0
        || segment.uuid != send_uuid(operation_id, &scope.bot_id, &scope.chat_id, 0)?
        || segment.upload.is_none()
        || segment.message_stage.is_none()
        || filename != artifact.display_name()
        || *upload_filename != expected_upload
        || resource.content_digest() != artifact.resource().content_digest
        || resource.byte_len() != artifact.resource().byte_len
        || resource.media_type() != artifact.resource().media_type
        || record.content_hash
            != delivery_file_plan_hash(
                scope,
                &permit.entity,
                artifact,
                operation_id,
                std::slice::from_ref(content),
            )?
    {
        return Err(conflict());
    }
    resource.validate().map_err(|_| conflict())
}

fn plan(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    content_hash: String,
    identity: SendIdentity,
    source: Option<SendSource>,
    segments: Vec<SendContent>,
) -> Result<SendPlan, FeishuError> {
    let uuids = (0..segments.len())
        .map(|index| send_uuid(operation_id, bot_id, chat_id, index))
        .collect::<Result<Vec<_>, _>>()?;
    for (segment, uuid) in segments.iter().zip(&uuids) {
        if let SendContent::Markdown { text } = segment
            && markdown_request_len(chat_id, text, uuid)? > POST_CONTENT_LIMIT_BYTES
        {
            return Err(rejected(
                "target and Markdown notice exceed the complete message JSON budget",
            ));
        }
    }
    Ok(SendPlan {
        content_hash,
        identity,
        source,
        segments,
        uuids,
        retention: None,
    })
}

const MAX_SEND_SEGMENTS: usize = 32;
const MAX_SEND_CHARS: usize = 200_000;

fn split_text(chat_id: &str, text: &str) -> Result<Vec<String>, FeishuError> {
    if text.chars().count() > MAX_SEND_CHARS {
        return Err(rejected("message text exceeds the send size bound"));
    }
    let uuid = "0".repeat(32);
    let mut segments = Vec::new();
    let mut rest = text;
    while !rest.is_empty() {
        if segments.len() == MAX_SEND_SEGMENTS {
            return Err(rejected("message requires more segments than allowed"));
        }
        let mut lower = 0;
        let mut upper = rest.len();
        while lower < upper {
            let mut end = lower + (upper - lower).div_ceil(2);
            while !rest.is_char_boundary(end) {
                end += 1;
            }
            if markdown_request_len(chat_id, &rest[..end], &uuid)? <= POST_CONTENT_LIMIT_BYTES {
                lower = end;
            } else {
                upper = end - 1;
                while !rest.is_char_boundary(upper) {
                    upper -= 1;
                }
            }
        }
        if lower == 0 {
            return Err(rejected("message envelope exceeds the send size bound"));
        }
        let end = if lower == rest.len() {
            lower
        } else {
            let prefix = &rest[..lower];
            prefix
                .rfind("\n\n")
                .map(|position| position + 2)
                .or_else(|| prefix.rfind('\n').map(|position| position + 1))
                .unwrap_or(lower)
        };
        segments.push(rest[..end].to_owned());
        rest = &rest[end..];
    }
    Ok(segments)
}

fn send_uuid(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    index: usize,
) -> Result<String, FeishuError> {
    fingerprint(&(operation_id, bot_id, chat_id, index)).map(|hash| hash[..32].to_owned())
}

fn fingerprint(value: &impl Serialize) -> Result<String, FeishuError> {
    // Stream serde's canonical typed encoding into the digest; escaping a long Markdown body
    // must not allocate an additional potentially 6x-sized JSON copy just to fingerprint it.
    struct HashWriter(Sha256);
    impl std::io::Write for HashWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0.update(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut writer = HashWriter(Sha256::new());
    serde_json::to_writer(&mut writer, value)
        .map_err(|_| rejected("could not encode send identity"))?;
    Ok(hex::encode(writer.0.finalize()))
}

pub(crate) fn rejected(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Rejected, message, false, None)
}
