use std::{
    path::PathBuf,
    sync::{Arc, Mutex},
    time::Duration,
};

use anyhow::{Context, Result};
use tokio::sync::oneshot;

use super::super::StudioRuntime;
use super::super::bot_archive_test_host::BotArchiveTestHost;
use super::test_support::{HeldWorkspaceSnapshot, PausedWorkspaceSnapshots};

struct ProjectFixture {
    _temp: tempfile::TempDir,
    _host: BotArchiveTestHost,
    root: PathBuf,
    project_id: String,
    runtime: StudioRuntime,
}

impl ProjectFixture {
    async fn new() -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let host = BotArchiveTestHost::new(&temp.path().join("home")).await?;
        let runtime = host.runtime.as_ref().clone();
        let root = temp.path().join("workspace");
        tokio::fs::create_dir(&root).await?;
        let project = runtime.open_project(&root).await?;
        Ok(Self {
            _temp: temp,
            _host: host,
            root,
            project_id: project.id,
            runtime,
        })
    }

    async fn create_active(&self) -> Result<crate::studio::ThreadRecord> {
        self.runtime
            .create_thread(&self.project_id, "LSP fixture")
            .await
    }

    async fn install_lsp_fixture(&self, display_name: &str) -> Result<()> {
        let configuration = self.root.join(".anywork/lsp/fixture.toml");
        tokio::fs::create_dir_all(configuration.parent().unwrap()).await?;
        let peer = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .context("Runtime crate parent")?
            .join("pl-tool/tests/support/lsp_fixture.py");
        anyhow::ensure!(peer.is_file(), "missing real LSP fixture {peer:?}");
        let source = format!(
            "schema_version = 1\nid = 'fixture'\ndisplay_name = '{display_name}'\ncommand = 'python3'\nargs = {}\nlanguage_ids = ['fixture']\nextensions = ['fixture']\noperations = ['hover']\n",
            serde_json::to_string(&[
                "-u".to_owned(),
                peer.display().to_string(),
                "{workspaceRoot}/lsp-requests.jsonl".to_owned(),
            ])?
        );
        tokio::fs::write(&configuration, source).await?;

        Ok(())
    }

    async fn shutdown(&self) -> Result<()> {
        self.runtime.shutdown_runtime().await?;
        Ok(())
    }
}

async fn wait_thread_lsp(
    runtime: &StudioRuntime,
    thread_id: &str,
    matches: impl Fn(&crate::StudioThreadLspStateSnapshot) -> bool,
) -> Result<crate::protocol::StudioThreadLspStateSnapshot> {
    let mut subscription = runtime
        .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
            thread_id: thread_id.to_owned(),
        })
        .await?;
    tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let Some(frame) = subscription.recv().await? else {
                anyhow::bail!("Thread LSP topic closed");
            };
            let snapshot = match frame {
                crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                    crate::StudioProductBaselineState::ThreadLsp(snapshot) => Some(*snapshot),
                    _ => {
                        anyhow::bail!("Thread LSP topic produced a different baseline")
                    }
                },
                crate::StudioProductFrame::Event(event) => match event.kind {
                    crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => {
                        Some(snapshot)
                    }
                    _ => None,
                },
                crate::StudioProductFrame::Lagged { .. } => None,
            };
            if let Some(snapshot) = snapshot
                && matches(&snapshot)
            {
                return Ok(snapshot);
            }
        }
    })
    .await
    .context("expected Thread LSP state was not published")?
}

#[tokio::test]
async fn cold_reads_and_reset_preserve_binding_then_hot_reset_applies_configuration() -> Result<()>
{
    let env = ProjectFixture::new().await?;
    env.install_lsp_fixture("first").await?;
    let thread = env
        .runtime
        .create_thread(&env.project_id, "cold LSP fixture")
        .await?;
    let warmed =
        wait_thread_lsp(&env.runtime, &thread.id, |state| state.binding_id.is_some()).await?;
    Box::pin(env.runtime.ensure_thread_owner(&thread.id))
        .await?
        .flush()
        .await?;
    env.runtime
        .session_of(&thread.id)
        .context("owning session")?
        .close(&thread.id)
        .await?;
    env.runtime.refresh_thread_lsp_states().await;
    let cold = env.runtime.read_thread_lsp_state(&thread.id).await?;
    assert!(cold.binding_id.is_none());
    assert!(cold.servers.is_empty());
    let request = crate::ThreadLspResetRequest {
        thread_id: thread.id.clone(),
        binding_id: warmed.binding_id.context("original LSP binding")?,
        server_id: "fixture".into(),
    };
    let stale = env
        .runtime
        .reset_thread_lsp_server(request.clone())
        .await
        .unwrap_err();
    assert_eq!(
        stale.downcast_ref::<crate::StudioError>().unwrap().reason(),
        Some(crate::StudioErrorReason::StaleLspBinding.label())
    );
    assert!(
        env.runtime
            .thread_factory
            .resource_scope(&thread.id)
            .is_none()
    );

    let _owner = Box::pin(env.runtime.ensure_thread_owner(&thread.id)).await?;
    let first = wait_thread_lsp(&env.runtime, &thread.id, |state| {
        state
            .servers
            .iter()
            .any(|server| server.display_name == "first" && server.phase == "ready")
    })
    .await?;
    let binding_id = first
        .binding_id
        .clone()
        .context("warm Thread LSP binding")?;
    env.runtime.refresh_thread_lsp_states().await;
    env.runtime.refresh_thread_lsp_states().await;
    assert_eq!(env.runtime.read_thread_lsp_state(&thread.id).await?, first);

    env.install_lsp_fixture("thread reset").await?;
    env.runtime
        .reset_thread_lsp_server(crate::ThreadLspResetRequest {
            binding_id: binding_id.clone(),
            ..request
        })
        .await?;
    let reset = wait_thread_lsp(&env.runtime, &thread.id, |state| {
        state
            .servers
            .iter()
            .any(|server| server.display_name == "thread reset" && server.phase == "ready")
    })
    .await?;
    assert_eq!(reset.binding_id.as_deref(), Some(binding_id.as_str()));
    assert!(reset.revision > first.revision);

    env.install_lsp_fixture("project reset").await?;
    env.runtime
        .reset_lsp_request(crate::LspResetRequest::Workspace {
            workspace_id: env.project_id.clone(),
        })
        .await?;
    let project_reset = wait_thread_lsp(&env.runtime, &thread.id, |state| {
        state
            .servers
            .iter()
            .any(|server| server.display_name == "project reset" && server.phase == "ready")
    })
    .await?;
    assert_eq!(project_reset.binding_id, reset.binding_id);
    assert!(project_reset.revision > reset.revision);
    env.shutdown().await
}

#[tokio::test]
async fn thread_lsp_rejects_invalid_bindings_and_publishes_retirement() -> Result<()> {
    let env = ProjectFixture::new().await?;
    let first = env.create_active().await?;
    let first_state =
        wait_thread_lsp(&env.runtime, &first.id, |state| state.binding_id.is_some()).await?;
    assert!(!first_state.binding_id.as_deref().unwrap().is_empty());
    assert!(first_state.servers.is_empty());
    let first_read = env.runtime.read_thread_lsp_state(&first.id).await?;
    assert_eq!(first_read.revision, first_state.revision);

    let second = env.create_active().await?;
    let second_state =
        wait_thread_lsp(&env.runtime, &second.id, |state| state.binding_id.is_some()).await?;
    assert!(!second_state.binding_id.as_deref().unwrap().is_empty());
    assert!(second_state.revision > first_state.revision);

    let stale = env
        .runtime
        .reset_thread_lsp_server(crate::ThreadLspResetRequest {
            thread_id: first.id.clone(),
            binding_id: "expired-binding-qualification".into(),
            server_id: "irrelevant-while-stale".into(),
        })
        .await
        .expect_err("stale qualification must be rejected before member lookup");
    let stale = stale
        .downcast_ref::<crate::StudioError>()
        .expect("typed stale binding error");
    assert_eq!(stale.code, crate::StudioErrorCode::Conflict);
    assert_eq!(
        stale.reason(),
        Some(crate::StudioErrorReason::StaleLspBinding.label())
    );

    let absent = env
        .runtime
        .reset_thread_lsp_server(crate::ThreadLspResetRequest {
            thread_id: first.id.clone(),
            binding_id: first_state.binding_id.clone().unwrap(),
            server_id: "not-a-member".into(),
        })
        .await
        .expect_err("a server outside this binding must be rejected");
    assert_eq!(
        absent
            .downcast_ref::<crate::StudioError>()
            .map(|error| error.code),
        Some(crate::StudioErrorCode::NotFound)
    );

    let mut retired_subscription = env
        .runtime
        .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
            thread_id: first.id.clone(),
        })
        .await?;
    let scope = env
        .runtime
        .thread_factory
        .resource_scope(&first.id)
        .expect("active Thread resource scope");
    env.runtime
        .thread_factory
        .close_scope_tools(&first.id, &scope)
        .await?;
    let retired = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let Some(frame) = retired_subscription.recv().await? else {
                anyhow::bail!("Thread LSP topic closed before retirement");
            };
            let snapshot = match frame {
                crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                    crate::StudioProductBaselineState::ThreadLsp(snapshot) => Some(*snapshot),
                    _ => {
                        anyhow::bail!("Thread LSP topic produced a different baseline")
                    }
                },
                crate::StudioProductFrame::Event(event) => match event.kind {
                    crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => {
                        Some(snapshot)
                    }
                    _ => None,
                },
                crate::StudioProductFrame::Lagged { .. } => None,
            };
            if let Some(snapshot) = snapshot
                && snapshot.binding_id.is_none()
                && snapshot.revision > first_state.revision
            {
                return Ok(snapshot);
            }
        }
    })
    .await
    .context("retired Thread LSP empty projection was not published")??;
    assert!(retired.servers.is_empty());
    let empty_read = env.runtime.read_thread_lsp_state(&first.id).await?;
    assert_eq!(empty_read.revision, retired.revision);
    assert_eq!(empty_read.binding_id, None);
    assert!(empty_read.servers.is_empty());

    let released = env
        .runtime
        .reset_thread_lsp_server(crate::ThreadLspResetRequest {
            thread_id: first.id.clone(),
            binding_id: first_state.binding_id.clone().unwrap(),
            server_id: "released-binding-server".into(),
        })
        .await
        .expect_err("a retired Thread binding must be rejected as stale");
    let released = released
        .downcast_ref::<crate::StudioError>()
        .expect("typed released binding error");
    assert_eq!(released.code, crate::StudioErrorCode::Conflict);
    assert_eq!(
        released.reason(),
        Some(crate::StudioErrorReason::StaleLspBinding.label())
    );

    let unknown = env
        .runtime
        .read_thread_lsp_state("unknown-thread-lsp")
        .await
        .expect_err("unknown Thread must not become an empty successful projection");
    assert_eq!(
        unknown
            .downcast_ref::<crate::StudioError>()
            .map(|error| error.code),
        Some(crate::StudioErrorCode::NotFound)
    );
    env.shutdown().await?;
    Ok(())
}

#[tokio::test]
async fn thread_lsp_cancellation_after_snapshot_commits_only_empty_projection() -> Result<()> {
    let env = ProjectFixture::new().await?;
    env.install_lsp_fixture("fixture").await?;
    let created = env.create_active().await?;
    let thread_id = created.id.clone();
    let mut topic = env
        .runtime
        .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
            thread_id: thread_id.clone(),
        })
        .await?;
    let initial = loop {
        let Some(frame) = topic.recv().await? else {
            anyhow::bail!("Thread LSP topic closed");
        };
        let snapshot = match frame {
            crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                crate::StudioProductBaselineState::ThreadLsp(snapshot) => Some(*snapshot),
                _ => anyhow::bail!("unexpected Thread LSP baseline"),
            },
            crate::StudioProductFrame::Event(event) => match event.kind {
                crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => Some(snapshot),
                _ => None,
            },
            crate::StudioProductFrame::Lagged { dropped, .. } => {
                anyhow::bail!("Thread LSP topic lost {dropped} frames")
            }
        };
        if let Some(snapshot) = snapshot
            && snapshot.binding_id.is_some()
            && snapshot.servers.iter().any(|server| server.id == "fixture")
        {
            break snapshot;
        }
    };
    let binding_id = initial.binding_id.clone().unwrap();
    let mut result_topic = env
        .runtime
        .subscribe_product_topic(crate::StudioProductTopic::ThreadLsp {
            thread_id: thread_id.clone(),
        })
        .await?;
    let (entered, captured) = oneshot::channel();
    let (resume, released) = oneshot::channel();
    let source = PausedWorkspaceSnapshots {
        registry: env.runtime.external_runtimes.lsp.clone(),
        server: "fixture",
        gate: Arc::new(Mutex::new(Some(HeldWorkspaceSnapshot {
            entered,
            released,
        }))),
    };
    let services = env.runtime.lsp_observation_services();
    let refresh = tokio::spawn(async move { services.refresh_thread_states(&source).await });
    let captured = tokio::time::timeout(Duration::from_secs(10), captured).await??;
    let current = env.runtime.thread_factory.binding_snapshot(&thread_id);
    let Some(current) = current else {
        resume.send(()).unwrap();
        anyhow::bail!("current accepted Thread binding disappeared before cancellation");
    };
    let same_binding = current.lsp_binding_id.as_deref() == Some(binding_id.as_str());
    let captured_member = captured.iter().any(|server| server.id == "fixture");
    current.lifetime.cancel();
    resume.send(()).unwrap();
    assert!(
        same_binding,
        "the cancellation must target the captured binding"
    );
    assert!(
        captured_member,
        "captured LSP server member must be non-empty"
    );
    refresh.await?;
    let published = env.runtime.read_thread_lsp_state(&thread_id).await?;
    assert!(published.revision > initial.revision);
    assert_eq!(published.binding_id, None);
    assert!(published.servers.is_empty());
    let retired_event = loop {
        let Some(frame) = result_topic.recv().await? else {
            anyhow::bail!("Thread LSP topic closed before invalidation event");
        };
        let snapshot = match frame {
            crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                crate::StudioProductBaselineState::ThreadLsp(snapshot) => Some(*snapshot),
                _ => anyhow::bail!("unexpected Thread LSP baseline"),
            },
            crate::StudioProductFrame::Event(event) => match event.kind {
                crate::StudioProductEventKind::ThreadLspStateChanged(snapshot) => Some(snapshot),
                _ => None,
            },
            crate::StudioProductFrame::Lagged { dropped, .. } => {
                anyhow::bail!("Thread LSP topic lost {dropped} events")
            }
        };
        if let Some(snapshot) = snapshot
            && snapshot.revision > initial.revision
        {
            break snapshot;
        }
    };
    assert_eq!(retired_event.binding_id, None);
    assert!(retired_event.servers.is_empty());
    env.shutdown().await?;
    Ok(())
}
