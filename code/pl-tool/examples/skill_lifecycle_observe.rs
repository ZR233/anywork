//! Explicit public Thread admission and discovery lifecycle observation (not an automated test).
//! cargo run -p pl-tool --example skill_lifecycle_observe -- SCRATCH [authorization|root|static-root|cancellation]
use std::{
    fs,
    path::Path,
    pin::Pin,
    sync::{Arc, Mutex},
};

use anyhow::{Context, ensure};
use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput, ModelToolCall,
        PreparedModelCall,
    },
    thread::{ModelStepLimit, ThreadError, ThreadHandle, ToolOutcome, TurnInput, TurnOutcome},
    tool::opaque::{CallContext, Registration, Tool},
};
use pl_tool::skill::{
    FileSystemSkillProvider, FrozenSkillCatalog, SkillCandidate, SkillCatalog, SkillDefinition,
    SkillDirectorySource, SkillProvider, SkillProviderId, SkillProviderObservation,
    SkillProviderRequest, SkillRegistry, SkillSourceKind, SkillsConfig, ThreadSkillKind,
    ThreadSkillTool,
};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let scratch = std::env::args_os()
        .nth(1)
        .context("pass an owned scratch directory")?;
    let mode = std::env::args().nth(2).unwrap_or_else(|| "all".into());
    if mode == "static-root-child" {
        return observe_static_root(Path::new(&scratch));
    }
    let temp = tempfile::Builder::new()
        .prefix("skill-lifecycle-")
        .tempdir_in(fs::canonicalize(scratch)?)?;
    match mode.as_str() {
        "authorization" => observe_authorization(temp.path()).await?,
        "root" => observe_root_type(temp.path()).await?,
        "static-root" => observe_static_root_isolated(temp.path()).await?,
        "cancellation" => observe_cancellation(temp.path()).await?,
        "all" => {
            observe_authorization(&temp.path().join("authorization")).await?;
            observe_root_type(&temp.path().join("root")).await?;
            #[cfg(unix)]
            observe_static_root_isolated(&temp.path().join("static-root")).await?;
            observe_cancellation(&temp.path().join("cancellation")).await?;
        }
        _ => anyhow::bail!("unknown observation: {mode}"),
    }
    println!("SKILL_LIFECYCLE_OBSERVATION=PASS mode={mode}");
    Ok(())
}

/// Model gates only provide an execution environment; real core freezes/admit/checks real Skill tools.
struct HeldSkillCall {
    entered: Option<oneshot::Sender<()>>,
    release: Option<oneshot::Receiver<()>>,
}

impl ModelSession for HeldSkillCall {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let entered = self.entered.take();
        let release = self.release.take();
        Ok(PreparedModelCall::new(async move {
            let first = entered.is_some();
            if let Some(entered) = entered {
                let _ = entered.send(());
            }
            if let Some(release) = release {
                let _ = release.await;
            }
            Ok(ModelStepOutput {
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: Vec::new(),
                tool_calls: if first {
                    vec![ModelToolCall {
                        call_id: "frozen-skill-call".into(),
                        tool_id: "skill_view".into(),
                        arguments: OpaquePayload::new("application/json", 1, r#"{"name":"owned"}"#)
                            .map_err(|error| ModelError {
                                kind: pl_core::model::ModelFailureKind::InvalidResponse,
                                details: None,
                                usage: Default::default(),
                                source: Some(Box::new(error)),
                            })?,
                    }]
                } else {
                    Vec::new()
                },
                private_context: None,
                usage: Default::default(),
            })
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

async fn catalog(
    root: &Path,
    sources: Vec<SkillDirectorySource>,
    request: SkillProviderRequest,
) -> anyhow::Result<FrozenSkillCatalog> {
    fs::create_dir_all(root)?;
    let registry = SkillRegistry::new();
    let _registration = registry.register(Arc::new(FileSystemSkillProvider::from_directories(
        "same-provider-id",
        sources,
    )?))?;
    Ok(registry.discover(request).await?)
}

fn request(root: &Path) -> SkillProviderRequest {
    SkillProviderRequest {
        workspace_root: root.to_owned(),
        config: SkillsConfig::default(),
        system_dir: None,
        cancellation: CancellationToken::new(),
    }
}

fn registration(catalog: &FrozenSkillCatalog) -> anyhow::Result<Registration> {
    let kind = ThreadSkillKind::View;
    let declaration = pl_model::runtime::thread_tool_declaration(&kind.declaration())?;
    Ok(ThreadSkillTool::new(catalog.discovery_sources(), kind).registration(declaration)?)
}

async fn observe_authorization(root: &Path) -> anyhow::Result<()> {
    for change in [
        "same",
        "contents-and-generation",
        "workspace",
        "config",
        "system",
        "source-root",
        "source-kind",
        "source-order",
    ] {
        let workspace = root.join(change);
        let skills = workspace.join("skills");
        prepare_source(&skills)?;
        let alternate = workspace.join("alternate");
        prepare_source(&alternate)?;
        let source = SkillDirectorySource::new(&skills, SkillSourceKind::Project);
        let mut initial_sources = vec![source.clone()];
        if change == "source-order" {
            initial_sources.push(SkillDirectorySource::new(
                &alternate,
                SkillSourceKind::Project,
            ));
        }
        let registry = SkillRegistry::new();
        let _registration = registry.register(Arc::new(
            FileSystemSkillProvider::from_directories("same-provider-id", initial_sources.clone())?,
        ))?;
        let original = registry.discover(request(&workspace)).await?;
        let (entered, observed) = oneshot::channel();
        let (release, held) = oneshot::channel();
        let thread = ThreadHandle::start(
            format!("skill-admission-{change}"),
            DynModelSession::new(HeldSkillCall {
                entered: Some(entered),
                release: Some(held),
            }),
        )?;
        thread
            .register_tools(vec![registration(&original)?])
            .await
            .map_err(|error| anyhow::anyhow!("register original: {error:?}"))?;
        let runner = tokio::spawn({
            let thread = thread.clone();
            async move {
                thread
                    .run_turn(TurnInput {
                        turn_id: "frozen-turn".into(),
                        attempt_prefix: "frozen-attempt".into(),
                        content: vec![ContextContent::Text {
                            text: Arc::from("load the owned skill"),
                        }],
                        max_model_steps: ModelStepLimit::Limited(
                            3.try_into().map_err(|_| ThreadError::InvalidIdentity)?,
                        ),
                        cancellation: CancellationToken::new(),
                    })
                    .await
            }
        });
        observed.await?;
        let mut new_request = request(&workspace);
        let mut new_sources = initial_sources;
        match change {
            "same" => {}
            "contents-and-generation" => {
                fs::write(
                    skills.join("owned/SKILL.md"),
                    document("changed after request freeze"),
                )?;
                original.invalidate();
            }
            "workspace" => {
                new_request.workspace_root = workspace.join("other-workspace");
                fs::create_dir_all(&new_request.workspace_root)?;
            }
            "config" => new_request.config.disabled.push("unrelated-name".into()),
            "system" => new_request.system_dir = Some(workspace.join("different-system")),
            "source-root" => new_sources[0].root = alternate.clone(),
            "source-kind" => new_sources[0].source = SkillSourceKind::User,
            "source-order" => {
                new_sources = vec![
                    SkillDirectorySource::new(&alternate, SkillSourceKind::Project),
                    source,
                ]
            }
            _ => unreachable!(),
        }
        let replacement = if change == "contents-and-generation" {
            registry.discover(new_request).await?
        } else {
            catalog(&workspace, new_sources, new_request).await?
        };
        let replaced = thread
            .register_tools(vec![registration(&replacement)?])
            .await;
        let _ = release.send(());
        let outcome = runner.await?;
        let snapshot = thread.snapshot();
        let deliveries = thread
            .effects()
            .await?
            .into_iter()
            .flat_map(|effect| effect.deliveries.to_vec())
            .collect::<Vec<_>>();
        let delivery = deliveries
            .iter()
            .find(|delivery| delivery.call_id == "frozen-skill-call");
        thread.close().await?;
        replaced.map_err(|error| anyhow::anyhow!("register replacement: {error:?}"))?;
        let tool_records = snapshot
            .context
            .records
            .iter()
            .filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
            .collect::<Vec<_>>();
        println!(
            "authorization change={change} outcome={outcome:?} tool_results={}",
            serde_json::to_string(&tool_records)?
        );
        if matches!(change, "same" | "contents-and-generation") {
            ensure!(
                matches!(&outcome, Ok(completed) if completed.outcome == TurnOutcome::Completed),
                "equivalent source reassembly revoked a frozen call: {outcome:?}"
            );
            ensure!(
                matches!(
                    delivery.map(|delivery| &delivery.outcome),
                    Some(ToolOutcome::Succeeded)
                ),
                "frozen Skill tool did not succeed: {delivery:?}"
            );
            ensure!(snapshot.context.records.iter().any(|record| matches!(record.source, ContextSource::ToolResult { .. }) && record.content.iter().any(|content| matches!(content, ContextContent::Text { text } if text.contains("owned skill") || text.contains("changed after request freeze")))), "real Skill tool did not deliver its content through Thread");
        } else {
            ensure!(
                matches!(outcome, Err(ThreadError::ToolPermissionRevoked))
                    || matches!(delivery.map(|delivery| &delivery.outcome), Some(ToolOutcome::Failed(error)) if matches!(error.source.downcast_ref::<ThreadError>(), Some(ThreadError::ToolPermissionRevoked))),
                "changed discovery authority was not revoked: {outcome:?}, delivery: {delivery:?}"
            );
        }
    }
    Ok(())
}

async fn observe_static_root_isolated(root: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(root)?;
    let status = tokio::process::Command::new(std::env::current_exe()?)
        .kill_on_drop(true)
        .arg(root)
        .arg("static-root-child")
        .env("HOME", root.join("home"))
        .env("USERPROFILE", root.join("home"))
        .status()
        .await?;
    ensure!(
        status.success(),
        "static public catalog observation failed: {status}"
    );
    Ok(())
}

#[cfg(unix)]
fn observe_static_root(root: &Path) -> anyhow::Result<()> {
    let user_source = root.join("user-source");
    let config = SkillsConfig {
        user_dir: user_source.to_string_lossy().into_owned(),
        ..SkillsConfig::default()
    };
    std::os::unix::fs::symlink(root.join("missing-target"), &user_source)?;
    let linked = SkillCatalog::discover(root, &config, None);
    println!("static-catalog-dangling-source outcome={linked:?}");
    ensure!(
        linked.is_err(),
        "public catalog treated a dangling source link as complete empty"
    );
    fs::remove_file(user_source)?;
    let missing = SkillCatalog::discover(root, &config, None)?;
    println!("static-catalog-missing-source outcome={missing:?}");
    ensure!(
        missing.complete && missing.skills.is_empty() && missing.warnings.is_empty(),
        "genuinely missing sources did not produce a complete empty catalog"
    );
    Ok(())
}

#[cfg(not(unix))]
fn observe_static_root(_: &Path) -> anyhow::Result<()> {
    anyhow::bail!("the dangling symbolic-link observation requires a Unix host")
}

async fn observe_root_type(root: &Path) -> anyhow::Result<()> {
    let skills = root.join("skills");
    prepare_source(&skills)?;
    let original = catalog(
        root,
        vec![SkillDirectorySource::new(&skills, SkillSourceKind::Project)],
        request(root),
    )
    .await?;
    let tool = ThreadSkillTool::new(original.discovery_sources(), ThreadSkillKind::List);
    fs::remove_dir_all(&skills)?;
    fs::write(&skills, "existing source is not a directory")?;
    let outcome = tool
        .execute(
            OpaquePayload::new("application/json", 1, "{}")?,
            call_context(CancellationToken::new()),
        )
        .await;
    println!("root-is-file outcome={outcome:?}");
    ensure!(
        outcome.is_err(),
        "existing ordinary-file source was reported as complete empty"
    );
    fs::remove_file(&skills)?;
    let missing = tool
        .execute(
            OpaquePayload::new("application/json", 1, "{}")?,
            call_context(CancellationToken::new()),
        )
        .await?;
    ensure!(serde_json::from_str::<serde_json::Value>(missing.payload().content())?["count"] == 0);
    prepare_source(&skills)?;
    tool.execute(
        OpaquePayload::new("application/json", 1, "{}")?,
        call_context(CancellationToken::new()),
    )
    .await?;
    Ok(())
}

#[derive(Debug)]
struct WorkerGate {
    started: oneshot::Sender<()>,
    cleanup_entered: oneshot::Sender<()>,
    cleanup_release: std::sync::mpsc::Receiver<()>,
    finished: oneshot::Sender<()>,
}

/// Only an environmental worker lifecycle, no Skill discovery/selection implementation.
#[derive(Debug)]
struct WorkerSource {
    id: SkillProviderId,
    gate: Mutex<Option<WorkerGate>>,
}

impl SkillProvider for WorkerSource {
    fn id(&self) -> &SkillProviderId {
        &self.id
    }
    fn discovery_identity(&self) -> String {
        "owned-worker-observation/v1".into()
    }
    fn list<'a>(
        &'a self,
        request: SkillProviderRequest,
    ) -> Pin<Box<dyn Future<Output = pl_protocol::Result<SkillProviderObservation>> + Send + 'a>>
    {
        let gate = self
            .gate
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        Box::pin(async move {
            if let Some(gate) = gate {
                tokio::task::spawn_blocking(move || {
                    let _ = gate.started.send(());
                    futures::executor::block_on(request.cancellation.cancelled());
                    let _ = gate.cleanup_entered.send(());
                    let _ = gate.cleanup_release.recv();
                    let _ = gate.finished.send(());
                })
                .await
                .map_err(|error| pl_protocol::PureError::ConfigError(error.to_string()))?;
            }
            Ok(SkillProviderObservation {
                candidates: Vec::new(),
                complete: true,
                warnings: Vec::new(),
            })
        })
    }
    fn load<'a>(
        &'a self,
        _: &'a SkillCandidate,
        _: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = pl_protocol::Result<SkillDefinition>> + Send + 'a>> {
        Box::pin(async {
            Err(pl_protocol::PureError::ConfigError(
                "environment source has no documents".into(),
            ))
        })
    }
    fn read_resource<'a>(
        &'a self,
        _: &'a SkillCandidate,
        _: &'a str,
        _: CancellationToken,
    ) -> Pin<Box<dyn Future<Output = pl_protocol::Result<String>> + Send + 'a>> {
        Box::pin(async {
            Err(pl_protocol::PureError::ConfigError(
                "environment source has no resources".into(),
            ))
        })
    }
}

async fn observe_cancellation(root: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(root)?;
    let source = Arc::new(WorkerSource {
        id: SkillProviderId::new("owned-worker")?,
        gate: Mutex::new(None),
    });
    let registry = SkillRegistry::new();
    let _registration = registry.register(source.clone())?;
    let original = registry.discover(request(root)).await?;
    let tool = ThreadSkillTool::new(original.discovery_sources(), ThreadSkillKind::List);
    let (started, observed) = oneshot::channel();
    let (cleanup_entered, cleanup_observed) = oneshot::channel();
    let (cleanup_release, released) = std::sync::mpsc::channel();
    let (finished, worker_finished) = oneshot::channel();
    *source
        .gate
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(WorkerGate {
        started,
        cleanup_entered,
        cleanup_release: released,
        finished,
    });
    let cancellation = CancellationToken::new();
    let mut operation = Box::pin(tool.execute(
        OpaquePayload::new("application/json", 1, "{}")?,
        call_context(cancellation.clone()),
    ));
    tokio::select! { result = &mut operation => anyhow::bail!("discovery returned before worker entry: {result:?}"), entered = observed => entered?, }
    cancellation.cancel();
    let early = tokio::select! { biased; result = &mut operation => Some(result), entered = cleanup_observed => { entered?; None } };
    let early = match early {
        Some(outcome) => Some(outcome),
        None => match futures::poll!(&mut operation) {
            std::task::Poll::Ready(outcome) => Some(outcome),
            std::task::Poll::Pending => None,
        },
    };
    let returned_early = early.is_some();
    cleanup_release.send(())?;
    let outcome = match early {
        Some(outcome) => outcome,
        None => operation.await,
    };
    worker_finished.await?;
    println!(
        "running-cancellation returned_before_worker_cleanup={returned_early} outcome={outcome:?}"
    );
    ensure!(
        !returned_early,
        "cancellation detached a still-owned blocking discovery worker"
    );
    ensure!(outcome.is_err(), "cancelled discovery succeeded");
    tool.execute(
        OpaquePayload::new("application/json", 1, "{}")?,
        call_context(CancellationToken::new()),
    )
    .await?;
    Ok(())
}

fn call_context(cancellation: CancellationToken) -> CallContext {
    CallContext {
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
        thread_id: "skill-lifecycle".into(),
        turn_id: "same-turn".into(),
        call_id: "cancel-in-flight".into(),
        cancellation,
        extensions: Default::default(),
        catalog: Arc::from(Vec::new()),
        extension_sequence: 0,
    }
}

fn document(body: &str) -> String {
    format!("---\nname: owned\ndescription: Owned skill observation.\n---\n\n{body}\n")
}
fn prepare_source(root: &Path) -> anyhow::Result<()> {
    fs::create_dir_all(root.join("owned"))?;
    fs::write(root.join(".ignore"), "!**\n")?;
    fs::write(root.join("owned/SKILL.md"), document("owned skill"))?;
    Ok(())
}
