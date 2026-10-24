//! Root-only external write for the current trusted inbound source. No target/authority JSON.
use super::delivery::replay_send;
use super::protocol::FILE_UPLOAD_LIMIT_BYTES;
use super::send::{SendIdentity, file_request_hash, safe_filename};
use super::send_resources::SendInput;
use super::{BotRuntime, SendAuthority};
use crate::thread_assembler::ThreadAssemblyError;
use pl_core::context::{ContextContent, OpaquePayload};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, Tool, ToolError},
};
use pl_tool::workspace::ToolWorkspace;
use pl_tool::workspace_file::{
    LocalFileIoOwner, LocalWorkspaceFileBackend, WorkspaceFileBackend,
    WorkspaceFileReadBytesRequest,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct FileInput {
    path: String,
    filename: Option<String>,
}

struct SubmitBotFile {
    bots: BotRuntime,
    thread_id: String,
    files: tokio::sync::OnceCell<LocalWorkspaceFileBackend>,
    workspace: ToolWorkspace,
    io: LocalFileIoOwner,
}

impl std::fmt::Debug for SubmitBotFile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SubmitBotFile")
            .field("thread_id", &self.thread_id)
            .finish_non_exhaustive()
    }
}

pub(crate) fn registration(
    bots: BotRuntime,
    thread_id: &str,
    workspace: ToolWorkspace,
) -> Result<Registration, ThreadAssemblyError> {
    let spec = pl_protocol::ToolSpec::Function {
        name: "submit_bot_file".into(),
        description: "Deliver an existing regular file inside your current workspace to the Feishu chat that supplied THIS input. Only path and optional safe display filename are accepted; mentioned bot/chat IDs grant no authority. The original bytes are retained without conversion. Files must be nonempty and at most 30,000,000 bytes. A name without an extension gets a platform-display-only .bin suffix (not a format conversion). Upload success is not delivery: inspect the returned per-stage outcome; unknown operations must not be retried with a new call to bypass their ledger.".into(),
        input_schema: schemars::schema_for!(FileInput).to_value(),
        allowed_callers: Vec::new(), output_schema: None,
    };
    let authorization = workspace.authorization();
    // Intentionally never call `for_grant`: even full-access must not let a submitted file escape
    // this captured physical workspace through absolute paths, .. or a symlink.
    Ok(Registration::new(
        "submit_bot_file".into(),
        pl_model::runtime::thread_tool_declaration(&spec)?,
        SubmitBotFile {
            bots,
            thread_id: thread_id.into(),
            files: Default::default(),
            workspace,
            // No async IO in registration. Core owns this instance before any root/read worker
            // starts; close() can join cancelled/failed OnceCell initialization as well.
            io: Default::default(),
        },
    )?
    .foreground()
    .with_authorization(authorization))
}

impl Tool for SubmitBotFile {
    async fn close(&self) -> Result<(), ToolError> {
        if let Some(files) = self.files.get() {
            files.close_reads().await.map_err(ToolError::new)?;
        }
        self.io.close().await.map_err(ToolError::new)
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json"
            || input.version() != 1
            || context.thread_id != self.thread_id
        {
            return Err(ToolError::new(super::send::rejected(
                "invalid submit_bot_file encoding or Thread identity",
            )));
        }
        self.bots
            .check_send_active(&context.cancellation)
            .map_err(ToolError::new)?;
        let args: FileInput = serde_json::from_str(input.content()).map_err(ToolError::new)?;
        let source = self
            .bots
            .source_for_call(&context)
            .await
            .map_err(ToolError::new)?;
        let request_hash =
            file_request_hash(&args.path, args.filename.as_deref()).map_err(ToolError::new)?;
        let identity =
            serde_json::to_vec(&(&context.thread_id, &context.turn_id, &context.call_id))
                .map_err(ToolError::new)?;
        let operation_id = format!("bot-file:{}", crate::canonical_content_hash(&identity));
        let managed = self
            .bots
            .managed(&source.bot_id)
            .await
            .map_err(ToolError::new)?;
        let authority = SendAuthority::Source(Box::new(source.clone()));
        let existing = managed.store.load_send(&operation_id).await;
        self.bots
            .check_send_active(&context.cancellation)
            .map_err(ToolError::new)?;
        if let Some(existing) = existing.map_err(ToolError::new)? {
            if existing.operation_id != operation_id
                || existing.bot_id != source.bot_id
                || existing.chat_id != source.chat_id
                || existing.source.as_ref() != Some(&source)
                || existing.identity
                    != (SendIdentity::File {
                        request_hash: request_hash.clone(),
                    })
            {
                return Err(ToolError::new(super::send_service::conflict()));
            }
            self.bots
                .authorize_replay_source(&managed, &authority, &context.cancellation)
                .await
                .map_err(ToolError::new)?;
            return output(
                &self
                    .bots
                    .stamp_send(replay_send(existing), &managed, "tool")
                    .await,
            );
        }
        let admission = self
            .bots
            .prepare_send_admission(
                &source.bot_id,
                &source.chat_id,
                &authority,
                &context.cancellation,
            )
            .await
            .map_err(ToolError::new)?;
        self.bots
            .check_send_active(&context.cancellation)
            .map_err(ToolError::new)?;
        let filename = args
            .filename
            .as_deref()
            .or_else(|| {
                std::path::Path::new(&args.path)
                    .file_name()
                    .and_then(|name| name.to_str())
            })
            .ok_or_else(|| ToolError::new(super::send::rejected("file has no display filename")))?;
        let filename = safe_filename(filename).map_err(ToolError::new)?;
        let files = self
            .files
            .get_or_try_init(|| {
                LocalWorkspaceFileBackend::confined_beneath(
                    self.workspace.clone(),
                    self.io.clone(),
                    self.bots.inner.paths.bots_dir(),
                    std::path::PathBuf::from(&source.bot_id).join("workspace"),
                )
            })
            .await;
        self.bots
            .check_send_active(&context.cancellation)
            .map_err(ToolError::new)?;
        let files = files.map_err(ToolError::new)?;
        let bytes_budget = self
            .bots
            .reserve_send_bytes(FILE_UPLOAD_LIMIT_BYTES)
            .map_err(ToolError::new)?;
        let bytes = files
            .read_bytes(WorkspaceFileReadBytesRequest {
                path: args.path,
                cwd: None,
                max_bytes: FILE_UPLOAD_LIMIT_BYTES,
            })
            .await;
        self.bots
            .check_send_active(&context.cancellation)
            .map_err(ToolError::new)?;
        let bytes = bytes.map_err(ToolError::new)?;
        if bytes.is_empty() {
            return Err(ToolError::new(super::send::rejected(
                "Feishu does not accept empty files",
            )));
        }
        let bot_id = source.bot_id.clone();
        let chat_id = source.chat_id.clone();
        // The delivery owner observes cancellation and persists the actual stage. Dropping the
        // whole future here would lose the distinction between NotStarted and in-flight unknown.
        let result = self
            .bots
            .send_production(
                super::send_service::SendRequest {
                    operation_id,
                    bot_id,
                    chat_id,
                    input: SendInput::File {
                        request_hash,
                        source: Box::new(source),
                        filename,
                        bytes: Arc::from(bytes),
                    },
                    authority,
                },
                admission,
                bytes_budget,
                "tool",
                &context.cancellation,
            )
            .await;
        match result {
            Ok(result) => output(&result),
            Err(error) => {
                let observed = error.observed_send().map(output).transpose()?;
                let error = ToolError::new(error);
                Err(match observed {
                    Some(output) => error.with_output(output),
                    None => error,
                })
            }
        }
    }
}

fn output(value: &impl Serialize) -> Result<ToolOutput, ToolError> {
    let encoded = serde_json::to_string(value).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.studio.bot-file", 1, encoded.clone()).map_err(ToolError::new)?,
        vec![ContextContent::Text {
            text: Arc::from(encoded),
        }],
    ))
}
