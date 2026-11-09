use super::*;
use crate::workspace::{AgentWorkspace, WorkspaceMutability};

#[tokio::test]
async fn fail_if_exists_preserves_destination_appearing_before_local_mutation() {
    let root = tempfile::tempdir().unwrap();
    let backend = LocalMutationCapability {
        paths: WorkspacePaths::new(root.path().into(), false)
            .await
            .unwrap(),
        workspace: ToolWorkspace::new(AgentWorkspace::confined(
            root.path(),
            WorkspaceMutability::ReadWrite,
        )),
    };
    for moving in [false, true] {
        for directory in [false, true] {
            let name = format!(
                "{}-{}",
                if moving { "move" } else { "copy" },
                if directory { "tree" } else { "file" }
            );
            let source = root.path().join(format!("{name}-source"));
            let target = root.path().join(format!("{name}-target"));
            std::fs::write(&source, b"source").unwrap();
            assert!(!backend.exists(&target).await.unwrap());
            if directory {
                std::fs::create_dir_all(target.join("nested")).unwrap();
                std::fs::write(target.join("nested/keep"), b"external tree").unwrap();
            } else {
                std::fs::write(&target, b"external file").unwrap();
            }
            let outcome = if moving {
                backend
                    .rename(&source, &target, PathCollision::FailIfExists)
                    .await
            } else {
                backend
                    .copy(&source, &target, PathCollision::FailIfExists)
                    .await
            };
            assert!(
                outcome.unwrap_err().to_string().contains("already exists"),
                "{name}"
            );
            assert_eq!(std::fs::read(&source).unwrap(), b"source", "{name}");
            if directory {
                assert_eq!(
                    std::fs::read(target.join("nested/keep")).unwrap(),
                    b"external tree",
                    "{name}"
                );
            } else {
                assert_eq!(std::fs::read(&target).unwrap(), b"external file", "{name}");
            }
        }
    }
}

#[tokio::test]
async fn explicit_overwrite_preserves_local_copy_and_move_behavior() {
    let root = tempfile::tempdir().unwrap();
    let backend = LocalMutationCapability {
        paths: WorkspacePaths::new(root.path().into(), false)
            .await
            .unwrap(),
        workspace: ToolWorkspace::new(AgentWorkspace::confined(
            root.path(),
            WorkspaceMutability::ReadWrite,
        )),
    };
    for moving in [false, true] {
        let source = root
            .path()
            .join(if moving { "move-source" } else { "copy-source" });
        let target = root
            .path()
            .join(if moving { "move-target" } else { "copy-target" });
        std::fs::write(&source, b"source").unwrap();
        std::fs::write(&target, b"replace").unwrap();
        if moving {
            backend
                .rename(&source, &target, PathCollision::Overwrite)
                .await
                .unwrap();
        } else {
            backend
                .copy(&source, &target, PathCollision::Overwrite)
                .await
                .unwrap();
        }
        assert_eq!(std::fs::read(&target).unwrap(), b"source");
        assert_eq!(source.exists(), !moving);
    }
}
