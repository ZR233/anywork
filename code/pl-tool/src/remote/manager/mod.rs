//! One explicit OpenSSH connection owns one foreground executor.
use crate::workspace_file::ExecutorWorkspaceFileBackend;
mod asset;
mod connection;
mod shutdown;
mod ssh;
use super::{RemoteWorkspaceHost, SshConfigEntry, SshConfigFile, SshError};
use asset::file_helper_assets;
pub use asset::{RemoteHelperAssets, RemoteHelperTarget};
use pl_remote_helper::{Executor, ExecutorId};
use serde::{Deserialize, Serialize};
use ssh::validate_profile;
use std::{
    collections::{BTreeMap, HashMap},
    path::PathBuf,
    sync::Arc,
};
use tokio::sync::{Mutex, RwLock, watch};
use tokio_util::{sync::CancellationToken, task::TaskTracker};
/// 不含 secret 的 SSH 服务器配置；别名即身份，对应 `~/.ssh/config` 的 Host。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SshServerProfile {
    pub alias: String,
    pub host_name: String,
    pub port: u16,
    pub username: String,
    pub identity_file: Option<String>,
}

/// 单个 SSH 服务器的 canonical 连接快照。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SshConnectionSnapshot {
    pub alias: String,
    pub state: SshConnectionState,
}

/// SSH transport 与 helper bootstrap 的穷尽状态。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum SshConnectionState {
    Disconnected,
    Connecting,
    Ready {
        helper_version: String,
        architecture: String,
    },
    Closing,
    Failed {
        code: String,
        message: String,
    },
}

type ServerControl = Arc<Mutex<()>>;
type CloseObservation = watch::Receiver<Option<Result<(), SshError>>>;

struct SshConnection {
    profile: Arc<SshServerProfile>,
    executor: Executor,
    process: Mutex<Box<dyn process_wrap::tokio::ChildWrapper>>,
    close: Mutex<Option<CloseObservation>>,
}
impl std::fmt::Debug for SshConnection {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SshConnection")
            .field("executor", &self.executor)
            .finish_non_exhaustive()
    }
}
#[derive(Clone, Default)]
struct SshPasswordStore(Arc<RwLock<HashMap<String, String>>>);
impl std::fmt::Debug for SshPasswordStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SshPasswordStore(..)")
    }
}
#[derive(Debug, Default)]
struct ConnectionIntent {
    cancelled: CancellationToken,
}
#[derive(Debug, Clone)]
struct ConnectionAttempt {
    intent: Arc<ConnectionIntent>,
    result: watch::Receiver<Option<Result<(), SshError>>>,
}
struct BrowseCursor {
    alias: String,
    executor: ExecutorId,
    path: String,
    parent: Option<String>,
    reader: Mutex<BrowseReader>,
    stop: CancellationToken,
}
struct BrowseReader {
    reader: Option<pl_remote_helper::fs::DirectoryReader>,
    pending: Option<pl_remote_helper::fs::DirectoryEntry>,
}
impl std::fmt::Debug for BrowseCursor {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BrowseCursor")
            .field("executor", &self.executor)
            .finish_non_exhaustive()
    }
}
#[derive(Debug, Clone)]
pub struct SshManager {
    servers: Arc<RwLock<HashMap<String, SshConfigEntry>>>,
    passwords: SshPasswordStore,
    ssh_config: SshConfigFile,
    helper_assets: Option<Arc<dyn RemoteHelperAssets>>,
    connections: Arc<Mutex<HashMap<String, Arc<SshConnection>>>>,
    connecting: Arc<Mutex<HashMap<String, ConnectionAttempt>>>,
    desired_connections: Arc<RwLock<HashMap<String, Arc<ConnectionIntent>>>>,
    states: Arc<RwLock<HashMap<String, watch::Sender<SshConnectionState>>>>,
    ready_revisions: watch::Sender<BTreeMap<String, u64>>,
    directories: Arc<Mutex<HashMap<String, Arc<BrowseCursor>>>>,
    controls: Arc<Mutex<HashMap<String, ServerControl>>>,
    admission: Arc<Mutex<bool>>,
    closing: CancellationToken,
    operations: TaskTracker,
}
impl SshManager {
    pub fn new(aarch64_helper: Option<PathBuf>, x86_64_helper: Option<PathBuf>) -> Self {
        Self::with_optional_helper_assets(file_helper_assets(aarch64_helper, x86_64_helper))
    }
    pub fn with_helper_assets(assets: Arc<dyn RemoteHelperAssets>) -> Self {
        Self::with_optional_helper_assets(Some(assets))
    }
    pub fn with_ssh_config(mut self, config: SshConfigFile) -> Self {
        self.ssh_config = config;
        self
    }
    fn with_optional_helper_assets(helper_assets: Option<Arc<dyn RemoteHelperAssets>>) -> Self {
        Self {
            servers: Default::default(),
            passwords: Default::default(),
            ssh_config: SshConfigFile::user_default().unwrap_or_else(|error| {
                tracing::warn!(%error, "falling back to default ssh config location");
                SshConfigFile::default_location(".ssh/config")
            }),
            helper_assets,
            connections: Default::default(),
            connecting: Default::default(),
            desired_connections: Default::default(),
            states: Default::default(),
            ready_revisions: watch::channel(Default::default()).0,
            directories: Default::default(),
            controls: Default::default(),
            admission: Arc::new(Mutex::new(true)),
            closing: Default::default(),
            operations: TaskTracker::new(),
        }
    }
    pub async fn set_server_password(&self, server_id: &str, password: Option<String>) {
        let mut passwords = self.passwords.0.write().await;
        match password.filter(|secret| !secret.is_empty()) {
            Some(secret) => {
                passwords.insert(server_id.to_string(), secret);
            }
            None => {
                passwords.remove(server_id);
            }
        }
    }

    /// 读取当前进程内缓存的服务器 SSH 密码。
    pub async fn server_password(&self, server_id: &str) -> Option<String> {
        self.passwords.0.read().await.get(server_id).cloned()
    }

    /// 判断当前进程内是否持有该服务器的非空 SSH 密码。
    pub async fn has_server_password(&self, server_id: &str) -> bool {
        self.passwords
            .0
            .read()
            .await
            .get(server_id)
            .is_some_and(|secret| !secret.is_empty())
    }

    /// 从 ssh config 文件重新加载服务器集合；文件是该数据的唯一事实源。
    pub async fn reload_servers(&self) -> Result<(), SshError> {
        let entries = self.ssh_config.read().await?;
        let mut servers = self.servers.write().await;
        servers.clear();
        for entry in entries {
            servers.insert(entry.profile.alias.clone(), entry);
        }
        Ok(())
    }

    /// 返回按别名稳定排序的服务器条目（含是否为 anywork 管理块）。
    pub async fn list_servers(&self) -> Vec<SshConfigEntry> {
        let mut servers = self
            .servers
            .read()
            .await
            .values()
            .cloned()
            .collect::<Vec<_>>();
        servers.sort_by(|left, right| left.profile.alias.cmp(&right.profile.alias));
        servers
    }

    /// 校验并把服务器配置写入 ssh config 管理块。
    ///
    /// 别名被手写条目占用、或文件写入失败时返回错误且不改变内存集合。
    pub async fn save_server(
        &self,
        profile: SshServerProfile,
    ) -> Result<SshServerProfile, SshError> {
        validate_profile(&profile)?;
        let _guard = self.control(&profile.alias).await.lock_owned().await;
        let previous = self
            .servers
            .read()
            .await
            .get(&profile.alias)
            .map(|entry| entry.profile.clone());
        self.ssh_config
            .upsert_managed(std::slice::from_ref(&profile))
            .await?;
        if previous.as_ref() != Some(&profile) {
            self.disconnect_server_inner(&profile.alias).await?;
        }
        self.ensure_state(&profile.alias).await;
        self.servers.write().await.insert(
            profile.alias.clone(),
            SshConfigEntry {
                profile: profile.clone(),
                managed: true,
            },
        );
        Ok(profile)
    }

    /// 删除服务器配置、连接与 workspace cache；仅 anywork 管理块可删除。
    pub async fn delete_server(&self, server_id: &str) -> Result<(), SshError> {
        let _guard = self.control(server_id).await.lock_owned().await;
        self.ssh_config.remove_managed(server_id).await?;
        self.disconnect_server_inner(server_id).await?;
        self.passwords.0.write().await.remove(server_id);
        self.servers.write().await.remove(server_id);
        self.states.write().await.remove(server_id);
        Ok(())
    }

    /// 读取服务器的 canonical 连接状态。
    pub async fn connection_snapshot(
        &self,
        server_id: &str,
    ) -> Result<SshConnectionSnapshot, SshError> {
        let sender = self.ensure_state(server_id).await;
        let state = sender.borrow().clone();
        Ok(SshConnectionSnapshot {
            alias: server_id.to_string(),
            state,
        })
    }

    /// 订阅服务器连接状态；订阅本身不会建立连接。
    pub async fn subscribe_state(&self, server_id: &str) -> watch::Receiver<SshConnectionState> {
        self.ensure_state(server_id).await.subscribe()
    }

    pub fn subscribe_ready(&self) -> watch::Receiver<BTreeMap<String, u64>> {
        self.ready_revisions.subscribe()
    }

    /// 完成架构探测、helper bootstrap 与协议握手。
    pub async fn test_connection(
        &self,
        server_id: &str,
    ) -> Result<SshConnectionSnapshot, SshError> {
        self.connect_server(server_id).await?;
        self.connection_snapshot(server_id).await
    }

    /// Explicit Connect/open actions coalesce one in-flight initialization.
    pub async fn connect_server(&self, server_id: &str) -> Result<(), SshError> {
        let _admitted = self.admit_connection().await?;
        let control = self.control(server_id).await;
        let guard = tokio::select! {guard=control.lock_owned()=>guard,_=self.closing.cancelled()=>return Err(SshError::ManagerClosing)};
        if self
            .connections
            .lock()
            .await
            .get(server_id)
            .is_some_and(|connection| !connection.executor.is_closed())
        {
            return Ok(());
        }
        let intent = self
            .desired_connections
            .write()
            .await
            .entry(server_id.into())
            .or_default()
            .clone();
        let mut result = {
            let mut connecting = self.connecting.lock().await;
            if let Some(attempt) = connecting.get(server_id) {
                attempt.result.clone()
            } else {
                let (send, receive) = watch::channel(None);
                connecting.insert(
                    server_id.into(),
                    ConnectionAttempt {
                        intent: intent.clone(),
                        result: receive.clone(),
                    },
                );
                let manager = self.clone();
                let alias = server_id.to_owned();
                let intent = intent.clone();
                self.operations.spawn(async move {
                    let result = manager.connect_once(&alias, intent).await;
                    manager.connecting.lock().await.remove(&alias);
                    send.send_replace(Some(result));
                });
                receive
            }
        };
        drop(guard);
        tokio::select! {
            _=self.closing.cancelled()=>Err(SshError::ManagerClosing),
            _=intent.cancelled.cancelled()=>Err(SshError::Cancelled),
            result=result.wait_for(Option::is_some)=>result.map_err(|_|SshError::Disconnected)?.as_ref().cloned().unwrap_or(Err(SshError::Disconnected)),
        }
    }
    async fn set_intent_state(
        &self,
        alias: &str,
        intent: &Arc<ConnectionIntent>,
        state: SshConnectionState,
    ) {
        let desired = self.desired_connections.read().await;
        if desired
            .get(alias)
            .is_some_and(|current| Arc::ptr_eq(current, intent))
            && !intent.cancelled.is_cancelled()
        {
            self.ensure_state(alias).await.send_replace(state);
        }
    }
    async fn control(&self, alias: &str) -> ServerControl {
        self.controls
            .lock()
            .await
            .entry(alias.into())
            .or_default()
            .clone()
    }
    pub async fn disconnect_server(&self, alias: &str) -> Result<(), SshError> {
        let _guard = self.control(alias).await.lock_owned().await;
        self.disconnect_server_inner(alias).await
    }
    async fn disconnect_server_inner(&self, alias: &str) -> Result<(), SshError> {
        if let Some(intent) = self.desired_connections.write().await.remove(alias) {
            intent.cancelled.cancel();
        }
        let attempt = self.connecting.lock().await.get(alias).cloned();
        if let Some(attempt) = attempt {
            attempt.intent.cancelled.cancel();
            let mut result = attempt.result;
            let _ = result.wait_for(Option::is_some).await;
        }
        self.set_state(alias, SshConnectionState::Closing).await;
        let cursors: Vec<_> = self
            .directories
            .lock()
            .await
            .iter()
            .filter(|(_, cursor)| cursor.alias == alias)
            .map(|(key, _)| key.clone())
            .collect();
        for key in cursors {
            self.close_directory(alias, key).await?;
        }
        let connection = self.connections.lock().await.get(alias).cloned();
        if let Some(connection) = connection {
            self.close_owned_connection(alias, connection).await?;
        }
        self.set_state(alias, SshConnectionState::Disconnected)
            .await;
        Ok(())
    }
    /// The button creates a fresh server; old handles remain closed.
    pub async fn reconnect_server(&self, alias: &str) -> Result<(), SshError> {
        self.disconnect_server(alias).await?;
        self.connect_server(alias).await
    }
    async fn active_connection(&self, alias: &str) -> Result<Arc<SshConnection>, SshError> {
        self.connections
            .lock()
            .await
            .get(alias)
            .cloned()
            .filter(|connection| !connection.executor.is_closed())
            .ok_or(SshError::Disconnected)
    }
    pub async fn open_workspace(
        &self,
        alias: &str,
        path: String,
    ) -> Result<ExecutorWorkspaceFileBackend, SshError> {
        Ok(self.open_workspace_host(alias, path).await?.files)
    }
    pub async fn open_workspace_host(
        &self,
        alias: &str,
        path: String,
    ) -> Result<RemoteWorkspaceHost, SshError> {
        let _admitted = self.admit_connection().await?;
        self.connect_server(alias).await?;
        let connection = self.active_connection(alias).await?;
        self.workspace_host(connection, path).await
    }
    pub async fn open_workspace_host_on_connection(
        &self,
        alias: &str,
        frozen: &ExecutorWorkspaceFileBackend,
        path: String,
    ) -> Result<RemoteWorkspaceHost, SshError> {
        let _admitted = self.admit_connection().await?;
        let connection = self.active_connection(alias).await?;
        if frozen.executor().id() != connection.executor.id() {
            return Err(SshError::Disconnected);
        }
        self.workspace_host(connection, path).await
    }
    async fn workspace_host(
        &self,
        connection: Arc<SshConnection>,
        path: String,
    ) -> Result<RemoteWorkspaceHost, SshError> {
        let executor = connection.executor.clone();
        let root = executor.path(&path)?;
        let root = executor.fs().canonicalize(&root).await?;
        if !executor
            .fs()
            .metadata(&root)
            .await?
            .is_some_and(|metadata| metadata.is_dir)
        {
            return Err(SshError::Protocol(
                "workspace root is not a directory".into(),
            ));
        }
        let environment = execution_environment(executor.target_info())?;
        Ok(RemoteWorkspaceHost {
            profile: connection.profile.clone(),
            files: ExecutorWorkspaceFileBackend::new(executor.clone(), root.as_str())?,
            commands: crate::command::ExecutorCommandBackend::new(
                executor.clone(),
                root.as_str(),
                environment.clone(),
            )?,
            git: crate::execution::ExecutorExecutionBackend::new(executor),
            execution_environment: environment,
        })
    }
    pub async fn browse_directories(
        &self,
        alias: &str,
        path: Option<String>,
        cursor: Option<String>,
    ) -> Result<pl_protocol::remote::RemoteDirectoryListing, SshError> {
        let _admitted = self.admit_connection().await?;
        let (key, state) = if let Some(key) = cursor {
            let state = self
                .directories
                .lock()
                .await
                .get(&key)
                .cloned()
                .ok_or_else(|| SshError::Protocol("directory cursor is closed".into()))?;
            let active = self.active_connection(alias).await?;
            if state.alias != alias
                || state.executor != active.executor.id()
                || path.as_ref().is_some_and(|path| path != &state.path)
            {
                return Err(SshError::Protocol(
                    "directory cursor belongs to another connection or path".into(),
                ));
            }
            (key, state)
        } else {
            self.connect_server(alias).await?;
            let connection = self.active_connection(alias).await?;
            let path = path
                .or_else(|| connection.executor.target_info().home.clone())
                .unwrap_or_else(|| connection.executor.target_info().initial_directory.clone());
            let target = connection
                .executor
                .fs()
                .canonicalize(&connection.executor.path(path)?)
                .await?;
            let reader = connection.executor.fs().read_dir(&target).await?;
            static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
            let key = format!(
                "directory-{}",
                NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
            );
            let state = Arc::new(BrowseCursor {
                alias: alias.into(),
                executor: connection.executor.id(),
                path: target.as_str().into(),
                parent: connection
                    .executor
                    .parent_path(&target)?
                    .map(|path| path.as_str().into()),
                reader: Mutex::new(BrowseReader {
                    reader: Some(reader),
                    pending: None,
                }),
                stop: CancellationToken::new(),
            });
            self.directories
                .lock()
                .await
                .insert(key.clone(), state.clone());
            (key, state)
        };
        let work = async {
            let mut held = state.reader.lock().await;
            let mut entries = Vec::new();
            loop {
                let entry = match held.pending.take() {
                    Some(entry) => Some(entry),
                    None => match held.reader.as_mut() {
                        Some(reader) => reader.next().await?,
                        None => return Err(SshError::Cancelled),
                    },
                };
                let Some(entry) = entry else {
                    return Ok((entries, false));
                };
                if !entry.is_dir {
                    continue;
                }
                if entries.len() == 128 {
                    held.pending = Some(entry);
                    return Ok((entries, true));
                }
                entries.push(pl_protocol::remote::RemoteDirectoryEntry {
                    name: entry.name,
                    path: entry.path,
                    is_directory: true,
                    is_symlink: entry.is_symlink,
                });
            }
        };
        let result = tokio::select! {result=work=>result,_=state.stop.cancelled()=>Err(SshError::Cancelled),_=self.closing.cancelled()=>Err(SshError::ManagerClosing)};
        let (mut entries, more) = match result {
            Ok(result) => result,
            Err(error) => {
                self.close_directory(alias, key).await?;
                return Err(error);
            }
        };
        entries.sort_by(|left, right| left.name.cmp(&right.name));
        let next_cursor = if more {
            Some(key)
        } else {
            self.close_directory(alias, key).await?;
            None
        };
        Ok(pl_protocol::remote::RemoteDirectoryListing {
            parent: state.parent.clone(),
            path: state.path.clone(),
            entries,
            next_cursor,
        })
    }
    pub async fn close_directory(&self, alias: &str, key: String) -> Result<(), SshError> {
        let cursor = {
            let mut cursors = self.directories.lock().await;
            if cursors
                .get(&key)
                .is_some_and(|cursor| cursor.alias != alias)
            {
                return Err(SshError::Protocol(
                    "directory cursor belongs to another server".into(),
                ));
            }
            cursors.remove(&key)
        };
        if let Some(cursor) = cursor {
            cursor.stop.cancel();
            let mut held = cursor.reader.lock().await;
            held.reader.take();
            held.pending.take();
        }
        Ok(())
    }
    async fn profile(&self, alias: &str) -> Result<SshServerProfile, SshError> {
        self.servers
            .read()
            .await
            .get(alias)
            .map(|entry| entry.profile.clone())
            .ok_or_else(|| SshError::Protocol("SSH server is not configured".into()))
    }
    async fn ensure_state(&self, alias: &str) -> watch::Sender<SshConnectionState> {
        self.states
            .write()
            .await
            .entry(alias.into())
            .or_insert_with(|| watch::channel(SshConnectionState::Disconnected).0)
            .clone()
    }
    async fn set_state(&self, alias: &str, state: SshConnectionState) {
        self.ensure_state(alias).await.send_replace(state);
    }
}
fn execution_environment(
    info: &pl_remote_helper::TargetInfo,
) -> Result<crate::environment::ExecutionEnvironment, SshError> {
    use crate::environment::{ExecutionEnvironment, ExecutionOs, ShellDialect};
    if info.os != "linux" {
        return Err(SshError::Protocol("SSH target must be Linux".into()));
    }
    let shell = info
        .shell
        .as_deref()
        .ok_or_else(|| SshError::Protocol("target shell is unavailable".into()))?;
    let dialect = match shell.rsplit('/').next() {
        Some("bash") => ShellDialect::Bash,
        Some("sh" | "dash" | "ash") => ShellDialect::Sh,
        _ => {
            return Err(SshError::Protocol(
                "unsupported target command shell".into(),
            ));
        }
    };
    Ok(ExecutionEnvironment::for_ssh(
        ExecutionOs::Linux,
        dialect,
        shell,
    ))
}
