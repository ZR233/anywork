//! 观察入口共享的结果合并与本地任务所有权。各 example 只使用所需子集。
#![allow(dead_code)]

/// 场景内本地任务的唯一 owner：收尾时先取消再逐个 join，绝不 detached。
#[derive(Default)]
pub struct TaskOwner {
    tasks: tokio::task::JoinSet<anyhow::Result<()>>,
}

impl TaskOwner {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn spawn<F>(&mut self, future: F)
    where
        F: std::future::Future<Output = anyhow::Result<()>> + Send + 'static,
    {
        self.tasks.spawn(future);
    }

    /// 取消并 join 全部本地任务；真正的失败与 panic 都作为清理失败报告。
    ///
    /// 先给任务一个真正结束的机会，再 abort 剩余任务：派生任务在结果接收端被丢弃后
    /// 会把**真实失败**归档回来，立即 abort 会丢掉这条证据。
    pub async fn shutdown(&mut self) -> anyhow::Result<()> {
        let mut failures: Vec<String> = Vec::new();
        let settled = tokio::time::timeout(CLEANUP_GRACE, async {
            while let Some(result) = self.tasks.join_next().await {
                record_failure(&mut failures, result);
            }
        })
        .await;
        if settled.is_err() {
            // 宽限到期与随之而来的强制 abort 本身就是清理失败：通用 owner 不得因为
            // “剩下的都被取消了”而静默成功。场景若有意取消任务，必须自己完成取消并
            // 验证后置事实，而不是依赖这里。
            let pending = self.tasks.len();
            failures.push(format!(
                "local tasks did not settle within {CLEANUP_GRACE:?}; {pending} task(s) were aborted forcefully and their outcome is unknown"
            ));
            self.tasks.abort_all();
            let mut cancelled = 0usize;
            while let Some(result) = self.tasks.join_next().await {
                match result {
                    Err(error) if error.is_cancelled() => cancelled += 1,
                    other => record_failure(&mut failures, other),
                }
            }
            if cancelled > 0 {
                failures.push(format!(
                    "{cancelled} task(s) were cancelled by the forced abort without reporting a result"
                ));
            }
        }
        if failures.is_empty() {
            Ok(())
        } else {
            anyhow::bail!(
                "local tasks did not finish cleanly: {}",
                failures.join("; ")
            )
        }
    }
}

/// 收尾宽限：只等待“任务自行结束”的最长时间，到期后 abort 剩余任务。
const CLEANUP_GRACE: std::time::Duration = std::time::Duration::from_millis(500);

fn record_failure(
    failures: &mut Vec<String>,
    result: Result<anyhow::Result<()>, tokio::task::JoinError>,
) {
    match result {
        Ok(Ok(())) => {}
        Ok(Err(error)) => failures.push(format!("task failed: {error:#}")),
        Err(error) if error.is_cancelled() => {}
        Err(error) => failures.push(format!("task join failed: {error}")),
    }
}

pub fn combine(outcome: anyhow::Result<()>, cleanup: anyhow::Result<()>) -> anyhow::Result<()> {
    match (outcome, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) => Err(error),
        (Ok(()), Err(cleanup)) => Err(cleanup),
        (Err(error), Err(cleanup)) => {
            Err(error.context(format!("cleanup also failed: {cleanup:#}")))
        }
    }
}

/// 在 deadline 内等待场景主体。
///
/// 超时只丢弃主体 future；调用方仍持有 helper/资源 owner，可在返回前执行统一收尾。
pub async fn run_with_deadline<F>(deadline: std::time::Duration, body: F) -> anyhow::Result<()>
where
    F: std::future::Future<Output = anyhow::Result<()>>,
{
    match tokio::time::timeout(deadline, body).await {
        Ok(result) => result,
        Err(_) => Err(anyhow::anyhow!(
            "scenario body did not settle within {deadline:?}"
        )),
    }
}
