//! Target capture preserves root exit and stream completion as independent facts.
#![cfg(target_os = "linux")]
#[path = "support/helper.rs"]
mod helper;
#[path = "support/remote.rs"]
mod support;
use pl_remote_helper::{CaptureSpec, CaptureState, ProcessExit, Stdio};
use tokio::io::AsyncReadExt;
#[tokio::test]
async fn target_capture_disk_failure_does_not_overwrite_observed_root_exit() -> anyhow::Result<()> {
    let helper = support::Helper::start(helper::remote_helper_executable()).await?;
    let stdout = helper.root.path().join("stdout");
    let stderr = helper.root.path().join("stderr");
    std::os::unix::fs::symlink("/dev/full", &stdout)?;
    let observed = async {
        // Root exits before the descendant writes; both facts are deterministic.
        let mut child = helper
            .executor
            .command("/bin/sh")
            .args([
                "-c",
                "exec 3<&0; (read line <&3; printf '%s' failure) & exit 23",
            ])
            .stdin(Stdio::Piped)
            .stdout(Stdio::Piped)
            .stderr(Stdio::Piped)
            .capture(CaptureSpec {
                stdout_path: stdout.to_str().unwrap().into(),
                stderr_path: stderr.to_str().unwrap().into(),
                max_bytes: 1024,
            })
            .spawn()
            .await?;
        let mut input = child.stdin.take().unwrap();
        assert_eq!(child.wait().await?, ProcessExit::Code(23));
        use tokio::io::AsyncWriteExt;
        input.write_all(b"release\n").await?;
        drop(input);
        let mut stdout = child.stdout.take().unwrap();
        let mut stderr = child.stderr.take().unwrap();
        let mut out_bytes = Vec::new();
        let mut err_bytes = Vec::new();
        let (out, err) = tokio::join!(
            stdout.read_to_end(&mut out_bytes),
            stderr.read_to_end(&mut err_bytes)
        );
        out?;
        err?;
        let capture = child.finish_capture().await?.unwrap();
        assert_eq!(capture.stdout.state, CaptureState::IoFailed);
        assert_eq!(capture.stdout.confirmed_bytes, None);
        assert_eq!(child.wait().await?, ProcessExit::Code(23));
        anyhow::Ok(())
    }
    .await;
    let closed = helper.close().await;
    observed?;
    closed
}
