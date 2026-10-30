use anyhow::{Context, Result, ensure};
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
};
use pl_protocol::{
    AgentWorkspaceMode, ThreadNotification, ThreadSubscriptionRequest, ThreadSubscriptionUpdate,
    ThreadWorkspaceMode,
    studio::{CreateThreadRequest, NewThreadModelRoute, StudioPromptInput},
};
use pl_provider_fixture::{FixtureServer, Protocol, RealtimeToolCall, Reply, ReplyStage, Step};
use pl_studio_runtime::{
    StudioHostKind, StudioRuntime, StudioRuntimeOptions,
    config::{ConfigPaths, ConfigStore, StudioConfig, UserAgentProfile, save_user_agent_profile},
};
use sea_orm::{ConnectionTrait, Database, DbBackend, Statement};
use std::{
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

pub const MODEL: &str = "lifecycle-model";
pub const EXECUTOR: &str = "lifecycle_executor";

pub fn git(path: &Path, args: &[&str]) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(path)
        .args(args)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .output()?;
    ensure!(
        output.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}

pub fn text_reply(text: &str, id: &str) -> Reply {
    Reply::Sse(pl_provider_fixture::responses_text(text, id, MODEL))
}

pub fn tool_reply(name: &str, call: &str, args: serde_json::Value) -> Reply {
    Reply::Sse(pl_provider_fixture::responses_tool_calls(
        call,
        MODEL,
        &[RealtimeToolCall {
            item_id: call,
            call_id: call,
            name,
            arguments: args.to_string(),
        }],
    ))
}

pub fn held_reply(stage: &ReplyStage, id: &str) -> Reply {
    stage.gated(
        vec![serde_json::json!({"type":"response.created","response":{"id":id,"model":MODEL}})],
        pl_provider_fixture::responses_text("released", id, MODEL)
            .into_iter()
            .skip(1)
            .collect(),
    )
}

pub async fn reached(stage: &ReplyStage) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), stage.wait_reached())
        .await
        .context("provider stage was not reached")
}

pub async fn completed_prompt(
    runtime: &StudioRuntime,
    id: &str,
    prompt: &str,
) -> Result<pl_protocol::Turn> {
    terminal(runtime, id, Some(&format!("input-{prompt}"))).await
}

async fn terminal(
    runtime: &StudioRuntime,
    id: &str,
    input: Option<&str>,
) -> Result<pl_protocol::Turn> {
    let mut subscription = runtime
        .subscribe_thread(ThreadSubscriptionRequest {
            thread_id: id.into(),
        })
        .await?;
    tokio::time::timeout(Duration::from_secs(20), async {
        while let Some(update) = subscription.recv().await? {
            if let ThreadSubscriptionUpdate::Notification { notification } = update
                && let ThreadNotification::TurnCompleted { turn } = notification.notification
                && input.is_none_or(|input| turn.input_id.as_deref() == Some(input))
            {
                return Ok::<_, anyhow::Error>(turn);
            }
        }
        anyhow::bail!("thread stream ended without a terminal Turn")
    })
    .await
    .context("terminal Turn not observed")?
}

pub struct Environment {
    pub _temp: tempfile::TempDir,
    pub home: PathBuf,
    pub repo: PathBuf,
    pub root_provider: FixtureServer,
    pub child_provider: FixtureServer,
    pub runtime: StudioRuntime,
    pub project: pl_studio_runtime::WorkspaceRecord,
}

impl Environment {
    pub async fn new(root: Vec<Step>, child: Vec<Step>) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let repo = temp.path().join("repo");
        std::fs::create_dir(&repo)?;
        git(&repo, &["init", "-b", "main"])?;
        git(&repo, &["config", "user.name", "Lifecycle Test"])?;
        git(
            &repo,
            &["config", "user.email", "lifecycle@example.invalid"],
        )?;
        std::fs::write(repo.join("tracked.txt"), "preserve project content\n")?;
        std::fs::write(repo.join(".gitignore"), ".anywork/\nignored.txt\n")?;
        git(&repo, &["add", "."])?;
        git(&repo, &["commit", "-m", "initial"])?;
        let root_provider = FixtureServer::start(root).await?;
        let child_provider = FixtureServer::start(child).await?;
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        for (account, provider) in [
            ("root-fixture", &root_provider),
            ("child-fixture", &child_provider),
        ] {
            let mut model = ModelInfo::compatible(MODEL);
            model
                .binding
                .set_transport(ModelTransportProfile::responses_http());
            model.capabilities.instruction_snapshot_overrides = true;
            model.base_instructions = "Lifecycle fixture model base".into();
            config.models.accounts.insert(
                AccountId::new(account)?,
                AccountConfig::from_explicit_models(
                    ProtocolEndpoint::compatible(account, provider.base_url()),
                    vec![model],
                ),
            );
        }
        let route = ModelRouteConfig {
            account_id: AccountId::new("root-fixture")?,
            model_id: MODEL.into(),
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
        let paths = ConfigPaths::from_config_dir(&home);
        ConfigStore::new(paths.clone()).save(&config)?;
        save_user_agent_profile(
            &paths,
            EXECUTOR,
            &UserAgentProfile {
                enabled: true,
                display_name: EXECUTOR.into(),
                description: "Identity integration".into(),
                when_to_use: "Identity integration".into(),
                system_instructions: "Follow the finite fixture script.".into(),
                account_id: AccountId::new("child-fixture")?,
                model_id: MODEL.into(),
                effort: None,
                workspace_mode: AgentWorkspaceMode::Worktree,
            },
            &config,
        )?;
        let runtime = Box::pin(StudioRuntime::initialize(Self::options(&home))).await?;
        let project = runtime.open_project(&repo).await?;
        Ok(Self {
            _temp: temp,
            home,
            repo,
            root_provider,
            child_provider,
            runtime,
            project,
        })
    }

    fn options(home: &Path) -> StudioRuntimeOptions {
        StudioRuntimeOptions {
            studio_home: Some(home.into()),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        }
    }

    pub async fn start(
        &self,
        mode: ThreadWorkspaceMode,
        prompt: &str,
    ) -> Result<pl_studio_runtime::StudioStartNewThreadResponse> {
        Box::pin(self.runtime.create_thread_command(
            self.project.id.clone(),
            CreateThreadRequest {
                title: Some("Lifecycle integration".into()),
                input: StudioPromptInput {
                    input_id: format!("input-{prompt}"),
                    text: prompt.into(),
                    attachment_draft_ids: Vec::new(),
                },
                mode: pl_protocol::ThreadModeId::simple().to_string(),
                route: NewThreadModelRoute {
                    account_id: "root-fixture".into(),
                    model_id: MODEL.into(),
                    effort: None,
                },
                delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                delegation_preference: None,
                workspace_mode: mode,
            },
            None,
        ))
        .await
    }

    pub async fn restart(&mut self) -> Result<()> {
        self.runtime.shutdown_runtime().await?;
        self.runtime = Box::pin(StudioRuntime::initialize(Self::options(&self.home))).await?;
        Ok(())
    }

    pub async fn finish(self, result: Result<()>) -> Result<()> {
        let shutdown = self.runtime.shutdown_runtime().await;
        let root = self.root_provider.finish().await;
        let child = self.child_provider.finish().await;
        if let Err(error) = result {
            return Err(error.context(format!(
                "cleanup results: runtime={:?}; root={:?}; child={:?}",
                shutdown.as_ref().map(|_| ()),
                root.as_ref().map(|_| ()),
                child.as_ref().map(|_| ()),
            )));
        }
        shutdown.context("runtime resource cleanup failed")?;
        root.context("root provider script failed")?;
        child.context("child provider script failed")?;
        Ok(())
    }
}

pub fn prompt_step(prompt: &str, step: usize, reply: Reply) -> Step {
    Step::prompt(Protocol::ResponsesHttp, prompt, step, reply)
}

pub fn spawn_reply(call: &str, message: &str) -> Reply {
    tool_reply(
        "spawn_agent",
        call,
        serde_json::json!({
            "profileId":EXECUTOR, "taskSummary":"Identity child", "message":message
        }),
    )
}

pub fn receipt(provider: &FixtureServer, call: &str) -> Result<serde_json::Value> {
    Ok(serde_json::from_str(&tool_output(provider, call)?)?)
}

pub fn tool_output(provider: &FixtureServer, call: &str) -> Result<String> {
    for request in provider.recorded().iter().rev() {
        if let Some(input) = request
            .body
            .get("input")
            .and_then(serde_json::Value::as_array)
        {
            for item in input.iter().rev() {
                if item["type"] == "function_call_output" && item["call_id"] == call {
                    return Ok(item["output"]
                        .as_str()
                        .context("tool output text")?
                        .to_owned());
                }
            }
        }
    }
    anyhow::bail!("provider did not observe a real tool receipt for {call}")
}

pub fn child_id(receipt: &serde_json::Value) -> Result<&str> {
    receipt["agentId"].as_str().context("real spawn agentId")
}

pub fn child_path(receipt: &serde_json::Value) -> Result<&Path> {
    Ok(Path::new(
        receipt["workspace"]["root"]
            .as_str()
            .context("spawn workspace root")?,
    ))
}

pub struct Saved {
    pub path: PathBuf,
    pub checkpoint: pl_core::thread::ThreadCheckpoint,
    pub context: Vec<String>,
}

/// Read only test-owned SQLite files; no production visibility is expanded for assertions/faults.
pub async fn saved(home: &Path, id: &str) -> Result<Saved> {
    let mut pending = vec![home.to_path_buf()];
    while let Some(directory) = pending.pop() {
        for entry in std::fs::read_dir(directory)? {
            let entry = entry?;
            if entry.file_type()?.is_dir() {
                pending.push(entry.path());
                continue;
            }
            if entry.file_name() != "history.sqlite" {
                continue;
            }
            let path = entry.path();
            let db = Database::connect(format!("sqlite://{}?mode=ro", path.display())).await?;
            let row = db
                .query_one_raw(Statement::from_string(
                    DbBackend::Sqlite,
                    "SELECT payload FROM session_checkpoint WHERE id=1",
                ))
                .await?;
            if let Some(row) = row {
                let checkpoint: pl_core::thread::ThreadCheckpoint =
                    serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
                if checkpoint.thread_id == id {
                    let context = db
                        .query_all_raw(Statement::from_string(
                            DbBackend::Sqlite,
                            "SELECT payload FROM current_context ORDER BY ordinal",
                        ))
                        .await?
                        .into_iter()
                        .map(|row| row.try_get::<String>("", "payload"))
                        .collect::<std::result::Result<Vec<_>, _>>()?;
                    db.close().await?;
                    return Ok(Saved {
                        path,
                        checkpoint,
                        context,
                    });
                }
            }
            db.close().await?;
        }
    }
    anyhow::bail!("no durable checkpoint for {id}")
}
