//! The approval covers physical observation only; full Git JSON is explicitly read.
use super::*;
use crate::delegation::{review_child::digest, review_wire::Disposition};

pub(super) const SUMMARY: &str =
    "Physical Git observation complete; materials valid; not a business-code review.";

pub(super) fn message(parent: &Git) -> String {
    format!(
        "{}\nWORKTREE_PHYSICAL_REVIEW:only\nScope: complete physical Git observation and validate its materials only; this is not business-code review. Submit the full actual Git JSON as message, not summary.",
        marker("read", parent)
    )
}

pub(super) fn require_target(reviewer: &Child, target: &Child) -> Result<()> {
    let review = reviewer
        .report
        .review
        .as_ref()
        .context("physical review projection missing")?;
    require(
        review.target.as_ref().is_some_and(|binding| {
            binding.agent_id == target.spawn.agent_id
                && binding.baseline.as_ref().is_some_and(|baseline| {
                    baseline.turn_id == target.report.turn_id
                        && baseline.input_id == target.report.input_id
                        && baseline.terminal_sequence == target.report.commit_sequence
                })
        }),
        "physical reviewer did not bind the exact observed target delivery",
    )
}

fn version(git: &Git) -> Result<String> {
    let assignment = serde_json::to_string(&(&git.path, &git.git_dir, &git.common_dir))?;
    Ok(format!(
        "HEAD:{} physical-assignment:{} status:{}",
        git.head,
        digest(&assignment),
        digest(&git.status)
    ))
}

pub(super) fn finish(flow: &Flow<'_>, git: &Git, full_json: &str) -> Progress<Decision> {
    tools(flow, &["finish_turn"])?;
    require(
        !git.head.is_empty() && !git.path.is_empty() && !git.git_dir.is_empty(),
        "physical review has no actual HEAD/assignment observation",
    )?;
    Ok(Decision::call(
        "worktree_child_evidence",
        &format!("{}-physical-finish", flow.prefix),
        "finish_turn",
        json!({"message":full_json,"review":{
            "disposition":"approved","summary":SUMMARY,"reviewedVersion":version(git)?
        }}),
    ))
}

pub(super) fn full_git(
    flow: &Flow<'_>,
    label: &str,
    child: &Spawn,
    report: &Report,
) -> Progress<Git> {
    let review = report
        .review
        .as_ref()
        .context("physical reviewer lacks typed conclusion")?;
    review.require_valid(report)?;
    require(
        review.disposition == Disposition::Approved
            && review.reason.is_none()
            && review.summary == SUMMARY
            && review
                .target
                .as_ref()
                .is_some_and(|target| target.feedback.is_none() && target.baseline.is_some()),
        "physical observation was not submitted as an explicitly scoped typed approval",
    )?;
    let mut cursor = None;
    let mut through = None;
    let mut ordinal = None;
    for index in 0..4 {
        let page: SavedPage = flow.read(
            &format!("{label}-git-full-{index}"),
            "read_agent_session",
            json!({"target":review.full_report.agent_id,"order":"descending","detail":"full",
                "limit":50,"cursor":cursor}),
        )?;
        require(
            page.agent_id == child.agent_id
                && page.path.len() == 2
                && page.path.last() == Some(&child.agent_id)
                && page.through_sequence > 0
                && through.is_none_or(|value| value == page.through_sequence)
                && matches!(page.order, SavedOrder::Descending)
                && matches!(page.detail, SavedDetail::Full)
                && page.items.len() <= 50
                && page.has_more == page.next_cursor.is_some(),
            "physical full-history page lost its exact reviewer/path/watermark",
        )?;
        through = Some(page.through_sequence);
        let mut git = None;
        for item in page.items {
            require(
                item.thread_id == child.agent_id
                    && ordinal.is_none_or(|value| item.ordinal < value),
                "physical reviewer history is unordered or foreign",
            )?;
            ordinal = Some(item.ordinal);
            if item.turn_id == report.turn_id
                && let SavedItemState::Text { data } = item.state
                && matches!(data.channel, SavedTextChannel::Final)
            {
                require(git.is_none(), "physical review has multiple final bodies")?;
                let observed: Git = serde_json::from_str(&data.text)
                    .context("explicit public full read did not contain actual Git JSON")?;
                require(
                    observed.kind == "worktreeEvidence"
                        && review.reviewed_version.as_deref() == Some(version(&observed)?.as_str()),
                    "physical reviewedVersion differs from the actual full Git observation",
                )?;
                git = Some(observed);
            }
        }
        if let Some(git) = git {
            return Ok(git);
        }
        cursor = page.next_cursor;
        require(
            cursor.is_some(),
            "reviewer public full history lacks original Git JSON",
        )?;
    }
    Err(anyhow::anyhow!("physical Git full history exceeded four bounded pages").into())
}
