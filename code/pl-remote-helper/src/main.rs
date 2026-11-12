#[cfg(target_os = "linux")]
mod environment;

#[cfg(target_os = "linux")]
mod process_worker;

fn main() -> std::process::ExitCode {
    let mut arguments = std::env::args_os().skip(1);
    let result = match arguments.next() {
        None => Err("expected --stdio or --process-worker".into()),
        #[cfg(target_os = "linux")]
        Some(mode) if mode == "--stdio" && arguments.next().is_none() => {
            environment::bootstrap_mode("--serve-connection").map_err(Into::into)
        }
        Some(mode) if mode == "--serve-connection" && arguments.next().is_none() => {
            run_connection()
        }
        #[cfg(target_os = "linux")]
        Some(mode) if mode == "--emit-environment" => match (arguments.next(), arguments.next()) {
            (Some(socket), None) => {
                environment::emit(std::path::Path::new(&socket)).map_err(Into::into)
            }
            _ => Err("environment capture requires exactly one socket path".into()),
        },
        Some(mode) if mode == "--process-worker" => run_worker(arguments.collect()),
        Some(_) => Err("unknown remote helper mode".into()),
    };
    match result {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            use std::io::Write;
            let _ = writeln!(std::io::stderr(), "pl-remote-helper failed: {error}");
            std::process::ExitCode::FAILURE
        }
    }
}

fn run_connection() -> Result<(), Box<dyn std::error::Error>> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;
    let io = tokio::io::join(tokio::io::stdin(), tokio::io::stdout());
    let result = runtime.block_on(pl_remote_helper::serve_connection(io));
    runtime.shutdown_timeout(std::time::Duration::ZERO);
    if matches!(result, Err(pl_remote_helper::ServerError::CleanupTimedOut)) {
        eprintln!("foreground server cleanup unconfirmed");
        std::process::exit(1);
    }
    result.map_err(Into::into)
}

#[cfg(target_os = "linux")]
fn run_worker(arguments: Vec<std::ffi::OsString>) -> Result<(), Box<dyn std::error::Error>> {
    use std::os::fd::{FromRawFd, OwnedFd};
    use std::os::unix::net::UnixStream;
    let [descriptor] = arguments.as_slice() else {
        return Err("process worker requires exactly one control fd".into());
    };
    let descriptor: i32 = descriptor
        .to_str()
        .ok_or("control fd is not UTF-8")?
        .parse()?;
    if descriptor < 3 {
        return Err("control fd must be distinct from standard IO".into());
    }
    // SAFETY: this is the binary entrypoint before Tokio or any other descriptor owner is
    // constructed. A valid inherited fd >= 3 is owned by this process and claimed exactly once.
    if unsafe { libc::fcntl(descriptor, libc::F_GETFD) } < 0 {
        return Err(std::io::Error::last_os_error().into());
    }
    // SAFETY: the preceding check establishes a live inherited fd; this single-threaded
    // entrypoint is its sole owner. Channel::new validates the connected Unix socket before spawn.
    let descriptor = unsafe { OwnedFd::from_raw_fd(descriptor) };
    let control = UnixStream::from(descriptor);
    process_worker::run(control)?;
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn run_worker(_: Vec<std::ffi::OsString>) -> Result<(), Box<dyn std::error::Error>> {
    Err("process worker requires Linux".into())
}
