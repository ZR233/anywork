//! Stateless authoring preview through the same machine as workflow_transition.
use super::machine::{CompletionInput, TransitionInput, WorkflowMachine, WorkflowOperation};
use super::{
    WorkflowBinding, WorkflowPreviewSnapshot, WorkflowRunLifecycle, WorkflowSessionState, new_run,
};
use crate::PureError;

/// Replays at most 128 direct edges in isolated memory. Natural-language truth is declared by the operator.
pub(crate) fn preview_workflow(
    binding: Option<WorkflowBinding>,
    previous_path: Vec<String>,
    target_state_id: Option<String>,
    reason: String,
) -> Result<WorkflowPreviewSnapshot, PureError> {
    const MAX_PATH_STATES: usize = 128;
    const PREVIEW_TIME: i64 = 0;
    if previous_path
        .len()
        .max(1)
        .saturating_add(usize::from(target_state_id.is_some()))
        > MAX_PATH_STATES
    {
        return Err(PureError::ConfigError(
            "preview path exceeds 128 states; reset the preview".into(),
        ));
    }
    let Some(binding) = binding else {
        return Ok(WorkflowPreviewSnapshot {
            accepted: true,
            message: "该模式没有工作流".into(),
            current_state: None,
            transitions: vec![],
            path: vec![],
            terminal: false,
        });
    };
    let initial_id = binding.graph.definition().initial_state_id.clone();
    let state = WorkflowSessionState {
        revision: 1,
        current_run: Some(new_run(&binding, None, "isolated-preview", PREVIEW_TIME)),
        ..Default::default()
    };
    let mut path = vec![initial_id.clone()];
    if previous_path
        .first()
        .is_some_and(|first| first != &initial_id)
    {
        return Err(PureError::ConfigError(
            "preview path must start at the initial state".into(),
        ));
    }
    let targets = previous_path.into_iter().skip(1).chain(target_state_id);
    let mut machine = WorkflowMachine::new(binding, state);
    let mut accepted = true;
    let mut message = "请选择下一阶段；自然语言条件由操作者判断".to_string();
    for (index, target) in targets.enumerate() {
        let state = machine.state();
        let run = state.current_run.as_ref().expect("preview has a run");
        let result = machine.apply_transition(
            TransitionInput {
                expected_run_id: run.run_id.clone(),
                expected_revision: state.revision,
                expected_state_id: run.current_state_id.clone(),
                target_state_id: target.clone(),
                force: false,
                completion: CompletionInput {
                    reason: reason.clone(),
                    summary: "工作流隔离预演".into(),
                    evidence: vec![],
                },
            },
            &WorkflowOperation {
                turn_id: "preview".into(),
                call_id: index.to_string(),
            },
            format!("preview:{index}:{target}"),
            PREVIEW_TIME,
        )?;
        if !result.accepted {
            accepted = false;
            message = result
                .recovery_action
                .unwrap_or_else(|| result.code.to_string());
            break;
        }
        path.push(target);
    }
    let run = machine
        .state()
        .current_run
        .as_ref()
        .expect("preview has a run");
    let terminal = run.lifecycle == WorkflowRunLifecycle::Terminal;
    if accepted && terminal {
        message = "已到达终态；可重置预演".into();
    }
    let graph = machine.graph();
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
