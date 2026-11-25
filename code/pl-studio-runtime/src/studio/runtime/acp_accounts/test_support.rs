//! Shared Studio setup and ACP account lifecycle witnesses for tests.

use anyhow::Result;

use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
use crate::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};

#[cfg(target_os = "linux")]
use {super::connection::AccountConnection, crate::AcpAuthAccount, std::time::Duration};

pub(in crate::studio::runtime) async fn test_runtime(
    configure: impl FnOnce(&ConfigPaths) -> Result<()>,
) -> Result<(tempfile::TempDir, StudioRuntime)> {
    let home = tempfile::tempdir()?;
    let config = StudioConfig::default_config()?;
    let paths = ConfigPaths::from_config_dir(home.path());
    ConfigStore::new(paths.clone()).save(&config)?;
    configure(&paths)?;
    let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
        studio_home: Some(home.path().to_owned()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    })
    .await?;
    Ok((home, runtime))
}

#[cfg(target_os = "linux")]
pub(super) async fn wait_account_state(
    runtime: &StudioRuntime,
    account: &str,
    predicate: impl Fn(&AcpAuthAccount) -> bool,
) -> AcpAuthAccount {
    tokio::time::timeout(Duration::from_secs(20), async {
        let mut updates = runtime
            .subscribe_product_topic(crate::StudioProductTopic::AcpAuth)
            .await
            .expect("auth topic opens");
        loop {
            let snapshot = match updates
                .recv()
                .await
                .expect("auth subscription succeeds")
                .expect("auth topic remains open")
            {
                crate::StudioProductFrame::Baseline(baseline) => match baseline.state {
                    crate::StudioProductBaselineState::AcpAuth(snapshot) => *snapshot,
                    other => panic!("unexpected auth baseline: {other:?}"),
                },
                crate::StudioProductFrame::Event(event) => match event.kind {
                    crate::StudioProductEventKind::AcpAuthStateChanged(snapshot) => *snapshot,
                    other => panic!("unexpected auth event: {other:?}"),
                },
                crate::StudioProductFrame::Lagged { dropped, .. } => {
                    panic!("lost {dropped} auth changes")
                }
            };
            if let Some(state) = snapshot
                .accounts
                .into_iter()
                .find(|state| state.account_id == account)
                && predicate(&state)
            {
                return state;
            }
        }
    })
    .await
    .expect("account reached expected state")
}

#[cfg(target_os = "linux")]
pub(super) async fn wait_retired(
    runtime: &StudioRuntime,
    old: &std::sync::Weak<AccountConnection>,
) {
    tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            if runtime.acp_accounts.inner.lock().retiring.is_empty() && old.upgrade().is_none() {
                break;
            }
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("original supervisor joined and historical owner released without another open");
}
