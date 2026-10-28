//! 正式 schema-ten 结构声明、新库创建与当前结构严格校验。
//!
//! 九号 `bot_delivery_items` 经 `migrate` 重整为**唯一当前实体账本**；本模块只声明结构、
//! 建立新库并逐行核对当前事实，不再保留第二份可编辑投递状态。

use super::super::audience;
use super::super::{statement, stored_i64, strict_text};
use super::{DeliveryScopeKey, DeliveryScopeOrigin, derive_flags, validate_entity_state};
use pl_protocol::studio::BotAuthorizationPhase;
use sea_orm::ConnectionTrait;

pub(super) const SCOPES: &str = "CREATE TABLE bot_delivery_scopes (
    scope_key TEXT PRIMARY KEY NOT NULL,
    scope_json TEXT NOT NULL CHECK(length(scope_json)>0),
    kind TEXT NOT NULL CHECK(kind IN ('frontend','legacyFinal')),
    bot_id TEXT NOT NULL CHECK(length(bot_id)>0),
    chat_id TEXT NOT NULL CHECK(length(chat_id)>0),
    thread_id TEXT NOT NULL,
    app_id TEXT NOT NULL,
    project_id TEXT NOT NULL,
    creation_id TEXT NOT NULL,
    binding_revision INTEGER NOT NULL CHECK(binding_revision>=0),
    origin_json TEXT NOT NULL CHECK(length(origin_json)>0),
    needs_recovery INTEGER NOT NULL CHECK(needs_recovery IN (0,1)),
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
)";

pub(super) const CLAIMS: &str = "CREATE TABLE bot_delivery_claims (
    scope_key TEXT PRIMARY KEY NOT NULL,
    owner_id TEXT NOT NULL DEFAULT '',
    lease_generation INTEGER NOT NULL CHECK(lease_generation>=0),
    work_version INTEGER NOT NULL CHECK(work_version>0),
    authorization_revision INTEGER NOT NULL DEFAULT 0 CHECK(authorization_revision>=0),
    expires_at INTEGER NOT NULL,
    stopped_reason TEXT NOT NULL DEFAULT '',
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(scope_key) REFERENCES bot_delivery_scopes(scope_key)
)";

pub(super) const CURSORS: &str = "CREATE TABLE bot_delivery_cursors (
    scope_key TEXT PRIMARY KEY NOT NULL,
    order_watermark INTEGER NOT NULL CHECK(order_watermark>=0),
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(scope_key) REFERENCES bot_delivery_scopes(scope_key)
)";

pub(super) const PENDING: &str = "CREATE TABLE bot_delivery_pending (
    scope_key TEXT NOT NULL,
    entity_key TEXT NOT NULL,
    item_order INTEGER NOT NULL CHECK(item_order>=-1),
    item_revision INTEGER NOT NULL CHECK(item_revision>=0),
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(scope_key,entity_key),
    FOREIGN KEY(scope_key) REFERENCES bot_delivery_scopes(scope_key),
    FOREIGN KEY(scope_key,entity_key) REFERENCES bot_delivery_items(scope_key,entity_key)
)";

/// 唯一当前实体账本：typed 稳定键 + 有界状态 + 派生计数列。
pub(super) const ITEMS: &str = "CREATE TABLE bot_delivery_items (
    scope_key TEXT NOT NULL,
    entity_key TEXT NOT NULL,
    entity_json TEXT NOT NULL CHECK(length(entity_json)>0),
    kind TEXT NOT NULL CHECK(kind IN ('textItem','publicArtifact','legacyFinal')),
    item_id TEXT NOT NULL DEFAULT '',
    publication_id TEXT NOT NULL DEFAULT '',
    turn_id TEXT NOT NULL DEFAULT '',
    item_order INTEGER NOT NULL CHECK(item_order>=-1),
    item_revision INTEGER NOT NULL CHECK(item_revision>=0),
    saved INTEGER NOT NULL CHECK(saved IN (0,1)),
    removed INTEGER NOT NULL CHECK(removed IN (0,1)),
    delivered INTEGER NOT NULL CHECK(delivered IN (0,1)),
    incomplete INTEGER NOT NULL CHECK(incomplete IN (0,1)),
    attention INTEGER NOT NULL CHECK(attention IN (0,1)),
    unknown INTEGER NOT NULL CHECK(unknown IN (0,1)),
    state_json TEXT NOT NULL CHECK(length(state_json)>0),
    ledger_version INTEGER NOT NULL CHECK(ledger_version>0),
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(scope_key,entity_key),
    FOREIGN KEY(scope_key) REFERENCES bot_delivery_scopes(scope_key)
)";

const DECLARATIONS: &[(&str, &str)] = &[
    ("bot_delivery_scopes", SCOPES),
    ("bot_delivery_claims", CLAIMS),
    ("bot_delivery_cursors", CURSORS),
    ("bot_delivery_items", ITEMS),
    ("bot_delivery_pending", PENDING),
];

/// 索引名与九号同名索引不冲突：九号 items 索引随旧表一起消失。
pub(super) const INDEXES: &[(&str, &str)] = &[
    (
        "bot_delivery_scope_thread",
        "CREATE INDEX bot_delivery_scope_thread ON bot_delivery_scopes(thread_id,kind,scope_key)",
    ),
    (
        "bot_delivery_scope_kind",
        "CREATE INDEX bot_delivery_scope_kind ON bot_delivery_scopes(kind,scope_key)",
    ),
    (
        "bot_delivery_entity_order",
        "CREATE INDEX bot_delivery_entity_order ON bot_delivery_items(scope_key,item_order,entity_key)",
    ),
    (
        "bot_delivery_item_identity",
        "CREATE UNIQUE INDEX bot_delivery_item_identity ON bot_delivery_items(scope_key,item_id)",
    ),
    (
        "bot_delivery_pending_order",
        "CREATE INDEX bot_delivery_pending_order ON bot_delivery_pending(scope_key,item_order,entity_key)",
    ),
    (
        "bot_delivery_item_pending",
        "CREATE INDEX bot_delivery_item_pending ON bot_delivery_items(scope_key) WHERE delivered=0 AND removed=0 AND incomplete=0 AND attention=0 AND unknown=0",
    ),
    (
        "bot_delivery_item_incomplete",
        "CREATE INDEX bot_delivery_item_incomplete ON bot_delivery_items(scope_key) WHERE incomplete=1",
    ),
    (
        "bot_delivery_item_attention",
        "CREATE INDEX bot_delivery_item_attention ON bot_delivery_items(scope_key) WHERE attention=1",
    ),
    (
        "bot_delivery_item_unknown",
        "CREATE INDEX bot_delivery_item_unknown ON bot_delivery_items(scope_key) WHERE unknown=1",
    ),
];

pub(in crate::bots::storage) fn declarations()
-> impl Iterator<Item = &'static (&'static str, &'static str)> {
    DECLARATIONS.iter().chain(INDEXES)
}

/// 迁移前对九号来源的唯一核对入口：精确声明，不做同号修补。
pub(in crate::bots) async fn ensure_legacy_items<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let expected = audience::legacy_items_declaration();
    let row = db
        .query_one_raw(statement(
            "SELECT sql FROM sqlite_schema WHERE type='table' AND name='bot_delivery_items'",
            vec![],
        ))
        .await?
        .ok_or_else(|| data_error("nine delivery ledger is missing"))?;
    let ddl: String = row.try_get("", "sql")?;
    anyhow::ensure!(
        normalized(&ddl) == normalized(expected),
        "incompatible nine delivery ledger declaration"
    );
    Ok(())
}

/// 十号严格校验：结构逐字核对 + 全部行解码 + 身份互相核对；只读、不重跑迁移。
pub(in crate::bots) async fn validate<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    for (name, expected) in declarations() {
        let row = db
            .query_one_raw(statement(
                "SELECT sql FROM sqlite_schema WHERE name=?",
                vec![(*name).into()],
            ))
            .await?
            .ok_or_else(|| anyhow::anyhow!("missing schema-ten delivery declaration: {name}"))?;
        let sql: String = row.try_get("", "sql")?;
        anyhow::ensure!(
            normalized(&sql) == normalized(expected),
            "incompatible schema-ten delivery declaration: {name}"
        );
    }
    validate_scopes(db).await?;
    validate_claims(db).await?;
    validate_cursors(db).await?;
    validate_entities(db).await?;
    validate_pending(db).await?;
    anyhow::ensure!(
        db.query_one_raw(statement("PRAGMA foreign_key_check", vec![]))
            .await?
            .is_none(),
        "bot delivery foreign key proof failed"
    );
    Ok(())
}

pub(super) async fn ensure_current_absent<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    for name in [
        "bot_delivery_scopes",
        "bot_delivery_claims",
        "bot_delivery_cursors",
        "bot_delivery_pending",
    ]
    .into_iter()
    .chain(INDEXES.iter().map(|(name, _)| *name))
    {
        anyhow::ensure!(
            db.query_one_raw(statement(
                "SELECT name FROM sqlite_schema WHERE name=?",
                vec![name.into()],
            ))
            .await?
            .is_none(),
            "unversioned delivery structure: {name}"
        );
    }
    Ok(())
}

pub(super) async fn table_exists<C: ConnectionTrait>(db: &C, table: &str) -> anyhow::Result<bool> {
    Ok(db
        .query_one_raw(statement(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name=?",
            vec![table.into()],
        ))
        .await?
        .is_some())
}

fn normalized(ddl: &str) -> String {
    ddl.chars()
        .filter(|c| !c.is_ascii_whitespace())
        .flat_map(char::to_lowercase)
        .collect()
}

pub(super) fn data_error(message: impl Into<String>) -> anyhow::Error {
    crate::studio::startup::data_error(anyhow::anyhow!(message.into()))
}

fn order_value(order: Option<u64>) -> anyhow::Result<i64> {
    match order {
        Some(order) => Ok(i64::try_from(order)
            .map_err(|_| data_error("delivery order exceeds the storage range"))?),
        // 不可证顺序用显式 `-1`；typed 状态里保持 `None`，不虚构 0。
        None => Ok(-1),
    }
}

async fn validate_scopes<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT * FROM bot_delivery_scopes WHERE scope_key>? ORDER BY scope_key LIMIT 64",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            after = strict_text(row, "scope_key")?;
            let scope = super::records::decode_scope_row(row)?;
            anyhow::ensure!(
                scope.key.kind() == strict_text(row, "kind")?,
                "delivery scope kind conflicts with its typed identity"
            );
            match (&scope.key, &scope.origin) {
                (
                    DeliveryScopeKey::Frontend { authorization },
                    DeliveryScopeOrigin::Frontend {
                        authorization: origin,
                    },
                ) if authorization == origin => {
                    let auth = audience::load_auth(db, authorization)
                        .await?
                        .ok_or_else(|| data_error("delivery scope authorization is missing"))?;
                    anyhow::ensure!(
                        auth.intent.authorization == *authorization
                            && auth.intent.thread_id == scope.thread_id
                            && auth.app_id == scope.app_id
                            && auth.project_id == scope.project_id
                            && auth.creation_id == scope.creation_id
                            && auth.intent.binding_revision == scope.binding_revision
                            && authorization.bot_id == scope.bot_id
                            && authorization.chat_id == scope.chat_id
                            && scope.binding_revision > 0,
                        "delivery scope and authorization identity conflict"
                    );
                    anyhow::ensure!(
                        !scope.needs_recovery,
                        "a proven frontend scope cannot be marked for recovery"
                    );
                    anyhow::ensure!(
                        matches!(
                            auth.phase,
                            BotAuthorizationPhase::PendingStart
                                | BotAuthorizationPhase::Active
                                | BotAuthorizationPhase::Paused
                                | BotAuthorizationPhase::Closed
                        ),
                        "delivery scope authorization phase is unknown"
                    );
                }
                (DeliveryScopeKey::LegacyFinal { .. }, DeliveryScopeOrigin::LegacyFinal { .. }) => {
                    super::legacy::validate(db, &scope).await?;
                }
                _ => return Err(data_error("delivery scope identity kind conflicts")),
            }
        }
    }
    Ok(())
}

async fn validate_claims<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT scope_key,owner_id,lease_generation,work_version,authorization_revision,expires_at
                 FROM bot_delivery_claims WHERE scope_key>? ORDER BY scope_key LIMIT 64",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            after = strict_text(row, "scope_key")?;
            let owner = strict_text(row, "owner_id")?;
            let generation = stored_i64(row, "lease_generation")?;
            let work_version = stored_i64(row, "work_version")?;
            let expires_at = stored_i64(row, "expires_at")?;
            anyhow::ensure!(
                generation >= 0
                    && work_version > 0
                    && expires_at >= 0
                    && stored_i64(row, "authorization_revision")? >= 0,
                "delivery claim numbers are out of range"
            );
            anyhow::ensure!(
                !owner.is_empty() || expires_at == 0,
                "delivery claim keeps an expired owner slot"
            );
        }
    }
    anyhow::ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM bot_delivery_claims c
             LEFT JOIN bot_delivery_scopes s ON s.scope_key=c.scope_key
             WHERE s.scope_key IS NULL LIMIT 1",
            vec![],
        ))
        .await?
        .is_none(),
        "delivery claim crosses its scope"
    );
    Ok(())
}

async fn validate_cursors<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT scope_key,order_watermark FROM bot_delivery_cursors
                 WHERE scope_key>? ORDER BY scope_key LIMIT 64",
                vec![after.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            after = strict_text(row, "scope_key")?;
            anyhow::ensure!(
                stored_i64(row, "order_watermark")? >= 0,
                "delivery cursor watermark is negative"
            );
        }
    }
    anyhow::ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM bot_delivery_cursors c
             LEFT JOIN bot_delivery_scopes s ON s.scope_key=c.scope_key
             WHERE s.scope_key IS NULL
             UNION ALL SELECT 1 FROM bot_delivery_scopes s LEFT JOIN bot_delivery_cursors c ON c.scope_key=s.scope_key WHERE c.scope_key IS NULL LIMIT 1",
            vec![],
        ))
        .await?
        .is_none(),
        "delivery cursor missing or crosses its scope"
    );
    Ok(())
}

async fn validate_entities<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    let mut after = (String::new(), String::new());
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT i.*,s.scope_json AS scope_json,s.kind AS scope_kind
                 FROM bot_delivery_items i
                 JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
                 WHERE (i.scope_key,i.entity_key)>(?,?)
                 ORDER BY i.scope_key,i.entity_key LIMIT 64",
                vec![after.0.clone().into(), after.1.clone().into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in &rows {
            after = (
                strict_text(row, "scope_key")?,
                strict_text(row, "entity_key")?,
            );
            let scope =
                DeliveryScopeKey::decode_stored(&after.0, &strict_text(row, "scope_json")?)?;
            anyhow::ensure!(
                scope.kind() == strict_text(row, "scope_kind")?,
                "delivery entity scope kind conflicts"
            );
            let entity = super::records::decode_entity_row(&scope, row)?;
            validate_entity_state(&entity.entity, &entity.state)?;
            let flags = derive_flags(entity.removed, &entity.state);
            let content_kind = entity.state.content.kind();
            anyhow::ensure!(
                strict_text(row, "kind")? == entity.entity.kind()
                    && (content_kind == entity.entity.kind()
                        || content_kind == "unresolved"
                        || content_kind == "removed"),
                "delivery entity kind conflicts with its typed content"
            );
            anyhow::ensure!(
                strict_text(row, "item_id")? == entity.entity.item_id()
                    && strict_text(row, "publication_id")? == entity.entity.publication_id()
                    && stored_i64(row, "item_order")? == order_value(entity.item_order)?
                    && u64::try_from(stored_i64(row, "item_revision")?)
                        .map_err(|_| data_error("delivery revision is out of range"))?
                        == entity.revision()
                    && (stored_i64(row, "saved")? != 0) == entity.saved
                    && (stored_i64(row, "removed")? != 0) == entity.removed
                    && (stored_i64(row, "delivered")? != 0) == flags.delivered
                    && (stored_i64(row, "incomplete")? != 0) == flags.incomplete
                    && (stored_i64(row, "attention")? != 0) == flags.attention
                    && (stored_i64(row, "unknown")? != 0) == flags.unknown,
                "delivery entity row disagrees with its typed state"
            );
            if let Some(binding) = &entity.state.file_operation {
                let scope_row = super::records::read_scope(db, &scope)
                    .await?
                    .ok_or_else(|| data_error("file scope missing"))?;
                anyhow::ensure!(
                    super::artifact::verify_send(
                        db,
                        &scope_row,
                        &entity.entity,
                        &binding.operation_id,
                        &binding.artifact
                    )
                    .await?
                        == *binding,
                    "delivery file reference conflicts with the original send operation"
                );
            }
        }
    }
    anyhow::ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM bot_delivery_items i
             LEFT JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.scope_key IS NULL LIMIT 1",
            vec![],
        ))
        .await?
        .is_none(),
        "delivery entity crosses its scope"
    );
    Ok(())
}

async fn validate_pending<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    anyhow::ensure!(db.query_one_raw(statement(
        "SELECT 1 FROM bot_delivery_items i LEFT JOIN bot_delivery_pending p ON p.scope_key=i.scope_key AND p.entity_key=i.entity_key
         WHERE (p.entity_key IS NOT NULL) <> (i.delivered=0 AND i.removed=0 AND i.incomplete=0 AND i.attention=0 AND i.unknown=0)
            OR (p.entity_key IS NOT NULL AND (p.item_order<>i.item_order OR p.item_revision<>i.item_revision))
         UNION ALL SELECT 1 FROM bot_delivery_pending p LEFT JOIN bot_delivery_items i ON p.scope_key=i.scope_key AND p.entity_key=i.entity_key
         WHERE i.entity_key IS NULL LIMIT 1", vec![])).await?.is_none(), "delivery pending index is missing, orphaned or inconsistent");
    Ok(())
}

#[cfg(test)]
mod tests {
    //! 保存/迁移专项：只验证真实 SQLite 上的持久与迁移不变量，不扩测试专用公共接口。

    use super::super::migrate::migrate;
    use super::*;
    use crate::bots::storage::audience::{self, Authorization, DeliveryObservation};
    use crate::bots::storage::card::{
        CardAction, CardBinding, CardLifecycle, CardOperation, CardOperationStatus, CardStream,
        hash,
    };
    use crate::bots::storage::publication::{
        DeliveryContent, DeliveryEntityKey, DeliveryHalt, DeliveryResult,
    };
    use crate::bots::storage::statement;
    use crate::bots::storage::target::TargetProof;
    use crate::studio::audience_start::{AudienceStartIntent, AudienceStartReceipt};
    use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
    use pl_protocol::BotAuthorizationId;
    use pl_protocol::studio::{
        BotAuthorizationPhase, BotItemLedgerSummary, BotItemPlatform, BotItemPresentation,
    };
    use sea_orm::{ConnectionTrait, Database, DatabaseConnection, TransactionTrait};

    const BOT: &str = "botfixture";
    const CHAT: &str = "chat-1";
    const THREAD: &str = "thread-1";
    const PROJECT: &str = "project";
    const APP: &str = "app";

    fn creation(chat: &str) -> String {
        format!("botthread:{BOT}:{chat}:op")
    }

    fn identity(chat: &str, message: &str) -> String {
        format!("{BOT}:{chat}:{message}")
    }

    fn original_input(chat: &str, message: &str) -> String {
        format!("bot:{BOT}:{chat}:{message}")
    }

    async fn connect(path: &std::path::Path) -> anyhow::Result<DatabaseConnection> {
        let mut options = sqlite_file_options(path, SqliteFileMode::Create, |options| {
            options.foreign_keys(true)
        })
        .await?;
        options.max_connections(1).min_connections(1);
        Ok(Database::connect(options).await?)
    }

    /// 九号来源：只建迁移/校验实际读取的结构，受众结构与九号实体表声明与生产一致。
    async fn nine_fixture(db: &DatabaseConnection) -> anyhow::Result<()> {
        for ddl in [
            audience::legacy_items_declaration(),
            "CREATE TABLE bot_audience_origins (
                thread_id TEXT PRIMARY KEY NOT NULL, chat_id TEXT NOT NULL,
                project_id TEXT NOT NULL, creation_id TEXT NOT NULL,
                binding_revision INTEGER NOT NULL, requires_upgrade INTEGER NOT NULL,
                summary_version INTEGER NOT NULL, target_json TEXT NOT NULL)",
            "CREATE TABLE bot_authorizations (
                chat_id TEXT NOT NULL, generation INTEGER NOT NULL, thread_id TEXT NOT NULL,
                control_revision INTEGER NOT NULL, phase TEXT NOT NULL, state_json TEXT NOT NULL,
                PRIMARY KEY(chat_id,generation))",
            "CREATE TABLE bot_card_streams (
                identity TEXT PRIMARY KEY, bot_id TEXT NOT NULL, chat_id TEXT NOT NULL,
                message_id TEXT NOT NULL, thread_id TEXT NOT NULL, original_input TEXT NOT NULL,
                watch_input TEXT NOT NULL, turn_id TEXT NOT NULL, version INTEGER NOT NULL,
                state_json TEXT NOT NULL, updated_at INTEGER NOT NULL)",
            "CREATE TABLE inbound_identities (identity TEXT PRIMARY KEY, bot_id TEXT NOT NULL, chat_id TEXT NOT NULL, message_id TEXT NOT NULL, content_hash TEXT NOT NULL, admitted_at INTEGER NOT NULL)",
            "CREATE TABLE inbound_work (
                identity TEXT PRIMARY KEY, bot_id TEXT NOT NULL, chat_id TEXT NOT NULL,
                message_id TEXT NOT NULL, app_id TEXT NOT NULL, project_id TEXT NOT NULL,
                creation_id TEXT NOT NULL, binding_revision INTEGER NOT NULL, open_id TEXT NOT NULL,
                chat_kind TEXT NOT NULL, watch_input TEXT NOT NULL, status TEXT NOT NULL, content_hash TEXT NOT NULL)",
            "CREATE TABLE thread_bindings (
                chat_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL, status TEXT NOT NULL,
                creation_id TEXT NOT NULL, project_id TEXT NOT NULL, revision INTEGER NOT NULL)",
            "CREATE TABLE send_operations (
                operation_id TEXT PRIMARY KEY, bot_id TEXT NOT NULL, chat_id TEXT NOT NULL,
                content_hash TEXT NOT NULL, status TEXT NOT NULL,
                platform_message_ids TEXT NOT NULL, segment_facts TEXT NOT NULL,
                send_identity TEXT NOT NULL, send_source TEXT NOT NULL)",
        ] {
            db.execute_unprepared(ddl).await?;
        }
        Ok(())
    }

    async fn insert_origin(db: &DatabaseConnection, chat: &str) -> anyhow::Result<()> {
        let thread = format!("{THREAD}-{chat}");
        db.execute_raw(statement(
            "INSERT INTO bot_audience_origins
               (thread_id,chat_id,project_id,creation_id,binding_revision,requires_upgrade,
                summary_version,target_json)
             VALUES(?,?,?,?,1,1,1,?)",
            vec![
                thread.clone().into(),
                chat.to_string().into(),
                PROJECT.into(),
                creation(chat).into(),
                TargetProof::Legacy {
                    target: crate::bots::storage::target::TargetKind::Group,
                }
                .encode()?
                .into(),
            ],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO bot_authorizations
               (chat_id,generation,thread_id,control_revision,phase,state_json)
             VALUES(?,1,?,1,'active',?)",
            vec![
                chat.to_string().into(),
                thread.clone().into(),
                serde_json::to_string(&active_authorization(chat, &thread))?.into(),
            ],
        ))
        .await?;
        db.execute_raw(statement(
            "INSERT INTO thread_bindings(chat_id,thread_id,status,creation_id,project_id,revision)
             VALUES(?,?,'bound',?,?,1)",
            vec![
                chat.to_string().into(),
                thread.into(),
                creation(chat).into(),
                PROJECT.into(),
            ],
        ))
        .await?;
        Ok(())
    }

    fn active_authorization(chat: &str, thread: &str) -> Authorization {
        let id = BotAuthorizationId {
            bot_id: BOT.to_string(),
            chat_id: chat.to_string(),
            generation: 1,
        };
        let intent = AudienceStartIntent {
            operation_id: format!("op-{chat}"),
            thread_id: thread.to_string(),
            authorization: id,
            binding_revision: 1,
        };
        Authorization {
            start: Some(AudienceStartReceipt {
                version: 1,
                intent: intent.clone(),
                extension_revision: 1,
                sequence: 1,
                excluded_turn_id: None,
            }),
            intent,
            app_id: APP.to_string(),
            project_id: PROJECT.to_string(),
            creation_id: creation(chat),
            revision: 1,
            phase: BotAuthorizationPhase::Active,
            closed: None,
            delivery_version: 1,
        }
    }

    async fn insert_work(
        db: &DatabaseConnection,
        chat: &str,
        message: &str,
        status: &str,
    ) -> anyhow::Result<()> {
        db.execute_raw(statement("INSERT INTO inbound_identities(identity,bot_id,chat_id,message_id,content_hash,admitted_at) VALUES(?,?,?,?,'hash',7)", vec![identity(chat,message).into(), BOT.into(), chat.into(), message.into()])).await?;
        db.execute_raw(statement(
            "INSERT INTO inbound_work
               (identity,bot_id,chat_id,message_id,app_id,project_id,creation_id,binding_revision,
                open_id,chat_kind,watch_input,status,content_hash)
             VALUES(?,?,?,?,?,?,?,1,'','group',?,?,'hash')",
            vec![
                identity(chat, message).into(),
                BOT.into(),
                chat.to_string().into(),
                message.to_string().into(),
                APP.into(),
                PROJECT.into(),
                creation(chat).into(),
                original_input(chat, message).into(),
                status.into(),
            ],
        ))
        .await?;
        Ok(())
    }

    async fn insert_nine_item(
        db: &DatabaseConnection,
        chat: &str,
        item: &str,
        version: i64,
    ) -> anyhow::Result<()> {
        let observation = DeliveryObservation {
            item_id: item.to_string(),
            thread_id: format!("{THREAD}-{chat}"),
            authorization: BotAuthorizationId {
                bot_id: BOT.to_string(),
                chat_id: chat.to_string(),
                generation: 1,
            },
            ledger: BotItemLedgerSummary {
                observed_revision: 3,
                projected: BotItemPresentation::None {},
                accepted: BotItemPresentation::None {},
                platform: BotItemPlatform::None {},
            },
            removed: false,
            pending: true,
            incomplete: false,
        };
        db.execute_raw(statement(
            "INSERT INTO bot_delivery_items(chat_id,generation,item_id,thread_id,version,state_json)
             VALUES(?,1,?,?,?,?)",
            vec![
                chat.to_string().into(),
                item.to_string().into(),
                format!("{THREAD}-{chat}").into(),
                version.into(),
                serde_json::to_string(&observation)?.into(),
            ],
        ))
        .await?;
        Ok(())
    }

    fn unknown_card(chat: &str, message: &str, card: &str) -> CardStream {
        let binding = CardBinding {
            bot_id: BOT.to_string(),
            chat_id: chat.to_string(),
            message_id: message.to_string(),
            thread_id: format!("{THREAD}-{chat}"),
            original_input: original_input(chat, message),
        };
        let action = CardAction::Content {
            text: "hello".to_string(),
            final_content: false,
        };
        let content_hash = hash(&serde_json::to_vec(&action).expect("card action encodes"));
        CardStream {
            binding,
            watch_input: original_input(chat, message),
            turn_id: Some("turn-1".into()),
            version: 2,
            lifecycle: CardLifecycle::Streaming,
            card_id: Some(card.into()),
            platform_message_id: Some(format!("om_{message}")),
            sequence: 1,
            confirmed_sequence: 1,
            confirmed_text: "hello".into(),
            confirmed_content_hash: hash(b"hello"),
            final_content_hash: None,
            last_operation: Some(CardOperation {
                action,
                sequence: 1,
                uuid: "0123456789abcdef0123456789abcdef".into(),
                content_hash,
                status: CardOperationStatus::Unknown,
                diagnostic: None,
            }),
            recovery_used: false,
            recovery: None,
            diagnostic: None,
        }
    }

    async fn insert_card(db: &DatabaseConnection, stream: &CardStream) -> anyhow::Result<()> {
        let binding = &stream.binding;
        db.execute_raw(statement(
            "INSERT INTO bot_card_streams
               (identity,bot_id,chat_id,message_id,thread_id,original_input,watch_input,turn_id,
                version,state_json,updated_at)
             VALUES(?,?,?,?,?,?,?,?,?,?,1)",
            vec![
                identity(&binding.chat_id, &binding.message_id).into(),
                binding.bot_id.clone().into(),
                binding.chat_id.clone().into(),
                binding.message_id.clone().into(),
                binding.thread_id.clone().into(),
                binding.original_input.clone().into(),
                stream.watch_input.clone().into(),
                stream.turn_id.clone().unwrap_or_default().into(),
                stream.version.into(),
                serde_json::to_string(stream)?.into(),
            ],
        ))
        .await?;
        Ok(())
    }

    async fn count(db: &DatabaseConnection, table: &str, predicate: &str) -> anyhow::Result<i64> {
        let row = db
            .query_one_raw(statement(
                &format!("SELECT COUNT(*) AS n FROM {table} WHERE {predicate}"),
                vec![],
            ))
            .await?
            .expect("count row");
        Ok(row.try_get("", "n")?)
    }

    async fn foreign_key_violations(db: &DatabaseConnection) -> anyhow::Result<i64> {
        let row = db
            .query_one_raw(statement(
                "SELECT COUNT(*) AS n FROM pragma_foreign_key_check",
                vec![],
            ))
            .await?
            .expect("foreign key count");
        Ok(row.try_get("", "n")?)
    }

    async fn columns(db: &DatabaseConnection, table: &str) -> anyhow::Result<Vec<String>> {
        let rows = db
            .query_all_raw(statement(
                "SELECT name FROM pragma_table_xinfo(?)",
                vec![table.to_string().into()],
            ))
            .await?;
        rows.iter()
            .map(|row| Ok(row.try_get::<String>("", "name")?))
            .collect()
    }

    async fn table_exists(db: &DatabaseConnection, table: &str) -> anyhow::Result<bool> {
        Ok(db
            .query_one_raw(statement(
                "SELECT name FROM sqlite_schema WHERE type='table' AND name=?",
                vec![table.to_string().into()],
            ))
            .await?
            .is_some())
    }

    #[tokio::test]
    async fn creates_current_schema_and_reopens_without_migrating() -> anyhow::Result<()> {
        use crate::bots::storage::{BotStateStore, DatabaseOrigin};
        let directory = tempfile::tempdir()?;
        let path = directory.path().join("state.sqlite");
        let store = BotStateStore::new(path.clone());
        let db = store.db().await?;
        validate(db).await?;
        let columns = columns(db, "bot_delivery_items").await?;
        assert!(columns.iter().any(|column| column == "scope_key"));
        assert!(!columns.iter().any(|column| column == "chat_id"));
        assert_eq!(foreign_key_violations(db).await?, 0);
        db.execute_unprepared("CREATE TRIGGER reject_reinitialization BEFORE UPDATE ON bot_meta BEGIN SELECT RAISE(ABORT,'completed migration replayed'); END").await?;
        // 十号冷重开由同一官方谱系只校验，不重跑迁移；既有库也不能冒充新建库。
        let cold = BotStateStore::new(path);
        validate(cold.db().await?).await?;
        assert!(
            crate::bots::storage::schema::initialize(db, DatabaseOrigin::Created)
                .await
                .is_err()
        );
        Ok(())
    }

    #[tokio::test]
    async fn migrates_observations_cards_and_unfinished_work_without_loss() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let db = connect(&directory.path().join("state.sqlite")).await?;
        nine_fixture(&db).await?;
        insert_origin(&db, CHAT).await?;
        insert_nine_item(&db, CHAT, "item-1", 4).await?;
        let card_stream = unknown_card(CHAT, "m-card", "card-1");
        insert_card(&db, &card_stream).await?;
        insert_work(&db, CHAT, "m-card", "pending").await?;
        insert_work(&db, CHAT, "m-work", "failed").await?;
        insert_work(&db, CHAT, "m-done", "completed").await?;

        let tx = db.begin().await?;
        migrate(&tx).await?;
        tx.commit().await?;
        validate(&db).await?;
        // 迁移后外键必须仍然完整（旧表先改名，再建当前表）。
        assert_eq!(foreign_key_violations(&db).await?, 0);
        assert_eq!(
            count(&db, "bot_delivery_scopes", "kind='frontend'").await?,
            1
        );
        assert_eq!(
            count(&db, "bot_delivery_scopes", "kind='legacyFinal'").await?,
            2
        );
        // 旧卡片材料已全部转移，原表不再保留第二份业务事实。
        assert_eq!(count(&db, "bot_card_streams", "1=1").await?, 0);
        assert_eq!(count(&db, "bot_delivery_items", "incomplete=1").await?, 1);
        assert_eq!(
            count(&db, "bot_delivery_pending", "1=1").await?,
            1,
            "only proven unfinished work is pending; observation and unknown are not replayable"
        );

        let frontend = DeliveryScopeKey::Frontend {
            authorization: BotAuthorizationId {
                bot_id: BOT.to_string(),
                chat_id: CHAT.to_string(),
                generation: 1,
            },
        };
        let observation = super::super::records::read_entity(
            &db,
            &frontend,
            &DeliveryEntityKey::TextItem {
                item_id: "item-1".to_string(),
            },
        )
        .await?
        .expect("observation entity");
        assert!(matches!(
            observation.state.content,
            DeliveryContent::Unresolved { .. }
        ));
        assert_eq!(observation.item_order, None, "order is not provable");
        assert_eq!(
            observation.revision(),
            0,
            "ledger version is not a revision"
        );
        assert!(!observation.state.content.kind().is_empty());

        let card_scope = DeliveryScopeKey::LegacyFinal {
            inbound_identity: identity(CHAT, "m-card"),
        };
        let card_entity = super::super::records::read_entity(
            &db,
            &card_scope,
            &DeliveryEntityKey::LegacyFinal {
                entity_id: card_stream.binding.reply_operation(),
            },
        )
        .await?
        .expect("card entity");
        assert_eq!(card_entity.state.card.card_id.as_deref(), Some("card-1"));
        assert_eq!(
            card_entity.state.card.platform_message_id.as_deref(),
            Some("om_m-card")
        );
        assert_eq!(card_entity.state.card.sequence, 1);
        assert_eq!(card_entity.state.card.confirmed_text, "hello");
        assert!(matches!(
            card_entity.state.halt,
            Some(DeliveryHalt::Unknown { .. })
        ));
        assert_eq!(
            card_entity
                .state
                .settled
                .as_ref()
                .map(|settled| &settled.result),
            Some(&DeliveryResult::Unknown { diagnostic: None })
        );
        let card_scope_row = super::super::records::read_scope(&db, &card_scope)
            .await?
            .expect("card scope");
        assert!(matches!(
            card_scope_row.origin,
            DeliveryScopeOrigin::LegacyFinal { legacy } if legacy.source.is_some() && legacy.needs_recovery.is_none()
        ));

        let work_scope_key = DeliveryScopeKey::LegacyFinal {
            inbound_identity: identity(CHAT, "m-work"),
        };
        let work_scope = super::super::records::read_scope(&db, &work_scope_key)
            .await?
            .expect("unfinished inbound scope");
        assert!(matches!(
            work_scope.origin,
            DeliveryScopeOrigin::LegacyFinal { legacy } if legacy.source.is_some() && legacy.needs_recovery.is_none()
        ));
        let work_entity = super::super::records::read_entity(
            &db,
            &work_scope_key,
            &DeliveryEntityKey::LegacyFinal {
                entity_id: CardBinding {
                    bot_id: BOT.to_string(),
                    chat_id: CHAT.to_string(),
                    message_id: "m-work".to_string(),
                    thread_id: format!("{THREAD}-{CHAT}"),
                    original_input: original_input(CHAT, "m-work"),
                }
                .reply_operation(),
            },
        )
        .await?
        .expect("unfinished inbound entity");
        assert!(work_entity.state.card.card_id.is_none());
        assert!(work_entity.state.halt.is_none());
        assert!(matches!(
            work_entity.state.content,
            DeliveryContent::Legacy {
                final_only: true,
                presentation: None
            }
        ));

        // 已完成入站不是旧投递义务。
        let done = DeliveryScopeKey::LegacyFinal {
            inbound_identity: identity(CHAT, "m-done"),
        };
        assert!(
            super::super::records::read_scope(&db, &done)
                .await?
                .is_none()
        );
        Ok(())
    }

    #[tokio::test]
    async fn legacy_admission_is_proven_and_turn_ownership_is_exclusive() -> anyhow::Result<()> {
        use super::super::{DeliveryInputChain, DeliveryTurnIdentity, DeliveryTurnOwner};
        let directory = tempfile::tempdir()?;
        let db = connect(&directory.path().join("state.sqlite")).await?;
        nine_fixture(&db).await?;
        insert_origin(&db, CHAT).await?;
        let stream = unknown_card(CHAT, "valid", "card-valid");
        insert_card(&db, &stream).await?;
        insert_work(&db, CHAT, "valid", "claimed").await?;
        for (message, status) in [
            ("missing", "pending"),
            ("hash", "pending"),
            ("time", "pending"),
            ("attention", "needs_attention"),
            ("future", "future_status"),
        ] {
            insert_work(&db, CHAT, message, status).await?;
        }
        insert_work(&db, CHAT, "unrouted", "pending").await?;
        db.execute_raw(statement("UPDATE inbound_work SET creation_id='unproven-creation',watch_input='unproven-watch' WHERE identity=?",vec![identity(CHAT,"unrouted").into()])).await?;
        db.execute_raw(statement(
            "DELETE FROM inbound_identities WHERE identity=?",
            vec![identity(CHAT, "missing").into()],
        ))
        .await?;
        db.execute_raw(statement(
            "UPDATE inbound_identities SET content_hash='other' WHERE identity=?",
            vec![identity(CHAT, "hash").into()],
        ))
        .await?;
        db.execute_raw(statement(
            "UPDATE inbound_identities SET admitted_at=0 WHERE identity=?",
            vec![identity(CHAT, "time").into()],
        ))
        .await?;
        let unproven_chat = "unproven-chat";
        insert_origin(&db, unproven_chat).await?;
        insert_work(&db, unproven_chat, "target", "pending").await?;
        db.execute_raw(statement(
            "UPDATE bot_audience_origins SET target_json=? WHERE chat_id=?",
            vec![TargetProof::Unproven.encode()?.into(), unproven_chat.into()],
        ))
        .await?;
        let tx = db.begin().await?;
        migrate(&tx).await?;
        tx.commit().await?;
        for (chat, message) in [
            (CHAT, "missing"),
            (CHAT, "hash"),
            (CHAT, "time"),
            (CHAT, "attention"),
            (CHAT, "future"),
            (unproven_chat, "target"),
        ] {
            let scope = super::super::records::read_scope(
                &db,
                &DeliveryScopeKey::LegacyFinal {
                    inbound_identity: identity(chat, message),
                },
            )
            .await?
            .unwrap();
            assert!(scope.needs_recovery, "{message} must remain unclaimable");
        }
        assert_eq!(count(&db, "bot_delivery_pending", "1=1").await?, 0);
        let scope = DeliveryScopeKey::LegacyFinal {
            inbound_identity: identity(CHAT, "valid"),
        };
        let turn = |turn: &str, input_chain| DeliveryTurnIdentity {
            thread_id: format!("{THREAD}-{CHAT}"),
            turn_id: turn.into(),
            input_chain,
        };
        assert_eq!(
            super::super::ownership::turn_owner(
                &db,
                &turn("turn-1", DeliveryInputChain::Unavailable)
            )
            .await?,
            DeliveryTurnOwner::LegacyFinal {
                scope: scope.clone()
            }
        );
        assert_eq!(
            super::super::ownership::turn_owner(
                &db,
                &turn(
                    "continuation-turn",
                    DeliveryInputChain::Proven {
                        input_id: "continuation-input".into(),
                        continuation_ancestors: vec![original_input(CHAT, "valid")]
                    }
                )
            )
            .await?,
            DeliveryTurnOwner::LegacyFinal {
                scope: scope.clone()
            }
        );
        assert_eq!(
            super::super::ownership::turn_owner(
                &db,
                &turn(
                    "future-turn",
                    DeliveryInputChain::Proven {
                        input_id: "independent-gui-input".into(),
                        continuation_ancestors: vec![]
                    }
                )
            )
            .await?,
            DeliveryTurnOwner::Frontend
        );
        assert_eq!(
            super::super::ownership::turn_owner(
                &db,
                &turn("unknown-turn", DeliveryInputChain::Unavailable)
            )
            .await?,
            DeliveryTurnOwner::Unproven
        );
        let entity = super::super::records::read_entity(
            &db,
            &scope,
            &DeliveryEntityKey::LegacyFinal {
                entity_id: stream.binding.reply_operation(),
            },
        )
        .await?
        .unwrap();
        assert_eq!(entity.turn_id.as_deref(), Some("turn-1"));
        let unresolved = super::super::records::read_scope(
            &db,
            &DeliveryScopeKey::LegacyFinal {
                inbound_identity: identity(CHAT, "unrouted"),
            },
        )
        .await?
        .unwrap();
        assert!(unresolved.thread_id.is_empty() && unresolved.needs_recovery);
        for thread in [format!("{THREAD}-{CHAT}"), "different-thread".to_string()] {
            for (input, ancestors) in [
                (original_input(CHAT, "unrouted"), vec![]),
                ("unproven-watch".into(), vec![]),
                (
                    "canonical-continuation".into(),
                    vec!["unproven-watch".into()],
                ),
            ] {
                let identity = DeliveryTurnIdentity {
                    thread_id: thread.clone(),
                    turn_id: "unrelated-turn".into(),
                    input_chain: DeliveryInputChain::Proven {
                        input_id: input,
                        continuation_ancestors: ancestors,
                    },
                };
                assert_eq!(
                    super::super::ownership::turn_owner(&db, &identity).await?,
                    DeliveryTurnOwner::Unproven
                );
            }
            let independent = DeliveryTurnIdentity {
                thread_id: thread,
                turn_id: "unrelated-turn".into(),
                input_chain: DeliveryInputChain::Proven {
                    input_id: "unrelated-gui".into(),
                    continuation_ancestors: vec![],
                },
            };
            assert_eq!(
                super::super::ownership::turn_owner(&db, &independent).await?,
                DeliveryTurnOwner::Frontend
            );
        }
        // 后来的合法 route 替换不否定原不可变来源，也不丢平台结果。
        db.execute_raw(statement(
            "UPDATE thread_bindings SET thread_id='replacement',revision=2 WHERE chat_id=?",
            vec![CHAT.into()],
        ))
        .await?;
        validate(&db).await?;
        // 不可变 admitted_at 被损坏才是重开恢复错误。
        db.execute_raw(statement(
            "UPDATE inbound_identities SET admitted_at=99 WHERE identity=?",
            vec![identity(CHAT, "valid").into()],
        ))
        .await?;
        assert!(validate(&db).await.is_err());
        Ok(())
    }

    #[tokio::test]
    async fn legacy_card_migration_keeps_proven_thread_and_attention_material() -> anyhow::Result<()>
    {
        let mut failures = Vec::new();
        for attention in [false, true] {
            let directory = tempfile::tempdir()?;
            let db = connect(&directory.path().join("state.sqlite")).await?;
            nine_fixture(&db).await?;
            insert_origin(&db, CHAT).await?;
            let mut stream = unknown_card(CHAT, "card", "legacy-card");
            stream.last_operation.as_mut().unwrap().status = CardOperationStatus::Confirmed;
            if attention {
                stream.lifecycle = CardLifecycle::NeedsAttention;
            } else {
                stream.binding.thread_id.clear();
            }
            insert_card(&db, &stream).await?;
            insert_work(&db, CHAT, "card", "pending").await?;
            // 唯一旧 origin 才是证明；当前 route 指向别处也不能猜成原 Thread。
            db.execute_unprepared(
                "UPDATE thread_bindings SET thread_id='different-route',revision=2",
            )
            .await?;
            let tx = db.begin().await?;
            if let Err(error) = migrate(&tx).await {
                failures.push(format!("attention={attention}: {error:#}"));
                tx.rollback().await?;
                continue;
            }
            tx.commit().await?;
            let key = DeliveryScopeKey::LegacyFinal {
                inbound_identity: identity(CHAT, "card"),
            };
            let scope = super::super::records::read_scope(&db, &key).await?.unwrap();
            let entity = super::super::records::read_entity(
                &db,
                &key,
                &DeliveryEntityKey::LegacyFinal {
                    entity_id: stream.binding.reply_operation(),
                },
            )
            .await?
            .unwrap();
            assert_eq!(scope.thread_id, format!("{THREAD}-{CHAT}"));
            assert_eq!(entity.state.card.card_id, stream.card_id);
            assert_eq!(entity.state.card.confirmed_text, stream.confirmed_text);
            assert!(matches!(
                entity.state.settled.as_ref().map(|settled| &settled.result),
                Some(DeliveryResult::ContentAccepted { .. })
            ));
            if attention {
                let flags = derive_flags(entity.removed, &entity.state);
                if !scope.needs_recovery || !flags.attention || flags.pending() {
                    failures.push("confirmed NeedsAttention was reopened as pending".into());
                }
            } else {
                assert!(!scope.needs_recovery);
            }
        }
        assert!(failures.is_empty(), "{failures:#?}");
        Ok(())
    }

    #[tokio::test]
    async fn migration_keeps_complete_actions_and_never_applies_new_limits_to_old_requests()
    -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let db = connect(&directory.path().join("state.sqlite")).await?;
        nine_fixture(&db).await?;
        insert_origin(&db, CHAT).await?;
        let actions = [
            CardAction::Create {
                text: "old create".into(),
            },
            CardAction::Send {},
            CardAction::Content {
                text: "x".repeat(5_000),
                final_content: true,
            },
            CardAction::Settings {
                streaming: false,
                lifecycle: CardLifecycle::Cancelled,
                recovery: true,
            },
        ];
        let mut expected = vec![];
        for (index, action) in actions.into_iter().enumerate() {
            let message = format!("action-{index}");
            let mut stream = unknown_card(CHAT, &message, "card-old");
            if matches!(action, CardAction::Create { .. }) {
                stream.card_id = None;
                stream.platform_message_id = None;
                stream.sequence = 0;
                stream.confirmed_sequence = 0;
                stream.confirmed_text.clear();
                stream.confirmed_content_hash.clear();
                stream.lifecycle = CardLifecycle::Empty;
            }
            if matches!(action, CardAction::Send { .. }) {
                stream.platform_message_id = None;
                stream.sequence = 0;
                stream.confirmed_sequence = 0;
                stream.lifecycle = CardLifecycle::Created;
            }
            let operation = stream.last_operation.as_mut().unwrap();
            operation.action = action.clone();
            operation.sequence = stream.sequence;
            operation.content_hash = hash(&serde_json::to_vec(&action)?);
            insert_card(&db, &stream).await?;
            insert_work(&db, CHAT, &message, "pending").await?;
            expected.push(stream);
        }
        let tx = db.begin().await?;
        migrate(&tx).await?;
        tx.commit().await?;
        validate(&db).await?;
        for stream in expected {
            let scope = DeliveryScopeKey::LegacyFinal {
                inbound_identity: identity(CHAT, &stream.binding.message_id),
            };
            let entity = super::super::records::read_entity(
                &db,
                &scope,
                &DeliveryEntityKey::LegacyFinal {
                    entity_id: stream.binding.reply_operation(),
                },
            )
            .await?
            .unwrap();
            let original = stream.last_operation.as_ref().unwrap();
            let intent = entity.state.settled.as_ref().unwrap().intent.clone();
            assert_eq!(intent.uuid, original.uuid);
            assert_eq!(intent.sequence, original.sequence);
            assert_eq!(
                intent.legacy_action_hash.as_deref(),
                Some(original.content_hash.as_str())
            );
            assert_eq!(intent.request_hash, intent.request.hash()?);
            let expected_target = match original.action {
                CardAction::Create { .. } => super::super::DeliveryRequestTarget::CreateCard,
                CardAction::Send { .. } => super::super::DeliveryRequestTarget::SendCard,
                CardAction::Content { .. } => super::super::DeliveryRequestTarget::ElementContent,
                CardAction::Settings { .. } => super::super::DeliveryRequestTarget::Settings,
            };
            assert_eq!(intent.request.target(), expected_target);
            assert_eq!(
                intent.request_hash,
                super::super::typed_digest(&(expected_target, intent.request.body()))?
            );
            match &original.action {
                CardAction::Create { text } => assert!(
                    matches!(&intent.action, super::super::DeliveryAction::CreateCard { text: saved } if saved==text)
                ),
                CardAction::Content {
                    text,
                    final_content,
                } => {
                    #[derive(serde::Deserialize)]
                    struct ContentBody {
                        content: String,
                        sequence: i32,
                        uuid: String,
                    }
                    let body: ContentBody = serde_json::from_str(intent.request.body())?;
                    assert_eq!(
                        (&body.content, body.sequence, &body.uuid),
                        (text, original.sequence, &original.uuid)
                    );
                    assert!(
                        matches!(&intent.action, super::super::DeliveryAction::UpdateContent { text: saved, final_content: saved_final, .. } if saved==text && saved_final==final_content)
                    );
                }
                CardAction::Settings {
                    streaming,
                    lifecycle,
                    recovery,
                } => assert!(
                    matches!(&intent.action, super::super::DeliveryAction::UpdateSettings { streaming: s, lifecycle: l, recovery: r, .. } if s==streaming && l==lifecycle && r==recovery)
                ),
                CardAction::Send {} => {
                    #[derive(serde::Deserialize)]
                    struct SendBody {
                        receive_id: String,
                        uuid: String,
                    }
                    let body: SendBody = serde_json::from_str(intent.request.body())?;
                    assert_eq!(body.receive_id, CHAT);
                    assert_eq!(body.uuid, original.uuid);
                }
            }
        }
        Ok(())
    }

    #[tokio::test]
    async fn pages_every_composite_key_without_skipping_rows() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let db = connect(&directory.path().join("state.sqlite")).await?;
        nine_fixture(&db).await?;
        // (chat,generation) 分页：65 个授权超过单页 64。
        for index in 0..65 {
            let chat = format!("chat-{index}");
            insert_origin(&db, &chat).await?;
        }
        // (chat,generation,item) 分页：70 个观察超过单页 64。
        for index in 0..70 {
            let item = format!("item-{index:03}");
            insert_nine_item(&db, "chat-0", &item, 1).await?;
        }
        // identity 分页：33 张卡片超过单页 32。
        for index in 0..33 {
            let message = format!("m-{index:03}");
            let stream = unknown_card("chat-0", &message, &format!("card-{index:03}"));
            insert_card(&db, &stream).await?;
            insert_work(&db, "chat-0", &message, "pending").await?;
        }

        let tx = db.begin().await?;
        migrate(&tx).await?;
        tx.commit().await?;
        validate(&db).await?;
        assert_eq!(
            count(&db, "bot_delivery_scopes", "kind='frontend'").await?,
            65
        );
        assert_eq!(
            count(&db, "bot_delivery_scopes", "kind='legacyFinal'").await?,
            33
        );
        assert_eq!(
            count(&db, "bot_delivery_items", "kind='textItem'").await?,
            70
        );
        assert_eq!(
            count(&db, "bot_delivery_items", "kind='legacyFinal'").await?,
            33
        );
        assert_eq!(count(&db, "bot_card_streams", "1=1").await?, 0);
        Ok(())
    }

    #[tokio::test]
    async fn corrupt_source_rolls_back_the_whole_transaction() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let db = connect(&directory.path().join("state.sqlite")).await?;
        nine_fixture(&db).await?;
        insert_origin(&db, CHAT).await?;
        let stream = unknown_card(CHAT, "m-card", "card-1");
        insert_card(&db, &stream).await?;
        insert_work(&db, CHAT, "m-card", "pending").await?;
        // 不可解码的旧观察行：整个迁移必须回滚并保原库。
        db.execute_raw(statement(
            "INSERT INTO bot_delivery_items(chat_id,generation,item_id,thread_id,version,state_json)
             VALUES(?,1,'item-bad',?,1,'{\"kind\":\"bogus\"}')",
            vec![CHAT.into(), format!("{THREAD}-{CHAT}").into()],
        ))
        .await?;

        let tx = db.begin().await?;
        assert!(migrate(&tx).await.is_err());
        drop(tx); // 回滚：原库保持九号结构与原行。

        assert!(!table_exists(&db, "bot_delivery_scopes").await?);
        let columns = columns(&db, "bot_delivery_items").await?;
        assert!(columns.iter().any(|column| column == "chat_id"));
        assert_eq!(count(&db, "bot_delivery_items", "1=1").await?, 1);
        assert_eq!(count(&db, "bot_card_streams", "1=1").await?, 1);
        Ok(())
    }
}
