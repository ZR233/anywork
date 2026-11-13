use crate::mode::{ThreadModeDefinition, ThreadModeId, WorkflowDefinition};

pub(crate) fn definition() -> ThreadModeDefinition {
    ThreadModeDefinition {
        id: ThreadModeId::new("mode.review").unwrap(),
        display_name: "Review".into(),
        description: "Review before delivery".into(),
        order: 1,
        prompt: "Follow the review workflow.".into(),
        workflow: Some(graph()),
    }
}

pub(crate) fn graph() -> WorkflowDefinition {
    serde_json::from_value(serde_json::json!({
        "title": "Review",
        "goal": "Deliver reviewed changes",
        "initialStateId": "review",
        "states": [
            {"id":"review", "title":"Review", "instructions":"Inspect the changes",
             "completionCriteria":["Checks passed"], "kind":"atomic"},
            {"id":"done", "title":"Done", "instructions":"Report the outcome",
             "completionCriteria":[], "kind":"final"}
        ],
        "transitions": [
            {"sourceStateId":"review", "targetStateId":"review", "guard":"More review is needed"},
            {"sourceStateId":"review", "targetStateId":"done", "guard":"Review passed"}
        ]
    }))
    .unwrap()
}
