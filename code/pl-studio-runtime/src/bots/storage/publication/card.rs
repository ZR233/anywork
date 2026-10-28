//! 卡片与文件的 typed 平台材料：动作/结果矩阵、呈现映射与旧卡片迁移映射。
//!
//! 只做类型与纯映射，不拥有 I/O，也不发起网络动作；sequence/uuid 由账本分配。

use super::*;
use crate::bots::storage::card::{
    CardAction, CardOperation, CardOperationStatus, CardRecovery, CardRecoveryPhase,
};

/// 卡片实体材料：复用既有 sequence/UUID/确认正文/恢复语义。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryCard {
    pub card_id: Option<String>,
    pub platform_message_id: Option<String>,
    pub sequence: i32,
    pub confirmed_sequence: i32,
    pub streaming: Option<bool>,
    pub recovery_used: bool,
    pub recovery: Option<DeliveryCardRecovery>,
    pub lifecycle: Option<CardLifecycle>,
    /// 已确认正文片段：旧值原样保留，不因新上限重写。
    pub confirmed_text: String,
    pub confirmed_content_hash: String,
    pub confirmed_presentation: Option<BotItemPresentation>,
    pub final_content_hash: Option<String>,
    pub diagnostic: Option<BotDiagnostic>,
    /// 只标识经本地无网络终局端口保存的原因，不能反向充当平台关闭回执。
    #[serde(default)]
    pub legacy_local_completion: Option<LegacyLocalCompletion>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum LegacyLocalCompletion {
    NoFinal,
    Discarded,
    InteractionEnded,
    Cancelled,
    Failed,
    BudgetLimited,
}

impl LegacyLocalCompletion {
    pub(super) fn lifecycle(self) -> CardLifecycle {
        match self {
            Self::NoFinal => CardLifecycle::NoFinalReply,
            Self::Discarded | Self::Cancelled => CardLifecycle::Cancelled,
            Self::InteractionEnded => CardLifecycle::InteractionEnded,
            Self::Failed => CardLifecycle::Failed,
            Self::BudgetLimited => CardLifecycle::BudgetLimited,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryCardRecovery {
    pub action: DeliveryAction,
    pub phase: CardRecoveryPhase,
}

/// 平台动作意图；`sequence` 由账本分配，不接受调用方覆盖。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(in crate::bots) enum DeliveryAction {
    CreateCard {
        text: String,
    },
    SendCard {
        card_id: String,
    },
    UpdateContent {
        card_id: String,
        text: String,
        final_content: bool,
    },
    UpdateSettings {
        card_id: String,
        streaming: bool,
        lifecycle: CardLifecycle,
        recovery: bool,
    },
}

impl DeliveryAction {
    pub(in crate::bots) fn card_id(&self) -> Option<&str> {
        match self {
            Self::CreateCard { .. } => None,
            Self::SendCard { card_id }
            | Self::UpdateContent { card_id, .. }
            | Self::UpdateSettings { card_id, .. } => Some(card_id),
        }
    }

    /// Create/Send 不消费内容序号；其余动作每次分配新的严格正序号。
    pub(in crate::bots) fn sequenced(&self) -> bool {
        matches!(
            self,
            Self::UpdateContent { .. } | Self::UpdateSettings { .. }
        )
    }

    pub(in crate::bots) fn kind(&self) -> BotCardOperationKind {
        match self {
            Self::CreateCard { .. } => BotCardOperationKind::Create,
            Self::SendCard { .. } => BotCardOperationKind::Send,
            Self::UpdateContent { .. } => BotCardOperationKind::Content,
            Self::UpdateSettings { .. } => BotCardOperationKind::Settings,
        }
    }

    pub(in crate::bots) fn text(&self) -> Option<&str> {
        match self {
            Self::CreateCard { text } | Self::UpdateContent { text, .. } => Some(text),
            _ => None,
        }
    }
}

/// 冻结目标不携带任意 URL 或 element；ElementContent 固定既有 answer 元素。
/// card_id 只能取原 DeliveryAction，chat_id 只能取原 scope。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum DeliveryRequestTarget {
    CreateCard,
    SendCard,
    ElementContent,
    WholeCard,
    Settings,
}

/// 请求实际目标与序列化正文。网络只能消费这份材料，不从最新 entity/内存条件重建。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct FrozenDeliveryRequest {
    target: DeliveryRequestTarget,
    body: String,
    migrated: bool,
}

impl FrozenDeliveryRequest {
    /// 由真实协议 serializer 在同步构造回调里返回；不在回调中进行 IO 或重入 store。
    pub(in crate::bots) fn new(
        target: DeliveryRequestTarget,
        body: String,
    ) -> Result<Self, FeishuError> {
        let request = Self {
            target,
            body,
            migrated: false,
        };
        request.validate()?;
        Ok(request)
    }
    pub(super) fn legacy(target: DeliveryRequestTarget, body: String) -> Result<Self, FeishuError> {
        let request = Self {
            target,
            body,
            migrated: true,
        };
        request.validate()?;
        Ok(request)
    }
    pub(in crate::bots) fn body(&self) -> &str {
        &self.body
    }
    pub(in crate::bots) fn target(&self) -> DeliveryRequestTarget {
        self.target
    }
    pub(in crate::bots) fn validate(&self) -> Result<(), FeishuError> {
        if self.migrated && self.target == DeliveryRequestTarget::WholeCard {
            return Err(rejected(
                "legacy operations cannot change to whole-card requests",
            ));
        }
        // 旧请求已发材料不受新预算裁剪；迁移解码本身已有旧协议文本上限。
        let bound = if self.migrated {
            2 * 1024 * 1024
        } else {
            DELIVERY_REQUEST_BYTES
        };
        if self.body.is_empty() || self.body.len() > bound {
            return Err(rejected(
                "serialized delivery request exceeds its material bound",
            ));
        }
        Ok(())
    }
    pub(in crate::bots) fn validate_for_action(
        &self,
        action: &DeliveryAction,
    ) -> Result<(), FeishuError> {
        self.validate()?;
        let matches = matches!(
            (self.target, action),
            (
                DeliveryRequestTarget::CreateCard,
                DeliveryAction::CreateCard { .. }
            ) | (
                DeliveryRequestTarget::SendCard,
                DeliveryAction::SendCard { .. }
            ) | (
                DeliveryRequestTarget::ElementContent | DeliveryRequestTarget::WholeCard,
                DeliveryAction::UpdateContent { .. }
            ) | (
                DeliveryRequestTarget::Settings,
                DeliveryAction::UpdateSettings { .. }
            )
        );
        if !matches {
            return Err(rejected(
                "frozen request target does not match its delivery action",
            ));
        }
        Ok(())
    }
    /// sha256(serde_json::to_vec(&(target, body)))，含 sha256: 前缀；不是仅 body 的摘要。
    pub(in crate::bots) fn hash(&self) -> Result<String, FeishuError> {
        typed_digest(&(self.target, self.body.as_str()))
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryOperationIdentity {
    pub operation_id: String,
    pub sequence: i32,
    pub uuid: String,
}

/// 平台结果；与动作种类严格匹配。Unknown 保留原事实，不重试、不换 UUID。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(in crate::bots) enum DeliveryResult {
    /// 原发送所有者凭本次不可重建的启动证明记录的本地事实，不是平台结果。
    NotStarted,
    Created {
        card_id: String,
    },
    Sent {
        card_id: String,
        message_id: String,
    },
    ContentAccepted {
        card_id: String,
    },
    SettingsAccepted {
        card_id: String,
        streaming: bool,
    },
    Rejected {
        diagnostic: String,
    },
    Unknown {
        diagnostic: Option<String>,
    },
}

/// 已持久化的操作意图；sequence/uuid 分配后不复用。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryIntent {
    pub operation_id: String,
    pub action: DeliveryAction,
    pub request_hash: String,
    pub request: FrozenDeliveryRequest,
    /// 旧 action 指纹单独保留；不能冒充当前准确请求字节的摘要。
    pub legacy_action_hash: Option<String>,
    pub content_revision: u64,
    pub integrity: BotTextIntegrity,
    pub saved: bool,
    pub sequence: i32,
    pub uuid: String,
    pub created_at: i64,
    pub lease_generation: u64,
    pub owner_id: String,
}

/// 原操作的最终结果，供迟到结算幂等核对与“不覆盖后继操作”判定。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliverySettled {
    pub intent: DeliveryIntent,
    pub result: DeliveryResult,
}

/// 首次发送记录之前的本地准备失败；不接受其它渠道限制或平台诊断作为原因。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum DeliveryFilePreparationBlock {
    SourceUnavailable,
    BudgetUnavailable,
}

impl DeliveryFilePreparationBlock {
    pub(super) fn platform_reason(self) -> BotFileBlockReason {
        match self {
            Self::SourceUnavailable => BotFileBlockReason::SourceUnavailable,
            Self::BudgetUnavailable => BotFileBlockReason::BudgetUnavailable,
        }
    }
}

/// 单项停止原因：真实网络终局与尚未建立发送记录的本地准备失败分别表达。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum DeliveryHalt {
    Unknown {
        operation_id: String,
        diagnostic: Option<String>,
    },
    Rejected {
        operation_id: String,
        diagnostic: String,
    },
    /// 由原文件账本的本地失败派生，不构成平台拒绝或未知的证据。
    LocalFailure {
        #[serde(rename = "operationId")]
        operation_id: String,
    },
    /// 只阻止精确 canonical 修订；不证明任何网络动作或平台结果。
    FilePreparation {
        revision: u64,
        reason: DeliveryFilePreparationBlock,
    },
}

/// 平台结果到 GUI typed 结果的映射；Unknown/Rejected 保留真实诊断。
pub(in crate::bots) fn platform_result(result: &DeliveryResult) -> BotPlatformResult {
    match result {
        DeliveryResult::NotStarted => BotPlatformResult::NotStarted {},
        DeliveryResult::Created { .. }
        | DeliveryResult::Sent { .. }
        | DeliveryResult::ContentAccepted { .. }
        | DeliveryResult::SettingsAccepted { .. } => BotPlatformResult::Accepted {},
        DeliveryResult::Rejected { diagnostic } => BotPlatformResult::Rejected {
            diagnostic: diagnostic_of(diagnostic),
        },
        DeliveryResult::Unknown { diagnostic } => BotPlatformResult::Unknown {
            diagnostic: match diagnostic {
                Some(diagnostic) => diagnostic_of(diagnostic),
                None => BotDiagnostic {
                    code: "deliveryUnknown".to_string(),
                    message: "the platform outcome of a started request is unknown".to_string(),
                    retryable: false,
                    platform_code: None,
                    guidance: None,
                },
            },
        },
    }
}

pub(in crate::bots) fn diagnostic_of(diagnostic: &str) -> BotDiagnostic {
    BotDiagnostic {
        code: "delivery".to_string(),
        message: diagnostic.to_string(),
        retryable: false,
        platform_code: None,
        guidance: None,
    }
}

/// 文件本地准入拒绝：0 字节或超过平台大小上限时本地产物仍有效，渠道明确未交付。
pub(in crate::bots) fn file_block_reason(file: &DeliveryFile) -> Option<BotFileBlockReason> {
    if file.artifact.resource().byte_len == 0 {
        Some(BotFileBlockReason::EmptyFile)
    } else if file.artifact.resource().byte_len
        > crate::bots::protocol::FILE_UPLOAD_LIMIT_BYTES as u64
    {
        Some(BotFileBlockReason::PlatformSizeLimit)
    } else {
        None
    }
}

pub(in crate::bots) fn file_outcome(
    upload: &BotPlatformResult,
    message: &BotPlatformResult,
    local_stop: Option<BotSendStopReason>,
) -> BotFileOutcome {
    if matches!(
        upload,
        BotPlatformResult::Unknown { .. } | BotPlatformResult::InFlight {}
    ) || matches!(
        message,
        BotPlatformResult::Unknown { .. } | BotPlatformResult::InFlight {}
    ) {
        BotFileOutcome::Unknown
    } else if matches!(upload, BotPlatformResult::Accepted {})
        && matches!(message, BotPlatformResult::Rejected { .. })
    {
        BotFileOutcome::Partial
    } else if matches!(upload, BotPlatformResult::Rejected { .. })
        || matches!(message, BotPlatformResult::Rejected { .. })
    {
        BotFileOutcome::Rejected
    } else if matches!(message, BotPlatformResult::Accepted {}) {
        BotFileOutcome::Delivered
    } else if local_stop.is_some() {
        BotFileOutcome::Stopped
    } else {
        BotFileOutcome::Pending
    }
}

/// 文件阶段只读快照：阶段事实仍由原发送账本持有。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryFileStage {
    pub operation_id: String,
    pub upload: BotPlatformResult,
    pub message: BotPlatformResult,
    pub local_stop: Option<BotSendStopReason>,
}

impl DeliveryFileStage {
    /// 唯一阶段仍在 send ledger；这里只派生围栏与 GUI 状态，不保存第二份阶段。
    pub(super) fn halt(&self) -> Option<DeliveryHalt> {
        let uncertain = [&self.upload, &self.message].into_iter().any(|stage| {
            matches!(
                stage,
                BotPlatformResult::Unknown { .. } | BotPlatformResult::InFlight {}
            )
        });
        if uncertain {
            return Some(DeliveryHalt::Unknown {
                operation_id: self.operation_id.clone(),
                diagnostic: Some("a started file stage has no confirmed outcome".into()),
            });
        }
        if let Some(diagnostic) =
            [&self.upload, &self.message]
                .into_iter()
                .find_map(|stage| match stage {
                    BotPlatformResult::Rejected { diagnostic } => Some(diagnostic),
                    _ => None,
                })
        {
            return Some(DeliveryHalt::Rejected {
                operation_id: self.operation_id.clone(),
                diagnostic: diagnostic.message.clone(),
            });
        }
        if !matches!(self.message, BotPlatformResult::Accepted {})
            && self.local_stop == Some(BotSendStopReason::LocalFailure)
        {
            return Some(DeliveryHalt::LocalFailure {
                operation_id: self.operation_id.clone(),
            });
        }
        None
    }

    /// 只证明此操作还有确定未启动的阶段。具体 upload/message 的 CAS 仍由原发送 writer
    /// 负责；upload 已 Accepted 时这里只允许剩下的 message，不授权再上传。
    pub(super) fn has_unstarted_stage(&self) -> bool {
        self.halt().is_none()
            && matches!(
                (&self.upload, &self.message),
                (
                    BotPlatformResult::NotStarted {} | BotPlatformResult::Accepted {},
                    BotPlatformResult::NotStarted {}
                )
            )
    }
}

pub(in crate::bots) fn item_platform(
    entity: &DeliveryEntity,
    file: Option<DeliveryFileStage>,
) -> BotItemPlatform {
    if let DeliveryContent::Unresolved { unresolved } = &entity.state.content
        && let Some(observation) = &unresolved.observation
    {
        return observation.platform.clone();
    }
    // 当前渠道限制优先呈现；旧 binding/阶段/接受结果仍保留在原账本中。
    if let DeliveryContent::File { file: content } = &entity.state.content {
        if let Some(reason) = file_block_reason(content) {
            return BotItemPlatform::Blocked { reason };
        }
        if let Some(DeliveryHalt::FilePreparation { revision, reason }) = &entity.state.halt
            && *revision == content.artifact.revision()
        {
            return BotItemPlatform::Blocked {
                reason: reason.platform_reason(),
            };
        }
    }
    if entity.state.file_operation.is_some() {
        let Some(DeliveryFileStage {
            operation_id,
            upload,
            message,
            local_stop,
        }) = file
        else {
            return BotItemPlatform::None {};
        };
        let outcome = file_outcome(&upload, &message, local_stop);
        return BotItemPlatform::File {
            operation_id: operation_id.clone(),
            content_revision: entity
                .state
                .file_operation
                .as_ref()
                .map(|binding| binding.artifact.revision())
                .unwrap_or(0),
            upload,
            message,
            outcome,
            local_stop,
        };
    }
    let operation = entity
        .state
        .in_flight
        .as_ref()
        .map(|intent| {
            (
                intent.operation_id.as_str(),
                intent.content_revision,
                intent.action.kind(),
                BotPlatformResult::InFlight {},
            )
        })
        .or_else(|| {
            entity.state.settled.as_ref().map(|settled| {
                (
                    settled.intent.operation_id.as_str(),
                    settled.intent.content_revision,
                    settled.intent.action.kind(),
                    platform_result(&settled.result),
                )
            })
        });
    match operation {
        Some((operation_id, content_revision, action, result)) => BotItemPlatform::Card {
            latest_operation: pl_protocol::studio::BotCardOperationSummary {
                operation_id: operation_id.to_string(),
                content_revision,
                action,
                result,
            },
        },
        None => BotItemPlatform::None {},
    }
}

/// 旧卡片操作到当前 typed 意图的迁移映射；材料缺失返回 `None`（调用方保留需恢复）。
pub(super) fn legacy_intent(
    operation: &CardOperation,
    chat_id: &str,
    card_id: Option<&str>,
    _platform_message_id: Option<&str>,
) -> Option<DeliveryIntent> {
    let action = legacy_action(&operation.action, card_id)?;
    let request = super::migrate::freeze_legacy_request(
        chat_id,
        &action,
        operation.sequence,
        &operation.uuid,
    )
    .ok()?;
    Some(DeliveryIntent {
        operation_id: format!("botcard:legacy:{}", operation.uuid),
        request_hash: request.hash().ok()?,
        request,
        legacy_action_hash: Some(operation.content_hash.clone()),
        content_revision: 0,
        integrity: BotTextIntegrity::Full,
        saved: false,
        sequence: operation.sequence,
        uuid: operation.uuid.clone(),
        created_at: 0,
        lease_generation: 0,
        owner_id: String::new(),
        action,
    })
}

fn legacy_action(action: &CardAction, card_id: Option<&str>) -> Option<DeliveryAction> {
    Some(match action {
        CardAction::Create { text } => DeliveryAction::CreateCard { text: text.clone() },
        CardAction::Send {} => DeliveryAction::SendCard {
            card_id: card_id?.to_string(),
        },
        CardAction::Content {
            text,
            final_content,
        } => DeliveryAction::UpdateContent {
            card_id: card_id?.to_string(),
            text: text.clone(),
            final_content: *final_content,
        },
        CardAction::Settings {
            streaming,
            lifecycle,
            recovery,
        } => {
            let card_id = card_id?.to_string();
            DeliveryAction::UpdateSettings {
                card_id,
                streaming: *streaming,
                lifecycle: *lifecycle,
                recovery: *recovery,
            }
        }
    })
}

pub(super) fn legacy_recovery(
    recovery: &CardRecovery,
    card_id: Option<&str>,
) -> Result<DeliveryCardRecovery, FeishuError> {
    Ok(DeliveryCardRecovery {
        action: legacy_action(&recovery.action, card_id).ok_or_else(unreadable)?,
        phase: recovery.phase,
    })
}

/// 已确认旧操作的结果；Intent 不能证明未启动，按 Unknown 保全。
pub(super) fn legacy_result(
    operation: &CardOperation,
    card_id: Option<&str>,
    platform_message_id: Option<&str>,
) -> Option<DeliveryResult> {
    Some(match operation.status {
        CardOperationStatus::Confirmed => match &operation.action {
            CardAction::Create { .. } => DeliveryResult::Created {
                card_id: card_id?.to_string(),
            },
            CardAction::Send {} => DeliveryResult::Sent {
                card_id: card_id?.to_string(),
                message_id: platform_message_id?.to_string(),
            },
            CardAction::Content { .. } => DeliveryResult::ContentAccepted {
                card_id: card_id?.to_string(),
            },
            CardAction::Settings { streaming, .. } => DeliveryResult::SettingsAccepted {
                card_id: card_id?.to_string(),
                streaming: *streaming,
            },
        },
        CardOperationStatus::Rejected => DeliveryResult::Rejected {
            diagnostic: operation
                .diagnostic
                .as_ref()
                .map(|diagnostic| diagnostic.message.clone())
                .unwrap_or_else(|| "the platform rejected the operation".to_string()),
        },
        CardOperationStatus::Unknown => DeliveryResult::Unknown {
            diagnostic: operation
                .diagnostic
                .as_ref()
                .map(|diagnostic| diagnostic.message.clone()),
        },
        // 迁移时原进程已不存在：无法证明未启动，只能按 Unknown 保全。
        CardOperationStatus::Intent => DeliveryResult::Unknown {
            diagnostic: Some(
                "a persisted card operation intent was never confirmed before migration"
                    .to_string(),
            ),
        },
    })
}

/// 结果与动作的种类/身份矩阵；不匹配保留原事实。
pub(in crate::bots) fn result_matches(
    action: &DeliveryAction,
    sequence: i32,
    result: &DeliveryResult,
) -> bool {
    let matched = match (action, result) {
        (DeliveryAction::CreateCard { .. }, DeliveryResult::Created { card_id }) => {
            !card_id.trim().is_empty()
        }
        (
            DeliveryAction::SendCard { card_id: card },
            DeliveryResult::Sent {
                card_id,
                message_id,
            },
        ) => card == card_id && !card_id.trim().is_empty() && !message_id.trim().is_empty(),
        (
            DeliveryAction::UpdateContent { card_id: card, .. },
            DeliveryResult::ContentAccepted { card_id },
        ) => card == card_id && !card_id.trim().is_empty(),
        (
            DeliveryAction::UpdateSettings {
                card_id: card,
                streaming,
                ..
            },
            DeliveryResult::SettingsAccepted {
                card_id,
                streaming: written,
            },
        ) => card == card_id && !card_id.trim().is_empty() && streaming == written,
        (
            _,
            DeliveryResult::NotStarted
            | DeliveryResult::Rejected { .. }
            | DeliveryResult::Unknown { .. },
        ) => true,
        _ => false,
    };
    // 已定居面的操作结果必须落在账本分配的序号上；Create/Send 不消费序号。
    let sequenced_ok = !action.sequenced() || sequence > 0;
    matched && sequenced_ok
}
