//! 独立投递账本：作用域、认领、恢复位置与实体操作材料。
//!
//! 只保存平台恢复必需的有界持久事实：作用域身份、独立认领、恢复位置、未完成项索引与
//! 实体操作材料。Session 仍是内容唯一事实源；文件阶段仍由既有 `send_operations` 持有；
//! GUI 摘要从本账本派生。所有类型仅在 `crate::bots` 内可见，消费者不得自行拼 SQL 或
//! 复制认领判定。
//!
//! 稳定身份不使用“冒号拼接后 split 反解”：作用域键与实体键都是 typed serde 编码的
//! `sha256:<64hex>` 摘要，行内同时保存完整 typed 身份并在每次解码时重算核对。

mod artifact;
mod card;
mod claim;
mod legacy;
mod legacy_request;
mod migrate;
mod ownership;
mod presentation;
mod records;
mod schema;
mod settlement;
mod store;

pub(in crate::bots) use artifact::{
    DeliveryFileBinding, SavedArtifact, delivery_file_plan_hash, delivery_file_request_hash,
};
pub(in crate::bots) use card::*;
pub(in crate::bots::storage) use claim::{LegacyScopeClosure, stop_legacy_scopes_in};
pub(in crate::bots) use migrate::migrate as migrate_schema;
pub(in crate::bots::storage) use migrate::preflight as preflight_migration;
pub(in crate::bots) use ownership::{DeliveryInputChain, DeliveryTurnIdentity, DeliveryTurnOwner};
pub(in crate::bots) use schema::validate as validate_schema;
pub(in crate::bots) use settlement::{
    ConfirmedDeliveryCardAttempt, DeliveryCardAdmission, DeliveryCardAttempt, MergeOutcome,
    SettlementOutcome,
};
pub(in crate::bots) use store::ensure_frontend_scope_in;
pub(in crate::bots) use store::{DeliveryEntityPage, DeliveryPendingPage, DeliveryScopePage};

use super::audience::Authorization;
use super::card::CardLifecycle;
use super::target::TargetProof;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::send::SendSource;
use pl_protocol::BotAuthorizationId;
use pl_protocol::studio::BotSendStopReason;
use pl_protocol::studio::{
    BotCardOperationKind, BotDiagnostic, BotFileBlockReason, BotFileOutcome, BotItemPlatform,
    BotItemPresentation, BotPlatformResult, BotPublicTextChannel, BotTextIntegrity,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// 独立投递归认领租约（秒）；owner 每 15 秒续约，续约把期限重置为完整租约。
pub(in crate::bots) const DELIVERY_CLAIM_TTL_SECONDS: i64 = 60;
pub(in crate::bots) const DELIVERY_CLAIM_RENEW_SECONDS: i64 = 15;
/// 单次有界读上限（作用域/实体/未完成项一致）。
pub(in crate::bots) const DELIVERY_READ_LIMIT: usize = 100;
/// 新文本正文的显示上限（Rust `char`）。
pub(in crate::bots) const DELIVERY_TEXT_CHARS: usize = 4_000;
/// 含宿主状态与截断说明的完整发送请求字节上限。
pub(in crate::bots) const DELIVERY_REQUEST_BYTES: usize = 30_000;

/// 投递作用域的稳定身份：持久身份，不是订阅 ID，也不伪造授权代次。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum DeliveryScopeKey {
    /// 完整前端：只引用原授权身份；phase/control/start 每次回读原授权事实。
    Frontend { authorization: BotAuthorizationId },
    /// 存量有限回复：原输入身份，不制造授权代次，也不伪造公开 item。
    LegacyFinal { inbound_identity: String },
}

impl DeliveryScopeKey {
    pub(in crate::bots) fn kind(&self) -> &'static str {
        match self {
            Self::Frontend { .. } => "frontend",
            Self::LegacyFinal { .. } => "legacyFinal",
        }
    }

    pub(in crate::bots) fn is_frontend(&self) -> bool {
        matches!(self, Self::Frontend { .. })
    }

    /// 账本稳定键：typed 编码的完整摘要，任意 ID 可含冒号。
    pub(in crate::bots) fn storage_key(&self) -> Result<String, FeishuError> {
        typed_digest(self)
    }

    /// 解码行内身份并核对稳定键：不做前缀/strip/split 反解。
    pub(in crate::bots) fn decode_stored(
        stored_key: &str,
        encoded: &str,
    ) -> Result<Self, FeishuError> {
        let key: Self = serde_json::from_str(encoded).map_err(|_| unreadable())?;
        if key.storage_key()? != stored_key {
            return Err(unreadable());
        }
        Ok(key)
    }
}

/// 作用域资格来源：两种范围各自保留自己的证明，不互相顶替。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum DeliveryScopeOrigin {
    /// 完整前端只引用原授权；不可变归属保存在范围列，phase/start 不另存副本。
    Frontend { authorization: BotAuthorizationId },
    /// 存量有限回复：原输入身份、原发送来源与创建期目标证明；缺失只记录需恢复原因。
    LegacyFinal { legacy: Box<LegacyFinalOrigin> },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct LegacyFinalOrigin {
    pub inbound_identity: String,
    pub original_input_id: String,
    pub watch_input: String,
    pub original_turn_id: Option<String>,
    pub source: Option<SendSource>,
    pub target: TargetProof,
    /// 迁移时的不可变受理资格，不取当前时钟补造。
    pub admission: Option<LegacyAdmission>,
    /// completed 的旧材料仍保留，但不是新待发义务。
    pub resumable: bool,
    pub needs_recovery: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct LegacyAdmission {
    pub content_hash: String,
    pub admitted_at: i64,
    pub status: String,
}

/// 作用域：不可变绑定事实 + 资格来源；创建后不再改写。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryScope {
    pub key: DeliveryScopeKey,
    pub bot_id: String,
    pub chat_id: String,
    pub thread_id: String,
    pub app_id: String,
    pub project_id: String,
    pub creation_id: String,
    pub binding_revision: u64,
    pub origin: DeliveryScopeOrigin,
    pub needs_recovery: bool,
}

/// 实体稳定身份；revision 是内容版本，绝不进入卡片或实体 key。
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) enum DeliveryEntityKey {
    TextItem {
        item_id: String,
    },
    PublicArtifact {
        item_id: String,
        publication_id: String,
    },
    /// 原实体身份（旧回复操作身份），不是新造公开 item。
    LegacyFinal {
        entity_id: String,
    },
}

impl DeliveryEntityKey {
    pub(in crate::bots) fn kind(&self) -> &'static str {
        match self {
            Self::TextItem { .. } => "textItem",
            Self::PublicArtifact { .. } => "publicArtifact",
            Self::LegacyFinal { .. } => "legacyFinal",
        }
    }

    pub(in crate::bots) fn item_id(&self) -> &str {
        match self {
            Self::TextItem { item_id } | Self::PublicArtifact { item_id, .. } => item_id,
            Self::LegacyFinal { entity_id } => entity_id,
        }
    }

    pub(in crate::bots) fn publication_id(&self) -> &str {
        match self {
            Self::PublicArtifact { publication_id, .. } => publication_id,
            _ => "",
        }
    }

    pub(in crate::bots) fn storage_key(&self) -> Result<String, FeishuError> {
        typed_digest(self)
    }

    pub(in crate::bots) fn decode_stored(
        stored_key: &str,
        encoded: &str,
    ) -> Result<Self, FeishuError> {
        let key: Self = serde_json::from_str(encoded).map_err(|_| unreadable())?;
        if key.storage_key()? != stored_key {
            return Err(unreadable());
        }
        Ok(key)
    }
}

/// 独立投递认领身份：owner + 单调租约代次 + 工作时序版本 + 期限。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryClaimToken {
    pub scope: DeliveryScopeKey,
    pub owner_id: String,
    pub lease_generation: u64,
    pub work_version: u64,
    pub authorization_revision: u64,
    pub expires_at: i64,
}

/// 认领/续约的 typed 结果；Busy/Stopped/Missing/LostClaim 不从诊断猜。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) enum DeliveryClaimOutcome {
    Acquired(DeliveryClaimToken),
    Busy {
        expires_at: i64,
    },
    /// 本次不能认领（PendingStart/Paused/已封闭/需恢复）。**不是**持久关闭结论：
    /// 消费者只能按原 typed 授权与变更通知恢复，不解析 `reason` 文案，也不据此删除义务。
    /// 只有 `stop_delivery_scope` 表达确定的封闭/需处理。
    Stopped {
        reason: String,
    },
    Missing,
    LostClaim,
}

/// 未完成项索引中的一条实体修订。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryPendingRevision {
    pub entity: DeliveryEntityKey,
    pub item_order: Option<u64>,
    pub item_revision: u64,
}

/// 恢复位置扫描水位；未完成项索引独立存表，不用最大序号代替修订跟踪。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryCursor {
    pub scope: DeliveryScopeKey,
    pub order_watermark: u64,
    pub updated_at: i64,
}

/// canonical 文本内容：有界展示正文 + 精确完整请求预算证明。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryText {
    pub channel: BotPublicTextChannel,
    pub revision: u64,
    pub integrity: BotTextIntegrity,
    pub saved: bool,
    pub body: String,
    pub body_chars: u64,
    pub request_bytes: u64,
}

/// canonical 文件内容；文件永不为 Truncated。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryFile {
    pub artifact: SavedArtifact,
}

/// 旧有限回复的新 canonical 呈现证明；不借用公开 item 的身份或 revision。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryLegacyCandidate {
    pub turn_id: String,
    pub input_chain: DeliveryInputChain,
    pub body: String,
    pub integrity: BotTextIntegrity,
    pub saved: bool,
    pub request_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryLegacyPresentation {
    pub turn_id: String,
    pub body: String,
    pub integrity: BotTextIntegrity,
    pub saved: bool,
    pub request_bytes: u64,
}

/// 实体内容 union：文本 / 文件 / 旧有限回复 / 不可证材料。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(in crate::bots) enum DeliveryContent {
    Text {
        text: DeliveryText,
    },
    File {
        file: DeliveryFile,
    },
    Removed {
        revision: u64,
    },
    /// 旧回复只有原输入/续接的 Final 资格，卡片材料在 `DeliveryEntityState::card`。
    Legacy {
        final_only: bool,
        /// 旧材料没有新的 canonical 证明；缺字段只能保守读作 None。
        #[serde(default)]
        presentation: Option<DeliveryLegacyPresentation>,
    },
    /// 来源不足：保留已知原材料与需恢复原因，不虚构 item 种类、order 或 canonical revision。
    Unresolved {
        unresolved: DeliveryUnresolved,
    },
}

impl DeliveryContent {
    pub(in crate::bots) fn revision(&self) -> u64 {
        match self {
            Self::Text { text } => text.revision,
            Self::File { file } => file.artifact.revision(),
            Self::Removed { revision } => *revision,
            Self::Legacy { .. } | Self::Unresolved { .. } => 0,
        }
    }

    pub(in crate::bots) fn kind(&self) -> &'static str {
        match self {
            Self::Text { .. } => "textItem",
            Self::File { .. } => "publicArtifact",
            Self::Removed { .. } => "removed",
            Self::Legacy { .. } => "legacyFinal",
            Self::Unresolved { .. } => "unresolved",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum DeliveryRecoveryReason {
    /// 旧九号观察行：canonical 顺序、revision 与正文无法证明。
    LegacyObservation,
    /// 旧卡片或未完成入站的来源链不足。
    LegacyUnprovable,
    /// 规范读取暂时不可用。
    CanonicalUnavailable,
}

/// 不可证材料的当前 typed 形式：保留真实已知段落，明确需恢复。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryUnresolved {
    pub reason: DeliveryRecoveryReason,
    pub observation: Option<pl_protocol::studio::BotItemLedgerSummary>,
    pub removed: bool,
    pub pending: bool,
    pub incomplete: bool,
    pub detail: String,
}

/// 实体持久状态：内容 + 平台观察 + 至多一个未结算操作 + 恢复材料引用。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryEntityState {
    pub content: DeliveryContent,
    /// 平台已投影的呈现（不是 canonical 正文事实）。
    pub projected: BotItemPresentation,
    /// 与具体 revision 绑定的已接受呈现。
    pub accepted: BotItemPresentation,
    pub card: DeliveryCard,
    /// 文件稳定 send-operation 引用；阶段事实仍由原账本持有。
    pub file_operation: Option<DeliveryFileBinding>,
    pub in_flight: Option<DeliveryIntent>,
    pub settled: Option<DeliverySettled>,
    pub halt: Option<DeliveryHalt>,
}

impl DeliveryEntityState {
    /// 准备失败不能覆盖任何已登记的网络材料，包括旧修订的已知结果。
    pub(super) fn has_network_history(&self) -> bool {
        self.has_operation_material() || self.card != DeliveryCard::default()
    }

    fn has_operation_material(&self) -> bool {
        self.file_operation.is_some()
            || self.in_flight.is_some()
            || self.settled.is_some()
            || self.projected != (BotItemPresentation::None {})
            || self.accepted != (BotItemPresentation::None {})
    }

    /// lifecycle 与 typed 本地终局本身不是网络事实；其它任何卡片材料仍使本地结束失格。
    pub(super) fn has_legacy_network_history(&self) -> bool {
        self.has_operation_material()
            || self.card
                != (DeliveryCard {
                    lifecycle: self.card.lifecycle,
                    legacy_local_completion: self.card.legacy_local_completion,
                    ..DeliveryCard::default()
                })
    }
}

/// 实体：稳定身份 + canonical 身份事实 + typed 状态。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryEntity {
    pub scope: DeliveryScopeKey,
    pub entity: DeliveryEntityKey,
    pub turn_id: Option<String>,
    /// 规范顺序；`None` 表示不可证（旧格式或来源不足），不虚构 0。
    pub item_order: Option<u64>,
    pub saved: bool,
    pub removed: bool,
    pub state: DeliveryEntityState,
    pub ledger_version: u64,
    pub updated_at: i64,
}

impl DeliveryEntity {
    pub(in crate::bots) fn revision(&self) -> u64 {
        self.state.content.revision()
    }
}

/// canonical 候选内容：只允许更新规范事实，不允许携带平台结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) enum DeliveryCandidateContent {
    Text {
        channel: BotPublicTextChannel,
        revision: u64,
        integrity: BotTextIntegrity,
        saved: bool,
        body: String,
        request_bytes: u64,
    },
    File {
        artifact: SavedArtifact,
    },
    Removed {
        revision: u64,
    },
}

impl DeliveryCandidateContent {
    fn revision(&self) -> u64 {
        match self {
            Self::Text { revision, .. } | Self::Removed { revision } => *revision,
            Self::File { artifact } => artifact.revision(),
        }
    }
}

/// 一次 canonical 合并；accepted/confirmed/in_flight 不在候选里，调用方无法覆盖。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryCandidate {
    pub entity: DeliveryEntityKey,
    pub turn_id: String,
    pub item_order: u64,
    /// O 从规范 input/continuation 事实取得完整关联；未知不能放行。
    pub input_chain: DeliveryInputChain,
    pub content: DeliveryCandidateContent,
}

/// 派生标志：与状态同事务重算，仅供有界计数与索引使用，不反向充当操作授权。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::bots) struct DeliveryFlags {
    pub delivered: bool,
    pub removed: bool,
    pub incomplete: bool,
    pub attention: bool,
    pub unknown: bool,
}

impl DeliveryFlags {
    /// 未完成：既不完整、也未被平台接受，也未被明确拒绝/未知终止。
    pub(in crate::bots) fn pending(self) -> bool {
        !self.delivered && !self.removed && !self.incomplete && !self.attention && !self.unknown
    }
}

pub(in crate::bots) fn derive_flags(removed: bool, state: &DeliveryEntityState) -> DeliveryFlags {
    let halted = state.halt.is_some()
        || state.card.lifecycle == Some(CardLifecycle::NeedsAttention)
        || matches!(&state.content,DeliveryContent::File { file } if file_block_reason(file).is_some());
    let incomplete = matches!(state.content, DeliveryContent::Unresolved { .. });
    // 恢复资格与已开始请求的结果正交：Unresolved 既可能仅有旧观察，也可能保留
    // 完整旧卡片操作。来源不足不能把后者的 Unknown 隐藏成零次未知。
    let unknown = matches!(state.halt, Some(DeliveryHalt::Unknown { .. }))
        || match &state.content {
            DeliveryContent::Unresolved { unresolved } => unresolved
                .observation
                .as_ref()
                .is_some_and(|summary| platform_unknown_count(&summary.platform) > 0),
            _ => false,
        };
    let delivered = if removed {
        true
    } else if incomplete || halted || state.in_flight.is_some() {
        false
    } else {
        match &state.content {
            DeliveryContent::Text { text } => {
                accepted_revision(&state.accepted) == Some(text.revision)
            }
            DeliveryContent::File { file } => {
                state.file_operation.is_some()
                    && accepted_revision(&state.accepted) == Some(file.artifact.revision())
            }
            DeliveryContent::Legacy { .. } => {
                state.card.lifecycle.is_some_and(CardLifecycle::terminal)
            }
            DeliveryContent::Removed { .. } => true,
            DeliveryContent::Unresolved { .. } => false,
        }
    };
    DeliveryFlags {
        delivered,
        removed,
        incomplete,
        attention: halted || incomplete,
        unknown,
    }
}

fn accepted_revision(presentation: &BotItemPresentation) -> Option<u64> {
    match presentation {
        BotItemPresentation::None {} => None,
        BotItemPresentation::Text { revision, .. } | BotItemPresentation::File { revision } => {
            Some(*revision)
        }
    }
}

/// 有界校验：新文本正文 4000 Rust char、完整请求 30000B、完整性是已知值。
pub(in crate::bots) fn validate_text(text: &DeliveryText) -> Result<(), FeishuError> {
    let chars = text.body.chars().count();
    if text.revision == 0 || u64::try_from(chars).ok() != Some(text.body_chars) {
        return Err(rejected("delivery text exceeds the presentation budget"));
    }
    validate_body_budget(&text.body, text.request_bytes)
}

pub(super) fn validate_body_budget(body: &str, request_bytes: u64) -> Result<(), FeishuError> {
    if body.chars().count() > DELIVERY_TEXT_CHARS
        || request_bytes > DELIVERY_REQUEST_BYTES as u64
        || !body.is_empty() && request_bytes == 0
    {
        return Err(rejected("delivery text exceeds the presentation budget"));
    }
    Ok(())
}

pub(super) fn validate_legacy_presentation(
    presentation: &DeliveryLegacyPresentation,
) -> Result<(), FeishuError> {
    if presentation.turn_id.is_empty() {
        return Err(rejected("legacy presentation requires its canonical Turn"));
    }
    validate_body_budget(&presentation.body, presentation.request_bytes)
}

pub(in crate::bots) fn validate_entity_state(
    entity: &DeliveryEntityKey,
    state: &DeliveryEntityState,
) -> Result<(), FeishuError> {
    match (&state.content, entity) {
        (DeliveryContent::Text { text }, DeliveryEntityKey::TextItem { .. }) => validate_text(text),
        (
            DeliveryContent::File { file },
            DeliveryEntityKey::PublicArtifact { publication_id, .. },
        ) if publication_id == file.artifact.publication_id()
            && entity.item_id() == file.artifact.item_id() =>
        {
            file.artifact.validate()
        }
        (
            DeliveryContent::Removed { revision },
            DeliveryEntityKey::TextItem { .. } | DeliveryEntityKey::PublicArtifact { .. },
        ) if *revision > 0 => Ok(()),
        (
            DeliveryContent::Legacy {
                final_only,
                presentation,
            },
            DeliveryEntityKey::LegacyFinal { .. },
        ) => {
            if !final_only {
                return Err(unreadable());
            }
            match presentation {
                Some(presentation) => validate_legacy_presentation(presentation),
                None => Ok(()),
            }
        }
        (DeliveryContent::Unresolved { .. }, _) => Ok(()),
        _ => Err(unreadable()),
    }
}

/// GUI 保留的旧观察只作观察，不能反向授予网络资格。
pub(in crate::bots) fn platform_unknown_count(platform: &BotItemPlatform) -> u64 {
    match platform {
        BotItemPlatform::Card { latest_operation } => u64::from(matches!(
            latest_operation.result,
            BotPlatformResult::Unknown { .. }
        )),
        BotItemPlatform::File {
            upload, message, ..
        } => {
            u64::from(matches!(upload, BotPlatformResult::Unknown { .. }))
                + u64::from(matches!(message, BotPlatformResult::Unknown { .. }))
        }
        _ => 0,
    }
}

/// 账本不可读：保留现场，要求本机恢复，不当成临时 IO。
pub(in crate::bots) fn unreadable() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot delivery ledger is unreadable or inconsistent; local recovery required",
        false,
        None,
    )
}

/// 同 identity 不同内容：固定冲突，不覆盖。
pub(in crate::bots) fn conflict() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot delivery identity already carries different content",
        false,
        None,
    )
}

/// 认领/授权/作用域已不允许该写入：不发起新副作用，也不抹掉已启动结果。
pub(in crate::bots) fn fenced() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot delivery claim or authorization no longer permits this write",
        false,
        None,
    )
}

pub(in crate::bots) fn rejected(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Rejected, message, false, None)
}

/// 授权侧新写许可：只有 Active（已保存起点）才允许新的平台写入。
pub(in crate::bots) fn authorization_active(auth: &Authorization) -> bool {
    auth.phase == pl_protocol::studio::BotAuthorizationPhase::Active && auth.start.is_some()
}

pub(in crate::bots) fn typed_digest<T: Serialize>(value: &T) -> Result<String, FeishuError> {
    let bytes = serde_json::to_vec(value).map_err(|_| unreadable())?;
    Ok(format!("sha256:{}", hex::encode(Sha256::digest(&bytes))))
}
