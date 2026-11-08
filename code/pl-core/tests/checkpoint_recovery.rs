mod support;
#[path = "support/tool.rs"]
mod tool_support;

use std::sync::{Arc, Mutex};

use pl_core::context::ContextSource;
use pl_core::model::DynModelSession;
use pl_core::thread::{
    StepInput, ThreadCheckpoint, ThreadHandle, ThreadSnapshot, ToolOutcome, TurnOutcome,
};
use tokio_util::sync::CancellationToken;

use support::{ScriptedModel, text, turn};
use tool_support::tool;

#[tokio::test]
async fn interaction_collection_revision_reopens_from_schema_six_without_guessing_legacy_versions()
{
    let checkpoint = ThreadCheckpoint::capture(
        "interaction-revision".into(),
        0,
        ThreadSnapshot {
            interaction_collection_revision: 41,
            ..Default::default()
        },
    )
    .unwrap();
    assert_eq!(checkpoint.schema_version, 6);
    let encoded = serde_json::to_value(&checkpoint).unwrap();
    let decoded: ThreadCheckpoint = serde_json::from_value(encoded.clone()).unwrap();
    let original =
        ThreadHandle::resume_without_model("interaction-revision".into(), Some(decoded)).unwrap();
    assert_eq!(original.snapshot().interaction_collection_revision, 41);
    let saved = original
        .checkpoint(original.snapshot().commit_sequence)
        .unwrap();
    assert_eq!(
        saved
            .pruned()
            .unwrap()
            .state
            .interaction_collection_revision,
        41
    );
    original.close().await.unwrap();

    let mut legacy = encoded;
    assert_eq!(
        legacy["state"]
            .as_object_mut()
            .unwrap()
            .remove("interactionCollectionRevision"),
        Some(serde_json::json!(41))
    );
    let decoded: ThreadCheckpoint = serde_json::from_value(legacy).unwrap();
    assert_eq!(decoded.state.interaction_collection_revision, 0);
    let restored =
        ThreadHandle::resume_without_model("interaction-revision".into(), Some(decoded)).unwrap();
    assert_eq!(restored.snapshot().interaction_collection_revision, 0);
    let saved = restored
        .checkpoint(restored.snapshot().commit_sequence)
        .unwrap();
    assert_eq!(saved.state.interaction_collection_revision, 0);
    restored.close().await.unwrap();
}

#[tokio::test]
async fn a_checkpoint_restores_context_without_replaying_model_work() {
    let (model, _) = ScriptedModel::new(&[]);
    let original = ThreadHandle::start("persistent".into(), DynModelSession::new(model)).unwrap();
    original.run_turn(turn("before-restart")).await.unwrap();
    let before = original.snapshot().context;
    let checkpoint = original
        .checkpoint(original.snapshot().commit_sequence)
        .unwrap();
    assert_eq!(checkpoint.state.context, before);
    assert!(
        ThreadHandle::resume_without_model("wrong-owner".into(), Some(checkpoint.clone())).is_err()
    );
    let serialized = serde_json::to_vec(&checkpoint).unwrap();
    original.close().await.unwrap();

    let restored = serde_json::from_slice(&serialized).unwrap();
    let (model, seen) = ScriptedModel::new(&[]);
    let thread = ThreadHandle::resume(
        "persistent".into(),
        DynModelSession::new(model),
        Some(restored),
    )
    .unwrap();
    assert_eq!(thread.snapshot().context, before);
    assert_eq!(
        thread
            .snapshot()
            .context
            .records
            .iter()
            .filter(|r| r.source == ContextSource::User)
            .count(),
        1
    );

    let completion = thread.run_turn(turn("after-restart")).await.unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);
    {
        let seen = seen.lock().unwrap();
        assert_eq!(
            &seen[0].records[..before.records.len()],
            before.records.as_ref()
        );
        assert!(seen[0].records.len() > before.records.len());
    }
    let now = thread.snapshot().context;
    assert!(now.revision > before.revision);
    assert!(
        now.records
            .iter()
            .any(|record| record.turn_id.as_deref() == Some("after-restart")
                && record.source == ContextSource::User)
    );
    thread.close().await.unwrap();
}

#[tokio::test]
async fn recovery_marks_a_pending_tool_interrupted_without_reexecuting_it() {
    let (model, _) = ScriptedModel::new(&["write"]);
    let original = ThreadHandle::start("interrupted".into(), DynModelSession::new(model)).unwrap();
    let executions = Arc::new(Mutex::new(Vec::new()));
    original
        .register_tools(vec![tool("write", &executions)])
        .await
        .unwrap();
    let output = original
        .step(StepInput {
            turn_id: "interrupted-turn".into(),
            attempt_id: "first-attempt".into(),
            content: vec![text("Use the write tool")],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    assert_eq!(output.tool_calls.len(), 1);
    assert!(executions.lock().unwrap().is_empty());
    let checkpoint = original
        .checkpoint(original.snapshot().commit_sequence)
        .unwrap();
    let restored =
        ThreadHandle::resume_without_model("interrupted".into(), Some(checkpoint)).unwrap();
    let snapshot = restored.snapshot();
    assert!(snapshot.context.records.iter().any(|record| {
        matches!(&record.source, ContextSource::ToolResult { call_id, .. } if call_id == "interrupted-turn-write")
    }));
    assert!(restored.effects().await.unwrap().iter().any(|effect| {
        effect.deliveries.iter().any(|delivery| {
            delivery.call_id == "interrupted-turn-write"
                && matches!(delivery.outcome, ToolOutcome::Interrupted)
        })
    }));
    assert!(executions.lock().unwrap().is_empty());
    original.close().await.unwrap();
    restored.close().await.unwrap();
}

#[derive(Debug)]
struct HeldTask(tokio_util::sync::CancellationToken);

impl pl_agent_tool::Tool for HeldTask {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
            std::sync::LazyLock::new(|| {
                pl_agent_tool::ToolDefinition::text("HeldTask", "Text tool for core runtime tests")
                    .expect("valid definition")
            });
        &DEFINITION
    }

    async fn execute(
        &self,
        _: pl_core::context::OpaquePayload,
        context: pl_core::tool::opaque::CallContext,
    ) -> Result<pl_core::tool::ToolOutput, pl_core::tool::opaque::ToolError> {
        tokio::select! {
            _ = self.0.cancelled() => {},
            _ = context.cancellation.cancelled() => {},
        }
        Ok(pl_core::tool::ToolOutput::new(
            pl_core::context::OpaquePayload::text("finished"),
            vec![text("finished")],
        ))
    }
}

#[tokio::test]
async fn background_result_identity_survives_consumed_history_pruning_and_recovery() {
    use pl_core::context::OpaquePayload;
    use pl_core::thread::{ToolDeliveryTarget, ToolDispatch, inbox::ThreadMessage};
    use pl_core::tool::opaque::Registration;

    let (model, _) = ScriptedModel::new(&["held"]);
    let thread =
        ThreadHandle::start("background-identities".into(), DynModelSession::new(model)).unwrap();
    // Legacy result IDs remain in durable history even after their resident ledger is pruned.
    let old_ids: std::collections::BTreeSet<_> = (0..65)
        .map(|index| format!("task-result:{index}"))
        .collect();
    for id in &old_ids {
        thread
            .send_message(ThreadMessage {
                kind: pl_core::context::AgentMessageKind::Report,
                id: id.clone(),
                source_id: "earlier-task".into(),
                payload: OpaquePayload::text("earlier result"),
                context: vec![text("earlier result")],
            })
            .await
            .unwrap();
    }
    let release = CancellationToken::new();
    thread
        .register_tools(vec![
            Registration::prepare("held".into(), OpaquePayload::text("held task"))
                .unwrap()
                .attach(pl_core::tool::opaque::RuntimeTool::new(HeldTask(
                    release.clone(),
                ))),
        ])
        .await
        .unwrap();
    thread
        .step(StepInput {
            turn_id: "background-turn".into(),
            attempt_id: "background-attempt".into(),
            content: vec![text("run task")],
            cancellation: CancellationToken::new(),
        })
        .await
        .unwrap();
    assert_eq!(thread.snapshot().consumed_message_identities.len(), 64);
    let ToolDispatch::Running(task) = thread
        .execute_tool("background-turn-held".into(), CancellationToken::new())
        .await
        .unwrap()
    else {
        panic!("held task must remain running")
    };
    let checkpoint = thread
        .checkpoint(thread.snapshot().commit_sequence)
        .unwrap();

    release.cancel();
    let delivery = thread
        .wait_task(&task.id, CancellationToken::new())
        .await
        .unwrap();
    let ToolDeliveryTarget::Inbox { message_id } = delivery.target else {
        panic!("background result must be delivered through inbox")
    };
    assert!(
        !old_ids.contains(&message_id),
        "reused durable identity: {message_id}"
    );
    let live_message = thread.snapshot().inbox.last().unwrap().clone();
    assert_eq!(live_message.sequence, 66);
    assert_eq!(live_message.message.id, message_id);
    thread.close().await.unwrap();

    let restored =
        ThreadHandle::resume_without_model("background-identities".into(), Some(checkpoint))
            .unwrap();
    let recovered_message = restored.snapshot().inbox.last().unwrap().clone();
    assert!(!old_ids.contains(&recovered_message.message.id));
    assert_eq!(recovered_message.sequence, 66);
    assert_eq!(recovered_message.message.id, message_id);
    assert!(restored.effects().await.unwrap().iter().any(|batch| {
        batch.deliveries.iter().any(|delivery| {
            delivery.call_id == task.call_id && matches!(delivery.outcome, ToolOutcome::Interrupted)
        })
    }));
    restored.close().await.unwrap();
}
