//! Read-only durable corroboration. Never repairs a database or substitutes a
//! snapshot for a real public command/provider request.
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::{AgentProfileSnapshot, AgentWorkspaceAssignmentSnapshot};
use sea_orm::sqlx::{
    Connection,
    sqlite::{SqliteConnectOptions, SqliteConnection},
};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    collections::BTreeMap,
    fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

const CURRENT_INSTRUCTION_SNAPSHOT_VERSION: u32 = 3;
const CURRENT_COMPACTION_RECEIPT_VERSION: u32 = 3;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct AgentIdentity {
    pub id: String,
    pub scope: String,
    pub usage_binding: AgentUsageBinding,
    pub revision: String,
    pub origin: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "entry",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub(super) enum AgentUsageBinding {
    RootEntry(RootEntry),
    Child,
    LegacyUnspecifiedRoot { source_version: u32 },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(super) enum RootEntry {
    Studio,
    Bot,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct Instructions {
    pub agent: AgentIdentity,
    pub agent_shape: AgentInstructionShape,
    pub base: Block,
    pub developer: Vec<Block>,
    pub user: Vec<Block>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "state", rename_all = "camelCase", deny_unknown_fields)]
pub(super) enum AgentInstructionShape {
    Absent,
    Present {
        #[serde(rename = "contentHash")]
        content_hash: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Block {
    pub source: Source,
    pub content: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Source {
    pub kind: String,
    pub label: String,
    pub path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct ContextRecord {
    pub id: String,
    pub source: RecordSource,
    pub content: Vec<RecordContent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct RecordSource {
    pub kind: String,
    pub source_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub(super) enum RecordContent {
    Text { text: String },
    Opaque { payload: serde_json::Value },
    Resource { reference: serde_json::Value },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Compaction {
    pub inference_id: String,
    pub turn_id: String,
    pub implementation: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct SavedEvidence {
    pub thread_id: String,
    pub snapshot_revision: u64,
    pub saved_runtime_epoch: String,
    pub instruction_revision: u64,
    pub history_seq: Option<u64>,
    pub context_revision: u64,
    pub instructions: Instructions,
    pub profile: Option<AgentProfileSnapshot>,
    pub workspace: Option<AgentWorkspaceAssignmentSnapshot>,
    pub compaction: Option<Compaction>,
    pub context: Vec<ContextRecord>,
}

impl Instructions {
    pub fn blocks(&self, kind: &str) -> Vec<&Block> {
        self.developer
            .iter()
            .filter(|block| block.source.kind == kind)
            .collect()
    }

    pub fn assert_root(&self, id: &str) -> Result<()> {
        ensure!(
            self.agent.id == id
                && self.agent.scope == "root"
                && self.agent.origin == "builtin"
                && self.agent.usage_binding
                    == AgentUsageBinding::RootEntry(if id == "root:feishu" {
                        RootEntry::Bot
                    } else {
                        RootEntry::Studio
                    })
                && !self.agent.revision.is_empty(),
            "wrong root Agent identity: {:?}",
            self.agent
        );
        ensure!(
            self.blocks("modeDefinition").len() == 1,
            "root has no independent Mode source"
        );
        let roles = self.blocks("agentDefinition");
        let AgentInstructionShape::Present { content_hash } = &self.agent_shape else {
            bail!("new root has no frozen Agent source shape");
        };
        ensure!(roles.len() == 1, "root must own exactly one Agent source");
        ensure!(
            !content_hash.is_empty() && *content_hash == digest(roles[0].content.as_bytes())?,
            "root Agent source differs from its frozen content identity"
        );
        ensure!(
            !self.base.content.is_empty() && !self.blocks("platform").is_empty(),
            "base/platform source missing"
        );
        Ok(())
    }

    pub fn assert_agent_frozen(&self, previous: &Self) -> Result<()> {
        ensure!(
            self.agent == previous.agent
                && self.agent_shape == previous.agent_shape
                && self.blocks("agentDefinition") == previous.blocks("agentDefinition"),
            "frozen Agent identity or role changed"
        );
        Ok(())
    }

    pub fn assert_mode_update_preserves_agent_and_non_model_sources(
        &self,
        previous: &Self,
    ) -> Result<()> {
        self.assert_agent_frozen(previous)?;
        ensure!(
            self.blocks("modeDefinition") != previous.blocks("modeDefinition"),
            "Mode source did not change"
        );
        let without_mode = |value: &Self| {
            value
                .developer
                .iter()
                .filter(|block| block.source.kind != "modeDefinition")
                .cloned()
                .collect::<Vec<_>>()
        };
        ensure!(
            without_mode(self) == without_mode(previous),
            "Mode update changed Agent or another non-Mode developer source"
        );
        ensure!(
            self.user == previous.user,
            "Mode update changed an unrelated user-context source"
        );
        if self.base != previous.base {
            let model_owned = |block: &Block| {
                matches!(block.source.kind.as_str(), "modelBase" | "builtInBase")
                    && block.source.path.is_none()
                    && block.source.label
                        == if block.source.kind == "modelBase" {
                            "model base"
                        } else {
                            "built-in base"
                        }
            };
            ensure!(
                model_owned(&self.base) && model_owned(&previous.base),
                "Mode update changed an explicit/config-owned base source"
            );
        }
        Ok(())
    }
}

impl SavedEvidence {
    pub fn assert_child(&self, parent_profile: &AgentProfileSnapshot) -> Result<()> {
        ensure!(
            self.profile.as_ref() == Some(parent_profile),
            "child did not freeze the real catalog Profile"
        );
        let expected_origin = if parent_profile.system {
            "builtin"
        } else {
            "profile"
        };
        ensure!(
            self.instructions.agent.id == parent_profile.profile_id
                && self.instructions.agent.scope == "child"
                && self.instructions.agent.origin == expected_origin
                && self.instructions.agent.usage_binding == AgentUsageBinding::Child
                && self.instructions.agent.revision == parent_profile.revision,
            "child Agent identity differs from frozen Profile"
        );
        let roles = self.instructions.blocks("agentDefinition");
        ensure!(
            roles.len() == 1 && roles[0].content == parent_profile.system_instructions.trim(),
            "child role differs from frozen Profile body"
        );
        let AgentInstructionShape::Present { content_hash } = &self.instructions.agent_shape else {
            bail!("child has no frozen Agent source shape");
        };
        ensure!(
            !content_hash.is_empty() && *content_hash == digest(roles[0].content.as_bytes())?,
            "child Agent source differs from its frozen content identity"
        );
        ensure!(
            self.instructions.blocks("modeDefinition").is_empty(),
            "child inherited root Mode source"
        );
        ensure!(
            self.workspace
                .as_ref()
                .is_some_and(|workspace| workspace.mode == parent_profile.workspace_mode),
            "child workspace mode differs from frozen Profile"
        );
        Ok(())
    }

    pub fn assert_compacted(&self, previous: &Self, marker: &str) -> Result<()> {
        let receipt = self
            .compaction
            .as_ref()
            .context("no durable compaction receipt")?;
        ensure!(
            receipt.error.is_none()
                && receipt.implementation.as_deref() == Some("textSummary")
                && !receipt.inference_id.is_empty(),
            "compaction did not succeed: {receipt:?}"
        );
        ensure!(
            self.context_revision > previous.context_revision,
            "context revision did not advance"
        );
        ensure!(
            self.context
                .iter()
                .any(|record| record.source.kind == "runtime"
                    && record.source.source_id.as_deref() == Some("model.compaction")
                    && record.text().contains(marker)),
            "no committed model compaction replacement"
        );
        self.instructions
            .assert_agent_frozen(&previous.instructions)?;
        Ok(())
    }
}

impl ContextRecord {
    pub fn text(&self) -> String {
        self.content
            .iter()
            .filter_map(|part| match part {
                RecordContent::Text { text } => Some(text.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join("\n")
    }
}

/// Counts persisted Thread identities without activating a cold child. The
/// public Thread directory is intentionally root-only, so it cannot prove that
/// a rejected spawn or a cold send did not create an extra child.
pub(super) async fn thread_ids(home: &Path) -> Result<Vec<String>> {
    let mut paths = Vec::new();
    collect(home, 0, &mut paths)?;
    let mut ids = Vec::new();
    for path in paths {
        let bytes = tokio::fs::read(&path).await?;
        let saved = strict_current(&bytes)?;
        ids.push(saved.thread_id);
    }
    ids.sort();
    ensure!(
        ids.windows(2).all(|pair| pair[0] != pair[1]),
        "duplicate saved Current Thread identity"
    );
    Ok(ids)
}

/// Observes each saved Current atomically, then independently records the durable history head.
/// Neither revision is treated as a fence for the other store.
pub(super) async fn load(home: &Path, thread_id: &str) -> Result<Option<SavedEvidence>> {
    let mut paths = Vec::new();
    collect(home, 0, &mut paths)?;
    let mut found = None;
    for path in paths {
        let bytes = tokio::fs::read(&path)
            .await
            .with_context(|| format!("read Current {}", path.display()))?;
        let saved = strict_current(&bytes)?;
        if saved.thread_id != thread_id {
            continue;
        }
        ensure!(
            found.is_none(),
            "duplicate Current identity for {thread_id}"
        );
        ensure!(
            saved.state.context.records.len() <= 512,
            "Agent observation context bound exceeded"
        );
        let context = serde_json::from_value(serde_json::to_value(&saved.state.context.records)?)?;
        let history = path.with_file_name("history.sqlite");
        let history_seq = if history.is_file() {
            let mut connection = SqliteConnection::connect_with(
                &SqliteConnectOptions::new()
                    .filename(&history)
                    .read_only(true),
            )
            .await?;
            let head: Option<i64> =
                sea_orm::sqlx::query_scalar("SELECT MAX(seq) FROM history_events")
                    .fetch_one(&mut connection)
                    .await?;
            connection.close().await?;
            head.map(u64::try_from).transpose()?
        } else {
            None
        };
        let extensions = &saved.state.extensions;
        found = Some(SavedEvidence {
            thread_id: saved.thread_id,
            snapshot_revision: saved.snapshot_revision,
            saved_runtime_epoch: saved.saved_runtime_epoch.to_string(),
            instruction_revision: extensions
                .get("studio.instructions")
                .context("saved instructions missing")?
                .revision,
            history_seq,
            context_revision: saved.state.context.revision,
            instructions: required(
                extensions,
                "studio.instructions",
                "pl.studio.instructions",
                CURRENT_INSTRUCTION_SNAPSHOT_VERSION,
            )?,
            profile: optional(
                extensions,
                "studio.agent-profile",
                "pl.studio.agent-profile",
                2,
            )?,
            workspace: optional(extensions, "studio.workspace", "pl.studio.workspace", 2)?,
            compaction: optional(
                extensions,
                "studio.compaction.latest",
                "pl.studio.compaction",
                CURRENT_COMPACTION_RECEIPT_VERSION,
            )?,
            context,
        });
    }
    Ok(found)
}

fn strict_current(bytes: &[u8]) -> Result<pl_core::thread::current::ThreadCurrent> {
    let envelope: serde_json::Value = serde_json::from_slice(bytes)?;
    let thread_id = envelope["threadId"]
        .as_str()
        .context("saved Current omitted its Thread identity")?;
    Ok(pl_core::thread::current::ThreadCurrent::from_json(
        bytes, thread_id,
    )?)
}

fn required<T: DeserializeOwned>(
    extensions: &BTreeMap<String, pl_core::thread::extensions::ExtensionRecord>,
    id: &str,
    format: &str,
    version: u32,
) -> Result<T> {
    optional(extensions, id, format, version)?
        .with_context(|| format!("saved extension {id} missing"))
}

fn optional<T: DeserializeOwned>(
    extensions: &BTreeMap<String, pl_core::thread::extensions::ExtensionRecord>,
    id: &str,
    format: &str,
    version: u32,
) -> Result<Option<T>> {
    extensions
        .get(id)
        .map(|record| {
            ensure!(
                record.revision > 0
                    && record.payload.format == format
                    && record.payload.version == version,
                "unsupported saved extension {id}"
            );
            serde_json::from_str(&record.payload.content)
                .with_context(|| format!("decode saved extension {id}"))
        })
        .transpose()
}

fn collect(dir: &Path, depth: usize, found: &mut Vec<PathBuf>) -> Result<()> {
    ensure!(
        depth <= 10 && found.len() <= 32,
        "Agent history search bound exceeded"
    );
    let mut entries = fs::read_dir(dir)?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    entries.sort();
    for path in entries {
        let metadata = fs::symlink_metadata(&path)?;
        if metadata.file_type().is_symlink() {
            continue;
        }
        if metadata.is_dir() {
            collect(&path, depth + 1, found)?;
        } else if path.file_name().is_some_and(|name| name == "current.json") {
            found.push(path);
        }
    }
    Ok(())
}

fn digest(bytes: &[u8]) -> Result<String> {
    let mut child = Command::new("sha256sum")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("start saved-payload sha256sum")?;
    let result = child
        .stdin
        .take()
        .context("sha256sum stdin missing")
        .and_then(|mut input| {
            input
                .write_all(bytes)
                .context("write saved payload to sha256sum")
        });
    let output = child
        .wait_with_output()
        .context("wait saved-payload sha256sum")?;
    result?;
    ensure!(output.status.success(), "saved-payload sha256sum failed");
    let text = String::from_utf8(output.stdout)?;
    let hash = text
        .split_whitespace()
        .next()
        .context("saved-payload digest absent")?;
    if hash.len() != 64 || !hash.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("malformed saved-payload digest");
    }
    Ok(format!("sha256:{hash}"))
}
