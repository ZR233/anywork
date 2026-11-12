//! Public execution semantics exercised with actual operating-system processes.
#![cfg(unix)]

use pl_remote_helper::{CaptureSpec, CaptureState, Executor, ProcessExit, StartKnowledge, Stdio};
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[tokio::test]
async fn literal_arguments_and_concurrent_environment_and_directories() {
    both(|executor| async move {
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
        match failure.cause {
            pl_remote_helper::ExecutionError::Io { source, .. } => {
                assert_eq!(source.kind(), std::io::ErrorKind::NotFound)
            }
            pl_remote_helper::ExecutionError::TargetIo(source) => {
                assert_eq!(source.kind, pl_remote_helper::IoErrorKind::NotFound)
            }
            error => panic!("spawn must retain the typed target IO failure: {error}"),
        }
        assert!(
            executor
                .command("/bin/true")
                .stdout(Stdio::Piped)
                .status()
                .await
                .is_err()
        );
    })
    .await;
}

#[tokio::test]
async fn stdin_drop_delivers_all_accepted_bytes_before_eof() {
    both(|executor| async move {
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
    })
    .await;
}

#[tokio::test]
async fn root_exit_is_independent_of_an_inherited_output_pipe() {
    both(|executor| async move {
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
    })
    .await;
}

#[tokio::test]
async fn cancelled_wait_can_be_waited_again_and_kill_is_idempotent() {
    both(|executor| async move {
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
    })
    .await;
}

#[tokio::test]
async fn capture_limit_counts_both_binary_streams_and_accepts_exact_limit() {
    both(|executor| async move {
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
    })
    .await;
}

async fn both<F, Fut>(case: F)
where
    F: Fn(Executor) -> Fut,
    Fut: std::future::Future<Output = ()>,
{
    both_with_timeout(Duration::from_secs(10), case).await;
}

async fn both_with_timeout<F, Fut>(budget: Duration, case: F)
where
    F: Fn(Executor) -> Fut,
    Fut: std::future::Future<Output = ()>,
{
    case(Executor::local().unwrap()).await;
    let (client, server) = tokio::io::duplex(1024 * 1024);
    let owner = tokio::spawn(pl_remote_helper::serve_connection(server));
    let executor = Executor::remote(client).await.unwrap();
    tokio::time::timeout(budget, case(executor))
        .await
        .expect("remote execution case timed out");
    tokio::time::timeout(Duration::from_secs(5), owner)
        .await
        .expect("server cleanup timed out")
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn unread_output_does_not_block_another_exit_or_kill() {
    both(|executor| async move {
        let mut flooding = executor
            .command("/bin/sh")
            .args(["-c", "while :; do printf 'unread output'; done"])
            .stdout(Stdio::Piped)
            .spawn()
            .await
            .unwrap();
        let other = tokio::time::timeout(
            Duration::from_secs(5),
            executor.command("/bin/echo").arg("independent").output(),
        )
        .await
        .unwrap()
        .unwrap();
        assert_eq!(other.stdout, b"independent\n");
        tokio::time::timeout(Duration::from_secs(5), flooding.kill())
            .await
            .unwrap()
            .unwrap();
    })
    .await;
}

#[tokio::test]
async fn connection_close_is_terminal_and_preserves_a_completed_exit() {
    let (client, server) = tokio::io::duplex(1024 * 1024);
    let owner = tokio::spawn(pl_remote_helper::serve_connection(server));
    let executor = Executor::remote(client).await.unwrap();
    let mut finished = executor
        .command("/bin/sh")
        .args(["-c", "exit 255"])
        .spawn()
        .await
        .unwrap();
    assert_eq!(finished.wait().await.unwrap(), ProcessExit::Code(255));
    let mut running = executor
        .command("/bin/cat")
        .stdin(Stdio::Piped)
        .spawn()
        .await
        .unwrap();
    let input = running.stdin.take().unwrap();
    executor.close().await.unwrap();
    assert!(running.wait().await.is_err());
    assert_eq!(finished.wait().await.unwrap(), ProcessExit::Code(255));
    assert_eq!(
        executor
            .command("/bin/true")
            .spawn()
            .await
            .unwrap_err()
            .knowledge,
        StartKnowledge::NotStarted
    );
    drop(input);
    drop(running);
    drop(finished);
    drop(executor);
    tokio::time::timeout(Duration::from_secs(5), owner)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn unread_eos_readers_keep_admission_and_bulk_drop_restores_capacity() {
    let (client, server) = tokio::io::duplex(1024 * 1024);
    let owner = tokio::spawn(pl_remote_helper::serve_connection(server));
    let executor = Executor::remote(client).await.unwrap();
    let directory = tempfile::tempdir().unwrap();
    let empty = directory.path().join("empty");
    tokio::fs::write(&empty, b"").await.unwrap();
    let path = executor.path(empty.to_str().unwrap()).unwrap();
    let mut live = executor
        .command("/bin/sleep")
        .arg("60")
        .spawn()
        .await
        .unwrap();
    let mut readers = Vec::new();
    for _ in 0..239 {
        readers.push(executor.fs().read(&path).await.unwrap());
    }
    let mut command = executor.command("/bin/true");
    assert!(
        tokio::time::timeout(Duration::from_millis(50), command.spawn())
            .await
            .is_err(),
        "unread EOS readers must retain all ordinary admission"
    );
    tokio::time::timeout(Duration::from_secs(5), live.kill())
        .await
        .unwrap()
        .unwrap();
    // Killing the root released one ordinary permit; a piped command still
    // needs a two-stream bundle, so the unconsumed readers must keep it waiting.
    command.stdout(Stdio::Piped);
    let mut pending = Box::pin(command.spawn());
    assert!(futures::poll!(&mut pending).is_pending());
    drop(readers);
    let mut child = tokio::time::timeout(Duration::from_secs(5), pending)
        .await
        .unwrap()
        .unwrap();
    child.wait().await.unwrap();
    drop(child);
    drop(command);
    drop(live);
    executor.close().await.unwrap();
    drop(executor);
    tokio::time::timeout(Duration::from_secs(5), owner)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
}

#[tokio::test]
async fn streaming_files_require_finish_and_preserve_the_previous_target_on_failure() {
    both(|executor| async move {
        use pl_remote_helper::fs::WriteMode;
        let directory = tempfile::tempdir().unwrap();
        let path = executor
            .path(directory.path().join("target").to_str().unwrap())
            .unwrap();
        tokio::fs::write(path.as_str(), b"original").await.unwrap();
        let mut abandoned = executor
            .fs()
            .write(&path, WriteMode::ReplaceAtomic, Some(100))
            .await
            .unwrap();
        abandoned.write_all(b"incomplete").await.unwrap();
        assert_eq!(
            abandoned.shutdown().await.unwrap_err().kind(),
            std::io::ErrorKind::Unsupported
        );
        drop(abandoned);
        assert_eq!(tokio::fs::read(path.as_str()).await.unwrap(), b"original");
        let mut short = executor
            .fs()
            .write(&path, WriteMode::ReplaceAtomic, Some(10))
            .await
            .unwrap();
        short.write_all(b"short").await.unwrap();
        assert!(short.finish().await.is_err());
        assert_eq!(tokio::fs::read(path.as_str()).await.unwrap(), b"original");
        let bytes = (0..4_000_000)
            .map(|index| (index % 251) as u8)
            .collect::<Vec<_>>();
        let mut writer = executor
            .fs()
            .write(&path, WriteMode::ReplaceAtomic, Some(bytes.len() as u64))
            .await
            .unwrap();
        writer.write_all(&bytes).await.unwrap();
        assert_eq!(writer.finish().await.unwrap().bytes, bytes.len() as u64);
        let mut actual = Vec::new();
        executor
            .fs()
            .read(&path)
            .await
            .unwrap()
            .read_to_end(&mut actual)
            .await
            .unwrap();
        assert_eq!(actual, bytes);
        let create = executor
            .fs()
            .write(&path, WriteMode::CreateNew, Some(0))
            .await
            .unwrap();
        assert!(create.finish().await.is_err());
        let empty_path = executor
            .path(directory.path().join("empty").to_str().unwrap())
            .unwrap();
        let empty = executor
            .fs()
            .write(&empty_path, WriteMode::CreateNew, Some(0))
            .await
            .unwrap();
        assert_eq!(empty.finish().await.unwrap().bytes, 0);
        assert_eq!(
            executor
                .fs()
                .metadata(&empty_path)
                .await
                .unwrap()
                .unwrap()
                .len,
            0
        );
    })
    .await;
}

#[tokio::test]
async fn directory_names_and_symlink_parent_paths_are_interpreted_on_the_target() {
    both(|executor| async move {
        let directory = tempfile::tempdir().unwrap();
        tokio::fs::create_dir_all(directory.path().join("nested/child"))
            .await
            .unwrap();
        tokio::fs::write(directory.path().join("nested/document"), b"through link/..")
            .await
            .unwrap();
        tokio::fs::write(directory.path().join("line\nbreak"), b"")
            .await
            .unwrap();
        std::os::unix::fs::symlink(
            directory.path().join("nested/child"),
            directory.path().join("link"),
        )
        .unwrap();
        let root = executor.path(directory.path().to_str().unwrap()).unwrap();
        let file = executor.join_path(&root, "link/../document").unwrap();
        let mut actual = Vec::new();
        executor
            .fs()
            .read(&file)
            .await
            .unwrap()
            .read_to_end(&mut actual)
            .await
            .unwrap();
        assert_eq!(actual, b"through link/..");
        let mut entries = executor.fs().read_dir(&root).await.unwrap();
        let mut names = Vec::new();
        while let Some(entry) = entries.next().await.unwrap() {
            names.push(entry.name);
        }
        assert!(names.contains(&"line\nbreak".to_owned()));
        let other = Executor::local().unwrap();
        assert!(other.fs().metadata(&file).await.is_err());
    })
    .await;
}

#[tokio::test]
async fn target_side_patch_keeps_ordered_partial_facts_and_rejects_oversized_reports_before_writes()
{
    both(|executor| async move {
        use pl_patch::PatchChange;
        let directory = tempfile::tempdir().unwrap();
        let root = executor.path(directory.path().to_str().unwrap()).unwrap();
        let patch = "*** Begin Patch\n*** Add File: document\n+before\n*** Update File: document\n@@\n-before\n+after\n*** End Patch\n";
        let report = executor.fs().apply_patch(&root, patch).await.unwrap();
        assert!(matches!(report.changes.as_slice(), [PatchChange::Add { .. }, PatchChange::Update { .. }]));
        assert_eq!(tokio::fs::read_to_string(directory.path().join("document")).await.unwrap(), "after\n");
        let partial = "*** Begin Patch\n*** Add File: saved\n+kept\n*** Delete File: missing\n*** End Patch\n";
        let failure = executor.fs().apply_patch(&root, partial).await.unwrap_err();
        let pl_remote_helper::PatchExecutionError::Patch(failure) = failure else { panic!("expected structured patch failure") };
        assert!(matches!(failure.applied_changes.as_slice(), [PatchChange::Add { .. }]));
        assert!(!failure.changes_may_be_incomplete);
        let mut oversized = String::from("*** Begin Patch\n*** Add File: must-not-exist\n+rejected\n");
        for index in 0..600 { oversized.push_str(&format!("*** Add File: {index}{}\n+small\n", "x".repeat(1000))); }
        oversized.push_str("*** End Patch\n");
        let failure = executor.fs().apply_patch(&root, &oversized).await.unwrap_err();
        assert!(failure.to_string().contains("ReportTooLarge"));
        assert!(!directory.path().join("must-not-exist").exists());
    }).await;
}

#[tokio::test]
async fn dropping_unread_capture_is_incomplete_even_after_root_exit() {
    both(|executor| async move {
        let directory = tempfile::tempdir().unwrap();
        let mut child = executor
            .command("/bin/echo")
            .arg("unread")
            .stdout(Stdio::Piped)
            .stderr(Stdio::Piped)
            .capture(CaptureSpec {
                stdout_path: directory.path().join("stdout").to_str().unwrap().into(),
                stderr_path: directory.path().join("stderr").to_str().unwrap().into(),
                max_bytes: 1024,
            })
            .spawn()
            .await
            .unwrap();
        child.wait().await.unwrap();
        assert!(futures::poll!(Box::pin(child.finish_capture())).is_pending());
        drop(child.stdout.take());
        let mut stderr = Vec::new();
        child
            .stderr
            .take()
            .unwrap()
            .read_to_end(&mut stderr)
            .await
            .unwrap();
        let capture = child.finish_capture().await.unwrap().unwrap();
        assert_eq!(capture.stdout.state, CaptureState::Incomplete);
        assert_eq!(capture.stdout.confirmed_bytes, None);
        assert_eq!(capture.stderr.state, CaptureState::Complete);
    })
    .await;
}

#[tokio::test]
async fn http_early_response_survives_infinite_upload_and_returns_stream_credit() {
    // The batch itself has a 30-second progress deadline; its outer owner must
    // allow that deadline and final cleanup, rather than cutting it off at ten seconds.
    both_with_timeout(Duration::from_secs(40), |executor| async move {
        use pl_remote_helper::http::HttpRequest;
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let address = listener.local_addr().unwrap();
        let peer = tokio::spawn(async move {
            for _ in 0..520 {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut header = Vec::new();
                while !header.windows(4).any(|bytes| bytes == b"\r\n\r\n") {
                    let mut bytes = [0; 1024];
                    let count = socket.read(&mut bytes).await.unwrap();
                    assert_ne!(count, 0);
                    header.extend_from_slice(&bytes[..count]);
                }
                socket.write_all(b"HTTP/1.1 413 Payload Too Large\r\nContent-Length: 3\r\nConnection: close\r\n\r\nend").await.unwrap();
                socket.shutdown().await.unwrap();
                // Keep the TCP read half alive until the client stops uploading;
                // dropping a socket with unread input would inject RST and invalidate
                // the HTTP response independently of the execution transport.
                let _ = tokio::io::copy(&mut socket, &mut tokio::io::sink()).await;
            }
        });
        let http = executor.http();
        tokio::time::timeout(Duration::from_secs(30), async {
            for _ in 0..520 {
                let mut response = http.execute(HttpRequest {
                    method: "POST".into(), url: format!("http://{address}/early"), headers: vec![], bearer_token_env_var: None,
                }, Box::pin(tokio::io::repeat(0x80))).await.unwrap();
                assert_eq!(response.head.status, 413);
                let mut body = Vec::new();
                response.body.read_to_end(&mut body).await.unwrap();
                assert_eq!(body, b"end");
            }
        }).await.expect("early responses must release upload owner, credit and admission");
        tokio::time::timeout(Duration::from_secs(2),peer).await.expect("HTTP peer cleanup timed out").unwrap();
        assert_eq!(executor.command("/bin/true").status().await.unwrap(), ProcessExit::Code(0));
    }).await;
}

#[tokio::test]
async fn filesystem_mutations_run_on_target_and_closed_handles_are_terminal() {
    both(|executor| async move {
        let directory = tempfile::tempdir().unwrap();
        let root = executor.path(directory.path().to_str().unwrap()).unwrap();
        let fs = executor.fs();
        let source = executor.join_path(&root, "source").unwrap();
        fs.create_dir(&source, false).await.unwrap();
        let file = executor.join_path(&source, "line\nbreak.bin").unwrap();
        let mut writer = fs
            .write(&file, pl_remote_helper::fs::WriteMode::CreateNew, Some(3))
            .await
            .unwrap();
        writer.write_all(b"\0\xff!").await.unwrap();
        writer.finish().await.unwrap();
        let target = executor.join_path(&root, "copy").unwrap();
        fs.copy_path(&source, &target, false).await.unwrap_err();
        fs.copy_path(&source, &target, true).await.unwrap();
        let copied = executor.join_path(&target, "line\nbreak.bin").unwrap();
        let mut bytes = Vec::new();
        fs.read(&copied)
            .await
            .unwrap()
            .read_to_end(&mut bytes)
            .await
            .unwrap();
        assert_eq!(bytes, b"\0\xff!");
        let renamed = executor.join_path(&root, "renamed").unwrap();
        fs.rename(&target, &renamed).await.unwrap();
        fs.remove(&renamed, true).await.unwrap();
        assert!(fs.metadata(&renamed).await.unwrap().is_none());
        // A destination hardlink must not truncate the source inode. The same
        // atomic publisher also keeps source permissions on the copied entry.
        use std::os::unix::fs::{MetadataExt, PermissionsExt};
        tokio::fs::set_permissions(file.as_str(), std::fs::Permissions::from_mode(0o640))
            .await
            .unwrap();
        let hardlink = executor.join_path(&root, "hardlink").unwrap();
        tokio::fs::hard_link(file.as_str(), hardlink.as_str())
            .await
            .unwrap();
        fs.copy_path(&file, &hardlink, false).await.unwrap();
        assert_eq!(tokio::fs::read(file.as_str()).await.unwrap(), b"\0\xff!");
        assert_eq!(
            tokio::fs::read(hardlink.as_str()).await.unwrap(),
            b"\0\xff!"
        );
        assert_ne!(
            tokio::fs::metadata(file.as_str()).await.unwrap().ino(),
            tokio::fs::metadata(hardlink.as_str()).await.unwrap().ino()
        );
        assert_eq!(
            tokio::fs::metadata(hardlink.as_str())
                .await
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o640
        );
        executor.close().await.unwrap();
        assert!(fs.read(&file).await.is_err());
        assert!(fs.create_dir(&target, false).await.is_err());
        assert!(executor.command("/bin/true").spawn().await.is_err());
    })
    .await;
}

#[tokio::test]
async fn executor_close_reclaims_native_pipes_even_when_public_handles_are_unpolled() {
    both(|executor| async move {
        let mut child = executor
            .command("/bin/sh")
            .args(["-c", "exec 3<&0; cat <&3 & exit 9"])
            .stdin(Stdio::Piped)
            .stdout(Stdio::Piped)
            .spawn()
            .await
            .unwrap();
        let mut input = child.stdin.take().unwrap();
        let mut output = child.stdout.take().unwrap();
        assert_eq!(child.wait().await.unwrap(), ProcessExit::Code(9));
        executor.close().await.unwrap();
        let mut bytes = [0; 8];
        assert!(
            tokio::time::timeout(Duration::from_secs(1), output.read(&mut bytes))
                .await
                .unwrap()
                .is_err()
        );
        assert!(input.write_all(b"closed").await.is_err());
        assert_eq!(child.wait().await.unwrap(), ProcessExit::Code(9));
    })
    .await;
}

#[tokio::test]
async fn non_utf8_directory_names_fail_without_closing_the_connection() {
    use std::os::unix::ffi::OsStringExt;
    both(|executor| async move {
        let directory = tempfile::tempdir().unwrap();
        tokio::fs::write(
            directory
                .path()
                .join(std::ffi::OsString::from_vec(vec![0xff])),
            b"private",
        )
        .await
        .unwrap();
        let path = executor.path(directory.path().to_str().unwrap()).unwrap();
        let mut reader = executor.fs().read_dir(&path).await.unwrap();
        let error = reader.next().await.unwrap_err();
        assert!(error.to_string().contains("UTF-8"), "{error}");
        assert_eq!(
            executor.command("/bin/true").status().await.unwrap(),
            ProcessExit::Code(0)
        );
    })
    .await;
}

#[tokio::test]
async fn cancelled_directory_observations_keep_entries_and_close_releases_unread_files() {
    both(|executor| async move {
        let directory = tempfile::tempdir().unwrap();
        let mut expected = std::collections::BTreeSet::new();
        for index in 0..512 {
            let name = format!("{index:04}-{}", "x".repeat(220));
            tokio::fs::write(directory.path().join(&name), b"entry")
                .await
                .unwrap();
            expected.insert(name);
        }
        let root = executor.path(directory.path().to_str().unwrap()).unwrap();
        let mut reader = executor.fs().read_dir(&root).await.unwrap();
        let mut observed = std::collections::BTreeSet::new();
        loop {
            let mut next = Box::pin(reader.next());
            let entry = match futures::poll!(next.as_mut()) {
                std::task::Poll::Ready(entry) => entry,
                std::task::Poll::Pending => {
                    // Cancel only this observation, retaining the same directory.
                    drop(next);
                    reader.next().await
                }
            }
            .unwrap();
            let Some(entry) = entry else { break };
            assert!(
                observed.insert(entry.name),
                "iteration must not duplicate an entry"
            );
        }
        assert_eq!(
            observed, expected,
            "cancelled next futures must not discard entries or partial records"
        );
        let large = executor.join_path(&root, "unread.bin").unwrap();
        tokio::fs::write(large.as_str(), vec![0x80; 256 * 1024])
            .await
            .unwrap();
        let mut unread = executor.fs().read(&large).await.unwrap();
        executor.close().await.unwrap();
        assert!(unread.read(&mut [0; 1]).await.is_err());
        assert!(
            reader.next().await.unwrap().is_none(),
            "known directory EOF remains valid"
        );
    })
    .await;
}
