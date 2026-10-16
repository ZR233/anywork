//! 从同一 Thread 的权威效果历史回读任务，不依赖有界内存窗口或诊断日志。
use super::{SessionStoreError, SqliteSessionStore, ThreadEffectQuery};
use crate::thread::{cold::DurableToolTask, task::TaskStatus};

pub(super) async fn read(
    store: &SqliteSessionStore,
    thread_id: &str,
    task_id: &str,
) -> Result<Option<DurableToolTask>, SessionStoreError> {
    let mut before_sequence = None;
    let mut task = None;
    let mut delivery = None;
    // 每页有界；序号上界沿不可变历史递减，其他 Thread 的历史不会进入查询。
    loop {
        let page = store
            .query_thread_effects(
                thread_id,
                ThreadEffectQuery {
                    before_sequence,
                    limit: 256,
                },
            )
            .await?;
        for effect in page.effects {
            if task.is_none() {
                task = effect
                    .tasks
                    .iter()
                    .rev()
                    .find(|task| task.id == task_id)
                    .cloned();
            }
            if let Some(record) = &task {
                if record.status == TaskStatus::Running {
                    return Ok(Some(DurableToolTask {
                        task: record.clone(),
                        delivery: None,
                    }));
                }
                if delivery.is_none() {
                    delivery = effect
                        .deliveries
                        .iter()
                        .rev()
                        .find(|item| item.call_id == record.call_id)
                        .cloned();
                }
                if let Some(output) = &delivery {
                    let status = match &output.outcome {
                        crate::thread::ToolOutcome::Succeeded => TaskStatus::Succeeded,
                        crate::thread::ToolOutcome::Failed(_) => TaskStatus::Failed,
                        crate::thread::ToolOutcome::Cancelled => TaskStatus::Cancelled,
                        crate::thread::ToolOutcome::Interrupted => TaskStatus::Interrupted,
                    };
                    if output.tool_id != record.tool_id || status != record.status {
                        return Err(SessionStoreError::Invalid(
                            "持久任务与完整结果的身份或终态不一致".into(),
                        ));
                    }
                    return Ok(Some(DurableToolTask {
                        task: record.clone(),
                        delivery,
                    }));
                }
            }
        }
        match page.next_before_sequence {
            Some(next) => before_sequence = Some(next),
            None => return Ok(task.map(|task| DurableToolTask { task, delivery })),
        }
    }
}
