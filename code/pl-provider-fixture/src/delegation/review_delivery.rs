//! Public model-visible exception notifications, separate from submitted reviews.
use super::{flow::*, review_wire::required_option, wire::*};
use anyhow::{Context, Result};
use serde::{Deserialize, Deserializer, Serialize};
use serde_json::json;

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct Exception {
    pub reviewer_id: String,
    pub turn_id: String,
    #[serde(deserialize_with = "required_option")]
    pub input_id: Option<String>,
    pub terminal_sequence: u64,
    pub target_agent_id: String,
    pub feedback_message_id: String,
    pub observation: Observation,
    pub outcome: Outcome,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum Observation {
    LiveTerminal,
    Reconciliation,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "state", rename_all = "camelCase", deny_unknown_fields)]
pub enum Outcome {
    Rejected { reason: Reason },
    Unconfirmed { reason: Reason },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "kind",
    content = "detail",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub enum Reason {
    RecoveryRequiresScheduling,
    MissingFrozenBaseline,
    TargetChanged,
    TargetUnavailable,
    AdmissionRejected(#[serde(deserialize_with = "error_chain")] Vec<String>),
    IdentityConflict,
    IdentityUnverifiable,
    StorageUnavailable(#[serde(deserialize_with = "error_chain")] Vec<String>),
    SendUnconfirmed(#[serde(deserialize_with = "error_chain")] Vec<String>),
    WorkspaceCheckRejected(WorkspaceFailure),
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WorkspaceFailure {
    pub certainty: Certainty,
    #[serde(deserialize_with = "error_chain")]
    pub source: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Certainty {
    Invalid,
    Unconfirmed,
}

fn error_chain<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Vec<String>, D::Error> {
    let chain = Vec::<String>::deserialize(deserializer)?;
    if chain.len() > 8 || chain.iter().any(|text| text.chars().count() > 512) {
        return Err(serde::de::Error::custom(
            "exception source exceeds 8 x 512 Unicode budget",
        ));
    }
    Ok(chain)
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Notice {
    /// Stable identity derived from the observed payload's documented contract,
    /// not a claimed provider-visible inbox receipt/envelope.
    pub exception_id: String,
    pub raw: String,
    pub payload: Exception,
}

impl Exception {
    fn message_id(&self) -> String {
        format!(
            "studio.review-exception.{}:{}:{}:{}:{}:{}:{}",
            self.reviewer_id.len(),
            self.reviewer_id,
            self.turn_id.len(),
            self.turn_id,
            self.terminal_sequence,
            self.target_agent_id.len(),
            self.target_agent_id
        )
    }

    fn validate(&self) -> Result<()> {
        require(
            !self.reviewer_id.is_empty()
                && !self.turn_id.is_empty()
                && self.terminal_sequence > 0
                && !self.target_agent_id.is_empty()
                && self.input_id.as_ref().is_none_or(|id| !id.is_empty())
                && self.feedback_message_id
                    == format!(
                        "studio.review.{}:{}:{}:{}:{}",
                        self.reviewer_id.len(),
                        self.reviewer_id,
                        self.turn_id.len(),
                        self.turn_id,
                        self.terminal_sequence
                    ),
            "exception lost its committed reviewer/Turn/feedback identity",
        )
    }
}

impl Request {
    pub fn review_exceptions(&self) -> Result<Vec<Notice>> {
        let mut notices = Vec::new();
        for raw in self
            .input
            .iter()
            .filter(|item| item.role.as_deref() == Some("user"))
            .filter_map(|item| item.content.as_ref().map(Text::joined))
            .filter(|text| {
                text.trim_start().starts_with('{')
                    && text.contains("\"reviewerId\"")
                    && text.contains("\"terminalSequence\"")
            })
        {
            let payload: Exception = serde_json::from_str(&raw)
                .context("decode production review delivery exception v1")?;
            payload.validate()?;
            let exception_id = payload.message_id();
            require(
                !notices
                    .iter()
                    .any(|notice: &Notice| notice.exception_id == exception_id),
                "duplicate independent review exception notification",
            )?;
            notices.push(Notice {
                exception_id,
                raw,
                payload,
            });
        }
        Ok(notices)
    }
}

pub(super) fn require_none(request: &Request, reviewer: &Spawn) -> Result<()> {
    require(
        !request
            .review_exceptions()?
            .iter()
            .any(|notice| notice.payload.reviewer_id == reviewer.agent_id),
        "unexpected review-delivery exception on a successful/no-wake path",
    )
}

pub(super) fn wait_exception(flow: &Flow<'_>, report: &Report, target: &Spawn) -> Progress<Notice> {
    for index in 0..8 {
        if let Some(notice) = flow
            .request
            .review_exceptions()?
            .into_iter()
            .find(|notice| notice.payload.reviewer_id == report.child_id)
        {
            let exception = &notice.payload;
            require(
                exception.turn_id == report.turn_id
                    && exception.input_id == report.input_id
                    && exception.terminal_sequence == report.commit_sequence
                    && exception.target_agent_id == target.agent_id
                    && exception.observation == Observation::LiveTerminal,
                "exception is not bound to this original review terminal/target",
            )?;
            return Ok(notice);
        }
        flow.raw(
            &format!("rf-exception-wait-{index}"),
            "wait",
            json!({"taskIds":[],"timeoutMs":300000}),
        )?;
    }
    Err(anyhow::anyhow!(
        "original submitted review has no independent exception after bounded waits"
    )
    .into())
}
