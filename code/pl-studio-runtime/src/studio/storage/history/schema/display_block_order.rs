//! One transactional upgrade from the published schema22 display index.
use super::*;
use crate::studio::storage::history::conversation::display::validate_header;
use crate::studio::thread_projection::presentation::DisplayHeader;

pub(super) struct DisplayBlockOrder;
impl MigrationName for DisplayBlockOrder {
    fn name(&self) -> &str {
        DISPLAY_BLOCK_ORDER
    }
}
#[sea_orm_migration::async_trait::async_trait]
impl MigrationTrait for DisplayBlockOrder {
    fn use_transaction(&self) -> Option<bool> {
        Some(true)
    }
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        upgrade(manager.get_connection()).await.map_err(conversion)
    }
}

async fn upgrade(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 22,
        "display order migration requires schema22"
    );
    work_snapshots::validate_preserved(db).await?;
    db.execute_unprepared("CREATE TABLE conversation_display_blocks_v23(
        block_id TEXT NOT NULL PRIMARY KEY,source_key TEXT NOT NULL,
        block_order INTEGER NOT NULL UNIQUE CHECK(block_order>0),
        sealed INTEGER NOT NULL CHECK(sealed IN (0,1)),updated_effect INTEGER NOT NULL,header BLOB NOT NULL);
        CREATE TABLE conversation_display_members_v23(
        block_id TEXT NOT NULL,member_order INTEGER NOT NULL CHECK(member_order>0),
        member_key TEXT NOT NULL UNIQUE,association_key TEXT NOT NULL,
        terminal INTEGER NOT NULL CHECK(terminal IN (0,1)),completion_id TEXT,
        updated_effect INTEGER NOT NULL,metadata BLOB NOT NULL,
        PRIMARY KEY(block_id,member_order),
        FOREIGN KEY(block_id) REFERENCES conversation_display_blocks_v23(block_id)) WITHOUT ROWID;").await?;
    let mut last_order = 0u64;
    let mut first_open = None;
    // Published order is authoritative even when it differs from original creation order.
    for published in [true, false] {
        let column = if published {
            "history_pos"
        } else {
            "block_order"
        };
        let condition = if published {
            "history_pos IS NOT NULL"
        } else {
            "history_pos IS NULL"
        };
        let mut after = 0i64;
        loop {
            let rows=db.query_all_raw(statement(&format!("SELECT block_id,source_key,block_order,history_pos,sealed,updated_effect,header FROM conversation_display_blocks WHERE {condition} AND {column}>? ORDER BY {column} LIMIT 128"),vec![after.into()])).await?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                after = row.try_get("", column)?;
                let mut value: serde_json::Value =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "header")?)?;
                ensure!(
                    value["version"] == 4 && value["skip_display"] == false,
                    "invalid schema22 display header; original history preserved"
                );
                ensure!(
                    value["id"].as_str() == Some(row.try_get::<String>("", "block_id")?.as_str())
                        && value["block_order"].as_u64()
                            == Some(u64::try_from(row.try_get::<i64>("", "block_order")?)?)
                        && value["history_pos"].as_u64()
                            == row
                                .try_get::<Option<i64>>("", "history_pos")?
                                .map(u64::try_from)
                                .transpose()?,
                    "schema22 display identity differs"
                );
                last_order = last_order
                    .checked_add(1)
                    .filter(|order| *order <= i64::MAX as u64)
                    .context("display order exhausted")?;
                value["version"] = 5.into();
                value["block_order"] = last_order.into();
                let object = value
                    .as_object_mut()
                    .context("display header must be an object")?;
                object.remove("history_pos");
                object.remove("skip_display");
                let header: DisplayHeader = serde_json::from_value(value)?;
                validate_header(&header)?;
                ensure!(
                    header.sealed == (row.try_get::<i64>("", "sealed")? == 1)
                        && serde_json::to_string(&header.source)?
                            == row.try_get::<String>("", "source_key")?,
                    "schema22 display indexed values differ"
                );
                ensure!(
                    !published || header.sealed,
                    "published display is not frozen"
                );
                if !header.sealed && first_open.is_none() {
                    first_open = Some(last_order);
                }
                db.execute_raw(statement("INSERT INTO conversation_display_blocks_v23(block_id,source_key,block_order,sealed,updated_effect,header) VALUES(?,?,?,?,?,?)",vec![header.id.clone().into(),serde_json::to_string(&header.source)?.into(),integer(last_order)?.into(),i64::from(header.sealed).into(),row.try_get::<i64>("","updated_effect")?.into(),serde_json::to_vec(&header)?.into()])).await?;
            }
        }
    }
    let mut block = String::new();
    let mut member = 0i64;
    loop {
        let rows=db.query_all_raw(statement("SELECT * FROM conversation_display_members WHERE (block_id,member_order)>(?,?) ORDER BY block_id,member_order LIMIT 128",vec![block.clone().into(),member.into()])).await?;
        if rows.is_empty() {
            break;
        }
        let decoded = rows
            .iter()
            .map(conversation::display::decode_member)
            .collect::<Result<Vec<_>>>()?;
        conversation::display::validate_original_references(db, &decoded).await?;
        let last = rows.last().expect("nonempty page");
        let next_block: String = last.try_get("", "block_id")?;
        let next_member: i64 = last.try_get("", "member_order")?;
        db.execute_raw(statement("INSERT INTO conversation_display_members_v23 SELECT * FROM conversation_display_members WHERE (block_id,member_order)>(?,?) AND (block_id,member_order)<=(?,?)",vec![block.into(),member.into(),next_block.clone().into(),next_member.into()])).await?;
        block = next_block;
        member = next_member;
    }
    for (old, new, keys) in [
        (
            "conversation_display_blocks",
            "conversation_display_blocks_v23",
            "block_id,source_key,sealed,updated_effect",
        ),
        (
            "conversation_display_members",
            "conversation_display_members_v23",
            "*",
        ),
    ] {
        for (left, right) in [(old, new), (new, old)] {
            ensure!(
                db.query_one_raw(statement(
                    &format!("SELECT {keys} FROM {left} EXCEPT SELECT {keys} FROM {right} LIMIT 1"),
                    vec![]
                ))
                .await?
                .is_none(),
                "display migration changed preserved identities or member bytes"
            );
        }
    }
    ensure!(
        db.query_one_raw(statement(
            "PRAGMA foreign_key_check(conversation_display_members_v23)",
            vec![]
        ))
        .await?
        .is_none(),
        "display migration has invalid member owners"
    );
    db.execute_unprepared("DROP TABLE conversation_display_members;
        DROP TABLE conversation_display_blocks;
        ALTER TABLE conversation_display_blocks_v23 RENAME TO conversation_display_blocks;
        ALTER TABLE conversation_display_members_v23 RENAME TO conversation_display_members;
        CREATE INDEX conversation_display_open ON conversation_display_blocks(block_order) WHERE sealed=0;
        CREATE UNIQUE INDEX conversation_display_current_work ON conversation_display_blocks((1)) WHERE sealed=0 AND json_extract(header,'$.body.kind')='work';
        CREATE INDEX conversation_display_unfinished ON conversation_display_members(block_id,member_order) WHERE terminal=0;
        ALTER TABLE history_meta RENAME COLUMN display_published_through TO display_ready_frontier;
        ALTER TABLE history_meta ADD COLUMN display_last_order INTEGER NOT NULL DEFAULT 0 CHECK(display_last_order>=0);").await?;
    let frontier = first_open.map_or(last_order, |order| order - 1);
    db.execute_raw(statement("UPDATE history_meta SET schema_version=23,display_ready_frontier=?,display_last_order=? WHERE id=1",vec![integer(frontier)?.into(),integer(last_order)?.into()])).await?;
    validate(db).await
}

pub(super) async fn validate(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        version(db).await? == 23,
        "display block order format is not current"
    );
    immutable_completion_runs::validate_preserved(db).await?;
    super::validate_keys(
        db,
        "conversation_display_blocks",
        &["block_id"],
        false,
        &["block_order"],
    )
    .await?;
    super::validate_keys(
        db,
        "conversation_display_members",
        &["block_id", "member_order"],
        false,
        &["member_key"],
    )
    .await?;
    db.query_all_raw(statement("SELECT block_id,source_key,block_order,sealed,updated_effect,header FROM conversation_display_blocks LIMIT 0",vec![])).await?;
    let row=db.query_one_raw(statement("SELECT display_ready_frontier,display_last_order,display_applied_effect,applied_write_seq FROM history_meta WHERE id=1",vec![])).await?.context("display metadata missing")?;
    let frontier: i64 = row.try_get("", "display_ready_frontier")?;
    ensure!(
        frontier >= 0
            && frontier <= row.try_get::<i64>("", "display_last_order")?
            && row.try_get::<i64>("", "display_applied_effect")?
                <= row.try_get::<i64>("", "applied_write_seq")?,
        "invalid display metadata cut"
    );
    for name in [
        "conversation_display_open",
        "conversation_display_current_work",
        "conversation_display_unfinished",
    ] {
        ensure!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE type='index' AND name=?",
                vec![name.into()]
            ))
            .await?
            .is_some(),
            "display index missing"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::{ChatSourceId, DisplayBlockBody, DisplayBlockRef, WorkTiming};

    const THREAD: &str = "display-snapshot-migration";

    #[tokio::test]
    async fn schema22_preparation_rejects_missing_structure_and_earlier_pending_migrations()
    -> Result<()> {
        async fn snapshot(db: &DatabaseConnection) -> Result<Vec<String>> {
            Ok(db
                .query_all_raw(statement(
                    "SELECT json_array(type,name,tbl_name,sql) AS fact FROM sqlite_schema
                     UNION ALL SELECT json_array(version,applied_at) FROM seaql_migrations
                     ORDER BY fact",
                    vec![],
                ))
                .await?
                .iter()
                .map(|row| row.try_get("", "fact"))
                .collect::<std::result::Result<Vec<_>, _>>()?)
        }

        for (damage, diagnostic) in [
            (
                "DROP INDEX conversation_display_current_work",
                "unique display tail index is missing",
            ),
            (
                "DELETE FROM seaql_migrations WHERE version='m20261108_000001_history_source_classification'",
                "schema 22 has pending earlier content migrations",
            ),
        ] {
            let (_dir, db) = work_snapshots::tests::fixture().await?;
            Migrator {
                thread_id: THREAD.into(),
                execution_identity: None,
                bot_root: None,
            }
            .up(&db, Some(1))
            .await?;
            db.execute_unprepared(damage).await?;
            let before = snapshot(&db).await?;
            let error = super::super::prepare(&db, THREAD, Preparation::Schema, None)
                .await
                .expect_err("inconsistent schema22 must be rejected before migration");
            assert!(format!("{error:#}").contains(diagnostic), "{error:#}");
            assert_eq!(version(&db).await?, 22);
            assert_eq!(snapshot(&db).await?, before);
        }
        Ok(())
    }

    #[tokio::test]
    async fn nonempty_upgrade_preserves_published_order_original_bytes_and_rolls_back_before_retry()
    -> Result<()> {
        let (_dir, db) = work_snapshots::tests::fixture().await?;
        let migrator = Migrator {
            thread_id: THREAD.into(),
            execution_identity: None,
            bot_root: None,
        };
        migrator.up(&db, Some(1)).await?;
        assert_eq!(version(&db).await?, 22);
        for seq in 1..=2i64 {
            db.execute_raw(statement("INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata,display_run_start,display_run_ordinal) VALUES(?,?,'conversation',NULL,?,?,NULL,NULL)",vec![seq.into(),format!("original-{seq}").into(),vec![0u8,255,seq as u8].into(),conversation::tests::metadata(&format!("original-{seq}")).to_vec().into()])).await?;
        }
        let original = db
            .query_all_raw(statement(
                "SELECT item_id,seq,payload,metadata FROM conversation_items ORDER BY seq",
                vec![],
            ))
            .await?;
        let database = db
            .query_one_raw(statement(
                "SELECT database_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .unwrap()
            .try_get::<String>("", "database_id")?;
        // Produce a real frozen observation, then encode only its header in the
        // published v4 shape. Original payload/body storage is shared by both schemas.
        use crate::studio::thread_projection::presentation::{ObservationInput, PresentationState};
        use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
        use pl_protocol::{
            ChatActiveStatus, ChatAtom, ChatAtomContent, ChatAtomKind, ChatAtomLifecycle,
            ChatContentRole, ChatFactPosition, ContentOwner, ContentRef, ContentTarget,
        };
        let mut atom: ChatAtom =
            serde_json::from_slice(&conversation::tests::metadata("observed-tool"))?;
        atom.kind = ChatAtomKind::ToolCall;
        atom.delivery = pl_protocol::ChatDeliveryKind::Foreground;
        atom.source = ChatSourceId::ForegroundTurn {
            turn_id: "observed-turn".into(),
        };
        atom.completion_item_id = None;
        atom.completion_seq = None;
        atom.payload = None;
        atom.lifecycle = ChatAtomLifecycle::Active {
            started: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            status: ChatActiveStatus::Running,
        };
        let owner = ContentOwner::Item {
            item_id: atom.id.clone(),
        };
        atom.contents = vec![ChatAtomContent {
            role: ChatContentRole::ToolOutput,
            reference: ContentRef {
                database_id: database.clone(),
                target: ContentTarget::Body {
                    owner: owner.clone(),
                    key: "tool.result".into(),
                },
            },
        }];
        let content = Arc::new(ChatContent {
            descriptor: ContentDescriptor {
                key: ChatContentKey {
                    owner: crate::studio::conversation_identity::content_owner_key(&owner)?,
                    key: "tool.result".into(),
                },
                byte_length: 6,
                generation: 1,
                media_type: None,
            },
            data: ContentData::Bytes(Arc::from(&b"prefix"[..])),
        });
        let mut state = PresentationState::default();
        state.bind(&database)?;
        state.prepare(1, 10, &[atom.clone()], &[], &[])?;
        let mut boundary = atom.clone();
        boundary.id = "boundary-text".into();
        boundary.kind = ChatAtomKind::Text;
        boundary.content_present = Some(true);
        boundary.contents.clear();
        boundary.lifecycle = ChatAtomLifecycle::Active {
            started: Some(ChatFactPosition {
                effect_seq: 2,
                suborder: 0,
            }),
            status: ChatActiveStatus::Running,
        };
        let observation = state.prepare_capturing(2, 20, &[boundary], &[], &[], |_| {
            Ok(ObservationInput::for_test(
                atom.clone(),
                vec![content.clone()],
            ))
        })?;
        let frozen = observation
            .blocks
            .iter()
            .find(|block| block.header.sealed)
            .unwrap();
        let waiting_id = frozen.header.id.as_str();
        for content in &observation.contents {
            conversation::content::write_content(&db, content, true).await?;
        }
        let member = observation
            .members
            .iter()
            .find(|member| member.block_id == waiting_id)
            .unwrap();
        let member_bytes = serde_json::to_vec(member)?;
        for (id, order, published, sealed) in [
            ("published-first", 3, Some(1), true),
            ("published-second", 1, Some(2), true),
            (waiting_id, 2, None, true),
            ("open-tail", 4, None, false),
        ] {
            let header = work_snapshots::DisplayHeader {
                version: 4,
                id: id.into(),
                source: ChatSourceId::ForegroundTurn { turn_id: id.into() },
                block_order: order,
                history_pos: published,
                boundary: None,
                first_content_at: None,
                sealed,
                unfinished: 0,
                next_member: 0,
                revision: 1,
                skip_display: false,
                thinking_summary: None,
                body: DisplayBlockBody::Work {
                    timing: WorkTiming {
                        started_at: Some(1),
                        finished_at: sealed.then_some(2),
                    },
                    members: DisplayBlockRef {
                        database_id: database.clone(),
                        block_id: id.into(),
                    },
                },
            };
            db.execute_raw(statement("INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header) VALUES(?,?,?,?,?,0,?)",vec![id.into(),serde_json::to_string(&header.source)?.into(),integer(order)?.into(),published.map(integer).transpose()?.into(),i64::from(sealed).into(),serde_json::to_vec(&header)?.into()])).await?;
        }
        let mut old_header = serde_json::to_value(frozen.header.as_ref())?;
        old_header["version"] = 4.into();
        old_header["block_order"] = 2.into();
        old_header["history_pos"] = serde_json::Value::Null;
        old_header["skip_display"] = false.into();
        db.execute_raw(statement(
            "UPDATE conversation_display_blocks SET source_key=?,header=? WHERE block_id=?",
            vec![
                serde_json::to_string(&frozen.header.source)?.into(),
                serde_json::to_vec(&old_header)?.into(),
                waiting_id.into(),
            ],
        ))
        .await?;
        db.execute_raw(statement("INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata) VALUES(?,1,?,?,0,NULL,0,?)", vec![
            waiting_id.into(), member.head.member_key.clone().into(), member.association_key.clone().into(), member_bytes.clone().into()
        ])).await?;
        db.execute_unprepared("UPDATE history_meta SET display_published_through=2 WHERE id=1;

            CREATE TRIGGER reject_display_version BEFORE UPDATE OF schema_version ON history_meta WHEN NEW.schema_version=23 BEGIN SELECT RAISE(ABORT,'controlled migration failure'); END;").await?;
        let error = super::super::prepare(&db, THREAD, Preparation::Schema, None)
            .await
            .expect_err("injected failure must roll back the entire migration including DDL");
        assert!(
            format!("{error:#}").contains("controlled migration failure"),
            "{error:#}"
        );
        assert_eq!(version(&db).await?, 22);
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM seaql_migrations WHERE version=?",
                vec![DISPLAY_BLOCK_ORDER.into()]
            ))
            .await?
            .is_none()
        );
        assert!(
            db.query_one_raw(statement(
                "SELECT 1 FROM sqlite_schema WHERE name LIKE 'conversation_display_%_v23'",
                vec![]
            ))
            .await?
            .is_none()
        );
        assert!(
            db.query_all_raw(statement(
                "SELECT history_pos FROM conversation_display_blocks",
                vec![]
            ))
            .await
            .is_ok()
        );
        db.execute_unprepared("DROP TRIGGER reject_display_version")
            .await?;
        super::super::prepare(&db, THREAD, Preparation::Schema, None).await?;
        super::super::prepare(&db, THREAD, Preparation::Schema, None).await?;
        validate(&db).await?;
        let heads = conversation::display::block_page(&db, 0, 4, 10, true).await?;
        assert_eq!(
            heads
                .iter()
                .map(|head| (head.id.as_str(), head.block_order.get()))
                .collect::<Vec<_>>(),
            [
                ("published-first", 1),
                ("published-second", 2),
                (waiting_id, 3),
                ("open-tail", 4)
            ]
        );
        assert_eq!(conversation::display::watermarks(&db).await?, (3, 0));
        let current = db
            .query_all_raw(statement(
                "SELECT item_id,seq,payload,metadata FROM conversation_items ORDER BY seq",
                vec![],
            ))
            .await?;
        assert_eq!(current.len(), original.len());
        for (before, after) in original.iter().zip(&current) {
            assert_eq!(
                before.try_get::<String>("", "item_id")?,
                after.try_get::<String>("", "item_id")?
            );
            assert_eq!(
                before.try_get::<i64>("", "seq")?,
                after.try_get::<i64>("", "seq")?
            );
            for field in ["payload", "metadata"] {
                assert_eq!(
                    before.try_get::<Vec<u8>>("", field)?,
                    after.try_get::<Vec<u8>>("", field)?
                );
            }
        }
        let saved_member = db
            .query_one_raw(statement(
                "SELECT metadata FROM conversation_display_members WHERE block_id=?",
                vec![waiting_id.into()],
            ))
            .await?
            .unwrap();
        assert_eq!(
            saved_member.try_get::<Vec<u8>>("", "metadata")?,
            member_bytes
        );
        assert!(
            !member.terminal,
            "frozen observation must remain distinct from a completion"
        );
        for content in &observation.contents {
            let expected = content.data.range(0, content.data.len())?;
            assert_eq!(
                conversation::content::read_body_bytes(
                    &db,
                    &content.descriptor.key,
                    0,
                    content.data.len()
                )
                .await?,
                expected.as_bytes()
            );
        }
        let recovery = conversation::display::recovery(&db).await?;
        assert!(
            recovery.unfinished.is_empty(),
            "frozen nonterminal observations must not resume execution"
        );
        let pending = migrator.get_pending_migrations_read_only(&db).await?;
        assert!(
            !pending
                .iter()
                .any(|migration| migration.name() == DISPLAY_BLOCK_ORDER)
        );
        assert!(
            db.query_one_raw(statement("PRAGMA foreign_key_check", vec![]))
                .await?
                .is_none()
        );
        Ok(())
    }
}
