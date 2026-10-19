//! Thread Mode authoring validation and canonicalization.

use std::collections::HashSet;

use pl_protocol::{
    ThreadModeDocument, ThreadModeEditorLayout, ThreadModeValidationIssue,
    ThreadModeValidationResult,
};

use super::{RegisteredThreadMode, ThreadModeManagerError as ManagerError};

/// Upper bound for one persisted or submitted Mode document.
pub(crate) const MAX_MODE_DOCUMENT_BYTES: usize = 256 * 1024;
const MAX_LAYOUT_ABSOLUTE_COORDINATE: f64 = 1_000_000.0;

/// Validate and canonicalize one complete authoring document.
///
/// Execution fields and the workflow are compiled by the same registration
/// path used by the runtime manager. Editor layout is validated against the
/// compiled workflow but never participates in the graph hash.
pub fn validate_mode_document(
    document: ThreadModeDocument,
) -> Result<ThreadModeDocument, Vec<ThreadModeValidationIssue>> {
    let registered =
        RegisteredThreadMode::from_definition(document.definition, 1).map_err(manager_issues)?;
    let definition = registered.definition();
    let mut issues = Vec::new();
    let editor = canonical_editor(document.editor, definition.workflow.as_ref(), &mut issues);
    let canonical = ThreadModeDocument { definition, editor };
    match serde_json::to_vec(&canonical) {
        Ok(bytes) if bytes.len() > MAX_MODE_DOCUMENT_BYTES => issues.push(issue(
            "tooLarge",
            "$",
            format!(
                "Mode document exceeds the {MAX_MODE_DOCUMENT_BYTES} byte limit after canonicalization"
            ),
        )),
        Ok(_) => {}
        Err(error) => issues.push(issue(
            "invalidDocument",
            "$",
            format!("Mode document cannot be serialized: {error}"),
        )),
    }
    if issues.is_empty() {
        Ok(canonical)
    } else {
        Err(issues)
    }
}

/// Parse and validate JSON authored by the editor.
pub fn validate_mode_json(json: &str) -> ThreadModeValidationResult {
    if json.len() > MAX_MODE_DOCUMENT_BYTES {
        return ThreadModeValidationResult {
            document: None,
            issues: vec![issue(
                "tooLarge",
                "$",
                format!("Mode JSON exceeds the {MAX_MODE_DOCUMENT_BYTES} byte limit"),
            )],
        };
    }
    let value = match serde_json::from_str::<serde_json::Value>(json) {
        Ok(value) => value,
        Err(error) => {
            return ThreadModeValidationResult {
                document: None,
                issues: vec![issue("invalidJson", "$", error.to_string())],
            };
        }
    };
    let mut shape_issues = Vec::new();
    reject_unknown_fields(&value, &mut shape_issues);
    if !shape_issues.is_empty() {
        return ThreadModeValidationResult {
            document: None,
            issues: shape_issues,
        };
    }
    let document = match serde_json::from_value::<ThreadModeDocument>(value) {
        Ok(document) => document,
        Err(error) => {
            return ThreadModeValidationResult {
                document: None,
                issues: vec![issue("invalidJson", "$", error.to_string())],
            };
        }
    };
    match validate_mode_document(document) {
        Ok(document) => ThreadModeValidationResult {
            document: Some(document),
            issues: Vec::new(),
        },
        Err(issues) => ThreadModeValidationResult {
            document: None,
            issues,
        },
    }
}

/// Return the canonical JSON Schema plus the semantic constraints enforced
/// after structural deserialization.
pub fn mode_document_schema() -> String {
    let mut schema = serde_json::to_value(schemars::schema_for!(ThreadModeDocument))
        .expect("Thread Mode JSON Schema must serialize");
    let Some(object) = schema.as_object_mut() else {
        return schema.to_string();
    };
    object.insert(
        "$comment".into(),
        serde_json::Value::String(
            "execution fields are id, displayName, description, order, prompt and workflow; editor.nodes is layout metadata only".into(),
        ),
    );
    object.insert(
        "x-anywork-semanticConstraints".into(),
        serde_json::json!([
            "workflow states and transitions are compiled before publication",
            "state IDs and transitions are unique and bounded",
            "the initial state and every transition endpoint must exist",
            "atomic states require completion criteria and final states have no outgoing transitions",
            "every state must be reachable from the initial state and able to reach a final state",
            "editor nodes have unique existing state IDs and finite bounded coordinates",
            "unknown fields are rejected at every document level",
            "editor layout is excluded from the compiled workflow graph hash"
        ]),
    );
    serde_json::to_string_pretty(&schema).expect("Thread Mode JSON Schema must serialize")
}

fn canonical_editor(
    mut editor: ThreadModeEditorLayout,
    workflow: Option<&pl_protocol::WorkflowDefinition>,
    issues: &mut Vec<ThreadModeValidationIssue>,
) -> ThreadModeEditorLayout {
    let state_ids = workflow
        .map(|workflow| {
            workflow
                .states
                .iter()
                .map(|state| state.id.as_str())
                .collect::<HashSet<_>>()
        })
        .unwrap_or_default();
    if workflow.is_none() && !editor.nodes.is_empty() {
        issues.push(issue(
            "noWorkflow",
            "editor.nodes",
            "layout nodes require a workflow",
        ));
    }
    if editor.nodes.len() > super::MAX_WORKFLOW_STATES {
        issues.push(issue(
            "tooMany",
            "editor.nodes",
            format!(
                "layout may contain at most {} nodes",
                super::MAX_WORKFLOW_STATES
            ),
        ));
    }
    let mut seen = HashSet::new();
    for (index, node) in editor.nodes.iter_mut().enumerate() {
        node.state_id = node.state_id.trim().to_string();
        if node.state_id.is_empty() {
            issues.push(issue(
                "required",
                format!("editor.nodes[{index}].stateId"),
                "layout node stateId must not be empty",
            ));
        } else if !state_ids.contains(node.state_id.as_str()) {
            issues.push(issue(
                "unknownState",
                format!("editor.nodes[{index}].stateId"),
                format!("layout references unknown state `{}`", node.state_id),
            ));
        }
        if !seen.insert(node.state_id.clone()) {
            issues.push(issue(
                "duplicate",
                format!("editor.nodes[{index}].stateId"),
                format!("layout duplicates state `{}`", node.state_id),
            ));
        }
        for (field, value) in [("x", node.x), ("y", node.y)] {
            if !value.is_finite() || value.abs() > MAX_LAYOUT_ABSOLUTE_COORDINATE {
                issues.push(issue(
                    "invalidCoordinate",
                    format!("editor.nodes[{index}].{field}"),
                    format!(
                        "layout coordinate must be finite and within ±{MAX_LAYOUT_ABSOLUTE_COORDINATE}"
                    ),
                ));
            }
        }
        if node.x == 0.0 && node.x.is_sign_negative() {
            node.x = 0.0;
        }
        if node.y == 0.0 && node.y.is_sign_negative() {
            node.y = 0.0;
        }
    }
    editor
        .nodes
        .sort_by(|left, right| left.state_id.cmp(&right.state_id));
    editor
}

fn manager_issues(error: ManagerError) -> Vec<ThreadModeValidationIssue> {
    match error {
        ManagerError::InvalidWorkflow { source, .. } => source
            .issues()
            .iter()
            .map(|issue| ThreadModeValidationIssue {
                code: issue.code.to_string(),
                path: issue.path.clone(),
                message: issue.message.clone(),
            })
            .collect(),
        ManagerError::InvalidRegistration { message, .. } => {
            vec![issue("invalidRegistration", "$", message)]
        }
        ManagerError::DuplicateInBatch { mode_id, .. } => vec![issue(
            "duplicate",
            "id",
            format!("Mode `{mode_id}` is duplicated"),
        )],
        other => vec![issue("invalidMode", "$", other.to_string())],
    }
}

fn reject_unknown_fields(value: &serde_json::Value, issues: &mut Vec<ThreadModeValidationIssue>) {
    let Some(document) = value.as_object() else {
        return;
    };
    reject_object_keys(
        document,
        &[
            "id",
            "displayName",
            "description",
            "order",
            "prompt",
            "workflow",
            "editor",
        ],
        "$",
        issues,
    );
    if let Some(workflow) = document.get("workflow").and_then(|value| value.as_object()) {
        reject_object_keys(
            workflow,
            &["title", "goal", "initialStateId", "states", "transitions"],
            "workflow",
            issues,
        );
        for (index, state) in workflow
            .get("states")
            .and_then(|value| value.as_array())
            .into_iter()
            .flatten()
            .enumerate()
            .filter_map(|(index, value)| value.as_object().map(|object| (index, object)))
        {
            reject_object_keys(
                state,
                &["id", "title", "instructions", "completionCriteria", "kind"],
                &format!("workflow.states[{index}]"),
                issues,
            );
        }
        for (index, transition) in workflow
            .get("transitions")
            .and_then(|value| value.as_array())
            .into_iter()
            .flatten()
            .enumerate()
            .filter_map(|(index, value)| value.as_object().map(|object| (index, object)))
        {
            reject_object_keys(
                transition,
                &["sourceStateId", "targetStateId", "guard"],
                &format!("workflow.transitions[{index}]"),
                issues,
            );
        }
    }
    if let Some(editor) = document.get("editor").and_then(|value| value.as_object()) {
        reject_object_keys(editor, &["nodes"], "editor", issues);
        for (index, node) in editor
            .get("nodes")
            .and_then(|value| value.as_array())
            .into_iter()
            .flatten()
            .enumerate()
            .filter_map(|(index, value)| value.as_object().map(|object| (index, object)))
        {
            reject_object_keys(
                node,
                &["stateId", "x", "y"],
                &format!("editor.nodes[{index}]"),
                issues,
            );
        }
    }
}

fn reject_object_keys(
    object: &serde_json::Map<String, serde_json::Value>,
    allowed: &[&str],
    path: &str,
    issues: &mut Vec<ThreadModeValidationIssue>,
) {
    for key in object.keys().filter(|key| !allowed.contains(&key.as_str())) {
        issues.push(issue(
            "unknownField",
            format!("{path}.{key}"),
            format!("unknown field `{key}`"),
        ));
    }
}

fn issue(
    code: impl Into<String>,
    path: impl Into<String>,
    message: impl Into<String>,
) -> ThreadModeValidationIssue {
    ThreadModeValidationIssue {
        code: code.into(),
        path: path.into(),
        message: message.into(),
    }
}
