//! The only Studio builtin producer that can prepare an explicit public artifact.
use super::{
    StudioThreadFactory,
    tool_bindings::{FileExecutionIdentity, ThreadToolLifetime},
};
use crate::resource_store::{ArchiveOrigin, PublicationEligibility};
use pl_core::{context::ResourceReader, tool::opaque::ToolError};
use pl_tool::{
    artifact::{
        ArtifactHost, ArtifactReceipt, ArtifactSource, MAX_ARTIFACT_BYTES, PublishArtifactInput,
    },
    media::ToolResourceOrigin,
    workspace_file::{
        LocalWorkspaceFileBackend, LocalWorkspaceRoot, WorkspaceFileBackend,
        WorkspaceFileReadBytesRequest,
    },
};
use sha2::{Digest, Sha256};
use std::{
    path::{Component, Path},
    sync::Arc,
};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone)]
struct Publications(StudioThreadFactory);

#[derive(Clone)]
struct PublicationBinding {
    file_execution: FileExecutionIdentity,
    lifetime: Arc<ThreadToolLifetime>,
    workspace: pl_tool::workspace::ToolWorkspace,
    remote: Option<pl_tool::remote::RemoteWorkspaceHost>,
}

impl StudioThreadFactory {
    pub(super) fn publication_registration(
        &self,
    ) -> Result<pl_core::tool::opaque::Registration, crate::thread_assembler::ThreadAssemblyError>
    {
        let declaration =
            pl_model::runtime::thread_tool_declaration(&pl_tool::artifact::declaration())?;
        Ok(
            pl_tool::artifact::ThreadPublishArtifactTool::new(Arc::new(Publications(self.clone())))
                .registration(declaration)?,
        )
    }
}

impl Publications {
    fn binding(&self, thread: &str) -> Result<PublicationBinding, ToolError> {
        self.0
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(thread)
            .filter(|binding| {
                !binding.target_invalidated && !binding.lifetime.cancellation.is_cancelled()
            })
            .map(|binding| PublicationBinding {
                file_execution: binding.file_execution.clone(),
                lifetime: binding.lifetime.clone(),
                workspace: binding.workspace.clone(),
                remote: binding.remote.clone(),
            })
            .ok_or_else(|| failure("Thread file execution binding is unavailable"))
    }

    fn current(
        &self,
        thread: &str,
        expected: &PublicationBinding,
        cancellation: &CancellationToken,
    ) -> bool {
        self.current_identity(
            thread,
            &expected.file_execution,
            &expected.lifetime.cancellation,
            cancellation,
        )
    }

    fn current_identity(
        &self,
        thread: &str,
        expected: &FileExecutionIdentity,
        lifetime: &CancellationToken,
        cancellation: &CancellationToken,
    ) -> bool {
        let bindings = self
            .0
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        !cancellation.is_cancelled()
            && !lifetime.is_cancelled()
            && bindings.get(thread).is_some_and(|current| {
                !current.target_invalidated
                    && !current.lifetime.cancellation.is_cancelled()
                    && current.file_execution.matches(expected)
            })
    }
}

impl ArtifactHost for Publications {
    async fn publish(
        &self,
        origin: ToolResourceOrigin,
        input: PublishArtifactInput,
        cancellation: CancellationToken,
    ) -> Result<ArtifactReceipt, ToolError> {
        if cancellation.is_cancelled() {
            return Err(cancelled_error());
        }
        let expected = self.binding(&origin.thread_id)?;
        let owner = self
            .0
            .services
            .store
            .thread_resources(&origin.thread_id)
            .await
            .map_err(host_failure)?;
        if owner
            .history()
            .tool_task(&origin.call_id)
            .await
            .map_err(host_failure)?
            .is_some_and(|saved| saved.delivery.is_some())
        {
            return Err(failure(
                "this publication call has already committed; it cannot be executed again",
            ));
        }
        if !self.current(&origin.thread_id, &expected, &cancellation) {
            return Err(inactive(&expected, &cancellation));
        }
        let mut hash = Sha256::new();
        hash.update(b"pl.studio.publication.v1\0");
        hash.update(serde_json::to_vec(&origin).map_err(ToolError::new)?);
        let publication_id = format!("publication:{}", hex::encode(hash.finalize()));
        let (preparation, (resource, default_name)) = match input.source {
            ArtifactSource::WorkspaceFile { path } => {
                let relative = workspace_path(&expected, &path)?;
                let filename = relative
                    .rsplit('/')
                    .next()
                    .filter(|name| pl_tool::artifact::validate_display_name(name).is_ok())
                    .unwrap_or("artifact")
                    .to_owned();
                let binding = expected.clone();
                let cancelled = cancellation.clone();
                owner.perform(ArchiveOrigin::Tool(origin.clone()), MAX_ARTIFACT_BYTES, move |store| async move {
                    let request = WorkspaceFileReadBytesRequest { cwd: None, path: relative, max_bytes: MAX_ARTIFACT_BYTES as usize };
                    let bytes = match &binding.remote {
                        Some(host) => host.files.read_bytes(request).await.map_err(ToolError::new)?,
                        None => {
                            let root = LocalWorkspaceRoot::open_beneath(binding.lifetime.file_io.clone(), binding.workspace.root().to_owned(), Default::default())
                                .await.map_err(ToolError::new)?;
                            let files = LocalWorkspaceFileBackend::confined_root(binding.workspace.clone(), root)
                                .await.map_err(ToolError::new)?;
                            files.read_bytes(request).await.map_err(ToolError::new)?
                        }
                    };
                    if cancelled.is_cancelled() { return Err(cancelled_error()); }
                    // Existing byte-based metadata inspection; never guess MIME from displayName.
                    let (bytes, media_type) = tokio::task::spawn_blocking(move || crate::studio::runtime::attachment_drafts::normalize::inspect_artifact_source(bytes, cancelled))
                        .await.map_err(ToolError::new)?.map_err(host_failure)?;
                    let reference = store.retain_bytes(bytes.into(), &media_type).await
                        .map_err(ToolError::new)?;
                    Ok(((reference.clone(), filename), vec![reference]))
                }).await.map_err(|error| preparation_error(error, &expected, &cancellation))?
            }
            ArtifactSource::ThreadResource { resource_id } => {
                let fact = owner
                    .history()
                    .resource_reference(&resource_id)
                    .await
                    .map_err(host_failure)?
                    .ok_or_else(|| {
                        failure("resource is not referenced by this Thread's persistent facts")
                    })?;
                if fact.reference.byte_len() > MAX_ARTIFACT_BYTES {
                    return Err(failure("artifact exceeds 50 MiB"));
                }
                let reference = fact.reference;
                let name = fact
                    .filename
                    .filter(|name| pl_tool::artifact::validate_display_name(name).is_ok())
                    .unwrap_or_else(|| "artifact".into());
                let verify = reference.clone();
                let cancelled = cancellation.clone();
                owner
                    .perform(
                        ArchiveOrigin::Tool(origin.clone()),
                        reference.byte_len(),
                        move |store| async move {
                            let bytes = store
                                .read(verify.clone(), cancelled)
                                .await
                                .map_err(ToolError::new)?;
                            verify.verify(&bytes).map_err(ToolError::new)?;
                            Ok(((verify.clone(), name), vec![verify]))
                        },
                    )
                    .await
                    .map_err(|error| preparation_error(error, &expected, &cancellation))?
            }
        };
        let display_name = input.display_name.unwrap_or(default_name);
        pl_tool::artifact::validate_display_name(&display_name)?;
        let receipt = ArtifactReceipt {
            publication_id,
            origin: origin.clone(),
            resource,
            display_name,
        };
        if !self.current(&origin.thread_id, &expected, &cancellation) {
            return Err(inactive(&expected, &cancellation));
        }
        let host = self.clone();
        // The pending proof retains only identity/cancellation, not copied Skill prompts, catalog
        // metadata, remote services or writable-path vectors from the whole installation binding.
        let identity = expected.file_execution.clone();
        let lifetime = expected.lifetime.cancellation.clone();
        owner.prove_publication(
            preparation,
            receipt.clone(),
            PublicationEligibility(Arc::new(move || {
                host.current_identity(&origin.thread_id, &identity, &lifetime, &cancellation)
            })),
        )?;
        Ok(receipt)
    }
}

fn workspace_path(binding: &PublicationBinding, path: &str) -> Result<String, ToolError> {
    if path.is_empty() {
        return Err(failure("artifact source path is empty"));
    }
    // Remote paths are POSIX even on a Windows host. This is only the publication's narrower
    // workspace boundary; actual access/no-follow/ordinary-file proof remains with the backend.
    if binding.remote.is_some() {
        if path.starts_with('/') || path.contains('\\') {
            return Err(failure(
                "SSH publication requires a workspace-relative POSIX path",
            ));
        }
        let mut parts = Vec::new();
        for part in path.split('/') {
            match part {
                "" | "." => {}
                ".." => {
                    if parts.pop().is_none() {
                        return Err(failure("artifact source is outside this Thread workspace"));
                    }
                }
                part => parts.push(part),
            }
        }
        return Ok(if parts.is_empty() {
            ".".into()
        } else {
            parts.join("/")
        });
    }
    let path = Path::new(path);
    let relative = if path.is_absolute() {
        path.strip_prefix(binding.workspace.root())
            .map_err(|_| failure("artifact source is outside this Thread workspace"))?
    } else {
        path
    };
    let mut parts = Vec::new();
    for part in relative.components() {
        match part {
            Component::Normal(part) => parts.push(
                part.to_str()
                    .ok_or_else(|| failure("artifact path is not UTF-8"))?,
            ),
            Component::CurDir => {}
            Component::ParentDir => {
                if parts.pop().is_none() {
                    return Err(failure("artifact source is outside this Thread workspace"));
                }
            }
            Component::RootDir | Component::Prefix(_) => {
                return Err(failure(
                    "artifact source must remain inside this Thread workspace",
                ));
            }
        }
    }
    Ok(if parts.is_empty() {
        ".".into()
    } else {
        parts.join("/")
    })
}
fn failure(message: &str) -> ToolError {
    ToolError::new(std::io::Error::other(message.to_owned()))
}
fn cancelled_error() -> ToolError {
    ToolError::new(pl_core::thread::ThreadError::Cancelled)
}
fn inactive(binding: &PublicationBinding, cancellation: &CancellationToken) -> ToolError {
    if cancellation.is_cancelled() || binding.lifetime.cancellation.is_cancelled() {
        cancelled_error()
    } else {
        failure("publication execution binding changed")
    }
}
fn preparation_error(
    error: ToolError,
    binding: &PublicationBinding,
    cancellation: &CancellationToken,
) -> ToolError {
    if cancellation.is_cancelled() || binding.lifetime.cancellation.is_cancelled() {
        cancelled_error()
    } else {
        error
    }
}
fn host_failure(error: anyhow::Error) -> ToolError {
    ToolError::new(std::io::Error::other(format!("{error:#}")))
}
