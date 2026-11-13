use std::{
    io,
    mem::size_of,
    os::windows::io::{AsRawHandle, FromRawHandle, OwnedHandle},
    ptr,
};

use tokio::{
    net::windows::named_pipe::{ClientOptions, NamedPipeClient, NamedPipeServer, ServerOptions},
    sync::Mutex,
};
use windows_sys::Win32::{
    Foundation::{GENERIC_READ, GENERIC_WRITE, HANDLE},
    Security::{
        ACCESS_ALLOWED_ACE, ACL, ACL_REVISION, AddAccessAllowedAce, GetLengthSid,
        GetTokenInformation, InitializeAcl, InitializeSecurityDescriptor, SECURITY_ATTRIBUTES,
        SECURITY_DESCRIPTOR, SetSecurityDescriptorDacl, TOKEN_QUERY, TOKEN_USER, TokenUser,
    },
    System::Threading::{GetCurrentProcess, OpenProcessToken},
};

pub(in crate::ipc) type Stream = NamedPipeServer;

pub(in crate::ipc) struct Lease;

impl Lease {
    pub fn close(&mut self) -> io::Result<()> {
        Ok(())
    }
}

pub(in crate::ipc) struct Listener {
    endpoint: String,
    next: Mutex<NamedPipeServer>,
}

impl Listener {
    pub async fn accept(&self) -> io::Result<Stream> {
        let mut next = self.next.lock().await;
        next.connect().await?;
        // Keep the connected original instance alive until the replacement
        // listener is created: there is never a name-squatting gap.
        let replacement = create(&self.endpoint, false)?;
        Ok(std::mem::replace(&mut *next, replacement))
    }
}

pub(in crate::ipc) async fn bind() -> io::Result<(Listener, Lease, String)> {
    let endpoint = format!(r"\\.\pipe\anywork-host-{}", uuid::Uuid::new_v4());
    let next = create(&endpoint, true)?;
    Ok((
        Listener {
            endpoint: endpoint.clone(),
            next: Mutex::new(next),
        },
        Lease,
        endpoint,
    ))
}

pub(in crate::ipc) async fn connect(endpoint: &str) -> io::Result<NamedPipeClient> {
    // Endpoint is local-only, even when supplied through the child environment.
    if !endpoint.starts_with(r"\\.\pipe\") {
        return Err(io::Error::other("host IPC endpoint is not local"));
    }
    ClientOptions::new().open(endpoint)
}

fn success(value: i32) -> io::Result<()> {
    if value == 0 {
        Err(io::Error::last_os_error())
    } else {
        Ok(())
    }
}

fn create(endpoint: &str, first: bool) -> io::Result<NamedPipeServer> {
    let mut raw_token: HANDLE = ptr::null_mut();
    // SAFETY: pseudo process handle is valid, output is a live local HANDLE.
    success(unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut raw_token) })?;
    // SAFETY: OpenProcessToken succeeded and transfers one owned handle.
    let token = unsafe { OwnedHandle::from_raw_handle(raw_token) };
    let mut bytes = 0u32;
    // SAFETY: null output with zero length is the documented size query.
    unsafe {
        GetTokenInformation(
            token.as_raw_handle(),
            TokenUser,
            ptr::null_mut(),
            0,
            &mut bytes,
        );
    }
    if bytes < size_of::<TOKEN_USER>() as u32 {
        return Err(io::Error::last_os_error());
    }
    // usize storage provides alignment for TOKEN_USER and its embedded SID.
    let mut user = vec![0usize; (bytes as usize).div_ceil(size_of::<usize>())];
    // SAFETY: aligned allocation is at least `bytes` long and stays live through create.
    success(unsafe {
        GetTokenInformation(
            token.as_raw_handle(),
            TokenUser,
            user.as_mut_ptr().cast(),
            bytes,
            &mut bytes,
        )
    })?;
    // SAFETY: successful TokenUser initialized TOKEN_USER and its SID in user.
    let sid = unsafe { (*user.as_ptr().cast::<TOKEN_USER>()).User.Sid };
    // SAFETY: SID is initialized by GetTokenInformation, user remains live.
    let sid_size = unsafe { GetLengthSid(sid) } as usize;
    let acl_size = size_of::<ACL>() + size_of::<ACCESS_ALLOWED_ACE>() - size_of::<u32>() + sid_size;
    let mut acl = vec![0usize; acl_size.div_ceil(size_of::<usize>())];
    let acl_ptr = acl.as_mut_ptr().cast::<ACL>();
    // SAFETY: aligned ACL storage covers acl_size; the SID is copied into it.
    success(unsafe { InitializeAcl(acl_ptr, acl_size as u32, ACL_REVISION) })?;
    success(unsafe {
        AddAccessAllowedAce(acl_ptr, ACL_REVISION, GENERIC_READ | GENERIC_WRITE, sid)
    })?;
    let mut descriptor = SECURITY_DESCRIPTOR::default();
    // SAFETY: descriptor is aligned writable storage; revision 1 is
    // SECURITY_DESCRIPTOR_REVISION. DACL points to live initialized ACL storage.
    success(unsafe {
        InitializeSecurityDescriptor((&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(), 1)
    })?;
    success(unsafe {
        SetSecurityDescriptorDacl(
            (&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(),
            1,
            acl_ptr,
            0,
        )
    })?;
    let mut attributes = SECURITY_ATTRIBUTES {
        nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: (&mut descriptor as *mut SECURITY_DESCRIPTOR).cast(),
        bInheritHandle: 0,
    };
    // SAFETY: all security structures remain live for this synchronous call;
    // Windows copies the descriptor into the new kernel object. Only current
    // TokenUser has an allow ACE, and remote clients are explicitly rejected.
    unsafe {
        ServerOptions::new()
            .first_pipe_instance(first)
            .reject_remote_clients(true)
            .create_with_security_attributes_raw(
                endpoint,
                (&mut attributes as *mut SECURITY_ATTRIBUTES).cast(),
            )
    }
}
