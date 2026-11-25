use crate::support;

use anyhow::{Context, Result, ensure};
use pl_core::context::OpaquePayload;
use pl_studio_runtime::{
    ChatScope, ThreadWorkspaceMode,
    history::{HistoryDemand, HistoryEventsQuery, read_event_body_bytes},
    resource_store::RESOURCE_ID_PREFIX,
};
use pl_tool::file_display::saved_file_display_receipt;
use serde_json::json;

async fn public_artifact(
    runtime: &pl_studio_runtime::StudioRuntime,
    thread: &str,
    turn: &str,
) -> Result<serde_json::Value> {
    let demand = HistoryDemand {
        max_rows: 128,
        max_bytes: 256 * 1024,
    };
    let reader = runtime
        .open_history_reader(thread, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
        .await?;
    let checked = async {
        let originals = reader
            .events_page(
                HistoryEventsQuery::Originals {
                    scope: ChatScope::conversation(None),
                },
                None,
                None,
                demand,
            )
            .await?;
        ensure!(!originals.entries.is_empty(), "history has no originals");
        for event in originals.entries {
            if event.payload_schema != "anywork.event/1" {
                continue;
            }
            let value: serde_json::Value = serde_json::from_str(&event.payload_json)?;
            if event.turn_id.as_deref() != Some(turn)
                || value["type"] != "tool"
                || value["data"]["invocation"]["name"] != "show_files"
            {
                continue;
            }
            ensure!(event.turn_id.as_deref() == Some(turn));
            ensure!(value["data"]["invocation"]["presentationContract"] == "builtin.show_files@1");
            let bytes = read_event_body_bytes(&reader, &event, "tool.output-artifacts", None)
                .await?
                .context("file display artifact manifest")?;
            let artifacts: serde_json::Value = serde_json::from_slice(&bytes)?;
            let artifact = artifacts
                .as_array()
                .context("artifact array")?
                .iter()
                .find(|item| {
                    item["kind"] == "opaque" && item["payload"]["format"] == "pl.tool.files"
                })
                .context("versioned file display artifact")?;
            ensure!(artifact["payload"]["version"] == 2);
            return Ok(artifact.clone());
        }
        anyhow::bail!("completed public tool original missing")
    }
    .await;
    reader.close().await;
    checked
}

fn show_files_reply(call: &str, arguments: serde_json::Value) -> pl_provider_fixture::Reply {
    let encoded = pl_provider_fixture::RealtimeToolCall {
        item_id: call,
        call_id: call,
        name: "show_files",
        arguments: arguments.to_string(),
    }
    .program("show_files");
    let mut input: serde_json::Value = serde_json::from_str(&encoded.arguments).unwrap();
    let invocation = input["code"]
        .as_str()
        .unwrap()
        .strip_prefix("return ")
        .unwrap();
    input["code"] =
        format!("local r={invocation}; return {{caption=r.caption, id=r.files[1].resource.id}}")
            .into();
    support::tool_reply("exec", call, input)
}

#[tokio::test]
async fn show_files_real_thread_cold_read_and_archive_reselection() -> Result<()> {
    const BYTES: &[u8] = b"private original file contents\n";
    const UNSELECTED: &[u8] = b"unselected original file contents\n";
    let digest = pl_core::context::content_hash(BYTES);
    let id = format!(
        "{RESOURCE_ID_PREFIX}{}",
        digest.strip_prefix("sha256:").context("digest")?
    );
    let unselected_id = format!(
        "{RESOURCE_ID_PREFIX}{}",
        pl_core::context::content_hash(UNSELECTED)
            .strip_prefix("sha256:")
            .context("digest")?
    );
    let mut env = support::Environment::new(
        vec![
            support::prompt_step(
                "display",
                0,
                show_files_reply(
                    "display-call",
                    json!({
                        "caption":"  selected files  ", "files":[
                            {"kind":"workspace","path":"report.txt"},
                            {"kind":"workspace","path":"missing.txt"},
                            {"kind":"workspace","path":"report-copy.txt"},
                            {"kind":"workspace","path":"unselected.txt"}
                        ]
                    }),
                ),
            ),
            support::prompt_step("display", 1, support::text_reply("done", "display-done")),
            support::prompt_step(
                "again",
                2,
                show_files_reply(
                    "archive-call",
                    json!({
                        "files":[
                            {"kind":"attachment","attachmentId":id},
                            {"kind":"attachment","attachmentId":"pl.studio.resource:unreferenced"},
                            {"kind":"attachment","attachmentId":unselected_id}
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
        std::fs::write(env.repo.join("unselected.txt"), UNSELECTED)?;
        let started = env.start(ThreadWorkspaceMode::Local, "display").await?;
        let thread = started.thread.id;
        let turn = support::completed_prompt(&env.runtime, &thread, "display").await?;
        let live_artifact = public_artifact(&env.runtime, &thread, &turn.id).await?;
        let requests = env.root_provider.recorded();
        let catalog = requests[0].body["tools"].as_array().context("catalog")?;
        ensure!(!catalog.iter().any(|tool| {
            tool["name"]
                .as_str()
                .is_some_and(|name| name.ends_with("show_files"))
        }));
        ensure!(catalog.iter().any(|tool| {
            tool["name"] == "exec"
                && tool["description"]
                    .as_str()
                    .is_some_and(|text| text.contains("tools[\"show_files\"]"))
        }));
        ensure!(!catalog.iter().any(|tool| {
            tool["name"]
                .as_str()
                .is_some_and(|name| name.ends_with("show_image"))
        }));
        let summary = support::tool_output(&env.root_provider, "display-call")?;
        ensure!(!summary.contains(std::str::from_utf8(BYTES)?.trim()));
        ensure!(!summary.contains(&env.repo.to_string_lossy().to_string()));
        ensure!(
            !summary.contains(&unselected_id),
            "unselected resource capability reached model context"
        );

        std::fs::remove_file(env.repo.join("report.txt"))?;
        std::fs::remove_file(env.repo.join("report-copy.txt"))?;
        std::fs::remove_file(env.repo.join("unselected.txt"))?;
        let calls_before_read = env.root_provider.recorded().len();
        env.restart().await?;
        ensure!(
            public_artifact(&env.runtime, &thread, &turn.id).await? == live_artifact,
            "cold History read changed the original display artifact"
        );
        ensure!(
            env.runtime
                .read_thread_attachment(thread.clone(), id.clone())
                .await?
                == BYTES
        );
        ensure!(
            env.root_provider.recorded().len() == calls_before_read,
            "cold read re-executed model/tool"
        );

        let revision = env
            .runtime
            .thread_snapshot(&thread)
            .await?
            .model_route
            .context("saved model route")?
            .revision;
        env.runtime
            .submit_prompt_command(
                thread.clone(),
                pl_studio_runtime::SubmitPromptRequest {
                    input: pl_studio_runtime::StudioPromptInput {
                        input_id: "input-again".into(),
                        text: "again".into(),
                        attachment_draft_ids: Vec::new(),
                    },
                    expected_model_route_revision: revision,
                },
            )
            .await?;
        let archive_turn = support::completed_prompt(&env.runtime, &thread, "again").await?;
        let archive_artifact = public_artifact(&env.runtime, &thread, &archive_turn.id).await?;
        let payload: OpaquePayload = serde_json::from_value(archive_artifact["payload"].clone())?;
        let receipt = saved_file_display_receipt(&payload)?.context("archive file receipt")?;
        ensure!(receipt.caption.is_none());
        ensure!(receipt.files.len() == 3);
        ensure!(
            env.runtime
                .read_thread_attachment(thread.clone(), id.clone())
                .await?
                == BYTES
        );
        ensure!(
            env.runtime
                .read_thread_attachment(thread, "pl.studio.resource:unreferenced".into())
                .await
                .is_err()
        );
        Ok(())
    }
    .await;
    env.finish(result).await
}
