//! macOS resident commands use the existing process-wrap Unix group owner.
//!
//! macOS has no Linux subreaper. We supervise the launched group, keep stdin open,
//! and fail native-exit reporting if reclamation was necessary instead of reporting
//! an empty descendant list as proof of product cleanup. Children that create a
//! new session are outside this platform mechanism's coverage.

use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail, ensure};
use nix::errno::Errno;
use nix::sys::signal::{Signal, killpg};
use nix::unistd::Pid;
use process_wrap::std::{ChildWrapper, CommandWrap, ProcessGroup};

static CANCELLED: AtomicBool = AtomicBool::new(false);
static SIGNALS: OnceLock<Result<(), String>> = OnceLock::new();
static RESIDENT_OWNER: Mutex<()> = Mutex::new(());

struct ResidentGroup {
    child: Box<dyn ChildWrapper>,
    closed: bool,
}

impl Drop for ResidentGroup {
    fn drop(&mut self) {
        if !self.closed {
            let _ = self.child.start_kill();
            let _ = self.child.wait();
        }
    }
}

fn group_exists(pid: u32) -> Result<bool> {
    match killpg(Pid::from_raw(i32::try_from(pid)?), None) {
        Ok(()) => Ok(true),
        Err(Errno::ESRCH) => Ok(false),
        Err(error) => Err(error).context("inspect resident process group"),
    }
}

pub(super) fn run_resident(command: &mut Command, display: &str) -> Result<super::ResidentExit> {
    let _owner = RESIDENT_OWNER
        .lock()
        .map_err(|_| anyhow::anyhow!("resident owner poisoned"))?;
    SIGNALS
        .get_or_init(|| {
            ctrlc::set_handler(|| CANCELLED.store(true, Ordering::Release))
                .map_err(|error| error.to_string())
        })
        .as_ref()
        .map_err(|error| anyhow::anyhow!(error.clone()))?;
    CANCELLED.store(false, Ordering::Release);
    super::print_command_context(command, display);
    command.stdin(Stdio::piped());
    let owned = std::mem::replace(command, Command::new("true"));
    let mut wrapped = CommandWrap::from(owned);
    wrapped.wrap(ProcessGroup::leader());
    let child = wrapped.spawn().context("start resident process group")?;
    let pid = child.id();
    let mut group = ResidentGroup {
        child,
        closed: false,
    };
    eprintln!("resident command started: pid={pid}, command={display}");
    let mut status = None;
    let mut closing = None;
    let mut signalled = false;
    let mut reclaimed = false;
    loop {
        // Observe the direct child's real status without process-wrap's group wait
        // hiding a still-running descendant. Only this owner waits for the child.
        if status.is_none() {
            status = group.child.inner_mut().try_wait()?;
        }
        let cancelled = CANCELLED.load(Ordering::Acquire);
        if status.is_some() && !group_exists(pid)? {
            group.closed = true;
            if reclaimed && !cancelled {
                bail!(
                    "resident process group {pid} leaked descendants; the harness reclaimed them"
                );
            }
            return Ok(super::ResidentExit {
                pid,
                status: status.context("resident root was not reaped")?,
                descendants_at_root_exit: Vec::new(),
                reclaimed_descendants: Vec::new(),
                cancelled,
            });
        }
        if closing.is_none() && (status.is_some() || cancelled) {
            closing = Some(Instant::now());
        }
        if let Some(started) = closing {
            if cancelled && !signalled {
                signal_group(pid, Signal::SIGTERM)?;
                signalled = true;
            }
            if started.elapsed() >= Duration::from_secs(3) {
                reclaimed = true;
                signal_group(pid, Signal::SIGKILL)?;
            }
            ensure!(
                started.elapsed() < Duration::from_secs(6),
                "resident process group {pid} cleanup timed out"
            );
        }
        std::thread::sleep(Duration::from_millis(30));
    }
}

fn signal_group(pid: u32, signal: Signal) -> Result<()> {
    match killpg(Pid::from_raw(i32::try_from(pid)?), signal) {
        Ok(()) | Err(Errno::ESRCH) => Ok(()),
        Err(error) => Err(error).context("signal resident process group"),
    }
}

#[cfg(test)]
mod tests {
    use super::run_resident;
    use std::process::{Command, Stdio};

    /// The harness must expose the direct child's real nonzero exit status.
    #[test]
    fn reports_native_exit_status() -> anyhow::Result<()> {
        let mut command = Command::new("/bin/sh");
        command.args(["-c", "exit 7"]);
        let exit = run_resident(&mut command, "native status fixture")?;
        assert_eq!(exit.status.code(), Some(7));
        assert!(!exit.cancelled);
        Ok(())
    }

    /// A root that abandons a child must fail reporting, and the group owner
    /// must terminate that real child before returning the failure.
    #[test]
    fn reclaims_leaked_group_without_reporting_success() -> anyhow::Result<()> {
        let directory = tempfile::tempdir()?;
        let pid_path = directory.path().join("child.pid");
        let mut command = Command::new("/bin/sh");
        command
            .args([
                "-c",
                "sleep 60 & printf '%s' \"$!\" > \"$1\"; exit 0",
                "fixture",
            ])
            .arg(&pid_path)
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        let result = run_resident(&mut command, "leaking native fixture");
        assert!(
            result
                .unwrap_err()
                .to_string()
                .contains("leaked descendants")
        );
        let pid: i32 = std::fs::read_to_string(pid_path)?.parse()?;
        assert_eq!(
            nix::sys::signal::kill(nix::unistd::Pid::from_raw(pid), None),
            Err(nix::errno::Errno::ESRCH)
        );
        Ok(())
    }
}
