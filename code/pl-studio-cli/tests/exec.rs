use anyhow::{Context, Result, ensure};
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, ReplyStage, Step};
use pl_studio_runtime::{ConfigPaths, ConfigStore, StudioConfig};
use std::{path::PathBuf, process::Stdio, time::Duration};
use tokio::io::AsyncWriteExt;

const MODEL: &str = "vendor/cli-fixture";
const PROMPT: &str = "CLI synthetic task";

struct Environment {
    temporary: tempfile::TempDir,
    home: PathBuf,
    task: PathBuf,
}

impl Environment {
    fn new(endpoint: &str) -> Result<Self> {
        let temporary = tempfile::tempdir()?;
        let home = temporary.path().join("profile");
        let task = temporary.path().join("task");
        std::fs::create_dir_all(&task)?;
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        let mut model = ModelInfo::compatible(MODEL);
        model
            .binding
            .set_transport(ModelTransportProfile::responses_http());
        config.models.accounts.insert(
            AccountId::new("fixture")?,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible("fixture", endpoint),
                vec![model],
            ),
        );
        let route = ModelRouteConfig {
            account_id: AccountId::new("fixture")?,
            model_id: MODEL.into(),
            effort: None,
        };
        for value in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *value = route.clone();
        }
        config.runtime.tool_capabilities.mcp = false;
        config.skills.auto_learn = false;
        config.skills.system.enabled = false;
        ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
        std::fs::write(temporary.path().join("prompt.txt"), PROMPT)?;
        Ok(Self {
            temporary,
            home,
            task,
        })
    }

    fn command(&self) -> tokio::process::Command {
        self.command_for("fixture", MODEL)
    }

    fn command_for(&self, account: &str, model: &str) -> tokio::process::Command {
        let mut command = tokio::process::Command::new(env!("CARGO_BIN_EXE_anywk"));
        command.current_dir(self.temporary.path()).args([
            "exec",
            "--studio-home",
            "profile",
            "--cwd",
            "task",
            "--account",
            account,
            "--model",
            model,
            "--prompt-file",
            "prompt.txt",
            "--no-default-user-skills",
        ]);
        command
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        command
    }
}

fn native_tool(name: &str, call: &str, arguments: serde_json::Value) -> Reply {
    Reply::Sse(pl_provider_fixture::responses_tool_calls(
        call,
        MODEL,
        &[pl_provider_fixture::RealtimeToolCall {
            item_id: call,
            call_id: call,
            name,
            arguments: arguments.to_string(),
        }
        .program(name)],
    ))
}

async fn output(command: &mut tokio::process::Command) -> Result<std::process::Output> {
    tokio::time::timeout(Duration::from_secs(90), command.output())
        .await
        .context("CLI watchdog")?
        .context("run anywk")
}

#[tokio::test]
async fn help_version_and_usage_do_not_create_a_runtime() -> Result<()> {
    let directory = tempfile::tempdir()?;
    for argument in ["--help", "--version"] {
        let mut command = tokio::process::Command::new(env!("CARGO_BIN_EXE_anywk"));
        command.current_dir(directory.path()).arg(argument);
        let result = output(&mut command).await?;
        ensure!(result.status.success());
        if argument == "--version" {
            assert_eq!(
                String::from_utf8(result.stdout)?,
                format!("anywk {}\n", pl_studio_update::STUDIO_VERSION.trim())
            );
        }
        assert!(std::fs::read_dir(directory.path())?.next().is_none());
    }
    let mut command = tokio::process::Command::new(env!("CARGO_BIN_EXE_anywk"));
    command.args(["exec", "--max-model-steps", "0"]);
    assert_eq!(output(&mut command).await?.status.code(), Some(2));
    Ok(())
}

#[tokio::test]
async fn production_cli_runs_non_git_task_from_stdin_and_emits_only_final_text() -> Result<()> {
    let answer = "最终输出🙂".repeat(24_000);
    let server = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT,
        0,
        Reply::Sse(pl_provider_fixture::responses_text(
            &answer, "cli-done", MODEL,
        )),
    )])
    .await?;
    let environment = Environment::new(&server.base_url())?;
    let original_config = std::fs::read(environment.home.join("config.toml"))?;
    let mut command = {
        let mut command = tokio::process::Command::new(env!("CARGO_BIN_EXE_anywk"));
        command.current_dir(environment.temporary.path()).args([
            "exec",
            "--studio-home",
            "profile",
            "--cwd",
            "task",
            "--account",
            "fixture",
            "--model",
            MODEL,
            "--prompt-file",
            "-",
            "--no-default-user-skills",
        ]);
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        command
    };
    let mut child = command.spawn()?;
    let mut input = child.stdin.take().context("stdin")?;
    input.write_all(PROMPT.as_bytes()).await?;
    input.shutdown().await?;
    drop(input);
    let result = tokio::time::timeout(Duration::from_secs(90), child.wait_with_output()).await??;
    assert_eq!(
        result.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(String::from_utf8(result.stdout)?, format!("{answer}\n"));
    assert_eq!(
        std::fs::read(environment.home.join("config.toml"))?,
        original_config
    );
    assert!(!environment.task.join(".git").exists());
    assert!(!environment.home.join("startup-backups").exists());
    let requests = server.finish().await?;
    assert_eq!(
        requests.len(),
        1,
        "a fixed title must not invoke another model"
    );
    Ok(())
}

#[tokio::test]
async fn production_cli_preserves_blocked_budget_and_model_failure_exits() -> Result<()> {
    let question = pl_provider_fixture::RealtimeToolCall { item_id: "ask", call_id: "ask", name: "request_user_input", arguments: serde_json::json!({"questions":[{"id":"choice","header":"Choice","question":"Choose?","isOther":true}]}).to_string() };
    let tool = pl_provider_fixture::RealtimeToolCall {
        item_id: "list",
        call_id: "list",
        name: "skills_list",
        arguments: "{}".into(),
    }
    .program("skills_list");
    for (reply, expected, steps) in [
        (
            Reply::Sse(pl_provider_fixture::responses_tool_calls(
                "blocked",
                MODEL,
                &[question],
            )),
            3,
            None,
        ),
        (
            Reply::Sse(pl_provider_fixture::responses_tool_calls(
                "budget",
                MODEL,
                &[tool],
            )),
            4,
            Some("1"),
        ),
        (
            Reply::HttpError {
                status: 400,
                code: "invalid_request_error".into(),
                message: "synthetic provider failure".into(),
            },
            10,
            None,
        ),
    ] {
        let server = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            0,
            reply,
        )])
        .await?;
        let environment = Environment::new(&server.base_url())?;
        let mut command = environment.command();
        if let Some(steps) = steps {
            command.args(["--max-model-steps", steps]);
        }
        let result = output(&mut command).await?;
        assert_eq!(
            result.status.code(),
            Some(expected),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(result.stdout.is_empty());
        server.finish().await?;
    }
    Ok(())
}

#[tokio::test]
async fn strict_cli_rejects_bad_inputs_without_replacing_configuration() -> Result<()> {
    let server = FixtureServer::start(Vec::new()).await?;
    let environment = Environment::new(&server.base_url())?;
    for bytes in [b"not valid TOML [".as_slice(), b"schema_version = 999999\n"] {
        std::fs::write(environment.home.join("config.toml"), bytes)?;
        let result = output(&mut environment.command()).await?;
        assert_eq!(
            result.status.code(),
            Some(2),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(result.stdout.is_empty());
        assert_eq!(std::fs::read(environment.home.join("config.toml"))?, bytes);
        assert!(!environment.home.join("startup-backups").exists());
    }
    std::fs::remove_file(environment.home.join("config.toml"))?;
    assert_eq!(
        output(&mut environment.command()).await?.status.code(),
        Some(2)
    );
    assert!(!environment.home.join("config.toml").exists());
    assert!(server.recorded().is_empty());
    server.finish().await?;
    Ok(())
}

#[tokio::test]
async fn invalid_native_routes_and_prompt_inputs_fail_before_inference() -> Result<()> {
    let server = FixtureServer::start(Vec::new()).await?;
    let environment = Environment::new(&server.base_url())?;
    for mut command in [
        environment.command_for("missing-account", MODEL),
        environment.command_for("fixture", "missing/model"),
    ] {
        let result = output(&mut command).await?;
        assert_eq!(
            result.status.code(),
            Some(2),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
    }
    for arguments in [
        ["--mode", "mode.missing"],
        ["--reasoning-effort", "not-supported"],
        ["--skill-dir", "missing-skills"],
    ] {
        let result = output(environment.command().args(arguments)).await?;
        assert_eq!(
            result.status.code(),
            Some(2),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
    }
    for bytes in [b" \n\t".as_slice(), b"\xff\xfe"] {
        std::fs::write(environment.temporary.path().join("prompt.txt"), bytes)?;
        assert_eq!(
            output(&mut environment.command()).await?.status.code(),
            Some(2)
        );
    }
    assert!(server.recorded().is_empty());
    server.finish().await?;
    Ok(())
}

#[tokio::test]
async fn environment_credentials_follow_native_protocol_requirements_without_keyring() -> Result<()>
{
    let server = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        PROMPT,
        0,
        Reply::Sse(pl_provider_fixture::responses_text(
            "environment credential accepted",
            "credential-done",
            MODEL,
        )),
    )])
    .await?;
    let environment = Environment::new(&server.base_url())?;
    let store = ConfigStore::new(ConfigPaths::from_config_dir(&environment.home));
    let mut config = store.load()?;
    let mut model = ModelInfo::compatible(MODEL);
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let mut account = AccountConfig::from_explicit_models(
        ProtocolEndpoint::deepseek(Some(server.base_url())),
        vec![model],
    );
    account.bearer_token_env = Some("ANYWK_REQUIRED_TEST_TOKEN".into());
    config
        .models
        .accounts
        .insert(AccountId::new("fixture")?, account);
    store.save(&config)?;
    let before = std::fs::read(environment.home.join("config.toml"))?;
    let result = output(
        environment
            .command()
            .env_remove("ANYWK_REQUIRED_TEST_TOKEN"),
    )
    .await?;
    assert_eq!(
        result.status.code(),
        Some(2),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert!(server.recorded().is_empty());
    let result = output(
        environment
            .command()
            .env("ANYWK_REQUIRED_TEST_TOKEN", "synthetic-secret-value"),
    )
    .await?;
    assert_eq!(
        result.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(
        String::from_utf8(result.stdout)?,
        "environment credential accepted\n"
    );
    assert!(!String::from_utf8(result.stderr)?.contains("synthetic-secret-value"));
    assert_eq!(std::fs::read(environment.home.join("config.toml"))?, before);
    server.finish().await?;
    Ok(())
}

#[tokio::test]
async fn root_and_child_share_the_explicit_readonly_skill_policy() -> Result<()> {
    const CHILD_INPUT: &str = "child-policy-input";
    const SKILL: &str = "cli-policy-skill";
    const MARKER: &str = "CLI_EXPLICIT_SKILL_BODY";
    let child_stage = ReplyStage::new();
    let root_stage = ReplyStage::new();
    let child = FixtureServer::start(vec![
        Step::prompt(Protocol::ResponsesHttp, CHILD_INPUT, 0, native_tool("skill_view", "child-view", serde_json::json!({"name":SKILL}))),
        Step::tool_output(Protocol::ResponsesHttp, "child-view", MARKER, 1, child_stage.gated(vec![serde_json::json!({"type":"response.created","response":{"id":"child-done","model":MODEL}})], pl_provider_fixture::responses_text("child finished", "child-done", MODEL).into_iter().skip(1).collect())),
    ]).await?;
    let root = FixtureServer::start(vec![
        Step::prompt(Protocol::ResponsesHttp, PROMPT, 0, native_tool("skill_view", "root-view", serde_json::json!({"name":SKILL}))),
        Step::tool_output(Protocol::ResponsesHttp, "root-view", MARKER, 1, Reply::Sse(pl_provider_fixture::responses_tool_calls("spawn", MODEL, &[pl_provider_fixture::RealtimeToolCall { item_id: "spawn", call_id: "spawn", name: "spawn_agent", arguments: serde_json::json!({"profileId":"cli_child","taskSummary":"check child skills","message":CHILD_INPUT}).to_string() }]))),
        Step::tool_output(Protocol::ResponsesHttp, "spawn", "agentId", 2, root_stage.gated(vec![serde_json::json!({"type":"response.created","response":{"id":"root-done","model":MODEL}})], pl_provider_fixture::responses_text("root finished", "root-done", MODEL).into_iter().skip(1).collect())),
    ]).await?;
    let environment = Environment::new(&root.base_url())?;
    let paths = ConfigPaths::from_config_dir(&environment.home);
    let store = ConfigStore::new(paths.clone());
    let mut config = store.load()?;
    let mut account = config.models.accounts[&AccountId::new("fixture")?].clone();
    account.base_url = child.base_url();
    account.bearer_token_env = Some("ANYWK_TEST_ENV_TOKEN".into());
    config
        .models
        .accounts
        .insert(AccountId::new("child")?, account);
    store.save(&config)?;
    pl_studio_runtime::config::save_user_agent_profile(
        &paths,
        "cli_child",
        &pl_studio_runtime::UserAgentProfile {
            enabled: true,
            display_name: "CLI Child".into(),
            description: "CLI child test".into(),
            when_to_use: "CLI child test".into(),
            binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                route: Some(pl_studio_runtime::NewThreadModelRoute {
                    account_id: "child".into(),
                    model_id: MODEL.into(),
                    effort: None,
                }),
                system_instructions: Some("Use the configured skill".into()),
            }),
            workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
        },
        &config,
        &Default::default(),
    )?;
    let collection = environment.temporary.path().join("evaluation-skills");
    let skill = collection.join(SKILL);
    std::fs::create_dir_all(&skill)?;
    std::fs::write(
        skill.join("SKILL.md"),
        format!("---\nname: {SKILL}\ndescription: CLI policy test\n---\n{MARKER}\n"),
    )?;
    let mut command = environment.command();
    command
        .args(["--skill-dir", "evaluation-skills"])
        .env("ANYWK_TEST_ENV_TOKEN", "synthetic-environment-token");
    let process = command.spawn()?;
    tokio::time::timeout(Duration::from_secs(60), async {
        tokio::join!(child_stage.wait_reached(), root_stage.wait_reached());
    })
    .await?;
    child_stage.release();
    root_stage.release();
    let result =
        tokio::time::timeout(Duration::from_secs(60), process.wait_with_output()).await??;
    assert_eq!(
        result.status.code(),
        Some(0),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(String::from_utf8(result.stdout)?, "root finished\n");
    for (provider, call) in [(&root, "root-view"), (&child, "child-view")] {
        assert!(provider.recorded().iter().any(|request| {
            pl_provider_fixture::observed_tool_output(&request.body, call)
                .is_some_and(|text| text.contains(MARKER))
        }));
        assert!(
            provider
                .recorded()
                .first()
                .unwrap()
                .body
                .to_string()
                .contains(SKILL)
        );
    }
    assert!(
        !skill.join(".usage.json").exists(),
        "External reads cannot update usage in the collection"
    );
    root.finish().await?;
    child.finish().await?;
    Ok(())
}

#[cfg(unix)]
#[tokio::test]
async fn native_signals_cancel_the_same_runtime_and_release_its_lock() -> Result<()> {
    for (signal, expected) in [(libc::SIGINT, 130), (libc::SIGTERM, 143)] {
        let stage = ReplyStage::new();
        let server = FixtureServer::start(vec![Step::prompt(Protocol::ResponsesHttp, PROMPT, 0, stage.gated(vec![serde_json::json!({"type":"response.created","response":{"id":"signal","model":MODEL}})], Vec::new()))]).await?;
        let environment = Environment::new(&server.base_url())?;
        let child = environment.command().spawn()?;
        tokio::time::timeout(Duration::from_secs(60), stage.wait_reached()).await?;
        // SAFETY: kill takes only integer values, with no borrowed memory. This positive PID
        // belongs to the live child retained here; the signal is one of the two native constants.
        assert_eq!(
            unsafe { libc::kill(child.id().context("child pid")? as i32, signal) },
            0
        );
        let result =
            tokio::time::timeout(Duration::from_secs(45), child.wait_with_output()).await??;
        assert_eq!(
            result.status.code(),
            Some(expected),
            "{}",
            String::from_utf8_lossy(&result.stderr)
        );
        assert!(result.stdout.is_empty());
        let runtime = pl_studio_runtime::StudioRuntime::initialize(
            pl_studio_runtime::StudioRuntimeOptions::cli(&environment.home),
        )
        .await?;
        runtime.shutdown_runtime().await?;
        server.finish().await?;
    }
    Ok(())
}
