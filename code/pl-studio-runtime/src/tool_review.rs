//! Automatic review policy, model invocation and response decoding owned by Studio.
use crate::approval::{ToolApprovalDecision, ToolReviewCallback, ToolReviewRequest};
use pl_model::completion::{CompletionRequest, ReasoningConfig, ReasoningSummary};
use pl_model::config::ResolvedModelRoute;
use pl_model::protocol::ProtocolEndpoint;
use pl_model::runtime::{ModelInvocationContext, ModelRuntime};
use pl_protocol::{Message, MessageContent, MessageRole};
use serde::Deserialize;
use std::sync::Arc;

#[derive(Clone)]
struct ReviewBinding {
    runtime: ModelRuntime,
    route: Arc<ResolvedModelRoute>,
    reasoning: Option<ReasoningConfig>,
}

pub(crate) fn reviewer(route: &ResolvedModelRoute) -> crate::Result<ToolReviewCallback> {
    let runtime = ModelRuntime::new_with_account_id(
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
    let builder = if endpoint.chatgpt_session.is_some() {
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
    let (events, _) = tokio::sync::broadcast::channel(1);
    let inference_id = crate::studio::new_id("review");
    let invocation = ModelInvocationContext::new(Default::default())
        .with_events(events)
        .with_trace_metadata(pl_model::completion::CompletionTraceContext {
            session_id: request.thread_id,
            turn_id: request.turn_id,
            inference_id: inference_id.clone(),
        })
        .with_cancellation(request.cancellation_token);
    let result = binding.runtime.complete(completion, invocation).await;
    let route = &binding.route;
    let accounting = match &result {
        Ok(response) => response.accounting.clone(),
        Err(failure) => (*failure.accounting).clone(),
    };
    let model_observation = match &result {
        Ok(response) => response.model_observation.clone(),
        Err(failure) => failure.model_observation().cloned(),
    };
    let billing = pl_protocol::InferenceBillingRecord {
        purpose: Some("review".into()),
        inference_id,
        account_id: route.account_id.as_str().into(),
        account_display_name: Some(route.endpoint.name.clone()),
        // 冻结的目录配置模型；发送/返回模型只留在 observation 诊断里。
        model_id: Some(route.model.model_id.clone()),
        model_observation,
        effort: route.effort.as_ref().map(|effort| effort.as_str().into()),
        context_window: route.context.context_window,
        accounting,
        prompt_generation: None,
        prompt_cache_policy: None,
        prefix_changed_reason: None,
        orchestration: result
            .as_ref()
            .ok()
            .map(|response| response.orchestration.clone())
            .unwrap_or_default(),
        timing: result.as_ref().ok().and_then(|response| response.timing),
        recorded_at: crate::studio::unix_seconds(),
    };
    let receipt = crate::studio::thread_projection::AuxiliaryBillingReceipt {
        billing,
        succeeded: result.is_ok(),
    };
    let saved = async {
        let payload = receipt.into_payload()?;
        request.task.record_observation(payload).await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
    if let Err(error) = saved {
        return ToolApprovalDecision::Denied {
            reason: format!("review accounting could not be admitted: {error}"),
        };
    }
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
    use pl_model::protocol::chatgpt::{
        ChatGptAuthError, ChatGptCredentialRecord, ChatGptCredentialStorage, ChatGptSession,
    };
    use pl_protocol::studio::ChatGptAccountInfo;

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
        let mut endpoint = ProtocolEndpoint::openai(None);
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
        endpoint.chatgpt_session = Some(ChatGptSession::new(
            &record,
            Arc::new(NoCredentialIo),
            temp.path().join("unused-review-credential-lock"),
        )?);
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
