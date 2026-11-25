//! Streaming ZIP extraction into the operation's private staging tree.

use std::collections::BTreeMap;
use std::fs::File;
use std::io::{BufReader, Read, Write};
use std::path::{Component, Path};

use flate2::bufread::DeflateDecoder;
use pl_tool::workspace::path_safety;
use rawzip::{CompressionMethod, RECOMMENDED_BUFFER_SIZE, ZipArchive};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

#[cfg(unix)]
use super::sync_tree;
use super::{
    COPY_CHUNK, ExtractInput, MAX_EXPANDED_BYTES, MAX_MEMBER_BYTES, MAX_MEMBERS, RECEIPT_FORMAT,
    RECEIPT_NAME, Receipt, ReceiptDirectory, ReceiptMember, has_exec_bit, io, normalize_relative,
    sanitize_member,
};
#[cfg(unix)]
use crate::studio::runtime::acp_install::permissions;
use crate::studio::runtime::acp_install::{
    mapping::failure,
    paths::{self, ManagedRoot},
};
use crate::{AcpInstallFailure, AcpInstallFailureCode, AcpInstallStage};

/// 文件类型掩码与允许类型（普通文件/目录）。
const S_IFMT: u32 = 0o170000;
const S_IFREG: u32 = 0o100000;
const S_IFDIR: u32 = 0o040000;
/// 通用目的位（APPNOTE 4.4.4）。只有下列常量会被用到，其余位（bit 4 enhanced-deflate、
/// bit 5 patched、bit 7–10/12/14–15 reserved 等）从不出现在 allowlist 里，因此一律被拒。
const FLAG_COMPRESSION_OPTION: u16 = 0x0006;
const FLAG_DATA_DESCRIPTOR: u16 = 0x0008;
const FLAG_UTF8: u16 = 0x0800;

/// 按实际支持的压缩方法给出通用目的位的 allowlist；不支持的方法没有 allowlist。
///
/// Deflate 的 bit 1–2 是格式定义的压缩级别选项（取值 0..=3），Store 必须为 0；加密、masked、
/// patched、enhanced-deflate 与全部保留位都不在集合内。这样"未知/不兼容方法旗标"是拒绝而不是
/// 被黑名单漏过（design/28 §28.7）。
fn allowed_flags(method: rawzip::CompressionMethod) -> Option<u16> {
    match method {
        rawzip::CompressionMethod::STORE => Some(FLAG_DATA_DESCRIPTOR | FLAG_UTF8),
        rawzip::CompressionMethod::DEFLATE => {
            Some(FLAG_DATA_DESCRIPTOR | FLAG_UTF8 | FLAG_COMPRESSION_OPTION)
        }
        _ => None,
    }
}

/// 解压到已校验的私有 staging，返回完整回执；创建的子目录逐层同步。
pub(in crate::studio::runtime::acp_install) fn extract(
    input: ExtractInput<'_>,
    root: &ManagedRoot,
    progress: &(dyn Fn(u64, Option<u64>) + Sync),
) -> Result<Receipt, AcpInstallFailure> {
    let ExtractInput {
        archive,
        staging,
        installation_id,
        release,
        command,
        args,
        archive_sha256,
        ..
    } = input;
    let stage = AcpInstallStage::Extract;
    let invalid = || failure(AcpInstallFailureCode::InvalidArchive, stage, false);

    root.validate_existing(archive, stage)?;
    root.validate_write(staging, stage)?;
    let file = File::open(archive).map_err(|_| io(stage))?;
    let archive_len = file.metadata().map_err(|_| io(stage))?.len();
    let mut buffer = vec![0u8; RECOMMENDED_BUFFER_SIZE];
    let archive = ZipArchive::from_file(file, &mut buffer).map_err(|_| invalid())?;

    let (members, directories) =
        extract_members(&archive, &mut buffer, archive_len, &input, root, progress)?;
    if members.is_empty() {
        return Err(invalid());
    }
    let command = normalize_relative(command);
    let Some(entry) = members.iter().find(|member| member.path == command) else {
        return Err(failure(
            AcpInstallFailureCode::MissingExecutable,
            stage,
            false,
        ));
    };
    // 入口必须是包内普通成员，且 Unix 上必须由包自己声明执行位：不为缺失执行位补权限，也不
    // 以"上游将来可能丢权限"为由放宽接受规则（design/28 §28.7 "可执行入口确认"）。
    if !has_exec_bit(entry.mode) {
        return Err(failure(
            AcpInstallFailureCode::MissingExecutable,
            stage,
            false,
        ));
    }
    // 成员写完后统一落地目录的最终权限（回执记录的就是最终值），再逐层由深到浅同步目录项。
    for directory in directories.values() {
        if let Some(directory_mode) = directory.mode {
            apply_mode(&staging.join(&directory.path), Some(directory_mode))?;
        }
    }
    let directories: Vec<ReceiptDirectory> = directories.into_values().collect();
    // Unix：权限位改变后同步文件，并同步嵌套目录与 staging 根目录项（design/28 §28.7
    // "Unix 在权限更新后同步文件，并同步嵌套目录、移动两端及新建祖先的必要目录项"）。
    // Windows 不执行目录同步，也不声称做过：成员文件已各自 `sync_all`，落盘保证来自随后的
    // 同卷 write-through 移动。
    #[cfg(unix)]
    {
        sync_tree(staging, &directories, stage)?;
        paths::sync_directory(staging, stage)?;
    }
    Ok(Receipt {
        format: RECEIPT_FORMAT,
        installation_id: installation_id.to_string(),
        release: release.clone(),
        command,
        args: args.to_vec(),
        archive_sha256: archive_sha256.to_string(),
        members,
        directories,
    })
}

type Directories = BTreeMap<String, ReceiptDirectory>;

fn extract_members<R: rawzip::ReaderAt>(
    archive: &ZipArchive<R>,
    buffer: &mut [u8],
    archive_len: u64,
    input: &ExtractInput<'_>,
    root: &ManagedRoot,
    progress: &(dyn Fn(u64, Option<u64>) + Sync),
) -> Result<(Vec<ReceiptMember>, Directories), AcpInstallFailure> {
    let stage = AcpInstallStage::Extract;
    let invalid = || failure(AcpInstallFailureCode::InvalidArchive, stage, false);
    let too_large = || failure(AcpInstallFailureCode::TooLarge, stage, false);
    let staging = input.staging;
    let cancellation = input.cancellation;
    // 不可信声明：先按上限早拒，再逐条处理；不据此预分配、也不把它当完成证明。
    let hint = archive.entries_hint();
    if hint > MAX_MEMBERS as u64 {
        return Err(too_large());
    }
    let directory_offset = archive.directory_offset();
    if directory_offset > archive_len {
        return Err(invalid());
    }

    let mut seen: BTreeMap<String, ()> = BTreeMap::new();
    let mut members: Vec<ReceiptMember> = Vec::new();
    let mut directories: BTreeMap<String, ReceiptDirectory> = BTreeMap::new();
    let mut compressed_ranges: Vec<(u64, u64)> = Vec::new();
    let mut payload = PayloadProgress {
        written: 0,
        cancellation,
        progress,
    };
    let mut declared_total = 0u64;
    let mut count = 0u64;
    let mut entries = archive.entries(buffer);
    loop {
        if cancellation.is_cancelled() {
            return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
        }
        let Some(entry) = entries.next_entry().map_err(|_| invalid())? else {
            break;
        };
        // 先计数再收集/写入：第 513 条在产生任何文件之前就被拒绝。
        count = count.saturating_add(1);
        if count > MAX_MEMBERS as u64 {
            return Err(too_large());
        }
        // 物理边界（只用公开 API）：local header 必须位于文件内、在中央目录之前，且不得落在任何
        // 已记录压缩数据区间内部或正好等于其起点（否则头与数据重叠）。这是单向检查：无法证明
        // "头不落在后续条目的数据里"，这一点在报告中如实标注。
        let header_offset = entry.local_header_offset();
        if header_offset >= directory_offset || header_offset >= archive_len {
            return Err(invalid());
        }
        match compressed_ranges.binary_search_by_key(&header_offset, |&(start, _)| start) {
            Ok(_) => return Err(invalid()),
            Err(position) => {
                if position > 0 && compressed_ranges[position - 1].1 > header_offset {
                    return Err(invalid());
                }
            }
        }
        // 压缩方法与通用目的位一起按 allowlist 判定：不支持的方法、未知/保留旗标一律拒绝。
        let Some(allowed) = allowed_flags(entry.compression_method()) else {
            return Err(invalid());
        };
        if entry.flags().bits() & !allowed != 0 {
            return Err(invalid());
        }
        let mode = entry.mode();
        if mode.is_symlink() {
            return Err(invalid());
        }
        let file_type = mode.value() & S_IFMT;
        if file_type != 0 && file_type != S_IFREG && file_type != S_IFDIR {
            return Err(invalid());
        }
        let raw = entry.file_path();
        let name = std::str::from_utf8(raw.as_bytes()).map_err(|_| invalid())?;
        let (relative, name_is_directory) = sanitize_member(name).ok_or_else(invalid)?;
        if name_is_directory != entry.is_dir() {
            return Err(invalid());
        }
        let key = relative.to_string_lossy().to_lowercase();
        if seen.insert(key, ()).is_some() {
            return Err(invalid());
        }
        if relative.file_name().and_then(|name| name.to_str()) == Some(RECEIPT_NAME) {
            return Err(invalid());
        }
        let destination = staging.join(&relative);
        root.validate_write(&destination, stage)?;
        let relative_text = relative.to_string_lossy().replace('\\', "/");
        prepare_member_parents(
            root,
            staging,
            &relative,
            &relative_text,
            entry.is_dir(),
            &mut directories,
        )?;
        if entry.is_dir() {
            let directory_mode = normalized_mode(mode.permissions());
            match std::fs::symlink_metadata(&destination) {
                Ok(metadata) if metadata.is_dir() => {}
                Ok(_) => return Err(invalid()),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                    paths::create_private_directory(&destination, stage)?;
                }
                Err(_) => return Err(io(stage)),
            }
            // 显式目录项的声明权限是权威值（可能晚于同名隐式父目录出现）。解压期间目录统一保持
            // 属主可写，声明权限在全部成员写完后统一落地，避免只读目录阻断后续成员写入。
            directories.insert(
                relative_text.clone(),
                ReceiptDirectory {
                    path: relative_text,
                    mode: Some(directory_mode),
                },
            );
            continue;
        }
        let declared = entry.uncompressed_size_hint();
        if declared > MAX_MEMBER_BYTES {
            return Err(too_large());
        }
        declared_total = declared_total
            .checked_add(declared)
            .filter(|total| *total <= MAX_EXPANDED_BYTES)
            .ok_or_else(too_large)?;

        let zip_entry = archive
            .get_entry(entry.wayfinder())
            .map_err(|_| invalid())?;
        let (start, end) = zip_entry.compressed_data_range();
        // 空 stored 文件是合法的半开区间 [start, start)。
        if start > end || end > directory_offset || end > archive_len {
            return Err(invalid());
        }
        if start < end {
            let position = compressed_ranges
                .binary_search_by_key(&start, |&(start, _)| start)
                .unwrap_or_else(|position| position);
            if position > 0 && compressed_ranges[position - 1].1 > start {
                return Err(invalid());
            }
            if compressed_ranges
                .get(position)
                .is_some_and(|&(next_start, _)| end > next_start)
            {
                return Err(invalid());
            }
            compressed_ranges.insert(position, (start, end));
        }
        validate_entry_headers(&entry, &zip_entry, allowed).map_err(|_| invalid())?;

        members.push(write_member(
            &zip_entry,
            entry.compression_method(),
            &destination,
            relative_text,
            normalized_mode(mode.permissions()),
            &mut payload,
        )?);
    }
    // 遍历结束必须与声明条数一致：声明少/多都是不可信目录。
    if count != hint {
        return Err(invalid());
    }
    Ok((members, directories))
}

fn prepare_member_parents(
    root: &ManagedRoot,
    staging: &Path,
    relative: &Path,
    relative_text: &str,
    is_directory: bool,
    directories: &mut Directories,
) -> Result<(), AcpInstallFailure> {
    let stage = AcpInstallStage::Extract;
    // 目录与文件都先逐层核验/规划父目录：`a/b/` 允许不先出现 `a/`，central 顺序任意。
    // 两阶段：先只规划（不创建），按本次真正新增的目录数做预算裁决，超预算时**在磁盘上
    // 什么都不建**就拒绝；预算内才创建，保证"过程预算"真的守住，而不是事后补救。
    let parents = plan_parents(root, staging, relative, stage)?;
    let adds_directory_entry = is_directory && !directories.contains_key(relative_text);
    let mut prospective = directories.len();
    for (parent, exists) in &parents {
        if !exists && !directories.contains_key(parent) {
            prospective = prospective.saturating_add(1);
        }
    }
    if adds_directory_entry {
        prospective = prospective.saturating_add(1);
    }
    if prospective > MAX_MEMBERS {
        return Err(failure(AcpInstallFailureCode::TooLarge, stage, false));
    }
    for (parent, exists) in parents {
        if !exists {
            let created = staging.join(&parent);
            paths::create_private_directory(&created, stage)?;
        }
        directories
            .entry(parent.clone())
            .or_insert(ReceiptDirectory {
                path: parent,
                mode: Some(normalized_mode(DIRECTORY_MODE_BITS)),
            });
    }
    Ok(())
}

fn write_member<R: rawzip::ReaderAt>(
    zip_entry: &rawzip::ZipEntry<'_, R>,
    method: CompressionMethod,
    destination: &Path,
    relative_text: String,
    member_mode: u32,
    payload: &mut PayloadProgress<'_>,
) -> Result<ReceiptMember, AcpInstallFailure> {
    let stage = AcpInstallStage::Extract;
    // 创建即按最终权限打开：不依赖 umask，也不留"先宽后收"的窗口。
    let mut output = paths::create_new_file(destination, member_mode, stage)?;
    #[cfg(unix)]
    permissions::verify(destination, false, stage)?;
    let mut writer = MemberWriter {
        output: &mut output,
        hasher: Sha256::new(),
        written: 0,
        written_total: &mut payload.written,
        progress: payload.progress,
        cancellation: payload.cancellation,
        stage,
    };
    match method {
        CompressionMethod::STORE => {
            // 库负责校验解压后大小与 CRC；实际字节上限与取消仍由本循环控制。
            let mut verifier = zip_entry.verifying_reader(zip_entry.reader());
            copy_member(&mut verifier, &mut writer)?;
        }
        CompressionMethod::DEFLATE => {
            let inflater = DeflateDecoder::new(BufReader::new(zip_entry.reader()));
            let mut verifier = zip_entry.verifying_reader(inflater);
            copy_member(&mut verifier, &mut writer)?;
        }
        _ => return Err(failure(AcpInstallFailureCode::InvalidArchive, stage, false)),
    }
    let (hasher, size) = writer.finish();
    // 先设权限再 fsync：权限位本身也必须落在持久化屏障之内。
    apply_mode(destination, Some(member_mode))?;
    output.sync_all().map_err(|_| io(stage))?;
    Ok(ReceiptMember {
        path: relative_text,
        size,
        sha256: hex::encode(hasher.finalize()),
        mode: Some(member_mode),
    })
}

struct PayloadProgress<'a> {
    written: u64,
    cancellation: &'a CancellationToken,
    progress: &'a (dyn Fn(u64, Option<u64>) + Sync),
}

/// 校验 local header 与 central directory 的一致性（**不比对 ZIP 尾部 data descriptor**）。
///
/// 用户已确认的产品政策（design/28 §28.7、design/24 与安装合同）：ZIP 尾部的 data descriptor 只是
/// 对 central 同一组 CRC/大小字段的**重复记录**，不再对它做额外比对，也不把它当作完整性依据：
/// 该重复记录的宽度由 central 的编码习惯决定，公开解析器无法可靠区分，用它做校验只会引入误判。
/// 明确承认：仅"descriptor 重复字段与 central 不同"这一差异不会被检出；这不是"跳过校验"。
///
/// 保留的校验：
/// - local header 的文件名、压缩方法必须与 central 相同；两侧通用目的位都必须是该方法 allowlist
///   的子集且 applicable 位一致（未知/保留位拒绝）；
/// - local header 的 CRC/压缩后/解压后大小必须等于 central；bit 3 下允许零占位。ZIP64 的具体尺寸
///   由 rawzip 已公开的 resolved hint API 提供（库从 ZIP64 扩展解码 u64），本模块不解析扩展字节；
/// - 真实解压数据与 central 的 CRC/大小由库 `verifying_reader` 校验，压缩区间由不重叠与边界检查
///   约束，另有发行 sha256、回执/本地 hash/完整树/路径/类型/权限/预算校验（见本模块其它函数）。
fn validate_entry_headers<R: rawzip::ReaderAt>(
    central: &rawzip::ZipFileHeaderRecord<'_>,
    entry: &rawzip::ZipEntry<'_, R>,
    allowed: u16,
) -> Result<(), ()> {
    // local header 的变长部分由库按需读入调用方缓冲；上限与 central 记录同一量级。
    let mut buffer = vec![0u8; RECOMMENDED_BUFFER_SIZE];
    let local = entry.local_header(&mut buffer).map_err(|_| ())?;
    if local.file_path().as_bytes() != central.file_path().as_bytes() {
        return Err(());
    }
    if local.compression_method() != central.compression_method() {
        return Err(());
    }
    let central_flags = central.flags().bits();
    let local_flags = local.flags().bits();
    if local_flags & !allowed != 0 {
        return Err(());
    }
    if central_flags & allowed != local_flags & allowed {
        return Err(());
    }
    let crc = central.crc32();
    let compressed = central.compressed_size_hint();
    let uncompressed = central.uncompressed_size_hint();
    // bit 3 只影响 local header 是否允许零占位。
    let local_may_be_zeroed = central_flags & FLAG_DATA_DESCRIPTOR != 0;
    if !local_sizes_match(&local, crc, compressed, uncompressed, local_may_be_zeroed) {
        return Err(());
    }
    // 尾部结构仍由成熟组件解析：解析失败要传播；bit 3 声明了 descriptor 却没有解析结果也拒绝。
    // **不比较** descriptor 的 CRC / 压缩后 / 解压后大小（用户明确只取消这组重复字段的比较），
    // 也不用它作为 payload 成功证据 —— 真实数据仍由 `verifying_reader` 对 central 的 CRC/大小
    // 校验。公开 API 不暴露 descriptor 消耗的字节宽度，因此"尾宽是否完全被验证"是已知局限：
    // 库内部按 central 内联哨兵决定宽度，混合 ZIP64 编码下取到的值我们不使用也不比较。
    let descriptor = entry.reader().data_descriptor().map_err(|_| ())?;
    if local_may_be_zeroed != descriptor.is_some() {
        return Err(());
    }
    Ok(())
}

/// local header 的 CRC/大小字段是否与 central 一致；`allow_zero` 只用于 bit 3 的零占位。
fn local_sizes_match(
    local: &rawzip::ZipLocalFileHeader<'_>,
    crc: u32,
    compressed: u64,
    uncompressed: u64,
    allow_zero: bool,
) -> bool {
    let matches = |actual: u64, expected: u64| actual == expected || (allow_zero && actual == 0);
    matches(u64::from(local.crc32()), u64::from(crc))
        && matches(local.compressed_size_hint(), compressed)
        && matches(local.uncompressed_size_hint(), uncompressed)
}

struct MemberWriter<'a> {
    output: &'a mut File,
    hasher: Sha256,
    written: u64,
    written_total: &'a mut u64,
    progress: &'a (dyn Fn(u64, Option<u64>) + Sync),
    cancellation: &'a CancellationToken,
    stage: AcpInstallStage,
}

impl MemberWriter<'_> {
    fn finish(self) -> (Sha256, u64) {
        (self.hasher, self.written)
    }
}

/// 分块搬运并累计摘要；取消、单成员上限与总量上限都在块之间检查。
fn copy_member(
    reader: &mut impl Read,
    writer: &mut MemberWriter<'_>,
) -> Result<(), AcpInstallFailure> {
    let mut buffer = vec![0u8; COPY_CHUNK];
    loop {
        if writer.cancellation.is_cancelled() {
            return Err(failure(
                AcpInstallFailureCode::Cancelled,
                writer.stage,
                true,
            ));
        }
        let read = reader
            .read(&mut buffer)
            .map_err(|_| failure(AcpInstallFailureCode::InvalidArchive, writer.stage, false))?;
        if read == 0 {
            return Ok(());
        }
        writer.written = writer.written.saturating_add(read as u64);
        *writer.written_total = writer.written_total.saturating_add(read as u64);
        if writer.written > MAX_MEMBER_BYTES || *writer.written_total > MAX_EXPANDED_BYTES {
            return Err(failure(
                AcpInstallFailureCode::TooLarge,
                writer.stage,
                false,
            ));
        }
        writer.hasher.update(&buffer[..read]);
        writer
            .output
            .write_all(&buffer[..read])
            .map_err(|_| io(writer.stage))?;
        (writer.progress)(*writer.written_total, None);
    }
}

/// 逐层规划成员父目录：既有的每一层都必须是真实目录（绝不跟随链接），缺失的只登记不创建。
///
/// 返回 `(相对路径, 是否已存在)`，调用方先做目录预算裁决，再据此创建缺少的层。
fn plan_parents(
    root: &ManagedRoot,
    staging: &Path,
    relative: &Path,
    stage: AcpInstallStage,
) -> Result<Vec<(String, bool)>, AcpInstallFailure> {
    let Some(parent) = relative.parent() else {
        return Ok(Vec::new());
    };
    let mut planned: Vec<(String, bool)> = Vec::new();
    let mut current = staging.to_path_buf();
    for component in parent.components() {
        let Component::Normal(part) = component else {
            return Err(failure(AcpInstallFailureCode::InvalidArchive, stage, false));
        };
        current.push(part);
        root.validate_write(&current, stage)?;
        let exists = match std::fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.is_dir() && !path_safety::is_link_or_reparse(&metadata) => {
                true
            }
            Ok(_) => {
                return Err(failure(AcpInstallFailureCode::InvalidArchive, stage, false));
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => false,
            Err(_) => return Err(io(stage)),
        };
        let relative_text = current
            .strip_prefix(staging)
            .map_err(|_| failure(AcpInstallFailureCode::InvalidArchive, stage, false))?
            .to_string_lossy()
            .replace('\\', "/");
        planned.push((relative_text, exists));
    }
    Ok(planned)
}

/// 隐式父目录的默认权限。
const DIRECTORY_MODE_BITS: u32 = 0o755;

/// 归一化权限位：去掉 setuid/setgid/sticky 与 group/other 写权限，保证属主可读。
fn normalized_mode(mode: u32) -> u32 {
    (mode & 0o777) & !0o022 | 0o400
}

fn apply_mode(path: &Path, mode: Option<u32>) -> Result<(), AcpInstallFailure> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Some(mode) = mode {
            let permissions = std::fs::Permissions::from_mode(mode);
            std::fs::set_permissions(path, permissions)
                .map_err(|_| io(AcpInstallStage::Extract))?;
        }
    }
    #[cfg(not(unix))]
    {
        let _ = (path, mode);
    }
    Ok(())
}
