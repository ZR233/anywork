//! The Python child alone owns SIGIO and the lease FD. OwnedProcess remains the
//! process-tree owner; callers must close this guard before their GUI runner.

use super::*;

pub(super) struct ImageLease {
    process: OwnedProcess,
    directory: PathBuf,
    joined: bool,
}

impl ImageLease {
    pub(super) fn start(source: &Path, directory: &Path) -> Result<Self> {
        ensure!(cfg!(target_os = "linux"), "media-handoff requires Linux");
        fs::create_dir(directory)?;
        let log = File::create(directory.join("holder.log"))?;
        let mut command = Command::new("python3");
        command
            .args(["-u", "-c", include_str!("image_lease.py")])
            .arg(source)
            .arg(directory)
            .stdin(Stdio::piped())
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));
        let mut lease = Self {
            process: OwnedProcess::start(&mut command, false)?,
            directory: directory.to_owned(),
            joined: false,
        };
        let deadline = Instant::now() + Duration::from_secs(10);
        while !directory.join("ready.json").is_file() {
            ensure!(
                !lease.process.exited()?,
                "image lease holder exited before ready: {}",
                directory.display()
            );
            ensure!(Instant::now() < deadline, "image lease ready timed out");
            thread::sleep(Duration::from_millis(20));
        }
        Ok(lease)
    }

    pub(super) fn check(&mut self) -> Result<()> {
        ensure!(
            !self.directory.join("error.json").is_file(),
            "image lease failed: {}",
            fs::read_to_string(self.directory.join("error.json")).unwrap_or_default()
        );
        if self.joined {
            return Ok(());
        }
        if let Some(status) = self.process.child.try_wait()? {
            self.process.stopped = true;
            self.joined = true;
            fs::write(
                self.directory.join("joined.tmp"),
                serde_json::to_vec(
                    &serde_json::json!({"exitCode": status.code(), "pid": self.process.child.id()}),
                )?,
            )?;
            fs::rename(
                self.directory.join("joined.tmp"),
                self.directory.join("joined.json"),
            )?;
            ensure!(
                status.success() && self.directory.join("released.json").is_file(),
                "image lease holder exited without successful explicit unlock: {status}"
            );
        }
        Ok(())
    }

    pub(super) fn close(&mut self, success: bool) -> Result<()> {
        if !success && !self.joined {
            fs::write(self.directory.join("abort.json"), b"{}\n")?;
        }
        let deadline = Instant::now() + Duration::from_secs(5);
        while !self.joined {
            if let Some(status) = self.process.child.try_wait()? {
                self.process.stopped = true;
                self.joined = true;
                fs::write(
                    self.directory.join("joined.tmp"),
                    serde_json::to_vec(
                        &serde_json::json!({"exitCode": status.code(), "pid": self.process.child.id()}),
                    )?,
                )?;
                fs::rename(
                    self.directory.join("joined.tmp"),
                    self.directory.join("joined.json"),
                )?;
                ensure!(
                    !success || status.success(),
                    "image lease holder failed: {status}"
                );
                break;
            }
            if Instant::now() >= deadline {
                // Existing process owner kills and joins; killing also closes
                // the FD, but is a cleanup failure, never a successful release.
                self.process.terminate();
                self.joined = self.process.stopped;
                bail!("image lease holder required forced cleanup");
            }
            thread::sleep(Duration::from_millis(20));
        }
        ensure!(
            self.directory.join("closed.json").is_file(),
            "image lease holder did not confirm FD close"
        );
        if success {
            self.check()?;
            ensure!(
                self.directory.join("released.json").is_file(),
                "image lease has no explicit release evidence"
            );
        }
        Ok(())
    }
}

impl Drop for ImageLease {
    fn drop(&mut self) {
        if !self.joined
            && let Err(error) = self.close(false)
        {
            eprintln!("image lease cleanup: {error:#}");
        }
    }
}
