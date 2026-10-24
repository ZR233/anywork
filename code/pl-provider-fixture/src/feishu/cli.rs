//! Standalone peer CLI lifecycle and evidence files.

use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tokio_util::sync::CancellationToken;

use super::{FeishuLiveStatus, FeishuPeer, FeishuPeerOptions, FeishuReport};

/// CLI options for `--feishu`. Model GUI scenarios stay unchanged.
pub struct FeishuCliOptions {
    pub ready_file: std::path::PathBuf,
    pub requests_file: Option<std::path::PathBuf>,
    pub report_file: Option<std::path::PathBuf>,
    pub status_file: Option<std::path::PathBuf>,
    pub bind_port: Option<u16>,
}

/// Run the independent Feishu peer until SIGINT/SIGTERM, then write evidence.
pub async fn run_feishu_cli(options: FeishuCliOptions) -> Result<()> {
    let mut peer = FeishuPeer::start_with_options(FeishuPeerOptions {
        bind_port: options.bind_port,
        ..FeishuPeerOptions::default()
    })
    .await?;
    let control = peer.control();
    if let Err(error) = write_json(&options.ready_file, &peer.ready_file("feishu")) {
        if let Some(report) = print_shutdown(&mut peer).await {
            for line in report.diagnostic_lines() {
                println!("{line}");
            }
        }
        return Err(error).context("feishu ready file after cleanup");
    }
    let mut status_watch = None;
    if let Some(path) = options.status_file.clone() {
        let control = control.clone();
        let stop = CancellationToken::new();
        let token = stop.clone();
        status_watch = Some((
            stop,
            tokio::spawn(async move {
                let mut written: Option<FeishuLiveStatus> = None;
                write_status(&path, &mut written, control.live_status().await)?;
                loop {
                    tokio::select! {
                        () = token.cancelled() => break,
                        () = tokio::time::sleep(Duration::from_millis(200)) => {
                            write_status(&path, &mut written, control.live_status().await)?;
                        }
                    }
                }
                Ok::<(), anyhow::Error>(())
            }),
        ));
    }
    let wait_outcome = wait_for_stop(status_watch).await;
    let report = print_shutdown(&mut peer).await;
    match wait_outcome {
        WaitOutcome::Signal => {}
        WaitOutcome::Watcher(result) => {
            if let Err(error) = result {
                if let Some(report) = &report {
                    for line in report.diagnostic_lines() {
                        println!("{line}");
                    }
                }
                return Err(error);
            }
        }
    }
    let Some(report) = report else {
        bail!("feishu shutdown did not produce a report");
    };
    if let Some(path) = options.requests_file.as_ref() {
        write_json(path, &report.calls)?;
    }
    if let Some(path) = options.report_file.as_ref() {
        write_json(path, &report)?;
    }
    for line in report.diagnostic_lines() {
        println!("{line}");
    }
    report.verify()?;
    Ok(())
}

enum WaitOutcome {
    Signal,
    Watcher(Result<()>),
}

type StatusWatch = (
    CancellationToken,
    tokio::task::JoinHandle<anyhow::Result<()>>,
);

fn status_watch_failed(joined: Result<anyhow::Result<()>, tokio::task::JoinError>) -> Result<()> {
    match joined {
        Ok(Ok(())) => Ok(()),
        Ok(Err(error)) => Err(error).context("feishu status file cannot be kept fresh"),
        Err(error) => Err(anyhow::Error::new(error).context("feishu status watcher crashed")),
    }
}

async fn wait_for_stop(status_watch: Option<StatusWatch>) -> WaitOutcome {
    let Some((stop, mut handle)) = status_watch else {
        wait_for_signal().await;
        return WaitOutcome::Signal;
    };
    tokio::select! {
        () = wait_for_signal() => {
            stop.cancel();
            let joined = handle.await;
            match status_watch_failed(joined) {
                Ok(()) => WaitOutcome::Signal,
                Err(error) => WaitOutcome::Watcher(Err(error)),
            }
        }
        joined = &mut handle => WaitOutcome::Watcher(status_watch_failed(joined)),
    }
}

async fn wait_for_signal() {
    #[cfg(unix)]
    {
        if let Ok(mut terminate) =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
        {
            tokio::select! {
                _ = tokio::signal::ctrl_c() => {}
                _ = terminate.recv() => {}
            }
            return;
        }
    }
    let _ = tokio::signal::ctrl_c().await;
}

async fn print_shutdown(peer: &mut FeishuPeer) -> Option<FeishuReport> {
    match peer.shutdown().await {
        Ok(report) => Some(report),
        Err(error) => {
            println!(
                "feishu_fixture_failure=shutdown error: {}",
                one_line(&error)
            );
            None
        }
    }
}

fn write_status(
    path: &Path,
    written: &mut Option<FeishuLiveStatus>,
    status: FeishuLiveStatus,
) -> Result<()> {
    if written.as_ref() == Some(&status) {
        return Ok(());
    }
    write_json(path, &status)?;
    *written = Some(status);
    Ok(())
}

fn write_json(path: &Path, value: &impl serde::Serialize) -> Result<()> {
    let parent = path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    serde_json::to_writer_pretty(&mut temporary, value)?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}

fn one_line(error: &anyhow::Error) -> String {
    error.to_string().replace(['\n', '\r'], " ")
}
