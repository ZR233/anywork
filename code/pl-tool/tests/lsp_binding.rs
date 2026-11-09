#![cfg(target_os = "linux")]
//! Production host adapters over a real registry, supervised helper and LSP peer.
use pl_agent_tool::Tool;
use pl_core::{context::OpaquePayload, tool::opaque::CallContext};
use pl_lsp::{
    catalog::{LspServerCatalog, LspUserServerConfig},
    query::LspQueryOperation,
    runtime::LspRuntimeRegistry,
};
use pl_tool::{
    lsp::{LocalLspHostBackend, LspPathBinding, LspToolKind, ThreadLspTool},
    workspace::{AgentWorkspace, ToolWorkspace},
};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
};

#[path = "support/helper.rs"]
mod helper;

fn context() -> CallContext {
    CallContext {
        thread_id: "lsp-binding".into(),
        turn_id: "turn".into(),
        call_id: "call".into(),
        cancellation: Default::default(),
        extensions: Default::default(),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    }
}

fn query(path: &Path) -> OpaquePayload {
    OpaquePayload::new(
        "application/json",
        1,
        serde_json::json!({
            "languageId": "fixture", "operation": "hover",
            "filePath": path, "line": 2, "character": 3
        })
        .to_string(),
    )
    .unwrap()
}

#[tokio::test]
async fn hosted_lsp_tools_share_registry_and_preserve_path_authorization() -> anyhow::Result<()> {
    let root = tempfile::tempdir()?;
    let outside = tempfile::tempdir()?;
    tokio::fs::write(root.path().join("fixture.marker"), b"").await?;
    tokio::fs::write(root.path().join("source.fixture"), b"line one\nline two\n").await?;
    let outside_source = outside.path().join("outside.fixture");
    tokio::fs::write(&outside_source, b"private").await?;
    std::os::unix::fs::symlink(&outside_source, root.path().join("escape.fixture"))?;
    let log = root.path().join("requests.jsonl");
    let fixture = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/support/lsp_fixture.py");
    let config = LspUserServerConfig {
        command: "python3".into(),
        args: vec![
            "-u".into(),
            fixture.display().to_string(),
            log.display().to_string(),
        ],
        language_ids: vec!["fixture".into()],
        detection: vec!["fixture.marker".into()],
        extensions: vec!["fixture".into()],
        display_name: Some("Fixture".into()),
        operations: vec![LspQueryOperation::Hover],
    };
    let mut catalog = LspServerCatalog::empty();
    catalog.insert(config.to_catalog_server("fixture"))?;
    let registry = LspRuntimeRegistry::with_catalog(catalog);
    let host = Arc::new(LocalLspHostBackend::new(
        root.path(),
        helper::remote_helper_executable().to_owned(),
    )?);
    registry
        .reconcile_workspace_membership_with_host(root.path(), host)
        .await;
    registry.probe_lsp_server(root.path()).await;
    let paths = LspPathBinding::Local(ToolWorkspace::new(AgentWorkspace::local(root.path())));
    let capabilities = ThreadLspTool::new(
        registry.clone(),
        paths.clone(),
        LspToolKind::Capabilities,
        LspToolKind::Capabilities.declaration(),
    );
    let queries = ThreadLspTool::new(
        registry.clone(),
        paths,
        LspToolKind::Query,
        LspToolKind::Query.declaration(),
    );
    // Always close the registry before propagating assertions or tool failures.
    let observed: anyhow::Result<()> = async {
        let result = capabilities
            .execute(OpaquePayload::new("application/json", 1, "{}")?, context())
            .await?;
        let value: serde_json::Value = serde_json::from_str(result.payload().content())?;
        anyhow::ensure!(value["servers"][0]["ready"] == true, "{value}");
        anyhow::ensure!(value["servers"][0]["languageIds"][0] == "fixture");
        let result = queries
            .execute(query(Path::new("source.fixture")), context())
            .await?;
        let value: serde_json::Value = serde_json::from_str(result.payload().content())?;
        anyhow::ensure!(value["operation"] == "hover");
        anyhow::ensure!(value["serverId"] == "fixture");
        anyhow::ensure!(
            value["result"]
                .as_str()
                .is_some_and(|text| text.contains("fixture hover"))
        );
        let before = tokio::fs::read_to_string(&log).await?;
        for forbidden in [&outside_source, &root.path().join("escape.fixture")] {
            let error = queries
                .execute(query(forbidden), context())
                .await
                .expect_err("path grant must remain host-owned");
            anyhow::ensure!(!error.to_string().contains("fixture hover"));
            anyhow::ensure!(
                tokio::fs::read_to_string(&log).await? == before,
                "denied paths must not reach the server"
            );
        }
        Ok(())
    }
    .await;
    let shutdown = registry.shutdown().await;
    observed?;
    shutdown?;
    let messages: Vec<serde_json::Value> = tokio::fs::read_to_string(&log)
        .await?
        .lines()
        .map(serde_json::from_str)
        .collect::<Result<_, _>>()?;
    let hovers: Vec<_> = messages
        .iter()
        .filter(|entry| entry["method"] == "textDocument/hover")
        .collect();
    anyhow::ensure!(hovers.len() == 1);
    anyhow::ensure!(hovers[0]["params"]["position"]["line"] == 1);
    anyhow::ensure!(hovers[0]["params"]["position"]["character"] == 2);
    anyhow::ensure!(messages.iter().any(|entry| entry["method"] == "shutdown"));
    anyhow::ensure!(messages.iter().any(|entry| entry["method"] == "exit"));
    Ok(())
}
