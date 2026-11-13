//! Actual production display SQL, sampled only after fixture setup finishes.
use super::super::run_read_tests::sqlite_work::{Sampler, Work};
use super::*;
use crate::studio::thread_projection::presentation::PresentationState;
use pl_protocol::{
    ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatFactPosition, ChatSourceId,
    ChatTerminalOutcome, DisplayMemberHead, LiveDisplayBlock,
};

fn report(case: &str, history: u64, members: u64, encoded: usize, work: &Work) {
    eprintln!(
        "DISPLAY_SQL_COST {}",
        serde_json::json!({
            "query":case, "frozen_history":history, "group_members":members,
            "statements":work.statements, "selected_heads":work.candidates,
            "selected_members":work.member_rows, "selected_reference_rows":work.reference_rows,
            "selected_rows":work.candidates + work.member_rows + work.reference_rows,
            "vm_steps":work.vm_steps, "fullscan_steps":work.fullscan_steps,
            "encoded_head_or_member_bytes":encoded, "denied_reads":work.denied_reads,
            "original_payload_authorizations":work.payload_column_authorizations,
        })
    );
}

async fn seed_history(
    db: &impl ConnectionTrait,
    base: &DisplayHeader,
    member: &DisplayMemberWrite,
    after: u64,
    through: u64,
) -> Result<()> {
    db.execute_raw(statement(
        "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
         INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header)
         SELECT 'history-'||i,?,i+CASE WHEN i>20 THEN 1 ELSE 0 END,i,1,2,
             CAST(json_set(?,'$.id','history-'||i,'$.block_order',i+CASE WHEN i>20 THEN 1 ELSE 0 END,
                 '$.history_pos',i,'$.body.members.blockId','history-'||i) AS BLOB) FROM n",
        vec![integer(after+1)?.into(), integer(through)?.into(),
            serde_json::to_string(&base.source)?.into(), serde_json::to_string(base)?.into()]
    )).await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata)
         SELECT block_id,1,block_id||':member:1',block_id||':association:1',1,NULL,2,
             CAST(json_set(?,'$.block_id',block_id,'$.head.memberOrder',1,
                 '$.head.memberKey',block_id||':member:1','$.association_key',block_id||':association:1','$.head.record.atom.id','tool-'||block_id) AS BLOB)
         FROM conversation_display_blocks WHERE history_pos>? AND history_pos<=? AND block_id<>'history-20'",
        vec![serde_json::to_string(member)?.into(), integer(after)?.into(), integer(through)?.into()]
    )).await?;
    db.execute_raw(statement("UPDATE history_meta SET applied_write_seq=2,display_applied_effect=2,display_published_through=? WHERE id=1",
        vec![integer(through)?.into()])).await?;
    Ok(())
}

async fn seed_members(
    db: &impl ConnectionTrait,
    base: &DisplayMemberWrite,
    headers: &mut [DisplayHeader; 2],
    after: u64,
    through: u64,
) -> Result<()> {
    db.execute_raw(statement(
        "WITH RECURSIVE n(i) AS (SELECT ? UNION ALL SELECT i+1 FROM n WHERE i<?)
         INSERT INTO conversation_display_members(block_id,member_order,member_key,association_key,terminal,completion_id,updated_effect,metadata)
         SELECT b.block_id,i,b.block_id||':member:'||i,b.block_id||':association:'||i,1,NULL,2,
             CAST(json_set(?,'$.block_id',b.block_id,'$.head.memberOrder',i,
                 '$.head.memberKey',b.block_id||':member:'||i,'$.association_key',b.block_id||':association:'||i,'$.head.record.atom.id','tool-'||i,
                 '$.head.record.atom.source',json_extract(b.header,'$.source')) AS BLOB)
         FROM n CROSS JOIN conversation_display_blocks b WHERE b.block_id IN ('history-20','open-work')",
        vec![integer(after+1)?.into(), integer(through)?.into(), serde_json::to_string(base)?.into()]
    )).await?;
    for header in headers {
        header.next_member = through;
        header.revision = through;
        db.execute_raw(statement(
            "UPDATE conversation_display_blocks SET header=? WHERE block_id=?",
            vec![serde_json::to_vec(header)?.into(), header.id.clone().into()],
        ))
        .await?;
    }
    Ok(())
}

#[tokio::test]
async fn display_sql_cost_is_bounded_across_frozen_history_and_hundred_thousand_members()
-> Result<()> {
    let (_dir, db) =
        crate::studio::storage::history::schema::work_snapshots::tests::fixture().await?;
    crate::studio::storage::history::schema::work_snapshots::initialize(&db).await?;

    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("database")?
        .try_get("", "database_id")?;
    let mut owner = PresentationState::default();
    owner.bind(&database)?;
    let mut atom: pl_protocol::ChatAtom =
        serde_json::from_slice(&super::super::tests::metadata("cost-seed"))?;
    atom.completion_item_id = None;
    atom.source = ChatSourceId::ForegroundTurn {
        turn_id: "history-turn".into(),
    };
    atom.kind = ChatAtomKind::ToolCall;
    atom.delivery = ChatDeliveryKind::Foreground;
    atom.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(ChatFactPosition {
            effect_seq: 1,
            suborder: 0,
        }),
        outcome: ChatTerminalOutcome::Cancelled,
    };
    let seed = owner.prepare(1, 10, &[atom], &[], &[])?;
    let mut frozen = seed.blocks[0].header.as_ref().clone();
    frozen.id = "history-20".into();
    frozen.block_order = 20;
    frozen.history_pos = Some(20);
    frozen.sealed = true;
    frozen.boundary = Some(ChatFactPosition {
        effect_seq: 2,
        suborder: 0,
    });
    if let DisplayBlockBody::Work { timing, members } = &mut frozen.body {
        timing.finished_at = Some(20);
        members.block_id = frozen.id.clone();
    }
    seed_history(&db, &frozen, &seed.members[0], 0, 20).await?;
    let mut open = frozen.clone();
    open.id = "open-work".into();
    open.source = ChatSourceId::ForegroundTurn {
        turn_id: "open-turn".into(),
    };
    open.block_order = 21;
    open.history_pos = None;
    open.boundary = None;
    open.sealed = false;
    if let DisplayBlockBody::Work { timing, members } = &mut open.body {
        timing.finished_at = None;
        members.block_id = open.id.clone();
    }
    db.execute_raw(statement(
        "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,sealed,updated_effect,header) VALUES(?,?,21,NULL,0,2,?)",
        vec![open.id.clone().into(), serde_json::to_string(&open.source)?.into(), serde_json::to_vec(&open)?.into()]
    )).await?;
    let mut headers = [frozen.clone(), open];
    let mut previous_members = 0;
    let mut previous_history = 20;
    let mut baseline: Option<[u64; 3]> = None;
    for (history, members) in [(20, 20), (20, 100_000), (100_000, 100_000)] {
        // All setup is outside native sampling windows. This fixture contains lightweight
        // saved rows only; it does not reproduce the production SELECT implementation.
        if history > previous_history {
            seed_history(&db, &frozen, &seed.members[0], previous_history, history).await?;
        }
        if members > previous_members {
            seed_members(
                &db,
                &seed.members[0],
                &mut headers,
                previous_members,
                members,
            )
            .await?;
        }
        previous_history = history;
        previous_members = members;

        let sampler = Sampler::display_heads(&db).await?;
        let outcome = history_heads(&db, 20, Some(21), 20).await;
        let work = sampler.finish(&db).await?;
        let heads = outcome?;
        assert_eq!(heads.len(), 20);
        assert_eq!(
            (
                work.statements,
                work.candidates,
                work.member_rows,
                work.reference_rows
            ),
            (1, 20, 0, 0)
        );
        assert_eq!(
            (
                work.denied_reads,
                work.payload_column_authorizations,
                work.fullscan_steps
            ),
            (0, 0, 0)
        );
        let history_vm = work.vm_steps;
        report(
            "history_heads",
            history,
            members,
            serde_json::to_vec(&heads)?.len(),
            &work,
        );

        let sampler = Sampler::display_heads(&db).await?;
        let outcome = open_heads(&db, None, 1).await;
        let work = sampler.finish(&db).await?;
        let heads = outcome?;
        assert_eq!(
            (
                work.statements,
                work.candidates,
                work.member_rows,
                work.reference_rows
            ),
            (1, 1, 0, 0)
        );
        assert_eq!(
            (
                work.denied_reads,
                work.payload_column_authorizations,
                work.fullscan_steps
            ),
            (0, 0, 0)
        );
        let live = heads
            .into_iter()
            .map(|header| LiveDisplayBlock {
                has_unfinished_members: false,
                thinking_summary: None,
                id: header.id,
                block_order: header.block_order,
                source: Some(header.source),
                body: header.body,
                state: if header.sealed {
                    pl_protocol::DisplayBlockState::Sealed
                } else {
                    pl_protocol::DisplayBlockState::Open
                },
            })
            .collect::<Vec<_>>();
        assert_eq!(live.len(), 1);
        let open_vm = work.vm_steps;
        report(
            "open_heads",
            history,
            members,
            serde_json::to_vec(&live)?.len(),
            &work,
        );

        let sampler = Sampler::display_members(&db).await?;
        let outcome = member_page(&db, "history-20", None, 20).await;
        let work = sampler.finish(&db).await?;
        let page = outcome?;
        assert_eq!(
            (
                work.statements,
                work.candidates,
                work.member_rows,
                work.reference_rows
            ),
            (2, 0, 20, 1)
        );
        assert_eq!(
            (
                work.denied_reads,
                work.payload_column_authorizations,
                work.fullscan_steps
            ),
            (0, 0, 0)
        );
        let page = page
            .into_iter()
            .map(|member| member.head)
            .collect::<Vec<DisplayMemberHead>>();
        assert_eq!(page.len(), 20);
        assert!(
            page.iter().all(|member| !matches!(
                member.record.atom.payload,
                Some(PayloadData::Inline { .. })
            ))
        );
        report(
            "member_page",
            history,
            members,
            serde_json::to_vec(&page)?.len(),
            &work,
        );
        let measured = [history_vm, open_vm, work.vm_steps];
        if let Some(baseline) = baseline {
            for (actual, initial) in measured.into_iter().zip(baseline) {
                assert!(
                    actual <= initial + 128,
                    "VM work grew with unselected history/members: {measured:?} vs {baseline:?}"
                );
            }
        } else {
            baseline = Some(measured);
        }
    }
    db.close().await?;
    Ok(())
}

#[tokio::test]
async fn v364_hundred_thousand_terminal_rows_commit_and_release_before_any_boundary() -> Result<()>
{
    let (_dir, db) =
        crate::studio::storage::history::schema::work_snapshots::tests::fixture().await?;
    crate::studio::storage::history::schema::work_snapshots::initialize(&db).await?;

    let database: String = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .unwrap()
        .try_get("", "database_id")?;
    let mut owner = PresentationState::default();
    owner.bind(&database)?;
    let mut tail_id = None;
    let mut last = None;
    for batch in 0..400u64 {
        let effect = batch + 1;
        let mut facts = Vec::new();
        for offset in 0..250u32 {
            let index = batch * 250 + u64::from(offset) + 1;
            let mut atom: pl_protocol::ChatAtom = serde_json::from_slice(
                &super::super::tests::metadata(&format!("long-tail-{index}")),
            )?;
            atom.kind = ChatAtomKind::ToolCall;
            atom.tool = Some(pl_protocol::ChatToolIdentity {
                call_id: format!("call-{index}"),
                name: "exec".into(),
            });
            atom.source = if index % 2 == 0 {
                ChatSourceId::BackgroundResult {
                    message_id: format!("result-{index}"),
                }
            } else {
                ChatSourceId::ForegroundTurn {
                    turn_id: "long-tail".into(),
                }
            };
            atom.delivery = if index % 2 == 0 {
                ChatDeliveryKind::Independent
            } else {
                ChatDeliveryKind::Foreground
            };
            atom.completion_item_id = None;
            atom.completion_seq = None;
            atom.contents.clear();
            atom.payload = None;
            atom.lifecycle = ChatAtomLifecycle::Terminal {
                started: None,
                ended: Some(ChatFactPosition {
                    effect_seq: effect,
                    suborder: offset,
                }),
                outcome: ChatTerminalOutcome::Cancelled,
            };
            facts.push(atom);
        }
        let measured = matches!(batch, 0 | 39 | 399);
        if measured {
            owner.begin_cost_observation();
        }
        let delta = owner.prepare(effect, effect as i64, &facts, &[], &[])?;
        assert_eq!(delta.blocks.len(), 1);
        assert_eq!(delta.members.len(), 250);
        let id = &delta.blocks[0].header.id;
        assert!(tail_id.as_ref().is_none_or(|previous| previous == id));
        tail_id = Some(id.clone());
        assert!(!delta.blocks[0].header.sealed);
        assert_eq!(delta.published_through, 0);
        let tx = db.begin().await?;
        apply(&tx, &delta).await?;
        tx.execute_raw(statement(
            "UPDATE history_meta SET applied_write_seq=? WHERE id=1",
            vec![integer(effect)?.into()],
        ))
        .await?;
        tx.commit().await?;
        owner.confirm(effect);
        assert_eq!(owner.resident_member_count(), 0);
        if measured {
            let visits = owner.finish_cost_observation();
            assert_eq!(visits.members.keys.len(), 250);
            assert_eq!(visits.heads.keys.len(), 1);
            assert!(
                visits
                    .members
                    .keys
                    .iter()
                    .all(|(_, position)| *position > batch * 250 && *position <= effect * 250)
            );
            eprintln!(
                "TAIL_COMMIT_COST {}",
                serde_json::json!({
                    "durable_members": effect * 250, "resident_members": owner.resident_member_count(),
                    "retained_bytes": owner.retained_bytes(), "member_reads": visits.members.reads,
                    "member_writes": visits.members.writes, "unique_members": visits.members.keys.len(),
                    "unique_heads": visits.heads.keys.len(), "head_reads": visits.heads.reads,
                    "head_writes": visits.heads.writes,
                })
            );
        }
        last = facts.pop();
    }
    let duplicate = last.unwrap();
    let duplicate_delta =
        owner.prepare(401, 1_000_000, std::slice::from_ref(&duplicate), &[], &[])?;
    assert!(
        duplicate_delta.members.is_empty(),
        "released terminal replay must not create a row"
    );
    assert!(duplicate_delta.blocks.is_empty());
    let tx = db.begin().await?;
    apply(&tx, &duplicate_delta).await?;
    tx.execute_unprepared("UPDATE history_meta SET applied_write_seq=401 WHERE id=1")
        .await?;
    tx.commit().await?;
    owner.confirm(401);
    let recovery = recovery(&db).await?;
    assert_eq!(recovery.open.len(), 1);
    assert!(recovery.unfinished.is_empty());
    assert_eq!(recovery.open[0].next_member, 100_000);
    let mut cold = PresentationState::default();
    cold.restore(
        &database,
        recovery.published,
        recovery.last_order,
        recovery.effect,
        recovery.open,
        recovery.unfinished,
    )?;
    assert_eq!(cold.resident_member_count(), 0);
    assert!(cold.retained_bytes() < 4096);
    let id = tail_id.unwrap();
    let sampler = Sampler::display_heads(&db).await?;
    let heads = open_heads(&db, None, 1).await;
    let work = sampler.finish(&db).await?;
    let heads = heads?;
    assert_eq!(heads[0].id, id);
    assert_eq!(
        (
            work.candidates,
            work.member_rows,
            work.fullscan_steps,
            work.denied_reads
        ),
        (1, 0, 0, 0)
    );
    report(
        "long_open_tail_head",
        0,
        100_000,
        serde_json::to_vec(&heads)?.len(),
        &work,
    );
    let sampler = Sampler::display_members(&db).await?;
    let page = member_page(&db, &id, None, 2).await;
    let work = sampler.finish(&db).await?;
    let page = page?;
    assert_eq!(
        page.iter().map(|m| m.head.member_order).collect::<Vec<_>>(),
        [99_999, 100_000]
    );
    assert_eq!(
        (work.member_rows, work.fullscan_steps, work.denied_reads),
        (2, 0, 0)
    );
    report(
        "long_open_tail_members",
        0,
        100_000,
        serde_json::to_vec(&page)?.len(),
        &work,
    );
    let mut next = duplicate;
    next.id = "after-cold".into();
    next.source = ChatSourceId::BackgroundResult {
        message_id: "after-cold".into(),
    };
    next.tool = Some(pl_protocol::ChatToolIdentity {
        call_id: "after-cold".into(),
        name: "exec".into(),
    });
    next.lifecycle = ChatAtomLifecycle::Terminal {
        started: None,
        ended: Some(ChatFactPosition {
            effect_seq: 402,
            suborder: 0,
        }),
        outcome: ChatTerminalOutcome::Cancelled,
    };
    let delta = cold.prepare(402, 2_000_000, &[next], &[], &[])?;
    assert_eq!(delta.blocks[0].header.id, id);
    assert_eq!(delta.members[0].head.member_order, 100_001);
    Ok(())
}
