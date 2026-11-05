#![cfg(windows)]

use std::io::{Read, Write};
use std::os::windows::io::AsHandle;
use std::process::Stdio;
use std::time::Duration;

use pl_remote_helper::process::{
    BackgroundSpawnError, spawn_background_command, wrap_background_command,
};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

#[test]
#[ignore = "child process fixture"]
fn pipe_child() {
    assert!(std::env::var_os("ANYWORK_PIPE_TEST_CHILD").is_some());
    let mut input = Vec::new();
    std::io::stdin().read_to_end(&mut input).unwrap();
    if std::env::var_os("ANYWORK_PIPE_TEST_IDLE").is_some() {
        std::process::exit(0);
    }
    assert_eq!(input, vec![b'i'; 128 * 1024]);
    for _ in 0..256 {
        std::io::stdout().write_all(&[b'o'; 1024]).unwrap();
        std::io::stderr().write_all(&[b'e'; 1024]).unwrap();
        std::thread::yield_now();
    }
    std::process::exit(0);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn background_process_drains_parallel_pipes() -> std::io::Result<()> {
    let mut runs = tokio::task::JoinSet::new();
    for _ in 0..32 {
        runs.spawn(async {
            let mut command = tokio::process::Command::new(std::env::current_exe()?);
            command
                .args(["--ignored", "--exact", "pipe_child", "--nocapture"])
                .env("ANYWORK_PIPE_TEST_CHILD", "1")
                .stdin(Stdio::piped())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped());
            let mut command = wrap_background_command(command);
            let child = spawn_background_command(&mut command)?;
            let mut process = child.process;
            let mut stdin = child.stdin.unwrap();
            let mut stdout = child.stdout.unwrap();
            let mut stderr = child.stderr.unwrap();
            let inspected = std::fs::File::from(stdout.as_handle().try_clone_to_owned()?);
            let inspection = tokio::task::spawn_blocking(move || {
                for _ in 0..100 {
                    // Pipe metadata may be unsupported. The query itself must
                    // never complete a different pending read on this handle.
                    let _ = inspected.metadata();
                    std::thread::sleep(Duration::from_millis(1));
                }
            });
            let mut output = Vec::new();
            let mut errors = Vec::new();
            let input = async move {
                stdin.write_all(&vec![b'i'; 128 * 1024]).await?;
                stdin.flush().await?;
                drop(stdin);
                std::io::Result::Ok(())
            };
            let (status, _, _, _) = tokio::try_join!(
                process.wait(),
                input,
                stdout.read_to_end(&mut output),
                stderr.read_to_end(&mut errors),
            )?;
            assert!(status.success(), "{status}");
            assert!(output.ends_with(&vec![b'o'; 256 * 1024]));
            assert_eq!(errors, vec![b'e'; 256 * 1024]);
            inspection.await.unwrap();
            std::io::Result::Ok(())
        });
    }
    tokio::time::timeout(Duration::from_secs(30), async {
        while let Some(result) = runs.join_next().await {
            result.unwrap()?;
        }
        std::io::Result::Ok(())
    })
    .await??;
    Ok(())
}

#[test]
fn idle_pipe_reads_leave_the_blocking_pool_available() -> std::io::Result<()> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .max_blocking_threads(1)
        .enable_all()
        .build()?;
    runtime.block_on(async {
        let mut command = tokio::process::Command::new(std::env::current_exe()?);
        command
            .args(["--ignored", "--exact", "pipe_child", "--nocapture"])
            .env("ANYWORK_PIPE_TEST_CHILD", "1")
            .env("ANYWORK_PIPE_TEST_IDLE", "1")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut command = wrap_background_command(command);
        let mut child = spawn_background_command(&mut command)?;
        let mut stdout = child.stdout.take().unwrap();
        let mut stderr = child.stderr.take().unwrap();
        let mut output = Vec::new();
        let mut errors = Vec::new();
        let output_read = stdout.read_to_end(&mut output);
        let error_read = stderr.read_to_end(&mut errors);
        tokio::pin!(output_read, error_read);
        assert!(futures::poll!(&mut output_read).is_pending());
        assert!(futures::poll!(&mut error_read).is_pending());
        let worker = tokio::task::spawn_blocking(|| 42);
        let available = tokio::time::timeout(Duration::from_secs(2), worker).await;

        // Always release the real process before asserting: a regression must
        // report failure instead of hanging runtime shutdown on a blocking read.
        child.process.start_kill()?;
        tokio::time::timeout(Duration::from_secs(5), child.process.wait()).await??;
        tokio::time::timeout(Duration::from_secs(5), async {
            tokio::try_join!(output_read, error_read)
        })
        .await??;
        assert_eq!(
            available
                .expect("idle pipes exhausted the blocking pool")
                .unwrap(),
            42
        );
        std::io::Result::Ok(())
    })
}

#[test]
fn stopped_io_driver_reports_failure_after_spawn() -> std::io::Result<()> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    let handle = runtime.handle().clone();
    runtime.shutdown_background();
    let _entered = handle.enter();
    let mut command = tokio::process::Command::new(std::env::current_exe()?);
    command
        .args(["--ignored", "--exact", "pipe_child", "--nocapture"])
        .env("ANYWORK_PIPE_TEST_CHILD", "1")
        .env("ANYWORK_PIPE_TEST_IDLE", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let mut command = wrap_background_command(command);
    // Windows process creation succeeds, but the real, closed I/O driver rejects
    // registration. This must not be reported as a command that never started.
    assert!(matches!(
        spawn_background_command(&mut command),
        Err(BackgroundSpawnError::Stdio(_))
    ));
    Ok(())
}
