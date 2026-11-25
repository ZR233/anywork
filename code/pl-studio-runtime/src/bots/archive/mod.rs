//! Thread-scoped reply admission and retained join/ledger responsibilities.
use super::owner::{BotRuntime, BotRuntimeInner};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use std::collections::BTreeSet;
use std::sync::Arc;
/// The reliable archive operation remains the durable seal after this guard drops.
pub(crate) struct BotArchiveGuard {
    inner: Arc<BotRuntimeInner>,
    threads: BTreeSet<String>,
}

impl Drop for BotArchiveGuard {
    fn drop(&mut self) {
        let mut seals = self
            .inner
            .reply_work
            .archive_seals
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        for id in &self.threads {
            if let Some(count) = seals.get_mut(id) {
                *count -= 1;
                if *count == 0 {
                    seals.remove(id);
                }
            }
        }
    }
}

impl BotRuntime {
    pub(crate) async fn delete_threads(&self, ids: &[String]) -> Result<(), FeishuError> {
        let bots = self
            .inner
            .bots
            .lock()
            .await
            .iter()
            .map(|(id, record)| (id.clone(), record.published.clone()))
            .collect::<Vec<_>>();
        for (id, bot) in bots {
            if let Some(bot) = bot {
                // Inbound binding claims, frozen-body admission and ledger deletion share this
                // same boundary. Reply join alone cannot observe an unregistered inbound writer.
                let _admission = bot.admission.lock().await;
                bot.store.delete_threads(ids).await?;
            } else {
                let path = self.inner.paths.bot_dir(&id).join("state.sqlite");
                pl_tool::workspace::path_safety::validate_path_for_write_async(
                    self.inner.paths.home(),
                    &path,
                )
                .await
                .map_err(|error| archive_error(&format!("unsafe bot state: {error}")))?;
                if tokio::fs::try_exists(&path)
                    .await
                    .map_err(|error| archive_error(&format!("bot state access failed: {error}")))?
                {
                    super::storage::BotStateStore::new(path)
                        .delete_threads(ids)
                        .await?;
                }
            }
        }
        Ok(())
    }
    /// Call after the archive scope is durable, and retain the guard until publication.
    pub(crate) async fn quiesce_archive_threads(
        &self,
        thread_ids: &[String],
    ) -> Result<BotArchiveGuard, FeishuError> {
        let threads = thread_ids.iter().cloned().collect::<BTreeSet<_>>();
        let mut replies = self.inner.reply_work.tasks.lock().await;
        let guard = BotArchiveGuard {
            inner: self.inner.clone(),
            threads,
        };
        {
            let mut seals = self
                .inner
                .reply_work
                .archive_seals
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            for id in &guard.threads {
                *seals.entry(id.clone()).or_default() += 1;
            }
        }
        for owner in replies.owners.values() {
            if guard.threads.contains(&owner.thread_id) {
                owner.cancellation.cancel();
            }
        }
        while replies
            .owners
            .values()
            .any(|owner| guard.threads.contains(&owner.thread_id))
        {
            replies.join_one().await?;
        }
        replies.retry_finishes(self, Some(&guard.threads)).await?;
        replies.report_faults(Some(&guard.threads))?;
        Ok(guard)
    }

    /// Used under the reply registration mutex, never the runtime lifecycle lock.
    pub(super) async fn ensure_reply_admission(
        &self,
        workspace_id: &str,
        thread_id: &str,
    ) -> Result<(), FeishuError> {
        if self
            .inner
            .reply_work
            .archive_seals
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .contains_key(thread_id)
        {
            return Err(archive_error("bot Thread archive is in progress"));
        }
        self.studio_host()
            .ok_or_else(|| archive_error("studio runtime host is unavailable"))?
            .ensure_bot_dispatch_allowed(workspace_id, thread_id)
            .await
            .map_err(|error| {
                archive_error(&format!("bot Thread dispatch admission failed: {error:#}"))
            })
    }
}

pub(super) fn archive_error(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Unavailable, message, true, None)
}

#[cfg(test)]
mod tests;
