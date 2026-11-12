use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use lsp_server::{ErrorCode, Message, Request, Response};
use lsp_types::{
    ConfigurationParams, ProgressParams, ProgressToken, PublishDiagnosticsParams,
    WorkDoneProgressCreateParams,
};
use serde_json::Value;
use tokio::sync::{Mutex, broadcast};

use crate::driver::LspServerDriver;
use crate::runtime::{LspResult, LspRuntimeError, ResolvedLspServer};

use super::configuration::{workspace_configuration_response, workspace_folder};
use super::connection::LspClient;
use super::retry::is_content_modified_error;
use super::rpc::RpcClient;
use super::status::LspClientStatus;

impl LspClient {
    pub(super) fn spawn_dispatcher(
        &self,
        mut inbound: tokio::sync::mpsc::Receiver<LspResult<Message>>,
        rpc: RpcClient,
        generation: u64,
    ) {
        let diagnostics = self.diagnostics.clone();
        let status = self.status.clone();
        let updates = self.diagnostics.updates.clone();
        let driver = self.driver.clone();
        let server = self.server.clone();
        let style = self.path_style();
        let server_id = self.server.id.clone();
        let initialized = self.initialized.clone();
        let connection_alive = self.connection_alive.clone();
        let connection_generation = self.connection_generation.clone();
        self.retain_task(tokio::spawn(async move {
            while let Some(message) = inbound.recv().await {
                let message = match message {
                    Ok(message) => message,
                    Err(error) => {
                        record_last_error_status(&status, error.to_string()).await;
                        rpc.fail_pending(error.to_string()).await;
                        break;
                    }
                };
                match message {
                    Message::Request(request) => {
                        let response = respond_to_server_request(
                            request,
                            driver.as_ref(),
                            &server,
                            style,
                            &status,
                            &updates,
                        )
                        .await;
                        let _ = rpc.respond(response).await;
                    }
                    Message::Notification(notification) => match notification.method.as_str() {
                        "$/progress" => {
                            if let Ok(params) =
                                serde_json::from_value::<ProgressParams>(notification.params)
                                && apply_progress_status(&status, params).await
                            {
                                let _ = updates.send(());
                            }
                        }
                        "textDocument/publishDiagnostics" => {
                            if let Ok(params) = serde_json::from_value::<PublishDiagnosticsParams>(
                                notification.params,
                            ) {
                                diagnostics.publish(params).await;
                            }
                        }
                        _ => {}
                    },
                    Message::Response(response) => {
                        let result = response.response_result.clone().map_err(|error| {
                            LspRuntimeError::Server {
                                code: i64::from(error.code),
                                message: error.message,
                            }
                        });
                        if let Err(error) = &result
                            && !is_content_modified_error(error)
                            && record_last_error_status(&status, error.to_string()).await
                        {
                            let _ = updates.send(());
                        }
                        rpc.complete(response).await;
                    }
                }
            }
            if clear_progress_status(&status).await {
                let _ = updates.send(());
            }
            rpc.fail_pending(format!("{server_id} connection closed"))
                .await;
            if generation_is_current(&connection_generation, generation) {
                initialized.store(false, Ordering::Relaxed);
                connection_alive.store(false, Ordering::Release);
                let _ = updates.send(());
            }
        }));
    }
}

pub(crate) async fn respond_to_server_request(
    request: Request,
    driver: &dyn LspServerDriver,
    server: &ResolvedLspServer,
    style: crate::host::LspPathStyle,
    status: &Arc<Mutex<LspClientStatus>>,
    updates: &broadcast::Sender<()>,
) -> Response {
    let result = match request.method.as_str() {
        "workspace/configuration" => {
            let params = match serde_json::from_value::<ConfigurationParams>(request.params) {
                Ok(params) => params,
                Err(error) => {
                    return Response::new_err(
                        request.id,
                        ErrorCode::InvalidParams as i32,
                        error.to_string(),
                    );
                }
            };
            workspace_configuration_response(params, driver)
        }
        "workspace/workspaceFolders" => match workspace_folder(server, style) {
            Ok(folder) => serde_json::json!([folder]),
            Err(error) => {
                return Response::new_err(
                    request.id,
                    ErrorCode::InternalError as i32,
                    error.to_string(),
                );
            }
        },
        "window/workDoneProgress/create" => {
            let params =
                match serde_json::from_value::<WorkDoneProgressCreateParams>(request.params) {
                    Ok(params) => params,
                    Err(error) => {
                        return Response::new_err(
                            request.id,
                            ErrorCode::InvalidParams as i32,
                            error.to_string(),
                        );
                    }
                };
            if register_progress_token_status(status, params.token).await {
                let _ = updates.send(());
            }
            Value::Null
        }
        _ => {
            return Response::new_err(
                request.id,
                ErrorCode::MethodNotFound as i32,
                format!("unsupported LSP client method: {}", request.method),
            );
        }
    };
    Response::new_ok(request.id, result)
}

pub(crate) async fn apply_progress_status(
    status: &Arc<Mutex<LspClientStatus>>,
    params: ProgressParams,
) -> bool {
    status.lock().await.apply_progress(params)
}

pub(crate) async fn clear_progress_status(status: &Arc<Mutex<LspClientStatus>>) -> bool {
    status.lock().await.clear_progress()
}

pub(crate) async fn record_last_error_status(
    status: &Arc<Mutex<LspClientStatus>>,
    message: String,
) -> bool {
    status.lock().await.record_error(message)
}

async fn register_progress_token_status(
    status: &Arc<Mutex<LspClientStatus>>,
    token: ProgressToken,
) -> bool {
    status.lock().await.register_progress_token(token)
}

fn generation_is_current(current: &AtomicU64, generation: u64) -> bool {
    current.load(Ordering::Relaxed) == generation
}
