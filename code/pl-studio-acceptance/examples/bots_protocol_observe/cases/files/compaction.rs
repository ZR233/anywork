//! Real Studio factory, ordinary HTTP admission, manual compact, replacement,
//! physical-copy deletion and cold factory recovery. No core/model fake is used.
use super::super::Session;
use super::compaction_owner::CompactTerminal;
use super::{input, requests, wait_idle, write_json};
use crate::{env, http};
use anyhow::{Context, Result, ensure};
use pl_protocol::{
    TimelinePageQuery,
    studio::{CreateThreadRequest, NewThreadModelRoute, StudioAttachmentAdmissionContext},
};
use pl_provider_fixture::bots_observe as model;
use pl_studio_runtime::StudioRuntime;
use std::{path::PathBuf, time::Duration};

const ORIGINAL: &[u8] = b"Old Turn reliable original. Not included in generated compaction summary.\nD2-compaction-file-tail\n";

pub(super) async fn run(session: &mut Session, evidence: &mut Vec<String>) -> Result<String> {
    let project = session
        .http()?
        .open_project(&session.project.to_string_lossy())
        .await?;
    // One explicit route serves both the draft admission and the Thread
    // creation, so the admitted originals can never be admitted against a
    // different model than the one the Thread really runs.
    let route = NewThreadModelRoute {
        account_id: env::model_account_id(&session.home)?,
        model_id: "fixture-model".into(),
        effort: None,
    };
    let drafts = session
        .http()?
        .upload_files(
            &StudioAttachmentAdmissionContext::NewThread {
                route: route.clone(),
            },
            &[("old-original.noext".into(), ORIGINAL.to_vec())],
        )
        .await?;
    ensure!(
        drafts.drafts.len() == 1 && drafts.drafts[0].byte_size == ORIGINAL.len() as u64,
        "ordinary HTTP admission did not preserve the user file"
    );
    let mut first = input("compact-file-input", model::COMPACT_FILE);
    first.attachment_draft_ids = vec![drafts.drafts[0].draft_id.clone()];
    let created = session
        .http()?
        .create_thread(
            &project.id,
            &CreateThreadRequest {
                title: Some("D2 real manual compaction".into()),
                input: first,
                mode: pl_protocol::ThreadModeId::SIMPLE.into(),
                route: route.clone(),
                delegation_mode: None,
                delegation_preference: None,
                workspace_mode: Default::default(),
            },
        )
        .await?;
    let thread_id = created.thread.id;
    requests::wait_executions(session, 1).await?;
    wait_idle(session, &thread_id).await?;
    let originals = requests::originals(session, &thread_id).await?;
    ensure!(
        originals.len() == 1
            && originals[0].byte_len == ORIGINAL.len()
            && originals[0].sha256 == model::sha256(ORIGINAL),
        "ordinary reliable attachment endpoint did not return the exact original"
    );
    let original = originals[0].clone();
    session
        .http()?
        .submit(
            &thread_id,
            input("compact-puretext-input", model::COMPACT_TEXT),
        )
        .await?;
    requests::wait_executions(session, 2).await?;
    wait_idle(session, &thread_id).await?;
    let last = requests::execution_requests(session)
        .pop()
        .context("puretext request missing")?;
    ensure!(
        requests::user_texts(&last)?
            .iter()
            .any(|text| text == model::COMPACT_TEXT),
        "current Turn was not pure text"
    );
    let files = requests::files(&last)?;
    ensure!(
        files.len() == 1,
        "old Turn file must still be a real file description before compaction"
    );
    let workspace = PathBuf::from(
        session
            .http()?
            .thread(&thread_id)
            .await?
            .thread
            .workspace_path,
    );
    let uploads = requests::thread_uploads(&workspace, &thread_id)?;
    let copy = requests::verify_file(&uploads, &files[0], &original)?;
    evidence.push(format!("ordinary HTTP user file -> old Turn; current Turn pure text; reliable attachment={} copy={} len={} sha256={}", original.attachment_id, files[0].path, original.byte_len, original.sha256));

    // HTTP does not publish a compact endpoint. Stop and reap that owner
    // before opening the same home with the actual public StudioRuntime API.
    let mut server = session.server.take().context("HTTP server not running")?;
    let pids = server.pids();
    server.stop()?;
    session.http = None;
    evidence.push(format!(
        "HTTP server stopped/reaped before public-runtime manual compact: {pids:?}"
    ));
    session.compaction_owner.initialize(&session.home).await?;
    let runtime = session.compaction_owner.runtime()?;
    let compact_result = manual_compact(&runtime, &thread_id, session, evidence).await;
    let first_close = session.compaction_owner.close().await;
    drop(runtime);
    compact_result?;
    first_close?;

    // Delete ONLY the verified execution copy, never the reliable resource.
    ensure!(
        std::fs::read(&copy)?.as_slice() == ORIGINAL,
        "execution copy changed before explicit deletion"
    );
    std::fs::remove_file(&copy)?;
    ensure!(
        !copy.exists(),
        "observer did not remove its isolated execution copy"
    );
    session.compaction_owner.initialize(&session.home).await?;
    let cold = session.compaction_owner.runtime()?;
    let cold_result =
        cold_recovery(&cold, &thread_id, &workspace, &original, session, evidence).await;
    let cold_close = session.compaction_owner.close().await;
    drop(cold);
    cold_result?;
    cold_close?;
    write_json(session, "compact-original.json", &original)?;
    Ok("ordinary text-only Studio Thread retained an old-Turn user file through a real explicit compact of current pure text; replacement and cold factory recovery rebuilt deleted execution copies from exact reliable bytes; closing a second genuinely held compact cancelled and joined it".into())
}

async fn manual_compact(
    runtime: &StudioRuntime,
    thread_id: &str,
    session: &mut Session,
    evidence: &mut Vec<String>,
) -> Result<()> {
    runtime.restore_thread(thread_id.to_owned()).await?;
    session.compaction_owner.spawn_compact(thread_id)?;
    let compact = session
        .compaction_owner
        .join_compact(Duration::from_secs(35))
        .await
        .context(
            "real Studio manual compact did not complete (possible upload-mutex/gate deadlock)",
        )?;
    ensure!(
        matches!(compact, CompactTerminal::Succeeded),
        "real manual compact failed: {compact:?}"
    );
    requests::wait_executions(session, 3).await?;
    let page = runtime
        .timeline_page(
            thread_id,
            &TimelinePageQuery {
                before: None,
                limit: Some(100),
            },
        )
        .await?;
    ensure!(
        page.items.iter().any(|item| matches!(
            item.preview.state(),
            pl_protocol::ThreadItemState::ContextCompaction(_)
        )),
        "manual compact did not publish a real context replacement timeline fact"
    );
    evidence.push("public StudioRuntime::compact_thread completed and published ContextCompaction; synthetic summary deliberately omitted file paths/bytes".into());
    let old_request = requests::execution_requests(session)
        .into_iter()
        .nth(1)
        .context("old puretext request missing before copy deletion")?;
    let old_files = requests::files(&old_request)?;
    ensure!(
        old_files.len() == 1,
        "old reliable file description disappeared before explicit deletion"
    );
    let workspace = PathBuf::from(
        runtime
            .thread_snapshot(thread_id)
            .await?
            .thread
            .workspace_path,
    );
    let uploads = requests::thread_uploads(&workspace, thread_id)?;
    let old_copy = requests::physical_path(&uploads, &old_files[0])?;
    ensure!(
        std::fs::read(&old_copy)?.as_slice() == ORIGINAL,
        "execution copy changed before replacement rebuild"
    );
    std::fs::remove_file(&old_copy)?;
    ensure!(
        !old_copy.exists(),
        "replacement rebuild did not start from an absent execution copy"
    );
    runtime
        .submit_prompt_command(
            thread_id.into(),
            pl_protocol::studio::SubmitPromptRequest {
                input: input("compact-after-input", model::COMPACT_AFTER),
                expected_model_route_revision: route_revision(runtime, thread_id).await?,
            },
        )
        .await?;
    requests::wait_executions(session, 4).await?;
    runtime_idle(runtime, thread_id).await?;
    let request = requests::execution_requests(session)
        .pop()
        .context("post-compact request missing")?;
    let files = requests::files(&request)?;
    ensure!(
        files.len() == 1,
        "context replacement lost old Turn user-file inventory"
    );
    let bytes = std::fs::read(requests::physical_path(&uploads, &files[0])?)?;
    ensure!(
        bytes.as_slice() == ORIGINAL,
        "post-compact file bytes changed"
    );
    evidence.push(format!(
        "replacement request retained file={} sha256={}",
        files[0].path,
        model::sha256(&bytes)
    ));
    Ok(())
}

async fn cold_recovery(
    runtime: &StudioRuntime,
    thread_id: &str,
    workspace: &std::path::Path,
    original: &requests::Original,
    session: &mut Session,
    evidence: &mut Vec<String>,
) -> Result<()> {
    runtime.restore_thread(thread_id.to_owned()).await?;
    runtime
        .submit_prompt_command(
            thread_id.into(),
            pl_protocol::studio::SubmitPromptRequest {
                input: input("compact-cold-input", model::COMPACT_COLD),
                expected_model_route_revision: route_revision(runtime, thread_id).await?,
            },
        )
        .await?;
    requests::wait_executions(session, 5).await?;
    runtime_idle(runtime, thread_id).await?;
    let request = requests::execution_requests(session)
        .pop()
        .context("cold restored request missing")?;
    let files = requests::files(&request)?;
    ensure!(
        files.len() == 1,
        "cold restore lost compacted file inventory"
    );
    let uploads = requests::thread_uploads(workspace, thread_id)?;
    let copy = requests::verify_file(&uploads, &files[0], original)?;
    let bytes = runtime
        .read_thread_attachment(thread_id.into(), original.attachment_id.clone())
        .await?;
    ensure!(
        bytes.as_slice() == ORIGINAL,
        "cold reliable resource read differs from original"
    );
    evidence.push(format!(
        "cold factory rebuilt deleted copy={} len={} sha256={}",
        files[0].path,
        bytes.len(),
        model::sha256(&bytes)
    ));
    // A second real compaction blocks in the provider. Shutdown is a public
    // cancellation operation and must finish both itself and the in-flight
    // compact future; dropping the join handle is never accepted as cleanup.
    std::fs::remove_file(copy)?;
    session.compaction_owner.spawn_compact(thread_id)?;
    let reached = requests::wait_executions(session, 6).await;
    let closed = session.compaction_owner.close().await;
    reached?;
    let closed = closed?;
    ensure!(
        closed.runtime_closed
            && closed.compact_pending_before_shutdown
            && closed.compact_joined
            && !closed.compact_aborted
            && matches!(
                closed.compact_terminal.as_ref(),
                Some(CompactTerminal::Failed { .. })
            ),
        "held compact did not cancel/join naturally after public shutdown: {closed:?}"
    );
    evidence.push("real provider-held compact observed; public shutdown completed; compact future returned cancellation/error and its task was joined".into());
    Ok(())
}

async fn route_revision(runtime: &StudioRuntime, thread_id: &str) -> Result<u64> {
    runtime
        .thread_snapshot(thread_id)
        .await?
        .runtime
        .and_then(|runtime| runtime.model_route)
        .map(|route| route.revision)
        .context("public runtime model route missing")
}

async fn runtime_idle(runtime: &StudioRuntime, thread_id: &str) -> Result<()> {
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        Ok(runtime
            .thread_snapshot(thread_id)
            .await?
            .active_turn
            .is_none())
    })
    .await
}
