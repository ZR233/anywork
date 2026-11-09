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
         INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,updated_effect,header)
         SELECT 'history-'||i,?,i+CASE WHEN i>20 THEN 1 ELSE 0 END,i,2,
             CAST(json_set(?,'$.id','history-'||i,'$.block_order',i+CASE WHEN i>20 THEN 1 ELSE 0 END,
                 '$.history_pos',i,'$.body.members.blockId','history-'||i) AS BLOB) FROM n",
        vec![integer(after+1)?.into(), integer(through)?.into(),
            serde_json::to_string(&base.source)?.into(), serde_json::to_string(base)?.into()]
    )).await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_display_members(block_id,member_order,member_key,terminal,completion_id,updated_effect,metadata)
         SELECT block_id,1,block_id||':member:1',1,NULL,2,
             CAST(json_set(?,'$.block_id',block_id,'$.head.memberOrder',1,
                 '$.head.memberKey',block_id||':member:1','$.head.atom.id','tool-'||block_id) AS BLOB)
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
         INSERT INTO conversation_display_members(block_id,member_order,member_key,terminal,completion_id,updated_effect,metadata)
         SELECT b.block_id,i,b.block_id||':member:'||i,1,NULL,2,
             CAST(json_set(?,'$.block_id',b.block_id,'$.head.memberOrder',i,
                 '$.head.memberKey',b.block_id||':member:'||i,'$.head.atom.id','tool-'||i,
                 '$.head.atom.source',json_extract(b.header,'$.source')) AS BLOB)
         FROM n CROSS JOIN conversation_display_blocks b WHERE b.block_id IN ('history-20','open-work')",
        vec![integer(after+1)?.into(), integer(through)?.into(), serde_json::to_string(base)?.into()]
    )).await?;
    for header in headers {
        header.next_member = through;
        header.revision = through;
        let DisplayBlockBody::Work { summary, .. } = &mut header.body else {
            unreachable!()
        };
        summary.total = through;
        summary.terminal = through;
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
        crate::studio::storage::history::schema::display_snapshots::tests::fixture().await?;
    crate::studio::storage::history::schema::display_snapshots::upgrade(&db).await?;
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
    frozen.boundary = Some(ChatFactPosition {
        effect_seq: 2,
        suborder: 0,
    });
    if let DisplayBlockBody::Work { members, .. } = &mut frozen.body {
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
    if let DisplayBlockBody::Work { members, .. } = &mut open.body {
        members.block_id = open.id.clone();
    }
    db.execute_raw(statement(
        "INSERT INTO conversation_display_blocks(block_id,source_key,block_order,history_pos,updated_effect,header) VALUES(?,?,21,NULL,2,?)",
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
                id: header.id,
                block_order: header.block_order,
                source: Some(header.source),
                body: header.body,
                closing: header.boundary.is_some(),
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
            page.iter()
                .all(|member| !matches!(member.atom.payload, Some(PayloadData::Inline { .. })))
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
