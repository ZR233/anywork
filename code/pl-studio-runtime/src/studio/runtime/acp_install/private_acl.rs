//! 受管对象的私有性核验（安装根、管理目录、既有文件）。
//!
//! 规则来自 design/28 §28.7 与本轮已确认的 Windows 决定：
//! - Unix：受管目录必须正好 `0o700`；受管文件不得带 group/other 写位与 setuid/setgid/sticky。
//! - Windows：读取**真实** owner 与 DACL（不依赖 `SE_DACL_PROTECTED`/继承标记推断），任何有效
//!   grant 只允许当前用户、`SYSTEM`、`BUILTIN\Administrators`；`CREATOR OWNER` 只允许作为普通
//!   inherit-only 模板出现，不对当前对象授权；object/callback/conditional/未知 ACE、未知 flags、
//!   null DACL 或任何查询失败一律 fail-closed。
//!
//! 这里只做必要查询与领域私有规则判定：不实现通用 ACL 引擎、不写 ACL、不审计整域权限，也不
//! 声称能防同权限（同用户/管理员）并发改 ACL。查询走 `windows-sys` 绑定，SID/安全描述符一律由
//! 系统 API 解释，不手工编解码字节。

use std::path::Path;

use pl_protocol::studio::{AcpInstallFailure, AcpInstallFailureCode, AcpInstallStage};

use super::mapping::failure_with_message;

/// 受管对象私有性核验入口；`is_directory` 只影响 Unix 的期望 mode。
pub(super) fn verify_private_object(
    path: &Path,
    is_directory: bool,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    #[cfg(unix)]
    {
        let _ = path;
        verify_unix(path, is_directory, stage)
    }
    #[cfg(windows)]
    {
        let _ = is_directory;
        windows::verify(path, stage)
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = (path, is_directory);
        Err(not_private(stage))
    }
}

/// 既有受管对象不是私有权限：明确拒绝，不重试也不改写权限。
pub(super) fn not_private(stage: AcpInstallStage) -> AcpInstallFailure {
    failure_with_message(
        AcpInstallFailureCode::Io,
        stage,
        false,
        "受管对象的权限不是产品私有权限，请检查后重试",
    )
}

/// 权限查询失败（例如无法读取 owner/DACL）：fail-closed，保留现场、不改 ACL。
pub(super) fn unverifiable(stage: AcpInstallStage) -> AcpInstallFailure {
    failure_with_message(
        AcpInstallFailureCode::Io,
        stage,
        false,
        "无法确认受管对象的私有权限，请检查文件系统权限后重试",
    )
}

#[cfg(unix)]
fn verify_unix(
    path: &Path,
    is_directory: bool,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    use std::os::unix::fs::PermissionsExt;

    let metadata = std::fs::symlink_metadata(path).map_err(|_| unverifiable(stage))?;
    let mode = metadata.permissions().mode() & 0o7777;
    let private = if is_directory {
        mode == super::paths::DIRECTORY_MODE
    } else {
        // 文件可以是 0o600/0o644 等，但不得让别人能写，也不得带特殊位。
        mode & 0o022 == 0 && mode & 0o7000 == 0
    };
    if private {
        Ok(())
    } else {
        tracing::debug!(
            mode = format_args!("{mode:04o}"),
            "rejecting ACP install object that is not private"
        );
        Err(not_private(stage))
    }
}

#[cfg(windows)]
mod windows {
    //! Windows 侧的 owner + DACL 查询与私有规则。
    //!
    //! 只使用 `windows-sys` 0.61.2 的既有绑定：`GetNamedSecurityInfoW` 一次取 OWNER 与 DACL，
    //! 安全描述符由 `LocalFree` 释放；SID 比对用 `EqualSid`，长度/范围先用 `GetLengthSid` 证明，令牌用户用
    //! `OpenProcessToken` + `GetTokenInformation(TokenUser)`。不手工编解码 SID/安全描述符字节。

    use std::ffi::c_void;
    use std::mem::{size_of, zeroed};
    use std::path::Path;
    use std::ptr::{addr_of, addr_of_mut, null_mut};

    use pl_protocol::studio::{AcpInstallFailure, AcpInstallStage};
    use windows_sys::Win32::Foundation::{
        CloseHandle, ERROR_INVALID_HANDLE, ERROR_SUCCESS, GetLastError, HANDLE, HLOCAL, LocalFree,
    };
    use windows_sys::Win32::Security::Authorization::{GetNamedSecurityInfoW, SE_FILE_OBJECT};
    use windows_sys::Win32::Security::{
        ACCESS_ALLOWED_ACE, ACCESS_DENIED_ACE, ACE_HEADER, ACL, ACL_SIZE_INFORMATION,
        AclSizeInformation, CONTAINER_INHERIT_ACE, CreateWellKnownSid, DACL_SECURITY_INFORMATION,
        EqualSid, GetAce, GetAclInformation, GetLengthSid, GetSecurityDescriptorLength,
        GetTokenInformation, INHERIT_ONLY_ACE, INHERITED_ACE, IsValidSid, NO_PROPAGATE_INHERIT_ACE,
        OBJECT_INHERIT_ACE, OWNER_SECURITY_INFORMATION, PSECURITY_DESCRIPTOR, PSID,
        SECURITY_MAX_SID_SIZE, SID, TOKEN_QUERY, TOKEN_USER, TokenUser, WELL_KNOWN_SID_TYPE,
        WinBuiltinAdministratorsSid, WinCreatorOwnerSid, WinLocalSystemSid,
    };
    use windows_sys::Win32::System::SystemServices::{
        ACCESS_ALLOWED_ACE_TYPE, ACCESS_DENIED_ACE_TYPE, SID_MAX_SUB_AUTHORITIES,
    };
    use windows_sys::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

    use super::{not_private, unverifiable};

    /// `ACE_HEADER::AceType` 在 ABI 里是 `u8`，官方 ACE 类型常量是 `u32`：这里只做宽窄转换，
    /// 取值来自 `windows-sys` 的 `SystemServices` 模块，不手写 ABI 数值。
    const ACE_TYPE_ACCESS_ALLOWED: u8 = ACCESS_ALLOWED_ACE_TYPE as u8;
    const ACE_TYPE_ACCESS_DENIED: u8 = ACCESS_DENIED_ACE_TYPE as u8;
    /// 产品认得的 ACE 继承标志集合；出现其它位（audit 位、保留位）即拒绝。
    const KNOWN_ACE_FLAGS: u8 = (OBJECT_INHERIT_ACE
        | CONTAINER_INHERIT_ACE
        | NO_PROPAGATE_INHERIT_ACE
        | INHERIT_ONLY_ACE
        | INHERITED_ACE) as u8;

    pub(super) fn verify(path: &Path, stage: AcpInstallStage) -> Result<(), AcpInstallFailure> {
        let wide = wide_path(path, stage)?;
        let allowed = AllowedSids::query(stage)?;
        let mut owner: PSID = null_mut();
        let mut dacl: *mut ACL = null_mut();
        let mut descriptor: PSECURITY_DESCRIPTOR = null_mut();
        // SAFETY: `wide` 是以 NUL 结尾且无内部 NUL 的 UTF-16 缓冲，调用期间保持存活；三个 out
        // 指针都指向本函数栈上的自有变量；成功返回时 descriptor 交给 `OwnedDescriptor` 释放，
        // owner/dacl 只在该 descriptor 存活期间使用。
        let status = unsafe {
            GetNamedSecurityInfoW(
                wide.as_ptr(),
                SE_FILE_OBJECT,
                OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION,
                &mut owner,
                null_mut(),
                &mut dacl,
                null_mut(),
                &mut descriptor,
            )
        };
        // 无论 status 如何，先把可能已分配的 descriptor 纳入 RAII：失败路径同样可能返回非 null，
        // 早退时由 Drop 释放，不漏释放。
        let descriptor = OwnedDescriptor::adopt(descriptor);
        if status != ERROR_SUCCESS {
            return Err(unverifiable(stage));
        }
        if descriptor.is_null() {
            return Err(not_private(stage));
        }
        let raw = descriptor.raw();
        // 描述符的真实长度由系统 API 给出：owner 指针必须落在 [descriptor, +len) 内，且其中的
        // SID 长度也必须落在同一范围内，之后才允许调用会读取 SID 内容的 API。
        // SAFETY: descriptor 来自上面成功的查询，`GetSecurityDescriptorLength` 只读其头部。
        let descriptor_len = unsafe { GetSecurityDescriptorLength(raw) } as usize;
        let descriptor_range =
            ByteRange::new(raw as usize, descriptor_len).ok_or_else(|| unverifiable(stage))?;
        if owner.is_null() {
            return Err(not_private(stage));
        }
        let _ = sid_len_within(owner, descriptor_range, stage)?;
        if !allowed.matches(owner, stage)? {
            return Err(not_private(stage));
        }
        if dacl.is_null() {
            // null DACL 等于把完全访问权交给所有人。
            return Err(not_private(stage));
        }
        check_acl(dacl, &allowed, stage)?;
        // 正常返回前显式释放并核对结果：LocalFree 失败要作为 typed 失败报告，不能仍返回 Ok。
        descriptor.finish(stage)
    }

    fn check_acl(
        dacl: *mut ACL,
        allowed: &AllowedSids,
        stage: AcpInstallStage,
    ) -> Result<(), AcpInstallFailure> {
        let mut info: ACL_SIZE_INFORMATION = unsafe { zeroed() };
        // SAFETY: dacl 来自已成功查询的安全描述符；out 缓冲正好是 ACL_SIZE_INFORMATION 大小。
        let ok = unsafe {
            GetAclInformation(
                dacl,
                addr_of_mut!(info) as *mut c_void,
                size_of::<ACL_SIZE_INFORMATION>() as u32,
                AclSizeInformation,
            )
        };
        if ok == 0 {
            return Err(unverifiable(stage));
        }
        // ACL 的实际使用字节是唯一可靠的范围上界：AceCount 只是计数，不能单独证明每个 ACE 的
        // 指针与长度安全。范围无效就 fail-closed。
        let acl_range = ByteRange::new(dacl as usize, info.AclBytesInUse as usize)
            .filter(|range| range.len >= size_of::<ACL>())
            .ok_or_else(|| unverifiable(stage))?;
        for index in 0..info.AceCount {
            let mut ace: *mut c_void = null_mut();
            // SAFETY: index 小于 AceCount；GetAce 只写本栈上的指针，不保留引用。
            if unsafe { GetAce(dacl, index, &mut ace) } == 0 || ace.is_null() {
                return Err(unverifiable(stage));
            }
            let ace_addr = ace as usize;
            // 1) 先证明固定头落在 ACL 范围内，之后才允许读 header。
            if !acl_range.contains(ace_addr, size_of::<ACE_HEADER>()) {
                return Err(unverifiable(stage));
            }
            // SAFETY: 上一步证明 [ace, ace+sizeof(ACE_HEADER)) 位于 ACL 使用范围之内。
            let header = unsafe { &*(ace as *const ACE_HEADER) };
            let ace_flags = header.AceFlags;
            let ace_type = header.AceType;
            let ace_size = header.AceSize as usize;
            if ace_size < size_of::<ACE_HEADER>() {
                return Err(unverifiable(stage));
            }
            // 2) 整个 ACE 必须完整落在 ACL 使用范围内。
            if !acl_range.contains(ace_addr, ace_size) {
                return Err(unverifiable(stage));
            }
            if ace_flags & !KNOWN_ACE_FLAGS != 0 {
                return Err(not_private(stage));
            }
            match ace_type {
                ACE_TYPE_ACCESS_ALLOWED => {
                    let sid = sid_inside_ace(
                        ace_addr,
                        ace_size,
                        std::mem::offset_of!(ACCESS_ALLOWED_ACE, SidStart),
                        stage,
                    )?;
                    if allowed.matches_creator_owner(sid, stage)? {
                        // CREATOR OWNER 只允许作为普通 inherit-only 模板：不得对当前对象授权。
                        if ace_flags & INHERIT_ONLY_ACE as u8 == 0 {
                            return Err(not_private(stage));
                        }
                    } else if !allowed.matches(sid, stage)? {
                        // 任何有效 grant 只允许当前用户/SYSTEM/Administrators，其余（即使只读）拒绝。
                        return Err(not_private(stage));
                    }
                }
                ACE_TYPE_ACCESS_DENIED => {
                    // deny 不授权，但结构与 SID extent 仍要可证明。
                    let _ = sid_inside_ace(
                        ace_addr,
                        ace_size,
                        std::mem::offset_of!(ACCESS_DENIED_ACE, SidStart),
                        stage,
                    )?;
                }
                _ => return Err(not_private(stage)),
            }
        }
        Ok(())
    }

    /// 一段已经由系统 API 给出的字节范围（起点 + 长度，加法已检查）。
    #[derive(Clone, Copy)]
    struct ByteRange {
        start: usize,
        len: usize,
    }

    impl ByteRange {
        fn new(start: usize, len: usize) -> Option<Self> {
            start.checked_add(len)?;
            Some(Self { start, len })
        }

        fn end(&self) -> usize {
            self.start + self.len
        }

        fn contains(&self, start: usize, len: usize) -> bool {
            let Some(end) = start.checked_add(len) else {
                return false;
            };
            start >= self.start && end <= self.end()
        }
    }

    /// 校验一个 SID 指针的结构与 extent 都在给定实体内，并返回官方长度。
    ///
    /// 顺序严格按要求：
    /// 1. 固定头（`Revision` + `SubAuthorityCount` + `IdentifierAuthority[6]`）必须在实体内；
    /// 2. 之后才读官方 `SID::SubAuthorityCount`，用 `SID_MAX_SUB_AUTHORITIES` 限制并 checked 计算
    ///    `8 + 4 * count`，证明整个 SID（含 `SubAuthority` 数组）仍在同一实体内；
    /// 3. extent 与结构都成立后才用 `IsValidSid` 证明结构合法，再用 `GetLengthSid` 交叉核对长度。
    ///
    /// `IsValidSid` 不再被当作"可以先越界读"的兜底：它只在 extent 已证明之后调用。
    fn sid_len_within(
        sid: PSID,
        range: ByteRange,
        stage: AcpInstallStage,
    ) -> Result<usize, AcpInstallFailure> {
        let addr = sid as usize;
        // 固定部分：Revision(1) + SubAuthorityCount(1) + IdentifierAuthority(6)。
        let fixed = size_of::<SID>() - size_of::<u32>();
        if !range.contains(addr, fixed) {
            return Err(unverifiable(stage));
        }
        // SAFETY: 上一步已证明该地址起至少固定头字节在实体内；这里只读官方 SID 结构体固定头
        // 范围内的一个 u8 字段（SubAuthorityCount），不读 SubAuthority 数组。
        let count = unsafe { addr_of!((*(sid as *const SID)).SubAuthorityCount).read() } as usize;
        let max = SID_MAX_SUB_AUTHORITIES as usize;
        if count > max {
            return Err(unverifiable(stage));
        }
        let len = fixed
            .checked_add(
                count
                    .checked_mul(size_of::<u32>())
                    .ok_or_else(|| unverifiable(stage))?,
            )
            .ok_or_else(|| unverifiable(stage))?;
        if !range.contains(addr, len) {
            return Err(unverifiable(stage));
        }
        // SAFETY: extent 已证明覆盖整个 SID；IsValidSid 只读取该范围内字段做结构校验。
        if unsafe { IsValidSid(sid) } == 0 {
            return Err(unverifiable(stage));
        }
        // SAFETY: 同一个已证明有效的 SID 指针；GetLengthSid 只读同一范围内字段。
        let reported = unsafe { GetLengthSid(sid) } as usize;
        if reported != len {
            return Err(unverifiable(stage));
        }
        Ok(len)
    }

    /// 计算并校验 `ACCESS_ALLOWED_ACE`/`ACCESS_DENIED_ACE` 中变长 SID 的起点与 extent。
    ///
    /// `AceSize` 已由调用方证明落在 ACL 范围内；这里再证明固定部分（Header+Mask+SidStart 起点）
    /// 与后续 SID 变长字节都在该 ACE 内，之后才允许把指针交给系统 API。
    fn sid_inside_ace(
        ace_addr: usize,
        ace_size: usize,
        sid_offset: usize,
        stage: AcpInstallStage,
    ) -> Result<PSID, AcpInstallFailure> {
        let fixed = sid_offset + size_of::<u32>();
        if ace_size < fixed {
            return Err(unverifiable(stage));
        }
        let ace_range = ByteRange::new(ace_addr, ace_size).ok_or_else(|| unverifiable(stage))?;
        let sid_addr = ace_addr + sid_offset;
        let sid: PSID = sid_addr as *mut c_void;
        sid_len_within(sid, ace_range, stage)?;
        Ok(sid)
    }

    /// 一个 SID：`buffer` 保持 SID 所在内存存活，`sid` 指向其中的变长 SID。
    struct Sid {
        _buffer: Vec<usize>,
        sid: PSID,
    }

    /// 允许的三类主体 SID：当前用户、SYSTEM、BUILTIN\Administrators，外加只允许模板化的
    /// CREATOR OWNER 识别。缓冲区用 `usize` 数组，保证 SID/TOKEN_USER 的对齐要求。
    struct AllowedSids {
        current: Sid,
        system: Sid,
        administrators: Sid,
        creator_owner: Sid,
    }

    impl AllowedSids {
        fn query(stage: AcpInstallStage) -> Result<Self, AcpInstallFailure> {
            Ok(Self {
                current: current_user_sid(stage)?,
                system: well_known_sid(WinLocalSystemSid, stage)?,
                administrators: well_known_sid(WinBuiltinAdministratorsSid, stage)?,
                creator_owner: well_known_sid(WinCreatorOwnerSid, stage)?,
            })
        }

        fn matches(&self, sid: PSID, stage: AcpInstallStage) -> Result<bool, AcpInstallFailure> {
            Ok(self.equals(sid, &self.current, stage)?
                || self.equals(sid, &self.system, stage)?
                || self.equals(sid, &self.administrators, stage)?)
        }

        fn matches_creator_owner(
            &self,
            sid: PSID,
            stage: AcpInstallStage,
        ) -> Result<bool, AcpInstallFailure> {
            self.equals(sid, &self.creator_owner, stage)
        }

        fn equals(
            &self,
            sid: PSID,
            candidate: &Sid,
            stage: AcpInstallStage,
        ) -> Result<bool, AcpInstallFailure> {
            if candidate.sid.is_null() {
                return Err(unverifiable(stage));
            }
            // SAFETY: 两个 SID 的字节范围都已先用 GetLengthSid 与其所属实体范围证明；`candidate.sid` 指向随 `candidate` 存活
            // 的、由系统 API 填充的 SID 内存。
            let equal = unsafe { EqualSid(sid, candidate.sid) };
            Ok(equal != 0)
        }
    }

    fn well_known_sid(
        kind: WELL_KNOWN_SID_TYPE,
        stage: AcpInstallStage,
    ) -> Result<Sid, AcpInstallFailure> {
        // SECURITY_MAX_SID_SIZE 已足以容纳任何知名 SID；用 usize 字数组保证对齐。
        let words = SECURITY_MAX_SID_SIZE as usize / size_of::<usize>() + 1;
        let mut buffer = vec![0usize; words];
        let mut size = SECURITY_MAX_SID_SIZE;
        // SAFETY: buffer 至少 SECURITY_MAX_SID_SIZE 字节，`size` 初值即其字节长度；domain 指针为
        // NULL 表示使用内置域；系统只写 buffer 内、最多 size 字节。
        let ok =
            unsafe { CreateWellKnownSid(kind, null_mut(), buffer.as_mut_ptr() as PSID, &mut size) };
        if ok == 0 {
            return Err(unverifiable(stage));
        }
        let sid = buffer.as_mut_ptr() as PSID;
        Ok(Sid {
            _buffer: buffer,
            sid,
        })
    }

    fn current_user_sid(stage: AcpInstallStage) -> Result<Sid, AcpInstallFailure> {
        let mut token: HANDLE = null_mut();
        // SAFETY: GetCurrentProcess 返回当前进程伪句柄（无需关闭）；OpenProcessToken 只写本栈上的
        // token 变量，成功时得到一个由 `TokenHandle` 关闭的真实句柄。
        if unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token) } == 0 {
            return Err(unverifiable(stage));
        }
        let token = TokenHandle::adopt(token);
        let mut needed: u32 = 0;
        // SAFETY: 第一次调用只取所需长度（预期 ERROR_INSUFFICIENT_BUFFER），不提供输出缓冲。
        unsafe {
            GetTokenInformation(token.raw(), TokenUser, null_mut(), 0, &mut needed);
        }
        if needed == 0 {
            return Err(unverifiable(stage));
        }
        // TOKEN_USER 含指针字段，缓冲用 usize 数组保证对齐；按字节长度换算并留余量，因为变长 SID
        // 紧跟结构体存放。
        let words = needed as usize / size_of::<usize>() + 2;
        let mut buffer = vec![0usize; words];
        // SAFETY: buffer 至少 needed 字节；系统写入 TOKEN_USER 结构体与随后的 SID 字节。
        let ok = unsafe {
            GetTokenInformation(
                token.raw(),
                TokenUser,
                buffer.as_mut_ptr() as *mut c_void,
                needed,
                &mut needed,
            )
        };
        if ok == 0 {
            return Err(unverifiable(stage));
        }
        if needed as usize > buffer.len() * size_of::<usize>() {
            return Err(unverifiable(stage));
        }
        // SAFETY: 系统刚写入 TOKEN_USER；指针按 usize 对齐，且 `needed` 已证明不超过缓冲字节数。
        let sid = unsafe { (*(buffer.as_ptr() as *const TOKEN_USER)).User.Sid };
        if sid.is_null() {
            return Err(unverifiable(stage));
        }
        // SID 变长部分也必须整体落在令牌缓冲内，之后 EqualSid 才被调用。
        let buffer_range = ByteRange::new(buffer.as_ptr() as usize, needed as usize)
            .ok_or_else(|| unverifiable(stage))?;
        sid_len_within(sid, buffer_range, stage)?;
        // 正常返回前显式关闭令牌句柄并核对结果（CloseHandle 返回 0 即失败）。
        token.finish(stage)?;
        Ok(Sid {
            _buffer: buffer,
            sid,
        })
    }

    /// 把路径转成以 NUL 结尾、无内部 NUL 的 UTF-16 缓冲。
    fn wide_path(path: &Path, stage: AcpInstallStage) -> Result<Vec<u16>, AcpInstallFailure> {
        use std::os::windows::ffi::OsStrExt;
        let mut wide: Vec<u16> = path.as_os_str().encode_wide().collect();
        if wide.contains(&0) {
            return Err(not_private(stage));
        }
        wide.push(0);
        Ok(wide)
    }

    /// 安全描述符的释放责任。
    ///
    /// `GetNamedSecurityInfoW` 只要返回非 null 描述符就由调用方 `LocalFree`（成功/失败都一样）；
    /// 正常返回前必须显式 `finish` 并核对 `LocalFree` 结果，`Drop` 只作为异常/早退回退，且
    /// `finish` 会先 `take` 掉指针，因此不会双重释放、也不会在释放成功后再次释放。
    struct OwnedDescriptor(Option<PSECURITY_DESCRIPTOR>);

    impl OwnedDescriptor {
        fn adopt(raw: PSECURITY_DESCRIPTOR) -> Self {
            Self(if raw.is_null() { None } else { Some(raw) })
        }

        fn raw(&self) -> PSECURITY_DESCRIPTOR {
            self.0.unwrap_or(null_mut())
        }

        fn is_null(&self) -> bool {
            self.0.is_none()
        }

        /// 正常路径的显式释放；`LocalFree` 返回 null 表示成功（官方契约）。
        ///
        /// 只有确认成功才 disarm（置 None，`Drop` 不再释放）；失败时对象所有权仍留在 guard 里，
        /// 由 `Drop` 做一次回退释放，同时如实返回 typed 失败——不会"先 take 再失败"而漏掉 owner。
        fn finish(mut self, stage: AcpInstallStage) -> Result<(), AcpInstallFailure> {
            let Some(raw) = self.0 else {
                return Ok(());
            };
            // SAFETY: 指针来自 GetNamedSecurityInfoW，且只在成功时 disarm；失败时由 Drop 回退一次。
            let freed = unsafe { LocalFree(raw as HLOCAL) };
            if freed.is_null() {
                self.0 = None;
                return Ok(());
            }
            Err(unverifiable(stage))
        }
    }

    impl Drop for OwnedDescriptor {
        fn drop(&mut self) {
            if let Some(raw) = self.0.take() {
                // SAFETY: 异常/早退回退；指针来自查询且尚未释放。
                unsafe {
                    LocalFree(raw as HLOCAL);
                }
            }
        }
    }

    /// 令牌句柄的关闭责任。
    ///
    /// 正常路径显式 `finish` 并核对 `CloseHandle` 返回值（0 表示失败），失败按 typed Io 报告；
    /// `Drop` 只作为异常/早退回退，`finish` 先 `take` 掉句柄，因此不会重复关闭。
    struct TokenHandle(Option<HANDLE>);

    impl TokenHandle {
        fn adopt(raw: HANDLE) -> Self {
            Self(if raw.is_null() { None } else { Some(raw) })
        }

        fn raw(&self) -> HANDLE {
            self.0.unwrap_or(null_mut())
        }

        /// 正常路径的显式关闭。
        ///
        /// - 成功：disarm（`Drop` 不再关闭），不会 double-close；
        /// - 失败且最后错误是 `ERROR_INVALID_HANDLE`（官方契约：该句柄值无效）：同样 disarm，
        ///   重试没有意义，也避免误关一个已被复用的句柄值，但仍返回 typed 失败；
        /// - 其它失败：句柄仍由 guard 持有，`Drop` 做一次回退关闭，并返回 typed 失败。
        fn finish(mut self, stage: AcpInstallStage) -> Result<(), AcpInstallFailure> {
            let Some(raw) = self.0 else {
                return Ok(());
            };
            // SAFETY: 句柄由 OpenProcessToken 成功返回，只在这里或 Drop 里关闭一次。
            if unsafe { CloseHandle(raw) } != 0 {
                self.0 = None;
                return Ok(());
            }
            // SAFETY: 读取线程最后错误码，只用于区分"句柄已无效"这一终态。
            let error = unsafe { GetLastError() };
            if error == ERROR_INVALID_HANDLE {
                self.0 = None;
            }
            Err(unverifiable(stage))
        }
    }

    impl Drop for TokenHandle {
        fn drop(&mut self) {
            if let Some(raw) = self.0.take() {
                // SAFETY: 异常/早退回退，只关闭一次。
                unsafe {
                    CloseHandle(raw);
                }
            }
        }
    }
}
