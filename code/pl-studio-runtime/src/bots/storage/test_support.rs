use super::*;

/// 直接以 v3 形态建库并塞入真实业务行：一条远古过期 claimed 的 work、
/// 一个 bound 绑定与一条发送事实，用于验证 v4 迁移的真实保全与 lease 语义。
pub(super) async fn v3_database(path: &Path) -> DatabaseConnection {
    let mut options = sqlite_file_options(path, SqliteFileMode::Create, |options| options)
        .await
        .unwrap();
    options.max_connections(1);
    let db = Database::connect(options).await.unwrap();
    db.execute_unprepared(
        "CREATE TABLE bot_meta (id INTEGER PRIMARY KEY CHECK (id = 1), schema_version INTEGER NOT NULL);
         INSERT INTO bot_meta(id, schema_version) VALUES(1, 3);
         CREATE TABLE inbound_identities (
            identity TEXT PRIMARY KEY, bot_id TEXT NOT NULL DEFAULT '',
            message_id TEXT NOT NULL, chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL, admitted_at INTEGER NOT NULL);
         CREATE TABLE inbound_work (
            identity TEXT PRIMARY KEY, bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL DEFAULT '', message_id TEXT NOT NULL DEFAULT '',
            content_hash TEXT NOT NULL DEFAULT '', text TEXT NOT NULL DEFAULT '',
            open_id TEXT NOT NULL DEFAULT '', chat_kind TEXT NOT NULL DEFAULT '',
            generation INTEGER NOT NULL DEFAULT 0, app_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '', creation_id TEXT NOT NULL DEFAULT '',
            binding_revision INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL,
            diagnostic TEXT NOT NULL, claimed_by TEXT NOT NULL DEFAULT '',
            claimed_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL);
         CREATE TABLE thread_bindings (
            chat_id TEXT PRIMARY KEY, thread_id TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'bound', creation_id TEXT NOT NULL DEFAULT '',
            project_id TEXT NOT NULL DEFAULT '', revision INTEGER NOT NULL DEFAULT 0,
            generation INTEGER NOT NULL DEFAULT 0, diagnostic TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL DEFAULT 0);
         CREATE TABLE observed_directs (
            chat_id TEXT PRIMARY KEY, open_id TEXT NOT NULL, name TEXT NOT NULL,
            last_observed_at INTEGER NOT NULL);
         CREATE TABLE pairing_requests (
            request_id TEXT PRIMARY KEY, open_id TEXT NOT NULL,
            display_name TEXT NOT NULL, created_at INTEGER NOT NULL);
         CREATE TABLE send_operations (
            operation_id TEXT PRIMARY KEY, bot_id TEXT NOT NULL DEFAULT '',
            chat_id TEXT NOT NULL, content_hash TEXT NOT NULL, status TEXT NOT NULL,
            platform_message_ids TEXT NOT NULL, updated_at INTEGER NOT NULL);
         CREATE TABLE binding_operations (
            operation_id TEXT PRIMARY KEY, bot_id TEXT NOT NULL, chat_id TEXT NOT NULL,
            content_hash TEXT NOT NULL, expected_revision INTEGER NOT NULL,
            creation_id TEXT NOT NULL, thread_id TEXT NOT NULL DEFAULT '',
            updated_at INTEGER NOT NULL);
         INSERT INTO inbound_work(identity, bot_id, chat_id, message_id, content_hash, text,
           open_id, chat_kind, app_id, project_id, creation_id, binding_revision, status,
           diagnostic, claimed_by, claimed_at, updated_at)
         VALUES('legacy:chat:m1', 'legacy', 'chat', 'm1', 'hash', 'question',
           'open', 'direct', 'app', 'project', 'botthread:legacy:chat', 1, 'claimed',
           '', 'crashed-worker', 1, 1);
         INSERT INTO thread_bindings(chat_id, thread_id, status, creation_id, project_id,
           revision, generation, diagnostic, created_at, updated_at)
         VALUES('chat', 'thread-1', 'bound', 'botthread:legacy:chat', 'project', 1, 1, '', 1, 1);
         INSERT INTO send_operations(operation_id, bot_id, chat_id, content_hash, status,
           platform_message_ids, updated_at)
         VALUES('op-1', 'legacy', 'chat', 'hash', 'succeeded', 'pm-1', 1);",
    )
    .await
    .unwrap();
    db
}

pub(super) async fn work_status(store: &BotStateStore, identity: &str) -> (String, String) {
    let db = store.db().await.unwrap();
    let row = db
        .query_one_raw(statement(
            "SELECT status, claimed_by FROM inbound_work WHERE identity=?",
            vec![identity.to_string().into()],
        ))
        .await
        .unwrap()
        .expect("migrated work row");
    (
        row.try_get("", "status").unwrap(),
        row.try_get("", "claimed_by").unwrap(),
    )
}
