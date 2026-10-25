/// 计划确认的归属规则：只有提交计划的那次工具调用拥有计划语义。
///
/// `plan_confirmation` 是**保留的问题 ID**，但它属于普通 payload 里的一条问题标识：
/// 旧历史的普通问答工具曾经复用过它，历史又必须原样只读保留。因此计划语义不能按
/// 问题 ID、标题文案或载荷形状推断——唯一稳定的来源是工具条目自己的权威名称
/// （运行时侧的 `TOOL_PLAN_SUBMIT`）。
library;

/// 提交计划的工具名（与 `pl-studio-runtime` 的 `TOOL_PLAN_SUBMIT` 一致）。
const String planSubmitToolName = 'plan_submit';

/// 该工具名称是否拥有计划确认语义。
///
/// 普通问答工具（例如 `ask_user` / `request_user_input`）即使携带了保留的问题 ID，
/// 也仍然只是普通问答：它既不能被隐藏成“待确认计划”，也不能被渲染成计划回执。
bool ownsPlanConfirmation(String? toolName) => toolName == planSubmitToolName;
