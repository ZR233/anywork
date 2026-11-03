//! Maintenance belongs to the original HistoryStore/Thread product owner. No
//! rebuild worker or input queue exists: the original channel keeps C's suffix.
use super::*;
use std::sync::atomic::Ordering;

enum MaintenanceAdmission<'a> {
    ColdRead,
    Owner(Option<&'a std::sync::Arc<()>>),
    #[cfg(test)]
    Explicit,
}

fn owner_changed() -> anyhow::Error {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Busy,
        "Conversation source continuity changed; open a new handle",
        true,
    )
    .with_reason(
        pl_protocol::studio::StudioErrorReason::ConversationResyncRequired,
        serde_json::Value::Null,
    )
    .into()
}

impl HistoryStore {
    #[cfg(test)]
    pub(crate) async fn arm_timeline_maintenance_waiter(
        &self,
    ) -> tokio::sync::oneshot::Receiver<()> {
        let (entered, received) = tokio::sync::oneshot::channel();
        *self.state.timeline_maintenance_waiter.lock().await = Some(entered);
        received
    }
    #[cfg(test)]
    pub(crate) async fn arm_timeline_read_need_gate(
        &self,
    ) -> (
        tokio::sync::oneshot::Receiver<()>,
        tokio::sync::oneshot::Sender<()>,
    ) {
        let (entered, received) = tokio::sync::oneshot::channel();
        let (release, released) = tokio::sync::oneshot::channel();
        *self.state.timeline_read_need_gate.lock().await = Some((entered, released));
        (received, release)
    }
    #[cfg(test)]
    pub(super) async fn wait_timeline_read_need_gate(&self) -> Result<()> {
        if let Some((entered, release)) = self.state.timeline_read_need_gate.lock().await.take() {
            let _ = entered.send(());
            release
                .await
                .context("cold maintenance admission cancelled")?;
        }
        Ok(())
    }
    #[cfg(test)]
    pub(crate) async fn arm_timeline_rebuild_gate(
        &self,
    ) -> (
        tokio::sync::oneshot::Receiver<()>,
        tokio::sync::oneshot::Sender<()>,
    ) {
        let (entered, received) = tokio::sync::oneshot::channel();
        let (release, released) = tokio::sync::oneshot::channel();
        *self.state.timeline_rebuild_gate.lock().await = Some((entered, released));
        (received, release)
    }
    pub(crate) fn register_timeline_channel(
        &self,
        channel: &std::sync::Arc<crate::studio::storage::thread_writer::HistoryChannel>,
    ) -> std::sync::Arc<()> {
        let owner = std::sync::Arc::new(());
        *self
            .state
            .timeline_owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = std::sync::Arc::downgrade(&owner);
        *self
            .state
            .timeline_channel
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) =
            Some(std::sync::Arc::downgrade(channel));
        owner
    }
    pub(crate) async fn timeline_prepare_guard(&self) -> tokio::sync::RwLockReadGuard<'_, ()> {
        self.state.timeline_owner_gate.read().await
    }
    pub(crate) async fn timeline_snapshot(&self) -> Result<Option<(String, String, u64, Vec<u8>)>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let tx = connection.db.begin().await?;
        let generation = conversation::timeline::generation(&tx).await?;
        let next = conversation::timeline::next_position(&tx).await?;
        let recovery = conversation::timeline::recovery(&tx).await?;
        tx.commit().await?;
        Ok(Some((
            connection.database_id.clone(),
            generation,
            next,
            recovery,
        )))
    }
    pub(crate) fn timeline_generation_changes(&self) -> tokio::sync::watch::Receiver<String> {
        self.state.timeline_generation.subscribe()
    }
    pub(crate) async fn timeline_generation(&self) -> Result<String> {
        {
            let _initializing = self.state.init.read().await;
            ensure!(
                !self.state.closed.load(Ordering::Acquire),
                "history is permanently closed"
            );
            let cached = self.state.timeline_generation.borrow().clone();
            if !cached.is_empty() {
                return Ok(cached);
            }
        }
        let Some(connection) = self.reader().await? else {
            return Ok(String::new());
        };
        let generation = conversation::timeline::generation(&connection.db).await?;
        self.state.timeline_generation.send_if_modified(|value| {
            if value.is_empty() {
                *value = generation.clone();
                true
            } else {
                false
            }
        });
        Ok(self.state.timeline_generation.borrow().clone())
    }
    pub(crate) fn request_timeline_maintenance(&self) {
        self.state.timeline_repair.store(true, Ordering::Release);
        self.state.timeline_repair_wake.notify_one();
    }
    pub(crate) fn retry_timeline_maintenance(&self) {
        if self
            .state
            .timeline_repair_failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
            .is_some()
        {
            self.request_timeline_maintenance();
        }
    }
    pub(crate) async fn timeline_maintenance_requested(&self) {
        self.state.timeline_repair_wake.notified().await;
    }
    pub(crate) fn pause_timeline(&self) {
        self.state.timeline_paused.store(true, Ordering::Release);
    }
    pub(crate) fn timeline_is_paused(&self) -> bool {
        self.state.timeline_paused.load(Ordering::Acquire)
    }
    pub(crate) async fn timeline_maintenance_needed(&self) -> Result<bool> {
        if let Some(error) = self
            .state
            .timeline_repair_failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
        {
            anyhow::bail!("timeline maintenance failed; explicit retry required: {error}");
        }
        if self.state.timeline_repair.load(Ordering::Acquire) || self.timeline_is_paused() {
            return Ok(true);
        }
        let Some(connection) = self.reader().await? else {
            return Ok(false);
        };
        let tx = connection.db.begin().await?;
        let needed = Self::timeline_needs_in(&tx, &connection.database_id).await?;
        tx.commit().await?;
        Ok(needed)
    }
    pub(super) async fn timeline_needs_in(
        db: &impl ConnectionTrait,
        database: &str,
    ) -> Result<bool> {
        // Canonical facts cannot be reconstructed from a latest checkpoint. If
        // they are damaged, preserve the database and report the source failure.
        db.query_all_raw(statement("SELECT effect_seq,suborder,atom_id,phase,fact_order,metadata FROM conversation_atom_facts LIMIT 0",vec![])).await?;
        // Inspect only bounded schema metadata. Missing derived columns are a
        // repairable fault; an I/O/Busy error fetching the schema is not.
        for (table, required) in [
            (
                "timeline_items",
                &[
                    "item_id",
                    "kind",
                    "location",
                    "position",
                    "commit_seq",
                    "metadata",
                    "projection_version",
                ][..],
            ),
            (
                "timeline_item_members",
                &[
                    "item_id",
                    "member_order",
                    "member_id",
                    "completion_item_id",
                    "admitted_effect",
                    "metadata",
                ][..],
            ),
            (
                "timeline_projection_state",
                &[
                    "singleton_id",
                    "projection_version",
                    "next_position",
                    "source_effect_seq",
                    "projection_generation",
                    "recovery",
                ][..],
            ),
        ] {
            let columns = db
                .query_all_raw(statement(&format!("PRAGMA table_info({table})"), vec![]))
                .await?
                .into_iter()
                .map(|row| row.try_get::<String>("", "name"))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            if required
                .iter()
                .any(|name| !columns.iter().any(|column| column.as_str() == *name))
            {
                return Ok(true);
            }
        }
        let state = match conversation::timeline::state(db).await {
            Ok(state) => state,
            Err(error) if error.is::<conversation::timeline::ProjectionFault>() => return Ok(true),
            Err(error) => return Err(error),
        };
        let Some((version, next)) = state else {
            return Ok(true);
        };
        if version != pl_protocol::TIMELINE_PROJECTION_VERSION {
            return Ok(true);
        }
        let generation = match conversation::timeline::generation(db).await {
            Ok(value) => value,
            Err(error) if error.is::<conversation::timeline::ProjectionFault>() => return Ok(true),
            Err(error) => return Err(error),
        };
        let recovery = match conversation::timeline::recovery(db).await {
            Ok(value) => value,
            Err(error) if error.is::<conversation::timeline::ProjectionFault>() => return Ok(true),
            Err(error) => return Err(error),
        };
        if recovery.len() > pl_protocol::CHAT_BATCH_MAX_BYTES as usize {
            return Ok(true);
        }
        let mut projection = crate::studio::thread_projection::TimelineProjection::new(
            database.into(),
            generation,
            next,
        );
        Ok(projection.restore_recovery(&recovery).is_err())
    }
    #[cfg(test)]
    pub(crate) async fn maintain_timeline(&self) -> Result<()> {
        self.maintain_timeline_in(MaintenanceAdmission::Explicit)
            .await
    }
    pub(crate) async fn maintain_timeline_if_needed(
        &self,
        owner: Option<&std::sync::Arc<()>>,
    ) -> Result<()> {
        self.maintain_timeline_in(MaintenanceAdmission::Owner(owner))
            .await
    }
    pub(super) async fn prepare_timeline_if_needed(&self) -> Result<()> {
        self.maintain_timeline_in(MaintenanceAdmission::ColdRead)
            .await
    }
    /// Revalidate admission before pausing or capturing the original channel's
    /// fixed handoff ticket. A cold capture never outranks an installed owner.
    async fn maintain_timeline_in(&self, admission: MaintenanceAdmission<'_>) -> Result<()> {
        #[cfg(test)]
        if let Some(entered) = self.state.timeline_maintenance_waiter.lock().await.take() {
            let _ = entered.send(());
        }
        let _owner = self.state.timeline_owner_gate.write().await;
        if let Some(error) = self
            .state
            .timeline_repair_failure
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone()
        {
            anyhow::bail!("timeline maintenance failed; explicit retry required: {error}");
        }
        let explicit = match &admission {
            #[cfg(test)]
            MaintenanceAdmission::Explicit => true,
            _ => false,
        };
        if !explicit && !self.timeline_maintenance_needed().await? {
            return Ok(()); // The old read/worker need was already resolved.
        }
        let registered = self
            .state
            .timeline_owner
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .upgrade();
        if explicit && registered.is_some() {
            self.request_timeline_maintenance();
            return Err(owner_changed());
        }
        match (&admission, registered.as_ref()) {
            (MaintenanceAdmission::ColdRead, Some(_)) => {
                self.request_timeline_maintenance();
                return Err(owner_changed());
            }
            (MaintenanceAdmission::Owner(expected), Some(actual)) => {
                ensure!(
                    expected.is_some_and(|expected| std::sync::Arc::ptr_eq(expected, actual)),
                    owner_changed()
                );
            }
            (MaintenanceAdmission::Owner(Some(_)), None) => return Err(owner_changed()),
            _ => {}
        }
        self.pause_timeline();
        let result = async {
            let channel = self
                .state
                .timeline_channel
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .as_ref()
                .and_then(std::sync::Weak::upgrade);
            if let Some(channel) = channel {
                let through = channel.handoff_ticket();
                channel
                    .await_handoff_durable(&self.state.thread_id, through)
                    .await?;
            }
            #[cfg(test)]
            if let Some((entered, release)) = self.state.timeline_rebuild_gate.lock().await.take() {
                let _ = entered.send(());
                release
                    .await
                    .context("timeline maintenance cancelled at durable cut")?;
            }
            let connection = self.writer().await?;
            let generation =
                Self::replace_timeline_in(&connection.db, &connection.database_id).await?;
            self.state
                .timeline_pending
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .clear();
            // No candidate generation escapes before the transaction commits.
            self.state.timeline_generation.send_replace(generation);
            self.state.timeline_repair.store(false, Ordering::Release);
            self.state.timeline_paused.store(false, Ordering::Release);
            // The actual owner may be idle and need no further Core effect.
            // This wake is a handover, not a new maintenance request.
            self.state.timeline_repair_wake.notify_one();
            Ok::<_, anyhow::Error>(())
        }
        .await;
        if let Err(error) = &result {
            *self
                .state
                .timeline_repair_failure
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(format!("{error:#}"));
        }
        result
    }
    async fn replace_timeline_in(db: &DatabaseConnection, database: &str) -> Result<String> {
        let tx = begin_write(db).await?;
        // The original prepared prefix saved its canonical starts/terminals even
        // if old derived rows were missing. C+1 remains unprepared in its channel.
        let cut = applied_write_seq(&tx).await?;
        let current = conversation::current::read(&tx).await?;
        ensure!(
            integer(current.source_effect_seq)? == cut,
            "timeline maintenance cut differs from original writer current"
        );
        tx.execute_unprepared("DROP TABLE IF EXISTS timeline_item_members; DROP TABLE IF EXISTS timeline_items; DROP TABLE IF EXISTS timeline_projection_state;").await?;
        tx.execute_unprepared(conversation::timeline::CREATE_DERIVED_SCHEMA)
            .await?;
        let generation = conversation::timeline::rebuild(&tx, database).await?;
        tx.commit().await?;
        Ok(generation)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn cancelling_maintenance_keeps_old_generation_and_releases_original_owner_gate()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let store = HistoryStore::open(
            &directory.path().join("history.sqlite"),
            "cancel-maintenance",
        )
        .await?;
        store.prepare_write().await?;
        let generation = store.timeline_generation().await?;
        let snapshot = store.conversation_current().await?;
        let (entered, release) = store.arm_timeline_rebuild_gate().await;
        let operation = tokio::spawn({
            let store = store.clone();
            async move { store.maintain_timeline().await }
        });
        entered.await?;
        operation.abort();
        assert!(operation.await.unwrap_err().is_cancelled());
        drop(release);
        assert_eq!(store.timeline_generation().await?, generation);
        assert_eq!(store.conversation_current().await?, snapshot);
        // The cancelled operation retained its pause, but owns no lock/process.
        // The same original owner can retry without any new queue or service.
        assert!(store.timeline_is_paused());
        store.maintain_timeline().await?;
        assert_ne!(store.timeline_generation().await?, generation);
        assert!(!store.timeline_is_paused());
        assert_eq!(store.conversation_current().await?, snapshot);
        Ok(())
    }
}
