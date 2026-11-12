use super::*;
use futures::{StreamExt, stream::BoxStream};

pub(crate) type WorkspaceWalkEntries = BoxStream<'static, Result<WorkspaceWalkEntry>>;
pub(crate) struct WorkspaceWalkEntry {
    pub(crate) path: String,
    pub(crate) is_dir: bool,
}
#[derive(Debug)]
pub struct WorkspaceDirectoryReader {
    reader: pl_remote_helper::fs::DirectoryReader,
    executor: Executor,
    root: TargetPath,
}
impl WorkspaceDirectoryReader {
    pub async fn next(&mut self) -> Result<Option<pl_protocol::remote::RemoteDirectoryEntry>> {
        let Some(entry) = self.reader.next().await.map_err(file_error)? else {
            return Ok(None);
        };
        let target = self.executor.path(&entry.path).map_err(file_error)?;
        let path = self
            .executor
            .relative_path(&self.root, &target)
            .map_err(file_error)?
            .ok_or_else(|| tool_error("file", "directory entry is outside workspace"))?;
        Ok(Some(pl_protocol::remote::RemoteDirectoryEntry {
            name: entry.name,
            path,
            is_directory: entry.is_dir,
            is_symlink: entry.is_symlink,
        }))
    }
}
impl ExecutorWorkspaceFileBackend {
    pub async fn open_directory(&self, path: String) -> Result<WorkspaceDirectoryReader> {
        let path = self
            .bound(self.path_request(path, None).map_err(file_error)?, true)
            .await
            .map_err(file_error)?;
        let reader = self
            .executor
            .fs()
            .read_dir(&path)
            .await
            .map_err(file_error)?;
        Ok(WorkspaceDirectoryReader {
            reader,
            root: self.root.clone(),
            executor: self.executor.clone(),
        })
    }
    pub(crate) async fn walk(&self, path: String) -> Result<WorkspaceWalkEntries> {
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
                        WorkspaceWalkEntry {
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
