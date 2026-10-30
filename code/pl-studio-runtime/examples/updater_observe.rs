//! Opt-in observations of the real updater. Never launches an installer.
use std::io::Write;
use std::path::PathBuf;

use anyhow::{Context, Result, ensure};
use pl_studio_runtime::{
    StudioHostKind, StudioRuntime, StudioRuntimeOptions, StudioUpdateCancellation,
    StudioUpdateCheck, StudioUpdateEvent, StudioUpdateStateSnapshot, StudioUpdater,
};

#[tokio::main]
async fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let mode = args
        .next()
        .context("usage: updater_observe state|download ARTIFACT_DIR [CANCEL_AFTER_BYTES]")?;
    let artifacts = std::path::absolute(args.next().context("missing artifact directory")?)?;
    std::fs::create_dir_all(
        artifacts
            .parent()
            .context("artifact directory has no parent")?,
    )?;
    std::fs::create_dir(&artifacts).context("use a new evidence directory for each observation")?;
    let result = match mode.as_str() {
        "state" => observe_state(&artifacts).await,
        "download" => {
            let cancel_after = args.next().map(|value| value.parse::<u64>()).transpose()?;
            observe_download(&artifacts, cancel_after).await
        }
        _ => anyhow::bail!("unknown observation {mode}"),
    };
    std::fs::write(
        artifacts.join("report.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "execution": if result.is_ok() { "completed" } else { "error" },
            "review": "pending",
            "detail": result.as_ref().err().map(|error| format!("{error:#}")),
            "platform": std::env::consts::OS,
        }))?,
    )?;
    result
}

async fn observe_state(artifacts: &std::path::Path) -> Result<()> {
    let home = artifacts.join("home");
    let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
        studio_home: Some(home.clone()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    })
    .await?;
    let path = home.join("data/settings.toml");
    let before = std::fs::read(&path)?;
    let original = std::fs::metadata(&path)?.permissions();
    let mut readonly = original.clone();
    readonly.set_readonly(true);
    std::fs::set_permissions(&path, readonly)?;
    let cancellation = StudioUpdateCancellation::new();
    cancellation.cancel();
    let result = runtime.check_studio_update(&cancellation).await;
    std::fs::set_permissions(&path, original)?;
    let after = std::fs::read(&path)?;
    std::fs::write(
        artifacts.join("state.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "state": result.as_ref().ok(),
            "error": result.as_ref().err().map(|error| format!("{error:#}")),
            "settingsUnchanged": before == after,
        }))?,
    )?;
    let stopped = runtime.shutdown_runtime().await;
    let state = result?;
    ensure!(
        matches!(state, StudioUpdateStateSnapshot::CheckFailed(value) if value.error().code == "cancelled"),
        "cancelled check did not reach its canonical terminal state"
    );
    ensure!(before == after, "update check modified settings.toml");
    stopped?;
    Ok(())
}

async fn observe_download(artifacts: &std::path::Path, cancel_after: Option<u64>) -> Result<()> {
    // The parent selects the isolated cache before creating any async runtime; never mutate
    // environment variables concurrently or write an observation into the user's cache.
    let cache_root = PathBuf::from(
        std::env::var_os("LOCALAPPDATA")
            .context("set LOCALAPPDATA to an isolated cache directory")?,
    );
    ensure!(
        cache_root.starts_with(
            artifacts
                .parent()
                .context("artifact directory has no parent")?
        ),
        "observation cache must be beside the evidence directories"
    );
    let updater = StudioUpdater::new_default()?;
    let StudioUpdateCheck::Available(update) = updater.check("0.0.0").await? else {
        anyhow::bail!("no stable release available");
    };
    std::fs::write(
        artifacts.join("manifest.json"),
        serde_json::to_vec_pretty(&update)?,
    )?;
    let cancellation = StudioUpdateCancellation::new();
    let observer_cancellation = cancellation.clone();
    let (events, mut receiver) = tokio::sync::mpsc::unbounded_channel();
    let mut output = std::fs::File::create(artifacts.join("events.txt"))?;
    let observer = tokio::spawn(async move {
        while let Some(event) = receiver.recv().await {
            writeln!(output, "{event:?}")?;
            if let StudioUpdateEvent::Progress { downloaded, total } = event
                && cancel_after
                    .is_some_and(|threshold| downloaded >= threshold && downloaded < total)
            {
                observer_cancellation.cancel();
            }
        }
        output.sync_all()?;
        Ok::<_, anyhow::Error>(())
    });
    let result = updater.download(update, events, cancellation).await;
    observer.await??;
    let prepared = result?;
    drop(prepared);
    Ok(())
}
