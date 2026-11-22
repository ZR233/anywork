#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_provider_fixture::{Protocol, ReplyStage, Step};
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ChatScope, CurrentView, StopThreadRequest, StudioRuntime,
    ThreadWorkspaceMode, TurnState,
    history::{HistoryDemand, HistoryEventsQuery, read_event_body_bytes},
};
use serde_json::Value;
use support::{Environment, current_demand, held_reply, program_reply, prompt_step, reached};

const PROMPT: &str = "read a skill, then hold the next model response";
const CALL: &str = "live-skill-load-call";
const SKILL: &str = "visible-skill";
const SKILL_CONTENT: &str = "# Visible skill\n\nKeep this guidance in context.";

async fn visible_skill(
    runtime: &StudioRuntime,
    thread: &str,
    active_turn: bool,
) -> Result<CurrentView> {
    let demand = current_demand();
    let reader = runtime
        .open_current_reader(thread, CURRENT_PROTOCOL_VERSION, demand)
        .await?;
    let result = async {
        let watch = reader.watch(None, demand).await?;
        let observed = tokio::time::timeout(support::integration_test_deadline()?, async {
            loop {
                let view = reader.snapshot(demand).await?;
                if view.state.active_turn.is_some() == active_turn
                    && view.state.runtime.as_ref().is_some_and(|runtime| {
                        runtime.active_skills.iter().any(|name| name == SKILL)
                    })
                {
                    return Ok(view);
                }
                ensure!(watch.next().await?.is_some(), "Current watch closed early");
            }
        })
        .await
        .context("skill activation not observed through Current");
        watch.close().await?;
        observed?
    }
    .await;
    reader.close().await?;
    result
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
    let checked = tokio::time::timeout(support::integration_test_deadline()?, async {
        let mut cut = reader.capture().await?;
        loop {
            let mut cursor = None;
            loop {
                let originals = reader
                    .events_page(
                        HistoryEventsQuery::Originals {
                            scope: ChatScope::conversation(None),
                        },
                        Some(cut.clone()),
                        cursor.clone(),
                        demand,
                    )
                    .await?;
                for event in originals.entries {
                    if event.payload_schema != "anywork.event/1" {
                        continue;
                    }
                    let value: Value = serde_json::from_str(&event.payload_json)?;
                    if event.turn_id.as_deref() != Some(turn)
                        || value["type"] != "tool"
                        || value["data"]["invocation"]["name"] != "skill_view"
                    {
                        continue;
                    }
                    ensure!(event.turn_id.as_deref() == Some(turn));
                    let bytes = read_event_body_bytes(&reader, &event, "tool.result", None)
                        .await?
                        .context("original tool result")?;
                    return Ok((event.event_id.clone(), value, bytes));
                }
                let Some(next) = originals.next else { break };
                ensure!(
                    cursor.as_ref() != Some(&next),
                    "originals cursor did not advance"
                );
                cursor = Some(next);
            }
            cut = reader.wait_changed(cut).await?;
        }
    })
    .await
    .context("completed nested tool original not observed");
    reader.close().await;
    checked?
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
                "# Visible skill",
                1,
                held_reply(&stage, "held-after-skill"),
            ),
        ],
        vec![],
    )
    .await?;
    let result = async {
        let skill = env.repo.join(".agents/skills").join(SKILL);
        std::fs::create_dir_all(&skill)?;
        std::fs::write(
            skill.join("SKILL.md"),
            format!("---\nname: {SKILL}\ndescription: Isolated activation fixture\n---\n\n{SKILL_CONTENT}\n"),
        )?;
        let started = env.start(ThreadWorkspaceMode::Local, PROMPT).await?;
        let thread_id = &started.thread.id;
        reached(&stage).await?;
        // The provider gate proves request progress, not publication by the
        // independent Current observer. Wait on that public observer itself.
        let current = visible_skill(&env.runtime, thread_id, true).await?;
        let turn = current.state
            .active_turn
            .as_ref()
            .context("original active Turn")?;
        ensure!(matches!(turn.state, TurnState::Running(_)));
        let turn_id = turn.id.clone();
        let runtime = current.state.runtime.as_ref().context("runtime projection")?;
        let execution_id = runtime
            .execution
            .as_ref()
            .context("original execution")?
            .id()
            .to_owned();
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
        visible_skill(&env.runtime, thread_id, false).await?;
        Ok(())
    }
    .await;
    stage.release();
    env.finish(result).await
}
