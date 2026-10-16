//! 按任务身份读取同事务维护的索引，完整正文仅从其原始 effect 定位读取。
use sea_orm::{ConnectionTrait, TransactionTrait};

use super::{SessionStoreError, SqliteSessionStore, sqlite, thread_history, tool_task_index};
use crate::{
    context::{ContextContent, ResourceReference, content_hash},
    thread::cold::DurableToolTask,
};

pub(super) async fn read(
    store: &SqliteSessionStore,
    thread_id: &str,
    task_id: &str,
) -> Result<Option<DurableToolTask>, SessionStoreError> {
    // 三类事实共用短读事务，避免读取旧交付定位与新资源补充的混合水位。
    let tx = store.owner.shared.db.begin().await?;
    let row = tx
        .query_one_raw(sqlite::statement(
            "SELECT * FROM thread_tool_tasks WHERE thread_id=? AND task_id=?",
            vec![thread_id.into(), task_id.into()],
        ))
        .await?;
    let Some(row) = row else {
        tx.commit().await?;
        return Ok(None);
    };
    let task = tool_task_index::decode_task(&row)?;
    let sequence: Option<i64> = row.try_get("", "delivery_sequence")?;
    let position: Option<i64> = row.try_get("", "delivery_position")?;
    let delivery = match (sequence, position) {
        (None, None) => None,
        (Some(sequence), Some(position)) if sequence > 0 && position >= 0 => {
            let entry = tx
                .query_one_raw(sqlite::statement(
                    "SELECT * FROM session_entries WHERE session_id=? AND id=?",
                    vec![
                        thread_id.into(),
                        format!("pl.resource.thread-commit.{sequence:020}").into(),
                    ],
                ))
                .await?
                .ok_or_else(|| SessionStoreError::Invalid("任务交付定位的 effect 不存在".into()))?;
            let effect = thread_history::decode_effect(entry, thread_id)?;
            let mut delivery = effect
                .deliveries
                .get(position as usize)
                .cloned()
                .ok_or_else(|| SessionStoreError::Invalid("任务交付定位越界".into()))?;
            if delivery.call_id != task.call_id
                || delivery.tool_id != task.tool_id
                || crate::thread::task::TaskStatus::from_outcome(&delivery.outcome) != task.status
            {
                return Err(SessionStoreError::Invalid(
                    "任务与持久交付身份或终态不一致".into(),
                ));
            }
            let resources = tx.query_all_raw(sqlite::statement(
                "SELECT reference_envelope,reference_hash FROM thread_tool_task_resources WHERE thread_id=? AND call_id=? ORDER BY rowid",
                vec![thread_id.into(), task.call_id.clone().into()],
            )).await?;
            for row in resources {
                let envelope: String = row.try_get("", "reference_envelope")?;
                if content_hash(envelope.as_bytes())
                    != row.try_get::<String>("", "reference_hash")?
                {
                    return Err(SessionStoreError::Invalid(
                        "任务资源补充完整性校验失败".into(),
                    ));
                }
                let reference: ResourceReference = serde_json::from_str(&envelope)?;
                reference
                    .validate()
                    .map_err(|error| SessionStoreError::Invalid(error.to_string()))?;
                let resource = ContextContent::Resource { reference };
                if !delivery.delivered_context.contains(&resource) {
                    delivery.delivered_context.push(resource);
                }
            }
            Some(delivery)
        }
        (None, Some(_)) | (Some(_), None) | (Some(_), Some(_)) => {
            return Err(SessionStoreError::Invalid("任务交付定位无效".into()));
        }
    };
    tx.commit().await?;
    Ok(Some(DurableToolTask { task, delivery }))
}
