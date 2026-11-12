//! Public execution semantics exercised with actual operating-system processes.
#![cfg(unix)]

use pl_remote_helper::{CaptureSpec, CaptureState, Executor, ProcessExit, StartKnowledge, Stdio};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
async fn literal_arguments_and_concurrent_environment_and_directories() {
    let executor = Executor::local().unwrap();
    let left = tempfile::tempdir().unwrap();
    let right = tempfile::tempdir().unwrap();
    let arguments = [
        "",
        "space here",
        "'single'",
        "\"double\"",
        "$HOME",
        "line\nbreak",
        "中文",
    ];
    let run = |directory: String, value: &'static str| {
        let mut command = executor.command("/bin/sh");
        command
            .args(["-c", "printf '%s\\0' \"$PWD\" \"$VALUE\" \"$@\"", "argv"])
            .args(arguments)
            .current_dir(directory)
            .env("VALUE", value);
        async move { command.output().await.unwrap() }
    };
    let (a, b) = tokio::join!(
        run(left.path().to_str().unwrap().into(), "left"),
        run(right.path().to_str().unwrap().into(), "right")
    );
    for (output, directory, value) in [(a, left.path(), "left"), (b, right.path(), "right")] {
        assert_eq!(output.status, ProcessExit::Code(0));
        let fields = output.stdout.split(|byte| *byte == 0).collect::<Vec<_>>();
        assert_eq!(fields[0], directory.to_str().unwrap().as_bytes());
        assert_eq!(fields[1], value.as_bytes());
        assert_eq!(&fields[2..fields.len() - 1], &arguments.map(str::as_bytes));
    }
    let failure = executor
        .command("/definitely/missing/anywork-command")
        .spawn()
        .await
        .unwrap_err();
    assert_eq!(failure.knowledge, StartKnowledge::NotStarted);
    assert!(
        executor
            .command("/bin/true")
            .stdout(Stdio::Piped)
            .status()
            .await
            .is_err()
    );
}

#[tokio::test]
async fn stdin_drop_delivers_all_accepted_bytes_before_eof() {
    let executor = Executor::local().unwrap();
    let mut child = executor
        .command("/bin/cat")
        .stdin(Stdio::Piped)
        .stdout(Stdio::Piped)
        .spawn()
        .await
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    let bytes = (0..200_000).map(|i| (i % 256) as u8).collect::<Vec<_>>();
    let ((), output) = tokio::join!(
        async {
            stdin.write_all(&bytes).await.unwrap();
            drop(stdin);
        },
        child.wait_with_output()
    );
    let output = output.unwrap();
    assert_eq!(output.status, ProcessExit::Code(0));
    assert_eq!(output.stdout, bytes);
}

#[tokio::test]
async fn root_exit_is_independent_of_an_inherited_output_pipe() {
    let executor = Executor::local().unwrap();
    // The descendant blocks on its inherited stdin, keeping stdout open after
    // the shell exits. Explicit input EOF releases it without a timing race.
    let mut child = executor
        .command("/bin/sh")
        .args(["-c", "exec 3<&0; cat <&3 & exit 23"])
        .stdin(Stdio::Piped)
        .stdout(Stdio::Piped)
        .spawn()
        .await
        .unwrap();
    let mut stdin = child.stdin.take().unwrap();
    assert_eq!(
        tokio::time::timeout(Duration::from_secs(5), child.wait())
            .await
            .unwrap()
            .unwrap(),
        ProcessExit::Code(23)
    );
    assert_eq!(child.wait().await.unwrap(), ProcessExit::Code(23));
    assert_eq!(child.id(), None);
    child.kill().await.unwrap();
    stdin.write_all(b"tail after root exit\n").await.unwrap();
    stdin.shutdown().await.unwrap();
    let mut output = Vec::new();
    child
        .stdout
        .take()
        .unwrap()
        .read_to_end(&mut output)
        .await
        .unwrap();
    assert_eq!(output, b"tail after root exit\n");
}

#[tokio::test]
async fn cancelled_wait_can_be_waited_again_and_kill_is_idempotent() {
    let executor = Executor::local().unwrap();
    let mut child = executor
        .command("/bin/cat")
        .stdin(Stdio::Piped)
        .spawn()
        .await
        .unwrap();
    let stdin = child.stdin.take().unwrap();
    assert!(futures::poll!(Box::pin(child.wait())).is_pending());
    assert_eq!(child.try_wait().unwrap(), None);
    child.start_kill().await.unwrap();
    assert!(matches!(
        child.wait().await.unwrap(),
        ProcessExit::Signal(_)
    ));
    child.kill().await.unwrap();
    drop(stdin);
}

#[tokio::test]
async fn capture_limit_counts_both_binary_streams_and_accepts_exact_limit() {
    let executor = Executor::local().unwrap();
    for (length, expected) in [
        (15, CaptureState::Complete),
        (16, CaptureState::Complete),
        (17, CaptureState::LimitExceeded),
    ] {
        let directory = tempfile::tempdir().unwrap();
        let stdout = directory.path().join("stdout");
        let stderr = directory.path().join("stderr");
        let output = executor
            .command("/bin/sh")
            .args([
                "-c",
                "printf '12345678'; head -c \"$1\" /dev/zero >&2",
                "test",
                &(length - 8).to_string(),
            ])
            .stdout(Stdio::Piped)
            .stderr(Stdio::Piped)
            .capture(CaptureSpec {
                stdout_path: stdout.to_str().unwrap().into(),
                stderr_path: stderr.to_str().unwrap().into(),
                max_bytes: 16,
            })
            .output()
            .await
            .unwrap();
        let capture = output.capture.unwrap();
        assert_eq!(
            capture.stdout.confirmed_bytes.unwrap() + capture.stderr.confirmed_bytes.unwrap(),
            length.min(16)
        );
        assert_eq!(output.stdout, tokio::fs::read(stdout).await.unwrap());
        assert_eq!(output.stderr, tokio::fs::read(stderr).await.unwrap());
        if expected == CaptureState::Complete {
            assert_eq!(capture.stdout.state, expected);
            assert_eq!(capture.stderr.state, expected);
        } else {
            assert!([capture.stdout.state, capture.stderr.state].contains(&expected));
        }
    }
}
