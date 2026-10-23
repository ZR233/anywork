//! reqwest/rustls transport with downlowd owning resume, checkpoints, retries and file writes.

use std::path::PathBuf;
use std::time::{Duration, Instant};

use tokio::sync::mpsc::{Sender, error::TrySendError};
use tokio_util::sync::CancellationToken;

use super::error::{StudioUpdateError, StudioUpdateErrorCode};
use super::types::{StudioUpdateAsset, StudioUpdateEvent};

pub(super) async fn download(
    client: &downlowd::Client,
    asset: StudioUpdateAsset,
    destination: PathBuf,
    progress: Sender<StudioUpdateEvent>,
    cancellation: CancellationToken,
) -> Result<(), StudioUpdateError> {
    match tokio::fs::metadata(&destination).await {
        Ok(metadata) if metadata.len() == asset.size => {
            sync_downloaded_file(&destination, asset.size).await?;
            report(&progress, asset.size, asset.size).await?;
            return Ok(());
        }
        Ok(_) => tokio::fs::remove_file(&destination)
            .await
            .map_err(io_error)?,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(io_error(error)),
    }
    let total = asset.size;
    let started = Instant::now();
    let mut last_report = None;
    let (failure, mut failures) = tokio::sync::mpsc::channel(1);
    let retry_failure = failure.clone();
    let progress_cancellation = cancellation.clone();
    let retry_cancellation = cancellation.clone();
    let progress_events = progress.clone();
    let result = client
        .get(asset.url)
        .destination(&destination)
        .on_progress(move |state| {
            let violation = if state.bytes() > total {
                Some((
                    StudioUpdateErrorCode::DownloadTooLarge,
                    "installer exceeded its declared size",
                ))
            } else if state.remote_length().is_some_and(|length| length != total) {
                Some((
                    StudioUpdateErrorCode::DownloadIncomplete,
                    "installer length does not match the manifest",
                ))
            } else if started.elapsed() >= Duration::from_secs(15 * 60) {
                Some((
                    StudioUpdateErrorCode::Network,
                    "installer download exceeded its 15 minute deadline",
                ))
            } else {
                None
            };
            if let Some((code, message)) = violation {
                let _ = failure.try_send(StudioUpdateError::new(code, message));
                state.cancel();
                return;
            }
            if progress_cancellation.is_cancelled() {
                state.cancel();
                return;
            }
            // The callback fires before downlowd has flushed/closed the destination. Only
            // intermediate samples may be coalesced here; authoritative total is sent below.
            if state.bytes() < total
                && last_report.is_none_or(|last: Instant| last.elapsed() >= Duration::from_millis(250)) {
                match progress_events.try_send(StudioUpdateEvent::Progress { downloaded: state.bytes(), total }) {
                    Ok(()) | Err(TrySendError::Full(_)) => {}
                    Err(TrySendError::Closed(_)) => {
                        let _ = failure.try_send(StudioUpdateError::new(
                            StudioUpdateErrorCode::Io,
                            "the update progress owner stopped during download",
                        ));
                        progress_cancellation.cancel();
                        state.cancel();
                    }
                }
                last_report = Some(Instant::now());
            }
        })
        .on_retry(move |retry| {
            if started.elapsed() >= Duration::from_secs(15 * 60) {
                let _ = retry_failure.try_send(StudioUpdateError::new(
                    StudioUpdateErrorCode::Network,
                    "installer download exceeded its 15 minute deadline",
                ));
                retry.cancel();
            } else if retry_cancellation.is_cancelled() || retry.total_tries() >= 4 {
                retry.cancel();
            } else {
                retry.set_delay(retry.delay().min(Duration::from_secs(2)));
            }
        })
        .send()
        .await;
    // Do not drop a pending download future on cancellation. The library must observe its
    // callbacks, flush and close its file before the cache lease or shutdown owner is released.
    if let Ok(error) = failures.try_recv() {
        return Err(error);
    }
    if cancellation.is_cancelled() {
        return Err(StudioUpdateError::new(
            StudioUpdateErrorCode::Cancelled,
            "Studio update download was cancelled; partial file retained",
        ));
    }
    result.map_err(download_error)?;
    sync_downloaded_file(&destination, total).await?;
    report(&progress, total, total).await?;
    Ok(())
}

async fn sync_downloaded_file(destination: &std::path::Path, total: u64) -> Result<(), StudioUpdateError> {
    let file = tokio::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(destination)
        .await
        .map_err(io_error)?;
    file.sync_all().await.map_err(io_error)?;
    if file.metadata().await.map_err(io_error)?.len() != total {
        return Err(StudioUpdateError::new(
            StudioUpdateErrorCode::DownloadIncomplete,
            "downloaded installer length does not match the manifest",
        ));
    }
    Ok(())
}

async fn report(progress: &Sender<StudioUpdateEvent>, downloaded: u64, total: u64) -> Result<(), StudioUpdateError> {
    super::install::send_event(progress, StudioUpdateEvent::Progress { downloaded, total }).await
}

pub(super) fn download_error(error: downlowd::Error) -> StudioUpdateError {
    let code = match &error {
        downlowd::Error::Write { .. } => StudioUpdateErrorCode::Io,
        downlowd::Error::BadRedirect { .. }
        | downlowd::Error::InvalidUrl { .. }
        | downlowd::Error::InvalidConfig { .. }
        | downlowd::Error::InvalidHeader { .. } => StudioUpdateErrorCode::InvalidManifest,
        downlowd::Error::Cancelled => StudioUpdateErrorCode::Cancelled,
        _ => StudioUpdateErrorCode::Network,
    };
    // CDN redirect URLs contain temporary credentials; downlowd strips the reqwest cause URL.
    StudioUpdateError::new(
        code,
        format!("installer download failed: {}", error.without_uri()),
    )
}

fn io_error(error: std::io::Error) -> StudioUpdateError {
    StudioUpdateError::new(
        StudioUpdateErrorCode::Io,
        format!("installer file operation failed: {error}"),
    )
}
