//! Explicit display facts, bound to the original canonical input/Turn owner.

use super::owner::ReplyRun;
use super::projection::ReplyProjection;
use crate::bots::InboundWorkOutcome;
use crate::channel_output::{ChannelDeliveryResult, ChannelTarget, FileDelivery};
use crate::studio::StudioRuntime;
use pl_tool::file_display::{AttachmentModality, FileDisplayResult, ResourceReference};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

fn operation(
    thread: &str,
    turn: &str,
    call: &str,
    index: Option<usize>,
    target: &ChannelTarget,
) -> String {
    let identity = serde_json::to_vec(&(thread, turn, call, index, target))
        .expect("file delivery identity contains only strings and an index");
    format!("file-display:{}", hex::encode(Sha256::digest(identity)))
}

pub(super) async fn deliver_file_displays(
    runtime: &StudioRuntime,
    run: &mut ReplyRun,
    turn_id: &str,
    projection: &ReplyProjection,
    cancel: &CancellationToken,
) -> Result<(), InboundWorkOutcome> {
    let binding = run.output.clone();
    let target = binding.target();
    let mut failures = Vec::new();
    for (call, receipt) in projection.file_displays() {
        let display = operation(&run.thread_id, turn_id, call, None, target);
        if run.delivered_displays.contains(&display) {
            continue;
        }
        if cancel.is_cancelled() {
            return Err(InboundWorkOutcome::Interrupted);
        }
        if let Some(caption) = &receipt.caption
            && receipt.files.iter().any(|file| {
                matches!(
                    file,
                    FileDisplayResult::Ready { .. } | FileDisplayResult::Deferred { .. }
                )
            })
        {
            record_result(
                binding
                    .send_caption(&format!("{display}:caption"), caption, cancel)
                    .await,
                "file caption",
                &mut failures,
            )?;
        }
        for (index, file) in receipt.files.iter().enumerate() {
            if cancel.is_cancelled() {
                return Err(InboundWorkOutcome::Interrupted);
            }
            let (file, bytes) = match file {
                FileDisplayResult::Ready {
                    resource,
                    filename,
                    modality,
                    ..
                } => {
                    let bytes = runtime
                        .read_thread_attachment(run.thread_id.clone(), resource.id().into())
                        .await
                        .map_err(|error| InboundWorkOutcome::Recoverable {
                            diagnostic: error.to_string(),
                        })?;
                    (
                        FileDelivery {
                            resource: resource.clone(),
                            filename: filename.clone(),
                            modality: *modality,
                        },
                        bytes,
                    )
                }
                FileDisplayResult::Deferred {
                    filename,
                    target: source,
                } => {
                    if binding
                        .deferred_file_limit()
                        .is_none_or(|limit| source.size > limit)
                    {
                        failures.push(format!(
                            "file item {index}: channel does not support this file size"
                        ));
                        continue;
                    }
                    let bytes = match runtime
                        .read_deferred_display_for_channel(&run.thread_id, source, cancel)
                        .await
                    {
                        Ok(Some(bytes)) => bytes,
                        Ok(None) => return Err(InboundWorkOutcome::Interrupted),
                        Err(error) => {
                            failures.push(format!("file item {index}: {error}"));
                            continue;
                        }
                    };
                    let digest = hex::encode(Sha256::digest(&bytes));
                    let resource = ResourceReference::new(
                        format!("channel-file:{digest}"),
                        format!("sha256:{digest}"),
                        source.size,
                        "application/octet-stream".into(),
                    )
                    .map_err(|error| InboundWorkOutcome::Recoverable {
                        diagnostic: error.to_string(),
                    })?;
                    (
                        FileDelivery {
                            resource,
                            filename: filename.clone(),
                            modality: AttachmentModality::File,
                        },
                        bytes,
                    )
                }
                FileDisplayResult::NetworkImage { .. } | FileDisplayResult::Failed { .. } => {
                    continue;
                }
            };
            let result = binding
                .send_file(
                    &operation(&run.thread_id, turn_id, call, Some(index), target),
                    &file,
                    bytes,
                    cancel,
                )
                .await;
            if cancel.is_cancelled() {
                return Err(InboundWorkOutcome::Interrupted);
            }
            record_result(result, &format!("file item {index}"), &mut failures)?;
        }
        run.delivered_displays.insert(display);
    }
    if !failures.is_empty() {
        // File status does not erase the independent final-text obligation.
        // Terminal completion is converted to NeedsAttention by the original owner.
        run.file_delivery_diagnostic = Some(format!(
            "explicit file delivery incomplete: {}",
            failures.join("; ")
        ));
    }
    Ok(())
}

fn record_result(
    result: ChannelDeliveryResult,
    item: &str,
    failures: &mut Vec<String>,
) -> Result<(), InboundWorkOutcome> {
    match result {
        ChannelDeliveryResult::Confirmed { .. } => Ok(()),
        ChannelDeliveryResult::Rejected {
            diagnostic,
            retryable: true,
        } => Err(InboundWorkOutcome::Recoverable { diagnostic }),
        ChannelDeliveryResult::Rejected {
            diagnostic,
            retryable: false,
        }
        | ChannelDeliveryResult::Unknown { diagnostic } => {
            failures.push(format!("{item}: {diagnostic}"));
            Ok(())
        }
    }
}
