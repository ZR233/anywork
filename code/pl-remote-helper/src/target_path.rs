use crate::{ExecutionError, Executor, ExecutorId};

/// A UTF-8 path interpreted by one concrete executor, never by the desktop OS.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TargetPath {
    pub(crate) executor: ExecutorId,
    pub(crate) value: String,
}

impl TargetPath {
    pub fn as_str(&self) -> &str {
        &self.value
    }
}

impl Executor {
    pub fn path(&self, path: impl AsRef<str>) -> Result<TargetPath, ExecutionError> {
        let path = path.as_ref();
        if path.contains('\0') {
            return Err(ExecutionError::InvalidInput(
                "target path contains NUL".into(),
            ));
        }
        let value = if self.target_info().os == "windows" {
            if !cfg!(windows) {
                return Err(ExecutionError::InvalidInput(
                    "Windows remote targets are unsupported".into(),
                ));
            }
            std::path::Path::new(&self.target_info().initial_directory)
                .join(path)
                .into_os_string()
                .into_string()
                .map_err(|_| ExecutionError::InvalidInput("target path is not UTF-8".into()))?
        } else if path.starts_with('/') {
            path.to_owned()
        } else {
            format!(
                "{}/{}",
                self.target_info().initial_directory.trim_end_matches('/'),
                path
            )
        };
        Ok(TargetPath {
            executor: self.id(),
            value,
        })
    }

    /// Joins without collapsing `link/..`; the target OS resolves symlinks.
    pub fn join_path(&self, base: &TargetPath, path: &str) -> Result<TargetPath, ExecutionError> {
        if base.executor != self.id() {
            return Err(ExecutionError::InvalidInput(
                "path belongs to another executor".into(),
            ));
        }
        if self.target_info().os == "windows" {
            let joined = std::path::Path::new(base.as_str()).join(path);
            return self.path(
                joined.to_str().ok_or_else(|| {
                    ExecutionError::InvalidInput("target path is not UTF-8".into())
                })?,
            );
        }
        if path.starts_with('/') {
            self.path(path)
        } else {
            self.path(format!("{}/{path}", base.as_str().trim_end_matches('/')))
        }
    }
}
