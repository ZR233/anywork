-- Frozen Studio v2 product schema. Runtime entities must not redefine this migration.

CREATE TABLE "projects" ( "id" varchar NOT NULL PRIMARY KEY, "name" varchar NOT NULL, "path" varchar NOT NULL, "ssh_alias" varchar, "created_at" integer NOT NULL, "updated_at" integer NOT NULL, "last_opened_at" integer, "closed" integer NOT NULL );

CREATE TABLE "app_settings" ( "key" varchar NOT NULL PRIMARY KEY, "value" varchar NOT NULL, "updated_at" integer NOT NULL );

CREATE TABLE "studio_objects" ( "owner_kind" varchar NOT NULL, "owner_id" varchar NOT NULL, "object_kind" varchar NOT NULL, "revision" integer NOT NULL, "schema_version" integer NOT NULL, "payload_json" varchar NOT NULL, "payload_hash" varchar NOT NULL, "updated_at" integer NOT NULL, CONSTRAINT "pk-studio_objects" PRIMARY KEY ("owner_kind", "owner_id", "object_kind") );

CREATE TABLE threads (
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
            last_user_message_at INTEGER, delegation_mode TEXT NOT NULL DEFAULT 'profile', delegation_preference TEXT NOT NULL DEFAULT 'balanced', frozen_model_json TEXT, explicitly_closed INTEGER NOT NULL DEFAULT 0 CHECK(explicitly_closed IN (0,1)),
            FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE
        );

CREATE INDEX "idx_projects_closed_last_opened_at" ON "projects" ("closed", "last_opened_at" DESC, "updated_at" DESC, "id" DESC);

CREATE UNIQUE INDEX idx_projects_local_path
         ON projects(path) WHERE ssh_alias IS NULL;

CREATE UNIQUE INDEX idx_projects_remote_path
         ON projects(ssh_alias, path) WHERE ssh_alias IS NOT NULL;

CREATE INDEX "idx_threads_project_updated" ON "threads" ("project_id", "archived", "updated_at" DESC, "id" DESC);

CREATE INDEX "idx_threads_root_parent" ON "threads" ("root_thread_id", "parent_thread_id", "created_at");
