//! Real Responses HTTP producer → Core current owner → registered writer → complete JSON.

use std::{
    path::Path,
    sync::{
        Arc, LazyLock,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

use anyhow::{Context, Result, bail, ensure};
use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    model::ModelFactory,
    thread::{
        ModelExecutionPhase, ModelStepLimit, ThreadError, ThreadHandle, ThreadLifecycle,
        TurnCompletion, TurnInput,
        current::{RuntimeEpoch, SavedModelPhase, ThreadCurrent},
        input::InputExecution,
    },
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RuntimeTool, ToolError},
    },
};
use pl_model::{
    completion::{
        ModelStreamCurrent, ModelStreamCurrentState, ModelStreamToolInputPhase, ToolSpec,
    },
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
    runtime::{ModelRuntime, ThreadModel, thread_tool_declaration},
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step};
use serde_json::json;
use tokio::{task::JoinHandle, time::timeout};
use tokio_util::sync::CancellationToken;

use super::CurrentSource;
use crate::studio::{
    paths::CURRENT_FILE_NAME,
    storage::{coordinator::ThreadPersistenceCoordinator, state::StateStore},
};

const THREAD: &str = "responses-current-thread";
const TURN: &str = "responses-current-turn";
const PROMPT: &str = "保存完整 commentary 和仍未完成的工具参数，不执行工具。";
const PARTIAL: &str = "{\"path\":\"src/ma";
const DEADLINE: Duration = Duration::from_secs(20);
const CLEANUP_DEADLINE: Duration = Duration::from_secs(5);
type TurnTask = JoinHandle<std::result::Result<TurnCompletion, ThreadError>>;

#[derive(Debug)]
struct ExecutionCounter(Arc<AtomicUsize>);

impl pl_agent_tool::Tool for ExecutionCounter {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: LazyLock<pl_agent_tool::ToolDefinition> = LazyLock::new(|| {
            pl_agent_tool::ToolDefinition::json(
                "read_file",
                "Execution must remain zero",
                json!({
                    "type":"object", "properties":{"path":{"type":"string"}}, "required":["path"]
                }),
            )
            .expect("valid static fixture schema")
        });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: OpaquePayload,
        _: CallContext,
    ) -> std::result::Result<ToolOutput, ToolError> {
        self.0.fetch_add(1, Ordering::Relaxed);
        Ok(ToolOutput::new(
            OpaquePayload::text("unexpected tool execution"),
            Vec::new(),
        ))
    }
}

fn stream_from_file(current: &ThreadCurrent) -> Result<ModelStreamCurrent> {
    let call = current
        .model_call
        .as_ref()
        .context("current must retain its interrupted model call")?;
    let SavedModelPhase::Streaming { stream } = &call.phase else {
        bail!("expected saved streaming observation, got {:?}", call.phase);
    };
    ModelStreamCurrent::decode(stream).context("decode producer-owned stream from current JSON")
}

async fn read_current(path: &Path) -> Result<ThreadCurrent> {
    let bytes = tokio::fs::read(path)
        .await
        .context("read independent current JSON")?;
    serde_json::from_slice(&bytes).context("decode complete current JSON")
}

fn has_prefix(stream: &ModelStreamCurrent, commentary: &str) -> bool {
    stream
        .content_parts
        .iter()
        .any(|part| part.text == commentary)
        && stream
            .tool_inputs
            .iter()
            .any(|input| input.input == PARTIAL)
}

fn check_saved(
    current: &ThreadCurrent,
    stream: &ModelStreamCurrent,
    epoch: RuntimeEpoch,
    commentary: &str,
    executions: &AtomicUsize,
) -> Result<()> {
    let call = current.model_call.as_ref().context("saved model call")?;
    ensure!(
        current.thread_id == THREAD && current.saved_runtime_epoch == epoch,
        "saved Thread/owner identity changed"
    );
    ensure!(
        call.source_run_id == epoch && call.source_turn_id == TURN,
        "saved call lost its original owner/Turn"
    );
    ensure!(
        stream.attempt_id == call.source_attempt_id,
        "Core and producer snapshots belong to different attempts"
    );
    ensure!(
        stream.response_id.as_deref() == Some("gated-current-response"),
        "response identity was not preserved"
    );
    ensure!(
        has_prefix(stream, commentary),
        "complete accepted commentary or raw partial JSON was lost"
    );
    ensure!(
        stream
            .blocks
            .iter()
            .any(|block| block.provider_item_id.as_deref() == Some("commentary") && block.closed),
        "the completed commentary member must survive while the response remains open"
    );
    ensure!(
        stream.tool_inputs.len() == 1,
        "expected exactly one incomplete tool input"
    );
    let input = &stream.tool_inputs[0];
    ensure!(
        input.name == "read_file" && input.provider_call_id.as_deref() == Some("call_0"),
        "original provider tool identity changed"
    );
    ensure!(
        input.phase == ModelStreamToolInputPhase::Streaming && input.input == PARTIAL,
        "partial JSON must remain an unparsed streaming string"
    );
    ensure!(
        stream.tool_calls.is_empty(),
        "partial input must not become an executable tool call"
    );
    ensure!(
        stream
            .call_bindings
            .iter()
            .any(|binding| binding.attempt_id == call.source_attempt_id
                && binding.provider_call_id == "call_0"
                && binding.call_id == input.call_id),
        "provider/internal attempt binding was lost"
    );
    ensure!(
        executions.load(Ordering::Relaxed) == 0
            && current.state.tasks.is_empty()
            && current.state.deliveries.is_empty(),
        "an incomplete tool call was executed or installed as a result"
    );
    ensure!(current.state.context.records.iter().any(|record| record.source == ContextSource::User && record.content.iter().any(|content| matches!(content, ContextContent::Text { text } if text.as_ref() == PROMPT))), "confirmed context lost the original input");
    ensure!(
        current
            .state
            .context
            .records
            .iter()
            .all(|record| !matches!(record.source, ContextSource::Assistant)
                && record.tool_calls.is_empty()),
        "an unfinished response was installed into confirmed model context"
    );
    current.validate(THREAD)?;
    Ok(())
}

async fn join_cancelled_turn(turn: &mut Option<TurnTask>) -> Result<()> {
    if let Some(task) = turn.as_mut() {
        let result = task.await;
        *turn = None;
        ensure!(
            result.context("join real Core Turn")?.is_err(),
            "the blocked model Turn must be cancelled, not completed"
        );
    }
    Ok(())
}

#[tokio::test]
async fn responses_http_sse_current_saves_partial_and_final_handoff() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let current_path = directory.path().join(CURRENT_FILE_NAME);
    let history_path = directory.path().join("history.sqlite");
    let unreadable_history = b"deliberately not a SQLite database; current must not open this";
    std::fs::write(&history_path, unreadable_history)?;
    let first = "完整 commentary 的第一段。".repeat(512);
    let second = "第二段已接纳，仍须完整保存。\n".repeat(512);
    let commentary = format!("{first}{second}");
    let reached = CancellationToken::new();
    let release = CancellationToken::new();
    let fixture = timeout(CLEANUP_DEADLINE, FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp, PROMPT, 0, Reply::GatedSse {
            before: vec![
                json!({"type":"response.created","response":{"id":"gated-current-response","model":"current-model"}}),
                json!({"type":"response.output_item.added","output_index":0,"item":{"id":"commentary","type":"message","role":"assistant","phase":"commentary","content":[]}}),
                json!({"type":"response.output_text.delta","output_index":0,"item_id":"commentary","content_index":0,"delta":first}),
                json!({"type":"response.output_text.delta","output_index":0,"item_id":"commentary","content_index":0,"delta":second}),
                json!({"type":"response.output_item.done","output_index":0,"item":{"id":"commentary","type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":commentary}]}}),
                json!({"type":"response.output_item.added","output_index":1,"item":{"id":"tool-input","type":"function_call","call_id":"call_0","name":"read_file","arguments":""}}),
                json!({"type":"response.function_call_arguments.delta","item_id":"tool-input","call_id":"call_0","delta":PARTIAL}),
            ], reached: reached.clone(), release: release.clone(), after: Vec::new(),
        },
    )])).await.context("start local Responses fixture timed out")??;

    let executions = Arc::new(AtomicUsize::new(0));
    let coordinator = ThreadPersistenceCoordinator::default();
    let mut store = StateStore::new(directory.path().into(), THREAD);
    let mut owners = Vec::new();
    let mut turn: Option<TurnTask> = None;
    let exercise = timeout(DEADLINE, async {
        let mut model = ModelInfo::compatible("current-model");
        model.binding.set_transport(ModelTransportProfile::responses_http());
        let factory = ModelFactory::new(ThreadModel::new(ModelRuntime::new_with_account_id(
            "fixture", ProtocolEndpoint::compatible("fixture", fixture.base_url()), model,
        )?, None));
        let handle = ThreadHandle::start_current(THREAD.into(), factory.open_session().await?)?;
        owners.push(handle.clone());
        handle.register_tools(vec![Registration::prepare("read_file".into(), thread_tool_declaration(&ToolSpec::Function {
            name: "read_file".into(), description: "Execution must remain zero".into(),
            input_schema: json!({"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}),
            allowed_callers: Vec::new(), output_schema: None,
        })?)?.attach(RuntimeTool::new(ExecutionCounter(executions.clone()))).foreground()]).await?;
        let epoch = handle.runtime_epoch();
        ensure!(!handle.snapshot().persistence.attached, "the new current owner must not attach history");
        store.attach_current(coordinator.clone(), None, epoch, CurrentSource::from_thread(handle.clone())).await?;
        let mut changes = handle.subscribe();
        turn = Some(tokio::spawn({
            let handle = handle.clone();
            async move { handle.run_turn(TurnInput {
                turn_id: TURN.into(), attempt_prefix: "current-fixture-attempt".into(),
                content: vec![ContextContent::Text { text: PROMPT.into() }],
                max_model_steps: ModelStepLimit::Unlimited, cancellation: CancellationToken::new(),
            }).await }
        }));
        tokio::select! {
            () = reached.cancelled() => {},
            result = turn.as_mut().context("running Turn")? => {
                turn = None;
                bail!("model Turn ended before the fixture gate: {result:?}");
            }
        }
        // Server delivery is not an acceptance ACK. Each probe below is driven by the real
        // owner's producer-dirty watch, and inspects only a newly persisted JSON, never RAM data.
        let saved = loop {
            let snapshot = tokio::select! {
                snapshot = changes.next() => snapshot.context("Core subscription closed during streaming")?,
                result = turn.as_mut().context("running Turn")? => {
                    turn = None;
                    bail!("model Turn ended while the next frame was blocked: {result:?}");
                }
            };
            if snapshot.model_execution != Some(ModelExecutionPhase::Running) { continue; }
            let receipt = store.flush_current(epoch).await?;
            let current = read_current(&current_path).await?;
            ensure!(current.snapshot_revision >= receipt.snapshot_revision, "file predates its flush receipt");
            let stream = stream_from_file(&current)?;
            if has_prefix(&stream, &commentary) { break (current, stream); }
        };
        check_saved(&saved.0, &saved.1, epoch, &commentary, &executions)?;
        ensure!(saved.1.state == ModelStreamCurrentState::Open, "the gate must leave the response open");
        ensure!(!release.is_cancelled() && fixture.recorded().len() == 1, "capture must not release the fixture or issue another request");
        let loaded = store.load_current().await?.context("independent current load")?;
        check_saved(&loaded, &stream_from_file(&loaded)?, epoch, &commentary, &executions)?;
        let source_attempt = saved.0.model_call.as_ref().context("saved call")?.source_attempt_id.clone();

        store.close_current(epoch).await?;
        join_cancelled_turn(&mut turn).await?;
        ensure!(handle.snapshot().lifecycle == ThreadLifecycle::Closed && !store.current_save_state()?.observer_registered, "close must join the owner and its observer");
        ensure!(!release.is_cancelled(), "close must finish without waiting for the next network frame");
        let final_current = read_current(&current_path).await?;
        let final_stream = stream_from_file(&final_current)?;
        check_saved(&final_current, &final_stream, epoch, &commentary, &executions)?;
        ensure!(matches!(final_stream.state, ModelStreamCurrentState::Failed { .. }), "final JSON must contain the producer's cancelled handoff, not an earlier open capture");
        ensure!(final_stream.attempt_id == source_attempt, "close changed the producing attempt");
        let final_loaded = store.load_current().await?.context("load final handoff independently")?;
        check_saved(&final_loaded, &stream_from_file(&final_loaded)?, epoch, &commentary, &executions)?;
        ensure!(tokio::fs::read(&history_path).await? == unreadable_history, "current touched independent history bytes");

        let restored = ThreadHandle::restore_current(final_loaded, None)?;
        owners.push(restored.clone());
        let new_epoch = restored.runtime_epoch();
        ensure!(new_epoch != epoch && matches!(restored.snapshot().input_execution, InputExecution::Paused), "cold restore must be paused under a new epoch");
        store.attach_current(coordinator.clone(), None, new_epoch, CurrentSource::from_thread(restored.clone())).await?;
        store.flush_current(new_epoch).await?;
        let paused = read_current(&current_path).await?;
        let old_call = paused.model_call.as_ref().context("paused saved call")?;
        ensure!(paused.saved_runtime_epoch == new_epoch && old_call.source_run_id == epoch && old_call.source_attempt_id == source_attempt, "restoring must not rewrite the old stream's source identity");
        let paused_stream = stream_from_file(&paused)?;
        ensure!(has_prefix(&paused_stream, &commentary) && paused_stream.attempt_id == source_attempt && matches!(paused_stream.state, ModelStreamCurrentState::Failed { .. }), "paused restore lost the complete last accepted stream");
        ensure!(executions.load(Ordering::Relaxed) == 0 && fixture.recorded().len() == 1, "paused restore must neither execute tools nor start a model request");
        store.close_current(new_epoch).await?;
        Ok::<_, anyhow::Error>(())
    }).await.context("real Responses current integration exceeded its deadline").and_then(|result| result);

    // All checks above return errors rather than panicking, so even a failed assertion reaches
    // explicit fixture release and join. Core/Turn cleanup is bounded independently as well.
    release.cancel();
    let writer_cleanup = timeout(CLEANUP_DEADLINE, async {
        if let Ok(state) = store.current_save_state()
            && let Some(epoch) = state.runtime_epoch
        {
            store.close_current(epoch).await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("current writer cleanup timed out")
    .and_then(|result| result);
    let owner_cleanup = timeout(CLEANUP_DEADLINE, async {
        for handle in &owners {
            if handle.snapshot().lifecycle != ThreadLifecycle::Closed {
                handle.close().await?;
            }
        }
        Ok::<_, anyhow::Error>(())
    })
    .await
    .context("Core owner cleanup timed out")
    .and_then(|result| result);
    let turn_cleanup = timeout(CLEANUP_DEADLINE, join_cancelled_turn(&mut turn))
        .await
        .context("Core Turn join timed out")
        .and_then(|result| result);
    let requests = timeout(CLEANUP_DEADLINE, fixture.finish())
        .await
        .context("fixture listener join timed out")
        .and_then(|result| result);
    exercise?;
    writer_cleanup?;
    owner_cleanup?;
    turn_cleanup?;
    let requests = requests?;
    ensure!(
        requests.len() == 1 && requests[0].accepted && requests[0].path.ends_with("/responses"),
        "expected exactly one accepted Responses HTTP request"
    );
    ensure!(
        requests[0].body["tools"]
            .as_array()
            .is_some_and(|tools| tools.iter().any(|tool| tool["name"] == "read_file")),
        "the real request did not include the executable tool declaration"
    );
    Ok(())
}
