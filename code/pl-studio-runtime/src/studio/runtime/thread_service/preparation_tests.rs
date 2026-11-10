//! Real create-to-first-input observations. Provider and MCP sockets are loopback-only.
use super::*;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tracing::{Subscriber, field::Visit, span};

#[path = "preparation_mcp_tests.rs"]
mod mcp;

#[derive(Clone, Default)]
struct PreparationLog(Arc<Mutex<Vec<String>>>);

#[derive(Default)]
struct Fields(String);
impl Visit for Fields {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        use std::fmt::Write;
        write!(&mut self.0, " {}={value:?}", field.name()).unwrap();
    }
}
impl Subscriber for PreparationLog {
    fn enabled(&self, metadata: &tracing::Metadata<'_>) -> bool {
        metadata.target() == "thread_preparation"
    }
    fn new_span(&self, _: &span::Attributes<'_>) -> span::Id {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
        span::Id::from_u64(NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed))
    }
    fn record(&self, _: &span::Id, _: &span::Record<'_>) {}
    fn record_follows_from(&self, _: &span::Id, _: &span::Id) {}
    fn event(&self, event: &tracing::Event<'_>) {
        let mut fields = Fields::default();
        event.record(&mut fields);
        eprintln!("PREPARATION{}", fields.0);
        self.0.lock().unwrap().push(fields.0);
    }
    fn enter(&self, _: &span::Id) {}
    fn exit(&self, _: &span::Id) {}
}

#[tokio::test]
async fn local_first_input_preparation_without_mcp() -> Result<()> {
    tokio::time::timeout(Duration::from_secs(20), async {
        let capture = PreparationLog::default();
        let dispatch = tracing::Dispatch::new(capture.clone());
        let _capture = tracing::dispatcher::set_default(&dispatch);
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _provider = configure(&home)?;
        let store = ConfigStore::new(ConfigPaths::from_config_dir(&home));
        let mut config = store.load()?;
        // Skills discovery normally reads the standard user home; never consume it here.
        config.skills.enabled = false;
        store.save(&config)?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir(&workspace).await?;
        let project = runtime.open_project(&workspace).await?;
        let started = Instant::now();
        let result = runtime
            .create_thread_command(
                project.id,
                request(pl_protocol::ThreadWorkspaceMode::Local),
                None,
            )
            .await;
        let elapsed = started.elapsed();
        let shutdown_started = Instant::now();
        let shutdown = runtime.shutdown_runtime().await;
        shutdown?;
        let response = result?;
        assert_eq!(response.submission.thread_id, response.thread.id);
        assert_eq!(response.submission.input_id, "standalone-start");
        assert!(response.submission.cursor > 0);
        assert!(
            capture
                .0
                .lock()
                .unwrap()
                .iter()
                .any(|line| line.contains("first_input") && line.contains("completed"))
        );
        eprintln!(
            "PREPARATION_RESULT slow_mcp=false create_ms={} shutdown_ms={}",
            elapsed.as_millis(),
            shutdown_started.elapsed().as_millis()
        );
        Ok::<_, anyhow::Error>(())
    })
    .await?
}
