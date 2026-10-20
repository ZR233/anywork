//! Stateless authoring preview through the same machine as workflow_transition.
use crate::workflow_tool::machine::{
    CompletionInput, TransitionInput, WorkflowMachine, WorkflowOperation,
};
use pl_protocol::{
    PureError, WorkflowPreviewRequest, WorkflowPreviewSnapshot, WorkflowSessionState,
};

/// Replays at most 128 direct edges in isolated memory. Natural-language truth is declared by the operator.
pub fn preview_workflow(
    request: WorkflowPreviewRequest,
) -> Result<WorkflowPreviewSnapshot, PureError> {
    if request.path.len() > 128 {
        return Err(PureError::ConfigError(
            "preview path exceeds 128 states; reset the preview".into(),
        ));
    }
    let mode = super::RegisteredThreadMode::from_definition(request.document.definition, 1)
        .map_err(|error| PureError::ConfigError(error.to_string()))?;
    let Some(graph) = mode.workflow() else {
        return Ok(WorkflowPreviewSnapshot {
            accepted: true,
            message: "该模式没有工作流".into(),
            current_state: None,
            transitions: vec![],
            path: vec![],
            terminal: false,
        });
    };
    let initial_id = graph.definition().initial_state_id.clone();
    let mut state = WorkflowSessionState {
        revision: 1,
        current_run: Some(super::new_run(&mode, graph, None, "isolated-preview", 0)),
        ..Default::default()
    };
    let mut path = vec![initial_id.clone()];
    if request
        .path
        .first()
        .is_some_and(|first| first != &initial_id)
    {
        return Err(PureError::ConfigError(
            "preview path must start at the initial state".into(),
        ));
    }
    let mut targets = request.path.iter().skip(1).cloned().collect::<Vec<_>>();
    if let Some(target) = request.target_state_id {
        targets.push(target);
    }
    if targets.len() > 127 {
        return Err(PureError::ConfigError(
            "preview path exceeds 128 states; reset the preview".into(),
        ));
    }
    let mut machine = WorkflowMachine::new(mode.clone(), state.clone());
    let mut accepted = true;
    let mut message = "请选择下一阶段；自然语言条件由操作者判断".to_string();
    for (index, target) in targets.into_iter().enumerate() {
        let run = state.current_run.as_ref().expect("preview has a run");
        let result = machine.apply_transition(
            TransitionInput {
                expected_run_id: run.run_id.clone(),
                expected_revision: state.revision,
                expected_state_id: run.current_state_id.clone(),
                target_state_id: target.clone(),
                completion: CompletionInput {
                    reason: request.reason.clone(),
                    summary: "工作流隔离预演".into(),
                    evidence: vec![],
                },
            },
            &WorkflowOperation {
                turn_id: "preview".into(),
                call_id: index.to_string(),
            },
            format!("preview:{index}:{target}"),
        )?;
        if !result.accepted {
            accepted = false;
            message = result
                .recovery_action
                .unwrap_or_else(|| result.code.to_string());
            break;
        }
        state = machine.state();
        path.push(target);
    }
    let run = state.current_run.as_ref().expect("preview has a run");
    let terminal = run.lifecycle == pl_protocol::WorkflowRunLifecycle::Terminal;
    if accepted && terminal {
        message = "已到达终态；可重置预演".into();
    }
    Ok(WorkflowPreviewSnapshot {
        accepted,
        message,
        current_state: graph.state(&run.current_state_id).cloned(),
        transitions: graph
            .outgoing(&run.current_state_id)
            .into_iter()
            .cloned()
            .collect(),
        path,
        terminal,
    })
}
