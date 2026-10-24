use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use base64::Engine;
use pl_protocol::{AttachmentModality, ThreadAttachment};

use crate::studio::ids::{new_id, unix_seconds};
use crate::studio::records::{AttachmentRecord, MaterializedAttachment};
use crate::studio::store::StudioStore;

pub(in crate::studio) const ATTACHMENT_CATALOG_SCHEMA_VERSION: u32 = 1;

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct AttachmentCatalog {
    pub(in crate::studio) schema_version: u32,
    pub(in crate::studio) thread_id: String,
    pub(in crate::studio) records: Vec<AttachmentRecord>,
}

impl StudioStore {
    /// Lists attachments with session-relative blob references. Use the materialization methods
    /// to read their bytes; the returned references are independent of the process working directory.
    pub async fn list_thread_attachments(&self, thread_id: &str) -> Result<Vec<AttachmentRecord>> {
        let _guard = self.attachment_lock().lock().await;
        self.load_attachment_catalog(thread_id).await
    }

    pub(in crate::studio) async fn record_attachments(
        &self,
        records: Vec<AttachmentRecord>,
    ) -> Result<()> {
        if records.is_empty() {
            return Ok(());
        }
        let thread_id = records[0].thread_id.clone();
        anyhow::ensure!(
            records.iter().all(|record| record.thread_id == thread_id),
            "attachment batch mixes Thread identities"
        );
        let _guard = self.attachment_lock().lock().await;
        let mut current = self.load_attachment_catalog(&thread_id).await?;
        let mut ids = current
            .iter()
            .map(|record| record.id.as_str())
            .collect::<std::collections::BTreeSet<_>>();
        for record in &records {
            anyhow::ensure!(ids.insert(&record.id), "duplicate attachment id");
        }
        current.extend(records);
        self.save_attachment_catalog(&thread_id, &current).await
    }

    pub async fn load_attachments(
        &self,
        thread_id: &str,
        attachment_ids: &[String],
    ) -> Result<Vec<AttachmentRecord>> {
        if attachment_ids.is_empty() {
            return Ok(Vec::new());
        }
        let mut records = self.list_thread_attachments(thread_id).await?;
        let mut ordered = Vec::with_capacity(attachment_ids.len());
        let mut seen = std::collections::BTreeSet::new();
        for attachment_id in attachment_ids {
            if !seen.insert(attachment_id) {
                bail!("duplicate attachment id: {attachment_id}");
            }
            let index = records
                .iter()
                .position(|record| record.id == *attachment_id)
                .with_context(|| format!("attachment {attachment_id} does not belong to Thread"))?;
            ordered.push(records.swap_remove(index));
        }
        Ok(ordered)
    }

    /// Retains an attachment in its owning Thread's reliable resource store.
    /// Both source resolution and integrity validation belong to this storage boundary.
    pub(in crate::studio) async fn retain_attachment_resource(
        &self,
        record: &AttachmentRecord,
    ) -> Result<pl_core::context::ResourceReference> {
        let session = self.registered_session_paths(&record.thread_id)?;
        let source = resolve_attachment_host_path(&session, &record.blob_relative_path)?;
        let resources = crate::resource_store::FileResourceStore::new(session.resources_dir());
        let reference = resources.retain_file(&source, &record.media_type).await?;
        anyhow::ensure!(
            reference.byte_len() == record.byte_size
                && reference.content_digest() == format!("sha256:{}", record.content_sha256),
            "attachment changed while preparing input"
        );
        Ok(reference)
    }

    pub async fn materialize_thread_attachments(
        &self,
        thread_id: &str,
    ) -> Result<Vec<MaterializedAttachment>> {
        let records = self.list_thread_attachments(thread_id).await?;
        self.materialize_attachment_records(records).await
    }

    pub async fn materialize_attachments(
        &self,
        thread_id: &str,
        attachment_ids: &[String],
    ) -> Result<Vec<MaterializedAttachment>> {
        let records = self.load_attachments(thread_id, attachment_ids).await?;
        self.materialize_attachment_records(records).await
    }

    pub(crate) async fn read_attachment_bytes(
        &self,
        thread_id: &str,
        attachment_id: &str,
    ) -> Result<Vec<u8>> {
        let record = self
            .load_attachments(thread_id, &[attachment_id.to_string()])
            .await?
            .into_iter()
            .next()
            .context("attachment is unavailable")?;
        tokio::fs::read(self.attachment_host_path(&record)?)
            .await
            .with_context(|| format!("failed to load attachment {attachment_id}"))
    }

    fn attachment_host_path(&self, record: &AttachmentRecord) -> Result<PathBuf> {
        let session = self.registered_session_paths(&record.thread_id)?;
        resolve_attachment_host_path(&session, &record.blob_relative_path)
    }

    async fn materialize_attachment_records(
        &self,
        records: Vec<AttachmentRecord>,
    ) -> Result<Vec<MaterializedAttachment>> {
        let mut materialized = Vec::with_capacity(records.len());
        for record in records {
            let bytes = tokio::fs::read(self.attachment_host_path(&record)?)
                .await
                .with_context(|| {
                    let id = &record.id;
                    format!("failed to read attachment {id}")
                })?;
            materialized.push(MaterializedAttachment {
                attachment_id: record.id,
                modality: match record.modality {
                    pl_protocol::studio::StudioAttachmentModality::Image => {
                        pl_protocol::AttachmentModality::Image
                    }
                    pl_protocol::studio::StudioAttachmentModality::Video => {
                        pl_protocol::AttachmentModality::Video
                    }
                    pl_protocol::studio::StudioAttachmentModality::File => {
                        pl_protocol::AttachmentModality::File
                    }
                },
                media_type: record.media_type,
                filename: record.filename,
                data: base64::engine::general_purpose::STANDARD.encode(bytes),
                byte_size: record.byte_size,
                width: record.width,
                height: record.height,
                initial_remote_url: None,
            });
        }
        Ok(materialized)
    }

    /// Unified blob fence: makes every attachment blob a checkpoint still names durable.
    ///
    /// A published `state.toml` must never name a blob whose bytes or directory entry are not on
    /// disk yet. New blobs are synced when they are promoted, but the writer validates and waits on
    /// this fence explicitly instead of depending on that scattered call order. A missing catalog
    /// record or a missing blob is *not* "nothing to fence": the checkpoint names a blob that is
    /// not provably durable, so publication fails closed and is retried, surfacing the failure as
    /// persistence diagnostics instead of publishing a `state.toml` that points at absent bytes.
    pub(in crate::studio) async fn blob_fence(
        &self,
        thread_id: &str,
        attachment_ids: &[String],
    ) -> Result<()> {
        if attachment_ids.is_empty() {
            return Ok(());
        }
        let records = self.list_thread_attachments(thread_id).await?;
        for attachment_id in attachment_ids {
            let Some(record) = records.iter().find(|record| &record.id == attachment_id) else {
                anyhow::bail!(
                    "checkpoint names attachment {attachment_id} with no catalog record for Thread {thread_id}"
                );
            };
            let path = self.attachment_host_path(record)?;
            if !tokio::fs::try_exists(&path).await? {
                anyhow::bail!(
                    "checkpoint names missing attachment blob {} for Thread {thread_id}",
                    path.display()
                );
            }
            sync_blob(&path).await?;
        }
        Ok(())
    }

    pub(crate) async fn promote_attachment_drafts(
        &self,
        thread_id: &str,
        drafts: &[AttachmentDraftObject],
    ) -> Result<Vec<AttachmentRecord>> {
        let mut created_paths = Vec::new();
        let mut prepared = Vec::with_capacity(drafts.len());
        for draft in drafts {
            let result = async {
                // Current attachments share the per-session content-addressed blob root
                // (`sessions/<storage-key>/blobs`) with their catalog.
                let dir = self
                    .thread_blobs_dir(thread_id)?
                    .join(&draft.content_sha256[..2]);
                tokio::fs::create_dir_all(&dir).await?;
                let storage_path = dir.join(&draft.content_sha256);
                let created = if tokio::fs::try_exists(&storage_path).await? {
                    false
                } else {
                    tokio::fs::copy(&draft.storage_path, &storage_path).await?;
                    // 引用 blob 的 catalog/checkpoint 只会在本调用返回之后发布，所以 blob 的字节
                    // 和它的目录项必须先落盘，否则崩溃后 TOML 会指向一个不存在的附件。
                    if let Err(error) = sync_blob(&storage_path).await {
                        let _ = tokio::fs::remove_file(&storage_path).await;
                        return Err(error);
                    }
                    true
                };
                Ok::<_, anyhow::Error>((storage_path, created))
            }
            .await;
            match result {
                Ok((storage_path, created)) => {
                    if created {
                        created_paths.push(storage_path.clone());
                    }
                    prepared.push((draft, storage_path));
                }
                Err(error) => {
                    cleanup_created_blobs(created_paths).await;
                    return Err(error);
                }
            }
        }

        let session = self.registered_session_paths(thread_id)?;
        prepared
            .into_iter()
            .map(|(draft, storage_path)| {
                Ok(AttachmentRecord {
                    id: new_id("attachment"),
                    thread_id: thread_id.to_string(),
                    modality: draft.modality,
                    media_type: draft.media_type.clone(),
                    filename: Some(draft.filename.clone()),
                    blob_relative_path: crate::studio::store::session_layout::relative_blob_path(
                        &session,
                        &storage_path,
                    )?,
                    byte_size: draft.byte_size,
                    content_sha256: draft.content_sha256.clone(),
                    width: draft.width,
                    height: draft.height,
                    created_at: unix_seconds(),
                })
            })
            .collect()
    }

    async fn load_attachment_catalog(&self, thread_id: &str) -> Result<Vec<AttachmentRecord>> {
        let session = self.registered_session_paths(thread_id)?;
        let path = session.attachments_catalog();
        match tokio::fs::read_to_string(&path).await {
            Ok(content) => {
                let catalog: AttachmentCatalog = toml::from_str(&content)
                    .with_context(|| format!("invalid attachment catalog {}", path.display()))?;
                anyhow::ensure!(
                    catalog.schema_version == ATTACHMENT_CATALOG_SCHEMA_VERSION
                        && catalog.thread_id == thread_id
                        && catalog
                            .records
                            .iter()
                            .all(|record| record.thread_id == thread_id),
                    "attachment catalog identity or schema mismatch"
                );
                for record in &catalog.records {
                    resolve_attachment_host_path(&session, &record.blob_relative_path)?;
                }
                Ok(catalog.records)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                // A missing catalog means this Thread has no attachments yet.
                Ok(Vec::new())
            }
            Err(error) => Err(error.into()),
        }
    }

    async fn save_attachment_catalog(
        &self,
        thread_id: &str,
        records: &[AttachmentRecord],
    ) -> Result<()> {
        let session = self.registered_session_paths(thread_id)?;
        tokio::fs::create_dir_all(session.root()).await?;
        for record in records {
            resolve_attachment_host_path(&session, &record.blob_relative_path)?;
        }
        write_attachment_catalog(&session.attachments_catalog(), thread_id, records).await
    }
}

fn resolve_attachment_host_path(
    session: &crate::studio::paths::SessionPaths,
    stored: &str,
) -> Result<PathBuf> {
    let recorded = PathBuf::from(stored);
    anyhow::ensure!(
        !recorded.is_absolute(),
        "persistent attachments must use session-relative blob paths"
    );
    let relative = crate::studio::paths::posix_relative(&recorded)?;
    anyhow::ensure!(
        stored == relative,
        "attachment reference must use canonical POSIX form"
    );
    let resolved = session.root().join(Path::new(&relative));
    anyhow::ensure!(
        resolved.starts_with(session.blobs_dir()),
        "attachment is outside its Thread blob root"
    );
    Ok(resolved)
}

/// Writes the canonical attachment catalog for one Thread.
async fn write_attachment_catalog(
    path: &std::path::Path,
    thread_id: &str,
    records: &[AttachmentRecord],
) -> Result<()> {
    let contents = toml::to_string(&AttachmentCatalog {
        schema_version: ATTACHMENT_CATALOG_SCHEMA_VERSION,
        thread_id: thread_id.to_owned(),
        records: records.to_vec(),
    })?
    .into_bytes();
    let path = path.to_path_buf();
    tokio::task::spawn_blocking(move || {
        pl_tool::workspace::write_file_atomically(&path, &contents)
    })
    .await??;
    Ok(())
}

async fn cleanup_created_blobs(paths: Vec<PathBuf>) {
    for path in paths {
        let _ = tokio::fs::remove_file(path).await;
    }
}

/// Makes one newly written attachment blob and its directory entry durable.
///
/// The catalog and every checkpoint that references the blob are published only after promotion
/// returns, so the file contents and the directory entry must be synced first. Directory sync is
/// skipped on Windows, which has no equivalent operation.
async fn sync_blob(path: &std::path::Path) -> Result<()> {
    let file = path.to_owned();
    // Windows backs `sync_all` with `FlushFileBuffers`, which requires a writable handle;
    // opening the blob read-only returns `ERROR_ACCESS_DENIED` there.
    tokio::task::spawn_blocking(move || {
        let handle = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(file)?;
        handle.sync_all()
    })
    .await??;
    #[cfg(unix)]
    if let Some(directory) = path.parent() {
        let directory = directory.to_owned();
        tokio::task::spawn_blocking(move || std::fs::File::open(directory)?.sync_all()).await??;
    }
    Ok(())
}

#[derive(Debug, Clone)]
pub(crate) struct AttachmentDraftObject {
    pub draft_id: String,
    pub modality: pl_protocol::studio::StudioAttachmentModality,
    pub media_type: String,
    pub filename: String,
    pub storage_path: PathBuf,
    pub byte_size: u64,
    pub content_sha256: String,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

pub(crate) fn thread_attachment(record: &AttachmentRecord) -> ThreadAttachment {
    ThreadAttachment {
        id: record.id.clone(),
        modality: match record.modality {
            pl_protocol::studio::StudioAttachmentModality::Image => AttachmentModality::Image,
            pl_protocol::studio::StudioAttachmentModality::Video => AttachmentModality::Video,
            pl_protocol::studio::StudioAttachmentModality::File => AttachmentModality::File,
        },
        media_type: record.media_type.clone(),
        filename: record.filename.clone(),
        width: record.width,
        height: record.height,
        byte_size: record.byte_size,
    }
}
