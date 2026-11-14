#[expect(
    dead_code,
    reason = "shared isolated fixtures serve several integration binaries"
)]
mod support;

use anyhow::{Context, Result, ensure};
use pl_protocol::{
    ChatAtomKind, ChatClassFilter, ChatScope, ContentRange, ReadDemand, ThreadWorkspaceMode,
};
use pl_studio_runtime::ConversationEvent;
use sea_orm::{ConnectionTrait, Database, DbBackend, Statement};
use support::{Environment, completed_prompt, prompt_step, text_reply};

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
        let started = env.start(ThreadWorkspaceMode::Worktree,"facts").await?;
        let id = &started.thread.id;
        let turn = completed_prompt(&env.runtime,id,"facts").await?;
        env.restart().await?;
        let demand = ReadDemand { max_items:128,max_bytes:256*1024 };
        let mut feed = env.runtime.open_conversation_feed(id,ChatScope { query_class:ChatClassFilter::All {},parent_id:None },demand).await?;
        let read = async {
            let Some(ConversationEvent::Chat { batch }) = feed.recv().await? else { anyhow::bail!("missing original baseline") };
            ensure!(batch.entries.iter().any(|entry| entry.atom.kind == ChatAtomKind::Inference),"Full lost the inference diagnostic");
            ensure!(batch.entries.iter().all(|entry| entry.atom.source_state.is_none()),"immutable originals gained dynamic source annotations");
            let text = batch.entries.iter().find(|entry| entry.atom.kind == ChatAtomKind::Text).context("real model text")?;
            let body = text.atom.contents.first().context("original text content")?;
            let bytes = feed.reader().read_content(&body.reference,ContentRange { offset:0,max_bytes:4096 }).await?;
            ensure!(bytes.bytes == "真实原件与恢复🧭".as_bytes());
            let page = env.runtime.list_thread_turns(id,None,10).await?;
            ensure!(page.turns.iter().any(|history| history.turn.id == turn.id && history.items.iter().any(|entry| entry.record_id == text.record_id)));
            ensure!(feed.reader().legacy_execution_evidence(None,demand).await?.entries.is_empty());
            Ok(())
        }.await;
        let close = feed.close().await;
        read?;
        close?;
        let saved = support::saved(&env.home,id).await?;
        let db = Database::connect(format!("sqlite://{}?mode=ro",saved.path.display())).await?;
        let check = async {
            let rows = db.query_all_raw(Statement::from_string(DbBackend::Sqlite,
                "SELECT name FROM sqlite_schema WHERE type='table' AND name IN ('history_items','conversation_atom_facts')")).await?;
            ensure!(rows.is_empty(),"retired execution tables remain");
            let version = db.query_one_raw(Statement::from_string(DbBackend::Sqlite,"SELECT schema_version,execution_order FROM history_meta WHERE id=1")).await?.context("history identity")?;
            ensure!(version.try_get::<i64>("","schema_version")? == 24 && version.try_get::<i64>("","execution_order")? > 0);
            let columns = db.query_all_raw(Statement::from_string(DbBackend::Sqlite,"PRAGMA table_info(conversation_items)")).await?;
            ensure!(!columns.iter().any(|column| column.try_get::<String>("","name").unwrap().starts_with("display_run_")));
            Ok(())
        }.await;
        db.close().await?;
        check
    }.await;
    env.finish(result).await
}
