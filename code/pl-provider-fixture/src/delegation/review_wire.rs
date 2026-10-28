//! Thin typed consumption of the current host review projection and public history.
use super::{flow::require, wire::*};
use anyhow::{Context, Result};
use serde::{Deserialize, Deserializer, Serialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Disposition {
    Approved,
    NeedsChanges,
    Inconclusive,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct Review {
    #[serde(deserialize_with = "required_option")]
    pub target: Option<Target>,
    pub disposition: Disposition,
    pub summary: String,
    #[serde(deserialize_with = "required_option")]
    pub reviewed_version: Option<String>,
    #[serde(deserialize_with = "required_option")]
    pub reason: Option<ConclusionReason>,
    pub full_report: Location,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Target {
    pub agent_id: String,
    pub feedback: Option<Feedback>,
    pub baseline: Option<Baseline>,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum Feedback {
    ToExecutor,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Baseline {
    pub turn_id: String,
    #[serde(deserialize_with = "required_option")]
    pub input_id: Option<String>,
    pub terminal_sequence: u64,
    pub message_sequence: u64,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Location {
    pub agent_id: String,
    pub turn_id: String,
}

#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum ConclusionReason {
    MissingConclusion,
    AbnormalTerminal,
    UnsettledWork,
    InvalidFrozenBinding,
}

// Required nullable fields must be present. Serde's ordinary Option handling
// otherwise turns a missing producer field into a successful None.
pub(super) fn required_option<'de, D, T>(deserializer: D) -> Result<Option<T>, D::Error>
where
    D: Deserializer<'de>,
    T: Deserialize<'de>,
{
    Option::<T>::deserialize(deserializer)
}

impl Review {
    pub fn require_valid(&self, report: &Report) -> Result<()> {
        require(
            self.full_report.agent_id == report.child_id
                && self.full_report.turn_id == report.turn_id
                && report.message == self.summary
                && report.last_tool.is_none()
                && !self.summary.trim().is_empty()
                && self.summary.chars().count() <= 512
                && if self.reason.is_some() {
                    self.disposition == Disposition::Inconclusive
                } else {
                    self.reviewed_version.as_ref().is_some_and(|version| {
                        !version.trim().is_empty() && version.chars().count() <= 2048
                    })
                },
            "compact review lost its identity/summary/full-history location",
        )
    }

    pub fn require_binding(&self, report: &Report, target: &Spawn) -> Result<&Baseline> {
        self.require_valid(report)?;
        let binding = self
            .target
            .as_ref()
            .context("review has no frozen target")?;
        require(
            binding.agent_id == target.agent_id,
            "review targeted another executor",
        )?;
        let baseline = binding
            .baseline
            .as_ref()
            .context("review lacks frozen baseline")?;
        require(
            !baseline.turn_id.is_empty() && baseline.terminal_sequence > 0,
            "review lacks committed target baseline identity",
        )?;
        Ok(baseline)
    }

    pub fn require_legacy(&self, summary: &str, report: &Report) -> Result<()> {
        self.require_valid(report)?;
        let expected = match summary {
            "delegation independent review: changes requested" => Disposition::NeedsChanges,
            "delegation independent review: approved"
            | "delegation recovery independent review: approved" => Disposition::Approved,
            _ => anyhow::bail!("unknown legacy review expectation"),
        };
        let target = self
            .target
            .as_ref()
            .context("legacy review lost its frozen target")?;
        require(
            self.summary == summary
                && self.disposition == expected
                && self.reason.is_none()
                && self
                    .reviewed_version
                    .as_ref()
                    .is_some_and(|version| version.starts_with("work/review-surface.txt sha256:"))
                && self.full_report.agent_id == report.child_id
                && self.full_report.turn_id == report.turn_id
                && !target.agent_id.is_empty()
                && target.baseline.is_some()
                && target.feedback.is_none(),
            "legacy journey did not receive its real typed review conclusion/version/identity",
        )
    }
}

// Live and cold host reports deliberately carry different Turn payloads. The
// explicit outer identities are checked by Report; neither variant is a fallback
// for a missing latest Turn or a malformed/non-normal completed state.
pub(super) fn terminal_turn<'de, D: Deserializer<'de>>(deserializer: D) -> Result<Turn, D::Error> {
    #[derive(Deserialize)]
    #[serde(untagged)]
    enum WireTurn {
        Live(Turn),
        Saved(ColdTurn),
    }
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ColdTurn {
        id: String,
        input_id: Option<String>,
        state: SavedTurnState,
    }
    match WireTurn::deserialize(deserializer)? {
        WireTurn::Live(turn) => Ok(turn),
        WireTurn::Saved(turn) => {
            if !matches!(turn.state, SavedTurnState::Completed { data: SavedCompleted { completed_at, completion: SavedCompletion::Normal } } if completed_at > 0)
            {
                return Err(serde::de::Error::custom(
                    "cold terminal report is not a normal completed Turn",
                ));
            }
            Ok(Turn {
                turn_id: turn.id,
                input_id: turn.input_id,
                state: TurnState::Finished("completed".into()),
            })
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct FileRead {
    pub path: String,
    pub start_line: usize,
    #[serde(deserialize_with = "required_option")]
    pub next_start_line: Option<usize>,
    pub content_hash: String,
    pub text: String,
}
