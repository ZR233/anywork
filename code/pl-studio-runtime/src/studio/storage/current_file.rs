//! Complete current JSON and retained session resources. No history dependency or migration.

use std::{borrow::Cow, collections::HashSet, io, path::PathBuf, sync::Arc};

use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{ContextContent, ResourceAccess},
    thread::current::{RuntimeEpoch, ThreadCurrent},
};
use tokio_util::sync::CancellationToken;

use crate::resource_store::FileResourceStore;
use crate::studio::paths::CURRENT_FILE_NAME;

/// The single physical publication boundary; tests may fail before or after replacement.
pub(super) type CurrentWrite = Arc<dyn Fn(&std::path::Path, &[u8]) -> io::Result<()> + Send + Sync>;

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
            write: Arc::new(write_current_atomically),
        }
    }

    #[cfg(test)]
    pub(super) fn with_write(mut self, write: CurrentWrite) -> Self {
        self.write = write;
        self
    }

    pub(super) fn directory(&self) -> &std::path::Path {
        &self.directory
    }

    pub(super) async fn load(&self) -> Result<Option<ThreadCurrent>> {
        let path = self.directory.join(CURRENT_FILE_NAME);
        let bytes = match tokio::fs::read(&path).await {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(error) => return Err(error).with_context(|| format!("read {}", path.display())),
        };
        let file = self.clone();
        let current = tokio::task::spawn_blocking(move || {
            let current: ThreadCurrent = serde_json::from_slice(&bytes)
                .with_context(|| format!("invalid Thread current {}", path.display()))?;
            file.validate(&current, None)?;
            Ok::<_, anyhow::Error>(current)
        })
        .await
        .context("join current decoder")??;
        self.verify_resources(&current, CancellationToken::new())
            .await?;
        Ok(Some(current))
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
        cancellation: CancellationToken,
    ) -> Result<()> {
        let resources =
            ResourceAccess::new(FileResourceStore::new(self.directory.join("resources")));
        verify_recovery_resources(current, &resources, cancellation).await
    }

    /// Encoding and the complete synchronous publication are one owned, non-aborted operation.
    /// An error after replacement is not a rollback and must never produce a success receipt.
    pub(super) async fn save(&self, current: ThreadCurrent) -> Result<()> {
        let file = self.clone();
        tokio::task::spawn_blocking(move || {
            let bytes = serde_json::to_vec(&current).context("encode complete Thread current")?;
            let path = file.directory.join(CURRENT_FILE_NAME);
            (file.write)(&path, &bytes)
                .with_context(|| format!("publish Thread current {}", path.display()))
        })
        .await
        .context("join current publication")?
    }
}

async fn verify_recovery_resources(
    current: &ThreadCurrent,
    resources: &ResourceAccess,
    cancellation: CancellationToken,
) -> Result<()> {
    let mut verified = HashSet::new();
    for content in current.recovery_contents() {
        let reference = match content {
            ContextContent::Resource { reference } => Cow::Borrowed(reference),
            ContextContent::Opaque { payload } => {
                let Some(attachment) = pl_model::runtime::decode_attachment(payload)
                    .context("decode model attachment required by current")?
                else {
                    continue;
                };
                Cow::Owned(attachment.reference)
            }
            ContextContent::Text { .. } => continue,
        };
        // One attempt can refer to the same immutable material through confirmed context and
        // pending delivery. Read it once, but never hide a different identity or metadata claim.
        if verified.insert((
            reference.id().to_owned(),
            reference.content_digest().to_owned(),
            reference.byte_len(),
            reference.media_type().to_owned(),
        )) {
            resources
                .read(&reference, cancellation.clone())
                .await
                .with_context(|| {
                    format!("current requires retained resource {}", reference.id())
                })?;
        }
    }
    Ok(())
}

fn write_current_atomically(path: &std::path::Path, bytes: &[u8]) -> io::Result<()> {
    // The shared helper currently skips directory synchronization on Windows. Fail closed until
    // its platform publication contract is implemented; do not invent a durability substitute.
    #[cfg(windows)]
    {
        let _ = (path, bytes);
        Err(io::Error::new(
            io::ErrorKind::Unsupported,
            "current publication requires directory synchronization, unavailable in the Windows atomic helper",
        ))
    }
    #[cfg(not(windows))]
    pl_tool::workspace::write_file_atomically(path, bytes)
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
        let file = CurrentFile::new(directory.path().into(), "file-test".into())
            .with_write(Arc::new(pl_tool::workspace::write_file_atomically));
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
        assert_eq!(std::fs::read(history)?, b"not a SQLite database");
        assert_eq!(
            std::fs::read_dir(directory.path())?.count(),
            2,
            "no blob/manifest/history artifacts"
        );
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
        let file = CurrentFile::new(directory.path().into(), "file-test".into())
            .with_write(Arc::new(pl_tool::workspace::write_file_atomically));
        let mut current = ThreadCurrent::new("file-test".into(), RuntimeEpoch::new());
        current.state.context.records = vec![ContextRecord {
            id: "attachment-record".into(),
            turn_id: None,
            source: ContextSource::User,
            content: vec![ContextContent::Resource {
                reference: reference.clone(),
            }],
            tool_calls: Vec::new(),
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
