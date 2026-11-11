#![cfg(feature = "live-tests")]

//! Explicit opt-in observation against an installed account, without a Studio session.
use anyhow::{Context, Result, ensure};
use pl_model::{
    completion::{
        CompletionRequest, Message, MessageContent, MessageRole, SystemPrompt, ToolCallPolicy,
        tool_definition_to_spec,
    },
    protocol::WireApi,
    runtime::{ModelInvocationContext, ModelRuntime},
};
use pl_protocol::{ModelContextItem, ToolResultRecord};
use serde_json::json;

fn message(role: MessageRole, text: &str) -> Message {
    Message {
        role,
        content: MessageContent::text(text),
        presentation: Default::default(),
        reasoning_content: None,
        tool_calls: None,
        tool_result: None,
        metadata: Default::default(),
    }
}

#[tokio::test]
#[ignore = "requires an explicitly selected live account and incurs model usage"]
async fn live_schema_tool_output_continues() -> Result<()> {
    let account_id = std::env::var("ANYWORK_LIVE_ACCOUNT_ID")
        .context("set ANYWORK_LIVE_ACCOUNT_ID to the installed account ID")?;
    let model_id = std::env::var("ANYWORK_LIVE_MODEL_ID")
        .context("set ANYWORK_LIVE_MODEL_ID to the requested model")?;
    let config = pl_studio_runtime::ConfigStore::default_app()?.load()?;
    let account = config
        .models
        .accounts
        .iter()
        .find(|(id, _)| id.as_str() == account_id)
        .map(|(_, account)| account)
        .context("selected account is not configured")?;
    let model = account
        .effective_models(None)?
        .into_iter()
        .find(|model| model.model_id == model_id)
        .context("selected model is not in this account's catalog")?;
    ensure!(
        model.binding.transport.protocol == WireApi::Responses,
        "selected model does not use the Responses protocol"
    );
    let connection_mode = model.binding.transport.default_connection_mode;
    let runtime = ModelRuntime::new_with_account_id(&account_id, account.to_endpoint()?, model)?
        .with_pricing_mode(account.billing_kind()?.into());

    let definition = pl_agent_tool::ToolDefinition::json(
        "schema_probe",
        "Return a synthetic test result without side effects.",
        json!({"type":"object","properties":{},"required":[],"additionalProperties":false}),
    )?
    .with_output_schema(
        json!({"type":"object","properties":{"result":{"type":"string"}},"required":["result"]}),
    )?;
    let mut request = CompletionRequest::builder()
        .system_prompt(SystemPrompt::new("This is an isolated tool-protocol test. Follow the user's instructions."))
        .messages(vec![message(MessageRole::User,
            "Call schema_probe once. After receiving its result, repeat its contents in your answer.")])
        .tools(vec![tool_definition_to_spec(&definition, ToolCallPolicy::DirectOnly)])
        .build();
    let first = runtime
        .complete(request.clone(), ModelInvocationContext::default())
        .await?;
    ensure!(
        first.tool_calls.len() == 1 && first.tool_calls[0].name == "schema_probe",
        "live model did not issue exactly one schema_probe call"
    );
    let call = &first.tool_calls[0];
    let mut output = message(
        MessageRole::Tool,
        "Synthetic schema probe result: blue-moon-7391",
    );
    output.tool_result = Some(ToolResultRecord {
        item_id: call.id.clone(),
        call_id: call.call_id.clone(),
        name: call.name.clone(),
        kind: call.kind(),
    });
    request.append_response(&first)?;
    request.input.push(ModelContextItem::from(output));
    let second = runtime
        .complete(request, ModelInvocationContext::default())
        .await?;
    ensure!(
        second.tool_calls.is_empty(),
        "live model requested another tool call"
    );
    let answer = second
        .content
        .as_deref()
        .context("live model returned no final text")?;
    ensure!(
        answer.contains("blue-moon-7391"),
        "live model did not consume the synthetic tool result"
    );
    println!(
        "live direct tool output accepted; model={}; transport={connection_mode:?}; tool calls=1; result observed",
        second.model,
    );
    Ok(())
}
