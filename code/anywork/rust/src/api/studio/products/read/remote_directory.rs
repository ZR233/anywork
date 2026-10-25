//! One native Remote page per scope; no directory rescan from local offsets.
use super::super::identity::*;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::{BridgeReadText, BridgeTextChunk};
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_protocol::products::read::remote_directory as protocol;
use pl_studio_runtime::remote_directory::StudioRemoteDirectoryRead;
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRemoteDirectoryReadHeader {
    pub scope_id: String,
    pub path: BridgeReadText,
    pub parent: Option<BridgeReadText>,
    pub next_cursor: Option<BridgeReadText>,
    pub page_entry_count: u64,
}

impl From<protocol::RemoteDirectoryReadHeader> for BridgeRemoteDirectoryReadHeader {
    fn from(value: protocol::RemoteDirectoryReadHeader) -> Self {
        Self {
            scope_id: value.scope_id,
            path: value.path.into(),
            parent: value.parent.map(Into::into),
            next_cursor: value.next_cursor.map(Into::into),
            page_entry_count: value.page_entry_count,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRemoteDirectoryEntryRead {
    pub name: BridgeReadText,
    pub path: BridgeReadText,
    pub is_directory: bool,
    pub is_symlink: bool,
}

impl From<protocol::RemoteDirectoryEntryRead> for BridgeRemoteDirectoryEntryRead {
    fn from(value: protocol::RemoteDirectoryEntryRead) -> Self {
        Self {
            name: value.name.into(),
            path: value.path.into(),
            is_directory: value.is_directory,
            is_symlink: value.is_symlink,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRemoteDirectoryEntryPage {
    pub scope_id: String,
    pub offset: u64,
    pub items: Vec<BridgeRemoteDirectoryEntryRead>,
    pub next_offset: Option<u64>,
}

impl From<protocol::RemoteDirectoryEntryPage> for BridgeRemoteDirectoryEntryPage {
    fn from(value: protocol::RemoteDirectoryEntryPage) -> Self {
        Self {
            scope_id: value.scope_id,
            offset: value.offset,
            items: value.items.into_iter().map(Into::into).collect(),
            next_offset: value.next_offset,
        }
    }
}
impl ModelsRead for StudioRemoteDirectoryRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
        StudioRemoteDirectoryRead::identity(self)
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        StudioRemoteDirectoryRead::ensure_open(self)
    }
    fn request_close(&self) {
        StudioRemoteDirectoryRead::request_close(self);
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        StudioRemoteDirectoryRead::close(self)
    }
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeRemoteDirectoryReadConnection {
    read: ModelsReadHandle<StudioRemoteDirectoryRead>,
}
impl BridgeRemoteDirectoryReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeRemoteDirectoryReadHeader, BridgeError> {
        let query = self.read.query(move |source| source.header())?;
        Ok(query.await?.into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeRemoteDirectoryEntryPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entries(offset, limit))?;
        Ok(query.await?.into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        let query = self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?;
        Ok(query.await?.into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.retry_close().await
    }
}
pub async fn open_directory(
    alias: String,
    path: Option<String>,
    cursor: Option<String>,
) -> Result<BridgeRemoteDirectoryReadConnection, BridgeError> {
    Ok(BridgeRemoteDirectoryReadConnection {
        read: open_read(move |runtime| runtime.open_directory(alias, path, cursor)).await?,
    })
}
pub async fn close_directory(alias: String, cursor: String) -> Result<(), BridgeError> {
    crate::api::studio::bridge_runtime::installed_bridge()?
        .studio
        .close_directory(alias, cursor)
        .await?;
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeSshConnectionState {
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
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSshConnectionSnapshot {
    pub alias: String,
    pub state: BridgeSshConnectionState,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSshServerProfile {
    pub alias: String,
    pub host_name: String,
    pub port: u16,
    pub username: String,
    pub identity_file: Option<String>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSshServerRuntimeEntry {
    pub profile: BridgeSshServerProfile,
    pub managed: bool,
    pub has_password: bool,
}
impl From<pl_studio_runtime::SshServerRuntimeEntry> for BridgeSshServerRuntimeEntry {
    fn from(value: pl_studio_runtime::SshServerRuntimeEntry) -> Self {
        Self {
            profile: BridgeSshServerProfile {
                alias: value.profile.alias,
                host_name: value.profile.host_name,
                port: value.profile.port,
                username: value.profile.username,
                identity_file: value.profile.identity_file,
            },
            managed: value.managed,
            has_password: value.has_password,
        }
    }
}

impl From<pl_studio_runtime::SshConnectionSnapshot> for BridgeSshConnectionSnapshot {
    fn from(value: pl_studio_runtime::SshConnectionSnapshot) -> Self {
        use pl_studio_runtime::SshConnectionState as State;
        let state = match value.state {
            State::Disconnected => BridgeSshConnectionState::Disconnected,
            State::Connecting => BridgeSshConnectionState::Connecting,
            State::Ready {
                helper_version,
                architecture,
            } => BridgeSshConnectionState::Ready {
                helper_version,
                architecture,
            },
            State::Reconnecting {
                attempt,
                delay_seconds,
            } => BridgeSshConnectionState::Reconnecting {
                attempt,
                delay_seconds,
            },
            State::Failed { code, message } => BridgeSshConnectionState::Failed { code, message },
        };
        Self {
            alias: value.alias,
            state,
        }
    }
}
pub async fn reload_servers() -> Result<Vec<BridgeSshServerRuntimeEntry>, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .list_ssh_servers()
        .await?
        .into_iter()
        .map(Into::into)
        .collect())
}
pub async fn save_server(
    profile: BridgeSshServerProfile,
    password: crate::api::studio::types::SshPasswordInput,
) -> Result<BridgeSshServerRuntimeEntry, BridgeError> {
    use crate::api::studio::types::SshPasswordInput;
    let password = match password {
        SshPasswordInput::Preserve => pl_studio_runtime::SshPasswordUpdate::Preserve,
        SshPasswordInput::Replace { value } => {
            pl_studio_runtime::SshPasswordUpdate::Replace { value }
        }
        SshPasswordInput::Clear => pl_studio_runtime::SshPasswordUpdate::Clear,
    };
    let profile = pl_studio_runtime::SshServerProfile {
        alias: profile.alias,
        host_name: profile.host_name,
        port: profile.port,
        username: profile.username,
        identity_file: profile.identity_file.filter(|path| !path.trim().is_empty()),
    };
    Ok(crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .save_ssh_server(profile, password)
        .await?
        .into())
}
pub async fn delete_server(alias: String) -> Result<(), BridgeError> {
    crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .delete_ssh_server(&alias)
        .await?;
    Ok(())
}
pub async fn authenticate_server(
    alias: String,
    password: String,
    remember_password: bool,
) -> Result<BridgeSshConnectionSnapshot, BridgeError> {
    let snapshot = crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .authenticate_ssh_server(&alias, password, remember_password)
        .await?;
    Ok(snapshot.into())
}
pub async fn test_server(alias: String) -> Result<BridgeSshConnectionSnapshot, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .test_ssh_connection(&alias)
        .await?
        .into())
}
pub async fn reconnect_server(alias: String) -> Result<BridgeSshConnectionSnapshot, BridgeError> {
    Ok(crate::api::studio::bridge_runtime::active_bridge()
        .await?
        .studio
        .reconnect_ssh_server(&alias)
        .await?
        .into())
}
