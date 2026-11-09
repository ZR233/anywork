use std::{convert::Infallible, fmt, future::Future, io::Write};

use secrecy::{ExposeSecret, SecretString};
use tempfile::TempPath;

use crate::GitError;

pub const GIT_TOKEN_ENV: &str = "PL_GIT_TOKEN";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GitCredentialOperation {
    Fetch,
    Push,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitCredentialRequest {
    pub operation: GitCredentialOperation,
    pub remote: String,
}

#[derive(Clone)]
pub struct GitCredential(SecretString);

impl fmt::Debug for GitCredential {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("GitCredential").field(&"[redacted]").finish()
    }
}

impl GitCredential {
    pub fn new(value: String) -> Self {
        Self(SecretString::from(value))
    }

    pub(crate) fn expose(&self) -> &str {
        self.0.expose_secret()
    }
}

/// Supplies an already-resolved short-lived Git credential; no storage policy.
pub trait GitCredentialProvider: fmt::Debug + Send + Sync {
    type Error: std::error::Error + Send + Sync + 'static;

    fn credential(
        &self,
        request: GitCredentialRequest,
    ) -> impl Future<Output = Result<Option<GitCredential>, Self::Error>> + Send;
}

#[derive(Debug, Clone, Default)]
pub struct NoGitCredentialProvider;

impl GitCredentialProvider for NoGitCredentialProvider {
    type Error = Infallible;

    async fn credential(
        &self,
        _request: GitCredentialRequest,
    ) -> Result<Option<GitCredential>, Self::Error> {
        Ok(None)
    }
}

/// The file contains no credential and is removed on success, failure or drop.
pub(crate) fn write_askpass_script(tool: &'static str) -> Result<TempPath, GitError> {
    let mut file = tempfile::Builder::new()
        .prefix("pl-tool-git-askpass-")
        .tempfile()
        .map_err(|source| GitError::Askpass {
            tool,
            message: "failed to create git askpass",
            source,
        })?;
    file.write_all(git_askpass_script().as_bytes())
        .map_err(|source| GitError::Askpass {
            tool,
            message: "failed to write git askpass",
            source,
        })?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.as_file()
            .set_permissions(std::fs::Permissions::from_mode(0o700))
            .map_err(|source| GitError::Askpass {
                tool,
                message: "failed to chmod git askpass",
                source,
            })?;
    }
    // Close the writable handle before Git executes the script (ETXTBSY on Unix).
    Ok(file.into_temp_path())
}

pub fn git_askpass_script() -> &'static str {
    "#!/bin/sh\ncase \"$1\" in\n  *Username*) printf '%s\\n' x-access-token ;;\n  *Password*) printf '%s\\n' \"$PL_GIT_TOKEN\" ;;\n  *) printf '\\n' ;;\nesac\n"
}
