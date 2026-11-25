//! Verify the frozen receipt and actual contents before reusing a published installation.

use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;
use tokio_util::sync::CancellationToken;

use super::{
    ExpectedInstall, MAX_EXPANDED_BYTES, MAX_MEMBER_BYTES, MAX_MEMBERS, RECEIPT_NAME, Receipt,
    ReceiptDirectory, has_exec_bit, normalize_relative, raw_mode, read_receipt, sanitize_member,
    sha256_file,
};
#[cfg(unix)]
use crate::studio::runtime::acp_install::permissions;
use crate::studio::runtime::acp_install::{mapping::failure, paths::ManagedRoot};
use crate::{AcpInstallFailure, AcpInstallFailureCode, AcpInstallStage};

/// 复用前的完整验证：冻结描述符、入口、完整树集合、mode/size/hash 都必须一致。
pub(in crate::studio::runtime::acp_install) fn verify_installed(
    root: &ManagedRoot,
    installed: &Path,
    expected: ExpectedInstall<'_>,
    cancellation: &CancellationToken,
    progress: &(dyn Fn(u64, Option<u64>) + Sync),
) -> Result<Receipt, AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    // 已发布安装目录同样必须在受管树内、是真实目录，且（Unix）保持产品私有权限。
    root.require_directory(installed, stage)?;
    let receipt = read_receipt(root, installed)?;
    let declared = index_receipt(&receipt, expected)?;
    verify_tree(root, installed, &declared)?;
    verify_members(root, installed, &receipt, cancellation, progress)?;
    Ok(receipt)
}

struct DeclaredTree<'a> {
    files: BTreeSet<String>,
    directories: BTreeMap<String, &'a ReceiptDirectory>,
}

fn index_receipt<'a>(
    receipt: &'a Receipt,
    expected: ExpectedInstall<'_>,
) -> Result<DeclaredTree<'a>, AcpInstallFailure> {
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
    let mut member_keys = BTreeSet::new();
    let mut executable_declared = false;
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
        if !member_keys.insert(member.path.to_lowercase()) {
            return Err(corrupt());
        }
        executable_declared |= member.path == command;
    }
    if !executable_declared {
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
            || member_keys.contains(&directory.path.to_lowercase())
        {
            return Err(corrupt());
        }
    }
    Ok(DeclaredTree {
        files: member_keys,
        directories: directory_index,
    })
}

fn verify_tree(
    root: &ManagedRoot,
    installed: &Path,
    expected: &DeclaredTree<'_>,
) -> Result<(), AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    // 实际内容集合必须与回执完全一致：任何额外/缺失条目、链接或特殊文件都会破坏集合相等
    // （严格枚举把链接与特殊文件当错误，而不是在校验前丢条目）。
    let actual = enumerate_installed(root, installed, stage)?;
    let actual_files: BTreeSet<_> = actual
        .files
        .keys()
        .map(|path| path.to_lowercase())
        .collect();
    if expected.files != actual_files || actual_files.len() != actual.files.len() {
        return Err(corrupt());
    }
    let actual_directories: BTreeMap<_, _> = actual
        .directories
        .iter()
        .map(|(path, metadata)| (path.to_lowercase(), metadata))
        .collect();
    if actual_directories.len() != actual.directories.len()
        || !actual_directories.keys().eq(expected.directories.keys())
    {
        return Err(corrupt());
    }
    for (path, directory) in &expected.directories {
        verify_mode(actual_directories[path], directory.mode)?;
    }
    Ok(())
}

fn verify_members(
    root: &ManagedRoot,
    installed: &Path,
    receipt: &Receipt,
    cancellation: &CancellationToken,
    progress: &(dyn Fn(u64, Option<u64>) + Sync),
) -> Result<(), AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
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
        verify_mode(&metadata, member.mode)?;
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
    Ok(())
}

fn verify_mode(
    metadata: &std::fs::Metadata,
    expected: Option<u32>,
) -> Result<(), AcpInstallFailure> {
    #[cfg(unix)]
    if let Some(mode) = raw_mode(metadata)
        && (permissions::forbidden_bits(mode)
            || Some(mode & 0o777) != expected.map(|mode| mode & 0o777))
    {
        return Err(corrupt());
    }
    #[cfg(not(unix))]
    let _ = (metadata, expected);
    Ok(())
}

fn corrupt() -> AcpInstallFailure {
    failure(
        AcpInstallFailureCode::CacheCorrupt,
        AcpInstallStage::Verify,
        false,
    )
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
