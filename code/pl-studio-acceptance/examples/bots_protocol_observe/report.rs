use anyhow::{Context, Result};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;

use super::env::ObservePaths;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum Verdict {
    Passed,
    Failed,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct CaseResult {
    pub name: &'static str,
    pub verdict: Verdict,
    pub detail: String,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub evidence: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ProcessEvidence {
    pub pid: u32,
    pub status: String,
    pub descendants_at_root_exit: Vec<u32>,
    pub reclaimed_descendants: Vec<u32>,
    pub cancelled: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct FileDigest {
    pub path: String,
    pub sha256: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ObserverIdentity {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workspace_head: Option<String>,
    pub example_files: Vec<FileDigest>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum ServerBinarySource {
    ExplicitPrebuilt,
    BuiltCurrent,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ServerIdentity {
    pub source: ServerBinarySource,
    pub canonical_path: PathBuf,
    pub sha256: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct RunSummary {
    pub entry: &'static str,
    pub output: PathBuf,
    pub summary_path: PathBuf,
    pub studio_home: PathBuf,
    pub cases: Vec<CaseResult>,
    pub gaps: Vec<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub process: Option<ProcessEvidence>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cleanup_error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub retained_home: Option<String>,
    pub fixture_mode: &'static str,
    pub human_verdict: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub observer: Option<ObserverIdentity>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub server: Option<ServerIdentity>,
}

impl RunSummary {
    pub fn for_paths(output: &Path, home: &Path) -> Self {
        Self {
            entry: "bots_protocol_observe",
            output: output.to_path_buf(),
            summary_path: output.join("summary.json"),
            studio_home: home.to_path_buf(),
            cases: Vec::new(),
            // Conservative default: every range stays unproven until
            // `finalize_gaps` narrows it from the typed case verdicts. An
            // unwritten or startup-failed run therefore never reports empty
            // gaps.
            gaps: conservative_gaps(),
            process: None,
            cleanup_error: None,
            retained_home: None,
            fixture_mode: "debug loopback Feishu peer + model FixtureServer",
            human_verdict: "pending; automated local evidence is not a real-tenant, SSH or GUI verdict",
            observer: None,
            server: None,
        }
    }

    /// Narrows the reported gaps to what this run actually proved.
    ///
    /// The only facts used are the typed case identities and verdicts already
    /// carried by `cases`; detail/message strings are never interpreted. A
    /// missing or failed case keeps its full gap range, so a red or skipped
    /// case can never narrow coverage, and passed cases only remove the ranges
    /// they really cover.
    pub(crate) fn finalize_gaps(&mut self) {
        let passed = |name: &str| {
            self.cases
                .iter()
                .any(|case| case.name == name && case.verdict == Verdict::Passed)
        };
        let mut gaps = vec![
            GAP_TIMELINE_WINDOW,
            GAP_CONFIG_SECRET_FAULT,
            GAP_LAGGED_REPLAY,
            GAP_PERMISSION_UNREACHABLE,
            GAP_CLAIM_TAKEOVER_RACE,
        ];
        if passed(CASE_REGISTRATION_LIFECYCLE) {
            gaps.push(GAP_REGISTRATION_CANCEL_CLAIM_WINDOW);
        } else {
            gaps.push(GAP_REGISTRATION_FULL);
            gaps.push(GAP_REGISTRATION_CANCEL);
        }
        if !passed(CASE_REPLY_INTERACTION_RESTART) {
            gaps.push(GAP_SAME_HOME_RESTART);
            gaps.push(GAP_LOCAL_CONTINUATION);
        }
        if !passed(CASE_REPLY_SEND_OUTCOMES) {
            gaps.push(GAP_SEGMENTED_OUTCOMES);
        }
        if !passed(CASE_OWNER_BINDING) {
            gaps.push(GAP_OWNER_BINDING);
        }
        append_file_gaps(&mut gaps, &passed);
        self.gaps = gaps;
    }
}

// Case identities mirrored from the case selectors in `cases` and its reply
// and registration submodules; matched by typed `CaseResult::name` only.
const CASE_REGISTRATION_LIFECYCLE: &str = "registration-lifecycle";
const CASE_REPLY_INTERACTION_RESTART: &str = "reply-interaction-restart";
const CASE_REPLY_SEND_OUTCOMES: &str = "reply-send-outcomes-restart";
const CASE_OWNER_BINDING: &str = "owner-binding-occupancy";

// Ranges no current observe case can prove; always reported.
const GAP_TIMELINE_WINDOW: &str =
    "Turn with more than 100 timeline items is not covered by this observe batch";
const GAP_CONFIG_SECRET_FAULT: &str = "config/secret fault keeps original association";
const GAP_LAGGED_REPLAY: &str = "Lagged subscriber gap: exact dropped-terminal replay after a Lagged frame is not covered \
     (thread watches fail closed instead of resyncing)";
const GAP_PERMISSION_UNREACHABLE: &str = "permission-pending ToolApproval is publicly unreachable under the constant effective \
     FullAccess policy";
const GAP_CLAIM_TAKEOVER_RACE: &str = "restart claim-takeover races: no public sweep marker exists, so the bounded quiet window \
     cannot prove precise lease takeover timing";

// Ranges a passed case removes for this run.
const GAP_REGISTRATION_FULL: &str = "registration begin/pending/slowDown/completed/denied/expired";
const GAP_REGISTRATION_CANCEL: &str = "local cancel during begin/poll hang plus late Completed";
const GAP_REGISTRATION_CANCEL_CLAIM_WINDOW: &str = "registration cancel precise claim-window race against an in-flight Completed at the exact \
     boundary is not covered";
const GAP_SAME_HOME_RESTART: &str = "same-home restart recovery";
const GAP_LOCAL_CONTINUATION: &str =
    "interaction desktop resolution along canonical continuation_id";
const GAP_SEGMENTED_OUTCOMES: &str =
    "automatic formal-reply .md-file/notice Partial and post Unknown facts across restart";
const GAP_OWNER_BINDING: &str = "explicit local conversation-Thread creation: stale-creation rejection before the first write, \
     first-occupancy publication and same-operation replay";

const GAP_CHAT_ISOLATION: &str =
    "bot+chat identity isolation and complete actual model-request context exclusion";
const GAP_MEDIA_INGRESS: &str = "raw media/file admission, actual native blocks, execution bytes and native-to-text cold recovery";
const GAP_FILE_SOURCE: &str = "current/canonical-continuation file source authorization and public revocation/local-input rejection";
const GAP_MARKDOWN: &str =
    "verbatim Markdown post, complete long .md download and full-JSON encoding limit";
const GAP_UPLOAD_OUTCOMES: &str =
    "real upload Reject/AcceptThenDrop/Hang-cancel and cold no-replay ledger evidence";
const GAP_FILE_SEND_OUTCOMES: &str = "real file-message Reject/AcceptThenDrop/Hang-cancel after accepted upload and cold no-replay evidence";
const GAP_FILE_COMPACTION: &str = "real Studio manual compact of pure text with old-Turn files, replacement/cold rebuild and shutdown cancellation";
const GAP_COMPACT_OUTER_TIMEOUT: &str = "outer case timeout drops its future while a real public Studio compact is held; Session must close/join before peer cleanup";
const GAP_SAME_TURN_STEERING: &str = "same-Turn steering file-source rejection: public HTTP prompt interrupts into a fresh Turn, so this is not proved by running-turn local-input evidence";
const GAP_FILE_TOOL_REPLAY: &str = "same submit_bot_file call identity with altered file intent is not publicly replayable through ordinary model tool calls";
const GAP_REAL_MEDIA_BOUNDARIES: &str = "real Feishu tenant/client rendering, native GUI and remote SSH file boundaries require separate human review";
const GAP_FILE_SOURCE_CHILD_PROJECT: &str = "child file-tool exclusion and separate project/cross-chat tool permissions require independent public-boundary evidence";
const GAP_ADMISSION_CEILINGS: &str =
    "ordinary public multipart 50MiB/32-file/128MiB admission ceilings and exact original readback";
const GAP_OUTGOING_CEILINGS: &str =
    "nonempty/30,000,000-byte outgoing file boundaries are not all exercised by these journeys";
const GAP_PRE_MESSAGE_CANCEL: &str = "uploadAccepted + messageNotStarted + stopReasonCancelled requires a deterministic public pre-message cancellation boundary; on-wire Hang cancellation is not that evidence";

fn append_file_gaps(gaps: &mut Vec<&'static str>, passed: &impl Fn(&str) -> bool) {
    for (case, gap) in [
        ("chat-isolation", GAP_CHAT_ISOLATION),
        ("chat-media-ingress", GAP_MEDIA_INGRESS),
        ("bot-file-source", GAP_FILE_SOURCE),
        ("bot-markdown-transfer", GAP_MARKDOWN),
        ("bot-upload-outcomes", GAP_UPLOAD_OUTCOMES),
        ("bot-file-send-outcomes", GAP_FILE_SEND_OUTCOMES),
        ("user-file-compaction", GAP_FILE_COMPACTION),
        ("user-file-compaction-timeout", GAP_COMPACT_OUTER_TIMEOUT),
        ("user-file-admission-limits", GAP_ADMISSION_CEILINGS),
    ] {
        if !passed(case) {
            gaps.push(gap);
        }
    }
    gaps.extend([
        GAP_SAME_TURN_STEERING,
        GAP_FILE_TOOL_REPLAY,
        GAP_REAL_MEDIA_BOUNDARIES,
        GAP_FILE_SOURCE_CHILD_PROJECT,
        GAP_OUTGOING_CEILINGS,
        GAP_PRE_MESSAGE_CANCEL,
    ]);
}

/// Every gap range in its unproven wording; the pre-finalize default.
fn conservative_gaps() -> Vec<&'static str> {
    let mut gaps = vec![
        GAP_TIMELINE_WINDOW,
        GAP_CONFIG_SECRET_FAULT,
        GAP_LAGGED_REPLAY,
        GAP_PERMISSION_UNREACHABLE,
        GAP_CLAIM_TAKEOVER_RACE,
        GAP_REGISTRATION_FULL,
        GAP_REGISTRATION_CANCEL,
        GAP_SAME_HOME_RESTART,
        GAP_LOCAL_CONTINUATION,
        GAP_SEGMENTED_OUTCOMES,
        GAP_OWNER_BINDING,
    ];
    append_file_gaps(&mut gaps, &|_| false);
    gaps
}

pub(crate) fn copy_redacted_log(paths: &ObservePaths) -> Result<()> {
    if !paths.server_log.is_file() {
        return Ok(());
    }
    let raw = fs::read_to_string(&paths.server_log)
        .with_context(|| format!("failed to read {}", paths.server_log.display()))?;
    fs::write(
        paths.output.join("studio-server.log"),
        crate::env::redact(&raw),
    )?;
    Ok(())
}

pub(crate) fn write(paths: &ObservePaths, summary: &RunSummary) -> Result<()> {
    fs::create_dir_all(&paths.output)?;
    let bytes =
        serde_json::to_vec_pretty(summary).context("failed to serialize observe summary")?;
    fs::write(&summary.summary_path, bytes)
        .with_context(|| format!("failed to write {}", summary.summary_path.display()))?;
    Ok(())
}

pub(crate) fn attach_process(path: &Path, process: &ProcessEvidence) -> Result<()> {
    let bytes = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    let mut value: serde_json::Value =
        serde_json::from_slice(&bytes).context("failed to parse observe summary")?;
    value["process"] =
        serde_json::to_value(process).context("failed to serialize process evidence")?;
    fs::write(path, serde_json::to_vec_pretty(&value)?)
        .with_context(|| format!("failed to rewrite {}", path.display()))?;
    Ok(())
}

pub(crate) fn summary_failed(path: &Path) -> Result<bool> {
    let bytes = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    let value: serde_json::Value =
        serde_json::from_slice(&bytes).context("failed to parse observe summary")?;
    let cases_failed = value["cases"]
        .as_array()
        .map(|cases| {
            cases
                .iter()
                .any(|case| case["verdict"].as_str() != Some("passed"))
        })
        .unwrap_or(true);
    let cleanup = value
        .get("cleanupError")
        .and_then(serde_json::Value::as_str)
        .is_some();
    Ok(cases_failed || cleanup)
}

pub(crate) fn process_evidence(
    pid: u32,
    status: ExitStatus,
    descendants_at_root_exit: Vec<u32>,
    reclaimed_descendants: Vec<u32>,
    cancelled: bool,
) -> ProcessEvidence {
    ProcessEvidence {
        pid,
        status: status.to_string(),
        descendants_at_root_exit,
        reclaimed_descendants,
        cancelled,
    }
}

pub(crate) fn one_line(value: &str) -> String {
    crate::env::redact(&value.replace(['\n', '\r'], " "))
}

pub(crate) fn passed(name: &'static str, detail: impl Into<String>) -> CaseResult {
    CaseResult {
        name,
        verdict: Verdict::Passed,
        detail: detail.into(),
        evidence: Vec::new(),
    }
}

pub(crate) fn failed(name: &'static str, detail: impl Into<String>) -> CaseResult {
    CaseResult {
        name,
        verdict: Verdict::Failed,
        detail: one_line(&detail.into()),
        evidence: Vec::new(),
    }
}
