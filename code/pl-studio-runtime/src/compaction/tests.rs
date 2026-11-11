//! One production regression for observed-source downsizing below the target's rough threshold.
use super::*;
use anyhow::{Context, Result};
use pl_core::{
    context::{ContextContent, ContextSnapshot},
    model::{ModelFactory, ModelRequest, ToolCallMode},
    thread::{
        ContextReplacementReason, ModelStepLimit, ReplaceContext, ThreadHandle, TurnInput,
        extensions::ExtensionMutation,
    },
};
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
    runtime::ModelRuntime,
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
use serde_json::json;

fn turn(id: &str, text: &str) -> TurnInput {
    TurnInput {
        turn_id: id.into(),
        attempt_prefix: id.into(),
        content: vec![ContextContent::Text { text: text.into() }],
        max_model_steps: ModelStepLimit::Limited(2.try_into().unwrap()),
        cancellation: Default::default(),
    }
}

#[tokio::test]
async fn source_observed_usage_triggers_downsizing_below_target_rough_threshold() -> Result<()> {
    // A small wire sample avoids the fixture's HTTP body cap; reported source usage is independent
    // from the target's rough text estimate, just as with the real 604202-token source checkpoint.
    let ledger = "ledger ".repeat(2048);
    let mut reported = responses_text("source answer", "source-turn", "source");
    reported.last_mut().unwrap()["response"]["usage"]["input_tokens"] = json!(604_202);
    let options = policy(OpenAiCompactionMode::Local);
    let source = FixtureServer::start(vec![
        Step::prompt(
            Protocol::ResponsesHttp,
            ledger.clone(),
            0,
            Reply::Sse(reported),
        ),
        Step::prompt(
            Protocol::ResponsesHttp,
            format!("{}\n\n{}", options.instructions, options.requirement),
            1,
            Reply::Sse(responses_text(
                "source handoff summary",
                "summary",
                "source",
            )),
        ),
    ])
    .await?;
    let target = FixtureServer::start(vec![Step::prompt(
        Protocol::ResponsesHttp,
        "TARGET_PENDING_INPUT_ONLY",
        0,
        Reply::Sse(responses_text("target continued", "target-turn", "target")),
    )])
    .await?;
    let mut config = crate::StudioConfig::default_config()?;
    config.models.accounts.clear();
    for (id, endpoint, window, threshold, base) in [
        (
            "source",
            source.base_url(),
            1_000_000,
            900_000,
            "SOURCE_BASE",
        ),
        ("target", target.base_url(), 500_000, 450_000, "TARGET_BASE"),
    ] {
        let mut model = ModelInfo::compatible(id);
        model
            .binding
            .set_transport(ModelTransportProfile::responses_http());
        model.context_window = Some(window);
        model.max_context_window = Some(window);
        model.max_output_tokens = Some(1024);
        model.auto_compact_token_limit = Some(threshold);
        model.base_instructions = base.into();
        config.models.accounts.insert(
            AccountId::new(id)?,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(id, endpoint),
                vec![model],
            ),
        );
    }
    let resolve = |id: &str| {
        config.models.resolve_route(
            crate::config::root_agent_route_id(),
            &ModelRouteConfig {
                account_id: AccountId::new(id).unwrap(),
                model_id: id.into(),
                effort: None,
            },
        )
    };
    let source_route = resolve("source")?;
    let target_route = resolve("target")?;
    let source_model = ThreadModel::new(ModelRuntime::from_route(&source_route)?, None);
    let modes = crate::mode::ThreadModeManager::default();
    let registry = crate::studio::thread::register_builtins(&modes)?;
    let mode = registry
        .mode(&pl_protocol::ThreadModeId::simple())
        .context("Simple mode")?;
    let snapshot: crate::instruction::InstructionSnapshot = serde_json::from_value(json!({
        "agent": {"id":"root:main", "scope":"root", "usageBinding":{"kind":"rootEntry","entry":"studio"},
            "revision":"1", "origin":"builtin"},
        "agentShape":{"state":"present","contentHash":pl_core::context::content_hash(b"fixture root instruction")},
        "base":{"source":{"kind":"modelBase","label":"model base"},"content":"SOURCE_BASE"},
        "developer":[
            {"source":{"kind":"agentDefinition","label":"fixture root"},"content":"fixture root instruction"},
            {"source":{"kind":"modeDefinition","label":mode.descriptor().display_name},"content":mode.prompt()}
        ], "user":[]
    }))?;
    let thread = ThreadHandle::start(
        "usage-handoff".into(),
        ModelFactory::new(source_model.clone())
            .open_session()
            .await?,
    )?;
    thread
        .replace_context(ReplaceContext {
            expected_revision: 0,
            reason: ContextReplacementReason::Rebuild,
            records: snapshot.context_records("usage-handoff"),
        })
        .await?;
    thread
        .mutate_extensions(vec![
            ExtensionMutation::Put {
                id: "studio.mode".into(),
                expected_revision: None,
                payload: crate::mode::encode_mode_snapshot(
                    &crate::mode::SavedThreadMode::capture(&mode, None),
                )?,
            },
            ExtensionMutation::Put {
                id: "studio.instructions".into(),
                expected_revision: None,
                payload: crate::instruction::encode_snapshot(&snapshot)?,
            },
            ExtensionMutation::Put {
                id: "studio.instructions.binding".into(),
                expected_revision: None,
                payload: pl_core::context::OpaquePayload::new(
                    "pl.studio.instruction-binding",
                    1,
                    serde_json::to_string(&instruction_binding(&source_route, &source_model))?,
                )?,
            },
        ])
        .await?;
    thread.run_turn(turn("source-turn", &ledger)).await?;
    let before = thread.snapshot();
    let origin = before
        .last_attempt_usage_origin
        .as_ref()
        .context("source observation")?;
    assert_eq!(origin.context_revision, before.context.revision);
    assert_eq!(
        before.last_attempt_usage.as_ref().unwrap().input_tokens,
        Some(604_202)
    );
    let target_model = ThreadModel::new(ModelRuntime::from_route(&target_route)?, None);
    let mut preview = before.context.records.to_vec();
    preview.push(pl_core::context::ContextRecord {
        id: "target-input".into(),
        turn_id: Some("target-turn".into()),
        source: pl_core::context::ContextSource::User,
        content: vec![ContextContent::Text {
            text: "TARGET_PENDING_INPUT_ONLY".into(),
        }],
        tool_calls: vec![],
    });
    let request = ModelRequest {
        thread_id: "usage-handoff".into(),
        turn_id: "target-turn".into(),
        attempt_id: "target-turn:0".into(),
        context: ContextSnapshot {
            revision: before.context.revision,
            records: preview.into(),
        },
        tools: Default::default(),
        tool_call_mode: ToolCallMode::Parallel,
        solo_tool_ids: Default::default(),
        committed_private_context: None,
        resources: None,
        cancellation: Default::default(),
        progress: None,
        members: None,
    };
    let estimate = target_model
        .estimate_input(&request, None)
        .await?
        .context("rough text estimate")?;
    assert!(estimate.tokens < target_route.context.auto_compact_limit.unwrap());
    assert_eq!(
        target_model
            .compaction_decision(&request, None, false)
            .await?,
        pl_model::runtime::ThreadCompactionDecision::Keep
    );
    thread
        .queue_deferred_model_update(
            crate::studio::model_binding::deferred_update(&target_route, &config, modes)?,
            vec![],
        )
        .await?;
    thread
        .run_turn(turn("target-turn", "TARGET_PENDING_INPUT_ONLY"))
        .await?;
    let after = thread.snapshot();
    let saved = after
        .extensions
        .get(LATEST_RECEIPT)
        .context("source summary must precede target continuation")?;
    let receipt = decode_receipt(saved.payload.version(), saved.payload.content())?;
    assert_eq!(receipt.binding.account_id, "source");
    assert_eq!(receipt.accounting.usage.input_tokens, Some(11));
    assert_eq!(
        after.last_attempt_usage.as_ref().unwrap().input_tokens,
        Some(11),
        "source usage is not target usage"
    );
    thread.close().await?;
    let source_requests = source.finish().await?;
    assert_eq!(source_requests.len(), 2);
    let summary = source_requests[1].body.to_string();
    assert!(summary.contains("SOURCE_BASE") && summary.contains(&ledger[..100]));
    assert!(!summary.contains("TARGET_BASE") && !summary.contains("TARGET_PENDING_INPUT_ONLY"));
    let target_requests = target.finish().await?;
    assert_eq!(target_requests.len(), 1);
    let continuation = target_requests[0].body.to_string();
    assert!(
        continuation.contains("source handoff summary") && continuation.contains("TARGET_BASE")
    );
    assert!(!continuation.contains(&ledger[..100]));
    Ok(())
}
