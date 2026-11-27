//! Product binding: frozen grants, archive membership, and saved display receipts.
use super::{FileDisplayOrigin, FileDisplayReceipt, FileDisplayResult, ShowFilesInput, failure};
use crate::{
    media::{DomainMediaHost, ToolMediaHost, domain_error},
    workspace_file::{
        WorkspaceFileBackend, WorkspaceFileReadBytesRequest, WorkspaceFileStatRequest,
    },
};
use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::{ContextContent, ResourceReference},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_model::completion::AttachmentModality;
use pl_tool_media::show_files as domain;
use std::sync::Arc;

struct AuthorizedFiles<B> {
    backend: Arc<B>,
    context: CallContext,
}

impl<B: WorkspaceFileBackend + 'static> domain::FileSource for AuthorizedFiles<B> {
    type Reference = ResourceReference;
    type Deferred = super::DeferredWorkspaceFile;
    type Error = ToolError;

    async fn defer_file(&self, path: &str) -> Result<Self::Deferred, ToolError> {
        self.backend.defer_file(path).await.map_err(ToolError::new)
    }

    async fn stat(&self, path: &str) -> Result<domain::FileStat, ToolError> {
        let stat = self
            .backend
            .stat(WorkspaceFileStatRequest {
                path: path.into(),
                cwd: None,
            })
            .await
            .map_err(ToolError::new)?;
        Ok(domain::FileStat {
            is_file: stat.is_file,
        })
    }

    async fn local_file_path(&self, path: &str) -> Result<Option<String>, ToolError> {
        self.backend
            .local_file_path(WorkspaceFileStatRequest {
                path: path.into(),
                cwd: None,
            })
            .await
            .map_err(ToolError::new)
    }

    async fn read_bytes(&self, path: &str) -> Result<Arc<[u8]>, ToolError> {
        self.backend
            .read_bytes(WorkspaceFileReadBytesRequest {
                path: path.into(),
                cwd: None,
                max_bytes: None,
            })
            .await
            .map(Into::into)
            .map_err(ToolError::new)
    }

    async fn archived_file(&self, id: &str) -> Result<domain::File<ResourceReference>, ToolError> {
        match super::archive::archived_file(&self.context, id).await? {
            FileDisplayResult::Ready {
                resource,
                filename,
                modality,
                origin,
            } => Ok(domain::File {
                resource,
                filename,
                modality: match modality {
                    AttachmentModality::Image => domain::Modality::Image,
                    AttachmentModality::Video => domain::Modality::Video,
                    AttachmentModality::File => domain::Modality::File,
                },
                origin: match origin {
                    FileDisplayOrigin::Local { path } => domain::Origin::Local { path },
                    FileDisplayOrigin::Remote => domain::Origin::Remote,
                    FileDisplayOrigin::Archive => domain::Origin::Archive,
                },
            }),
            FileDisplayResult::Failed { message, .. } => Err(failure(&message)),
            FileDisplayResult::Deferred { .. } | FileDisplayResult::NetworkImage { .. } => {
                Err(failure("display item is not an archived resource"))
            }
        }
    }
}

#[derive(Debug)]
pub struct ThreadShowFilesTool<B, H> {
    backend: Arc<B>,
    media: Arc<H>,
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> ThreadShowFilesTool<B, H> {
    pub fn new(backend: Arc<B>, media: Arc<H>) -> Self {
        Self { backend, media }
    }
}

impl<B: WorkspaceFileBackend + 'static, H: ToolMediaHost> TypedTool for ThreadShowFilesTool<B, H> {
    const NAME: &'static str = domain::NAME;
    const DESCRIPTION: &'static str = domain::DESCRIPTION;
    type Args = ShowFilesInput;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    async fn execute(
        &self,
        input: ShowFilesInput,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let backend = match self.backend.for_grant(&context.grant) {
            Some(backend) => Arc::new(backend),
            None => self.backend.clone(),
        };
        let cancellation = context.cancellation.clone();
        let output = domain::ShowFiles::new(Arc::new(DomainMediaHost(self.media.clone())))
            .execute(
                input,
                domain::Context {
                    source: AuthorizedFiles { backend, context },
                    cancellation,
                },
            )
            .await
            .map_err(|error| match error.into_original() {
                Ok(source) => domain_error(source),
                Err(error) => failure(&error.to_string()),
            })?;
        let files: Vec<_> = output
            .files
            .into_iter()
            .map(|result| match result {
                domain::FileResult::Ready(file) => FileDisplayResult::Ready {
                    resource: file.resource,
                    filename: file.filename,
                    modality: match file.modality {
                        domain::Modality::Image => AttachmentModality::Image,
                        domain::Modality::Video => AttachmentModality::Video,
                        domain::Modality::File => AttachmentModality::File,
                    },
                    origin: match file.origin {
                        domain::Origin::Local { path } => FileDisplayOrigin::Local { path },
                        domain::Origin::Remote => FileDisplayOrigin::Remote,
                        domain::Origin::Archive => FileDisplayOrigin::Archive,
                    },
                },
                domain::FileResult::Failed { filename, message } => {
                    FileDisplayResult::Failed { filename, message }
                }
                domain::FileResult::Deferred { filename, target } => {
                    FileDisplayResult::Deferred { filename, target }
                }
                domain::FileResult::NetworkImage { filename, url } => {
                    FileDisplayResult::NetworkImage { filename, url }
                }
            })
            .collect();
        let ready = files
            .iter()
            .filter(|file| matches!(file, FileDisplayResult::Ready { .. }))
            .count();
        let deferred = files
            .iter()
            .filter(|file| matches!(file, FileDisplayResult::Deferred { .. }))
            .count();
        let previews = files
            .iter()
            .filter(|file| matches!(file, FileDisplayResult::NetworkImage { .. }))
            .count();
        let mut model_context = vec![ContextContent::Text {
            text: format!(
                "File display: {ready} archived, {previews} network previews, {deferred} deferred, {} failed.",
                files.len() - ready - deferred - previews
            )
            .into(),
        }];
        for file in &files {
            if let FileDisplayResult::Ready { resource, .. } = file {
                model_context.push(ContextContent::Resource {
                    reference: resource.clone(),
                });
            }
        }
        let data = serde_json::json!({"files": files.iter().map(|file| match file {
            FileDisplayResult::Ready { resource, filename, modality, .. } => serde_json::json!({
                "status": "ready", "filename": filename, "resource": resource, "modality": modality,
            }),
            FileDisplayResult::Failed { filename, message } => serde_json::json!({
                "status": "failed", "filename": filename, "message": message,
            }),
            FileDisplayResult::Deferred { filename, .. } => serde_json::json!({"status": "deferred", "filename": filename}),
            FileDisplayResult::NetworkImage { filename, .. } => serde_json::json!({"status": "networkImage", "filename": filename}),
        }).collect::<Vec<_>>(), "caption": output.caption});
        let details = serde_json::to_value(FileDisplayReceipt {
            caption: output.caption,
            files,
        })
        .map_err(ToolError::new)?;
        Ok(ToolOutput::from_data(data, model_context)
            .with_details(serde_json::json!({"fileDisplay": details})))
    }
}
