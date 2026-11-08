//! Index seeks over immutable completions. Never scan a run to find its representative.
use super::*;

// CROSS JOIN fixes the outer loop to the bounded representatives. An ordinary JOIN can be
// reordered into a rowid range walk over the entire history by SQLite's optimizer.
pub(super) const RUN_HEADS_SQL: &str = "
WITH RECURSIVE picked(seq, run_start, n) AS (
 SELECT seq, display_run_start, 1 FROM conversation_items WHERE seq = (
   SELECT seq FROM conversation_items INDEXED BY conversation_items_visible_seq
   WHERE display_run_start IS NOT NULL AND seq<=? ORDER BY seq DESC LIMIT 1)
 UNION ALL
 SELECT r.seq,r.display_run_start,p.n+1 FROM picked p
 JOIN conversation_items r ON r.seq = (
   SELECT seq FROM conversation_items INDEXED BY conversation_items_visible_seq
   WHERE display_run_start IS NOT NULL AND seq<p.run_start ORDER BY seq DESC LIMIT 1)
 WHERE p.n<?
)
SELECT r.seq,r.item_id,r.query_class,r.parent_id,r.metadata,
       length(r.payload) AS byte_length,r.display_run_start,r.display_run_ordinal
FROM picked p CROSS JOIN conversation_items r ON r.seq=p.seq WHERE p.seq>?
ORDER BY p.seq DESC";

pub(super) async fn page(
    db: &impl ConnectionTrait,
    request: &ChatHistoryRequest,
    budget: &dyn ChatBudget,
    ascending: bool,
) -> Result<ChatHistoryPage> {
    let query = request
        .query
        .as_ref()
        .context("run selection requires query")?;
    ensure!(
        query.parent_id.is_none(),
        "run selection cannot have a parent"
    );
    if let ChatSelection::Run { start_seq } = query.selection {
        ensure!(start_seq > 0, "run start must be positive");
        integer(start_seq)?;
    }
    ensure!(
        query.query_class == "conversation",
        "Native run selection requires conversation class"
    );
    let heads = query.selection == ChatSelection::RunHeads;
    ensure!(
        !heads || !ascending,
        "RunHeads only supports descending selection"
    );
    let mut upper = request.ceiling.min(
        request
            .before
            .map(|before| before.saturating_sub(1))
            .unwrap_or(request.ceiling),
    );
    let mut after = request.after;
    let mut items = Vec::new();
    let mut remaining = request.demand;
    let exhausted;
    loop {
        if upper <= after {
            exhausted = true;
            break;
        }
        let limit = remaining.max_items.min(64);
        let rows = if heads {
            db.query_all_raw(statement(
                RUN_HEADS_SQL,
                vec![
                    integer(upper)?.into(),
                    integer(limit)?.into(),
                    integer(after)?.into(),
                ],
            ))
            .await?
        } else {
            let ChatSelection::Run { start_seq } = query.selection else {
                anyhow::bail!("invalid run selection")
            };
            let order = if ascending { "ASC" } else { "DESC" };
            db.query_all_raw(statement(
                &format!(
                "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,
                        display_run_start,display_run_ordinal
                 FROM conversation_items INDEXED BY conversation_items_by_run_seq
                 WHERE display_run_start IS NOT NULL AND display_run_start=?
                   AND seq<=? AND seq>? ORDER BY seq {order} LIMIT ?"
            ),
                vec![
                    integer(start_seq)?.into(),
                    integer(upper)?.into(),
                    integer(after)?.into(),
                    integer(limit)?.into(),
                ],
            ))
            .await?
        };
        tracing::debug!(target: "conversation_work", sql_candidates=rows.len(), run_heads=heads,
                        "SQL run index selection");
        let mut window_request = request.clone();
        window_request.demand = remaining;
        let page = materialize(
            db,
            &window_request,
            budget,
            ascending,
            &rows,
            rows.len() < limit,
            heads,
        )
        .await?;
        let count = page.items.len();
        let last = if ascending {
            page.items.last()
        } else {
            page.items.first()
        };
        if let Some(last) = last {
            if ascending {
                after = last.header.append_seq;
            } else {
                upper = if heads {
                    last.header
                        .run
                        .context("representative has no run")?
                        .start_seq
                        - 1
                } else {
                    last.header.append_seq - 1
                };
            }
        }
        for item in &page.items {
            let mode = match item.payload {
                PayloadData::Inline(_) => PayloadMode::Inline,
                PayloadData::Deferred { .. } => PayloadMode::Deferred,
            };
            remaining.max_bytes -= budget.item_bytes(&item.header, mode);
        }
        remaining.max_items -= count;
        // Each descending window arrives ascending. Reverse only these bounded windows;
        // the whole accumulated result is reversed once below.
        if ascending {
            items.extend(page.items);
        } else {
            items.extend(page.items.into_iter().rev());
        }
        if count < rows.len() || remaining.max_items == 0 || page.exhausted {
            exhausted = page.exhausted;
            break;
        }
    }
    if !ascending {
        items.reverse();
    }
    Ok(ChatHistoryPage { items, exhausted })
}
