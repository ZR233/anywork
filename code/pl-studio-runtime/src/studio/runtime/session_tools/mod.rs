//! Thread-owned product tools. Queries share the desktop's directory and content owners.
mod content;

use std::collections::HashMap;
use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use pl_core::context::{ContextContent, OpaquePayload};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, Tool, ToolError},
};
use pl_protocol::studio::{ThreadDirectoryFilter, ThreadDirectoryQuery};
use pl_protocol::{
    AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID, InteractionContent, InteractionPurpose,
    InteractionRequest, InteractionResolution, InteractionStatus, ToolApprovalResolution,
    ToolApprovalResolutionPayload, UserInputAnswer, UserInputResolution,
};
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
    ReadInteraction,
    ApprovePlan,
    RevisePlan,
    Answer,
    DecideApproval,
}

impl Operation {
    fn name(self) -> &'static str {
        match self {
            Self::List => "list_sessions",
            Self::Get => "get_session",
            Self::Search => "search_session_messages",
            Self::Read => "read_session_messages",
            Self::Send => "send_session_message",
            Self::ReadInteraction => "read_session_interaction",
            Self::ApprovePlan => "approve_session_plan",
            Self::RevisePlan => "revise_session_plan",
            Self::Answer => "answer_session_questions",
            Self::DecideApproval => "decide_session_tool_approval",
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
    [
        Operation::List,
        Operation::Get,
        Operation::Search,
        Operation::Read,
        Operation::Send,
        Operation::ReadInteraction,
        Operation::ApprovePlan,
        Operation::RevisePlan,
        Operation::Answer,
        Operation::DecideApproval,
    ]
    .into_iter().map(|operation| {
        let (description, input_schema) = match operation {
            Operation::List => ("List anywork sessions across projects with status and pagination. Use returned session IDs, never guess IDs.", schemars::schema_for!(ListInput).to_value()),
            Operation::Get => ("Read a session's current state, model and pending interactions without running it.", schemars::schema_for!(GetInput).to_value()),
            Operation::Search => ("Search complete visible message text (including Chinese) across anywork sessions. Continue with the returned cursor until complete; a partial page is not an exhaustive search.", schemars::schema_for!(content::SearchInput).to_value()),
            Operation::Read => ("Read session message history and attachment references. Use itemId and continuation to read the full text of a long message.", schemars::schema_for!(content::ReadInput).to_value()),
            Operation::Send => ("Send the user's requested message to an existing anywork session. This starts or steers execution like a desktop user message. Attachments must be IDs already attached to your own bot session. Acceptance is not task completion; use get_session/read_session_messages for the result.", schemars::schema_for!(SendInput).to_value()),
            Operation::ReadInteraction => ("Read one pending interaction of an anywork session in full: the complete plan document of a plan confirmation, every question with its options, or the tool approval request. Read it before resolving an interaction ID reported by get_session.", schemars::schema_for!(InteractionInput).to_value()),
            Operation::ApprovePlan => ("Approve the pending implementation plan of an anywork session so work proceeds, acting on the user's explicit instruction. Use the pending plan confirmation interaction ID from get_session; read_session_interaction shows the full plan first.", schemars::schema_for!(InteractionInput).to_value()),
            Operation::RevisePlan => ("Request changes to the pending implementation plan of an anywork session, acting on the user's explicit instruction. Required feedback states what to change; the session returns to drafting a revised plan.", schemars::schema_for!(RevisePlanInput).to_value()),
            Operation::Answer => ("Answer the pending questions of an anywork session on the user's behalf. Each answer selects option labels and/or free text as the user actually said; a free-text entry is a custom reply.", schemars::schema_for!(AnswerInput).to_value()),
            Operation::DecideApproval => ("Approve or deny a pending tool approval of an anywork session as explicitly instructed by the user; read_session_interaction shows what is being approved.", schemars::schema_for!(ApprovalInput).to_value()),
        };
        let declaration = pl_model::runtime::thread_tool_declaration(&pl_protocol::ToolSpec::Function {
            name: operation.name().into(), description: description.into(), input_schema,
            allowed_callers: vec![], output_schema: None,
        })?;
        let tool = SessionTool { bots: bots.clone(), source_thread_id: thread_id.into(), operation };
        let registration = Registration::new(operation.name().into(), declaration, tool)?;
        Ok(if matches!(operation, Operation::Send | Operation::ApprovePlan | Operation::RevisePlan | Operation::Answer | Operation::DecideApproval) { registration.foreground() } else { registration })
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
                        "revision": interaction.revision, "scope": interaction.scope,
                        "summary": interaction_summary(&interaction.content)})
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
            Operation::ReadInteraction => {
                let args: InteractionInput = serde_json::from_str(input.content())?;
                output(
                    &runtime
                        .read_interaction_from_bot(&self.source_thread_id, &args)
                        .await?,
                )
            }
            Operation::ApprovePlan => {
                let args: InteractionInput = serde_json::from_str(input.content())?;
                runtime
                    .resolve_from_bot(
                        &self.source_thread_id,
                        &context,
                        args,
                        approve_plan_resolution(),
                    )
                    .await
            }
            Operation::RevisePlan => {
                let args: RevisePlanInput = serde_json::from_str(input.content())?;
                ensure!(
                    !args.feedback.trim().is_empty(),
                    "revision feedback is required"
                );
                ensure!(
                    args.feedback.len() <= crate::plan_tool::state::MAX_FEEDBACK_BYTES,
                    "revision feedback is too long"
                );
                runtime
                    .resolve_from_bot(
                        &self.source_thread_id,
                        &context,
                        InteractionInput {
                            session_id: args.session_id,
                            interaction_id: args.interaction_id,
                        },
                        revise_plan_resolution(args.feedback),
                    )
                    .await
            }
            Operation::Answer => {
                let args: AnswerInput = serde_json::from_str(input.content())?;
                runtime
                    .resolve_from_bot(
                        &self.source_thread_id,
                        &context,
                        InteractionInput {
                            session_id: args.session_id,
                            interaction_id: args.interaction_id,
                        },
                        answer_resolution(args.answers),
                    )
                    .await
            }
            Operation::DecideApproval => {
                let args: ApprovalInput = serde_json::from_str(input.content())?;
                runtime
                    .resolve_from_bot(
                        &self.source_thread_id,
                        &context,
                        InteractionInput {
                            session_id: args.session_id,
                            interaction_id: args.interaction_id,
                        },
                        approval_resolution(args.approve, args.reason),
                    )
                    .await
            }
        }
    }
}

/// Plan 决议答案与 [13](design/13-plan.md) 的解释入口对齐：`Approve` 实施计划，
/// `Revise` 加反馈要求修订；不在此另立语义。
fn ensure_plan_confirmation(interaction: &InteractionRequest) -> Result<()> {
    ensure!(
        matches!(
            interaction.scope.purpose,
            InteractionPurpose::AgentSessionPlanConfirmation(_)
        ),
        "interaction is not a plan confirmation"
    );
    let InteractionContent::UserInput(content) = &interaction.content else {
        anyhow::bail!("plan confirmation must be a user input interaction");
    };
    ensure!(
        content
            .questions()
            .iter()
            .any(|question| question.id == AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID),
        "plan confirmation question is missing"
    );
    Ok(())
}

fn user_input_resolution(question_id: &str, answers: Vec<String>) -> InteractionResolution {
    InteractionResolution::UserInput(UserInputResolution {
        answers: HashMap::from([(question_id.to_string(), UserInputAnswer { answers })]),
    })
}

fn approve_plan_resolution() -> impl FnOnce(&InteractionRequest) -> Result<InteractionResolution> {
    move |interaction| {
        ensure_plan_confirmation(interaction)?;
        Ok(user_input_resolution(
            AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID,
            vec!["Approve".to_string()],
        ))
    }
}

fn revise_plan_resolution(
    feedback: String,
) -> impl FnOnce(&InteractionRequest) -> Result<InteractionResolution> {
    move |interaction| {
        ensure_plan_confirmation(interaction)?;
        Ok(user_input_resolution(
            AGENT_SESSION_PLAN_CONFIRMATION_QUESTION_ID,
            vec!["Revise".to_string(), feedback],
        ))
    }
}

fn answer_resolution(
    answers: HashMap<String, Vec<String>>,
) -> impl FnOnce(&InteractionRequest) -> Result<InteractionResolution> {
    move |interaction| {
        ensure!(
            matches!(interaction.scope.purpose, InteractionPurpose::General),
            "plan confirmations use approve_session_plan or revise_session_plan"
        );
        let InteractionContent::UserInput(content) = &interaction.content else {
            anyhow::bail!("user questions must be a user input interaction");
        };
        ensure!(!answers.is_empty(), "answers are empty");
        for (question_id, selected) in &answers {
            ensure!(
                content
                    .questions()
                    .iter()
                    .any(|question| &question.id == question_id),
                "unknown question `{question_id}`"
            );
            ensure!(
                !selected.is_empty(),
                "question `{question_id}` has no answer"
            );
        }
        Ok(InteractionResolution::UserInput(UserInputResolution {
            answers: answers
                .into_iter()
                .map(|(question_id, selected)| (question_id, UserInputAnswer { answers: selected }))
                .collect(),
        }))
    }
}

fn approval_resolution(
    approve: bool,
    reason: Option<String>,
) -> impl FnOnce(&InteractionRequest) -> Result<InteractionResolution> {
    move |interaction| {
        let InteractionContent::ToolApproval(_) = &interaction.content else {
            anyhow::bail!("interaction is not a tool approval");
        };
        if !approve {
            ensure!(
                reason
                    .as_deref()
                    .is_some_and(|value| !value.trim().is_empty()),
                "denials require a reason"
            );
        }
        Ok(InteractionResolution::ToolApproval(
            ToolApprovalResolutionPayload {
                decision: if approve {
                    ToolApprovalResolution::Approved
                } else {
                    ToolApprovalResolution::Denied
                },
                reason,
            },
        ))
    }
}

fn interaction_summary(content: &InteractionContent) -> serde_json::Value {
    match content {
        InteractionContent::UserInput(request) => serde_json::json!(
            request
                .questions()
                .iter()
                .map(|question| serde_json::json!({
                    "id": question.id,
                    "header": question.header,
                    "options": question.options.as_ref().map(|options| options
                        .iter()
                        .map(|option| &option.label)
                        .collect::<Vec<_>>())
                        .unwrap_or_default(),
                    "isOther": question.is_other,
                }))
                .collect::<Vec<_>>()
        ),
        InteractionContent::ToolApproval(request) => serde_json::json!({
            "tool": request.request().name,
        }),
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

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct InteractionInput {
    session_id: String,
    interaction_id: String,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct RevisePlanInput {
    session_id: String,
    interaction_id: String,
    feedback: String,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AnswerInput {
    session_id: String,
    interaction_id: String,
    /// Maps each pending question ID to the selected option labels and/or free text.
    answers: HashMap<String, Vec<String>>,
}

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ApprovalInput {
    session_id: String,
    interaction_id: String,
    approve: bool,
    reason: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SendReceipt {
    session_id: String,
    input_id: String,
    accepted: bool,
    duplicate: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ResolutionReceipt {
    session_id: String,
    interaction_id: String,
    status: &'static str,
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
            let bytes = self
                .read_thread_attachment(source.into(), record.id)
                .await?;
            let output = destination.clone();
            tokio::task::spawn_blocking(move || {
                pl_tool::workspace::write_file_atomically(&output, &bytes)
            })
            .await??;
            sources.push(
                pl_protocol::studio::StudioAttachmentDraftSource::LocalFile {
                    path: destination.to_string_lossy().into_owned(),
                },
            );
        }
        let drafts = if sources.is_empty() {
            Vec::new()
        } else {
            self.admit_attachment_drafts(pl_protocol::studio::AdmitAttachmentDraftsRequest {
                context: pl_protocol::studio::StudioAttachmentAdmissionContext::ExistingThread {
                    thread_id: args.session_id.clone(),
                },
                sources,
            })
            .await?
            .drafts
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

    /// Reads one pending interaction of another session in full, including the plan document
    /// or every question with its options. The interaction must still be pending when read.
    async fn read_interaction_from_bot(
        &self,
        source: &str,
        args: &InteractionInput,
    ) -> Result<serde_json::Value> {
        self.pending_interaction_from_bot(source, &args.session_id, &args.interaction_id)
            .await
            .map(|interaction| {
                let kind = match &interaction.content {
                    InteractionContent::UserInput(_) => "userInput",
                    InteractionContent::ToolApproval(_) => "toolApproval",
                };
                let detail = match &interaction.content {
                    InteractionContent::UserInput(content) => serde_json::json!({
                        "questions": content.questions(),
                    }),
                    InteractionContent::ToolApproval(content) => {
                        serde_json::json!({"request": content.request()})
                    }
                };
                serde_json::json!({
                    "sessionId": args.session_id,
                    "interactionId": interaction.interaction_id,
                    "revision": interaction.revision,
                    "status": InteractionStatus::Pending.as_str(),
                    "kind": kind,
                    "purpose": interaction.scope.purpose,
                    "summary": interaction_summary(&interaction.content),
                    "detail": detail,
                })
            })
    }

    /// Resolves another session's interaction through the desktop's canonical boundary.
    /// Original questions/requests remain available after the pending snapshot evicts a terminal
    /// interaction, so repeats can reach that boundary's idempotent receipt or explicit conflict.
    async fn resolve_from_bot(
        &self,
        source: &str,
        context: &CallContext,
        args: InteractionInput,
        build_resolution: impl FnOnce(&InteractionRequest) -> Result<InteractionResolution>,
    ) -> Result<ToolOutput> {
        self.ensure_interaction_target_from_bot(source, &args.session_id, &args.interaction_id)
            .await?;
        let current = self
            .read_interaction_for_resolve(&args.interaction_id)
            .await?
            .with_context(|| format!("interaction `{}` not found", args.interaction_id))?;
        let resolution = build_resolution(&current.interaction)?;
        ensure!(
            !context.cancellation.is_cancelled(),
            "session tool cancelled before resolution"
        );
        let identity = serde_json::to_vec(&(
            source,
            &context.turn_id,
            &context.call_id,
            &args.interaction_id,
        ))?;
        let operation_id = format!("bot-resolve:{}", crate::canonical_content_hash(&identity));
        // 决议经该交互所属成员的主会话宿主提交；原交互身份与版本不变。
        let host_thread_id = self
            .interaction_host_thread(&current.interaction.scope.thread_id)
            .await?;
        let response = self
            .resolve_interaction(
                operation_id,
                host_thread_id,
                current.interaction.revision,
                args.interaction_id.clone(),
                resolution,
            )
            .await?;
        output(&ResolutionReceipt {
            session_id: args.session_id,
            interaction_id: args.interaction_id,
            status: response.interaction.status().as_str(),
        })
    }

    /// Loads a still-pending interaction of another session, enforcing the shared bot tool
    /// guards: never the source session itself, never an archived target.
    async fn pending_interaction_from_bot(
        &self,
        source: &str,
        session_id: &str,
        interaction_id: &str,
    ) -> Result<InteractionRequest> {
        self.ensure_interaction_target_from_bot(source, session_id, interaction_id)
            .await?;
        let snapshot = self.thread_snapshot(session_id).await?;
        snapshot
            .interactions
            .into_iter()
            .find(|interaction| interaction.interaction_id == interaction_id)
            .with_context(|| format!("interaction `{interaction_id}` is not pending"))
    }

    /// Validates the requested target before either pending reads or terminal resolution replays.
    async fn ensure_interaction_target_from_bot(
        &self,
        source: &str,
        session_id: &str,
        interaction_id: &str,
    ) -> Result<()> {
        ensure!(
            session_id != source,
            "cannot resolve interactions of the source session itself"
        );
        let (owner, _) = crate::thread_assembler::decode_interaction_key(interaction_id)?;
        ensure!(
            owner == session_id,
            "interaction belongs to another session"
        );
        let target = self.read_thread(session_id).await?;
        ensure!(!target.archived, "target session is archived");
        Ok(())
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
