//! 当前作用域、实体与双向恢复索引：同一套即时与重开校验，不补造缺失事实。
use super::super::{audience, statement, stored_i64, strict_text};
use super::store::storage;
use super::*;
use crate::studio::unix_seconds;
use sea_orm::{ConnectionTrait, QueryResult, Value};

pub(super) async fn cursor_exists<C: ConnectionTrait>(
    db: &C,
    key: &DeliveryScopeKey,
) -> Result<bool, FeishuError> {
    Ok(db
        .query_one_raw(statement(
            "SELECT 1 AS present FROM bot_delivery_cursors WHERE scope_key=?",
            vec![key.storage_key()?.into()],
        ))
        .await
        .map_err(storage)?
        .is_some())
}

/// 恢复索引是完整性约束，不是可随读重建的缓存。只查本 scope，正常读写也拒绝缺行。
pub(super) async fn validate_scope_indexes<C: ConnectionTrait>(
    db: &C,
    key: &DeliveryScopeKey,
) -> Result<(), FeishuError> {
    let key = key.storage_key()?;
    let row = db
        .query_one_raw(statement(
            "SELECT order_watermark,updated_at FROM bot_delivery_cursors WHERE scope_key=?",
            vec![key.clone().into()],
        ))
        .await
        .map_err(storage)?
        .ok_or_else(unreadable)?;
    if stored_i64(&row, "order_watermark")? < 0 || stored_i64(&row, "updated_at")? < 0 {
        return Err(unreadable());
    }
    let inconsistent = db.query_one_raw(statement(
        "SELECT 1 FROM bot_delivery_items i LEFT JOIN bot_delivery_pending p
           ON p.scope_key=i.scope_key AND p.entity_key=i.entity_key
         WHERE i.scope_key=?1 AND (
           (p.entity_key IS NOT NULL) <> (i.delivered=0 AND i.removed=0 AND i.incomplete=0 AND i.attention=0 AND i.unknown=0)
           OR (p.entity_key IS NOT NULL AND (p.item_order<>i.item_order OR p.item_revision<>i.item_revision)))
         UNION ALL SELECT 1 FROM bot_delivery_pending p LEFT JOIN bot_delivery_items i
           ON p.scope_key=i.scope_key AND p.entity_key=i.entity_key
         WHERE p.scope_key=?1 AND i.entity_key IS NULL LIMIT 1", vec![key.into()])).await.map_err(storage)?;
    if inconsistent.is_some() {
        return Err(unreadable());
    }
    Ok(())
}

pub(super) fn validate_entity(entity: &DeliveryEntity) -> Result<(), FeishuError> {
    super::validate_entity_state(&entity.entity, &entity.state)?;
    if [
        entity.state.card.card_id.as_deref(),
        entity.state.card.platform_message_id.as_deref(),
    ]
    .into_iter()
    .flatten()
    .any(|id| id.trim().is_empty())
    {
        return Err(unreadable());
    }
    if entity.entity.item_id().is_empty()
        || entity.ledger_version == 0
        || entity.ledger_version > i64::MAX as u64
        || entity.turn_id.as_deref().is_some_and(str::is_empty)
        || entity.item_order == Some(0)
        || entity
            .item_order
            .is_some_and(|value| value > i64::MAX as u64)
        || entity.revision() > i64::MAX as u64
    {
        return Err(unreadable());
    }
    match &entity.state.content {
        DeliveryContent::Text { text } => {
            if entity.turn_id.is_none()
                || entity.item_order.is_none()
                || text.saved != entity.saved
                || entity.removed
            {
                return Err(unreadable());
            }
        }
        DeliveryContent::File { file } => {
            if entity.turn_id.as_deref() != Some(file.artifact.turn_id())
                || entity.item_order != Some(file.artifact.item_order())
                || !entity.saved
                || entity.removed
            {
                return Err(unreadable());
            }
        }
        DeliveryContent::Removed { .. } => {
            if !entity.removed || entity.turn_id.is_none() || entity.item_order.is_none() {
                return Err(unreadable());
            }
        }
        DeliveryContent::Legacy { .. } => {
            if entity.scope.is_frontend() || entity.item_order.is_some() {
                return Err(unreadable());
            }
        }
        DeliveryContent::Unresolved { .. } => {}
    }
    if let Some(reason) = entity.state.card.legacy_local_completion
        && (entity.scope.is_frontend()
            || !matches!(entity.state.content, DeliveryContent::Legacy { .. })
            || entity.state.card.lifecycle != Some(reason.lifecycle())
            || entity.state.has_legacy_network_history()
            || entity.state.halt.is_some())
    {
        return Err(unreadable());
    }
    if let Some(binding) = &entity.state.file_operation {
        binding.artifact.validate()?;
        if binding.operation_id.is_empty()
            || binding.content_hash.is_empty()
            || binding.uuid.is_empty()
            || binding.artifact.entity_key() != entity.entity
            || binding.artifact.revision() > entity.revision()
        {
            return Err(unreadable());
        }
    }
    if let Some(DeliveryHalt::FilePreparation { revision, .. }) = &entity.state.halt
        && (!entity.scope.is_frontend()
            || !matches!(&entity.state.content, DeliveryContent::File { file } if file.artifact.revision() == *revision)
            || entity.state.has_network_history())
    {
        return Err(unreadable());
    }
    if entity.state.in_flight.is_some() && entity.state.halt.is_some() {
        return Err(unreadable());
    }
    for intent in entity
        .state
        .in_flight
        .iter()
        .chain(entity.state.settled.iter().map(|settled| &settled.intent))
    {
        intent.request.validate_for_action(&intent.action)?;
        if intent.operation_id.is_empty()
            || intent.uuid.is_empty()
            || intent.request.hash()? != intent.request_hash
            || intent.sequence < 0
            || (intent.action.sequenced() && intent.sequence == 0)
            || intent.sequence > entity.state.card.sequence
        {
            return Err(unreadable());
        }
    }
    if let Some(settled) = &entity.state.settled
        && !super::result_matches(
            &settled.intent.action,
            settled.intent.sequence,
            &settled.result,
        )
    {
        return Err(unreadable());
    }
    if entity.state.card.confirmed_sequence < 0
        || entity.state.card.confirmed_sequence > entity.state.card.sequence
    {
        return Err(unreadable());
    }
    Ok(())
}

/// 作用域行写入：迁移与新建共用；重复身份由主键拒绝。
pub(in crate::bots::storage) async fn insert_scope_row<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScope,
) -> anyhow::Result<()> {
    let origin = serde_json::to_string(&scope.origin)?;
    db.execute_raw(statement(
        "INSERT INTO bot_delivery_scopes
           (scope_key,scope_json,kind,bot_id,chat_id,thread_id,app_id,project_id,creation_id,
            binding_revision,origin_json,needs_recovery,created_at,updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        vec![
            scope.key.storage_key()?.into(),
            serde_json::to_string(&scope.key)?.into(),
            scope.key.kind().into(),
            scope.bot_id.clone().into(),
            scope.chat_id.clone().into(),
            scope.thread_id.clone().into(),
            scope.app_id.clone().into(),
            scope.project_id.clone().into(),
            scope.creation_id.clone().into(),
            i64::try_from(scope.binding_revision)
                .map_err(|_| unreadable())?
                .into(),
            origin.into(),
            i64::from(scope.needs_recovery).into(),
            unix_seconds().into(),
            unix_seconds().into(),
        ],
    ))
    .await?;
    Ok(())
}

pub(in crate::bots::storage) async fn insert_cursor_row<C: ConnectionTrait>(
    db: &C,
    key: &DeliveryScopeKey,
) -> anyhow::Result<()> {
    db.execute_raw(statement(
        "INSERT INTO bot_delivery_cursors(scope_key,order_watermark,updated_at) VALUES(?,0,?)",
        vec![key.storage_key()?.into(), unix_seconds().into()],
    ))
    .await?;
    Ok(())
}

pub(in crate::bots::storage) async fn insert_entity_row<C: ConnectionTrait>(
    db: &C,
    entity: &DeliveryEntity,
) -> anyhow::Result<()> {
    let mut values = entity_values(entity)?;
    db.execute_raw(statement(
        "INSERT INTO bot_delivery_items
           (scope_key,entity_key,entity_json,kind,item_id,publication_id,turn_id,item_order,
            item_revision,saved,removed,delivered,incomplete,attention,unknown,state_json,
            ledger_version,updated_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        std::mem::take(&mut values),
    ))
    .await?;
    Ok(())
}

pub(in crate::bots::storage) async fn read_scope<C: ConnectionTrait>(
    db: &C,
    key: &DeliveryScopeKey,
) -> Result<Option<DeliveryScope>, FeishuError> {
    let scope = db
        .query_one_raw(statement(
            "SELECT * FROM bot_delivery_scopes WHERE scope_key=?",
            vec![key.storage_key()?.into()],
        ))
        .await
        .map_err(storage)?
        .as_ref()
        .map(decode_scope_row)
        .transpose()?;
    if let Some(scope) = &scope {
        validate_scope_indexes(db, key).await?;
        match &scope.key {
            DeliveryScopeKey::LegacyFinal { .. } => super::legacy::validate(db, scope).await?,
            DeliveryScopeKey::Frontend { authorization } => {
                let auth = audience::load_auth(db, authorization)
                    .await?
                    .ok_or_else(unreadable)?;
                let origin = audience::read_origin(db, &scope.thread_id)
                    .await?
                    .ok_or_else(unreadable)?;
                if scope.bot_id != authorization.bot_id
                    || scope.chat_id != authorization.chat_id
                    || scope.app_id != auth.app_id
                    || scope.thread_id != auth.intent.thread_id
                    || scope.project_id != auth.project_id
                    || scope.creation_id != auth.creation_id
                    || scope.binding_revision != auth.intent.binding_revision
                    || origin.chat_id != scope.chat_id
                    || origin.project_id != scope.project_id
                    || origin.creation_id != scope.creation_id
                    || origin.binding_revision != scope.binding_revision
                {
                    return Err(unreadable());
                }
            }
        }
    }
    Ok(scope)
}

pub(in crate::bots::storage) fn decode_scope_row(
    row: &QueryResult,
) -> Result<DeliveryScope, FeishuError> {
    let key = DeliveryScopeKey::decode_stored(
        &strict_text(row, "scope_key")?,
        &strict_text(row, "scope_json")?,
    )?;
    let origin: DeliveryScopeOrigin =
        serde_json::from_str(&strict_text(row, "origin_json")?).map_err(|_| unreadable())?;
    let matches = matches!(
        (&key, &origin),
        (
            DeliveryScopeKey::Frontend { authorization },
            DeliveryScopeOrigin::Frontend {
                authorization: origin
            }
        ) if authorization == origin
    ) || matches!(
        (&key, &origin),
        (
            DeliveryScopeKey::LegacyFinal { inbound_identity },
            DeliveryScopeOrigin::LegacyFinal { legacy }
        ) if inbound_identity == &legacy.inbound_identity
    );
    if !matches || key.kind() != strict_text(row, "kind")? {
        return Err(unreadable());
    }
    let needs_recovery = match stored_i64(row, "needs_recovery")? {
        0 => false,
        1 => true,
        _ => return Err(unreadable()),
    };
    Ok(DeliveryScope {
        key,
        bot_id: strict_text(row, "bot_id")?,
        chat_id: strict_text(row, "chat_id")?,
        thread_id: strict_text(row, "thread_id")?,
        app_id: strict_text(row, "app_id")?,
        project_id: strict_text(row, "project_id")?,
        creation_id: strict_text(row, "creation_id")?,
        binding_revision: u64::try_from(stored_i64(row, "binding_revision")?)
            .map_err(|_| unreadable())?,
        origin,
        needs_recovery,
    })
}

pub(in crate::bots::storage) fn decode_entity_row(
    scope: &DeliveryScopeKey,
    row: &QueryResult,
) -> Result<DeliveryEntity, FeishuError> {
    let entity = DeliveryEntityKey::decode_stored(
        &strict_text(row, "entity_key")?,
        &strict_text(row, "entity_json")?,
    )?;
    let state: DeliveryEntityState =
        serde_json::from_str(&strict_text(row, "state_json")?).map_err(|_| unreadable())?;
    let decoded = DeliveryEntity {
        scope: scope.clone(),
        entity,
        turn_id: super::super::empty_to_none(strict_text(row, "turn_id")?),
        item_order: match stored_i64(row, "item_order")? {
            -1 => None,
            value if value >= 0 => Some(u64::try_from(value).map_err(|_| unreadable())?),
            _ => return Err(unreadable()),
        },
        saved: stored_i64(row, "saved")? != 0,
        removed: stored_i64(row, "removed")? != 0,
        state,
        ledger_version: u64::try_from(stored_i64(row, "ledger_version")?)
            .map_err(|_| unreadable())?,
        updated_at: stored_i64(row, "updated_at")?,
    };
    validate_entity(&decoded)?;
    let flags = derive_flags(decoded.removed, &decoded.state);
    if strict_text(row, "scope_key")? != scope.storage_key()?
        || strict_text(row, "kind")? != decoded.entity.kind()
        || strict_text(row, "item_id")? != decoded.entity.item_id()
        || strict_text(row, "publication_id")? != decoded.entity.publication_id()
        || u64::try_from(stored_i64(row, "item_revision")?).map_err(|_| unreadable())?
            != decoded.revision()
        || [
            "saved",
            "removed",
            "delivered",
            "incomplete",
            "attention",
            "unknown",
        ]
        .iter()
        .zip([
            decoded.saved,
            decoded.removed,
            flags.delivered,
            flags.incomplete,
            flags.attention,
            flags.unknown,
        ])
        .any(|(column, expected)| stored_i64(row, column).ok() != Some(i64::from(expected)))
    {
        return Err(unreadable());
    }
    Ok(decoded)
}

pub(in crate::bots::storage) async fn read_entity<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScopeKey,
    entity: &DeliveryEntityKey,
) -> Result<Option<DeliveryEntity>, FeishuError> {
    let scope_row = read_scope(db, scope).await?.ok_or_else(unreadable)?;
    let entity = db
        .query_one_raw(statement(
            "SELECT * FROM bot_delivery_items WHERE scope_key=? AND entity_key=?",
            vec![scope.storage_key()?.into(), entity.storage_key()?.into()],
        ))
        .await
        .map_err(storage)?
        .as_ref()
        .map(|row| decode_entity_row(scope, row))
        .transpose()?;
    if let Some(entity) = &entity
        && let Some(binding) = &entity.state.file_operation
        && super::artifact::verify_send(
            db,
            &scope_row,
            &entity.entity,
            &binding.operation_id,
            &binding.artifact,
        )
        .await?
            != *binding
    {
        return Err(unreadable());
    }
    Ok(entity)
}

pub(super) fn order_value(order: Option<u64>) -> i64 {
    match order {
        Some(order) => i64::try_from(order).unwrap_or(i64::MAX),
        None => -1,
    }
}

pub(super) fn entity_key_order(entity: &DeliveryEntity) -> String {
    entity.entity.storage_key().unwrap_or_default()
}

fn entity_values(entity: &DeliveryEntity) -> Result<Vec<Value>, FeishuError> {
    validate_entity(entity)?;
    let flags = derive_flags(entity.removed, &entity.state);
    Ok(vec![
        entity.scope.storage_key()?.into(),
        entity.entity.storage_key()?.into(),
        serde_json::to_string(&entity.entity)
            .map_err(|_| unreadable())?
            .into(),
        entity.entity.kind().into(),
        entity.entity.item_id().to_string().into(),
        entity.entity.publication_id().to_string().into(),
        entity.turn_id.clone().unwrap_or_default().into(),
        order_value(entity.item_order).into(),
        i64::try_from(entity.revision())
            .map_err(|_| unreadable())?
            .into(),
        i64::from(entity.saved).into(),
        i64::from(entity.removed).into(),
        i64::from(flags.delivered).into(),
        i64::from(flags.incomplete).into(),
        i64::from(flags.attention).into(),
        i64::from(flags.unknown).into(),
        serde_json::to_string(&entity.state)
            .map_err(|_| unreadable())?
            .into(),
        i64::try_from(entity.ledger_version)
            .map_err(|_| unreadable())?
            .into(),
        entity.updated_at.into(),
    ])
}

pub(super) async fn write_entity<C: ConnectionTrait>(
    db: &C,
    entity: &DeliveryEntity,
    expected: Option<u64>,
) -> Result<(), FeishuError> {
    let scope = read_scope(db, &entity.scope)
        .await?
        .ok_or_else(unreadable)?;
    let values = entity_values(entity)?;
    let updated = match expected {
        None => {
            let mut values = values;
            db.execute_raw(statement(
                "INSERT INTO bot_delivery_items
                   (scope_key,entity_key,entity_json,kind,item_id,publication_id,turn_id,item_order,
                    item_revision,saved,removed,delivered,incomplete,attention,unknown,state_json,
                    ledger_version,updated_at)
                 VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                std::mem::take(&mut values),
            ))
            .await
            .map_err(storage)?
        }
        Some(expected) => {
            // 状态列与派生标志同一写入更新；CAS 只用账本版本，不用内容修订。
            let mut values = values[2..].to_vec();
            values.extend([
                entity.scope.storage_key()?.into(),
                entity.entity.storage_key()?.into(),
                i64::try_from(expected).map_err(|_| unreadable())?.into(),
            ]);
            db.execute_raw(statement(
                "UPDATE bot_delivery_items SET
                   entity_json=?,kind=?,item_id=?,publication_id=?,turn_id=?,item_order=?,
                   item_revision=?,saved=?,removed=?,delivered=?,incomplete=?,attention=?,
                   unknown=?,state_json=?,ledger_version=?,updated_at=?
                 WHERE scope_key=? AND entity_key=? AND ledger_version=?",
                std::mem::take(&mut values),
            ))
            .await
            .map_err(storage)?
        }
    };
    if updated.rows_affected() != 1 {
        return Err(conflict());
    }
    let authorization = match &scope.key {
        DeliveryScopeKey::Frontend { authorization } => Some(authorization),
        DeliveryScopeKey::LegacyFinal { .. } => None,
    };
    audience::note_delivery_change(db, authorization, &scope.thread_id).await
}

/// 未完成项索引与实体状态同事务维护：同一实体只保留最新修订位置。
pub(super) async fn sync_pending<C: ConnectionTrait>(
    db: &C,
    entity: &DeliveryEntity,
) -> Result<(), FeishuError> {
    let scope = entity.scope.storage_key()?;
    let key = entity.entity.storage_key()?;
    let flags = derive_flags(entity.removed, &entity.state);
    if !flags.pending() {
        db.execute_raw(statement(
            "DELETE FROM bot_delivery_pending WHERE scope_key=? AND entity_key=?",
            vec![scope.into(), key.into()],
        ))
        .await
        .map_err(storage)?;
        return validate_scope_indexes(db, &entity.scope).await;
    }
    db.execute_raw(statement(
        "INSERT INTO bot_delivery_pending(scope_key,entity_key,item_order,item_revision,updated_at)
         VALUES(?,?,?,?,?)
         ON CONFLICT(scope_key,entity_key) DO UPDATE SET
           item_order=excluded.item_order,
           item_revision=excluded.item_revision,
           updated_at=excluded.updated_at",
        vec![
            scope.into(),
            key.into(),
            order_value(entity.item_order).into(),
            i64::try_from(entity.revision())
                .map_err(|_| unreadable())?
                .into(),
            unix_seconds().into(),
        ],
    ))
    .await
    .map_err(storage)?;
    validate_scope_indexes(db, &entity.scope).await
}
