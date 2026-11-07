#![cfg(target_os = "linux")]

use std::error::Error;
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixStream;
use std::process::Stdio;
use std::time::Duration;

use pl_protocol::process_worker::{
    PROCESS_WORKER_PROTOCOL_VERSION, ProcessWorkerCommand, ProcessWorkerConfiguration,
    ProcessWorkerEvent,
};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

#[tokio::test]
async fn terminal_delivery_drains_late_cancellation_before_worker_exit()
-> Result<(), Box<dyn Error>> {
    let (parent, worker) = UnixStream::pair()?;
    parent.set_nonblocking(true)?;
    let control = tokio::net::UnixStream::from_std(parent)?;
    let descriptor = worker.as_raw_fd();
    let mut command = tokio::process::Command::new(env!("CARGO_BIN_EXE_pl-remote-helper"));
    command
        .args(["--process-worker", &descriptor.to_string()])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .kill_on_drop(true);
    // SAFETY: worker owns descriptor until spawn returns. The child hook only uses
    // async-signal-safe fcntl on its copied descriptor table, without allocating or locking.
    unsafe {
        command.pre_exec(move || {
            let flags = libc::fcntl(descriptor, libc::F_GETFD);
            if flags < 0 || libc::fcntl(descriptor, libc::F_SETFD, flags & !libc::FD_CLOEXEC) < 0 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut child = command.spawn()?;
    drop(command);
    drop(worker);
    let (reader, mut writer) = control.into_split();
    let mut events = BufReader::new(reader).lines();
    let outcome = tokio::time::timeout(Duration::from_secs(10), async {
        let ready = events.next_line().await?.ok_or("missing Ready")?;
        let ready = serde_json::from_str::<ProcessWorkerEvent>(&ready)?;
        if ready
            != (ProcessWorkerEvent::Ready {
                protocol_version: PROCESS_WORKER_PROTOCOL_VERSION,
            })
        {
            return Err("unexpected Ready".into());
        }
        let configuration = serde_json::to_vec(&ProcessWorkerConfiguration {
            program: b"/bin/sh".to_vec(),
            arguments: vec![b"-c".to_vec(), b"exit 23".to_vec()],
            directory: None,
            environment: Vec::new(),
        })?;
        writer
            .write_all(&(configuration.len() as u32).to_be_bytes())
            .await?;
        writer.write_all(&configuration).await?;
        writer
            .write_all(&[ProcessWorkerCommand::Start as u8])
            .await?;
        let mut observed = Vec::new();
        while let Some(event) = events.next_line().await? {
            observed.push(serde_json::from_str::<ProcessWorkerEvent>(&event)?);
        }
        // Event EOF seals the result, but cancellation may already be in flight on
        // the opposite half. It must still be drained before the socket is closed.
        writer
            .write_all(&[ProcessWorkerCommand::Cancel as u8])
            .await?;
        writer.shutdown().await?;
        Ok::<_, Box<dyn Error>>(observed)
    })
    .await;
    if !matches!(&outcome, Ok(Ok(_))) {
        child.kill().await?;
    }
    let status = match tokio::time::timeout(Duration::from_secs(10), child.wait()).await {
        Ok(status) => status?,
        Err(error) => {
            child.kill().await?;
            return Err(error.into());
        }
    };
    let observed = outcome??;
    assert!(status.success(), "supervisor failed: {status}");
    assert!(matches!(
        observed.as_slice(),
        [ProcessWorkerEvent::Started { pid }, ProcessWorkerEvent::Exited {
            exit_code: Some(23),
            signal: None,
        }] if *pid > 0
    ));
    Ok(())
}
