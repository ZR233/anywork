use super::*;
use pl_protocol::{DisplayBlockBody, DisplayBlockRef, LiveDisplayBlock};

mod lifecycle;
mod live_cursor;
mod position_width;
mod production;

fn demand(max_items: u32) -> ReadDemand {
    ReadDemand {
        max_items,
        max_bytes: 16 * 1024,
    }
}

fn body(id: &str) -> DisplayBlockBody {
    DisplayBlockBody::Work {
        summary: Box::default(),
        members: DisplayBlockRef {
            database_id: "database".into(),
            block_id: id.into(),
        },
    }
}

fn block(pos: u64) -> DisplayBlock {
    let id = format!("block-{pos}");
    DisplayBlock {
        body: body(&id),
        id,
        history_pos: pos,
    }
}

fn live(through: u64, ids: &[u64]) -> LiveDisplayWindow {
    LiveDisplayWindow {
        revision: 7,
        history_through: through,
        execution_present: true,
        current_work_id: ids.last().map(|order| format!("block-{order}")),
        blocks: ids
            .iter()
            .map(|order| {
                let id = format!("block-{order}");
                LiveDisplayBlock {
                    body: body(&id),
                    id,
                    block_order: *order,
                    source: None,
                    state: if ids.last() == Some(order) {
                        pl_protocol::DisplayBlockState::Open
                    } else {
                        pl_protocol::DisplayBlockState::Sealed
                    },
                }
            })
            .collect(),
        older: None,
    }
}

#[test]
fn split_handoff_keeps_fixed_target_and_unpublished_live_until_last_frame() -> Result<()> {
    let mut delivery = TimelineDelivery::new(0);
    let target = live(2, &[3]);
    delivery.capture(target.clone())?;
    let first = delivery.append(vec![block(1)], demand(1))?;
    assert_eq!(first.from_pos, Some(0));
    assert_eq!(first.through_pos, 1);
    assert!(first.live.is_none());
    // A newer watch value is not allowed to overtake an already captured target.
    assert!(delivery.capture(live(5, &[6])).is_err());
    assert_eq!(delivery.target_through(), Some(2));
    let second = delivery.append(vec![block(2)], demand(1))?;
    assert_eq!(second.from_pos, Some(1));
    assert_eq!(second.through_pos, 2);
    assert_eq!(second.live, Some(target));
    assert_eq!(delivery.delivered(), 2);
    assert_eq!(delivery.target_through(), None);
    // Coalesced watch notifications do not define the frozen prefix: the next read fills 3..5.
    delivery.capture(live(5, &[6]))?;
    for pos in 3..=5 {
        let batch = delivery.append(vec![block(pos)], demand(1))?;
        assert_eq!(batch.blocks[0].history_pos, pos);
        assert_eq!(batch.live.is_some(), pos == 5);
    }
    Ok(())
}

#[test]
fn unchanged_p_delivers_live_without_history_and_without_requiring_atomic_h() -> Result<()> {
    let mut delivery = TimelineDelivery::new(4);
    let mut changed = live(4, &[5]);
    let DisplayBlockBody::Work { summary, .. } = &mut changed.blocks[0].body else {
        unreachable!()
    };
    summary.total = 2;
    summary.terminal = 1;
    summary.running = 1;
    delivery.capture(changed.clone())?;
    let frame = delivery.append(Vec::new(), demand(1))?;
    assert!(frame.blocks.is_empty());
    assert_eq!(frame.from_pos, Some(4));
    assert_eq!(frame.through_pos, 4);
    assert_eq!(frame.live, Some(changed));
    // Removing a reliably empty text segment also needs no fabricated history position.
    delivery.capture(live(4, &[]))?;
    assert_eq!(
        delivery.append(Vec::new(), demand(1))?.live,
        Some(live(4, &[]))
    );
    Ok(())
}

#[test]
fn rejected_prefix_and_byte_budget_do_not_advance_delivery() -> Result<()> {
    let mut delivery = TimelineDelivery::new(0);
    delivery.capture(live(2, &[3]))?;
    assert!(delivery.append(vec![], demand(1)).is_err());
    assert!(delivery.append(vec![block(2)], demand(1)).is_err());
    assert!(
        delivery
            .append(vec![block(1), block(2)], demand(1))
            .is_err()
    );
    let tiny = ReadDemand {
        max_items: 1,
        max_bytes: 1,
    };
    assert!(delivery.append(vec![block(1)], tiny).is_err());
    assert_eq!(delivery.delivered(), 0);
    assert_eq!(delivery.target_through(), Some(2));
    delivery.append(vec![block(1)], demand(1))?;
    assert!(delivery.append(vec![block(2)], tiny).is_err());
    assert_eq!(delivery.delivered(), 1);
    assert_eq!(delivery.target_through(), Some(2));
    let final_frame = delivery.append(vec![block(2)], demand(1))?;
    assert!(final_frame.live.is_some());
    Ok(())
}

#[test]
fn set_is_same_cut_and_prepend_cannot_replace_live_or_change_stream_position() -> Result<()> {
    let delivery = TimelineDelivery::new(9);
    let set = history_batch(
        ChatPlacement::Set,
        vec![block(9)],
        Some("older".into()),
        9,
        Some(live(9, &[10])),
        demand(1),
    )?;
    assert_eq!(set.through_pos, 9);
    assert!(set.from_pos.is_none());
    assert!(
        history_batch(
            ChatPlacement::Set,
            vec![block(9)],
            None,
            9,
            Some(live(10, &[11])),
            demand(1),
        )
        .is_err()
    );
    assert!(
        history_batch(
            ChatPlacement::Prepend,
            vec![block(1)],
            None,
            9,
            Some(live(9, &[10])),
            demand(1),
        )
        .is_err()
    );
    let prepend = history_batch(
        ChatPlacement::Prepend,
        vec![block(1)],
        None,
        9,
        None,
        demand(1),
    )?;
    assert!(prepend.live.is_none());
    assert_eq!(delivery.delivered(), 9);
    Ok(())
}

#[test]
fn final_head_and_live_can_use_separate_bounded_frames_at_the_same_p() -> Result<()> {
    let target = live(1, &[2, 3, 4]);
    let shell = TimelineBatch {
        presentation_version: PRESENTATION_VERSION,
        placement: ChatPlacement::Append,
        blocks: vec![],
        before: None,
        from_pos: Some(1),
        through_pos: 1,
        live: Some(target.clone()),
    };
    let demand = ReadDemand {
        max_items: 1,
        max_bytes: encoded_size(&shell)? as u32,
    };
    let mut delivery = TimelineDelivery::new(0);
    delivery.capture(target.clone())?;
    let first = delivery.append(vec![block(1)], demand)?;
    assert_eq!(first.through_pos, 1);
    assert!(first.live.is_none());
    assert_eq!(delivery.target_through(), Some(1));
    let last = delivery.append(vec![], demand)?;
    assert_eq!(last.from_pos, Some(1));
    assert_eq!(last.through_pos, 1);
    assert_eq!(last.live, Some(target));
    assert!(delivery.target_through().is_none());
    Ok(())
}

#[tokio::test]
async fn empty_production_feed_shares_query_qualification_and_close_wakes_receive() -> Result<()> {
    use crate::runtime_test_support::Environment;
    use futures::poll;
    use std::task::Poll;
    let env = Environment::new(vec![], vec![]).await?;
    let result = async {
        let thread = env
            .runtime
            .create_thread(&env.project.id, "empty display feed")
            .await?;
        let mut feed = env
            .runtime
            .open_timeline_feed(&thread.id, demand(1))
            .await?;
        let TimelineEvent::Timeline { batch } = feed.receive().await?;
        assert_eq!(batch.placement, ChatPlacement::Set);
        assert!(batch.blocks.is_empty());
        assert_eq!(batch.through_pos, 0);
        let initial_live = batch.live.expect("Set must carry live at its P");
        assert!(initial_live.blocks.is_empty());
        assert!(
            initial_live.execution_present,
            "create_thread installs the real resident owner, even before its first work block"
        );
        let mut state = env.runtime.open_conversation_state_feed(&thread.id).await?;
        assert!(matches!(
            state.recv().await?,
            Some(pl_protocol::ThreadSubscriptionUpdate::Snapshot { .. })
        ));
        state.close().await?;
        let reader = feed.reader().clone();
        let cancellation = feed.cancellation_token();
        {
            let receiving = feed.receive();
            tokio::pin!(receiving);
            assert!(matches!(poll!(&mut receiving), Poll::Pending));
            // Query admission is not the receive lock, and no stream ACK is necessary.
            reader.read_business_refs().await?;
            cancellation.cancel();
            assert!(matches!(
                receiving
                    .await
                    .expect_err("close must wake receive")
                    .downcast_ref::<ChatError>(),
                Some(ChatError::Cancelled)
            ));
        }
        feed.close().await?;
        reader.read_business_refs().await?;
        reader.close().await?;
        assert!(reader.read_business_refs().await.is_err());
        Ok(())
    }
    .await;
    env.finish(result).await
}
