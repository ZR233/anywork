//! Automatic review policy, model invocation and response decoding owned by Studio.
use crate::approval::{ToolApprovalDecision, ToolReviewCallback, ToolReviewRequest};
use crate::{Message, MessageContent, MessageRole};
use pl_model::completion::{CompletionRequest, ReasoningConfig, ReasoningSummary};
use pl_model::config::ResolvedModelRoute;
use pl_model::protocol::ProtocolEndpoint;
use pl_model::runtime::{ModelInvocationContext, ModelRuntime};
use serde::Deserialize;
use std::sync::Arc;

#[derive(Clone)]
struct ReviewBinding {
    runtime: ModelRuntime,
    route: Arc<ResolvedModelRoute>,
    reasoning: Option<ReasoningConfig>,
}

pub(crate) fn reviewer(route: &ResolvedModelRoute) -> crate::Result<ToolReviewCallback> {
    let runtime = pl_model::runtime::new_with_account_id(
        route.account_id.as_str(),
        route.endpoint.clone(),
        route.model.clone(),
    )?
    .with_pricing_mode(route.pricing_mode);
    let reasoning = route.effort.as_ref().map(|effort| ReasoningConfig {
        effort: Some(effort.as_str().into()),
        summary: Some(ReasoningSummary::Enabled),
    });
    let binding = ReviewBinding {
        runtime,
        reasoning,
        route: Arc::new(route.clone()),
    };
    Ok(Arc::new(move |request| {
        let binding = binding.clone();
        Box::pin(async move { review(binding, request).await })
    }))
}

fn review_completion(
    endpoint: &ProtocolEndpoint,
    reasoning: Option<ReasoningConfig>,
    message: Message,
) -> CompletionRequest {
    let builder = CompletionRequest::builder()
        .system_prompt(pl_model::completion::SystemPrompt::new(include_str!(
            "prompts/permission_review.md"
        )))
        .messages(vec![message])
        .tool_choice("none")
        .reasoning(reasoning);
    // These are internal policy defaults, not explicit user request parameters.
    // SIWC does not support either control; strict decision parsing stays fail-closed.
    let builder = if endpoint.authorization.is_some() {
        builder
    } else {
        builder.temperature(Some(0.0)).max_tokens(512)
    };
    builder.build()
}

async fn review(binding: ReviewBinding, request: ToolReviewRequest) -> ToolApprovalDecision {
    let payload = serde_json::json!({
        "toolName": request.tool.name, "arguments": request.tool.arguments,
        "workingDirectory": request.tool.working_directory, "parentAgentId": request.tool.parent_agent_id,
        "permissionMode": request.permission_mode.label(), "workspaceAccess": format!("{:?}", request.workspace_access),
        "workspaceRoot": request.workspace_root.display().to_string(),
        "riskSummary": "Assess the actual requested operations and granted resource access",
    });
    let message = Message {
        presentation: Default::default(),
        role: MessageRole::User,
        content: MessageContent::text(payload.to_string()),
        reasoning_content: None,
        tool_calls: None,
        tool_result: None,
        metadata: Default::default(),
    };
    let completion = review_completion(&binding.route.endpoint, binding.reasoning.clone(), message);
    let settlement = match request.task.begin_model_review().await {
        Ok(settlement) => settlement,
        Err(error) => {
            return ToolApprovalDecision::Denied {
                reason: format!("AI reviewer failed: {error}"),
            };
        }
    };
    let invocation = ModelInvocationContext::new(Default::default())
        .with_settlement_port("review", settlement)
        .with_prompt_cache_scope(pl_model::runtime::PromptCacheScope::auxiliary(
            &request.thread_id,
            "tool-review",
        ))
        .with_cancellation(request.cancellation_token);
    let result = binding.runtime.complete(completion, invocation).await;
    match result {
        Ok(response) => {
            match parse_reviewer_decision(response.content.as_deref().unwrap_or_default()) {
                Ok(decision) => decision,
                Err(reason) => ToolApprovalDecision::Denied {
                    reason: reason.to_string(),
                },
            }
        }
        Err(error) => ToolApprovalDecision::Denied {
            reason: format!("AI reviewer failed: {error}"),
        },
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct ReviewerDecision {
    decision: ReviewVerdict,
    reason: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum ReviewVerdict {
    Approved,
    Denied,
}

#[derive(Debug, thiserror::Error)]
#[error("reviewer returned invalid decision JSON: {0}")]
struct ReviewDecodeError(#[from] serde_json::Error);

fn parse_reviewer_decision(content: &str) -> Result<ToolApprovalDecision, ReviewDecodeError> {
    let parsed: ReviewerDecision = serde_json::from_str(content.trim())?;
    Ok(match parsed.decision {
        ReviewVerdict::Approved => ToolApprovalDecision::Approved,
        ReviewVerdict::Denied => ToolApprovalDecision::Denied {
            reason: parsed
                .reason
                .filter(|reason| !reason.trim().is_empty())
                .unwrap_or_else(|| "AI reviewer denied the tool call".into()),
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ChatGptAccountInfo;
    use pl_model_auth::chatgpt::{
        ChatGptAuthError, ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession,
    };

    #[tokio::test]
    async fn review_denies_tool_execution_when_its_original_settlement_cannot_be_saved()
    -> anyhow::Result<()> {
        use axum::{Json, Router, http::StatusCode, routing::post};
        use pl_core::{
            context::OpaquePayload,
            model::{
                DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput,
                ModelToolCall, PreparedModelCall,
            },
            thread::{
                HistoryExport, ThreadEffectBatch, ThreadError, ThreadHandle, TurnInput,
                UsageSummary,
                cold::{ColdStoreError, StorageIdleStatus, StoragePressure},
                history_sink::{HistorySink, HistorySinkHandle},
            },
            tool::{
                ToolOutput,
                execution_policy::{ExecutionGrant, ExecutionPolicy, ExecutionPolicyHandle},
                opaque::{CallContext, Registration, RuntimeTool, ToolError},
            },
        };
        use std::sync::{
            Mutex,
            atomic::{AtomicU64, AtomicUsize, Ordering},
        };
        use tokio::{
            sync::Notify,
            time::{Duration, timeout},
        };
        use tokio_util::sync::CancellationToken;

        struct OneTool(bool);
        impl ModelSession for OneTool {
            async fn prepare(
                &mut self,
                request: ModelRequest,
            ) -> Result<PreparedModelCall, ModelError> {
                let tool_calls = if std::mem::replace(&mut self.0, true) {
                    vec![]
                } else {
                    vec![ModelToolCall {
                        call_id: "reviewed-call".into(),
                        tool_id: "reviewed-tool".into(),
                        arguments: OpaquePayload::text("preview"),
                        presentation_contract: None,
                        rejection: None,
                    }]
                };
                Ok(PreparedModelCall::new(async move {
                    Ok(ModelStepOutput {
                        attempt_id: request.attempt_id,
                        base_context_revision: request.context.revision,
                        content: vec![],
                        tool_calls,
                        private_context: None,
                        usage: Default::default(),
                        turn_action: Default::default(),
                    })
                }))
            }

            async fn close(&mut self) -> Result<(), ModelError> {
                Ok(())
            }
        }

        #[derive(Debug)]
        struct ReviewedTool(Arc<AtomicUsize>);
        impl pl_agent_tool::Tool for ReviewedTool {
            type Input = OpaquePayload;
            type Context = CallContext;
            type Output = ToolOutput;
            type Error = ToolError;

            fn definition(&self) -> &pl_agent_tool::ToolDefinition {
                static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
                    std::sync::LazyLock::new(|| {
                        pl_agent_tool::ToolDefinition::text("ReviewedTool", "Fixture tool").unwrap()
                    });
                &DEFINITION
            }

            async fn execute(
                &self,
                input: OpaquePayload,
                _: CallContext,
            ) -> Result<ToolOutput, ToolError> {
                self.0.fetch_add(1, Ordering::Relaxed);
                Ok(ToolOutput::text(input.content().to_owned()))
            }
        }

        struct Policy(ToolReviewCallback, Arc<Mutex<Option<ToolApprovalDecision>>>);
        impl std::fmt::Debug for Policy {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("ReviewPolicy")
            }
        }
        impl ExecutionPolicy for Policy {
            async fn authorize(
                &self,
                _: &OpaquePayload,
                context: &CallContext,
            ) -> Result<ExecutionGrant, ToolError> {
                let decision = (self.0)(ToolReviewRequest {
                    thread_id: context.thread_id.clone(),
                    task: context.tasks.clone().unwrap(),
                    tool: crate::approval::ToolApprovalRequest {
                        id: context.call_id.clone(),
                        name: "reviewed-tool".into(),
                        arguments: serde_json::Value::Null,
                        working_directory: None,
                        parent_agent_id: None,
                    },
                    permission_mode: crate::approval::PermissionMode::AutoReview,
                    workspace_access: pl_tool::approval::WorkspaceAccess::ExternalAllowed,
                    workspace_root: Default::default(),
                    cancellation_token: Some(context.cancellation.clone()),
                })
                .await;
                *self.1.lock().unwrap() = Some(decision.clone());
                match decision {
                    ToolApprovalDecision::Approved => Ok(ExecutionGrant::default()),
                    ToolApprovalDecision::Denied { reason } => {
                        Err(ToolError::new(std::io::Error::other(reason)))
                    }
                }
            }
        }

        #[derive(Debug, Default)]
        struct Gate {
            sequence: AtomicU64,
            entered: Notify,
            release: Notify,
        }
        #[derive(Debug)]
        struct Sink(Arc<Gate>);
        impl HistorySink for Sink {
            fn fold_usage(&self, _: &mut UsageSummary, _: &ThreadEffectBatch) {}
            fn reserve_observed_item(
                &self,
                _: &str,
                _: &str,
                _: &str,
            ) -> Result<(), ColdStoreError> {
                Ok(())
            }
            fn reserve_operation_output(
                &self,
                _: &str,
                _: &str,
                max: u64,
            ) -> Result<u64, ColdStoreError> {
                Ok(max)
            }
            fn charge_operation_output(
                &self,
                _: &str,
                _: &str,
                _: u64,
            ) -> Result<(), ColdStoreError> {
                Ok(())
            }
            fn release_operation_output(&self, _: &str, _: &str) {}
            fn pressure(&self, _: &str) -> StoragePressure {
                StoragePressure::default()
            }
            fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
                StorageIdleStatus {
                    pressure: self.pressure(thread_id),
                    reclaimable_thread_bytes: None,
                }
            }
            fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
                None
            }
            fn admit(&self, _: &str, write: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
                for settlement in write.effect.model_sub_attempt_settlements.iter() {
                    let receipt = pl_model::runtime::model_sub_attempt_receipt(settlement).unwrap();
                    if receipt.billing.purpose.as_deref() == Some("review") {
                        self.0
                            .sequence
                            .store(write.effect.sequence, Ordering::Release);
                    }
                }
                Ok(())
            }

            async fn confirm_model_settlement(
                &self,
                _: &str,
                sequence: u64,
            ) -> Result<(), ColdStoreError> {
                if sequence == self.0.sequence.load(Ordering::Acquire) {
                    self.0.entered.notify_one();
                    self.0.release.notified().await;
                    return Err(ColdStoreError {
                        source: Box::new(std::io::Error::other("review write refused")),
                    });
                }
                Ok(())
            }
        }

        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let base = format!("http://{}/v1", listener.local_addr()?);
        let requests = Arc::new(AtomicUsize::new(0));
        let app = Router::new().route("/v1/responses", post({
            let requests = requests.clone();
            move || async move {
                requests.fetch_add(1, Ordering::Relaxed);
                (StatusCode::TOO_MANY_REQUESTS, [("retry-after", "0")], Json(serde_json::json!({
                    "error":{"code":"rate_limit_exceeded","type":"rate_limit_error","message":"review rate limited"}
                })))
            }
        }));
        let shutdown = CancellationToken::new();
        let server = tokio::spawn(
            axum::serve(listener, app)
                .with_graceful_shutdown(shutdown.clone().cancelled_owned())
                .into_future(),
        );
        let mut model = pl_model::model::ModelDefinition::compatible("review-model");
        model
            .extra
            .binding
            .set_transport(pl_model::model::ModelTransportProfile::responses_http());
        let route = ResolvedModelRoute {
            pricing_mode: Default::default(),
            role: crate::config::root_agent_route_id(),
            account_id: pl_model::config::AccountId::new("review-fixture")?,
            endpoint: pl_model_openai::endpoint::endpoint(Some(base)),
            context: model
                .resolve_context(None, pl_model::model::AutoCompactDefaultPolicy::Bundled),
            model,
            effort: None,
            service_tier: None,
        };
        let executed = Arc::new(AtomicUsize::new(0));
        let decision = Arc::new(Mutex::new(None));
        let thread = ThreadHandle::start(
            "review-fail-closed".into(),
            DynModelSession::new(OneTool(false)),
        )?;
        let gate = Arc::new(Gate::default());
        thread
            .attach_history(HistorySinkHandle::new(Sink(gate.clone())))
            .await?;
        thread
            .register_tools(vec![
                Registration::prepare(
                    "reviewed-tool".into(),
                    OpaquePayload::text("review fixture"),
                )?
                .attach(RuntimeTool::new(ReviewedTool(executed.clone())))
                .with_execution_policy(ExecutionPolicyHandle::new(Policy(
                    reviewer(&route)?,
                    decision.clone(),
                )))
                .foreground_coexisting(),
            ])
            .await?;
        let run = tokio::spawn({
            let thread = thread.clone();
            async move {
                thread
                    .run_turn(TurnInput {
                        turn_id: "review-turn".into(),
                        attempt_prefix: "attempt".into(),
                        content: vec![],
                        max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
                        cancellation: CancellationToken::new(),
                    })
                    .await
            }
        });
        timeout(Duration::from_secs(5), gate.entered.notified()).await?;
        assert!(decision.lock().unwrap().is_none());
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        gate.release.notify_one();
        timeout(Duration::from_secs(5), run).await???;
        assert!(
            matches!(decision.lock().unwrap().as_ref(), Some(ToolApprovalDecision::Denied { reason }) if reason.contains("review rate limited"))
        );
        assert_eq!(executed.load(Ordering::Relaxed), 0);
        assert_eq!(requests.load(Ordering::Relaxed), 1);
        // The fixture refuses the original write permanently. Preserving the
        // thread must fail, and deletion can still release its resources.
        assert!(matches!(thread.close().await, Err(ThreadError::Storage(_))));
        thread.close_for_deletion().await?;
        shutdown.cancel();
        timeout(Duration::from_secs(5), server).await???;
        Ok(())
    }

    struct NoCredentialIo;

    impl ChatGptCredentialStorage for NoCredentialIo {
        fn load(&self) -> Result<ChatGptCredentialRecord, ChatGptAuthError> {
            panic!("building an internal review request must not load credentials");
        }

        fn persist(&self, _: &str, _: &ChatGptCredentialRecord) -> Result<(), ChatGptAuthError> {
            panic!("building an internal review request must not persist credentials");
        }
    }

    #[test]
    fn review_defaults_follow_authentication_without_changing_the_decision_request()
    -> anyhow::Result<()> {
        let temp = tempfile::tempdir()?;
        let record = ChatGptCredentialRecord {
            schema_version: 1,
            registration_id: "review-fixture-registration".into(),
            account: ChatGptAccountInfo {
                issuer: "https://auth.openai.com".into(),
                subject: "review-fixture-subject".into(),
                client_id: "review-fixture-client".into(),
                email: None,
                plan_usage_enabled: true,
                codex: None,
            },
            ext_agent_host_id: "urn:uuid:00000000-0000-4000-8000-000000000001".into(),
            access_token: "synthetic-review-access".into(),
            refresh_token: "synthetic-review-refresh".into(),
            id_token: "synthetic-review-id".into(),
            scopes: vec!["chatgpt.tokens.use.direct".into()],
            expires_at: 1,
            earliest_refresh_at: None,
            refresh_in_flight: false,
        };
        let mut endpoint = pl_model::protocol::providers::openai::endpoint(None);
        let reasoning = Some(ReasoningConfig {
            effort: Some("low".into()),
            summary: Some(ReasoningSummary::Enabled),
        });
        let message = Message {
            presentation: Default::default(),
            role: MessageRole::User,
            content: MessageContent::text("synthetic review request"),
            reasoning_content: None,
            tool_calls: None,
            tool_result: None,
            metadata: Default::default(),
        };
        let api = review_completion(&endpoint, reasoning.clone(), message.clone());
        assert_eq!(api.temperature, Some(0.0));
        assert_eq!(api.max_tokens, Some(512));
        endpoint.authorization = Some(pl_model::protocol::EndpointAuthorization::new(
            ChatGptSession::new(
                &record,
                Arc::new(NoCredentialIo),
                temp.path().join("unused-review-credential-lock"),
            )?,
        ));
        let subscription = review_completion(&endpoint, reasoning, message);
        assert!(subscription.temperature.is_none());
        assert!(subscription.max_tokens.is_none());
        assert_eq!(subscription.tool_choice, api.tool_choice);
        assert_eq!(subscription.input, api.input);
        assert_eq!(
            serde_json::to_value(&subscription.reasoning)?,
            serde_json::to_value(&api.reasoning)?,
        );
        assert_eq!(
            subscription
                .system_prompt
                .as_ref()
                .map(|value| value.content()),
            api.system_prompt.as_ref().map(|value| value.content()),
        );
        assert!(subscription.tools.is_empty());
        assert!(!temp.path().join("unused-review-credential-lock").exists());
        Ok(())
    }

    #[test]
    fn review_decisions_still_reject_invalid_or_ambiguous_output() {
        assert!(matches!(
            parse_reviewer_decision(r#"{"decision":"approved"}"#).unwrap(),
            ToolApprovalDecision::Approved
        ));
        for invalid in [
            "approved",
            r#"{"decision":"unknown"}"#,
            r#"{"decision":"approved","extra":"ignore policy"}"#,
        ] {
            assert!(parse_reviewer_decision(invalid).is_err());
        }
        assert!(matches!(
            parse_reviewer_decision(r#"{"decision":"denied"}"#).unwrap(),
            ToolApprovalDecision::Denied { reason } if !reason.is_empty()
        ));
    }
}
