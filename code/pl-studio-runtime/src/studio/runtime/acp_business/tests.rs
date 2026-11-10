//! The fixture is only a strict ACP peer; all admission, IO, SDK state,
//! publication and process reclamation below use production owners.
use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, Result};
use pl_protocol::studio::*;
use tokio::time::timeout;

use crate as studio_runtime;

#[path = "../../../../tests/support/acp_transport_fixture.rs"]
mod acp_transport_fixture;
use acp_transport_fixture::AcpTransportFixture as Fixture;

#[tokio::test]
async fn public_launch_failures_distinguish_install_required_from_missing_executable() -> Result<()>
{
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
    let mut open = fixture
        .open_intent(AcpOpenIntent::Load("remote-one".into()))
        .await?;
    let observer = open.observation.as_mut().unwrap();
    let first = timeout(Duration::from_secs(15), observer.recv()).await?;
    assert!(
        matches!(first, Some(AcpSessionEvent::Update { .. })),
        "history must precede Ready: {first:?}"
    );
    Fixture::ready(&mut open).await?;
    let target = open.target.clone();
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
    let close = fixture.runtime.close_acp_session(target).await?;
    assert!(close.local_complete, "{close:?}");
    assert!(
        !PathBuf::from(format!("/proc/{pid}")).exists(),
        "supervised process must exit"
    );
    let methods = std::fs::read_to_string(fixture.home.path().join("calls"))?;
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
async fn cancelling_close_waiter_keeps_original_preparation_join_and_worker_tree() -> Result<()> {
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
async fn public_acp_tree_archive_restore_delete_preserves_native_and_remote_data() -> Result<()> {
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
    ) -> Result<pl_protocol::DelegationSettings, crate::thread_assembler::ThreadAssemblyError> {
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
        .map_err(
            |error| crate::thread_assembler::ThreadAssemblyError::Resource {
                operation: "open native child history",
                source: error.into_boxed_dyn_error(),
            },
        )?;
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
async fn project_archive_captures_unpublished_acp_preparation_and_real_worker_tree() -> Result<()> {
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
