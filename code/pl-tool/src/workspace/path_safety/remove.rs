use std::path::Path;

use super::{PathSafetyError, metadata_if_real, validate_existing_path};

/// Removes one real directory below its trusted root. The standard library owns
/// recursive traversal and does not follow child symbolic links or junctions.
pub fn remove_dir_all_no_follow(root: &Path, target: &Path) -> Result<(), PathSafetyError> {
    validate_existing_path(root, target)?;
    let metadata = metadata_if_real(target)?.ok_or_else(|| PathSafetyError::LinkOrReparse {
        path: target.to_path_buf(),
    })?;
    if !metadata.is_dir() {
        return Err(PathSafetyError::io(
            "inspect removal directory",
            target,
            std::io::Error::new(
                std::io::ErrorKind::NotADirectory,
                "target is not a directory",
            ),
        ));
    }
    std::fs::remove_dir_all(target).map_err(|source| PathSafetyError::Io {
        operation: "remove directory tree",
        path: target.to_path_buf(),
        // remove_dir_all documents NotFound as having performed no removal.
        removal_started: source.kind() != std::io::ErrorKind::NotFound,
        source,
    })
}

/// Keeps validation and the complete standard-library traversal in one blocking
/// operation rather than dispatching a filesystem task for every child entry.
pub async fn remove_dir_all_no_follow_async(
    root: &Path,
    target: &Path,
) -> Result<(), PathSafetyError> {
    let root = root.to_owned();
    let target = target.to_owned();
    let error_path = target.clone();
    tokio::task::spawn_blocking(move || remove_dir_all_no_follow(&root, &target))
        .await
        .map_err(|source| PathSafetyError::Io {
            operation: "join directory removal",
            path: error_path,
            source: std::io::Error::other(source),
            removal_started: true,
        })?
}
