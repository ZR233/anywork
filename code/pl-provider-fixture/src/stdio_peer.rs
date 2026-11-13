//! Process identity for normal shutdown peers.
#[cfg(target_os = "linux")]
use std::fs;

/// The Linux process start time (jiffies since boot) for [pid], if alive.
///
/// Field 22 of `/proc/<pid>/stat`; the executable name may contain spaces and
/// parentheses, so parsing resumes after the last `)`.
#[cfg(target_os = "linux")]
pub(crate) fn proc_start_ticks(pid: u32) -> Option<u64> {
    let stat = fs::read_to_string(format!("/proc/{pid}/stat")).ok()?;
    let after_name = &stat[stat.rfind(')')? + 1..];
    let fields: Vec<&str> = after_name.split_whitespace().collect();
    fields.get(19).and_then(|value| value.parse::<u64>().ok())
}

/// Non-Linux hosts have no `/proc` start-time baseline.
#[cfg(not(target_os = "linux"))]
pub(crate) fn proc_start_ticks(_pid: u32) -> Option<u64> {
    None
}
