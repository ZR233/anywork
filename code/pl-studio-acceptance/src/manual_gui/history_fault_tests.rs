use super::*;
use pl_protocol::{
    SucceededThreadTool, ThreadContentLifecycle, ThreadItem, ThreadItemState, ThreadTextChannel,
    ThreadTextItem, ThreadToolInvocation, ThreadToolItem, ThreadToolOutput, ThreadToolState,
};

fn item(id: &str, turn: &str, state: ThreadItemState) -> ThreadItem {
    ThreadItem::new(id.into(), "thread".into(), turn.into(), 1, 1, 1, 1, state)
}

fn answer(id: &str, channel: ThreadTextChannel) -> ThreadItem {
    item(
        id,
        "fault-turn",
        ThreadItemState::Text(ThreadTextItem::new(
            channel,
            pl_provider_fixture::GUI_HISTORY_FAULT_ANSWER.into(),
            Vec::new(),
            ThreadContentLifecycle::completed(1),
        )),
    )
}

fn tool(id: &str, turn: &str, result: &str) -> ThreadItem {
    item(
        id,
        turn,
        ThreadItemState::Tool(ThreadToolItem::new(
            ThreadToolInvocation::new(
                pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_CALL_ID.into(),
                "exec".into(),
                pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER.into(),
            ),
            ThreadToolState::Succeeded(SucceededThreadTool::new(
                1,
                ThreadToolOutput::new(result.into(), Vec::new(), Vec::new(), Some(0)),
            )),
        )),
    )
}

fn write_items(path: &Path, items: &[ThreadItem]) -> Result<()> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let options = SqliteConnectOptions::new().filename(path).create_if_missing(true);
        let mut connection = SqliteConnection::connect_with(&options).await?;
        sea_orm::sqlx::query(
            "CREATE TABLE IF NOT EXISTS history_items(item_id TEXT PRIMARY KEY, payload TEXT NOT NULL)",
        ).execute(&mut connection).await?;
        sea_orm::sqlx::query("DELETE FROM history_items").execute(&mut connection).await?;
        for item in items {
            sea_orm::sqlx::query("INSERT INTO history_items(item_id,payload) VALUES(?1,?2)")
                .bind(&item.id).bind(serde_json::to_string(item)?)
                .execute(&mut connection).await?;
        }
        connection.close().await?;
        Ok(())
    })
}

#[test]
fn history_fault_counts_real_final_and_tool_output_not_user_or_arguments() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let database = temp.path().join("history.sqlite");
    write_items(
        &database,
        &[
            answer("input", ThreadTextChannel::User),
            answer("commentary", ThreadTextChannel::Commentary),
            answer("answer", ThreadTextChannel::Final),
            tool("argument-only", "fault-turn", "ordinary output"),
            tool(
                "result",
                "fault-turn",
                pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
            ),
        ],
    )?;
    let originals = history_fault_originals(&database)?;
    originals.validate()?;
    assert_eq!(originals.answers[0].item_id, "answer");
    assert_eq!(originals.tools[0].item_id, "result");
    assert_eq!(
        originals.tools[0].tool_call_id.as_deref(),
        Some(pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_CALL_ID)
    );
    Ok(())
}

#[test]
fn history_fault_rejects_duplicate_originals_and_cross_turn_results() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let database = temp.path().join("history.sqlite");
    write_items(
        &database,
        &[
            answer("answer", ThreadTextChannel::Final),
            answer("duplicate", ThreadTextChannel::Final),
            tool(
                "result",
                "fault-turn",
                pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
            ),
        ],
    )?;
    assert!(history_fault_originals(&database)?.validate().is_err());
    write_items(
        &database,
        &[
            answer("answer", ThreadTextChannel::Final),
            tool(
                "result",
                "different-turn",
                pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER,
            ),
        ],
    )?;
    assert!(history_fault_originals(&database)?.validate().is_err());
    Ok(())
}

#[test]
fn history_fault_execution_receipts_preserve_real_counts_and_reject_garbage() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let path = temp
        .path()
        .join(pl_provider_fixture::GUI_HISTORY_FAULT_EXECUTIONS_FILE);
    assert_eq!(history_fault_execution_count(temp.path())?, 0);
    let marker = pl_provider_fixture::GUI_HISTORY_FAULT_TOOL_MARKER;
    fs::write(&path, format!("{marker}\r\n"))?;
    assert_eq!(history_fault_execution_count(temp.path())?, 1);
    fs::write(&path, format!("{marker}\n{marker}\n"))?;
    assert_eq!(history_fault_execution_count(temp.path())?, 2);
    fs::write(&path, "not the tool receipt\n")?;
    assert!(history_fault_execution_count(temp.path()).is_err());
    Ok(())
}

#[test]
fn history_fault_fixture_stage_ignores_optional_titles_and_rejects_missing_evidence() -> Result<()>
{
    let script = pl_provider_fixture::gui_history_fault_script();
    let mut status = pl_provider_fixture::FixtureLiveStatus {
        accepted: 0,
        rejected: 0,
        total: 0,
        consumed_steps: 0,
        expected_steps: script.len(),
        remaining_optional: false,
    };
    assert_eq!(history_fault_required_consumed(status)?, 0);
    let mut required = 0;
    for step in &script {
        status.consumed_steps += 1;
        status.accepted += 1;
        status.total += 1;
        if !step.optional {
            required += 1;
        }
        assert_eq!(history_fault_required_consumed(status)?, required);
    }
    assert_eq!(required, pl_provider_fixture::HISTORY_FAULT_REQUIRED_STEPS);
    status.rejected = 1;
    assert!(history_fault_required_consumed(status).is_err());
    status.rejected = 0;
    status.consumed_steps += 1;
    assert!(history_fault_required_consumed(status).is_err());
    status.consumed_steps = 0;
    status.expected_steps = 0;
    assert!(history_fault_required_consumed(status).is_err());
    Ok(())
}
