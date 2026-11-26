//! Native root route changes through the same CAS and submission used by the composer.
use crate::support;

use anyhow::{Context, Result, ensure};
use pl_model::model::ModelTransportProfile;
use pl_provider_fixture::ReplyStage;
use pl_studio_runtime::{
    SetThreadModelRouteRequest, StudioPromptInput, SubmitPromptRequest,
    ThreadActivityToolState, ThreadWaitState, ThreadWorkspaceMode, TurnCancellationCause,
    TurnState,
};
use serde_json::json;
use support::{Environment, prompt_step, reached, text_reply, tool_reply};

const OLD_INPUT: &str = "Keep the source-only tool pending until my next message.";
const NEW_INPUT: &str = "Continue with the newly selected model.";
const WAIT_CALL: &str = "source-only-held-wait";
const SUMMARY: &str = "Portable handoff: the old wait was cancelled; continue the user's work.";

#[tokio::test]
async fn active_root_route_save_then_submit_summarizes_source_after_tool_cancellation() -> Result<()>
{
    let summary_stage = ReplyStage::new();
    let env = Environment::with_transport(
        vec![
            prompt_step(
                OLD_INPUT,
                0,
                tool_reply("wait", WAIT_CALL, json!({"taskIds":[],"timeoutMs":300000})),
            ),
            prompt_step(
                "请根据以上完整上下文生成压缩摘要。",
                1,
                summary_stage.gated(
                    vec![json!({"type":"response.created","response":{
                        "id":"source-summary","model":support::MODEL
                    }})],
                    pl_provider_fixture::responses_text(SUMMARY, "source-summary", support::MODEL)
                        .into_iter()
                        .skip(1)
                        .collect(),
                ),
            ),
        ],
        vec![prompt_step(
            NEW_INPUT,
            0,
            text_reply(
                "Target accepted the new input and portable summary.",
                "target-turn",
            ),
        )],
        ModelTransportProfile::responses_http(),
    )
    .await?;
    let result = tokio::time::timeout(support::integration_test_deadline()?, async {
        let started = env.start(ThreadWorkspaceMode::Local, OLD_INPUT).await?;
        let id = &started.thread.id;
        let feed = env.runtime.open_conversation_feed(id, 64).await?;
        let observation = async {
            loop {
                let meta = feed.session_meta_snapshot();
                // Current exposes attempt-scoped Core call IDs, whereas WAIT_CALL is
                // the provider's wire ID. Bind this barrier to the original input and
                // its unique foreground wait instead of comparing the two ID domains.
                if meta.activity.as_ref().is_some_and(|activity| {
                    activity.input_id.as_deref() == Some(format!("input-{OLD_INPUT}").as_str())
                        && matches!(activity.tools.active.as_slice(), [tool]
                            if tool.name == "wait"
                                && tool.state == ThreadActivityToolState::Running
                                && tool.wait.as_ref().is_some_and(|wait|
                                    wait.state() == ThreadWaitState::Waiting))
                }) {
                    return Ok::<_, anyhow::Error>(meta);
                }
                ensure!(
                    feed.next_event().await.is_some(),
                    "ConversationFeed closed before the source wait started"
                );
            }
        }
        .await;
        feed.close().await;
        let held = observation?;
        let source_turn = held
            .active_turn
            .as_ref()
            .context("source Turn is active")?;
        let revision = held
            .model_route
            .as_ref()
            .context("source route")?
            .revision;
        let saved = env
            .runtime
            .save_thread_model_route(
                id,
                SetThreadModelRouteRequest {
                    operation_id: "save-target-during-source-wait".into(),
                    expected_model_route_revision: revision,
                    account_id: "child-fixture".into(),
                    model_id: support::MODEL.into(),
                    effort: None,
                    service_tier: None,
                },
            )
            .await?;
        ensure!(
            env.child_provider.recorded().is_empty(),
            "saving a route sent a target request"
        );
        let selected = env
            .runtime
            .thread_snapshot(id)
            .await?
            .model_route
            .context("saved target route")?;
        ensure!(selected.account_id == "child-fixture" && selected.revision > revision);
        ensure!(saved.runtime.thread_id == *id);

        // This public admission prepares B before interrupting A. Cancelling the held wait
        // then pairs its result into A's committed context, advancing it after that candidate's
        // snapshot. A deferred context CAS would reject B at precisely this boundary.
        let accepted = env
            .runtime
            .submit_prompt_command(
                id.clone(),
                SubmitPromptRequest {
                    input: StudioPromptInput {
                        input_id: format!("input-{NEW_INPUT}"),
                        text: NEW_INPUT.into(),
                        attachment_draft_ids: Vec::new(),
                    },
                    expected_model_route_revision: selected.revision,
                },
            )
            .await
            .context("new input must survive source context progress after B preparation")?;
        ensure!(accepted.thread_id == *id && accepted.input_id == format!("input-{NEW_INPUT}"));
        tokio::select! {
            result = reached(&summary_stage) => result?,
            terminal = support::completed_prompt(&env.runtime, id, NEW_INPUT) => {
                anyhow::bail!("new Turn ended before source summarization: {:?}", terminal?.state);
            }
        }
        ensure!(
            env.child_provider.recorded().is_empty(),
            "target ran before the source summary finished"
        );
        let source = env.root_provider.recorded();
        ensure!(source.len() == 2 && source.iter().all(|request| request.accepted));
        let summary_input = &source[1].body;
        ensure!(summary_input["input"].to_string().contains(OLD_INPUT));
        let cancellation = pl_provider_fixture::observed_tool_output(summary_input, WAIT_CALL)
            .context("source summary must include the newly committed wait cancellation")?;
        ensure!(
            cancellation.contains("cancelled"),
            "source wait did not advance context through cancellation: {cancellation}"
        );
        ensure!(
            !summary_input["input"].to_string().contains(NEW_INPUT),
            "new input leaked into old-context summary"
        );
        summary_stage.release();

        let old = support::completed_prompt(&env.runtime, id, OLD_INPUT).await?;
        ensure!(
            old.id == source_turn.id
                && matches!(&old.state, TurnState::Cancelled(state)
                    if *state.cause() == TurnCancellationCause::Interrupted),
            "old Turn was not interrupted: {:?}",
            old.state
        );
        let target = support::completed_prompt(&env.runtime, id, NEW_INPUT).await?;
        ensure!(
            matches!(target.state, TurnState::Completed(_)),
            "new Turn failed: {:?}",
            target.state
        );
        let target_requests = env.child_provider.recorded();
        ensure!(target_requests.len() == 1 && target_requests[0].accepted);
        let target_input = &target_requests[0].body["input"];
        ensure!(
            target_input.to_string().contains(SUMMARY),
            "target lost the portable summary"
        );
        ensure!(
            target_input.to_string().contains(NEW_INPUT),
            "target lost the new user input"
        );
        ensure!(
            !target_input.to_string().contains(WAIT_CALL),
            "target replayed a source tool identity"
        );
        ensure!(
            !target_input.to_string().contains(OLD_INPUT),
            "target replayed old user history instead of its summary"
        );
        ensure!(
            target_input
                .as_array()
                .context("target Responses input")?
                .iter()
                .all(|item| {
                    !matches!(
                        item["type"].as_str(),
                        Some("function_call" | "function_call_output")
                    )
                }),
            "target replayed old tool calls/results"
        );
        ensure!(
            env.root_provider.recorded().len() == 2,
            "new input was sent back to A"
        );
        Ok(())
    })
    .await
    .context("active model handoff integration watchdog")
    .and_then(std::convert::identity);
    summary_stage.release();
    env.finish(result).await
}
