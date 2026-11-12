//! One launch scope, distinct from the process-wide last-resort Job.

use std::io;
use std::os::windows::io::{AsHandle, AsRawHandle};
use std::process::{Command, ExitStatus};

use process_wrap_windows::std::JobObjectHandle;
use process_wrap_windows::std::{
    ChildWrapper, CommandWrap, CreationFlags, JobObject, JobObjectChild,
};
use windows_sys::Win32::System::JobObjects::{
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION, JobObjectBasicAccountingInformation,
    QueryInformationJobObject,
};

/// A process and its dedicated Job, assigned before the child resumes.
/// Assignment is suspended-start orchestration, not atomic creation-time assignment.
/// Root status and Job completion are deliberately separate observations.
#[derive(Debug)]
pub struct OwnedChild {
    child: Box<dyn ChildWrapper>,
    job: JobObjectHandle,
}

impl OwnedChild {
    /// Consumes a configured command; pass all Windows flags explicitly because
    /// std does not expose flags previously set on a `Command`.
    pub fn spawn(command: Command, flags: u32) -> io::Result<Self> {
        let mut command = CommandWrap::from(command);
        command.wrap(CreationFlags(flags)).wrap(JobObject);
        let child = command.spawn()?;
        let job = (child.as_ref() as &dyn std::any::Any)
            .downcast_ref::<JobObjectChild>()
            .expect("JobObject is the outermost wrapper")
            .job_handle()
            .clone();
        Ok(Self { child, job })
    }

    /// OS identity of the root, retained after it exits.
    pub fn id(&self) -> u32 {
        self.child.id()
    }

    /// Observe only the root; this never enters process-wrap's Job wait loop.
    pub fn try_wait(&mut self) -> io::Result<Option<ExitStatus>> {
        // The sole child wrapper is JobObject, whose direct inner is std Child.
        // Do not call JobObjectChild::try_wait (completion-port drain) here.
        self.child.inner_mut().try_wait()
    }

    /// One bounded kernel query. Errors never imply an empty tree.
    pub fn tree_exited(&self) -> io::Result<bool> {
        job_is_empty(&self.job)
    }

    /// Request termination of the whole scope, including after root exit.
    pub fn terminate(&self) -> io::Result<()> {
        self.job.terminate(1)
    }
}

fn job_is_empty(job: &impl AsHandle) -> io::Result<bool> {
    // SAFETY: zero is valid for this output-only C accounting structure.
    let mut info: JOBOBJECT_BASIC_ACCOUNTING_INFORMATION = unsafe { std::mem::zeroed() };
    // SAFETY: the borrow keeps the Job handle live; the writable, aligned local
    // buffer and its exact size match the requested information class. The API
    // retains no pointer and we read the output only after success.
    let result = unsafe {
        QueryInformationJobObject(
            job.as_handle().as_raw_handle(),
            JobObjectBasicAccountingInformation,
            std::ptr::addr_of_mut!(info).cast(),
            std::mem::size_of_val(&info) as u32,
            std::ptr::null_mut(),
        )
    };
    if result == 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(info.ActiveProcesses == 0)
}

impl Drop for OwnedChild {
    fn drop(&mut self) {
        // No KillOnDrop wrapper: its synchronous wait would defeat the caller's
        // deadline. Termination is only a last request, never completion proof.
        if let Err(error) = self.terminate() {
            eprintln!("failed to terminate Windows launch Job: {error}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::process::Stdio;
    use std::time::{Duration, Instant};

    const FIXTURE: &str = "process::windows::child::tests::job_fixture";

    #[test]
    fn job_fixture() -> anyhow::Result<()> {
        let Some(directory) = std::env::var_os("PL_JOB_FIXTURE") else {
            return Ok(());
        };
        let directory = std::path::PathBuf::from(directory);
        if std::env::var_os("PL_JOB_WORKER").is_some() {
            fs::write(directory.join("ready"), "ready")?;
            let deadline = Instant::now() + Duration::from_secs(20);
            while !directory.join("release").exists() {
                anyhow::ensure!(Instant::now() < deadline, "worker release timed out");
                std::thread::sleep(Duration::from_millis(10));
            }
        } else {
            let _worker = Command::new(std::env::current_exe()?)
                .args(["--exact", FIXTURE, "--nocapture"])
                .env("PL_JOB_WORKER", "1")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()?;
        }
        Ok(())
    }

    #[test]
    fn job_completion_survives_root_exit_and_stop() -> anyhow::Result<()> {
        for terminate in [false, true] {
            let directory = tempfile::tempdir()?;
            let mut command = Command::new(std::env::current_exe()?);
            command
                .args(["--exact", FIXTURE, "--nocapture"])
                .env("PL_JOB_FIXTURE", directory.path())
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null());
            let mut child = OwnedChild::spawn(command, 0)?;
            let deadline = Instant::now() + Duration::from_secs(10);
            while child.try_wait()?.is_none() || !directory.path().join("ready").exists() {
                anyhow::ensure!(Instant::now() < deadline, "root/worker not ready");
                std::thread::sleep(Duration::from_millis(10));
            }
            assert!(!child.tree_exited()?, "root exit is not tree exit");
            if terminate {
                child.terminate()?;
            } else {
                fs::write(directory.path().join("release"), "release")?;
            }
            let deadline = Instant::now() + Duration::from_secs(10);
            while !child.tree_exited()? {
                anyhow::ensure!(Instant::now() < deadline, "Job did not exit");
                std::thread::sleep(Duration::from_millis(10));
            }
            assert!(child.tree_exited()?);
        }
        Ok(())
    }

    #[test]
    fn query_failure_is_not_completion() -> anyhow::Result<()> {
        let file = tempfile::tempfile()?;
        assert!(job_is_empty(&file).is_err());
        Ok(())
    }
}
