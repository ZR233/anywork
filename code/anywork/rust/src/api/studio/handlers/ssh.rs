use pl_studio_runtime::{
    SshConnectionSnapshot, SshConnectionState, SshPasswordUpdate, SshServerProfile,
    SshServerRuntimeEntry,
};

use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::types::{
    AuthenticateSshServerRequest, BridgeError, ProjectDto, RemoteDirectoryEntryDto,
    RemoteDirectoryListingDto, SaveSshServerRequest, SshConnectionSnapshotDto, SshPasswordInput,
    SshServerDto,
};

pub async fn list_ssh_servers() -> Result<Vec<SshServerDto>, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge
        .studio
        .list_ssh_servers()
        .await?
        .into_iter()
        .map(server_dto)
        .collect())
}

pub async fn save_ssh_server(request: SaveSshServerRequest) -> Result<SshServerDto, BridgeError> {
    let password = match request.password {
        SshPasswordInput::Preserve => SshPasswordUpdate::Preserve,
        SshPasswordInput::Replace { value } => SshPasswordUpdate::Replace { value },
        SshPasswordInput::Clear => SshPasswordUpdate::Clear,
    };
    let entry = active_bridge()
        .await?
        .studio
        .save_ssh_server(
            SshServerProfile {
                alias: request.alias,
                host_name: request.host_name,
                port: request.port,
                username: request.username,
                identity_file: request.identity_file.filter(|path| !path.trim().is_empty()),
            },
            password,
        )
        .await?;
    Ok(server_dto(entry))
}

pub async fn delete_ssh_server(alias: String) -> Result<(), BridgeError> {
    active_bridge()
        .await?
        .studio
        .delete_ssh_server(&alias)
        .await?;
    Ok(())
}

pub async fn authenticate_ssh_server(
    request: AuthenticateSshServerRequest,
) -> Result<SshConnectionSnapshotDto, BridgeError> {
    let snapshot = active_bridge()
        .await?
        .studio
        .authenticate_ssh_server(&request.alias, request.password, request.remember_password)
        .await?;
    Ok(connection_dto(snapshot))
}

pub async fn test_ssh_connection(alias: String) -> Result<SshConnectionSnapshotDto, BridgeError> {
    let snapshot = active_bridge()
        .await?
        .studio
        .test_ssh_connection(&alias)
        .await?;
    Ok(connection_dto(snapshot))
}

pub async fn reconnect_ssh_server(alias: String) -> Result<SshConnectionSnapshotDto, BridgeError> {
    let snapshot = active_bridge()
        .await?
        .studio
        .reconnect_ssh_server(&alias)
        .await?;
    Ok(connection_dto(snapshot))
}

pub async fn browse_remote_directories(
    alias: String,
    path: Option<String>,
    cursor: Option<String>,
) -> Result<RemoteDirectoryListingDto, BridgeError> {
    let listing = active_bridge()
        .await?
        .studio
        .browse_remote_directories(&alias, path, cursor)
        .await?;
    Ok(RemoteDirectoryListingDto {
        path: listing.path,
        parent: listing.parent,
        next_cursor: listing.next_cursor,
        entries: listing
            .entries
            .into_iter()
            .filter(|entry| entry.is_directory && !entry.is_symlink)
            .map(|entry| RemoteDirectoryEntryDto {
                name: entry.name,
                path: entry.path,
                is_directory: entry.is_directory,
            })
            .collect(),
    })
}

pub async fn close_remote_directory(alias: String, cursor: String) -> Result<(), BridgeError> {
    active_bridge()
        .await?
        .studio
        .close_remote_directory(&alias, cursor)
        .await?;
    Ok(())
}

pub async fn open_remote_project(alias: String, path: String) -> Result<ProjectDto, BridgeError> {
    Ok(active_bridge()
        .await?
        .studio
        .open_remote_project(&alias, path)
        .await?
        .into())
}

fn server_dto(entry: SshServerRuntimeEntry) -> SshServerDto {
    SshServerDto {
        alias: entry.profile.alias,
        host_name: entry.profile.host_name,
        port: entry.profile.port,
        username: entry.profile.username,
        identity_file: entry.profile.identity_file,
        managed: entry.managed,
        has_password: entry.has_password,
    }
}

fn connection_dto(snapshot: SshConnectionSnapshot) -> SshConnectionSnapshotDto {
    let mut dto = SshConnectionSnapshotDto {
        alias: snapshot.alias,
        state: String::new(),
        helper_version: None,
        architecture: None,
        attempt: None,
        delay_seconds: None,
        error_code: None,
        error_message: None,
    };
    match snapshot.state {
        SshConnectionState::Disconnected => dto.state = "disconnected".to_string(),
        SshConnectionState::Connecting => dto.state = "connecting".to_string(),
        SshConnectionState::Ready {
            helper_version,
            architecture,
        } => {
            dto.state = "ready".to_string();
            dto.helper_version = Some(helper_version);
            dto.architecture = Some(architecture);
        }
        SshConnectionState::Reconnecting {
            attempt,
            delay_seconds,
        } => {
            dto.state = "reconnecting".to_string();
            dto.attempt = Some(attempt);
            dto.delay_seconds = Some(delay_seconds);
        }
        SshConnectionState::Failed { code, message } => {
            dto.state = "failed".to_string();
            dto.error_code = Some(code);
            dto.error_message = Some(message);
        }
    }
    dto
}
