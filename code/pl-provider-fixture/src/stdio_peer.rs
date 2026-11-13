//! Process identity for normal shutdown peers.
#[cfg(target_os = "linux")]
use std::fs;

/// The Linux process start time (jiffies since boot) for `pid`, if alive.
///
/// Field 22 of `/proc/<pid>/stat`; the executable name may contain spaces and
/// parentheses, so parsing resumes after the last `)`.
#[cfg(target_os = "linux")]
pub fn proc_start_ticks(pid: u32) -> Option<u64> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let after_name = &stat[stat.rfind(')')? + 1..];
    let fields: Vec<&str> = after_name.split_whitespace().collect();
    fields.get(19).and_then(|value| value.parse::<u64>().ok())
}

/// Windows creation time (100ns intervals since 1601) for a live `pid`.
#[cfg(windows)]
pub fn proc_start_ticks(pid: u32) -> Option<u64> {
    use windows_sys::Win32::Foundation::{CloseHandle, FILETIME, WAIT_TIMEOUT};
    use windows_sys::Win32::System::Threading::{
        GetProcessTimes, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_SYNCHRONIZE,
        WaitForSingleObject,
    };
    let mut created = FILETIME::default();
    let mut exited = FILETIME::default();
    let mut kernel = FILETIME::default();
    let mut user = FILETIME::default();
    // SAFETY: OpenProcess grants query/wait access; each output is a distinct,
    // initialized FILETIME valid through the synchronous call. The acquired
    // handle is closed exactly once on both success and failure paths.
    let success = unsafe {
        let handle = OpenProcess(
            PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_SYNCHRONIZE,
            0,
            pid,
        );
        if handle.is_null() {
            return None;
        }
        let result = GetProcessTimes(handle, &mut created, &mut exited, &mut kernel, &mut user);
        // GetProcessTimes leaves exit time undefined for a live process; the
        // process handle's signalled state is the actual liveness observation.
        let alive = WaitForSingleObject(handle, 0) == WAIT_TIMEOUT;
        CloseHandle(handle);
        result != 0 && alive
    };
    success.then_some((u64::from(created.dwHighDateTime) << 32) | u64::from(created.dwLowDateTime))
}

/// Hosts without an implemented process-identity baseline.
#[cfg(not(any(target_os = "linux", windows)))]
pub fn proc_start_ticks(_pid: u32) -> Option<u64> {
    None
}
