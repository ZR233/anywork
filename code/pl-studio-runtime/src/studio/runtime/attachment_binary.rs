//! Original-file pins over the runtime's existing scope and read-call owners.
use std::fs::File;
use std::future::Future;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result};
pub use pl_protocol::studio::{
    AttachmentBinaryChunk, AttachmentBinaryIdentity, AttachmentBinaryTarget, FeedCloseReport,
    StudioError,
};

use super::StudioRuntime;
use super::read_calls::ReadCalls;
use super::read_scopes::{PinnedMaterial, ReadScopeBudgetKey, ReadScopeOwner};

const DEFAULT_BLOCK_BYTES: i64 = 65536;
const MAX_BLOCK_BYTES: i64 = 262144;

struct BinaryFile {
    // Each seek/read is one worker operation under this file-only lock, never a registry lock.
    file: Mutex<File>,
    byte_length: i64,
}

#[derive(Default)]
struct BinaryMaterial {
    file: Option<Arc<BinaryFile>>,
}

/// A query-only resource: no producer, ACK, arbitrary path or mutable attachment catalog.
/// Caller cancellation abandons waiting, not the actual registered opening/IO worker.
pub struct StudioAttachmentBinaryRead {
    identity: AttachmentBinaryIdentity,
    byte_length: i64,
    owner: Arc<ReadScopeOwner>,
    material: Arc<PinnedMaterial<Mutex<BinaryMaterial>>>,
    calls: ReadCalls,
}

// Registered before the first await, including a future dropped without ever being polled.
struct Opening(Option<Arc<ReadScopeOwner>>);
impl Drop for Opening {
    fn drop(&mut self) {
        if let Some(owner) = &self.0 {
            owner.request_close();
            owner.release_if_joined();
        }
    }
}

impl StudioRuntime {
    /// Pins the original draft file. Open and remove linearize on the original entries owner.
    /// # Errors
    /// Returns typed NotFound, Storage, Cancelled or the original shared scope/call limit.
    pub fn open_draft_binary(
        &self,
        draft_id: String,
    ) -> impl Future<Output = Result<StudioAttachmentBinaryRead>> + Send + 'static + use<> {
        self.open_attachment_binary(AttachmentBinaryTarget::Draft { draft_id })
    }

    /// Authorizes the owned Thread/catalog or complete typed delivery before opening a file.
    /// # Errors
    /// Returns the original ownership error, typed NotFound/Storage or shared admission failure.
    pub fn open_thread_binary(
        &self,
        thread_id: String,
        attachment_id: String,
    ) -> impl Future<Output = Result<StudioAttachmentBinaryRead>> + Send + 'static + use<> {
        self.open_attachment_binary(AttachmentBinaryTarget::Thread {
            thread_id,
            attachment_id,
        })
    }

    fn open_attachment_binary(
        &self,
        target: AttachmentBinaryTarget,
    ) -> impl Future<Output = Result<StudioAttachmentBinaryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        // Both the scope reservation and its single ReadCalls registration are synchronous.
        let admitted = (|| -> Result<_> {
            let incarnation = self.observation_ids.next()?;
            let identity = AttachmentBinaryIdentity {
                scope_id: crate::studio::new_id("attachment-read"),
                runtime_epoch: self.owner_epoch.clone(),
                incarnation,
                target: target.clone(),
            };
            let key = match &target {
                AttachmentBinaryTarget::Draft { .. } => ReadScopeBudgetKey::AttachmentDraftRuntime,
                AttachmentBinaryTarget::Thread { thread_id, .. } => {
                    ReadScopeBudgetKey::Thread(thread_id.clone())
                }
            };
            let group = self.read_scopes.group(key, incarnation);
            let (owner, material) = group.open(
                identity.scope_id.clone(),
                Mutex::new(BinaryMaterial::default()),
            )?;
            let opening = Opening(Some(owner.clone()));
            let slot = material.clone();
            let query = owner.run(&self.read_calls, async move {
                let file = Arc::new(runtime.open_attachment_file(target).await?);
                let length = file.byte_length;
                slot.read(|slot| {
                    slot.lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .file = Some(file);
                    Ok(())
                })?;
                Ok(length)
            });
            Ok((identity, owner, material, opening, query))
        })();
        let calls = self.read_calls.clone();
        async move {
            let (identity, owner, material, mut opening, query) = admitted?;
            let byte_length = match query.await {
                Ok(length) => length,
                Err(error) => {
                    // Read errors do not become sticky cleanup errors; real failed joins do.
                    let _ = owner.close().await;
                    return Err(error);
                }
            };
            owner.ensure_open()?;
            let read = StudioAttachmentBinaryRead {
                identity,
                byte_length,
                owner,
                material,
                calls,
            };
            opening.0.take();
            Ok(read)
        }
    }

    async fn open_attachment_file(&self, target: AttachmentBinaryTarget) -> Result<BinaryFile> {
        let (file, expected_length) = match target {
            AttachmentBinaryTarget::Draft { draft_id } => {
                self.attachment_drafts.open_binary(&draft_id).await?
            }
            AttachmentBinaryTarget::Thread {
                thread_id,
                attachment_id,
            } => {
                self.read_owned_thread(&thread_id).await?;
                if attachment_id.starts_with(crate::resource_store::RESOURCE_ID_PREFIX) {
                    let reference = self
                        .authorized_tool_media(&thread_id, &attachment_id)
                        .await?;
                    let resources = crate::resource_store::FileResourceStore::new(
                        self.store
                            .session_resources_dir(&thread_id)
                            .context(StudioError::storage())?,
                    );
                    let expected_length = reference.byte_len();
                    // Hash and every later block use this exact File; no verified-path reopen.
                    let file =
                        tokio::task::spawn_blocking(move || resources.open_verified(&reference))
                            .await?
                            .context(StudioError::storage())?;
                    (file, expected_length)
                } else {
                    let record = self
                        .store
                        .list_thread_attachments(&thread_id)
                        .await
                        .context(StudioError::storage())?
                        .into_iter()
                        .find(|record| record.id == attachment_id)
                        .ok_or_else(|| StudioError::not_found("ThreadAttachment"))?;
                    let path = self
                        .store
                        .attachment_host_path(&record)
                        .context(StudioError::storage())?;
                    let file = tokio::task::spawn_blocking(move || File::open(path)).await??;
                    (file, record.byte_size)
                }
            }
        };
        tokio::task::spawn_blocking(move || {
            let metadata = file.metadata()?;
            if !metadata.is_file() || metadata.len() != expected_length {
                return Err(StudioError::storage().into());
            }
            let byte_length = i64::try_from(metadata.len()).context(StudioError::storage())?;
            Ok(BinaryFile {
                file: Mutex::new(file),
                byte_length,
            })
        })
        .await?
    }

    async fn authorized_tool_media(
        &self,
        thread_id: &str,
        attachment_id: &str,
    ) -> Result<pl_core::context::ResourceReference> {
        let facts = self
            .read_thread_state(thread_id)
            .await
            .context(StudioError::storage())?;
        let mut deliveries = facts.deliveries.to_vec();
        // Read the pending window first. An effect released from this window is already in
        // history, so the following typed history query closes that handoff race.
        if let Some((_, handle)) = self
            .threads
            .observed_threads()
            .into_iter()
            .find(|(id, _)| id == thread_id)
        {
            for effect in handle.effects().await? {
                deliveries.extend(effect.deliveries.iter().cloned());
            }
        }
        deliveries.extend(
            self.store
                .history(thread_id)
                .await
                .context(StudioError::storage())?
                .tool_media_deliveries(attachment_id)
                .await
                .context(StudioError::storage())?,
        );
        crate::studio::thread_projection::persisted_reference(&deliveries, attachment_id)
            .context(StudioError::storage())?
            .ok_or_else(|| StudioError::not_found("ThreadToolAttachment").into())
    }
}

impl StudioAttachmentBinaryRead {
    pub fn identity(&self) -> AttachmentBinaryIdentity {
        self.identity.clone()
    }
    pub fn byte_length(&self) -> i64 {
        self.byte_length
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.owner.ensure_open()
    }

    /// Registers the actual bounded file operation before returning its future.
    /// # Errors
    /// maxBytes must be 1..=262144 (default 65536); offset must be in 0..=byteLength.
    /// A changed length or premature EOF is Storage, including at the original terminal offset.
    pub fn read(
        &self,
        offset: i64,
        max_bytes: Option<i64>,
    ) -> impl Future<Output = Result<AttachmentBinaryChunk>> + Send + 'static + use<> {
        let material = self.material.clone();
        self.owner.run(&self.calls, async move {
            let maximum = max_bytes.unwrap_or(DEFAULT_BLOCK_BYTES);
            if !(1..=MAX_BLOCK_BYTES).contains(&maximum) {
                return Err(
                    StudioError::invalid_argument("Binary maxBytes must be in 1..=262144").into(),
                );
            }
            let file = material.read(|slot| {
                slot.lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .file
                    .clone()
                    .ok_or_else(StudioError::internal)
            })?;
            if offset < 0 || offset > file.byte_length {
                return Err(StudioError::invalid_argument(
                    "Binary offset must be in 0..=byteLength",
                )
                .into());
            }
            // Reject overflow before IO, rather than saturating/clamping an overflowing request.
            if offset < file.byte_length {
                offset.checked_add(maximum).ok_or_else(|| {
                    StudioError::invalid_argument("Binary offset plus maxBytes overflowed")
                })?;
            }
            tokio::task::spawn_blocking(move || file.read_block(offset, maximum)).await?
        })
    }

    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.owner.close().await
    }

    /// The native session-forwarding consumer also uses this original pin, with bounded buffers
    /// and the existing read-call supervision for the complete atomic output worker.
    pub(in crate::studio::runtime) fn copy_to(
        &self,
        destination: PathBuf,
    ) -> impl Future<Output = Result<()>> + Send + 'static + use<> {
        let material = self.material.clone();
        self.owner.run(&self.calls, async move {
            let file = material.read(|slot| {
                slot.lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .file
                    .clone()
                    .ok_or_else(StudioError::internal)
            })?;
            tokio::task::spawn_blocking(move || {
                let parent = destination
                    .parent()
                    .context("attachment destination has no parent")?;
                let mut output = tempfile::NamedTempFile::new_in(parent)?;
                let mut offset = 0;
                loop {
                    let block = file.read_block(offset, DEFAULT_BLOCK_BYTES)?;
                    output.write_all(&block.bytes)?;
                    match block.next_offset {
                        Some(next) => offset = next,
                        None => break,
                    }
                }
                output.as_file().sync_all()?;
                output.persist(destination)?;
                Ok(())
            })
            .await?
        })
    }
}

impl Drop for StudioAttachmentBinaryRead {
    fn drop(&mut self) {
        self.request_close();
        self.owner.release_if_joined();
    }
}

impl BinaryFile {
    fn read_block(&self, offset: i64, maximum: i64) -> Result<AttachmentBinaryChunk> {
        let mut file = self.file.lock().map_err(|_| StudioError::storage())?;
        let original_length = u64::try_from(self.byte_length).context(StudioError::storage())?;
        if file.metadata()?.len() != original_length {
            return Err(StudioError::storage().into());
        }
        let count = usize::try_from(maximum.min(self.byte_length - offset))
            .context(StudioError::storage())?;
        let mut bytes = vec![0; count];
        file.seek(SeekFrom::Start(
            u64::try_from(offset).context(StudioError::storage())?,
        ))?;
        // read_exact detects external truncate: an intermediate empty/short read is not EOF.
        file.read_exact(&mut bytes)?;
        if file.metadata()?.len() != original_length {
            return Err(StudioError::storage().into());
        }
        let next = offset
            .checked_add(i64::try_from(bytes.len()).context(StudioError::storage())?)
            .ok_or_else(StudioError::storage)?;
        Ok(AttachmentBinaryChunk {
            offset,
            bytes,
            next_offset: (next < self.byte_length).then_some(next),
        })
    }
}
