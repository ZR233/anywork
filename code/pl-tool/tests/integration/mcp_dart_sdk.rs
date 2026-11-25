//! Opt-in compatibility check against an installed official Dart SDK.
use pl_tool::mcp::{
    McpConnectRequest, McpConnector,
    config::{
        EffectiveMcpServerConfig, McpExecutionContext, McpServerMutationPolicy,
        McpServerSourceKind, McpServerStatusKind,
    },
};
use std::{path::PathBuf, time::Duration};

#[tokio::test]
#[ignore = "requires MCP_DART_SDK and MCP_DART_SCRATCH"]
async fn official_dart_sdk_roots_and_analysis() -> anyhow::Result<()> {
    let sdk = PathBuf::from(std::env::var("MCP_DART_SDK")?);
    let scratch = PathBuf::from(std::env::var("MCP_DART_SCRATCH")?);
    std::fs::create_dir_all(scratch.join("home"))?;
    std::fs::create_dir_all(scratch.join("package/lib"))?;
    std::fs::write(
        scratch.join("package/pubspec.yaml"),
        "name: mcp_compatibility_probe\nenvironment:\n  sdk: ^3.14.0\n",
    )?;
    std::fs::write(
        scratch.join("package/lib/probe.dart"),
        "int answer() => 'not an integer';\n",
    )?;
    let config = EffectiveMcpServerConfig {
        id: "official-dart".into(),
        source_kind: McpServerSourceKind::User,
        source_label: "test".into(),
        source_detail: None,
        status_kind: McpServerStatusKind::Enabled,
        status_message: None,
        mutation_policy: McpServerMutationPolicy::UserEditable,
        bearer_token: None,
        tool_effect: None,
        execution_context: McpExecutionContext::Host,
        config: serde_json::from_value(serde_json::json!({
            "transport": "stdio",
            "startup_mode": "initialize",
            "command": sdk.join("bin/dart"),
            "args": ["mcp-server", "--dart-sdk", sdk, "--log-file", scratch.join("protocol.log")],
            "env": {"HOME": scratch.join("home")},
            "cwd": scratch,
            "startup_timeout_secs": 30,
            "tool_timeout_secs": 30
        }))?,
    };
    let connector = McpConnector::default();
    let session = tokio::time::timeout(
        Duration::from_secs(40),
        connector.connect(McpConnectRequest {
            server_id: "official-dart".into(),
            server: config,
        }),
    )
    .await??;
    let result: anyhow::Result<()> = async {
        let tools = session.list_tools().await?;
        println!("tools/list count={}", tools.len());
        let roots = tools.iter().find(|tool| tool.name == "roots").unwrap();
        println!("roots schema={}", serde_json::to_value(roots)?);
        let uri = reqwest::Url::from_directory_path(scratch.join("package"))
            .unwrap()
            .to_string();
        let roots_result = session
            .call_tool(
                "roots".into(),
                serde_json::json!({"command": "add", "uris": [uri]}),
            )
            .await?;
        println!("roots result={}", serde_json::to_value(&roots_result)?);
        anyhow::ensure!(roots_result.is_error != Some(true), "roots failed");
        let analysis = session
            .call_tool("analyze_files".into(), serde_json::json!({}))
            .await?;
        let analysis_json = serde_json::to_string(&analysis)?;
        println!("analysis={analysis_json}");
        anyhow::ensure!(analysis.is_error != Some(true), "analysis failed");
        anyhow::ensure!(
            analysis_json.contains("return_of_invalid_type"),
            "missing expected semantic diagnostic"
        );
        Ok(())
    }
    .await;
    let closed = session.close().await;
    println!("close={closed:?}");
    closed?;
    result
}
