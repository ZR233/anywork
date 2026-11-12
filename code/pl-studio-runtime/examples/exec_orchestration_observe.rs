//! One fresh, isolated benchmark trial using the production Studio runtime.
use anyhow::{Context, Result, ensure};
use pl_model::{
    config::{AccountConfig, AccountId, ModelCatalogId, ModelRouteConfig, ReasoningEffort},
    protocol::ProtocolEndpoint,
};
use pl_protocol::{
    DelegationMode, ThreadStatus, ThreadWorkspaceMode,
    studio::{CreateThreadRequest, NewThreadModelRoute, StudioPromptInput},
};
use pl_studio_runtime::{
    ConfigPaths, ConfigStore, StudioConfig, StudioRuntime, StudioRuntimeOptions,
};
use serde::Deserialize;
use std::{
    path::{Path, PathBuf},
    time::{Duration, Instant},
};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Manifest {
    home: PathBuf,
    workspace: PathBuf,
    output: PathBuf,
    prompt_file: PathBuf,
    base_url: String,
    timeout_seconds: u64,
}

fn write(path: impl AsRef<Path>, value: &impl serde::Serialize) -> Result<()> {
    std::fs::write(path, serde_json::to_vec_pretty(value)?)?;
    Ok(())
}

fn configure(m: &Manifest) -> Result<()> {
    ensure!(!m.home.exists(), "a new experiment home is required");
    ensure!(
        m.home.is_absolute() && m.workspace.is_absolute() && m.output.is_absolute(),
        "absolute paths required"
    );
    ensure!(
        (1..=3000).contains(&m.timeout_seconds),
        "timeout must be 1..=3000"
    );
    let mut c = StudioConfig::default_config()?;
    let mut endpoint = ProtocolEndpoint::compatible("pilot", m.base_url.clone());
    endpoint.service_capabilities.prompt_cache.dialect =
        pl_model::protocol::PromptCacheDialect::OpenAiPromptCacheKey;
    let catalog = AccountConfig::from_bundled_catalog(
        endpoint.clone(),
        ModelCatalogId::new("openai")?,
        vec![],
    );
    let mut models = catalog
        .effective_models(None)?
        .into_iter()
        .filter(|model| model.model_id == "gpt-6-luna")
        .collect::<Vec<_>>();
    ensure!(
        models.len() == 1,
        "frozen model pool is not in the bundled catalog"
    );
    for model in &mut models {
        model
            .binding
            .set_transport(pl_model::model::ModelTransportProfile::responses_http());
    }
    let mut endpoint = ProtocolEndpoint::compatible("pilot", m.base_url.clone());
    // This experiment gateway forwards OpenAI Responses cache keys; other service capabilities
    // remain disabled rather than inheriting the official endpoint's tools and compaction.
    endpoint.service_capabilities.prompt_cache.dialect =
        pl_model::protocol::PromptCacheDialect::OpenAiPromptCacheKey;
    let mut account = AccountConfig::from_explicit_models(endpoint, models);
    account.bearer_token_env = Some("PILOT_MODEL_API_KEY".into());
    c.models.accounts.clear();
    c.models.accounts.insert(AccountId::new("pilot")?, account);
    let route = ModelRouteConfig {
        account_id: AccountId::new("pilot")?,
        model_id: "gpt-6-luna".into(),
        effort: Some(ReasoningEffort::new("high")),
    };
    for selected in c.mode_model_routes.values_mut() {
        *selected = route.clone();
    }
    c.skills.enabled = false;
    c.skills.auto_learn = false;
    c.web_search.mode = pl_protocol::search::WebSearchMode::Disabled;
    c.deepseek_web_search.enabled = false;
    c.instructions.project_doc_max_bytes = 0;
    // Keep exactly the directory executor for routed trials; no auxiliary reviewer or explorer.
    c.disabled_system_agents
        .extend(["explorer", "reviewer", "worktree_executor"].map(String::from));
    c.disabled_system_agents.insert("executor".into());
    c.delegation.mode = DelegationMode::Automatic;
    std::fs::create_dir_all(&m.home)?;
    ConfigStore::new(ConfigPaths::from_config_dir(&m.home)).save(&c)?;
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    let path = std::env::args()
        .nth(1)
        .context("usage: exec_orchestration_observe MANIFEST.json")?;
    let m: Manifest = serde_json::from_slice(&std::fs::read(path)?)?;
    std::fs::create_dir_all(&m.output)?;
    configure(&m)?;
    let started = Instant::now();
    // Test host selects the existing in-memory credential store only. Models, tools,
    // execution and persistence remain the production implementations with a real endpoint.
    let mut options = StudioRuntimeOptions::http_server(Some(m.home.clone()));
    options.host = pl_studio_runtime::StudioHostKind::Test;
    let runtime = Box::pin(StudioRuntime::initialize(options)).await?;
    let result = run(&runtime, &m).await;
    // Always await production shutdown; a cancelled collector must not orphan model/tool work.
    let shutdown = runtime.shutdown_runtime().await;
    write(
        m.output.join("completion.json"),
        &serde_json::json!({
            "elapsed_seconds":started.elapsed().as_secs_f64(),
            "run_error":result.as_ref().err().map(|e| format!("{e:#}")),
            "shutdown_error":shutdown.as_ref().err().map(|e| format!("{e:#}")),
            "model":"gpt-6-luna", "effort":"high", "cold_start":true
        }),
    )?;
    shutdown?;
    result
}

async fn run(runtime: &StudioRuntime, m: &Manifest) -> Result<()> {
    ensure!(
        runtime.runtime_snapshot().await?.startup_recovery.is_none(),
        "startup recovery reset experiment configuration"
    );
    let project = runtime.open_project(&m.workspace).await?;
    let task = std::fs::read_to_string(&m.prompt_file)?;
    let protocol = "Solve the task using the available tools. Do not delegate or ask questions. Run the relevant tests and report their actual result. Keep command output focused on what you need.";
    let created = Box::pin(runtime.create_thread_command(
        project.id,
        CreateThreadRequest {
            title: Some("exec orchestration experiment".into()),
            input: StudioPromptInput {
                input_id: "pilot-task".into(),
                text: format!("{protocol}\n\nTask:\n{task}"),
                attachment_draft_ids: vec![],
            },
            mode: "mode.simple".into(),
            route: NewThreadModelRoute {
                account_id: "pilot".into(),
                model_id: "gpt-6-luna".into(),
                effort: Some("high".into()),
            },
            delegation_mode: Some(DelegationMode::Automatic),
            delegation_preference: None,
            workspace_mode: ThreadWorkspaceMode::Local,
        },
        None,
    ))
    .await?;
    let root = created.thread.id.clone();
    write(m.output.join("root.json"), &created)?;
    let start = Instant::now();
    let mut ids = std::collections::BTreeSet::from([root.clone()]);
    let mut quiet = 0;
    loop {
        let state = runtime.read_state().await?;
        let directory = state
            .agent_directory
            .state
            .value()
            .context("agent directory unavailable")?;
        // A directory reservation precedes the child's live owner and checkpoint.
        // Only read a child once it has actually entered a Turn, or after the parent
        // has received the successful spawn receipt (handled below).
        for agent in &directory.agents {
            if agent.execution.as_ref().and_then(|e| e.turn_id()).is_some() {
                ids.insert(agent.thread_id.clone());
            }
        }
        let mut idle = true;
        let mut completed = ids.len() == directory.agents.len();
        let observed_ids = ids.clone();
        for id in &observed_ids {
            let s = runtime.thread_snapshot(id).await?;
            write(m.output.join(format!("{id}.snapshot.json")), &s)?;
            idle &= matches!(
                s.thread.status,
                ThreadStatus::Idle | ThreadStatus::Closed | ThreadStatus::Faulted
            );
            let turns = runtime.list_thread_turns(id, None, 100).await?;
            if id == &root {
                let value = serde_json::to_value(&turns)?;
                for turn in value["turns"].as_array().into_iter().flatten() {
                    for item in turn["items"].as_array().into_iter().flatten() {
                        let data = &item["state"]["data"];
                        if data["invocation"]["name"] != "spawn_agent"
                            || data["state"]["kind"] != "succeeded"
                        {
                            continue;
                        }
                        if let Some(result) = data["state"]["data"]["output"]["result"].as_str() {
                            let receipt: serde_json::Value = serde_json::from_str(result)?;
                            let agent_id = receipt["agentId"]
                                .as_str()
                                .or_else(|| receipt["receipt"]["agentId"].as_str());
                            if let Some(agent) = directory
                                .agents
                                .iter()
                                .find(|a| Some(a.agent_id.as_str()) == agent_id)
                            {
                                ids.insert(agent.thread_id.clone());
                            }
                        }
                    }
                }
            }
            completed &=
                !turns.turns.is_empty() && turns.turns.iter().all(|t| t.turn.state.is_terminal());
            write(m.output.join(format!("{id}.turns.json")), &turns)?;
        }
        write(m.output.join("directory.json"), &directory)?;
        if idle && completed {
            quiet += 1;
        } else {
            quiet = 0;
        }
        if quiet >= 3 {
            break;
        }
        ensure!(
            start.elapsed().as_secs() < m.timeout_seconds,
            "task exceeded wall time"
        );
        tokio::time::sleep(Duration::from_secs(1)).await;
    }
    ensure!(ids.len() == 1, "single-agent trial spawned children");
    Ok(())
}
