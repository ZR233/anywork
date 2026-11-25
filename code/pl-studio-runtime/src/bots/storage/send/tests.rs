use super::*;

fn text_record(operation_id: &str, content_hash: &str, status: SendRecordStatus) -> SendRecord {
    SendRecord {
        operation_id: operation_id.into(),
        bot_id: "bot".into(),
        chat_id: "chat".into(),
        content_hash: content_hash.into(),
        status,
        platform_message_ids: Vec::new(),
        segments: Vec::new(),
        facts_complete: true,
    }
}

/// 身份核对与 upsert 共用一个事务：同一 operationId 的不同正文被拒绝且账本保持原样，
/// 同一身份的进度则覆盖写入。
#[tokio::test]
async fn save_send_keeps_identity_verification_and_upsert_in_one_transaction() -> anyhow::Result<()>
{
    let directory = tempfile::tempdir()?;
    let store = BotStateStore::new(directory.path().join("ledger.sqlite"));
    store
        .save_send(&text_record(
            "operation",
            "hash-a",
            SendRecordStatus::Unknown,
        ))
        .await?;
    let mut progress = text_record("operation", "hash-a", SendRecordStatus::Succeeded);
    progress.platform_message_ids.push("message".into());
    store.save_send(&progress).await?;
    let stored = store
        .load_send("operation")
        .await?
        .expect("the progress is persisted");
    assert_eq!(stored.status, SendRecordStatus::Succeeded);
    assert_eq!(stored.platform_message_ids, ["message"]);

    let conflict = store
        .save_send(&text_record(
            "operation",
            "hash-b",
            SendRecordStatus::Rejected,
        ))
        .await
        .expect_err("a different body under the same operationId is a conflict");
    assert_eq!(conflict.kind(), FeishuErrorKind::Conflict);
    let stored = store
        .load_send("operation")
        .await?
        .expect("the rejected save leaves the record in place");
    assert_eq!(stored.content_hash, "hash-a");
    assert_eq!(stored.status, SendRecordStatus::Succeeded);
    Ok(())
}
