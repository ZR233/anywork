use std::path::Path;
use std::sync::atomic::Ordering;

use lsp_types::{
    DidChangeTextDocumentParams, DidCloseTextDocumentParams, DidOpenTextDocumentParams,
    FileChangeType, Position, Range, TextDocumentContentChangeEvent, TextDocumentIdentifier,
    TextDocumentItem, TextDocumentSyncCapability, TextDocumentSyncKind, Uri,
    VersionedTextDocumentIdentifier,
};

use super::configuration::watched_file_event_params;
use super::connection::LspClient;
use super::uri::parse_uri;
use crate::runtime::{LspResult, LspRuntimeError};

const MAX_FILE_SIZE_BYTES: u64 = 10_000_000;

#[derive(Debug, Clone, Copy)]
pub(super) struct DocumentSync {
    open_close: bool,
    change: TextDocumentSyncKind,
}

impl Default for DocumentSync {
    fn default() -> Self {
        Self {
            open_close: false,
            change: TextDocumentSyncKind::NONE,
        }
    }
}

impl DocumentSync {
    pub(super) fn from_capability(capability: Option<&TextDocumentSyncCapability>) -> Self {
        match capability {
            Some(TextDocumentSyncCapability::Kind(change)) => Self {
                open_close: *change != TextDocumentSyncKind::NONE,
                change: *change,
            },
            Some(TextDocumentSyncCapability::Options(options)) => Self {
                open_close: options.open_close.unwrap_or(false),
                change: options.change.unwrap_or(TextDocumentSyncKind::NONE),
            },
            None => Self::default(),
        }
    }
}

#[derive(Debug, Clone)]
pub(super) struct OpenDocument {
    uri: Uri,
    version: i32,
    content: String,
}

impl LspClient {
    pub(crate) async fn open_document(&self, path: &Path, uri: &str) -> LspResult<()> {
        let _sync = self.document_sync.lock().await;
        self.synchronize_document_locked(path, Some(uri)).await
    }

    async fn synchronize_document_locked(&self, path: &Path, uri: Option<&str>) -> LspResult<()> {
        let mut documents = self.opened_files.lock().await;
        if uri.is_none() && !documents.contains_key(path) {
            return Ok(());
        }
        // Reading and publishing share the same order, so an older disk read cannot
        // overwrite a newer version. Hold the cache guard until the queued write is recorded.
        let content = self.read_document(path).await?;
        let sync = *self.negotiated_document_sync.read().map_err(|_| {
            LspRuntimeError::Unavailable("LSP document sync state is poisoned".into())
        })?;
        if let Some(document) = documents.get_mut(path) {
            self.diagnostics.restore_file(path).await;
            if document.content == content {
                return Ok(());
            }
            if sync.change != TextDocumentSyncKind::NONE {
                let next_version = document.version + 1;
                self.notify(
                    "textDocument/didChange",
                    document_change(document, next_version, &content, sync.change),
                )
                .await?;
                document.version = next_version;
            }
            document.content = content;
        } else if let Some(uri) = uri {
            let language_id = self.server.language_for_path(path).unwrap_or("text");
            let uri = parse_uri(uri)?;
            self.diagnostics.restore_file(path).await;
            if sync.open_close {
                self.notify(
                    "textDocument/didOpen",
                    DidOpenTextDocumentParams {
                        text_document: TextDocumentItem {
                            uri: uri.clone(),
                            language_id: language_id.to_string(),
                            version: 1,
                            text: content.clone(),
                        },
                    },
                )
                .await?;
            }
            documents.insert(
                path.to_path_buf(),
                OpenDocument {
                    uri,
                    version: 1,
                    content,
                },
            );
        }
        Ok(())
    }

    async fn close_document_locked(&self, path: &Path) -> LspResult<()> {
        let mut documents = self.opened_files.lock().await;
        let document = documents.get(path);
        if let Some(document) = document {
            let open_close = self
                .negotiated_document_sync
                .read()
                .map_err(|_| {
                    LspRuntimeError::Unavailable("LSP document sync state is poisoned".into())
                })?
                .open_close;
            if open_close {
                self.notify(
                    "textDocument/didClose",
                    DidCloseTextDocumentParams {
                        text_document: TextDocumentIdentifier {
                            uri: document.uri.clone(),
                        },
                    },
                )
                .await?;
            }
            documents.remove(path);
        }
        Ok(())
    }

    pub(crate) async fn refresh_document(&self, path: &Path) -> LspResult<()> {
        let _sync = self.document_sync.lock().await;
        let paths = self
            .opened_files
            .lock()
            .await
            .keys()
            .filter(|opened| opened.starts_with(path))
            .cloned()
            .collect::<Vec<_>>();
        let mut failure = None;
        for path in paths {
            let result = async {
                let is_file = if let Some(host) = &self.host {
                    host.stat(&path)
                        .await
                        .map_err(|error| LspRuntimeError::Unavailable(error.to_string()))?
                        .is_some_and(|stat| stat.is_file)
                } else {
                    match tokio::fs::metadata(&path).await {
                        Ok(metadata) => metadata.is_file(),
                        Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
                        Err(error) => return Err(error.into()),
                    }
                };
                if is_file {
                    self.synchronize_document_locked(&path, None).await
                } else {
                    self.diagnostics.delete_path(&path).await;
                    self.close_document_locked(&path).await
                }
            }
            .await;
            if let Err(error) = result {
                failure.get_or_insert(error);
            }
        }
        failure.map_or(Ok(()), Err)
    }

    pub(crate) async fn file_changed(&self, path: &Path) -> LspResult<()> {
        let _sync = self.document_sync.lock().await;
        let is_file = if let Some(host) = &self.host {
            host.stat(path)
                .await
                .map_err(|error| LspRuntimeError::Unavailable(error.to_string()))?
                .ok_or_else(|| {
                    LspRuntimeError::Unavailable(format!(
                        "LSP changed path does not exist: {}",
                        path.display()
                    ))
                })?
                .is_file
        } else {
            tokio::fs::metadata(path).await?.is_file()
        };
        if is_file {
            self.diagnostics.restore_file(path).await;
        } else {
            self.diagnostics.restore_subtree(path).await;
        }
        self.notify_watched_file_event(path, FileChangeType::CHANGED)
            .await
    }

    pub(crate) async fn file_deleted(&self, path: &Path) -> LspResult<()> {
        let _sync = self.document_sync.lock().await;
        self.diagnostics.delete_path(path).await;
        let documents = self
            .opened_files
            .lock()
            .await
            .keys()
            .filter(|opened| opened.starts_with(path))
            .cloned()
            .collect::<Vec<_>>();
        let mut failure = None;
        for path in documents {
            if let Err(error) = self.close_document_locked(&path).await {
                failure.get_or_insert(error);
            }
        }
        if let Err(error) = self
            .notify_watched_file_event(path, FileChangeType::DELETED)
            .await
        {
            failure.get_or_insert(error);
        }
        failure.map_or(Ok(()), Err)
    }

    async fn notify_watched_file_event(&self, path: &Path, typ: FileChangeType) -> LspResult<()> {
        if !self.initialized.load(Ordering::Relaxed) {
            return Ok(());
        }
        self.notify(
            "workspace/didChangeWatchedFiles",
            watched_file_event_params(path, typ, self.path_style())?,
        )
        .await
    }

    async fn read_document(&self, path: &Path) -> LspResult<String> {
        if let Some(host) = &self.host {
            let stat = host
                .stat(path)
                .await
                .map_err(|error| LspRuntimeError::Unavailable(error.to_string()))?
                .ok_or_else(|| {
                    LspRuntimeError::Unavailable(format!(
                        "LSP document does not exist: {}",
                        path.display()
                    ))
                })?;
            if !stat.is_file {
                return Err(LspRuntimeError::Unavailable(format!(
                    "LSP document is not a file: {}",
                    path.display()
                )));
            }
            if stat.byte_size > MAX_FILE_SIZE_BYTES {
                return Err(document_too_large(path));
            }
            let bytes = host
                .read_file(path, MAX_FILE_SIZE_BYTES)
                .await
                .map_err(|error| LspRuntimeError::Unavailable(error.to_string()))?;
            let content = String::from_utf8(bytes).map_err(|error| {
                LspRuntimeError::Unavailable(format!(
                    "LSP document is not UTF-8 ({}): {error}",
                    path.display()
                ))
            })?;
            Ok(content)
        } else {
            if tokio::fs::metadata(path).await?.len() > MAX_FILE_SIZE_BYTES {
                return Err(document_too_large(path));
            }
            let content = tokio::fs::read_to_string(path).await?;
            if content.len() as u64 > MAX_FILE_SIZE_BYTES {
                return Err(document_too_large(path));
            }
            Ok(content)
        }
    }
}

fn document_too_large(path: &Path) -> LspRuntimeError {
    LspRuntimeError::Unavailable(format!(
        "LSP document exceeds the existing {MAX_FILE_SIZE_BYTES}-byte sync limit: {}",
        path.display()
    ))
}

fn document_change(
    document: &OpenDocument,
    version: i32,
    content: &str,
    change: TextDocumentSyncKind,
) -> DidChangeTextDocumentParams {
    DidChangeTextDocumentParams {
        text_document: VersionedTextDocumentIdentifier {
            uri: document.uri.clone(),
            version,
        },
        content_changes: vec![TextDocumentContentChangeEvent {
            range: (change == TextDocumentSyncKind::INCREMENTAL).then(|| Range {
                start: Position::new(0, 0),
                end: document_end(&document.content),
            }),
            range_length: None,
            text: content.to_string(),
        }],
    }
}

fn document_end(content: &str) -> Position {
    let mut end = Position::new(0, 0);
    let mut chars = content.chars().peekable();
    while let Some(character) = chars.next() {
        match character {
            '\r' => {
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
                end.line += 1;
                end.character = 0;
            }
            '\n' => {
                end.line += 1;
                end.character = 0;
            }
            character => end.character += character.len_utf16() as u32,
        }
    }
    end
}
