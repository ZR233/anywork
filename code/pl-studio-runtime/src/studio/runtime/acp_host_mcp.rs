//! Instance-owned ACP Host MCP transport. Domain authority remains in AgentHost.
use std::collections::BTreeMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use anyhow::{Context, Result};
use axum::{Router, body::Body, middleware::Next, response::Response};
use http::{Request, StatusCode, header::AUTHORIZATION};
use pl_acp::session::{AllowOnceForTool, PermissionToolCall, PrepareOpen, schema};
use pl_agent_tool::ToolDefinition;
use pl_studio_mcp::{
    HostCatalog, HostContent, HostError, HostInvocation, HostMcpService, HostResult, HostTool,
    HostTools, ipc::IpcServer,
};
use pl_tool::collaboration::control::{AgentCallContext, ControlError};
use rmcp::transport::streamable_http_server::{
    SessionManager, StreamableHttpServerConfig, StreamableHttpService,
    session::local::LocalSessionManager,
};
use serde_json::Value;
use tokio::task::JoinHandle;
use tokio_util::{
    sync::CancellationToken,
    task::{TaskTracker, task_tracker::TaskTrackerToken},
};

use super::acp_business::AcpResources;
use crate::{
    config::ConfigRuntime,
    thread_assembler::{AgentHost, SessionRuntime},
};

const SERVER_NAME: &str = "anywork";
const MCP_NAME_SEPARATORS: [&str; 6] = ["__", "_", ":", "/", ".", "-"];

/// All references held by the protocol callback are weak with respect to its owner.
pub(crate) async fn prepare_open(
    owner: &SessionRuntime,
    identity: &crate::AgentThreadIdentity,
    resources: &Arc<AcpResources>,
    config: &ConfigRuntime,
    cwd: &str,
    selection: crate::DelegationSettings,
) -> Result<PrepareOpen> {
    let snapshot = config.read()?;
    let profiles = config.agent_profiles_snapshot()?;
    let host = owner.acp_agent_host(identity, resources, &profiles, selection)?;
    let instructions = if let Some(tools) = resources.workspace_tools.get() {
        workspace_instructions(&snapshot.config.instructions, identity, cwd, tools).await?
    } else {
        instructions(&snapshot.config.instructions, identity, cwd)?
    };
    let caller = identity.agent_id.clone();
    let is_root = identity.parent_agent_id.is_none();
    let resources = Arc::downgrade(resources);
    Ok(Arc::new(move |capabilities| {
        let resources = resources.clone();
        let host = host.clone();
        let caller = caller.clone();
        let mut instructions = instructions.clone();
        Box::pin(async move {
            let resources = resources.upgrade().ok_or(pl_acp::session::Error::Closed)?;
            let frontend = if capabilities.mcp_capabilities.http {
                None
            } else {
                Some(
                    resources
                        .host_mcp_frontend()
                        .await
                        .map_err(|error| pl_acp::session::Error::Preparation(error.to_string()))?,
                )
            };
            instructions.push_str(
                "\nCall tools from the anywork MCP catalog directly by their `anywork_*` \
                 names, or by the equivalent qualified names displayed by your ACP client. \
                 Use `anywork_list_agents`, `anywork_send_message`, `anywork_wait_agent`, \
                 `anywork_interrupt_agent`, and `anywork_close_agent` for the member operations \
                 and targets the host allows. Retain the real child and report identities and \
                 use the cursors from `anywork_wait_agent`. A receipt accepting a child or a \
                 message does not establish completed work. Host tools operate within the \
                 configured workspace permissions.\n",
            );
            append_delegation_instructions(&mut instructions, &host);
            if let Some(workflow_plan) = resources.workflow_plan.get() {
                instructions.push_str(
                    "\nYour Plan belongs to this agent. Inspect it with `anywork_plan_current`, \
                     `anywork_plan_next`, and `anywork_plan_history`. For mutations, call \
                     `anywork_plan_transition` with the latest Plan `expectedRevision`. To revise \
                     an approved plan, move it to `drafting` before submitting the updated plan. \
                     If a previous prompt ended before its Plan confirmation was answered, \
                     return that Plan to `drafting` before resubmitting it.\n\
                     When a material decision requires the user, call `anywork_request_user_input` \
                     if it is available. Submit a complete plain-language Markdown Plan with \
                     `anywork_plan_transition` using `targetState=awaitingConfirmation` and \
                     `force=false`. Call each of these interactive tools on its own. The host \
                     presents a structured card and the call waits for the user's response. \
                     The host applies approval or revision feedback, or handles cancellation. \
                     Continue dependent implementation only after the host returns an accepted \
                     decision with `snapshot.state=approved`. Never approve the Plan yourself or \
                     use `force=true` to bypass confirmation. If the user requests changes, use \
                     the feedback to revise and resubmit the Plan. Honor cancellation. If the \
                     card is unavailable or there is no decision, report the need for user input \
                     and pause the work that depends on it.\n",
                );
                if let Some(mode_instructions) = workflow_plan.compiled_mode_instructions() {
                    instructions.push_str(&mode_instructions);
                }
            }
            if !is_root {
                instructions.push_str(
                    "\nAs a child agent, use your own Plan for your assigned work. Root workflow \
                     transitions and child spawning are unavailable in this session.\n",
                );
            }
            let mut setup = resources
                .prepare_host_mcp(host, caller, is_root, frontend)
                .await
                .map_err(|error| pl_acp::session::Error::Preparation(error.to_string()))?;
            setup.instructions = Some(instructions);
            Ok(setup)
        })
    }))
}

fn append_delegation_instructions(instructions: &mut String, host: &AgentHost) {
    if host.identity.parent_agent_id.is_some() {
        return;
    }
    let profiles = host.spawn_profiles();
    if profiles.is_empty() {
        instructions.push_str(
            "\nNo executable child Profile is available in this session. Continue work within \
             your own authorized scope and report any work blocked by the lack of a child.\n",
        );
        return;
    }
    instructions.push_str(
        "\nRead `anywork_list_agent_profiles` before delegating. Copy the enabled Profile's \
         `definition.definitionId` into `profileId`. Use its backend and workspace contract \
         to select the matching branch of `anywork_spawn_agent`. When the task calls for \
         a child and you have selected a valid Profile, invoke that tool and wait for the \
         child report. Look for the server-qualified name as well, such as \
         `mcp_anywork_anywork_spawn_agent` in agy. If it is absent from your callable tools, \
         report that you could not send a call. If you sent one, report its actual result.\n",
    );
    let selection = host.delegation();
    let has_native = profiles
        .iter()
        .any(|profile| profile.backend == crate::AgentBackendKind::Native);
    let has_acp = profiles
        .iter()
        .any(|profile| profile.backend == crate::AgentBackendKind::Acp);
    match selection.mode {
        crate::DelegationMode::Profile => instructions.push_str(
            "Fixed delegation is frozen for this session. Use the Profile's preset route and \
             omit `modelSelection`.\n",
        ),
        crate::DelegationMode::Automatic => instructions.push_str(
            "Automatic delegation is frozen for this session. The Profile sets the role and \
             workspace permissions. Follow the selection rules for its backend.\n",
        ),
    }
    if has_native && let Some(preference) = crate::studio::delegation::preference_prompt(selection)
    {
        instructions.push_str(
            "For an automatic Native dispatch, read the candidate list with \
             `anywork_list_delegation_models`, then batch-read details for suitable candidates \
             with `anywork_get_delegation_models`. If either tool or a suitable candidate is \
             unavailable, use an eligible ACP Profile or continue within your authorized scope. \
             Pass an explicit `modelSelection` with the selected `accountId` and `modelId`. \
             Choose a legal `effort` from the model's returned options when nonempty and omit \
             `effort` when there are none. Apply the following shared preference to Native \
             model selection.\n",
        );
        instructions.push_str(
            &preference
                .replace("先发现 delegation_model 工具，用", "直接用")
                .replace("list_delegation_models", "anywork_list_delegation_models")
                .replace("get_delegation_models", "anywork_get_delegation_models"),
        );
        instructions.push('\n');
    }
    if has_acp {
        instructions.push_str(
            "For an ACP Profile in either mode, omit `modelSelection`. Use `acpConfig` only \
             for actual settings declared by that ACP service. Supply an ordered array of \
             `{id, value}` using declared option value IDs or booleans as appropriate. \
             Otherwise omit `acpConfig` to use the service's new-session defaults. Never \
             infer these settings from the parent's model or session.\n",
        );
    }
}

fn instructions(
    config: &crate::config::InstructionsConfig,
    identity: &crate::AgentThreadIdentity,
    cwd: &str,
) -> Result<String> {
    let mut text = instruction_base(config, identity, cwd);
    let path = std::path::Path::new(cwd);
    let documents = pl_tool::workspace::load_workspace_instruction_documents(
        path,
        path,
        config.project_doc_max_bytes,
        &config.project_doc_fallback_filenames,
    )?;
    append_documents(&mut text, documents);
    Ok(text)
}

fn instruction_base(
    config: &crate::config::InstructionsConfig,
    identity: &crate::AgentThreadIdentity,
    cwd: &str,
) -> String {
    let mut text = format!(
        "You are an agent managed by anywork. ACP host protocol cwd: {cwd}\nAgent: {}\nRole: {}\n\
         Both root and child agents must proactively send concise progress updates as ordinary \
         user-visible ACP messages while working. For a nontrivial task, send an update before \
         the first tool call and at important findings, phase changes, blockers, and before and \
         after long operations. Do not leave ongoing work without an informative update for \
         more than one minute. Each update should use 1-3 natural sentences to explain what is \
         complete, the important result or blocker, and what comes next; avoid repetitive status \
         messages or a tool-by-tool transcript. Hidden thoughts do not replace visible progress. \
         Never reveal hidden reasoning, drafts, or chain of thought. Use normal visible messages, \
         not Native phase tags or invented commentary/final markers. End with a self-contained \
         report of actual outcomes, verification, limitations, and unfinished work. \
         Host tool receipts describe acceptance, not success.\n",
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
    text
}

fn append_documents(text: &mut String, documents: pl_tool::workspace::WorkspaceInstructions) {
    for document in documents.documents {
        text.push_str(&format!(
            "\nProject instructions ({}):\n",
            document.path.display()
        ));
        text.push_str(&document.content);
    }
}

async fn workspace_instructions(
    config: &crate::config::InstructionsConfig,
    identity: &crate::AgentThreadIdentity,
    cwd: &str,
    tools: &super::acp_workspace_tools::WorkspaceTools,
) -> Result<String> {
    let mut text = instruction_base(config, identity, cwd);
    let binding = &tools.binding;
    let environment = &binding.environment;
    let files = binding
        .workspace
        .workspace()
        .session_files()
        .context("missing session files")?;
    text.push_str(&format!(
        "\nACP and its login state run on the Studio host. Host protocol cwd: {cwd}\n\
         Business execution target: {}; OS: {}; shell dialect: {}; shell executable: {}\n\
         Business workspace root: {}\n\
         Execution-side session files, relative to that business root:\n\
         scratch: {}\nartifacts: {}\ncommands: {}\nuploads: {}\nPython environment: {}\n\
         Use the anywork_ workspace tools for business commands, files and enabled Git. \
         These host tools retain the real execution identity, permissions, captures and cleanup owner. \
         Do not infer business paths from host cwd or use local tools for an SSH workspace. \
         Use anywork_read_text_file for UTF-8 files and anywork_view_image for images when present. \
         Use anywork_exec_command for directory listing and search when enabled. \
         Absent commands grant no execution capability. Accepted executions remain owned by this instance. \
         Use anywork_wait and anywork_get_tool_task to read results, not another prompt's automatic delivery. \
         Tool permissions are not an OS sandbox and cannot disable the external agent's own host tools.\n",
        if binding.remote.is_some() { "SSH" } else { "local" },
        environment.os.as_str(), environment.shell.as_str(), environment.shell_path_display(),
        binding.workspace.root().display(), files.scratch().display(), files.artifacts().display(),
        files.commands().display(), files.uploads().display(), files.python_environment().display(),
    ));
    let documents = pl_tool::workspace_file::load_workspace_instructions(
        &binding.execution.files(),
        config.project_doc_max_bytes,
        &config.project_doc_fallback_filenames,
    )
    .await?;
    append_documents(&mut text, documents);
    if let Some((catalog, _)) = &binding.skills {
        text.push_str("\nHost skills use anywork_skills_list and anywork_skill_view, including support files. \
            Use anywork_skill_manage only when present. Unprefixed skill tool names in the index or \
            documents refer to these host tools, not the external agent's own skill catalog.\n");
        text.push_str(&pl_tool::skill::build_skills_prompt_from_catalog(
            catalog.snapshot(),
        ));
    }
    Ok(text)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MetaMcpMatch<'a> {
    Absent,
    Matched(&'a str),
    Rejected,
}

fn strip_mcp_separator(input: &str) -> Option<&str> {
    MCP_NAME_SEPARATORS
        .iter()
        .find_map(|separator| input.strip_prefix(separator))
}

fn host_mcp_tool_from_name<'a>(
    name: &'a str,
    tools: &BTreeMap<String, HostBinding>,
) -> Option<&'a str> {
    if let Some(after_mcp) = name
        .strip_prefix("mcp")
        .and_then(strip_mcp_separator)
        .and_then(|rest| rest.strip_prefix(SERVER_NAME))
        .and_then(strip_mcp_separator)
        && tools.contains_key(after_mcp)
    {
        return Some(after_mcp);
    }
    name.strip_prefix(SERVER_NAME)
        .and_then(strip_mcp_separator)
        .filter(|tool| tools.contains_key(*tool))
}

fn inspect_host_mcp_meta<'a>(
    meta: &'a schema::Meta,
    tools: &BTreeMap<String, HostBinding>,
) -> MetaMcpMatch<'a> {
    if let Some(flag) = meta.get("is_mcp_tool_call")
        && flag.as_bool() != Some(true)
    {
        return MetaMcpMatch::Rejected;
    }
    let Some(mcp) = meta.get("mcp") else {
        return MetaMcpMatch::Absent;
    };
    let Some(mcp) = mcp.as_object() else {
        return MetaMcpMatch::Rejected;
    };
    let Some(server) = mcp.get("server").and_then(Value::as_str) else {
        return MetaMcpMatch::Rejected;
    };
    if server != SERVER_NAME {
        return MetaMcpMatch::Rejected;
    }
    let Some(tool) = mcp.get("tool").and_then(Value::as_str) else {
        return MetaMcpMatch::Rejected;
    };
    if tools.contains_key(tool) {
        MetaMcpMatch::Matched(tool)
    } else {
        MetaMcpMatch::Rejected
    }
}

fn matches_host_mcp_tool_call(
    tool_call: PermissionToolCall<'_>,
    tools: &BTreeMap<String, HostBinding>,
) -> bool {
    let name_tool = tool_call
        .name
        .map(|name| host_mcp_tool_from_name(name, tools));
    let meta_match = tool_call.meta.map_or(MetaMcpMatch::Absent, |meta| {
        inspect_host_mcp_meta(meta, tools)
    });
    match (name_tool, meta_match) {
        (Some(None), _) | (_, MetaMcpMatch::Rejected) | (None, MetaMcpMatch::Absent) => false,
        (Some(Some(name_tool)), MetaMcpMatch::Matched(meta_tool)) => name_tool == meta_tool,
        (Some(Some(_)), MetaMcpMatch::Absent) | (None, MetaMcpMatch::Matched(_)) => true,
    }
}

/// Held directly by AcpResources. Debug deliberately omits its bearer and URL.
pub(crate) struct HostMcp {
    shutdown: CancellationToken,
    join: Option<JoinHandle<std::io::Result<()>>>,
    sessions: Option<Arc<LocalSessionManager>>,
    ipc: Option<IpcServer>,
    handlers: TaskTracker,
    observed_calls: Arc<AtomicU64>,
    host: Arc<AgentHost>,
    caller: crate::AgentId,
    domain_closed: CancellationToken,
    tools: Arc<BTreeMap<String, HostBinding>>,
    protocol_closed: bool,
}

impl HostMcp {
    /// Attach this owner to AcpResources before any fallible setup or await.
    pub(super) fn pending(
        host: AgentHost,
        caller: crate::AgentId,
        domain_closed: CancellationToken,
    ) -> Self {
        Self {
            shutdown: CancellationToken::new(),
            join: None,
            sessions: None,
            ipc: None,
            handlers: TaskTracker::new(),
            observed_calls: Arc::new(AtomicU64::new(0)),
            host: Arc::new(host),
            caller,
            domain_closed,
            tools: Arc::new(BTreeMap::new()),
            protocol_closed: false,
        }
    }

    pub(super) async fn launch(
        &mut self,
        is_root: bool,
        frontend: Option<&std::path::Path>,
        workspace: Option<Arc<super::acp_workspace_tools::WorkspaceTools>>,
        workflow_plan: Option<Arc<super::acp_business::AcpWorkflowPlanOwner>>,
    ) -> Result<schema::McpServer> {
        let tools = Arc::get_mut(&mut self.tools).context("Host MCP tools already published")?;
        crate::thread_assembler::host_agent_tools::register(
            self.host.clone(),
            is_root,
            true,
            &mut AgentMcpTools(tools),
        )?;
        if let Some(workspace) = workspace {
            workspace.bind(tools).await?;
        }
        if let Some(wp) = workflow_plan {
            attach_workflow_and_plan_tools(tools, wp, is_root)?;
        }
        let handler = Handler {
            host: self.host.clone(),
            caller: self.caller.clone(),
            tools: self.tools.clone(),
            domain_closed: self.domain_closed.clone(),
            observed_calls: self.observed_calls.clone(),
            _lifetime: self.handlers.token(),
        };
        if let Some(command) = frontend {
            use pl_studio_mcp::{IPC_CAPABILITY_ENV, IPC_ENDPOINT_ENV, STDIO_ARG};
            self.ipc = Some(IpcServer::bind(handler, self.shutdown.clone()).await?);
            let ipc = self.ipc.as_ref().expect("attached IPC owner");
            return Ok(schema::McpServer::Stdio(
                schema::McpServerStdio::new(SERVER_NAME, command)
                    .args(vec![STDIO_ARG.into()])
                    .env(vec![
                        schema::EnvVariable::new(IPC_ENDPOINT_ENV, ipc.endpoint()),
                        schema::EnvVariable::new(IPC_CAPABILITY_ENV, ipc.capability()),
                    ]),
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
        server_config.cancellation_token = self.shutdown.clone();
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
        let stopped = self.shutdown.clone();
        self.join = Some(tokio::spawn(async move {
            axum::serve(listener, app)
                .with_graceful_shutdown(stopped.cancelled_owned())
                .await
        }));
        self.sessions = Some(sessions);
        Ok(schema::McpServer::Http(
            schema::McpServerHttp::new(SERVER_NAME, format!("http://{address}/mcp")).headers(vec![
                schema::HttpHeader::new("Authorization", format!("Bearer {bearer}")),
            ]),
        ))
    }

    pub(super) fn permission_filter(&self) -> AllowOnceForTool {
        let tools = Arc::downgrade(&self.tools);
        let closed = self.domain_closed.clone();
        Arc::new(move |tool_call| {
            !closed.is_cancelled()
                && tools
                    .upgrade()
                    .is_some_and(|tools| matches_host_mcp_tool_call(tool_call, &tools))
        })
    }

    pub(super) fn protocol_closed(&self) -> bool {
        self.protocol_closed
    }

    /// The owning resources call this only after accepted business tasks have joined.
    pub(super) async fn close_tools(&self) -> Result<()> {
        let mut failure = None;
        for binding in self.tools.values() {
            if let Err(error) = binding.close().await {
                failure.get_or_insert(error);
            }
        }
        failure.map_or(Ok(()), |error| Err(error.into()))
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
        self.protocol_closed = failure.is_none();
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
    caller: crate::AgentId,
    tools: Arc<BTreeMap<String, HostBinding>>,
    domain_closed: CancellationToken,
    observed_calls: Arc<AtomicU64>,
    // Clones remain alive until rmcp has finished their sessions/requests.
    _lifetime: TaskTrackerToken,
}

type DomainResult = Result<HostResult, ControlError>;
type DomainInvocation = dyn Fn(
        Arc<AgentHost>,
        pl_core::context::OpaquePayload,
        AgentCallContext,
    ) -> futures::future::BoxFuture<'static, DomainResult>
    + Send
    + Sync;
type CloseInvocation = dyn Fn() -> futures::future::BoxFuture<'static, Result<(), pl_core::tool::opaque::ToolError>>
    + Send
    + Sync;
pub(super) type HostHandle<C, O = pl_core::tool::ToolOutput> = pl_agent_tool::ToolHandle<
    pl_core::context::OpaquePayload,
    C,
    O,
    pl_core::tool::opaque::ToolError,
>;

/// Declaration, input codec and the original instance are admitted together.
pub(super) struct HostBinding {
    declaration: HostTool,
    projection: pl_studio_mcp::ToolProjection,
    invoke: Box<DomainInvocation>,
    close: Box<CloseInvocation>,
    closed: tokio::sync::Mutex<bool>,
}

impl HostBinding {
    async fn close(&self) -> Result<(), pl_core::tool::opaque::ToolError> {
        let mut closed = self.closed.lock().await;
        if !*closed {
            (self.close)().await?;
            *closed = true;
        }
        Ok(())
    }
}

pub(super) fn prepare_binding(
    tools: &BTreeMap<String, HostBinding>,
    definition: &ToolDefinition,
    input: pl_studio_mcp::JsonInput,
) -> Result<pl_studio_mcp::ToolProjection> {
    let projection = pl_studio_mcp::ToolProjection::prepare(definition, input, false)?;
    anyhow::ensure!(
        !tools.contains_key(&projection.declaration().tool_id),
        "duplicate Host MCP tool identity"
    );
    Ok(projection)
}

pub(super) fn attach_binding<C, O, T, F>(
    tools: &mut BTreeMap<String, HostBinding>,
    projection: pl_studio_mcp::ToolProjection,
    tool: T,
    invoke: F,
) where
    C: Send + 'static,
    O: Send + 'static,
    T: pl_agent_tool::Tool<
            Input = pl_core::context::OpaquePayload,
            Context = C,
            Output = O,
            Error = pl_core::tool::opaque::ToolError,
        >,
    F: Fn(
            Arc<HostHandle<C, O>>,
            Arc<AgentHost>,
            pl_core::context::OpaquePayload,
            AgentCallContext,
        ) -> futures::future::BoxFuture<'static, DomainResult>
        + Send
        + Sync
        + 'static,
{
    let handle = Arc::new(pl_agent_tool::ToolHandle::new(tool));
    let closing = handle.clone();
    let declaration = projection.declaration().clone();
    let id = declaration.tool_id.clone();
    let binding = HostBinding {
        declaration,
        projection,
        invoke: Box::new(move |host, input, context| invoke(handle.clone(), host, input, context)),
        close: Box::new(move || {
            let handle = closing.clone();
            Box::pin(async move { handle.close().await })
        }),
        closed: tokio::sync::Mutex::new(false),
    };
    assert!(
        tools.insert(id, binding).is_none(),
        "prepared Host MCP identity changed"
    );
}

pub(super) fn projected_input(
    input: pl_studio_mcp::ProjectedInput,
) -> pl_core::context::OpaquePayload {
    match input {
        pl_studio_mcp::ProjectedInput::Json(text) => {
            pl_core::context::OpaquePayload::new("application/json", 1, text)
                .expect("fixed JSON encoding")
        }
        pl_studio_mcp::ProjectedInput::Text(text) => pl_core::context::OpaquePayload::text(text),
    }
}

#[derive(Debug, thiserror::Error)]
#[error("the registered Host tool returned Native control without an ACP state owner")]
struct UnsupportedHostControl;

pub(super) fn data_output(
    output: pl_core::tool::ToolOutput,
) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
    if output.control() != pl_core::tool::ToolControl::Continue
        || !output.extension_mutations().is_empty()
        || !output.revealed_tools().is_empty()
        || output.interaction().is_some()
    {
        return Err(
            pl_core::tool::opaque::ToolError::new(UnsupportedHostControl).with_output(output),
        );
    }
    Ok(output)
}

pub(super) fn host_result(
    result: Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError>,
) -> HostResult {
    let observed = match &result {
        Ok(output) => Some(output),
        Err(error) => error.observed_output(),
    };
    let value = observed
        .map(|output| {
            serde_json::from_str(output.payload().content())
                .unwrap_or_else(|_| Value::String(output.payload().content().into()))
        })
        .unwrap_or(Value::Null);
    match result {
        Ok(_) => HostResult {
            value,
            is_error: false,
            content: None,
        },
        Err(error) => HostResult {
            value: serde_json::json!({"error": error.to_string(), "output": value}),
            is_error: true,
            content: None,
        },
    }
}

struct AgentMcpTools<'a>(&'a mut BTreeMap<String, HostBinding>);

pub(super) fn attach_direct<T>(
    tools: &mut BTreeMap<String, HostBinding>,
    projection: pl_studio_mcp::ToolProjection,
    tool: T,
) where
    T: pl_agent_tool::Tool<
            Input = pl_core::context::OpaquePayload,
            Context = AgentCallContext,
            Output = pl_core::tool::ToolOutput,
            Error = pl_core::tool::opaque::ToolError,
        >,
{
    attach_binding(tools, projection, tool, |handle, host, input, context| {
        Box::pin(async move {
            host.authorize_workspace_call(&context).await?;
            Ok(host_result(
                handle.execute(input, context).await.and_then(data_output),
            ))
        })
    });
}

impl crate::thread_assembler::host_agent_tools::AgentToolSink for AgentMcpTools<'_> {
    type Context = AgentCallContext;
    type Prepared = pl_studio_mcp::ToolProjection;
    fn prepare(
        &mut self,
        definition: &ToolDefinition,
        _: crate::thread_assembler::host_agent_tools::AgentToolOptions,
    ) -> Result<Self::Prepared> {
        if definition.name() == "spawn_agent" {
            let definition = acp_spawn_definition(definition)?;
            return prepare_binding(self.0, &definition, pl_studio_mcp::JsonInput::Object);
        }
        prepare_binding(self.0, definition, pl_studio_mcp::JsonInput::Object)
    }
    fn attach<T>(&mut self, projection: Self::Prepared, tool: T)
    where
        T: pl_agent_tool::Tool<
                Input = pl_core::context::OpaquePayload,
                Context = AgentCallContext,
                Output = pl_core::tool::ToolOutput,
                Error = pl_core::tool::opaque::ToolError,
            >,
    {
        attach_direct(self.0, projection, tool);
    }
}

#[derive(Debug, Clone, Copy)]
enum AcpPlanToolKind {
    AskUser,
    Current,
    Next,
    History,
    Transition,
}

/// ACP submits or withdraws a Plan. Feedback and approval arrive through the host card.
#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AcpPlanTransitionInput {
    #[schemars(with = "String")]
    target_state: pl_tool_plan::PlanState,
    #[serde(default)]
    #[schemars(with = "String", transform = omit_plan_argument_default)]
    content: Option<String>,
    #[serde(default)]
    #[schemars(with = "u64", transform = omit_plan_argument_default)]
    expected_revision: Option<u64>,
    #[serde(default)]
    #[schemars(transform = omit_plan_argument_default)]
    force: bool,
}

fn omit_plan_argument_default(schema: &mut schemars::Schema) {
    schema.remove("default");
}

impl From<AcpPlanTransitionInput> for pl_tool_plan::PlanTransitionArgs {
    fn from(input: AcpPlanTransitionInput) -> Self {
        Self {
            target_state: input.target_state,
            content: input.content,
            feedback: None,
            reason: None,
            force: input.force,
            expected_revision: input.expected_revision,
            idempotency_key: None,
        }
    }
}

struct AcpPlanBindingTool {
    definition: ToolDefinition,
    kind: AcpPlanToolKind,
    owner: Arc<super::acp_business::AcpWorkflowPlanOwner>,
}

impl pl_agent_tool::Tool for AcpPlanBindingTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = AgentCallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: pl_core::context::OpaquePayload,
        context: AgentCallContext,
    ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
        use crate::tool_json::{JsonToolInput, json_output};
        use pl_core::tool::opaque::ToolError;
        use pl_tool_plan::PlanHost;

        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let input = JsonToolInput::new(&input)?;
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
            .unwrap_or(0);
        let plan_ctx = super::acp_business::AcpPlanToolContext {
            call_id: context.call_id.clone(),
            turn_id: context.call_id,
            now_ms,
        };
        let value = match self.kind {
            AcpPlanToolKind::AskUser => {
                let args: pl_tool::ask_user::AskUserInput = input.decode()?;
                let resolution = self
                    .owner
                    .ask_user(
                        plan_ctx.call_id,
                        args.into_questions()?,
                        &context.cancellation,
                    )
                    .await
                    .map_err(|error| ToolError::new(std::io::Error::other(error)))?;
                serde_json::to_value(resolution).map_err(ToolError::new)?
            }
            AcpPlanToolKind::Current => {
                let _: pl_tool_plan::PlanEmptyArgs = input.decode()?;
                serde_json::to_value(self.owner.current(plan_ctx).await.map_err(ToolError::new)?)
                    .map_err(ToolError::new)?
            }
            AcpPlanToolKind::Next => {
                let _: pl_tool_plan::PlanEmptyArgs = input.decode()?;
                serde_json::to_value(self.owner.next(plan_ctx).await.map_err(ToolError::new)?)
                    .map_err(ToolError::new)?
            }
            AcpPlanToolKind::History => {
                let args: pl_tool_plan::PlanHistoryArgs = input.decode()?;
                serde_json::to_value(
                    self.owner
                        .history(args, plan_ctx)
                        .await
                        .map_err(ToolError::new)?,
                )
                .map_err(ToolError::new)?
            }
            AcpPlanToolKind::Transition => {
                let args: AcpPlanTransitionInput = input.decode()?;
                let outcome = self
                    .owner
                    .transition_from_tool(args.into(), plan_ctx, &context.cancellation)
                    .await
                    .map_err(|error| ToolError::new(std::io::Error::other(error)))?;
                serde_json::to_value(&outcome).map_err(ToolError::new)?
            }
        };
        json_output("application/json", &value)
    }
}

struct AcpWorkflowBindingTool {
    definition: ToolDefinition,
    kind: crate::workflow_tool::WorkflowOperationKind,
    owner: Arc<super::acp_business::AcpWorkflowPlanOwner>,
}

impl pl_agent_tool::Tool for AcpWorkflowBindingTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = AgentCallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: pl_core::context::OpaquePayload,
        context: AgentCallContext,
    ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
        use crate::tool_json::{JsonToolInput, json_output};
        use crate::workflow_tool::{
            WorkflowOperationKind,
            machine::{EmptyInput, RestartInput, TransitionInput, WorkflowOperation},
        };
        use pl_core::tool::opaque::ToolError;

        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let input = JsonToolInput::new(&input)?;
        let arg_hash = input.argument_hash();
        let op = WorkflowOperation {
            turn_id: context.call_id.clone(),
            call_id: context.call_id,
        };
        let value = match self.kind {
            WorkflowOperationKind::Current => {
                let _: EmptyInput = input.decode()?;
                self.owner
                    .workflow_current_json()
                    .await
                    .map_err(ToolError::new)?
            }
            WorkflowOperationKind::Next => {
                let _: EmptyInput = input.decode()?;
                self.owner
                    .workflow_next_json()
                    .await
                    .map_err(ToolError::new)?
            }
            WorkflowOperationKind::Graph => {
                let _: EmptyInput = input.decode()?;
                self.owner
                    .workflow_graph_json()
                    .await
                    .map_err(ToolError::new)?
            }
            WorkflowOperationKind::History => {
                let _: EmptyInput = input.decode()?;
                self.owner
                    .workflow_history_json()
                    .await
                    .map_err(ToolError::new)?
            }
            WorkflowOperationKind::Transition => {
                let args: TransitionInput = input.decode()?;
                self.owner
                    .workflow_transition(args, op, arg_hash)
                    .await
                    .map_err(ToolError::new)?
            }
            WorkflowOperationKind::Restart => {
                let args: RestartInput = input.decode()?;
                self.owner
                    .workflow_restart(args, op, arg_hash)
                    .await
                    .map_err(ToolError::new)?
            }
        };
        json_output("application/json", &value)
    }
}

fn attach_workflow_and_plan_tools(
    tools: &mut BTreeMap<String, HostBinding>,
    owner: Arc<super::acp_business::AcpWorkflowPlanOwner>,
    is_root: bool,
) -> Result<()> {
    use pl_agent_tool::typed::{TypedTool, input_schema_for};
    use pl_tool_plan::{
        PlanCurrentTool, PlanEmptyArgs, PlanHistoryArgs, PlanHistoryTool, PlanNextTool,
        PlanTransitionTool,
    };

    type Owner = super::acp_business::AcpWorkflowPlanOwner;
    let plan_defs = [
        (
            AcpPlanToolKind::AskUser,
            pl_tool::ask_user::ask_user_tool_definition(),
        ),
        (
            AcpPlanToolKind::Current,
            ToolDefinition::json(
                PlanCurrentTool::<Owner>::NAME,
                PlanCurrentTool::<Owner>::DESCRIPTION,
                input_schema_for::<PlanEmptyArgs>(),
            )?,
        ),
        (
            AcpPlanToolKind::Next,
            ToolDefinition::json(
                PlanNextTool::<Owner>::NAME,
                PlanNextTool::<Owner>::DESCRIPTION,
                input_schema_for::<PlanEmptyArgs>(),
            )?,
        ),
        (
            AcpPlanToolKind::History,
            ToolDefinition::json(
                PlanHistoryTool::<Owner>::NAME,
                PlanHistoryTool::<Owner>::DESCRIPTION,
                input_schema_for::<PlanHistoryArgs>(),
            )?,
        ),
        (
            AcpPlanToolKind::Transition,
            ToolDefinition::json(
                PlanTransitionTool::<Owner>::NAME,
                "Submit Markdown for host confirmation with targetState=awaitingConfirmation and content. Use targetState=drafting to withdraw or revise.",
                input_schema_for::<AcpPlanTransitionInput>(),
            )?,
        ),
    ];
    for (kind, definition) in plan_defs {
        let projection = prepare_binding(tools, &definition, pl_studio_mcp::JsonInput::Object)?;
        attach_direct(
            tools,
            projection,
            AcpPlanBindingTool {
                definition,
                kind,
                owner: Arc::clone(&owner),
            },
        );
    }

    if is_root {
        for (kind, definition) in crate::workflow_tool::workflow_tool_definitions()? {
            let definition = if matches!(
                kind,
                crate::workflow_tool::WorkflowOperationKind::Transition
            ) {
                acp_workflow_transition_definition(&definition)?
            } else {
                definition
            };
            let projection = prepare_binding(tools, &definition, pl_studio_mcp::JsonInput::Object)?;
            attach_direct(
                tools,
                projection,
                AcpWorkflowBindingTool {
                    definition,
                    kind,
                    owner: Arc::clone(&owner),
                },
            );
        }
    }
    Ok(())
}

fn acp_workflow_transition_definition(definition: &ToolDefinition) -> Result<ToolDefinition> {
    Ok(ToolDefinition::json(
        definition.name(),
        "Move the workflow to an allowed next stage.",
        compact_acp_input_schema(definition)?.to_value(),
    )?)
}

fn acp_spawn_definition(definition: &ToolDefinition) -> Result<ToolDefinition> {
    let mut schema = compact_acp_input_schema(definition)?.to_value();
    let (properties, required) = (
        schema["properties"]
            .as_object()
            .context("spawn properties")?
            .clone(),
        schema["required"]
            .as_array()
            .context("spawn required fields")?
            .clone(),
    );
    let branches = schema["oneOf"].as_array_mut().context("spawn branches")?;
    for branch in branches {
        let branch = branch.as_object_mut().context("spawn branch object")?;
        // The root constraints apply to every branch. Keep only the additional
        // constraints here, including false schemas that forbid a field.
        branch
            .get_mut("properties")
            .and_then(Value::as_object_mut)
            .context("spawn branch properties")?
            .retain(|name, value| properties.get(name) != Some(value));
        let branch_required = branch
            .get_mut("required")
            .and_then(Value::as_array_mut)
            .context("spawn branch required fields")?;
        branch_required.retain(|name| !required.contains(name));
        if branch_required.is_empty() {
            branch.remove("required");
        }
    }
    Ok(ToolDefinition::json(
        definition.name(),
        "Start a child using an enabled Profile. For an ACP child, use the requested model in acpConfig.",
        schema,
    )?)
}

fn compact_acp_input_schema(definition: &ToolDefinition) -> Result<schemars::Schema> {
    use schemars::transform::{RecursiveTransform, Transform};

    let pl_agent_tool::InputFormat::JsonSchema(schema) = definition.input() else {
        anyhow::bail!("ACP tool `{}` requires a JSON schema", definition.name());
    };
    let mut schema = schemars::Schema::try_from(schema.clone())?;
    // Keep the shared parameter contract while omitting annotations that can
    // prevent ACP clients from exposing the function to their model.
    RecursiveTransform(|schema: &mut schemars::Schema| {
        for key in ["title", "$schema", "description", "format", "default"] {
            schema.remove(key);
        }
    })
    .transform(&mut schema);
    Ok(schema)
}

impl HostTools for Handler {
    async fn catalog(&self) -> Result<HostCatalog, HostError> {
        Ok(self
            .tools
            .values()
            .map(|tool| tool.declaration.clone())
            .collect())
    }

    async fn invoke(
        &self,
        request: HostInvocation,
        cancellation: CancellationToken,
    ) -> Result<HostResult, HostError> {
        if !self.tools.contains_key(&request.tool_id) {
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
        // Normal calls retain no payload copy; this evidence is explicitly opt-in.
        let evidence = tracing::enabled!(
            target: "pl_studio_runtime::acp_host_call_evidence",
            tracing::Level::TRACE
        )
        .then(|| (arguments.clone(), context.call_id.clone()));
        // Keep the dispatch union's large retirement/cold-activation states on the heap at
        // this transport boundary, rather than inlining them through rmcp's request poll
        // frames. This changes allocation, not operation ownership or cancellation.
        let invoke = Box::pin(self.invoke_domain(&request.tool_id, arguments, context));
        let result = tokio::select! {
            result = invoke => result,
            () = self.domain_closed.cancelled() => Err(ControlError::Closed),
        };
        let result = result.unwrap_or_else(|error| HostResult {
            value: serde_json::json!({ "error": error.to_string() }),
            is_error: true,
            content: None,
        });
        if let Some((arguments, host_call_id)) = evidence {
            let summary;
            let logged_value =
                if request.tool_id == "anywork_request_user_input" && !result.is_error {
                    summary = Value::String("User answered".into());
                    &summary
                } else if let Some(content) = &result.content {
                    summary = match content {
                        HostContent::Text(text) => {
                            serde_json::json!({"contentType": "text", "bytes": text.len()})
                        }
                        HostContent::Image { mime_type, .. } => {
                            serde_json::json!({"contentType": "image", "mimeType": mime_type})
                        }
                    };
                    &summary
                } else {
                    &result.value
                };
            tracing::trace!(
                target: "pl_studio_runtime::acp_host_call_evidence",
                record_json = %serde_json::json!({
                    "kind": "acp_host_call_result",
                    "version": 1,
                    "pid": std::process::id(),
                    "callerAgentId": self.caller.as_str(),
                    "hostCallId": host_call_id,
                    "toolId": request.tool_id,
                    "arguments": arguments,
                    "value": logged_value,
                    "isError": result.is_error,
                }),
                "host_mcp_call_result"
            );
        }
        Ok(result)
    }
}

impl Handler {
    async fn invoke_domain(
        &self,
        tool_id: &str,
        arguments: Value,
        context: AgentCallContext,
    ) -> DomainResult {
        let binding = self.tools.get(tool_id).ok_or(ControlError::Closed)?;
        let Value::Object(arguments) = arguments else {
            return Err(ControlError::service(HostError::InvalidRequest));
        };
        let input = binding
            .projection
            .decode(arguments)
            .map_err(ControlError::service)?;
        (binding.invoke)(self.host.clone(), projected_input(input), context).await
    }
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use std::sync::{Arc, Mutex};

    use anyhow::{Context, Result, ensure};
    use pl_acp::session::schema;
    use pl_tool::collaboration::{control::AgentCallContext, thread::AgentControlHost};
    use reqwest::{Client, StatusCode, header};
    use serde_json::{Value, json};
    use tokio_util::sync::CancellationToken;

    use crate::acp_transport_fixture::AcpTransportFixture as Fixture;

    use super::{AgentHost, HostMcp};
    use crate::studio::runtime::acp_workspace_tools::WorkspaceTools;
    use crate::studio::thread_factory::PreparedAcpWorkspace;
    use pl_tool::{
        command::WorkspaceExecutionBinding,
        environment::{ExecutionEnvironment, ExecutionOs, ShellDialect},
        remote::{SshServerProfile, SshWorkspaceBinding},
        workspace::{AgentWorkspace, SessionFiles, ToolWorkspace},
    };
    use std::{path::PathBuf, time::Duration};

    impl HostMcp {
        async fn start(
            host: AgentHost,
            caller: crate::AgentId,
            domain_closed: CancellationToken,
            is_root: bool,
            frontend: Option<&std::path::Path>,
        ) -> Result<(Self, schema::McpServer)> {
            Self::start_bound(host, caller, domain_closed, is_root, frontend, None).await
        }

        async fn start_with_workflow(
            host: AgentHost,
            caller: crate::AgentId,
            domain_closed: CancellationToken,
            is_root: bool,
            frontend: Option<&std::path::Path>,
            workflow_plan: Option<Arc<crate::studio::runtime::acp_business::AcpWorkflowPlanOwner>>,
        ) -> Result<(Self, schema::McpServer)> {
            Self::start_fixture(
                host,
                caller,
                domain_closed,
                is_root,
                frontend,
                None,
                workflow_plan,
            )
            .await
        }

        async fn start_bound(
            host: AgentHost,
            caller: crate::AgentId,
            domain_closed: CancellationToken,
            is_root: bool,
            frontend: Option<&std::path::Path>,
            workspace: Option<Arc<WorkspaceTools>>,
        ) -> Result<(Self, schema::McpServer)> {
            Self::start_fixture(
                host,
                caller,
                domain_closed,
                is_root,
                frontend,
                workspace,
                None,
            )
            .await
        }

        async fn start_fixture(
            host: AgentHost,
            caller: crate::AgentId,
            domain_closed: CancellationToken,
            is_root: bool,
            frontend: Option<&std::path::Path>,
            workspace: Option<Arc<WorkspaceTools>>,
            workflow_plan: Option<Arc<crate::studio::runtime::acp_business::AcpWorkflowPlanOwner>>,
        ) -> Result<(Self, schema::McpServer)> {
            let mut service = Self::pending(host, caller, domain_closed);
            match service
                .launch(is_root, frontend, workspace, workflow_plan)
                .await
            {
                Ok(definition) => Ok((service, definition)),
                Err(error) => {
                    service
                        .close()
                        .await
                        .context("failed to reclaim rejected MCP transport")?;
                    service
                        .close_tools()
                        .await
                        .context("failed to reclaim rejected MCP tools")?;
                    Err(error)
                }
            }
        }
    }

    #[derive(Clone, Default)]
    struct EvidenceBuffer(Arc<Mutex<Vec<u8>>>);

    impl<'writer> tracing_subscriber::fmt::MakeWriter<'writer> for EvidenceBuffer {
        type Writer = tracing_subscriber::fmt::writer::MutexGuardWriter<'writer, Vec<u8>>;

        fn make_writer(&'writer self) -> Self::Writer {
            tracing_subscriber::fmt::MakeWriter::make_writer(self.0.as_ref())
        }
    }

    fn capture_evidence(buffer: EvidenceBuffer, filter: &str) -> tracing::subscriber::DefaultGuard {
        let subscriber = tracing_subscriber::fmt()
            .with_env_filter(tracing_subscriber::EnvFilter::new(filter))
            .without_time()
            .with_ansi(false)
            .with_writer(buffer)
            .finish();
        tracing::subscriber::set_default(subscriber)
    }

    fn evidence_records(buffer: &EvidenceBuffer) -> Result<Vec<Value>> {
        let text = String::from_utf8(buffer.0.lock().unwrap().clone())?;
        text.lines()
            .filter(|line| line.contains("pl_studio_runtime::acp_host_call_evidence"))
            .map(|line| {
                let (_, record) = line
                    .split_once("host_mcp_call_result record_json=")
                    .context("complete host call evidence field must be last on one line")?;
                serde_json::from_str(record).context("host call evidence JSON")
            })
            .collect()
    }

    fn check_evidence(
        record: &Value,
        caller: &str,
        tool: &str,
        arguments: &Value,
        value: &Value,
        is_error: bool,
    ) -> Result<()> {
        ensure!(record.as_object().context("evidence object")?.len() == 9);
        ensure!(record["kind"] == "acp_host_call_result" && record["version"] == 1);
        ensure!(record["pid"] == std::process::id());
        ensure!(record["callerAgentId"] == caller);
        ensure!(
            record["hostCallId"]
                .as_str()
                .is_some_and(|id| id.starts_with("acp-call-"))
        );
        ensure!(record["toolId"] == tool);
        ensure!(record["arguments"] == *arguments);
        ensure!(record["value"] == *value);
        ensure!(record["isError"] == is_error);
        Ok(())
    }

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

        async fn tool(&mut self, name: &str, arguments: Value) -> Result<Value> {
            let response = self
                .request("tools/call", json!({"name":name,"arguments":arguments}))
                .await?;
            ensure!(
                response["error"].is_null(),
                "MCP protocol failure: {response}"
            );
            ensure!(
                response["result"]["isError"] != true,
                "MCP tool failed: {response}"
            );
            Ok(response["result"]["structuredContent"].clone())
        }

        async fn task_result(&mut self, task: &str) -> Result<Value> {
            Ok(self.task_reply(task).await?["value"].clone())
        }

        async fn completed_tool(
            &mut self,
            name: &str,
            arguments: Value,
        ) -> Result<pl_studio_mcp::HostResult> {
            let response = self
                .request("tools/call", json!({"name":name,"arguments":arguments}))
                .await?;
            ensure!(
                response["error"].is_null(),
                "MCP protocol failure: {response}"
            );
            let result = &response["result"];
            if result["structuredContent"]["status"] == "running" {
                let task = result["structuredContent"]["taskId"]
                    .as_str()
                    .context("pending tool receipt")?;
                Ok(serde_json::from_value(self.task_reply(task).await?)?)
            } else {
                Ok(pl_studio_mcp::HostResult {
                    value: result["structuredContent"].clone(),
                    is_error: result["isError"] == true,
                    content: None,
                })
            }
        }

        async fn completed_value(&mut self, name: &str, arguments: Value) -> Result<Value> {
            let result = self.completed_tool(name, arguments).await?;
            ensure!(!result.is_error, "MCP tool {name} failed: {}", result.value);
            Ok(result.value)
        }

        async fn task_reply(&mut self, task: &str) -> Result<Value> {
            self.tool("anywork_wait", json!({"taskIds":[task],"timeoutMs":30000}))
                .await?;
            let mut content = String::new();
            let mut cursor = 0;
            loop {
                let result = self
                    .tool(
                        "anywork_get_tool_task",
                        json!({"taskId":task,"resultCursor":cursor}),
                    )
                    .await?;
                content.push_str(
                    result["result"]["content"]
                        .as_str()
                        .context("task result content")?,
                );
                match result["result"]["nextCursor"].as_u64() {
                    Some(next) => cursor = next,
                    None => break,
                }
            }
            Ok(serde_json::from_str(&content)?)
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
            None,
            "acp-child",
            &crate::config::UserAgentProfile {
                enabled: true,
                display_name: "ACP child".into(),
                description: "Ordinary ACP task".into(),
                when_to_use: "External coding task".into(),
                binding: crate::AgentBinding::Acp(crate::AcpAgentConfig {
                    account_id: "business-peer".into(),
                }),
                workspace_mode: crate::AgentWorkspaceMode::Directory,
            },
        )?;
        Ok(())
    }

    struct SshWorkspaceMcp<'a> {
        fixture: &'a Fixture,
        root: PathBuf,
        target: crate::AcpSessionTarget,
        host: crate::thread_assembler::AgentHost,
        caller: crate::AgentId,
        cancellation: CancellationToken,
        executor: pl_remote_helper::Executor,
        binding: PreparedAcpWorkspace,
        config: crate::config::StudioConfig,
        services: &'a mut Vec<(HostMcp, Arc<WorkspaceTools>)>,
    }

    impl SshWorkspaceMcp<'_> {
        async fn start(
            &mut self,
            config: &crate::config::StudioConfig,
            binding: PreparedAcpWorkspace,
        ) -> Result<HttpMcp> {
            let tools = WorkspaceTools::new_with_handoff_timeout(
                self.target.thread_id.clone(),
                binding,
                config,
                Duration::from_millis(250),
            );
            let (service, definition) = HostMcp::start_bound(
                self.host.clone(),
                self.caller.clone(),
                self.cancellation.clone(),
                true,
                None,
                Some(tools.clone()),
            )
            .await?;
            self.services.push((service, tools));
            let mut peer = HttpMcp::from_definition(definition)?;
            peer.initialize().await?;
            Ok(peer)
        }

        async fn start_default(&mut self) -> Result<HttpMcp> {
            self.start(&self.config.clone(), self.binding.clone()).await
        }
    }

    async fn with_ssh_workspace(
        check: impl for<'a, 'f> FnOnce(
            &'a mut SshWorkspaceMcp<'f>,
        ) -> futures::future::BoxFuture<'a, Result<()>>,
    ) -> Result<()> {
        use futures::FutureExt;

        let fixture = Fixture::new("replay").await?;
        let root = fixture.home.path().join("business-target");
        tokio::fs::create_dir(&root).await?;
        let (client, server) = tokio::io::duplex(64 * 1024);
        let helper = tokio::spawn(pl_remote_helper::serve_connection(server));
        let executor = pl_remote_helper::Executor::remote(client).await?;
        let mut target = None;
        let mut services = Vec::new();
        let result = std::panic::AssertUnwindSafe(async {
            let mut open = fixture.open().await?;
            Fixture::ready(&mut open).await?;
            target = Some(open.target.clone());
            let owner = fixture
                .runtime
                .sessions
                .get(&crate::SessionId::new(open.target.session_id.clone())?)
                .context("session owner")?;
            let resources = owner
                .resident_acp(&open.target.thread_id)?
                .context("ACP resources")?;
            let identity = fixture
                .runtime
                .agent_facility
                .product_events
                .agent_execution_identity(&open.target.thread_id)
                .context("member identity")?
                .0;
            let host = owner.acp_agent_host(
                &identity,
                &resources,
                &fixture.runtime.config_runtime.agent_profiles_snapshot()?,
                fixture.runtime.config_runtime.read()?.config.delegation,
            )?;
            let execution = WorkspaceExecutionBinding::new(
                executor.clone(),
                root.to_str().context("business root")?,
            )?;
            let files = SessionFiles::new(&open.target.thread_id);
            pl_tool::workspace::prepare_session_files(&execution.files(), &files).await?;
            let mut config = fixture.runtime.config_runtime.read()?.config;
            config.runtime.tool_capabilities.git = true;
            let binding = PreparedAcpWorkspace {
                workspace: ToolWorkspace::new(
                    AgentWorkspace::local(&root).with_session_files(files),
                ),
                execution: execution.clone(),
                environment: ExecutionEnvironment::for_ssh(
                    ExecutionOs::Linux,
                    ShellDialect::Bash,
                    "/bin/bash",
                ),
                skills: None,
                lsp: None,
                remote: Some(SshWorkspaceBinding {
                    profile: Arc::new(SshServerProfile {
                        alias: "in-process-helper".into(),
                        host_name: "fixture".into(),
                        port: 22,
                        username: "fixture".into(),
                        identity_file: None,
                    }),
                    execution: execution.clone(),
                    execution_environment: ExecutionEnvironment::for_ssh(
                        ExecutionOs::Linux,
                        ShellDialect::Bash,
                        "/bin/bash",
                    ),
                }),
                store: crate::resource_store::FileResourceStore::new(
                    fixture
                        .runtime
                        .store
                        .session_resources_dir_for(&fixture.workspace.id, &open.target.thread_id)?,
                ),
                host_scratch: fixture
                    .runtime
                    .store
                    .session_scratch_dir_for(&fixture.workspace.id, &open.target.thread_id)?,
            };
            let mut workspace = SshWorkspaceMcp {
                fixture: &fixture,
                root,
                target: open.target,
                host,
                caller: identity.agent_id,
                cancellation: resources.cancellation.clone(),
                executor: executor.clone(),
                binding,
                config,
                services: &mut services,
            };
            check(&mut workspace).await
        })
        .catch_unwind()
        .await;
        let mut cleanup = Ok(());
        for (mut service, tools) in services {
            if let Err(error) = tools.close().await {
                cleanup = cleanup.and(Err(error));
            }
            if let Err(error) = service.close().await {
                cleanup = cleanup.and(Err(error));
            }
        }
        if let Some(target) = target {
            match fixture.runtime.close_acp_session(target).await {
                Ok(close) if close.local_complete => {}
                Ok(close) => cleanup = cleanup.and(Err(anyhow::anyhow!("ACP close: {close:?}"))),
                Err(error) => cleanup = cleanup.and(Err(error)),
            }
        }
        let closed = executor.close().await;
        let helper = tokio::time::timeout(Duration::from_secs(5), helper).await;
        let shutdown = fixture.runtime.shutdown_runtime().await;
        result.unwrap_or_else(|panic| std::panic::resume_unwind(panic))?;
        cleanup?;
        closed?;
        helper???;
        shutdown?;
        Ok(())
    }

    #[tokio::test]
    async fn ssh_workspace_mcp_reads_typed_content_without_exec() -> Result<()> {
        use base64::{Engine as _, engine::general_purpose::STANDARD};

        with_ssh_workspace(|h| {
            Box::pin(async move {
                let mut config = h.config.clone();
                config.runtime.tool_capabilities.exec = false;
                let mut peer = h.start(&config, h.binding.clone()).await?;
                let mut png = std::io::Cursor::new(Vec::new());
                image::DynamicImage::ImageRgb8(image::RgbImage::from_pixel(
                    10,
                    12,
                    image::Rgb([18, 91, 144]),
                ))
                .write_to(&mut png, image::ImageFormat::Png)?;
                tokio::fs::write(h.root.join("plot"), png.into_inner()).await?;
                tokio::fs::write(h.root.join("notes.txt"), "远端内容\n").await?;
                tokio::fs::write(h.root.join("large.txt"), vec![b'x'; 256 * 1024 + 1]).await?;
                let outside = h.root.parent().context("fixture parent")?;
                tokio::fs::write(outside.join("outside.txt"), "outside").await?;
                std::os::unix::fs::symlink(outside, h.root.join("escape"))?;

                let text = peer
                    .request(
                        "tools/call",
                        json!({"name":"anywork_read_text_file","arguments":{"path":"notes.txt"}}),
                    )
                    .await?;
                ensure!(text["result"]["content"] == json!([{"type":"text","text":"远端内容\n"}]));
                ensure!(text["result"].get("structuredContent").is_none());

                let image = peer
                    .request(
                        "tools/call",
                        json!({"name":"anywork_view_image","arguments":{"path":"plot"}}),
                    )
                    .await?;
                let blocks = image["result"]["content"]
                    .as_array()
                    .context("image response")?;
                ensure!(
                    blocks.len() == 1
                        && blocks[0]["type"] == "image"
                        && blocks[0]["mimeType"] == "image/png"
                );
                ensure!(image["result"].get("structuredContent").is_none());
                let pixels = image::load_from_memory(
                    &STANDARD.decode(blocks[0]["data"].as_str().context("image data")?)?,
                )?
                .into_rgb8();
                ensure!(
                    pixels.dimensions() == (10, 12) && pixels.get_pixel(0, 0).0 == [18, 91, 144]
                );

                for (name, path) in [
                    ("anywork_read_text_file", "large.txt"),
                    ("anywork_read_text_file", "escape/outside.txt"),
                    ("anywork_view_image", "notes.txt"),
                ] {
                    let failed = peer.completed_tool(name, json!({"path":path})).await?;
                    ensure!(
                        failed.is_error && failed.value["error"].is_string(),
                        "{name} should reject {path}"
                    );
                }
                Ok(())
            })
        })
        .await
    }

    #[tokio::test]
    async fn ssh_workspace_mcp_enforces_host_admission_paths_and_tool_capabilities() -> Result<()> {
        with_ssh_workspace(|h| Box::pin(async move {
            let forged = pl_tool::collaboration::control::AgentCallContext {
                caller: crate::AgentId::new("forged-agent")?, call_id: "not-a-transport-id".into(), cancellation: CancellationToken::new(),
            };
            ensure!(h.host.authorize_workspace_call(&forged).await.is_err(), "forged caller acquired workspace tools");
            let mut remote_project = h.fixture.workspace.clone();
            remote_project.ssh_alias = Some("in-process-helper".into());
            let protocol_cwd = h.fixture.runtime.thread_factory.prepare_acp_protocol_cwd(
                &h.target.thread_id, &remote_project, "/not-a-host-directory/business-root", None,
            ).await?;
            ensure!(std::path::Path::new(&protocol_cwd).is_dir() && protocol_cwd.ends_with("/acp-cwd"));
            ensure!(!std::path::Path::new("/not-a-host-directory/business-root").exists());
            ensure!(h.fixture.runtime.thread_factory.prepare_acp_protocol_cwd(
                &h.target.thread_id, &remote_project, "/not-a-host-directory/business-root", Some(&h.fixture.workspace.path),
            ).await.is_err(), "load accepted a business root as host protocol cwd");
            let mut peer = h.start_default().await?;
            let config = h.config.clone();
            let catalog = peer.request("tools/list", json!({})).await?;
            let catalog = catalog["result"]["tools"].as_array().context("catalog")?;
            ensure!(catalog.iter().any(|tool| tool["name"] == "anywork_exec_command"));
            ensure!(!catalog.iter().any(|tool| tool["name"] == "anywork_exec" || tool["name"] == "anywork_sleep"));
            let patch = catalog.iter().find(|tool| tool["name"] == "anywork_apply_patch").context("patch declaration")?;
            ensure!(patch["inputSchema"]["properties"]["input"]["type"] == "string");

            // Wait for each operation to finish before sending a dependent request.
            peer.completed_value("anywork_create_directory", json!({"path":"src"})).await?;
            peer.completed_value("anywork_write_file", json!({"path":"src/file.txt","mode":"create","content":"before\n"})).await?;
            peer.completed_value("anywork_apply_patch", json!({"input":"*** Begin Patch\n*** Update File: src/file.txt\n@@\n-before\n+after\n*** End Patch"})).await?;
            let stat = peer.completed_value("anywork_stat_path", json!({"path":"src/file.txt"})).await?;
            ensure!(stat["exists"] == true && stat["type"] == "file" && stat["len"] == 6, "stat result: {stat}");
            peer.completed_value("anywork_copy_path", json!({"from":"src/file.txt","to":"copy.txt","collision":"failIfExists"})).await?;
            peer.completed_value("anywork_move_path", json!({"from":"copy.txt","to":"moved.txt","collision":"failIfExists"})).await?;
            peer.completed_value("anywork_delete_path", json!({"path":"moved.txt","mode":"file"})).await?;
            ensure!(tokio::fs::read_to_string(h.root.join("src/file.txt")).await? == "after\n");
            ensure!(!std::path::Path::new(&h.fixture.workspace.path).join("src/file.txt").exists(), "file tool used ACP host cwd");
            tokio::fs::create_dir(h.fixture.home.path().join("outside")).await?;
            std::os::unix::fs::symlink(h.fixture.home.path().join("outside"), h.root.join("escape"))?;
            let denied = peer.completed_tool("anywork_write_file", json!({"path":"escape/forbidden","content":"bad","mode":"create"})).await?;
            ensure!(denied.is_error && !h.fixture.home.path().join("outside/forbidden").exists());
            let git = peer.completed_value("anywork_git_workspace_info", json!({})).await?;
            ensure!(git["worktree"] == h.root.to_str().context("Git root")?);

            // Disabling commands does not turn file permission into unrestricted host access.
            let mut file_config = config.clone();
            file_config.runtime.tool_capabilities.exec = false;
            file_config.runtime.tool_capabilities.git = false;
            file_config.runtime.permission_mode = crate::approval::PermissionMode::FullAccess;
            let mut files_peer = h.start(&file_config, h.binding.clone()).await?;
            let denied = files_peer.request("tools/call", json!({"name":"anywork_exec_command","arguments":{"command":"false"}})).await?;
            ensure!(denied["error"]["code"] == -32602);
            let denied = files_peer.completed_tool("anywork_write_file", json!({"path":h.fixture.home.path().join("outside/full-access-forbidden"),"content":"bad","mode":"create"})).await?;
            ensure!(denied.is_error && !h.fixture.home.path().join("outside/full-access-forbidden").exists());
            h.executor.close().await?;
            let stale = peer.completed_tool("anywork_stat_path", json!({"path":"src/file.txt"})).await?;
            ensure!(stale.is_error, "stale execution binding silently rebound");
            Ok(())
        })).await
    }

    #[tokio::test]
    async fn ssh_workspace_mcp_isolates_owned_tasks_and_retains_command_output() -> Result<()> {
        with_ssh_workspace(|h| Box::pin(async move {
            let mut peer = h.start_default().await?;
            let mut files_peer = h.start_default().await?;
            let command = peer.tool("anywork_exec_command", json!({"command":"printf ready; cat; printf done","interactive":true})).await?;
            let task = command["taskId"].as_str().context("running exec receipt")?.to_owned();
            let foreign = files_peer.request("tools/call", json!({"name":"anywork_get_tool_task","arguments":{"taskId":task,"resultCursor":0}})).await?;
            ensure!(foreign["result"]["isError"] == true, "another task owner accepted an original receipt from this instance");
            let mut input = peer.tool("anywork_write_stdin", json!({"taskId":task,"chars":"input\n","closeStdin":true})).await?;
            if input["status"] == "running" {
                let input_task = input["taskId"].as_str().context("stdin operation receipt")?.to_owned();
                input = peer.task_result(&input_task).await?;
            }
            ensure!(input["targetTaskId"] == task && input["inputReceipt"]["acceptedBytes"] == 6, "stdin did not use the real exec receipt: {input}");
            let result = peer.task_result(&task).await?;
            ensure!(result["stdout"]["content"].as_str().context("stdout")?.contains("readyinput\ndone"));
            let wrong = peer.completed_tool("anywork_write_stdin", json!({"taskId":"task:foreign-instance","chars":"do-not-send"})).await?;
            ensure!(wrong.is_error, "foreign task stdin succeeded");

            let mut output = peer.tool("anywork_exec_command", json!({"command":"head -c 70000 /dev/zero | tr '\\0' x","maxOutputChars":64})).await?;
            if output["status"] == "running" {
                let task = output["taskId"].as_str().context("output command receipt")?.to_owned();
                output = peer.task_result(&task).await?;
            }
            ensure!(output["stdout"]["wasTruncated"] == true && output["stdout"]["content"].as_str().context("preview")?.len() <= 64, "unexpected output preview: {output}");
            let capture = output["stdoutFile"].as_str().context("capture path")?;
            ensure!(tokio::fs::metadata(h.root.join(capture)).await?.len() == 70000);
            let cancelled = peer.tool("anywork_exec_command", json!({"command":"cat","interactive":true})).await?;
            let cancelled = cancelled["taskId"].as_str().context("cancellable receipt")?;
            peer.tool("anywork_cancel_tool_task", json!({"taskId":cancelled})).await?;
            let ready = peer.tool("anywork_wait", json!({"taskIds":[cancelled],"timeoutMs":30000})).await?;
            ensure!(ready["tasks"][0]["status"] == "cancelled");

            Ok(())
        })).await
    }

    #[tokio::test]
    async fn ssh_workspace_mcp_request_cancellation_preserves_accepted_command() -> Result<()> {
        with_ssh_workspace(|h| Box::pin(async move {
            let mut peer = h.start_default().await?;
            // Official MCP cancellation ends the request observation, not its admitted command.
            let request_id = peer.next_id;
            let mut request_peer = peer.clone();
            peer.next_id += 1;
            let pending = tokio::spawn(async move {
                request_peer.request("tools/call", json!({"name":"anywork_exec_command","arguments":{"command":"printf accepted > started; while test ! -e release; do sleep 0.01; done; printf completed > completed"}})).await
            });
            tokio::time::timeout(Duration::from_secs(5), async {
                while !h.root.join("started").exists() { tokio::task::yield_now().await; }
            }).await?;
            peer.cancel_request(request_id).await?;
            pending.abort();
            let _ = pending.await;
            tokio::fs::write(h.root.join("release"), b"go").await?;
            tokio::time::timeout(Duration::from_secs(5), async {
                while !h.root.join("completed").exists() { tokio::task::yield_now().await; }
            }).await?;
            let listed = peer.tool("anywork_list_tool_tasks", json!({})).await?;
            let listed = listed.as_array().context("task list")?;
            let running = listed.iter().filter_map(|task| task["taskId"].as_str()).map(str::to_owned).collect::<Vec<_>>();
            peer.tool("anywork_wait", json!({"taskIds":running,"timeoutMs":30000})).await?;
            Ok(())
        })).await
    }

    #[tokio::test]
    async fn ssh_workspace_mcp_repairs_capture_without_replaying_command() -> Result<()> {
        with_ssh_workspace(|h| Box::pin(async move {
            let config = h.config.clone();
            // Retention failure owns the original capture and retries storage, not execution.
            let blocked = h.fixture.home.path().join("blocked-resource-store");
            tokio::fs::write(&blocked, b"block directory creation").await?;
            let binding = PreparedAcpWorkspace {
                store: crate::resource_store::FileResourceStore::new(blocked.clone()),
                ..h.binding.clone()
            };
            let mut failed_peer = h.start(&config, binding).await?;
            let failing = h.services.last().context("failing workspace tools")?.1.clone();
            let response = failed_peer.request("tools/call", json!({"name":"anywork_exec_command","arguments":{"command":"printf once >> mutation-count; printf archive-output"}})).await?;
            ensure!(response["error"].is_null(), "MCP protocol failure: {response}");
            let result = &response["result"];
            let receipt = &result["structuredContent"];
            let failed_task = receipt["taskId"].as_str().context("original task receipt")?;
            if receipt["status"] == "running" {
                ensure!(result["isError"] != true, "running tool reported failure: {response}");
                failed_peer.tool("anywork_wait", json!({"taskIds":[failed_task],"timeoutMs":30000})).await?;
            } else {
                ensure!(result["isError"] == true && receipt["resultArchiveError"].is_string(), "missing archive failure: {response}");
            }
            let before = failed_peer.tool("anywork_get_tool_task", json!({"taskId":failed_task,"resultCursor":0})).await?;
            ensure!(before["task"]["status"] == "failed" && before["archiveError"].is_string(), "task did not retain the archive failure: {before}");
            ensure!(before["result"]["content"].is_string(), "failed task lost its result: {before}");
            ensure!(failing.close().await.is_err(), "unretained command output was treated as closed");
            tokio::fs::remove_file(&blocked).await?;
            failing.close().await?;
            let after = failed_peer.tool("anywork_get_tool_task", json!({"taskId":failed_task,"resultCursor":0})).await?;
            ensure!(before["result"] == after["result"]);
            ensure!(after["outputRepairs"].as_array().is_some_and(|repairs| !repairs.is_empty()));
            ensure!(tokio::fs::read_to_string(h.root.join("mutation-count")).await? == "once", "archive repair reexecuted a mutation");

            Ok(())
        })).await
    }

    #[tokio::test]
    async fn acp_close_joins_owned_workspace_commands_before_releasing_usage() -> Result<()> {
        let fixture = Fixture::new("replay").await?;
        let mut target = None;
        let mut service = None;
        let result = async {
            let mut open = fixture.open().await?;
            Fixture::ready(&mut open).await?;
            target = Some(open.target.clone());
            let owner = fixture
                .runtime
                .sessions
                .get(&crate::SessionId::new(open.target.session_id.clone())?)
                .context("session owner")?;
            let resources = owner
                .resident_acp(&open.target.thread_id)?
                .context("ACP resources")?;
            let identity = owner
                .acp_identity(&open.target.thread_id)
                .context("member identity")?;
            let host = owner.acp_agent_host(
                &identity,
                &resources,
                &fixture.runtime.config_runtime.agent_profiles_snapshot()?,
                fixture.runtime.config_runtime.read()?.config.delegation,
            )?;
            // Normal ACP opening already owns the prepared workspace tools and usage lease.
            // Exercise that real owner rather than preparing a second test-only binding.
            let tools = resources
                .workspace_tools
                .get()
                .context("original prepared workspace tools")?
                .clone();
            let (transport, definition) = HostMcp::start_bound(
                host,
                identity.agent_id,
                resources.cancellation.clone(),
                true,
                None,
                Some(tools),
            )
            .await?;
            service = Some(transport);
            let mut peer = HttpMcp::from_definition(definition)?;
            peer.initialize().await?;
            let task = peer
                .tool(
                    "anywork_exec_command",
                    json!({"command":"printf '%s' $$ > owned-command-pid; cat","interactive":true}),
                )
                .await?;
            ensure!(task["taskId"].is_string());
            let pid = tokio::fs::read_to_string(
                std::path::Path::new(&fixture.workspace.path).join("owned-command-pid"),
            )
            .await?;
            ensure!(std::path::Path::new(&format!("/proc/{pid}")).exists());
            let closed = fixture
                .runtime
                .close_acp_session(open.target.clone())
                .await?;
            ensure!(
                closed.local_complete,
                "workspace command prevented actual resource close: {closed:?}"
            );
            ensure!(
                !std::path::Path::new(&format!("/proc/{pid}")).exists(),
                "closed reported while its command was still alive"
            );
            ensure!(
                resources.close().await.local_complete,
                "retrying completed close recreated expired cleanup"
            );
            target = None;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        let mut cleanup = Ok(());
        if let Some(mut service) = service {
            cleanup = service.close().await;
        }
        if let Some(target) = target {
            match fixture.runtime.close_acp_session(target).await {
                Ok(close) if close.local_complete => {}
                Ok(close) => cleanup = cleanup.and(Err(anyhow::anyhow!("ACP close: {close:?}"))),
                Err(error) => cleanup = cleanup.and(Err(error)),
            }
        }
        let shutdown = fixture.runtime.shutdown_runtime().await;
        result?;
        cleanup?;
        shutdown?;
        Ok(())
    }

    #[tokio::test(flavor = "current_thread")]
    async fn ipc_calls_original_host_without_an_http_mcp_listener() -> Result<()> {
        use pl_studio_mcp::{HostInvocation, HostTools, ipc::IpcClient};

        let evidence = EvidenceBuffer::default();
        let _disabled = capture_evidence(evidence.clone(), "warn");
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
                .get(&crate::SessionId::new(open.target.session_id.clone())?)
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
                    .any(|tool| tool.tool_id == "anywork_list_agent_profiles"),
                "root directory was not delivered"
            );
            let listed = ipc
                .invoke(
                    HostInvocation {
                        tool_id: "anywork_list_agents".into(),
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
            ensure!(
                evidence_records(&evidence)?.is_empty(),
                "default warn filter emitted a host call payload"
            );
            // These fixtures stay on this OS thread, including the existing spawned handlers.
            let _enabled = capture_evidence(
                evidence.clone(),
                "warn,pl_studio_runtime::acp_host_call_evidence=trace",
            );
            let profiles = ipc
                .invoke(
                    HostInvocation {
                        tool_id: "anywork_list_agent_profiles".into(),
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
            let records = evidence_records(&evidence)?;
            ensure!(
                records.len() == 1,
                "one IPC call must emit one evidence record"
            );
            check_evidence(
                &records[0],
                &open.target.agent_id,
                "anywork_list_agent_profiles",
                &json!({}),
                &profiles.value,
                profiles.is_error,
            )?;
            let forged = json!({
                "callerAgentId":"forged-caller",
                "hostCallId":"forged-host-call",
                "requestId":"forged-mcp-request",
                "toolCallId":"forged-acp-tool",
                "nested":{"text":"first\n第二行","items":[1,true,null]}
            });
            let failed = ipc
                .invoke(
                    HostInvocation {
                        tool_id: "anywork_list_agents".into(),
                        arguments: forged.as_object().unwrap().clone(),
                    },
                    CancellationToken::new(),
                )
                .await?;
            ensure!(
                failed.is_error,
                "invalid original domain arguments unexpectedly succeeded"
            );
            let records = evidence_records(&evidence)?;
            ensure!(
                records.len() == 2,
                "two enabled IPC calls must emit two records"
            );
            check_evidence(
                &records[1],
                &open.target.agent_id,
                "anywork_list_agents",
                &forged,
                &failed.value,
                failed.is_error,
            )?;
            ensure!(records[0]["hostCallId"] != records[1]["hostCallId"]);
            ensure!(records[1]["hostCallId"] != forged["hostCallId"]);
            ensure!(records[1]["callerAgentId"] != forged["callerAgentId"]);
            ensure!(
                service
                    .as_ref()
                    .unwrap()
                    .observed_counter()
                    .load(std::sync::atomic::Ordering::Acquire)
                    == 3,
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

    #[tokio::test(flavor = "current_thread")]
    async fn http_auth_tools_and_instance_shutdown_are_isolated() -> Result<()> {
        let evidence = EvidenceBuffer::default();
        // Match the IPC test's warn -> TRACE scopes. Keeping both dispatches alive
        // prevents uncaptured concurrent calls from caching this shared callsite as
        // never through tracing-core's single-dispatch fast path.
        let _baseline = capture_evidence(evidence.clone(), "warn");
        let _capture = capture_evidence(
            evidence.clone(),
            "warn,pl_studio_runtime::acp_host_call_evidence=trace",
        );
        let fixture = Fixture::new("replay").await?;
        let mut target = None;
        let mut services = Vec::new();
        let result = async {
            save_acp_child_profile(&fixture)?;
            let mut open = fixture.open().await?;
            Fixture::ready(&mut open).await?;
            target = Some(open.target.clone());
            let target = target.as_ref().context("published ACP target")?;

            let owner = fixture
                .runtime
                .sessions
                .get(&crate::SessionId::new(target.session_id.clone())?)
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
            let spawned = host
                .spawn(
                    AgentCallContext {
                        caller: identity.agent_id.clone(),
                        call_id: "catalog-child".into(),
                        cancellation: CancellationToken::new(),
                    },
                    serde_json::from_value(json!({
                        "profileId": "acp-child",
                        "taskSummary": "Inspect the child tool catalog",
                        "message": "Complete this isolated catalog check"
                    }))?,
                )
                .await?;
            ensure!(
                spawned.message_error.is_none(),
                "child message was not accepted"
            );
            let child_identity = fixture
                .runtime
                .agent_facility
                .product_events
                .member_identity(
                    &identity.session_id,
                    &crate::AgentId::new(spawned.receipt.agent_id)?,
                )
                .context("published child identity")?;
            let child_resources = owner
                .resident_acp(child_identity.thread_id.as_str())?
                .context("published child resources")?;
            let child_host = owner.acp_agent_host(
                &child_identity,
                &child_resources,
                &profile_snapshot,
                selection,
            )?;
            let (second_service, second_definition) = HostMcp::start(
                child_host,
                child_identity.agent_id,
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
                    .json(
                        &json!({"jsonrpc":"2.0","id":index + 1,"method":"initialize","params":{}}),
                    )
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
            let records = evidence_records(&evidence)?;
            ensure!(
                records.len() == 1,
                "one HTTP call must emit one evidence record; observed {}, scoped TRACE enabled {}",
                records.len(),
                tracing::enabled!(
                    target: "pl_studio_runtime::acp_host_call_evidence",
                    tracing::Level::TRACE
                )
            );
            check_evidence(
                &records[0],
                &target.agent_id,
                "anywork_list_agent_profiles",
                &json!({}),
                &profiles["result"]["structuredContent"],
                false,
            )?;

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
            let denied = second
                .request(
                    "tools/call",
                    json!({"name": "anywork_list_agent_profiles", "arguments": {}}),
                )
                .await?;
            ensure!(
                denied["error"]["code"] == -32602,
                "an instance must reject calls outside its own prepared catalog"
            );
            ensure!(
                services[1]
                    .observed_counter()
                    .load(std::sync::atomic::Ordering::Acquire)
                    == 0,
                "a rejected tool name reached the domain binding"
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
            ensure!(
                evidence_records(&evidence)?.len() == 1,
                "catalog requests and rejected calls must not duplicate domain evidence"
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
                .get(&crate::SessionId::new(open.target.session_id.clone())?)
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
    async fn public_acp_open_answers_only_eligible_host_mcp_permissions() -> Result<()> {
        use crate::AcpSessionEvent;
        use pl_acp::session::schema::{ContentBlock, StopReason, TextContent};
        use std::time::Duration;

        struct PermissionCase {
            name: &'static str,
            pre_updates: Vec<Value>,
            tool_call: Value,
            options: Vec<Value>,
            auto_allowed: bool,
        }

        fn build_tool_call(
            id: &str,
            title: &str,
            tool_name: Option<&str>,
            meta: Option<Value>,
        ) -> Value {
            let mut map = serde_json::Map::new();
            map.insert("toolCallId".into(), json!(id));
            map.insert("title".into(), json!(title));
            if let Some(tool_name) = tool_name {
                map.insert("name".into(), json!(tool_name));
            }
            if let Some(meta) = meta {
                map.insert("_meta".into(), meta);
            }
            Value::Object(map)
        }

        let fixture = Fixture::new("mcp-permission").await?;
        let result = async {
            let mut open = fixture.open().await?;
            Fixture::ready(&mut open).await?;
            let observation = open.observation.as_mut().context("original observation")?;
            let once = json!({"optionId":"this-call", "kind":"allow_once", "name":"Allow"});
            let always = json!({"optionId":"remember", "kind":"allow_always", "name":"Remember"});
            let reject = json!({"optionId":"deny", "kind":"reject_once", "name":"Deny"});
            let standard = || vec![always.clone(), reject.clone(), once.clone()];
            let agy_name = "mcp_anywork_anywork_list_agents";
            let cases = vec![
                PermissionCase {
                    name: "eligible host tool auto-allows once",
                    pre_updates: Vec::new(),
                    tool_call: build_tool_call(
                        "eligible host tool auto-allows once",
                        agy_name,
                        Some(agy_name),
                        None,
                    ),
                    options: standard(),
                    auto_allowed: true,
                },
                PermissionCase {
                    name: "title is not a tool identity",
                    pre_updates: Vec::new(),
                    tool_call: build_tool_call(
                        "title is not a tool identity",
                        "anywork_anywork_exec_command",
                        None,
                        None,
                    ),
                    options: standard(),
                    auto_allowed: false,
                },
                PermissionCase {
                    name: "duplicate allow option is not automatic",
                    pre_updates: Vec::new(),
                    tool_call: build_tool_call(
                        "duplicate allow option is not automatic",
                        agy_name,
                        Some(agy_name),
                        None,
                    ),
                    options: vec![
                        once.clone(),
                        json!({"optionId":"this-call", "kind":"reject_once", "name":"Deny"}),
                    ],
                    auto_allowed: false,
                },
            ];

            for PermissionCase {
                name: case,
                pre_updates,
                tool_call,
                options,
                auto_allowed,
            } in cases
            {
                std::fs::write(
                    fixture.home.path().join("permission-request.json"),
                    serde_json::to_vec(&json!({
                        "preUpdates": pre_updates,
                        "toolCall": tool_call,
                        "options": options,
                    }))?,
                )?;
                let run = fixture
                    .runtime
                    .prompt_acp_session(
                        open.target.clone(),
                        vec![ContentBlock::Text(TextContent::new(case))],
                    )
                    .await?;
                let mut manual = false;
                tokio::time::timeout(Duration::from_secs(5), async {
                    loop {
                        match observation.recv().await.context("ACP observation closed")? {
                            AcpSessionEvent::Permission { id, request } => {
                                ensure!(!auto_allowed, "{case} unexpectedly required confirmation");
                                ensure!(
                                    !manual && request.tool_call.tool_call_id.0.as_ref() == case
                                );
                                fixture
                                    .runtime
                                    .answer_acp_permission(open.target.clone(), id, None)
                                    .await?;
                                manual = true;
                            }
                            AcpSessionEvent::Completed { completed } => {
                                ensure!(
                                    completed.run == run
                                        && completed.result?.stop_reason == StopReason::EndTurn
                                );
                                return Ok::<_, anyhow::Error>(());
                            }
                            AcpSessionEvent::Gap { gap } => {
                                anyhow::bail!("ACP observation gap: {gap:?}")
                            }
                            _ => {}
                        }
                    }
                })
                .await
                .with_context(|| format!("{case} did not complete"))??;
                ensure!(
                    manual != auto_allowed,
                    "unexpected permission event for {case}"
                );
                let outcome: Value = serde_json::from_slice(&std::fs::read(
                    fixture.home.path().join("permission-outcome.json"),
                )?)?;
                let expected = if auto_allowed {
                    json!({"outcome":"selected", "optionId":"this-call"})
                } else {
                    json!({"outcome":"cancelled"})
                };
                assert_eq!(outcome, expected, "{case}");
            }
            let close = fixture.runtime.close_acp_session(open.target).await?;
            ensure!(close.local_complete, "ACP close: {close:?}");
            Ok::<_, anyhow::Error>(())
        }
        .await;
        let shutdown = fixture.runtime.shutdown_runtime().await;
        result?;
        shutdown?;
        Ok(())
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
                .get(&crate::SessionId::new(open.target.session_id.clone())?)
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
            let child_id = spawned["result"]["structuredContent"]["agentId"]
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

            let child_agent = crate::AgentId::new(child_id.clone())?;
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

    #[tokio::test]
    async fn host_mcp_exposes_acp_workflow_and_plan_tools_with_forced_transitions_and_child_isolation()
    -> Result<()> {
        use crate::AcpSessionEvent;
        use crate::studio::runtime::acp_business::AcpWorkflowPlanOwner;
        use std::time::Duration;
        use tokio::time::timeout;

        let fixture = Fixture::new("normal").await?;
        let mut open = fixture.open().await?;
        let target = open.target.clone();
        Fixture::ready(&mut open).await?;
        open.completion.wait().await?;

        // Trigger initial turn reconciliation so a live workflow run starts at `triage`.
        fixture
            .runtime
            .prompt_acp_session(
                target.clone(),
                vec![crate::acp_schema::ContentBlock::Text(
                    crate::acp_schema::TextContent::new("start turn"),
                )],
            )
            .await?;
        timeout(Duration::from_secs(10), async {
            let observer = open.observation.as_mut().context("observer")?;
            loop {
                match observer.recv().await.context("stream ended")? {
                    AcpSessionEvent::Completed { .. } => return Ok::<_, anyhow::Error>(()),
                    AcpSessionEvent::Failed { error } => anyhow::bail!("ACP failed: {error:?}"),
                    _ => {}
                }
            }
        })
        .await??;

        let owner = fixture
            .runtime
            .sessions
            .get(&crate::SessionId::new(target.session_id.clone())?)
            .context("session owner")?;
        let resources = owner
            .resident_acp(&target.thread_id)?
            .context("acp resources")?;
        let wp = resources
            .workflow_plan
            .get()
            .cloned()
            .context("workflow_plan owner")?;
        let compiled_prompt = wp
            .compiled_mode_instructions()
            .context("compiled mode prompt")?;
        ensure!(compiled_prompt.contains("anywork_workflow_transition"));
        ensure!(compiled_prompt.contains("anywork_plan_transition"));

        let identity = fixture
            .runtime
            .agent_facility
            .product_events
            .agent_execution_identity(&target.thread_id)
            .context("root identity")?
            .0;
        let profiles = fixture.runtime.config_runtime.agent_profiles_snapshot()?;
        let delegation = fixture.runtime.config_runtime.read()?.config.delegation;
        let host = owner.acp_agent_host(&identity, &resources, &profiles, delegation)?;
        let (mut root_service, root_def) = HostMcp::start_with_workflow(
            host,
            identity.agent_id.clone(),
            CancellationToken::new(),
            true,
            None,
            Some(wp.clone()),
        )
        .await?;
        let mut root_peer = HttpMcp::from_definition(root_def)?;
        root_peer.initialize().await?;
        let root_tools = root_peer.request("tools/list", json!({})).await?;
        let root_names: Vec<String> = root_tools["result"]["tools"]
            .as_array()
            .context("root tools")?
            .iter()
            .filter_map(|t| t["name"].as_str().map(str::to_owned))
            .collect();
        for expected in [
            "anywork_plan_current",
            "anywork_plan_next",
            "anywork_plan_history",
            "anywork_plan_transition",
            "anywork_workflow_current",
            "anywork_workflow_next",
            "anywork_workflow_graph",
            "anywork_workflow_history",
            "anywork_workflow_transition",
            "anywork_workflow_restart",
        ] {
            ensure!(
                root_names.iter().any(|name| name == expected),
                "root ACP catalog missing `{expected}`: {root_names:?}"
            );
        }

        // Child ACP agent gets independent `anywork_plan_*` tools and NO `anywork_workflow_*` tools.
        let child_dir = tempfile::tempdir()?;
        let child_wp = AcpWorkflowPlanOwner::load_or_init(
            "child-thread".into(),
            false,
            child_dir.path().to_path_buf(),
            fixture.runtime.thread_modes.clone(),
            None,
        )
        .await?;
        let child_host = owner.acp_agent_host(&identity, &resources, &profiles, delegation)?;
        let (mut child_service, child_def) = HostMcp::start_with_workflow(
            child_host,
            identity.agent_id.clone(),
            CancellationToken::new(),
            false,
            None,
            Some(child_wp),
        )
        .await?;
        let mut child_peer = HttpMcp::from_definition(child_def)?;
        child_peer.initialize().await?;
        let child_tools = child_peer.request("tools/list", json!({})).await?;
        let child_names: Vec<String> = child_tools["result"]["tools"]
            .as_array()
            .context("child tools")?
            .iter()
            .filter_map(|t| t["name"].as_str().map(str::to_owned))
            .collect();
        for expected in [
            "anywork_plan_current",
            "anywork_plan_next",
            "anywork_plan_history",
            "anywork_plan_transition",
        ] {
            ensure!(child_names.iter().any(|name| name == expected));
        }
        ensure!(
            !child_names
                .iter()
                .any(|name| name.starts_with("anywork_workflow_")),
            "child ACP agent unexpectedly exposed workflow tools: {child_names:?}"
        );

        // Read initial workflow state (`triage`), test non-forced invalid jump returns rich hints.
        let current = root_peer
            .tool("anywork_workflow_current", json!({}))
            .await?;
        let run_id = current["runId"].as_str().context("runId")?.to_owned();
        let rev = current["revision"].as_u64().context("revision")?;
        ensure!(current["currentStateId"] == "triage");

        let rejected = root_peer
            .tool(
                "anywork_workflow_transition",
                json!({
                    "expectedRunId": run_id,
                    "expectedRevision": rev,
                    "expectedStateId": "triage",
                    "targetStateId": "reviewing",
                    "completion": { "reason": "skip", "summary": "bad", "evidence": ["test"] }
                }),
            )
            .await?;
        ensure!(
            rejected["accepted"] == false && rejected["code"] == "transitionNotAllowed",
            "disallowed transition must be rejected when force=false: {rejected}"
        );
        let err_msg = rejected["error"]["message"].as_str().unwrap_or_default();
        ensure!(
            err_msg.contains("simple") && err_msg.contains("planning"),
            "diagnostic should list allowed transitions: {rejected}"
        );

        // Valid path: triage -> simple -> planning, then forced jump to completed.
        let to_simple = root_peer
            .tool(
                "anywork_workflow_transition",
                json!({
                    "expectedRunId": run_id,
                    "expectedRevision": rev,
                    "expectedStateId": "triage",
                    "targetStateId": "simple",
                    "completion": { "reason": "small scope", "summary": "start simple", "evidence": ["ok"] }
                }),
            )
            .await?;
        ensure!(
            to_simple["accepted"] == true && to_simple["snapshot"]["currentStateId"] == "simple"
        );
        let rev2 = to_simple["snapshot"]["revision"].as_u64().context("rev2")?;
        let escalate = root_peer
            .tool(
                "anywork_workflow_transition",
                json!({
                    "expectedRunId": run_id,
                    "expectedRevision": rev2,
                    "expectedStateId": "simple",
                    "targetStateId": "planning",
                    "completion": { "reason": "expanded scope", "summary": "escalate to planning", "evidence": ["ok"] }
                }),
            )
            .await?;
        ensure!(
            escalate["accepted"] == true && escalate["snapshot"]["currentStateId"] == "planning"
        );
        let rev3 = escalate["snapshot"]["revision"].as_u64().context("rev3")?;
        let forced = root_peer
            .tool(
                "anywork_workflow_transition",
                json!({
                    "expectedRunId": run_id,
                    "expectedRevision": rev3,
                    "expectedStateId": "planning",
                    "targetStateId": "completed",
                    "force": true,
                    "completion": { "reason": "override", "summary": "forced jump", "evidence": ["admin"] }
                }),
            )
            .await?;
        ensure!(
            forced["accepted"] == true
                && forced["forced"] == true
                && forced["snapshot"]["currentStateId"] == "completed"
        );

        // The transport fixture has no active prompt. Opening the Plan tool
        // catalog does not create an interaction or mutate either Plan.
        let root_plan = root_peer.tool("anywork_plan_current", json!({})).await?;
        ensure!(root_plan["state"] == "drafting" && root_plan["revision"] == 0);
        let child_plan = child_peer.tool("anywork_plan_current", json!({})).await?;
        ensure!(child_plan["state"] == "drafting" && child_plan["revision"] == 0);

        let snap = fixture.runtime.acp_session_snapshot(target.clone()).await?;
        let wf_state = snap.workflow_state.context("snapshot workflow_state")?;
        let wf_run = wf_state.run.context("snapshot workflow run")?;
        ensure!(wf_run.current_state_id == "completed" && wf_run.last_transition_forced);
        ensure!(
            wf_state.plan.context("snapshot plan")?.state
                == crate::plan_tool::AgentSessionPlanPhase::Drafting
        );

        root_service.close().await?;
        child_service.close().await?;
        fixture.runtime.close_acp_session(target).await?;
        fixture.runtime.shutdown_runtime().await?;
        Ok(())
    }
}

#[cfg(test)]
mod host_mcp_match {
    use std::collections::BTreeMap;

    use pl_acp::session::PermissionToolCall;
    use pl_agent_tool::ToolDefinition;

    use super::{HostBinding, inspect_host_mcp_meta, matches_host_mcp_tool_call, schema};

    fn catalog() -> BTreeMap<String, HostBinding> {
        let mut tools = BTreeMap::new();
        for name in ["list_agents", "wait_agent", "exec_command"] {
            let definition = ToolDefinition::text(name, "match catalog").expect("tool name");
            let projection = pl_studio_mcp::ToolProjection::prepare(
                &definition,
                pl_studio_mcp::JsonInput::Object,
                false,
            )
            .expect("tool projection");
            let declaration = projection.declaration().clone();
            let id = declaration.tool_id.clone();
            tools.insert(
                id,
                HostBinding {
                    declaration,
                    projection,
                    invoke: Box::new(|_, _, _| {
                        Box::pin(async { unreachable!("matcher catalog is not invoked") })
                    }),
                    close: Box::new(|| Box::pin(async { Ok(()) })),
                    closed: tokio::sync::Mutex::new(false),
                },
            );
        }
        tools
    }

    fn meta(value: serde_json::Value) -> schema::Meta {
        let mut meta = schema::Meta::new();
        for (key, item) in value.as_object().expect("meta object").clone() {
            meta.insert(key, item);
        }
        meta
    }

    #[test]
    fn matches_only_structural_host_tool_identity() {
        let tools = catalog();
        let listed = meta(serde_json::json!({
            "mcp": {"server": "anywork", "tool": "anywork_list_agents"},
            "is_mcp_tool_call": true,
        }));
        let waiting = meta(serde_json::json!({
            "mcp": {"server": "anywork", "tool": "anywork_wait_agent"},
            "is_mcp_tool_call": true,
        }));
        let flag_only = meta(serde_json::json!({"is_mcp_tool_call": true}));
        let other_server = meta(serde_json::json!({
            "mcp": {"server": "other", "tool": "anywork_list_agents"},
            "is_mcp_tool_call": true,
        }));
        let unknown_tool = meta(serde_json::json!({
            "mcp": {"server": "anywork", "tool": "anywork_unknown"},
            "is_mcp_tool_call": true,
        }));
        let rejected_flag = meta(serde_json::json!({
            "mcp": {"server": "anywork", "tool": "anywork_list_agents"},
            "is_mcp_tool_call": false,
        }));
        let cases = [
            (None, Some(&listed), true, "omitted name with host meta"),
            (
                Some("mcp_anywork_anywork_list_agents"),
                None,
                true,
                "antigravity separator",
            ),
            (
                Some("mcp__anywork__anywork_list_agents"),
                None,
                true,
                "claude separator",
            ),
            (
                Some("mcp:anywork:anywork_list_agents"),
                None,
                true,
                "colon separator",
            ),
            (
                Some("mcp/anywork/anywork_list_agents"),
                None,
                true,
                "slash separator",
            ),
            (
                Some("mcp.anywork.anywork_list_agents"),
                None,
                true,
                "dot separator",
            ),
            (
                Some("mcp-anywork-anywork_list_agents"),
                None,
                true,
                "hyphen separator",
            ),
            (
                Some("anywork_anywork_list_agents"),
                None,
                true,
                "server prefix",
            ),
            (
                Some("mcp_anywork_anywork_list_agents"),
                Some(&listed),
                true,
                "consistent name and meta",
            ),
            (
                Some("mcp_anywork_anywork_list_agents"),
                Some(&flag_only),
                true,
                "true flag without mcp object",
            ),
            (None, None, false, "absent identity"),
            (Some("anywork_list_agents"), None, false, "bare tool name"),
            (
                Some("mcp_anywork_anywork_list_agents_extra"),
                None,
                false,
                "trailing suffix",
            ),
            (
                Some("mcp_other_anywork_list_agents"),
                None,
                false,
                "other server in name",
            ),
            (None, Some(&other_server), false, "other server in meta"),
            (
                Some("mcp_anywork_anywork_unknown"),
                None,
                false,
                "unknown tool in name",
            ),
            (None, Some(&unknown_tool), false, "unknown tool in meta"),
            (
                Some("mcp_anywork_anywork_list_agents"),
                Some(&rejected_flag),
                false,
                "false mcp flag rejects a valid name",
            ),
            (
                Some("mcp_anywork_anywork_list_agents"),
                Some(&waiting),
                false,
                "name and meta tool mismatch",
            ),
            (
                Some("bash"),
                Some(&listed),
                false,
                "disallowed name with valid meta",
            ),
        ];
        for (name, meta, expected, label) in cases {
            assert_eq!(
                matches_host_mcp_tool_call(PermissionToolCall { name, meta }, &tools),
                expected,
                "{label}"
            );
        }
        assert!(
            matches!(
                inspect_host_mcp_meta(&listed, &tools),
                super::MetaMcpMatch::Matched("anywork_list_agents")
            ),
            "meta match must return the catalog tool, not the display title"
        );
    }
}

#[cfg(test)]
mod future_sizes {
    use super::*;
    use crate::thread_assembler::agent_wait::WaitAgentRequest;
    use pl_tool::collaboration::thread::{AgentCloseOptions, AgentControlHost, AgentSpawn};
    use rmcp::{RoleServer, ServerHandler, model::CallToolRequestParams, service::RequestContext};

    fn bounded<Input, F: std::future::Future + std::marker::Send>(
        _: impl FnOnce(Input) -> F,
    ) -> usize {
        std::mem::size_of::<F>()
    }

    #[test]
    fn host_mcp_handler_future_sizes() {
        bounded(
            |(handler, value, context): (&'static Handler, Value, AgentCallContext)| {
                handler.invoke_domain("anywork_wait_agent", value, context)
            },
        );
        let request = bounded(
            |(handler, request, context): (
                &'static HostMcpService<Handler>,
                CallToolRequestParams,
                RequestContext<RoleServer>,
            )| handler.call_tool(request, context),
        );
        bounded(
            |(host, context, request): (&'static AgentHost, AgentCallContext, AgentSpawn)| {
                host.spawn(context, request)
            },
        );
        bounded(|(host, context): (&'static AgentHost, AgentCallContext)| host.list(context));
        bounded(|(host, context): (&'static AgentHost, AgentCallContext)| {
            host.close(context, "child", AgentCloseOptions::default())
        });
        bounded(
            |(host, context, request): (&'static AgentHost, AgentCallContext, WaitAgentRequest)| {
                host.wait_agent(context, request)
            },
        );
        bounded(
            |(host, context, request): (
                &'static AgentHost,
                AgentCallContext,
                crate::ListDelegationModelsRequest,
            )| host.list_delegation_models(context, request),
        );
        bounded(
            |(host, context, request): (
                &'static AgentHost,
                AgentCallContext,
                crate::GetDelegationModelsRequest,
            )| host.get_delegation_models(context, request),
        );
        assert!(request <= 16 * 1024, "tool request inlines {request} bytes");
    }
}
