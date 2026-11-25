//! Studio 对 Thread 领域的产品内置实现。

// 随 Studio 二进制发布的内置 Thread Mode 注册入口。
use std::sync::Arc;

use crate::mode::{
    ThreadModeManager, ThreadModeRegistrySnapshot, ThreadModeSource, ThreadModeSourceId,
    ThreadModeSourceKind,
};
use anyhow::{Context, Result};

const BUILTIN_SOURCE_ID: &str = "studio.builtin";

pub(crate) fn register_builtins(
    manager: &ThreadModeManager,
) -> Result<Arc<ThreadModeRegistrySnapshot>> {
    let registrations = [REGISTRATION]
        .into_iter()
        .map(|registration| registration.to_registration())
        .collect::<Result<Vec<_>, _>>()?;
    manager
        .replace_source(
            ThreadModeSource {
                id: ThreadModeSourceId::new(BUILTIN_SOURCE_ID)?,
                kind: ThreadModeSourceKind::Builtin,
            },
            registrations,
        )
        .context("failed to register built-in Thread Modes")
}

use crate::mode::{
    StaticThreadModeRegistration, StaticWorkflowDefinition, StaticWorkflowState,
    StaticWorkflowTransition,
};
use crate::workflow_tool::WorkflowStateKind;

pub const PROMPT: &str = r#"# Auto 自动模式

你拥有唯一内置的自适应自动工作流（`mode.auto`），以及与工作流独立但协同使用的 `Plan` 状态机。

## 1. 自适应流程分流与设计冲突升级（必须从 `triage` 起步）
- 收到用户请求后，先在 `triage`（需求评估）做最小必要核实，判断复杂度与是否涉及既有设计冲突：
  - **直接处理（`simple`）**：仅限普通问答、查询或单点小修，且同时满足“范围明确、无已有设计/文档/契约冲突、用户未要求先出计划”。完成后经必要验证直接转入 `completed`。
  - **必须进入规划（`planning`）的三类情况**：
    1. 跨模块改造、架构调整、多阶段实施或高风险变更；
    2. **用户明确要求先出计划、先给方案或先讨论**；
    3. **用户要求或候选实现方法与项目已有设计、文档或契约存在冲突**。
  - **中途升级与冲突回退**：在 `simple`、`editing_documents`、`working`、`integrating`、`reviewing` 任一阶段，一旦发现范围/风险超出预期、用户要求出计划，或**发现实现方法与已有设计冲突**，禁止以代码暗中覆盖设计；必须立即暂停受影响修改、保留现场并切入或退回 `planning`。

## 2. 计划阶段规则：先切阶段，再问冲突，再调 `plan_transition` 出 ELI5 计划
- 每个智能体各自持有独立 `Plan` 对象：`plan_transition` 与 `request_user_input` 为**顶层独占工具**（调用时必须独占一次模型响应，严禁与 `exec` 或其他工具同批调用）；`workflow_*` 与 `plan_current` / `plan_next` / `plan_history` 在 Native 模式下通过 `exec` 的 `tools.*`（如 `tools.workflow_transition(args)`、`tools.plan_current({})`——注意其返回 JSON 文本，直接打印或先 `json.decode` 再读 `document.content`）调用，在 ACP/MCP 模式下按对应顶层工具调用。简单路径下无需强制创建计划；**但只要需求属于规划路径或触发冲突升级，必须严格按以下顺序执行**：
  1. **必须先切入 `planning` 阶段**：`plan_transition` 提交确认和 `request_user_input` 提问都会**立即挂起当前轮次等待用户回答**。因此，若当前工作流还在 `triage`（或 `simple` / `working` / `integrating` / `reviewing`），**必须先单独调用一次 `exec` 执行 `return tools.workflow_transition(args)` 把工作流切换至 `planning`**；**严禁**在工作流仍处于 `triage` 等非 `planning` 阶段时提前调用 `request_user_input` 或 `plan_transition`！
  2. **冲突先询问**：进入 `planning` 后，若用户要求或实现方法与已有设计冲突，或存在影响方向的未决取舍，先调用 `request_user_input` 用通俗大白话说明“原设计怎么规定 → 冲突在哪里 → 可选方案与利弊 → 推荐做法”，等待用户决定后再定稿（若用户已在需求中明确方向且无歧义，勿反问“要不要出计划”）。
  3. **必须调用 `plan_transition` 提交确认**：进入 `planning` 且方向明确后，**必须**独占调用 `plan_transition(targetState: "awaitingConfirmation", content: "<完整 Markdown 计划>")` 且保持默认 `force=false` 以向用户发起确认卡片（非交互环境或用户显式声明免确认时才可跳过等待）。**禁止**只在普通正文或 `<proposed_plan>` 标签里写计划而不调 `plan_transition`，**禁止**在提请确认时传入 `force=true`（这会跳过确认交互）。若当前 Plan 已处于 `approved`（例如设计冲突回退重规划），须先调用 `plan_transition(targetState: "drafting")`，再切入 `awaitingConfirmation`。
  4. **计划默认遵循 ELI5 规则**（除非用户另行指定风格）：默认读者没有读过项目代码、不懂内部黑话，用大白话、短句和直白类比写出让非源码读者也能秒懂的计划——先讲“要达到什么效果/解决什么痛点”，再讲“现在怎么运作与哪里卡住或冲突”“关键概念一句话解释”“分步怎么改与为什么”“不做什么、影响边界和取舍”“怎么验证改好了”。文件路径、函数/符号名和命令只作补充定位，不能代替人话解释。

## 3. 审查阶段必须先读 Plan 再安排审查
- 进入 `reviewing` 阶段后，第一步必须读取当前最新 Plan 正文（核对宿主 `studio.plan.document` / `pl.plan` 投影中的 `markdown` 正文；若投影缺失、无正文或不确定是否最新，先通过 `exec` 调用 `tools.plan_current({})`——或按顶层声明调用 `plan_current`——读取权威计划的 `document.content`）。
- 第二步根据 Plan 中的目标、非目标边界、冲突裁定、风险点和验收标准安排审查：委派 `reviewer` 时随完整适用 Plan（及实施期调整）明确写出审查清单——要审什么、怎么核查（重点路径、契约与文档一致性、错误路径、已有与待补证据）、哪些属非目标，以及通过/打回判据；无绑定执行者时，主代理同样按 Plan 逐项核对差异与真实检查输出。

## 4. 工作流推进纪律
- 宿主 `pl.workflow` 投影完整时，直接使用其中的 `runId`、`revision` 与 `currentStateId`，通过 `workflow_transition` 提交 `completion:{reason,summary,evidence}` 推进；仅当投影缺失或发生 CAS 冲突时查询 `workflow_current` / `workflow_next`。默认 `force=false` 沿合法边转换；简单任务完成后须在同轮交付验证后推进至 `completed`。
"#;

const STATES: &[StaticWorkflowState] = &[
    StaticWorkflowState {
        id: "triage",
        title: "需求评估",
        instructions: "快速核实用户目标、约束、影响范围及现有设计与文档。仅当任务范围小、目标明确、与已有设计无冲突且用户未要求先出计划时，先通过 `exec` 调用 `tools.workflow_transition` 沿 `triage -> simple` 切换；凡涉及跨模块/多阶段/重构/高风险、用户要求先出计划，或用户要求/实现方向与已有设计冲突，先通过 `exec` 单独调用 `tools.workflow_transition` 沿 `triage -> planning` 切换。严禁在仍处于 `triage` 时就提前调用 `plan_transition` 或 `request_user_input`（这会立刻挂起等待用户输入导致工作流停在 `triage`）。",
        completion_criteria: &[
            "已完成最小必要核实，明确复杂度结论及是否存在与既有设计的冲突。",
            "已根据复杂度、用户规划要求与设计一致性选择 `simple` 或 `planning`。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "simple",
        title: "直接处理",
        instructions: "直接检查、实施并做必要验证。执行中若发现复杂度、影响范围或风险超出预期，用户要求先出计划，或实现方法/用户要求与项目已有设计或契约冲突，立刻停止受影响修改、保留现场并通过 `simple -> planning` 升级规划；已完成交付且有充分验证事实时通过 `simple -> completed` 结束。",
        completion_criteria: &[
            "简单交付：需求已完成并经必要核验，或已因复杂度/设计冲突/用户要求转入 `planning`。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "planning",
        title: "方案规划",
        instructions: "核对目标、现场代码、相关设计与依赖边界；既有文档与规约均是待核实、可质疑材料，不以旧约定直接否定新需求，也不暗中违背设计。若发现用户要求或候选实现方法与已有设计冲突，或存在影响方向的未决取舍，先调用 `request_user_input` 用通俗大白话讲清“原设计规定、冲突点、可选做法及利弊、推荐选择”，待明确后再定稿。方案清晰后必须调用 `plan_transition(targetState: \"awaitingConfirmation\", content: ..., force: false)` 提交完整 Markdown 计划供用户确认（若原 Plan 已 `approved` 则先切 `drafting` 再切 `awaitingConfirmation`）；严禁只在聊天正文或 `<proposed_plan>` 写计划替代调用工具，严禁传 `force=true` 跳过确认。计划正文默认按 ELI5 规则撰写：假设读者没看过代码，先讲目标效果、现状与冲突、关键概念通俗解释，再列分步做法与理由、非目标与取舍、以及具体可核验的验收标准（路径与代码符号只作定位补充）。待 Plan 达到 `approved` 后（非交互或显式免确认除外），推进至 `editing_documents` 或 `working`。",
        completion_criteria: &[
            "目标、非目标、边界与验收标准清晰有据；若有设计冲突或未决取舍，已先通过 `request_user_input` 询问明确。",
            "已按默认 ELI5 规则调用 `plan_transition(awaitingConfirmation, force=false)` 提交计划且宿主 Plan 为 `approved`（非交互或显式免确认除外）。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "editing_documents",
        title: "文档整理",
        instructions: "按已批准计划同步受影响的设计、接口、协议或配置文档，使设计与计划一致；无契约变化时确认适用性即可，不制造冗余改动，随后推进至 `working`。若梳理文档时发现方案缺口或与既有设计产生新冲突，暂停改写、保留现场并退回 `planning`，先询问用户再重新出计划确认。",
        completion_criteria: &[
            "前向推进：受影响设计与契约文档已与批准计划同步，或已确认无需变更。",
            "冲突返工：已暂停受影响文档改写并保留现场，退回 `planning` 重新询问与规划。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "working",
        title: "执行实现",
        instructions: "严格按已批准计划与既定设计直接实施或协调子智能体完成修改与局部自测。执行期间若发现实现方法与已有设计、契约或已批准计划存在冲突，禁止以代码暗中覆盖设计或擅改方案——立即暂停受影响改动、保留现场与仍有效证据，沿 `working -> planning` 退回规划，先询问用户裁定再重新出计划；若仅需同步既有批准方案内的设计文档，沿 `working -> editing_documents` 处理。",
        completion_criteria: &[
            "前向推进：计划内实现与局部验证已完成，改动归属与实际版本清晰。",
            "设计冲突/返工：受影响实施已暂停并保留现场与有效证据，准备退回 `planning`（询问并重出计划）或 `editing_documents`。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "integrating",
        title: "集成验证",
        instructions: "核对多方修改、构建/生成产物、跨层依赖与联调验证结果；区分可复用有效证据与待补验证，不机械重跑已证明项。实现缺陷回退 `working`；既定方案内文档偏差回退 `editing_documents`；若集成暴露实现方法与已有设计冲突或需调整总体方案，暂停受影响整合、保留现场并退回 `planning`，先询问用户再重新出计划。",
        completion_criteria: &[
            "前向推进：各部分改动已整合且必要联调证据有效，具备整体验收条件。",
            "冲突/返工：受影响整合已暂停并保留现场，明确退回目标及原因。",
        ],
        kind: WorkflowStateKind::Atomic,
    },
    StaticWorkflowState {
        id: "reviewing",
        title: "复核验收",
        instructions: "进入本阶段后先读取当前最新 Plan 正文（核对宿主 `studio.plan.document` / `pl.plan` 投影中的 `markdown` 正文，若投影缺失、无正文或不确定是否最新，先通过 `exec` 调用 `tools.plan_current({})`——返回 JSON 文本，直接打印或用 `json.decode` 读取 `document.content`——或按顶层声明调用 `plan_current` 读取）。根据 Plan 的目标、非目标边界、冲突裁定、风险点与验收标准制定审查清单，据此安排审查：委派 `reviewer` 时，除完整适用 Plan（及调整）外，须明确交代依据 Plan 定制的审查方法、重点核查条目/路径/契约与文档一致性、非目标范围及通过/打回判据；无绑定执行者由主代理直接复核时，同样逐项对照 Plan 与真实代码差异及验证输出。补足尚缺门禁、完成适用子智能体评价并核对资源/临时进程回收。实现未满足 Plan 回退 `working`，文档偏差回退 `editing_documents`，发现设计冲突或根本方案缺陷回退 `planning`（询问并重出计划）；确认无误后进入 `completed`。",
        completion_criteria: &[
            "已读取最新 Plan（`studio.plan.document` / `pl.plan` / `plan_current`）并据此完成或指导 `reviewer` 完成逐项对照审查。",
            "逐项满足 Plan 与用户目标，关键门禁与验证均有真实结果，适用评价及资源/进程回收已完成。",
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
        "triage",
        "simple",
        "任务范围小、目标清晰、与既有设计无冲突且用户未要求先出计划，适合直接处理。",
    ),
    edge(
        "triage",
        "planning",
        "任务涉及跨模块设计/重构/高风险，或用户要求先出计划，或需求与已有设计存在冲突。",
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
        "执行中发现复杂度/风险超预期、用户要求出计划，或需求/实现方法与已有设计冲突，需询问并出计划。",
    ),
    edge("simple", "stopped", "任务被取消或遇到阻塞无法安全继续。"),
    edge(
        "planning",
        "editing_documents",
        "方案与设计冲突已明确，已通过 `plan_transition` 提交 ELI5 计划且宿主 Plan 为 `approved`（非交互或显式免确认除外），需先同步设计/契约文档。",
    ),
    edge(
        "planning",
        "working",
        "方案与设计冲突已明确，已通过 `plan_transition` 提交 ELI5 计划且宿主 Plan 为 `approved`（非交互或显式免确认除外），无需前置改文档可直接实现。",
    ),
    edge("planning", "stopped", "任务已取消或方案无法成立。"),
    edge(
        "editing_documents",
        "working",
        "受影响设计或契约文档已与批准计划同步，可进入代码与功能实现。",
    ),
    edge(
        "editing_documents",
        "planning",
        "梳理文档时发现方案缺口或与既有设计冲突，已暂停改写并回规划询问用户重出计划。",
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
        "实施过程中发现需在既定批准方案内同步修订设计或接口文档。",
    ),
    edge(
        "working",
        "planning",
        "实施时发现实现方法与已有设计冲突或需重整总体方案，已暂停受影响改动保现场，回规划询问并重出计划。",
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
        "集成核对发现设计或契约文档偏差，需要同步更新。",
    ),
    edge(
        "integrating",
        "planning",
        "集成核对暴露与既有设计冲突或需调整总体方案，已暂停受影响整合保现场，回规划询问并重出计划。",
    ),
    edge("integrating", "stopped", "任务已取消或无法完成集成。"),
    edge(
        "reviewing",
        "completed",
        "已读取最新 Plan 并据此完成对照审查，目标、设计一致性与真实门禁验证无误，适用评价及资源回收已完成。",
    ),
    edge(
        "reviewing",
        "working",
        "复核验收发现实现未满足 Plan 或存在缺陷，退回修复并补验。",
    ),
    edge(
        "reviewing",
        "editing_documents",
        "复核验收发现设计或文档偏差，退回更新。",
    ),
    edge(
        "reviewing",
        "planning",
        "复核验收发现与既有设计冲突或根本方案缺陷，退回规划询问用户并重出计划。",
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

const WORKFLOW: StaticWorkflowDefinition = StaticWorkflowDefinition {
    title: "自动",
    goal: "评估任务复杂度并自动选择直接处理（必要时无缝升级规划）或完整任务工程流程，确保可靠交付。",
    initial_state_id: "triage",
    states: STATES,
    transitions: TRANSITIONS,
};

pub(crate) const REGISTRATION: StaticThreadModeRegistration = StaticThreadModeRegistration {
    id: "mode.auto",
    display_name: "自动",
    description: "根据需求复杂度自动选择直接处理或完整规划验证流程，并支持简单处理中途升级规划",
    order: 10,
    prompt: PROMPT,
    workflow: Some(WORKFLOW),
};

#[cfg(test)]
mod tests {
    use crate::mode::{ThreadModeId, ThreadModeManager};
    use crate::studio::thread::register_builtins;
    use crate::workflow_tool::machine::{
        CompletionInput, TransitionInput, WorkflowMachine, WorkflowOperation,
    };
    use crate::workflow_tool::{WorkflowSessionState, new_run};

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
        let binding = mode.workflow_binding().unwrap();

        let make_machine = || {
            let run = new_run(&binding, None, "auto-seed", 1);
            WorkflowMachine::new(
                binding.clone(),
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
            let run = state.current_run.as_ref().unwrap();
            let res = machine
                .apply_transition(
                    TransitionInput {
                        expected_run_id: run.run_id.clone(),
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
                    2,
                )
                .unwrap();
            assert!(res.accepted, "expected {from} -> {to} to succeed");
        };

        // Path A: triage -> simple -> completed
        let mut simple_machine = make_machine();
        step(&mut simple_machine, "triage", "simple", 1);
        step(&mut simple_machine, "simple", "completed", 2);
        assert_eq!(
            simple_machine
                .state()
                .current_run
                .as_ref()
                .unwrap()
                .current_state_id,
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
                .as_ref()
                .unwrap()
                .current_state_id,
            "completed"
        );
    }
}
