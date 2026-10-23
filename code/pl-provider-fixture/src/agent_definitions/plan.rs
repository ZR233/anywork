use super::wire;
use crate::{RealtimeToolCall, Reply, responses_text, responses_tool_calls};
use anyhow::{Context, Result, ensure};
use serde_json::{Value, json};
use std::collections::BTreeMap;

pub const ROOT_MODEL: &str = "agent-root";
pub const COMPACT_MODEL: &str = "agent-root-compact";
pub const CHILD_MODEL: &str = "agent-system-child";
pub const USER_MODEL_OLD: &str = "agent-user-old";
pub const USER_MODEL_NEW: &str = "agent-user-new";
pub const UNAVAILABLE_MODEL: &str = "agent-withdrawn";
pub const USER_PROFILE: &str = "observe-user";
pub const DISABLED_PROFILE: &str = "observe-disabled";
pub const UNAVAILABLE_PROFILE: &str = "observe-unavailable";

/// Finite phases, not a registry of arbitrary scripts.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum AgentPhase {
    MainFirst,
    FeishuFirst,
    CatalogFrozen,
    CatalogEmpty,
    CatalogRestored,
    RefuseMain,
    RefuseFeishu,
    RefuseWritable,
    RefuseReview,
    MainTask,
    FeishuTask,
    CompactMain,
    CompactFeishu,
    SpawnSystem,
    SpawnUser,
    ChildSystem,
    ChildUser,
    ColdCatalog,
    ColdFeishu,
    ResumeSystem,
    ResumeUser,
    ChildSystemResumed,
    ChildUserResumed,
}

impl AgentPhase {
    pub const ALL: &'static [Self] = &[
        Self::MainFirst,
        Self::FeishuFirst,
        Self::CatalogFrozen,
        Self::CatalogEmpty,
        Self::CatalogRestored,
        Self::RefuseMain,
        Self::RefuseFeishu,
        Self::RefuseWritable,
        Self::RefuseReview,
        Self::MainTask,
        Self::FeishuTask,
        Self::CompactMain,
        Self::CompactFeishu,
        Self::SpawnSystem,
        Self::SpawnUser,
        Self::ChildSystem,
        Self::ChildUser,
        Self::ColdCatalog,
        Self::ColdFeishu,
        Self::ResumeSystem,
        Self::ResumeUser,
        Self::ChildSystemResumed,
        Self::ChildUserResumed,
    ];

    pub const fn marker(self) -> &'static str {
        match self {
            Self::MainFirst => "[[agent_main_first]]",
            Self::FeishuFirst => "[[agent_feishu_first]]",
            Self::CatalogFrozen => "[[agent_catalog_frozen]]",
            Self::CatalogEmpty => "[[agent_catalog_empty]]",
            Self::CatalogRestored => "[[agent_catalog_restored]]",
            Self::RefuseMain => "[[agent_refuse_main]]",
            Self::RefuseFeishu => "[[agent_refuse_feishu]]",
            Self::RefuseWritable => "[[agent_refuse_writable]]",
            Self::RefuseReview => "[[agent_refuse_review]]",
            Self::MainTask => "[[agent_main_task]]",
            Self::FeishuTask => "[[agent_feishu_task]]",
            Self::CompactMain => "agent-summary-main",
            Self::CompactFeishu => "agent-summary-feishu",
            Self::SpawnSystem => "[[agent_spawn_system]]",
            Self::SpawnUser => "[[agent_spawn_user]]",
            Self::ChildSystem => "[[agent_child_system]]",
            Self::ChildUser => "[[agent_child_user]]",
            Self::ColdCatalog => "[[agent_cold_catalog]]",
            Self::ColdFeishu => "[[agent_cold_feishu]]",
            Self::ResumeSystem => "[[agent_resume_system]]",
            Self::ResumeUser => "[[agent_resume_user]]",
            Self::ChildSystemResumed => "[[agent_child_system_resumed]]",
            Self::ChildUserResumed => "[[agent_child_user_resumed]]",
        }
    }

    pub const fn expected_attempts(self) -> usize {
        match self {
            Self::CatalogFrozen
            | Self::CatalogEmpty
            | Self::CatalogRestored
            | Self::ColdCatalog
            | Self::RefuseMain
            | Self::RefuseFeishu
            | Self::RefuseWritable
            | Self::RefuseReview => 2,
            Self::SpawnSystem | Self::SpawnUser | Self::ResumeSystem | Self::ResumeUser => 3,
            _ => 1,
        }
    }

    pub const fn is_gated(self) -> bool {
        matches!(
            self,
            Self::CatalogFrozen
                | Self::CompactMain
                | Self::CompactFeishu
                | Self::ChildSystem
                | Self::ChildUser
                | Self::ChildSystemResumed
                | Self::ChildUserResumed
        )
    }

    pub fn action_call(self) -> String {
        format!("agent-{self:?}-action")
    }

    pub fn wait_call(self) -> String {
        format!("agent-{self:?}-wait")
    }

    pub fn child_phase(self) -> Option<Self> {
        match self {
            Self::SpawnSystem => Some(Self::ChildSystem),
            Self::SpawnUser => Some(Self::ChildUser),
            Self::ResumeSystem => Some(Self::ChildSystemResumed),
            Self::ResumeUser => Some(Self::ChildUserResumed),
            _ => None,
        }
    }

    pub fn profile(self) -> Option<&'static str> {
        match self {
            Self::SpawnSystem
            | Self::ResumeSystem
            | Self::ChildSystem
            | Self::ChildSystemResumed => Some("explorer"),
            Self::SpawnUser | Self::ResumeUser | Self::ChildUser | Self::ChildUserResumed => {
                Some(USER_PROFILE)
            }
            _ => None,
        }
    }

    pub fn report(self) -> String {
        format!("agent-report-{self:?}")
    }
}

pub(super) fn reply(
    phase: AgentPhase,
    ordinal: usize,
    body: &Value,
    children: &mut BTreeMap<String, String>,
    child_turns: &BTreeMap<AgentPhase, (String, String)>,
) -> Result<Reply> {
    use AgentPhase::*;
    let model = body
        .get("model")
        .and_then(Value::as_str)
        .context("model missing")?;
    if ordinal == 0 {
        return match phase {
            CatalogFrozen | CatalogEmpty | CatalogRestored | ColdCatalog => {
                call(phase, "list_agent_profiles", json!({}), model)
            }
            RefuseMain | RefuseFeishu | RefuseWritable | RefuseReview => {
                let profile = match phase {
                    RefuseMain => "root:main",
                    RefuseFeishu => "root:feishu",
                    RefuseWritable => "explorer",
                    _ => "reviewer",
                };
                let mut args = json!({"profileId": profile, "taskSummary": "Rejected Agent probe", "message": "No child may execute this rejected probe."});
                if phase == RefuseWritable {
                    args["writablePaths"] = json!([]);
                }
                call(phase, "spawn_agent", args, model)
            }
            SpawnSystem | SpawnUser => {
                let child = phase.child_phase().context("spawn child phase missing")?;
                let mut args = json!({
                    "profileId": phase.profile().context("spawn Profile missing")?,
                    "taskSummary": format!("Agent observation {child:?}"),
                    "message": format!("{} Finish this synthetic read-only observation without any file mutation.", child.marker()),
                    "metadata": {"syntheticObservation": "agent-definitions"},
                });
                if phase == SpawnUser {
                    args["writablePaths"] = json!(["owned"]);
                }
                call(phase, "spawn_agent", args, model)
            }
            ResumeSystem | ResumeUser => {
                let profile = phase.profile().context("resume Profile missing")?;
                let target = children
                    .get(profile)
                    .context("resume has no original spawn receipt")?;
                let child = phase.child_phase().context("resume child phase missing")?;
                call(
                    phase,
                    "send_message",
                    json!({
                        "target": target,
                        "message": format!("{} Continue the original child; do not create any Agent or mutate files.", child.marker()),
                    }),
                    model,
                )
            }
            ChildSystem | ChildUser | ChildSystemResumed | ChildUserResumed => {
                ensure!(
                    !wire::declared(body, "spawn_agent"),
                    "child has spawn capability"
                );
                // A natural final closes this model step without a tool task
                // still running at the report's commit point. The strict
                // parent oracle requires the actual report to own no tasks.
                Ok(Reply::Sse(responses_text(
                    &phase.report(),
                    &format!("{phase:?}"),
                    model,
                )))
            }
            CompactMain | CompactFeishu => Ok(Reply::Sse(responses_text(
                phase.marker(),
                &format!("{phase:?}"),
                model,
            ))),
            _ => Ok(Reply::Sse(responses_text(
                &format!("Agent observation {phase:?} complete."),
                &format!("{phase:?}"),
                model,
            ))),
        };
    }
    let output = wire::tool_output(body, &phase.action_call())?;
    if let Some(child) = phase.child_phase() {
        let profile = phase.profile().context("delegated Profile missing")?;
        if ordinal == 1 {
            if matches!(phase, SpawnSystem | SpawnUser) {
                #[derive(serde::Deserialize)]
                #[serde(rename_all = "camelCase")]
                struct Receipt {
                    agent_id: String,
                    profile_id: String,
                    message_accepted: bool,
                }
                let receipt: Receipt = serde_json::from_str(output).context("real spawn result")?;
                ensure!(
                    receipt.message_accepted
                        && receipt.profile_id == profile
                        && !receipt.agent_id.is_empty(),
                    "invalid spawn receipt"
                );
                ensure!(
                    children.insert(profile.into(), receipt.agent_id).is_none(),
                    "Profile spawned twice"
                );
            }
            return Ok(Reply::Sse(responses_tool_calls(
                &format!("{phase:?}-wait"),
                model,
                &[RealtimeToolCall {
                    item_id: &phase.wait_call(),
                    call_id: &phase.wait_call(),
                    name: "wait",
                    arguments: json!({"taskIds": [], "timeoutMs": 45000}).to_string(),
                }],
            )));
        }
        wire::tool_output(body, &phase.wait_call())?;
        let id = children
            .get(profile)
            .context("child identity missing at completion")?;
        let (turn_child, turn) = child_turns
            .get(&child)
            .context("public current child Turn was never bound")?;
        ensure!(turn_child == id, "bound Turn belongs to a different child");
        wire::child_report(body, id, turn, &child.report())?;
    }
    Ok(Reply::Sse(responses_text(
        &format!("Agent observation {phase:?} complete."),
        &format!("{phase:?}-done"),
        model,
    )))
}

fn call(phase: AgentPhase, name: &str, arguments: Value, model: &str) -> Result<Reply> {
    let id = phase.action_call();
    Ok(Reply::Sse(responses_tool_calls(
        &format!("{phase:?}"),
        model,
        &[RealtimeToolCall {
            item_id: &id,
            call_id: &id,
            name,
            arguments: arguments.to_string(),
        }],
    )))
}
