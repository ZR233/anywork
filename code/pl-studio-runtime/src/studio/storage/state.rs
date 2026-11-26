//! Independent current.json ownership and the isolated, one-shot v2 TOML migration boundary.
//! Normal Current recovery never reads History. Legacy files are removed only after the explicit
//! schema-24 import can be read back and verified.

mod current;

use std::path::{Path, PathBuf};

use crate::studio::storage::legacy_checkpoint::ThreadCheckpoint;
use anyhow::{Context, Result, ensure};

/// Frozen continuation provenance decoded only during schema-24 import.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct LegacyInputContinuation {
    pub(crate) point_id: String,
    pub(crate) source_turn_id: Option<String>,
}

/// Frozen schema-24 backup identity for an admitted input.
///
/// This is migration material only. Normal idempotency comes from the resident Thread state;
/// neither realtime admission nor Current recovery reads this row as a fallback.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct InputIdentityEntry {
    /// Content digest of the originally accepted body, for future content-equality checks.
    pub(crate) digest: String,
    /// 该输入是否携带接续来源；控制输入的受理结果据此重建。
    ///
    /// 旧版本写入的行没有这个字段，按「没有接续来源」解码，历史身份保持原样。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) continuation: Option<LegacyInputContinuation>,
    /// Delivery routing receipt retained from the original admission.
    pub(crate) delivery: pl_core::thread::input::InputDelivery,
    pub(crate) id: String,
    /// 原始受理的用途：控制输入在正文离开驻留队列后仍然可识别。
    ///
    /// 旧行没有该字段时按普通消息解码。
    #[serde(default)]
    pub(crate) purpose: pl_core::thread::input::InputPurpose,
    /// 控制输入受理时调用方冻结的模型路由版本；首写值即请求身份的一部分。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) expected_model_route_revision: Option<u64>,
    /// 控制输入首次受理时的输入 revision；重放原回执时用它重建目标戳，不被后续状态推进覆盖。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(crate) continuation_admission_revision: Option<u64>,
    pub(crate) ordinal: u64,
    pub(crate) revision: u64,
    pub(crate) state: pl_core::thread::input::InputState,
    /// Original admission watermark, returned as the repeat submission cursor.
    pub(crate) accepted_sequence: u64,
}

#[derive(Clone)]
pub(crate) struct StateStore {
    directory: PathBuf,
    thread_id: String,
    legacy_calls: Option<super::calls::CallsStore>,
    current: Option<current::CurrentRegistration>,
    coordinator: Option<super::coordinator::ThreadPersistenceCoordinator>,
}

impl StateStore {
    pub(crate) fn new(directory: PathBuf, thread_id: &str) -> Self {
        Self {
            directory,
            thread_id: thread_id.to_owned(),
            legacy_calls: None,
            current: None,
            coordinator: None,
        }
    }

    pub(crate) fn with_legacy_calls(mut self, calls: super::calls::CallsStore) -> Self {
        self.legacy_calls = Some(calls);
        self
    }

    /// Binds checkpoint fallback diagnostics to the coordinator that observes this Thread.
    pub(crate) fn with_persistence(
        mut self,
        coordinator: super::coordinator::ThreadPersistenceCoordinator,
    ) -> Self {
        self.coordinator = Some(coordinator);
        self
    }

    /// The sole v2 TOML import entry.
    ///
    /// This is maintenance-only. The caller must hold the Thread maintenance gate and retire every
    /// schema-24 writer before invoking it. Normal Current recovery reads `current.json`; it never
    /// opens History or calls this method. SQLite schema preparation finishes before any TOML
    /// checkpoint is decoded, and the original files remain in place until the import has been
    /// read back and verified. Import never deletes the primary manifest, fallback manifest or
    /// checkpoint bodies: those are user-owned migration evidence with no cleanup authorization.
    pub(crate) async fn legacy_prepare(
        &self,
        history: &super::history::HistoryStore,
    ) -> Result<Option<ThreadCheckpoint>> {
        ensure!(
            history.thread_id() == self.thread_id,
            "history database belongs to another Thread"
        );
        history.prepare_activation().await?;
        if let Some(checkpoint) = history.checkpoint().await? {
            return Ok(Some(checkpoint));
        }
        // The explicit legacy import must not carry its parser, accounting and temporary state in
        // every normal Current load. Allocate that owned branch only when migration is needed.
        Box::pin(self.clone().import_legacy_checkpoint(history.clone())).await
    }

    async fn import_legacy_checkpoint(
        self,
        history: super::history::HistoryStore,
    ) -> Result<Option<ThreadCheckpoint>> {
        let Some(mut checkpoint) = self.legacy_checkpoint().await? else {
            ensure!(
                history.watermark().await? == 0,
                "history exists without a recovery checkpoint"
            );
            return Ok(None);
        };
        // Old compaction receipts used one extension key per request. History owns the old
        // reductions and accounting is already cumulative; only the newest receipt is current.
        let latest_compaction = checkpoint
            .state
            .extensions
            .values()
            .filter(|record| record.payload.format() == "pl.studio.compaction")
            .max_by_key(|record| record.revision)
            .cloned();
        checkpoint
            .state
            .extensions
            .retain(|_, record| record.payload.format() != "pl.studio.compaction");
        if let Some(record) = latest_compaction {
            checkpoint
                .state
                .extensions
                .insert(crate::context_preparation::LATEST_RECEIPT.into(), record);
        }
        let legacy_costs = match &self.legacy_calls {
            Some(calls) => {
                calls
                    .legacy_session_costs(&self.thread_id, checkpoint.history_fence)
                    .await?
            }
            None => Vec::new(),
        };
        if let Some(calls) = &self.legacy_calls {
            let auxiliary = calls.legacy_auxiliary_usage(&self.thread_id).await?;
            let summary = &mut checkpoint.state.usage_summary;
            for (target, value) in [
                (
                    &mut summary.totals.inference_count,
                    auxiliary.totals.inference_count,
                ),
                (
                    &mut summary.totals.prompt_tokens,
                    auxiliary.totals.prompt_tokens,
                ),
                (
                    &mut summary.totals.completion_tokens,
                    auxiliary.totals.completion_tokens,
                ),
                (
                    &mut summary.totals.cached_prompt_tokens,
                    auxiliary.totals.cached_prompt_tokens,
                ),
                (
                    &mut summary.totals.cache_write_tokens,
                    auxiliary.totals.cache_write_tokens,
                ),
                (
                    &mut summary.totals.reasoning_tokens,
                    auxiliary.totals.reasoning_tokens,
                ),
                (
                    &mut summary.totals.total_tokens,
                    auxiliary.totals.total_tokens,
                ),
            ] {
                *target = target
                    .checked_add(value)
                    .context("legacy auxiliary accounting overflow")?;
            }
            summary.diagnostics.legacy_incomplete |= auxiliary.has_incomplete_usage();
            summary.diagnostics.legacy_unknown = true;
            summary.cache.incomplete |= auxiliary.cache.incomplete;
            summary.pricing.incomplete |= auxiliary.pricing.incomplete;
        }
        history
            .import_checkpoint(&checkpoint, &legacy_costs)
            .await?;
        let restored = history
            .checkpoint()
            .await?
            .context("imported checkpoint is absent")?;
        Ok(Some(restored))
    }

    /// Reads the replaced v2 TOML manifest for explicit recovery and layout-migration evidence.
    ///
    /// This verifies the source version, Thread identity and every external body before any caller
    /// can materialize `current.json` or create schema 24. It is never part of normal Current reads.
    pub(in crate::studio) async fn legacy_checkpoint(&self) -> Result<Option<ThreadCheckpoint>> {
        let mut primary_error = None;
        for path in [self.path(), self.previous_path()] {
            let content = match tokio::fs::read_to_string(&path).await {
                Ok(content) => content,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => continue,
                Err(error) => return Err(error.into()),
            };
            if let Ok(value) = toml::from_str::<toml::Value>(&content)
                && let Some(version) = value.get("schemaVersion").and_then(toml::Value::as_integer)
            {
                ensure!(
                    (1..=i64::from(ThreadCheckpoint::SCHEMA_VERSION)).contains(&version),
                    "unsupported checkpoint schema {version}; source files preserved"
                );
            }
            let checkpoint = match self.read_checkpoint(&content, &path).await {
                Ok(checkpoint) => checkpoint,
                Err(error) if path == self.path() => {
                    primary_error = Some(error);
                    continue;
                }
                Err(error) => return Err(primary_error.unwrap_or(error)),
            };
            ensure!(
                checkpoint.thread_id == self.thread_id,
                "Thread checkpoint belongs to another Thread"
            );
            if path == self.previous_path() {
                // 显式恢复诊断：回退到 `state.prev.toml` 是一次真实恢复，不是普通加载。只有
                // `state.toml` 缺失或不可解析时才会走到这里，因此必须留下可追溯的原因。
                let primary = primary_error.as_ref().map_or_else(
                    || "state.toml was missing".to_owned(),
                    std::string::ToString::to_string,
                );
                if let Some(coordinator) = &self.coordinator {
                    coordinator.record_checkpoint_recovery(
                        &self.thread_id,
                        format!("recovered the Thread checkpoint from state.prev.toml ({primary})"),
                    );
                }
                tracing::warn!(
                    thread_id = %self.thread_id,
                    recovered_from = %path.display(),
                    primary = %primary,
                    "recovered the Thread checkpoint from state.prev.toml"
                );
            }
            return Ok(Some(checkpoint));
        }
        match primary_error {
            Some(error) => Err(error),
            None => Ok(None),
        }
    }

    /// Parses one checkpoint file and materializes every body it references.
    ///
    /// Externalized bodies are restored here, before the checkpoint is handed to any caller, so
    /// activation, the owner and the next model request always see the exact original bytes. A
    /// missing, corrupt or mismatchingly-targeted blob fails closed; it is never read as an empty
    /// body, and it never silently becomes a truncated model context.
    async fn read_checkpoint(&self, content: &str, path: &Path) -> Result<ThreadCheckpoint> {
        let value: toml::Value = toml::from_str(content)
            .with_context(|| format!("invalid Thread checkpoint {}", path.display()))?;
        let version = value
            .get("schemaVersion")
            .and_then(toml::Value::as_integer)
            .context("checkpoint schemaVersion is missing")?;
        if ThreadCheckpoint::is_legacy_schema(u32::try_from(version)?) {
            let mut legacy = super::legacy_checkpoint::LegacyThreadCheckpoint::decode_json(
                &serde_json::to_string(&value)?,
            )?;
            // Even bodies discarded by the new layout are checked before deleting the old manifest.
            for entry in legacy.dropped_attempt_bodies() {
                let bytes = tokio::fs::read(self.blob_path(entry.reference.digest())?).await?;
                entry.reference.verify(&bytes)?;
            }
            while let Some(entry) = legacy.pending_body().cloned() {
                let bytes = tokio::fs::read(self.blob_path(entry.reference.digest())?).await?;
                legacy.materialize_body(&entry.reference, &bytes)?;
            }
            let route = self.legacy_route(&value).await?;
            let mut checkpoint = legacy.into_current()?;
            if !checkpoint
                .state
                .extensions
                .contains_key(crate::studio::model_route::MODEL_ROUTE_EXTENSION)
                && let Some(route) = route
            {
                checkpoint.state.extension_sequence = checkpoint
                    .state
                    .extension_sequence
                    .checked_add(1)
                    .context("legacy extension sequence exhausted")?;
                checkpoint.state.extensions.insert(
                    crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
                    pl_core::thread::extensions::ExtensionRecord {
                        revision: checkpoint.state.extension_sequence,
                        payload: crate::studio::model_route::encode(&route.into())?,
                    },
                );
            }
            crate::context_preparation::migrate_checkpoint_sources(&mut checkpoint)?;
            return Ok(checkpoint);
        }
        let mut checkpoint = parse_checkpoint(content, path)?;
        while let Some(entry) = checkpoint.pending_body().cloned() {
            let blob = self.blob_path(entry.reference.digest())?;
            let bytes = tokio::fs::read(&blob).await.with_context(|| {
                format!(
                    "checkpoint body {} is missing for Thread {}",
                    entry.reference.digest(),
                    self.thread_id
                )
            })?;
            checkpoint
                .materialize_body(&entry.reference, &bytes)
                .map_err(|error| {
                    anyhow::anyhow!(
                        "checkpoint body {} is unusable for Thread {}: {error}",
                        entry.reference.digest(),
                        self.thread_id
                    )
                })?;
        }
        Ok(checkpoint)
    }

    /// Preserve the selected model at the migration boundary without retaining tool schemas.
    async fn legacy_route(
        &self,
        value: &toml::Value,
    ) -> Result<Option<pl_model::config::ModelRouteConfig>> {
        let root = serde_json::to_value(value)?;
        let Some(attempts) = root
            .get("state")
            .and_then(|state| state.get("attempts"))
            .and_then(serde_json::Value::as_array)
        else {
            return Ok(None);
        };
        for (index, attempt) in attempts.iter().enumerate().rev() {
            let Some(metadata) = attempt
                .get("requestMetadata")
                .filter(|value| !value.is_null())
            else {
                continue;
            };
            let mut payload: pl_core::context::OpaquePayload =
                serde_json::from_value(metadata.clone())?;
            if payload.format() != "pl.model.prepared-request" {
                continue;
            }
            if let Some(entries) = root
                .get("externalBodies")
                .and_then(serde_json::Value::as_array)
            {
                for entry in entries {
                    if let Ok(entry) = serde_json::from_value::<
                        super::legacy_checkpoint::LegacyCheckpointExternalBody,
                    >(entry.clone())
                        && matches!(entry.slot, super::legacy_checkpoint::LegacyCheckpointBodySlot::AttemptMetadata { attempt_index } if attempt_index == index)
                    {
                        let bytes =
                            tokio::fs::read(self.blob_path(entry.reference.digest())?).await?;
                        entry.reference.verify(&bytes)?;
                        payload = pl_core::context::OpaquePayload::new(
                            payload.format(),
                            payload.version(),
                            String::from_utf8(bytes)?,
                        )?;
                    }
                }
            }
            // Metadata belongs to the old manifest and may be externalized. Upgrade only after
            // restoring and verifying those bytes, before entering the current-only reader.
            if let Some(current) = pl_model::runtime::migration::migrate_payload(&payload)? {
                payload = current;
            }
            let receipt = pl_model::runtime::model_request_receipt(&payload)?;
            return Ok(Some(pl_model::config::ModelRouteConfig {
                account_id: pl_model::config::AccountId::new(receipt.binding.account_id)?,
                model_id: receipt.binding.model_id,
                effort: receipt
                    .reasoning
                    .and_then(|reasoning| reasoning.effort)
                    .map(pl_model::config::ReasoningEffort::new),
            }));
        }
        Ok(None)
    }

    /// Root of the checkpoint's own content-addressed blob store inside the session directory.
    ///
    /// It lives beside the attachment blobs, under the same session `blobs` root, so relocating a
    /// session directory carries both and every reference stays resolvable without absolute paths.
    fn checkpoint_blobs_dir(&self) -> PathBuf {
        self.directory.join("blobs").join("checkpoint")
    }

    /// Absolute path of one referenced body, derived from its content address.
    fn blob_path(&self, digest: &str) -> Result<PathBuf> {
        let hex = digest
            .strip_prefix("sha256:")
            .with_context(|| format!("checkpoint body digest {digest} is not a SHA-256 address"))?;
        ensure!(
            hex.len() == 64 && hex.bytes().all(|byte| byte.is_ascii_hexdigit()),
            "checkpoint body digest {digest} is not a SHA-256 address"
        );
        Ok(self.checkpoint_blobs_dir().join(&hex[..2]).join(hex))
    }

    fn path(&self) -> PathBuf {
        self.directory.join("state.toml")
    }

    fn previous_path(&self) -> PathBuf {
        self.directory.join("state.prev.toml")
    }
}

/// 解析一份 checkpoint 文件，并拒绝本实现无法解释的未来 schema 版本。
///
/// 尚未外置正文的 schema-1 文件原样接受，因为它已经在文件里保留完整正文。未来版本则显式失败
/// 闭锁：本层不做任何"尽力解读新布局"的宽容解码——一个不认识的版本无法区分真实正文与引用，调用
/// 方因此把它当作不可用的快照处理：主文件不可用时回退 `state.prev.toml` 并登记显式恢复诊断，两份
/// 都不可用时报错。
fn parse_checkpoint(content: &str, path: &Path) -> Result<ThreadCheckpoint> {
    let checkpoint: ThreadCheckpoint = toml::from_str(content)
        .with_context(|| format!("invalid Thread checkpoint {}", path.display()))?;
    ensure!(
        ThreadCheckpoint::supports_schema(checkpoint.schema_version),
        "unsupported Thread checkpoint schema {} in {}; this build reads schema {}",
        checkpoint.schema_version,
        path.display(),
        ThreadCheckpoint::SCHEMA_VERSION
    );
    Ok(checkpoint)
}
