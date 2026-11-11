//! Explicit live evidence for tool failure recovery, with an isolated in-memory account and Thread.
use anyhow::{Context, Result};
use pl_core::{
    context::ContextContent,
    model::{DynModelSession, Model, ModelError, ModelRequest, ModelSession, PreparedModelCall},
    thread::{ModelStepLimit, ThreadHandle, TurnInput},
    tool::opaque::Registration,
};
use pl_model::{
    config::AccountConfig,
    runtime::{ModelRuntime, ThreadModel},
};
use pl_tool::{
    binding::{ToolCallPolicy, prepare_registration},
    lsp::{LspPathBinding, LspToolKind, ThreadLspTool},
    workspace::{AgentWorkspace, ToolWorkspace},
};
use std::{path::Path, sync::Arc, time::Duration};
use tokio::sync::Notify;

struct PreparingGate {
    inner: DynModelSession,
    gate: Option<(Arc<Notify>, Arc<Notify>)>,
}

impl ModelSession for PreparingGate {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let prepared = self.inner.prepare(request).await?;
        if let Some((entered, release)) = self.gate.take() {
            entered.notify_one();
            release.notified().await;
        }
        Ok(prepared)
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        self.inner.close().await
    }
}

fn tools(
    registry: &pl_lsp::runtime::LspRuntimeRegistry,
    root: &Path,
    include_query: bool,
) -> Result<Vec<Registration>> {
    let workspace = ToolWorkspace::new(AgentWorkspace::local(root));
    [LspToolKind::Status, LspToolKind::Query]
        .into_iter()
        .filter(|kind| include_query || matches!(kind, LspToolKind::Status))
        .map(|kind| {
            let definition = kind.declaration();
            let prepared = prepare_registration(
                definition.name(),
                &definition,
                ToolCallPolicy::DirectAndProgrammatic,
            )?;
            // Direct exposure is deliberate fault assembly: production normally hides queries
            // until a server is ready. This invokes the real unavailable-server error path.
            Ok(prepared
                .attach(pl_agent_tool::ToolHandle::new(ThreadLspTool::new(
                    registry.clone(),
                    LspPathBinding::Local(workspace.clone()),
                    kind,
                    definition,
                )))
                .foreground_coexisting())
        })
        .collect()
}

#[tokio::main]
async fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let account_id = args
        .next()
        .context("usage: tool_error_observe ACCOUNT MODEL NEW_ARTIFACT_DIR")?;
    let model_id = args.next().context("missing model")?;
    let artifacts = std::path::absolute(args.next().context("missing artifact directory")?)?;
    tokio::fs::create_dir(&artifacts)
        .await
        .context("use a new artifact directory")?;
    let installed = pl_studio_runtime::ConfigStore::default_app()?;
    let config: toml::Value =
        toml::from_str(&tokio::fs::read_to_string(installed.paths().config_file()).await?)?;
    let mut account: AccountConfig = config
        .get("models")
        .and_then(|v| v.get("accounts"))
        .and_then(|v| v.get(&account_id))
        .context("selected account is not configured")?
        .clone()
        .try_into()?;
    let credential_id = account_id.clone();
    let stored = tokio::task::spawn_blocking(move || {
        match keyring::Entry::new("anywork", &format!("account:{credential_id}"))?.get_password() {
            Ok(secret) => Ok(Some(secret)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(error) => Err(error),
        }
    })
    .await??;
    account.bearer_token = stored.or(account.bearer_token);
    let mut model = account
        .effective_models(None)?
        .into_iter()
        .find(|m| m.model_id == model_id)
        .context("model is not in selected account catalog")?;
    model.max_output_tokens = Some(2048);
    // Credentials are read only and leased in memory; no installed config/history is opened for writes.
    let runtime = ModelRuntime::new_with_account_id(
        "isolated-tool-error-observe",
        account.to_endpoint()?,
        model,
    )?
    .with_pricing_mode(account.billing_kind()?.into());
    for remove_query in [false, true] {
        let scenario = if remove_query {
            "catalog-removal"
        } else {
            "unavailable-lsp"
        };
        let root = artifacts.join(scenario);
        tokio::fs::create_dir(&root).await?;
        tokio::fs::write(root.join("source.rs"), "fn main() {}\n").await?;
        let registry = pl_lsp::runtime::LspRuntimeRegistry::new();
        let entered = Arc::new(Notify::new());
        let release = Arc::new(Notify::new());
        let inner = ThreadModel::new(runtime.clone(), None)
            .open_session()
            .await?;
        let thread = ThreadHandle::start(
            scenario.into(),
            DynModelSession::new(PreparingGate {
                inner,
                gate: remove_query.then(|| (entered.clone(), release.clone())),
            }),
        )?;
        thread
            .register_tools(tools(&registry, &root, true)?)
            .await?;
        let input = TurnInput {
            turn_id: scenario.into(),
            attempt_prefix: format!("{scenario}-attempt"),
            content: vec![ContextContent::Text {
                text: Arc::from(
                    "This is a tool-error recovery observation. First call lsp_query exactly once to hover source.rs, languageId rust, line 1, character 1. A failure is expected. After receiving its result call lsp_status to inspect current availability, then report both actual outcomes briefly. Do not stop after the first tool error and do not repeat the failed query.",
                ),
            }],
            max_model_steps: ModelStepLimit::Limited(8.try_into()?),
            cancellation: Default::default(),
        };
        let cancel = input.cancellation.clone();
        let runner = {
            let thread = thread.clone();
            tokio::spawn(async move { thread.run_turn(input).await })
        };
        let observed: Result<()> = async {
            if remove_query {
                tokio::time::timeout(Duration::from_secs(60), entered.notified()).await?;
                thread
                    .register_tools(tools(&registry, &root, false)?)
                    .await?;
                release.notify_one();
            }
            Ok(())
        }
        .await;
        if observed.is_err() {
            cancel.cancel();
            release.notify_one();
        }
        // A timed observation cancels then joins the same owner; no provider task is abandoned.
        let mut runner = runner;
        let (joined, timed_out) = tokio::select! {
            result = &mut runner => (Some(result), false),
            _ = tokio::time::sleep(Duration::from_secs(180)) => { cancel.cancel(); (None, true) },
        };
        let joined = match joined {
            Some(result) => result,
            None => runner.await,
        };
        let run_result = joined
            .map_err(anyhow::Error::from)
            .and_then(|result| result.map_err(anyhow::Error::from));
        let evidence: Result<()> = async {
            let effects = thread.effects().await?;
            let report = serde_json::json!({
            "sourceAccount": account_id, "isolatedAccount": "isolated-tool-error-observe", "model": model_id,
            "platform": std::env::consts::OS, "scenario": scenario, "timedOut": timed_out, "review": "pending",
            "error": run_result.as_ref().err().map(ToString::to_string),
            "completion": run_result.as_ref().ok().map(|completed| serde_json::json!({
                "modelSteps": completed.model_steps, "outcome": format!("{:?}", completed.outcome),
            })),
            "turns": thread.snapshot().turns,
            "deliveries": effects.iter().flat_map(|e| e.deliveries.iter()).collect::<Vec<_>>(),
            "attempts": effects.iter().filter_map(|e| e.attempt.as_ref()).collect::<Vec<_>>(),
            });
            tokio::fs::write(root.join("report.json"), serde_json::to_vec_pretty(&report)?).await?;
            Ok(())
        }.await;
        let closed = thread.close().await;
        let shutdown = registry.shutdown().await;
        observed?;
        closed?;
        shutdown?;
        evidence?;
        run_result?;
        anyhow::ensure!(
            !timed_out,
            "live observation timed out; partial evidence retained"
        );
        println!("Collected {scenario} at {}", root.display());
    }
    Ok(())
}
