//! 系统 OpenSSH 连接、重连与 remote workspace handle 的本地 owner。

mod asset;
mod connection;
mod shutdown;
mod ssh;

use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;

use pl_protocol::remote::{
    REMOTE_PROTOCOL_VERSION, RemoteDirectoryListing, RemoteHello, RemoteRequest, RemoteResponse,
};
use process_wrap::tokio::ChildWrapper;
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, RwLock, watch};
use tokio_util::sync::CancellationToken;
use tokio_util::task::TaskTracker;

use super::{
    RemoteClient, RemoteClientError, RemoteCommandBackend, RemoteExecutionBackend,
    RemoteWorkspaceFileBackend, RemoteWorkspaceHost, normalize_remote_absolute_path,
};
use crate::environment::{ExecutionEnvironment, ExecutionOs, ShellDialect};
use pl_protocol::remote::RemoteShellDialect;

pub use self::asset::{RemoteHelperAssets, RemoteHelperTarget};
use self::asset::{file_helper_assets, load_helper, upload_helper};
use self::ssh::{run_ssh_capture, ssh_command, validate_profile};
use super::ssh_config::{SshConfigEntry, SshConfigFile};

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
    Reconnecting {
        attempt: u32,
        delay_seconds: u64,
    },
    Failed {
        code: String,
        message: String,
    },
}

struct SshConnection {
    client: RemoteClient,
    process: Arc<Mutex<Box<dyn ChildWrapper>>>,
    heartbeat: CancellationToken,
    execution_environment: ExecutionEnvironment,
    remote_path: String,
}

impl std::fmt::Debug for SshConnection {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("SshConnection")
            .field("client", &self.client)
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Default)]
struct SshPasswordStore(Arc<RwLock<HashMap<String, String>>>);

impl std::fmt::Debug for SshPasswordStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("SshPasswordStore(..)")
    }
}

#[derive(Debug, Default)]
struct ConnectionIntent {
    cancelled: CancellationToken,
}
#[derive(Debug, Clone)]
struct ConnectionAttempt {
    intent: Arc<ConnectionIntent>,
    result: watch::Receiver<Option<Result<(), RemoteClientError>>>,
}

type WorkspaceOpening = Result<
    (
        Arc<super::client::workspace::WorkspaceLease>,
        ExecutionEnvironment,
    ),
    RemoteClientError,
>;

type RetiredConnections = Vec<(String, Arc<SshConnection>)>;

type WorkspaceAttempts =
    Mutex<HashMap<(String, String), watch::Receiver<Option<WorkspaceOpening>>>>;

/// 系统 OpenSSH、helper bootstrap、远端 workspace 与自动重连的本地 owner。
#[derive(Debug, Clone)]
pub struct SshManager {
    servers: Arc<RwLock<HashMap<String, SshConfigEntry>>>,
    passwords: SshPasswordStore,
    ssh_config: SshConfigFile,
    helper_assets: Option<Arc<dyn RemoteHelperAssets>>,
    connections: Arc<Mutex<HashMap<String, Arc<SshConnection>>>>,
    admission: Arc<Mutex<bool>>,
    closing: CancellationToken,
    operations: TaskTracker,
    connecting: Arc<Mutex<HashMap<String, ConnectionAttempt>>>,
    opening_workspaces: Arc<WorkspaceAttempts>,
    resource_policy: pl_remote_helper::budget::ResourcePolicy,
    budget: Arc<tokio::sync::OnceCell<pl_remote_helper::budget::ResourceBudget>>,
    workspaces: Arc<super::client::workspace::WorkspaceCache>,
    states: Arc<RwLock<HashMap<String, watch::Sender<SshConnectionState>>>>,
    ready_revisions: watch::Sender<BTreeMap<String, u64>>,
    desired_connections: Arc<RwLock<HashMap<String, Arc<ConnectionIntent>>>>,
    retired_connections: Arc<Mutex<RetiredConnections>>,
}

struct BrowseCursor {
    client: RemoteClient,
    cursor: Option<String>,
}
impl Drop for BrowseCursor {
    fn drop(&mut self) {
        if let Some(cursor) = self.cursor.take() {
            self.client
                .release_resource(RemoteRequest::CloseDirectory { cursor });
        }
    }
}

impl SshManager {
    /// 使用可选的开发 helper 资产创建 manager。
    ///
    /// 每个资产仍必须带有相邻的 `.sha256` 文件；生产环境应使用
    /// [`Self::with_helper_assets`] 提供随应用分发的按需解压资产。
    pub fn new(aarch64_helper: Option<PathBuf>, x86_64_helper: Option<PathBuf>) -> Self {
        Self::with_optional_helper_assets(file_helper_assets(aarch64_helper, x86_64_helper))
    }

    /// 使用宿主提供的按需解压资产创建 manager。
    pub fn with_helper_assets(helper_assets: Arc<dyn RemoteHelperAssets>) -> Self {
        Self::with_optional_helper_assets(Some(helper_assets))
    }

    /// 显式指定 ssh config 文件；默认使用用户 `~/.ssh/config`。
    ///
    /// 测试与启动协调器用它隔离或收敛配置写入范围。
    pub fn with_ssh_config(mut self, ssh_config: SshConfigFile) -> Self {
        self.ssh_config = ssh_config;
        self
    }

    /// Host-wide memory policy shared by every helper; set before opening connections.
    pub fn with_resource_policy(
        mut self,
        policy: pl_remote_helper::budget::ResourcePolicy,
    ) -> Self {
        self.resource_policy = policy;
        self
    }

    fn with_optional_helper_assets(helper_assets: Option<Arc<dyn RemoteHelperAssets>>) -> Self {
        Self {
            servers: Arc::new(RwLock::new(HashMap::new())),
            passwords: SshPasswordStore::default(),
            ssh_config: SshConfigFile::user_default().unwrap_or_else(|error| {
                tracing::warn!(%error, "falling back to the default ssh config location");
                SshConfigFile::default_location(".ssh/config")
            }),
            helper_assets,
            connections: Arc::new(Mutex::new(HashMap::new())),
            admission: Arc::new(Mutex::new(true)),
            closing: CancellationToken::new(),
            operations: TaskTracker::new(),
            resource_policy: Default::default(),
            connecting: Default::default(),
            opening_workspaces: Default::default(),
            budget: Default::default(),
            workspaces: Default::default(),
            states: Arc::new(RwLock::new(HashMap::new())),
            ready_revisions: watch::channel(BTreeMap::new()).0,
            desired_connections: Default::default(),
            retired_connections: Default::default(),
        }
    }

    /// 更新或清除指定服务器别名在当前进程内的 SSH 密码租约。
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
    pub async fn reload_servers(&self) -> Result<(), RemoteClientError> {
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
    ) -> Result<SshServerProfile, RemoteClientError> {
        validate_profile(&profile)?;
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
            self.disconnect_server(&profile.alias).await?;
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
    pub async fn delete_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        self.ssh_config.remove_managed(server_id).await?;
        self.disconnect_server(server_id).await?;
        self.passwords.0.write().await.remove(server_id);
        self.servers.write().await.remove(server_id);
        self.states.write().await.remove(server_id);
        self.workspaces
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .retain(|(id, _), _| id != server_id);
        Ok(())
    }

    /// 读取服务器的 canonical 连接状态。
    pub async fn connection_snapshot(
        &self,
        server_id: &str,
    ) -> Result<SshConnectionSnapshot, RemoteClientError> {
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

    /// Subscribes to completed connections, including automatic reconnections.
    ///
    /// Revisions are local to this manager and retained across disconnects. Consumers
    /// must compare revisions, since multiple connections can complete between reads.
    /// Subscribing does not connect and carries no credentials or remote environment.
    pub fn subscribe_ready(&self) -> watch::Receiver<BTreeMap<String, u64>> {
        self.ready_revisions.subscribe()
    }

    /// 完成架构探测、helper bootstrap 与协议握手。
    pub async fn test_connection(
        &self,
        server_id: &str,
    ) -> Result<SshConnectionSnapshot, RemoteClientError> {
        self.connect_server(server_id).await?;
        self.connection_snapshot(server_id).await
    }

    /// Shares one in-flight connection attempt; ordinary requests never take this gate.
    pub async fn connect_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        let _operation = self.admit_connection().await?;
        let intent = self
            .desired_connections
            .write()
            .await
            .entry(server_id.to_owned())
            .or_insert_with(|| Arc::new(ConnectionIntent::default()))
            .clone();
        self.connect_for_intent(server_id, intent).await
    }

    async fn connect_for_intent(
        &self,
        server_id: &str,
        intent: Arc<ConnectionIntent>,
    ) -> Result<(), RemoteClientError> {
        loop {
            if self.closing.is_cancelled() {
                return Err(RemoteClientError::ManagerClosing);
            }
            if intent.cancelled.is_cancelled() {
                return Err(RemoteClientError::Cancelled);
            }
            let ready = self
                .connections
                .lock()
                .await
                .get(server_id)
                .cloned()
                .filter(|connection| !connection.client.is_disconnected());
            if let Some(connection) = ready {
                if let Some(hello) = connection.client.hello() {
                    self.set_intent_state(
                        server_id,
                        &intent,
                        SshConnectionState::Ready {
                            helper_version: hello.helper_version,
                            architecture: hello.architecture,
                        },
                    )
                    .await;
                }
                return Ok(());
            }
            let (mut result, same_intent) = {
                let mut connecting = self.connecting.lock().await;
                if intent.cancelled.is_cancelled() {
                    return Err(RemoteClientError::Cancelled);
                }
                if let Some(attempt) = connecting.get(server_id) {
                    (
                        attempt.result.clone(),
                        Arc::ptr_eq(&attempt.intent, &intent),
                    )
                } else {
                    let (report, result) = watch::channel(None);
                    connecting.insert(
                        server_id.to_owned(),
                        ConnectionAttempt {
                            intent: intent.clone(),
                            result: result.clone(),
                        },
                    );
                    let manager = self.clone();
                    let alias = server_id.to_owned();
                    let attempt_intent = intent.clone();
                    self.operations.spawn(async move {
                        let outcome = manager.connect_once(&alias, attempt_intent).await;
                        // Remove before waking waiters so a replacement cannot spin on a completed slot.
                        manager.connecting.lock().await.remove(&alias);
                        report.send_replace(Some(outcome));
                    });
                    (result, true)
                }
            };
            let outcome = tokio::select! {
                _ = self.closing.cancelled() => return Err(RemoteClientError::ManagerClosing),
                _ = intent.cancelled.cancelled() => return Err(RemoteClientError::Cancelled),
                result = result.wait_for(Option::is_some) => result.map_err(|_| RemoteClientError::Disconnected)?
                    .as_ref().cloned().unwrap_or(Err(RemoteClientError::Disconnected)),
            };
            if same_intent {
                return outcome;
            }
            // A superseded owner has now finished cleanup; the new intent may create its attempt.
        }
    }

    async fn set_intent_state(
        &self,
        alias: &str,
        intent: &Arc<ConnectionIntent>,
        state: SshConnectionState,
    ) {
        let sender = self.ensure_state(alias).await;
        let desired = self.desired_connections.read().await;
        if !intent.cancelled.is_cancelled()
            && desired
                .get(alias)
                .is_some_and(|current| Arc::ptr_eq(current, intent))
        {
            sender.send_if_modified(|current| {
                if *current == state {
                    false
                } else {
                    *current = state;
                    true
                }
            });
        }
    }

    /// Cancels this alias's connection intent and joins its current and in-flight owners.
    pub async fn disconnect_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        let _operation = self.admit_connection().await?;
        let (connection, attempt) = {
            let mut desired = self.desired_connections.write().await;
            if let Some(intent) = desired.remove(server_id) {
                intent.cancelled.cancel();
            }
            let connection = self.connections.lock().await.get(server_id).cloned();
            if let Some(connection) = &connection {
                connection.client.begin_close();
                connection.heartbeat.cancel();
            }
            let attempt = self
                .connecting
                .lock()
                .await
                .get(server_id)
                .map(|attempt| attempt.result.clone());
            (connection, attempt)
        };
        let close = async {
            match connection {
                Some(connection) => self.close_owned_connection(server_id, connection).await,
                None => Ok(()),
            }
        };
        let joining = async {
            if let Some(mut attempt) = attempt {
                let outcome = attempt
                    .wait_for(Option::is_some)
                    .await
                    .map_err(|_| RemoteClientError::Disconnected)?
                    .as_ref()
                    .cloned()
                    .unwrap_or(Err(RemoteClientError::Disconnected));
                match outcome {
                    Ok(()) | Err(RemoteClientError::Cancelled) => {}
                    Err(error) => return Err(error),
                }
            }
            Ok(())
        };
        let (close, joining) = tokio::join!(close, joining);
        close?;
        joining?;
        let sender = self.ensure_state(server_id).await;
        let desired = self.desired_connections.read().await;
        if !desired.contains_key(server_id) {
            sender.send_replace(SshConnectionState::Disconnected);
        }
        Ok(())
    }

    /// Replaces the transport while retaining this alias's existing connection intent.
    pub async fn reconnect_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        let _operation = self.admit_connection().await?;
        let intent = self
            .desired_connections
            .write()
            .await
            .entry(server_id.to_owned())
            .or_insert_with(|| Arc::new(ConnectionIntent::default()))
            .clone();
        let connection = self.connections.lock().await.get(server_id).cloned();
        if let Some(connection) = connection {
            connection.heartbeat.cancel();
            connection.client.detach().await?;
        }
        self.connect_for_intent(server_id, intent).await
    }

    /// 浏览远端目录；该功能只用于宿主 UI，不注册给模型。
    pub async fn browse_directories(
        &self,
        server_id: &str,
        path: Option<String>,
        cursor: Option<String>,
    ) -> Result<RemoteDirectoryListing, RemoteClientError> {
        let _operation = self.admit_connection().await?;
        let client = self.client(server_id).await?;
        let continuing = cursor.is_some();
        let mut guard = BrowseCursor {
            client: client.clone(),
            cursor,
        };
        loop {
            let request = match guard.cursor.clone() {
                Some(cursor) => RemoteRequest::ContinueDirectory { cursor },
                None => RemoteRequest::BrowseDirectories { path: path.clone() },
            };
            let reply = tokio::select! {
                _ = self.closing.cancelled() => return Err(RemoteClientError::ManagerClosing),
                reply = client.request(request, &[]) => reply?,
            };
            let mut listing = match reply.response {
                RemoteResponse::Directory(listing) | RemoteResponse::Directories(listing) => {
                    listing
                }
                _ => {
                    return Err(RemoteClientError::Protocol(
                        "unexpected directory response".into(),
                    ));
                }
            };
            guard.cursor = listing.next_cursor.clone();
            if continuing && path.as_ref().is_some_and(|path| path != &listing.path) {
                return Err(RemoteClientError::Protocol(
                    "directory cursor does not match requested path".into(),
                ));
            }
            // Selection and presentation policy belongs to the host. The helper returns a raw
            // single-level page, also used by file tools, Skill discovery and recursive traversal.
            listing.entries.retain(|entry| entry.is_directory);
            listing
                .entries
                .sort_by(|left, right| left.name.cmp(&right.name));
            if listing.entries.is_empty() && listing.next_cursor.is_some() {
                continue;
            }
            guard.cursor = None;
            return Ok(listing);
        }
    }
    pub async fn close_directory(
        &self,
        server_id: &str,
        cursor: String,
    ) -> Result<(), RemoteClientError> {
        let connection = self.connections.lock().await.get(server_id).cloned();
        if let Some(connection) = connection {
            connection
                .client
                .request(RemoteRequest::CloseDirectory { cursor }, &[])
                .await?;
        }
        Ok(())
    }

    /// 打开远端 workspace 并返回文件 backend。
    pub async fn open_workspace(
        &self,
        server_id: &str,
        path: String,
    ) -> Result<RemoteWorkspaceFileBackend, RemoteClientError> {
        Ok(self.open_workspace_host(server_id, path).await?.files)
    }

    /// 打开或复用远端 workspace 的完整本地 backend 集合。
    pub async fn open_workspace_host(
        &self,
        server_id: &str,
        path: String,
    ) -> Result<RemoteWorkspaceHost, RemoteClientError> {
        // 跨端入口统一归一化为 POSIX：宿主形态（含 Windows 分隔符）的同一远端目录必须
        // 映射到同一个缓存键与同一个 helper workspace，不得因 canonicalize 失败或重复
        // 打开而产生两个 workspace handle。缓存键语义保持既有形状（请求路径用于查找、
        // helper canonical 路径用于存放）。
        let path = normalize_remote_absolute_path(&path)
            .map_err(|error| RemoteClientError::Protocol(error.to_string()))?;
        let _operation = self.admit_connection().await?;
        let client = self.client(server_id).await?;
        // Keep transport, workspace and environment from one connection, even if
        // reconnect raced the initial lookup. Never publish a mixed-generation host.
        let connection = self
            .connections
            .lock()
            .await
            .get(server_id)
            .cloned()
            .filter(|connection| {
                connection.client.is_same_connection(&client) && !client.is_disconnected()
            })
            .ok_or(RemoteClientError::Disconnected)?;
        let cached = {
            let cache = self
                .workspaces
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            cache
                .get(&(server_id.to_string(), path.clone()))
                .and_then(|entry| Some((entry.lease.upgrade()?, entry.environment.clone())))
        }
        .filter(|(lease, _)| lease.is_connection(&client));
        let (lease, execution_environment) = match cached {
            Some(cached) => cached,
            None => {
                let key = (server_id.to_owned(), path.clone());
                let mut opening = {
                    let mut openings = self.opening_workspaces.lock().await;
                    if let Some(opening) = openings.get(&key) {
                        opening.clone()
                    } else {
                        let (report, receiver) = watch::channel(None);
                        openings.insert(key.clone(), receiver.clone());
                        let manager = self.clone();
                        let client = client.clone();
                        let environment = connection.execution_environment.clone();
                        self.operations.spawn(async move {
                            let result = tokio::time::timeout(
                                std::time::Duration::from_secs(15),
                                client.open_workspace_lease(
                                    path,
                                    key.0.clone(),
                                    manager.workspaces.clone(),
                                ),
                            )
                            .await
                            .map_err(|_| {
                                RemoteClientError::Protocol("SSH workspace open timed out".into())
                            })
                            .and_then(|v| v)
                            .map(|lease| (lease, environment));
                            if let Ok((lease, environment)) = &result {
                                manager
                                    .workspaces
                                    .lock()
                                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                                    .insert(
                                        (key.0.clone(), lease.path.clone()),
                                        super::client::workspace::CachedWorkspace {
                                            lease: Arc::downgrade(lease),
                                            environment: environment.clone(),
                                        },
                                    );
                            }
                            // Publish the weak cache before releasing single-flight registration.
                            // A new caller cannot slip between removal and cache publication.
                            manager.opening_workspaces.lock().await.remove(&key);
                            report.send_replace(Some(result));
                        });
                        receiver
                    }
                };
                let (lease, _) = opening
                    .wait_for(Option::is_some)
                    .await
                    .map_err(|_| RemoteClientError::Disconnected)?
                    .as_ref()
                    .cloned()
                    .ok_or(RemoteClientError::Disconnected)??;
                // One result is published, then its producer closes. Join that close so the
                // completed attempt cannot retain the last strong lease after our caller drops it.
                while opening.changed().await.is_ok() {}
                let environment = connection.execution_environment.clone();
                (lease, environment)
            }
        };
        Ok(RemoteWorkspaceHost {
            files: RemoteWorkspaceFileBackend::new(client.clone(), lease.clone()),
            commands: RemoteCommandBackend::new(client.clone(), lease.clone()),
            git: RemoteExecutionBackend::new(client, lease),
            execution_environment,
        })
    }

    async fn client(&self, server_id: &str) -> Result<RemoteClient, RemoteClientError> {
        self.connect_server(server_id).await?;
        self.connections
            .lock()
            .await
            .get(server_id)
            .map(|connection| connection.client.clone())
            .ok_or(RemoteClientError::Disconnected)
    }

    async fn profile(&self, server_id: &str) -> Result<SshServerProfile, RemoteClientError> {
        self.servers
            .read()
            .await
            .get(server_id)
            .map(|entry| entry.profile.clone())
            .ok_or_else(|| RemoteClientError::Protocol(format!("unknown SSH server '{server_id}'")))
    }

    async fn ensure_state(&self, server_id: &str) -> watch::Sender<SshConnectionState> {
        if let Some(sender) = self.states.read().await.get(server_id).cloned() {
            return sender;
        }
        let mut states = self.states.write().await;
        states
            .entry(server_id.to_string())
            .or_insert_with(|| watch::channel(SshConnectionState::Disconnected).0)
            .clone()
    }

    async fn set_state(&self, server_id: &str, state: SshConnectionState) {
        self.ensure_state(server_id)
            .await
            .send_if_modified(|current| {
                if *current == state {
                    false
                } else {
                    *current = state;
                    true
                }
            });
    }

    fn spawn_disconnect_monitor(
        &self,
        server_id: String,
        client: RemoteClient,
        intent: Arc<ConnectionIntent>,
    ) {
        let manager = self.clone();
        let generation = client.generation();
        // The admitting connect operation is still tracked while this task is added.
        self.operations.spawn(async move {
            tokio::select! {
                biased;
                _ = manager.closing.cancelled() => return,
                _ = client.wait_disconnected() => {},
            }
            if client.generation() != generation { return; }
            tracing::warn!(%server_id, reason = ?client.disconnect_reason(), "SSH transport disconnected");
            if manager.closing.is_cancelled() || intent.cancelled.is_cancelled() { return; }
            manager.reconnect_with_backoff(server_id, intent).await;
        });
    }

    fn spawn_heartbeat(
        &self,
        server_id: String,
        client: RemoteClient,
        cancelled: CancellationToken,
    ) {
        let closing = self.closing.clone();
        self.operations.spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(5));
            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            loop {
                tokio::select! {
                    biased;
                    () = closing.cancelled() => break,
                    () = cancelled.cancelled() => break,
                    () = client.wait_disconnected() => break,
                    _ = interval.tick() => {}
                }
                let result = tokio::select! {
                    biased;
                    () = closing.cancelled() => break,
                    () = cancelled.cancelled() => break,
                    // Require a helper response, not merely a successful local pipe write.
                    result = client.heartbeat() => result,
                };
                if result.is_err() {
                    tracing::warn!(%server_id, "SSH heartbeat failed; closing transport");
                    let _ = client.detach().await;
                    break;
                }
            }
        });
    }

    async fn reconnect_with_backoff(&self, server_id: String, intent: Arc<ConnectionIntent>) {
        const DELAYS: [u64; 6] = [1, 2, 4, 8, 15, 30];
        let mut attempt = 0_u32;
        loop {
            if self
                .connections
                .lock()
                .await
                .get(&server_id)
                .is_some_and(|connection| !connection.client.is_disconnected())
            {
                return;
            }
            if intent.cancelled.is_cancelled() {
                return;
            }
            attempt = attempt.saturating_add(1);
            let delay_seconds = DELAYS[(attempt as usize - 1).min(DELAYS.len() - 1)];
            self.set_intent_state(
                &server_id,
                &intent,
                SshConnectionState::Reconnecting {
                    attempt,
                    delay_seconds,
                },
            )
            .await;
            tokio::select! {
                biased;
                _ = self.closing.cancelled() => return,
                _ = intent.cancelled.cancelled() => return,
                _ = tokio::time::sleep(std::time::Duration::from_secs(delay_seconds)) => {},
            }
            match self.connect_for_intent(&server_id, intent.clone()).await {
                Ok(()) => return,
                Err(RemoteClientError::ManagerClosing | RemoteClientError::Cancelled) => return,
                Err(_) => {}
            }
        }
    }
}

pub(super) fn execution_environment_from_hello(
    hello: &RemoteHello,
) -> Result<ExecutionEnvironment, RemoteClientError> {
    let os = match hello.os.to_ascii_lowercase().as_str() {
        "windows" => ExecutionOs::Windows,
        "linux" => ExecutionOs::Linux,
        "macos" | "darwin" => ExecutionOs::Macos,
        value => ExecutionOs::Other(value.to_string()),
    };
    let shell = match hello.shell.dialect {
        RemoteShellDialect::Bash => ShellDialect::Bash,
        RemoteShellDialect::Sh => ShellDialect::Sh,
        RemoteShellDialect::Pwsh => ShellDialect::Pwsh,
        RemoteShellDialect::PowerShell => ShellDialect::PowerShell,
        RemoteShellDialect::Cmd => ShellDialect::Cmd,
    };
    if hello.shell.path.trim().is_empty() {
        return Err(RemoteClientError::Protocol(
            "helper hello returned an empty shell path".to_string(),
        ));
    }
    Ok(ExecutionEnvironment::for_ssh(
        os,
        shell,
        hello.shell.path.clone(),
    ))
}
