//! ZIP 内容校验、私有 staging 解压、版本化回执、复用校验与原子发布。
//!
//! 读取端使用 `rawzip` 的公开 lending central-directory 迭代器：固定大小解析缓冲、逐条读取原始
//! 记录，不先物化整张成员表、不按不可信声明预分配、也不做任何隐式去重。ZIP 格式细节（local
//! header、data descriptor、ZIP64、CRC 与实际大小）由库解析，本模块按官方 validation 规则追加
//! 产品政策：路径、重复/大小写、类型、加密/masked/reserved flags、压缩法、大小上限、不重叠的压缩
//! 区间、local/descriptor 一致性、权限归一化与入口资格。
//!
//! 全部是同步阻塞工作，只能由 owner 的 `spawn_blocking` 调用；取消在成员与缓冲块之间协作检查，
//! join 责任始终留在 owner。发布把"已提交"与"已确认持久化"分开报告（见 design/28 §28.6、§28.7）。
//!
//! 威胁边界是 [design/28 §28.7] 确认的标准桌面应用模型：防护不可信分发内容、预先存在的符号
//! 链接/reparse、路径越界与损坏安装，不承诺抵御能同时改写当前用户配置、安装管理树或进程权限的
//! 同权限恶意进程或管理员，也不是 OS 沙箱。实际链接、权限与完整性检查一项都不因此跳过。
//!
//! [design/28 §28.7]: ../../../../../../design/28-acp.md

use std::collections::BTreeMap;
use std::fs::{File, OpenOptions};
use std::io::{BufReader, Read, Write};
use std::path::{Component, Path, PathBuf};

use flate2::bufread::DeflateDecoder;
use pl_protocol::studio::{
    AcpInstallFailure, AcpInstallFailureCode, AcpInstallRelease, AcpInstallStage,
};
use pl_tool::workspace::path_safety;
use rawzip::{CompressionMethod, RECOMMENDED_BUFFER_SIZE, ZipArchive};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::mapping::{failure, failure_with_message};
#[cfg(unix)]
use super::paths;
use super::paths::ManagedRoot;

/// 成员数量上限。
pub(super) const MAX_MEMBERS: usize = 512;
/// 解压总量上限。
pub(super) const MAX_EXPANDED_BYTES: u64 = 4 * 1024 * 1024 * 1024;
/// 单成员上限。
pub(super) const MAX_MEMBER_BYTES: u64 = 2 * 1024 * 1024 * 1024;
/// 回执文件名；它是保留名，不能与包成员冲突。
pub(super) const RECEIPT_NAME: &str = "receipt.json";
/// 回执格式版本；同时记录目录集合（含 mode），供复用做完整内容比对。
const RECEIPT_FORMAT: u32 = 1;
/// 回执自身的大小上限：512 个成员与目录的清单远小于该值，超出即视为缓存损坏，不整块读入。
const MAX_RECEIPT_BYTES: u64 = 8 * 1024 * 1024;
/// 握手缓冲。
const COPY_CHUNK: usize = 64 * 1024;
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

/// 版本化安装回执：描述符、入口、本地 archive 摘要、完整成员与目录清单。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct Receipt {
    pub(super) format: u32,
    pub(super) installation_id: String,
    pub(super) release: AcpInstallRelease,
    pub(super) command: String,
    pub(super) args: Vec<String>,
    pub(super) archive_sha256: String,
    pub(super) members: Vec<ReceiptMember>,
    /// 归档中的目录（相对路径 + 归一化 mode，含成员隐含的父目录）。
    pub(super) directories: Vec<ReceiptDirectory>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReceiptMember {
    pub(super) path: String,
    pub(super) size: u64,
    pub(super) sha256: String,
    /// 归一化后的 Unix 权限位；其它平台为 `None`。
    pub(super) mode: Option<u32>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReceiptDirectory {
    pub(super) path: String,
    pub(super) mode: Option<u32>,
}

/// 一次解压的输入：源包、私有 staging、冻结发行身份与入口。
#[derive(Debug, Clone, Copy)]
pub(super) struct ExtractInput<'a> {
    pub(super) archive: &'a Path,
    pub(super) staging: &'a Path,
    pub(super) installation_id: &'a str,
    pub(super) release: &'a AcpInstallRelease,
    pub(super) command: &'a str,
    pub(super) args: &'a [String],
    pub(super) archive_sha256: &'a str,
    pub(super) cancellation: &'a CancellationToken,
}

/// 复用时要求被验证安装与本次冻结身份完全一致。
#[derive(Debug, Clone, Copy)]
pub(super) struct ExpectedInstall<'a> {
    pub(super) installation_id: &'a str,
    pub(super) release: &'a AcpInstallRelease,
    pub(super) command: &'a str,
    pub(super) args: &'a [String],
}

/// 发布结果：`rename` 已生效，但目录项持久化可能尚未确认。
pub(super) enum PublishOutcome {
    Confirmed,
    /// 已提交（安装目录可见），但持久化屏障失败或平台保证未确认：不能报告为完整成功，也不能
    /// 谎称回滚。
    CommittedButUnconfirmed,
}

/// 流式摘要；`progress` 报告已处理的真实字节数与已知总量（文件长度）。
pub(super) fn sha256_file(
    path: &Path,
    cancellation: &CancellationToken,
    progress: &(dyn Fn(u64, Option<u64>) + Sync),
) -> Result<String, AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    let mut file = File::open(path).map_err(|_| io(stage))?;
    let total = file.metadata().map(|metadata| metadata.len()).ok();
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; COPY_CHUNK];
    let mut processed = 0u64;
    loop {
        if cancellation.is_cancelled() {
            return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
        }
        let read = file.read(&mut buffer).map_err(|_| io(stage))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        processed = processed.saturating_add(read as u64);
        progress(processed, total);
    }
    Ok(hex::encode(hasher.finalize()))
}

/// 解压到已校验的私有 staging，返回完整回执；创建的子目录逐层同步。
pub(super) fn extract(
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
        cancellation,
    } = input;
    let stage = AcpInstallStage::Extract;
    let invalid = || failure(AcpInstallFailureCode::InvalidArchive, stage, false);
    let too_large = || failure(AcpInstallFailureCode::TooLarge, stage, false);

    root.validate_existing(archive, stage)?;
    root.validate_write(staging, stage)?;
    let file = File::open(archive).map_err(|_| io(stage))?;
    let archive_len = file.metadata().map_err(|_| io(stage))?.len();
    let mut buffer = vec![0u8; RECOMMENDED_BUFFER_SIZE];
    let archive = ZipArchive::from_file(file, &mut buffer).map_err(|_| invalid())?;

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
    let mut written_total = 0u64;
    let mut declared_total = 0u64;
    let mut count = 0u64;
    let mut entries = archive.entries(&mut buffer);
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
        // 目录与文件都先逐层核验/规划父目录：`a/b/` 允许不先出现 `a/`，central 顺序任意。
        // 两阶段：先只规划（不创建），按本次真正新增的目录数做预算裁决，超预算时**在磁盘上
        // 什么都不建**就拒绝；预算内才创建，保证"过程预算"真的守住，而不是事后补救。
        let parents = plan_parents(root, staging, &relative, stage)?;
        let adds_directory_entry = entry.is_dir() && !directories.contains_key(&relative_text);
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
            return Err(too_large());
        }
        for (parent, exists) in parents {
            if !exists {
                let created = staging.join(&parent);
                create_private_directory(&created, EXTRACT_DIRECTORY_MODE, stage)?;
            }
            directories
                .entry(parent.clone())
                .or_insert(ReceiptDirectory {
                    path: parent,
                    mode: Some(normalized_mode(DIRECTORY_MODE_BITS)),
                });
        }
        if entry.is_dir() {
            let directory_mode = normalized_mode(mode.permissions());
            match std::fs::symlink_metadata(&destination) {
                Ok(metadata) if metadata.is_dir() => {}
                Ok(_) => return Err(invalid()),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                    create_private_directory(&destination, EXTRACT_DIRECTORY_MODE, stage)?;
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

        let member_mode = normalized_mode(mode.permissions());
        // 创建即按最终权限打开：不依赖 umask，也不留"先宽后收"的窗口。
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(member_mode);
        }
        let mut output = options.open(&destination).map_err(|_| io(stage))?;
        #[cfg(unix)]
        super::permissions::verify(&destination, false, stage)?;
        let mut writer = MemberWriter {
            output: &mut output,
            hasher: Sha256::new(),
            written: 0,
            written_total: &mut written_total,
            progress,
            cancellation,
            stage,
        };
        match entry.compression_method() {
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
            _ => return Err(invalid()),
        }
        let (hasher, size) = writer.finish();
        // 先设权限再 fsync：权限位本身也必须落在持久化屏障之内。
        apply_mode(&destination, Some(member_mode))?;
        output.sync_all().map_err(|_| io(stage))?;
        members.push(ReceiptMember {
            path: relative_text,
            size,
            sha256: hex::encode(hasher.finalize()),
            mode: Some(member_mode),
        });
    }
    // 遍历结束必须与声明条数一致：声明少/多都是不可信目录。
    if count != hint {
        return Err(invalid());
    }
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

/// 写入回执；Unix 上再同步 staging 根目录项（Windows 的落盘保证来自 move 的 write-through）。
pub(super) fn write_receipt(
    root: &ManagedRoot,
    staging: &Path,
    receipt: &Receipt,
) -> Result<(), AcpInstallFailure> {
    let stage = AcpInstallStage::Publish;
    let bytes = serde_json::to_vec(receipt).map_err(|_| io(stage))?;
    let path = staging.join(RECEIPT_NAME);
    root.validate_write(&path, stage)?;
    // 显式 0600：不依赖 umask（宿主机 umask=0002 时默认 0666 会变 0664）。只影响新建文件。
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&path).map_err(|_| io(stage))?;
    #[cfg(unix)]
    super::permissions::verify(&path, false, stage)?;
    file.write_all(&bytes)
        .and_then(|()| file.sync_all())
        .map_err(|_| io(stage))?;
    #[cfg(unix)]
    {
        paths::sync_directory(staging, stage)
    }
    #[cfg(not(unix))]
    {
        Ok(())
    }
}

/// 读取已发布回执；缺失、链接、不可解析或格式不符都按缓存损坏处理，不静默替换。
pub(super) fn read_receipt(
    root: &ManagedRoot,
    installed: &Path,
) -> Result<Receipt, AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    let corrupt = || failure(AcpInstallFailureCode::CacheCorrupt, stage, false);
    let path = installed.join(RECEIPT_NAME);
    root.validate_existing(&path, stage)
        .map_err(|_| corrupt())?;
    root.require_file(&path, stage).map_err(|_| corrupt())?;
    let length = std::fs::symlink_metadata(&path)
        .map_err(|_| corrupt())?
        .len();
    if length > MAX_RECEIPT_BYTES {
        return Err(corrupt());
    }
    let bytes = std::fs::read(&path).map_err(|_| corrupt())?;
    let receipt: Receipt = serde_json::from_slice(&bytes).map_err(|_| corrupt())?;
    if receipt.format != RECEIPT_FORMAT {
        return Err(corrupt());
    }
    Ok(receipt)
}

/// 复用前的完整验证：冻结描述符、入口、完整树集合、mode/size/hash 都必须一致。
pub(super) fn verify_installed(
    root: &ManagedRoot,
    installed: &Path,
    expected: ExpectedInstall<'_>,
    cancellation: &CancellationToken,
    progress: &(dyn Fn(u64, Option<u64>) + Sync),
) -> Result<Receipt, AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    let corrupt = || failure(AcpInstallFailureCode::CacheCorrupt, stage, false);
    // 已发布安装目录同样必须在受管树内、是真实目录，且（Unix）保持产品私有权限。
    root.require_directory(installed, stage)?;
    let receipt = read_receipt(root, installed)?;
    // 回执内容必须与本次冻结描述符完全一致：ID 只是由这些字段重算出的摘要，不构成认证。
    if receipt.installation_id != expected.installation_id
        || receipt.release != *expected.release
        || receipt.command != normalize_relative(expected.command)
        || receipt.args != expected.args
        || receipt.members.is_empty()
        || receipt.members.len() > MAX_MEMBERS
        || receipt.directories.len() > MAX_MEMBERS
    {
        return Err(corrupt());
    }
    let command = normalize_relative(expected.command);
    if sanitize_member(&command)
        .map(|(path, is_dir)| path.to_string_lossy().replace('\\', "/") == command && !is_dir)
        != Some(true)
    {
        return Err(corrupt());
    }
    let mut member_index: BTreeMap<String, &ReceiptMember> = BTreeMap::new();
    let mut member_keys: BTreeMap<String, ()> = BTreeMap::new();
    let mut declared_total = 0u64;
    for member in &receipt.members {
        // 回执自身不可信：先按协议上限约束声明值，再据此哈希。
        if member.size > MAX_MEMBER_BYTES
            || member.sha256.len() != 64
            || !member.sha256.bytes().all(|byte| byte.is_ascii_hexdigit())
        {
            return Err(corrupt());
        }
        declared_total = declared_total
            .checked_add(member.size)
            .filter(|total| *total <= MAX_EXPANDED_BYTES)
            .ok_or_else(corrupt)?;
        let Some((relative, is_directory)) = sanitize_member(&member.path) else {
            return Err(corrupt());
        };
        if is_directory || relative.to_string_lossy().replace('\\', "/") != member.path {
            return Err(corrupt());
        }
        if member_keys.insert(member.path.to_lowercase(), ()).is_some() {
            return Err(corrupt());
        }
        member_index.insert(member.path.clone(), member);
    }
    if !member_index.contains_key(&command) {
        return Err(corrupt());
    }
    let mut directory_index: BTreeMap<String, &ReceiptDirectory> = BTreeMap::new();
    for directory in &receipt.directories {
        let Some((relative, is_directory)) = sanitize_member(&format!("{}/", directory.path))
        else {
            return Err(corrupt());
        };
        if !is_directory || relative.to_string_lossy().replace('\\', "/") != directory.path {
            return Err(corrupt());
        }
        if directory_index
            .insert(directory.path.to_lowercase(), directory)
            .is_some()
            || member_keys.contains_key(&directory.path.to_lowercase())
        {
            return Err(corrupt());
        }
    }
    // 实际内容集合必须与回执完全一致：任何额外/缺失条目、链接或特殊文件都会破坏集合相等
    // （严格枚举把链接与特殊文件当错误，而不是在校验前丢条目）。
    let actual = enumerate_installed(root, installed, stage)?;
    let expected_files: std::collections::BTreeSet<String> = member_index
        .keys()
        .map(|path| path.to_lowercase())
        .collect();
    let actual_files: std::collections::BTreeSet<String> = actual
        .files
        .keys()
        .map(|path| path.to_lowercase())
        .collect();
    if expected_files != actual_files
        || expected_files.len() != member_index.len()
        || actual_files.len() != actual.files.len()
    {
        return Err(corrupt());
    }
    let actual_directories: std::collections::BTreeSet<String> = actual
        .directories
        .keys()
        .map(|path| path.to_lowercase())
        .collect();
    if actual_directories != directory_index.keys().cloned().collect()
        || actual_directories.len() != actual.directories.len()
    {
        return Err(corrupt());
    }
    // 目录权限：实际值必须是已声明的归一化受控权限。
    for (path, expected) in &directory_index {
        let metadata = actual
            .directories
            .iter()
            .find(|(actual_path, _)| actual_path.to_lowercase() == *path)
            .map(|(_, metadata)| metadata);
        let Some(metadata) = metadata else {
            return Err(corrupt());
        };
        if let Some(actual_mode) = raw_mode(metadata)
            && (forbidden_bits(actual_mode)
                || Some(actual_mode & 0o777) != expected.mode.map(|mode| mode & 0o777))
        {
            return Err(corrupt());
        }
    }
    let mut processed = 0u64;
    let total = receipt.members.iter().map(|member| member.size).sum();
    for member in &receipt.members {
        if cancellation.is_cancelled() {
            return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
        }
        let path = installed.join(Path::new(&member.path));
        root.validate_existing(&path, stage)?;
        let metadata = std::fs::symlink_metadata(&path).map_err(|_| corrupt())?;
        if !metadata.is_file() || metadata.len() != member.size {
            return Err(corrupt());
        }
        // 每个既有成员在读取/哈希之前都核对路径、类型及平台适用的权限位。
        root.require_file(&path, stage).map_err(|_| corrupt())?;
        // 原始权限位：先拒真实禁用位（group/other 写、setid/sticky），再比期望值。
        if let Some(actual_mode) = raw_mode(&metadata)
            && (forbidden_bits(actual_mode)
                || Some(actual_mode & 0o777) != member.mode.map(|mode| mode & 0o777))
        {
            return Err(corrupt());
        }
        let offset = processed;
        let hashed = sha256_file(&path, cancellation, &|done, _| {
            progress(offset.saturating_add(done), Some(total))
        })?;
        if hashed != member.sha256 {
            return Err(corrupt());
        }
        processed = processed.saturating_add(member.size);
    }
    let executable = installed.join(&receipt.command);
    let metadata = std::fs::symlink_metadata(&executable).map_err(|_| corrupt())?;
    if !metadata.is_file() || !has_exec_bit(raw_mode(&metadata)) {
        return Err(failure(
            AcpInstallFailureCode::MissingExecutable,
            stage,
            false,
        ));
    }
    Ok(receipt)
}

/// 复用前的持久化补齐。
///
/// 哈希只能证明"内容相同"，不能证明上一次写入真的落了盘，因此复用必须先对每个真实成员文件与
/// 回执各做一次真实 `sync_all`，再补平台适用的屏障：
/// - Unix：逐层同步嵌套目录、已发布目录自身与新建祖先目录项；
/// - Windows：不做也不声称 Unix 等价的目录 fsync，落盘保证来自文件 `sync_all` 与发布时的同卷
///   write-through 移动（design/28 §28.7）。
///
/// 任何一步失败都如实返回 `false`，由调用方按"已发布但未确认"处理，绝不报告就绪。
pub(super) fn confirm_durable(root: &ManagedRoot, installed: &Path, receipt: &Receipt) -> bool {
    let stage = AcpInstallStage::Verify;
    if root.validate_existing(installed, stage).is_err() {
        return false;
    }
    if !sync_member_files(installed, receipt) {
        return false;
    }
    #[cfg(unix)]
    {
        sync_tree(installed, &receipt.directories, stage).is_ok()
            && paths::sync_directory(installed, stage).is_ok()
            && installed
                .parent()
                .is_some_and(|parent| paths::sync_ancestors(root.anchor(), parent, stage).is_ok())
    }
    #[cfg(not(unix))]
    {
        true
    }
}

/// 对回执列出的每个成员文件与回执自身做一次真实 `sync_all`。
///
/// Windows 的 `FlushFileBuffers` 需要可写句柄，因此那里以读写方式打开；Unix 的 `fsync` 对只读
/// 句柄同样有效。这里不读内容，也不修改文件。
fn sync_member_files(installed: &Path, receipt: &Receipt) -> bool {
    let mut paths: Vec<PathBuf> = receipt
        .members
        .iter()
        .map(|member| installed.join(&member.path))
        .collect();
    paths.push(installed.join(RECEIPT_NAME));
    paths.iter().all(|path| sync_file(path).is_ok())
}

fn sync_file(path: &Path) -> std::io::Result<()> {
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(windows)]
    options.write(true);
    options.open(path)?.sync_all()
}

/// 同文件系统原子发布：目标以任何形式存在都不覆盖（调用方必须先走复用校验）。
///
/// 移动本身复用 [`pl_tool::workspace::atomic_file::move_owned_path`] 的成熟实现：Unix 是 `rename`
/// 加两端父目录同步，Windows 是同卷 `MoveFileExW(MOVEFILE_WRITE_THROUGH, replace = false)`。
/// 它对"移动已生效但随后的同步失败"只能返回 `io::Error`，因此这里在 `Err` 分支核对
/// source/target 的实际事实：已提交就报告 [`PublishOutcome::CommittedButUnconfirmed`]，绝不谎称
/// 回滚、也不删除现场（design/28 §28.7）。
pub(super) fn publish(
    root: &ManagedRoot,
    staging: &Path,
    installed: &Path,
) -> Result<PublishOutcome, AcpInstallFailure> {
    let stage = AcpInstallStage::Publish;
    root.validate_existing(staging, stage)?;
    match std::fs::symlink_metadata(installed) {
        Ok(_) => return Err(failure(AcpInstallFailureCode::CacheCorrupt, stage, false)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(_) => return Err(io(stage)),
    }
    if let Some(parent) = installed.parent() {
        root.validate_write(parent, stage)?;
        // 目标父目录链由调用方的受管 `ensure_dir` 建立；这里只复核它仍是真实目录。
        root.validate_existing(parent, stage)?;
    }
    if pl_tool::workspace::move_owned_path(staging, installed).is_err() {
        // 移动的失败可能发生在提交之后：只按现有事实表达结果。
        let installed_present = std::fs::symlink_metadata(installed).is_ok();
        let staging_present = std::fs::symlink_metadata(staging).is_ok();
        return match (installed_present, staging_present) {
            (true, false) => Ok(PublishOutcome::CommittedButUnconfirmed),
            // 未提交（staging 仍在）或两者并存（外部干预）：保留现场并如实失败。
            _ => Err(io(stage)),
        };
    }
    // Unix 追加：已发布目录自身的目录项与新建祖先目录项需要持久化屏障（`move_owned_path` 只同步
    // 移动两端父目录）。Windows 不做、也不声称执行目录同步。
    #[cfg(unix)]
    {
        let mut confirmed = paths::sync_directory(installed, stage).is_ok();
        if let Some(parent) = installed.parent() {
            confirmed &= paths::sync_ancestors(root.anchor(), parent, stage).is_ok();
        }
        Ok(if confirmed {
            PublishOutcome::Confirmed
        } else {
            PublishOutcome::CommittedButUnconfirmed
        })
    }
    #[cfg(not(unix))]
    {
        Ok(PublishOutcome::Confirmed)
    }
}

/// 入口相对路径的规范形态：POSIX 分隔、无前导 `./`。
pub(super) fn normalize_relative(command: &str) -> String {
    let command = command.trim().replace('\\', "/");
    command.trim_start_matches("./").to_string()
}

struct ActualTree {
    files: BTreeMap<String, std::fs::Metadata>,
    directories: BTreeMap<String, std::fs::Metadata>,
}

fn enumerate_installed(
    root: &ManagedRoot,
    installed: &Path,
    stage: AcpInstallStage,
) -> Result<ActualTree, AcpInstallFailure> {
    let mut files = BTreeMap::new();
    let mut directories = BTreeMap::new();
    let mut stack = vec![installed.to_path_buf()];
    while let Some(directory) = stack.pop() {
        for (entry, metadata) in root.entries_strict(&directory, stage)? {
            // 真实树本身的规模也是不可信输入：超过协议上限的目录只能是损坏缓存。
            if files.len().saturating_add(directories.len()) > MAX_MEMBERS * 2 {
                return Err(failure(AcpInstallFailureCode::CacheCorrupt, stage, false));
            }
            let relative = entry
                .strip_prefix(installed)
                .map_err(|_| failure(AcpInstallFailureCode::CacheCorrupt, stage, false))?;
            let text = relative.to_string_lossy().replace('\\', "/");
            if metadata.is_dir() {
                directories.insert(text, metadata);
                stack.push(entry);
            } else if metadata.is_file() {
                if text == RECEIPT_NAME {
                    continue;
                }
                files.insert(text, metadata);
            } else {
                return Err(failure(AcpInstallFailureCode::CacheCorrupt, stage, false));
            }
        }
    }
    Ok(ActualTree { files, directories })
}

/// Unix 专用：由深到浅同步嵌套目录项。
#[cfg(unix)]
fn sync_tree(
    base: &Path,
    directories: &[ReceiptDirectory],
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    // 由深到浅：父目录项的持久化依赖子目录项已存在。
    let mut ordered: Vec<&ReceiptDirectory> = directories.iter().collect();
    ordered.sort_by_key(|directory| std::cmp::Reverse(directory.path.matches('/').count()));
    for directory in ordered {
        paths::sync_directory(&base.join(&directory.path), stage)?;
    }
    Ok(())
}

/// 成员路径安全校验：返回（相对路径, 是否为目录）。只允许一个尾部分隔符表示目录项。
fn sanitize_member(name: &str) -> Option<(PathBuf, bool)> {
    if name.is_empty() || name.contains('\\') || name.contains('\0') {
        return None;
    }
    let (body, is_directory) = match name.strip_suffix('/') {
        Some(body) => (body, true),
        None => (name, false),
    };
    if body.is_empty() || body.contains("//") {
        return None;
    }
    if body.starts_with('/') || body.as_bytes().get(1) == Some(&b':') {
        return None;
    }
    if body.len() > 1024 {
        return None;
    }
    let mut path = PathBuf::new();
    for segment in body.split('/') {
        if segment.is_empty() || segment == "." || segment == ".." {
            return None;
        }
        if segment.contains(':') || segment.ends_with('.') || segment.ends_with(' ') {
            return None;
        }
        if is_windows_reserved(segment) {
            return None;
        }
        if segment.chars().any(char::is_control) {
            return None;
        }
        path.push(segment);
    }
    match path.components().next() {
        Some(Component::Normal(_)) => Some((path, is_directory)),
        _ => None,
    }
}

fn is_windows_reserved(segment: &str) -> bool {
    let stem = segment
        .split('.')
        .next()
        .unwrap_or(segment)
        .trim_end()
        .to_uppercase();
    matches!(
        stem.as_str(),
        "CON"
            | "PRN"
            | "AUX"
            | "NUL"
            | "CONIN$"
            | "CONOUT$"
            | "COM1"
            | "COM2"
            | "COM3"
            | "COM4"
            | "COM5"
            | "COM6"
            | "COM7"
            | "COM8"
            | "COM9"
            | "COM¹"
            | "COM²"
            | "COM³"
            | "LPT1"
            | "LPT2"
            | "LPT3"
            | "LPT4"
            | "LPT5"
            | "LPT6"
            | "LPT7"
            | "LPT8"
            | "LPT9"
            | "LPT¹"
            | "LPT²"
            | "LPT³"
    )
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

/// 解压期间目录的临时私有权限：属主可读写执行，保证成员在目录权限最终落地前仍可写入。
const EXTRACT_DIRECTORY_MODE: u32 = 0o700;

/// 以显式权限创建目录：Unix 在创建调用上就限制权限，不留"先宽后收"的窗口。
///
/// 创建权限仍会被进程 umask 收紧，调用方随后必须显式设置最终权限（回执记录的是最终值）。
fn create_private_directory(
    path: &Path,
    mode: u32,
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    // 只有 Unix 通过 `DirBuilderExt::mode` 在创建调用上限制权限，因此可变绑定只在那里存在。
    #[cfg(unix)]
    let mut builder = std::fs::DirBuilder::new();
    #[cfg(not(unix))]
    let builder = std::fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        builder.mode(mode);
    }
    #[cfg(not(unix))]
    {
        let _ = mode;
    }
    builder.create(path).map_err(|_| io(stage))
}

/// 归一化权限位：去掉 setuid/setgid/sticky 与 group/other 写权限，保证属主可读。
fn normalized_mode(mode: u32) -> u32 {
    (mode & 0o777) & !0o022 | 0o400
}

/// 真实权限位（含禁用位），用于严格校验磁盘现状。
fn raw_mode(metadata: &std::fs::Metadata) -> Option<u32> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        Some(metadata.permissions().mode() & 0o7777)
    }
    #[cfg(not(unix))]
    {
        let _ = metadata;
        None
    }
}

/// 任何 group/other 写或 setuid/setgid/sticky 都视为不可接受。
fn forbidden_bits(mode: u32) -> bool {
    mode & 0o022 != 0 || mode & 0o7000 != 0
}

/// 入口执行资格：Unix 要求最终安装文件带执行位（包未声明时由安装器为入口补上）；
/// 其它平台以"包内普通文件"为准。
fn has_exec_bit(mode: Option<u32>) -> bool {
    #[cfg(unix)]
    {
        mode.is_some_and(|mode| mode & 0o111 != 0)
    }
    #[cfg(not(unix))]
    {
        let _ = mode;
        true
    }
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

fn io(stage: AcpInstallStage) -> AcpInstallFailure {
    failure(AcpInstallFailureCode::Io, stage, true)
}

/// 发布未确认持久化时的固定安全摘要；不承诺"未提交"，也不谎称回滚。
pub(super) fn unconfirmed_publish_failure() -> AcpInstallFailure {
    failure_with_message(
        AcpInstallFailureCode::Io,
        AcpInstallStage::Publish,
        true,
        "官方 server 安装可能已发布但未确认持久化，请重试检查",
    )
}
