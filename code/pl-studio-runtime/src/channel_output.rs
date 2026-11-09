//! Explicit file delivery to a frozen channel target. Upload confirmation is not delivery.
//!
//! Adapters receive archived original bytes, never filesystem paths. The calling owner
//! must durably record each attempted stage before polling its future, and must not
//! automatically retry an unknown outcome.

use pl_core::context::ResourceReference;
use pl_protocol::AttachmentModality;
use serde::{Deserialize, Serialize};
use std::{collections::BTreeMap, future::Future, pin::Pin, sync::Arc};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChannelTarget {
    pub adapter: String,
    pub account_id: String,
    pub conversation_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileDelivery {
    pub resource: ResourceReference,
    pub filename: String,
    pub modality: AttachmentModality,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileCapabilities {
    pub image_max_bytes: Option<u64>,
    pub file_max_bytes: Option<u64>,
}

/// Adapter-owned material; only the adapter that created it interprets the value.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UploadHandle(pub String);

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlatformMessageId(pub String);

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ChannelError {
    #[error("file delivery rejected: {0}")]
    Rejected(String),
    #[error("file delivery acceptance unknown: {0}")]
    Unknown(String),
}

/// Result of the selected owner's complete, ledger-backed send, not just an upload.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChannelDeliveryResult {
    Confirmed { message_ids: Vec<PlatformMessageId> },
    Rejected { diagnostic: String, retryable: bool },
    Unknown { diagnostic: String },
}

/// A source-selected sender owns authentication, authorization and durable replay.
/// Construction must not send anything. Each method revalidates its source lease.
pub trait ChannelOutputPort: Send + Sync {
    fn send_caption(
        &self,
        target: &ChannelTarget,
        operation_id: &str,
        caption: &str,
        cancel: &CancellationToken,
    ) -> impl Future<Output = ChannelDeliveryResult> + Send;

    fn send_file(
        &self,
        target: &ChannelTarget,
        operation_id: &str,
        file: &FileDelivery,
        bytes: Vec<u8>,
        cancel: &CancellationToken,
    ) -> impl Future<Output = ChannelDeliveryResult> + Send;
}

type OutputFuture<'a> = Pin<Box<dyn Future<Output = ChannelDeliveryResult> + Send + 'a>>;

trait ErasedOutputPort: Send + Sync {
    fn send_caption<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        caption: &'a str,
        cancel: &'a CancellationToken,
    ) -> OutputFuture<'a>;
    fn send_file<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        file: &'a FileDelivery,
        bytes: Vec<u8>,
        cancel: &'a CancellationToken,
    ) -> OutputFuture<'a>;
}

impl<T: ChannelOutputPort> ErasedOutputPort for T {
    fn send_caption<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        caption: &'a str,
        cancel: &'a CancellationToken,
    ) -> OutputFuture<'a> {
        Box::pin(ChannelOutputPort::send_caption(
            self, target, operation, caption, cancel,
        ))
    }
    fn send_file<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        file: &'a FileDelivery,
        bytes: Vec<u8>,
        cancel: &'a CancellationToken,
    ) -> OutputFuture<'a> {
        Box::pin(ChannelOutputPort::send_file(
            self, target, operation, file, bytes, cancel,
        ))
    }
}

/// Immutable source binding. Generic dispatch cannot substitute the target or sender.
#[derive(Clone)]
pub struct ChannelOutputBinding {
    target: ChannelTarget,
    port: Arc<dyn ErasedOutputPort>,
}

impl ChannelOutputBinding {
    pub fn new(target: ChannelTarget, port: impl ChannelOutputPort + 'static) -> Self {
        Self {
            target,
            port: Arc::new(port),
        }
    }

    pub fn target(&self) -> &ChannelTarget {
        &self.target
    }

    pub async fn send_caption(
        &self,
        operation: &str,
        caption: &str,
        cancel: &CancellationToken,
    ) -> ChannelDeliveryResult {
        self.port
            .send_caption(&self.target, operation, caption, cancel)
            .await
    }

    pub async fn send_file(
        &self,
        operation: &str,
        file: &FileDelivery,
        bytes: Vec<u8>,
        cancel: &CancellationToken,
    ) -> ChannelDeliveryResult {
        if let Err(error) = file.resource.verify(&bytes) {
            return ChannelDeliveryResult::Rejected {
                diagnostic: error.to_string(),
                retryable: false,
            };
        }
        self.port
            .send_file(&self.target, operation, file, bytes, cancel)
            .await
    }
}

pub trait ChannelAdapter: Send + Sync {
    fn capabilities(&self) -> FileCapabilities;

    fn upload(
        &self,
        target: &ChannelTarget,
        operation_id: &str,
        file: &FileDelivery,
        bytes: Vec<u8>,
    ) -> impl Future<Output = Result<UploadHandle, ChannelError>> + Send;

    fn send(
        &self,
        target: &ChannelTarget,
        operation_id: &str,
        file: &FileDelivery,
        uploaded: &UploadHandle,
    ) -> impl Future<Output = Result<PlatformMessageId, ChannelError>> + Send;
}

type AdapterFuture<'a, T> = Pin<Box<dyn Future<Output = Result<T, ChannelError>> + Send + 'a>>;

// The only erasure boundary: routing is independent of concrete platform names.
trait ErasedAdapter: Send + Sync {
    fn capabilities(&self) -> FileCapabilities;
    fn upload<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        file: &'a FileDelivery,
        bytes: Vec<u8>,
    ) -> AdapterFuture<'a, UploadHandle>;
    fn send<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        file: &'a FileDelivery,
        handle: &'a UploadHandle,
    ) -> AdapterFuture<'a, PlatformMessageId>;
}

impl<T: ChannelAdapter> ErasedAdapter for T {
    fn capabilities(&self) -> FileCapabilities {
        ChannelAdapter::capabilities(self)
    }
    fn upload<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        file: &'a FileDelivery,
        bytes: Vec<u8>,
    ) -> AdapterFuture<'a, UploadHandle> {
        Box::pin(ChannelAdapter::upload(self, target, operation, file, bytes))
    }
    fn send<'a>(
        &'a self,
        target: &'a ChannelTarget,
        operation: &'a str,
        file: &'a FileDelivery,
        handle: &'a UploadHandle,
    ) -> AdapterFuture<'a, PlatformMessageId> {
        Box::pin(ChannelAdapter::send(self, target, operation, file, handle))
    }
}

#[derive(Default)]
pub struct ChannelRegistry {
    adapters: BTreeMap<String, Box<dyn ErasedAdapter>>,
}

impl ChannelRegistry {
    pub fn register(
        &mut self,
        key: String,
        adapter: impl ChannelAdapter + 'static,
    ) -> Result<(), ChannelError> {
        if key.is_empty() || self.adapters.contains_key(&key) {
            return Err(ChannelError::Rejected(
                "duplicate or empty adapter key".into(),
            ));
        }
        self.adapters.insert(key, Box::new(adapter));
        Ok(())
    }

    fn adapter(&self, target: &ChannelTarget) -> Result<&dyn ErasedAdapter, ChannelError> {
        self.adapters
            .get(&target.adapter)
            .map(|adapter| adapter.as_ref())
            .ok_or_else(|| ChannelError::Rejected("channel adapter is not registered".into()))
    }

    pub fn capabilities(&self, target: &ChannelTarget) -> Result<FileCapabilities, ChannelError> {
        Ok(self.adapter(target)?.capabilities())
    }

    pub async fn upload(
        &self,
        target: &ChannelTarget,
        operation: &str,
        file: &FileDelivery,
        bytes: Vec<u8>,
    ) -> Result<UploadHandle, ChannelError> {
        if file.filename.is_empty() || file.filename.contains(['/', '\\', '\r', '\n', '\0']) {
            return Err(ChannelError::Rejected(
                "delivery requires a filename, not a path".into(),
            ));
        }
        file.resource
            .verify(&bytes)
            .map_err(|error| ChannelError::Rejected(error.to_string()))?;
        let capabilities = self.capabilities(target)?;
        let limit = match file.modality {
            AttachmentModality::Image => capabilities.image_max_bytes,
            AttachmentModality::File | AttachmentModality::Video => capabilities.file_max_bytes,
        };
        if limit.is_none_or(|limit| bytes.len() as u64 > limit) {
            return Err(ChannelError::Rejected(
                "adapter does not support this file type or size".into(),
            ));
        }
        self.adapter(target)?
            .upload(target, operation, file, bytes)
            .await
    }

    pub async fn send(
        &self,
        target: &ChannelTarget,
        operation: &str,
        file: &FileDelivery,
        handle: &UploadHandle,
    ) -> Result<PlatformMessageId, ChannelError> {
        self.adapter(target)?
            .send(target, operation, file, handle)
            .await
    }
}
