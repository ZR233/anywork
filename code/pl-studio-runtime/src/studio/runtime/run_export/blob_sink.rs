//! Stream canonical originals into content-addressed files and verify existing blobs.
use super::types::{ExportedBlobV3, validate_export_relative_path};
use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};
use std::fs;
use std::future::Future;
use std::path::{Path, PathBuf};
use tokio::fs::File;
use tokio::io::{AsyncReadExt, AsyncWriteExt, BufWriter};

const VERIFY_CHUNK_BYTES: usize = 64 * 1024;

/// Streaming content-addressed blob writer abstraction (allows test doubles without bypassing real files).
pub trait ContentBlobSink {
    type Writer: BlobChunkWriter;
    fn begin_blob(&mut self) -> impl Future<Output = Result<Self::Writer>> + Send;
}

pub trait BlobChunkWriter {
    fn write_chunk(&mut self, chunk: &[u8]) -> impl Future<Output = Result<()>> + Send;
    fn finish(
        self,
        media_type: Option<String>,
        encoding: String,
    ) -> impl Future<Output = Result<ExportedBlobV3>> + Send;
}

pub struct FsContentBlobSink {
    output_dir: PathBuf,
    contents_dir: PathBuf,
}

impl FsContentBlobSink {
    pub fn new(output_dir: PathBuf) -> Self {
        let contents_dir = output_dir.join("contents");
        Self {
            output_dir,
            contents_dir,
        }
    }
}

pub struct FsBlobWriter {
    output_dir: PathBuf,
    contents_dir: PathBuf,
    temp_path: PathBuf,
    file: Option<BufWriter<File>>,
    hasher: Sha256,
    byte_length: u64,
}

impl Drop for FsBlobWriter {
    fn drop(&mut self) {
        self.file.take();
        let _ = fs::remove_file(&self.temp_path);
    }
}

impl ContentBlobSink for FsContentBlobSink {
    type Writer = FsBlobWriter;

    async fn begin_blob(&mut self) -> Result<Self::Writer> {
        tokio::fs::create_dir_all(&self.contents_dir)
            .await
            .with_context(|| format!("ensure contents dir {}", self.contents_dir.display()))?;
        ensure!(
            !fs::symlink_metadata(&self.contents_dir)?
                .file_type()
                .is_symlink(),
            "contents directory must not be a symlink"
        );
        let nonce = uuid::Uuid::new_v4().simple();
        let temp_path = self
            .contents_dir
            .join(format!(".blob.{}.{nonce}.tmp", std::process::id()));
        let file = File::create(&temp_path)
            .await
            .with_context(|| format!("create content temp file {}", temp_path.display()))?;
        Ok(FsBlobWriter {
            output_dir: self.output_dir.clone(),
            contents_dir: self.contents_dir.clone(),
            temp_path,
            file: Some(BufWriter::new(file)),
            hasher: Sha256::new(),
            byte_length: 0,
        })
    }
}

impl BlobChunkWriter for FsBlobWriter {
    async fn write_chunk(&mut self, chunk: &[u8]) -> Result<()> {
        let writer = self.file.as_mut().context("blob writer already finished")?;
        writer.write_all(chunk).await?;
        self.hasher.update(chunk);
        self.byte_length = self
            .byte_length
            .checked_add(chunk.len() as u64)
            .context("blob length overflow")?;
        Ok(())
    }

    async fn finish(
        mut self,
        media_type: Option<String>,
        encoding: String,
    ) -> Result<ExportedBlobV3> {
        let mut writer = self.file.take().context("blob writer already finished")?;
        writer.flush().await?;
        let file = writer.into_inner();
        file.sync_all().await?;
        drop(file);

        let sha256 = hex::encode(self.hasher.clone().finalize());
        let rel_path = format!("contents/{sha256}.bin");
        validate_export_relative_path(&rel_path)?;
        let final_path = self.output_dir.join(&rel_path);
        ensure!(
            final_path.starts_with(&self.contents_dir),
            "resolved content path escaped contents directory: {}",
            final_path.display()
        );

        match tokio::fs::symlink_metadata(&final_path).await {
            Ok(meta) => {
                ensure!(
                    !meta.file_type().is_symlink() && meta.is_file(),
                    "existing content target {} is not a regular file",
                    final_path.display()
                );
                ensure!(
                    meta.len() == self.byte_length,
                    "existing content blob {} length {} disagrees with expected {}",
                    rel_path,
                    meta.len(),
                    self.byte_length
                );
                verify_existing_file_sha256(&final_path, &sha256).await?;
                let _ = fs::remove_file(&self.temp_path);
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                tokio::fs::rename(&self.temp_path, &final_path)
                    .await
                    .with_context(|| {
                        format!(
                            "commit content blob {} -> {}",
                            self.temp_path.display(),
                            final_path.display()
                        )
                    })?;
            }
            Err(error) => {
                let _ = fs::remove_file(&self.temp_path);
                return Err(error)
                    .with_context(|| format!("inspect content target {}", final_path.display()));
            }
        }

        Ok(ExportedBlobV3 {
            path: rel_path,
            byte_length: self.byte_length,
            sha256,
            media_type,
            encoding,
        })
    }
}

async fn verify_existing_file_sha256(path: &Path, expected_sha256: &str) -> Result<()> {
    let file = File::open(path)
        .await
        .with_context(|| format!("open existing content blob {}", path.display()))?;
    let actual = hash_reader(file).await?;
    ensure!(
        actual == expected_sha256,
        "content hash mismatch in {}: expected {expected_sha256}, observed {actual}",
        path.display()
    );
    Ok(())
}

pub(super) async fn hash_file(path: &Path) -> Result<String> {
    hash_reader(File::open(path).await?).await
}

async fn hash_reader(mut file: File) -> Result<String> {
    let mut hasher = Sha256::new();
    // Keep the bounded chunk on the heap: this verifier is nested in the export task's
    // async state machine, whose inline buffers otherwise multiply across polling frames.
    let mut buf = vec![0_u8; VERIFY_CHUNK_BYTES];
    loop {
        let n = file.read(&mut buf).await?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}
