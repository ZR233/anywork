//! Only the named product migration reads schema-1 close records and their branch-bound lease.
use super::{AgentCloseGitGrant, AgentCloseRecord, OwnedWorktreeBinding};
use crate::studio::{
    agent_close::AgentWorktreeCleanup,
    agent_host::worktree_lease::{
        WorkspaceIdentity, WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
    },
    entity::studio_object,
    store::object::{PersistedStudioObject, decode_object},
};
use anyhow::{Result, ensure};
use pl_core::context::content_hash;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, ConnectionTrait, EntityTrait, IntoActiveModel,
    QueryFilter, QueryOrder,
};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CloseV1 {
    agent_id: String,
    parent_id: String,
    root_id: String,
    project_id: String,
    revision: u64,
    force: bool,
    worktree: Option<BindingV1>,
    git: Option<GrantV1>,
    execution_closed: bool,
    worktree_cleanup: AgentWorktreeCleanup,
    error: Option<pl_protocol::StateError>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct BindingV1 {
    lease: LeaseV1,
    identity: WorkspaceIdentity,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct GrantV1 {
    delivery: WorkspaceIdentity,
    expected_head: String,
    expected_common_dir: String,
    removal_started: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LeaseV1 {
    revision: u64,
    state: WorktreeLeaseState,
    owner_kind: WorktreeLeaseOwnerKind,
    owner_thread_id: String,
    root_thread_id: String,
    project_id: String,
    ssh_alias: Option<String>,
    repository_root: String,
    path: String,
    branch: String,
    base_commit: String,
    #[serde(default)]
    restore_authorized_at: Option<i64>,
}

impl CloseV1 {
    fn upgrade(self) -> Result<AgentCloseRecord> {
        let worktree = self
            .worktree
            .map(|binding| {
                let old = binding.lease;
                ensure!(
                    !old.branch.trim().is_empty(),
                    "schema-1 close lease branch is empty"
                );
                // Retiring these representation fields supplies neither deletion nor rebuild authority.
                let _retired_restore_grant = old.restore_authorized_at;
                Ok::<_, anyhow::Error>(OwnedWorktreeBinding {
                    identity: binding.identity,
                    lease: WorktreeLease {
                        revision: old.revision,
                        state: old.state,
                        owner_kind: old.owner_kind,
                        owner_thread_id: old.owner_thread_id,
                        root_thread_id: old.root_thread_id,
                        workspace_id: old.project_id,
                        ssh_alias: old.ssh_alias,
                        repository_root: old.repository_root,
                        path: old.path,
                        base_commit: old.base_commit,
                    },
                })
            })
            .transpose()?;
        Ok(AgentCloseRecord {
            agent_id: self.agent_id,
            parent_id: self.parent_id,
            root_id: self.root_id,
            workspace_id: self.project_id,
            revision: self.revision,
            force: self.force,
            worktree,
            git: self.git.map(|grant| AgentCloseGitGrant {
                delivery: grant.delivery,
                expected_head: grant.expected_head,
                expected_common_dir: grant.expected_common_dir,
                removal_started: grant.removal_started,
            }),
            execution_closed: self.execution_closed,
            worktree_cleanup: self.worktree_cleanup,
            error: self.error,
        })
    }
}

/// The official migration runner supplies one transaction for all records and its completion row.
/// Unknown versions, payload hashes, owners and semantic conflicts fail the whole named step.
pub(in crate::studio::store) async fn upgrade_bindings(db: &impl ConnectionTrait) -> Result<()> {
    let rows = studio_object::Entity::find()
        .filter(studio_object::Column::ObjectKind.eq(AgentCloseRecord::OBJECT_KIND))
        .order_by_asc(studio_object::Column::OwnerKind)
        .order_by_asc(studio_object::Column::OwnerId)
        .all(db)
        .await?;
    for mut row in rows {
        ensure!(
            row.owner_kind == AgentCloseRecord::OWNER_KIND,
            "agent close migration owner-kind conflict"
        );
        if row.schema_version == AgentCloseRecord::SCHEMA_VERSION {
            decode_object::<AgentCloseRecord>(row)?;
            continue;
        }
        ensure!(
            matches!(row.schema_version, 1 | 2),
            "unknown agent close object version {}",
            row.schema_version
        );
        ensure!(
            content_hash(row.payload_json.as_bytes()) == row.payload_hash,
            "agent close {} hash mismatch before binding migration",
            row.owner_id
        );
        let record = if row.schema_version == 1 {
            let old: CloseV1 = serde_json::from_str(&row.payload_json)?;
            old.upgrade()?
        } else {
            // Schema 2 already retired branch identity, but still froze projectId at the two
            // ownership positions. Do not recursively rename opaque values or other project facts.
            let mut old: serde_json::Value = serde_json::from_str(&row.payload_json)?;
            rename_owner(
                old.as_object_mut()
                    .ok_or_else(|| anyhow::anyhow!("invalid close V2"))?,
            )?;
            if let Some(lease) = old.pointer_mut("/worktree/lease") {
                rename_owner(
                    lease
                        .as_object_mut()
                        .ok_or_else(|| anyhow::anyhow!("invalid close V2 lease"))?,
                )?;
            }
            serde_json::from_value(old)?
        };
        let payload = serde_json::to_string(&record)?;
        row.payload_json = payload.clone();
        row.payload_hash = content_hash(payload.as_bytes());
        row.schema_version = AgentCloseRecord::SCHEMA_VERSION;
        // This checks the unchanged row revision and ID as well as all current binding/grant facts.
        decode_object::<AgentCloseRecord>(row.clone())?;
        let mut active = row.into_active_model();
        active.payload_json = Set(payload.clone());
        active.payload_hash = Set(content_hash(payload.as_bytes()));
        active.schema_version = Set(AgentCloseRecord::SCHEMA_VERSION);
        // Keep updated_at, revision, force, results, errors, all IDs and removal_started unchanged.
        active.update(db).await?;
    }
    Ok(())
}

fn rename_owner(object: &mut serde_json::Map<String, serde_json::Value>) -> Result<()> {
    ensure!(
        !object.contains_key("workspaceId"),
        "conflicting close V2 ownership fields"
    );
    let id = object
        .remove("projectId")
        .ok_or_else(|| anyhow::anyhow!("missing close V2 projectId"))?;
    object.insert("workspaceId".into(), id);
    Ok(())
}

#[cfg(test)]
mod migration_tests {
    use super::*;
    use anyhow::Context;
    use sea_orm::{Database, DatabaseBackend, DatabaseConnection, Statement};
    use serde_json::{Value, json};
    use std::path::Path;

    const STEP: &str = "m20261027_000005_agent_close_binding";

    async fn product_25() -> Result<DatabaseConnection> {
        let db = Database::connect("sqlite::memory:").await?;
        db.execute_unprepared(include_str!("../product_schema.sql"))
            .await?;
        db.execute_unprepared(include_str!("../agent_evaluations.sql"))
            .await?;
        db.execute_unprepared("PRAGMA user_version=25").await?;
        Ok(db)
    }

    fn legacy_record(repository: &Path, agent: &str, owned: bool) -> Value {
        let path = crate::agent::worktree::WorktreeManager::allocate_path(
            repository,
            "root",
            &crate::agent::worktree::WorktreeOwnership::Child {
                child_id: agent.into(),
            },
        );
        let worktree = owned.then(|| {
            json!({
                "lease": {
                    "revision": 9, "state": "preserved", "ownerKind": "child",
                    "ownerThreadId": agent, "rootThreadId": "root", "projectId": "project",
                    "sshAlias": null, "repositoryRoot": repository, "path": path,
                    "branch": "pure-agent-original", "baseCommit": "a".repeat(40),
                    "restoreAuthorizedAt": 123,
                },
                "identity": {"endpoint": {"kind": "local"}, "root": path},
            })
        });
        let git = owned.then(|| {
            json!({
                "delivery": {"endpoint": {"kind": "local"}, "root": repository},
                "expectedHead": "b".repeat(40), "expectedCommonDir": repository.join(".git"),
                "removalStarted": true,
            })
        });
        let cleanup = if owned {
            json!({"kind": "removed", "path": path})
        } else {
            json!({"kind": "notApplicable"})
        };
        json!({
            "agentId": agent, "parentId": "parent", "rootId": "root", "projectId": "project",
            "revision": 7, "force": owned, "worktree": worktree, "git": git,
            "executionClosed": true, "worktreeCleanup": cleanup,
            "error": {"code": "originalCloseFailure", "message": "original bounded failure", "retryable": true},
        })
    }

    fn legacy_row(repository: &Path, agent: &str, owned: bool) -> Result<studio_object::Model> {
        let payload = serde_json::to_string(&legacy_record(repository, agent, owned))?;
        Ok(studio_object::Model {
            owner_kind: "thread".into(),
            owner_id: agent.into(),
            object_kind: "agentClose".into(),
            schema_version: 1,
            revision: 7,
            payload_hash: content_hash(payload.as_bytes()),
            payload_json: payload,
            updated_at: 123456,
        })
    }

    async fn close_rows(db: &DatabaseConnection) -> Result<Vec<studio_object::Model>> {
        Ok(studio_object::Entity::find()
            .filter(studio_object::Column::ObjectKind.eq("agentClose"))
            .order_by_asc(studio_object::Column::OwnerKind)
            .order_by_asc(studio_object::Column::OwnerId)
            .all(db)
            .await?)
    }

    async fn product_format(db: &DatabaseConnection) -> Result<i64> {
        Ok(db
            .query_one_raw(Statement::from_string(
                DatabaseBackend::Sqlite,
                "PRAGMA user_version",
            ))
            .await?
            .context("product format")?
            .try_get_by_index(0)?)
    }

    #[tokio::test]
    async fn named_upgrade_preserves_closed_facts_with_and_without_owned_worktrees() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let db = product_25().await?;
        let mut expected = Vec::new();
        for (agent, owned) in [("a-owned", true), ("b-review", false)] {
            let row = legacy_row(temp.path(), agent, owned)?;
            row.into_active_model().insert(&db).await?;
            let mut payload = legacy_record(temp.path(), agent, owned);
            if owned {
                let lease = payload["worktree"]["lease"]
                    .as_object_mut()
                    .context("frozen lease")?;
                lease.remove("branch");
                lease.remove("restoreAuthorizedAt");
                let owner = lease.remove("projectId").context("legacy lease owner")?;
                lease.insert("workspaceId".into(), owner);
            }
            let owner = payload
                .as_object_mut()
                .context("legacy close")?
                .remove("projectId")
                .context("legacy owner")?;
            payload["workspaceId"] = owner;
            expected.push(payload);
        }
        // A current representation is validated without a rewrite even when this step is pending.
        let mut current = legacy_row(temp.path(), "c-current", false)?;
        current.schema_version = 3;
        let mut payload: Value = serde_json::from_str(&current.payload_json)?;
        let owner = payload
            .as_object_mut()
            .context("current close")?
            .remove("projectId")
            .context("current owner")?;
        payload["workspaceId"] = owner;
        current.payload_json = serde_json::to_string(&payload)?;
        current.payload_hash = content_hash(current.payload_json.as_bytes());
        current.clone().into_active_model().insert(&db).await?;
        crate::studio::store::schema::migrate(&db).await?;
        let rows = close_rows(&db).await?;
        for (row, expected) in rows[..2].iter().zip(expected) {
            assert_eq!(row.schema_version, 3);
            assert_eq!(row.revision, 7);
            assert_eq!(row.updated_at, 123456);
            assert_eq!(row.payload_hash, content_hash(row.payload_json.as_bytes()));
            assert_eq!(
                serde_json::to_value(decode_object::<AgentCloseRecord>(row.clone())?)?,
                expected
            );
        }
        assert_eq!(rows[2], current);
        assert_eq!(product_format(&db).await?, 27);
        assert!(
            db.query_one_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "SELECT version FROM seaql_migrations WHERE version=?",
                [STEP.into()],
            ))
            .await?
            .is_some()
        );
        crate::studio::store::schema::migrate(&db).await?;
        assert_eq!(
            close_rows(&db).await?,
            rows,
            "current records must remain byte-identical"
        );
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn latest_v2_close_schema_two_preserves_frozen_cleanup_and_authorization_facts()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let db = product_25().await?;
        let mut expected = Vec::new();
        for (agent, owned) in [("a-schema-two-owned", true), ("b-schema-two-review", false)] {
            let mut row = legacy_row(temp.path(), agent, owned)?;
            let mut old = legacy_record(temp.path(), agent, owned);
            if owned {
                let lease = old["worktree"]["lease"]
                    .as_object_mut()
                    .context("v2 lease")?;
                lease.remove("branch");
                lease.remove("restoreAuthorizedAt");
            }
            assert!(old.get("projectId").is_some());
            assert!(old.get("workspaceId").is_none());
            row.schema_version = 2;
            row.payload_json = old.to_string();
            row.payload_hash = content_hash(row.payload_json.as_bytes());
            row.into_active_model().insert(&db).await?;
            let owner = old
                .as_object_mut()
                .context("close")?
                .remove("projectId")
                .context("owner")?;
            old["workspaceId"] = owner;
            if owned {
                let owner = old["worktree"]["lease"]
                    .as_object_mut()
                    .context("lease")?
                    .remove("projectId")
                    .context("lease owner")?;
                old["worktree"]["lease"]["workspaceId"] = owner;
            }
            expected.push(old);
        }
        crate::studio::store::schema::migrate(&db).await?;
        let rows = close_rows(&db).await?;
        for (row, expected) in rows.iter().zip(expected) {
            assert_eq!(row.schema_version, 3);
            assert_eq!(row.revision, 7);
            assert_eq!(row.updated_at, 123456);
            assert_eq!(
                serde_json::to_value(decode_object::<AgentCloseRecord>(row.clone())?)?,
                expected
            );
        }
        crate::studio::store::schema::migrate(&db).await?;
        assert_eq!(close_rows(&db).await?, rows);
        db.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn invalid_close_fact_rolls_back_every_binding_and_named_completion() -> Result<()> {
        let temp = tempfile::tempdir()?;
        for fault in [
            "version",
            "hash",
            "ownerKind",
            "ownerId",
            "revision",
            "binding",
        ] {
            let db = product_25().await?;
            legacy_row(temp.path(), "a-valid", true)?
                .into_active_model()
                .insert(&db)
                .await?;
            let mut invalid = legacy_row(temp.path(), "z-invalid", true)?;
            match fault {
                "version" => invalid.schema_version = 99,
                "hash" => invalid.payload_hash = "wrong-hash".into(),
                "ownerKind" => invalid.owner_kind = "z-not-thread".into(),
                "ownerId" => invalid.owner_id = "z-other-owner".into(),
                "revision" => invalid.revision += 1,
                "binding" => {
                    let mut payload: Value = serde_json::from_str(&invalid.payload_json)?;
                    payload["worktree"]["lease"]["rootThreadId"] = json!("wrong-root");
                    invalid.payload_json = serde_json::to_string(&payload)?;
                    invalid.payload_hash = content_hash(invalid.payload_json.as_bytes());
                }
                _ => unreachable!(),
            }
            invalid.into_active_model().insert(&db).await?;
            let original = close_rows(&db).await?;
            assert!(
                crate::studio::store::schema::migrate(&db).await.is_err(),
                "{fault}"
            );
            assert_eq!(
                close_rows(&db).await?,
                original,
                "{fault}: no partial representation upgrade"
            );
            assert_eq!(
                product_format(&db).await?,
                25,
                "{fault}: product format must roll back"
            );
            assert!(
                db.query_one_raw(Statement::from_sql_and_values(
                    DatabaseBackend::Sqlite,
                    "SELECT version FROM seaql_migrations WHERE version=?",
                    [STEP.into()],
                ))
                .await?
                .is_none(),
                "{fault}: no false migration completion"
            );
            db.close().await?;
        }
        Ok(())
    }
}
