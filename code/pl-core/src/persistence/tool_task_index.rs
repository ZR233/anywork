//! 与不可变 effect 同事务维护的任务身份及交付定位；不复制交付正文。
use sea_orm::ConnectionTrait;

use super::{SessionStoreError, sqlite};
use crate::{
    context::content_hash,
    thread::{ThreadEffectBatch, task::TaskRecord},
};

pub(super) const SCHEMA: &str = "
    CREATE TABLE thread_tool_tasks (
        thread_id TEXT NOT NULL, task_id TEXT NOT NULL, call_id TEXT NOT NULL,
        task_envelope TEXT NOT NULL, task_hash TEXT NOT NULL,
        delivery_sequence INTEGER, delivery_position INTEGER,
        PRIMARY KEY(thread_id,task_id), UNIQUE(thread_id,call_id));
    CREATE TABLE thread_tool_task_resources (
        thread_id TEXT NOT NULL, call_id TEXT NOT NULL, reference_hash TEXT NOT NULL,
        reference_envelope TEXT NOT NULL,
        PRIMARY KEY(thread_id,call_id,reference_hash));";

pub(super) fn decode_task(row: &sea_orm::QueryResult) -> Result<TaskRecord, SessionStoreError> {
    let envelope: String = row.try_get("", "task_envelope")?;
    let hash: String = row.try_get("", "task_hash")?;
    let task: TaskRecord = serde_json::from_str(&envelope)?;
    if content_hash(envelope.as_bytes()) != hash
        || task.id != row.try_get::<String>("", "task_id")?
        || task.call_id != row.try_get::<String>("", "call_id")?
        || task.id != format!("task:{}", task.call_id)
    {
        return Err(SessionStoreError::Invalid(
            "任务索引完整性或身份不一致".into(),
        ));
    }
    Ok(task)
}

pub(super) async fn apply(
    tx: &impl ConnectionTrait,
    effect: &ThreadEffectBatch,
) -> Result<(), SessionStoreError> {
    for task in effect.tasks.iter() {
        if task.id != format!("task:{}", task.call_id) || task.revision == 0 {
            return Err(SessionStoreError::Invalid("任务身份或修订号无效".into()));
        }
        let previous = tx
            .query_one_raw(sqlite::statement(
                "SELECT * FROM thread_tool_tasks WHERE thread_id=? AND task_id=?",
                vec![effect.thread_id.clone().into(), task.id.clone().into()],
            ))
            .await?;
        if let Some(row) = previous {
            let previous = decode_task(&row)?;
            if task.call_id != previous.call_id
                || task.tool_id != previous.tool_id
                || task.turn_id != previous.turn_id
                || task.revision < previous.revision
                || (task.revision == previous.revision && task != &previous)
            {
                return Err(SessionStoreError::Invalid(
                    "任务索引修订或调用身份冲突".into(),
                ));
            }
            if task == &previous {
                continue;
            }
        }
        let envelope = serde_json::to_string(task)?;
        tx.execute_raw(sqlite::statement(
            "INSERT INTO thread_tool_tasks(thread_id,task_id,call_id,task_envelope,task_hash)
             VALUES(?,?,?,?,?) ON CONFLICT(thread_id,task_id) DO UPDATE SET
             task_envelope=excluded.task_envelope,task_hash=excluded.task_hash",
            vec![
                effect.thread_id.clone().into(),
                task.id.clone().into(),
                task.call_id.clone().into(),
                envelope.clone().into(),
                content_hash(envelope.as_bytes()).into(),
            ],
        ))
        .await?;
    }
    for (position, delivery) in effect.deliveries.iter().enumerate() {
        // 准备期间取消、尚未实际启动的调用也有交付，但没有 task 身份。
        let row = tx
            .query_one_raw(sqlite::statement(
                "SELECT * FROM thread_tool_tasks WHERE thread_id=? AND call_id=?",
                vec![
                    effect.thread_id.clone().into(),
                    delivery.call_id.clone().into(),
                ],
            ))
            .await?;
        let Some(row) = row else {
            continue;
        };
        let task = decode_task(&row)?;
        if task.tool_id != delivery.tool_id
            || task.status != crate::thread::task::TaskStatus::from_outcome(&delivery.outcome)
        {
            return Err(SessionStoreError::Invalid("任务与交付终态不一致".into()));
        }
        if row
            .try_get::<Option<i64>>("", "delivery_sequence")?
            .is_some()
        {
            return Err(SessionStoreError::Invalid("调用重复交付完整结果".into()));
        }
        tx.execute_raw(sqlite::statement(
            "UPDATE thread_tool_tasks SET delivery_sequence=?,delivery_position=? WHERE thread_id=? AND call_id=?",
            vec![integer(effect.sequence)?.into(), integer(position as u64)?.into(),
                effect.thread_id.clone().into(), delivery.call_id.clone().into()],
        )).await?;
    }
    for repair in effect.delivery_repairs.iter() {
        repair
            .reference
            .validate()
            .map_err(|error| SessionStoreError::Invalid(error.to_string()))?;
        let row = tx
            .query_one_raw(sqlite::statement(
                "SELECT delivery_sequence FROM thread_tool_tasks WHERE thread_id=? AND call_id=?",
                vec![
                    effect.thread_id.clone().into(),
                    repair.call_id.clone().into(),
                ],
            ))
            .await?;
        let sequence = match row {
            Some(row) => row.try_get::<Option<i64>>("", "delivery_sequence")?,
            None => None,
        };
        if sequence.is_none() {
            return Err(SessionStoreError::Invalid(
                "资源补充没有已提交的任务交付".into(),
            ));
        }
        let envelope = serde_json::to_string(&repair.reference)?;
        tx.execute_raw(sqlite::statement(
            "INSERT INTO thread_tool_task_resources(thread_id,call_id,reference_hash,reference_envelope)
             VALUES(?,?,?,?) ON CONFLICT(thread_id,call_id,reference_hash) DO NOTHING",
            vec![effect.thread_id.clone().into(), repair.call_id.clone().into(),
                content_hash(envelope.as_bytes()).into(), envelope.into()],
        )).await?;
    }
    Ok(())
}

fn integer(value: u64) -> Result<i64, SessionStoreError> {
    i64::try_from(value).map_err(|_| SessionStoreError::Invalid("任务索引整数溢出".into()))
}
