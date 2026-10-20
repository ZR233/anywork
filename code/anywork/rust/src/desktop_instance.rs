//! Pre-engine native startup. The native host installs the lease once and keeps it for the
//! process lifetime; FRB borrows the same lock instead of racing a second acquisition.

use std::sync::OnceLock;

use anyhow::{Context, Result};
use pl_protocol::studio::StudioErrorCode;
use pl_studio_runtime::{
    RemoteHelperSource, StudioInstance, StudioInstanceLease, StudioRuntimeOptions,
};

static INSTANCE: OnceLock<Result<StudioInstance>> = OnceLock::new();
static HOST_LEASE: OnceLock<StudioInstanceLease> = OnceLock::new();

/// Fixed-size C ABI shared with runner_common/studio_instance.h. No pointers, ownership-bearing
/// values or Rust enums cross this boundary. `key` is a NUL-terminated SHA-256 hex digest.
#[repr(C)]
pub struct NativeInstanceClaim {
    status: u32,
    key: [u8; 65],
}

/// Called on the native platform thread before creating an engine. Repeated calls only retry
/// the same resolved home's nonblocking lock, never rereading environment or opening databases.
#[unsafe(no_mangle)]
pub extern "C" fn anywork_desktop_instance_claim() -> NativeInstanceClaim {
    std::panic::catch_unwind(claim).unwrap_or_else(|_| {
        crate::diagnostics::record_instance_diagnostic("claim_failed", "-", "panic");
        NativeInstanceClaim {
            status: 2,
            key: [0; 65],
        }
    })
}

fn claim() -> NativeInstanceClaim {
    let mut result = NativeInstanceClaim {
        status: 2,
        key: [0; 65],
    };
    let instance = match INSTANCE.get_or_init(prepare) {
        Ok(instance) => instance,
        Err(error) => {
            crate::diagnostics::record_instance_diagnostic("claim_failed", "-", &error.to_string());
            return result;
        }
    };
    result.key[..64].copy_from_slice(instance.key().as_bytes());
    if HOST_LEASE.get().is_some() {
        result.status = 0;
        return result;
    }
    match instance.try_acquire() {
        Ok(lease) => {
            // Only native startup calls claim. OnceLock also ensures an accidental concurrent
            // call cannot replace or release the already-published host lease.
            let _ = HOST_LEASE.set(lease);
            result.status = 0;
            crate::diagnostics::record_instance_diagnostic("owner_acquired", instance.key(), "ok");
        }
        Err(error) if error.code == StudioErrorCode::InstanceBusy => {
            result.status = 1;
        }
        Err(error) => crate::diagnostics::record_instance_diagnostic(
            "claim_failed",
            instance.key(),
            error.code.label(),
        ),
    }
    result
}

/// Native activation diagnostics. Codes are fixed by the shared C header; unknown input is an
/// explicit diagnostic, not a successful redirect. Panic never unwinds into the native runner.
#[unsafe(no_mangle)]
pub extern "C" fn anywork_desktop_instance_report(event: u32) {
    let _ = std::panic::catch_unwind(|| {
        let event = match event {
            0 => "redirected",
            1 => "activation_unavailable",
            2 => "endpoint_failed",
            3 => "window_activated",
            4 => "activation_pending",
            _ => "invalid_native_event",
        };
        let key = INSTANCE
            .get()
            .and_then(|instance| instance.as_ref().ok())
            .map_or("-", StudioInstance::key);
        crate::diagnostics::record_instance_diagnostic(event, key, "native");
    });
}

pub(crate) fn lease() -> Result<StudioInstanceLease> {
    HOST_LEASE
        .get()
        .cloned()
        .context("native desktop startup did not acquire the Studio home lease")
}

fn prepare() -> Result<StudioInstance> {
    let executable = std::env::current_exe()
        .context("locate the application executable for bundled remote helper resources")?;
    let bundle_root = executable
        .parent()
        .context("application executable has no parent")?;
    Ok(StudioInstance::prepare(
        StudioRuntimeOptions::desktop().with_remote_helper_source(RemoteHelperSource::Bundled(
            bundle_root.join("data").join("remote-helper"),
        )),
    )?)
}
