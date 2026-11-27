use super::{
    ThreadStorageSink,
    storage_fault_tests::{Fixture, spawn_live_projection_for_thread, test_thread},
};
use anyhow::{Context, Result};
use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall,
        PreparedModelCall,
    },
    thread::{ModelStepLimit, ThreadHandle, TurnInput, history_sink::HistorySinkHandle},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_tool::{
    exec::TOOL_EXEC,
    task_control::{TaskControlKind, TaskControlTool, query_definition},
};
use serde_json::{Value, json};
use std::sync::{
    Arc, LazyLock,
    atomic::{AtomicUsize, Ordering},
};
use tokio_util::sync::CancellationToken;

const ORIGINAL_CALL: &str = "original-command";
const TASK_ID: &str = "task:original-command";
const QUERY: &str = "get_tool_task";

struct Script {
    cursor: usize,
}

impl ModelSession for Script {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let turn = &request.turn_id;
        let completed = request.context.records.iter().any(|record| {
            record.turn_id.as_ref() == Some(turn)
                && matches!(record.source, ContextSource::ToolResult { .. })
        });
        let tool_calls = if completed {
            vec![]
        } else {
            let (call_id, tool_id, args) = if turn == "run-original" {
                (ORIGINAL_CALL.into(), TOOL_EXEC, json!({}))
            } else {
                (
                    format!("query:{turn}"),
                    QUERY,
                    json!({"taskId":TASK_ID,"resultCursor":self.cursor}),
                )
            };
            vec![ModelToolCall {
                presentation_contract: None,
                rejection: None,
                call_id,
                tool_id: tool_id.into(),
                arguments: OpaquePayload::new("application/json", 1, args.to_string()).unwrap(),
            }]
        };
        Ok(PreparedModelCall::new(async move {
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![ContextContent::Text {
                    text: "fixture model".into(),
                }],
                tool_calls,
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

struct CommandResult {
    executions: Arc<AtomicUsize>,
    result: ToolOutput,
}

impl pl_agent_tool::Tool for CommandResult {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: LazyLock<pl_agent_tool::ToolDefinition> = LazyLock::new(|| {
            pl_agent_tool::ToolDefinition::json(
                TOOL_EXEC,
                "Counted command result",
                json!({"type":"object"}),
            )
            .unwrap()
        });
        &DEFINITION
    }

    async fn execute(&self, _: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        self.executions.fetch_add(1, Ordering::Relaxed);
        Ok(self.result.clone())
    }
}

fn query_registration() -> Result<Registration> {
    Ok(
        TaskControlTool::new(TaskControlKind::Query, query_definition()).registration(
            Registration::prepare(QUERY.into(), OpaquePayload::text(QUERY))?,
        ),
    )
}

async fn run_turn(owner: &ThreadHandle, turn: &str) -> Result<()> {
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        owner.run_turn(TurnInput {
            turn_id: turn.into(),
            attempt_prefix: turn.into(),
            content: vec![ContextContent::Text {
                text: "query original".into(),
            }],
            max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
            cancellation: CancellationToken::new(),
        }),
    )
    .await??;
    Ok(())
}

fn query_page(owner: &ThreadHandle, turn: &str) -> Result<Value> {
    let context = owner.snapshot().context.clone();
    let call_id = format!("query:{turn}");
    let data = context
        .records
        .iter()
        .find_map(|record| {
            let ContextSource::ToolResult {
                call_id: observed,
                tool_id,
            } = &record.source
            else {
                return None;
            };
            (observed == &call_id && tool_id == QUERY)
                .then(|| record.tool_data.as_value())
                .flatten()
        })
        .context("query tool did not publish program data")?;
    assert_eq!(data["task"]["taskId"], TASK_ID);
    assert_eq!(data["task"]["status"], "succeeded");
    Ok(data["result"].clone())
}

async fn finish_history(sink: &ThreadStorageSink, id: &str, sequence: u64) -> Result<()> {
    let channel = &sink.0.channel;
    let mut updates = channel.subscribe();
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        loop {
            let error = updates.borrow_and_update().error.clone();
            if let Some(error) = error {
                anyhow::bail!("History handoff failed: {error}");
            }
            if channel.handoff_ticket() >= sequence {
                break;
            }
            updates.changed().await?;
        }
        channel.await_handoff_durable(id, sequence).await
    })
    .await??;
    channel.stop_and_join().await
}

#[tokio::test]
async fn tool_result_attached_history_preserves_pages_and_command_resources_after_reopen()
-> Result<()> {
    let id = "attached-command-result";
    let fixture = Fixture::new(id).await?;
    let paths = fixture.store.registered_session_paths(id)?;
    let resources = crate::resource_store::FileResourceStore::new(paths.root().join("resources"));
    let stdout_bytes = b"complete retained stdout\0";
    let stderr_bytes = b"complete retained stderr\n";
    let stdout = resources
        .retain_bytes(Arc::from(stdout_bytes.as_slice()), "text/plain")
        .await?;
    let stderr = resources
        .retain_bytes(Arc::from(stderr_bytes.as_slice()), "text/plain")
        .await?;
    let result = ToolOutput::from_data(
        json!({"stdout":"🧭".repeat(2300),"stderr":""}),
        vec![ContextContent::Text {
            text: "short model preview".into(),
        }],
    )
    .with_details(
        json!({"command":{"exitCode":0,"stdoutResource":stdout,"stderrResource":stderr}}),
    );
    let expected = serde_json::to_string(result.result())?;
    let executions = Arc::new(AtomicUsize::new(0));
    let owner =
        ThreadHandle::start_current(id.into(), Some(DynModelSession::new(Script { cursor: 0 })))?;
    owner
        .attach_history(HistorySinkHandle::new(fixture.sink.clone()))
        .await?;
    let projector = spawn_live_projection_for_thread(fixture.store.clone(), id);
    owner
        .register_tools(vec![
            Registration::prepare(TOOL_EXEC.into(), OpaquePayload::text(TOOL_EXEC))?.attach(
                pl_core::tool::opaque::RuntimeTool::new(CommandResult {
                    executions: executions.clone(),
                    result,
                }),
            ),
            query_registration()?,
        ])
        .await?;
    run_turn(&owner, "run-original").await?;
    run_turn(&owner, "active-read").await?;
    let first = query_page(&owner, "active-read")?;
    let cursor = usize::try_from(
        first["nextCursor"]
            .as_u64()
            .context("missing continuation")?,
    )?;
    assert!(cursor <= 8192 && expected.is_char_boundary(cursor));
    assert_eq!(first["content"].as_str(), Some(&expected[..cursor]));
    assert_eq!(first["totalBytes"], expected.len());
    assert_eq!(executions.load(Ordering::Relaxed), 1);

    owner.close().await?;
    let current = owner.capture_current(CancellationToken::new()).await?;
    assert!(current.state.deliveries.is_empty());
    let current_file =
        crate::studio::storage::current_file::CurrentFile::new(paths.root().to_owned(), id.into());
    current_file.save(current).await?;
    finish_history(&fixture.sink, id, owner.snapshot().commit_sequence).await?;
    projector.await?;
    drop(owner);
    let history = fixture.store.history(id).await?;
    history.close().await?;
    drop(history);
    drop(fixture.sink);
    drop(fixture.projection);

    let cold_reader = crate::history::HistoryStore::open_reader(
        paths.history_database(),
        id,
        crate::history::HistoryLimits::default(),
    )
    .await?;
    for (resource, bytes) in [
        (stdout, stdout_bytes.as_slice()),
        (stderr, stderr_bytes.as_slice()),
    ] {
        assert_eq!(
            crate::studio::history_resources::read(&cold_reader, &resources, resource.id()).await?,
            bytes
        );
    }
    cold_reader.close().await;

    let cold_sink = ThreadStorageSink::new(fixture.store.clone(), test_thread(id)).await?;
    let current = current_file
        .load()
        .await?
        .context("cold Current is absent")?;
    let cold =
        ThreadHandle::restore_current(current, Some(DynModelSession::new(Script { cursor })))?;
    cold.attach_history(HistorySinkHandle::new(cold_sink.clone()))
        .await?;
    let reprojector = spawn_live_projection_for_thread(fixture.store.clone(), id);
    cold.register_tools(vec![query_registration()?]).await?;
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        cold.resume_current(
            "cold-read".into(),
            ModelStepLimit::Limited(3.try_into().unwrap()),
            CancellationToken::new(),
        ),
    )
    .await??;
    let second = query_page(&cold, "cold-read")?;
    assert_eq!(second["content"].as_str(), Some(&expected[cursor..]));
    assert!(second["nextCursor"].is_null());
    assert_eq!(second["totalBytes"], expected.len());
    assert_eq!(executions.load(Ordering::Relaxed), 1);
    cold.close().await?;
    finish_history(&cold_sink, id, cold.snapshot().commit_sequence).await?;
    reprojector.await?;
    Ok(())
}
