//! Live collection only. A human/agent reads the evidence; no marker or automated acceptance verdict.
use anyhow::{Context, Result};
use pl_studio_runtime::{
    ConfigStore, STUDIO_CONFIG_SCHEMA_VERSION, StudioHostKind, StudioRuntime, StudioRuntimeOptions,
};
use std::{
    collections::BTreeSet,
    io::Write,
    path::{Path, PathBuf},
    time::Duration,
};

#[tokio::main]
async fn main() -> Result<()> {
    let selected_route = ObservationRoute::from_env()?;
    let installed = ConfigStore::default_app()?;
    let config_content = std::fs::read_to_string(installed.paths().config_file())?;
    #[derive(serde::Deserialize)]
    struct ConfigVersion {
        schema_version: u32,
    }
    let version: ConfigVersion = toml::from_str(&config_content)?;
    // Earlier migrations may import inline credentials or copy the legacy provider namespace.
    anyhow::ensure!(
        (23..=STUDIO_CONFIG_SCHEMA_VERSION).contains(&version.schema_version),
        "observation requires config schema 23..={STUDIO_CONFIG_SCHEMA_VERSION} without credential migration; found {}",
        version.schema_version
    );
    let artifacts = match std::env::var_os("ANYWORK_WORKFLOW_ARTIFACT_DIR") {
        Some(path) => PathBuf::from(path),
        None => tempfile::Builder::new()
            .prefix("anywork-collaboration-")
            .tempdir()?
            .keep(),
    };
    std::fs::create_dir_all(&artifacts)?;
    let home = artifacts.join("studio-home");
    // Never resume an older observation's pending credential migration.
    std::fs::create_dir(&home).context("observation requires a new isolated Studio home")?;
    let ssh_alias = match std::env::var("ANYWORK_OBSERVATION_SSH_ALIAS") {
        Ok(alias) => Some(alias),
        Err(std::env::VarError::NotPresent) => None,
        Err(error) => return Err(error.into()),
    };
    let workspace = match (
        &ssh_alias,
        std::env::var_os("ANYWORK_OBSERVATION_SSH_WORKSPACE"),
    ) {
        (None, None) => tempfile::Builder::new()
            .prefix("anywork-observation-workspace-")
            .tempdir()?
            .keep(),
        (Some(alias), Some(path)) => {
            anyhow::ensure!(
                !alias.trim().is_empty() && !path.is_empty() && path.to_str().is_some(),
                "observation SSH alias and workspace must both be nonempty"
            );
            PathBuf::from(path)
        }
        _ => anyhow::bail!(
            "ANYWORK_OBSERVATION_SSH_ALIAS and ANYWORK_OBSERVATION_SSH_WORKSPACE must be set together"
        ),
    };
    std::fs::write(
        artifacts.join("workspace-path.txt"),
        workspace.to_string_lossy().as_bytes(),
    )?;
    let workspace_mode = match std::env::var("ANYWORK_OBSERVATION_WORKSPACE_MODE").as_deref() {
        Ok("worktree") => pl_protocol::ThreadWorkspaceMode::Worktree,
        Ok("local") | Err(std::env::VarError::NotPresent) => {
            pl_protocol::ThreadWorkspaceMode::Local
        }
        other => anyhow::bail!("invalid observation workspace mode: {other:?}"),
    };
    if workspace_mode == pl_protocol::ThreadWorkspaceMode::Worktree {
        anyhow::ensure!(
            ssh_alias.is_none(),
            "SSH observation requires an existing isolated workspace in local mode"
        );
        initialize_repository(&workspace)?;
    }
    // Copy the validated bytes, never save a hydrated config: credentials belong to the user.
    std::fs::write(home.join("config.toml"), &config_content)?;
    if let Some(ObservationRoute {
        account_id,
        model_id,
    }) = &selected_route
    {
        let mut config: toml::Value = toml::from_str(&config_content)?;
        let accounts = config
            .get_mut("models")
            .and_then(|v| v.get_mut("accounts"))
            .and_then(toml::Value::as_table_mut)
            .context("account table is missing")?;
        let selected = accounts
            .get(account_id)
            .context("observation account is not configured")?
            .clone();
        let account: pl_model::config::AccountConfig = selected.clone().try_into()?;
        let model = account
            .effective_models(None)?
            .into_iter()
            .find(|m| m.model_id == *model_id)
            .context("observation model is not configured")?;
        let effort = model
            .parameters
            .iter()
            .find(|p| p.name == "effort")
            .and_then(|p| p.candidates.first());
        accounts.clear();
        accounts.insert(account_id.clone(), selected);
        let routes = config
            .get_mut("models")
            .and_then(|v| v.get_mut("routes"))
            .and_then(toml::Value::as_table_mut)
            .context("route table is missing")?;
        for (_, route) in routes.iter_mut() {
            let route = route.as_table_mut().context("invalid route")?;
            route.insert("account_id".into(), account_id.clone().into());
            route.insert("model_id".into(), model_id.clone().into());
            if let Some(effort) = effort {
                route.insert("effort".into(), effort.clone().into());
            } else {
                route.remove("effort");
            }
        }
        let modes = config
            .get_mut("mode_model_routes")
            .and_then(toml::Value::as_table_mut)
            .context("mode route table is missing")?;
        for (_, route) in modes.iter_mut() {
            let route = route.as_table_mut().context("invalid mode route")?;
            route.insert("account_id".into(), account_id.clone().into());
            route.insert("model_id".into(), model_id.clone().into());
            if let Some(effort) = effort {
                route.insert("effort".into(), effort.clone().into());
            } else {
                route.remove("effort");
            }
        }
        std::fs::write(home.join("config.toml"), toml::to_string(&config)?)?;
    }
    // The isolated copy uses the production startup migration, rather than strict current-schema
    // loading. Collection rejects any reset-to-defaults recovery before submitting a model task.
    let prompt = match std::env::var_os("ANYWORK_OBSERVATION_PROMPT") {
        Some(path) => std::fs::read_to_string(path)?,
        None => "请派两个 fresh-context explorer 分别解释文件所有权和 Turn 生命周期。详细、自包含地派发。一个自然 final，另一个 finish_turn。等待完整报告，阅读后总结；不修改文件，不提交计划，不询问用户。".into(),
    };
    let seconds = std::env::var("ANYWORK_OBSERVATION_SECONDS")
        .ok()
        .map(|v| v.parse::<u64>())
        .transpose()?
        .unwrap_or(180);
    let mut options = StudioRuntimeOptions {
        studio_home: Some(home),
        host: StudioHostKind::Desktop,
        ..StudioRuntimeOptions::desktop()
    };
    if let Some(bundle) = std::env::var_os("ANYWORK_OBSERVATION_HELPER_BUNDLE") {
        options = options.with_remote_helper_source(
            pl_studio_runtime::RemoteHelperSource::Bundled(PathBuf::from(bundle)),
        );
    }
    let runtime = StudioRuntime::initialize(options).await?;
    let mut observers = Vec::new();
    let result = collect(
        &runtime,
        &mut observers,
        Observation {
            workspace: &workspace,
            artifacts: &artifacts,
            prompt,
            workspace_mode,
            seconds,
            selected_route,
            ssh_alias: ssh_alias.as_deref(),
        },
    )
    .await;
    // Even failed collection must close the runtime and drain every evidence writer.
    let shutdown = runtime.shutdown_runtime().await;
    let observations = futures::future::join_all(observers).await;
    result?;
    shutdown?;
    for observation in observations {
        observation??;
    }
    std::fs::write(
        artifacts.join("observation.txt"),
        "Collection ended. Read the complete event streams, snapshots and wire evidence; no automated acceptance verdict was computed.\n",
    )?;
    Ok(())
}

struct Observation<'a> {
    workspace: &'a Path,
    artifacts: &'a Path,
    prompt: String,
    workspace_mode: pl_protocol::ThreadWorkspaceMode,
    seconds: u64,
    selected_route: Option<ObservationRoute>,
    ssh_alias: Option<&'a str>,
}

struct ObservationRoute {
    account_id: String,
    model_id: String,
}

impl ObservationRoute {
    fn from_env() -> Result<Option<Self>> {
        use std::env::VarError;
        match (
            std::env::var("ANYWORK_OBSERVATION_ACCOUNT"),
            std::env::var("ANYWORK_OBSERVATION_MODEL"),
        ) {
            (Err(VarError::NotPresent), Err(VarError::NotPresent)) => Ok(None),
            (Ok(account_id), Ok(model_id)) => {
                anyhow::ensure!(
                    !account_id.trim().is_empty() && !model_id.trim().is_empty(),
                    "observation account and model must both be nonempty"
                );
                Ok(Some(Self {
                    account_id,
                    model_id,
                }))
            }
            (Err(VarError::NotUnicode(_)), _) | (_, Err(VarError::NotUnicode(_))) => {
                anyhow::bail!("observation account and model must both be valid Unicode")
            }
            _ => anyhow::bail!(
                "ANYWORK_OBSERVATION_ACCOUNT and ANYWORK_OBSERVATION_MODEL must be set together"
            ),
        }
    }
}

async fn collect(
    runtime: &StudioRuntime,
    observers: &mut Vec<tokio::task::JoinHandle<Result<()>>>,
    observation: Observation<'_>,
) -> Result<()> {
    let Observation {
        workspace,
        artifacts,
        prompt,
        workspace_mode,
        seconds,
        selected_route,
        ssh_alias,
    } = observation;
    anyhow::ensure!(
        runtime.runtime_snapshot().await?.startup_recovery.is_none(),
        "isolated Studio startup reset configuration; refusing to observe a default account"
    );
    let project = match ssh_alias {
        Some(alias) => {
            runtime
                .open_remote_project(alias, workspace.to_string_lossy().into_owned())
                .await?
        }
        None => runtime.open_project(workspace).await?,
    };
    std::fs::write(
        artifacts.join("project.json"),
        serde_json::to_vec_pretty(&project)?,
    )?;
    let route = runtime
        .read_settings()?
        .config
        .settings
        .mode_model_routes
        .into_iter()
        .find(|route| route.mode_id == "mode.simple")
        .context("simple mode route is unavailable")?;
    if let Some(ObservationRoute {
        account_id,
        model_id,
    }) = selected_route
    {
        anyhow::ensure!(
            route.account_id == account_id && route.model_id == model_id,
            "isolated Studio route differs from the requested observation account/model"
        );
    }
    let created = runtime
        .create_thread_command(
            project.id,
            pl_protocol::studio::CreateThreadRequest {
                title: Some("真实协作过程观察".into()),
                input: pl_protocol::studio::StudioPromptInput {
                    input_id: format!("observation-{}", std::process::id()),
                    text: prompt,
                    attachment_draft_ids: vec![],
                },
                mode: "mode.simple".into(),
                route: pl_protocol::studio::NewThreadModelRoute {
                    account_id: route.account_id,
                    model_id: route.model_id,
                    // 设置快照把 effort 投影为非空字符串；空值表示不指定。
                    effort: Some(route.effort).filter(|value| !value.trim().is_empty()),
                },
                workspace_mode,
                delegation_mode: None,
                delegation_preference: None,
            },
            None,
        )
        .await?;
    let thread = created.thread;
    std::fs::write(
        artifacts.join("root-thread.json"),
        serde_json::to_vec_pretty(&thread)?,
    )?;
    let mut observed = BTreeSet::new();
    observers.push(observe(runtime, &thread.id, artifacts).await?);
    observed.insert(thread.id.clone());
    println!(
        "Observing real API execution for {seconds}s. Artifacts: {}. No automatic pass/fail verdict.",
        artifacts.display()
    );
    let deadline = tokio::time::Instant::now() + Duration::from_secs(seconds);
    while tokio::time::Instant::now() < deadline {
        // The product directory exists before a new Thread's first history write.
        // Do not read a cold timeline while its SQLite schema is still initializing.
        let state = runtime.read_state().await?;
        if let Some(directory) = state.agent_directory.state.value() {
            for agent in directory
                .agents
                .iter()
                .filter(|agent| agent.root_thread_id == thread.id)
            {
                if observed.insert(agent.thread_id.clone()) {
                    match observe(runtime, &agent.thread_id, artifacts).await {
                        Ok(handle) => observers.push(handle),
                        // Directory membership precedes publication, so a just-reserved child
                        // is not subscribable yet; skip this cycle and retry on the next poll.
                        Err(error) => {
                            println!("observation defers {}: {error}", agent.thread_id);
                            observed.remove(&agent.thread_id);
                        }
                    }
                }
            }
        }
        tokio::time::sleep(Duration::from_millis(500)).await;
    }
    for id in &observed {
        let mut cursor = None;
        let mut turns = Vec::new();
        loop {
            let page = runtime
                .list_thread_turns(id, cursor.as_deref(), 200)
                .await?;
            turns.extend(page.turns);
            cursor = page.next_cursor;
            if cursor.is_none() {
                break;
            }
        }
        std::fs::write(
            artifacts.join(format!("{id}.turns.json")),
            serde_json::to_vec_pretty(&turns)?,
        )?;
        let snapshot = runtime.thread_snapshot(id).await?;
        std::fs::write(
            artifacts.join(format!("{id}.snapshot.json")),
            serde_json::to_vec_pretty(&snapshot)?,
        )?;
        // 只需一次有界观察：一页最新内容（服务端合法上限 100 条），产物本身带 `hasOlder` 与下一条
        // 边界，需要更长历史时由调用方按该不透明边界继续取，而不是在例子里把整段会话物化一遍。
        let page = runtime
            .timeline_page(
                id,
                &pl_protocol::TimelinePageQuery {
                    before: None,
                    limit: Some(100),
                },
            )
            .await?;
        std::fs::write(
            artifacts.join(format!("{id}.timeline.json")),
            serde_json::to_vec_pretty(&page)?,
        )?;
    }
    Ok(())
}

fn initialize_repository(workspace: &Path) -> Result<()> {
    for args in [
        vec!["init"],
        vec!["config", "user.name", "anywork observation"],
        vec!["config", "user.email", "observation@anywork.invalid"],
    ] {
        run_git(workspace, &args)?;
    }
    std::fs::write(
        workspace.join("README.md"),
        "Isolated live collaboration workspace.\n",
    )?;
    run_git(workspace, &["add", "README.md"])?;
    run_git(
        workspace,
        &["commit", "-m", "chore: initialize observation workspace"],
    )
}

fn run_git(workspace: &Path, args: &[&str]) -> Result<()> {
    let output = std::process::Command::new("git")
        .arg("-c")
        .arg("core.hooksPath=")
        .args(args)
        .current_dir(workspace)
        .output()?;
    anyhow::ensure!(
        output.status.success(),
        "observation git {args:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(())
}

async fn observe(
    runtime: &StudioRuntime,
    id: &str,
    artifacts: &Path,
) -> Result<tokio::task::JoinHandle<Result<()>>> {
    let mut stream = runtime
        .subscribe_thread(pl_protocol::ThreadSubscriptionRequest {
            thread_id: id.into(),
        })
        .await?;
    let mut file = std::fs::File::create(artifacts.join(format!("{id}.events.jsonl")))?;
    Ok(tokio::spawn(async move {
        while let Some(event) = stream.recv().await? {
            serde_json::to_writer(&mut file, &event)?;
            file.write_all(b"\n")?;
            file.flush()?;
        }
        Ok(())
    }))
}
