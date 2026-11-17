#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_provider_fixture::{Protocol, ReplyStage, Step};
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ChatScope, StopThreadRequest, ThreadWorkspaceMode, TurnState,
    history::{
        HistoryBodyRole, HistoryDemand, HistoryEventBodyRef, HistoryEventsQuery, HistoryReader,
    },
};
use serde_json::Value;
use support::{Environment, current_demand, held_reply, program_reply, prompt_step, reached};

const PROMPT: &str = "read a skill, then hold the next model response";
const CALL: &str = "live-skill-load-call";
const SKILL: &str = "canvas-design";

async fn body(reader: &HistoryReader, reference: &HistoryEventBodyRef) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    while bytes.len() as u64 != reference.byte_length {
        let window = reader
            .read_body(
                reference.clone(),
                bytes.len() as u64,
                (reference.byte_length - bytes.len() as u64).min(1024) as u32,
            )
            .await?;
        ensure!(!window.bytes.is_empty(), "tool body did not advance");
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}

async fn public_tool(
    runtime: &pl_studio_runtime::StudioRuntime,
    thread: &str,
    turn: &str,
) -> Result<(String, Value, Vec<u8>)> {
    let demand = HistoryDemand {
        max_rows: 128,
        max_bytes: 256 * 1024,
    };
    let reader = runtime
        .open_history_reader(thread, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
        .await?;
    let checked = async {
        let originals = reader
            .events_page(
                HistoryEventsQuery::Originals {
                    scope: ChatScope::conversation(None),
                },
                None,
                None,
                demand,
            )
            .await?;
        for event in originals.entries {
            let Some(payload_ref) = &event.payload_ref else {
                continue;
            };
            let payload = body(&reader, payload_ref).await?;
            let value: Value = serde_json::from_slice(&payload)?;
            if value["type"] != "tool"
                || !value["data"]["invocation"]["callId"]
                    .as_str()
                    .is_some_and(|id| id.starts_with(&format!("{CALL}:nested:")))
            {
                continue;
            }
            ensure!(event.header.turn_id.as_deref() == Some(turn));
            let bodies = reader
                .list_bodies(event.header.event_id.clone(), None, demand)
                .await?;
            let result = bodies
                .entries
                .into_iter()
                .find(|entry| {
                    entry.body_key == "tool.result" && entry.role == HistoryBodyRole::ToolOutput
                })
                .context("original tool result")?;
            let bytes = body(&reader, &result.reference).await?;
            return Ok((event.header.event_id.clone(), value, bytes));
        }
        anyhow::bail!("completed nested tool original missing")
    }
    .await;
    reader.close().await;
    checked
}

#[tokio::test]
async fn completed_tool_and_skill_activation_are_public_before_the_turn_is_cancelled() -> Result<()>
{
    let stage = ReplyStage::new();
    let env = Environment::new(
        vec![
            prompt_step(
                PROMPT,
                0,
                program_reply("skill_view", CALL, serde_json::json!({"name": SKILL})),
            ),
            Step::tool_output(
                Protocol::ResponsesHttp,
                CALL,
                "# Canvas design",
                1,
                held_reply(&stage, "held-after-skill"),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        let started = env.start(ThreadWorkspaceMode::Local, PROMPT).await?;
        let thread_id = &started.thread.id;
        reached(&stage).await?;
        let snapshot = env.runtime.thread_snapshot(thread_id).await?;
        let turn = snapshot
            .active_turn
            .as_ref()
            .context("original active Turn")?;
        let input_id = format!("input-{PROMPT}");
        ensure!(turn.input_id.as_deref() == Some(input_id.as_str()));
        ensure!(matches!(turn.state, TurnState::Running(_)));
        let turn_id = turn.id.clone();
        let runtime = snapshot.runtime.as_ref().context("runtime projection")?;
        let execution_id = runtime
            .execution
            .as_ref()
            .context("original execution")?
            .id()
            .to_owned();
        ensure!(runtime.active_skills.iter().any(|name| name == SKILL));

        let current = env
            .runtime
            .open_current_reader(thread_id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let view = current.snapshot(current_demand()).await?;
        ensure!(view.projection.execution_present);
        ensure!(
            view.projection
                .active_turn
                .is_some_and(|head| head.id == turn_id)
        );
        current.close().await?;

        let viewed: Value = serde_json::from_str(&support::tool_output(&env.root_provider, CALL)?)?;
        let expected_output = format!(
            "Skill: {}\nResource: {}\n\n{}",
            viewed["skill"]["name"]
                .as_str()
                .context("viewed skill name")?,
            viewed["filePath"].as_str().context("viewed skill file")?,
            viewed["content"].as_str().context("viewed skill content")?
        );
        let (event_id, payload, output) = public_tool(&env.runtime, thread_id, &turn_id).await?;
        ensure!(payload["data"]["state"]["kind"] == "succeeded");
        ensure!(output == expected_output.as_bytes());

        env.runtime
            .stop_thread(
                thread_id.clone(),
                StopThreadRequest {
                    operation_id: "stop-held-skill-execution".into(),
                    expected_execution_id: execution_id,
                },
            )
            .await?;
        let terminal = support::completed_prompt(&env.runtime, thread_id, PROMPT).await?;
        ensure!(terminal.id == turn_id && matches!(terminal.state, TurnState::Cancelled(_)));
        stage.release();

        let after = public_tool(&env.runtime, thread_id, &turn_id).await?;
        ensure!(
            after.0 == event_id,
            "cancellation rewrote the tool identity"
        );
        ensure!(
            after.1 == payload,
            "cancellation rewrote the canonical tool"
        );
        ensure!(after.2 == output, "cancellation rewrote the tool result");
        let after_snapshot = env
            .runtime
            .thread_snapshot(thread_id)
            .await?
            .runtime
            .context("post-cancel runtime")?;
        ensure!(
            after_snapshot
                .active_skills
                .iter()
                .any(|name| name == SKILL)
        );
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}
