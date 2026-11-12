//! Real collaboration paths; only the external ACP peer is replaced.
use crate::acp_transport_fixture::AcpTransportFixture as Fixture;
use crate::thread_assembler::agent_wait::{WaitAgentRequest, WaitAgentResult};
use crate::thread_assembler::{AgentHost, SessionRuntime};
use anyhow::{Context, Result};
use futures::FutureExt;
use pl_protocol::studio::{AcpOpenIntent, OpenAcpSessionRequest};
use pl_tool::collaboration::control::AgentCallContext;
use pl_tool::collaboration::thread::{AgentControlHost, AgentMessage, AgentSpawn};
use std::sync::Arc;
use std::time::Duration;

async fn peer_opening(fixture: &Fixture) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        while !tokio::fs::try_exists(fixture.home.path().join("opening")).await? {
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await?
}

fn hold_peer_open(fixture: &Fixture) -> Result<()> {
    for name in ["opening", "release"] {
        let path = fixture.home.path().join(name);
        if path.exists() {
            std::fs::remove_file(path)?;
        }
    }
    std::fs::write(fixture.home.path().join("mode"), "load-hold")?;
    Ok(())
}

async fn rename_during_open(
    fixture: &Fixture,
    caller: &pl_protocol::AgentThreadIdentity,
    title: &str,
) -> Result<()> {
    fixture
        .runtime
        .rename_thread(
            format!("rename-{title}"),
            caller.thread_id.to_string(),
            title.into(),
        )
        .await?;
    std::fs::write(fixture.home.path().join("release"), "release")?;
    std::fs::write(fixture.home.path().join("mode"), "replay")?;
    Ok(())
}

fn session_unchanged(
    fixture: &Fixture,
    caller: &pl_protocol::AgentThreadIdentity,
    title: &str,
    delegation: pl_protocol::DelegationSettings,
) -> Result<()> {
    let sessions = fixture.runtime.store.catalog().sessions();
    let sessions = sessions
        .iter()
        .filter(|session| session.workspace_id == fixture.workspace.id)
        .collect::<Vec<_>>();
    assert_eq!(
        sessions.len(),
        1,
        "a child must not create a second Session"
    );
    let session = sessions[0];
    assert_eq!(session.session_id, caller.session_id.as_str());
    assert_eq!(session.root_agent_id, caller.agent_id.as_str());
    assert_eq!(
        session.title, title,
        "child publication overwrote a concurrent root title"
    );
    assert_eq!(session.delegation_mode, delegation.mode);
    assert_eq!(session.delegation_preference, delegation.preference);
    eprintln!(
        "Session preserved through child publication: session={}, title={}, mode={:?}, preference={:?}, sessionCount={}",
        session.session_id,
        session.title,
        session.delegation_mode,
        session.delegation_preference,
        sessions.len()
    );
    Ok(())
}

async fn native_inbox_report(
    runtime: &crate::studio::StudioRuntime,
    owner: &SessionRuntime,
    caller: &pl_protocol::AgentThreadIdentity,
    child: &pl_protocol::AgentThreadIdentity,
    resources: &super::AcpResources,
    completed: &pl_acp::session::Completed,
) -> Result<String> {
    let parent = owner
        .observed_thread(caller.thread_id.as_str())
        .context("Native parent")?;
    let scope = owner.native_resources(&parent)?;
    let mut changes = scope
        .observations
        .lock()
        .unwrap()
        .last()
        .context("Native parent observation")?
        .report_changes();
    let history = runtime.store.history(caller.thread_id.as_str()).await?;
    let expected_id = format!(
        "studio.acp.{}:{}:{}:{}",
        child.agent_id.as_str().len(),
        child.agent_id,
        resources.generation,
        completed.completion_sequence
    );
    tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            let snapshot = parent.snapshot();
            let records = snapshot
                .inbox
                .iter()
                .filter(|record| record.message.id == expected_id)
                .collect::<Vec<_>>();
            if let Some(receipt) = history.message_identity(&expected_id).await?
                && let Some(record) = records.first()
            {
                assert_eq!(
                    records.len(),
                    1,
                    "stable completion identity was duplicated"
                );
                assert_eq!(
                    record.message.source_id,
                    format!("agent:{}", child.thread_id)
                );
                assert_eq!(
                    record.message.kind,
                    pl_core::context::AgentMessageKind::Report
                );
                assert_eq!(receipt.sequence, record.sequence);
                assert_eq!(
                    receipt.digest.as_deref(),
                    Some(record.message.digest().as_str())
                );
                let body: serde_json::Value =
                    serde_json::from_str(record.message.payload.content())?;
                assert_eq!(body["agentId"], child.agent_id.as_str());
                assert_eq!(body["backend"], "acp");
                assert_eq!(body["generation"], resources.generation);
                assert_eq!(body["completionSequence"], completed.completion_sequence);
                assert_eq!(
                    body["run"],
                    serde_json::json!({
                        "instance": completed.run.instance, "sequence": completed.run.sequence,
                    })
                );
                assert_eq!(body["summary"], completed.summary);
                assert_eq!(body["truncated"], completed.truncated);
                assert_eq!(
                    body["result"],
                    serde_json::to_value(completed.result.as_ref().unwrap())?
                );
                eprintln!(
                    "Native inbox durable report: id={expected_id}, acceptedSequence={}, run={:?}",
                    receipt.sequence, completed.run
                );
                return Ok::<_, anyhow::Error>(expected_id.clone());
            }
            drop(snapshot);
            changes.changed().await?;
        }
    })
    .await?
}

async fn close_fixture(fixture: &Fixture, result: std::thread::Result<Result<()>>) -> Result<()> {
    close_runtime(&fixture.runtime, &fixture.workspace.id, result).await
}

async fn close_runtime(
    runtime: &crate::studio::StudioRuntime,
    workspace: &str,
    result: std::thread::Result<Result<()>>,
) -> Result<()> {
    let cleanup = runtime.shutdown_runtime().await.map(|_| ());
    if cleanup.is_err() {
        // A storage failure remains a test failure, but cannot leave the peer process behind.
        for owner in runtime.sessions.resident_sessions() {
            for id in owner.acp_roots_for_workspace(workspace) {
                if let Some(resources) = owner.resident_acp(&id)? {
                    let outcome = resources.close().await;
                    eprintln!(
                        "ACP failure cleanup: thread={id}, localComplete={}, outcome={outcome:?}",
                        outcome.local_complete
                    );
                }
            }
            let report = owner.close_session().await;
            for (id, error) in report.iter() {
                eprintln!(
                    "original Session close retry failed: thread={id}, error={:#}",
                    anyhow::Error::from(error.clone())
                );
            }
        }
    }
    match result {
        Ok(Ok(())) => cleanup.context("mixed fixture runtime shutdown"),
        Ok(Err(error)) => match cleanup {
            Ok(()) => Err(error),
            Err(cleanup) => {
                Err(error.context(format!("runtime shutdown also failed: {cleanup:#}")))
            }
        },
        Err(panic) => {
            if let Err(error) = cleanup {
                eprintln!("runtime shutdown after test panic failed: {error:#}");
            }
            std::panic::resume_unwind(panic)
        }
    }
}

fn call(
    _host: &AgentHost,
    caller: &pl_protocol::AgentThreadIdentity,
    id: &str,
) -> AgentCallContext {
    AgentCallContext {
        caller: caller.agent_id.clone(),
        call_id: id.into(),
        cancellation: Default::default(),
    }
}

fn wait_report<'a>(
    host: &'a AgentHost,
    caller: &pl_protocol::AgentThreadIdentity,
    target: &pl_protocol::AgentId,
    call_id: &str,
    after: Option<String>,
) -> futures::future::BoxFuture<
    'a,
    std::result::Result<WaitAgentResult, pl_tool::collaboration::control::ControlError>,
> {
    let future = host.wait_agent(
        call(host, caller, call_id),
        WaitAgentRequest {
            target: target.to_string(),
            after,
            timeout_ms: 20_000,
        },
    );
    // The source reader owns its pending I/O; keep repeated read operations out of
    // the long scenario's inline layout without spawning tasks or changing its stack.
    Box::pin(future)
}

fn save_profile(fixture: &Fixture) -> Result<()> {
    fixture.runtime.save_user_agent_profile(
        "save-acp-child".into(),
        fixture.runtime.read_settings()?.config.revision,
        "acp-child",
        &crate::config::UserAgentProfile {
            enabled: true,
            display_name: "ACP child".into(),
            description: "Ordinary ACP task".into(),
            when_to_use: "External coding task".into(),
            binding: pl_protocol::AgentBinding::Acp(pl_protocol::AcpAgentConfig {
                account_id: "business-peer".into(),
            }),
            workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
        },
    )?;
    Ok(())
}

async fn host(
    fixture: &Fixture,
    native: bool,
) -> Result<(SessionRuntime, pl_protocol::AgentThreadIdentity, AgentHost)> {
    let profiles = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
    if native {
        let current = fixture.runtime.config_runtime.read()?;
        fixture
            .runtime
            .config_runtime
            .update(current.revision, |config| {
                let mut config = config.clone();
                for account in config.models.accounts.values_mut() {
                    account.bearer_token = Some("isolated-unused-fixture-token".into());
                    account.bearer_token_env = None;
                    account.base_url = "http://127.0.0.1:9".into();
                }
                Ok(config)
            })?;
        let root = fixture
            .runtime
            .create_thread(&fixture.workspace.id, "Native root")
            .await?;
        let thread = fixture.runtime.ensure_thread_owner(&root.id).await?;
        let owner = fixture
            .runtime
            .session_of(&root.id)
            .context("Native owner")?;
        let identity = fixture
            .runtime
            .agent_facility
            .product_events
            .agent_execution_identity(&root.id)
            .context("Native identity")?
            .0;
        let resources = owner.native_resources(&thread)?;
        let selection =
            crate::studio::delegation::saved(&thread.snapshot())?.context("Native delegation")?;
        let host = owner.native_agent_host(&identity, &resources, &profiles, selection)?;
        Ok((owner, identity, host))
    } else {
        let mut open = fixture.open().await?;
        Fixture::ready(&mut open).await?;
        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(open.target.session_id)?)
            .context("ACP owner")?;
        let identity = owner
            .acp_identity(&open.target.thread_id)
            .context("ACP identity")?;
        let resources = owner
            .resident_acp(&open.target.thread_id)?
            .context("ACP resources")?;
        let host = owner.acp_agent_host(
            &identity,
            &resources,
            &profiles,
            fixture.runtime.config_runtime.read()?.config.delegation,
        )?;
        Ok((owner, identity, host))
    }
}

async fn completion(
    resources: &Arc<super::AcpResources>,
    after: u64,
) -> Result<pl_acp::session::Completed> {
    tokio::time::timeout(Duration::from_secs(20), async {
        let session = resources.session()?;
        let mut changed = session.completion_changes();
        loop {
            if let Some(completed) = session.snapshot().await?.last_completed
                && completed.completion_sequence > after
            {
                return Ok(completed);
            }
            changed.changed().await?;
        }
    })
    .await?
}

fn rebuild_native_parent_and_restore_child<'a>(
    fixture: &'a Fixture,
    caller: &'a pl_protocol::AgentThreadIdentity,
    child: &'a pl_protocol::AgentThreadIdentity,
    old_generation: String,
    old_cursor: String,
    old_message_id: String,
) -> futures::future::BoxFuture<'a, Result<()>> {
    Box::pin(async move {
        use crate::studio::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};

        fixture
            .runtime
            .shutdown_runtime()
            .await
            .context("shut down original runtime before reconstruction")?;
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(fixture.home.path().join("studio")),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await
        .context("reload original mixed StudioRuntime")?;
        let result = std::panic::AssertUnwindSafe(async {
            let parent = runtime.ensure_thread_owner(caller.thread_id.as_str()).await
                .context("restore Native parent from mixed public directory")?;
            let owner = runtime.session_of(caller.thread_id.as_str())
                .context("reconstructed Native parent owner")?;
            let resources = owner.native_resources(&parent)?;
            let profiles = runtime.config_runtime.agent_profiles_snapshot()?;
            let selection = crate::studio::delegation::saved(&parent.snapshot())?
                .context("reconstructed parent delegation")?;
            let host = owner.native_agent_host(caller, &resources, &profiles, selection)?;
            let restored_identity = runtime.agent_facility.product_events
                .member_identity(&caller.session_id, &child.agent_id)
                .context("reconstructed public child identity")?;
            assert_eq!(restored_identity.thread_id, child.thread_id);
            assert_eq!(restored_identity.parent_agent_id.as_ref(), Some(&caller.agent_id));
            assert!(owner.resident_acp(child.thread_id.as_str())?.is_none());
            let history = runtime.store.history(caller.thread_id.as_str()).await?;
            let old_receipt = history.message_identity(&old_message_id).await?
                .context("prior durable report survived runtime reconstruction")?;

            let accepted = host.send(call(&host, caller, "runtime-rebuilt-send"), AgentMessage {
                id: "after-runtime-reconstruction".into(),
                target: child.agent_id.to_string(),
                message: "task after full runtime reconstruction".into(),
            }).await.context("restore ACP child after full runtime reconstruction")?;
            assert!(accepted.sequence.is_none());
            let restored = owner.resident_acp(child.thread_id.as_str())?
                .context("ACP child restored by original send owner")?;
            assert_ne!(restored.generation, old_generation);
            let completed = completion(&restored, 0).await?;
            assert_eq!(completed.completion_sequence, 1);
            let stale = wait_report(&host, caller, &child.agent_id, "rebuilt-stale-cursor",
                Some(old_cursor.clone())).await.expect_err("cursor must bind the previous resource generation");
            assert!(stale.to_string().contains("invalid or stale agent report cursor"), "{stale}");
            let latest = wait_report(&host, caller, &child.agent_id, "rebuilt-latest", None).await?;
            assert!(!latest.timed_out && !latest.gap);
            assert_eq!(latest.reports.len(), 1);
            assert_eq!(latest.reports[0]["generation"], restored.generation);
            assert_eq!(latest.reports[0]["completionSequence"], completed.completion_sequence);
            assert_eq!(latest.reports[0]["summary"], completed.summary);
            assert_eq!(latest.reports[0]["result"], serde_json::to_value(&completed.result)?);
            assert!(latest.cursor.is_some());
            assert_ne!(latest.cursor.as_deref(), Some(old_cursor.as_str()));
            let new_message_id = native_inbox_report(&runtime, &owner, caller, child,
                &restored, &completed).await?;
            assert_ne!(new_message_id, old_message_id);
            let new_receipt = history.message_identity(&new_message_id).await?
                .context("new generation durable Native inbox receipt")?;
            assert!(new_receipt.sequence > old_receipt.sequence);
            let retained = history.message_identity(&old_message_id).await?
                .context("new generation cannot replace the previous durable report")?;
            assert_eq!(retained.sequence, old_receipt.sequence);
            assert_eq!(retained.digest, old_receipt.digest);
            eprintln!("full StudioRuntime reconstruction: oldGeneration={old_generation}, newGeneration={}, completionSequence={}, oldMessage={old_message_id}, newMessage={new_message_id}, staleCursorRejected=true, sameProcess=true",
                restored.generation, completed.completion_sequence);

            let closed = host.close(call(&host, caller, "close-rebuilt-child"),
                child.agent_id.as_str(), Default::default()).await?;
            assert!(closed.error.is_none(), "{closed:?}");
            assert!(closed.agents[0].execution_closed);
            assert!(closed.agents[0].worktree_cleanup.is_terminal());
            assert!(owner.resident_acp(child.thread_id.as_str())?.is_none());
            assert!(owner.observed_thread(caller.thread_id.as_str()).is_some());
            Ok(())
        }).catch_unwind().await;
        close_runtime(&runtime, &fixture.workspace.id, result).await
    })
}

#[tokio::test]
async fn native_and_acp_roots_share_real_acp_child_control_and_retirement() -> Result<()> {
    for native in [true, false] {
        let fixture = Fixture::new("replay").await?;
        eprintln!(
            "mixed ACP child fixture: native={native}, home={}",
            fixture.home.path().display()
        );
        let scenario = async {
            save_profile(&fixture)?;
            let (owner, caller, host) = host(&fixture, native).await?;
            let frozen_delegation = host.delegation();
            let current = fixture.runtime.config_runtime.read()?;
            fixture
                .runtime
                .config_runtime
                .update(current.revision, |config| {
                    let mut config = config.clone();
                    config.delegation.mode = pl_protocol::DelegationMode::Automatic;
                    config.delegation.preference = pl_protocol::DelegationPreference::Economy;
                    Ok(config)
                })?;
            hold_peer_open(&fixture)?;
            let spawning = host.spawn(call(&host, &caller, "spawn"), serde_json::from_value::<AgentSpawn>(
            serde_json::json!({"profileId":"acp-child","taskSummary":"Do the task","message":"first task"})
        )?);
            tokio::pin!(spawning);
            tokio::select! {
                result = &mut spawning => anyhow::bail!("spawn settled before peer open gate: {result:?}"),
                result = peer_opening(&fixture) => result?,
            }
            rename_during_open(&fixture, &caller, "during-new-child").await?;
            let result = spawning.await?;
            session_unchanged(&fixture, &caller, "during-new-child", frozen_delegation)?;
            assert!(result.receipt.model.is_none());
            assert!(result.receipt.message_sequence.is_none());
            assert!(
                result.receipt.message_accepted,
                "{:?}",
                result.message_error
            );
            let agent = pl_protocol::AgentId::new(result.receipt.agent_id)?;
            let identity = fixture
                .runtime
                .agent_facility
                .product_events
                .member_identity(&caller.session_id, &agent)
                .context("child identity")?;
            assert_eq!(identity.parent_agent_id.as_ref(), Some(&caller.agent_id));
            assert!(
                owner.observed_thread(identity.thread_id.as_str()).is_none(),
                "ACP cannot create a fake Native Thread"
            );
            let resources = owner
                .resident_acp(identity.thread_id.as_str())?
                .context("ACP child resources")?;
            let first = completion(&resources, 0).await?;
            assert_eq!(first.summary, "actual answer");
            assert_eq!(first.completion_sequence, 1);
            let first_message_id = if native {
                Some(
                    native_inbox_report(
                        &fixture.runtime,
                        &owner,
                        &caller,
                        &identity,
                        &resources,
                        &first,
                    )
                    .await?,
                )
            } else {
                None
            };
            let observed = wait_report(&host, &caller, &agent, "first-wait", None).await?;
            assert!(!observed.timed_out && !observed.gap);
            assert_eq!(observed.reports.len(), 1);
            assert_eq!(observed.reports[0]["generation"], resources.generation);
            assert_eq!(
                observed.reports[0]["completionSequence"],
                first.completion_sequence
            );
            assert_eq!(observed.reports[0]["summary"], first.summary);
            let old_cursor = observed.cursor.context("first ACP report cursor")?;
            let rows = host
                .list(call(&host, &caller, "list"))
                .await
                .context("list after first ACP completion and Native inbox handoff")?;
            let row = rows
                .iter()
                .find(|row| row["id"] == agent.as_str())
                .context("child row")?;
            assert_eq!(row["lastCompleted"]["summary"], "actual answer");
            assert_eq!(row["parentId"], caller.agent_id.as_str());
            assert!(row.get("frozenModel").is_none());
            let send = host
                .send(
                    call(&host, &caller, "send"),
                    AgentMessage {
                        id: "second".into(),
                        target: agent.to_string(),
                        message: "second task".into(),
                    },
                )
                .await?;
            assert!(send.sequence.is_none());
            let second = completion(&resources, first.completion_sequence).await?;
            if native {
                native_inbox_report(
                    &fixture.runtime,
                    &owner,
                    &caller,
                    &identity,
                    &resources,
                    &second,
                )
                .await?;
            }
            assert!(
                host.interrupt(call(&host, &caller, "stop-idle"), agent.as_str())
                    .await
                    .is_err()
            );
            let child_profiles = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
            let child_host =
                owner.acp_agent_host(&identity, &resources, &child_profiles, host.delegation())?;
            assert!(child_host.spawn_profiles().is_empty());
            assert!(
                child_host
                    .list_agent_profiles(call(&child_host, &identity, "query"))
                    .await
                    .is_err()
            );
            let old_instance = resources.instance;
            let old_generation = resources.generation.clone();
            let mut inspection = fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: "business-peer".into(),
                    expected_connection_revision: fixture.revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: Some(identity.thread_id.to_string()),
                    intent: AcpOpenIntent::Load("remote-one".into()),
                })
                .await?;
            assert!(
                inspection.observation.is_some(),
                "UI must receive the retained original observer"
            );
            Fixture::ready(&mut inspection).await?;
            let closed = fixture.runtime.close_acp_session(inspection.target).await?;
            assert!(closed.local_complete, "{closed:?}");
            assert!(
                owner.acp_identity(caller.thread_id.as_str()).is_some(),
                "closing child cannot close root"
            );
            drop(resources);
            let rows = host.list(call(&host, &caller, "cold-list")).await?;
            let row = rows
                .iter()
                .find(|row| row["id"] == agent.as_str())
                .context("cold child")?;
            assert_eq!(row["lifecycle"]["kind"], "cold");
            hold_peer_open(&fixture)?;
            let sending = host.send(
                call(&host, &caller, "cold-send"),
                AgentMessage {
                    id: "cold".into(),
                    target: agent.to_string(),
                    message: "restored task".into(),
                },
            );
            tokio::pin!(sending);
            tokio::select! {
                result = &mut sending => anyhow::bail!("cold send settled before peer open gate: {result:?}"),
                result = peer_opening(&fixture) => result?,
            }
            rename_during_open(&fixture, &caller, "during-restored-child").await?;
            let send = sending.await?;
            session_unchanged(
                &fixture,
                &caller,
                "during-restored-child",
                frozen_delegation,
            )?;
            assert!(send.sequence.is_none());
            let restored = owner
                .resident_acp(identity.thread_id.as_str())?
                .context("restored ACP resources")?;
            assert_ne!(restored.instance, old_instance);
            assert_ne!(restored.generation, old_generation);
            let cold_completed = completion(&restored, 0).await?;
            assert_eq!(
                cold_completed.completion_sequence,
                first.completion_sequence
            );
            let stale = wait_report(
                &host,
                &caller,
                &agent,
                "stale-cursor",
                Some(old_cursor.clone()),
            )
            .await
            .expect_err("a previous resource generation cannot read the new completion");
            assert!(
                stale
                    .to_string()
                    .contains("invalid or stale agent report cursor"),
                "{stale}"
            );
            let observed = wait_report(&host, &caller, &agent, "restored-wait", None).await?;
            assert!(!observed.timed_out && !observed.gap);
            assert_eq!(observed.reports.len(), 1);
            assert_eq!(observed.reports[0]["generation"], restored.generation);
            assert_eq!(
                observed.reports[0]["completionSequence"],
                cold_completed.completion_sequence
            );
            assert_eq!(observed.reports[0]["summary"], cold_completed.summary);
            assert_ne!(observed.cursor.as_deref(), Some(old_cursor.as_str()));
            assert!(observed.cursor.is_some());
            let latest_message_id = if native {
                let new_id = native_inbox_report(
                    &fixture.runtime,
                    &owner,
                    &caller,
                    &identity,
                    &restored,
                    &cold_completed,
                )
                .await?;
                let old_id = first_message_id.context("first Native inbox message identity")?;
                assert_ne!(new_id, old_id);
                assert!(
                    fixture
                        .runtime
                        .store
                        .history(caller.thread_id.as_str())
                        .await?
                        .message_identity(&old_id)
                        .await?
                        .is_some(),
                    "reopening the child erased its prior durable parent report"
                );
                Some(new_id)
            } else {
                None
            };
            eprintln!(
                "ACP resource reconstruction: oldGeneration={old_generation}, newGeneration={}, reusedCompletionSequence={}, staleCursorRejected=true",
                restored.generation, cold_completed.completion_sequence
            );
            assert!(
                child_host
                    .list(call(&child_host, &identity, "stale-host"))
                    .await
                    .is_err()
            );
            let generation = restored.generation.clone();
            drop(restored);
            if let Some(message_id) = latest_message_id {
                rebuild_native_parent_and_restore_child(
                    &fixture,
                    &caller,
                    &identity,
                    generation,
                    observed
                        .cursor
                        .context("restored ACP cursor before runtime reconstruction")?,
                    message_id,
                )
                .await?;
                assert!(
                    host.list(call(&host, &caller, "old-runtime-host"))
                        .await
                        .is_err()
                );
                return Ok(());
            }
            let result = host
                .close(
                    call(&host, &caller, "close"),
                    agent.as_str(),
                    Default::default(),
                )
                .await?;
            assert!(result.error.is_none(), "{result:?}");
            assert!(result.agents[0].execution_closed);
            assert!(result.agents[0].worktree_cleanup.is_terminal());
            assert!(owner.resident_acp(identity.thread_id.as_str())?.is_none());
            assert!(owner.acp_identity(caller.thread_id.as_str()).is_some());
            Ok(())
        };
        eprintln!(
            "mixed child scenario future bytes={}",
            std::mem::size_of_val(&scenario)
        );
        let result = std::panic::AssertUnwindSafe(scenario).catch_unwind().await;
        close_fixture(&fixture, result)
            .await
            .with_context(|| format!("mixed ACP child, native caller={native}"))?;
    }
    Ok(())
}

#[tokio::test]
async fn acp_target_forbidden_arguments_fail_before_membership_or_process_preparation() -> Result<()>
{
    let fixture = Fixture::new("replay").await?;
    let result = std::panic::AssertUnwindSafe(async {
    save_profile(&fixture)?;
    let (owner, caller, host) = host(&fixture, false).await?;
    for field in [
        serde_json::json!({"modelSelection":{"accountId":"ignored","modelId":"ignored"}}),
        serde_json::json!({"writablePaths":[]}),
        serde_json::json!({"reviewTargetAgentId":"ignored"}),
        serde_json::json!({"reviewFeedback":"toExecutor"}),
    ] {
        let mut request = serde_json::json!({"profileId":"acp-child","taskSummary":"No side effect","message":"task"});
        request
            .as_object_mut()
            .unwrap()
            .extend(field.as_object().unwrap().clone());
        assert!(
            host.spawn(
                call(&host, &caller, "invalid"),
                serde_json::from_value(request)?
            )
            .await
            .is_err()
        );
    }
    assert_eq!(host.list(call(&host, &caller, "list")).await
        .context("list ACP root after forbidden spawn requests")?.len(), 1);
    assert!(owner.observed_thread(caller.thread_id.as_str()).is_none());
    let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
    assert_eq!(
        calls.lines().filter(|line| *line == "initialize").count(),
        1
    );
    Ok(())
    }).catch_unwind().await;
    close_fixture(&fixture, result).await
}

#[tokio::test]
async fn acp_root_reads_native_failed_report_from_child_history_and_closes_without_parent_ack()
-> Result<()> {
    use pl_model::config::{AccountConfig, AccountId};
    use pl_model::model::ModelInfo;
    use pl_model::protocol::ProtocolEndpoint;
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step};

    let fixture = Fixture::new("replay").await?;
    let mut provider = None;
    let result = std::panic::AssertUnwindSafe(async {
        provider = Some(FixtureServer::start(vec![Step::prompt(
            Protocol::Chat, "native-failure-task", 0,
            Reply::HttpError {
                status: 400, code: "mixed_native_fixture_failure".into(),
                message: "deliberate isolated Native failure".into(),
            },
        )]).await?);
        let provider = provider.as_ref().unwrap();
        let account_id = AccountId::new("mixed-native-fixture")?;
        let current = fixture.runtime.config_runtime.read()?;
        fixture.runtime.config_runtime.update(current.revision, |config| {
            let mut config = config.clone();
            config.models.accounts.insert(account_id.clone(), AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible("Mixed Native fixture", provider.base_url()),
                vec![ModelInfo::compatible("mixed-native-model")],
            ));
            Ok(config)
        })?;
        fixture.runtime.save_user_agent_profile(
            "save-native-child".into(), fixture.runtime.read_settings()?.config.revision,
            "native-child", &crate::config::UserAgentProfile {
                enabled: true, display_name: "Native child".into(),
                description: "Ordinary native task".into(), when_to_use: "Native report fixture".into(),
                workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
                binding: pl_protocol::AgentBinding::Native(pl_protocol::NativeAgentConfig {
                    route: Some(pl_protocol::studio::NewThreadModelRoute {
                        account_id: account_id.to_string(), model_id: "mixed-native-model".into(), effort: None,
                    }),
                    system_instructions: Some("Execute the ordinary task.".into()),
                }),
            },
        )?;
        let (owner, caller, host) = host(&fixture, false).await?;
        let parent_resources = owner.resident_acp(caller.thread_id.as_str())?.context("ACP parent resources")?;
        let parent_instance = parent_resources.instance;
        let result = host.spawn(call(&host, &caller, "spawn-native"), serde_json::from_value::<AgentSpawn>(
            serde_json::json!({"profileId":"native-child","taskSummary":"Native failure evidence","message":"native-failure-task"})
        )?).await.context("ACP root spawn ordinary Native child")?;
        assert!(result.receipt.message_accepted, "{:?}", result.message_error);
        assert!(result.receipt.model.is_some());
        assert!(result.receipt.message_sequence.is_some());
        let agent = pl_protocol::AgentId::new(result.receipt.agent_id)?;
        let identity = fixture.runtime.agent_facility.product_events
            .member_identity(&caller.session_id, &agent).context("Native child identity")?;
        assert_eq!(identity.parent_agent_id.as_ref(), Some(&caller.agent_id));
        let observed = wait_report(&host, &caller, &agent, "wait-native", None)
            .await.context("ACP root wait_agent reads Native child's source report")?;
        assert!(!observed.timed_out && !observed.gap);
        assert_eq!(observed.reports.len(), 1);
        let report: pl_core::thread::inbox::ThreadMessage = serde_json::from_value(observed.reports[0].clone())?;
        let body: serde_json::Value = serde_json::from_str(report.payload.content())?;
        assert_eq!(body["childId"], identity.thread_id.as_str());
        assert_eq!(body["turn"]["state"]["kind"], "failed");
        assert!(body["review"].is_null(), "ordinary child must not create structured review");
        let turn_id = body["turnId"].as_str().context("original terminal turn identity")?;
        let history = fixture.runtime.store.history(identity.thread_id.as_str()).await?;
        let terminal_sequence = history.terminal_report_sequence(turn_id).await?.context("durable terminal sequence")?;
        assert_eq!(body["commitSequence"], terminal_sequence);
        assert_eq!(report.id, crate::studio::agent_close::terminal_report_id(identity.thread_id.as_str(), terminal_sequence));
        assert_eq!(report.source_id, format!("studio.child:{}", identity.thread_id));
        assert_eq!(history.parent_report(terminal_sequence).await?, Some(report.clone()));
        let child = owner.observed_thread(identity.thread_id.as_str()).context("Native child owner")?;
        assert!(child.snapshot().execution.is_none());
        let saved_items = history.items_for_turn(turn_id).await?;
        assert!(saved_items.iter().any(|item| matches!(item.state(),
            pl_protocol::ThreadItemState::Turn(turn)
                if matches!(turn.state(), pl_protocol::TurnState::Failed(_)))),
            "the child's original failed Turn must remain in its durable history");
        let record = fixture.runtime.store.read_thread(identity.thread_id.as_str()).await?.context("Native child record")?;
        let checkpoint = crate::studio::thread_factory::recovery::load_checkpoint_for_recovery(
            &fixture.runtime.store, &record.into(),
        ).await?.context("Native child's own saved checkpoint")?;
        assert!(checkpoint.state.commit_sequence >= terminal_sequence,
            "the child's own checkpoint must cover the source report commit");
        let protocol = fixture.runtime.agent_facility.product_events
            .thread_snapshot(identity.thread_id.as_str())?.context("Native child projection")?;
        assert_eq!(
            owner.acknowledge_parent_reports(&fixture.runtime.store, &protocol).await?,
            crate::thread_assembler::observation::ParentReportAcknowledgement::Absent,
        );
        assert!(owner.observed_thread(caller.thread_id.as_str()).is_none());
        assert_eq!(owner.resident_acp(caller.thread_id.as_str())?.unwrap().instance, parent_instance);
        assert_eq!(provider.live_status().accepted, 1);
        assert_eq!(provider.live_status().rejected, 0);
        eprintln!("ACP->Native saved failed report: child={}, turn={turn_id}, terminalSequence={terminal_sequence}, messageId={}, cursor={:?}",
            identity.agent_id, report.id, observed.cursor);
        let closed = host.close(call(&host, &caller, "close-native"), agent.as_str(), Default::default()).await?;
        assert!(closed.error.is_none(), "{closed:?}");
        assert!(closed.agents[0].execution_closed);
        assert!(closed.agents[0].worktree_cleanup.is_terminal());
        assert_eq!(history.parent_report(terminal_sequence).await?, Some(report));
        let close_record = fixture.runtime.store.agent_close(identity.thread_id.as_str()).await?.context("durable permanent close")?;
        assert!(close_record.execution_closed && close_record.worktree_cleanup.is_terminal());
        assert!(owner.observed_thread(caller.thread_id.as_str()).is_none());
        assert_eq!(owner.resident_acp(caller.thread_id.as_str())?.unwrap().instance, parent_instance);
        assert!(host.send(call(&host, &caller, "closed-native-send"), AgentMessage {
            id: "after-close".into(), target: agent.to_string(), message: "must not run".into(),
        }).await.is_err());
        Ok(())
    }).catch_unwind().await;
    let provider_cleanup = match provider {
        Some(provider) => provider.shutdown().await.and_then(|report| report.verify()),
        None => Ok(()),
    };
    let result = close_fixture(&fixture, result).await;
    match result {
        Ok(()) => provider_cleanup,
        Err(error) => match provider_cleanup {
            Ok(()) => Err(error),
            Err(cleanup) => {
                Err(error.context(format!("provider shutdown also failed: {cleanup:#}")))
            }
        },
    }
}
