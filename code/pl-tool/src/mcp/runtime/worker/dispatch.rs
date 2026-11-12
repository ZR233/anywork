//! [`RuntimeWorker`] 的工具调用与资源查询分发,以及失败 session 标记。

use std::sync::Arc;
use std::time::Duration;

use futures::FutureExt;
use pl_protocol::{PureError, Result};
use rmcp::model::*;
use rmcp::service::ServiceError;
use serde_json::{Map, Value};
use tokio::sync::mpsc;

use super::super::{McpGeneration, ResourceOperation, RuntimeCommand};
use super::RuntimeWorker;
use super::redaction::McpErrorRedactor;
use super::tools::serialize_resource_result;
use crate::mcp::ConnectedMcp;
use crate::mcp::connector::{ConnectionIdentity, is_connection_failure};
use crate::mcp::health::McpAvailabilityKind;
use crate::unix_seconds;

type ResourceSession = (String, Arc<ConnectedMcp>, Duration, McpErrorRedactor);

impl RuntimeWorker {
    pub(super) fn spawn_tool_call(
        &mut self,
        generation: McpGeneration,
        server_id: String,
        raw_name: String,
        arguments: Value,
        reply: tokio::sync::oneshot::Sender<Result<CallToolResult>>,
    ) {
        let session = self.session(generation, &server_id);
        let commands = self.commands.clone();
        if let Some(state) = self.generations.get_mut(&generation) {
            state.leases += 1;
        }
        self.requests.push(
            async move {
                let result = match session {
                    Ok((session, request_timeout, redactor)) => session
                        .call_tool_timed(raw_name, arguments, request_timeout)
                        .await
                        .map_err(|error| {
                            request_error(error, &server_id, &session, &redactor, &commands)
                        }),
                    Err(error) => Err(error),
                };
                let _ = reply.send(result);
                generation
            }
            .boxed(),
        );
    }

    pub(super) fn spawn_resource_query(
        &mut self,
        generation: McpGeneration,
        server_id: Option<String>,
        operation: ResourceOperation,
        reply: tokio::sync::oneshot::Sender<Result<Value>>,
    ) {
        let sessions = self.sessions(generation, server_id.as_deref());
        let commands = self.commands.clone();
        if let Some(state) = self.generations.get_mut(&generation) {
            state.leases += 1;
        }
        self.requests.push(
            async move {
                let result = resource_query(sessions, operation, commands).await;
                let _ = reply.send(result);
                generation
            }
            .boxed(),
        );
    }

    fn session(
        &self,
        generation: McpGeneration,
        server_id: &str,
    ) -> Result<(Arc<ConnectedMcp>, Duration, McpErrorRedactor)> {
        if let Some(state) = self.generations.get(&generation) {
            state.ensure_active()?;
        }
        self.generations
            .get(&generation)
            .and_then(|generation| generation.servers.get(server_id))
            .and_then(|server| {
                (server.availability == McpAvailabilityKind::Available)
                    .then(|| server.session.clone())
                    .flatten()
                    .map(|session| (session, server.request_timeout, server.redactor.clone()))
            })
            .ok_or_else(|| PureError::ToolExecutionFailed {
                tool: "mcp".to_string(),
                error: format!(
                    "MCP server '{server_id}' is unavailable in generation {}",
                    generation.0
                ),
            })
    }

    fn sessions(
        &self,
        generation: McpGeneration,
        server_id: Option<&str>,
    ) -> Result<Vec<ResourceSession>> {
        let state =
            self.generations
                .get(&generation)
                .ok_or_else(|| PureError::ToolExecutionFailed {
                    tool: "mcp".to_string(),
                    error: format!("MCP generation {} is unavailable", generation.0),
                })?;
        state.ensure_active()?;
        match server_id {
            Some(server_id) => {
                let supports_resources = state
                    .servers
                    .get(server_id)
                    .is_some_and(|server| server.supports_resources);
                if !supports_resources {
                    return Err(PureError::ToolExecutionFailed {
                        tool: "mcp".to_string(),
                        error: format!(
                            "MCP server '{server_id}' does not declare the resources capability"
                        ),
                    });
                }
                let (session, request_timeout, redactor) = self.session(generation, server_id)?;
                Ok(vec![(
                    server_id.to_string(),
                    session,
                    request_timeout,
                    redactor,
                )])
            }
            None => Ok(state
                .servers
                .values()
                .filter_map(|server| {
                    (server.availability == McpAvailabilityKind::Available
                        && server.supports_resources)
                        .then(|| server.session.clone())
                        .flatten()
                        .map(|session| {
                            (
                                server.descriptor.id.clone(),
                                session,
                                server.request_timeout,
                                server.redactor.clone(),
                            )
                        })
                })
                .collect()),
        }
    }

    pub(super) fn mark_unavailable(
        &mut self,
        identity: &Arc<ConnectionIdentity>,
        server_id: &str,
        error: String,
    ) {
        let mut changed = false;
        for generation in self.generations.values_mut() {
            if let Some(server) = generation.servers.get_mut(server_id) {
                let same_session = server
                    .session
                    .as_ref()
                    .is_some_and(|session| Arc::ptr_eq(identity, &session.identity));
                if same_session && server.availability != McpAvailabilityKind::Unavailable {
                    server.availability = McpAvailabilityKind::Unavailable;
                    server.message = Some(error.clone());
                    server.last_checked_at = Some(unix_seconds());
                    changed = true;
                }
            }
        }
        if changed {
            self.emit_update();
        }
    }
}

async fn resource_query(
    sessions: Result<Vec<ResourceSession>>,
    operation: ResourceOperation,
    commands: mpsc::UnboundedSender<RuntimeCommand>,
) -> Result<Value> {
    let sessions = sessions?;
    let explicit = sessions.len() == 1;
    let mut values = Map::new();
    for (server_id, session, request_timeout, redactor) in sessions {
        let request = match &operation {
            ResourceOperation::ListResources { cursor } => {
                ClientRequest::ListResourcesRequest(ListResourcesRequest::with_param(
                    PaginatedRequestParams::default().with_cursor(cursor.clone()),
                ))
            }
            ResourceOperation::ListResourceTemplates { cursor } => {
                ClientRequest::ListResourceTemplatesRequest(
                    ListResourceTemplatesRequest::with_param(
                        PaginatedRequestParams::default().with_cursor(cursor.clone()),
                    ),
                )
            }
            ResourceOperation::ReadResource { uri } => ClientRequest::ReadResourceRequest(
                ReadResourceRequest::new(ReadResourceRequestParams::new(uri.clone())),
            ),
        };
        let result = session
            .request(request, request_timeout)
            .await
            .map_err(|error| request_error(error, &server_id, &session, &redactor, &commands))?;
        let value = match (&operation, result) {
            (
                ResourceOperation::ListResources { .. },
                ServerResult::ListResourcesResult(result),
            ) => serialize_resource_result(result),
            (
                ResourceOperation::ListResourceTemplates { .. },
                ServerResult::ListResourceTemplatesResult(result),
            ) => serialize_resource_result(result),
            (ResourceOperation::ReadResource { .. }, ServerResult::ReadResourceResult(result)) => {
                serialize_resource_result(result)
            }
            _ => Err(request_error(
                ServiceError::UnexpectedResponse,
                &server_id,
                &session,
                &redactor,
                &commands,
            )),
        }?;
        if explicit {
            return Ok(value);
        }
        values.insert(server_id, value);
    }
    Ok(Value::Object(values))
}

fn request_error(
    error: ServiceError,
    server_id: &str,
    session: &ConnectedMcp,
    redactor: &McpErrorRedactor,
    commands: &mpsc::UnboundedSender<RuntimeCommand>,
) -> PureError {
    let message = redactor.redact(error.to_string());
    if is_connection_failure(&error) {
        let _ = commands.send(RuntimeCommand::MarkUnavailable {
            identity: session.identity.clone(),
            server_id: server_id.to_owned(),
            error: message.clone(),
        });
    }
    PureError::ToolExecutionFailed {
        tool: server_id.to_owned(),
        error: message,
    }
}
