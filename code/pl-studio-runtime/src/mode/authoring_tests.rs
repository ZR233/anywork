use super::{ThreadModeDocument, WorkflowPreviewRequest, preview_workflow, validate_mode_json};
use serde_json::{Value, json};

fn workflow_document() -> Value {
    json!({
        "id": "mode.authoring-test",
        "displayName": "Authoring",
        "description": "Test layout and preview",
        "order": 1,
        "prompt": "Follow the workflow",
        "workflow": {
            "title": "Review",
            "goal": "Review and complete",
            "initialStateId": "review",
            "states": [
                {"id": "review", "title": "Review", "instructions": "Review", "completionCriteria": ["Reviewed"], "kind": "atomic"},
                {"id": "done", "title": "Done", "instructions": "", "kind": "final"}
            ],
            "transitions": [
                {"sourceStateId": "review", "targetStateId": "review", "guard": "Review again"},
                {"sourceStateId": "review", "targetStateId": "done", "guard": "Reviewed"}
            ]
        },
        "editor": {"nodes": [{"stateId": "review", "x": 1, "y": 2}]}
    })
}

#[test]
fn flat_mode_json_rejects_unknown_fields_in_document_and_nested_objects() {
    let valid = workflow_document();
    let parsed = validate_mode_json(&valid.to_string()).document.unwrap();
    let encoded = serde_json::to_value(parsed).unwrap();
    assert_eq!(encoded["id"], "mode.authoring-test");
    assert_eq!(encoded["workflow"]["initialStateId"], "review");
    assert!(encoded.get("definition").is_none());

    for path in [
        "",
        "/workflow/states/0",
        "/workflow/transitions/0",
        "/editor/nodes/0",
    ] {
        let mut value = valid.clone();
        value.pointer_mut(path).unwrap()["extra"] = true.into();
        let json = value.to_string();
        assert!(
            serde_json::from_str::<ThreadModeDocument>(&json).is_err(),
            "{path}"
        );
        let result = validate_mode_json(&json);
        assert!(result.document.is_none(), "{path}");
        assert!(
            result.issues[0].message.contains("unknown field `extra`"),
            "{path}"
        );
    }
}

#[test]
fn layout_errors_describe_missing_workflow_and_empty_state_ids() {
    let mut value = workflow_document();
    value["workflow"] = Value::Null;
    let result = validate_mode_json(&value.to_string());
    let codes: Vec<_> = result
        .issues
        .iter()
        .map(|issue| issue.code.as_str())
        .collect();
    assert_eq!(codes, ["noWorkflow"]);

    let mut value = workflow_document();
    value["editor"]["nodes"] = json!([
        {"stateId": "", "x": 1, "y": 2},
        {"stateId": " ", "x": 3, "y": 4}
    ]);
    let result = validate_mode_json(&value.to_string());
    let codes: Vec<_> = result
        .issues
        .iter()
        .map(|issue| issue.code.as_str())
        .collect();
    assert_eq!(codes, ["required", "required"]);
}

#[test]
fn description_limit_applies_to_the_persisted_trimmed_value() {
    let mut value = workflow_document();
    let max = "字".repeat(1365) + "a";
    value["description"] = json!(format!("  {max}  "));
    let validated = validate_mode_json(&value.to_string()).document.unwrap();
    assert_eq!(validated.description, max);

    value["description"] = json!(format!("{max}b"));
    let result = validate_mode_json(&value.to_string());
    assert!(result.document.is_none());
    assert!(result.issues[0].message.contains("4096 bytes"));
}

#[test]
fn preview_is_replayable_and_counts_the_next_target_in_its_limit() -> anyhow::Result<()> {
    let document = serde_json::from_value(workflow_document())?;
    let mut request = WorkflowPreviewRequest {
        document,
        path: vec!["review".into(); 127],
        target_state_id: Some("done".into()),
        reason: "Review complete".into(),
    };
    let result = preview_workflow(request.clone())?;
    assert!(result.accepted && result.terminal);
    assert_eq!(result.path.len(), 128);
    assert_eq!(result.path.last().map(String::as_str), Some("done"));
    assert_eq!(preview_workflow(request.clone())?, result);

    request.path.push("review".into());
    let error = preview_workflow(request).unwrap_err();
    assert!(error.to_string().contains("exceeds 128 states"));
    Ok(())
}
