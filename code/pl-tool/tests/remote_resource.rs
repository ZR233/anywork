//! Product workspace binding preserves confinement without server-side workspace leases.
#![cfg(target_os = "linux")]
#[path = "support/helper.rs"]
mod helper;
#[path = "support/remote.rs"]
mod support;
use pl_tool::workspace_file::{
    WorkspaceFileBackend, WorkspaceFileReadRequest, WorkspaceFileWriteRequest,
};
#[tokio::test]
async fn workspace_binding_preserves_neighbors_and_cannot_recover_closed_handles()
-> anyhow::Result<()> {
    let helper = support::Helper::start(helper::remote_helper_executable()).await?;
    let outside = tempfile::tempdir()?;
    tokio::fs::write(outside.path().join("private"), b"neighbor").await?;
    std::os::unix::fs::symlink(outside.path(), helper.root.path().join("escape"))?;
    let files = helper.files.clone();
    let observed = async {
        assert!(
            files
                .read_text(WorkspaceFileReadRequest {
                    path: "escape/private".into(),
                    cwd: None
                })
                .await
                .is_err()
        );
        assert!(
            files
                .write_text(WorkspaceFileWriteRequest {
                    path: "escape/private".into(),
                    cwd: None,
                    mode: pl_tool::workspace::WriteMode::Overwrite,
                    content: "changed".into()
                })
                .await
                .is_err()
        );
        files.remove_path("escape".into(), None, true).await?;
        assert_eq!(
            tokio::fs::read(outside.path().join("private")).await?,
            b"neighbor"
        );
        files.create_directory("owned/sub".into(), None).await?;
        files
            .write_text(WorkspaceFileWriteRequest {
                path: "owned/sub/value".into(),
                cwd: None,
                mode: pl_tool::workspace::WriteMode::Create,
                content: "complete".into(),
            })
            .await?;
        files
            .copy_path(
                "owned".into(),
                "copied".into(),
                None,
                true,
                pl_tool_filesystem::PathCollision::FailIfExists,
            )
            .await?;
        assert_eq!(
            files
                .read_text(WorkspaceFileReadRequest {
                    path: "copied/sub/value".into(),
                    cwd: None
                })
                .await?,
            "complete"
        );
        files.remove_path("owned".into(), None, true).await?;
        assert_eq!(
            files
                .read_text(WorkspaceFileReadRequest {
                    path: "copied/sub/value".into(),
                    cwd: None
                })
                .await?,
            "complete"
        );
        anyhow::Ok(())
    }
    .await;
    let closed = helper.close().await;
    observed?;
    closed?;
    assert!(
        files
            .read_text(WorkspaceFileReadRequest {
                path: "copied/sub/value".into(),
                cwd: None
            })
            .await
            .is_err()
    );
    Ok(())
}
