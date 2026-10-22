//! A real SSH probe with a gated public asset provider makes cancellation ordering observable.
use anyhow::{Context, ensure};
use pl_tool::remote::{
    RemoteClientError, RemoteHelperAssets, RemoteHelperTarget, SshConfigFile, SshConnectionState,
    SshManager, SshServerProfile,
};
use std::{
    path::Path,
    sync::{Arc, Condvar, Mutex},
};

#[derive(Debug)]
struct GatedAssets {
    entered: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    released: Mutex<bool>,
    wake: Condvar,
}
impl RemoteHelperAssets for GatedAssets {
    fn load(&self, _: RemoteHelperTarget) -> Result<Arc<[u8]>, RemoteClientError> {
        if let Some(entered) = self.entered.lock().unwrap().take() {
            let _ = entered.send(());
        }
        let mut released = self.released.lock().unwrap();
        while !*released {
            released = self.wake.wait(released).unwrap();
        }
        // Cancellation must stop before these deliberately invalid bytes can be uploaded or run.
        Ok(Arc::from(&b"cancelled-before-upload"[..]))
    }
}
struct ReleaseGate(Arc<GatedAssets>);
impl Drop for ReleaseGate {
    fn drop(&mut self) {
        *self.0.released.lock().unwrap() = true;
        self.0.wake.notify_all();
    }
}
pub async fn cancellation_joins_connect(
    profile: SshServerProfile,
    known_hosts: &Path,
) -> anyhow::Result<()> {
    let directory = tempfile::tempdir()?;
    let config = directory.path().join("ssh_config");
    std::fs::write(
        &config,
        format!(
            "UserKnownHostsFile {}\nIdentitiesOnly yes\n",
            known_hosts.display()
        ),
    )?;
    let (entered, entering) = tokio::sync::oneshot::channel();
    let assets = Arc::new(GatedAssets {
        entered: Mutex::new(Some(entered)),
        released: Mutex::new(false),
        wake: Condvar::new(),
    });
    let release = ReleaseGate(assets.clone());
    let manager = SshManager::with_helper_assets(assets).with_ssh_config(SshConfigFile::at(config));
    let alias = profile.alias.clone();
    manager.save_server(profile).await?;
    let connecting_manager = manager.clone();
    let connecting_alias = alias.clone();
    let mut connecting =
        tokio::spawn(async move { connecting_manager.connect_server(&connecting_alias).await });
    tokio::select! {
        result = tokio::time::timeout(std::time::Duration::from_secs(30), entering) => {
            result.context("asset load did not start")??;
        }
        result = &mut connecting => anyhow::bail!("connection finished before asset gate: {:?}", result?),
    }
    let disconnecting = manager.disconnect_server(&alias);
    tokio::pin!(disconnecting);
    ensure!(
        futures::poll!(&mut disconnecting).is_pending(),
        "disconnect returned before the in-flight owner settled"
    );
    drop(release);
    disconnecting.await?;
    ensure!(matches!(
        connecting.await?,
        Err(RemoteClientError::Cancelled)
    ));
    ensure!(matches!(
        manager.connection_snapshot(&alias).await?.state,
        SshConnectionState::Disconnected
    ));
    manager.shutdown().await?;
    println!("SSH_CONNECT_CANCELLATION_OWNERSHIP=PASS");
    Ok(())
}

/// Observe only children of this validator, never unrelated user SSH sessions.
pub fn verify_single_business_channel(phase: &str) -> anyhow::Result<()> {
    #[cfg(target_os = "linux")]
    {
        let mut children = std::collections::BTreeSet::new();
        for task in std::fs::read_dir("/proc/self/task")? {
            let task = task?;
            let path = task.path().join("children");
            let Ok(pids) = std::fs::read_to_string(path) else {
                continue;
            };
            children.extend(pids.split_whitespace().map(str::to_owned));
        }
        let channels = children
            .into_iter()
            .filter(|pid| {
                std::fs::read_link(format!("/proc/{pid}/exe"))
                    .ok()
                    .and_then(|path| path.file_name().map(|name| name == "ssh"))
                    .unwrap_or(false)
            })
            .count();
        ensure!(
            channels == 1,
            "{phase}: expected one business SSH child, found {channels}"
        );
        println!(
            "{}",
            serde_json::json!({"scenario":"single-ssh-channel", "phase":phase, "channels":channels})
        );
    }
    #[cfg(not(target_os = "linux"))]
    let _ = phase;
    Ok(())
}
