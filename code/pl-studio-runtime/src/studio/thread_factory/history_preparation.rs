//! Offline preparation of the current history store, before any Thread is activated.

use anyhow::{Context, Result, ensure};
use std::sync::Arc;

use super::StudioThreadFactory;
use crate::agent::definition::VerifiedAgentIdentity;
use crate::studio::ThreadRecord;
use crate::studio::storage::history::{ExecutionIdentityMigration, HistoryInitialization};

#[derive(Debug, thiserror::Error)]
#[error("Thread {thread_id} history could not be prepared; original data retained")]
struct HistoryPreparationFailure {
    thread_id: String,
    #[source]
    source: anyhow::Error,
}

#[derive(Debug, thiserror::Error)]
#[error("{} Thread histories could not be prepared; original data retained", .remaining.len() + 1)]
struct HistoryPreparationFailures {
    #[source]
    first: HistoryPreparationFailure,
    remaining: Vec<HistoryPreparationFailure>,
}

impl StudioThreadFactory {
    /// Uses directory identities only to enumerate sources; never creates execution resources.
    pub(in crate::studio) async fn prepare_history_catalog(&self) -> Result<()> {
        let entries = self.services.store.catalog().entries();
        let mut pending = Vec::new();
        let mut failures = Vec::new();
        let mut needs_root_ownership = false;
        for entry in entries {
            let thread = ThreadRecord::from_directory_thread(entry.to_thread());
            let paths = match self
                .services
                .store
                .session_paths(&thread.project_id, &thread.id)
            {
                Ok(paths) => paths,
                Err(error) => {
                    failures.push((thread.id, error));
                    continue;
                }
            };
            match tokio::fs::try_exists(paths.history_database()).await {
                Ok(exists) => {
                    needs_root_ownership |= !exists && thread.parent_thread_id.is_none();
                    pending.push((thread, paths, exists));
                }
                Err(error) => failures.push((thread.id, error.into())),
            }
        }
        // The normal bot loader also starts external producers. Recover durable ownership first,
        // without activating them, only when an old root actually needs its identity converted.
        let bot_ownership = if needs_root_ownership {
            self.services.bots.prepare_history_ownership().await
        } else {
            Ok(())
        };
        for (thread, paths, current_exists) in pending {
            let result = async {
                let history = self
                    .services
                    .store
                    .history_for(&thread.project_id, &thread.id)
                    .await?;
                if current_exists {
                    return history.prepare_activation().await;
                }
                let live_bot = if thread.parent_thread_id.is_none() {
                    bot_ownership.clone().map_err(anyhow::Error::new)?;
                    self.services
                        .bots
                        .config_for_thread(&thread.id)
                        .await?
                        .map(|config| config.id)
                } else {
                    None
                };
                history
                    .initialize(HistoryInitialization::ImportV2 {
                        source_database: paths.legacy_history_database(),
                        legacy_state: self
                            .services
                            .store
                            .state_for(&thread.project_id, &thread.id)?,
                        migrate_execution_identity: self
                            .history_identity_migration(&thread, live_bot),
                    })
                    .await
            }
            .await;
            match result {
                Ok(()) => tracing::info!(
                    thread_id = %thread.id,
                    existing_target = current_exists,
                    "current Thread history is ready; legacy sources retained"
                ),
                Err(error) => {
                    // Keep every failure and its source; neither a failed member nor an already
                    // completed member is rewritten or treated as an empty/new conversation.
                    failures.push((thread.id, error));
                }
            }
        }
        let mut failures = failures
            .into_iter()
            .map(|(thread_id, source)| {
                // Report every affected identity, without logging checkpoint or parser contents.
                tracing::warn!(%thread_id, "current Thread history is not ready; original data retained");
                HistoryPreparationFailure { thread_id, source }
            });
        let Some(first) = failures.next() else {
            return Ok(());
        };
        Err(crate::studio::startup::migration_error(
            "history-current",
            "prepare_registered_threads",
            HistoryPreparationFailures {
                first,
                remaining: failures.collect(),
            },
        ))
    }

    fn history_identity_migration(
        &self,
        thread: &ThreadRecord,
        live_bot: Option<String>,
    ) -> ExecutionIdentityMigration {
        let thread_id = thread.id.clone();
        let role = thread.role.clone();
        let child = thread.parent_thread_id.is_some();
        let modes = self.services.thread_modes.clone();
        Arc::new(move |state| {
            let identity = if child {
                let profile =
                    crate::studio::model_route::required_saved_profile(state, &thread_id)?;
                ensure!(
                    profile.profile_id == role,
                    "saved child Profile conflicts with its directory role"
                );
                VerifiedAgentIdentity::child(&profile)?
            } else {
                let owner = crate::studio::model_route::verified_bot_owner(
                    live_bot.as_deref(),
                    Some(state),
                )?;
                crate::mode::migrate_mode_snapshot(state, &modes)?;
                ensure!(
                    state.extensions.contains_key("studio.mode"),
                    "root Thread has no saved Mode identity; original checkpoint preserved"
                );
                if owner.is_some() {
                    VerifiedAgentIdentity::BotRoot
                } else {
                    VerifiedAgentIdentity::GenericRoot
                }
            };
            crate::instruction::migrate_saved_representation(state, &identity)
        })
    }
}

/// Normal recovery validates current facts; obsolete representations belong only to import.
pub(super) fn validate_current_instructions(
    state: &pl_core::thread::ThreadSnapshot,
    identity: &VerifiedAgentIdentity,
) -> Result<()> {
    let record = state
        .extensions
        .get("studio.instructions")
        .context("saved Thread has no instruction snapshot")?;
    let snapshot = crate::instruction::decode_snapshot(&record.payload)?;
    identity.validate(&snapshot.agent)?;
    Ok(())
}
