//! Explicit live cache observation through the production Thread adapter; credentials are read only.
use anyhow::{Context, Result};
use pl_core::{
    context::ContextContent,
    model::Model,
    thread::{ModelStepLimit, RuntimeFact, ThreadHandle, TurnInput},
};
use pl_model::{
    completion::ReasoningConfig,
    config::AccountConfig,
    runtime::{ModelRuntime, ThreadModel},
};
use std::{path::PathBuf, sync::Arc};
use tokio_util::sync::CancellationToken;

#[tokio::main]
async fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    let id = args.next().context("account required")?;
    let model_id = args.next().context("model required")?;
    let artifacts = PathBuf::from(args.next().context("new artifact directory required")?);
    tokio::fs::create_dir(&artifacts).await?;
    let instruction_history = args.next().as_deref() == Some("--instruction-history");
    let installed = pl_studio_runtime::ConfigStore::default_app()?;
    let raw: toml::Value =
        toml::from_str(&tokio::fs::read_to_string(installed.paths().config_file()).await?)?;
    let mut account: AccountConfig = raw
        .get("models")
        .and_then(|v| v.get("accounts"))
        .and_then(|v| v.get(&id))
        .context("account missing")?
        .clone()
        .try_into()?;
    let credential_id = id.clone();
    let stored = tokio::task::spawn_blocking(move || {
        match keyring::Entry::new("anywork", &format!("account:{credential_id}"))?.get_password() {
            Ok(secret) => Ok(Some(secret)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(error) => Err(error),
        }
    })
    .await??;
    account.bearer_token = stored.or(account.bearer_token);
    let model = account
        .effective_models(None)?
        .into_iter()
        .find(|m| m.model_id == model_id)
        .context("model missing")?;
    let effort = model
        .parameters
        .iter()
        .find(|p| p.name == "effort")
        .and_then(|p| p.candidates.first())
        .cloned();
    let endpoint = account.to_endpoint()?;
    // 消费真实冻结分发策略，不靠开关捏造 append 能力：未知绑定按 safe replace 走。
    let instruction_update_strategy = endpoint.instruction_update_strategy(&model);
    let runtime = ModelRuntime::new_with_account_id(&id, endpoint, model)?
        .with_pricing_mode(account.billing_kind()?.into());
    let factory = ThreadModel::new(
        runtime,
        Some(ReasoningConfig {
            effort: effort.clone(),
            summary: None,
        }),
    );
    let thread =
        ThreadHandle::start("cache-observation".into(), factory.open_session().await?).unwrap();
    let text = |s: String| ContextContent::Text { text: Arc::from(s) };
    let stable = (0..512)
        .map(|n| format!("固定合成材料 {n}: 此材料只用于观察缓存，没有其他任务。\n"))
        .collect::<String>();
    let instruction = |revision: u64, replaces: Option<String>| {
        let content = format!(
            "你只输出唯一标记 SNAPSHOT_V{revision}。这是完整当前指令，替代此前所有宿主指令，不要输出其他文字。"
        );
        let content_hash = pl_core::context::content_hash(content.as_bytes());
        pl_core::context::ContextRecord {
            id: format!("host-instruction:{revision}"),
            turn_id: None,
            source: pl_core::context::ContextSource::InstructionSnapshot {
                revision,
                content_hash,
                replaces,
            },
            content: vec![text(content)],
            tool_calls: vec![],
        }
    };
    if instruction_history {
        thread
            .replace_context(pl_core::thread::ReplaceContext {
                expected_revision: thread.snapshot().context.revision,
                reason: pl_core::thread::ContextReplacementReason::Rebuild,
                records: vec![instruction(1, None)],
            })
            .await?;
    }
    let execution = async {
        for (index, phase) in ["warmup", "stable", "stateUpdate", "stableAfterUpdate"].iter().enumerate() {
            if instruction_history && index == 2 {
                let snapshot = thread.snapshot();
                let replaces = snapshot.context.records.iter().find_map(|r| match &r.source { pl_core::context::ContextSource::InstructionSnapshot { content_hash, .. } => Some(content_hash.clone()), _ => None });
                let mut records = snapshot.context.records.to_vec(); records.push(instruction(2, replaces));
                thread.replace_context(pl_core::thread::ReplaceContext { expected_revision: snapshot.context.revision, reason: pl_core::thread::ContextReplacementReason::Rebuild, records }).await?;
            }
            let state = if index < 2 { "已批准；当前阶段：实施" } else { "已批准；当前阶段：验证" };
            thread.update_facts(vec![RuntimeFact { source_id: "observation.state".into(), content: vec![text(format!("{stable}\n当前宿主状态：{state}"))] }]).await?;
            let turn_id = format!("observation-{index}");
            let result = tokio::time::timeout(std::time::Duration::from_secs(180), thread.run_turn(TurnInput {
                turn_id: turn_id.clone(), attempt_prefix: turn_id, content: vec![text(if instruction_history { "遵照当前有效指令输出唯一标记。" } else { "只回复当前阶段名称，不调用工具，不请求批准。" }.into())],
                max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()), cancellation: CancellationToken::new(),
            })).await;
            tokio::fs::write(artifacts.join(format!("{index}-{phase}.json")), serde_json::to_vec_pretty(&serde_json::json!({"phase":phase,"result":format!("{result:?}"),"snapshot":thread.snapshot()}))?).await?;
            result.context("model timeout")??;
        }
        anyhow::Ok(())
    }.await;
    let close = thread.close().await;
    tokio::fs::write(artifacts.join("report.json"), serde_json::to_vec_pretty(&serde_json::json!({"account":id,"model":model_id,"effort":effort,"instructionHistory":instruction_history,"instructionUpdateStrategy":format!("{instruction_update_strategy:?}"),"execution":execution.as_ref().err().map(ToString::to_string),"close":format!("{close:?}"),"manualReview":"pending"}))?).await?;
    execution?;
    close?;
    Ok(())
}
