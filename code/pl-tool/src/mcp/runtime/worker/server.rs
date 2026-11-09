//! MCP 运行态 server 与 generation 结构,以及 descriptor/fingerprint 投影。

use std::collections::{BTreeMap, BTreeSet};
use std::hash::{Hash, Hasher};
use std::sync::Arc;
use std::time::Duration;

use pl_protocol::McpServerDescriptor;
use rmcp::model::Tool;
use serde_json::Value;

use super::super::{McpGeneration, McpResetScope, McpRuntimeToolDescriptor, McpToolSafetyHints};
use super::redaction::McpErrorRedactor;
use super::tools::{PROBE_TIMEOUT, configured_tool_timeout, serialize_optional};
use crate::approval::ToolEffect;
use crate::mcp::ConnectedMcp;
use crate::mcp::config::EffectiveMcpServerConfig;
use crate::mcp::config::McpServerConfig;
use crate::mcp::config::McpServerSourceKind;
use crate::mcp::config::{McpExecutionContext, McpServerTransport};
use crate::mcp::health::McpAvailabilityKind;
use crate::mcp::naming::assign_exposed_tool_names;
use crate::unix_seconds;

pub(super) struct RuntimeGeneration {
    pub(super) id: McpGeneration,
    pub(super) servers: BTreeMap<String, RuntimeServer>,
    pub(super) leases: usize,
    pub(super) retired: bool,
    pub(super) authorization: pl_core::tool::opaque::ToolAuthorization,
    authorization_scope: AuthorizationScope,
}

impl RuntimeGeneration {
    pub(super) fn empty(id: McpGeneration) -> Self {
        Self {
            id,
            servers: BTreeMap::new(),
            leases: 0,
            retired: false,
            authorization: pl_core::tool::opaque::ToolAuthorization::unique(),
            authorization_scope: AuthorizationScope::default(),
        }
    }

    /// Called only by the serial worker at publication, never on a retired generation.
    pub(super) fn freeze_authorization(&mut self, previous: &Self) {
        let scope = AuthorizationScope::from_servers(&self.servers);
        if scope == previous.authorization_scope {
            self.authorization = previous.authorization.clone();
        }
        self.authorization_scope = scope;
    }
}

/// Private, non-serialized and deliberately without Debug: it includes credential bindings.
#[derive(Default, PartialEq, Eq)]
struct AuthorizationScope {
    servers: BTreeMap<String, AuthorizedServer>,
    resource_assignments: BTreeSet<String>,
}

#[derive(PartialEq, Eq)]
struct AuthorizedServer {
    source: McpServerSourceKind,
    transport: McpServerTransport,
    command: Option<String>,
    args: Vec<String>,
    env: BTreeMap<String, String>,
    cwd: Option<String>,
    url: Option<String>,
    headers: BTreeMap<String, String>,
    bearer_token: Option<String>,
    bearer_token_env_var: Option<String>,
    execution_context: McpExecutionContext,
    effect: Option<ToolEffect>,
    /// Actual frozen dispatch identities, not schema or remote presentation hints.
    tools: BTreeMap<String, String>,
}

impl AuthorizationScope {
    fn from_servers(servers: &BTreeMap<String, RuntimeServer>) -> Self {
        let mut scope = Self::default();
        for (id, server) in servers {
            if server.availability != McpAvailabilityKind::Available {
                continue;
            }
            let configured = &server.configured;
            let target = &configured.config;
            scope.servers.insert(
                id.clone(),
                AuthorizedServer {
                    source: configured.source_kind,
                    transport: target.transport,
                    command: target.command.clone(),
                    args: target.args.clone(),
                    env: target.env.clone(),
                    cwd: target.cwd.clone(),
                    url: target.url.clone(),
                    headers: target.headers.clone(),
                    bearer_token: configured.bearer_token.clone(),
                    bearer_token_env_var: target.bearer_token_env_var.clone(),
                    execution_context: configured.execution_context.clone(),
                    effect: server.tool_effect,
                    tools: server
                        .tools
                        .iter()
                        .map(|tool| (tool.exposed_name.clone(), tool.raw_name.clone()))
                        .collect(),
                },
            );
            if server.supports_resources {
                scope.resource_assignments.insert(id.clone());
            }
        }
        scope
    }
}

pub(super) fn reset_failed(scope: &McpResetScope, generation: &RuntimeGeneration) -> bool {
    match scope {
        McpResetScope::Server { server_id } => generation
            .servers
            .get(server_id)
            .is_none_or(|server| server.availability == McpAvailabilityKind::Unavailable),
        McpResetScope::All => generation
            .servers
            .values()
            .any(|server| server.availability == McpAvailabilityKind::Unavailable),
    }
}

pub(super) struct RuntimeServer {
    configured: EffectiveMcpServerConfig,
    pub(super) descriptor: McpServerDescriptor,
    pub(super) fingerprint: u64,
    pub(super) availability: McpAvailabilityKind,
    pub(super) message: Option<String>,
    pub(super) last_checked_at: Option<i64>,
    pub(super) session: Option<Arc<ConnectedMcp>>,
    pub(super) definitions: Vec<Tool>,
    pub(super) tools: Vec<McpRuntimeToolDescriptor>,
    pub(super) supports_resources: bool,
    pub(super) request_timeout: Duration,
    pub(super) config: McpServerConfig,
    pub(super) tool_effect: Option<ToolEffect>,
    pub(super) redactor: McpErrorRedactor,
}

pub(super) struct AvailableRuntimeServer {
    pub(super) configured: EffectiveMcpServerConfig,
    pub(super) descriptor: McpServerDescriptor,
    pub(super) fingerprint: u64,
    pub(super) session: Arc<ConnectedMcp>,
    pub(super) definitions: Vec<Tool>,
    pub(super) supports_resources: bool,
    pub(super) request_timeout: Duration,
    pub(super) config: McpServerConfig,
    pub(super) tool_effect: Option<ToolEffect>,
    pub(super) redactor: McpErrorRedactor,
}

impl Clone for RuntimeServer {
    fn clone(&self) -> Self {
        Self {
            configured: self.configured.clone(),
            descriptor: self.descriptor.clone(),
            fingerprint: self.fingerprint,
            availability: self.availability,
            message: self.message.clone(),
            last_checked_at: self.last_checked_at,
            session: self.session.clone(),
            definitions: self.definitions.clone(),
            tools: self.tools.clone(),
            supports_resources: self.supports_resources,
            request_timeout: self.request_timeout,
            config: self.config.clone(),
            tool_effect: self.tool_effect,
            redactor: self.redactor.clone(),
        }
    }
}

impl RuntimeServer {
    /// The fingerprint is only a cache prefilter, never the equality proof for a binding.
    pub(super) fn matches_config(&self, next: &EffectiveMcpServerConfig) -> bool {
        self.configured.config == next.config
            && self.configured.status_kind == next.status_kind
            && self.configured.source_kind == next.source_kind
            && self.configured.bearer_token == next.bearer_token
            && self.configured.execution_context == next.execution_context
            && self.configured.tool_effect == next.tool_effect
    }

    pub(super) fn terminal(
        config: &EffectiveMcpServerConfig,
        fingerprint: u64,
        availability: McpAvailabilityKind,
        message: Option<String>,
    ) -> Self {
        Self {
            configured: config.clone(),
            descriptor: server_descriptor(config),
            fingerprint,
            availability,
            message,
            last_checked_at: None,
            session: None,
            definitions: Vec::new(),
            tools: Vec::new(),
            supports_resources: false,
            request_timeout: configured_tool_timeout(config.config.tool_timeout_secs),
            config: config.config.clone(),
            tool_effect: config.tool_effect,
            redactor: McpErrorRedactor::new(config),
        }
    }

    pub(super) fn available(input: AvailableRuntimeServer) -> Self {
        Self {
            configured: input.configured,
            descriptor: input.descriptor,
            fingerprint: input.fingerprint,
            availability: McpAvailabilityKind::Available,
            message: Some(format!("Available with {} tools", input.definitions.len())),
            last_checked_at: Some(unix_seconds()),
            session: Some(input.session),
            definitions: input.definitions,
            tools: Vec::new(),
            supports_resources: input.supports_resources,
            request_timeout: input.request_timeout,
            config: input.config,
            tool_effect: input.tool_effect,
            redactor: input.redactor,
        }
    }

    pub(super) fn unavailable(
        descriptor: McpServerDescriptor,
        fingerprint: u64,
        error: String,
        configured: EffectiveMcpServerConfig,
        redactor: McpErrorRedactor,
    ) -> Self {
        Self {
            config: configured.config.clone(),
            configured,
            descriptor,
            fingerprint,
            availability: McpAvailabilityKind::Unavailable,
            message: Some(error),
            last_checked_at: Some(unix_seconds()),
            session: None,
            definitions: Vec::new(),
            tools: Vec::new(),
            supports_resources: false,
            request_timeout: PROBE_TIMEOUT,
            tool_effect: None,
            redactor,
        }
    }
}

pub(super) fn assign_tool_descriptors(servers: &mut BTreeMap<String, RuntimeServer>) {
    let names = assign_exposed_tool_names(servers.iter().flat_map(|(server_id, server)| {
        server
            .definitions
            .iter()
            .map(move |definition| (server_id.as_str(), definition.name.as_ref()))
    }));
    let mut names = names.into_iter();
    for server in servers.values_mut() {
        server.tools = server
            .definitions
            .iter()
            .map(|definition| {
                let annotations = serialize_optional(&definition.annotations);
                let safety_hints = McpToolSafetyHints::parse(annotations.as_ref());
                // Remote display hints never grant local read/programmatic privileges.
                let effect = server.tool_effect;
                McpRuntimeToolDescriptor {
                    server_id: server.descriptor.id.clone(),
                    raw_name: definition.name.to_string(),
                    exposed_name: names.next().expect("every MCP tool receives a name"),
                    description: definition
                        .description
                        .as_deref()
                        .unwrap_or_default()
                        .to_string(),
                    input_schema: Value::Object(definition.input_schema.as_ref().clone()),
                    output_schema: definition
                        .output_schema
                        .as_ref()
                        .map(|schema| Value::Object(schema.as_ref().clone())),
                    annotations,
                    icons: serialize_optional(&definition.icons),
                    metadata: serialize_optional(&definition.meta),
                    safety_hints,
                    effect,
                }
            })
            .collect();
    }
}

pub(super) fn unique_sessions(servers: BTreeMap<String, RuntimeServer>) -> Vec<Arc<ConnectedMcp>> {
    let mut seen = BTreeSet::new();
    servers
        .into_values()
        .filter_map(|server| server.session)
        .filter(|session| seen.insert(Arc::as_ptr(session) as usize))
        .collect()
}

pub(super) fn server_descriptor(config: &EffectiveMcpServerConfig) -> McpServerDescriptor {
    McpServerDescriptor {
        id: config.id.clone(),
        source: config.source_kind.as_str().to_string(),
        transport: config.config.transport.as_str().to_string(),
        endpoint: config.config.endpoint_summary(),
        built_in: config.source_kind == McpServerSourceKind::BuiltIn,
    }
}

pub(super) fn server_fingerprint(server: &EffectiveMcpServerConfig) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    server.config.hash(&mut hasher);
    server.status_kind.as_str().hash(&mut hasher);
    server.source_kind.as_str().hash(&mut hasher);
    server.bearer_token.hash(&mut hasher);
    server.tool_effect.hash(&mut hasher);
    server.execution_context.hash(&mut hasher);
    hasher.finish()
}
