#![cfg(target_os = "linux")]
//! Directory sharing and interruption must never strand a physical LSP owner.
use pl_lsp::host::ExecutorLspHost;
use pl_lsp::runtime::LspRuntimeRegistry;
use pl_remote_helper::Executor;
use std::{path::Path, sync::Arc, time::Duration};

async fn fixture(root: &Path, delay: u32) -> anyhow::Result<()> {
    let directory = root.join(".anywork/lsp");
    tokio::fs::create_dir_all(&directory).await?;
    let peer = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/support/lsp_fixture.py");
    tokio::fs::write(
        directory.join("fixture.toml"),
        format!(
            "schema_version = 1\nid = 'fixture'\ncommand = 'python3'\nargs = ['-u', {}, '{{workspaceRoot}}/requests.jsonl']\nlanguage_ids = ['fixture']\nextensions = ['fixture']\n[env]\nLSP_FIXTURE_DELAY = '{delay}'\n",
            serde_json::to_string(&peer)?,
        ),
    )
    .await?;
    Ok(())
}

fn host(executor: &Executor, root: &Path) -> anyhow::Result<Arc<ExecutorLspHost>> {
    Ok(Arc::new(ExecutorLspHost::new(
        executor.clone(),
        root.to_str().unwrap(),
    )?))
}

async fn requests(root: &Path) -> anyhow::Result<Vec<serde_json::Value>> {
    let text = tokio::fs::read_to_string(root.join("requests.jsonl")).await?;
    text.lines()
        .map(|line| serde_json::from_str(line).map_err(Into::into))
        .collect()
}

#[tokio::test]
async fn users_share_one_service_and_final_close_serializes_reacquisition() -> anyhow::Result<()> {
    let executor = Executor::local()?;
    let root = tempfile::tempdir()?;
    fixture(root.path(), 0).await?;
    let registry = LspRuntimeRegistry::new();
    let view = registry.execution_scope("local");
    let observed: anyhow::Result<()> = async {
        let primary_host = host(&executor, root.path())?;
        let primary_owner = Arc::downgrade(&primary_host);
        let first = view
            .acquire_workspace(root.path(), Some(primary_host), None)
            .await?;
        let clone = first.clone();
        let second = registry
            .execution_scope("local")
            .acquire_workspace(root.path(), Some(host(&executor, root.path())?), None)
            .await?;
        tokio::time::timeout(Duration::from_secs(20), first.wait_initialized()).await??;
        anyhow::ensure!(view.has_ready_servers(root.path()).await);
        first.close().await?;
        anyhow::ensure!(
            clone.is_closed(),
            "all clones of the same user must be invalidated"
        );
        clone.close().await?;
        anyhow::ensure!(
            view.has_ready_servers(root.path()).await,
            "another Thread still owns the service"
        );
        second
            .refresh_configuration(Some(host(&executor, root.path())?), None)
            .await?;
        tokio::time::timeout(Duration::from_secs(20), second.wait_initialized()).await??;
        anyhow::ensure!(
            requests(root.path())
                .await?
                .iter()
                .filter(|request| request["method"] == "fixture/start")
                .count()
                == 1
        );

        // close starts reclamation even before the returned future is polled.
        let closing = second.close();
        let third = view
            .acquire_workspace(root.path(), Some(host(&executor, root.path())?), None)
            .await?;
        closing.await?;
        anyhow::ensure!(
            primary_owner.upgrade().is_none(),
            "the old directory host must be released"
        );
        tokio::time::timeout(Duration::from_secs(20), third.wait_initialized()).await??;
        anyhow::ensure!(view.has_ready_servers(root.path()).await);
        clone.close().await?;
        anyhow::ensure!(
            view.has_ready_servers(root.path()).await,
            "old clones must not close the new generation"
        );
        third.close().await?;
        let log = requests(root.path()).await?;
        let starts: Vec<_> = log
            .iter()
            .filter(|request| request["method"] == "fixture/start")
            .collect();
        anyhow::ensure!(starts.len() == 2);
        for start in starts {
            let pid = start["pid"].as_u64().unwrap();
            anyhow::ensure!(
                !Path::new(&format!("/proc/{pid}")).exists(),
                "LSP process {pid} survived final close"
            );
        }
        anyhow::ensure!(!view.has_ready_servers(root.path()).await);
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    Ok(())
}

#[tokio::test]
async fn interrupted_initialization_drop_is_tracked_until_global_shutdown() -> anyhow::Result<()> {
    let executor = Executor::local()?;
    let root = tempfile::tempdir()?;
    fixture(root.path(), 60).await?;
    let registry = LspRuntimeRegistry::new();
    let view = registry.execution_scope("local");
    let primary_host = host(&executor, root.path())?;
    let owner = Arc::downgrade(&primary_host);
    let lease = view
        .acquire_workspace(root.path(), Some(primary_host), None)
        .await?;
    let started = tokio::time::timeout(Duration::from_secs(20), async {
        loop {
            if let Ok(log) = requests(root.path()).await
                && log.iter().any(|request| request["method"] == "initialize")
            {
                return log;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await;
    drop(lease);
    // There is deliberately no explicit lease close: failed/cancelled assembly
    // relies on Drop, while global shutdown must still wait for its owned task.
    let shutdown = tokio::time::timeout(Duration::from_secs(20), registry.shutdown()).await;
    let log = started?;
    shutdown??;
    anyhow::ensure!(
        owner.upgrade().is_none(),
        "initialization retained the file host"
    );
    for start in log
        .iter()
        .filter(|request| request["method"] == "fixture/start")
    {
        let pid = start["pid"].as_u64().unwrap();
        anyhow::ensure!(
            !Path::new(&format!("/proc/{pid}")).exists(),
            "initializing process {pid} survived shutdown"
        );
    }
    Ok(())
}
