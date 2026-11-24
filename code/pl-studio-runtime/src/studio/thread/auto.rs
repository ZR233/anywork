use crate::mode::{
    StaticThreadModeRegistration, StaticWorkflowDefinition, StaticWorkflowState,
    StaticWorkflowTransition,
};
use crate::workflow_tool::WorkflowStateKind;

pub const PROMPT: &str = r#"# Auto 自动模式

你拥有唯一内置的自适应自动工作流（`mode.auto`），以及与工作流完全解耦的独立 `Plan` 状态机。

## 1. 自适应流程分叉（必须从 `triage` 起步评估）
- 收到用户请求后，先在 `triage`（需求评估）判断复杂度与风险：
  - **简单需求**（普通问答、查询、单点小修、范围完全明确且无需正式设计/计划确认）：调用 `workflow_transition` 切换到 `simple`（直接处理），直接完成修改或答复并验证后转入 `completed`。
  - **简单中途升级**：若在 `simple` 执行过程中发现范围扩大、跨模块耦合或需要系统设计与确认，可随时通过 `workflow_transition` 直接从 `simple` 转入 `planning`（方案规划）。
  - **复杂需求**（跨模块改造、架构重构、高风险变更或需多阶段拆解/协作验收）：从 `triage` 转入 `planning`，依次按 `planning` → `editing_documents`/`working` → `integrating` → `reviewing` → `completed` 推进，并按需沿返工边回退或委派子智能体。

## 2. 独立 Plan 状态机（与工作流解耦）
- 每个智能体（根与子）均各自持有一个独立 `Plan` 对象（`plan_current`、`plan_next`、`plan_history`、`plan_transition`），不与工作流强绑定。
- 仅在复杂方案需要用户审批确认或明确阶段化追踪时，才调用 `plan_transition`（例如带完整 Markdown `content` 切到 `awaitingConfirmation`）；简单任务无需强制创建或确认计划。
- 使用 `plan_transition`（以及 `workflow_transition`）时默认 `force=false`，必须沿合法路径切换；若切入非法目标会返回允许的候选状态与全部有效状态提示；仅在确需绕过状态规则强制纠正时，才显式传 `force=true`。

## 3. 工作流状态与结束规则
- 当宿主的 workflow 投影完整时直接使用其中的 `runId`、`revision` 与 `currentStateId`，通过 `workflow_transition` 提交 `completion:{reason,summary,evidence}` 推进；仅当投影缺失或发生 CAS 冲突时查询 `workflow_current` / `workflow_next`。
- 简单任务可在首次答复/完成修改的同一轮次内推进到 `simple` 并在交付验证后转入 `completed`；禁止停留或遗忘推进最终状态。
"#;

const STATES: &[StaticWorkflowState] = &[
    StaticWorkflowState {
        id: "triage",
        title: "需求评估",
        instructions: "快速理解用户目标、约束和涉及范围。若目标明确、风险低且无需正式规划或设计协同，沿 `triage -> simple` 直接处理；若涉及跨模块设计、多阶段实施、重构或需方案确认，沿 `triage -> planning` 进入正式规划流程。",
        completion_criteria: &[
            "已完成最小必要核实，明确任务复杂度结论。",
            "已选择 `simple`（直接处理）或 `planning`（方案规划）路径。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "simple",
        title: "直接处理",
        instructions: "直接检查、实施并做必要验证，不必机械走重型计划审批流程。如发现实际复杂度、影响范围或风险超出预期，立刻通过 `simple -> planning` 转入正式规划；已完成交付且有充分事实时通过 `simple -> completed` 结束。",
        completion_criteria: &["简单交付：需求已直接完成并经过必要核验，或转入 `planning` 继续。"],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "planning",
        title: "方案规划",
        instructions: "核对目标、现场代码、相关设计与依赖边界；任何既有文档和规约均是待核实材料。复杂任务可按需使用独立 `plan_transition` 记录方案或提交确认；无额外设计确认需求时可直接推进至 `editing_documents` 或 `working`。",
        completion_criteria: &[
            "目标、非目标、边界与验收标准清晰且有事实依据。",
            "如需用户确认计划，已通过独立 `plan_transition` 完成确认。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "editing_documents",
        title: "文档整理",
        instructions: "若方案涉及架构、接口、协议或配置契约变化，先同步相关设计文档或技能说明；无契约变化时确认适用性即可，直接推进至 `working`。",
        completion_criteria: &["受影响设计与契约文档已同步，或已确认无需变更。"],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "working",
        title: "执行实现",
        instructions: "按既定方案直接实施或协调子智能体并行/隔离完成修改与局部自测。发现设计偏差或需补充规划时，沿返工边回退到 `editing_documents` 或 `planning`。",
        completion_criteria: &[
            "前向推进：目标实现与局部验证已完成，改动归属清晰。",
            "返工回退：受影响工作已收敛并保留现场。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "integrating",
        title: "集成验证",
        instructions: "核对多方修改、构建产物、跨层依赖与集成测试结果，确认无冲突和遗漏。实现缺陷回退 `working`，设计偏差回退 `editing_documents` 或 `planning`。",
        completion_criteria: &["前向推进：各部分改动已集成并完成必要联调验证，具备整体验收条件。"],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "reviewing",
        title: "复核验收",
        instructions: "对照用户原始目标、代码差异与真实测试/检查输出做最终交付核验；补足尚缺的门禁检查并核对资源/临时进程回收。发现问题可退回 `working` / `editing_documents` / `planning`，确认无误后进入 `completed`。",
        completion_criteria: &["逐项满足用户目标，关键门禁与验证均有真实结果且未遗留运行进程。"],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "completed",
        title: "已完成",
        instructions: "",
        completion_criteria: &[],
        kind: WorkflowStateKind::Final,
    },
    StaticWorkflowState {
        id: "stopped",
        title: "已停止",
        instructions: "",
        completion_criteria: &[],
        kind: WorkflowStateKind::Final,
    },
];

const TRANSITIONS: &[StaticWorkflowTransition] = &[
    edge(
        "triage",
        "simple",
        "任务范围小、目标清晰、无需正式规划与文档协同，适合直接处理。",
    ),
    edge(
        "triage",
        "planning",
        "任务涉及跨模块设计、重构、高风险修改或需要正式规划与分阶段验证。",
    ),
    edge(
        "triage",
        "stopped",
        "任务已取消或缺少必要授权/前提无法继续。",
    ),
    edge(
        "simple",
        "completed",
        "直接处理与必要验证已完成，可以向用户交付结果。",
    ),
    edge(
        "simple",
        "planning",
        "直接处理中途发现复杂度、耦合度或风险超出预期，需升级转入正式规划。",
    ),
    edge("simple", "stopped", "任务被取消或遇到阻塞无法安全继续。"),
    edge(
        "planning",
        "editing_documents",
        "方案已明确，且需要先同步设计/接口/配置契约文档。",
    ),
    edge(
        "planning",
        "working",
        "方案已明确且无需前置文档修改，可直接进入执行实现。",
    ),
    edge("planning", "stopped", "任务已取消或方案无法成立。"),
    edge(
        "editing_documents",
        "working",
        "受影响设计或契约文档已同步，可进入代码与功能实现。",
    ),
    edge(
        "editing_documents",
        "planning",
        "梳理文档时发现方案存在缺口，需要回到规划调整。",
    ),
    edge(
        "editing_documents",
        "stopped",
        "任务已取消或设计无法达成一致。",
    ),
    edge(
        "working",
        "integrating",
        "核心实现完成，需跨模块整合、代码生成或联合验证。",
    ),
    edge(
        "working",
        "reviewing",
        "实现范围集中、无需额外集成步骤，可直接进入复核验收。",
    ),
    edge(
        "working",
        "editing_documents",
        "实施过程中发现需修订设计或接口契约。",
    ),
    edge(
        "working",
        "planning",
        "实施过程中发现架构或总体方案需重新规划。",
    ),
    edge("working", "stopped", "任务已取消或无法继续实现。"),
    edge(
        "integrating",
        "reviewing",
        "集成与跨模块联调通过，具备最终复核验收条件。",
    ),
    edge(
        "integrating",
        "working",
        "集成核对发现实现缺陷，需要退回修改。",
    ),
    edge(
        "integrating",
        "editing_documents",
        "集成核对发现设计或契约偏差，需要修改文档。",
    ),
    edge("integrating", "planning", "集成核对发现需要调整整体方案。"),
    edge("integrating", "stopped", "任务已取消或无法完成集成。"),
    edge(
        "reviewing",
        "completed",
        "对照目标与真实检查结果确认交付完整无误。",
    ),
    edge(
        "reviewing",
        "working",
        "复核验收发现实现问题，退回修复并补验。",
    ),
    edge(
        "reviewing",
        "editing_documents",
        "复核验收发现设计或文档偏差，退回更新。",
    ),
    edge(
        "reviewing",
        "planning",
        "复核验收发现根本方案缺陷，退回重新规划。",
    ),
    edge("reviewing", "stopped", "任务已取消或无法通过验收。"),
];

const fn edge(
    source_state_id: &'static str,
    target_state_id: &'static str,
    guard: &'static str,
) -> StaticWorkflowTransition {
    StaticWorkflowTransition {
        source_state_id,
        target_state_id,
        guard,
    }
}

pub const WORKFLOW: StaticWorkflowDefinition = StaticWorkflowDefinition {
    title: "自动",
    goal: "评估任务复杂度并自动选择直接处理（必要时无缝升级规划）或完整任务工程流程，确保可靠交付。",
    initial_state_id: "triage",
    states: STATES,
    transitions: TRANSITIONS,
};

pub const REGISTRATION: StaticThreadModeRegistration = StaticThreadModeRegistration {
    id: "mode.auto",
    display_name: "自动",
    description: "根据需求复杂度自动选择直接处理或完整规划验证流程，并支持简单处理中途升级规划",
    order: 10,
    prompt: PROMPT,
    workflow: Some(WORKFLOW),
};

#[cfg(test)]
mod tests {
    use crate::mode::{ThreadModeId, ThreadModeManager, new_run};
    use crate::studio::thread::register_builtins;
    use crate::workflow_tool::WorkflowSessionState;
    use crate::workflow_tool::machine::{
        CompletionInput, TransitionInput, WorkflowMachine, WorkflowOperation,
    };

    #[test]
    fn only_mode_auto_is_registered_as_builtin() {
        let manager = ThreadModeManager::default();
        let snapshot = register_builtins(&manager).expect("register builtins");
        let ids: Vec<_> = snapshot
            .catalog()
            .modes
            .iter()
            .map(|item| item.id.as_str().to_owned())
            .collect();
        assert_eq!(ids, vec!["mode.auto"]);
    }

    #[test]
    fn auto_workflow_supports_simple_and_escalation_to_planning() {
        let manager = ThreadModeManager::default();
        let snapshot = register_builtins(&manager).expect("register builtins");
        let mode = snapshot.mode(&ThreadModeId::auto()).unwrap().clone();
        let compiled = mode.workflow().unwrap();

        let make_machine = || {
            let run = new_run(&mode, compiled, None, "auto-seed", 1);
            WorkflowMachine::new(
                mode.clone(),
                WorkflowSessionState {
                    revision: 1,
                    current_run: Some(run),
                    archived_runs: Vec::new(),
                    archived_run_count: 0,
                    archived_run_digest: String::new(),
                    operation_receipts: Vec::new(),
                },
            )
        };
        let step = |machine: &mut WorkflowMachine, from: &str, to: &str, idx: usize| {
            let state = machine.state();
            let run = state.current_run.unwrap();
            let res = machine
                .apply_transition(
                    TransitionInput {
                        expected_run_id: run.run_id,
                        expected_revision: state.revision,
                        expected_state_id: from.into(),
                        target_state_id: to.into(),
                        force: false,
                        completion: CompletionInput {
                            reason: format!("{from} -> {to}"),
                            summary: "ok".into(),
                            evidence: vec!["verified".into()],
                        },
                    },
                    &WorkflowOperation {
                        turn_id: "t".into(),
                        call_id: format!("c{idx}"),
                    },
                    format!("h{idx}"),
                )
                .unwrap();
            assert!(res.accepted, "expected {from} -> {to} to succeed");
        };

        // Path A: triage -> simple -> completed
        let mut simple_machine = make_machine();
        step(&mut simple_machine, "triage", "simple", 1);
        step(&mut simple_machine, "simple", "completed", 2);
        assert_eq!(
            simple_machine.state().current_run.unwrap().current_state_id,
            "completed"
        );

        // Path B: triage -> simple -> planning -> editing_documents -> working -> integrating -> reviewing -> completed
        let mut escalated_machine = make_machine();
        step(&mut escalated_machine, "triage", "simple", 1);
        step(&mut escalated_machine, "simple", "planning", 2);
        step(&mut escalated_machine, "planning", "editing_documents", 3);
        step(&mut escalated_machine, "editing_documents", "working", 4);
        step(&mut escalated_machine, "working", "integrating", 5);
        step(&mut escalated_machine, "integrating", "reviewing", 6);
        step(&mut escalated_machine, "reviewing", "completed", 7);
        assert_eq!(
            escalated_machine
                .state()
                .current_run
                .unwrap()
                .current_state_id,
            "completed"
        );
    }
}
