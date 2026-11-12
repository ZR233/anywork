use super::*;
use futures::{StreamExt, stream::BoxStream};

pub(in crate::remote) type RemoteWalkEntries = BoxStream<'static, Result<RemoteWalkEntry>>;
pub(in crate::remote) struct RemoteWalkEntry {
    pub(in crate::remote) path: String,
    pub(in crate::remote) is_dir: bool,
}
#[derive(Debug)]
pub struct RemoteDirectoryReader {
    reader: pl_remote_helper::fs::DirectoryReader,
    root: String,
}
impl RemoteDirectoryReader {
    pub async fn next(&mut self) -> Result<Option<pl_protocol::remote::RemoteDirectoryEntry>> {
        let Some(entry) = self
            .reader
            .next()
            .await
            .map_err(|error| remote_file_error(error.into()))?
        else {
            return Ok(None);
        };
        let path = entry
            .path
            .strip_prefix(self.root.trim_end_matches('/'))
            .and_then(|path| path.strip_prefix('/'))
            .ok_or_else(|| tool_error("file", "directory entry is outside workspace"))?
            .to_owned();
        Ok(Some(pl_protocol::remote::RemoteDirectoryEntry {
            name: entry.name,
            path,
            is_directory: entry.is_dir,
            is_symlink: entry.is_symlink,
        }))
    }
}
impl RemoteWorkspaceFileBackend {
    pub async fn open_directory(&self, path: String) -> Result<RemoteDirectoryReader> {
        let path = self
            .bound(
                self.path_request(path, None).map_err(remote_file_error)?,
                true,
            )
            .await
            .map_err(remote_file_error)?;
        let reader = self
            .executor
            .fs()
            .read_dir(&path)
            .await
            .map_err(|error| remote_file_error(error.into()))?;
        Ok(RemoteDirectoryReader {
            reader,
            root: self.root.as_str().into(),
        })
    }
    pub(in crate::remote) async fn walk(&self, path: String) -> Result<RemoteWalkEntries> {
        let root = self.open_directory(path).await?;
        let backend = self.clone();
        Ok(futures::stream::try_unfold(
            (vec![root], None::<String>, backend),
            move |(mut stack, pending, backend)| async move {
                if let Some(path) = pending {
                    stack.push(backend.open_directory(path).await?);
                }
                loop {
                    let Some(reader) = stack.last_mut() else {
                        return Ok(None);
                    };
                    let Some(entry) = reader.next().await? else {
                        stack.pop();
                        continue;
                    };
                    let name = entry.path.rsplit('/').next().unwrap_or_default();
                    if entry.is_symlink
                        || (entry.is_directory
                            && matches!(name, ".git" | "target" | "node_modules"))
                    {
                        continue;
                    }
                    let pending = entry.is_directory.then(|| entry.path.clone());
                    return Ok(Some((
                        RemoteWalkEntry {
                            path: entry.path,
                            is_dir: entry.is_directory,
                        },
                        (stack, pending, backend),
                    )));
                }
            },
        )
        .boxed())
    }
}
