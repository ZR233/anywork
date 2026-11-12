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
    fn check_path_owner(&self, path: &TargetPath) -> Result<(), ExecutionError> {
        if path.executor == self.id() {
            Ok(())
        } else {
            Err(ExecutionError::InvalidInput(
                "path belongs to another executor".into(),
            ))
        }
    }
    /// Parent in the target's path syntax. Root has no parent; symlinks are not resolved here.
    pub fn parent_path(&self, path: &TargetPath) -> Result<Option<TargetPath>, ExecutionError> {
        self.check_path_owner(path)?;
        let parent = if self.target_info().os == "windows" {
            std::path::Path::new(path.as_str())
                .parent()
                .map(|parent| {
                    parent.to_str().map(str::to_owned).ok_or_else(|| {
                        ExecutionError::InvalidInput("target path is not UTF-8".into())
                    })
                })
                .transpose()?
        } else {
            let value = path.as_str().trim_end_matches('/');
            if value.is_empty() {
                None
            } else {
                value.rsplit_once('/').map(|(parent, _)| {
                    if parent.is_empty() {
                        "/".into()
                    } else {
                        parent.to_owned()
                    }
                })
            }
        };
        parent.map(|parent| self.path(parent)).transpose()
    }
    /// Lexical display projection only. Access checks must first resolve the relevant
    /// path or existing ancestor on the target filesystem.
    pub fn relative_path(
        &self,
        base: &TargetPath,
        path: &TargetPath,
    ) -> Result<Option<String>, ExecutionError> {
        self.check_path_owner(base)?;
        self.check_path_owner(path)?;
        if self.target_info().os == "windows" {
            return std::path::Path::new(path.as_str())
                .strip_prefix(base.as_str())
                .ok()
                .map(|path| {
                    path.to_str()
                        .map(|path| {
                            if path.is_empty() {
                                ".".into()
                            } else {
                                path.into()
                            }
                        })
                        .ok_or_else(|| {
                            ExecutionError::InvalidInput("target path is not UTF-8".into())
                        })
                })
                .transpose();
        }
        let base = base.as_str().trim_end_matches('/');
        if path.as_str().trim_end_matches('/') == base {
            return Ok(Some(".".into()));
        }
        Ok(path
            .as_str()
            .strip_prefix(base)
            .and_then(|path| path.strip_prefix('/'))
            .map(str::to_owned))
    }

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
            let joined = std::path::Path::new(&self.target_info().initial_directory).join(path);
            // Windows canonicalize returns verbatim paths. Use the workspace's
            // existing checked simplifier so Git's regular spelling and native
            // FS replies bind the same location; reserved/ambiguous paths retain
            // their verbatim form. This branch never parses a Linux target path.
            dunce::simplified(&joined)
                .to_owned()
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
