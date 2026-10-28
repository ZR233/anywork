//! 九到十事务迁移：完整唯一 keyset 分页、旧材料 typed 转换与来源不足的显式保全。

use super::super::audience;
use super::super::card::{self, CardBinding, CardStream};
use super::super::{inbound_identity, statement, stored_i64, strict_text};
pub(super) use super::legacy_request::freeze_legacy_request;
use super::schema::{
    CLAIMS, CURSORS, INDEXES, ITEMS, PENDING, SCOPES, data_error, ensure_current_absent,
    ensure_legacy_items, table_exists, validate,
};
use super::*;
use crate::studio::unix_seconds;
use pl_protocol::studio::BotItemPresentation;
use sea_orm::ConnectionTrait;

/// Read-only proof of all old operation materials before the official runner installs any record.
pub(in crate::bots::storage) async fn preflight<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    ensure_current_absent(db).await?;
    ensure_legacy_items(db).await?;
    let mut after: Option<String> = None;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT * FROM bot_card_streams WHERE (?1 IS NULL OR identity>?1) ORDER BY identity LIMIT 32",
            vec![after.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let stream = card::decode_stored(row)?;
            let identity = inbound_identity(
                &stream.binding.bot_id,
                &stream.binding.chat_id,
                &stream.binding.message_id,
            );
            after = Some(identity.clone());
            let facts = super::legacy::facts(
                db,
                &identity,
                &stream.binding,
                &stream.watch_input,
                stream.turn_id.as_deref(),
            )
            .await?;
            legacy_card_state(&stream, facts.origin.needs_recovery).map_err(data_error)?;
            if let Some(recovery) = &stream.recovery {
                super::card::legacy_recovery(recovery, stream.card_id.as_deref())?;
            }
        }
    }
    let mut after: Option<String> = None;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT identity,bot_id,chat_id,message_id,watch_input FROM inbound_work w WHERE (?1 IS NULL OR identity>?1) AND status<>'completed' AND NOT EXISTS(SELECT 1 FROM bot_card_streams c WHERE c.bot_id=w.bot_id AND c.chat_id=w.chat_id AND c.message_id=w.message_id) ORDER BY identity LIMIT 64",
            vec![after.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let identity = strict_text(&row, "identity")?;
            after = Some(identity.clone());
            let binding = CardBinding {
                bot_id: strict_text(&row, "bot_id")?,
                chat_id: strict_text(&row, "chat_id")?,
                message_id: strict_text(&row, "message_id")?,
                thread_id: String::new(),
                original_input: original_input_id(&identity),
            };
            anyhow::ensure!(
                !binding.bot_id.is_empty()
                    && !binding.chat_id.is_empty()
                    && !binding.message_id.is_empty()
                    && !identity.is_empty(),
                "legacy work has no retainable delivery identity"
            );
            let watch = strict_text(&row, "watch_input")?;
            let watched = if watch.is_empty() {
                binding.original_input.as_str()
            } else {
                watch.as_str()
            };
            super::legacy::facts(db, &identity, &binding, watched, None).await?;
        }
    }
    Ok(())
}

/// 正式九到十迁移：严格核验来源后在调用方事务内重整唯一实体账本并搬移旧材料。
pub(in crate::bots) async fn migrate<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    ensure_current_absent(db).await?;
    ensure_legacy_items(db).await?;
    for table in [
        "bot_authorizations",
        "bot_audience_origins",
        "bot_card_streams",
        "inbound_work",
        "inbound_identities",
        "thread_bindings",
    ] {
        anyhow::ensure!(
            table_exists(db, table).await?,
            "delivery migration source is missing: {table}"
        );
    }
    // 先让旧表改名，再建立当前表：`bot_delivery_pending` 的外键必须指向新的
    // `bot_delivery_items`，不能在 rename 之前建立（SQLite 会把已有外键改写到
    // 重命名后的旧表，随后 DROP 旧表会让该外键失效）。
    db.execute_unprepared("ALTER TABLE bot_delivery_items RENAME TO bot_delivery_items_nine")
        .await?;
    for ddl in [SCOPES, CLAIMS, CURSORS, ITEMS, PENDING] {
        db.execute_unprepared(ddl).await?;
    }
    migrate_frontend_scopes(db).await?;
    migrate_observations(db).await?;
    migrate_legacy_cards(db).await?;
    migrate_legacy_work(db).await?;
    // 旧卡片材料已进入当前 typed 状态：原表不再保留第二份可编辑业务事实。
    db.execute_unprepared("DELETE FROM bot_card_streams")
        .await?;
    db.execute_unprepared("DROP TABLE bot_delivery_items_nine")
        .await?;
    for (_, ddl) in INDEXES {
        db.execute_unprepared(ddl).await?;
    }
    // 每个迁移实体在写入时同步当前派生索引，不从 delivered=0 猜待发义务。
    validate(db).await
}

fn generation(value: u64) -> anyhow::Result<i64> {
    i64::try_from(value).map_err(|_| data_error("delivery identity exceeds the storage range"))
}

/// 前端作用域：只从已保存授权与其 origin 的一致事实建立，分页键为 (chat,generation)。
async fn migrate_frontend_scopes<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = (String::new(), 0_i64);
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT * FROM bot_authorizations WHERE (chat_id,generation)>(?,?)
                 ORDER BY chat_id,generation LIMIT 64",
                vec![after.0.clone().into(), after.1.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            let auth = audience::authorization_row(row)?;
            let id = auth.intent.authorization.clone();
            if id.bot_id.is_empty()
                || id.chat_id.is_empty()
                || auth.app_id.is_empty()
                || auth.intent.thread_id.is_empty()
                || auth.intent.binding_revision == 0
            {
                return Err(data_error(
                    "authorization identity is not provable for a delivery scope",
                ));
            }
            let origin = audience::read_origin(db, &auth.intent.thread_id)
                .await?
                .ok_or_else(|| data_error("authorization has no proven creation origin"))?;
            if origin.chat_id != id.chat_id
                || origin.project_id != auth.project_id
                || origin.creation_id != auth.creation_id
                || origin.binding_revision != auth.intent.binding_revision
                || origin.thread_id != auth.intent.thread_id
            {
                return Err(data_error(
                    "authorization and creation origin conflict for delivery scope",
                ));
            }
            let key = DeliveryScopeKey::Frontend {
                authorization: id.clone(),
            };
            super::records::insert_scope_row(
                db,
                &DeliveryScope {
                    key: key.clone(),
                    bot_id: id.bot_id.clone(),
                    chat_id: origin.chat_id.clone(),
                    thread_id: origin.thread_id.clone(),
                    app_id: auth.app_id.clone(),
                    project_id: origin.project_id.clone(),
                    creation_id: origin.creation_id.clone(),
                    binding_revision: origin.binding_revision,
                    origin: DeliveryScopeOrigin::Frontend {
                        authorization: id.clone(),
                    },
                    needs_recovery: false,
                },
            )
            .await?;
            super::records::insert_cursor_row(db, &key).await?;
            after = (id.chat_id, generation(id.generation)?);
        }
    }
    Ok(())
}

/// 旧九号观察行：真实已知内容保留为 typed `Unresolved`，不虚构顺序/修订/正文。
async fn migrate_observations<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = (String::new(), 0_i64, String::new());
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT chat_id,generation,item_id,thread_id,version,state_json
                 FROM bot_delivery_items_nine
                 WHERE (chat_id,generation,item_id)>(?,?,?)
                 ORDER BY chat_id,generation,item_id LIMIT 64",
                vec![
                    after.0.clone().into(),
                    after.1.into(),
                    after.2.clone().into(),
                ],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            let chat = strict_text(row, "chat_id")?;
            let generation_value = stored_i64(row, "generation")?;
            let item = strict_text(row, "item_id")?;
            let thread = strict_text(row, "thread_id")?;
            let version = stored_i64(row, "version")?;
            let observation: audience::DeliveryObservation =
                serde_json::from_str(&strict_text(row, "state_json")?)
                    .map_err(|_| data_error("nine delivery observation is not decodable"))?;
            if observation.item_id != item
                || observation.authorization.chat_id != chat
                || i64::try_from(observation.authorization.generation)
                    .map_err(|_| data_error("delivery observation generation is out of range"))?
                    != generation_value
                || observation.thread_id != thread
                || version <= 0
            {
                return Err(data_error(
                    "nine delivery observation identity conflicts with its row",
                ));
            }
            let key = DeliveryScopeKey::Frontend {
                authorization: observation.authorization.clone(),
            };
            let scope = super::records::read_scope(db, &key)
                .await?
                .ok_or_else(|| data_error("delivery observation has no proven scope"))?;
            if scope.thread_id != thread || scope.chat_id != chat {
                return Err(data_error(
                    "delivery observation crosses its authorized Thread scope",
                ));
            }
            let state = DeliveryEntityState {
                content: DeliveryContent::Unresolved {
                    unresolved: DeliveryUnresolved {
                        reason: DeliveryRecoveryReason::LegacyObservation,
                        observation: Some(observation.ledger.clone()),
                        removed: observation.removed,
                        pending: observation.pending,
                        incomplete: observation.incomplete,
                        detail: format!(
                            "nine observation ledger version {version}; canonical order and revision are not proven"
                        ),
                    },
                },
                projected: BotItemPresentation::None {},
                accepted: BotItemPresentation::None {},
                card: DeliveryCard::default(),
                file_operation: None,
                in_flight: None,
                settled: None,
                halt: None,
            };
            after = (chat, generation_value, item.clone());
            insert_migrated_entity(
                db,
                &key,
                DeliveryEntityKey::TextItem { item_id: item },
                None,
                false,
                observation.removed,
                state,
            )
            .await?;
        }
    }
    Ok(())
}

/// 旧卡片：可证时迁成可接续当前 `LegacyFinal`；不可证时保留需恢复材料。
async fn migrate_legacy_cards<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT * FROM bot_card_streams WHERE identity>? ORDER BY identity LIMIT 32",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let stream = card::decode_stored(row)?;
            after = inbound_identity(
                &stream.binding.bot_id,
                &stream.binding.chat_id,
                &stream.binding.message_id,
            );
            migrate_legacy_card(db, &stream).await?;
        }
    }
    Ok(())
}

async fn migrate_legacy_card<C: ConnectionTrait>(
    db: &C,
    stream: &CardStream,
) -> anyhow::Result<()> {
    let binding = &stream.binding;
    let identity = inbound_identity(&binding.bot_id, &binding.chat_id, &binding.message_id);
    let mut facts = super::legacy::facts(
        db,
        &identity,
        binding,
        &stream.watch_input,
        stream.turn_id.as_deref(),
    )
    .await?;
    if stream.lifecycle == CardLifecycle::NeedsAttention && facts.origin.needs_recovery.is_none() {
        facts.origin.needs_recovery = Some("legacy card needs local attention".into());
    }
    if !facts.origin.resumable
        && !stream.lifecycle.terminal()
        && facts.origin.needs_recovery.is_none()
    {
        facts.origin.needs_recovery =
            Some("completed legacy input cannot create a new unfinished obligation".into());
    }
    let key = DeliveryScopeKey::LegacyFinal {
        inbound_identity: identity.clone(),
    };
    let needs_recovery = facts.origin.needs_recovery.clone();
    super::records::insert_scope_row(
        db,
        &DeliveryScope {
            key: key.clone(),
            bot_id: binding.bot_id.clone(),
            chat_id: binding.chat_id.clone(),
            thread_id: facts.thread_id.clone(),
            app_id: facts.app_id.clone(),
            project_id: facts.project_id.clone(),
            creation_id: facts.creation_id.clone(),
            binding_revision: facts.binding_revision,
            origin: DeliveryScopeOrigin::LegacyFinal {
                legacy: Box::new(facts.origin),
            },
            needs_recovery: needs_recovery.is_some(),
        },
    )
    .await?;
    super::records::insert_cursor_row(db, &key).await?;
    let card = DeliveryCard {
        card_id: stream.card_id.clone(),
        platform_message_id: stream.platform_message_id.clone(),
        sequence: stream.sequence,
        confirmed_sequence: stream.confirmed_sequence,
        streaming: if stream.lifecycle.terminal() || stream.lifecycle == CardLifecycle::Paused {
            Some(false)
        } else if stream.platform_message_id.is_some() {
            Some(true)
        } else {
            None
        },
        recovery_used: stream.recovery_used,
        recovery: stream
            .recovery
            .as_ref()
            .map(|recovery| super::card::legacy_recovery(recovery, stream.card_id.as_deref()))
            .transpose()?,
        lifecycle: Some(stream.lifecycle),
        confirmed_text: stream.confirmed_text.clone(),
        confirmed_content_hash: stream.confirmed_content_hash.clone(),
        confirmed_presentation: None,
        final_content_hash: stream.final_content_hash.clone(),
        diagnostic: stream.diagnostic.clone(),
        legacy_local_completion: None,
    };
    // 来源不足是 Unresolved；操作材料本身无法无损解码则回滚，不能清掉旧表后丢请求。
    let (content, settled, halt) = legacy_card_state(stream, needs_recovery).map_err(data_error)?;
    let state = DeliveryEntityState {
        content,
        projected: BotItemPresentation::None {},
        accepted: BotItemPresentation::None {},
        card,
        file_operation: None,
        in_flight: None,
        settled,
        halt,
    };
    insert_migrated_entity(
        db,
        &key,
        DeliveryEntityKey::LegacyFinal {
            entity_id: binding.reply_operation(),
        },
        stream.turn_id.clone(),
        false,
        false,
        state,
    )
    .await?;
    Ok(())
}

type LegacyState = (
    DeliveryContent,
    Option<DeliverySettled>,
    Option<DeliveryHalt>,
);

/// 旧卡片操作 → 当前已结算事实；Intent 不能证明未启动，按 Unknown 保全。
fn legacy_card_state(
    stream: &CardStream,
    unprovable: Option<String>,
) -> Result<LegacyState, String> {
    let operation = stream.last_operation.as_ref();
    let mapped = operation.and_then(|operation| {
        let intent = super::card::legacy_intent(
            operation,
            &stream.binding.chat_id,
            stream.card_id.as_deref(),
            stream.platform_message_id.as_deref(),
        )?;
        let result = super::card::legacy_result(
            operation,
            stream.card_id.as_deref(),
            stream.platform_message_id.as_deref(),
        )?;
        Some((intent, result))
    });
    let content = match unprovable {
        Some(reason) => unresolved(reason),
        None => DeliveryContent::Legacy {
            final_only: true,
            presentation: None,
        },
    };
    let Some((intent, result)) = mapped else {
        if operation.is_some() {
            return Err("legacy card operation identity is incomplete".to_string());
        }
        return Ok((content, None, None));
    };
    if !result_matches(&intent.action, intent.sequence, &result) {
        return Err("legacy card operation and result disagree".to_string());
    }
    let halt = match &result {
        DeliveryResult::Unknown { diagnostic } => Some(DeliveryHalt::Unknown {
            operation_id: intent.operation_id.clone(),
            diagnostic: diagnostic.clone(),
        }),
        DeliveryResult::Rejected { diagnostic } => Some(DeliveryHalt::Rejected {
            operation_id: intent.operation_id.clone(),
            diagnostic: diagnostic.clone(),
        }),
        _ => None,
    };
    Ok((content, Some(DeliverySettled { intent, result }), halt))
}

/// 未完成入站且没有卡片：仍是旧有限回复义务，迁成可接续 `LegacyFinal`。
async fn migrate_legacy_work<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT identity,bot_id,chat_id,message_id,watch_input
                 FROM inbound_work
                 WHERE identity>? AND status<>'completed'
                   AND NOT EXISTS(SELECT 1 FROM bot_card_streams c
                     WHERE c.bot_id=inbound_work.bot_id AND c.chat_id=inbound_work.chat_id
                       AND c.message_id=inbound_work.message_id)
                 ORDER BY identity LIMIT 64",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            let identity = strict_text(row, "identity")?;
            after = identity.clone();
            let bot = strict_text(row, "bot_id")?;
            let chat = strict_text(row, "chat_id")?;
            let message = strict_text(row, "message_id")?;
            let watch_input = strict_text(row, "watch_input")?;
            let key = DeliveryScopeKey::LegacyFinal {
                inbound_identity: identity.clone(),
            };
            if super::records::read_scope(db, &key).await?.is_some() {
                continue;
            }
            let binding = CardBinding {
                bot_id: bot,
                chat_id: chat,
                message_id: message,
                thread_id: String::new(),
                original_input: original_input_id(&identity),
            };
            let watched = if watch_input.is_empty() {
                original_input_id(&identity)
            } else {
                watch_input
            };
            let facts = super::legacy::facts(db, &identity, &binding, &watched, None).await?;
            let needs_recovery = facts.origin.needs_recovery.clone();
            let thread = facts.thread_id.clone();
            super::records::insert_scope_row(
                db,
                &DeliveryScope {
                    key: key.clone(),
                    bot_id: binding.bot_id.clone(),
                    chat_id: binding.chat_id.clone(),
                    thread_id: thread.clone(),
                    app_id: facts.app_id.clone(),
                    project_id: facts.project_id.clone(),
                    creation_id: facts.creation_id.clone(),
                    binding_revision: facts.binding_revision,
                    origin: DeliveryScopeOrigin::LegacyFinal {
                        legacy: Box::new(facts.origin),
                    },
                    needs_recovery: needs_recovery.is_some(),
                },
            )
            .await?;
            super::records::insert_cursor_row(db, &key).await?;
            let state = DeliveryEntityState {
                content: needs_recovery.clone().map(unresolved).unwrap_or(
                    DeliveryContent::Legacy {
                        final_only: true,
                        presentation: None,
                    },
                ),
                projected: BotItemPresentation::None {},
                accepted: BotItemPresentation::None {},
                card: DeliveryCard::default(),
                file_operation: None,
                in_flight: None,
                settled: None,
                halt: None,
            };
            insert_migrated_entity(
                db,
                &key,
                DeliveryEntityKey::LegacyFinal {
                    entity_id: CardBinding {
                        thread_id: thread,
                        ..binding
                    }
                    .reply_operation(),
                },
                None,
                false,
                false,
                state,
            )
            .await?;
        }
    }
    Ok(())
}

pub(super) fn original_input_id(identity: &str) -> String {
    // 原执行器的规范输入身份：`bot:<bot>:<chat>:<message>`，由入站身份唯一派生。
    format!("bot:{identity}")
}

fn unresolved(detail: String) -> DeliveryContent {
    DeliveryContent::Unresolved {
        unresolved: DeliveryUnresolved {
            reason: DeliveryRecoveryReason::LegacyUnprovable,
            observation: None,
            removed: false,
            pending: false,
            incomplete: true,
            detail,
        },
    }
}

async fn insert_migrated_entity<C: ConnectionTrait>(
    db: &C,
    scope: &DeliveryScopeKey,
    entity: DeliveryEntityKey,
    turn_id: Option<String>,
    saved: bool,
    removed: bool,
    state: DeliveryEntityState,
) -> anyhow::Result<()> {
    validate_entity_state(&entity, &state)?;
    let entity = DeliveryEntity {
        scope: scope.clone(),
        entity,
        turn_id,
        // 旧材料没有可证规范顺序：typed `None`，行内显式 `-1`。
        item_order: None,
        saved,
        removed,
        state,
        ledger_version: 1,
        updated_at: unix_seconds(),
    };
    super::records::insert_entity_row(db, &entity).await?;
    super::records::sync_pending(db, &entity).await?;
    Ok(())
}
