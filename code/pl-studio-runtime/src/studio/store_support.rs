//! Studio v2 product schema for new projects and product settings.

use anyhow::Result;
use sea_orm::sea_query::{Index, IndexCreateStatement, IndexOrder};
use sea_orm::{ConnectionTrait, DatabaseConnection};

use crate::studio::entity;

pub(super) const STUDIO_DATABASE_SCHEMA_VERSION: i64 = 25;

pub(super) async fn initialize_studio_schema(db: &DatabaseConnection) -> Result<()> {
    create_thread_lifecycle_tables(db).await?;
    create_agent_evaluations(db).await?;
    db.get_schema_builder()
        .register(entity::app_setting::Entity)
        .register(entity::project::Entity)
        .register(entity::studio_object::Entity)
        .apply(db)
        .await?;
    create_state_indexes(db).await?;
    set_schema_version(db).await?;
    Ok(())
}

async fn create_thread_lifecycle_tables(db: &DatabaseConnection) -> Result<()> {
    db.execute_unprepared(
        r#"
        CREATE TABLE IF NOT EXISTS threads (
            id TEXT PRIMARY KEY NOT NULL,
            project_id TEXT NOT NULL,
            title TEXT NOT NULL,
            mode TEXT NOT NULL,
            root_thread_id TEXT NOT NULL,
            parent_thread_id TEXT,
            role TEXT NOT NULL,
            agent_path TEXT NOT NULL UNIQUE,
            state_json TEXT NOT NULL CHECK (json_valid(state_json)),
            state_kind TEXT GENERATED ALWAYS AS (
                json_extract(state_json, '$.kind')
            ) STORED NOT NULL CHECK (
                state_kind IN (
                    'idle', 'queued', 'running', 'waitingTool',
                    'waitingInteraction', 'cancelling', 'closing', 'closed',
                    'faulted'
                )
            ),
            revision INTEGER NOT NULL,
            runtime_revision INTEGER,
            event_sequence INTEGER NOT NULL,
            metadata_json TEXT NOT NULL,
            usage_json TEXT NOT NULL,
            last_context_tokens INTEGER,
            trace_sequence INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            archived INTEGER NOT NULL,
            workspace_mode TEXT NOT NULL DEFAULT 'local',
            workspace_path TEXT NOT NULL DEFAULT '',
            last_user_message_at INTEGER,
            delegation_mode TEXT NOT NULL DEFAULT 'profile',
            delegation_preference TEXT NOT NULL DEFAULT 'balanced',
            frozen_model_json TEXT,
            explicitly_closed INTEGER NOT NULL DEFAULT 0 CHECK(explicitly_closed IN (0,1)),
            FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
        );

        "#,
    )
    .await?;
    Ok(())
}

/// Independent typed product domain, deliberately not a generic object or call-statistics row.
pub(in crate::studio) async fn create_agent_evaluations(db: &impl ConnectionTrait) -> Result<()> {
    db.execute_unprepared(r#"
        CREATE TABLE agent_evaluations (
            agent_id TEXT PRIMARY KEY NOT NULL,
            parent_agent_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            model_id TEXT NOT NULL,
            effort TEXT,
            profile_id TEXT NOT NULL,
            mode TEXT NOT NULL CHECK(mode IN ('profile','automatic')),
            preference TEXT NOT NULL CHECK(preference IN ('economy','balanced','fast')),
            turn_id TEXT NOT NULL,
            revision INTEGER NOT NULL CHECK(revision > 0),
            task_category TEXT NOT NULL,
            outcome TEXT NOT NULL CHECK(outcome IN ('passed','failed','notRated')),
            quality INTEGER,
            instruction_following INTEGER,
            comment TEXT NOT NULL CHECK(length(trim(comment)) > 0 AND length(comment) <= 300),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            CHECK ((outcome = 'notRated' AND quality IS NULL AND instruction_following IS NULL)
                OR (outcome IN ('passed','failed') AND quality IS NOT NULL AND instruction_following IS NOT NULL AND quality BETWEEN 1 AND 5
                    AND instruction_following BETWEEN 1 AND 5))
        );
        CREATE INDEX idx_agent_evaluations_model_updated ON agent_evaluations
            (account_id, model_id, updated_at DESC, agent_id DESC);
    "#).await?;
    Ok(())
}

pub(super) fn non_empty_title(title: &str) -> String {
    let title = title.trim();
    if title.is_empty() {
        "新会话".to_string()
    } else {
        title.chars().take(80).collect()
    }
}

async fn set_schema_version(db: &impl ConnectionTrait) -> Result<()> {
    db.execute_unprepared(&format!(
        "PRAGMA user_version = {STUDIO_DATABASE_SCHEMA_VERSION}"
    ))
    .await?;
    Ok(())
}

async fn create_state_indexes(db: &DatabaseConnection) -> Result<()> {
    create_project_indexes(db).await?;
    let indexes = [
        Index::create()
            .name("idx_threads_project_updated")
            .table(entity::thread::Entity)
            .col(entity::thread::Column::ProjectId)
            .col(entity::thread::Column::Archived)
            .col((entity::thread::Column::UpdatedAt, IndexOrder::Desc))
            .col((entity::thread::Column::Id, IndexOrder::Desc))
            .to_owned(),
        Index::create()
            .name("idx_threads_root_parent")
            .table(entity::thread::Entity)
            .col(entity::thread::Column::RootThreadId)
            .col(entity::thread::Column::ParentThreadId)
            .col(entity::thread::Column::CreatedAt)
            .to_owned(),
    ];
    for index in indexes {
        execute_index(db, index).await?;
    }
    Ok(())
}

async fn create_project_indexes(db: &impl ConnectionTrait) -> Result<()> {
    let recent = Index::create()
        .name("idx_projects_closed_last_opened_at")
        .table(entity::project::Entity)
        .col(entity::project::Column::Closed)
        .col((entity::project::Column::LastOpenedAt, IndexOrder::Desc))
        .col((entity::project::Column::UpdatedAt, IndexOrder::Desc))
        .col((entity::project::Column::Id, IndexOrder::Desc))
        .to_owned();
    db.execute(&recent).await?;
    db.execute_unprepared(
        "CREATE UNIQUE INDEX idx_projects_local_path
         ON projects(path) WHERE ssh_alias IS NULL;
         CREATE UNIQUE INDEX idx_projects_remote_path
         ON projects(ssh_alias, path) WHERE ssh_alias IS NOT NULL;",
    )
    .await?;
    Ok(())
}

async fn execute_index(db: &DatabaseConnection, index: IndexCreateStatement) -> Result<()> {
    db.execute(&index).await?;
    Ok(())
}
