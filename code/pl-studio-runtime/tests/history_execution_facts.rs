#[expect(
    dead_code,
    reason = "shared isolated fixtures serve several integration binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_studio_runtime::{
    CURRENT_PROTOCOL_VERSION, ChatAtomKind, ChatScope, ThreadWorkspaceMode,
    history::{
        HistoryBodyRole, HistoryDemand, HistoryEventBodyRef, HistoryEventsQuery, HistoryReader,
    },
};
use sea_orm::{ConnectionTrait, Database, DbBackend, Statement};
use support::{Environment, completed_prompt, current_demand, prompt_step, text_reply};

async fn body(reader: &HistoryReader, reference: &HistoryEventBodyRef) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    while bytes.len() as u64 != reference.byte_length {
        let window = reader
            .read_body(
                reference.clone(),
                bytes.len() as u64,
                (reference.byte_length - bytes.len() as u64).min(64 * 1024) as u32,
            )
            .await?;
        ensure!(!window.bytes.is_empty(), "history body did not advance");
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}

#[tokio::test]
async fn durable_reopen_uses_original_records_without_execution_or_run_copies() -> Result<()> {
    let mut env = Environment::new(
        vec![prompt_step(
            "facts",
            0,
            text_reply("真实原件与恢复🧭", "facts"),
        )],
        vec![],
    )
    .await?;
    let result = async {
        let started = env.start(ThreadWorkspaceMode::Worktree, "facts").await?;
        let id = &started.thread.id;
        let turn = completed_prompt(&env.runtime, id, "facts").await?;
        env.runtime.synchronize_thread_observation(id).await?;
        let saved = support::saved(&env.home, id).await?;
        env.restart().await?;

        let current = env
            .runtime
            .open_current_reader(id, CURRENT_PROTOCOL_VERSION, current_demand())
            .await?;
        let view = current.snapshot(current_demand()).await?;
        ensure!(
            !view.projection.execution_present,
            "cold Current replayed an execution"
        );
        ensure!(
            !view.projection
                .atoms
                .iter()
                .any(|atom| atom.kind == ChatAtomKind::Text),
            "cold Current replayed completed history into its live owner"
        );
        current.close().await?;

        let demand = HistoryDemand {
            max_rows: 128,
            max_bytes: 256 * 1024,
        };
        let reader = env
            .runtime
            .open_history_reader(id, pl_studio_runtime::history::HISTORY_PROTOCOL_VERSION)
            .await?;
        let originals = reader
            .events_page(
                HistoryEventsQuery::Originals {
                    scope: ChatScope {
                        query_class: pl_studio_runtime::ChatClassFilter::All {},
                        parent_id: None,
                    },
                },
                None,
                None,
                demand,
            )
            .await?;
        let mut text_identity = None;
        let mut saw_inference = false;
        for event in originals.entries {
            let Some(original) = &event.header.original else {
                continue;
            };
            saw_inference |= original.original_kind == ChatAtomKind::Inference;
            let Some(payload_ref) = &event.payload_ref else {
                continue;
            };
            let payload = body(&reader, payload_ref).await?;
            let envelope: serde_json::Value = serde_json::from_slice(&payload)?;
            ensure!(envelope["contract"] == "anywork.chat/1");
            if original.original_kind != ChatAtomKind::Text {
                continue;
            }
            let entries = reader
                .list_bodies(event.header.event_id.clone(), None, demand)
                .await?;
            let reference = entries
                .entries
                .into_iter()
                .find(|entry| entry.role == HistoryBodyRole::Body)
                .context("text original has no body")?;
            if body(&reader, &reference.reference).await? == "真实原件与恢复🧭".as_bytes() {
                ensure!(text_identity.is_none(), "text original was duplicated");
                text_identity = Some(event.header.event_id.clone());
            }
        }
        ensure!(saw_inference, "history lost the inference diagnostic");
        let text_identity = text_identity.context("real model text original")?;
        reader.close().await;

        let page = env.runtime.list_thread_turns(id, None, 10).await?;
        ensure!(page
            .turns
            .iter()
            .any(|history| history.turn.id == turn.id
                && history
                    .items
                    .iter()
                    .any(|entry| entry.header.event_id == text_identity)));

        let db = Database::connect(format!("sqlite://{}?mode=ro", saved.path.display())).await?;
        let check = async {
            let rows = db
                .query_all_raw(Statement::from_string(
                    DbBackend::Sqlite,
                    "SELECT name FROM sqlite_schema WHERE type='table' AND name IN ('history_items','conversation_atom_facts','conversation_items','session_checkpoint','current_context')",
                ))
                .await?;
            ensure!(rows.is_empty(), "retired execution/current tables remain");
            let identity = db
                .query_one_raw(Statement::from_string(
                    DbBackend::Sqlite,
                    "SELECT schema_version,thread_id FROM history_store_meta WHERE singleton=1",
                ))
                .await?
                .context("history identity")?;
            ensure!(identity.try_get::<i64>("", "schema_version")? == 25);
            ensure!(identity.try_get::<String>("", "thread_id")?.as_str() == id.as_str());
            Ok(())
        }
        .await;
        db.close().await?;
        check
    }
    .await;
    env.finish(result).await
}
