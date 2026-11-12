//! Small cache-key comparison through production ThreadModel preparation.
//! Run only behind a caller-owned budget gateway; this example does not implement billing admission.
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSnapshot, ContextSource},
    model::{Model, ModelRequest, ToolCallMode},
};
use pl_model::{
    completion::ReasoningConfig,
    config::AccountConfig,
    model::{ModelProtocolOptions, ModelTransportProfile, ResponsesMaxTokensField},
    protocol::{EffectivePromptCachePolicy, PromptCacheDialect},
    runtime::{ModelRuntime, ThreadModel, model_response_receipt},
};
use serde_json::json;
use std::path::PathBuf;

#[tokio::main]
async fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let account_id = args.next().context("account required")?;
    let model_id = args.next().context("model required")?;
    let output = PathBuf::from(args.next().context("new output directory required")?);
    let effort = args.next().unwrap_or_else(|| "high".into());
    let home =
        PathBuf::from(std::env::var("ANYWORK_HOME").context("isolated ANYWORK_HOME required")?);
    let config: toml::Value =
        toml::from_str(&tokio::fs::read_to_string(home.join("config.toml")).await?)?;
    let account: AccountConfig = config["models"]["accounts"][&account_id]
        .clone()
        .try_into()?;
    let mut model = account
        .effective_models(None)?
        .into_iter()
        .find(|m| m.model_id == model_id)
        .context("model missing")?;
    // Match the research gateway's declared transport; it forwards Responses over HTTP only.
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    let endpoint = account.to_endpoint()?;
    ensure!(
        endpoint.effective_prompt_cache_policy(&model)
            == EffectivePromptCachePolicy::OpenAiPromptCacheKey,
        "the selected account must explicitly support Responses cache keys"
    );
    ensure!(
        model
            .parameters
            .iter()
            .any(|p| p.name == "effort" && p.has_candidate(&effort)),
        "unsupported reasoning effort"
    );
    // Bound every output, including reasoning, before the gateway makes its admission decision.
    model.max_output_tokens = Some(256);
    let ModelProtocolOptions::Responses(options) = &mut model.binding.request.protocol else {
        anyhow::bail!("Responses model required")
    };
    options.max_tokens_field = ResponsesMaxTokensField::MaxOutputTokens;
    tokio::fs::create_dir(&output)
        .await
        .context("use a new output directory")?;
    let run_id = uuid::Uuid::new_v4().to_string();
    let execution = async {
        for (arm, dialect) in [
            ("omitted", PromptCacheDialect::None),
            ("enabled", PromptCacheDialect::OpenAiPromptCacheKey),
        ] {
            let mut endpoint = endpoint.clone();
            endpoint.service_capabilities.prompt_cache.dialect = dialect;
            let runtime = ModelRuntime::new_with_account_id(&account_id, endpoint, model.clone())?
                .with_pricing_mode(account.billing_kind()?.into());
            let factory = ThreadModel::new(
                runtime,
                Some(ReasoningConfig {
                    effort: Some(effort.clone()),
                    summary: None,
                }),
            );
            let thread_id = format!("{run_id}-{arm}");
            // Independent initial prefixes prevent one arm warming the other. Check their
            // provider-counted lengths in the admission ledger before comparing cache use.
            let arm_prefix = if arm == "omitted" { "A" } else { "B" };
            let material = format!(
                "{run_id}-{arm_prefix}\n{}\nReply with OK only.",
                "Stable synthetic cache material for a bounded observation.\n".repeat(256),
            );
            let context = ContextSnapshot {
                revision: 1,
                records: vec![ContextRecord {
                    id: "synthetic-input".into(),
                    turn_id: None,
                    source: ContextSource::User,
                    content: vec![ContextContent::Text {
                        text: material.into(),
                    }],
                    tool_calls: vec![],
                }]
                .into(),
            };
            let mut session = factory.open_session().await?;
            let calls = async {
                for index in 0..3 {
                    let prepared = session
                        .prepare(ModelRequest {
                            thread_id: thread_id.clone(),
                            turn_id: format!("turn-{index}"),
                            attempt_id: format!("attempt-{index}"),
                            context: context.clone(),
                            tools: Default::default(),
                            tool_call_mode: ToolCallMode::Sequential,
                            solo_tool_ids: Default::default(),
                            committed_private_context: None,
                            resources: None,
                            cancellation: Default::default(),
                            progress: None,
                            members: None,
                        })
                        .await?;
                    let response = prepared.execute().await?;
                    let receipt =
                        model_response_receipt(&response)?.context("missing model receipt")?;
                    let record = json!({
                        "arm": arm, "phase": if index == 0 { "warmup" } else { "reuse" },
                        "threadId": thread_id, "receipt": receipt,
                    });
                    tokio::fs::write(
                        output.join(format!("{arm}-{index}.json")),
                        serde_json::to_vec_pretty(&record)?,
                    )
                    .await?;
                }
                anyhow::Ok(())
            }
            .await;
            let close = session.close().await;
            calls?;
            close?;
        }
        anyhow::Ok(())
    }
    .await;
    let report = json!({
        "runId": run_id, "account": account_id, "model": model_id, "effort": effort,
        "execution": execution.as_ref().err().map(ToString::to_string),
        "comparison": "cache-key hint only; server automatic caching remains enabled",
    });
    tokio::fs::write(
        output.join("report.json"),
        serde_json::to_vec_pretty(&report)?,
    )
    .await?;
    execution
}
