use super::*;
use crate::studio::{
    StudioStore,
    storage_fault_test_support::{
        ThreadStorageSink, close_factory, spawn_live_projection_for_thread,
    },
};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    model::{
        DynModelSession, Model, ModelError, ModelFactory, ModelRequest, ModelSession,
        ModelStepOutput, PreparedModelCall,
    },
    thread::{
        TurnInput,
        cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
    },
};
use sea_orm::{Database, SqliteTransactionMode, TransactionOptions, TransactionTrait};
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
    time::Duration,
};

fn context(caller: &str, cancellation: CancellationToken) -> CallContext {
    CallContext {
        thread_id: caller.into(),
        turn_id: "query".into(),
        call_id: "read-saved".into(),
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
        cancellation,
        extensions: Arc::new(Default::default()),
        catalog: Arc::from([]),
        extension_sequence: 0,
    }
}

fn tool(owner: &SessionRuntime) -> Result<QueryTool> {
    Ok(QueryTool {
        definition: ToolDefinition::json(
            "read_agent_session",
            "Read saved history",
            pl_agent_tool::typed::input_schema_for::<SessionInput>(),
        )?,
        registry: Arc::downgrade(&owner.0),
        kind: Kind::Session,
    })
}

fn input(value: serde_json::Value) -> OpaquePayload {
    OpaquePayload::new("application/json", 1, value.to_string()).unwrap()
}

async fn query(tool: &QueryTool, value: serde_json::Value) -> Result<AgentSessionPage> {
    let result = tokio::time::timeout(
        Duration::from_secs(5),
        tool.execute(input(value), context("root", CancellationToken::new())),
    )
    .await??;
    Ok(serde_json::from_str(result.payload().content())?)
}

fn record(id: &str, parent: Option<&str>, path: &std::path::Path) -> pl_protocol::Thread {
    let mut record = pl_protocol::Thread::placeholder(id);
    record.workspace_id = "query-project".into();
    record.root_thread_id = "root".into();
    record.parent_thread_id = parent.map(str::to_owned);
    record.workspace_path = path.to_string_lossy().into_owned();
    record
}

#[derive(Debug)]
struct CountFlush {
    sink: ThreadStorageSink,
    calls: Arc<AtomicUsize>,
}

impl ColdStore for CountFlush {
    fn pressure(&self, thread: &str) -> StoragePressure {
        self.sink.pressure(thread)
    }
    fn subscribe_pressure(&self, thread: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        self.sink.subscribe_pressure(thread)
    }
    fn admit(&self, thread: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        self.sink.admit(thread, write)
    }
    async fn flush(&self, thread: &str, sequence: u64) -> Result<(), ColdStoreError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.sink.flush(thread, sequence).await
    }
}

struct SavedThenBlocked(Arc<Mutex<Option<tokio::sync::oneshot::Sender<()>>>>);
struct Session {
    first: bool,
    entered: Arc<Mutex<Option<tokio::sync::oneshot::Sender<()>>>>,
}
impl Model for SavedThenBlocked {
    async fn open_session(&self) -> Result<DynModelSession, ModelError> {
        Ok(DynModelSession::new(Session {
            first: true,
            entered: self.0.clone(),
        }))
    }
}
impl ModelSession for Session {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let first = std::mem::replace(&mut self.first, false);
        let entered = self.entered.clone();
        Ok(PreparedModelCall::new(async move {
            if !first {
                if let Some(entered) = entered.lock().unwrap().take() {
                    let _ = entered.send(());
                }
                request.cancellation.cancelled().await;
            }
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![ContextContent::Text {
                    text: Arc::from("saved answer"),
                }],
                tool_calls: vec![],
                private_context: None,
                usage: Default::default(),
            })
        }))
    }
    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

fn turn(id: &str, cancellation: CancellationToken) -> TurnInput {
    TurnInput {
        turn_id: id.into(),
        attempt_prefix: format!("attempt-{id}"),
        content: vec![ContextContent::Text {
            text: Arc::from("question"),
        }],
        max_model_steps: pl_core::thread::ModelStepLimit::Limited(1.try_into().unwrap()),
        cancellation,
    }
}

#[tokio::test]
async fn read_agent_session_returns_saved_page_while_model_and_writer_are_blocked() -> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = StudioStore::open(dir.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let owner = SessionRuntime::open(pl_protocol::SessionId::new("root")?);
    fixture.install(&owner)?;
    let record = record("root", None, dir.path());
    fixture.events.commit_test_thread(&record).await?;
    let sink = ThreadStorageSink::new(store.clone(), record, None).await?;
    let projection = spawn_live_projection_for_thread(store.clone(), "root");
    let calls = Arc::new(AtomicUsize::new(0));
    let mut spec = super::super::agents::archive_tests::spec("root".into(), None, dir.path());
    spec.initial_extensions.insert(
        crate::studio::delegation::EXTENSION.into(),
        crate::studio::delegation::encode(Default::default())?,
    );
    spec.cold_store = Some(ColdStoreHandle::new(CountFlush {
        sink,
        calls: calls.clone(),
    }));
    let mut activation = ThreadActivation::native_test("root", None);
    activation.agent.session_id = owner.id().clone();
    owner.install_explicit_activation(activation);
    let root = owner.assemble(spec).await?;
    let (entered_tx, entered) = tokio::sync::oneshot::channel();
    root.replace_model(ModelFactory::new(SavedThenBlocked(Arc::new(Mutex::new(
        Some(entered_tx),
    )))))
    .await?;
    root.run_turn(turn("saved", CancellationToken::new()))
        .await?;
    root.flush().await?;
    let tool = tool(&owner)?;
    let before = query(&tool, serde_json::json!({"target":"root", "detail":"full"})).await?;
    assert!(
        !before.items.is_empty(),
        "the original writer must have saved real execution history"
    );
    let path = store.registered_session_paths("root")?.history_database();
    let options = crate::studio::paths::sqlite_file_options(
        &path,
        crate::studio::paths::SqliteFileMode::ReadWrite,
        |options| options,
    )
    .await?;
    let blocker = Database::connect(options).await?;
    let cancellation = CancellationToken::new();
    let running = root.run_turn(turn("blocked", cancellation.clone()));
    let read = async {
        entered.await?;
        let locked = blocker
            .begin_with_options(TransactionOptions {
                sqlite_transaction_mode: Some(SqliteTransactionMode::Immediate),
                ..Default::default()
            })
            .await?;
        let history = store.history("root").await?;
        let saved = history
            .agent_page(true, false, None, None, None, 20, &CancellationToken::new())
            .await?;
        tokio::time::timeout(
            Duration::from_secs(5),
            root.queue_runtime_facts(vec![pl_core::thread::RuntimeFact {
                source_id: "query-pending-save".into(),
                content: vec![ContextContent::Text {
                    text: Arc::from("blocked behind the writer transaction"),
                }],
            }]),
        )
        .await
        .context("running owner must admit the pending runtime fact")??;
        calls.store(0, Ordering::SeqCst);
        let page = query(&tool, serde_json::json!({"target":"root", "detail":"full"})).await;
        assert_eq!(
            calls.load(Ordering::SeqCst),
            0,
            "reading must never ask the target to flush"
        );
        let page = page?;
        assert_eq!(page.through_sequence, saved.0);
        assert_eq!(page.items, saved.2);
        assert!(page.through_sequence >= before.through_sequence);
        let first = query(
            &tool,
            serde_json::json!({"target":"root", "detail":"full", "limit":1}),
        )
        .await?;
        assert_eq!(first.items, page.items[..1]);
        assert!(
            first.has_more,
            "the real execution supplies multiple entries"
        );
        let next = query(
            &tool,
            serde_json::json!({
                "target":"root", "detail":"full", "limit":1,
                "cursor":first.next_cursor.context("continuation")?,
            }),
        )
        .await?;
        assert_eq!(next.through_sequence, saved.0);
        assert_eq!(next.items, page.items[1..2]);
        assert!(
            query(&tool, serde_json::json!({"target":"root", "limit":0}),)
                .await
                .is_err()
        );
        assert_eq!(
            calls.load(Ordering::SeqCst),
            0,
            "continuation and errors must not flush"
        );
        assert_eq!(
            owner.0.state().entries.len(),
            1,
            "reading must not activate another execution"
        );
        locked.rollback().await?;
        cancellation.cancel();
        Ok::<_, anyhow::Error>(())
    };
    let (execution, read) = tokio::time::timeout(Duration::from_secs(15), async {
        tokio::join!(running, read)
    })
    .await?;
    read?;
    assert!(
        matches!(execution, Err(pl_core::thread::ThreadError::Cancelled)),
        "the deliberately cancelled model must finish through the typed cancellation path"
    );
    assert!(owner.close_session().await.is_empty());
    projection.abort();
    let _ = projection.await;
    blocker.close().await?;
    fixture.shutdown().await?;
    store.close().await?;
    Ok(())
}

#[tokio::test]
async fn read_agent_session_preserves_cold_empty_errors_permissions_and_cursor_binding()
-> Result<()> {
    let dir = tempfile::tempdir()?;
    let store = StudioStore::open(dir.path().join("data/studio.sqlite")).await?;
    let fixture = close_factory(&store)?;
    let owner = SessionRuntime::open(pl_protocol::SessionId::new("root")?);
    fixture.install(&owner)?;
    for (id, parent) in [
        ("root", None),
        ("cold", Some("root")),
        ("sibling", Some("root")),
    ] {
        fixture
            .events
            .commit_test_thread(&record(id, parent, dir.path()))
            .await?;
    }
    let mut spec = super::super::agents::archive_tests::spec("root".into(), None, dir.path());
    spec.initial_extensions.insert(
        crate::studio::delegation::EXTENSION.into(),
        crate::studio::delegation::encode(Default::default())?,
    );
    let mut activation = ThreadActivation::native_test("root", None);
    activation.agent.session_id = owner.id().clone();
    owner.install_explicit_activation(activation);
    owner.assemble(spec).await?;
    let tool = tool(&owner)?;
    let page = query(&tool, serde_json::json!({"target":"cold"})).await?;
    assert_eq!(
        (page.through_sequence, page.items.len(), page.has_more),
        (0, 0, false)
    );
    let path = store.registered_session_paths("cold")?.history_database();
    assert!(!path.exists(), "cold read cannot create the database");
    assert!(owner.thread("cold").is_none());
    let services = owner.0.state().agent_services.clone().unwrap();
    assert!(services.authorize("cold", "sibling").await.is_err());
    assert!(services.authorize("cold", "root").await.is_err());
    let cursor = Cursor {
        version: 2,
        target: "cold".into(),
        through: 0,
        ceiling: 0,
        order: Order::Descending,
        detail: Detail::Text,
        anchor: 1,
    };
    let cursor =
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(serde_json::to_vec(&cursor)?);
    for value in [
        serde_json::json!({"target":"sibling", "cursor":cursor}),
        serde_json::json!({"target":"cold", "cursor":cursor, "order":"ascending"}),
        serde_json::json!({"target":"cold", "cursor":cursor, "detail":"full"}),
        serde_json::json!({"target":"cold", "limit":0}),
        serde_json::json!({"target":"missing"}),
    ] {
        assert!(query(&tool, value).await.is_err());
    }
    // A writer initialization gate gives the original request a real lock wait.
    // Use a fresh cold member to enter initialization before its first query.
    let fresh = store.history("sibling").await?;
    let (entered, release) = fresh.arm_init_gate().await;
    let read_entered = fresh.arm_reader_before_init().await;
    let cancellation = CancellationToken::new();
    let init = fresh.prepare_write();
    let read = async {
        entered.await?;
        let cancel = async {
            read_entered.await.unwrap();
            cancellation.cancel();
        };
        let (result, ()) = tokio::join!(
            tool.execute(
                input(serde_json::json!({"target":"sibling"})),
                context("root", cancellation.clone())
            ),
            cancel
        );
        let error = result.expect_err("cancelled original request");
        assert!(matches!(
            error.source.downcast_ref::<pl_core::thread::ThreadError>(),
            Some(pl_core::thread::ThreadError::Cancelled)
        ));
        release
            .send(())
            .map_err(|_| anyhow::anyhow!("initializer disappeared"))?;
        Ok::<_, anyhow::Error>(())
    };
    let (initialized, cancelled) =
        tokio::time::timeout(Duration::from_secs(10), async { tokio::join!(init, read) }).await?;
    initialized?;
    cancelled?;
    let page = query(&tool, serde_json::json!({"target":"sibling"})).await?;
    assert!(page.items.is_empty());
    // Real storage damage remains an error at the tool boundary.
    tokio::fs::create_dir_all(path.parent().unwrap()).await?;
    tokio::fs::write(&path, b"invalid SQLite database").await?;
    let error = query(&tool, serde_json::json!({"target":"cold"}))
        .await
        .expect_err("real storage errors must survive the tool boundary");
    assert!(
        error.chain().any(|source| source.is::<sea_orm::DbErr>()),
        "{error:#}"
    );
    assert!(owner.thread("cold").is_none());
    assert!(owner.thread("sibling").is_none());
    assert!(owner.close_session().await.is_empty());
    fixture.shutdown().await?;
    store.close().await?;
    Ok(())
}
