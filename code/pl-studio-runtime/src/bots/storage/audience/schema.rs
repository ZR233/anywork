//! Exact schema-nine declarations and the transactional eight-to-nine boundary.

use super::{DeliveryObservation, SyncOperation, authorization, counts, origin, proof};
use crate::bots::storage::statement;
use sea_orm::ConnectionTrait;

const ORIGINS: &str = "CREATE TABLE bot_audience_origins (
    thread_id TEXT PRIMARY KEY NOT NULL,
    chat_id TEXT NOT NULL CHECK(length(chat_id)>0),
    project_id TEXT NOT NULL,
    creation_id TEXT NOT NULL,
    binding_revision INTEGER NOT NULL CHECK(binding_revision>0),
    requires_upgrade INTEGER NOT NULL CHECK(requires_upgrade IN (0,1)),
    summary_version INTEGER NOT NULL CHECK(summary_version>0),
    target_json TEXT NOT NULL CHECK(length(target_json)>0)
)";
const AUTHORIZATIONS: &str = "CREATE TABLE bot_authorizations (
    chat_id TEXT NOT NULL,
    generation INTEGER NOT NULL CHECK(generation>0),
    thread_id TEXT NOT NULL,
    control_revision INTEGER NOT NULL CHECK(control_revision>0),
    phase TEXT NOT NULL CHECK(phase IN ('pending','active','paused','closed')),
    state_json TEXT NOT NULL,
    PRIMARY KEY(chat_id,generation),
    FOREIGN KEY(thread_id) REFERENCES bot_audience_origins(thread_id)
)";
const OPERATIONS: &str = "CREATE TABLE bot_sync_operations (
    operation_id TEXT PRIMARY KEY NOT NULL,
    thread_id TEXT NOT NULL,
    request_json TEXT NOT NULL,
    FOREIGN KEY(thread_id) REFERENCES bot_audience_origins(thread_id)
)";
const ITEMS: &str = "CREATE TABLE bot_delivery_items (
    chat_id TEXT NOT NULL,
    generation INTEGER NOT NULL CHECK(generation>0),
    item_id TEXT NOT NULL CHECK(length(item_id)>0),
    thread_id TEXT NOT NULL,
    version INTEGER NOT NULL CHECK(version>0),
    state_json TEXT NOT NULL,
    PRIMARY KEY(chat_id,generation,item_id),
    FOREIGN KEY(chat_id,generation) REFERENCES bot_authorizations(chat_id,generation),
    FOREIGN KEY(thread_id) REFERENCES bot_audience_origins(thread_id)
)";
const DECLARATIONS: &[(&str, &str)] = &[
    ("bot_audience_origins", ORIGINS),
    ("bot_authorizations", AUTHORIZATIONS),
    ("bot_sync_operations", OPERATIONS),
    ("bot_delivery_items", ITEMS),
];
const INDEXES: &[(&str, &str)] = &[
    (
        "bot_authorizations_thread",
        "CREATE INDEX bot_authorizations_thread ON bot_authorizations(thread_id,generation)",
    ),
    (
        "bot_authorizations_pending",
        "CREATE INDEX bot_authorizations_pending ON bot_authorizations(phase,chat_id,generation)",
    ),
    (
        "bot_delivery_thread",
        "CREATE INDEX bot_delivery_thread ON bot_delivery_items(thread_id,item_id)",
    ),
];

pub(in crate::bots::storage) async fn migrate<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    ensure_eight_absent(db).await?;
    migrate_eight(db).await
}

/// The first read-only boundary also runs before an adoption step can record completion.
pub(in crate::bots::storage) async fn ensure_eight_absent<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    for table in ["thread_bindings", "binding_operations"] {
        anyhow::ensure!(
            db.query_one_raw(statement(
                "SELECT name FROM pragma_table_xinfo(?) WHERE name='target_json'",
                vec![table.into()]
            ))
            .await?
            .is_none(),
            "unversioned creation target structure; original database retained"
        );
    }
    // A v8 database must not already carry a partial/unknown schema-nine shape.
    for (name, _) in DECLARATIONS
        .iter()
        .chain(INDEXES)
        .chain(counts::INDEXES)
        .chain(proof::INDEXES)
    {
        anyhow::ensure!(
            db.query_one_raw(statement(
                "SELECT name FROM sqlite_schema WHERE name=?",
                vec![(*name).into()],
            ))
            .await?
            .is_none(),
            "unversioned bot audience structure; original database retained"
        );
    }
    Ok(())
}

/// Validate the same immutable origin/target evidence used by the eight-to-nine conversion,
/// without installing indexes or writing origins. Incomplete evidence stays unproven as before;
/// contradictory or malformed evidence must fail before any migration step modifies the source.
pub(in crate::bots::storage) async fn preflight_eight<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    ensure_eight_absent(db).await?;
    preflight_origins(db, proof::Boundary::SchemaEight).await
}

pub(in crate::bots::storage) async fn preflight_file_without_cards<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    ensure_eight_absent(db).await?;
    preflight_origins(db, proof::Boundary::FileWithoutCards).await
}

async fn preflight_origins<C: ConnectionTrait>(
    db: &C,
    boundary: proof::Boundary,
) -> anyhow::Result<()> {
    let threads = if matches!(boundary, proof::Boundary::FileWithoutCards) {
        "SELECT thread_id FROM (SELECT thread_id FROM thread_bindings UNION SELECT thread_id FROM binding_operations) WHERE thread_id<>'' AND (?1 IS NULL OR thread_id>?1) ORDER BY thread_id LIMIT 64"
    } else {
        "SELECT thread_id FROM (SELECT thread_id FROM thread_bindings UNION SELECT thread_id FROM binding_operations UNION SELECT thread_id FROM bot_card_streams) WHERE thread_id<>'' AND (?1 IS NULL OR thread_id>?1) ORDER BY thread_id LIMIT 64"
    };
    let mut after: Option<String> = None;
    loop {
        let rows = db
            .query_all_raw(statement(threads, vec![after.clone().into()]))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let thread: String = row.try_get("", "thread_id")?;
            after = Some(thread.clone());
            let evidence = proof::collect(db, &thread, boundary).await?;
            if let Some(origin) = evidence.into_legacy_origin(thread) {
                preflight_target(
                    db,
                    boundary,
                    &origin.thread_id,
                    &origin.creation_id,
                    &origin.chat_id,
                    &origin.project_id,
                )
                .await?;
            }
        }
    }
    let mut after: Option<String> = None;
    loop {
        let rows = db.query_all_raw(statement(
            "SELECT chat_id,creation_id,project_id FROM thread_bindings WHERE status='creating' AND (?1 IS NULL OR chat_id>?1) ORDER BY chat_id LIMIT 64",
            vec![after.clone().into()],
        )).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let chat = super::super::strict_text(&row, "chat_id")?;
            after = Some(chat.clone());
            preflight_target(
                db,
                boundary,
                "",
                &super::super::strict_text(&row, "creation_id")?,
                &chat,
                &super::super::strict_text(&row, "project_id")?,
            )
            .await?;
        }
    }
    Ok(())
}

async fn preflight_target<C: ConnectionTrait>(
    db: &C,
    boundary: proof::Boundary,
    thread: &str,
    creation: &str,
    chat: &str,
    project: &str,
) -> anyhow::Result<()> {
    if matches!(boundary, proof::Boundary::FileWithoutCards) {
        super::super::target::legacy_file_source(db, creation, chat, project).await?;
    } else {
        super::super::target::legacy(db, thread, creation, chat, project).await?;
    }
    Ok(())
}

async fn migrate_eight<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    for table in ["thread_bindings", "binding_operations"] {
        db.execute_unprepared(&format!(
            "ALTER TABLE {table} ADD COLUMN target_json TEXT NOT NULL DEFAULT '{}'",
            super::super::target::UNPROVEN
        ))
        .await?;
    }
    for (_, ddl) in DECLARATIONS
        .iter()
        .chain(INDEXES)
        .chain(counts::INDEXES)
        .chain(proof::INDEXES)
    {
        db.execute_unprepared(ddl).await?;
    }
    // Inherited schema-eight performance indexes are not forbidden partial schema-nine facts.
    // Reuse the owner installer, then validate their exact declarations with the target schema.
    counts::prepare_indexes(db).await?;
    // Compare every known field before recording an origin. Missing proof leaves the original
    // business rows intact and the Thread unavailable; it never becomes a guessed revision one.
    let mut after = String::new();
    loop {
        let threads = db.query_all_raw(statement(
            "SELECT thread_id FROM (SELECT thread_id FROM thread_bindings
             UNION SELECT thread_id FROM binding_operations UNION SELECT thread_id FROM bot_card_streams)
             WHERE thread_id<>'' AND thread_id>? ORDER BY thread_id LIMIT 64", vec![after.into()],
    )).await?;
        let done = threads.len() < 64;
        after = String::new();
        for row in threads {
            let thread: String = row.try_get("", "thread_id")?;
            after = thread.clone();
            let evidence = proof::collect(db, &thread, proof::Boundary::SchemaEight).await?;
            if let Some(mut origin) = evidence.into_legacy_origin(thread) {
                origin.target = super::super::target::legacy(
                    db,
                    &origin.thread_id,
                    &origin.creation_id,
                    &origin.chat_id,
                    &origin.project_id,
                )
                .await?;
                db.execute_raw(statement("INSERT INTO bot_audience_origins
                (thread_id,chat_id,project_id,creation_id,binding_revision,requires_upgrade,summary_version,target_json)
                    VALUES(?,?,?,?,?,1,1,?)",vec![origin.thread_id.into(),origin.chat_id.into(),
                        origin.project_id.into(),origin.creation_id.into(),i64::try_from(origin.binding_revision)?.into(),origin.target.encode()?.into()])).await?;
            }
        }
        if done {
            break;
        }
    }
    db.execute_unprepared("UPDATE thread_bindings SET target_json=(SELECT o.target_json FROM bot_audience_origins o WHERE o.thread_id=thread_bindings.thread_id AND o.creation_id=thread_bindings.creation_id) WHERE EXISTS(SELECT 1 FROM bot_audience_origins o WHERE o.thread_id=thread_bindings.thread_id AND o.creation_id=thread_bindings.creation_id)").await?;
    db.execute_unprepared("UPDATE binding_operations SET target_json=(SELECT o.target_json FROM bot_audience_origins o WHERE o.creation_id=binding_operations.creation_id AND o.thread_id=binding_operations.thread_id) WHERE EXISTS(SELECT 1 FROM bot_audience_origins o WHERE o.creation_id=binding_operations.creation_id AND o.thread_id=binding_operations.thread_id)").await?;
    // 尚未完成的创建意图没有 origin，只能从它自己的原入站/已记录直聊事实采纳；
    // 采纳不到的一律保持 Unproven，由接续路径要求本机处理，不回填猜测值。
    let unproven = super::super::target::TargetProof::Unproven.encode()?;
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT chat_id,creation_id,project_id,revision FROM thread_bindings
                 WHERE status='creating' AND target_json=?1 AND chat_id>?2
                 ORDER BY chat_id LIMIT 64",
                vec![unproven.clone().into(), after.clone().into()],
            ))
            .await?;
        let done = rows.len() < 64;
        for row in rows {
            let chat = super::super::strict_text(&row, "chat_id")?;
            after.clone_from(&chat);
            let creation = super::super::strict_text(&row, "creation_id")?;
            let project = super::super::strict_text(&row, "project_id")?;
            let revision: i64 = row.try_get("", "revision")?;
            let proof = super::super::target::legacy(db, "", &creation, &chat, &project).await?;
            if matches!(proof, super::super::target::TargetProof::Unproven) {
                continue;
            }
            let encoded = proof.encode()?;
            db.execute_raw(statement(
                "UPDATE thread_bindings SET target_json=?1 WHERE chat_id=?2",
                vec![encoded.clone().into(), chat.clone().into()],
            ))
            .await?;
            // 同一创建意图的未完成 operation 必须与本行同源：一边有证明一边没有会让
            // 之后的绑定无法同源比较。只按精确的 chat/creation/水位匹配，不跨创建回填。
            if let Some(expected_revision) = revision.checked_sub(1) {
                db.execute_raw(statement(
                    "UPDATE binding_operations SET target_json=?1
                     WHERE chat_id=?2 AND creation_id=?3 AND thread_id='' AND expected_revision=?4",
                    vec![
                        encoded.into(),
                        chat.into(),
                        creation.into(),
                        expected_revision.into(),
                    ],
                ))
                .await?;
            }
        }
        if done {
            break;
        }
    }
    validate(db).await?;
    Ok(())
}

pub(in crate::bots::storage) async fn validate<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    validate_boundary(db, Boundary::Nine, false).await
}

/// Only previously declared performance indexes may be absent at this import boundary. Present
/// declarations and all source data are still validated; Publication10 installs missing indexes
/// in its own transaction before performing the formal conversion.
pub(in crate::bots::storage) async fn validate_source_nine<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    validate_boundary(db, Boundary::Nine, true).await
}

/// 十号结构下只校验受众部分：实体账本已由投递模块重整，不再要求九号 items 形状。
pub(in crate::bots::storage) async fn validate_current<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    validate_boundary(db, Boundary::Ten, false).await
}

/// 九号 `bot_delivery_items` 的精确声明，供投递迁移核对来源而不是修补同号结构。
pub(in crate::bots::storage) fn legacy_items_declaration() -> &'static str {
    ITEMS
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Boundary {
    Nine,
    Ten,
}

async fn validate_boundary<C: ConnectionTrait>(
    db: &C,
    boundary: Boundary,
    allow_missing_secondary: bool,
) -> anyhow::Result<()> {
    validate_target_structure(db).await?;
    let mut required: Vec<(&str, &str, bool)> = Vec::new();
    for (name, ddl) in DECLARATIONS.iter().copied() {
        if boundary == Boundary::Nine || name != "bot_delivery_items" {
            required.push((name, ddl, false));
        }
    }
    for (name, ddl) in INDEXES.iter().copied() {
        if boundary == Boundary::Nine || name != "bot_delivery_thread" {
            required.push((name, ddl, false));
        }
    }
    for (name, ddl) in match boundary {
        Boundary::Nine => counts::INDEXES
            .iter()
            .copied()
            .chain(proof::INDEXES.iter().copied()),
        Boundary::Ten => counts::CURRENT_INDEXES
            .iter()
            .copied()
            .chain(proof::CURRENT_INDEXES.iter().copied()),
    } {
        required.push((name, ddl, allow_missing_secondary));
    }
    for (name, ddl) in proof::INHERITED_INDEXES.iter().copied() {
        required.push((name, ddl, allow_missing_secondary));
    }
    for (name, expected, optional) in required {
        let row = db
            .query_one_raw(statement(
                "SELECT sql FROM sqlite_schema WHERE name=?",
                vec![name.into()],
            ))
            .await?;
        let Some(row) = row else {
            anyhow::ensure!(optional, "missing schema-nine audience declaration: {name}");
            continue;
        };
        let sql: String = row.try_get("", "sql")?;
        // Case-sensitive, including constraint literals. Only formatting whitespace is ignored.
        let normalized = |text: &str| {
            text.chars()
                .filter(|c| !c.is_ascii_whitespace())
                .collect::<String>()
        };
        anyhow::ensure!(
            normalized(&sql) == normalized(expected),
            "incompatible schema-nine audience declaration"
        );
    }
    if boundary == Boundary::Nine {
        let mut after = String::new();
        // Old pending operations keep their exact bytes, but malformed nested card identities must
        // not silently enter a new authorization schema. One row bounds retained historical bodies.
        loop {
            let row=db.query_one_raw(statement("SELECT identity,bot_id,chat_id,message_id,thread_id,original_input,watch_input,turn_id,version,state_json FROM bot_card_streams WHERE identity>? ORDER BY identity LIMIT 1",vec![after.clone().into()])).await?;
            let Some(row) = row else { break };
            after = row.try_get("", "identity")?;
            super::super::card::decode_stored(row)?;
        }
    }
    let mut after = String::new();
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT * FROM bot_audience_origins WHERE thread_id>? ORDER BY thread_id LIMIT 100",
                vec![after.clone().into()],
            ))
            .await?;
        let done = rows.len() < 100;
        for row in &rows {
            let origin = origin(row)?;
            if let super::super::target::TargetProof::Created { evidence } = &origin.target {
                if allow_missing_secondary {
                    super::super::target::check_sources_for_import(db, &origin, &evidence.bot_id)
                        .await?;
                } else {
                    super::super::target::check_sources(db, &origin, &evidence.bot_id).await?;
                }
            } else {
                anyhow::ensure!(origin.requires_upgrade, "unproven current creation target");
            }
            let proof_boundary = if allow_missing_secondary {
                proof::Boundary::ImportNine
            } else {
                proof::Boundary::Current
            };
            proof::collect(db, &origin.thread_id, proof_boundary)
                .await?
                .check(&origin, None)?;
            after = origin.thread_id;
        }
        if done {
            break;
        }
    }
    let mut after = (String::new(), 0i64);
    loop {
        let rows=db.query_all_raw(statement("SELECT * FROM bot_authorizations WHERE (chat_id,generation)>(?,?) ORDER BY chat_id,generation LIMIT 100",vec![after.0.clone().into(),after.1.into()])).await?;
        let done = rows.len() < 100;
        for row in rows {
            let auth = authorization(&row)?;
            let origin = super::read::read_origin(db, &auth.intent.thread_id)
                .await?
                .ok_or_else(|| anyhow::anyhow!("authorization has no proven origin"))?;
            anyhow::ensure!(
                auth.intent.authorization.chat_id == origin.chat_id
                    && auth.project_id == origin.project_id
                    && auth.creation_id == origin.creation_id
                    && auth.intent.binding_revision == origin.binding_revision,
                "authorization and creation identity conflict"
            );
            after = (
                auth.intent.authorization.chat_id,
                i64::try_from(auth.intent.authorization.generation)?,
            );
        }
        if done {
            break;
        }
    }
    anyhow::ensure!(
        db.query_one_raw(statement(
            "SELECT b.chat_id FROM thread_bindings b
        JOIN bot_audience_origins o ON b.thread_id=o.thread_id
        WHERE b.chat_id<>o.chat_id OR b.project_id<>o.project_id LIMIT 1",
            vec![]
        ))
        .await?
        .is_none(),
        "current route and audience origin conflict"
    );
    anyhow::ensure!(
        db.query_one_raw(statement(
            "SELECT a.chat_id FROM bot_authorizations a
        JOIN bot_audience_origins o ON a.thread_id=o.thread_id WHERE a.chat_id<>o.chat_id LIMIT 1",
            vec![]
        ))
        .await?
        .is_none(),
        "authorization and Thread target conflict"
    );
    let mut after = String::new();
    loop {
        let rows=db.query_all_raw(statement("SELECT operation_id,thread_id,request_json FROM bot_sync_operations WHERE operation_id>? ORDER BY operation_id LIMIT 64",vec![after.clone().into()])).await?;
        let done = rows.len() < 64;
        for row in rows {
            let operation: SyncOperation =
                serde_json::from_str(&row.try_get::<String>("", "request_json")?)?;
            after = row.try_get("", "operation_id")?;
            anyhow::ensure!(
                !after.is_empty()
                    && operation.request.operation_id == after
                    && operation.request.thread_id == row.try_get::<String>("", "thread_id")?,
                "invalid audience operation identity"
            );
            let auth = super::read::load_auth(db, &operation.authorization)
                .await?
                .ok_or_else(|| anyhow::anyhow!("audience operation has no authorization"))?;
            anyhow::ensure!(
                auth.intent.thread_id == operation.request.thread_id,
                "audience operation crosses Thread scope"
            );
        }
        if done {
            break;
        }
    }
    if boundary == Boundary::Nine {
        let mut after = (String::new(), 0i64, String::new());
        loop {
            let rows=db.query_all_raw(statement("SELECT chat_id,generation,item_id,thread_id,state_json FROM bot_delivery_items WHERE (chat_id,generation,item_id)>(?,?,?) ORDER BY chat_id,generation,item_id LIMIT 32",vec![after.0.clone().into(),after.1.into(),after.2.clone().into()])).await?;
            let done = rows.len() < 32;
            for row in rows {
                let observation: DeliveryObservation =
                    serde_json::from_str(&row.try_get::<String>("", "state_json")?)?;
                after = (
                    row.try_get("", "chat_id")?,
                    row.try_get("", "generation")?,
                    row.try_get("", "item_id")?,
                );
                anyhow::ensure!(
                    observation.item_id == after.2
                        && observation.authorization.chat_id == after.0
                        && i64::try_from(observation.authorization.generation)? == after.1
                        && observation.thread_id == row.try_get::<String>("", "thread_id")?,
                    "invalid delivery observation scope"
                );
                let auth = super::read::load_auth(db, &observation.authorization)
                    .await?
                    .ok_or_else(|| anyhow::anyhow!("delivery has no authorization"))?;
                anyhow::ensure!(
                    auth.intent.thread_id == observation.thread_id,
                    "delivery crosses Thread scope"
                );
            }
            if done {
                break;
            }
        }
    }
    anyhow::ensure!(
        db.query_one_raw(statement("PRAGMA foreign_key_check", vec![]))
            .await?
            .is_none(),
        "bot audience foreign key proof failed"
    );
    Ok(())
}

pub(in crate::bots::storage) async fn validate_target_structure<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    for table in ["thread_bindings", "binding_operations"] {
        let row=db.query_one_raw(statement("SELECT type,\"notnull\",hidden,dflt_value FROM pragma_table_xinfo(?) WHERE name='target_json'",vec![table.into()])).await?.ok_or_else(||anyhow::anyhow!("missing current creation target structure"))?;
        anyhow::ensure!(
            row.try_get::<String>("", "type")? == "TEXT"
                && row.try_get::<i64>("", "notnull")? == 1
                && row.try_get::<i64>("", "hidden")? == 0
                && row.try_get::<Option<String>>("", "dflt_value")?.as_deref()
                    == Some("'{\"kind\":\"unproven\"}'"),
            "incompatible creation target structure"
        );
        let key = if table == "thread_bindings" {
            "chat_id"
        } else {
            "operation_id"
        };
        // 空主键行同样必须被解码：首页不带 `>` 谓词，之后才按上一行续页。
        let mut after: Option<String> = None;
        loop {
            let rows = match &after {
                None => {
                    db.query_all_raw(statement(
                        &format!("SELECT {key},target_json FROM {table} ORDER BY {key} LIMIT 64"),
                        vec![],
                    ))
                    .await?
            }
                Some(after) => {
                    db.query_all_raw(statement(
                        &format!(
                            "SELECT {key},target_json FROM {table} WHERE {key}>? ORDER BY {key} LIMIT 64"
                        ),
                        vec![after.clone().into()],
                    ))
                    .await?
            }
            };
            let done = rows.len() < 64;
            for row in rows {
                after = Some(super::super::strict_text(&row, key)?);
                super::super::target::TargetProof::decode(&row)?;
            }
            if done {
                break;
            }
        }
    }
    Ok(())
}
