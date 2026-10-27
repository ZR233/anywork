//! Typed copies of observed receipts, not an alternative product state store.
use super::*;

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Receipt {
    pub root_agent_id: String,
    pub phase: String,
    pub evidence: Evidence,
}

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Evidence {
    pub checkpoints: Vec<Checkpoint>,
    pub children: Vec<Child>,
    pub closes: Vec<Close>,
    pub admissions: Vec<Admission>,
    pub reopened: Vec<Reopened>,
    pub no_head: Option<no_head::NoHeadEvidence>,
    pub not_present: Vec<absent::AbsentCase>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Checkpoint {
    pub label: String,
    pub git: Git,
}

impl Evidence {
    pub fn checkpoint(&mut self, label: &str, git: Git) {
        self.checkpoints.push(Checkpoint {
            label: label.into(),
            git,
        });
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SpawnIdentity {
    pub agent_id: String,
    pub profile_id: String,
    pub model: Route,
    pub message_accepted: bool,
    pub message_sequence: Option<u64>,
}

impl SpawnIdentity {
    pub fn as_spawn(&self) -> Spawn {
        Spawn {
            agent_id: self.agent_id.clone(),
            profile_id: self.profile_id.clone(),
            model: self.model.clone(),
            message_accepted: self.message_accepted,
            message_sequence: self.message_sequence,
        }
    }
}

impl From<Spawn> for SpawnIdentity {
    fn from(spawn: Spawn) -> Self {
        Self {
            agent_id: spawn.agent_id,
            profile_id: spawn.profile_id,
            model: spawn.model,
            message_accepted: spawn.message_accepted,
            message_sequence: spawn.message_sequence,
        }
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Child {
    pub spawn: SpawnIdentity,
    pub report: TerminalReport,
    pub git: Git,
    pub evaluation: Evaluation,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct TerminalReport {
    pub child_id: String,
    pub commit_sequence: u64,
    pub turn: TerminalTurn,
    pub message: String,
    pub messages: Vec<Delivery>,
    pub running_tasks: Vec<String>,
    pub pending_interactions: Vec<String>,
    pub permissions: Vec<PermissionEvidence>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct TerminalTurn {
    pub input_id: Option<String>,
    pub turn_id: String,
    pub state: CompletedState,
}

#[derive(Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
pub(super) enum CompletedState {
    Finished(String),
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Delivery {
    id: String,
    source_id: String,
    sequence: u64,
    consumed: bool,
}

#[derive(Serialize, Deserialize)]
pub(super) struct PermissionEvidence {
    state: ObservedPermission,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum ObservedPermission {
    Pending,
    Allowed,
    Denied,
    Cancelled,
}

impl TerminalReport {
    pub fn observed(report: Report) -> Result<Self> {
        report.completed()?;
        let TurnState::Finished(outcome) = report.turn.state else {
            anyhow::bail!("terminal report changed after validation")
        };
        Ok(Self {
            child_id: report.child_id,
            commit_sequence: report.commit_sequence,
            turn: TerminalTurn {
                input_id: report.turn.input_id,
                turn_id: report.turn.turn_id,
                state: CompletedState::Finished(outcome),
            },
            message: report.message,
            messages: report
                .messages
                .into_iter()
                .map(|message| Delivery {
                    id: message.id,
                    source_id: message.source_id,
                    sequence: message.sequence,
                    consumed: message.consumed,
                })
                .collect(),
            running_tasks: report.running_tasks,
            pending_interactions: report.pending_interactions,
            permissions: report
                .permissions
                .into_iter()
                .map(|permission| PermissionEvidence {
                    state: match permission.state {
                        PermissionState::Pending => ObservedPermission::Pending,
                        PermissionState::Allowed => ObservedPermission::Allowed,
                        PermissionState::Denied => ObservedPermission::Denied,
                        PermissionState::Cancelled => ObservedPermission::Cancelled,
                    },
                })
                .collect(),
        })
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Close {
    pub label: String,
    pub force: bool,
    pub result: Closed,
    pub tool_output: String,
    pub git: Git,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(super) struct DirectoryIdentity {
    pub id: String,
    pub parent_id: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Admission {
    pub label: String,
    pub before: Git,
    pub after: Git,
    pub directory_before: Vec<DirectoryIdentity>,
    pub directory_after: Vec<DirectoryIdentity>,
    pub rejection: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Reopened {
    pub child_id: String,
    pub turn_id: String,
    pub close: Closed,
    pub refused_send: RefusedSend,
    pub git: Git,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct RefusedSend {
    call_id: String,
    tool: String,
    target: String,
    tool_error: String,
    provider_requests_before: usize,
    provider_requests_after: usize,
    before: ClosedIdentity,
    after: ClosedIdentity,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClosedIdentity {
    target: String,
    parent_agent_id: String,
    model: Route,
    turn_id: String,
    lifecycle: Lifecycle,
    pending_inputs: usize,
    running_tasks: usize,
}
