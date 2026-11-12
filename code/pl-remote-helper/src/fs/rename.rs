//! Exclusive rename uses the target OS primitive. Unsupported filesystems return
//! their original error; there is no check-then-replace or copy/delete fallback.
use std::{io, path::Path};

pub(super) async fn rename(
    source: &Path,
    target: &Path,
    collision: super::PathCollision,
) -> io::Result<()> {
    if collision == super::PathCollision::Overwrite {
        return tokio::fs::rename(source, target).await;
    }
    let source = source.to_owned();
    let target = target.to_owned();
    // The registered mutation owner awaits this blocking syscall even if its observer leaves.
    tokio::task::spawn_blocking(move || exclusive(&source, &target))
        .await
        .map_err(io::Error::other)?
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
fn exclusive(source: &Path, target: &Path) -> io::Result<()> {
    use std::{ffi::CString, os::unix::ffi::OsStrExt};
    let source = CString::new(source.as_os_str().as_bytes())?;
    let target = CString::new(target.as_os_str().as_bytes())?;
    // SAFETY: both owned CStrings are valid NUL-terminated inputs for the entire
    // synchronous call. These APIs do not retain pointers; errno is read immediately.
    #[cfg(target_os = "linux")]
    let result = unsafe {
        libc::renameat2(
            libc::AT_FDCWD,
            source.as_ptr(),
            libc::AT_FDCWD,
            target.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    #[cfg(target_os = "macos")]
    let result = unsafe { libc::renamex_np(source.as_ptr(), target.as_ptr(), libc::RENAME_EXCL) };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}

#[cfg(windows)]
fn exclusive(source: &Path, target: &Path) -> io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    use windows::{
        Win32::Storage::FileSystem::{MOVEFILE_FLAGS, MoveFileExW},
        core::PCWSTR,
    };
    let source: Vec<u16> = source.as_os_str().encode_wide().chain(Some(0)).collect();
    let target: Vec<u16> = target.as_os_str().encode_wide().chain(Some(0)).collect();
    // SAFETY: owned, NUL-terminated wide buffers outlive this synchronous call;
    // flags=0 disallows replacement and cross-volume copy/delete.
    unsafe {
        MoveFileExW(
            PCWSTR(source.as_ptr()),
            PCWSTR(target.as_ptr()),
            MOVEFILE_FLAGS(0),
        )
    }
    .map_err(|error| io::Error::from_raw_os_error(error.code().0 & 0xffff))
}
