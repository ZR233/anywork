use super::*;
use crate::mode::{
    SavedThreadMode, ThreadModeId, ThreadModeManager, encode_mode_snapshot,
    workflow_binding_from_snapshot,
};
use crate::studio::thread::register_builtins;
use crate::workflow_tool::new_run;
use pl_core::thread::extensions::{ExtensionMutation, ExtensionRecord};
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::sync::Arc;

fn call_context(active: bool) -> CallContext {
    let modes = ThreadModeManager::default();
    let snapshot = register_builtins(&modes).unwrap();
    let mode = snapshot.mode(&ThreadModeId::auto()).unwrap();
    let saved_mode = SavedThreadMode::capture(&mode, None);
    let state = WorkflowSessionState {
        revision: 1,
        current_run: active.then(|| new_run(&mode.workflow_binding().unwrap(), None, "test", 100)),
        ..Default::default()
    };
    CallContext {
        thread_id: "workflow-thread".into(),
        turn_id: "workflow-turn".into(),
        call_id: "workflow-call".into(),
        cancellation: Default::default(),
        extensions: Arc::new(BTreeMap::from([
            (
                MODE_EXTENSION.into(),
                ExtensionRecord {
                    revision: 0,
                    payload: encode_mode_snapshot(&saved_mode).unwrap(),
                },
            ),
            (
                WORKFLOW_EXTENSION.into(),
                ExtensionRecord {
                    revision: 0,
                    payload: encode_workflow_state(&state).unwrap(),
                },
            ),
        ])),
        catalog: Arc::from([]),
        extension_sequence: 0,
        grant: Default::default(),
        context: Default::default(),
        history_fence: 0,
        model_projection: None,
        tasks: None,
    }
}

fn declared_shape<'a>(schema: &'a Value, data: &Value) -> &'a Value {
    let fields = data
        .as_object()
        .expect("workflow program data is an object");
    let variants = schema["anyOf"]
        .as_array()
        .map_or(std::slice::from_ref(schema), Vec::as_slice);
    variants
        .iter()
        .find(|variant| {
            let properties = variant["properties"].as_object().unwrap();
            fields.keys().all(|name| properties.contains_key(name))
                && variant["required"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .all(|name| fields.contains_key(name.as_str().unwrap()))
        })
        .unwrap_or_else(|| panic!("no declared shape for data {data} in {schema}"))
}

async fn invoke(
    kind: WorkflowOperationKind,
    input: Value,
    context: &CallContext,
) -> (ToolOutput, ToolDefinition) {
    let definition = kind.definition().unwrap();
    let tool = ThreadWorkflowTool {
        definition: definition.clone(),
        kind,
        resolve_workflow: workflow_binding_from_snapshot,
    };
    let raw = OpaquePayload::new("application/json", 1, input.to_string()).unwrap();
    let output = tool.execute(raw, context.clone()).await.unwrap();
    declared_shape(definition.output_schema().unwrap(), output.data().unwrap());
    (output, definition)
}

#[tokio::test]
async fn workflow_queries_declare_their_own_active_and_inactive_data() {
    let inactive = call_context(false);
    let active = call_context(true);
    for kind in [
        WorkflowOperationKind::Current,
        WorkflowOperationKind::Next,
        WorkflowOperationKind::History,
    ] {
        let (output, definition) = invoke(kind, json!({}), &inactive).await;
        let data = output.data().unwrap();
        assert_eq!(data.get("currentRun"), Some(&Value::Null));
        let shape = declared_shape(definition.output_schema().unwrap(), data);
        assert_eq!(shape["properties"]["currentRun"]["type"], "null");
        assert!(output.extension_mutations().is_empty());

        let (output, _) = invoke(kind, json!({}), &active).await;
        let data = output.data().unwrap();
        assert!(data["runId"].as_str().is_some());
        match kind {
            WorkflowOperationKind::Current => assert_eq!(data["currentState"]["id"], "triage"),
            WorkflowOperationKind::Next => assert!(
                data["transitions"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|edge| edge["targetStateId"] == "simple")
            ),
            WorkflowOperationKind::History => assert_eq!(data["history"], json!([])),
            _ => unreachable!(),
        }
    }

    let (graph, _) = invoke(WorkflowOperationKind::Graph, json!({}), &active).await;
    assert_eq!(
        graph.data().unwrap()["definition"]["initialStateId"],
        "triage"
    );
}

#[tokio::test]
async fn workflow_mutations_declare_distinct_acceptance_and_cas_rejection() {
    let mut context = call_context(true);
    let (current, _) = invoke(WorkflowOperationKind::Current, json!({}), &context).await;
    let current = current.data().unwrap();
    let (transition, definition) = invoke(
        WorkflowOperationKind::Transition,
        json!({
            "expectedRunId": current["runId"],
            "expectedRevision": 1,
            "expectedStateId": "triage",
            "targetStateId": "simple",
            "completion": {"reason": "small task", "summary": "scope confirmed"}
        }),
        &context,
    )
    .await;
    let data = transition.data().unwrap();
    assert_eq!(data["accepted"], true);
    assert_eq!(data["code"], "transitioned");
    assert_eq!(data["snapshot"]["currentStateId"], "simple");
    assert_eq!(data["operationRevision"], 2);
    let shape = declared_shape(definition.output_schema().unwrap(), data);
    assert_eq!(shape["properties"]["accepted"]["const"], true);
    assert!(shape["properties"]["snapshot"]["$ref"].is_string());
    let [
        ExtensionMutation::Put {
            id,
            expected_revision,
            payload,
        },
    ] = transition.extension_mutations()
    else {
        panic!("a successful transition must update the Workflow extension");
    };
    assert_eq!(id, WORKFLOW_EXTENSION);
    assert_eq!(*expected_revision, Some(0));
    Arc::make_mut(&mut context.extensions).insert(
        id.clone(),
        ExtensionRecord {
            revision: 1,
            payload: payload.clone(),
        },
    );
    context.call_id = "workflow-restart".into();

    let mut restart = json!({
        "expectedRunId": current["runId"],
        "expectedRevision": 1,
        "expectedStateId": "simple",
        "reason": "start a new task"
    });
    let (rejected, definition) =
        invoke(WorkflowOperationKind::Restart, restart.clone(), &context).await;
    let rejection = rejected.data().unwrap();
    assert_eq!(rejection["accepted"], false);
    assert_eq!(rejection["error"]["code"], "staleRevision");
    assert_eq!(rejection["snapshot"], data["snapshot"]);
    assert!(rejected.extension_mutations().is_empty());
    let schema = definition.output_schema().unwrap();
    let shape = declared_shape(schema, rejection);
    assert_eq!(shape["properties"]["accepted"]["const"], false);
    assert_eq!(
        schema["$defs"]["WorkflowTransitionError"]["properties"]["recoveryAction"]["type"],
        "string"
    );

    restart["expectedRevision"] = json!(2);
    let (restarted, _) = invoke(WorkflowOperationKind::Restart, restart, &context).await;
    let data = restarted.data().unwrap();
    assert_eq!(data["code"], "restarted");
    assert_eq!(data["operationRevision"], 3);
    assert_eq!(data["snapshot"]["currentStateId"], "triage");
    assert_ne!(data["snapshot"]["runId"], current["runId"]);
    assert!(matches!(
        restarted.extension_mutations(),
        [ExtensionMutation::Put {
            expected_revision: Some(1),
            ..
        }]
    ));
}
