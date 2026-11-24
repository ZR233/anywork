#[expect(
    dead_code,
    reason = "shared isolated fixtures also serve other integration test binaries"
)]
mod support;

use anyhow::{Context, Result};
use axum::{Router, extract::State, response::IntoResponse, routing::post};
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelDefinition, ModelTransportProfile},
};
use pl_provider_fixture::{RealtimeToolCall, responses_text, responses_tool_calls};
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, CreateThreadRequest, DelegationMode, NewThreadModelRoute,
    StudioHostKind, StudioPromptInput, StudioRuntime, StudioRuntimeOptions,
    StudioSubmitPromptOptions, StudioSubmitPromptRequest, ThreadWorkspaceMode,
    config::{ConfigPaths, ConfigStore, StudioConfig},
    mode::ThreadModeId,
};
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};
use tokio::net::TcpListener;

#[derive(Default)]
struct DynamicServerState {
    calls: usize,
    seen_workflow_context: Vec<Value>,
}

fn extract_json_object_after(text: &str, marker: &str) -> Option<Value> {
    let mut rest = text;
    while let Some((_, after)) = rest.split_once(marker) {
        if let Some(start) = after.find('{') {
            let mut stream =
                serde_json::Deserializer::from_str(&after[start..]).into_iter::<Value>();
            if let Some(Ok(parsed)) = stream.next()
                && parsed.get("runId").is_some()
            {
                return Some(parsed);
            }
        }
        rest = after;
    }
    None
}

fn extract_workflow_projection(body: &Value) -> Option<Value> {
    if let Some(input) = body.get("input").and_then(|v| v.as_array()) {
        // Always take the LAST/latest `studio.workflow` context projection in `input`.
        for item in input.iter().rev() {
            if let Some(s) = item.get("content").and_then(|c| c.as_str())
                && let Some(parsed) = extract_json_object_after(s, "studio.workflow")
            {
                return Some(parsed);
            }
            if let Some(arr) = item.get("content").and_then(|c| c.as_array()) {
                let joined: String = arr
                    .iter()
                    .filter_map(|part| part.get("text").and_then(|t| t.as_str()))
                    .collect::<Vec<_>>()
                    .join("\n");
                if let Some(parsed) = extract_json_object_after(&joined, "studio.workflow") {
                    return Some(parsed);
                }
            }
        }
    }
    if let Some(instructions) = body.get("instructions").and_then(|v| v.as_str())
        && let Some(parsed) = extract_json_object_after(instructions, "studio.workflow")
    {
        return Some(parsed);
    }
    None
}

async fn responses_handler(
    State(state): State<Arc<Mutex<DynamicServerState>>>,
    body: String,
) -> impl IntoResponse {
    let body_json: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    let wf = extract_workflow_projection(&body_json);
    let (step, run_id, rev, current_state) = {
        let mut guard = state.lock().unwrap();
        let step = guard.calls;
        guard.calls += 1;
        if let Some(wf_val) = &wf {
            guard.seen_workflow_context.push(wf_val.clone());
        }
        let run_id = wf
            .as_ref()
            .and_then(|v| v["runId"].as_str())
            .unwrap_or("")
            .to_string();
        let rev = wf
            .as_ref()
            .and_then(|v| v["revision"].as_u64())
            .unwrap_or(0);
        let cur = wf
            .as_ref()
            .and_then(|v| v["currentState"]["id"].as_str())
            .unwrap_or("")
            .to_string();
        (step, run_id, rev, cur)
    };

    let events = match step {
        // Turn 1, request 0: move workflow triage -> planning
        0 => {
            assert!(
                !run_id.is_empty(),
                "workflow projection missing in request 0: {body_json}"
            );
            responses_tool_calls(
                "resp-0",
                support::MODEL,
                &[RealtimeToolCall {
                    item_id: "item-wf-1",
                    call_id: "call-wf-1",
                    name: "exec",
                    arguments: json!({
                        "code": "return tools.workflow_transition(args)",
                        "args": {
                            "expectedRunId": run_id,
                            "expectedRevision": rev,
                            "expectedStateId": current_state,
                            "targetStateId": "planning",
                            "completion": {
                                "reason": "complex task needs planning",
                                "summary": "Assessed complexity and moved to planning",
                                "evidence": ["initial triage"]
                            }
                        }
                    })
                    .to_string(),
                }],
            )
        }
        // Turn 1, request 1: update plan via forced jump to approved so turn 1 finishes cleanly
        1 => responses_tool_calls(
            "resp-1",
            support::MODEL,
            &[RealtimeToolCall {
                item_id: "item-plan-1",
                call_id: "call-plan-1",
                name: "plan_transition",
                arguments: json!({
                    "targetState": "approved",
                    "force": true,
                    "expectedRevision": 0,
                    "content": "# Native Restart Blueprint\n\n- Step A: persist\n- Step B: verify after restart",
                    "reason": "commit plan for restart recovery test"
                })
                .to_string(),
            }],
        ),
        // Turn 1, request 2: finish turn 1 before runtime shutdown
        2 => responses_text("turn 1 done at planning", "resp-2", support::MODEL),
        // Turn 2 (AFTER RESTART!), request 3: verify workflow was still in `planning` (not reset to `triage`) and force-jump or transition planning -> working -> completed
        3 => responses_tool_calls(
            "resp-3",
            support::MODEL,
            &[RealtimeToolCall {
                item_id: "item-wf-2",
                call_id: "call-wf-2",
                name: "exec",
                arguments: json!({
                    "code": "return tools.workflow_transition(args)",
                    "args": {
                        "expectedRunId": run_id,
                        "expectedRevision": rev,
                        "expectedStateId": current_state,
                        "targetStateId": "working",
                        "completion": {
                            "reason": "plan ready after restart",
                            "summary": "Resumed planning into working after restart",
                            "evidence": ["restored snapshot"]
                        }
                    }
                })
                .to_string(),
            }],
        ),
        _ => responses_text("turn 2 continued from planning", "resp-4", support::MODEL),
    };

    let mut sse = String::new();
    for event in events {
        sse.push_str("data: ");
        sse.push_str(&event.to_string());
        sse.push_str("\n\n");
    }
    sse.push_str("data: [DONE]\n\n");
    ([("content-type", "text/event-stream")], sse)
}

#[tokio::test]
async fn native_workflow_and_plan_state_recover_after_shutdown_and_restart() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let repo = temp.path().join("repo");
    std::fs::create_dir_all(&repo)?;
    support::git(&repo, &["init", "-b", "main"])?;
    support::git(&repo, &["config", "--local", "core.autocrlf", "false"])?;
    support::git(&repo, &["config", "--local", "core.eol", "lf"])?;
    support::git(&repo, &["config", "user.name", "Restart Test"])?;
    support::git(&repo, &["config", "user.email", "restart@example.invalid"])?;
    std::fs::write(repo.join("README.md"), "hello\n")?;
    support::git(&repo, &["add", "."])?;
    support::git(&repo, &["commit", "-m", "init"])?;

    let state = Arc::new(Mutex::new(DynamicServerState::default()));
    let listener = TcpListener::bind(("127.0.0.1", 0)).await?;
    let addr = listener.local_addr()?;
    let app = Router::new()
        .route("/responses", post(responses_handler))
        .with_state(state.clone());
    let server_handle = tokio::spawn(async move {
        let _ = axum::serve(listener, app).await;
    });

    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    let mut model = ModelDefinition::compatible(support::MODEL);
    model
        .extra
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    config.models.accounts.insert(
        AccountId::new("dynamic-root")?,
        AccountConfig::from_explicit_models(
            pl_model::protocol::providers::openai::compatible_endpoint(
                "dynamic-root",
                format!("http://{addr}"),
            ),
            vec![model],
        ),
    );
    let route = ModelRouteConfig {
        account_id: AccountId::new("dynamic-root")?,
        model_id: support::MODEL.into(),
        effort: None,
    };
    for selected in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        *selected = route.clone();
    }
    ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;

    let options = StudioRuntimeOptions {
        studio_home: Some(home.clone()),
        host: StudioHostKind::Test,
        skill_search: pl_studio_runtime::SkillSearchOptions {
            include_default_user_dir: false,
            additional_dirs: Vec::new(),
        },
        ..StudioRuntimeOptions::desktop()
    };
    let runtime = Box::pin(StudioRuntime::initialize(options.clone())).await?;
    let project = runtime.open_project(&repo).await?;
    let created = Box::pin(runtime.create_thread_command(
        project.id.clone(),
        CreateThreadRequest {
            title: Some("Native restart recovery".into()),
            input: StudioPromptInput {
                input_id: "turn-1".into(),
                text: "plan and restart".into(),
                attachment_draft_ids: Vec::new(),
            },
            mode: ThreadModeId::auto().to_string(),
            route: NewThreadModelRoute {
                account_id: "dynamic-root".into(),
                model_id: support::MODEL.into(),
                effort: None,
            },
            service_tier: None,
            delegation_mode: Some(DelegationMode::Profile),
            delegation_preference: None,
            workspace_mode: ThreadWorkspaceMode::Local,
        },
        None,
    ))
    .await?;
    let thread_id = created.thread.id.clone();
    support::terminal(&runtime, &thread_id, Some("turn-1")).await?;

    // Shutdown cleanly and restart StudioRuntime from disk.
    runtime.shutdown_runtime().await?;
    let restarted = Box::pin(StudioRuntime::initialize(options)).await?;

    let reader = restarted
        .open_current_reader(
            &thread_id,
            CURRENT_PROTOCOL_VERSION,
            support::current_demand(),
        )
        .await?;
    let view = reader.snapshot(support::current_demand()).await?;
    let rt = view.state.runtime.context("restored runtime state")?;
    let wf = rt.workflow.context("restored workflow snapshot")?;
    let run = wf.current_run.context("restored workflow run")?;
    assert_eq!(run.mode_id, ThreadModeId::auto());
    assert_eq!(run.current_state_id, "planning");
    assert_eq!(wf.revision, 2);
    assert_eq!(run.visited_state_ids, vec!["triage", "planning"]);
    assert!(!run.last_transition_forced);
    let graph = restarted
        .thread_workflow_graph(&thread_id)
        .await?
        .context("restored workflow graph")?;
    assert_eq!(graph.mode_id, ThreadModeId::auto());
    assert_eq!(graph.initial_state_id, "triage");
    let definition = restarted.read_thread_mode_definition(&ThreadModeId::auto())?;
    let workflow = definition
        .document
        .definition
        .workflow
        .as_ref()
        .context("auto mode workflow")?;
    assert_eq!(graph.states.len(), workflow.states.len());
    assert_eq!(graph.edges.len(), workflow.transitions.len());

    let plan = rt.plan.context("restored plan snapshot")?;
    assert_eq!(
        plan.state,
        pl_studio_runtime::plan_tool::AgentSessionPlanPhase::Approved
    );
    assert_eq!(plan.revision, 1);
    let doc = plan.document.context("restored plan document")?;
    assert!(doc.markdown.contains("Native Restart Blueprint"));

    let saved = support::saved(&home, &thread_id).await?;
    let persisted_plan = pl_studio_runtime::plan_tool::decode_plan_state(
        &saved.current.state.extensions[pl_studio_runtime::plan_tool::PLAN_EXTENSION].payload,
    )?;
    assert_eq!(persisted_plan.plan.history.len(), 1);
    assert!(persisted_plan.plan.history[0].forced);
    reader.close().await?;

    // Send turn 2 after restart and verify the active `planning` run was preserved (NOT reset to `triage`).
    restarted
        .submit_prompt(StudioSubmitPromptRequest {
            thread_id: thread_id.clone(),
            input: StudioPromptInput {
                input_id: "turn-2".into(),
                text: "continue workflow".into(),
                attachment_draft_ids: Vec::new(),
            },
            options: StudioSubmitPromptOptions::default(),
        })
        .await?;
    support::terminal(&restarted, &thread_id, Some("turn-2")).await?;

    let reader2 = restarted
        .open_current_reader(
            &thread_id,
            CURRENT_PROTOCOL_VERSION,
            support::current_demand(),
        )
        .await?;
    let view2 = reader2.snapshot(support::current_demand()).await?;
    let wf2 = view2
        .state
        .runtime
        .context("post-restart runtime")?
        .workflow
        .context("post-restart workflow")?;
    let run2 = wf2.current_run.context("post-restart run")?;
    assert_eq!(run2.current_state_id, "working");
    assert_eq!(wf2.revision, 3);
    assert_eq!(
        run2.visited_state_ids,
        vec!["triage", "planning", "working"]
    );
    reader2.close().await?;

    restarted.shutdown_runtime().await?;
    server_handle.abort();
    Ok(())
}
