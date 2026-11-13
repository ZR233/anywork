//! ACP business resources; membership and preparation remain owned by SessionRuntime.
mod api;

mod observation;
mod projection;
mod resources;

pub(crate) use api::AcpBusinessOwner;
pub use api::AcpSessionOpen;
pub use observation::{AcpSessionCompletion, AcpSessionObservation};
pub(crate) use resources::{AcpCloseOutcome, AcpResources};

#[cfg(all(test, target_os = "linux"))]
mod mixed_tests {
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

    async fn close_fixture(
        fixture: &Fixture,
        result: std::thread::Result<Result<()>>,
    ) -> Result<()> {
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
            let selection = crate::studio::delegation::saved(&thread.snapshot())?
                .context("Native delegation")?;
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
    async fn acp_target_forbidden_arguments_fail_before_membership_or_process_preparation()
    -> Result<()> {
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
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    //! The fixture is only a strict ACP peer; all admission, IO, SDK state,
    //! publication and process reclamation below use production owners.
    use std::path::PathBuf;
    use std::time::Duration;

    use anyhow::{Context, Result};
    use pl_protocol::studio::*;
    use tokio::time::timeout;

    use crate::acp_transport_fixture::AcpTransportFixture as Fixture;

    #[tokio::test]
    async fn public_launch_failures_distinguish_install_required_from_missing_executable()
    -> Result<()> {
        let fixture = Fixture::new("replay").await?;
        let missing = fixture.home.path().join("nonexistent-private-command");
        for (account_id, template, command) in [
            ("uninstalled-template", Some(AcpProvider::Antigravity), None),
            (
                "missing-command",
                None,
                Some(missing.to_string_lossy().into_owned()),
            ),
        ] {
            fixture.runtime.save_acp_account(UpdateAcpAccountRequest {
                operation_id: format!("save-{account_id}"),
                expected_revision: fixture.runtime.read_settings()?.config.revision,
                expected_document_revision: None,
                account: AcpAccountUpdate {
                    account_id: account_id.into(),
                    name: account_id.into(),
                    enabled: true,
                    command,
                    args: None,
                    template,
                    env: std::collections::BTreeMap::new(),
                },
            })?;
        }
        for (account_id, expected) in [
            (
                "uninstalled-template",
                AcpBusinessFailureKind::InstallRequired,
            ),
            ("missing-command", AcpBusinessFailureKind::MissingExecutable),
        ] {
            let revision = fixture
                .runtime
                .read_settings()?
                .config
                .settings
                .acp_accounts
                .into_iter()
                .find(|account| account.account_id == account_id)
                .context("saved launch definition")?
                .connection_revision;
            let error = match fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: account_id.into(),
                    expected_connection_revision: revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: None,
                    intent: AcpOpenIntent::New,
                })
                .await
            {
                Err(error) => error,
                Ok(_) => anyhow::bail!("invalid launch unexpectedly opened"),
            };
            let failure = error
                .downcast_ref::<AcpBusinessFailure>()
                .context("typed business launch failure")?;
            assert_eq!(failure.kind, expected);
            assert!(failure.rpc_code.is_none());
            assert!(failure.rpc_data.is_none());
            assert!(failure.auth_methods.is_empty());
            assert!(
                !failure
                    .message
                    .contains(&*fixture.home.path().to_string_lossy())
            );
            assert!(
                fixture
                    .runtime
                    .store
                    .directory_members_for_project(&fixture.workspace.id)?
                    .is_empty(),
                "failed launch must not invent a product association"
            );
        }
        assert!(!fixture.home.path().join("pid").exists());
        assert!(!fixture.home.path().join("calls").exists());
        assert!(!fixture.runtime.store.acp_servers_root().exists());
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn factory_stream_publication_prompt_and_real_reclamation() -> Result<()> {
        let fixture = Fixture::new("replay").await?;
        assert!(
            fixture
                .runtime
                .acp_prompt_capabilities_for_thread("missing")
                .await
                .is_err()
        );
        assert!(!fixture.home.path().join("pid").exists());
        let mut open = fixture
            .open_intent(AcpOpenIntent::Load("remote-one".into()))
            .await?;
        let observer = open.observation.as_mut().unwrap();
        let first = timeout(Duration::from_secs(15), observer.recv()).await?;
        assert!(
            matches!(first, Some(AcpSessionEvent::Initialized { .. })),
            "initialize must precede replay: {first:?}"
        );
        let first = timeout(Duration::from_secs(15), observer.recv()).await?;
        assert!(
            matches!(first, Some(AcpSessionEvent::Update { .. })),
            "history must precede Ready: {first:?}"
        );
        Fixture::ready(&mut open).await?;
        let target = open.target.clone();
        assert_eq!(
            fixture
                .runtime
                .acp_prompt_capabilities_for_thread(&target.thread_id)
                .await?,
            pl_acp::session::schema::PromptCapabilities::default()
        );
        assert_ne!(target.session_id, target.agent_id);
        assert_ne!(target.agent_id, target.thread_id);
        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(target.session_id.clone())?)
            .unwrap();
        assert!(
            owner.observed_threads().is_empty(),
            "ACP is never a Native observation"
        );
        let (session, agent) = fixture
            .runtime
            .agent_facility
            .product_events
            .directory_facts(&target.thread_id)
            .unwrap();
        assert!(session.native_mode.is_none());
        assert!(matches!(
            agent.backend,
            pl_protocol::session::AgentBackend::Acp { .. }
        ));
        let native_paths = fixture
            .runtime
            .store
            .paths()
            .session_paths(&fixture.workspace.id, &target.thread_id)?;
        assert!(!native_paths.history_database().exists());
        assert!(!native_paths.session_manifest().exists());
        let reused = fixture
            .runtime
            .open_acp_session(OpenAcpSessionRequest {
                thread_id: Some(target.thread_id.clone()),
                intent: AcpOpenIntent::New,
                account_id: "business-peer".into(),
                expected_connection_revision: fixture.revision,
                workspace_id: fixture.workspace.id.clone(),
            })
            .await?;
        assert_eq!(reused.target, target);
        assert!(reused.observation.is_none());
        let entry = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut disabled = entry.definition;
        disabled.enabled = false;
        fixture.runtime.config_runtime.save_acp_definition(
            fixture.runtime.config_runtime.read()?.revision,
            &disabled,
            Some(entry.document_revision),
        )?;
        let unavailable = fixture
            .runtime
            .list_acp_sessions(target.clone(), ListSessionsRequest::new())
            .await
            .unwrap_err();
        assert_eq!(unavailable.kind, AcpBusinessFailureKind::Unsupported);
        let run = fixture
            .runtime
            .prompt_acp_session(
                target.clone(),
                vec![pl_acp::session::schema::ContentBlock::Text(
                    pl_acp::session::schema::TextContent::new("hello"),
                )],
            )
            .await?;
        loop {
            if let AcpSessionEvent::Completed { completed } =
                open.observation.as_mut().unwrap().recv().await.unwrap()
            {
                assert_eq!(completed.run, run);
                assert!(completed.result.is_ok());
                break;
            }
        }
        let pid = fixture.pid("pid")?;
        let close = fixture.runtime.close_acp_session(target.clone()).await?;
        assert!(close.local_complete, "{close:?}");
        assert!(
            fixture
                .runtime
                .acp_prompt_capabilities_for_thread(&target.thread_id)
                .await
                .is_err()
        );
        assert!(
            !PathBuf::from(format!("/proc/{pid}")).exists(),
            "supervised process must exit"
        );
        let methods = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            methods
                .lines()
                .filter(|method| *method == "initialize")
                .count(),
            1,
            "capability reads must never initialize or reopen a session"
        );
        assert_eq!(
            methods
                .lines()
                .filter(|method| *method == "session/load")
                .count(),
            1
        );
        assert_eq!(
            methods
                .lines()
                .filter(|method| *method == "session/new")
                .count(),
            0
        );
        assert!(
            !methods.lines().any(|method| method == "session/list"),
            "unsupported list must not fallback"
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn auth_failure_preserves_real_guidance_and_no_phantom_catalog() -> Result<()> {
        let fixture = Fixture::new("auth").await?;
        let mut open = fixture.open().await?;
        let failure = timeout(Duration::from_secs(15), async {
            loop {
                if let AcpSessionEvent::Failed { error } = open
                    .observation
                    .as_mut()
                    .unwrap()
                    .recv()
                    .await
                    .context("failure event")?
                {
                    return Ok::<_, anyhow::Error>(error);
                }
            }
        })
        .await??;
        assert_eq!(failure.kind, AcpBusinessFailureKind::Rpc);
        assert_eq!(failure.auth_methods.len(), 1);
        assert_eq!(failure.auth_methods[0].id, "login");
        assert!(
            fixture
                .runtime
                .agent_facility
                .product_events
                .directory_facts(&open.target.thread_id)
                .is_none()
        );
        let pid = fixture.pid("pid")?;
        assert!(!PathBuf::from(format!("/proc/{pid}")).exists());
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn first_prompt_failure_keeps_published_instance_closeable() -> Result<()> {
        let fixture = Fixture::new("prompt-fail").await?;
        let mut open = fixture.open().await?;
        Fixture::ready(&mut open).await?;
        fixture
            .runtime
            .prompt_acp_session(
                open.target.clone(),
                vec![pl_acp::session::schema::ContentBlock::Text(
                    pl_acp::session::schema::TextContent::new("fail"),
                )],
            )
            .await?;
        loop {
            if let AcpSessionEvent::Completed { completed } =
                open.observation.as_mut().unwrap().recv().await.unwrap()
            {
                assert!(completed.result.is_err());
                break;
            }
        }
        assert!(
            fixture
                .runtime
                .acp_session_snapshot(open.target.clone())
                .await?
                .ready
        );
        let original = open.target.clone();
        assert!(
            fixture
                .runtime
                .close_acp_session(open.target)
                .await?
                .local_complete
        );
        let mut reopened = fixture
            .runtime
            .open_acp_session(OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: fixture.revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id: Some(original.thread_id.clone()),
                intent: AcpOpenIntent::Load("remote-one".into()),
            })
            .await?;
        Fixture::ready(&mut reopened).await?;
        assert_eq!(reopened.target.agent_id, original.agent_id);
        assert_ne!(reopened.target.instance, original.instance);
        let stale = fixture
            .runtime
            .interrupt_acp_session(
                original,
                AcpRunId {
                    instance: 1,
                    sequence: 1,
                },
            )
            .await
            .unwrap_err();
        assert_eq!(stale.kind, AcpBusinessFailureKind::Stale);
        assert!(
            fixture
                .runtime
                .close_acp_session(reopened.target)
                .await?
                .local_complete
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn observation_gap_does_not_lose_product_publication_or_remote_identity() -> Result<()> {
        let fixture = Fixture::new("gap").await?;
        let mut open = fixture
            .open_intent(AcpOpenIntent::Load("remote-one".into()))
            .await?;
        let observation = open.observation.as_mut().unwrap();
        timeout(Duration::from_secs(15), open.completion.wait()).await??;
        assert!(matches!(
            observation.recv().await,
            Some(AcpSessionEvent::Gap { .. })
        ));
        let snapshot = fixture
            .runtime
            .acp_session_snapshot(open.target.clone())
            .await?;
        assert_eq!(snapshot.acp_session_id.as_deref(), Some("remote-one"));
        assert!(snapshot.ready);
        let (_, agent) = fixture
            .runtime
            .agent_facility
            .product_events
            .directory_facts(&open.target.thread_id)
            .unwrap();
        let pl_protocol::session::AgentBackend::Acp { reference } = agent.backend else {
            panic!("ACP reference");
        };
        assert_eq!(reference.acp_session_id, "remote-one");
        assert!(
            fixture
                .runtime
                .close_acp_session(open.target)
                .await?
                .local_complete
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn cancelling_close_waiter_keeps_original_preparation_join_and_worker_tree() -> Result<()>
    {
        let fixture = Fixture::new("hang").await?;
        let open = fixture.open().await?;
        timeout(Duration::from_secs(15), async {
            while !fixture.home.path().join("opening").exists() {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await?;
        let pid = fixture.pid("pid")?;
        let child = fixture.pid("child")?;
        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(
                open.target.session_id.clone(),
            )?)
            .unwrap();
        let resources = owner.resident_acp(&open.target.thread_id)?.unwrap();
        let runtime = fixture.runtime.clone();
        let target = open.target.clone();
        let waiter = tokio::spawn(async move { runtime.close_acp_session(target).await });
        timeout(Duration::from_secs(5), async {
            while owner.phase() == crate::session::SessionPhase::Open {
                tokio::task::yield_now().await;
            }
        })
        .await?;
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        // This joins the same retained Session close, not the cancelled request future.
        let report = timeout(Duration::from_secs(15), owner.close_session()).await?;
        if !report.is_empty() {
            timeout(Duration::from_secs(5), async {
                while PathBuf::from(format!("/proc/{pid}")).exists()
                    || PathBuf::from(format!("/proc/{child}")).exists()
                {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await?;
            assert!(
                timeout(Duration::from_secs(5), owner.close_session())
                    .await?
                    .is_empty()
            );
        }
        assert!(!resources.has_obligations());
        assert!(!PathBuf::from(format!("/proc/{pid}")).exists());
        assert!(!PathBuf::from(format!("/proc/{child}")).exists());
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn catalog_write_failure_retains_original_successful_reference_for_cleanup_retry()
    -> Result<()> {
        let fixture = Fixture::new("prompt-fail").await?;
        let catalog = fixture.runtime.store.paths().catalog_file();
        let original = std::fs::read(&catalog).ok();
        if original.is_some() {
            std::fs::remove_file(&catalog)?;
        }
        std::fs::create_dir(&catalog)?;
        let mut open = fixture.open().await?;
        let error = timeout(Duration::from_secs(15), async {
            loop {
                if let AcpSessionEvent::Failed { error } = open
                    .observation
                    .as_mut()
                    .unwrap()
                    .recv()
                    .await
                    .context("publication failure")?
                {
                    return Ok::<_, anyhow::Error>(error);
                }
            }
        })
        .await??;
        assert_eq!(error.kind, AcpBusinessFailureKind::Publication);
        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(
                open.target.session_id.clone(),
            )?)
            .unwrap();
        assert!(
            owner
                .resident_acp(&open.target.thread_id)?
                .unwrap()
                .has_obligations()
        );
        std::fs::remove_dir(&catalog)?;
        if let Some(original) = original {
            std::fs::write(&catalog, original)?;
        }
        assert!(
            fixture
                .runtime
                .close_acp_session(open.target.clone())
                .await?
                .local_complete
        );
        let (_, agent) = fixture
            .runtime
            .agent_facility
            .product_events
            .directory_facts(&open.target.thread_id)
            .unwrap();
        let pl_protocol::session::AgentBackend::Acp { reference } = agent.backend else {
            panic!("ACP reference");
        };
        assert_eq!(reference.acp_session_id, "remote-one");
        let methods = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            methods
                .lines()
                .filter(|method| *method == "session/new")
                .count(),
            1,
            "local repair must not issue a second business open"
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn cold_callers_share_original_publication_success_and_failure() -> Result<()> {
        for fail in [false, true] {
            let fixture = Fixture::new("replay").await?;
            let mut original = fixture.open().await?;
            Fixture::ready(&mut original).await?;
            original.completion.wait().await?;
            fixture
                .runtime
                .close_acp_session(original.target.clone())
                .await?;
            std::fs::write(
                fixture.home.path().join("mode"),
                if fail { "hang-auth" } else { "hang" },
            )?;
            let request = OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: fixture.revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id: Some(original.target.thread_id.clone()),
                intent: AcpOpenIntent::Load("remote-one".into()),
            };
            let (first, second) = tokio::join!(
                fixture.runtime.open_acp_session(request.clone()),
                fixture.runtime.open_acp_session(request),
            );
            let first = first?;
            let second = second?;
            assert_eq!(first.target, second.target);
            assert_ne!(first.target.instance, original.target.instance);
            assert_ne!(first.observation.is_some(), second.observation.is_some());
            timeout(Duration::from_secs(15), async {
                while !fixture.home.path().join("opening").exists() {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await?;
            assert!(
                timeout(Duration::from_millis(20), first.completion.wait())
                    .await
                    .is_err()
            );
            let rename = fixture
                .runtime
                .rename_thread(
                    "rename-during-load".into(),
                    first.target.thread_id.clone(),
                    "renamed during load".into(),
                )
                .await?;
            assert_eq!(rename.thread.title, "renamed during load");
            if !fail {
                // The existing writer's independent archive field must survive the old cold baseline.
                let (base, _) = fixture
                    .runtime
                    .agent_facility
                    .product_events
                    .directory_facts(&first.target.thread_id)
                    .unwrap();
                let mut archived = base.clone();
                archived.archived = true;
                fixture
                    .runtime
                    .agent_facility
                    .product_events
                    .commit_session_update(base, archived)
                    .await?;
            }
            std::fs::write(fixture.home.path().join("release"), "")?;
            let (a, b) = timeout(Duration::from_secs(15), async {
                tokio::join!(first.completion.wait(), second.completion.wait())
            })
            .await?;
            if fail {
                assert_eq!(a.unwrap_err().rpc_code, Some(-32000));
                assert_eq!(b.unwrap_err().rpc_code, Some(-32000));
                assert_eq!(
                    first.completion.wait().await.unwrap_err().rpc_code,
                    Some(-32000)
                );
            } else {
                a?;
                b?;
                second.completion.wait().await?;
                let member = fixture
                    .runtime
                    .agent_facility
                    .product_events
                    .directory_member(&first.target.thread_id)?
                    .unwrap();
                assert_eq!(member.session.title, "renamed during load");
                assert!(member.session.archived);
                assert!(
                    fixture
                        .runtime
                        .close_acp_session(first.target.clone())
                        .await?
                        .local_complete
                );
            }
            let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
            assert_eq!(
                calls.lines().filter(|line| *line == "session/new").count(),
                1
            );
            assert_eq!(
                calls.lines().filter(|line| *line == "session/load").count(),
                1
            );
            fixture.runtime.shutdown_runtime().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn public_acp_tree_archive_restore_delete_preserves_native_and_remote_data() -> Result<()>
    {
        use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};

        let fixture = Fixture::new("replay").await?;
        let mut open = fixture.open().await?;
        Fixture::ready(&mut open).await?;
        let target = open.target.clone();
        assert_ne!(target.session_id, target.thread_id);
        assert_ne!(target.agent_id, target.thread_id);
        let binding = fixture
            .runtime
            .store
            .workspace_identity(&target.thread_id)
            .await?
            .context("real ACP open must persist its workspace binding")?;
        let tree = fixture
            .runtime
            .store
            .read_directory_tree(&target.thread_id)
            .await?;
        assert_eq!(tree.len(), 1);
        assert_eq!(tree[0].root_thread_id, target.thread_id);
        assert_eq!(tree[0].session.session_id, target.session_id);
        assert!(!tree[0].is_native());
        let error = fixture
            .runtime
            .thread_snapshot(&target.thread_id)
            .await
            .unwrap_err();
        assert!(matches!(
            error.downcast_ref::<crate::thread_assembler::ThreadAssemblyError>(),
            Some(crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend { .. })
        ));
        assert!(
            fixture
                .runtime
                .agent_facility
                .product_events
                .thread_snapshot(&target.thread_id)
                .is_err()
        );
        let (_, mut native_session, mut native) =
            crate::studio::store::directory::DirectoryDelta::register_session(
                "native-neighbor".into(),
                &fixture.workspace.id,
                "Native neighbor",
                pl_protocol::ThreadModeId::simple(),
                pl_protocol::ThreadWorkspaceMode::Local,
                fixture.workspace.path.clone(),
                crate::config::ROOT_AGENT_ROUTE_KEY,
            );
        native_session.session_id = "native-session".into();
        // Cross-namespace collision: this neighbor Agent is not the ACP Thread.
        native_session.root_agent_id = target.thread_id.clone();
        native.agent_id = native_session.root_agent_id.clone();
        native.session_id = native_session.session_id.clone();
        let native_delta = crate::studio::store::directory::DirectoryDelta {
            session_upserts: vec![native_session],
            agent_upserts: vec![native.clone()],
            ..Default::default()
        };
        fixture
            .runtime
            .agent_facility
            .product_events
            .commit_directory(native_delta)
            .await?;
        fixture
            .runtime
            .store
            .bind_workspace_identity(&native.thread_id, &binding)
            .await?;
        for agent_id in [&target.agent_id, &native.agent_id] {
            fixture
                .runtime
                .store
                .database()
                .execute_raw(Statement::from_sql_and_values(
                    DatabaseBackend::Sqlite,
                    "INSERT INTO agent_evaluations
             (agent_id,parent_agent_id,account_id,model_id,profile_id,mode,preference,turn_id,
              revision,task_category,outcome,comment,created_at,updated_at)
             VALUES (?,?,'fixture','model','profile','profile','balanced','final',1,
                     'coding','notRated','original evaluation',1,1)",
                    [agent_id.clone().into(), agent_id.clone().into()],
                ))
                .await?;
        }
        let native_history = fixture
            .runtime
            .store
            .session_paths(&fixture.workspace.id, &native.thread_id)?;
        let native_bytes = std::fs::read(native_history.session_manifest())?;
        let archive = fixture
            .runtime
            .archive_thread("archive-acp".into(), target.thread_id.clone())
            .await?
            .context("ACP archive result")?;
        assert_eq!(archive.result.archived_root_id, target.thread_id);
        assert_eq!(
            archive
                .result
                .next_root
                .as_ref()
                .map(|row| row.thread_id.as_str()),
            Some(native.thread_id.as_str())
        );
        assert!(
            fixture
                .runtime
                .store
                .catalog()
                .get_session(&target.session_id)
                .unwrap()
                .archived
        );
        let restored = fixture
            .runtime
            .restore_thread(target.thread_id.clone())
            .await?;
        assert!(!restored.archived);
        assert_eq!(restored.session_id, target.session_id);
        let deleted = fixture
            .runtime
            .delete_thread("delete-acp".into(), target.thread_id.clone())
            .await?
            .context("ACP delete result")?;
        assert_eq!(
            deleted.result.deleted_thread_ids,
            vec![target.thread_id.clone()]
        );
        assert!(
            fixture
                .runtime
                .store
                .workspace_identity(&target.thread_id)
                .await?
                .is_none()
        );
        assert_eq!(
            fixture
                .runtime
                .store
                .workspace_identity(&native.thread_id)
                .await?,
            Some(binding)
        );
        assert!(
            fixture
                .runtime
                .store
                .read_agent_evaluation(&target.agent_id)
                .await?
                .is_none()
        );
        assert!(
            fixture
                .runtime
                .store
                .read_agent_evaluation(&native.agent_id)
                .await?
                .is_some()
        );
        assert!(
            fixture
                .runtime
                .store
                .catalog()
                .agent_by_thread(&target.thread_id)
                .is_none()
        );
        assert!(
            fixture
                .runtime
                .store
                .catalog()
                .get_session(&target.session_id)
                .is_none()
        );
        assert!(
            fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions
                .contains_key("business-peer")
        );
        assert_eq!(
            std::fs::read(native_history.session_manifest())?,
            native_bytes
        );
        let acp_paths = fixture
            .runtime
            .store
            .session_paths(&fixture.workspace.id, &target.thread_id)?;
        assert!(!acp_paths.session_manifest().exists());
        assert!(!acp_paths.history_database().exists());
        assert!(
            std::fs::read_to_string(fixture.home.path().join("calls"))?
                .lines()
                .all(|line| line != "session/delete")
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    struct ColdNativeLeaf {
        root: PathBuf,
        store: crate::studio::StudioStore,
        thread: pl_protocol::Thread,
        usage: std::sync::Mutex<Option<crate::studio::WorkspaceUsageLease>>,
    }

    impl std::fmt::Debug for ColdNativeLeaf {
        fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.debug_struct("ColdNativeLeaf")
                .field("root", &self.root)
                .finish_non_exhaustive()
        }
    }

    impl crate::thread_assembler::StudioActivationFactory for ColdNativeLeaf {
        async fn root_delegation(
            &self,
            _: &crate::thread_assembler::ThreadActivation,
        ) -> Result<pl_protocol::DelegationSettings, crate::thread_assembler::ThreadAssemblyError>
        {
            panic!("cold ACP parent must not become a Native root");
        }

        async fn prepare(
            &self,
            request: crate::thread_assembler::ThreadPreparation,
        ) -> Result<
            crate::thread_assembler::StudioThreadSpec,
            crate::thread_assembler::ThreadAssemblyError,
        > {
            let mut spec = crate::thread_assembler::archive_test_spec(
                request.identity.id().into(),
                request.identity.parent_id().map(str::to_owned),
                &self.root,
            );
            spec.workspace_usage = self.usage.lock().unwrap().take();
            let persistence = crate::studio::storage_fault_test_support::ThreadStorageSink::new(
                self.store.clone(),
                self.thread.clone(),
                None,
            )
            .await
            .map_err(|error| {
                crate::thread_assembler::ThreadAssemblyError::Resource {
                    operation: "open native child history",
                    source: error.into_boxed_dyn_error(),
                }
            })?;
            spec.cold_store = Some(pl_core::thread::cold::ColdStoreHandle::new(persistence));
            Ok(spec)
        }
    }

    #[tokio::test]
    async fn cold_native_child_uses_real_acp_root_identity_and_workspace_without_parent_activation()
    -> Result<()> {
        let fixture = Fixture::new("replay").await?;
        let mut open = fixture.open().await?;
        Fixture::ready(&mut open).await?;
        fixture
            .runtime
            .close_acp_session(open.target.clone())
            .await?;
        let root = fixture
            .runtime
            .store
            .directory_member(&open.target.thread_id)?
            .unwrap();
        let child = crate::studio::records::AgentDirectoryRecord {
            agent_id: "native-leaf-agent".into(),
            thread_id: "native-leaf-thread".into(),
            session_id: root.session.session_id.clone(),
            parent_agent_id: Some(root.agent.agent_id.clone()),
            role: "fixture".into(),
            title: Some("Native child".into()),
            backend: pl_protocol::session::AgentBackend::Native {
                config: pl_protocol::NativeAgentConfig {
                    route: None,
                    system_instructions: None,
                },
                status: pl_protocol::ThreadStatus::Idle,
            },
            explicitly_closed: false,
            created_at: 1,
            updated_at: 1,
        };
        fixture
            .runtime
            .agent_facility
            .product_events
            .commit_directory(crate::studio::store::directory::DirectoryDelta {
                agent_upserts: vec![child.clone()],
                ..Default::default()
            })
            .await?;
        let member = fixture
            .runtime
            .store
            .directory_member(&child.thread_id)?
            .unwrap();
        assert_eq!(
            member.parent_thread_id.as_deref(),
            Some(root.agent.thread_id.as_str())
        );
        assert_eq!(member.root_thread_id, root.agent.thread_id);
        assert_ne!(member.root_thread_id, member.session.session_id);
        let (physical, _) =
            crate::studio::agent_host::workspace_preparation::root_session_workspace_root(
                &fixture.runtime.store,
                &fixture.runtime.agent_facility.worktrees,
                &fixture.runtime.ssh_manager,
                &root,
                &fixture.workspace,
                PathBuf::from(&root.session.workspace_path),
            )
            .await?;
        assert_eq!(physical, dunce::canonicalize(&fixture.workspace.path)?);
        let usage = fixture
            .runtime
            .thread_factory
            .reserve_workspace_use(&child.thread_id, &fixture.workspace)
            .await?;
        fixture
            .runtime
            .thread_factory
            .assign_workspace_use(&usage, &fixture.workspace, &physical)
            .await?;
        let root_identity = pl_protocol::AgentThreadIdentity {
            session_id: pl_protocol::SessionId::new(root.session.session_id.clone())?,
            agent_id: pl_protocol::AgentId::new(root.agent.agent_id.clone())?,
            parent_agent_id: None,
            thread_id: pl_protocol::ThreadId::new(root.agent.thread_id.clone())?,
        };
        let owner = fixture
            .runtime
            .sessions
            .materialize(&root_identity.session_id)?;
        owner.retain_directory_identity(&root_identity)?;
        let leaf = owner
            .activate(
                fixture
                    .runtime
                    .thread_factory
                    .activation(&child.thread_id)?,
                ColdNativeLeaf {
                    root: physical,
                    store: fixture.runtime.store.clone(),
                    thread: fixture
                        .runtime
                        .agent_facility
                        .product_events
                        .thread_snapshot(&child.thread_id)?
                        .unwrap(),
                    usage: std::sync::Mutex::new(Some(usage)),
                },
            )
            .await?;
        assert!(owner.resident_acp(&root.agent.thread_id)?.is_none());
        assert!(owner.observed_thread(&root.agent.thread_id).is_none());
        assert!(owner.observed_thread(&child.thread_id).is_some());
        let report = owner.close_session().await;
        assert!(report.is_empty(), "{report:#?}");
        assert_eq!(
            leaf.snapshot().lifecycle,
            pl_core::thread::ThreadLifecycle::Closed
        );
        let native_paths = fixture
            .runtime
            .store
            .session_paths(&fixture.workspace.id, &child.thread_id)?;
        let manifest = std::fs::read_to_string(native_paths.session_manifest())?;
        assert!(manifest.contains(&root.agent.thread_id));
        let acp_paths = fixture
            .runtime
            .store
            .session_paths(&fixture.workspace.id, &root.agent.thread_id)?;
        assert!(!acp_paths.session_manifest().exists());
        let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            calls.lines().filter(|line| *line == "session/new").count(),
            1
        );
        assert_eq!(
            calls.lines().filter(|line| *line == "session/load").count(),
            0
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn project_archive_preserves_distinct_acp_session_namespace() -> Result<()> {
        let fixture = Fixture::new("replay").await?;
        let mut open = fixture.open().await?;
        Fixture::ready(&mut open).await?;
        assert_ne!(open.target.session_id, open.target.thread_id);
        let pid = fixture.pid("pid")?;
        assert!(
            fixture
                .runtime
                .archive_project(&fixture.workspace.id)
                .await?
                .is_some()
        );
        let session = fixture
            .runtime
            .store
            .catalog()
            .get_session(&open.target.session_id)
            .unwrap();
        assert!(session.archived);
        assert!(!PathBuf::from(format!("/proc/{pid}")).exists());
        assert!(PathBuf::from(&fixture.workspace.path).is_dir());
        assert!(
            fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions
                .contains_key("business-peer")
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }

    #[tokio::test]
    async fn project_archive_captures_unpublished_acp_preparation_and_real_worker_tree()
    -> Result<()> {
        let fixture = Fixture::new("hang").await?;
        let open = fixture.open().await?;
        timeout(Duration::from_secs(15), async {
            while !fixture.home.path().join("opening").exists() {
                tokio::time::sleep(Duration::from_millis(10)).await;
            }
        })
        .await?;
        assert!(
            fixture
                .runtime
                .store
                .catalog()
                .agent_by_thread(&open.target.thread_id)
                .is_none()
        );
        let pid = fixture.pid("pid")?;
        let child = fixture.pid("child")?;
        let first = timeout(
            Duration::from_secs(15),
            fixture.runtime.archive_project(&fixture.workspace.id),
        )
        .await?;
        if first.is_err() {
            // A real Pending acknowledgement retains the original owner; no new process is started.
            timeout(Duration::from_secs(15), async {
                while PathBuf::from(format!("/proc/{pid}")).exists()
                    || PathBuf::from(format!("/proc/{child}")).exists()
                {
                    tokio::time::sleep(Duration::from_millis(10)).await;
                }
            })
            .await?;
            assert!(
                fixture
                    .runtime
                    .archive_project(&fixture.workspace.id)
                    .await?
                    .is_some()
            );
        } else {
            assert!(first?.is_some());
        }
        assert!(open.completion.wait().await.is_err());
        assert!(!PathBuf::from(format!("/proc/{pid}")).exists());
        assert!(!PathBuf::from(format!("/proc/{child}")).exists());
        assert!(
            fixture
                .runtime
                .store
                .catalog()
                .agent_by_thread(&open.target.thread_id)
                .is_none()
        );
        assert!(
            fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: "business-peer".into(),
                    expected_connection_revision: fixture.revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: None,
                    intent: AcpOpenIntent::New,
                })
                .await
                .is_err()
        );
        let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            calls
                .lines()
                .filter(|method| *method == "session/new")
                .count(),
            1
        );
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }
}
