//! Thread-owned product tools. Queries share the desktop's directory and content owners.
mod content;

use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use pl_core::context::{ContextContent, OpaquePayload};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, Tool, ToolError},
};
use pl_protocol::studio::{ThreadDirectoryFilter, ThreadDirectoryQuery};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use super::StudioRuntime;
use crate::bots::BotRuntime;
use crate::thread_assembler::ThreadAssemblyError;

#[derive(Clone, Copy)]
enum Operation {
    List,
    Get,
    Search,
    Read,
    Send,
}

impl Operation {
    fn name(self) -> &'static str {
        match self {
            Self::List => "list_sessions",
            Self::Get => "get_session",
            Self::Search => "search_session_messages",
            Self::Read => "read_session_messages",
            Self::Send => "send_session_message",
        }
    }
}

struct SessionTool {
    bots: BotRuntime,
    source_thread_id: String,
    operation: Operation,
}

impl std::fmt::Debug for SessionTool {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SessionTool")
            .field("operation", &self.operation.name())
            .finish_non_exhaustive()
    }
}

pub(crate) fn registrations(
    bots: BotRuntime,
    thread_id: &str,
) -> Result<Vec<Registration>, ThreadAssemblyError> {
    [Operation::List, Operation::Get, Operation::Search, Operation::Read, Operation::Send]
        .into_iter().map(|operation| {
            let (description, input_schema) = match operation {
                Operation::List => ("List anywork sessions across projects with status and pagination. Use returned session IDs, never guess IDs.", schemars::schema_for!(ListInput).to_value()),
                Operation::Get => ("Read a session's current state, model and pending interactions without running it.", schemars::schema_for!(GetInput).to_value()),
                Operation::Search => ("Search complete visible message text (including Chinese) across anywork sessions. Continue with the returned cursor until complete; a partial page is not an exhaustive search.", schemars::schema_for!(content::SearchInput).to_value()),
                Operation::Read => ("Read session message history and attachment references. Use itemId and continuation to read the full text of a long message.", schemars::schema_for!(content::ReadInput).to_value()),
                Operation::Send => ("Send the user's requested message to an existing anywork session. This starts or steers execution like a desktop user message. Attachments must be IDs already attached to your own bot session. Acceptance is not task completion; use get_session/read_session_messages for the result.", schemars::schema_for!(SendInput).to_value()),
            };
            let declaration = pl_model::runtime::thread_tool_declaration(&pl_protocol::ToolSpec::Function {
                name: operation.name().into(), description: description.into(), input_schema,
                allowed_callers: vec![], output_schema: None,
            })?;
            let tool = SessionTool { bots: bots.clone(), source_thread_id: thread_id.into(), operation };
            let registration = Registration::new(operation.name().into(), declaration, tool)?;
            Ok(if matches!(operation, Operation::Send) { registration.foreground() } else { registration })
        }).collect()
}

impl Tool for SessionTool {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.run(input, context)
            .await
            .map_err(|error| ToolError::new(std::io::Error::other(error)))
    }
}

impl SessionTool {
    async fn run(&self, input: OpaquePayload, context: CallContext) -> Result<ToolOutput> {
        ensure!(
            input.format() == "application/json" && input.version() == 1,
            "unsupported session tool encoding"
        );
        ensure!(
            context.thread_id == self.source_thread_id,
            "session tool belongs to another Thread"
        );
        ensure!(
            !context.cancellation.is_cancelled(),
            "session tool cancelled"
        );
        let bot = self
            .bots
            .config_for_thread(&self.source_thread_id)
            .await?
            .context("session tool is no longer bound to a bot")?;
        ensure!(bot.enabled, "bot is disabled");
        let runtime = self
            .bots
            .studio_host()
            .context("Studio runtime is closed")?;
        match self.operation {
            Operation::List => {
                let args: ListInput = serde_json::from_str(input.content())?;
                ensure!(
                    (1..=100).contains(&args.limit),
                    "limit must be between 1 and 100"
                );
                output(
                    &runtime
                        .agent_facility
                        .product_events
                        .query_threads(&args.query(), args.cursor.as_deref(), args.limit as usize)
                        .await?,
                )
            }
            Operation::Get => {
                let args: GetInput = serde_json::from_str(input.content())?;
                let snapshot = runtime.thread_snapshot(&args.session_id).await?;
                let recent = runtime
                    .timeline_reader(&args.session_id)
                    .await?
                    .page(&pl_protocol::TimelinePageQuery {
                        before: None,
                        limit: Some(16),
                    })
                    .await?;
                let execution = recent
                    .items
                    .into_iter()
                    .rev()
                    .filter(|item| {
                        matches!(
                            item.preview.kind(),
                            pl_protocol::ThreadItemKind::Turn
                                | pl_protocol::ThreadItemKind::Inference
                        )
                    })
                    .take(4)
                    .map(|item| item.preview)
                    .collect::<Vec<_>>();
                let pending = snapshot.interactions.iter().take(32).map(|interaction| {
                    let kind = match &interaction.content {
                        pl_protocol::InteractionContent::UserInput(_) => "userInput",
                        pl_protocol::InteractionContent::ToolApproval(_) => "toolApproval",
                    };
                    serde_json::json!({"interactionId": interaction.interaction_id, "kind": kind,
                        "revision": interaction.revision, "scope": interaction.scope})
                }).collect::<Vec<_>>();
                output(
                    &serde_json::json!({"thread": snapshot.thread, "activeTurn": snapshot.active_turn,
                    "model": snapshot.runtime.and_then(|runtime| runtime.model_route),
                    "pending": pending, "pendingCount": snapshot.interactions.len(), "activity": snapshot.activity,
                    "recentExecution": execution, "storage": snapshot.storage}),
                )
            }
            Operation::Read => {
                content::read(&runtime, serde_json::from_str(input.content())?).await
            }
            Operation::Search => {
                content::search(
                    &runtime,
                    serde_json::from_str(input.content())?,
                    &context.cancellation,
                )
                .await
            }
            Operation::Send => {
                let args: SendInput = serde_json::from_str(input.content())?;
                runtime
                    .send_from_bot(&bot.id, &self.source_thread_id, &context, args)
                    .await
            }
        }
    }
}

fn default_limit() -> u32 {
    25
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ListInput {
    project_id: Option<String>,
    search: Option<String>,
    #[serde(default)]
    archived: bool,
    #[serde(default)]
    status: StatusFilter,
    cursor: Option<String>,
    #[serde(default = "default_limit")]
    limit: u32,
}

#[derive(Default, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
enum StatusFilter {
    #[default]
    All,
    Running,
    Attention,
}

impl ListInput {
    fn query(&self) -> ThreadDirectoryQuery {
        ThreadDirectoryQuery {
            project_id: self.project_id.clone(),
            search: self.search.clone(),
            archived: self.archived,
            filter: match self.status {
                StatusFilter::All => ThreadDirectoryFilter::All,
                StatusFilter::Running => ThreadDirectoryFilter::Running,
                StatusFilter::Attention => ThreadDirectoryFilter::Attention,
            },
        }
    }
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct GetInput {
    session_id: String,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SendInput {
    session_id: String,
    text: String,
    #[serde(default)]
    attachment_ids: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SendReceipt {
    session_id: String,
    input_id: String,
    accepted: bool,
    duplicate: bool,
}

impl StudioRuntime {
    async fn send_from_bot(
        &self,
        bot_id: &str,
        source: &str,
        context: &CallContext,
        args: SendInput,
    ) -> Result<ToolOutput> {
        ensure!(
            args.session_id != source,
            "cannot send to the source session itself"
        );
        ensure!(args.attachment_ids.len() <= 16, "too many attachments");
        ensure!(
            !args.text.trim().is_empty() || !args.attachment_ids.is_empty(),
            "message is empty"
        );
        let identity =
            serde_json::to_vec(&(source, &context.turn_id, &context.call_id, &args.session_id))?;
        let input_id = format!("bot-forward:{}", crate::canonical_content_hash(&identity));
        let receipt = |duplicate| SendReceipt {
            session_id: args.session_id.clone(),
            input_id: input_id.clone(),
            accepted: true,
            duplicate,
        };
        if matches!(
            self.bot_input_fact(&args.session_id, &input_id).await?,
            crate::bots::BotInputRead::Ready { .. } | crate::bots::BotInputRead::NotReady
        ) {
            return output(&receipt(true));
        }
        let target = self.read_thread(&args.session_id).await?;
        ensure!(!target.archived, "target session is archived");
        // Only canonical attachments belonging to the sending session may be forwarded.
        let records = self
            .store
            .load_attachments(source, &args.attachment_ids)
            .await?;
        let mut sources = Vec::new();
        let uploads = self
            .bots
            .inner
            .paths
            .bot_dir(bot_id)
            .join("workspace")
            .join(pl_tool::workspace::SessionFiles::new(source).root())
            .join("uploads");
        for record in records {
            ensure!(
                !context.cancellation.is_cancelled(),
                "session message cancelled before admission"
            );
            let filename = std::path::Path::new(record.filename.as_deref().unwrap_or("attachment"))
                .file_name()
                .context("attachment has no filename")?;
            let destination = uploads
                .join(hex::encode(Sha256::digest(record.id.as_bytes())))
                .join(filename);
            tokio::fs::create_dir_all(destination.parent().context("attachment parent missing")?)
                .await?;
            let read = self.open_thread_binary(source.into(), record.id).await?;
            let copied = read.copy_to(destination.clone()).await;
            let closed = read.close().await;
            if let pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } = closed.outcome {
                anyhow::bail!(
                    "attachment forwarding retained unresolved read ownership: {issues:?}"
                );
            }
            copied?;
            sources.push(
                pl_protocol::studio::StudioAttachmentDraftSource::LocalFile {
                    path: destination.to_string_lossy().into_owned(),
                },
            );
        }
        let drafts = if sources.is_empty() {
            Vec::new()
        } else {
            let job = self.begin_attachment_admission(
                crate::studio::new_id("session-attachment-admission"),
                pl_protocol::studio::AdmitAttachmentDraftsRequest {
                    context:
                        pl_protocol::studio::StudioAttachmentAdmissionContext::ExistingThread {
                            thread_id: args.session_id.clone(),
                        },
                    sources,
                },
            )?;
            let outcome = job.result().await;
            let closed = job.close().await;
            match outcome {
                pl_protocol::studio::AttachmentAdmissionOutcome::Returned { value } => value.drafts,
                pl_protocol::studio::AttachmentAdmissionOutcome::Rejected { error }
                | pl_protocol::studio::AttachmentAdmissionOutcome::UnknownOutcome { error } => {
                    return match closed.outcome {
                        pl_protocol::studio::FeedCloseOutcome::Clean => Err(error.into()),
                        pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => {
                            Err(super::super::draft_commands::DraftCommandsCloseFailure {
                                issues,
                                source: Some(error.into()),
                            }
                            .into())
                        }
                    };
                }
            }
        };
        let draft_ids: Vec<_> = drafts.into_iter().map(|draft| draft.draft_id).collect();
        let submitted = if context.cancellation.is_cancelled() {
            Err(anyhow::anyhow!(
                "session message cancelled before submission"
            ))
        } else {
            self.submit_prompt(super::super::StudioSubmitPromptRequest {
                thread_id: args.session_id.clone(),
                input: pl_protocol::studio::StudioPromptInput {
                    input_id: input_id.clone(),
                    text: format!("[机器人代发 · {bot_id} · 来源会话 {source}]\n{}", args.text),
                    attachment_draft_ids: draft_ids.clone(),
                },
                options: Default::default(),
            })
            .await
        };
        for id in draft_ids {
            if let Err(error) = self.remove_attachment_draft(id).await {
                tracing::warn!(%error, "failed to release forwarded attachment draft");
            }
        }
        submitted?;
        output(&receipt(false))
    }
}

fn output(value: &impl Serialize) -> Result<ToolOutput> {
    let encoded = serde_json::to_string(value)?;
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.studio.session-tool", 1, encoded.clone())?,
        vec![ContextContent::Text {
            text: Arc::from(encoded),
        }],
    ))
}
