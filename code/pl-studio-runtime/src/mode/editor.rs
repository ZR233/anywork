//! Thread Mode authoring validation and canonicalization.

use std::collections::HashSet;

use crate::mode::{
    ThreadModeDocument, ThreadModeEditorLayout, ThreadModeValidationIssue,
    ThreadModeValidationResult, WorkflowPreviewRequest, WorkflowPreviewSnapshot,
};
use crate::workflow_tool::{MAX_WORKFLOW_STATES, WorkflowDefinition};

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
    let (definition, editor) = document.into_parts();
    let registered =
        RegisteredThreadMode::from_definition(definition, 1).map_err(manager_issues)?;
    let definition = registered.definition();
    let mut issues = Vec::new();
    let editor = canonical_editor(editor, definition.workflow.as_ref(), &mut issues);
    let canonical = ThreadModeDocument::from_parts(definition, editor);
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
    let document = match serde_json::from_str::<ThreadModeDocument>(json) {
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

/// Compiles an editor draft and replays its workflow in an isolated machine.
pub fn preview_workflow(
    request: WorkflowPreviewRequest,
) -> Result<WorkflowPreviewSnapshot, crate::PureError> {
    let (definition, _) = request.document.into_parts();
    let mode = RegisteredThreadMode::from_definition(definition, 1)
        .map_err(|error| crate::PureError::ConfigError(error.to_string()))?;
    crate::workflow_tool::preview_workflow(
        mode.workflow_binding(),
        request.path,
        request.target_state_id,
        request.reason,
    )
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
    workflow: Option<&WorkflowDefinition>,
    issues: &mut Vec<ThreadModeValidationIssue>,
) -> ThreadModeEditorLayout {
    let state_ids = workflow.map(|workflow| {
        workflow
            .states
            .iter()
            .map(|state| state.id.as_str())
            .collect::<HashSet<_>>()
    });
    if workflow.is_none() && !editor.nodes.is_empty() {
        issues.push(issue(
            "noWorkflow",
            "editor.nodes",
            "layout nodes require a workflow",
        ));
    }
    if editor.nodes.len() > MAX_WORKFLOW_STATES {
        issues.push(issue(
            "tooMany",
            "editor.nodes",
            format!("layout may contain at most {MAX_WORKFLOW_STATES} nodes"),
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
        } else if let Some(state_ids) = &state_ids {
            if !state_ids.contains(node.state_id.as_str()) {
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
