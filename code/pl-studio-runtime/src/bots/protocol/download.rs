//! Bounded resource download and joinable local file publication.
use super::classify::{classify_http_status, transport};
use super::error::{FeishuError, FeishuErrorKind};
use super::http::FeishuHttp;
use std::path::{Path, PathBuf};
use tempfile::NamedTempFile;
use tokio_util::sync::CancellationToken;

/// Filesystem operations run inside the download owner's blocking jobs.
pub(in crate::bots) trait ResourceFiles: Send + Sync {
    fn create(
        &self,
        destination: &Path,
        cancel: &CancellationToken,
    ) -> std::io::Result<(NamedTempFile, PathBuf)>;
    fn persist(
        &self,
        temporary: NamedTempFile,
        native_destination: &Path,
        logical_destination: &Path,
    ) -> std::io::Result<()>;
}

pub(in crate::bots) struct LocalResourceFiles;

impl ResourceFiles for LocalResourceFiles {
    fn create(
        &self,
        destination: &Path,
        _: &CancellationToken,
    ) -> std::io::Result<(NamedTempFile, PathBuf)> {
        let parent = destination
            .parent()
            .ok_or_else(|| std::io::Error::other("resource parent missing"))?;
        let filename = destination
            .file_name()
            .ok_or_else(|| std::io::Error::other("resource filename missing"))?;
        std::fs::create_dir_all(parent)?;
        // Keep Win32's native spelling inside the owned filesystem operation.
        let parent = std::fs::canonicalize(parent)?;
        let native_destination = parent.join(filename);
        Ok((NamedTempFile::new_in(parent)?, native_destination))
    }

    fn persist(
        &self,
        temporary: NamedTempFile,
        native_destination: &Path,
        _: &Path,
    ) -> std::io::Result<()> {
        temporary
            .persist(native_destination)
            .map_err(|error| error.error)?;
        Ok(())
    }
}

impl FeishuHttp {
    /// Streams a message-owned resource to an atomically published file. Credentials stay in
    /// the Authorization header; path segments cannot change the configured API origin.
    pub async fn download_message_resource(
        &self,
        token: &str,
        message_id: &str,
        key: &str,
        kind: &str,
        destination: &std::path::Path,
        cancel: &CancellationToken,
    ) -> Result<(), FeishuError> {
        use tokio::io::AsyncWriteExt;
        let mut url = self.open_api().clone();
        url.path_segments_mut()
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "invalid resource API base",
                    false,
                    None,
                )
            })?
            .pop_if_empty()
            .extend([
                "open-apis",
                "im",
                "v1",
                "messages",
                message_id,
                "resources",
                key,
            ]);
        url.query_pairs_mut().append_pair("type", kind);
        let request = self.client().get(url).bearer_auth(token).send();
        let mut response = tokio::select! {
            biased;
            _ = cancel.cancelled() => return Err(resource_cancelled()),
            response = request => response.map_err(transport)?,
        };
        if !response.status().is_success() {
            return Err(classify_http_status(response.status()));
        }
        let limit = if kind == "image" {
            20 * 1024 * 1024
        } else {
            50 * 1024 * 1024
        };
        if response
            .content_length()
            .is_some_and(|length| length > limit)
        {
            return Err(resource_too_large());
        }
        if cancel.is_cancelled() {
            return Err(resource_cancelled());
        }
        // Started filesystem work must drain before the temporary file can be removed.
        let setup_files = self.resource_files.clone();
        let setup_destination = destination.to_owned();
        let setup_cancel = cancel.clone();
        let (temporary, native_destination) = tokio::task::spawn_blocking(move || {
            setup_files.create(&setup_destination, &setup_cancel)
        })
        .await
        .map_err(resource_io)?
        .map_err(resource_io)?;
        let mut file = tokio::fs::File::from_std(temporary.reopen().map_err(resource_io)?);
        let transferred = async {
            let mut total = 0u64;
            loop {
                // Network reads have no file operation to drain; cancellation
                // stops producing new writes, but never abandons an old write.
                let chunk = tokio::select! {
                    biased;
                    _ = cancel.cancelled() => return Err(resource_cancelled()),
                    chunk = response.chunk() => chunk.map_err(transport)?,
                };
                let Some(bytes) = chunk else {
                    return Ok(());
                };
                total = total
                    .checked_add(bytes.len() as u64)
                    .ok_or_else(resource_too_large)?;
                if total > limit {
                    return Err(resource_too_large());
                }
                file.write_all(&bytes).await.map_err(resource_io)?;
            }
        }
        .await;
        // write_all may only have filled Tokio's buffer. Drain even on network,
        // limit, write-error and cancellation exits, before removing the temp.
        let flushed = file.flush().await.map_err(resource_io);
        let synced = if transferred.is_ok() && flushed.is_ok() && !cancel.is_cancelled() {
            file.sync_all().await.map_err(resource_io)
        } else {
            Ok(())
        };
        // into_std also waits for in-flight work if flush reported an error.
        drop(file.into_std().await);
        if let Err(error) = transferred {
            if let Err(flush_error) = flushed {
                tracing::warn!(%flush_error, "resource flush failed while draining a failed download");
            }
            return Err(error);
        }
        flushed?;
        synced?;
        if cancel.is_cancelled() {
            return Err(resource_cancelled());
        }
        let files = self.resource_files.clone();
        let destination = destination.to_owned();
        tokio::task::spawn_blocking(move || {
            files.persist(temporary, &native_destination, &destination)
        })
        .await
        .map_err(resource_io)?
        .map_err(resource_io)?;
        if cancel.is_cancelled() {
            return Err(resource_cancelled());
        }
        Ok(())
    }
}

fn resource_io(error: impl std::fmt::Display) -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        format!("message resource storage: {error}"),
        true,
        None,
    )
}

fn resource_cancelled() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "message resource download cancelled after draining file work",
        true,
        None,
    )
}

fn resource_too_large() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Rejected,
        "消息附件超过支持的大小（图片 20 MiB，文件 50 MiB）",
        false,
        None,
    )
}
