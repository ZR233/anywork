use super::{production::timeline, *};
use crate::{
    runtime_test_support::Environment,
    studio::runtime::conversation_feed::tests::completed_runs::{Harness, finish, start},
};
use anyhow::Context;
use std::collections::BTreeSet;

async fn handoff_at_decimal_boundary(delivered: u64) -> Result<()> {
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let mut h = Harness::new(&env).await?;
        // Use real reliable boundaries. Empty text closes each Work without adding a text card,
        // keeping the initial history page smaller than the later multi-head live window.
        for i in 0..delivered {
            let work = format!("seed-work-{i}");
            let empty = format!("seed-empty-{i}");
            h.effect(vec![start(&work, true)], vec![]).await?;
            h.effect(vec![], vec![finish(&work, true, "finished")?])
                .await?;
            h.effect(vec![start(&empty, false)], vec![]).await?;
            h.effect(vec![], vec![finish(&empty, false, "")?]).await?;
        }
        h.effect(vec![start("handoff-work", true)], vec![]).await?;
        h.effect(vec![], vec![finish("handoff-work", true, "finished")?])
            .await?;
        let generous = ReadDemand {
            max_items: 8,
            max_bytes: pl_protocol::CHAT_BATCH_MAX_BYTES,
        };
        let mut feed = env
            .runtime
            .open_timeline_feed(&h.thread.id, generous)
            .await?;
        let initial = timeline(&mut feed).await?;
        assert_eq!(initial.through_pos, delivered);
        let retiring_id = initial
            .live
            .as_ref()
            .context("initial live Work")?
            .blocks
            .last()
            .context("Work waiting for a reliable boundary")?
            .id
            .clone();

        // The first text begins the handoff, and the unfinished text prefix holds all eight
        // subsequent live heads. Long but bounded provider identities make that window larger
        // than the initial history page, without loading or padding any content body.
        let starts = (0..8)
            .map(|i| start(&format!("pending-text-{i}-{}", "p".repeat(512)), false))
            .collect();
        h.effect(starts, vec![]).await?;
        let cut = feed
            .reader()
            .capture_display(None, 9, Some(u64::MAX), 0)
            .await?;
        let target = delivered + 1;
        assert_eq!(cut.published, target);
        let tokens = feed.reader().presentation_tokens().await?;
        let full_live = feed.reader().cut_live(&cut, generous, &tokens)?;
        assert_eq!(full_live.blocks.len(), 8);
        assert!(full_live.older.is_none());

        let old_reserve = TimelineBatch {
            presentation_version: PRESENTATION_VERSION,
            placement: ChatPlacement::Append,
            blocks: Vec::new(),
            before: None,
            from_pos: Some(delivered),
            through_pos: target,
            live: Some(full_live.clone()),
        };
        let tight_bytes = encoded_size(&old_reserve)? as u32;
        let final_full = TimelineBatch {
            from_pos: Some(target),
            ..old_reserve
        };
        assert_eq!(encoded_size(&final_full)?, tight_bytes as usize + 1);
        assert!(
            encoded_size(&initial)? <= tight_bytes as usize,
            "initial={} tight={tight_bytes}",
            encoded_size(&initial)?
        );
        assert!(tight_bytes <= generous.max_bytes);
        // Tighten only this private fixture's demand after the exact wire size is known. The
        // already delivered Set also fits the same ceiling; source, reader, cut and receive path
        // are real. No owner, timeline target, or delivery position is synthesized.
        feed.demand = ReadDemand {
            max_bytes: tight_bytes,
            ..generous
        };

        let mut accepted_ids = Vec::new();
        let mut final_live = None;
        let mut previous = delivered;
        for _ in 0..3 {
            let batch = timeline(&mut feed).await?;
            assert!(encoded_size(&batch)? <= tight_bytes as usize);
            assert_eq!(batch.from_pos, Some(previous));
            assert!(batch.through_pos >= previous && batch.through_pos <= target);
            previous = batch.through_pos;
            accepted_ids.extend(batch.blocks.iter().map(|block| block.id.clone()));
            if let Some(live) = batch.live {
                assert_eq!(batch.through_pos, target);
                final_live = Some(live);
                break;
            }
            assert_eq!(feed.delivery.target_through(), Some(target));
        }
        let live =
            final_live.context("the captured target must finish, not terminate on demand")?;
        assert_eq!(accepted_ids, [retiring_id]);
        assert_eq!(live.history_through, target);
        assert_eq!(live.revision, cut.revision);
        assert!(
            live.blocks.len() < full_live.blocks.len(),
            "reserve must reduce the page, not widen the budget"
        );
        assert!(
            live.older.is_some(),
            "unselected live heads must remain queryable"
        );
        assert_eq!(feed.delivery.delivered(), target);
        assert!(feed.delivery.target_through().is_none());

        let mut ids = live
            .blocks
            .iter()
            .map(|head| head.id.clone())
            .collect::<BTreeSet<_>>();
        let mut before = live.older;
        while let Some(cursor) = before {
            let older = feed.reader().load_live_older(&cursor, feed.demand).await?;
            assert!(encoded_size(&older)? <= tight_bytes as usize);
            assert_eq!(
                (older.history_through, older.revision),
                (target, cut.revision)
            );
            ids.extend(older.blocks.into_iter().map(|head| head.id));
            before = older.older;
        }
        assert_eq!(
            ids,
            full_live.blocks.into_iter().map(|head| head.id).collect()
        );
        feed.close().await?;
        feed.reader().close().await?;
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn handoff_budget_remains_bounded_across_9_to_10_with_multiple_live_heads() -> Result<()> {
    handoff_at_decimal_boundary(9).await
}

#[tokio::test]
async fn handoff_budget_remains_bounded_across_99_to_100_with_multiple_live_heads() -> Result<()> {
    handoff_at_decimal_boundary(99).await
}
