use futures::future::BoxFuture;
use pl_lsp::{
    host::{
        LspHostBackend, LspHostError, LspHostFileStat, LspHostProcess, LspHostSpawnRequest,
        LspPathStyle,
    },
    runtime::{LspLifecyclePhase, LspRuntimeRegistry},
};
use std::{
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

const ROOT: &str = "/remote/project";
const DIRECTORY: &str = "/remote/project/.anywork/lsp";
const DOCUMENT: &str = "/remote/project/.anywork/lsp/rust.toml";
const MANIFEST: &str = "/remote/project/Cargo.toml";
const CONFIG: &[u8] = b"schema_version = 1\nid = 'rust'\ncommand = 'fixture'\nlanguage_ids = ['rust']\ndetection = ['Cargo.toml']\n";

#[derive(Debug, Default)]
struct PosixFiles {
    configured: AtomicBool,
    observed: Mutex<Vec<String>>,
}

impl PosixFiles {
    fn record(&self, operation: &str, path: &Path) -> String {
        let path = path.to_string_lossy().into_owned();
        self.observed
            .lock()
            .unwrap()
            .push(format!("{operation}:{path}"));
        path
    }
}

impl LspHostBackend for PosixFiles {
    fn path_style(&self) -> LspPathStyle {
        LspPathStyle::Posix
    }

    fn identity(&self) -> String {
        "posix-configuration-fixture".into()
    }

    fn join_path(&self, base: &Path, path: &str) -> Result<PathBuf, LspHostError> {
        Ok(format!(
            "{}/{path}",
            base.display().to_string().trim_end_matches('/')
        )
        .into())
    }

    fn read_file<'a>(
        &'a self,
        path: &'a Path,
        _: u64,
    ) -> BoxFuture<'a, Result<Vec<u8>, LspHostError>> {
        Box::pin(async move {
            let path = self.record("read", path);
            if path == DOCUMENT {
                Ok(CONFIG.to_vec())
            } else {
                Err(LspHostError::new(format!(
                    "unexpected document path: {path}"
                )))
            }
        })
    }

    fn stat<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<Option<LspHostFileStat>, LspHostError>> {
        Box::pin(async move {
            let path = self.record("stat", path);
            Ok(match path.as_str() {
                DIRECTORY if self.configured.load(Ordering::SeqCst) => Some(LspHostFileStat {
                    is_file: false,
                    byte_size: 0,
                }),
                MANIFEST => Some(LspHostFileStat {
                    is_file: true,
                    byte_size: 1,
                }),
                _ => None,
            })
        })
    }

    fn list_directory<'a>(
        &'a self,
        path: &'a Path,
        _: usize,
    ) -> BoxFuture<'a, Result<Vec<String>, LspHostError>> {
        Box::pin(async move {
            let path = self.record("list", path);
            if path == DIRECTORY {
                Ok(vec!["rust.toml".into()])
            } else {
                Err(LspHostError::new(format!(
                    "unexpected directory path: {path}"
                )))
            }
        })
    }

    fn spawn<'a>(
        &'a self,
        _: LspHostSpawnRequest,
    ) -> BoxFuture<'a, Result<LspHostProcess, LspHostError>> {
        Box::pin(async { Err(LspHostError::new("fixture server launch reached")) })
    }
}

#[tokio::test]
async fn running_workspace_rescans_configuration_using_target_paths() {
    tokio::time::timeout(Duration::from_secs(10), async {
        let host = Arc::new(PosixFiles::default());
        let registry = LspRuntimeRegistry::new();
        let root = Path::new(ROOT);
        let lease = registry
            .acquire_workspace(root, Some(host.clone()), None)
            .await
            .unwrap();
        lease.wait_initialized().await.unwrap();
        assert!(registry.snapshots_for_workspace(root).await.is_empty());

        host.configured.store(true, Ordering::SeqCst);
        registry.notify_file_changed(Path::new(DOCUMENT)).await;
        lease.wait_initialized().await.unwrap();
        let snapshots = registry.snapshots_for_workspace(root).await;
        assert_eq!(snapshots.len(), 1, "{snapshots:?}");
        assert_eq!(snapshots[0].id, "rust");
        assert_eq!(snapshots[0].configuration_path.as_deref(), Some(DOCUMENT));
        assert_eq!(snapshots[0].phase, LspLifecyclePhase::Failed);
        assert!(
            snapshots[0]
                .availability_message
                .as_deref()
                .unwrap()
                .contains("fixture server launch reached")
        );
        let observed = host.observed.lock().unwrap().clone();
        for expected in [
            format!("stat:{DIRECTORY}"),
            format!("list:{DIRECTORY}"),
            format!("read:{DOCUMENT}"),
            format!("stat:{MANIFEST}"),
        ] {
            assert!(
                observed.contains(&expected),
                "missing {expected}: {observed:?}"
            );
        }
        host.configured.store(false, Ordering::SeqCst);
        registry.notify_file_deleted(Path::new(DOCUMENT)).await;
        lease.wait_initialized().await.unwrap();
        assert!(registry.snapshots_for_workspace(root).await.is_empty());
        lease.close().await.unwrap();
        registry.shutdown().await.unwrap();
    })
    .await
    .expect("configuration scan did not finish");
}
