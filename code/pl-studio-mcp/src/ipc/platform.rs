#[cfg(unix)]
#[path = "unix.rs"]
mod implementation;
#[cfg(windows)]
#[path = "windows.rs"]
mod implementation;

pub(super) use implementation::{Lease, Stream, bind, connect};
