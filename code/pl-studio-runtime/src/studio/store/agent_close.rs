//! The explicit execution seal and one original owned-worktree binding, not a history source.
mod migration;
use super::{
    StudioStore,
    object::{PersistedStudioObject, decode_object, load_object, put_object},
};
use crate::studio::{
    agent_close::{AgentCloseResult, AgentWorktreeCleanup},
    agent_host::worktree_lease::{
        WorkspaceEndpoint, WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind,
    },
};
use anyhow::{Context, Result, ensure};
pub(super) use migration::upgrade_bindings;
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter, TransactionTrait};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct OwnedWorktreeBinding {
    pub(in crate::studio) lease: WorktreeLease,
    pub identity: WorkspaceIdentity,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct AgentCloseGitGrant {
    pub delivery: WorkspaceIdentity,
    pub expected_head: String,
    pub expected_common_dir: String,
    /// An interrupted remove must never replay its authority against a replacement path.
    pub removal_started: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct AgentCloseRecord {
    pub agent_id: String,
    pub parent_id: String,
    pub root_id: String,
    pub workspace_id: String,
    pub revision: u64,
    pub force: bool,
    pub worktree: Option<OwnedWorktreeBinding>,
    pub git: Option<AgentCloseGitGrant>,
    pub execution_closed: bool,
    pub worktree_cleanup: AgentWorktreeCleanup,
    pub error: Option<pl_protocol::StateError>,
}

impl AgentCloseRecord {
    pub(crate) fn changed(&mut self) -> Result<()> {
        self.revision = self
            .revision
            .checked_add(1)
            .context("agent close revision exhausted")?;
        Ok(())
    }

    pub(crate) fn result(&self) -> AgentCloseResult {
        AgentCloseResult {
            agent_id: self.agent_id.clone(),
            execution_closed: self.execution_closed,
            worktree_cleanup: self.worktree_cleanup.clone(),
        }
    }
}

impl PersistedStudioObject for AgentCloseRecord {
    type PersistenceDto = Self;
    const OWNER_KIND: &'static str = "thread";
    const OBJECT_KIND: &'static str = "agentClose";
    const SCHEMA_VERSION: i64 = 3;

    fn revision(&self) -> u64 {
        self.revision
    }
    fn to_persistence_dto(&self) -> Self {
        self.clone()
    }
    fn from_persistence_dto(dto: Self) -> Result<Self> {
        Ok(dto)
    }
    fn validate_owner(&self, owner: &str) -> Result<()> {
        ensure!(
            self.agent_id == owner && self.parent_id != owner && self.root_id != owner,
            "agent close owner identity mismatch"
        );
        if let Some(binding) = &self.worktree {
            let lease = &binding.lease;
            lease.validate_identity()?;
            ensure!(
                lease.owner_kind == WorktreeLeaseOwnerKind::Child
                    && lease.owner_thread_id == owner
                    && lease.root_thread_id == self.root_id
                    && lease.workspace_id == self.workspace_id
                    && binding.identity.matches_root(&lease.path),
                "agent close worktree ownership mismatch"
            );
            ensure!(
                matches!(binding.identity.endpoint, WorkspaceEndpoint::Ssh { .. })
                    == lease.ssh_alias.is_some(),
                "close endpoint differs from the original lease transport"
            );
            WorkspaceIdentity::canonical(
                binding.identity.endpoint.clone(),
                binding.identity.root.clone(),
            )?;
            match &self.worktree_cleanup {
                AgentWorktreeCleanup::Removed { path }
                | AgentWorktreeCleanup::NotPresent { path, .. } => ensure!(
                    *path == lease.path,
                    "close result path differs from its ownership binding"
                ),
                AgentWorktreeCleanup::NotApplicable => {
                    anyhow::bail!("owned worktree cannot have a not-applicable result")
                }
                AgentWorktreeCleanup::Pending | AgentWorktreeCleanup::Failed { .. } => {}
            }
            if let Some(grant) = &self.git {
                ensure!(
                    grant.delivery.endpoint == binding.identity.endpoint
                        && grant.delivery != binding.identity
                        && !grant.expected_common_dir.is_empty()
                        && matches!(grant.expected_head.len(), 40 | 64)
                        && grant
                            .expected_head
                            .bytes()
                            .all(|byte| byte.is_ascii_hexdigit()),
                    "invalid exact child close Git grant"
                );
                WorkspaceIdentity::canonical(
                    grant.delivery.endpoint.clone(),
                    grant.delivery.root.clone(),
                )?;
            }
        } else {
            ensure!(
                self.git.is_none(),
                "close without an owned worktree has a Git grant"
            );
            ensure!(
                !matches!(
                    self.worktree_cleanup,
                    AgentWorktreeCleanup::Removed { .. } | AgentWorktreeCleanup::NotPresent { .. }
                ),
                "close without ownership cannot report worktree removal"
            );
        }
        ensure!(
            self.execution_closed || self.worktree_cleanup == AgentWorktreeCleanup::Pending,
            "worktree result precedes real execution closure"
        );
        Ok(())
    }
}

pub(in crate::studio) async fn migrate_bot_roots(
    db: &sea_orm::DatabaseConnection,
    mappings: &mut [crate::studio::startup::storage_layout::bot_roots::BotRootMove],
) -> Result<()> {
    use crate::studio::entity::studio_object;
    use sea_orm::{ActiveModelTrait, ActiveValue::Set, IntoActiveModel};
    let tx = db.begin().await?;
    for mapping in mappings {
        let evidence = mapping.clone();
        for (thread, proof) in &mapping.threads {
            if !proof.proven_local_root || evidence.blocked.contains_key(thread) {
                continue;
            }
            let Some(row) = studio_object::Entity::find_by_id((
                AgentCloseRecord::OWNER_KIND.to_owned(),
                thread.clone(),
                AgentCloseRecord::OBJECT_KIND.to_owned(),
            ))
            .one(&tx)
            .await?
            else {
                continue;
            };
            let mut record = decode_object::<AgentCloseRecord>(row.clone())?;
            ensure!(
                record.workspace_id == evidence.workspace_id,
                "bot close Workspace ownership mismatch"
            );
            let relocation = (|| -> Result<()> {
                if let Some(binding) = &mut record.worktree {
                    ensure!(
                        binding.identity.endpoint == WorkspaceEndpoint::Local
                            && binding.lease.ssh_alias.is_none(),
                        "bot close binding is not local; original facts preserved"
                    );
                    evidence.exact_path(&mut binding.identity.root)?;
                    evidence.exact_path(&mut binding.lease.repository_root)?;
                    evidence.exact_path(&mut binding.lease.path)?;
                }
                if let Some(grant) = &mut record.git {
                    ensure!(
                        grant.delivery.endpoint == WorkspaceEndpoint::Local,
                        "bot close grant is not local; original facts preserved"
                    );
                    evidence.exact_path(&mut grant.delivery.root)?;
                    // A worktree/common-dir grant cannot be safely inferred from a path prefix.
                    ensure!(
                        grant.expected_common_dir == evidence.old_root
                            || grant.expected_common_dir == evidence.new_root,
                        "bot close common-dir grant is not an exact managed root; original authorization preserved"
                    );
                    evidence.exact_path(&mut grant.expected_common_dir)?;
                }
                Ok(())
            })();
            if let Err(error) = relocation {
                mapping.blocked.insert(thread.clone(), format!("bot close execution binding cannot be safely relocated; original authorization preserved: {error}"));
                continue;
            }
            let payload = serde_json::to_string(&record)?;
            let mut active = row.into_active_model();
            active.payload_json = Set(payload.clone());
            active.payload_hash = Set(pl_core::context::content_hash(payload.as_bytes()));
            active.update(&tx).await?;
        }
    }
    tx.commit().await?;
    Ok(())
}

impl StudioStore {
    pub(crate) async fn agent_close(&self, id: &str) -> Result<Option<AgentCloseRecord>> {
        load_object(self.database(), id).await
    }

    pub(crate) async fn agent_closes(&self) -> Result<Vec<AgentCloseRecord>> {
        use crate::studio::entity::studio_object;
        studio_object::Entity::find()
            .filter(studio_object::Column::ObjectKind.eq(AgentCloseRecord::OBJECT_KIND))
            .all(self.database())
            .await?
            .into_iter()
            .map(decode_object::<AgentCloseRecord>)
            .collect()
    }

    /// An unpublished old candidate never grants deletion; its source is left untouched.
    pub(crate) async fn has_legacy_retirement(&self, id: &str) -> Result<bool> {
        use crate::studio::entity::studio_object::{self, Column};
        Ok(studio_object::Entity::find()
            .filter(Column::OwnerKind.eq("thread"))
            .filter(Column::OwnerId.eq(id))
            .filter(Column::ObjectKind.eq("agentRetirement"))
            .one(self.database())
            .await?
            .is_some())
    }

    /// The domain job owns this transaction even when its original caller stops waiting.
    pub(crate) async fn save_agent_close(&self, record: &AgentCloseRecord) -> Result<()> {
        record.validate_owner(&record.agent_id)?;
        let tx = self.database().begin().await?;
        put_object(&tx, &record.agent_id, record, crate::studio::unix_seconds()).await?;
        tx.commit().await?;
        ensure!(
            self.agent_close(&record.agent_id).await?.as_ref() == Some(record),
            "agent close transaction verification failed"
        );
        Ok(())
    }

    pub(crate) async fn ensure_agent_execution_allowed(&self, id: &str) -> Result<()> {
        if self.agent_close(id).await?.is_some() || self.has_legacy_retirement(id).await? {
            return Err(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Conflict,
                "Permanently closed agent cannot execute or receive a new evaluation",
                false,
            )
            .into());
        }
        Ok(())
    }
}
