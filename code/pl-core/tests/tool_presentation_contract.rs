//! Presentation evidence follows the frozen request, not a later tool-directory lookup.
use pl_core::{
    context::OpaquePayload,
    model::{
        DynModelSession, ModelError, ModelRequest, ModelSession, ModelToolCall, PreparedModelCall,
        ToolPresentationContract,
    },
    thread::{ThreadCheckpoint, ThreadHandle, TurnOutcome},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, Tool, ToolError},
    },
};
use std::sync::{Arc, Mutex};
use tokio::sync::oneshot;

mod support;

struct FrozenRequestModel {
    entered: Option<oneshot::Sender<()>>,
    release: Option<oneshot::Receiver<()>>,
    requests: Arc<Mutex<Vec<ModelRequest>>>,
}

impl ModelSession for FrozenRequestModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        self.requests.lock().unwrap().push(request.clone());
        let entered = self.entered.take();
        let release = self.release.take();
        Ok(PreparedModelCall::new(async move {
            let calls = if let Some(entered) = entered {
                let declaration = &request.tools[0];
                let call = ModelToolCall {
                    call_id: "frozen-call".into(),
                    tool_id: declaration.tool_id.clone(),
                    arguments: OpaquePayload::text("  original bytes\n"),
                    rejection: None,
                    presentation_contract: declaration.presentation_contract.clone(),
                };
                entered.send(()).unwrap();
                release.unwrap().await.unwrap();
                vec![call]
            } else {
                vec![]
            };
            Ok(support::response(&request, calls))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[derive(Debug)]
struct RecordingTool {
    generation: &'static str,
    events: Arc<Mutex<Vec<String>>>,
}

impl Tool for RecordingTool {
    async fn execute(&self, input: OpaquePayload, _: CallContext) -> Result<ToolOutput, ToolError> {
        self.events
            .lock()
            .unwrap()
            .push(format!("execute:{}", self.generation));
        Ok(ToolOutput::new(
            input.clone(),
            vec![support::text(input.content())],
        ))
    }

    async fn close(&self) -> Result<(), ToolError> {
        self.events
            .lock()
            .unwrap()
            .push(format!("close:{}", self.generation));
        Ok(())
    }
}

fn registration(generation: &'static str, events: &Arc<Mutex<Vec<String>>>) -> Registration {
    Registration::new(
        "same-tool".into(),
        OpaquePayload::text("unchanged declaration"),
        RecordingTool {
            generation,
            events: events.clone(),
        },
    )
    .unwrap()
    .foreground_coexisting()
}

#[tokio::test]
async fn hot_refresh_preserves_frozen_marker_executor_and_saved_context() {
    let (entered, observed) = oneshot::channel();
    let (release, held) = oneshot::channel();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let events = Arc::new(Mutex::new(Vec::new()));
    let contract = ToolPresentationContract::new("vendor.unknown@任意值");
    let thread = ThreadHandle::start(
        "presentation".into(),
        DynModelSession::new(FrozenRequestModel {
            entered: Some(entered),
            release: Some(held),
            requests: requests.clone(),
        }),
    )
    .unwrap();
    thread
        .register_tools(vec![
            registration("original", &events).with_presentation_contract(contract.clone()),
        ])
        .await
        .unwrap();
    let active = thread.clone();
    let turn = tokio::spawn(async move { active.run_turn(support::turn("frozen")).await });
    tokio::time::timeout(std::time::Duration::from_secs(5), observed)
        .await
        .unwrap()
        .unwrap();
    // Only the presentation contract and executor generation change. The old call keeps its lease.
    thread
        .register_tools(vec![registration("replacement", &events)])
        .await
        .unwrap();
    assert!(events.lock().unwrap().is_empty());
    release.send(()).unwrap();
    let completion = turn.await.unwrap().unwrap();
    assert_eq!(completion.outcome, TurnOutcome::Completed);
    {
        let requests = requests.lock().unwrap();
        assert_eq!(requests.len(), 2);
        assert_eq!(
            requests[0].tools[0].presentation_contract.as_ref(),
            Some(&contract)
        );
        assert_eq!(
            requests[1].tools[0].presentation_contract,
            Some(ToolPresentationContract::generic())
        );
        let mut legacy_declaration = serde_json::to_value(&requests[0].tools[0]).unwrap();
        assert!(
            legacy_declaration
                .as_object_mut()
                .unwrap()
                .remove("presentationContract")
                .is_some()
        );
        let legacy_declaration: pl_core::model::ModelToolDeclaration =
            serde_json::from_value(legacy_declaration).unwrap();
        assert_eq!(legacy_declaration.presentation_contract, None);
        assert_eq!(
            legacy_declaration.declaration,
            requests[0].tools[0].declaration
        );
    }
    let before = thread.snapshot().context;
    let calls = before
        .records
        .iter()
        .flat_map(|record| record.tool_calls.iter())
        .collect::<Vec<_>>();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].presentation_contract.as_ref(), Some(&contract));
    assert_eq!(calls[0].arguments.content(), "  original bytes\n");
    let saved = serde_json::to_vec(
        &thread
            .checkpoint(thread.snapshot().commit_sequence)
            .unwrap(),
    )
    .unwrap();
    thread.close().await.unwrap();
    let events_before_restore = events.lock().unwrap().clone();
    assert_eq!(
        events_before_restore,
        ["execute:original", "close:original", "close:replacement"]
    );
    let (model, observed) = support::ScriptedModel::new(&[]);
    let restored = ThreadHandle::resume(
        "presentation".into(),
        DynModelSession::new(model),
        Some(serde_json::from_slice(&saved).unwrap()),
    )
    .unwrap();
    assert_eq!(restored.snapshot().context, before);
    restored
        .run_turn(support::turn("after-restore"))
        .await
        .unwrap();
    assert_eq!(
        &observed.lock().unwrap()[0].records[..before.records.len()],
        before.records.as_ref()
    );
    assert_eq!(*events.lock().unwrap(), events_before_restore);
    restored.close().await.unwrap();

    // Missing fields in actual saved call envelopes remain None, without consulting registrations.
    let mut legacy: serde_json::Value = serde_json::from_slice(&saved).unwrap();
    let mut removed = 0;
    for record in legacy["state"]["context"]["records"]
        .as_array_mut()
        .unwrap()
    {
        if let Some(calls) = record
            .get_mut("toolCalls")
            .and_then(serde_json::Value::as_array_mut)
        {
            for call in calls {
                assert!(
                    call.as_object_mut()
                        .unwrap()
                        .remove("presentationContract")
                        .is_some()
                );
                removed += 1;
            }
        }
    }
    assert_eq!(removed, 1);
    let legacy: ThreadCheckpoint = serde_json::from_value(legacy).unwrap();
    let restored = ThreadHandle::resume_without_model("presentation".into(), Some(legacy)).unwrap();
    let context = restored.snapshot().context;
    let calls = context
        .records
        .iter()
        .flat_map(|record| &record.tool_calls)
        .collect::<Vec<_>>();
    assert_eq!(calls.len(), 1);
    assert_eq!(calls[0].presentation_contract, None);
    assert_eq!(calls[0].arguments.content(), "  original bytes\n");
    assert_eq!(*events.lock().unwrap(), events_before_restore);
    restored.close().await.unwrap();
}
