//! Lexical path contracts at the worktree boundary; no host filesystem probes.
use std::path::Path;

use super::WorktreeError;

pub(super) const MAX_ADMIN_BACKLINK_BYTES: usize = 128 * 1024;

/// Converts a workspace path for its execution site, retaining native local path spelling.
/// Remote paths use the shared POSIX contract even when allocated on a Windows host.
pub(crate) fn workspace_path_text(
    path: &Path,
    remote: bool,
) -> Result<String, pl_tool::remote::RemotePathError> {
    if remote {
        pl_tool::remote::normalize_remote_absolute_path(&path.to_string_lossy())
    } else {
        Ok(path.to_string_lossy().into_owned())
    }
}

pub(crate) fn workspace_paths_equal(
    left: &Path,
    right: &Path,
    remote: bool,
) -> Result<bool, pl_tool::remote::RemotePathError> {
    if remote {
        Ok(workspace_path_text(left, true)? == workspace_path_text(right, true)?)
    } else {
        Ok(left == right)
    }
}

pub(super) fn checked_admin_dir(raw: &str, common_dir: &str) -> Result<String, WorktreeError> {
    let admin = resolved_git_path(raw, "").ok_or_else(|| {
        WorktreeError::IdentityMismatch("registration admin directory cannot be normalized".into())
    })?;
    let prefix = format!("{common_dir}/worktrees/");
    if !admin
        .strip_prefix(&prefix)
        .is_some_and(|leaf| !leaf.is_empty() && !leaf.contains('/'))
    {
        return Err(WorktreeError::IdentityMismatch(
            "registration admin directory is outside the owning repository".into(),
        ));
    }
    Ok(admin)
}

pub(super) fn decode_backlink(bytes: &[u8], admin_dir: &str) -> Result<String, WorktreeError> {
    if bytes.len() > MAX_ADMIN_BACKLINK_BYTES {
        return Err(WorktreeError::IdentityMismatch(
            "registration admin backlink exceeds its path bound".into(),
        ));
    }
    let text = std::str::from_utf8(bytes).map_err(|_| {
        WorktreeError::IdentityMismatch("registration admin backlink is not a UTF-8 path".into())
    })?;
    // Git can rewrite both linking files to relative paths during creation or repair. The
    // backlink is relative to this verified admin directory, not to the checkout or common dir.
    resolved_git_path(text, admin_dir).ok_or_else(|| {
        WorktreeError::IdentityMismatch("registration admin backlink cannot be normalized".into())
    })
}

//
// Git answers `--git-common-dir` in one of two shapes: `.git` (relative to the directory it was asked
// in) or an absolute path. Two answers are comparable only after the same lexical resolution, and that
// resolution has to be platform-correct: a Windows drive letter and a UNC share are absolute just like a
// POSIX `/`, separators differ, and Windows compares paths case-insensitively while POSIX does not.

/// Resolves one `rev-parse` path answer against the directory it was asked in.
///
/// `None` means the answer cannot be proven: empty, relative to an unresolvable base, or escaping above
/// the filesystem root. Windows-style answers (drive letter or UNC) are folded to lower case, because a
/// Windows path that differs only by case is the same directory; POSIX answers keep their case.
pub(super) fn resolved_git_path(raw: &str, base: &str) -> Option<String> {
    let raw = normalized_separators(raw);
    if raw.is_empty() {
        return None;
    }
    // A drive-relative answer (`C:foo`) is neither an absolute identity nor a usable relative segment:
    // it depends on a per-drive current directory this comparison never knows.
    if drive_relative_git_path(&raw) {
        return None;
    }
    let base = normalized_separators(base);
    let joined = if absolute_git_path(&raw) {
        raw
    } else if absolute_git_path(&base) {
        format!("{}/{}", base.trim_end_matches('/'), raw)
    } else {
        return None;
    };
    let (prefix, rest, windows_style) = split_git_root(&joined)?;
    let mut parts: Vec<&str> = Vec::new();
    for part in rest.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            other => parts.push(other),
        }
    }
    let body = parts.join("/");
    let normalized = if prefix.is_empty() {
        format!("/{body}")
    } else if body.is_empty() {
        format!("{prefix}/")
    } else {
        format!("{prefix}/{body}")
    };
    Some(if windows_style {
        normalized.to_ascii_lowercase()
    } else {
        normalized
    })
}

/// Normalizes the separators Git may print on either platform.
fn normalized_separators(value: &str) -> String {
    value.trim().replace('\\', "/")
}

/// Whether the value names an absolute location on either platform.
fn absolute_git_path(value: &str) -> bool {
    value.starts_with('/') || drive_prefix(value).is_some()
}

/// The drive designation of a Windows path, when it has one and is not drive-relative (`C:foo`).
fn drive_prefix(value: &str) -> Option<&str> {
    let bytes = value.as_bytes();
    if bytes.len() < 2 || bytes[1] != b':' || !bytes[0].is_ascii_alphabetic() {
        return None;
    }
    match value[2..].chars().next() {
        None | Some('/') => Some(&value[..2]),
        // `C:foo` is relative to the drive's current directory: not an absolute identity.
        Some(_) => None,
    }
}

/// Whether the value names a location relative to a drive's current directory (`C:foo`).
fn drive_relative_git_path(value: &str) -> bool {
    let bytes = value.as_bytes();
    if bytes.len() < 2 || bytes[1] != b':' || !bytes[0].is_ascii_alphabetic() {
        return false;
    }
    !matches!(value[2..].chars().next(), None | Some('/'))
}

/// Splits an absolute path into (root, rest, windows_style).
///
/// The root is `/` for POSIX, a drive (`c:`) for Windows paths, and `//server/share` for a UNC path. UNC
/// roots keep their two leading components, which are the share identity and never fold into `..`.
fn split_git_root(value: &str) -> Option<(String, String, bool)> {
    if let Some(rest) = value.strip_prefix("//") {
        let mut parts = rest.splitn(3, '/');
        let server = parts.next().filter(|part| !part.is_empty())?;
        let share = parts.next().filter(|part| !part.is_empty())?;
        let rest = parts.next().unwrap_or_default().to_string();
        return Some((format!("//{server}/{share}"), rest, true));
    }
    if let Some(drive) = drive_prefix(value) {
        let rest = value[2..].trim_start_matches('/').to_string();
        return Some((drive.to_ascii_lowercase(), rest, true));
    }
    if value.starts_with('/') {
        return Some((
            String::new(),
            value.trim_start_matches('/').to_string(),
            false,
        ));
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn workspace_paths_preserve_execution_site_contracts() {
        // No path has to exist: these are execution-side strings, never host probes.
        let remote = Path::new(r"\remote\Project\.\worktree\");
        assert_eq!(
            workspace_path_text(remote, true).unwrap(),
            "/remote/Project/worktree"
        );
        assert!(
            workspace_paths_equal(remote, Path::new("/remote/Project/worktree"), true).unwrap()
        );
        assert!(
            !workspace_paths_equal(remote, Path::new("/remote/project/worktree"), true).unwrap()
        );
        assert!(workspace_path_text(Path::new("/remote/../outside"), true).is_err());
        assert!(workspace_path_text(Path::new("relative/worktree"), true).is_err());

        // Local spelling, including spaces and native separators, must remain untouched.
        let local = Path::new(r" local\Project ");
        assert_eq!(
            workspace_path_text(local, false).unwrap(),
            local.to_string_lossy()
        );
        assert!(workspace_paths_equal(local, local, false).unwrap());
        #[cfg(unix)]
        assert!(!workspace_paths_equal(local, Path::new(" local/Project "), false).unwrap());
    }

    #[test]
    fn git_answers_resolve_against_their_own_base() {
        for (raw, base, expected) in [
            ("../.git", "/Repo/checkout", Some("/Repo/.git")),
            (r"C:\Repo\..\Other\.git", "", Some("c:/other/.git")),
            (
                r"\\Server\Share\Repo\.git",
                "",
                Some("//server/share/repo/.git"),
            ),
            ("C:relative", "/Repo", None),
            ("../../escape", "/Repo", None),
            (".git", "relative", None),
        ] {
            assert_eq!(
                resolved_git_path(raw, base).as_deref(),
                expected,
                "{raw:?} from {base:?}"
            );
        }
    }
}
