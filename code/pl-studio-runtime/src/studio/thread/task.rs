use crate::mode::{
    StaticThreadModeRegistration, StaticWorkflowDefinition, StaticWorkflowState,
    StaticWorkflowTransition,
};
use pl_protocol::WorkflowStateKind;

pub const PROMPT: &str = r#"# Task 任务模式

你负责一项 canonical task。角色职责与协作遵循共用系统合同；阶段工作只以最新宿主 workflow 投影的指令、完成标准和直接出边为准，不另建交付状态或固定分工流程。

投影完整时直接使用其中的 runId、revision 和状态，不重复查询；信息缺失或 CAS 冲突时才用 workflow 查询恢复。通过 workflow_transition 沿直接边提交 completion:{reason,summary,evidence}，不跳阶段、不虚报不适用操作。workflow_restart 仅用于明确的新尝试。Plan 确认由独立 plan_* 状态机管理，已有批准不会因压缩或阶段返工失效。
"#;

const STATES: &[StaticWorkflowState] = &[
    StaticWorkflowState {
        id: "planning",
        title: "规划",
        instructions: "核对目标、现有设计和现场；只澄清无法从事实推断且影响目标或关键决定的问题。按需直接取证或委派只读探索，不重复已有调查。计划完整后直接 plan_submit，不先询问是否继续。",
        completion_criteria: &[
            "目标、非目标及授权范围明确，方案有事实依据。",
            "计划说明所有权、必要依赖与验收；简单任务不机械建立 DAG。",
            "当前宿主 Plan 状态为 approved。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "editing_documents",
        title: "更新设计文档",
        instructions: "按角色保留职责先同步受影响的权威设计，使其与批准计划一致；无契约变化只核对适用性，不制造文档改动。具体实现留在代码。",
        completion_criteria: &[
            "受影响设计已同步，或已确认无需变更。",
            "设计与计划一致，不存在阻塞实施的未决契约。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "working",
        title: "委派实施",
        instructions: "按已确定契约实施，优先处理关键依赖和已就绪成果；具体分工由根智能体按交付收益选择。出现实质阻塞按共用合同裁定。确认需改设计时暂停受影响实施，沿返工边回 editing_documents，不必等待全部实现完成。",
        completion_criteria: &[
            "前向推进：计划实现已交付，版本、依赖和写入责任可核对。",
            "前向推进：已有验证及审查证据有效，后续集中验收事项已明确交接，无须先裁决的阻塞。",
            "设计返工：可不满足前向条件；受影响实施已暂停，现场和仍有效证据保留。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "integrating",
        title: "核对成果",
        instructions: "核对计划成果、实际版本、依赖及已选择的整合操作；directory 成果不制造合入。区分有效复用与待执行证据，不因换阶段重跑检查。实现缺陷回 working；确认设计问题时暂停受影响工作，直接回 editing_documents。",
        completion_criteria: &[
            "前向推进：计划成果和实际整合操作已完成，当前版本及工作区归属清楚。",
            "前向推进：已执行、有效复用与待执行的验收事项有明确交接，返工现场可用。",
            "设计返工：可不满足前向条件；受影响实施已暂停，现场和仍有效证据保留。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "reviewing",
        title: "整体验收",
        instructions: "根智能体对照完整目标、计划、当前差异和证据作交付判断；只补尚缺且适用的检查，不复制各执行者已完成的验证。实现缺陷回 working，设计偏差回 editing_documents。",
        completion_criteria: &[
            "目标与实际交付逐项对应，无未解决的设计或实现问题。",
            "用户明确要求、适用项目门禁及已安排的审查均有当前有效证据；未覆盖范围如实说明。",
            "交付及返修已结束，评价与资源回收遵循共用合同并有真实结果。",
        ],
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
        "planning",
        "editing_documents",
        "完整计划有事实依据，且宿主 Plan 状态为 approved。",
    ),
    edge("planning", "stopped", "任务已取消或无法安全继续。"),
    edge(
        "editing_documents",
        "working",
        "受影响设计已与批准计划同步，无阻塞实施的未决契约。",
    ),
    edge(
        "editing_documents",
        "stopped",
        "任务已取消或无法形成一致设计。",
    ),
    edge(
        "working",
        "integrating",
        "实现成果、实际版本及必要交接已就绪，无须先裁决的阻塞。",
    ),
    edge(
        "working",
        "editing_documents",
        "已确认需要设计修订，受影响实施已暂停，现场与有效证据保留。",
    ),
    edge("working", "stopped", "任务已取消或实施无法安全继续。"),
    edge("integrating", "working", "交付核对发现实现缺陷或缺失成果。"),
    edge(
        "integrating",
        "reviewing",
        "成果、依赖、版本及实际整合操作已核对，具备最终验收条件。",
    ),
    edge(
        "integrating",
        "editing_documents",
        "已确认需要设计修订，受影响实施已暂停，现场与有效证据保留。",
    ),
    edge(
        "integrating",
        "stopped",
        "任务已取消或无法安全完成成果核对。",
    ),
    edge(
        "reviewing",
        "working",
        "审查或必要验收发现实现缺陷，需要修复并补充受影响证据。",
    ),
    edge(
        "reviewing",
        "editing_documents",
        "验收发现架构或契约缺陷，需要修改设计。",
    ),
    edge(
        "reviewing",
        "completed",
        "根智能体已依据真实证据确认交付满足要求，无未解决问题，必要资源回收已确认。",
    ),
    edge("reviewing", "stopped", "任务已取消或无法安全完成最终验收。"),
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
    title: "任务",
    goal: "由根智能体规划、设计、协调现有执行者与审查者并综合验收，按用户目标完成任务。",
    initial_state_id: "planning",
    states: STATES,
    transitions: TRANSITIONS,
};

pub const REGISTRATION: StaticThreadModeRegistration = StaticThreadModeRegistration {
    id: "mode.task",
    display_name: "任务",
    description: "由根智能体协调现有执行者与审查者，完成任务设计、实施调度和独立验收",
    order: 20,
    prompt: PROMPT,
    workflow: Some(WORKFLOW),
};
