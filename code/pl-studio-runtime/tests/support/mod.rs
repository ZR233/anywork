use anyhow::{Context, Result, ensure};
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelDefinition, ModelTransportProfile},
};
use pl_provider_fixture::{FixtureServer, Protocol, RealtimeToolCall, Reply, ReplyStage, Step};
use pl_studio_runtime::{
    AgentWorkspaceMode, CreateThreadRequest, NewThreadModelRoute, ReadDemand, StudioHostKind,
    StudioPromptInput, StudioRuntime, StudioRuntimeOptions, ThreadWorkspaceMode,
    config::{ConfigPaths, ConfigStore, StudioConfig, UserAgentProfile, save_user_agent_profile},
};
use std::{
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

pub const MODEL: &str = "lifecycle-model";
pub const EXECUTOR: &str = "lifecycle_executor";

/// A runner watchdog for real database integration, not a product latency target.
/// One configured deadline covers the operation; notifications never extend it.
pub fn integration_test_deadline() -> Result<Duration> {
    match std::env::var("ANYWORK_TEST_INTEGRATION_TIMEOUT_SECONDS") {
        Ok(value) => {
            let seconds = value
                .parse::<u64>()
                .context("ANYWORK_TEST_INTEGRATION_TIMEOUT_SECONDS must be a positive integer")?;
            ensure!(
                seconds > 0,
                "ANYWORK_TEST_INTEGRATION_TIMEOUT_SECONDS must be greater than zero"
            );
            Ok(Duration::from_secs(seconds))
        }
        Err(std::env::VarError::NotPresent) => Ok(Duration::from_secs(300)),
        Err(error) => Err(error).context("read integration test watchdog configuration"),
    }
}

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

pub fn program_reply(name: &str, call: &str, args: serde_json::Value) -> Reply {
    Reply::Sse(pl_provider_fixture::responses_tool_calls(
        call,
        MODEL,
        &[RealtimeToolCall {
            item_id: call,
            call_id: call,
            name,
            arguments: args.to_string(),
        }
        .program(name)],
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
    tokio::time::timeout(integration_test_deadline()?, stage.wait_reached())
        .await
        .context("provider stage was not reached")
}

pub async fn completed_prompt(
    runtime: &StudioRuntime,
    id: &str,
    prompt: &str,
) -> Result<pl_studio_runtime::Turn> {
    terminal(runtime, id, Some(&format!("input-{prompt}"))).await
}

pub fn current_demand() -> ReadDemand {
    ReadDemand {
        max_items: 64,
        max_bytes: 64 * 1024,
    }
}

pub async fn terminal(
    runtime: &StudioRuntime,
    id: &str,
    input: Option<&str>,
) -> Result<pl_studio_runtime::Turn> {
    use pl_studio_runtime::history::{
        HistoryBusinessRowHead, HistoryDemand, HistoryTurnState, read_event_body_bytes,
    };
    let reader = runtime
        .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
        .await?;
    let demand = HistoryDemand {
        max_rows: 128,
        max_bytes: 256 * 1024,
    };
    let observed = tokio::time::timeout(integration_test_deadline()?, async {
        let mut cut = reader.capture().await?;
        loop {
            let mut cursor = None;
            loop {
                let page = reader
                    .turns_page(Some(cut.clone()), cursor.clone(), demand)
                    .await?;
                for entry in page.entries {
                    let HistoryBusinessRowHead::Turn(head) = entry.head else {
                        continue;
                    };
                    if !input.is_none_or(|input| head.input_id.as_deref() == Some(input))
                        || !matches!(
                            head.state,
                            HistoryTurnState::Completed
                                | HistoryTurnState::Cancelled
                                | HistoryTurnState::Failed
                                | HistoryTurnState::BudgetLimited
                        )
                    {
                        continue;
                    }
                    let event = head.detail_event_id.context("terminal Turn detail event")?;
                    let detail = reader.read_event(event, demand).await?;
                    let bytes = read_event_body_bytes(&reader, &detail, "turn_detail", None)
                        .await?
                        .context("immutable Turn detail body")?;
                    let turn: pl_studio_runtime::Turn = serde_json::from_slice(&bytes)?;
                    ensure!(
                        turn.id == head.turn_id
                            && turn.thread_id == id
                            && turn.state.is_terminal()
                            && input.is_none_or(|input| turn.input_id.as_deref() == Some(input)),
                        "immutable Turn detail identity differs"
                    );
                    return Ok::<_, anyhow::Error>(turn);
                }
                let Some(next) = page.next else { break };
                ensure!(
                    cursor.as_ref() != Some(&next),
                    "Turn cursor did not advance"
                );
                cursor = Some(next);
            }
            cut = reader.wait_changed(cut).await?;
        }
    })
    .await
    .context("terminal History Turn not observed");
    reader.close().await;
    observed?
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
        Self::with_transport(root, child, ModelTransportProfile::responses_http()).await
    }

    pub async fn with_transport(
        root: Vec<Step>,
        child: Vec<Step>,
        transport: ModelTransportProfile,
    ) -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let repo = temp.path().join("repo");
        std::fs::create_dir(&repo)?;
        git(&repo, &["init", "-b", "main"])?;
        // Production Git and the isolated test helper must agree on checkout bytes,
        // regardless of the host's system-wide Windows line-ending configuration.
        git(&repo, &["config", "--local", "core.autocrlf", "false"])?;
        git(&repo, &["config", "--local", "core.eol", "lf"])?;
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
            let mut model = ModelDefinition::compatible(MODEL);
            model.extra.binding.set_transport(transport.clone());
            model.extra.capabilities.instruction_snapshot_overrides = true;
            model.base.model_messages.instructions_template = "Lifecycle fixture model base".into();
            config.models.accounts.insert(
                AccountId::new(account)?,
                AccountConfig::from_explicit_models(
                    pl_model::protocol::providers::openai::compatible_endpoint(
                        account,
                        provider.base_url(),
                    ),
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
                binding: pl_studio_runtime::AgentBinding::Native(
                    pl_studio_runtime::NativeAgentConfig {
                        route: Some(pl_studio_runtime::NewThreadModelRoute {
                            account_id: "child-fixture".into(),
                            model_id: MODEL.into(),
                            effort: None,
                        }),
                        system_instructions: Some("Follow the finite fixture script.".into()),
                    },
                ),
                workspace_mode: AgentWorkspaceMode::Worktree,
            },
            &config,
            &Default::default(),
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
            skill_search: pl_studio_runtime::SkillSearchOptions {
                include_default_user_dir: false,
                additional_dirs: Vec::new(),
            },
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
                mode: pl_studio_runtime::mode::ThreadModeId::simple().to_string(),
                route: NewThreadModelRoute {
                    account_id: "root-fixture".into(),
                    model_id: MODEL.into(),
                    effort: None,
                },
                service_tier: None,
                delegation_mode: Some(pl_studio_runtime::DelegationMode::Profile),
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
        if let Some(text) = pl_provider_fixture::observed_tool_output(&request.body, call) {
            return Ok(text);
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
    pub root: PathBuf,
    pub current: pl_core::thread::current::ThreadCurrent,
}

/// Locate the Thread-owned saved Current without opening a provider or requiring History.
/// The returned History path can legitimately be absent for a Current-only Thread.
pub async fn saved(home: &Path, id: &str) -> Result<Saved> {
    let mut pending = vec![home.to_path_buf()];
    while let Some(directory) = pending.pop() {
        for entry in std::fs::read_dir(&directory)? {
            let entry = entry?;
            if entry.file_type()?.is_dir() {
                pending.push(entry.path());
                continue;
            }
            if entry.file_name() != "current.json" {
                continue;
            }
            let current: pl_core::thread::current::ThreadCurrent =
                serde_json::from_slice(&std::fs::read(entry.path())?)?;
            if current.thread_id != id {
                continue;
            }
            current.validate(id)?;
            let root = directory.clone();
            return Ok(Saved {
                path: root.join("history.sqlite"),
                root,
                current,
            });
        }
    }
    anyhow::bail!("no saved Current for {id}")
}
