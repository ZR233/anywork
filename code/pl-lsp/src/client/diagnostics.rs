use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;

use lsp_types::{DiagnosticSeverity, NumberOrString, PublishDiagnosticsParams};
use tokio::sync::Mutex;

use crate::clock::unix_seconds;
use crate::query::{LspDiagnostic, LspPosition, LspRange};

use super::uri::{file_uri_to_path, normalize_separators, path_to_file_uri};

#[derive(Default)]
struct DiagnosticVisibility {
    // The most specific subtree rule wins. Exact file restorations are exceptions
    // to deleted ancestors, without allowing their still-deleted siblings.
    subtrees: HashMap<PathBuf, bool>,
    restored_files: HashSet<PathBuf>,
}

impl DiagnosticVisibility {
    fn permits(&self, path: &Path) -> bool {
        self.restored_files.contains(path)
            || self
                .subtrees
                .iter()
                .filter(|(root, _)| path.starts_with(root))
                .max_by_key(|(root, _)| root.components().count())
                .is_none_or(|(_, visible)| *visible)
    }

    fn delete(&mut self, path: PathBuf) {
        self.subtrees.retain(|root, _| !root.starts_with(&path));
        self.restored_files.retain(|file| !file.starts_with(&path));
        self.subtrees.insert(path, false);
    }

    fn restore_file(&mut self, path: PathBuf) {
        if !self.permits(&path) {
            self.restored_files.insert(path);
        }
    }

    fn restore_subtree(&mut self, path: PathBuf) {
        self.subtrees.retain(|root, _| !root.starts_with(&path));
        self.restored_files.retain(|file| !file.starts_with(&path));
        if !self.permits(&path) {
            self.subtrees.insert(path, true);
        }
    }
}

/// 诊断收集器，负责接收 LSP 服务器发布的诊断信息并存储。
#[derive(Clone)]
pub(crate) struct DiagnosticSink {
    style: crate::host::LspPathStyle,
    server_id: String,
    workspace_root: PathBuf,
    pub diagnostics: Arc<Mutex<HashMap<String, Vec<LspDiagnostic>>>>,
    visibility: Arc<Mutex<DiagnosticVisibility>>,
    pub updates: tokio::sync::broadcast::Sender<()>,
}

impl DiagnosticSink {
    pub fn new(
        server_id: String,
        workspace_root: PathBuf,
        diagnostics: Arc<Mutex<HashMap<String, Vec<LspDiagnostic>>>>,
        updates: tokio::sync::broadcast::Sender<()>,
        style: crate::host::LspPathStyle,
    ) -> Self {
        Self {
            style,
            server_id,
            workspace_root,
            diagnostics,
            visibility: Arc::new(Mutex::new(DiagnosticVisibility::default())),
            updates,
        }
    }

    pub async fn publish(&self, params: PublishDiagnosticsParams) {
        // Hold this guard through insertion: deletion either clears a completed publish
        // or suppresses it, including unversioned late notifications after didClose.
        let visibility = self.visibility.lock().await;
        let path = file_uri_to_path(params.uri.as_str(), self.style);
        if !visibility.permits(&path) {
            return;
        }
        let received_at = unix_seconds();
        let display_path = path
            .strip_prefix(&self.workspace_root)
            .map(normalize_separators)
            .unwrap_or_else(|_| normalize_separators(&path));
        let diagnostics = params
            .diagnostics
            .iter()
            .map(|diagnostic| LspDiagnostic {
                server_id: self.server_id.clone(),
                uri: params.uri.as_str().to_string(),
                path: display_path.clone(),
                range: LspRange {
                    start: LspPosition {
                        line: diagnostic.range.start.line,
                        character: diagnostic.range.start.character,
                    },
                    end: LspPosition {
                        line: diagnostic.range.end.line,
                        character: diagnostic.range.end.character,
                    },
                },
                severity: diagnostic.severity.map(diagnostic_severity),
                message: diagnostic.message.clone(),
                source: diagnostic.source.clone(),
                code: diagnostic.code.clone().map(number_or_string),
                received_at,
            })
            .collect::<Vec<_>>();
        let server_id = &self.server_id;
        let uri_str = params.uri.as_str();
        self.diagnostics
            .lock()
            .await
            .insert(format!("{server_id}:{uri_str}"), diagnostics);
        let _ = self.updates.send(());
    }

    pub(super) async fn delete_path(&self, path: &Path) {
        let path = file_uri_to_path(&path_to_file_uri(path, self.style), self.style);
        let mut visibility = self.visibility.lock().await;
        visibility.delete(path.clone());
        let prefix = format!("{}:", self.server_id);
        self.diagnostics.lock().await.retain(|key, _| {
            let Some(uri) = key.strip_prefix(&prefix) else {
                return true;
            };
            !file_uri_to_path(uri, self.style).starts_with(&path)
        });
        let _ = self.updates.send(());
    }

    pub(super) async fn restore_file(&self, path: &Path) {
        let path = file_uri_to_path(&path_to_file_uri(path, self.style), self.style);
        self.visibility.lock().await.restore_file(path);
    }

    pub(super) async fn restore_subtree(&self, path: &Path) {
        let path = file_uri_to_path(&path_to_file_uri(path, self.style), self.style);
        self.visibility.lock().await.restore_subtree(path);
    }
}

/// 将 LSP 诊断 severity 映射为数值。
fn diagnostic_severity(severity: DiagnosticSeverity) -> u32 {
    match severity {
        DiagnosticSeverity::ERROR => 1,
        DiagnosticSeverity::WARNING => 2,
        DiagnosticSeverity::INFORMATION => 3,
        DiagnosticSeverity::HINT => 4,
        _ => 0,
    }
}

/// 将 `NumberOrString` 转换为字符串。
fn number_or_string(nos: NumberOrString) -> String {
    match nos {
        NumberOrString::Number(n) => n.to_string(),
        NumberOrString::String(s) => s,
    }
}
