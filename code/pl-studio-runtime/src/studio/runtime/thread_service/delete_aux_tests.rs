//! Deletion isolates undecodable auxiliary rows while ordinary reads remain strict.
use super::*;
use std::sync::{Arc, Mutex};
use tracing::{Subscriber, field::Visit, span};

#[derive(Clone, Default)]
struct Captured(Arc<Mutex<Vec<String>>>);

impl Visit for Captured {
    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        self.0
            .lock()
            .unwrap()
            .push(format!("{}={value}", field.name()));
    }
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        self.0
            .lock()
            .unwrap()
            .push(format!("{}={value:?}", field.name()));
    }
}

impl Subscriber for Captured {
    fn enabled(&self, metadata: &tracing::Metadata<'_>) -> bool {
        metadata.target().starts_with("pl_studio_runtime")
    }
    fn new_span(&self, attributes: &span::Attributes<'_>) -> span::Id {
        attributes.record(&mut self.clone());
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        span::Id::from_u64(NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed))
    }
    fn record(&self, _: &span::Id, values: &span::Record<'_>) {
        values.record(&mut self.clone());
    }
    fn record_follows_from(&self, _: &span::Id, _: &span::Id) {}
    fn event(&self, event: &tracing::Event<'_>) {
        event.record(&mut self.clone());
    }
    fn enter(&self, _: &span::Id) {}
    fn exit(&self, _: &span::Id) {}
}

async fn damaged_aux(
    runtime: &StudioRuntime,
    kind: &str,
    owner: &str,
    object: &str,
    schema: i64,
    payload: &str,
) -> Result<()> {
    runtime.store.database().execute_raw(Statement::from_sql_and_values(
        DatabaseBackend::Sqlite,
        "INSERT OR REPLACE INTO studio_objects
         (owner_kind,owner_id,object_kind,revision,schema_version,payload_json,payload_hash,updated_at)
         VALUES (?,?,?,1,?,?,?,0)",
        [kind.into(), owner.into(), object.into(), schema.into(), payload.into(),
            pl_core::context::content_hash(payload.as_bytes()).into()],
    )).await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_skips_bad_aux_preserves_unknown_rows_and_logs_safe_reasons() -> Result<()>
{
    use crate::studio::store::thread_archive::ArchiveScope;
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("bad-aux-root", &project.id, "root")
        .await?;
    let neighbor = runtime
        .create_thread_with_id("bad-aux-neighbor", &project.id, "keep")
        .await?;
    let secret = "SYNTHETIC-SECRET-USER-CONTENT";
    let broken = format!(r#"{{"rootId":"{secret}""#);
    let project_scope = ArchiveScope::Workspace(project.id.clone()).key();
    let neighbor_scope = ArchiveScope::Thread(neighbor.id.clone()).key();
    let root_scope = ArchiveScope::Thread(root.id.clone()).key();
    for scope in [&project_scope, &neighbor_scope, &root_scope] {
        damaged_aux(&runtime, "archive", scope, "threadArchive", 2, &broken).await?;
    }
    damaged_aux(
        &runtime,
        "thread",
        "unknown-private",
        "threadPreparation",
        2,
        &broken,
    )
    .await?;
    let invalid = serde_json::json!({
        "identity": { "threadId": "invalid-stop", "workspaceId": project.id,
            "parentId": neighbor.id, "rootId": neighbor.id },
        "revision": 1, "binding": { "state": "unbound" },
        "save": "required", "storage": null, "disposition": "pending",
        "stopped": true, "retired": false, "published": false
    });
    // Use the actual binding representation so this reaches validation, rather than JSON shape.
    let mut invalid = invalid;
    invalid["binding"] = serde_json::to_value(
        crate::studio::store::thread_preparation::PreparationBinding::Unbound,
    )?;
    damaged_aux(
        &runtime,
        "thread",
        "invalid-stop",
        "threadPreparation",
        2,
        &invalid.to_string(),
    )
    .await?;
    assert!(runtime.store.thread_preparations().await.is_err());
    assert!(runtime.store.thread_archives().await.is_err());
    let captured = Captured::default();
    let dispatch = tracing::Dispatch::new(captured.clone());
    let _capture = tracing::dispatcher::set_default(&dispatch);
    let failed = workspace.join(SessionFiles::new(&root.id).root());
    if failed.exists() {
        tokio::fs::remove_dir_all(&failed).await?;
    }
    tokio::fs::create_dir_all(failed.parent().unwrap()).await?;
    tokio::fs::write(&failed, secret).await?;
    runtime
        .delete_thread("safe-aux-failed-correlation".into(), root.id.clone())
        .await
        .expect_err("preserve the wrong target while logging safe failure metadata");
    tokio::fs::remove_file(&failed).await?;
    runtime
        .delete_thread("safe-aux-correlation".into(), root.id.clone())
        .await?
        .unwrap();
    let records = captured.0.lock().unwrap().join("\n");
    for expected in [
        "deletion_id=safe-aux-correlation",
        "stage=",
        "member=",
        "reason=aux_json",
        "reason=preparation_save_ack",
        "decision=preserve_unknown_skip",
        "outcome=skipped",
        "elapsed_ms=",
        "line=",
        "column=",
        "outcome=incomplete",
        "decision=continue_independent",
    ] {
        assert!(
            records.contains(expected),
            "missing {expected} in {records}"
        );
    }
    assert!(
        !records.contains(secret),
        "raw auxiliary body leaked into diagnostics"
    );
    assert!(runtime.store.read_thread(&root.id).await?.is_none());
    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
    // Shared objects whose scope cannot be decoded retain exactly their original bytes.
    let rows = runtime
        .store
        .database()
        .query_all_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT payload_json FROM studio_objects WHERE
         (owner_kind='archive' AND owner_id IN (?,?))
         OR (owner_id='unknown-private' AND object_kind='threadPreparation')",
            [project_scope.into(), neighbor_scope.into()],
        ))
        .await?;
    assert_eq!(rows.len(), 3);
    for row in rows {
        assert_eq!(row.try_get::<String>("", "payload_json")?, broken);
    }
    assert!(runtime.store.thread_preparations().await.is_err());
    runtime.shutdown_runtime().await?;
    Ok(())
}
