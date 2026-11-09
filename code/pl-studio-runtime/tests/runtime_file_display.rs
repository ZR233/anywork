#[expect(dead_code, reason = "shared isolated runtime fixtures")]
mod support;

use anyhow::{Context, Result, ensure};
use pl_core::{context::ContextContent, thread::ToolDelivery};
use pl_protocol::{
    ChatScope, ContentRange, PayloadData, ReadDemand, ThreadWorkspaceMode,
    studio::{StudioPromptInput, SubmitPromptRequest},
};
use pl_studio_runtime::resource_store::RESOURCE_ID_PREFIX;
use pl_tool::file_display::{FileDisplayOrigin, FileDisplayResult, saved_file_display_receipt};
use sea_orm::{ConnectionTrait, Database, DbBackend, Statement};
use serde_json::json;

async fn public_artifact(
    runtime: &pl_studio_runtime::StudioRuntime,
    thread: &str,
    turn: &str,
) -> Result<serde_json::Value> {
    let mut feed = runtime
        .open_conversation_feed(
            thread,
            ChatScope::Children {
                parent_id: pl_core::chat::ChatKey::new("turn", turn)?.as_str().into(),
            },
            ReadDemand {
                max_items: 64,
                max_bytes: 256 * 1024,
            },
        )
        .await?;
    let checked = async {
        let batch = tokio::time::timeout(support::integration_test_deadline()?, async {
            loop {
                if let pl_studio_runtime::ConversationEvent::Chat { batch } =
                    feed.recv().await?.context("public Chat ended")?
                {
                    return Ok::<_, anyhow::Error>(batch);
                }
            }
        })
        .await??;
        ensure!(
            batch.before.is_none(),
            "fixture unexpectedly requires paging"
        );
        for entry in batch.entries {
            let atom = entry.atom;
            let bytes = match atom.payload.context("sealed atom")? {
                PayloadData::Inline { bytes } => bytes,
                PayloadData::Deferred {
                    reference,
                    byte_length,
                } => {
                    ensure!(byte_length < 64 * 1024);
                    feed.reader()
                        .read_content(
                            &reference,
                            ContentRange {
                                offset: 0,
                                max_bytes: 64 * 1024,
                            },
                        )
                        .await?
                        .bytes
                }
            };
            let value: serde_json::Value = serde_json::from_slice(&bytes)?;
            if value["type"] != "tool" || value["data"]["invocation"]["callId"] != "display-call" {
                continue;
            }
            ensure!(value["data"]["invocation"]["presentationContract"] == "builtin.show_files@1");
            let manifest = feed
                .reader()
                .list_contents(
                    &atom.id,
                    None,
                    ReadDemand {
                        max_items: 64,
                        max_bytes: 256 * 1024,
                    },
                )
                .await?;
            let artifacts = manifest
                .entries
                .iter()
                .find(|entry| entry.key == "tool.output-artifacts")
                .context("file display artifact manifest")?;
            let bytes = feed
                .reader()
                .read_content(
                    &artifacts.reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: 64 * 1024,
                    },
                )
                .await?
                .bytes;
            let artifacts: serde_json::Value = serde_json::from_slice(&bytes)?;
            let artifact = artifacts
                .as_array()
                .context("artifact array")?
                .iter()
                .find(|item| {
                    item["kind"] == "opaque" && item["payload"]["format"] == "pl.tool.files"
                })
                .context("versioned file display artifact")?;
            ensure!(artifact["payload"]["version"] == 1);
            return Ok(artifact.clone());
        }
        anyhow::bail!("completed public tool atom missing")
    }
    .await;
    let reader = feed.reader().clone();
    feed.request_close();
    reader.request_close();
    let (feed_closed, reader_closed) = tokio::join!(feed.close(), reader.close());
    let closed = feed_closed.and(reader_closed);
    checked
        .with_context(|| format!("feed close: {closed:?}"))
        .and_then(|value| {
            closed?;
            Ok(value)
        })
}

async fn delivery(home: &std::path::Path, thread: &str, call: &str) -> Result<ToolDelivery> {
    let saved = support::saved(home, thread).await?;
    let db = Database::connect(format!("sqlite://{}?mode=ro", saved.path.display())).await?;
    let row = db
        .query_one_raw(Statement::from_sql_and_values(
            DbBackend::Sqlite,
            "SELECT delivery_payload FROM history_tool_tasks WHERE call_id=?",
            [call.into()],
        ))
        .await?
        .context("original committed file delivery")?;
    let result = serde_json::from_str(&row.try_get::<String>("", "delivery_payload")?)?;
    db.close().await?;
    Ok(result)
}

#[tokio::test]
async fn show_files_real_thread_cold_read_and_archive_reselection() -> Result<()> {
    const BYTES: &[u8] = b"private original file contents\n";
    let digest = pl_core::context::content_hash(BYTES);
    let id = format!(
        "{RESOURCE_ID_PREFIX}{}",
        digest.strip_prefix("sha256:").context("digest")?
    );
    let mut env = support::Environment::new(
        vec![
            support::prompt_step(
                "display",
                0,
                support::tool_reply(
                    "show_files",
                    "display-call",
                    json!({
                        "caption":"  selected files  ", "files":[
                            {"kind":"workspace","path":"report.txt"},
                            {"kind":"workspace","path":"missing.txt"},
                            {"kind":"workspace","path":"report-copy.txt"}
                        ]
                    }),
                ),
            ),
            support::prompt_step("display", 1, support::text_reply("done", "display-done")),
            support::prompt_step(
                "again",
                2,
                support::tool_reply(
                    "show_files",
                    "archive-call",
                    json!({
                        "files":[
                            {"kind":"attachment","attachmentId":id},
                            {"kind":"attachment","attachmentId":"pl.studio.resource:unreferenced"}
                        ]
                    }),
                ),
            ),
            support::prompt_step("again", 3, support::text_reply("done", "archive-done")),
        ],
        Vec::new(),
    )
    .await?;
    let result = async {
        std::fs::write(env.repo.join("report.txt"), BYTES)?;
        std::fs::write(env.repo.join("report-copy.txt"), BYTES)?;
        let started = env.start(ThreadWorkspaceMode::Local, "display").await?;
        let thread = started.thread.id;
        let turn = support::completed_prompt(&env.runtime, &thread, "display").await?;
        let live_artifact = public_artifact(&env.runtime, &thread, &turn.id).await?;
        let requests = env.root_provider.recorded();
        let tool_names: Vec<_> = requests[0].body["tools"].as_array().context("catalog")?
            .iter().filter_map(|tool| tool["name"].as_str()).collect();
        ensure!(tool_names.iter().any(|name| name.ends_with("show_files")));
        ensure!(!tool_names.iter().any(|name| name.ends_with("show_image")));
        let summary = support::tool_output(&env.root_provider, "display-call")?;
        ensure!(!summary.contains(std::str::from_utf8(BYTES)?.trim()));
        ensure!(!summary.contains(&env.repo.to_string_lossy().to_string()));
        // Destroy the original paths before closing and cold reading the actual archived bytes.
        std::fs::remove_file(env.repo.join("report.txt"))?;
        std::fs::remove_file(env.repo.join("report-copy.txt"))?;
        let calls_before_read = env.root_provider.recorded().len();
        env.restart().await?;
        ensure!(public_artifact(&env.runtime, &thread, &turn.id).await? == live_artifact,
            "cold read changed the original display artifact");
        ensure!(env.runtime.read_thread_attachment(thread.clone(), id.clone()).await? == BYTES);
        ensure!(env.root_provider.recorded().len() == calls_before_read, "cold read re-executed model/tool");
        let original = delivery(&env.home, &thread, "display-call").await?;
        ensure!(original.delivered_context.iter().all(|content| !matches!(content, ContextContent::Opaque { .. })));
        let receipt = saved_file_display_receipt(original.output.payload())?.context("file receipt")?;
        ensure!(receipt.caption.as_deref() == Some("selected files") && receipt.files.len() == 3);
        ensure!(matches!(&receipt.files[0], FileDisplayResult::Ready { resource, filename, origin:FileDisplayOrigin::Local { path }, .. }
            if resource.id() == id && filename == "report.txt" && std::path::Path::new(path).is_absolute()));
        ensure!(matches!(&receipt.files[1], FileDisplayResult::Failed { filename, .. } if filename == "missing.txt"));
        ensure!(matches!(&receipt.files[2], FileDisplayResult::Ready { resource, filename, .. }
            if resource.id() == id && filename == "report-copy.txt"));
        // The recovered call resolves the original receipt using the current Thread's frozen
        // context and durable task facts, preserving a filename rather than trusting an id prefix.
        let revision = env.runtime.thread_snapshot(&thread).await?.model_route
            .context("saved model route")?.revision;
        env.runtime.submit_prompt_command(thread.clone(), SubmitPromptRequest {
            input: StudioPromptInput { input_id:"input-again".into(), text:"again".into(), attachment_draft_ids:Vec::new() },
            expected_model_route_revision: revision,
        }).await?;
        support::completed_prompt(&env.runtime, &thread, "again").await?;
        env.restart().await?;
        let selected = delivery(&env.home, &thread, "archive-call").await?;
        let selected = saved_file_display_receipt(selected.output.payload())?.context("archive receipt")?;
        ensure!(matches!(&selected.files[0], FileDisplayResult::Ready { resource, filename, .. }
            if resource.id() == id && filename == "report.txt"));
        ensure!(matches!(&selected.files[1], FileDisplayResult::Failed { .. }));
        ensure!(env.runtime.read_thread_attachment(thread.clone(), id.clone()).await? == BYTES);
        ensure!(env.runtime.read_thread_attachment(thread, "pl.studio.resource:unreferenced".into()).await.is_err());
        Ok(())
    }.await;
    env.finish(result).await
}
