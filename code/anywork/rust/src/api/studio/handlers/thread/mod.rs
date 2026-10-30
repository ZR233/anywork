use crate::api::studio::convert::commands::command_receipt;
use crate::frb_generated::StreamSink;
use anyhow::Context;
use std::sync::Arc;

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::records::thread_from_record;
use crate::api::studio::convert::{
    settings::bridge_settings_snapshot,
    thread_stream::{bridge_thread, runtime_snapshot},
};
use crate::api::studio::types::{
    ArchiveThreadResult, BridgeArchiveThreadCommandReply, BridgeError, BridgeNewThreadStartEvent,
    BridgeRenameThreadCommandReply, BridgeStartNewThreadRequest, BridgeThread,
    BridgeThreadModeCommandReply, BridgeThreadModelRouteCommandReply, StartNewThreadResponse,
    SubmitPromptResponse,
};
use pl_studio_runtime::ThreadModeId;

fn thread_mode(mode: String) -> Result<ThreadModeId, BridgeError> {
    ThreadModeId::new(mode).map_err(|error| anyhow::anyhow!(error).into())
}

/// Streams preparation and one terminal outcome while creating a root Thread.
///
/// Creation errors are carried by `Failed` after the normal resource settlement;
/// losing the sink does not cancel creation. `Succeeded` confirms acceptance of the
/// first input, independently of its later model execution or history persistence.
pub async fn start_new_thread(
    request: BridgeStartNewThreadRequest,
    sink: StreamSink<BridgeNewThreadStartEvent>,
) -> Result<(), BridgeError> {
    let BridgeStartNewThreadRequest {
        workspace_id,
        input,
        mode,
        account_id,
        model_id,
        effort,
        workspace_mode,
        delegation_mode,
        delegation_preference,
    } = request;
    // One invocation owns both observation and the final command outcome. A closed sink
    // only loses observation; the existing creation owner still settles all resources.
    let progress_sink = sink.clone();
    let response: Result<StartNewThreadResponse, BridgeError> = async {
        let mode = thread_mode(mode)?;
        let workspace_mode = match workspace_mode.as_deref().map(str::trim) {
            None | Some("") | Some("local") => pl_protocol::ThreadWorkspaceMode::Local,
            Some("worktree") => pl_protocol::ThreadWorkspaceMode::Worktree,
            Some(other) => {
                return Err(anyhow::anyhow!(
                    "workspaceMode must be local or worktree, received {other:?}"
                )
                .into());
            }
        };
        let bridge = active_bridge().await?;
        let response = bridge
            .studio
            .create_thread_command(
                workspace_id,
                pl_protocol::studio::CreateThreadRequest {
                    title: None,
                    input: input.into(),
                    mode: mode.label().to_string(),
                    route: pl_protocol::studio::NewThreadModelRoute {
                        account_id,
                        model_id,
                        effort,
                    },
                    workspace_mode,
                    delegation_mode: Some(delegation_mode.into()),
                    delegation_preference: Some(delegation_preference.into()),
                },
                Some(Arc::new(move |progress| {
                    let _ = progress_sink.add(BridgeNewThreadStartEvent::Progress(progress.into()));
                })),
            )
            .await?;
        Ok(StartNewThreadResponse {
            thread: bridge_thread(thread_from_record(response.thread)),
            receipt: SubmitPromptResponse {
                thread_id: response.submission.thread_id,
                input_id: response.submission.input_id,
                revision: response.submission.cursor,
            },
        })
    }
    .await;
    let event = match response {
        Ok(response) => BridgeNewThreadStartEvent::Succeeded(Box::new(response)),
        Err(error) => BridgeNewThreadStartEvent::Failed(error),
    };
    let _ = sink.add(event);
    Ok(())
}

/// Renames a root Thread and returns its canonical directory record.
pub async fn rename_thread(
    operation_id: String,
    thread_id: String,
    title: String,
) -> Result<BridgeRenameThreadCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .rename_thread(operation_id, thread_id, title)
        .await?;
    Ok(BridgeRenameThreadCommandReply {
        thread: bridge_thread(thread_from_record(response.thread)),
        receipt: command_receipt(response.receipt),
    })
}

/// Archives a root Thread and selects the next available Thread.
///
/// # Errors
///
/// Returns an error when the Thread does not exist, is a child Thread, or its tree is active.
pub async fn archive_thread(
    operation_id: String,
    thread_id: String,
) -> Result<BridgeArchiveThreadCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let archived = bridge
        .studio
        .archive_thread(operation_id, thread_id)
        .await?
        .context("selected Thread not found")?;
    Ok(BridgeArchiveThreadCommandReply {
        result: ArchiveThreadResult {
            archived_root_id: archived.result.archived_root_id,
            removed_thread_ids: archived.result.removed_thread_ids,
            next_root: archived
                .result
                .next_root
                .map(thread_from_record)
                .map(bridge_thread),
        },
        receipt: command_receipt(archived.receipt),
    })
}

/// Forces one idle context compaction through the canonical Thread owner.
pub async fn compact_thread(thread_id: String) -> Result<(), BridgeError> {
    active_bridge()
        .await?
        .studio
        .compact_thread(&thread_id)
        .await?;
    Ok(())
}

/// Changes the selected root Thread to a registered Thread Mode ID.
///
/// # Errors
///
/// Returns an error when the Thread does not exist, is a child Thread, or is busy.
pub async fn set_thread_mode(
    operation_id: String,
    thread_id: String,
    mode: String,
) -> Result<BridgeThreadModeCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .set_thread_mode(operation_id, &thread_id, thread_mode(mode)?)
        .await?;
    Ok(BridgeThreadModeCommandReply {
        receipt: command_receipt(response.receipt),
    })
}

/// Changes a root Thread's durable model route. The active Turn keeps its admitted binding.
pub async fn set_thread_model_route(
    operation_id: String,
    thread_id: String,
    account_id: String,
    model_id: String,
    effort: Option<String>,
    expected_model_route_revision: u64,
    expected_settings_revision: u64,
) -> Result<BridgeThreadModelRouteCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    let response = bridge
        .studio
        .save_thread_model_route(
            &thread_id,
            pl_protocol::studio::SetThreadModelRouteRequest {
                operation_id,
                expected_model_route_revision,
                expected_settings_revision,
                account_id,
                model_id,
                effort,
            },
        )
        .await?;
    Ok(BridgeThreadModelRouteCommandReply {
        receipt: command_receipt(response.receipt),
        runtime: runtime_snapshot(response.runtime),
        settings: bridge_settings_snapshot(response.settings),
        mode_default_saved: response.mode_default_saved,
        warning: response.warning,
    })
}

/// Restores an archived session tree with its original identity and history.
pub async fn restore_thread(thread_id: String) -> Result<BridgeThread, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_thread(thread_from_record(
        bridge.studio.restore_thread(thread_id).await?,
    )))
}
