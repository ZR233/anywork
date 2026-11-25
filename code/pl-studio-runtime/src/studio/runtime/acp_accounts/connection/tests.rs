use super::super::test_support::{wait_account_state, wait_retired};
use super::*;
use crate::acp_transport_fixture::AcpTransportFixture as Fixture;
use crate::protocol::*;
use crate::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
use anyhow::Result;
use futures::FutureExt;
use std::time::Duration;

async fn with_cleanup(
    runtime: &StudioRuntime,
    work: impl std::future::Future<Output = Result<()>>,
) -> Result<()> {
    let result = std::panic::AssertUnwindSafe(work).catch_unwind().await;
    let cleanup = runtime.shutdown_runtime().await.map(|_| ());
    match result {
        Ok(Ok(())) => cleanup,
        Ok(Err(error)) => match cleanup {
            Ok(()) => Err(error),
            Err(cleanup) => Err(error.context(format!("account cleanup also failed: {cleanup:#}"))),
        },
        Err(panic) => {
            if let Err(error) = cleanup {
                eprintln!("account cleanup after panic failed: {error:#}");
            }
            std::panic::resume_unwind(panic)
        }
    }
}

async fn marker(path: &std::path::Path) {
    tokio::time::timeout(Duration::from_secs(15), async {
        while !path.exists() {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("synthetic peer reached marker");
}

// Count real anonymous image FDs, not cached Arc entries. Never read pipes, sockets,
// or unrelated files: only deleted regular files of the synthetic payload's size.
fn image_fds(payload: &[u8]) -> Result<usize> {
    let mut count = 0;
    for entry in std::fs::read_dir("/proc/self/fd")? {
        let path = entry?.path();
        let Ok(target) = std::fs::read_link(&path) else {
            continue;
        };
        if !target
            .as_os_str()
            .as_encoded_bytes()
            .ends_with(b" (deleted)")
        {
            continue;
        }
        let Ok(metadata) = std::fs::metadata(&path) else {
            continue;
        };
        if metadata.is_file()
            && metadata.len() == payload.len() as u64
            && std::fs::read(&path).is_ok_and(|bytes| bytes == payload)
        {
            count += 1;
        }
    }
    Ok(count)
}

#[tokio::test]
async fn repair_stdio_history_reuses_one_physical_image_and_isolates_sessions() -> Result<()> {
    use sha2::{Digest, Sha256};
    let bundle = tempfile::tempdir()?;
    let target = format!("{}-unknown-linux-gnu", std::env::consts::ARCH);
    let directory = bundle.path().join(&target);
    std::fs::create_dir(&directory)?;
    // Native ELF fixture only; the synthetic peer never executes this helper.
    let mut payload = std::fs::read("/usr/bin/true")?;
    payload.extend_from_slice(bundle.path().as_os_str().as_encoded_bytes());
    let archive = directory.join("pl-studio-mcp.zst");
    std::fs::write(&archive, zstd::bulk::compress(&payload, 1)?)?;
    std::fs::write(
        directory.join("pl-studio-mcp.metadata.json"),
        serde_json::to_vec(
            &serde_json::json!({"target":target, "sha256":hex::encode(Sha256::digest(&payload))}),
        )?,
    )?;
    let fixture = Fixture::with_mcp_source(
        "mcp-stdio",
        crate::HostMcpSource::Bundled(bundle.path().into()),
    )
    .await?;
    with_cleanup(&fixture.runtime, async {
        assert_eq!(image_fds(&payload)?, 0);
        let (first, second) = tokio::join!(fixture.open(), fixture.open());
        let mut first = first?;
        let mut anchor = second?;
        let (a, b) = tokio::join!(Fixture::ready(&mut first), Fixture::ready(&mut anchor));
        a?;
        b?;
        first.completion.wait().await?;
        anchor.completion.wait().await?;
        let pid = fixture.pid("pid")?;
        let first_owner = fixture
            .runtime
            .sessions
            .get(&crate::SessionId::new(first.target.session_id.clone())?)
            .expect("first session is resident");
        let first_resources = first_owner
            .resident_acp(&first.target.thread_id)?
            .expect("first ACP member is resident");
        assert_eq!(image_fds(&payload)?, 1);
        assert!(
            fixture
                .runtime
                .close_acp_session(first.target)
                .await?
                .local_complete
        );
        assert!(
            first_resources.cancellation.is_cancelled(),
            "close revokes only this member's domain qualification"
        );
        // Further sessions must reuse the prepared image even after its source disappears.
        std::fs::remove_file(archive)?;
        for _ in 0..8 {
            let mut next = fixture.open().await?;
            Fixture::ready(&mut next).await?;
            next.completion.wait().await?;
            assert_eq!(fixture.pid("pid")?, pid);
            assert_eq!(image_fds(&payload)?, 1);
            assert!(
                fixture
                    .runtime
                    .close_acp_session(next.target)
                    .await?
                    .local_complete
            );
        }
        fixture
            .runtime
            .prompt_acp_session(
                anchor.target.clone(),
                vec![pl_acp::session::schema::ContentBlock::Text(
                    pl_acp::session::schema::TextContent::new("anchor still owns its tools"),
                )],
            )
            .await?;
        tokio::time::timeout(Duration::from_secs(10), async {
            loop {
                if let Some(AcpSessionEvent::Completed { completed }) =
                    anchor.observation.as_mut().unwrap().recv().await
                {
                    assert!(completed.result.is_ok());
                    break;
                }
            }
        })
        .await?;
        let owner = fixture
            .runtime
            .sessions
            .get(&crate::SessionId::new(anchor.target.session_id.clone())?)
            .expect("anchor session is resident");
        let resources = owner
            .resident_acp(&anchor.target.thread_id)?
            .expect("anchor ACP member is resident");
        assert_eq!(resources.host_mcp_status().await["injected"], true);
        assert!(
            !resources.cancellation.is_cancelled(),
            "anchor retains its own qualification"
        );
        let paths = std::fs::read_to_string(fixture.home.path().join("stdio-helper-paths"))?;
        let paths: Vec<_> = paths.lines().collect();
        assert_eq!(paths.len(), 10);
        assert!(paths.iter().all(|path| *path == paths[0]));
        let image = PathBuf::from(paths[0]);
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("stdio-isolation"))?,
            "10"
        );
        assert!(
            fixture
                .runtime
                .close_acp_session(anchor.target)
                .await?
                .local_complete
        );
        assert_eq!(
            image_fds(&payload)?,
            1,
            "closed members do not release the account image"
        );
        assert!(image.exists());
        use std::os::unix::fs::MetadataExt;
        let original_image = std::fs::metadata(&image)?;
        fixture.runtime.shutdown_runtime().await?;
        assert_eq!(image_fds(&payload)?, 0);
        // Numeric /proc FD paths can be reused by shutdown's unrelated file I/O.
        // The original anonymous inode, rather than that number, must be gone.
        assert!(
            !std::fs::metadata(&image).is_ok_and(|current| current.dev() == original_image.dev()
                && current.ino() == original_image.ino())
        );
        assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
        Ok(())
    })
    .await
}

#[tokio::test]
async fn repair_retirement_releases_historical_owners_without_another_open() -> Result<()> {
    // HTTP sessions must not even inspect an unavailable stdio bundle.
    let missing = tempfile::tempdir()?.path().join("not-installed");
    let fixture =
        Fixture::with_mcp_source("mcp-http", crate::HostMcpSource::Bundled(missing)).await?;
    with_cleanup(&fixture.runtime, async {
        let mut revision = fixture.revision;
        let mut previous = None;
        for generation in 0..5 {
            let mut open = fixture
                .runtime
                .open_acp_session(OpenAcpSessionRequest {
                    account_id: "business-peer".into(),
                    expected_connection_revision: revision,
                    workspace_id: fixture.workspace.id.clone(),
                    thread_id: None,
                    intent: AcpOpenIntent::New,
                })
                .await?;
            Fixture::ready(&mut open).await?;
            open.completion.wait().await?;
            if let Some((pid, weak)) = previous.take() {
                assert!(
                    !std::path::Path::new(&format!("/proc/{pid}")).exists(),
                    "new readiness cannot overlap the old process"
                );
                wait_retired(&fixture.runtime, &weak).await;
            }
            let pid = fixture.pid("pid")?;
            let entry = fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["business-peer"]
                .clone();
            let account = fixture.runtime.acp_accounts.connection(&entry.definition)?;
            let weak = Arc::downgrade(&account);
            drop(account);
            if generation == 4 {
                fixture
                    .runtime
                    .config_runtime
                    .delete_acp_definition("business-peer", entry.document_revision)?;
                // No later open, prepare or close call is allowed to do this cleanup for us.
                wait_retired(&fixture.runtime, &weak).await;
                assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
            } else {
                let mut changed = entry.definition;
                changed
                    .env
                    .insert("SYNTHETIC_GENERATION".into(), generation.to_string());
                fixture
                    .runtime
                    .config_runtime
                    .save_acp_definition(&changed, Some(entry.document_revision))?;
                revision = fixture
                    .runtime
                    .config_runtime
                    .read_acp_definitions()
                    .definitions["business-peer"]
                    .connection_revision;
                previous = Some((pid, weak));
            }
        }
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            5
        );
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("mcp-http-received"))?,
            "true"
        );
        Ok(())
    })
    .await
}

fn pending_account(
    runtime: &StudioRuntime,
) -> (Arc<AccountConnection>, tokio::sync::oneshot::Sender<()>) {
    let (_, ready) = watch::channel(None);
    let (release, blocked) = tokio::sync::oneshot::channel();
    let account = Arc::new(AccountConnection {
        account_id: "synthetic-retirement".into(),
        revision: 1,
        cancel: CancellationToken::new(),
        cleanup: pl_acp::auth::CleanupBudget::new(PROCESS_CLEANUP_LIMIT),
        ready,
        protocol: Mutex::new(None),
        members: Mutex::new(Vec::new()),
        mcp_source: crate::HostMcpSource::External,
        frontend: tokio::sync::Mutex::new(Frontend::default()),
        join: RetainedTask::running(tokio::spawn(async move {
            let _ = blocked.await;
        })),
        // Deliberately announce cleanup before task return: only awaiting the original
        // JoinHandle, never these flags alone, is proof that it is safe to deregister.
        settled: AtomicBool::new(true),
        supervisor_finished: AtomicBool::new(true),
        failure: Mutex::new(None),
        initialized_at: Mutex::new(None),
        launch_now: tokio::sync::Notify::new(),
        retirement_wake: runtime.acp_accounts.inner.retirement_wake.clone(),
        issue: Mutex::new(None),
        retry: tokio::sync::Notify::new(),
        installed_version: Mutex::new(None),
        pending_upgrade_version: Mutex::new(None),
    });
    (account, release)
}

#[tokio::test]
async fn repair_retirement_preserves_pending_original_join_when_waiter_is_cancelled() -> Result<()>
{
    let fixture = Fixture::new("replay").await?;
    with_cleanup(&fixture.runtime, async {
        let (account, release) = pending_account(&fixture.runtime);
        let waiting = account.clone();
        let waiter = tokio::spawn(async move { waiting.wait().await });
        tokio::time::timeout(Duration::from_secs(5), async {
            while !account.join.join_wait_in_progress() {
                tokio::task::yield_now().await;
            }
        })
        .await?;
        waiter.abort();
        assert!(waiter.await.unwrap_err().is_cancelled());
        assert_eq!(account.join.running_handle_retained(), Some(true));
        fixture
            .runtime
            .acp_accounts
            .inner
            .lock()
            .retiring
            .push(account.clone());
        fixture
            .runtime
            .acp_accounts
            .inner
            .retirement_wake
            .notify_one();
        tokio::time::timeout(Duration::from_secs(5), async {
            while !account.join.join_wait_in_progress() {
                tokio::task::yield_now().await;
            }
        })
        .await?;
        assert_eq!(
            fixture.runtime.acp_accounts.inner.lock().retiring.len(),
            1,
            "even settled flags cannot discard a pending join"
        );
        let weak = Arc::downgrade(&account);
        drop(account);
        release.send(()).unwrap();
        wait_retired(&fixture.runtime, &weak).await;
        Ok(())
    })
    .await
}

#[tokio::test]
async fn repair_retirement_errors_are_bounded_without_retaining_historical_owners() -> Result<()> {
    let fixture = Fixture::new("replay").await?;
    let work = std::panic::AssertUnwindSafe(async {
        for index in 0..4 {
            let (account, release) = pending_account(&fixture.runtime);
            *account.issue.lock().unwrap() = Some(format!("failure-{index}:{}", "x".repeat(8192)));
            let weak = Arc::downgrade(&account);
            fixture
                .runtime
                .acp_accounts
                .inner
                .lock()
                .retiring
                .push(account);
            fixture
                .runtime
                .acp_accounts
                .inner
                .retirement_wake
                .notify_one();
            release.send(()).unwrap();
            wait_retired(&fixture.runtime, &weak).await;
            let registry = fixture.runtime.acp_accounts.inner.lock();
            let issue = registry
                .retirement_issue
                .as_ref()
                .expect("retired failure remains observable");
            assert!(issue.chars().count() <= 2048);
            assert!(
                issue.contains(&format!("failure-{index}:")),
                "only the latest issue is retained"
            );
        }
        Ok::<_, anyhow::Error>(())
    })
    .catch_unwind()
    .await;
    // Always run real cleanup. Historical failures must remain truthful shutdown
    // failures even though no full historical owner is retained.
    let shutdown = fixture.runtime.shutdown_runtime().await;
    match work {
        Err(panic) => std::panic::resume_unwind(panic),
        Ok(result) => result?,
    }
    assert!(
        shutdown.is_err(),
        "a recorded retirement failure must prevent Clean shutdown"
    );
    assert!(
        fixture
            .runtime
            .acp_accounts
            .inner
            .retirement_join
            .slot_is_empty()
            .await
    );
    Ok(())
}

#[tokio::test]
async fn acp_account_reuses_check_and_business_sessions_and_retires_configuration() -> Result<()> {
    let fixture = Fixture::new("replay").await?;
    with_cleanup(&fixture.runtime, async {
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            account.active_operation.is_none()
                && matches!(account.state, AcpAuthState::Verified { .. })
        })
        .await;
        let pid = fixture.pid("pid")?;
        let mut first = fixture.open().await?;
        Fixture::ready(&mut first).await?;
        first.completion.wait().await?;
        let mut second = fixture.open().await?;
        Fixture::ready(&mut second).await?;
        second.completion.wait().await?;
        assert_ne!(
            fixture
                .runtime
                .acp_session_snapshot(first.target.clone())
                .await?
                .acp_session_id,
            fixture
                .runtime
                .acp_session_snapshot(second.target.clone())
                .await?
                .acp_session_id
        );
        assert_eq!(fixture.pid("pid")?, pid);
        let definition = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut renamed = definition.definition.clone();
        renamed.display_name = "Only the name changed".into();
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&renamed, Some(definition.document_revision))?;
        assert_eq!(
            fixture
                .runtime
                .config_runtime
                .read_acp_definitions()
                .definitions["business-peer"]
                .connection_revision,
            fixture.revision
        );
        fixture.runtime.start_acp_auth(StartAcpAuthRequest {
            operation_id: "second-check".into(),
            account_id: "business-peer".into(),
            expected_connection_revision: fixture.revision,
            action: AcpAuthAction::Check,
        })?;
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            account.active_operation.is_none()
                && matches!(account.state, AcpAuthState::Verified { .. })
        })
        .await;
        assert!(
            fixture
                .runtime
                .close_acp_session(first.target)
                .await?
                .local_complete
        );
        assert!(std::path::Path::new(&format!("/proc/{pid}")).exists());
        fixture
            .runtime
            .prompt_acp_session(
                second.target.clone(),
                vec![pl_acp::session::schema::ContentBlock::Text(
                    pl_acp::session::schema::TextContent::new("only the second member"),
                )],
            )
            .await?;
        loop {
            if let Some(AcpSessionEvent::Completed { completed }) =
                second.observation.as_mut().unwrap().recv().await
            {
                assert!(completed.result.is_ok());
                break;
            }
        }
        let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            calls.lines().filter(|call| *call == "initialize").count(),
            1
        );
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            1
        );
        let process_cwd = std::fs::read_to_string(fixture.home.path().join("process-cwd"))?;
        assert_ne!(process_cwd, fixture.workspace.path);
        let sessions = std::fs::read_to_string(fixture.home.path().join("sessions"))?;
        let sessions: Vec<serde_json::Value> = sessions
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect();
        assert_eq!(
            sessions
                .iter()
                .filter(|session| session["cwd"] == process_cwd && session["mcp"] == false)
                .count(),
            2
        );
        assert_eq!(
            sessions
                .iter()
                .filter(|session| session["cwd"] == fixture.workspace.path
                    && session["mcp"] == true)
                .count(),
            2
        );
        let definition = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut changed = definition.definition;
        changed
            .env
            .insert("SYNTHETIC_GENERATION".into(), "two".into());
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&changed, Some(definition.document_revision))?;
        assert!(
            fixture
                .runtime
                .prompt_acp_session(second.target, vec![])
                .await
                .is_err()
        );
        let revision = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .connection_revision;
        let mut replacement = fixture
            .runtime
            .open_acp_session(OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id: None,
                intent: AcpOpenIntent::New,
            })
            .await?;
        Fixture::ready(&mut replacement).await?;
        replacement.completion.wait().await?;
        assert!(
            !std::path::Path::new(&format!("/proc/{pid}")).exists(),
            "old process was reaped before replacement became ready"
        );
        assert_ne!(fixture.pid("pid")?, pid);
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            2
        );
        let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            calls.lines().filter(|call| *call == "initialize").count(),
            2
        );
        assert_eq!(
            calls
                .lines()
                .filter(|call| *call == "session/prompt")
                .count(),
            1,
            "retirement cannot replay accepted input"
        );
        let final_pid = fixture.pid("pid")?;
        fixture.runtime.shutdown_runtime().await?;
        assert!(!std::path::Path::new(&format!("/proc/{final_pid}")).exists());
        Ok(())
    })
    .await
}

#[tokio::test]
async fn acp_template_background_prepare_is_shared_nonblocking_and_never_autoauthenticates()
-> Result<()> {
    let fixture = Fixture::disabled("initialize-hold").await?;
    with_cleanup(&fixture.runtime, async {
        let script = format!("#!/usr/bin/python3\n{}", crate::acp_transport_fixture::PEER);
        crate::studio::runtime::acp_install::seed_synthetic_install(
            &fixture.runtime.store,
            script.as_bytes(),
        );
        let entry = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut definition = entry.definition;
        definition.enabled = true;
        definition.launch =
            crate::config::AcpLaunch::Template(crate::config::AcpProvider::Antigravity);
        // Config returns while initialize is still deliberately held by the peer.
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&definition, Some(entry.document_revision))?;
        marker(&fixture.home.path().join("initializing")).await;
        let one = fixture.runtime.acp_accounts.connection(&definition)?;
        let two = fixture.runtime.acp_accounts.connection(&definition)?;
        assert!(Arc::ptr_eq(&one, &two));
        let waiter = tokio::spawn(async move { two.prepared().await });
        tokio::task::yield_now().await;
        waiter.abort();
        assert!(matches!(waiter.await, Err(error) if error.is_cancelled()));
        assert!(
            !one.cancel.is_cancelled(),
            "waiter cancellation cannot withdraw shared preparation"
        );
        std::fs::write(fixture.home.path().join("mode"), "auth")?;
        std::fs::write(fixture.home.path().join("release-init"), "continue")?;
        let required = wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.state, AcpAuthState::Required { .. })
        })
        .await;
        let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            calls.lines().filter(|call| *call == "initialize").count(),
            1
        );
        assert!(!calls.contains("authenticate") && !calls.contains("session/prompt"));
        let pid = fixture.pid("pid")?;
        fixture.runtime.continue_acp_auth(ContinueAcpAuthRequest {
            operation_id: "explicit-login".into(),
            account_id: "business-peer".into(),
            expected_connection_revision: required.connection_revision,
            target_operation_id: required.active_operation.unwrap().operation_id,
            method_id: "login".into(),
        })?;
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            account.active_operation.is_none()
                && matches!(account.state, AcpAuthState::Verified { .. })
        })
        .await;
        let mut business = fixture
            .runtime
            .open_acp_session(OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: required.connection_revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id: None,
                intent: AcpOpenIntent::New,
            })
            .await?;
        Fixture::ready(&mut business).await?;
        business.completion.wait().await?;
        fixture.runtime.start_acp_auth(StartAcpAuthRequest {
            operation_id: "explicit-usage".into(),
            account_id: "business-peer".into(),
            expected_connection_revision: required.connection_revision,
            action: AcpAuthAction::QueryUsage,
        })?;
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            account.active_operation.is_none() && account.usage.is_some()
        })
        .await;
        assert!(
            fixture
                .runtime
                .acp_session_snapshot(business.target)
                .await?
                .ready
        );
        assert_eq!(fixture.pid("pid")?, pid);
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            1
        );
        let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            calls.lines().filter(|call| *call == "authenticate").count(),
            1
        );
        assert_eq!(
            calls
                .lines()
                .filter(|call| *call == "session/prompt")
                .count(),
            1
        );
        fixture.runtime.shutdown_runtime().await?;
        assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
        // Startup consumes the saved template definition and validated synthetic install, not a GUI read.
        let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
            studio_home: Some(fixture.home.path().join("studio")),
            host: StudioHostKind::Test,
            ..StudioRuntimeOptions::desktop()
        })
        .await?;
        with_cleanup(&runtime, async {
            wait_account_state(&runtime, "business-peer", |account| {
                account.active_operation.is_none()
                    && matches!(account.state, AcpAuthState::Verified { .. })
            })
            .await;
            assert_eq!(
                std::fs::read_to_string(fixture.home.path().join("spawns"))?
                    .lines()
                    .count(),
                2
            );
            let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
            assert_eq!(
                calls.lines().filter(|call| *call == "authenticate").count(),
                1
            );
            assert_eq!(
                calls.lines().filter(|call| *call == "session/load").count(),
                0
            );
            let pid = fixture.pid("pid")?;
            runtime.shutdown_runtime().await?;
            assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
            Ok(())
        })
        .await?;
        Ok(())
    })
    .await
}

#[tokio::test]
async fn acp_different_accounts_keep_remote_ids_and_retirement_isolated() -> Result<()> {
    let fixture = Fixture::new("replay").await?;
    with_cleanup(&fixture.runtime, async {
        let mut first = fixture.open().await?;
        Fixture::ready(&mut first).await?;
        first.completion.wait().await?;
        let entry = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let first_owner = fixture.runtime.acp_accounts.connection(&entry.definition)?;
        let other_root = fixture.home.path().join("other-peer");
        std::fs::create_dir(&other_root)?;
        std::fs::write(other_root.join("mode"), "replay")?;
        let mut definition = entry.definition.clone();
        definition.id = "other-peer".into();
        definition.env.insert(
            "ACP_FIXTURE_ROOT".into(),
            other_root.to_string_lossy().into_owned(),
        );
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&definition, None)?;
        let revision = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["other-peer"]
            .connection_revision;
        let mut second = fixture
            .runtime
            .open_acp_session(OpenAcpSessionRequest {
                account_id: "other-peer".into(),
                expected_connection_revision: revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id: None,
                intent: AcpOpenIntent::New,
            })
            .await?;
        Fixture::ready(&mut second).await?;
        second.completion.wait().await?;
        assert_eq!(
            fixture
                .runtime
                .acp_session_snapshot(first.target.clone())
                .await?
                .acp_session_id,
            fixture
                .runtime
                .acp_session_snapshot(second.target.clone())
                .await?
                .acp_session_id,
            "identical remote IDs belong to different connection scopes"
        );
        let first_pid = fixture.pid("pid")?;
        let second_pid: u32 = std::fs::read_to_string(other_root.join("pid"))?.parse()?;
        assert_ne!(first_pid, second_pid);
        let mut disabled = entry.definition;
        disabled.enabled = false;
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&disabled, Some(entry.document_revision))?;
        first_owner.close().await?;
        assert!(!std::path::Path::new(&format!("/proc/{first_pid}")).exists());
        assert!(std::path::Path::new(&format!("/proc/{second_pid}")).exists());
        fixture
            .runtime
            .prompt_acp_session(
                second.target.clone(),
                vec![pl_acp::session::schema::ContentBlock::Text(
                    pl_acp::session::schema::TextContent::new("other account still works"),
                )],
            )
            .await?;
        loop {
            if let Some(AcpSessionEvent::Completed { completed }) =
                second.observation.as_mut().unwrap().recv().await
            {
                assert!(completed.result.is_ok());
                break;
            }
        }
        assert_eq!(
            std::fs::read_to_string(other_root.join("calls"))?
                .lines()
                .filter(|call| *call == "initialize")
                .count(),
            1
        );
        fixture.runtime.shutdown_runtime().await?;
        assert!(!std::path::Path::new(&format!("/proc/{second_pid}")).exists());
        Ok(())
    })
    .await
}
#[tokio::test]
async fn generic_background_connection_restarts_without_replaying_sessions_or_prompts() -> Result<()>
{
    let fixture = Fixture::new("replay").await?;
    with_cleanup(&fixture.runtime, async {
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Ready)
                && matches!(account.state, AcpAuthState::Verified { .. })
                && account.active_operation.is_none()
        })
        .await;
        assert!(
            fixture
                .runtime
                .acp_accounts
                .inner
                .lock()
                .accepted
                .is_empty()
        );
        let first_pid = fixture.pid("pid")?;
        let mut first = fixture.open().await?;
        Fixture::ready(&mut first).await?;
        first.completion.wait().await?;
        let mut second = fixture.open().await?;
        Fixture::ready(&mut second).await?;
        second.completion.wait().await?;
        assert_eq!(fixture.pid("pid")?, first_pid);
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            1
        );
        assert!(
            std::process::Command::new("/bin/kill")
                .args(["-KILL", &first_pid.to_string()])
                .status()?
                .success()
        );
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(
                account.connection,
                AcpConnectionState::Retrying { attempt: 1, .. }
            )
        })
        .await;
        assert!(
            !std::path::Path::new(&format!("/proc/{first_pid}")).exists(),
            "old process must be reaped before reconnect is scheduled"
        );
        tokio::time::pause();
        tokio::time::advance(crate::studio::runtime::acp_accounts::lifecycle::retry_delay(1)).await;
        tokio::time::resume();
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Ready)
                && matches!(account.state, AcpAuthState::Verified { .. })
                && account.active_operation.is_none()
        })
        .await;
        let next_pid = fixture.pid("pid")?;
        assert_ne!(next_pid, first_pid);
        assert!(
            fixture
                .runtime
                .acp_accounts
                .inner
                .lock()
                .accepted
                .is_empty(),
            "background reconnects do not consume command dedup identities"
        );
        assert!(
            fixture
                .runtime
                .prompt_acp_session(
                    first.target,
                    vec![pl_acp::session::schema::ContentBlock::Text(
                        pl_acp::session::schema::TextContent::new("must not replay")
                    )]
                )
                .await
                .is_err()
        );
        let mut next = fixture.open().await?;
        Fixture::ready(&mut next).await?;
        next.completion.wait().await?;
        let calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        assert_eq!(
            calls.lines().filter(|line| *line == "initialize").count(),
            2
        );
        assert!(!calls.lines().any(|line| line == "session/prompt"));
        assert_eq!(fixture.pid("pid")?, next_pid);
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            2
        );
        for (stable, expected_attempt) in [(false, 2), (true, 1)] {
            let old_pid = fixture.pid("pid")?;
            tokio::time::pause();
            tokio::time::advance(Duration::from_secs(if stable { 60 } else { 59 })).await;
            tokio::time::resume();
            if !stable {
                // Inject the observed stop boundary before a delayed physical exit.
                // Cleanup crossing 60 seconds must not reset this short-lived instance.
                let account = fixture.runtime.acp_accounts.inner.lock().slots["business-peer"]
                    .connection
                    .as_ref()
                    .expect("ready account")
                    .clone();
                fixture
                    .runtime
                    .acp_accounts
                    .inner
                    .connection_state(&account, AcpConnectionState::Stopping);
                tokio::time::pause();
                tokio::time::advance(Duration::from_secs(10)).await;
                tokio::time::resume();
            }
            assert!(
                std::process::Command::new("/bin/kill")
                    .args(["-KILL", &old_pid.to_string()])
                    .status()?
                    .success()
            );
            wait_account_state(&fixture.runtime, "business-peer", |account| {
                matches!(account.connection, AcpConnectionState::Retrying { attempt, .. }
                    if attempt == expected_attempt)
            })
            .await;
            assert!(!std::path::Path::new(&format!("/proc/{old_pid}")).exists());
            tokio::time::pause();
            tokio::time::advance(
                crate::studio::runtime::acp_accounts::lifecycle::retry_delay(expected_attempt),
            )
            .await;
            tokio::time::resume();
            wait_account_state(&fixture.runtime, "business-peer", |account| {
                matches!(account.connection, AcpConnectionState::Ready)
                    && matches!(account.state, AcpAuthState::Verified { .. })
                    && account.active_operation.is_none()
            })
            .await;
            assert_ne!(fixture.pid("pid")?, old_pid);
        }
        Ok(())
    })
    .await
}

#[tokio::test]
async fn disabling_during_reconnect_cancels_the_original_deadline() -> Result<()> {
    let fixture = Fixture::new("replay").await?;
    with_cleanup(&fixture.runtime, async {
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.state, AcpAuthState::Verified { .. })
                && account.active_operation.is_none()
        })
        .await;
        let pid = fixture.pid("pid")?;
        assert!(
            std::process::Command::new("/bin/kill")
                .args(["-KILL", &pid.to_string()])
                .status()?
                .success()
        );
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Retrying { .. })
        })
        .await;
        let entry = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut disabled = entry.definition;
        disabled.enabled = false;
        tokio::time::pause();
        let saved = fixture
            .runtime
            .config_runtime
            .save_acp_definition(&disabled, Some(entry.document_revision));
        tokio::time::advance(Duration::from_secs(120)).await;
        tokio::time::resume();
        saved?;
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Stopped)
                && account.active_operation.is_none()
        })
        .await;
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            1
        );
        assert!(!std::path::Path::new(&format!("/proc/{pid}")).exists());
        Ok(())
    })
    .await
}

#[tokio::test]
async fn invalid_enabled_command_is_blocked_without_retry_or_command_ledger_growth() -> Result<()> {
    let fixture = Fixture::disabled("replay").await?;
    with_cleanup(&fixture.runtime, async {
        let entry = fixture.runtime.config_runtime.read_acp_definitions().definitions["business-peer"].clone();
        let mut invalid = entry.definition;
        invalid.enabled = true;
        invalid.launch = crate::config::AcpLaunch::Command {
            command: fixture.home.path().join("missing-executable").to_string_lossy().into_owned(), args: vec![],
        };
        fixture.runtime.config_runtime.save_acp_definition(&invalid, Some(entry.document_revision),
        )?;
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(&account.connection, AcpConnectionState::Blocked { failure } if failure.code == AcpAuthFailureCode::MissingExecutable)
                && account.active_operation.is_none()
        }).await;
        tokio::time::pause();
        tokio::time::advance(Duration::from_secs(120)).await;
        tokio::time::resume();
        assert!(!fixture.home.path().join("spawns").exists());
        assert!(fixture.runtime.acp_accounts.inner.lock().accepted.is_empty());
        assert!(fixture.runtime.acp_accounts.inner.lock().slots["business-peer"].lifecycle.retry_at.is_none());
        Ok(())
    }).await
}

#[tokio::test]
async fn acp_business_observer_is_delivered_before_slow_shared_initialize() -> Result<()> {
    let fixture = Fixture::new("initialize-hold").await?;
    with_cleanup(&fixture.runtime, async {
        let opening = tokio::time::timeout(Duration::from_secs(5), fixture.open()).await;
        // Release even on a failed assertion so failure cleanup does not depend on killing
        // a blocked protocol fixture to establish the behavior under test.
        std::fs::write(fixture.home.path().join("mode"), "replay")?;
        std::fs::write(fixture.home.path().join("release-init"), "continue")?;
        let mut open = opening??;
        assert!(open.observation.is_some());
        Fixture::ready(&mut open).await?;
        open.completion.wait().await?;
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            1
        );
        Ok(())
    })
    .await
}

#[tokio::test]
async fn query_usage_on_ready_verified_connection_keeps_verified_and_single_process() -> Result<()>
{
    let fixture = Fixture::disabled("replay").await?;
    with_cleanup(&fixture.runtime, async {
        let script = format!("#!/usr/bin/python3\n{}", crate::acp_transport_fixture::PEER);
        crate::studio::runtime::acp_install::seed_synthetic_install(
            &fixture.runtime.store,
            script.as_bytes(),
        );
        let entry = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut template = entry.definition;
        template.enabled = true;
        template.launch =
            crate::config::AcpLaunch::Template(crate::config::AcpProvider::Antigravity);
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&template, Some(entry.document_revision))?;
        let ready = wait_account_state(&fixture.runtime, "business-peer", |account| {
            account.active_operation.is_none()
                && matches!(account.connection, AcpConnectionState::Ready)
                && matches!(account.state, AcpAuthState::Verified { .. })
        })
        .await;
        let pid = fixture.pid("pid")?;

        let mut updates = fixture
            .runtime
            .subscribe_product_topic(crate::StudioProductTopic::AcpAuth)
            .await?;
        fixture.runtime.start_acp_auth(StartAcpAuthRequest {
            operation_id: "usage-1".into(),
            account_id: "business-peer".into(),
            expected_connection_revision: ready.connection_revision,
            action: AcpAuthAction::QueryUsage,
        })?;
        let finished = tokio::time::timeout(Duration::from_secs(15), async {
            let mut saw_active = false;
            loop {
                let frame = updates
                    .recv()
                    .await
                    .expect("auth stream ok")
                    .expect("auth stream open");
                let snapshot = match frame {
                    crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                        crate::StudioProductBaselineState::AcpAuth(snapshot) => *snapshot,
                        other => panic!("unexpected baseline: {other:?}"),
                    },
                    crate::StudioProductFrame::Event(event) => match event.kind {
                        crate::StudioProductEventKind::AcpAuthStateChanged(snapshot) => *snapshot,
                        other => panic!("unexpected event: {other:?}"),
                    },
                    crate::StudioProductFrame::Lagged { dropped, .. } => {
                        panic!("lagged {dropped} auth frames")
                    }
                };
                let account = snapshot
                    .accounts
                    .into_iter()
                    .find(|account| account.account_id == "business-peer")
                    .expect("account present");
                assert!(
                    matches!(account.state, AcpAuthState::Verified { .. }),
                    "QueryUsage must not clobber Verified auth state: {:?}",
                    account.state
                );
                if let Some(op) = account.active_operation.as_ref() {
                    assert_eq!(op.action, AcpAuthAction::QueryUsage);
                    saw_active = true;
                } else if saw_active && account.usage.is_some() {
                    return account;
                }
            }
        })
        .await?;
        assert!(matches!(
            finished.usage,
            Some(crate::AcpUsageObservation {
                state: crate::AcpUsageState::Ready { .. },
                ..
            })
        ));

        // Cancelling a held QueryUsage on Ready + Verified also preserves Verified & usage.
        std::fs::write(fixture.home.path().join("mode"), "prompt-hold")?;
        fixture.runtime.start_acp_auth(StartAcpAuthRequest {
            operation_id: "usage-cancel".into(),
            account_id: "business-peer".into(),
            expected_connection_revision: ready.connection_revision,
            action: AcpAuthAction::QueryUsage,
        })?;
        marker(&fixture.home.path().join("prompting")).await;
        fixture.runtime.cancel_acp_auth(CancelAcpAuthRequest {
            operation_id: "cancel-usage-op".into(),
            account_id: "business-peer".into(),
            target_operation_id: "usage-cancel".into(),
        })?;
        std::fs::write(fixture.home.path().join("release"), "continue")?;
        let after_cancel = wait_account_state(&fixture.runtime, "business-peer", |account| {
            account.active_operation.is_none()
        })
        .await;
        assert!(matches!(after_cancel.state, AcpAuthState::Verified { .. }));
        assert_eq!(after_cancel.usage, finished.usage);
        assert_eq!(fixture.pid("pid")?, pid);
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            1
        );
        Ok(())
    })
    .await
}

#[tokio::test]
async fn business_open_wakes_retrying_backoff_immediately() -> Result<()> {
    let fixture = Fixture::new("replay").await?;
    with_cleanup(&fixture.runtime, async {
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Ready)
                && matches!(account.state, AcpAuthState::Verified { .. })
                && account.active_operation.is_none()
        })
        .await;
        let first_pid = fixture.pid("pid")?;
        // Force a long retry backoff after the process dies by seeding prior attempts.
        fixture
            .runtime
            .acp_accounts
            .inner
            .lock()
            .slots
            .get_mut("business-peer")
            .expect("slot exists")
            .lifecycle
            .seed_attempts_for_test(5);
        assert!(
            std::process::Command::new("/bin/kill")
                .args(["-KILL", &first_pid.to_string()])
                .status()?
                .success()
        );
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Retrying { .. })
        })
        .await;
        assert!(
            fixture.runtime.acp_accounts.inner.lock().slots["business-peer"]
                .lifecycle
                .retry_at
                .is_some_and(
                    |deadline| deadline > tokio::time::Instant::now() + Duration::from_secs(10)
                )
        );
        let mut open = tokio::time::timeout(
            Duration::from_secs(5),
            fixture.open_intent(AcpOpenIntent::Draft {
                workspace_mode: crate::ThreadWorkspaceMode::Local,
                delegation_mode: None,
                delegation_preference: None,
                mode: None,
            }),
        )
        .await??;
        Fixture::ready(&mut open).await?;
        open.completion.wait().await?;
        assert_eq!(
            std::fs::read_to_string(fixture.home.path().join("spawns"))?
                .lines()
                .count(),
            2
        );
        let second_pid = fixture.pid("pid")?;
        assert_ne!(second_pid, first_pid);
        assert!(std::path::Path::new(&format!("/proc/{second_pid}")).exists());
        Ok(())
    })
    .await
}
