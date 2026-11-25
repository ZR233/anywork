//! Real collaboration paths; only the external ACP peer is replaced.
use crate::acp_transport_fixture::AcpTransportFixture as Fixture;
use crate::thread_assembler::agent_wait::{WaitAgentRequest, WaitAgentResult};
use crate::thread_assembler::{AgentHost, SessionRuntime};
use crate::{AcpOpenIntent, OpenAcpSessionRequest};
use anyhow::{Context, Result};
use futures::FutureExt;
use pl_tool::collaboration::control::AgentCallContext;
use pl_tool::collaboration::thread::{AgentControlHost, AgentMessage, AgentSpawn};
use std::sync::Arc;
use std::time::Duration;

async fn peer_opening(fixture: &Fixture) -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        while !tokio::fs::try_exists(fixture.home.path().join("opening")).await? {
            tokio::task::yield_now().await;
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
    caller: &crate::AgentThreadIdentity,
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
    caller: &crate::AgentThreadIdentity,
    title: &str,
    delegation: crate::DelegationSettings,
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
    Ok(())
}

async fn native_inbox_report(
    runtime: &crate::studio::StudioRuntime,
    caller: &crate::AgentThreadIdentity,
    child: &crate::AgentThreadIdentity,
    resources: &super::AcpResources,
    completed: &pl_acp::session::Completed,
) -> Result<String> {
    let expected_id = format!(
        "studio.acp.{}:{}:{}:{}",
        child.agent_id.as_str().len(),
        child.agent_id,
        resources.generation,
        completed.completion_sequence
    );
    let text = serde_json::to_string(&serde_json::json!({
        "agentId": child.agent_id, "backend": "acp", "generation": resources.generation,
        "run": {"instance": completed.run.instance, "sequence": completed.run.sequence},
        "completionSequence": completed.completion_sequence,
        "result": completed.result.as_ref().map_err(|error| anyhow::anyhow!("ACP completion failed: {error}"))?,
        "summary": completed.summary, "truncated": completed.truncated,
    }))?;
    let expected = pl_core::thread::inbox::ThreadMessage {
        kind: pl_core::context::AgentMessageKind::Report,
        id: expected_id.clone(),
        source_id: format!("agent:{}", child.thread_id),
        payload: pl_core::context::OpaquePayload::text(text.clone()),
        context: vec![pl_core::context::ContextContent::Text { text: text.into() }],
    };
    let parent = runtime
        .ensure_thread_owner(caller.thread_id.as_str())
        .await?;
    let mut changes = parent.subscribe();
    // ACP completion reaches the Native recipient's ordinary inbox. A child report has no
    // public parent-message original: verify its actual acceptance, even if already consumed.
    tokio::time::timeout(Duration::from_secs(20), async {
        while let Some(snapshot) = changes.next().await {
            let pending = snapshot
                .inbox
                .iter()
                .filter(|entry| entry.message.id == expected_id)
                .collect::<Vec<_>>();
            let consumed = snapshot
                .consumed_message_identities
                .iter()
                .filter(|entry| entry.id == expected_id)
                .collect::<Vec<_>>();
            if pending.is_empty() && consumed.is_empty() {
                continue;
            }
            assert_eq!(
                pending.len() + consumed.len(),
                1,
                "duplicate stable ACP report"
            );
            if let Some(record) = pending.first() {
                assert_eq!(record.message, expected);
                assert!(record.sequence > 0);
            } else {
                assert_eq!(consumed[0].digest, expected.digest());
                assert!(consumed[0].sequence > 0);
            }
            return Ok::<_, anyhow::Error>(expected_id);
        }
        anyhow::bail!("Native recipient closed before accepting the ACP result")
    })
    .await
    .context("Native inbox did not accept the exact ACP result")?
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
                    let _ = resources.close().await;
                }
            }
            let _ = owner.close_session().await;
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
            let _ = cleanup;
            std::panic::resume_unwind(panic)
        }
    }
}

fn call(_host: &AgentHost, caller: &crate::AgentThreadIdentity, id: &str) -> AgentCallContext {
    AgentCallContext {
        caller: caller.agent_id.clone(),
        call_id: id.into(),
        cancellation: Default::default(),
    }
}

fn wait_report<'a>(
    host: &'a AgentHost,
    caller: &crate::AgentThreadIdentity,
    target: &crate::AgentId,
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
        None,
        "acp-child",
        &crate::config::UserAgentProfile {
            enabled: true,
            display_name: "ACP child".into(),
            description: "Ordinary ACP task".into(),
            when_to_use: "External coding task".into(),
            binding: crate::AgentBinding::Acp(crate::AcpAgentConfig {
                account_id: "business-peer".into(),
            }),
            workspace_mode: crate::AgentWorkspaceMode::Directory,
        },
    )?;
    Ok(())
}

async fn host(
    fixture: &Fixture,
    native: bool,
) -> Result<(SessionRuntime, crate::AgentThreadIdentity, AgentHost)> {
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
            .get(&crate::SessionId::new(open.target.session_id)?)
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
    .await
    .context("wait for the next ACP completion")?
}

fn rebuild_native_parent_and_restore_child<'a>(
    fixture: &'a Fixture,
    caller: &'a crate::AgentThreadIdentity,
    child: &'a crate::AgentThreadIdentity,
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
            let parent = runtime
                .ensure_thread_owner(caller.thread_id.as_str())
                .await
                .context("restore Native parent from mixed public directory")?;
            let owner = runtime
                .session_of(caller.thread_id.as_str())
                .context("reconstructed Native parent owner")?;
            let resources = owner.native_resources(&parent)?;
            let profiles = runtime.config_runtime.agent_profiles_snapshot()?;
            let selection = crate::studio::delegation::saved(&parent.snapshot())?
                .context("reconstructed parent delegation")?;
            let host = owner.native_agent_host(caller, &resources, &profiles, selection)?;
            let restored_identity = runtime
                .agent_facility
                .product_events
                .member_identity(&caller.session_id, &child.agent_id)
                .context("reconstructed public child identity")?;
            assert_eq!(restored_identity.thread_id, child.thread_id);
            assert_eq!(
                restored_identity.parent_agent_id.as_ref(),
                Some(&caller.agent_id)
            );
            assert!(owner.resident_acp(child.thread_id.as_str())?.is_none());
            let accepted = host
                .send(
                    call(&host, caller, "runtime-rebuilt-send"),
                    AgentMessage {
                        id: "after-runtime-reconstruction".into(),
                        target: child.agent_id.to_string(),
                        message: "task after full runtime reconstruction".into(),
                    },
                )
                .await
                .context("restore ACP child after full runtime reconstruction")?;
            assert!(accepted.sequence.is_none());
            let restored = owner
                .resident_acp(child.thread_id.as_str())?
                .context("ACP child restored by original send owner")?;
            assert_ne!(restored.generation, old_generation);
            let completed = completion(&restored, 0).await?;
            assert_eq!(completed.completion_sequence, 1);
            let stale = wait_report(
                &host,
                caller,
                &child.agent_id,
                "rebuilt-stale-cursor",
                Some(old_cursor.clone()),
            )
            .await
            .expect_err("cursor must bind the previous resource generation");
            assert!(
                stale
                    .to_string()
                    .contains("invalid or stale agent report cursor"),
                "{stale}"
            );
            let latest =
                wait_report(&host, caller, &child.agent_id, "rebuilt-latest", None).await?;
            assert!(!latest.timed_out && !latest.gap);
            assert_eq!(latest.reports.len(), 1);
            assert_eq!(latest.reports[0]["generation"], restored.generation);
            assert_eq!(
                latest.reports[0]["completionSequence"],
                completed.completion_sequence
            );
            assert_eq!(latest.reports[0]["summary"], completed.summary);
            assert_eq!(
                latest.reports[0]["result"],
                serde_json::to_value(&completed.result)?
            );
            assert!(latest.cursor.is_some());
            assert_ne!(latest.cursor.as_deref(), Some(old_cursor.as_str()));
            let new_message_id =
                native_inbox_report(&runtime, caller, child, &restored, &completed).await?;
            assert_ne!(new_message_id, old_message_id);
            let closed = host
                .close(
                    call(&host, caller, "close-rebuilt-child"),
                    child.agent_id.as_str(),
                    Default::default(),
                )
                .await?;
            assert!(closed.error.is_none(), "{closed:?}");
            assert!(closed.agents[0].execution_closed);
            assert!(closed.agents[0].worktree_cleanup.is_terminal());
            assert!(owner.resident_acp(child.thread_id.as_str())?.is_none());
            assert!(owner.observed_thread(caller.thread_id.as_str()).is_some());
            Ok(())
        })
        .catch_unwind()
        .await;
        close_runtime(&runtime, &fixture.workspace.id, result).await
    })
}

async fn with_mixed_root(
    native: bool,
    check: impl for<'a> FnOnce(
        &'a Fixture,
        SessionRuntime,
        crate::AgentThreadIdentity,
        AgentHost,
    ) -> futures::future::BoxFuture<'a, Result<()>>,
) -> Result<()> {
    let fixture = Fixture::new("replay").await?;
    let scenario = async {
        save_profile(&fixture)?;
        // Native preparation has a deep future. Keep it out of the combined fixture layout.
        let (owner, caller, host) = Box::pin(host(&fixture, native)).await?;
        check(&fixture, owner, caller, host).await
    };
    let result = std::panic::AssertUnwindSafe(scenario).catch_unwind().await;
    close_fixture(&fixture, result)
        .await
        .with_context(|| format!("mixed ACP child, native caller={native}"))
}

fn assert_root_resident(owner: &SessionRuntime, caller: &crate::AgentThreadIdentity, native: bool) {
    if native {
        assert!(
            owner.observed_thread(caller.thread_id.as_str()).is_some(),
            "closing child also closed Native root"
        );
    } else {
        assert!(
            owner.acp_identity(caller.thread_id.as_str()).is_some(),
            "closing child also closed ACP root"
        );
    }
}

async fn spawn_child(
    fixture: &Fixture,
    owner: &SessionRuntime,
    caller: &crate::AgentThreadIdentity,
    host: &AgentHost,
    rename_while_opening: bool,
) -> Result<(
    crate::AgentThreadIdentity,
    Arc<super::AcpResources>,
    pl_acp::session::Completed,
)> {
    if rename_while_opening {
        hold_peer_open(fixture)?;
    }
    let spawning = host.spawn(call(host, caller, "spawn"), serde_json::from_value::<AgentSpawn>(
        serde_json::json!({"profileId":"acp-child","taskSummary":"Do the task","message":"first task"})
    )?);
    tokio::pin!(spawning);
    if rename_while_opening {
        tokio::select! {
            result = &mut spawning => anyhow::bail!("spawn settled before peer open gate: {result:?}"),
            result = peer_opening(fixture) => result?,
        }
        rename_during_open(fixture, caller, "during-new-child").await?;
    }
    let result = spawning.await?;
    assert!(result.receipt.model.is_none());
    assert!(result.receipt.message_sequence.is_none());
    assert!(
        result.receipt.message_accepted,
        "{:?}",
        result.message_error
    );
    let agent = crate::AgentId::new(result.receipt.agent_id)?;
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
    Ok((identity, resources, first))
}

#[tokio::test]
async fn native_and_acp_roots_control_and_observe_new_acp_children() -> Result<()> {
    for native in [true, false] {
        with_mixed_root(native, |fixture, owner, caller, host| {
            Box::pin(async move {
                let frozen_delegation = host.delegation();
                change_delegation_defaults(fixture)?;
                let (identity, resources, first) =
                    spawn_child(fixture, &owner, &caller, &host, true).await?;
                let agent = identity.agent_id.clone();
                session_unchanged(fixture, &caller, "during-new-child", frozen_delegation)?;
                if native {
                    native_inbox_report(&fixture.runtime, &caller, &identity, &resources, &first)
                        .await?;
                }
                let observed = wait_report(&host, &caller, &agent, "first-wait", None).await?;
                assert!(!observed.timed_out && !observed.gap);
                assert_eq!(observed.reports.len(), 1);
                assert_eq!(observed.reports[0]["generation"], resources.generation);
                assert_eq!(
                    observed.reports[0]["completionSequence"],
                    first.completion_sequence
                );
                assert_eq!(observed.reports[0]["summary"], first.summary);
                assert!(observed.cursor.is_some());
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
                    native_inbox_report(&fixture.runtime, &caller, &identity, &resources, &second)
                        .await?;
                }
                assert!(
                    host.interrupt(call(&host, &caller, "stop-idle"), agent.as_str())
                        .await
                        .is_err()
                );
                let child_profiles = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
                let child_host = owner.acp_agent_host(
                    &identity,
                    &resources,
                    &child_profiles,
                    host.delegation(),
                )?;
                assert!(child_host.spawn_profiles().is_empty());
                assert!(
                    child_host
                        .list_agent_profiles(call(&child_host, &identity, "query"))
                        .await
                        .is_err()
                );
                Ok(())
            })
        })
        .await?;
    }
    Ok(())
}

fn change_delegation_defaults(fixture: &Fixture) -> Result<()> {
    let current = fixture.runtime.config_runtime.read()?;
    fixture
        .runtime
        .config_runtime
        .update(current.revision, |config| {
            let mut config = config.clone();
            config.delegation.mode = crate::DelegationMode::Automatic;
            config.delegation.preference = crate::DelegationPreference::Economy;
            Ok(config)
        })?;
    Ok(())
}

#[tokio::test]
async fn native_and_acp_roots_restore_cold_children_with_new_report_generation() -> Result<()> {
    for native in [true, false] {
        with_mixed_root(native, |fixture, owner, caller, host| Box::pin(async move {
            let (identity, resources, first) = spawn_child(fixture, &owner, &caller, &host, false).await?;
            let agent = identity.agent_id.clone();
            let frozen_delegation = host.delegation();
            change_delegation_defaults(fixture)?;
            let prior = wait_report(&host, &caller, &agent, "first-wait", None).await?;
            let old_cursor = prior.cursor.context("first ACP report cursor")?;
            let first_message_id = if native {
                Some(native_inbox_report(&fixture.runtime, &caller, &identity, &resources, &first).await?)
            } else {
                None
            };
            let child_profiles = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
            let child_host = owner.acp_agent_host(&identity, &resources, &child_profiles, host.delegation())?;
            let old_instance = resources.instance;
            let old_generation = resources.generation.clone();
            let mut inspection = fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: "business-peer".into(),
                    expected_connection_revision: fixture.revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: Some(identity.thread_id.to_string()),
                    intent: AcpOpenIntent::Load {
                        session_id: "remote-one".into(),
                    },
                })
                .await?;
            assert!(
                inspection.observation.is_some(),
                "UI must receive the retained original observer"
            );
            Fixture::ready(&mut inspection).await?;
            let closed = fixture.runtime.close_acp_session(inspection.target).await?;
            assert!(closed.local_complete, "{closed:?}");
            assert_root_resident(&owner, &caller, native);
            drop(resources);
            let rows = host.list(call(&host, &caller, "cold-list")).await?;
            let row = rows
                .iter()
                .find(|row| row["id"] == agent.as_str())
                .context("cold child")?;
            assert_eq!(row["lifecycle"]["kind"], "cold");
            hold_peer_open(fixture)?;
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
                result = peer_opening(fixture) => result?,
            }
            rename_during_open(fixture, &caller, "during-restored-child").await?;
            let send = sending.await?;
            session_unchanged(
                fixture,
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
            if let Some(first_message_id) = first_message_id {
                let message_id = native_inbox_report(&fixture.runtime, &caller, &identity, &restored, &cold_completed).await?;
                assert_ne!(message_id, first_message_id);
            }
            assert!(
                child_host
                    .list(call(&child_host, &identity, "stale-host"))
                    .await
                    .is_err()
            );
            drop(restored);
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
            assert_root_resident(&owner, &caller, native);
            Ok(())
        })).await?;
    }
    Ok(())
}

#[tokio::test]
async fn rebuilt_native_runtime_restores_acp_child_and_delivers_a_new_inbox_report() -> Result<()> {
    with_mixed_root(true, |fixture, owner, caller, host| {
        Box::pin(async move {
            let (identity, resources, first) =
                spawn_child(fixture, &owner, &caller, &host, false).await?;
            let message_id =
                native_inbox_report(&fixture.runtime, &caller, &identity, &resources, &first)
                    .await?;
            let report =
                wait_report(&host, &caller, &identity.agent_id, "before-restart", None).await?;
            let cursor = report
                .cursor
                .context("ACP cursor before runtime reconstruction")?;
            let generation = resources.generation.clone();
            drop(resources);
            rebuild_native_parent_and_restore_child(
                fixture, &caller, &identity, generation, cursor, message_id,
            )
            .await?;
            assert!(
                host.list(call(&host, &caller, "old-runtime-host"))
                    .await
                    .is_err()
            );
            Ok(())
        })
    })
    .await
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
    use pl_model::model::ModelDefinition;
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
            pl_model::protocol::providers::openai::compatible_endpoint("Mixed Native fixture", provider.base_url()),
            vec![ModelDefinition::compatible("mixed-native-model")],
        ));
        Ok(config)
    })?;
    fixture.runtime.save_user_agent_profile(
        "save-native-child".into(), None,
        "native-child", &crate::config::UserAgentProfile {
            enabled: true, display_name: "Native child".into(),
            description: "Ordinary native task".into(), when_to_use: "Native report fixture".into(),
            workspace_mode: crate::AgentWorkspaceMode::Directory,
            binding: crate::AgentBinding::Native(crate::NativeAgentConfig {
                route: Some(crate::NewThreadModelRoute {
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
    let agent = crate::AgentId::new(result.receipt.agent_id)?;
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
    let reader = fixture
        .runtime
        .open_history_reader(
            identity.thread_id.as_str(),
            crate::history::HISTORY_PROTOCOL_VERSION,
        )
        .await?;
    let terminal_sequence = body["commitSequence"]
        .as_u64()
        .context("durable terminal sequence")?;
    assert_eq!(body["commitSequence"], terminal_sequence);
    assert_eq!(report.id, crate::studio::agent_close::terminal_report_id(identity.thread_id.as_str(), terminal_sequence));
    assert_eq!(report.source_id, format!("studio.child:{}", identity.thread_id));
    let child = owner.observed_thread(identity.thread_id.as_str()).context("Native child owner")?;
    assert!(child.snapshot().execution.is_none());
    let turn_page = reader
        .events_page(
            crate::history::HistoryEventsQuery::Turn {
                turn_id: turn_id.to_owned(),
            },
            None,
            None,
            crate::history::HistoryDemand {
                max_rows: 16,
                max_bytes: 1024 * 1024,
            },
        )
        .await?;
    assert!(
        turn_page.entries.iter().any(|entry| {
            entry.row_scope == Some(crate::history::HistoryBusinessRowScope::Turn)
                && matches!(
                    crate::history::body::decode_business_head_from_record(entry),
                    Ok(crate::history::HistoryBusinessRowHead::Turn(
                        crate::history::HistoryTurnHead {
                            state: crate::history::HistoryTurnState::Failed,
                            ..
                        }
                    ))
                )
        }),
        "the child's original failed Turn remains durable"
    );
    let protocol = fixture.runtime.agent_facility.product_events
        .thread_snapshot(identity.thread_id.as_str())?.context("Native child projection")?;
    assert_eq!(
        owner.acknowledge_parent_reports(&protocol).await?,
        crate::thread_assembler::observation::ParentReportAcknowledgement::Absent,
    );
    assert!(owner.observed_thread(caller.thread_id.as_str()).is_none());
    assert_eq!(owner.resident_acp(caller.thread_id.as_str())?.unwrap().instance, parent_instance);
    assert_eq!(provider.live_status().accepted, 1);
    assert_eq!(provider.live_status().rejected, 0);
    let closed = host.close(call(&host, &caller, "close-native"), agent.as_str(), Default::default()).await?;
    assert!(closed.error.is_none(), "{closed:?}");
    assert!(closed.agents[0].execution_closed);
    assert!(closed.agents[0].worktree_cleanup.is_terminal());
    let record = fixture.runtime.store.read_thread(identity.thread_id.as_str()).await?.context("Native child record")?;
    let current = crate::studio::thread_factory::recovery::load_current_for_recovery(
        &fixture.runtime.store, &record.into(),
    ).await?.context("Native child's own final saved current")?;
    assert_eq!(current.state.lifecycle, pl_core::thread::ThreadLifecycle::Closed);
    let close_record = fixture.runtime.store.agent_close(identity.thread_id.as_str()).await?.context("durable permanent close")?;
    assert!(close_record.execution_closed && close_record.worktree_cleanup.is_terminal());
    assert!(owner.observed_thread(caller.thread_id.as_str()).is_none());
    assert_eq!(owner.resident_acp(caller.thread_id.as_str())?.unwrap().instance, parent_instance);
    assert!(host.send(call(&host, &caller, "closed-native-send"), AgentMessage {
        id: "after-close".into(), target: agent.to_string(), message: "must not run".into(),
    }).await.is_err());
    // The ACP root is not a Native session entry. Once its Native child is fully
    // closed, release the shared connection explicitly and prove the owner has no
    // descendant obligation left before fixture-wide runtime shutdown.
    owner.close(identity.thread_id.as_str()).await?;
    assert!(owner.observed_thread(identity.thread_id.as_str()).is_none());
    let parent_close = parent_resources.close().await;
    assert!(
        parent_close.local_complete,
        "ACP root cleanup retained local resources: {parent_close:?}"
    );
    assert!(parent_close.driver_error.is_none(), "{parent_close:?}");
    assert!(owner.close_session().await.is_empty());
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
