//! Incremental remote directory reader and depth-first traversal owned on the host.
use super::*;
use futures::{StreamExt, stream::BoxStream};
use pl_protocol::Result;

pub(in crate::remote) type RemoteWalkEntries = BoxStream<'static, Result<RemoteWalkEntry>>;

pub(in crate::remote) struct RemoteWalkEntry {
    pub(in crate::remote) path: String,
    pub(in crate::remote) is_dir: bool,
}

pub struct RemoteDirectoryReader {
    client: RemoteClient,
    workspace: Arc<super::super::client::workspace::WorkspaceLease>,
    entries: VecDeque<pl_protocol::remote::RemoteDirectoryEntry>,
    cursor: Option<String>,
    memory: Option<pl_remote_helper::budget::ByteLease>,
}
impl std::fmt::Debug for RemoteDirectoryReader {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RemoteDirectoryReader")
            .field("has_next", &self.cursor.is_some())
            .finish_non_exhaustive()
    }
}
impl RemoteDirectoryReader {
    pub async fn next(&mut self) -> Result<Option<pl_protocol::remote::RemoteDirectoryEntry>> {
        loop {
            if let Some(entry) = self.entries.pop_front() {
                return Ok(Some(entry));
            }
            self.memory = None;
            let Some(cursor) = self.cursor.clone() else {
                return Ok(None);
            };
            let reply = self
                .client
                .workspace_request(
                    self.workspace.clone(),
                    RemoteRequest::ContinueDirectory { cursor },
                    &[],
                )
                .await
                .map_err(remote_file_error)?;
            let RemoteResponse::Directory(page) = reply.response else {
                return Err(tool_error("file", "unexpected directory page"));
            };
            self.cursor = page.next_cursor;
            self.memory = Some(
                self.client
                    .reserve_page(
                        page.entries
                            .iter()
                            .map(|entry| {
                                entry.name.len() + entry.path.len() + std::mem::size_of_val(entry)
                            })
                            .sum(),
                    )
                    .map_err(remote_file_error)?,
            );
            self.entries = page.entries.into();
        }
    }
}
impl Drop for RemoteDirectoryReader {
    fn drop(&mut self) {
        if let Some(cursor) = self.cursor.take() {
            self.client
                .release_resource(RemoteRequest::CloseDirectory { cursor });
        }
    }
}
impl RemoteWorkspaceFileBackend {
    pub async fn open_directory(&self, path: String) -> Result<RemoteDirectoryReader> {
        open(&self.client, self.lease.clone(), path).await
    }
    pub(in crate::remote) async fn walk(&self, path: String) -> Result<RemoteWalkEntries> {
        let root = open(&self.client, self.lease.clone(), path).await?;
        let client = self.client.clone();
        let workspace = self.lease.clone();
        Ok(futures::stream::try_unfold(
            (vec![root], None::<String>, client, workspace),
            move |(mut stack, pending, client, workspace)| async move {
                if let Some(path) = pending {
                    stack.push(open(&client, workspace.clone(), path).await?);
                }
                loop {
                    let Some(reader) = stack.last_mut() else {
                        return Ok(None);
                    };
                    let Some(entry) = reader.next().await? else {
                        stack.pop();
                        continue;
                    };
                    if entry.is_symlink || (entry.is_directory && skip_directory(&entry.path)) {
                        continue;
                    }
                    let pending = entry.is_directory.then(|| entry.path.clone());
                    return Ok(Some((
                        RemoteWalkEntry {
                            path: entry.path,
                            is_dir: entry.is_directory,
                        },
                        (stack, pending, client, workspace),
                    )));
                }
            },
        )
        .boxed())
    }
}

fn skip_directory(path: &str) -> bool {
    let name = path
        .trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or(path);
    matches!(name, ".git" | "target" | "node_modules")
}

async fn open(
    client: &RemoteClient,
    workspace: Arc<super::super::client::workspace::WorkspaceLease>,
    path: String,
) -> Result<RemoteDirectoryReader> {
    let reply = client
        .workspace_request(
            workspace.clone(),
            RemoteRequest::ListDirectory(RemotePathRequest {
                workspace_id: workspace.id.clone(),
                path,
            }),
            &[],
        )
        .await
        .map_err(remote_file_error)?;
    let RemoteResponse::Directory(page) = reply.response else {
        return Err(tool_error("file", "unexpected directory response"));
    };
    let memory = match client.reserve_page(
        page.entries
            .iter()
            .map(|entry| entry.name.len() + entry.path.len() + std::mem::size_of_val(entry))
            .sum(),
    ) {
        Ok(memory) => memory,
        Err(error) => {
            if let Some(cursor) = page.next_cursor {
                client.release_resource(RemoteRequest::CloseDirectory { cursor });
            }
            return Err(remote_file_error(error));
        }
    };
    Ok(RemoteDirectoryReader {
        client: client.clone(),
        workspace,
        entries: page.entries.into(),
        cursor: page.next_cursor,
        memory: Some(memory),
    })
}
