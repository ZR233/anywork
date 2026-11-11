//! 按环境作用域（`Host` / `Ssh`）组织的单文件 MCP 配置目录资源、合并规则与 CRUD 原子提交。

use std::collections::{BTreeMap, BTreeSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use pl_protocol::{
    CreateMcpDocumentRequest, DeleteMcpDocumentRequest, McpCatalogEntry, McpCatalogSnapshot,
    McpConfigStatusKind, McpDocumentCommitReceipt, McpDocumentContent, McpDocumentDiagnostic,
    McpDocumentRef, McpEffectiveSource, McpExecutionLocation, McpScope, PureError, Result,
    UpdateMcpDocumentRequest,
};
use pl_tool::mcp::config::{
    EffectiveMcpServerConfig, McpExecutionContext, McpServerMutationPolicy, McpServerSourceKind,
    McpServerStatusKind, McpServerTransport, validate_mcp_identifier,
};
use pl_tool::remote::RemoteCommandBackend;
use sha2::{Digest, Sha256};
use tokio::sync::watch;

use super::ConfigPaths;
use super::mcp::build_builtin_effective_config;
use super::mcp_document::{McpFileSpecV1, McpFileV1};

pub const MAX_MCP_DOCUMENT_BYTES: usize = 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum McpDocumentError {
    NotFound(String),
    Conflict(String),
    ValidationFailed(String),
    Io(String),
}

impl std::fmt::Display for McpDocumentError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotFound(msg)
            | Self::Conflict(msg)
            | Self::ValidationFailed(msg)
            | Self::Io(msg) => formatter.write_str(msg),
        }
    }
}

impl std::error::Error for McpDocumentError {}

impl From<PureError> for McpDocumentError {
    fn from(error: PureError) -> Self {
        match error {
            PureError::ConfigError(msg) => Self::ValidationFailed(msg),
            PureError::Io(err) => Self::Io(err.to_string()),
            other => Self::ValidationFailed(other.to_string()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScopedEffectiveMcpServer {
    pub id: String,
    pub document: McpDocumentRef,
    pub config_status: McpConfigStatusKind,
    pub effective_source: McpEffectiveSource,
    pub execution_location: McpExecutionLocation,
    pub built_in: bool,
    pub server: EffectiveMcpServerConfig,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedThreadMcpServer {
    pub id: String,
    pub effective_source: McpEffectiveSource,
    pub execution_location: McpExecutionLocation,
    pub built_in: bool,
    pub server: EffectiveMcpServerConfig,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScopedMcpScan {
    pub entries: Vec<McpCatalogEntry>,
    pub diagnostics: Vec<McpDocumentDiagnostic>,
    pub effective_servers: BTreeMap<String, ScopedEffectiveMcpServer>,
    pub document_revisions: BTreeMap<String, u64>,
}

struct ScopeResourceState {
    revision: u64,
    scan: ScopedMcpScan,
    updates: Arc<watch::Sender<u64>>,
}

#[derive(Clone, Default)]
pub struct McpCatalogResource {
    scopes: Arc<Mutex<BTreeMap<McpScope, ScopeResourceState>>>,
    write_lock: Arc<Mutex<()>>,
}

impl McpCatalogResource {
    pub fn new(paths: &ConfigPaths, models: &pl_model::config::AgentModelConfig) -> Self {
        let resource = Self::default();
        let _ = resource.adopt_scan(paths, models, &McpScope::Host);
        resource
    }

    pub fn read_catalog(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        scope: &McpScope,
    ) -> Result<McpCatalogSnapshot> {
        let mut guard = self
            .scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(state) = guard.get(scope) {
            return Ok(McpCatalogSnapshot {
                scope: scope.clone(),
                revision: state.revision,
                entries: state.scan.entries.clone(),
                diagnostics: state.scan.diagnostics.clone(),
            });
        }
        let scan = scan_scope_catalog(paths, models, scope)?;
        let (tx, _) = watch::channel(1);
        let snapshot = McpCatalogSnapshot {
            scope: scope.clone(),
            revision: 1,
            entries: scan.entries.clone(),
            diagnostics: scan.diagnostics.clone(),
        };
        guard.insert(
            scope.clone(),
            ScopeResourceState {
                revision: 1,
                scan,
                updates: Arc::new(tx),
            },
        );
        Ok(snapshot)
    }

    pub fn subscribe(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        scope: &McpScope,
    ) -> Result<(McpCatalogSnapshot, watch::Receiver<u64>)> {
        let mut guard = self
            .scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !guard.contains_key(scope) {
            let scan = scan_scope_catalog(paths, models, scope)?;
            let (tx, _) = watch::channel(1);
            guard.insert(
                scope.clone(),
                ScopeResourceState {
                    revision: 1,
                    scan,
                    updates: Arc::new(tx),
                },
            );
        }
        let state = guard.get(scope).expect("inserted scope state");
        let snapshot = McpCatalogSnapshot {
            scope: scope.clone(),
            revision: state.revision,
            entries: state.scan.entries.clone(),
            diagnostics: state.scan.diagnostics.clone(),
        };
        let rx = state.updates.subscribe();
        Ok((snapshot, rx))
    }

    /// Re-scans `scope` and returns `(snapshot, changed)`.
    pub fn adopt_scan(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        scope: &McpScope,
    ) -> Result<(McpCatalogSnapshot, bool)> {
        let scan = scan_scope_catalog(paths, models, scope)?;
        let mut guard = self
            .scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(state) = guard.get_mut(scope) {
            let changed = state.scan != scan;
            if changed {
                state.revision = state.revision.saturating_add(1);
                state.scan = scan;
            }
            let snapshot = McpCatalogSnapshot {
                scope: scope.clone(),
                revision: state.revision,
                entries: state.scan.entries.clone(),
                diagnostics: state.scan.diagnostics.clone(),
            };
            let updates = state.updates.clone();
            let rev = state.revision;
            drop(guard);
            if changed {
                updates.send_replace(rev);
            }
            Ok((snapshot, changed))
        } else {
            let (tx, _) = watch::channel(1);
            let snapshot = McpCatalogSnapshot {
                scope: scope.clone(),
                revision: 1,
                entries: scan.entries.clone(),
                diagnostics: scan.diagnostics.clone(),
            };
            guard.insert(
                scope.clone(),
                ScopeResourceState {
                    revision: 1,
                    scan,
                    updates: Arc::new(tx),
                },
            );
            Ok((snapshot, true))
        }
    }

    /// Re-scans `Host` and all currently tracked scopes (plus any provided scopes), returning all scopes whose scan changed.
    pub fn refresh_all_scopes(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        extra_scopes: &[McpScope],
    ) -> Vec<McpScope> {
        let mut scopes: BTreeSet<McpScope> = {
            let guard = self
                .scopes
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            guard.keys().cloned().collect()
        };
        scopes.insert(McpScope::Host);
        for extra in extra_scopes {
            scopes.insert(extra.clone());
        }
        let mut changed_scopes = Vec::new();
        for scope in scopes {
            if let Ok((_snapshot, changed)) = self.adopt_scan(paths, models, &scope)
                && changed
            {
                changed_scopes.push(scope);
            }
        }
        changed_scopes
    }

    pub fn effective_servers_for_scope(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        scope: &McpScope,
    ) -> Result<BTreeMap<String, ScopedEffectiveMcpServer>> {
        let _ = self.read_catalog(paths, models, scope)?;
        let guard = self
            .scopes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        Ok(guard
            .get(scope)
            .map(|state| state.scan.effective_servers.clone())
            .unwrap_or_default())
    }

    pub fn resolve_thread_mcp_configs(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        scope: &McpScope,
        workspace_root: &Path,
        host_base_cwd: &Path,
        remote_commands: Option<Arc<RemoteCommandBackend>>,
    ) -> Result<BTreeMap<String, ResolvedThreadMcpServer>> {
        let scoped = self.effective_servers_for_scope(paths, models, scope)?;
        resolve_scoped_servers_for_thread(
            scoped,
            scope,
            workspace_root,
            host_base_cwd,
            remote_commands,
        )
    }

    pub fn read_document(
        &self,
        paths: &ConfigPaths,
        document: &McpDocumentRef,
    ) -> std::result::Result<McpDocumentContent, McpDocumentError> {
        let path = resolve_document_path(paths, document)?;
        let meta = match fs::symlink_metadata(&path) {
            Ok(meta) => meta,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Err(McpDocumentError::NotFound(format!(
                    "MCP document '{}' does not exist",
                    document.relative_path
                )));
            }
            Err(error) => return Err(McpDocumentError::Io(error.to_string())),
        };
        if meta.file_type().is_symlink() {
            return Err(McpDocumentError::ValidationFailed(format!(
                "MCP document '{}' must not be a symlink",
                document.relative_path
            )));
        }
        if !meta.is_file() {
            return Err(McpDocumentError::ValidationFailed(format!(
                "MCP document '{}' is not a regular file",
                document.relative_path
            )));
        }
        if meta.len() > MAX_MCP_DOCUMENT_BYTES as u64 {
            return Err(McpDocumentError::ValidationFailed(format!(
                "MCP document '{}' exceeds 1 MiB limit",
                document.relative_path
            )));
        }
        let bytes = fs::read(&path).map_err(|error| McpDocumentError::Io(error.to_string()))?;
        if bytes.len() > MAX_MCP_DOCUMENT_BYTES {
            return Err(McpDocumentError::ValidationFailed(format!(
                "MCP document '{}' exceeds 1 MiB limit",
                document.relative_path
            )));
        }
        let raw_toml = String::from_utf8(bytes.clone()).map_err(|error| {
            McpDocumentError::ValidationFailed(format!(
                "MCP document '{}' is not valid UTF-8: {error}",
                document.relative_path
            ))
        })?;
        let revision = document_revision(&document.relative_path, &bytes);
        let (id, diagnostic) = match McpFileV1::parse_and_validate(&raw_toml, &document.scope) {
            Ok(parsed) => {
                let filename = path
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or_default();
                let diag = if matches!(document.scope, McpScope::Ssh { .. }) {
                    let expected = canonical_mcp_filename(&parsed.id)?;
                    if filename != expected {
                        Some(McpDocumentDiagnostic {
                            document: document.clone(),
                            id: Some(parsed.id.clone()),
                            code: "file_identity_mismatch".to_owned(),
                            message: format!(
                                "SSH MCP filename '{filename}' does not match canonical filename '{expected}' for id '{}'",
                                parsed.id
                            ),
                        })
                    } else {
                        None
                    }
                } else {
                    None
                };
                (Some(parsed.id), diag)
            }
            Err(error) => {
                let peeked_id = McpFileV1::peek_id(&raw_toml);
                (
                    peeked_id.clone(),
                    Some(McpDocumentDiagnostic {
                        document: document.clone(),
                        id: peeked_id,
                        code: "invalid_document".to_owned(),
                        message: error.to_string(),
                    }),
                )
            }
        };
        Ok(McpDocumentContent {
            document: document.clone(),
            id,
            revision,
            raw_toml,
            diagnostic,
        })
    }

    pub fn create_document(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        request: &CreateMcpDocumentRequest,
    ) -> std::result::Result<(McpDocumentCommitReceipt, Vec<McpScope>), McpDocumentError> {
        let _write_guard = self
            .write_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if request.raw_toml.len() > MAX_MCP_DOCUMENT_BYTES {
            return Err(McpDocumentError::ValidationFailed(
                "MCP document exceeds 1 MiB limit".to_owned(),
            ));
        }
        validate_mcp_identifier(&request.id, "MCP server id")?;
        let parsed = McpFileV1::parse_and_validate(&request.raw_toml, &request.scope)?;
        if parsed.id != request.id {
            return Err(McpDocumentError::ValidationFailed(format!(
                "MCP document id '{}' does not match requested id '{}'",
                parsed.id, request.id
            )));
        }
        let doc_ref = canonical_document_ref(&request.scope, &request.id)?;
        let target_path = resolve_document_path(paths, &doc_ref)?;
        if fs::symlink_metadata(&target_path).is_ok() {
            return Err(McpDocumentError::Conflict(format!(
                "MCP document '{}' already exists",
                doc_ref.relative_path
            )));
        }
        if matches!(request.scope, McpScope::Host)
            && host_id_exists_in_other_file(paths, &request.id, &target_path)?
        {
            return Err(McpDocumentError::Conflict(format!(
                "Host MCP server id '{}' is already defined by another file",
                request.id
            )));
        }

        let canonical_bytes = request.raw_toml.as_bytes();
        write_file_atomic(&target_path, canonical_bytes)
            .map_err(|error| McpDocumentError::Io(error.to_string()))?;
        let doc_rev = document_revision(&doc_ref.relative_path, canonical_bytes);
        let (snapshot, _) = self.adopt_scan(paths, models, &request.scope)?;
        let mut changed_scopes = vec![request.scope.clone()];
        if matches!(request.scope, McpScope::Host) {
            for changed in self.refresh_all_scopes(paths, models, &[]) {
                if !changed_scopes.contains(&changed) {
                    changed_scopes.push(changed);
                }
            }
        }
        Ok((
            McpDocumentCommitReceipt {
                document: Some(doc_ref),
                revision: doc_rev,
                snapshot,
            },
            changed_scopes,
        ))
    }

    pub fn update_document(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        request: &UpdateMcpDocumentRequest,
    ) -> std::result::Result<(McpDocumentCommitReceipt, Vec<McpScope>), McpDocumentError> {
        let _write_guard = self
            .write_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if request.raw_toml.len() > MAX_MCP_DOCUMENT_BYTES {
            return Err(McpDocumentError::ValidationFailed(
                "MCP document exceeds 1 MiB limit".to_owned(),
            ));
        }
        let target_path = resolve_document_path(paths, &request.document)?;
        let meta = match fs::symlink_metadata(&target_path) {
            Ok(meta) => meta,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Err(McpDocumentError::NotFound(format!(
                    "MCP document '{}' does not exist",
                    request.document.relative_path
                )));
            }
            Err(error) => return Err(McpDocumentError::Io(error.to_string())),
        };
        if meta.file_type().is_symlink() {
            return Err(McpDocumentError::ValidationFailed(format!(
                "MCP document '{}' must not be a symlink",
                request.document.relative_path
            )));
        }
        let current_bytes =
            fs::read(&target_path).map_err(|error| McpDocumentError::Io(error.to_string()))?;
        let actual_revision = document_revision(&request.document.relative_path, &current_bytes);
        if actual_revision != request.expected_revision {
            return Err(McpDocumentError::Conflict(format!(
                "MCP document '{}' revision conflict: expected {}, actual {actual_revision}",
                request.document.relative_path, request.expected_revision
            )));
        }

        let parsed = McpFileV1::parse_and_validate(&request.raw_toml, &request.document.scope)?;
        let filename = target_path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default();
        match &request.document.scope {
            McpScope::Ssh { .. } => {
                let expected_filename = canonical_mcp_filename(&parsed.id)?;
                if filename != expected_filename {
                    return Err(McpDocumentError::ValidationFailed(format!(
                        "SSH MCP document '{}' cannot change id to '{}' (expected filename '{expected_filename}')",
                        request.document.relative_path, parsed.id
                    )));
                }
            }
            McpScope::Host => {
                if let Ok(current_str) = std::str::from_utf8(&current_bytes)
                    && let Ok(existing_doc) =
                        McpFileV1::parse_and_validate(current_str, &McpScope::Host)
                    && existing_doc.id != parsed.id
                {
                    return Err(McpDocumentError::ValidationFailed(format!(
                        "MCP document '{}' cannot change server id from '{}' to '{}'",
                        request.document.relative_path, existing_doc.id, parsed.id
                    )));
                }
                if host_id_exists_in_other_file(paths, &parsed.id, &target_path)? {
                    return Err(McpDocumentError::Conflict(format!(
                        "Host MCP server id '{}' is already defined by another file",
                        parsed.id
                    )));
                }
            }
        }

        let canonical_bytes = request.raw_toml.as_bytes();
        write_file_atomic(&target_path, canonical_bytes)
            .map_err(|error| McpDocumentError::Io(error.to_string()))?;
        let doc_rev = document_revision(&request.document.relative_path, canonical_bytes);
        let (snapshot, _) = self.adopt_scan(paths, models, &request.document.scope)?;
        let mut changed_scopes = vec![request.document.scope.clone()];
        if matches!(request.document.scope, McpScope::Host) {
            for changed in self.refresh_all_scopes(paths, models, &[]) {
                if !changed_scopes.contains(&changed) {
                    changed_scopes.push(changed);
                }
            }
        }
        Ok((
            McpDocumentCommitReceipt {
                document: Some(request.document.clone()),
                revision: doc_rev,
                snapshot,
            },
            changed_scopes,
        ))
    }

    pub fn delete_document(
        &self,
        paths: &ConfigPaths,
        models: &pl_model::config::AgentModelConfig,
        request: &DeleteMcpDocumentRequest,
    ) -> std::result::Result<(McpDocumentCommitReceipt, Vec<McpScope>), McpDocumentError> {
        let _write_guard = self
            .write_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let target_path = resolve_document_path(paths, &request.document)?;
        let meta = match fs::symlink_metadata(&target_path) {
            Ok(meta) => meta,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Err(McpDocumentError::NotFound(format!(
                    "MCP document '{}' does not exist",
                    request.document.relative_path
                )));
            }
            Err(error) => return Err(McpDocumentError::Io(error.to_string())),
        };
        if !meta.file_type().is_symlink() {
            let current_bytes =
                fs::read(&target_path).map_err(|error| McpDocumentError::Io(error.to_string()))?;
            let actual_revision =
                document_revision(&request.document.relative_path, &current_bytes);
            if actual_revision != request.expected_revision {
                return Err(McpDocumentError::Conflict(format!(
                    "MCP document '{}' revision conflict: expected {}, actual {actual_revision}",
                    request.document.relative_path, request.expected_revision
                )));
            }
        }

        fs::remove_file(&target_path).map_err(|error| McpDocumentError::Io(error.to_string()))?;
        let (snapshot, _) = self.adopt_scan(paths, models, &request.document.scope)?;
        let mut changed_scopes = vec![request.document.scope.clone()];
        if matches!(request.document.scope, McpScope::Host) {
            for changed in self.refresh_all_scopes(paths, models, &[]) {
                if !changed_scopes.contains(&changed) {
                    changed_scopes.push(changed);
                }
            }
        }
        Ok((
            McpDocumentCommitReceipt {
                document: None,
                revision: snapshot.revision,
                snapshot,
            },
            changed_scopes,
        ))
    }
}

pub fn canonical_mcp_filename(id: &str) -> Result<String> {
    validate_mcp_identifier(id, "MCP server id")?;
    let key = crate::studio::paths::storage_key(id, "MCP server")
        .map_err(|error| PureError::ConfigError(error.to_string()))?;
    Ok(format!("{key}.toml"))
}

pub fn canonical_document_ref(scope: &McpScope, id: &str) -> Result<McpDocumentRef> {
    let filename = canonical_mcp_filename(id)?;
    let relative_path = match scope {
        McpScope::Host => format!("mcp/host/{filename}"),
        McpScope::Ssh { ssh_alias } => {
            let ssh_key = crate::studio::paths::storage_key(ssh_alias, "SSH server")
                .map_err(|error| PureError::ConfigError(error.to_string()))?;
            format!("mcp/ssh/{ssh_key}/{filename}")
        }
    };
    Ok(McpDocumentRef {
        scope: scope.clone(),
        relative_path,
    })
}

pub fn scope_dir(paths: &ConfigPaths, scope: &McpScope) -> Result<PathBuf> {
    match scope {
        McpScope::Host => Ok(paths.mcp_host_dir()),
        McpScope::Ssh { ssh_alias } => {
            if ssh_alias.trim().is_empty() {
                return Err(PureError::ConfigError(
                    "SSH alias must not be empty".to_owned(),
                ));
            }
            paths.mcp_ssh_dir(ssh_alias)
        }
    }
}

pub fn resolve_document_path(
    paths: &ConfigPaths,
    document: &McpDocumentRef,
) -> std::result::Result<PathBuf, McpDocumentError> {
    let expected_prefix = match &document.scope {
        McpScope::Host => "mcp/host/".to_owned(),
        McpScope::Ssh { ssh_alias } => {
            if ssh_alias.trim().is_empty() {
                return Err(McpDocumentError::ValidationFailed(
                    "SSH alias must not be empty".to_owned(),
                ));
            }
            let ssh_key = crate::studio::paths::storage_key(ssh_alias, "SSH server")
                .map_err(|error| McpDocumentError::ValidationFailed(error.to_string()))?;
            format!("mcp/ssh/{ssh_key}/")
        }
    };
    let Some(filename) = document.relative_path.strip_prefix(&expected_prefix) else {
        return Err(McpDocumentError::ValidationFailed(format!(
            "MCP document path '{}' does not belong to scope {:?}",
            document.relative_path, document.scope
        )));
    };
    if filename.is_empty()
        || filename.contains('/')
        || filename.contains('\\')
        || !filename.ends_with(".toml")
        || Path::new(filename)
            .components()
            .any(|c| !matches!(c, Component::Normal(_)))
    {
        return Err(McpDocumentError::ValidationFailed(format!(
            "invalid MCP document filename '{filename}'"
        )));
    }
    Ok(paths.config_dir().join(&document.relative_path))
}

pub fn document_revision(relative_path: &str, bytes: &[u8]) -> u64 {
    let mut hasher = Sha256::new();
    hasher.update(relative_path.as_bytes());
    hasher.update([0]);
    hasher.update(bytes);
    let digest = hasher.finalize();
    let mut raw = [0u8; 8];
    raw.copy_from_slice(&digest[..8]);
    u64::from_be_bytes(raw).max(1)
}

/// Initializes the 4 built-in Zhipu MCP files under `<StudioHome>/mcp/host/` once on a fresh installation
/// where neither `config.toml` nor `mcp/host` exists yet.
pub fn ensure_default_host_builtins_if_fresh(paths: &ConfigPaths) -> Result<()> {
    if paths.config_file().exists() || paths.mcp_host_dir().exists() {
        return Ok(());
    }
    let host_dir = paths.mcp_host_dir();
    fs::create_dir_all(&host_dir)?;
    for doc in McpFileV1::default_host_builtins() {
        let filename = canonical_mcp_filename(&doc.id)?;
        let target = host_dir.join(filename);
        let encoded = doc.encode()?;
        write_file_atomic(&target, encoded.as_bytes())?;
    }
    Ok(())
}

pub fn scan_scope_catalog(
    paths: &ConfigPaths,
    models: &pl_model::config::AgentModelConfig,
    scope: &McpScope,
) -> Result<ScopedMcpScan> {
    let host_scan = match scan_host_directory(paths, models) {
        Ok(scan) => scan,
        Err(error) => HostScanInternal {
            valid_docs: BTreeMap::new(),
            entries: Vec::new(),
            diagnostics: vec![McpDocumentDiagnostic {
                document: McpDocumentRef {
                    scope: McpScope::Host,
                    relative_path: "mcp/host".to_owned(),
                },
                id: None,
                code: "scope_read_error".to_owned(),
                message: format!("failed to read Host MCP directory: {error}"),
            }],
            effective_servers: BTreeMap::new(),
            document_revisions: BTreeMap::new(),
        },
    };
    match scope {
        McpScope::Host => Ok(host_scan.into_scoped_scan()),
        McpScope::Ssh { ssh_alias } => {
            if ssh_alias.trim().is_empty() {
                return Err(PureError::ConfigError(
                    "SSH alias must not be empty".to_owned(),
                ));
            }
            scan_ssh_directory_with_host(paths, models, ssh_alias, &host_scan)
        }
    }
}

struct HostScanInternal {
    valid_docs: BTreeMap<String, (McpDocumentRef, McpFileV1)>,
    entries: Vec<McpCatalogEntry>,
    diagnostics: Vec<McpDocumentDiagnostic>,
    effective_servers: BTreeMap<String, ScopedEffectiveMcpServer>,
    document_revisions: BTreeMap<String, u64>,
}

impl HostScanInternal {
    fn into_scoped_scan(self) -> ScopedMcpScan {
        ScopedMcpScan {
            entries: self.entries,
            diagnostics: self.diagnostics,
            effective_servers: self.effective_servers,
            document_revisions: self.document_revisions,
        }
    }
}

fn is_ignored_temp_or_backup_name(name: &str) -> bool {
    name.starts_with('.') || name.ends_with(".bak") || name.ends_with(".tmp") || name.ends_with('~')
}

fn scan_host_directory(
    paths: &ConfigPaths,
    models: &pl_model::config::AgentModelConfig,
) -> Result<HostScanInternal> {
    let host_dir = paths.mcp_host_dir();
    match fs::symlink_metadata(&host_dir) {
        Ok(meta) => {
            if meta.file_type().is_symlink() {
                return Err(PureError::ConfigError(
                    "Host MCP directory must not be a symlink".to_owned(),
                ));
            }
            if !meta.is_dir() {
                return Err(PureError::ConfigError(
                    "Host MCP path is not a directory".to_owned(),
                ));
            }
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(HostScanInternal {
                valid_docs: BTreeMap::new(),
                entries: Vec::new(),
                diagnostics: Vec::new(),
                effective_servers: BTreeMap::new(),
                document_revisions: BTreeMap::new(),
            });
        }
        Err(error) => return Err(PureError::from(error)),
    }

    let dir_entries = fs::read_dir(&host_dir).map_err(PureError::from)?;

    let mut file_names = Vec::new();
    for entry in dir_entries {
        let entry = entry.map_err(PureError::from)?;
        let path = entry.path();
        if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
            if is_ignored_temp_or_backup_name(name) {
                continue;
            }
            if path.extension().and_then(|ext| ext.to_str()) == Some("toml") {
                file_names.push((name.to_owned(), path));
            }
        }
    }
    file_names.sort_by(|a, b| a.0.cmp(&b.0));

    let mut parsed_by_id: BTreeMap<String, Vec<(McpDocumentRef, McpFileV1)>> = BTreeMap::new();
    let mut diagnostics = Vec::new();
    let mut invalid_entries = Vec::new();
    let mut document_revisions = BTreeMap::new();

    for (file_name, path) in file_names {
        let doc_ref = McpDocumentRef {
            scope: McpScope::Host,
            relative_path: format!("mcp/host/{file_name}"),
        };
        let meta = match fs::symlink_metadata(&path) {
            Ok(meta) => meta,
            Err(error) => {
                let message = format!("failed to inspect MCP file '{file_name}': {error}");
                diagnostics.push(McpDocumentDiagnostic {
                    document: doc_ref.clone(),
                    id: None,
                    code: "io_error".to_owned(),
                    message: message.clone(),
                });
                invalid_entries.push(invalid_catalog_entry(
                    file_name.trim_end_matches(".toml").to_owned(),
                    doc_ref,
                    false,
                    message,
                ));
                continue;
            }
        };
        if meta.file_type().is_symlink() {
            let message = format!("MCP entry '{file_name}' must not be a symlink");
            diagnostics.push(McpDocumentDiagnostic {
                document: doc_ref.clone(),
                id: None,
                code: "symlink_rejected".to_owned(),
                message: message.clone(),
            });
            invalid_entries.push(invalid_catalog_entry(
                file_name.trim_end_matches(".toml").to_owned(),
                doc_ref,
                false,
                message,
            ));
            continue;
        }
        if !meta.is_file() {
            let message = format!("MCP entry '{file_name}' is not a regular TOML file");
            diagnostics.push(McpDocumentDiagnostic {
                document: doc_ref.clone(),
                id: None,
                code: "invalid_document".to_owned(),
                message: message.clone(),
            });
            invalid_entries.push(invalid_catalog_entry(
                file_name.trim_end_matches(".toml").to_owned(),
                doc_ref,
                false,
                message,
            ));
            continue;
        }
        if meta.len() > MAX_MCP_DOCUMENT_BYTES as u64 {
            let message = format!("MCP file '{file_name}' exceeds 1 MiB limit");
            diagnostics.push(McpDocumentDiagnostic {
                document: doc_ref.clone(),
                id: None,
                code: "document_too_large".to_owned(),
                message: message.clone(),
            });
            invalid_entries.push(invalid_catalog_entry(
                file_name.trim_end_matches(".toml").to_owned(),
                doc_ref,
                false,
                message,
            ));
            continue;
        }

        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) => {
                let message = format!("failed to read MCP file '{file_name}': {error}");
                diagnostics.push(McpDocumentDiagnostic {
                    document: doc_ref.clone(),
                    id: None,
                    code: "io_error".to_owned(),
                    message: message.clone(),
                });
                invalid_entries.push(invalid_catalog_entry(
                    file_name.trim_end_matches(".toml").to_owned(),
                    doc_ref,
                    false,
                    message,
                ));
                continue;
            }
        };
        if bytes.len() > MAX_MCP_DOCUMENT_BYTES {
            let message = format!("MCP file '{file_name}' exceeds 1 MiB limit");
            diagnostics.push(McpDocumentDiagnostic {
                document: doc_ref.clone(),
                id: None,
                code: "document_too_large".to_owned(),
                message: message.clone(),
            });
            invalid_entries.push(invalid_catalog_entry(
                file_name.trim_end_matches(".toml").to_owned(),
                doc_ref,
                false,
                message,
            ));
            continue;
        }
        document_revisions.insert(
            doc_ref.relative_path.clone(),
            document_revision(&doc_ref.relative_path, &bytes),
        );
        let raw_toml = match std::str::from_utf8(&bytes) {
            Ok(content) => content,
            Err(error) => {
                let message = format!("MCP file '{file_name}' is not valid UTF-8: {error}");
                diagnostics.push(McpDocumentDiagnostic {
                    document: doc_ref.clone(),
                    id: None,
                    code: "invalid_utf8".to_owned(),
                    message: message.clone(),
                });
                invalid_entries.push(invalid_catalog_entry(
                    file_name.trim_end_matches(".toml").to_owned(),
                    doc_ref,
                    false,
                    message,
                ));
                continue;
            }
        };

        match McpFileV1::parse_and_validate(raw_toml, &McpScope::Host) {
            Ok(doc) => {
                parsed_by_id
                    .entry(doc.id.clone())
                    .or_default()
                    .push((doc_ref, doc));
            }
            Err(error) => {
                let peeked_id = McpFileV1::peek_id(raw_toml);
                let display_id = peeked_id
                    .clone()
                    .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                let message = error.to_string();
                diagnostics.push(McpDocumentDiagnostic {
                    document: doc_ref.clone(),
                    id: peeked_id,
                    code: "invalid_document".to_owned(),
                    message: message.clone(),
                });
                invalid_entries.push(invalid_catalog_entry(display_id, doc_ref, false, message));
            }
        }
    }

    let mut valid_docs = BTreeMap::new();
    let mut entries = Vec::new();
    let mut effective_servers = BTreeMap::new();

    for (id, mut docs) in parsed_by_id {
        if docs.len() > 1 {
            let paths_list: Vec<&str> = docs
                .iter()
                .map(|(doc_ref, _)| doc_ref.relative_path.as_str())
                .collect();
            let message = format!(
                "duplicate Host MCP id '{id}' across files: {}",
                paths_list.join(", ")
            );
            for (doc_ref, _) in docs {
                diagnostics.push(McpDocumentDiagnostic {
                    document: doc_ref.clone(),
                    id: Some(id.clone()),
                    code: "duplicate_id".to_owned(),
                    message: message.clone(),
                });
                invalid_entries.push(invalid_catalog_entry(
                    id.clone(),
                    doc_ref,
                    false,
                    message.clone(),
                ));
            }
            continue;
        }
        let (doc_ref, doc) = docs.pop().expect("single doc");
        let built = build_scoped_entry_and_server(
            &doc_ref,
            &doc,
            models,
            &McpScope::Host,
            false,
            false,
            false,
        )?;
        if let Some((entry, scoped_server)) = built {
            entries.push(entry);
            effective_servers.insert(id.clone(), scoped_server);
            valid_docs.insert(id, (doc_ref, doc));
        }
    }

    entries.extend(invalid_entries);
    entries.sort_by(|a, b| {
        a.id.cmp(&b.id).then_with(|| {
            a.document
                .as_ref()
                .map(|d| d.relative_path.as_str())
                .cmp(&b.document.as_ref().map(|d| d.relative_path.as_str()))
        })
    });

    Ok(HostScanInternal {
        valid_docs,
        entries,
        diagnostics,
        effective_servers,
        document_revisions,
    })
}

fn scan_ssh_directory_with_host(
    paths: &ConfigPaths,
    models: &pl_model::config::AgentModelConfig,
    ssh_alias: &str,
    host_scan: &HostScanInternal,
) -> Result<ScopedMcpScan> {
    let scope = McpScope::Ssh {
        ssh_alias: ssh_alias.to_owned(),
    };
    let ssh_key = crate::studio::paths::storage_key(ssh_alias, "SSH server")
        .map_err(|error| PureError::ConfigError(error.to_string()))?;
    let ssh_dir = paths.mcp_ssh_dir(ssh_alias)?;

    // Map canonical filename `<sha256(host_id)>.toml` -> `host_id` for all valid Host servers.
    let mut canonical_to_host_id = BTreeMap::new();
    for host_id in host_scan.valid_docs.keys() {
        let canonical = canonical_mcp_filename(host_id)?;
        canonical_to_host_id.insert(canonical, host_id.clone());
    }

    let mut occupied_host_ids = BTreeSet::new();
    let mut entries = Vec::new();
    let mut diagnostics = host_scan
        .diagnostics
        .iter()
        .filter(|d| d.code == "scope_read_error")
        .cloned()
        .collect::<Vec<_>>();
    let mut effective_servers = BTreeMap::new();
    let mut document_revisions = BTreeMap::new();

    let ssh_dir_exists = match fs::symlink_metadata(&ssh_dir) {
        Ok(meta) => {
            if meta.file_type().is_symlink() || !meta.is_dir() {
                diagnostics.push(McpDocumentDiagnostic {
                    document: McpDocumentRef {
                        scope: scope.clone(),
                        relative_path: format!("mcp/ssh/{ssh_key}"),
                    },
                    id: None,
                    code: "scope_read_error".to_owned(),
                    message: "SSH MCP path is not a regular directory".to_owned(),
                });
                return Ok(ScopedMcpScan {
                    entries: Vec::new(),
                    diagnostics,
                    effective_servers: BTreeMap::new(),
                    document_revisions: BTreeMap::new(),
                });
            }
            true
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
        Err(error) => {
            diagnostics.push(McpDocumentDiagnostic {
                document: McpDocumentRef {
                    scope: scope.clone(),
                    relative_path: format!("mcp/ssh/{ssh_key}"),
                },
                id: None,
                code: "scope_read_error".to_owned(),
                message: format!("failed to inspect SSH MCP directory: {error}"),
            });
            return Ok(ScopedMcpScan {
                entries: Vec::new(),
                diagnostics,
                effective_servers: BTreeMap::new(),
                document_revisions: BTreeMap::new(),
            });
        }
    };

    if ssh_dir_exists {
        let dir_entries = match fs::read_dir(&ssh_dir) {
            Ok(entries) => entries,
            Err(error) => {
                diagnostics.push(McpDocumentDiagnostic {
                    document: McpDocumentRef {
                        scope: scope.clone(),
                        relative_path: format!("mcp/ssh/{ssh_key}"),
                    },
                    id: None,
                    code: "scope_read_error".to_owned(),
                    message: format!("failed to read SSH MCP directory: {error}"),
                });
                return Ok(ScopedMcpScan {
                    entries: Vec::new(),
                    diagnostics,
                    effective_servers: BTreeMap::new(),
                    document_revisions: BTreeMap::new(),
                });
            }
        };
        let mut raw_entries = Vec::new();
        for entry in dir_entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(error) => {
                    diagnostics.push(McpDocumentDiagnostic {
                        document: McpDocumentRef {
                            scope: scope.clone(),
                            relative_path: format!("mcp/ssh/{ssh_key}"),
                        },
                        id: None,
                        code: "scope_read_error".to_owned(),
                        message: format!("failed to enumerate SSH MCP directory: {error}"),
                    });
                    return Ok(ScopedMcpScan {
                        entries: Vec::new(),
                        diagnostics,
                        effective_servers: BTreeMap::new(),
                        document_revisions: BTreeMap::new(),
                    });
                }
            };
            let path = entry.path();
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                raw_entries.push((name.to_owned(), path));
            }
        }
        raw_entries.sort_by(|a, b| a.0.cmp(&b.0));

        for (file_name, path) in raw_entries {
            let matched_host_id = canonical_to_host_id.get(&file_name).cloned();
            if let Some(host_id) = &matched_host_id {
                // Any directory entry at `<canonical_mcp_filename(host_id)>` occupies the slot and blocks inheritance!
                occupied_host_ids.insert(host_id.clone());
            } else if is_ignored_temp_or_backup_name(&file_name) {
                continue;
            }

            let is_toml = path.extension().and_then(|ext| ext.to_str()) == Some("toml");
            let doc_ref = McpDocumentRef {
                scope: scope.clone(),
                relative_path: format!("mcp/ssh/{ssh_key}/{file_name}"),
            };

            let metadata = match fs::symlink_metadata(&path) {
                Ok(meta) => meta,
                Err(error) => {
                    if is_toml || matched_host_id.is_some() {
                        let display_id = matched_host_id
                            .clone()
                            .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                        let message =
                            format!("failed to inspect SSH MCP entry '{file_name}': {error}");
                        diagnostics.push(McpDocumentDiagnostic {
                            document: doc_ref.clone(),
                            id: matched_host_id,
                            code: "io_error".to_owned(),
                            message: message.clone(),
                        });
                        entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                    }
                    continue;
                }
            };

            if metadata.file_type().is_symlink() {
                if is_toml || matched_host_id.is_some() {
                    let display_id = matched_host_id
                        .clone()
                        .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                    let message = format!("SSH MCP entry '{file_name}' must not be a symlink");
                    diagnostics.push(McpDocumentDiagnostic {
                        document: doc_ref.clone(),
                        id: matched_host_id,
                        code: "symlink_rejected".to_owned(),
                        message: message.clone(),
                    });
                    entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                }
                continue;
            }

            if !metadata.is_file() {
                if is_toml || matched_host_id.is_some() {
                    let display_id = matched_host_id
                        .clone()
                        .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                    let message = format!("SSH MCP entry '{file_name}' is not a regular TOML file");
                    diagnostics.push(McpDocumentDiagnostic {
                        document: doc_ref.clone(),
                        id: matched_host_id,
                        code: "invalid_document".to_owned(),
                        message: message.clone(),
                    });
                    entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                }
                continue;
            }

            if !is_toml {
                continue;
            }

            if metadata.len() > MAX_MCP_DOCUMENT_BYTES as u64 {
                let display_id = matched_host_id
                    .clone()
                    .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                let message = format!("SSH MCP file '{file_name}' exceeds 1 MiB limit");
                diagnostics.push(McpDocumentDiagnostic {
                    document: doc_ref.clone(),
                    id: matched_host_id,
                    code: "document_too_large".to_owned(),
                    message: message.clone(),
                });
                entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                continue;
            }

            let bytes = match fs::read(&path) {
                Ok(bytes) => bytes,
                Err(error) => {
                    let display_id = matched_host_id
                        .clone()
                        .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                    let message = format!("failed to read SSH MCP file '{file_name}': {error}");
                    diagnostics.push(McpDocumentDiagnostic {
                        document: doc_ref.clone(),
                        id: matched_host_id,
                        code: "io_error".to_owned(),
                        message: message.clone(),
                    });
                    entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                    continue;
                }
            };
            if bytes.len() > MAX_MCP_DOCUMENT_BYTES {
                let display_id = matched_host_id
                    .clone()
                    .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                let message = format!("SSH MCP file '{file_name}' exceeds 1 MiB limit");
                diagnostics.push(McpDocumentDiagnostic {
                    document: doc_ref.clone(),
                    id: matched_host_id,
                    code: "document_too_large".to_owned(),
                    message: message.clone(),
                });
                entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                continue;
            }
            document_revisions.insert(
                doc_ref.relative_path.clone(),
                document_revision(&doc_ref.relative_path, &bytes),
            );
            let raw_toml = match std::str::from_utf8(&bytes) {
                Ok(content) => content,
                Err(error) => {
                    let display_id = matched_host_id
                        .clone()
                        .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                    let message = format!("SSH MCP file '{file_name}' is not valid UTF-8: {error}");
                    diagnostics.push(McpDocumentDiagnostic {
                        document: doc_ref.clone(),
                        id: matched_host_id,
                        code: "invalid_utf8".to_owned(),
                        message: message.clone(),
                    });
                    entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                    continue;
                }
            };

            match McpFileV1::parse_and_validate(raw_toml, &scope) {
                Ok(doc) => {
                    let expected_filename = canonical_mcp_filename(&doc.id)?;
                    if file_name != expected_filename {
                        // Filename does not match `storage_key(doc.id)`.
                        let (code, display_id, message) = if let Some(host_id) = &matched_host_id {
                            (
                                "file_identity_mismatch".to_owned(),
                                host_id.clone(),
                                format!(
                                    "SSH MCP file '{file_name}' occupies Host id '{host_id}' slot but declares mismatched id '{}'",
                                    doc.id
                                ),
                            )
                        } else {
                            (
                                "invalid_filename".to_owned(),
                                doc.id.clone(),
                                format!(
                                    "SSH MCP file '{file_name}' does not match canonical filename '{expected_filename}' for id '{}'",
                                    doc.id
                                ),
                            )
                        };
                        diagnostics.push(McpDocumentDiagnostic {
                            document: doc_ref.clone(),
                            id: Some(display_id.clone()),
                            code,
                            message: message.clone(),
                        });
                        entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                        continue;
                    }

                    occupied_host_ids.insert(doc.id.clone());
                    let host_has_id = host_scan.valid_docs.contains_key(&doc.id);
                    let built = build_scoped_entry_and_server(
                        &doc_ref,
                        &doc,
                        models,
                        &scope,
                        false,
                        true,
                        host_has_id,
                    )?;
                    if let Some((entry, scoped_server)) = built {
                        entries.push(entry);
                        effective_servers.insert(doc.id.clone(), scoped_server);
                    } else if matches!(doc.spec, McpFileSpecV1::Disabled) {
                        let shadowed_builtin = host_scan
                            .valid_docs
                            .get(&doc.id)
                            .is_some_and(|(_, d)| matches!(d.spec, McpFileSpecV1::Builtin { .. }));
                        entries.push(McpCatalogEntry {
                            id: doc.id.clone(),
                            document: Some(doc_ref),
                            config_status: McpConfigStatusKind::ShadowedDisable,
                            effective_source: McpEffectiveSource::SshDisabledTombstone,
                            execution_location: None,
                            transport: None,
                            endpoint_summary: None,
                            built_in: shadowed_builtin,
                            inherited_from_host: false,
                            overridden_in_scope: true,
                            can_override_in_ssh: true,
                            can_disable_in_ssh: false,
                            can_restore_inheritance: true,
                            message: Some(
                                "Disabled in this SSH environment (inheritance blocked)".to_owned(),
                            ),
                        });
                    }
                }
                Err(error) => {
                    let peeked_id = McpFileV1::peek_id(raw_toml);
                    let display_id = matched_host_id
                        .clone()
                        .or(peeked_id.clone())
                        .unwrap_or_else(|| file_name.trim_end_matches(".toml").to_owned());
                    let message = error.to_string();
                    diagnostics.push(McpDocumentDiagnostic {
                        document: doc_ref.clone(),
                        id: matched_host_id.or(peeked_id),
                        code: "invalid_document".to_owned(),
                        message: message.clone(),
                    });
                    entries.push(invalid_catalog_entry(display_id, doc_ref, true, message));
                }
            }
        }
    }

    // Inherit any valid Host document whose id slot is NOT occupied in this SSH scope.
    for (host_id, (host_doc_ref, host_doc)) in &host_scan.valid_docs {
        if occupied_host_ids.contains(host_id) {
            continue;
        }
        if let Some((entry, scoped_server)) = build_scoped_entry_and_server(
            host_doc_ref,
            host_doc,
            models,
            &scope,
            true,
            false,
            false,
        )? {
            entries.push(entry);
            effective_servers.insert(host_id.clone(), scoped_server);
        }
    }

    entries.sort_by(|a, b| {
        a.id.cmp(&b.id).then_with(|| {
            a.document
                .as_ref()
                .map(|d| d.relative_path.as_str())
                .cmp(&b.document.as_ref().map(|d| d.relative_path.as_str()))
        })
    });

    Ok(ScopedMcpScan {
        entries,
        diagnostics,
        effective_servers,
        document_revisions,
    })
}

fn build_scoped_entry_and_server(
    doc_ref: &McpDocumentRef,
    doc: &McpFileV1,
    models: &pl_model::config::AgentModelConfig,
    scope: &McpScope,
    inherited_from_host: bool,
    overridden_in_scope: bool,
    host_has_id: bool,
) -> Result<Option<(McpCatalogEntry, ScopedEffectiveMcpServer)>> {
    let is_ssh_override = matches!(scope, McpScope::Ssh { .. }) && !inherited_from_host;
    let ssh_alias = match scope {
        McpScope::Host => None,
        McpScope::Ssh { ssh_alias } => Some(ssh_alias.clone()),
    };

    match &doc.spec {
        McpFileSpecV1::Disabled => Ok(None),
        McpFileSpecV1::Server(config) => {
            let effective_source = match (scope, inherited_from_host) {
                (McpScope::Host, _) => McpEffectiveSource::HostServer,
                (McpScope::Ssh { .. }, true) => McpEffectiveSource::InheritedHostServer,
                (McpScope::Ssh { .. }, false) => McpEffectiveSource::SshOverrideServer,
            };
            let execution_location = match (is_ssh_override, config.transport) {
                (false, McpServerTransport::Stdio) => McpExecutionLocation::HostLocal,
                (false, McpServerTransport::StreamableHttp) => {
                    McpExecutionLocation::HostRemoteStreamableHttp
                }
                (true, McpServerTransport::Stdio) => McpExecutionLocation::SshRemote {
                    ssh_alias: ssh_alias.clone().unwrap_or_default(),
                },
                (true, McpServerTransport::StreamableHttp) => {
                    McpExecutionLocation::SshRemoteStreamableHttp {
                        ssh_alias: ssh_alias.unwrap_or_default(),
                    }
                }
            };
            let (config_status, status_kind, status_message) = if !config.enabled {
                (
                    McpConfigStatusKind::Disabled,
                    McpServerStatusKind::Disabled,
                    None,
                )
            } else if !is_ssh_override
                && config.transport == McpServerTransport::StreamableHttp
                && let Some(env_var) = config.bearer_token_env_var.as_deref()
                && std::env::var(env_var)
                    .ok()
                    .map(|v| v.trim().to_owned())
                    .filter(|v| !v.is_empty())
                    .is_none()
            {
                (
                    McpConfigStatusKind::MissingPrereq,
                    McpServerStatusKind::MissingCredential,
                    Some(format!(
                        "Set environment variable '{env_var}' to enable this server"
                    )),
                )
            } else {
                (
                    McpConfigStatusKind::Enabled,
                    McpServerStatusKind::Enabled,
                    None,
                )
            };

            let bearer_token = if !is_ssh_override
                && config.transport == McpServerTransport::StreamableHttp
                && let Some(env_var) = config.bearer_token_env_var.as_deref()
            {
                std::env::var(env_var)
                    .ok()
                    .map(|v| v.trim().to_owned())
                    .filter(|v| !v.is_empty())
            } else {
                None
            };

            let endpoint_summary = config.endpoint_summary();
            let transport_label = config.transport.as_str().to_owned();
            let effective = EffectiveMcpServerConfig {
                id: doc.id.clone(),
                config: config.as_ref().clone(),
                source_kind: McpServerSourceKind::User,
                source_label: "User".to_owned(),
                source_detail: None,
                status_kind,
                status_message: status_message.clone(),
                mutation_policy: McpServerMutationPolicy::UserEditable,
                bearer_token,
                tool_effect: None,
                execution_context: McpExecutionContext::Host,
            };
            let entry = McpCatalogEntry {
                id: doc.id.clone(),
                document: Some(doc_ref.clone()),
                config_status,
                effective_source,
                execution_location: Some(execution_location.clone()),
                transport: Some(transport_label),
                endpoint_summary: Some(endpoint_summary),
                built_in: false,
                inherited_from_host,
                overridden_in_scope,
                can_override_in_ssh: matches!(scope, McpScope::Ssh { .. }) && inherited_from_host,
                can_disable_in_ssh: matches!(scope, McpScope::Ssh { .. })
                    && (inherited_from_host || host_has_id),
                can_restore_inheritance: matches!(scope, McpScope::Ssh { .. })
                    && overridden_in_scope,
                message: status_message,
            };
            let scoped = ScopedEffectiveMcpServer {
                id: doc.id.clone(),
                document: doc_ref.clone(),
                config_status,
                effective_source,
                execution_location,
                built_in: false,
                server: effective,
            };
            Ok(Some((entry, scoped)))
        }
        McpFileSpecV1::Builtin {
            enabled,
            required,
            builtin_id,
            cwd,
        } => {
            let effective = build_builtin_effective_config(
                builtin_id,
                *enabled,
                *required,
                cwd.clone(),
                models,
            )
            .ok_or_else(|| {
                PureError::ConfigError(format!("unknown built-in MCP server '{builtin_id}'"))
            })?;
            let effective_source = match (scope, inherited_from_host) {
                (McpScope::Host, _) => McpEffectiveSource::HostBuiltin,
                (McpScope::Ssh { .. }, true) => McpEffectiveSource::InheritedHostBuiltin,
                (McpScope::Ssh { .. }, false) => McpEffectiveSource::SshOverrideBuiltin,
            };
            let execution_location = match (is_ssh_override, effective.config.transport) {
                (false, McpServerTransport::Stdio) => McpExecutionLocation::HostLocal,
                (false, McpServerTransport::StreamableHttp) => {
                    McpExecutionLocation::HostRemoteStreamableHttp
                }
                (true, McpServerTransport::Stdio) => McpExecutionLocation::SshRemote {
                    ssh_alias: ssh_alias.clone().unwrap_or_default(),
                },
                (true, McpServerTransport::StreamableHttp) => {
                    McpExecutionLocation::SshRemoteStreamableHttp {
                        ssh_alias: ssh_alias.unwrap_or_default(),
                    }
                }
            };
            let config_status = match effective.status_kind {
                McpServerStatusKind::Enabled => McpConfigStatusKind::Enabled,
                McpServerStatusKind::Disabled => McpConfigStatusKind::Disabled,
                McpServerStatusKind::MissingCredential => McpConfigStatusKind::MissingPrereq,
            };
            let endpoint_summary = effective.config.endpoint_summary();
            let transport_label = effective.config.transport.as_str().to_owned();
            let message = effective.status_message.clone();
            let entry = McpCatalogEntry {
                id: doc.id.clone(),
                document: Some(doc_ref.clone()),
                config_status,
                effective_source,
                execution_location: Some(execution_location.clone()),
                transport: Some(transport_label),
                endpoint_summary: Some(endpoint_summary),
                built_in: true,
                inherited_from_host,
                overridden_in_scope,
                can_override_in_ssh: matches!(scope, McpScope::Ssh { .. }) && inherited_from_host,
                can_disable_in_ssh: matches!(scope, McpScope::Ssh { .. }),
                can_restore_inheritance: matches!(scope, McpScope::Ssh { .. })
                    && overridden_in_scope,
                message,
            };
            let scoped = ScopedEffectiveMcpServer {
                id: doc.id.clone(),
                document: doc_ref.clone(),
                config_status,
                effective_source,
                execution_location,
                built_in: true,
                server: effective,
            };
            Ok(Some((entry, scoped)))
        }
    }
}

fn invalid_catalog_entry(
    id: String,
    document: McpDocumentRef,
    in_ssh_scope: bool,
    message: String,
) -> McpCatalogEntry {
    McpCatalogEntry {
        built_in: false,
        id,
        document: Some(document),
        config_status: McpConfigStatusKind::InvalidDocument,
        effective_source: McpEffectiveSource::InvalidFile,
        execution_location: None,
        transport: None,
        endpoint_summary: None,
        inherited_from_host: false,
        overridden_in_scope: in_ssh_scope,
        can_override_in_ssh: false,
        can_disable_in_ssh: false,
        can_restore_inheritance: in_ssh_scope,
        message: Some(message),
    }
}

pub fn resolve_scoped_servers_for_thread(
    scoped: BTreeMap<String, ScopedEffectiveMcpServer>,
    scope: &McpScope,
    workspace_root: &Path,
    host_base_cwd: &Path,
    remote_commands: Option<Arc<RemoteCommandBackend>>,
) -> Result<BTreeMap<String, ResolvedThreadMcpServer>> {
    let mut resolved = BTreeMap::new();
    for (id, mut entry) in scoped {
        if !entry.server.config.enabled
            || !matches!(
                entry.config_status,
                McpConfigStatusKind::Enabled | McpConfigStatusKind::MissingPrereq
            )
        {
            continue;
        }
        match &entry.execution_location {
            McpExecutionLocation::HostLocal | McpExecutionLocation::HostRemoteStreamableHttp => {
                entry.server.execution_context = McpExecutionContext::Host;
            }
            McpExecutionLocation::SshRemote { .. }
            | McpExecutionLocation::SshRemoteStreamableHttp { .. } => {
                let commands = remote_commands.as_deref().cloned().ok_or_else(|| {
                    PureError::ConfigError(format!(
                        "remote MCP server '{id}' requires an active SSH command backend"
                    ))
                })?;
                entry.server.execution_context = McpExecutionContext::Remote { commands };
            }
        }

        if entry.server.config.transport == McpServerTransport::Stdio {
            let expanded_cwd = resolve_stdio_cwd(
                entry.server.config.cwd.as_deref(),
                scope,
                entry.effective_source,
                workspace_root,
                host_base_cwd,
            )?;
            entry.server.config.cwd = Some(expanded_cwd);
        }

        resolved.insert(
            id.clone(),
            ResolvedThreadMcpServer {
                id,
                effective_source: entry.effective_source,
                execution_location: entry.execution_location,
                built_in: entry.built_in,
                server: entry.server,
            },
        );
    }
    Ok(resolved)
}

pub fn resolve_stdio_cwd(
    configured_cwd: Option<&str>,
    scope: &McpScope,
    effective_source: McpEffectiveSource,
    workspace_root: &Path,
    host_base_cwd: &Path,
) -> Result<String> {
    if let Some(raw) = configured_cwd
        && raw.trim().is_empty()
    {
        return Err(PureError::ConfigError(
            "MCP stdio cwd must not be empty when specified".to_owned(),
        ));
    }
    let is_remote_stdio = matches!(
        effective_source,
        McpEffectiveSource::SshOverrideServer | McpEffectiveSource::SshOverrideBuiltin
    );
    let base_dir = match (scope, is_remote_stdio) {
        (McpScope::Host, _) => workspace_root,
        (McpScope::Ssh { .. }, true) => workspace_root,
        (McpScope::Ssh { .. }, false) => host_base_cwd,
    };

    match configured_cwd {
        None => Ok(base_dir.to_string_lossy().into_owned()),
        Some(raw) => {
            if is_remote_stdio {
                if raw.starts_with('/') {
                    Ok(raw.to_owned())
                } else {
                    let base = base_dir.to_string_lossy();
                    let trimmed = base.trim_end_matches('/');
                    if trimmed.is_empty() {
                        Ok(format!("/{raw}"))
                    } else {
                        Ok(format!("{trimmed}/{raw}"))
                    }
                }
            } else {
                let path = Path::new(raw);
                if path.is_absolute() {
                    Ok(raw.to_owned())
                } else {
                    Ok(base_dir.join(path).to_string_lossy().into_owned())
                }
            }
        }
    }
}

fn host_id_exists_in_other_file(
    paths: &ConfigPaths,
    target_id: &str,
    ignore_path: &Path,
) -> std::result::Result<bool, McpDocumentError> {
    let host_dir = paths.mcp_host_dir();
    let entries = match fs::read_dir(&host_dir) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(McpDocumentError::Io(error.to_string())),
    };
    for entry in entries {
        let entry = entry.map_err(|e| McpDocumentError::Io(e.to_string()))?;
        let path = entry.path();
        if path == ignore_path || path.extension().and_then(|e| e.to_str()) != Some("toml") {
            continue;
        }
        if let Ok(raw) = fs::read_to_string(&path)
            && McpFileV1::peek_id(&raw).as_deref() == Some(target_id)
        {
            return Ok(true);
        }
    }
    Ok(false)
}

pub(crate) fn write_file_atomic(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let parent = path.parent().ok_or_else(|| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("path has no parent directory: {}", path.display()),
        )
    })?;
    fs::create_dir_all(parent)?;
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("mcp.toml");
    let temp_path = parent.join(format!(".{file_name}.{}.{nanos}.tmp", std::process::id()));
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&temp_path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = file.set_permissions(fs::Permissions::from_mode(0o600));
    }
    if let Err(error) = file.write_all(bytes).and_then(|()| file.sync_all()) {
        let _ = fs::remove_file(&temp_path);
        return Err(error);
    }
    drop(file);
    if let Err(error) = fs::rename(&temp_path, path) {
        let _ = fs::remove_file(&temp_path);
        return Err(error);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::StudioConfig;

    #[test]
    fn ssh_scope_inherits_overrides_disables_and_fails_closed_without_fallback() {
        let temp = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(temp.path());
        let config = StudioConfig::default_config().unwrap();
        let resource = McpCatalogResource::new(&paths, &config.models);

        // 1. Create two Host MCP servers: `shared_git` and `shared_http`.
        let (git_receipt, _) = resource
            .create_document(
                &paths,
                &config.models,
                &CreateMcpDocumentRequest {
                    scope: McpScope::Host,
                    id: "shared_git".to_owned(),
                    raw_toml: r#"schema_version = 1
id = "shared_git"
kind = "server"
enabled = true
required = true
transport = "stdio"
command = "uvx"
args = ["mcp-server-git"]
cwd = "tools/git"
"#
                    .to_owned(),
                },
            )
            .unwrap();
        assert!(git_receipt.document.is_some());

        let (_http_receipt, _) = resource
            .create_document(
                &paths,
                &config.models,
                &CreateMcpDocumentRequest {
                    scope: McpScope::Host,
                    id: "shared_http".to_owned(),
                    raw_toml: r#"schema_version = 1
id = "shared_http"
kind = "server"
enabled = true
transport = "streamableHttp"
url = "https://host.example.com/mcp"
"#
                    .to_owned(),
                },
            )
            .unwrap();

        let ssh_scope = McpScope::Ssh {
            ssh_alias: "gpu-box".to_owned(),
        };

        // T18: Unoverridden Host servers are inherited in SSH scope and execute on Host.
        let ssh_initial = resource
            .read_catalog(&paths, &config.models, &ssh_scope)
            .unwrap();
        let inherited_git = ssh_initial
            .entries
            .iter()
            .find(|e| e.id == "shared_git")
            .unwrap();
        assert_eq!(
            inherited_git.effective_source,
            McpEffectiveSource::InheritedHostServer
        );
        assert_eq!(
            inherited_git.execution_location,
            Some(McpExecutionLocation::HostLocal)
        );
        assert!(inherited_git.inherited_from_host);
        assert!(inherited_git.can_override_in_ssh);
        assert!(inherited_git.can_disable_in_ssh);
        let inherited_servers = resource
            .effective_servers_for_scope(&paths, &config.models, &ssh_scope)
            .unwrap();
        assert!(inherited_servers["shared_git"].server.config.required);

        // Inherited stdio cwd resolves against host_base_cwd, NOT remote workspace_root.
        let resolved_inherited_cwd = resolve_stdio_cwd(
            Some("tools/git"),
            &ssh_scope,
            McpEffectiveSource::InheritedHostServer,
            Path::new("/remote/workspace"),
            Path::new("/host/home"),
        )
        .unwrap();
        assert_eq!(
            resolved_inherited_cwd,
            Path::new("/host/home").join("tools/git").to_string_lossy()
        );

        // T19: Override `shared_git` in SSH scope -> executes on SshRemote and resolves cwd against remote workspace_root.
        let (override_receipt, _) = resource
            .create_document(
                &paths,
                &config.models,
                &CreateMcpDocumentRequest {
                    scope: ssh_scope.clone(),
                    id: "shared_git".to_owned(),
                    raw_toml: r#"schema_version = 1
id = "shared_git"
kind = "server"
enabled = true
transport = "stdio"
command = "/usr/local/bin/mcp-git-remote"
cwd = "sub/remote"
"#
                    .to_owned(),
                },
            )
            .unwrap();
        let overridden_git = override_receipt
            .snapshot
            .entries
            .iter()
            .find(|e| e.id == "shared_git")
            .unwrap();
        assert_eq!(
            overridden_git.effective_source,
            McpEffectiveSource::SshOverrideServer
        );
        assert_eq!(
            overridden_git.execution_location,
            Some(McpExecutionLocation::SshRemote {
                ssh_alias: "gpu-box".to_owned()
            })
        );
        assert!(overridden_git.overridden_in_scope);
        assert!(overridden_git.can_restore_inheritance);
        let overridden_servers = resource
            .effective_servers_for_scope(&paths, &config.models, &ssh_scope)
            .unwrap();
        assert!(!overridden_servers["shared_git"].server.config.required);

        let resolved_remote_cwd = resolve_stdio_cwd(
            Some("sub/remote"),
            &ssh_scope,
            McpEffectiveSource::SshOverrideServer,
            Path::new("/remote/workspace"),
            Path::new("/host/home"),
        )
        .unwrap();
        assert_eq!(resolved_remote_cwd, "/remote/workspace/sub/remote");

        // T20: Disable `shared_http` in SSH scope via `kind = "disabled"` tombstone -> suppressed from effective servers,
        // and deleting the tombstone restores Host inheritance.
        let (tombstone_receipt, _) = resource
            .create_document(
                &paths,
                &config.models,
                &CreateMcpDocumentRequest {
                    scope: ssh_scope.clone(),
                    id: "shared_http".to_owned(),
                    raw_toml: r#"schema_version = 1
id = "shared_http"
kind = "disabled"
"#
                    .to_owned(),
                },
            )
            .unwrap();
        let tombstone_entry = tombstone_receipt
            .snapshot
            .entries
            .iter()
            .find(|e| e.id == "shared_http")
            .unwrap();
        assert_eq!(
            tombstone_entry.effective_source,
            McpEffectiveSource::SshDisabledTombstone
        );
        assert_eq!(
            tombstone_entry.config_status,
            McpConfigStatusKind::ShadowedDisable
        );
        let effective_with_tombstone = resource
            .effective_servers_for_scope(&paths, &config.models, &ssh_scope)
            .unwrap();
        assert!(!effective_with_tombstone.contains_key("shared_http"));

        let (after_delete_tombstone, _) = resource
            .delete_document(
                &paths,
                &config.models,
                &DeleteMcpDocumentRequest {
                    document: tombstone_receipt.document.unwrap(),
                    expected_revision: tombstone_receipt.revision,
                },
            )
            .unwrap();
        let restored_http = after_delete_tombstone
            .snapshot
            .entries
            .iter()
            .find(|e| e.id == "shared_http")
            .unwrap();
        assert_eq!(
            restored_http.effective_source,
            McpEffectiveSource::InheritedHostServer
        );
        let effective_after_restore = resource
            .effective_servers_for_scope(&paths, &config.models, &ssh_scope)
            .unwrap();
        assert!(effective_after_restore.contains_key("shared_http"));

        // T21: Invalid SSH override file occupies the `shared_http` id slot and fails closed without falling back to Host.
        let invalid_ssh_doc = canonical_document_ref(&ssh_scope, "shared_http").unwrap();
        let invalid_ssh_path = resolve_document_path(&paths, &invalid_ssh_doc).unwrap();
        fs::create_dir_all(invalid_ssh_path.parent().unwrap()).unwrap();
        fs::write(
            &invalid_ssh_path,
            "schema_version = 1\nid = \"shared_http\"\nkind = \"server\"\ntransport = \"stdio\"\n",
        )
        .unwrap();
        let (corrupted_snapshot, _) = resource
            .adopt_scan(&paths, &config.models, &ssh_scope)
            .unwrap();
        let corrupted_entry = corrupted_snapshot
            .entries
            .iter()
            .find(|e| e.id == "shared_http")
            .unwrap();
        assert_eq!(
            corrupted_entry.config_status,
            McpConfigStatusKind::InvalidDocument
        );
        assert_eq!(
            corrupted_entry.effective_source,
            McpEffectiveSource::InvalidFile
        );
        let effective_with_corrupted_override = resource
            .effective_servers_for_scope(&paths, &config.models, &ssh_scope)
            .unwrap();
        assert!(
            !effective_with_corrupted_override.contains_key("shared_http"),
            "invalid SSH override must fail closed and never fall back to Host server"
        );
    }
}
