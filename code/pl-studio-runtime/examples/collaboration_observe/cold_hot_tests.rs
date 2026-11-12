//! Real passive State source replacement, using the shared finite provider fixture.
use super::*;
use anyhow::ensure;
use pl_protocol::{
    ThreadNotification, ThreadSubscriptionUpdate, ThreadWorkspaceMode,
    studio::{StudioPromptInput, SubmitPromptRequest},
};
use pl_provider_fixture::ReplyStage;

#[expect(
    dead_code,
    reason = "shared Runtime fixture also serves other test binaries"
)]
#[path = "../../tests/support/mod.rs"]
mod support;

async fn progress_until(
    writer: &mut EventWriter,
    boundary: &super::super::Boundary,
    ready: impl Fn(&EventProgress) -> bool,
) -> Result<()> {
    loop {
        {
            let progress = writer
                .progress
                .lock()
                .map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
            ensure!(
                progress.coverage.error.is_none(),
                "writer failed: {:?}",
                progress.coverage.error
            );
            if ready(&progress) {
                return Ok(());
            }
        }
        boundary
            .read(async {
                writer
                    .changed
                    .changed()
                    .await
                    .context("writer progress closed")
            })
            .await?;
    }
}

#[tokio::test]
async fn real_cold_hot_source_joins_at_new_terminal_without_healing_interval() -> Result<()> {
    use support::{Environment, completed_prompt, held_reply, prompt_step, reached, text_reply};
    let held = ReplyStage::new();
    let mut env = Environment::new(
        vec![
            prompt_step("segment-seed", 0, text_reply("saved terminal", "seed")),
            prompt_step("segment-next", 1, held_reply(&held, "next")),
        ],
        vec![],
    )
    .await?;
    let directory = tempfile::tempdir()?;
    let sink = Evidence::new(directory.path().into())?;
    let boundary = super::super::Boundary::new(
        support::integration_test_deadline()?.as_secs(),
        tokio_util::sync::CancellationToken::new(),
    );
    // Retain ownership across every early error, including a failure before provider release.
    let mut active_writer = None;
    let result: Result<()> = async {
        let started = env.start(ThreadWorkspaceMode::Local, "segment-seed").await?;
        let id = started.thread.id;
        let previous = completed_prompt(&env.runtime, &id, "segment-seed").await?;
        ensure!(
            matches!(previous.state, pl_protocol::TurnState::Completed(_)),
            "seed provider script failed: {:?}",
            previous.state
        );
        let old_anchor = TurnAnchor::from_turn(&previous)?;
        env.restart().await?;
        let cold = super::super::state::snapshot(&env.runtime, &id, &boundary).await?;
        ensure!(
            cold.active_turn.is_none() && cold.storage.is_none(),
            "restart did not leave a passive cold source"
        );
        let route_revision = cold.model_route.context("saved route")?.revision;
        let feed = env.runtime.open_conversation_state_feed(&id).await?;
        let old_feed_closed = feed.cancellation_token();
        active_writer = Some(EventWriter::start(
            feed,
            &env.runtime,
            &boundary,
            &sink,
            &id,
            0,
        )?);
        progress_until(
            active_writer.as_mut().context("owned writer")?,
            &boundary,
            |state| state.anchors.contains_key(&old_anchor.key()),
        )
        .await?;

        // Public submit reinstalls the owner; the fixture gate holds the new Turn open.
        env.runtime
            .submit_prompt_command(
                id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: "input-segment-next".into(),
                        text: "segment-next".into(),
                        attachment_draft_ids: vec![],
                    },
                    expected_model_route_revision: route_revision,
                },
            )
            .await?;
        reached(&held).await?;
        progress_until(
            active_writer.as_mut().context("owned writer")?,
            &boundary,
            |state| {
                !state.coverage.segments.is_empty()
                    && state.coverage.initial_snapshot_revision.is_some()
            },
        )
        .await?;
        ensure!(old_feed_closed.is_cancelled(), "invalidated cold feed was not closed");
        {
            let writer = active_writer.as_ref().context("owned writer")?;
            let state = writer
                .progress
                .lock()
                .map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
            let first = &state.coverage.segments[0];
            ensure!(
                first.initial_snapshot_revision.is_some()
                    && first.consumed_last.is_some()
                    && first.invalidated.as_ref().is_some_and(|error| {
                        error.reason()
                            == Some(pl_protocol::studio::StudioErrorReason::ConversationResyncRequired.label())
                    }),
                "old segment did not retain its consumed prefix and typed source invalidation"
            );
            ensure!(
                !state.coverage.interval_complete
                    && !state.coverage.complete
                    && state.coverage.target.is_none()
                    && state.coverage.matched_at.is_none(),
                "new baseline inherited completion from the old segment"
            );
            // Hot open may legitimately replay the saved terminal before the new Turn becomes
            // active. A cached old key is allowed only if a real notification in this new segment
            // re-established it; the unit regression separately proves clearing even without replay.
            // The writer may append another frame outside this progress lock. Compare only
            // newline-committed records, not a concurrently serialized trailing frame.
            let bytes = std::fs::read(directory.path().join("threads/000/events.jsonl"))?;
            let through = bytes.iter().rposition(|byte| *byte == b'\n').map_or(0, |at| at + 1);
            let records = std::str::from_utf8(&bytes[..through])?;
            let replayed = recorded_terminal(
                records,
                state.coverage.segments.len(),
                &old_anchor,
            )?
            .is_some();
            ensure!(
                !state.anchors.contains_key(&old_anchor.key()) || replayed,
                "old anchor survived without delivery in the new segment"
            );
            println!(
                "old terminal consumed before replacement; oldAnchorReplayedInLatestSegment={replayed}"
            );
        }
        held.release();
        let terminal = completed_prompt(&env.runtime, &id, "segment-next").await?;
        ensure!(
            matches!(terminal.state, pl_protocol::TurnState::Completed(_)),
            "new provider script failed: {:?}",
            terminal.state
        );
        ensure!(terminal.id != previous.id, "second input did not create a distinct Turn");
        env.runtime.synchronize_thread_observation(&id).await?;
        let page = boundary.read(env.runtime.list_thread_turns(&id, None, 1)).await?;
        let target = TurnAnchor::from_turn(&page.turns.first().context("durable terminal")?.turn)?;
        ensure!(target == TurnAnchor::from_turn(&terminal)?, "durable anchor differs from new terminal");
        let coverage = active_writer
            .take()
            .context("owned writer")?
            .finish(Ok(target.clone()), &boundary)
            .await?;
        ensure!(
            !coverage.interval_complete && coverage.capture_complete && !coverage.complete,
            "source gap was healed or prevented normal writer completion"
        );
        ensure!(coverage.error.is_none(), "writer did not exit normally: {:?}", coverage.error);
        let final_segment = coverage.segments.last().context("latest segment")?;
        ensure!(
            final_segment.complete && final_segment.target.as_ref() == Some(&target),
            "latest segment did not confirm the actual new terminal"
        );
        let matched = final_segment.matched_at.context("latest terminal match")?;
        let records = std::fs::read_to_string(directory.path().join("threads/000/events.jsonl"))?;
        let delivered = recorded_terminal(&records, coverage.segments.len() - 1, &target)?
            .context("new target was not delivered in the latest segment")?;
        ensure!(
            (delivered.epoch, delivered.revision) == (matched.epoch, matched.revision),
            "match watermark was inherited rather than delivered in the latest segment"
        );
        let index = std::fs::read_to_string(directory.path().join("files.jsonl"))?;
        let indexed: Vec<serde_json::Value> = index.lines().map(serde_json::from_str).collect::<std::result::Result<_, _>>()?;
        ensure!(
            indexed.len() == 1 && indexed[0]["complete"] == true,
            "joined writer did not register a complete file capture"
        );
        ensure!(
            indexed[0]["sha256"] == sha256(records.as_bytes())
                && indexed[0]["bytes"] == records.len(),
            "file index does not describe the actual closed writer output"
        );
        println!(
            "real cold root -> hot owner: segments={}, intervalComplete={}, captureComplete={}, complete={}, latestTargetMatched=true, writerJoined=true, invalidatedFeedClosed=true",
            coverage.segments.len(), coverage.interval_complete, coverage.capture_complete, coverage.complete,
        );
        Ok(())
    }
    .await;
    held.release();
    let drained = match active_writer.take() {
        Some(writer) => writer
            .finish(
                Err(anyhow::anyhow!("cold/hot test stopped before target")),
                &boundary,
            )
            .await
            .map(|_| ()),
        None => Ok(()),
    };
    let result = combine_write_result(result, drained, "cold/hot writer cleanup");
    env.finish(result).await
}

#[tokio::test]
async fn stopped_scene_preserves_terminal_prefix_for_independent_cleanup() -> Result<()> {
    use support::{Environment, completed_prompt, held_reply, prompt_step, reached, text_reply};
    let held = ReplyStage::new();
    let env = Environment::new(
        vec![
            prompt_step("boundary-seed", 0, text_reply("previous terminal", "seed")),
            prompt_step("boundary-next", 1, held_reply(&held, "next")),
        ],
        vec![],
    )
    .await?;
    let directory = tempfile::tempdir()?;
    let sink = Evidence::new(directory.path().into())?;
    let scene_stop = tokio_util::sync::CancellationToken::new();
    let scene = super::super::Boundary::new(
        support::integration_test_deadline()?.as_secs(),
        scene_stop.clone(),
    );
    let cleanup_stop = tokio_util::sync::CancellationToken::new();
    let mut cleanup = None;
    let mut writers = Vec::new();
    let result: Result<()> = async {
        let started = env.start(ThreadWorkspaceMode::Local, "boundary-seed").await?;
        let id = started.thread.id;
        let seed = completed_prompt(&env.runtime, &id, "boundary-seed").await?;
        ensure!(matches!(seed.state, pl_protocol::TurnState::Completed(_)), "seed failed");
        let unmatched = TurnAnchor::from_turn(&seed)?;
        // Use another real Thread for the negative target identity: a same-Thread State feed
        // may legitimately replay an older terminal even when opened during a newer Turn.
        let started = env.start(ThreadWorkspaceMode::Local, "boundary-next").await?;
        let id = started.thread.id;
        reached(&held).await?;
        let mut closed = Vec::new();
        for index in 0..2 {
            let feed = env.runtime.open_conversation_state_feed(&id).await?;
            closed.push(feed.cancellation_token());
            writers.push(EventWriter::start(feed, &env.runtime, &scene, &sink, &id, index)?);
        }
        held.release();
        let terminal = completed_prompt(&env.runtime, &id, "boundary-next").await?;
        ensure!(matches!(terminal.state, pl_protocol::TurnState::Completed(_)), "new Turn failed");
        let expected = TurnAnchor::from_turn(&terminal)?;
        for writer in &mut writers {
            progress_until(writer, &scene, |state| state.anchors.contains_key(&expected.key())).await?;
            let state = writer.progress.lock().map_err(|_| anyhow::anyhow!("event progress poisoned"))?;
            ensure!(!state.anchors.contains_key(&unmatched.key()), "old Turn unexpectedly delivered");
            ensure!(state.coverage.target.is_none(), "target was declared before cleanup");
        }

        scene_stop.cancel();
        ensure!(scene.check().is_err(), "original scene did not stop");
        cleanup = Some(super::super::Boundary::new(30, cleanup_stop.clone()));
        let cleanup = cleanup.as_ref().context("independent cleanup")?;
        // Declare the known unmatched terminal as an intermediate target. Its progress
        // acknowledgement proves the worker processed control after the original scene stopped,
        // before cleanup obtains and submits the actual matching durable target.
        writers[0].target.send_replace(Some(unmatched.clone()));
        progress_until(&mut writers[0], cleanup, |state| {
            state.coverage.target.as_ref() == Some(&unmatched)
        }).await?;
        env.runtime.synchronize_thread_observation(&id).await?;
        let page = cleanup.read(env.runtime.list_thread_turns(&id, None, 1)).await?;
        let target = TurnAnchor::from_turn(&page.turns.first().context("durable target")?.turn)?;
        ensure!(target == expected, "cleanup read did not return the consumed exact terminal");
        let coverage = writers.remove(0).finish(Ok(target), cleanup).await?;
        ensure!(
            coverage.complete && coverage.interval_complete && coverage.capture_complete
                && coverage.matched_at.is_some() && coverage.error.is_none(),
            "stopped scene destroyed the prefix before independent cleanup: {:?}",
            coverage.error
        );
        ensure!(closed[0].is_cancelled(), "confirmed feed did not close");

        // A different real terminal is not cached by the remaining writer. Ending only the
        // independent cleanup budget must stop that still-owned feed and preserve the failure.
        let stopped = writers[0].stop.clone();
        cleanup_stop.cancel();
        let missing = writers.remove(0).finish(Ok(unmatched), cleanup).await?;
        ensure!(
            !missing.complete && !missing.capture_complete && missing.matched_at.is_none()
                && missing.error.is_some() && stopped.is_cancelled() && closed[1].is_cancelled(),
            "unmatched target did not stop, close, and join under the cleanup boundary"
        );
        let index = std::fs::read_to_string(directory.path().join("files.jsonl"))?;
        let indexed: Vec<serde_json::Value> = index.lines().map(serde_json::from_str).collect::<std::result::Result<_, _>>()?;
        ensure!(
            indexed.len() == 2 && indexed[0]["complete"] == true && indexed[1]["complete"] == false,
            "confirmed and incomplete writer captures were not finalized distinctly"
        );
        for record in indexed {
            let bytes = std::fs::read(directory.path().join(record["path"].as_str().context("file path")?))?;
            ensure!(
                record["sha256"] == sha256(&bytes) && record["bytes"] == bytes.len(),
                "joined file capture differs from its finalized index"
            );
        }
        println!("sceneStoppedBeforeTarget=true, targetControlAcknowledged=true, independentCleanupMatched=true, unmatchedCleanupStopped=true, writersJoined=2");
        Ok(())
    }
    .await;
    held.release();
    let cleanup = cleanup.unwrap_or_else(|| super::super::Boundary::new(30, cleanup_stop));
    let mut drained = Ok(());
    for writer in writers {
        let joined = writer
            .finish(
                Err(anyhow::anyhow!("dual-boundary test stopped before target")),
                &cleanup,
            )
            .await
            .map(|_| ());
        drained = combine_write_result(drained, joined, "dual-boundary writer cleanup");
    }
    env.finish(combine_write_result(result, drained, "dual-boundary test"))
        .await
}

fn recorded_terminal(
    records: &str,
    segment: usize,
    target: &TurnAnchor,
) -> Result<Option<StreamWatermark>> {
    for line in records.lines() {
        let record: serde_json::Value = serde_json::from_str(line)?;
        if record["segment"] != segment {
            continue;
        }
        let Some(update) = record.get("update") else {
            continue;
        };
        if let ThreadSubscriptionUpdate::Notification { notification } =
            serde_json::from_value(update.clone())?
            && let ThreadNotification::TurnCompleted { turn }
            | ThreadNotification::TurnUpdated { turn } = notification.notification
            && turn.state.is_terminal()
            && TurnAnchor::from_turn(&turn)? == *target
        {
            return Ok(Some(StreamWatermark {
                epoch: notification.epoch,
                revision: notification.revision,
            }));
        }
    }
    Ok(None)
}
