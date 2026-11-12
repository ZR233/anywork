use crate::{Executor, TargetPath};
use pl_patch::{
    PatchBackend, PatchError, PatchFailure, PatchPathDisplay, PatchReport, PatchResult,
};
use std::path::{Path, PathBuf};

const PATCH_LIMIT: usize = 16 * 1024 * 1024;
const DIAGNOSTIC_LIMIT: usize = 8 * 1024;

struct NativePatch {
    executor: Executor,
    cwd: TargetPath,
    cancel: tokio_util::sync::CancellationToken,
}

impl PatchPathDisplay for NativePatch {
    fn display_path(&self, path: &Path) -> String {
        path.strip_prefix(self.cwd.as_str())
            .unwrap_or(path)
            .to_str()
            .expect("all patch paths were validated as UTF-8")
            .to_owned()
    }
}

impl NativePatch {
    fn target(&self, path: &Path) -> PatchResult<TargetPath> {
        self.executor
            .path(
                path.to_str()
                    .ok_or_else(|| PatchError::new("patch path is not UTF-8"))?,
            )
            .map_err(PatchError::new)
    }
    fn cancelled(&self) -> PatchResult<()> {
        if self.executor.is_closed() || self.cancel.is_cancelled() {
            Err(PatchError::new("patch execution cancelled"))
        } else {
            Ok(())
        }
    }
}

impl PatchBackend for NativePatch {
    async fn resolve_existing(&self, path: &str) -> PatchResult<PathBuf> {
        self.cancelled()?;
        self.executor
            .join_path(&self.cwd, path)
            .map(|path| PathBuf::from(path.as_str()))
            .map_err(PatchError::new)
    }
    async fn resolve_for_write(&self, path: &str) -> PatchResult<PathBuf> {
        self.resolve_existing(path).await
    }
    async fn reject_symlink_write(&self, path: &Path) -> PatchResult<()> {
        self.cancelled()?;
        let path = self.target(path)?;
        if self
            .executor
            .fs()
            .symlink_metadata(&path)
            .await
            .map_err(PatchError::new)?
            .is_some_and(|metadata| metadata.is_symlink)
        {
            return Err(PatchError::new(
                "patch writes to a final symlink are unsupported",
            ));
        }
        Ok(())
    }
    async fn ensure_file(&self, path: &Path) -> PatchResult<()> {
        let path = self.target(path)?;
        if !self
            .executor
            .fs()
            .metadata(&path)
            .await
            .map_err(PatchError::new)?
            .is_some_and(|metadata| metadata.is_file)
        {
            return Err(PatchError::new("patch target is not a regular file"));
        }
        Ok(())
    }
    async fn read_to_string(&self, path: &Path) -> PatchResult<String> {
        self.cancelled()?;
        tokio::fs::read_to_string(path)
            .await
            .map_err(PatchError::new)
    }
    async fn read_optional_text(&self, path: &Path) -> PatchResult<Option<String>> {
        self.cancelled()?;
        match tokio::fs::read_to_string(path).await {
            Ok(text) => Ok(Some(text)),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(PatchError::new(error)),
        }
    }
    async fn create_parent_dirs(&self, path: &Path) -> PatchResult<()> {
        self.cancelled()?;
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent)
                .await
                .map_err(PatchError::new)?;
        }
        Ok(())
    }
    async fn write_text(&self, path: &Path, content: &str) -> PatchResult<()> {
        use tokio::io::AsyncWriteExt;
        self.cancelled()?;
        let target = self.target(path)?;
        let mut writer = self
            .executor
            .fs()
            .write(
                &target,
                super::WriteMode::ReplaceAtomic,
                Some(content.len() as u64),
            )
            .await
            .map_err(PatchError::new)?;
        writer
            .write_all(content.as_bytes())
            .await
            .map_err(PatchError::new)?;
        self.cancelled()?;
        writer.finish().await.map_err(PatchError::new)?;
        Ok(())
    }
    async fn remove_file(&self, path: &Path) -> PatchResult<()> {
        self.cancelled()?;
        tokio::fs::remove_file(path).await.map_err(PatchError::new)
    }
}

pub(super) async fn apply(
    executor: Executor,
    cwd: TargetPath,
    patch: &str,
    cancel: tokio_util::sync::CancellationToken,
) -> Result<PatchReport, PatchFailure> {
    let failure = |diagnostic: String| PatchFailure {
        diagnostic,
        applied_changes: Vec::new(),
        changes_may_be_incomplete: false,
    };
    if patch.len() > PATCH_LIMIT {
        return Err(failure("patch exceeds 16 MiB".into()));
    }
    let paths = pl_patch::affected_paths(patch).map_err(|error| failure(error.to_string()))?;
    let mut budget = DIAGNOSTIC_LIMIT + 256;
    for path in paths {
        let path = executor
            .join_path(&cwd, &path.path)
            .map_err(|error| failure(error.to_string()))?;
        let encoded = serde_json::to_vec(path.as_str())
            .expect("path serializes")
            .len();
        budget = budget
            .saturating_add(encoded.saturating_mul(2))
            .saturating_add(256);
        if budget > crate::stream::DESCRIPTOR_LIMIT {
            return Err(failure(
                "ReportTooLarge: patch report exceeds 1 MiB before any modification".into(),
            ));
        }
    }
    let backend = NativePatch {
        executor,
        cwd,
        cancel,
    };
    backend
        .cancelled()
        .map_err(|error| failure(error.to_string()))?;
    match pl_patch::apply_patch(patch, &backend).await {
        Ok(outcome) => Ok(outcome.report(&backend)),
        Err(error) => {
            let mut failure = error
                .failure()
                .cloned()
                .unwrap_or_else(|| failure(error.to_string()));
            if serde_json::to_vec(&failure.diagnostic)
                .expect("diagnostic serializes")
                .len()
                > DIAGNOSTIC_LIMIT
            {
                let mut length = failure.diagnostic.len().min(DIAGNOSTIC_LIMIT / 6 - 32);
                while !failure.diagnostic.is_char_boundary(length) {
                    length -= 1;
                }
                failure.diagnostic.truncate(length);
                failure.diagnostic.push_str(" [diagnostic truncated]");
            }
            Err(failure)
        }
    }
}
