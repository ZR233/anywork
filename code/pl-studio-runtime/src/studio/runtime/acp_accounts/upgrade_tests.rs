//! 受管 Antigravity 大版本 `1` 升级时的连接无感切换测试。

use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;

use super::connection::AccountConnection;
use crate::acp_transport_fixture::AcpTransportFixture as Fixture;
use crate::config::{AcpLaunch, AcpProvider as ConfigAcpProvider};
use crate::studio::runtime::acp_install::seed_synthetic_install_version;
use crate::{
    AcpAuthAccount, AcpAuthAction, AcpAuthState, AcpConnectionState, AcpOpenIntent, AcpProvider,
    AcpSessionEvent, OpenAcpSessionRequest, StartAcpAuthRequest, StudioProductBaselineState,
    StudioProductEventKind, StudioProductFrame, StudioProductTopic, StudioRuntime,
};

fn peer_wrapper_script(version: &str) -> Vec<u8> {
    let script_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/support/acp_business_peer.py"
    );
    format!(
        "#!/bin/sh\nprintf '%s' '{version}' > \"$ACP_FIXTURE_ROOT/server-version\"\nexec python3 '{script_path}' \"$@\"\n"
    )
    .into_bytes()
}

async fn wait_account_state(
    runtime: &StudioRuntime,
    account_id: &str,
    predicate: impl Fn(&AcpAuthAccount) -> bool,
) -> AcpAuthAccount {
    tokio::time::timeout(Duration::from_secs(20), async {
        let mut updates = runtime
            .subscribe_product_topic(StudioProductTopic::AcpAuth)
            .await
            .expect("auth topic opens");
        loop {
            let snapshot = match updates
                .recv()
                .await
                .expect("auth subscription receives frame")
                .expect("auth topic remains open")
            {
                StudioProductFrame::Baseline(baseline) => match baseline.state {
                    StudioProductBaselineState::AcpAuth(snapshot) => *snapshot,
                    other => panic!("unexpected auth baseline: {other:?}"),
                },
                StudioProductFrame::Event(event) => match event.kind {
                    StudioProductEventKind::AcpAuthStateChanged(snapshot) => *snapshot,
                    other => panic!("unexpected auth event: {other:?}"),
                },
                StudioProductFrame::Lagged { dropped, .. } => {
                    panic!("lost {dropped} auth frames")
                }
            };
            if let Some(account) = snapshot
                .accounts
                .into_iter()
                .find(|account| account.account_id == account_id)
                && predicate(&account)
            {
                return account;
            }
        }
    })
    .await
    .expect("account reached expected state")
}

async fn wait_retired(runtime: &StudioRuntime, old: &std::sync::Weak<AccountConnection>) {
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            if runtime.acp_accounts.inner.lock().retiring.is_empty() && old.upgrade().is_none() {
                break;
            }
            tokio::time::sleep(Duration::from_millis(5)).await;
        }
    })
    .await
    .expect("retired connection and old server process cleaned up");
}

#[tokio::test]
async fn managed_upgrade_when_idle_retires_old_process_and_reconnects_cleanly() -> Result<()> {
    let fixture = Fixture::disabled("replay").await?;
    seed_synthetic_install_version(
        &fixture.runtime.store,
        "1.5.2",
        &peer_wrapper_script("1.5.2"),
    );

    let result: Result<()> = async {
        let entry = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut definition = entry.definition;
        definition.enabled = true;
        definition.launch = AcpLaunch::Template(ConfigAcpProvider::Antigravity);
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&definition, Some(entry.document_revision))?;

        let ready_v1 = wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Ready)
                && matches!(
                    &account.state,
                    AcpAuthState::Verified { server: Some(server), .. }
                        if server.version == "1.5.2"
                )
        })
        .await;
        let old_pid = fixture.pid("pid")?;
        let old_conn = Arc::downgrade(&fixture.runtime.acp_accounts.connection(&definition)?);
        let settings_rev_before = fixture.runtime.read_settings()?.config.revision;

        // Upgrade installation on disk and notify accounts owner.
        seed_synthetic_install_version(
            &fixture.runtime.store,
            "1.5.3",
            &peer_wrapper_script("1.5.3"),
        );
        fixture
            .runtime
            .acp_accounts
            .installation_ready(AcpProvider::Antigravity, "1.5.3");

        let ready_v2 = wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Ready)
                && matches!(
                    &account.state,
                    AcpAuthState::Verified { server: Some(server), .. }
                        if server.version == "1.5.3"
                )
        })
        .await;

        wait_retired(&fixture.runtime, &old_conn).await;
        let new_pid = fixture.pid("pid")?;
        assert_ne!(old_pid, new_pid);
        assert!(!std::path::Path::new(&format!("/proc/{old_pid}")).exists());
        assert_eq!(
            fixture.runtime.read_settings()?.config.revision,
            settings_rev_before
        );
        assert_eq!(ready_v1.connection_revision, ready_v2.connection_revision);

        // Existing revision remains accepted cleanly for subsequent connection-scoped operations.
        fixture.runtime.start_acp_auth(StartAcpAuthRequest {
            operation_id: "usage-after-upgrade".into(),
            account_id: "business-peer".into(),
            expected_connection_revision: ready_v2.connection_revision,
            action: AcpAuthAction::QueryUsage,
        })?;
        wait_account_state(&fixture.runtime, "business-peer", |account| {
            account.active_operation.is_none()
                && matches!(account.connection, AcpConnectionState::Ready)
        })
        .await;
        Ok(())
    }
    .await;

    let shutdown = fixture.runtime.shutdown_runtime().await;
    result?;
    shutdown?;
    Ok(())
}

#[tokio::test]
async fn managed_upgrade_defers_while_active_session_runs_then_switches_on_close() -> Result<()> {
    let fixture = Fixture::disabled("replay").await?;
    seed_synthetic_install_version(
        &fixture.runtime.store,
        "1.5.2",
        &peer_wrapper_script("1.5.2"),
    );

    let result: Result<()> = async {
        let entry = fixture
            .runtime
            .config_runtime
            .read_acp_definitions()
            .definitions["business-peer"]
            .clone();
        let mut definition = entry.definition;
        definition.enabled = true;
        definition.launch = AcpLaunch::Template(ConfigAcpProvider::Antigravity);
        fixture
            .runtime
            .config_runtime
            .save_acp_definition(&definition, Some(entry.document_revision))?;

        let ready_v1 = wait_account_state(&fixture.runtime, "business-peer", |account| {
            matches!(account.connection, AcpConnectionState::Ready)
                && matches!(
                    &account.state,
                    AcpAuthState::Verified { server: Some(server), .. }
                        if server.version == "1.5.2"
                )
        })
        .await;
        let pid_v1 = fixture.pid("pid")?;
        let old_conn = Arc::downgrade(&fixture.runtime.acp_accounts.connection(&definition)?);

        // Open active session on v1.5.2.
        let mut session = fixture
            .runtime
            .open_acp_session(OpenAcpSessionRequest {
                account_id: "business-peer".into(),
                expected_connection_revision: ready_v1.connection_revision,
                workspace_id: fixture.workspace.id.clone(),
                thread_id: None,
                intent: AcpOpenIntent::New,
            })
            .await?;
        Fixture::ready(&mut session).await?;
        session.completion.wait().await?;

        // Upgrade installation while active session is open: connection must NOT switch yet.
        seed_synthetic_install_version(
            &fixture.runtime.store,
            "1.5.3",
            &peer_wrapper_script("1.5.3"),
        );
        fixture
            .runtime
            .acp_accounts
            .installation_ready(AcpProvider::Antigravity, "1.5.3");

        tokio::time::sleep(Duration::from_millis(80)).await;
        assert_eq!(fixture.pid("pid")?, pid_v1);
        assert!(std::path::Path::new(&format!("/proc/{pid_v1}")).exists());

        // Existing session continues processing prompts without interruption.
        fixture
            .runtime
            .prompt_acp_session(
                session.target.clone(),
                vec![pl_acp::session::schema::ContentBlock::Text(
                    pl_acp::session::schema::TextContent::new("continue on 1.5.2"),
                )],
            )
            .await?;
        loop {
            if let Some(AcpSessionEvent::Completed { .. }) =
                session.observation.as_mut().unwrap().recv().await
            {
                break;
            }
        }

        // Observe every AcpAuth snapshot transition around closing the active session.
        let mut updates = fixture
            .runtime
            .subscribe_product_topic(StudioProductTopic::AcpAuth)
            .await?;
        fixture
            .runtime
            .close_acp_session(session.target.clone())
            .await?;

        tokio::time::timeout(Duration::from_secs(20), async {
            loop {
                let snapshot = match updates
                    .recv()
                    .await
                    .expect("auth subscription stays open")
                    .expect("auth frame arrives")
                {
                    StudioProductFrame::Baseline(baseline) => match baseline.state {
                        StudioProductBaselineState::AcpAuth(snapshot) => *snapshot,
                        other => panic!("unexpected auth baseline: {other:?}"),
                    },
                    StudioProductFrame::Event(event) => match event.kind {
                        StudioProductEventKind::AcpAuthStateChanged(snapshot) => *snapshot,
                        other => panic!("unexpected auth event: {other:?}"),
                    },
                    StudioProductFrame::Lagged { dropped, .. } => {
                        panic!("lagged {dropped} auth frames");
                    }
                };
                if let Some(account) = snapshot
                    .accounts
                    .into_iter()
                    .find(|account| account.account_id == "business-peer")
                {
                    assert!(
                        !matches!(account.connection, AcpConnectionState::Retrying { .. }),
                        "intentional upgrade must not flash Retrying: {account:?}"
                    );
                    if matches!(account.connection, AcpConnectionState::Ready)
                        && matches!(
                            &account.state,
                            AcpAuthState::Verified { server: Some(server), .. }
                                if server.version == "1.5.3"
                        )
                    {
                        break;
                    }
                }
            }
            Ok::<_, anyhow::Error>(())
        })
        .await??;

        wait_retired(&fixture.runtime, &old_conn).await;
        let pid_v2 = fixture.pid("pid")?;
        assert_ne!(pid_v1, pid_v2);
        assert!(!std::path::Path::new(&format!("/proc/{pid_v1}")).exists());
        Ok(())
    }
    .await;

    let shutdown = fixture.runtime.shutdown_runtime().await;
    result?;
    shutdown?;
    Ok(())
}
