//! Complete current JSON and retained session resources. No history dependency.

use std::{
    collections::{HashMap, HashSet},
    io,
    path::PathBuf,
    time::Instant,
};

use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use futures::future::BoxFuture;
use pl_core::{
    context::{ContextContent, ResourceReader, ResourceReference},
    thread::current::{CURRENT_SCHEMA_VERSION, RuntimeEpoch, ThreadCurrent},
};
use tokio::io::AsyncWriteExt;
use tokio_util::sync::CancellationToken;

use crate::resource_store::FileResourceStore;
use crate::studio::paths::CURRENT_FILE_NAME;

/// The physical writer owns the path and encoded bytes until the complete write settles.
type CurrentWrite = Arc<dyn Fn(PathBuf, Vec<u8>) -> BoxFuture<'static, Result<()>> + Send + Sync>;

#[cfg(test)]
type BlockingCurrentWrite = Arc<dyn Fn(&std::path::Path, &[u8]) -> io::Result<()> + Send + Sync>;

// Owned by one writer incarnation and one session directory, never shared between owners.
pub(super) type VerifiedResources = HashSet<(String, String, u64, String)>;

/// Explicit history-upgrade read boundary. Verify the decoded Current and preserve its exact bytes.
pub(crate) async fn read_for_upgrade(
    directory: impl Into<PathBuf>,
    thread_id: &str,
) -> Result<(ThreadCurrent, Vec<u8>)> {
    let file = CurrentFile::new(directory.into(), thread_id.to_owned());
    file.load_with_bytes(true)
        .await?
        .ok_or_else(|| anyhow::anyhow!("Thread current is missing"))
}

fn current_version(bytes: &[u8]) -> Result<u32> {
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Header {
        schema_version: u32,
    }
    Ok(serde_json::from_slice::<Header>(bytes)?.schema_version)
}

fn decode_for_upgrade(bytes: &[u8], thread_id: &str) -> Result<ThreadCurrent> {
    if current_version(bytes)? == 1 {
        let mut old: serde_json::Value = serde_json::from_slice(bytes)?;
        super::tool_result_upgrade::upgrade_state(&mut old)?;
        old["schemaVersion"] = CURRENT_SCHEMA_VERSION.into();
        let mut current = ThreadCurrent::from_json(&serde_json::to_vec(&old)?, thread_id)?;
        super::tool_result_upgrade::upgrade_pending_tool_messages(&mut current.state)?;
        Ok(current)
    } else {
        Ok(ThreadCurrent::from_json(bytes, thread_id)?)
    }
}

pub(crate) async fn verify_for_upgrade(
    directory: impl Into<PathBuf>,
    thread_id: &str,
    current: &ThreadCurrent,
) -> Result<()> {
    let file = CurrentFile::new(directory.into(), thread_id.to_owned());
    file.validate(current, None)?;
    file.verify_resources(
        current,
        &mut VerifiedResources::new(),
        CancellationToken::new(),
    )
    .await
}

#[derive(Clone)]
pub(super) struct CurrentFile {
    directory: PathBuf,
    thread_id: String,
    write: CurrentWrite,
}

impl std::fmt::Debug for CurrentFile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CurrentFile")
            .field("directory", &self.directory)
            .field("thread_id", &self.thread_id)
            .finish_non_exhaustive()
    }
}

impl CurrentFile {
    pub(super) fn new(directory: PathBuf, thread_id: String) -> Self {
        Self {
            directory,
            thread_id,
            write: Arc::new(|path, bytes| Box::pin(write_current_file(path, bytes))),
        }
    }

    #[cfg(test)]
    pub(super) fn with_write(mut self, write: BlockingCurrentWrite) -> Self {
        self.write = Arc::new(move |path, bytes| {
            let write = write.clone();
            Box::pin(async move {
                let write_path = path.clone();
                tokio::task::spawn_blocking(move || write(&write_path, &bytes))
                    .await
                    .context("join current write")?
                    .with_context(|| format!("write Thread current {}", path.display()))
            })
        });
        self
    }

    pub(super) fn directory(&self) -> &std::path::Path {
        &self.directory
    }

    pub(super) fn thread_id(&self) -> &str {
        &self.thread_id
    }

    pub(super) async fn load(&self) -> Result<Option<ThreadCurrent>> {
        Ok(self
            .load_with_bytes(false)
            .await?
            .map(|(current, _)| current))
    }

    async fn read_bytes(&self) -> Result<Option<Vec<u8>>> {
        let path = self.directory.join(CURRENT_FILE_NAME);
        match tokio::fs::read(&path).await {
            Ok(bytes) => Ok(Some(bytes)),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error).with_context(|| format!("read {}", path.display())),
        }
    }

    /// Identifies a legacy file without decoding its producer state or verifying its resources.
    pub(super) async fn legacy_bytes(&self) -> Result<Option<Vec<u8>>> {
        let Some(bytes) = self.read_bytes().await? else {
            return Ok(None);
        };
        let schema = current_version(&bytes).context("read Current schema for maintenance")?;
        match schema {
            CURRENT_SCHEMA_VERSION => Ok(None),
            1 => Ok(Some(bytes)),
            other => anyhow::bail!("unsupported current schema {other}"),
        }
    }

    pub(super) async fn prepare_legacy(
        &self,
        original: Vec<u8>,
    ) -> Result<(ThreadCurrent, Vec<u8>)> {
        self.decode_and_verify(original, true).await
    }

    /// The coordinator owns Current admission for this directory through legacy publication.
    pub(super) fn publish_legacy(&self, current: &ThreadCurrent, original: &[u8]) -> Result<()> {
        let encoded = serde_json::to_vec(current)?;
        let backup_root = self.directory.join("migration-backups");
        let backup = backup_root.join("current-tool-result-v1");
        std::fs::create_dir_all(&backup)?;
        #[cfg(unix)]
        for directory in [&backup, &backup_root, &self.directory] {
            std::fs::File::open(directory)?.sync_all()?;
        }
        let backup = backup.join("current.original.json");
        if backup.try_exists()? {
            ensure!(
                std::fs::read(&backup)?.as_slice() == original,
                "current migration backup differs from source"
            );
        } else {
            pl_tool::workspace::write_file_atomically(&backup, original)?;
        }
        pl_tool::workspace::write_file_atomically(&self.directory.join(CURRENT_FILE_NAME), &encoded)
            .context("publish upgraded Current")
    }

    async fn decode_and_verify(
        &self,
        bytes: Vec<u8>,
        upgrade: bool,
    ) -> Result<(ThreadCurrent, Vec<u8>)> {
        let path = self.directory.join(CURRENT_FILE_NAME);
        let file = self.clone();
        let (current, bytes) = tokio::task::spawn_blocking(move || {
            let current = if upgrade {
                decode_for_upgrade(&bytes, &file.thread_id)
            } else {
                ThreadCurrent::from_json(&bytes, &file.thread_id).map_err(anyhow::Error::from)
            }
            .with_context(|| format!("invalid Thread current {}", path.display()))?;
            Ok::<_, anyhow::Error>((current, bytes))
        })
        .await
        .context("join current decoder")??;
        self.verify_resources(
            &current,
            &mut VerifiedResources::new(),
            CancellationToken::new(),
        )
        .await?;
        Ok((current, bytes))
    }

    async fn load_with_bytes(&self, upgrade: bool) -> Result<Option<(ThreadCurrent, Vec<u8>)>> {
        let started = Instant::now();
        let Some(bytes) = self.read_bytes().await? else {
            return Ok(None);
        };
        let (current, bytes) = self.decode_and_verify(bytes, upgrade).await?;
        tracing::debug!(target: "current_work",
            thread_id = self.thread_id,
            current_load_ms = started.elapsed().as_secs_f64() * 1000.0,
            current_json_bytes = bytes.len(),
            current_snapshot_age_ms = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_or(0, |now| now.as_millis().saturating_sub(current.saved_at.max(0) as u128)) as u64,
            "current loaded without history"
        );
        Ok(Some((current, bytes)))
    }

    pub(super) fn validate(
        &self,
        current: &ThreadCurrent,
        epoch: Option<&RuntimeEpoch>,
    ) -> Result<()> {
        current.validate(&self.thread_id)?;
        if let Some(epoch) = epoch {
            ensure!(
                &current.saved_runtime_epoch == epoch,
                "current capture belongs to another runtime epoch"
            );
        }
        Ok(())
    }

    pub(super) async fn verify_resources(
        &self,
        current: &ThreadCurrent,
        verified: &mut VerifiedResources,
        cancellation: CancellationToken,
    ) -> Result<()> {
        let resources = FileResourceStore::new(self.directory.join("resources"));
        verify_recovery_resources(current, &resources, verified, cancellation).await
    }

    /// Encoding and the complete write are owned by the writer until they finish.
    /// A failed or interrupted overwrite may leave an incomplete file.
    pub(super) async fn save(&self, current: impl Into<Arc<ThreadCurrent>>) -> Result<()> {
        let current = current.into();
        let (bytes, encode_elapsed) = tokio::task::spawn_blocking(move || {
            let started = Instant::now();
            let bytes = serde_json::to_vec(&current)?;
            Ok::<_, serde_json::Error>((bytes, started.elapsed()))
        })
        .await
        .context("join current encoder")?
        .context("encode complete Thread current")?;
        tracing::debug!(target: "current_work",
            thread_id = self.thread_id,
            current_encode_ms = encode_elapsed.as_secs_f64() * 1000.0,
            current_json_bytes = bytes.len(),
            "current encoded"
        );
        tokio::fs::create_dir_all(&self.directory)
            .await
            .with_context(|| format!("create current directory {}", self.directory.display()))?;
        (self.write)(self.directory.join(CURRENT_FILE_NAME), bytes).await
    }
}

async fn write_current_file(path: PathBuf, bytes: Vec<u8>) -> Result<()> {
    let mut options = tokio::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    // Preserve private-file permissions while writing in place.
    #[cfg(unix)]
    options.mode(0o600);
    let mut file = options
        .open(&path)
        .await
        .with_context(|| format!("open Thread current {}", path.display()))?;
    file.write_all(&bytes)
        .await
        .with_context(|| format!("write Thread current {}", path.display()))?;
    // Tokio's file writes may still be running on its blocking pool until flush completes.
    file.flush()
        .await
        .with_context(|| format!("finish Thread current write {}", path.display()))
}

async fn verify_recovery_resources(
    current: &ThreadCurrent,
    resources: &FileResourceStore,
    verified: &mut VerifiedResources,
    cancellation: CancellationToken,
) -> Result<()> {
    let mut referenced = HashMap::new();
    // A capture can name the same material through more than one saved slot. Deduplicate exact
    // claims while keeping conflicting identity or metadata available to the verifier.
    let mut retain = |reference: ResourceReference| {
        let key = (
            reference.id().to_owned(),
            reference.content_digest().to_owned(),
            reference.byte_len(),
            reference.media_type().to_owned(),
        );
        referenced.entry(key).or_insert(reference);
    };
    for content in current.recovery_contents() {
        let reference = match content {
            ContextContent::Resource { reference } => reference.clone(),
            ContextContent::Media { payload } => {
                let Some(attachment) = pl_model::runtime::decode_attachment(payload)
                    .context("decode model attachment required by current")?
                else {
                    continue;
                };
                attachment.reference
            }
            ContextContent::Text { .. } | ContextContent::Opaque { .. } => continue,
        };
        retain(reference);
    }
    for delivery in current.state.deliveries.iter() {
        for reference in pl_tool::exec::saved_command_resources(delivery.output.details())
            .context("decode retained command output required by current")?
        {
            retain(reference);
        }
    }
    verified.retain(|key| referenced.contains_key(key));
    for (key, reference) in referenced {
        if !verified.contains(&key) {
            // FileResourceStore validates length and digest in its ResourceReader implementation;
            // calling ResourceAccess here would hash the same bytes a second time.
            resources
                .read(reference.clone(), cancellation.clone())
                .await
                .with_context(|| {
                    format!("current requires retained resource {}", reference.id())
                })?;
            verified.insert(key);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_core::{
        context::{ContextRecord, ContextSource, OpaquePayload},
        model::ToolCallMode,
        thread::current::{CurrentModelCall, SavedModelPhase},
    };

    #[tokio::test]
    async fn current_is_self_contained_even_with_unreadable_history() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let history = directory.path().join("history.sqlite");
        std::fs::write(&history, b"not a SQLite database")?;
        let file = CurrentFile::new(directory.path().into(), "file-test".into());
        assert!(file.load().await?.is_none());
        let epoch = RuntimeEpoch::new();
        let mut current = ThreadCurrent::new("file-test".into(), epoch);
        current.saved_at = 123;
        current.state.context.records = vec![ContextRecord {
            id: "long-user-record".into(),
            turn_id: None,
            source: ContextSource::User,
            content: vec![ContextContent::Text {
                text: "完整正文".repeat(32 * 1024).into(),
            }],
            tool_calls: Vec::new(),
            tool_data: Default::default(),
        }]
        .into();
        current.model_call = Some(CurrentModelCall {
            source_run_id: epoch,
            source_execution_id: "execution".into(),
            source_turn_id: "turn".into(),
            source_attempt_id: "attempt".into(),
            tools: Arc::from([]),
            tool_call_mode: ToolCallMode::Sequential,
            solo_tool_ids: Arc::from([]),
            prepared_parameters: None,
            phase: SavedModelPhase::Streaming {
                stream: OpaquePayload::new("test.stream", 1, "{\"path\":\"src/ma")?,
            },
        });
        let expected = serde_json::to_value(&current)?;
        file.save(current).await?;
        let restored = file.load().await?.expect("complete current exists");
        assert_eq!(serde_json::to_value(restored)?, expected);
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = std::fs::metadata(directory.path().join(CURRENT_FILE_NAME))?
                .permissions()
                .mode();
            assert_eq!(mode & 0o077, 0, "new current files are private");
        }
        let smaller = ThreadCurrent::new("file-test".into(), epoch);
        file.save(smaller.clone()).await?;
        assert_eq!(
            serde_json::to_value(file.load().await?.expect("overwritten current exists"))?,
            serde_json::to_value(smaller)?,
            "overwriting a longer current must not leave a trailing fragment"
        );
        assert_eq!(std::fs::read(history)?, b"not a SQLite database");
        assert_eq!(
            std::fs::read_dir(directory.path())?.count(),
            2,
            "no blob/manifest/history artifacts"
        );
        Ok(())
    }

    #[tokio::test]
    async fn upgrade_read_preserves_the_exact_existing_current_bytes() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let current = ThreadCurrent::new("file-test".into(), RuntimeEpoch::new());
        let bytes = serde_json::to_vec_pretty(&current)?;
        std::fs::write(directory.path().join(CURRENT_FILE_NAME), &bytes)?;

        let (restored, exact) =
            read_for_upgrade(directory.path().to_path_buf(), "file-test").await?;

        assert_eq!(restored.thread_id, "file-test");
        assert_eq!(exact, bytes);
        Ok(())
    }

    #[tokio::test]
    async fn rejects_corruption_unknown_schema_wrong_thread_and_missing_fields_without_mutation()
    -> Result<()> {
        let directory = tempfile::tempdir()?;
        let file = CurrentFile::new(directory.path().into(), "file-test".into());
        let current = ThreadCurrent::new("file-test".into(), RuntimeEpoch::new());
        let mut future = current.clone();
        future.schema_version = 99;
        let mut other = current.clone();
        other.thread_id = "another-thread".into();
        let mut missing = serde_json::to_value(&current)?;
        missing.as_object_mut().unwrap().remove("state");
        for bytes in [
            b"{broken json".to_vec(),
            serde_json::to_vec(&future)?,
            serde_json::to_vec(&other)?,
            serde_json::to_vec(&missing)?,
        ] {
            let path = directory.path().join("current.json");
            std::fs::write(&path, &bytes)?;
            assert!(file.load().await.is_err());
            assert_eq!(
                std::fs::read(&path)?,
                bytes,
                "invalid current is retained, not migrated or replaced"
            );
        }
        Ok(())
    }

    #[tokio::test]
    async fn validates_retained_assets_length_digest_and_presence_without_history() -> Result<()> {
        let directory = tempfile::tempdir()?;
        let resources = FileResourceStore::new(directory.path().join("resources"));
        let reference = resources
            .retain_bytes(
                Arc::from(b"durable attachment".as_slice()),
                "application/octet-stream",
            )
            .await?;
        let file = CurrentFile::new(directory.path().into(), "file-test".into());
        let mut current = ThreadCurrent::new("file-test".into(), RuntimeEpoch::new());
        current.state.context.records = vec![ContextRecord {
            id: "attachment-record".into(),
            turn_id: None,
            source: ContextSource::User,
            content: vec![ContextContent::Resource {
                reference: reference.clone(),
            }],
            tool_calls: Vec::new(),
            tool_data: Default::default(),
        }]
        .into();
        file.save(current).await?;
        assert!(file.load().await?.is_some());
        let path = directory.path().join("current.json");
        let original = std::fs::read(&path)?;
        let asset = directory.path().join("resources").join(
            reference
                .id()
                .strip_prefix(crate::resource_store::RESOURCE_ID_PREFIX)
                .unwrap(),
        );
        // Same length but different digest, then a length mismatch, then a missing material.
        for changed in [b"replaced content!!".as_slice(), b"short".as_slice()] {
            std::fs::write(&asset, changed)?;
            assert!(file.load().await.is_err());
            assert_eq!(std::fs::read(&path)?, original);
        }
        std::fs::remove_file(asset)?;
        assert!(file.load().await.is_err());
        assert_eq!(std::fs::read(path)?, original);
        Ok(())
    }
}

#[cfg(test)]
mod attachment_tests;
