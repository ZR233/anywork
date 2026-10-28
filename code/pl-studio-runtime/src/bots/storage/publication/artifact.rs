//! Saved 公开文件的窄证明及原发送账本绑定。资源引用本身不授予外发资格。

use super::*;
use crate::studio::TimelineItemMetadata;
use pl_protocol::{ThreadItemState, TimelineLifecycle};
use sea_orm::ConnectionTrait;

/// 只能由 canonical metadata 构造；保存的是精确 producer/item/revision，不是 caller bool。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct SavedArtifact {
    thread_id: String,
    turn_id: String,
    item_id: String,
    item_order: u64,
    revision: u64,
    publication_id: String,
    tool_call_id: String,
    resource: pl_protocol::ThreadArtifactResource,
    display_name: String,
}

impl SavedArtifact {
    /// 必须传 `TimelineContentReader::read_metadata` 的完整 Present 值，不能从 ThreadItem
    /// 或工具回执推定 Saved。未保存/非终态/非公开文件均拒绝，不改变本地原件。
    pub(in crate::bots) fn from_metadata(
        metadata: &TimelineItemMetadata,
    ) -> Result<Self, FeishuError> {
        let shell = &metadata.shell;
        let ThreadItemState::PublicArtifact(artifact) = shell.state() else {
            return Err(rejected(
                "only a canonical PublicArtifact can authorize file delivery",
            ));
        };
        if !metadata.saved || metadata.lifecycle != TimelineLifecycle::Terminal {
            return Err(rejected(
                "public artifact is not durably saved and terminal",
            ));
        }
        let proof = Self {
            thread_id: shell.thread_id.clone(),
            turn_id: shell.turn_id.clone(),
            item_id: shell.id.clone(),
            item_order: shell.ordinal,
            revision: shell.revision,
            publication_id: artifact.publication_id.clone(),
            tool_call_id: artifact.tool_call_id.clone(),
            resource: artifact.resource.clone(),
            display_name: artifact.display_name.clone(),
        };
        proof.validate()?;
        Ok(proof)
    }

    pub(in crate::bots) fn validate(&self) -> Result<(), FeishuError> {
        if [
            &self.thread_id,
            &self.turn_id,
            &self.item_id,
            &self.publication_id,
            &self.tool_call_id,
            &self.display_name,
        ]
        .iter()
        .any(|id| id.is_empty())
            || self.item_order == 0
            || self.revision == 0
            || self.revision > i64::MAX as u64
            || self.item_order > i64::MAX as u64
            || self.resource.byte_len > 50 * 1024 * 1024
        {
            return Err(rejected(
                "public artifact proof has an invalid canonical identity",
            ));
        }
        pl_core::context::ResourceReference::new(
            self.resource.id.clone(),
            self.resource.content_digest.clone(),
            self.resource.byte_len,
            self.resource.media_type.clone(),
        )
        .map_err(|_| rejected("public artifact proof has an invalid resource"))?;
        Ok(())
    }

    pub(in crate::bots) fn thread_id(&self) -> &str {
        &self.thread_id
    }
    pub(in crate::bots) fn turn_id(&self) -> &str {
        &self.turn_id
    }
    pub(in crate::bots) fn item_id(&self) -> &str {
        &self.item_id
    }
    pub(in crate::bots) fn item_order(&self) -> u64 {
        self.item_order
    }
    pub(in crate::bots) fn revision(&self) -> u64 {
        self.revision
    }
    pub(in crate::bots) fn publication_id(&self) -> &str {
        &self.publication_id
    }
    pub(in crate::bots) fn tool_call_id(&self) -> &str {
        &self.tool_call_id
    }
    pub(in crate::bots) fn resource(&self) -> &pl_protocol::ThreadArtifactResource {
        &self.resource
    }
    pub(in crate::bots) fn display_name(&self) -> &str {
        &self.display_name
    }

    pub(in crate::bots) fn entity_key(&self) -> DeliveryEntityKey {
        DeliveryEntityKey::PublicArtifact {
            item_id: self.item_id.clone(),
            publication_id: self.publication_id.clone(),
        }
    }
}

/// 原发送操作绑定的固定 revision 与 producer/resource；后来修订不能冒充这次发送。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryFileBinding {
    pub operation_id: String,
    pub artifact: SavedArtifact,
    pub content_hash: String,
    pub uuid: String,
}

/// F 构造自动前端 SendPlan 时与 bind 使用同一请求指纹。此入口不读取或归档资源。
pub(in crate::bots) fn delivery_file_request_hash(
    scope: &DeliveryScope,
    entity: &DeliveryEntityKey,
    artifact: &SavedArtifact,
) -> Result<String, FeishuError> {
    artifact.validate()?;
    if !scope.key.is_frontend()
        || scope.thread_id != artifact.thread_id()
        || *entity != artifact.entity_key()
    {
        return Err(conflict());
    }
    typed_digest(&(
        "frontend-public-artifact",
        &scope.key,
        &scope.bot_id,
        &scope.chat_id,
        &scope.thread_id,
        &scope.app_id,
        &scope.project_id,
        &scope.creation_id,
        scope.binding_revision,
        entity,
        artifact,
    ))
}

/// F 的自动 plan 必须使用这个完整指纹（source=None），不能套用主动工具的 source hash。
pub(in crate::bots) fn delivery_file_plan_hash(
    scope: &DeliveryScope,
    entity: &DeliveryEntityKey,
    artifact: &SavedArtifact,
    operation_id: &str,
    segments: &[crate::bots::send::SendContent],
) -> Result<String, FeishuError> {
    if operation_id.is_empty() {
        return Err(conflict());
    }
    typed_digest(&(
        "frontend-file-plan",
        operation_id,
        &scope.bot_id,
        &scope.chat_id,
        delivery_file_request_hash(scope, entity, artifact)?,
        segments,
    ))
}

pub(super) async fn verify_send<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScope,
    entity: &DeliveryEntityKey,
    operation_id: &str,
    artifact: &SavedArtifact,
) -> Result<DeliveryFileBinding, FeishuError> {
    use super::super::{send_record_from_row, statement};
    use crate::bots::send::{SendContent, SendIdentity};
    let row = db.query_one_raw(statement("SELECT operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,segment_facts,send_identity,send_source FROM send_operations WHERE operation_id=?", vec![operation_id.to_string().into()])).await.map_err(super::store::storage)?.ok_or_else(unreadable)?;
    let record = send_record_from_row(row)?;
    if record.operation_id != operation_id
        || record.bot_id != scope.bot_id
        || record.chat_id != scope.chat_id
        || record.source.is_some()
        || !record.facts_complete
        || record.segments.len() != 1
        || record.identity
            != (SendIdentity::File {
                request_hash: delivery_file_request_hash(scope, entity, artifact)?,
            })
    {
        return Err(conflict());
    }
    let segment = &record.segments[0];
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
        artifact.display_name().to_string()
    };
    // 与既有 send::send_uuid 相同的 typed 单文件身份；该 helper 当前是发送模块私有。
    let uuid_digest = typed_digest(&(operation_id, &scope.bot_id, &scope.chat_id, 0_usize))?;
    let expected_uuid = uuid_digest
        .strip_prefix("sha256:")
        .ok_or_else(unreadable)?
        .get(..32)
        .ok_or_else(unreadable)?;
    if segment.upload.is_none()
        || segment.message_stage.is_none()
        || segment.index != 0
        || segment.uuid != expected_uuid
        || filename != artifact.display_name()
        || *upload_filename != expected_upload
        || resource.content_digest() != artifact.resource.content_digest
        || resource.byte_len() != artifact.resource.byte_len
        || resource.media_type() != artifact.resource.media_type
        || record.content_hash
            != delivery_file_plan_hash(
                scope,
                entity,
                artifact,
                operation_id,
                std::slice::from_ref(content),
            )?
    {
        return Err(conflict());
    }
    resource.validate().map_err(|_| unreadable())?;
    Ok(DeliveryFileBinding {
        operation_id: operation_id.to_string(),
        artifact: artifact.clone(),
        content_hash: record.content_hash,
        uuid: segment.uuid.clone(),
    })
}
