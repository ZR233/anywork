use anyhow::{Context, Result, ensure};
use pl_acp::session::schema;
use reqwest::{Client, StatusCode, header};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;

use crate::acp_transport_fixture::AcpTransportFixture as Fixture;

use super::HostMcp;

#[derive(Clone)]
struct HttpMcp {
    client: Client,
    url: String,
    bearer: String,
    session_id: Option<String>,
    next_id: u64,
}

impl HttpMcp {
    fn from_definition(definition: schema::McpServer) -> Result<Self> {
        let schema::McpServer::Http(server) = definition else {
            anyhow::bail!("Host MCP did not provide an HTTP server definition");
        };
        let bearer = server
            .headers
            .iter()
            .find(|item| item.name.eq_ignore_ascii_case("authorization"))
            .and_then(|item| item.value.strip_prefix("Bearer "))
            .context("Host MCP bearer header is missing")?
            .to_owned();
        Ok(Self {
            client: Client::new(),
            url: server.url,
            bearer,
            session_id: None,
            next_id: 1,
        })
    }

    async fn post(&self, body: Value, bearer: Option<&str>) -> Result<reqwest::Response> {
        let mut request = self
            .client
            .post(&self.url)
            .header(header::CONTENT_TYPE, "application/json")
            .header(header::ACCEPT, "application/json, text/event-stream");
        if let Some(bearer) = bearer {
            request = request.bearer_auth(bearer);
        }
        if let Some(session_id) = &self.session_id {
            request = request.header("mcp-session-id", session_id);
        }
        Ok(request.json(&body).send().await?)
    }

    async fn rpc_result(
        response: reqwest::Response,
        expected_id: u64,
        operation: &str,
    ) -> Result<Value> {
        ensure!(
            response.status().is_success(),
            "MCP {operation} failed with HTTP status {}",
            response.status()
        );
        let content_type = response
            .headers()
            .get(header::CONTENT_TYPE)
            .and_then(|value| value.to_str().ok())
            .unwrap_or("<missing>")
            .to_owned();
        let body = response.bytes().await?;
        if content_type.starts_with("application/json") {
            return serde_json::from_slice(&body)
                .with_context(|| format!("decode MCP {operation} JSON response"));
        }
        ensure!(
            content_type.starts_with("text/event-stream"),
            "MCP {operation} returned unsupported content type {content_type}"
        );
        let body = std::str::from_utf8(&body)
            .with_context(|| format!("decode MCP {operation} event stream as UTF-8"))?;
        for line in body.lines() {
            let Some(data) = line.strip_prefix("data:") else {
                continue;
            };
            let Ok(message) = serde_json::from_str::<Value>(data.trim()) else {
                continue;
            };
            if message["id"] == expected_id {
                return Ok(message);
            }
        }
        anyhow::bail!("MCP {operation} event stream omitted response id {expected_id}")
    }

    async fn initialize(&mut self) -> Result<()> {
        let id = self.next_id;
        let response = self
            .post(
                json!({
                    "jsonrpc": "2.0",
                    "id": id,
                    "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-03-26",
                        "capabilities": {},
                        "clientInfo": {"name": "host-mcp-integration-test", "version": "1"}
                    }
                }),
                Some(&self.bearer),
            )
            .await?;
        self.session_id = response
            .headers()
            .get("mcp-session-id")
            .map(|value| value.to_str().map(str::to_owned))
            .transpose()?;
        let result = Self::rpc_result(response, id, "initialize").await?;
        ensure!(
            result["result"]["protocolVersion"].is_string(),
            "MCP initialize response is missing protocolVersion"
        );
        self.next_id += 1;
        let response = self
            .post(
                json!({"jsonrpc": "2.0", "method": "notifications/initialized"}),
                Some(&self.bearer),
            )
            .await?;
        ensure!(
            response.status().is_success(),
            "MCP initialized notification failed with HTTP status {}",
            response.status()
        );
        Ok(())
    }

    async fn request(&mut self, method: &str, params: Value) -> Result<Value> {
        let id = self.next_id;
        self.next_id += 1;
        let response = self
            .post(
                json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}),
                Some(&self.bearer),
            )
            .await?;
        let result = Self::rpc_result(response, id, method).await?;
        ensure!(result["id"] == id, "MCP response id did not match request");
        Ok(result)
    }

    async fn cancel_request(&self, request_id: u64) -> Result<()> {
        let response = self
            .post(
                json!({
                    "jsonrpc": "2.0",
                    "method": "notifications/cancelled",
                    "params": {"requestId": request_id}
                }),
                Some(&self.bearer),
            )
            .await?;
        ensure!(
            response.status().is_success(),
            "MCP cancellation notification failed with HTTP status {}",
            response.status()
        );
        Ok(())
    }
}

fn save_acp_child_profile(fixture: &Fixture) -> Result<()> {
    fixture.runtime.save_user_agent_profile(
        "save-http-acp-child".into(),
        fixture.runtime.read_settings()?.config.revision,
        "acp-child",
        &crate::config::UserAgentProfile {
            enabled: true,
            display_name: "ACP child".into(),
            description: "Ordinary ACP task".into(),
            when_to_use: "External coding task".into(),
            binding: pl_protocol::AgentBinding::Acp(pl_protocol::AcpAgentConfig {
                account_id: "business-peer".into(),
            }),
            workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
        },
    )?;
    Ok(())
}

#[tokio::test]
async fn ipc_calls_original_host_without_an_http_mcp_listener() -> Result<()> {
    use pl_studio_mcp::{HostInvocation, HostOperation, HostTools, ipc::IpcClient};

    let fixture = Fixture::new("mcp-http").await?;
    let mut target = None;
    let mut service = None;
    let mut client = None;
    let result = async {
        let mut open = fixture.open().await?;
        target = Some(open.target.clone());
        Fixture::ready(&mut open).await?;
        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(
                open.target.session_id.clone(),
            )?)
            .context("published owner")?;
        let resources = owner
            .resident_acp(&open.target.thread_id)?
            .context("ACP resources")?;
        let identity = fixture
            .runtime
            .agent_facility
            .product_events
            .agent_execution_identity(&open.target.thread_id)
            .context("identity")?
            .0;
        let profiles = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
        let host = owner.acp_agent_host(
            &identity,
            &resources,
            &profiles,
            fixture.runtime.config_runtime.read()?.config.delegation,
        )?;
        // This consumes the domain IPC endpoint directly. Production executable
        // startup is covered by pl-studio-mcp and the real agy journey.
        let (transport, definition) = HostMcp::start(
            host,
            identity.agent_id.clone(),
            CancellationToken::new(),
            true,
            Some(std::path::Path::new("/unused/pl-studio-mcp")),
        )
        .await?;
        ensure!(
            transport.sessions.is_none() && transport.join.is_none(),
            "stdio selected an HTTP MCP listener"
        );
        service = Some(transport);
        let schema::McpServer::Stdio(definition) = definition else {
            anyhow::bail!("expected a standard stdio definition");
        };
        let env = |name: &str| {
            definition
                .env
                .iter()
                .find(|item| item.name == name)
                .map(|item| item.value.clone())
                .context("missing IPC environment")
        };
        client = Some(
            IpcClient::connect(
                env(pl_studio_mcp::IPC_ENDPOINT_ENV)?,
                env(pl_studio_mcp::IPC_CAPABILITY_ENV)?,
            )
            .await
            .context("connect IPC client")?,
        );
        let ipc = client.as_ref().unwrap();
        let catalog = ipc.catalog().await.context("read IPC catalog")?;
        ensure!(
            catalog
                .iter()
                .any(|tool| tool.operation == HostOperation::ListAgentProfiles),
            "root directory was not delivered"
        );
        let listed = ipc
            .invoke(
                HostInvocation {
                    operation: HostOperation::ListAgents,
                    arguments: Default::default(),
                },
                CancellationToken::new(),
            )
            .await
            .context("invoke original member list")?;
        ensure!(
            !listed.is_error && listed.value.to_string().contains(&open.target.agent_id),
            "IPC did not read the original member directory"
        );
        let profiles = ipc
            .invoke(
                HostInvocation {
                    operation: HostOperation::ListAgentProfiles,
                    arguments: Default::default(),
                },
                CancellationToken::new(),
            )
            .await
            .context("invoke original profile list")?;
        ensure!(
            !profiles.is_error && profiles.value.is_object(),
            "profile domain query failed"
        );
        ensure!(
            service
                .as_ref()
                .unwrap()
                .observed_counter()
                .load(std::sync::atomic::Ordering::Acquire)
                == 2,
            "domain call count differs"
        );
        service.as_mut().unwrap().close().await?;
        ensure!(
            ipc.catalog().await.is_err(),
            "closed instance still accepts IPC"
        );
        Ok::<_, anyhow::Error>(())
    }
    .await;
    let mut cleanup = Ok(());
    if let Some(client) = client {
        cleanup = client
            .close()
            .await
            .context("join IPC client after server close");
    }
    if let Some(mut service) = service
        && let Err(error) = service.close().await
    {
        cleanup = cleanup.and(Err(error));
    }
    if let Some(target) = target {
        match fixture.runtime.close_acp_session(target).await {
            Ok(close) if close.local_complete => {}
            Ok(close) => cleanup = cleanup.and(Err(anyhow::anyhow!("ACP cleanup: {close:?}"))),
            Err(error) => cleanup = cleanup.and(Err(error)),
        }
    }
    let shutdown = fixture.runtime.shutdown_runtime().await;
    result?;
    cleanup?;
    shutdown?;
    Ok(())
}

#[tokio::test]
async fn http_auth_tools_and_instance_shutdown_are_isolated() -> Result<()> {
    let fixture = Fixture::new("replay").await?;
    let mut target = None;
    let mut services = Vec::new();
    let result = async {
        let mut open = fixture.open().await?;
        Fixture::ready(&mut open).await?;
        target = Some(open.target.clone());
        let target = target.as_ref().context("published ACP target")?;

        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(target.session_id.clone())?)
            .context("published ACP session owner")?;
        let resources = owner
            .resident_acp(&target.thread_id)?
            .context("published ACP resources")?;
        let identity = fixture
            .runtime
            .agent_facility
            .product_events
            .agent_execution_identity(&target.thread_id)
            .context("published ACP execution identity")?
            .0;
        let profile_snapshot = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
        let selection = fixture.runtime.config_runtime.read()?.config.delegation;
        let host = owner.acp_agent_host(&identity, &resources, &profile_snapshot, selection)?;

        let (first_service, first_definition) = HostMcp::start(
            host.clone(),
            identity.agent_id.clone(),
            CancellationToken::new(),
            true,
            None,
        )
        .await?;
        services.push(first_service);
        let (second_service, second_definition) = HostMcp::start(
            host,
            identity.agent_id.clone(),
            CancellationToken::new(),
            false,
            None,
        )
        .await?;
        services.push(second_service);
        let mut first = HttpMcp::from_definition(first_definition)?;
        let mut second = HttpMcp::from_definition(second_definition)?;

        for (index, bearer) in [None, Some("incorrect-test-token")].into_iter().enumerate() {
            let mut request = first
                .client
                .post(&first.url)
                .header(header::CONTENT_TYPE, "application/json");
            if let Some(bearer) = bearer {
                request = request.bearer_auth(bearer);
            }
            let response = request
                .json(&json!({"jsonrpc":"2.0","id":index + 1,"method":"initialize","params":{}}))
                .send()
                .await?;
            ensure!(
                response.status() == StatusCode::UNAUTHORIZED,
                "missing or incorrect bearer was not rejected"
            );
        }

        first.initialize().await?;
        let listed = first.request("tools/list", json!({})).await?;
        let tools = listed["result"]["tools"]
            .as_array()
            .context("tools/list result")?;
        ensure!(
            tools
                .iter()
                .any(|tool| tool["name"] == "anywork_list_agent_profiles"),
            "root MCP instance omitted the profile query"
        );
        let profiles = first
            .request(
                "tools/call",
                json!({
                    "name": "anywork_list_agent_profiles",
                    "arguments": {}
                }),
            )
            .await?;
        ensure!(
            profiles["result"]["isError"] != true,
            "the actual profile domain call failed"
        );
        ensure!(
            profiles["result"]["structuredContent"].is_object()
                || profiles["result"]["content"].is_array(),
            "profile query did not return a result"
        );

        second.initialize().await?;
        let child_tools = second.request("tools/list", json!({})).await?;
        let child_tools = child_tools["result"]["tools"]
            .as_array()
            .context("child tools/list result")?;
        ensure!(
            !child_tools
                .iter()
                .any(|tool| tool["name"] == "anywork_list_agent_profiles"),
            "child MCP instance exposed a root-only profile query"
        );

        services[0].close().await?;
        let closed_response = first
            .post(
                json!({"jsonrpc":"2.0","id":100,"method":"tools/list","params":{}}),
                Some(&first.bearer),
            )
            .await;
        ensure!(
            closed_response.is_err()
                || !closed_response
                    .as_ref()
                    .is_ok_and(|response| response.status().is_success()),
            "closed MCP endpoint still accepted its former session"
        );
        let surviving = second.request("tools/list", json!({})).await?;
        ensure!(
            surviving["result"]["tools"].is_array(),
            "closing one endpoint affected another instance"
        );

        services[1].close().await?;
        let closed_response = second
            .post(
                json!({"jsonrpc":"2.0","id":101,"method":"tools/list","params":{}}),
                Some(&second.bearer),
            )
            .await;
        ensure!(
            closed_response.is_err()
                || !closed_response
                    .as_ref()
                    .is_ok_and(|response| response.status().is_success()),
            "second closed endpoint remained usable"
        );
        Ok::<_, anyhow::Error>(())
    }
    .await;

    let mut cleanup = Ok(());
    for service in &mut services {
        if let Err(error) = service.close().await
            && cleanup.is_ok()
        {
            cleanup = Err(error);
        }
    }
    if let Some(target) = target {
        match fixture.runtime.close_acp_session(target).await {
            Ok(close) if close.local_complete => {}
            Ok(close) => {
                if cleanup.is_ok() {
                    cleanup = Err(anyhow::anyhow!(
                        "ACP fixture did not close completely: {close:?}"
                    ));
                }
            }
            Err(error) if cleanup.is_ok() => cleanup = Err(error),
            Err(_) => {}
        }
    }
    if let Err(error) = fixture.runtime.shutdown_runtime().await
        && cleanup.is_ok()
    {
        cleanup = Err(error);
    }
    result?;
    cleanup?;
    Ok(())
}

#[tokio::test]
async fn public_acp_open_injects_advertised_http_mcp_and_joins_it_on_close() -> Result<()> {
    let fixture = Fixture::new("mcp-http").await?;
    let mut target = None;
    let result = async {
        let mut open = fixture.open().await?;
        target = Some(open.target.clone());
        Fixture::ready(&mut open).await?;

        let received = std::fs::read_to_string(fixture.home.path().join("mcp-http-received"))?;
        ensure!(
            received == "true",
            "ACP peer did not receive the expected HTTP MCP definition and Authorization header"
        );
        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(
                open.target.session_id.clone(),
            )?)
            .context("published ACP owner")?;
        let resources = owner
            .resident_acp(&open.target.thread_id)?
            .context("published ACP resources")?;
        let status = resources.host_mcp_status().await;
        ensure!(
            status["injected"] == true,
            "Host MCP was not installed into the published ACP resources"
        );
        ensure!(
            status["observedToolCalls"] == 0,
            "capability injection must not be reported as a model tool call"
        );

        let close = fixture
            .runtime
            .close_acp_session(open.target.clone())
            .await?;
        ensure!(
            close.local_complete,
            "closing ACP did not join its Host MCP service: {close:?}"
        );
        target = None;
        Ok::<_, anyhow::Error>(())
    }
    .await;

    let mut cleanup = Ok(());
    if let Some(target) = target {
        match fixture.runtime.close_acp_session(target).await {
            Ok(close) if close.local_complete => {}
            Ok(close) => {
                cleanup = Err(anyhow::anyhow!(
                    "ACP fixture did not close completely: {close:?}"
                ));
            }
            Err(error) => cleanup = Err(error),
        }
    }
    if let Err(error) = fixture.runtime.shutdown_runtime().await
        && cleanup.is_ok()
    {
        cleanup = Err(error);
    }
    match (result, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
        (Err(error), Err(cleanup)) => Err(error.context(format!(
            "ACP capability fixture cleanup also failed: {cleanup:#}"
        ))),
    }
}

#[tokio::test]
async fn http_spawn_wait_cancellation_and_service_close_preserve_child_run() -> Result<()> {
    use std::time::Duration;

    let fixture = Fixture::new("prompt-hold").await?;
    let mut root_target = None;
    let mut host_service = None;
    let mut waiting_task = None;
    let mut long_wait_task = None;
    let result = async {
        save_acp_child_profile(&fixture)?;
        let mut open = fixture.open().await?;
        Fixture::ready(&mut open).await?;
        root_target = Some(open.target.clone());
        let owner = fixture
            .runtime
            .sessions
            .get(&pl_protocol::SessionId::new(
                open.target.session_id.clone(),
            )?)
            .context("published root ACP owner")?;
        let root_identity = owner
            .acp_identity(&open.target.thread_id)
            .context("published root ACP identity")?;
        let root_resources = owner
            .resident_acp(&open.target.thread_id)?
            .context("published root ACP resources")?;
        let profiles = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
        let host = owner.acp_agent_host(
            &root_identity,
            &root_resources,
            &profiles,
            fixture.runtime.config_runtime.read()?.config.delegation,
        )?;
        let (service, definition) = HostMcp::start(
            host,
            root_identity.agent_id.clone(),
            CancellationToken::new(),
            true,
            None,
        )
        .await?;
        host_service = Some(service);
        let mut client = HttpMcp::from_definition(definition)?;
        client.initialize().await?;

        let spawned = client
            .request(
                "tools/call",
                json!({
                    "name": "anywork_spawn_agent",
                    "arguments": {
                        "profileId": "acp-child",
                        "taskSummary": "Complete the held ACP task",
                        "message": "Run the held task"
                    }
                }),
            )
            .await?;
        ensure!(
            spawned["result"]["isError"] != true,
            "the real ACP child spawn failed"
        );
        let child_id = spawned["result"]["structuredContent"]["receipt"]["agentId"]
            .as_str()
            .context("spawn result agent id")?
            .to_owned();
        ensure!(!child_id.is_empty(), "spawn returned an empty agent id");

        let prompting = fixture.home.path().join("prompting");
        tokio::time::timeout(Duration::from_secs(20), async {
            while !prompting.exists() {
                tokio::task::yield_now().await;
            }
        })
        .await
        .context("fixture ACP child did not reach the held prompt")?;

        let child_agent = pl_protocol::AgentId::new(child_id.clone())?;
        let child_identity = fixture
            .runtime
            .agent_facility
            .product_events
            .member_identity(&root_identity.session_id, &child_agent)
            .context("published ACP child identity")?;
        let child_resources = owner
            .resident_acp(child_identity.thread_id.as_str())?
            .context("published ACP child resources")?;
        let active_run = child_resources
            .session()?
            .snapshot()
            .await?
            .active_run
            .context("held child active run")?;

        let service = host_service.as_ref().context("running Host MCP service")?;
        let observed_calls = service.observed_counter();
        let wait_target = child_id.clone();
        let mut waiting_client = client.clone();
        let wait_request_id = waiting_client.next_id;
        client.next_id += 1;
        waiting_task = Some(tokio::spawn(async move {
            waiting_client
                .request(
                    "tools/call",
                    json!({
                        "name": "anywork_wait_agent",
                        "arguments": {
                            "target": wait_target,
                            "timeoutMs": 300000
                        }
                    }),
                )
                .await
        }));
        tokio::time::timeout(Duration::from_secs(10), async {
            while observed_calls.load(std::sync::atomic::Ordering::Acquire) < 2 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .context("Host MCP did not observe the long wait call")?;

        client.cancel_request(wait_request_id).await?;
        let mut waiting = waiting_task.take().context("waiting HTTP task")?;
        let cancelled_wait = tokio::time::timeout(Duration::from_secs(10), &mut waiting)
            .await
            .context("MCP-cancelled wait request did not end")?;
        ensure!(
            cancelled_wait.is_ok(),
            "cancelled HTTP wait task failed to join"
        );
        let _cancelled_wait_result = cancelled_wait.unwrap();
        waiting_task = None;
        let still_active = child_resources.session()?.snapshot().await?.active_run;
        ensure!(
            still_active == Some(active_run),
            "cancelling report observation changed the ACP child active run"
        );
        let peer_calls = std::fs::read_to_string(fixture.home.path().join("calls"))?;
        ensure!(
            !peer_calls.lines().any(|line| line == "session/cancel"),
            "cancelling report observation sent ACP session/cancel"
        );

        std::fs::write(fixture.home.path().join("release"), "")?;
        let report = client
            .request(
                "tools/call",
                json!({
                    "name": "anywork_wait_agent",
                    "arguments": {
                        "target": child_id,
                        "timeoutMs": 300000
                    }
                }),
            )
            .await?;
        ensure!(
            report["result"]["isError"] != true,
            "wait for completed ACP child report failed: {}",
            report["result"]["structuredContent"]["error"]
        );
        let report = &report["result"]["structuredContent"];
        ensure!(
            report["reports"]
                .as_array()
                .is_some_and(|reports| !reports.is_empty()),
            "wait did not return the real ACP completion report"
        );
        ensure!(
            report["reports"][0]["summary"] == "actual answer",
            "wait returned an unexpected report summary"
        );
        let cursor = report["cursor"]
            .as_str()
            .context("completed report cursor")?
            .to_owned();

        let long_wait_target = child_id.clone();
        let long_wait_cursor = cursor;
        let mut long_wait_client = client.clone();
        let long_wait_id = long_wait_client.next_id;
        client.next_id += 1;
        long_wait_task = Some(tokio::spawn(async move {
            long_wait_client
                .request(
                    "tools/call",
                    json!({
                        "name": "anywork_wait_agent",
                        "arguments": {
                            "target": long_wait_target,
                            "after": long_wait_cursor,
                            "timeoutMs": 300000
                        }
                    }),
                )
                .await
        }));
        let service = host_service.as_ref().context("running Host MCP service")?;
        let observed_calls = service.observed_counter();
        tokio::time::timeout(Duration::from_secs(10), async {
            while observed_calls.load(std::sync::atomic::Ordering::Acquire) < 4 {
                tokio::task::yield_now().await;
            }
        })
        .await
        .context("Host MCP did not observe the cursor-based long wait")?;
        let mut probe = client.clone();
        probe.request("tools/list", json!({})).await?;
        ensure!(
            !long_wait_task
                .as_ref()
                .is_some_and(tokio::task::JoinHandle::is_finished),
            "cursor-based wait returned before its HTTP service was closed"
        );

        host_service
            .as_mut()
            .context("running Host MCP service")?
            .close()
            .await?;
        let mut long_wait = long_wait_task.take().context("cursor wait HTTP task")?;
        let closed_wait = tokio::time::timeout(Duration::from_secs(10), &mut long_wait)
            .await
            .context("closing Host MCP did not end the cursor-based wait");
        let closed_wait = match closed_wait {
            Ok(result) => result,
            Err(error) => {
                long_wait.abort();
                let _ = long_wait.await;
                return Err(error);
            }
        };
        ensure!(
            closed_wait.is_ok(),
            "cursor-based HTTP wait task failed to join"
        );
        let _ = (long_wait_id, closed_wait.unwrap());
        Ok::<_, anyhow::Error>(())
    }
    .await;

    let _ = std::fs::write(fixture.home.path().join("release"), "");
    let mut cleanup = Ok(());
    if let Some(service) = host_service.as_mut()
        && let Err(error) = service.close().await
    {
        cleanup = Err(error);
    }
    if let Some(mut task) = waiting_task.take() {
        match tokio::time::timeout(Duration::from_secs(10), &mut task).await {
            Ok(Ok(_)) => {}
            Ok(Err(error)) => {
                if cleanup.is_ok() {
                    cleanup = Err(anyhow::anyhow!("waiting HTTP task failed to join: {error}"));
                }
            }
            Err(_) => {
                task.abort();
                let _ = task.await;
                if cleanup.is_ok() {
                    cleanup = Err(anyhow::anyhow!(
                        "waiting HTTP task did not stop during cleanup"
                    ));
                }
            }
        }
    }
    if let Some(mut task) = long_wait_task.take() {
        match tokio::time::timeout(Duration::from_secs(10), &mut task).await {
            Ok(Ok(_)) => {}
            Ok(Err(error)) => {
                if cleanup.is_ok() {
                    cleanup = Err(anyhow::anyhow!(
                        "cursor wait HTTP task failed to join: {error}"
                    ));
                }
            }
            Err(_) => {
                task.abort();
                let _ = task.await;
                if cleanup.is_ok() {
                    cleanup = Err(anyhow::anyhow!(
                        "cursor wait HTTP task did not stop during cleanup"
                    ));
                }
            }
        }
    }
    if let Some(target) = root_target {
        match fixture.runtime.close_acp_session(target).await {
            Ok(close) if close.local_complete => {}
            Ok(close) if cleanup.is_ok() => {
                cleanup = Err(anyhow::anyhow!(
                    "root ACP fixture did not close completely: {close:?}"
                ));
            }
            Err(error) if cleanup.is_ok() => cleanup = Err(error),
            _ => {}
        }
    }
    if let Err(error) = fixture.runtime.shutdown_runtime().await
        && cleanup.is_ok()
    {
        cleanup = Err(error);
    }
    match (result, cleanup) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
        (Err(error), Err(cleanup)) => {
            Err(error.context(format!("ACP spawn/wait cleanup also failed: {cleanup:#}")))
        }
    }
}
