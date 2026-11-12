//! Instance-owned ACP Host MCP transport. Domain authority remains in AgentHost.
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{Context, Result};
use axum::{Router, body::Body, middleware::Next, response::Response};
use http::{Request, StatusCode, header::AUTHORIZATION};
use pl_acp::session::{OpenSetup, PrepareOpen, schema};
use pl_agent_tool::{InputFormat, ToolDefinition};
use pl_studio_mcp::{
    HostCatalog, HostError, HostInvocation, HostMcpService, HostOperation, HostResult, HostTool,
    HostTools, ipc::IpcServer,
};
use pl_tool::collaboration::{
    control::{AgentCallContext, ControlError},
    thread::{AgentCloseOptions, AgentControlHost, AgentControlKind, AgentMessage, AgentSpawn},
};
use rmcp::transport::streamable_http_server::{
    SessionManager, StreamableHttpServerConfig, StreamableHttpService,
    session::local::LocalSessionManager,
};
use serde::Deserialize;
use serde_json::Value;
use tokio::task::JoinHandle;
use tokio_util::{
    sync::CancellationToken,
    task::{TaskTracker, task_tracker::TaskTrackerToken},
};

use super::acp_business::AcpResources;
use crate::{
    config::ConfigRuntime,
    thread_assembler::{
        AgentHost, SessionRuntime,
        agent_wait::{WaitAgentRequest, WaitAgentResult},
    },
};

#[cfg(all(test, target_os = "linux"))]
#[path = "acp_host_mcp/tests.rs"]
mod tests;

#[cfg(test)]
mod future_sizes {
    use super::*;
    use rmcp::{RoleServer, ServerHandler, model::CallToolRequestParams, service::RequestContext};

    fn bounded<Input, F: std::future::Future + std::marker::Send>(
        name: &str,
        _: impl FnOnce(Input) -> F,
    ) -> usize {
        let bytes = std::mem::size_of::<F>();
        eprintln!("{name}: {bytes} bytes");
        bytes
    }

    #[test]
    fn host_mcp_handler_future_sizes() {
        bounded(
            "Host MCP domain dispatch",
            |(handler, value, context): (&'static Handler, Value, AgentCallContext)| {
                handler.invoke_domain("anywork_wait_agent", value, context)
            },
        );
        let request = bounded(
            "Host MCP tool request",
            |(handler, request, context): (
                &'static HostMcpService<Handler>,
                CallToolRequestParams,
                RequestContext<RoleServer>,
            )| handler.call_tool(request, context),
        );
        bounded(
            "Host spawn",
            |(host, context, request): (&'static AgentHost, AgentCallContext, AgentSpawn)| {
                host.spawn(context, request)
            },
        );
        bounded(
            "Host list",
            |(host, context): (&'static AgentHost, AgentCallContext)| host.list(context),
        );
        bounded(
            "Host close",
            |(host, context): (&'static AgentHost, AgentCallContext)| {
                host.close(context, "child", AgentCloseOptions::default())
            },
        );
        bounded(
            "Host wait",
            |(host, context, request): (&'static AgentHost, AgentCallContext, WaitAgentRequest)| {
                host.wait_agent(context, request)
            },
        );
        bounded(
            "Host models",
            |(host, context, request): (
                &'static AgentHost,
                AgentCallContext,
                pl_protocol::ListDelegationModelsRequest,
            )| host.list_delegation_models(context, request),
        );
        bounded(
            "Host model",
            |(host, context, request): (
                &'static AgentHost,
                AgentCallContext,
                pl_protocol::GetDelegationModelRequest,
            )| host.get_delegation_model(context, request),
        );
        assert!(request <= 16 * 1024, "tool request inlines {request} bytes");
    }
}

/// All references held by the protocol callback are weak with respect to its owner.
pub(crate) fn prepare_open(
    owner: &SessionRuntime,
    identity: &pl_protocol::AgentThreadIdentity,
    resources: &Arc<AcpResources>,
    config: &ConfigRuntime,
    cwd: &str,
    selection: pl_protocol::DelegationSettings,
    mcp_source: crate::host_mcp_assets::HostMcpSource,
) -> Result<PrepareOpen> {
    let snapshot = config.read()?;
    let profiles = config.agent_profiles_snapshot()?;
    let host = owner.acp_agent_host(identity, resources, &profiles, selection)?;
    let instructions = instructions(&snapshot.config.instructions, identity, cwd)?;
    let caller = identity.agent_id.clone();
    let is_root = identity.parent_agent_id.is_none();
    let resources = Arc::downgrade(resources);
    Ok(Arc::new(move |capabilities| {
        let resources = resources.clone();
        let host = host.clone();
        let caller = caller.clone();
        let mut instructions = instructions.clone();
        let mcp_source = mcp_source.clone();
        Box::pin(async move {
            let resources = resources.upgrade().ok_or(pl_acp::session::Error::Closed)?;
            let frontend = if capabilities.mcp_capabilities.http {
                None
            } else {
                Some(
                    crate::host_mcp_assets::prepare(mcp_source)
                        .await
                        .map_err(|error| pl_acp::session::Error::Preparation(error.to_string()))?,
                )
            };
            let definition = resources
                .prepare_host_mcp(host, caller, is_root, frontend)
                .await
                .map_err(|error| pl_acp::session::Error::Preparation(error.to_string()))?;
            instructions.push_str(
                "\nUse the anywork_ tools for host-managed agent delegation, member queries, \
                 report waiting, interruption and closing. Agent IDs and profile IDs come from \
                 these tools. Receipt acceptance is not completion; use anywork_wait_agent \
                 cursors and retain actual report identities. These tools do not grant recursive \
                 spawn, Native review/workflow or filesystem restrictions to ACP agents.\n",
            );
            Ok(OpenSetup {
                mcp_servers: vec![definition],
                instructions: Some(instructions),
            })
        })
    }))
}

fn instructions(
    config: &crate::config::InstructionsConfig,
    identity: &pl_protocol::AgentThreadIdentity,
    cwd: &str,
) -> Result<String> {
    let mut text = format!(
        "You are an agent managed by anywork. Workspace: {cwd}\nAgent: {}\nRole: {}\n\
         Report progress and actual outcomes. Host tool receipts describe acceptance, not success.\n",
        identity.agent_id,
        if identity.parent_agent_id.is_some() {
            "child"
        } else {
            "root"
        },
    );
    for block in [&config.base_override, &config.developer, &config.user] {
        if !block.trim().is_empty() {
            text.push('\n');
            text.push_str(block);
        }
    }
    let path = std::path::Path::new(cwd);
    let documents = pl_tool::workspace::load_workspace_instruction_documents(
        path,
        path,
        config.project_doc_max_bytes,
        &config.project_doc_fallback_filenames,
    )?;
    for document in documents.documents {
        text.push_str(&format!(
            "\nProject instructions ({}):\n",
            document.path.display()
        ));
        text.push_str(&document.content);
    }
    Ok(text)
}

/// Held directly by AcpResources. Debug deliberately omits its bearer and URL.
pub(crate) struct HostMcp {
    shutdown: CancellationToken,
    join: Option<JoinHandle<std::io::Result<()>>>,
    sessions: Option<Arc<LocalSessionManager>>,
    ipc: Option<IpcServer>,
    handlers: TaskTracker,
    observed_calls: Arc<AtomicU64>,
}

impl HostMcp {
    pub(crate) async fn start(
        host: AgentHost,
        caller: pl_protocol::AgentId,
        domain_closed: CancellationToken,
        is_root: bool,
        frontend: Option<&std::path::Path>,
    ) -> Result<(Self, schema::McpServer)> {
        let tools = declarations(&host, is_root)?;
        let shutdown = CancellationToken::new();
        let handlers = TaskTracker::new();
        let observed_calls = Arc::new(AtomicU64::new(0));
        let handler = Handler {
            host: Arc::new(host),
            caller,
            tools: Arc::new(tools),
            domain_closed,
            observed_calls: observed_calls.clone(),
            _lifetime: handlers.token(),
        };
        if let Some(command) = frontend {
            use pl_studio_mcp::{IPC_CAPABILITY_ENV, IPC_ENDPOINT_ENV, STDIO_ARG};
            let ipc = IpcServer::bind(handler, shutdown.clone()).await?;
            let definition = schema::McpServer::Stdio(
                schema::McpServerStdio::new("anywork", command)
                    .args(vec![STDIO_ARG.into()])
                    .env(vec![
                        schema::EnvVariable::new(IPC_ENDPOINT_ENV, ipc.endpoint()),
                        schema::EnvVariable::new(IPC_CAPABILITY_ENV, ipc.capability()),
                    ]),
            );
            return Ok((
                Self {
                    shutdown,
                    join: None,
                    sessions: None,
                    ipc: Some(ipc),
                    handlers,
                    observed_calls,
                },
                definition,
            ));
        }
        let listener = tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0)).await?;
        let address = listener.local_addr()?;
        let bearer = format!(
            "{}{}",
            uuid::Uuid::new_v4().simple(),
            uuid::Uuid::new_v4().simple()
        );
        let authorization = http::HeaderValue::from_str(&format!("Bearer {bearer}"))?;
        let sessions = Arc::new(LocalSessionManager::default());
        let handler = HostMcpService::new(handler);
        let mut server_config = StreamableHttpServerConfig::default();
        server_config.cancellation_token = shutdown.clone();
        server_config.json_response = true;
        let service = StreamableHttpService::new(
            move || Ok(handler.clone()),
            sessions.clone(),
            server_config,
        );
        let app = Router::new()
            .nest_service("/mcp", service)
            .layer(axum::middleware::from_fn(
                move |request: Request<Body>, next: Next| {
                    let expected = authorization.clone();
                    async move {
                        if request.headers().get(AUTHORIZATION) != Some(&expected) {
                            return Response::builder()
                                .status(StatusCode::UNAUTHORIZED)
                                .body(Body::empty())
                                .expect("valid unauthorized response");
                        }
                        next.run(request).await
                    }
                },
            ));
        let stopped = shutdown.clone();
        let join = tokio::spawn(async move {
            axum::serve(listener, app)
                .with_graceful_shutdown(stopped.cancelled_owned())
                .await
        });
        let endpoint = format!("http://{address}/mcp");
        let definition = schema::McpServer::Http(
            schema::McpServerHttp::new("anywork", endpoint).headers(vec![schema::HttpHeader::new(
                "Authorization",
                format!("Bearer {bearer}"),
            )]),
        );
        Ok((
            Self {
                shutdown,
                join: Some(join),
                sessions: Some(sessions),
                ipc: None,
                handlers,
                observed_calls,
            },
            definition,
        ))
    }

    pub(crate) fn observed_counter(&self) -> Arc<AtomicU64> {
        self.observed_calls.clone()
    }

    /// Join the selected transport and original handler lifetimes in place.
    pub(crate) async fn close(&mut self) -> Result<()> {
        self.shutdown.cancel();
        let mut failure = None;
        if let Some(sessions) = self.sessions.as_ref() {
            let ids = sessions
                .sessions
                .read()
                .await
                .keys()
                .cloned()
                .collect::<Vec<_>>();
            for id in ids {
                if let Err(error) = sessions.close_session(&id).await {
                    failure.get_or_insert_with(|| anyhow::anyhow!(error));
                }
            }
        }
        if let Some(ipc) = self.ipc.as_mut() {
            match ipc.close().await {
                Ok(()) => self.ipc = None,
                Err(error) => {
                    failure.get_or_insert_with(|| anyhow::anyhow!(error));
                }
            }
        }
        if let Some(join) = self.join.as_mut() {
            let result = join
                .await
                .context("Host MCP HTTP task failed")
                .and_then(|result| result.map_err(anyhow::Error::from));
            self.join = None;
            if let Err(error) = result {
                failure.get_or_insert(error);
            }
        }
        self.handlers.close();
        self.handlers.wait().await;
        failure.map_or(Ok(()), Err)
    }
}

impl Drop for HostMcp {
    fn drop(&mut self) {
        self.shutdown.cancel();
    }
}

#[derive(Clone)]
struct Handler {
    host: Arc<AgentHost>,
    caller: pl_protocol::AgentId,
    tools: Arc<HostCatalog>,
    domain_closed: CancellationToken,
    observed_calls: Arc<AtomicU64>,
    // Clones remain alive until rmcp has finished their sessions/requests.
    _lifetime: TaskTrackerToken,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
struct Empty {}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Target {
    target: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Send {
    target: String,
    message: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Close {
    target: String,
    #[serde(default)]
    force: bool,
}

fn declarations(host: &AgentHost, is_root: bool) -> Result<HostCatalog> {
    let profiles = host.spawn_profiles();
    let selection = host.delegation();
    let mut definitions = Vec::new();
    for kind in [
        AgentControlKind::Spawn,
        AgentControlKind::Send,
        AgentControlKind::List,
        AgentControlKind::Interrupt,
        AgentControlKind::Close,
    ] {
        if let Some(definition) = kind.declaration(&profiles, selection.mode)? {
            definitions.push(definition);
        }
    }
    if is_root {
        definitions.push(ToolDefinition::json(
            "list_agent_profiles",
            "Read the same executable Profile catalog as spawn_agent.",
            pl_agent_tool::typed::input_schema_for::<Empty>(),
        )?);
    }
    definitions.push(ToolDefinition::json(
        "wait_agent",
        "Read original terminal reports. Without after, latest may predate a recent send. \
         Reuse the returned cursor for subsequent reports. Cancelling only ends observation.",
        pl_agent_tool::typed::input_schema_for::<WaitAgentRequest>(),
    )?);
    if is_root && selection.mode == pl_protocol::DelegationMode::Automatic {
        definitions.push(ToolDefinition::json(
            "list_delegation_models",
            "Query enabled Native child model candidates; ACP does not use modelSelection.",
            pl_agent_tool::typed::input_schema_for::<pl_protocol::ListDelegationModelsRequest>(),
        )?);
        definitions.push(ToolDefinition::json(
            "get_delegation_model",
            "Read a Native child model's current eligibility and supported effort.",
            pl_agent_tool::typed::input_schema_for::<pl_protocol::GetDelegationModelRequest>(),
        )?);
    }
    definitions
        .into_iter()
        .map(|definition| {
            let InputFormat::JsonSchema(input) = definition.input() else {
                anyhow::bail!("Host MCP requires a JSON tool schema")
            };
            Ok(HostTool {
                operation: HostOperation::from_tool_name(&format!("anywork_{}", definition.name()))
                    .context("unknown host operation declaration")?,
                description: definition.description().to_owned(),
                input_schema: input
                    .as_object()
                    .context("tool schema must be an object")?
                    .clone(),
            })
        })
        .collect()
}

impl HostTools for Handler {
    async fn catalog(&self) -> Result<HostCatalog, HostError> {
        Ok(self.tools.as_ref().clone())
    }

    async fn invoke(
        &self,
        request: HostInvocation,
        cancellation: CancellationToken,
    ) -> Result<HostResult, HostError> {
        if !self
            .tools
            .iter()
            .any(|tool| tool.operation == request.operation)
        {
            return Err(HostError::InvalidRequest);
        }
        self.observed_calls.fetch_add(1, Ordering::AcqRel);
        let arguments = Value::Object(request.arguments);
        // The transport owns the supplied token. Completing a domain call must
        // retire only its own context, not cancel the IPC stream before its reply.
        let cancellation = cancellation.child_token();
        let _cancel_on_drop = cancellation.clone().drop_guard();
        let context = AgentCallContext {
            caller: self.caller.clone(),
            call_id: crate::studio::ids::new_id("acp-call"),
            cancellation,
        };
        // Keep the dispatch union's large retirement/cold-activation states on the heap at
        // this transport boundary, rather than inlining them through rmcp's request poll
        // frames. This changes allocation, not operation ownership or cancellation.
        let invoke =
            Box::pin(self.invoke_domain(request.operation.tool_name(), arguments, context));
        let result = tokio::select! {
            result = invoke => result,
            () = self.domain_closed.cancelled() => Err(ControlError::Closed),
        };
        let (value, error) = match result {
            Ok(value) => value,
            Err(error) => (serde_json::json!({ "error": error.to_string() }), true),
        };
        Ok(HostResult {
            value,
            is_error: error,
        })
    }
}

fn decode<T: serde::de::DeserializeOwned>(value: Value) -> Result<T, ControlError> {
    serde_json::from_value(value).map_err(ControlError::service)
}
fn encoded(value: impl serde::Serialize) -> Result<(Value, bool), ControlError> {
    serde_json::to_value(value)
        .map(|value| (value, false))
        .map_err(ControlError::service)
}

impl Handler {
    async fn invoke_domain(
        &self,
        name: &str,
        arguments: Value,
        context: AgentCallContext,
    ) -> Result<(Value, bool), ControlError> {
        match name {
            "anywork_spawn_agent" => {
                let result = self
                    .host
                    .spawn(context, decode::<AgentSpawn>(arguments)?)
                    .await?;
                let error = result.message_error.as_ref().map(ToString::to_string);
                Ok((
                    serde_json::json!({ "receipt": result.receipt, "messageError": error }),
                    error.is_some(),
                ))
            }
            "anywork_send_message" => {
                let request: Send = decode(arguments)?;
                let id = context.call_id.clone();
                encoded(
                    self.host
                        .send(
                            context,
                            AgentMessage {
                                id,
                                target: request.target,
                                message: request.message,
                            },
                        )
                        .await?,
                )
            }
            "anywork_list_agents" => {
                let _: Empty = decode(arguments)?;
                encoded(self.host.list(context).await?)
            }
            "anywork_interrupt_agent" => {
                let request: Target = decode(arguments)?;
                encoded(self.host.interrupt(context, &request.target).await?)
            }
            "anywork_close_agent" => {
                let request: Close = decode(arguments)?;
                encoded(
                    self.host
                        .close(
                            context,
                            &request.target,
                            AgentCloseOptions {
                                force: request.force,
                            },
                        )
                        .await?,
                )
            }
            "anywork_list_agent_profiles" => {
                let _: Empty = decode(arguments)?;
                encoded(self.host.list_agent_profiles(context).await?)
            }
            "anywork_list_delegation_models" => encoded(
                self.host
                    .list_delegation_models(context, decode(arguments)?)
                    .await?,
            ),
            "anywork_get_delegation_model" => encoded(
                self.host
                    .get_delegation_model(context, decode(arguments)?)
                    .await?,
            ),
            "anywork_wait_agent" => {
                let result: WaitAgentResult =
                    self.host.wait_agent(context, decode(arguments)?).await?;
                encoded(result)
            }
            _ => Err(ControlError::Closed),
        }
    }
}
