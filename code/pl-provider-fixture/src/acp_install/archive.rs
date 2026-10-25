//! Real ZIP packages for the ACP auto-install acceptance.
//!
//! Every archive is produced by the workspace `zip` dependency (or by the
//! standard `zip` tool for the encrypted case); the fixture never hand-writes a
//! ZIP codec. Hostile shapes are produced by adding the real hostile member, or
//! by patching one structural field of an otherwise valid archive, so production
//! still parses them with the mature decoder.

use std::fs;
use std::io::{Cursor, Write};
use std::path::Path;
use std::sync::Arc;

use anyhow::{Context, Result, bail, ensure};
use serde::Serialize;
use sha2::{Digest, Sha256};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

use super::control::{AcpInstallControl, ArchiveVariant};
use super::fixed;

/// Auxiliary member kept next to the program, mirroring the official package
/// that ships a second helper binary.
pub const AUXILIARY_MEMBER: &str = "localharness_external";

/// Genuinely empty member the valid empty-member package ships.
pub const EMPTY_MEMBER: &str = "empty-helper.flag";

/// Whether this variant's package also carries the synthetic agent control member.
///
/// Only shapes that go through [`package`] carry it: those are the packages the
/// product can actually install and the packaged agent can be started from. The
/// hand-built hostile samples deliberately stay minimal.
fn serves_agent_control(variant: ArchiveVariant) -> bool {
    matches!(
        variant,
        ArchiveVariant::Normal
            | ArchiveVariant::ProgramNotExecutable
            | ArchiveVariant::Duplicate
            | ArchiveVariant::CaseCollision
            | ArchiveVariant::MissingExecutable
            | ArchiveVariant::Truncated
            | ArchiveVariant::CorruptCrc
            | ArchiveVariant::TooLargeDeclared
            | ArchiveVariant::SizeMismatch
    )
}

/// One member as the fixture reports it in its ready/report evidence.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct MemberRecord {
    pub path: String,
    pub size: u64,
    pub sha256: String,
    pub mode: u32,
}

/// A complete archive response the peer can serve.
#[derive(Debug)]
pub struct ArchiveBuild {
    pub bytes: Arc<Vec<u8>>,
    pub sha256: String,
    pub members: Vec<MemberRecord>,
    pub program_member: String,
}

/// Builds the archive this lifecycle serves for `target`.
pub fn build(control: &AcpInstallControl, target: &str) -> Result<ArchiveBuild> {
    let program_path = &control.archive.program;
    ensure!(
        program_path.is_file(),
        "packaged ACP fixture program is not a regular file: {}",
        program_path.display()
    );
    let program = fs::read(program_path).with_context(|| {
        format!(
            "failed to read the packaged ACP fixture program: {}",
            program_path.display()
        )
    })?;
    let auxiliary = fs::read(&control.archive.auxiliary).with_context(|| {
        format!(
            "failed to read the packaged auxiliary member: {}",
            control.archive.auxiliary.display()
        )
    })?;
    let program_name = fixed::program_member(target)
        .with_context(|| format!("no fixed Antigravity release is defined for target {target}"))?;
    let agent_control = serde_json::to_vec(&serde_json::json!({
        "stateDir": control.archive.agent_state_dir,
    }))
    .context("failed to encode the packaged agent control member")?;
    let variant = control.archive.variant;
    let bytes = match variant {
        ArchiveVariant::Normal => package(program_name, &program, &auxiliary, &agent_control)?,
        ArchiveVariant::ProgramNotExecutable => {
            package_with_modes(program_name, &program, 0o644, &auxiliary, &agent_control)?
        }
        ArchiveVariant::Traversal => hostile_member("../escape.txt", &auxiliary)?,
        ArchiveVariant::AbsolutePath => hostile_member("/etc/escape.txt", &auxiliary)?,
        ArchiveVariant::Backslash => hostile_member("sub\\..\\escape.txt", &auxiliary)?,
        ArchiveVariant::Ads => hostile_member("program.par:payload", &auxiliary)?,
        ArchiveVariant::Symlink => symlink_member(&auxiliary, "escape-link")?,
        ArchiveVariant::Duplicate => {
            let base = package(program_name, &program, &auxiliary, &agent_control)?;
            duplicate_central_entry(&base, program_name)?
        }
        ArchiveVariant::CaseCollision => {
            let bytes = package(program_name, &program, &auxiliary, &agent_control)?;
            let collision = program_name.to_uppercase();
            add_member(bytes, &collision, b"case collision\n", 0o644)?
        }
        ArchiveVariant::MissingExecutable => {
            package("not-the-program.par", &program, &auxiliary, &agent_control)?
        }
        ArchiveVariant::Truncated => {
            let bytes = package(program_name, &program, &auxiliary, &agent_control)?;
            let cut = bytes.len() * 3 / 5;
            bytes[..cut].to_vec()
        }
        ArchiveVariant::CorruptCrc => {
            let mut bytes = package(program_name, &program, &auxiliary, &agent_control)?;
            let index = bytes.len() / 3;
            bytes[index] ^= 0xFF;
            bytes
        }
        ArchiveVariant::TooLargeDeclared => {
            let bytes = package(program_name, &program, &auxiliary, &agent_control)?;
            patch_uncompressed_size(&bytes, program_name, 0xFFFF_FFF0)?
        }
        ArchiveVariant::TooManyMembers => too_many_members(program_name, &program, &auxiliary)?,
        ArchiveVariant::Zip64 => package_zip64(program_name, &program, &auxiliary)?,
        ArchiveVariant::Zip64DataDescriptor => {
            data_descriptor_package(program_name, program_path, &control.archive.auxiliary)?
        }
        ArchiveVariant::DataDescriptorZero => {
            descriptor_sample(program_name, program_path, DescriptorShape::ZeroFields)?
        }
        ArchiveVariant::DataDescriptorLocalNonZero => {
            descriptor_sample(program_name, program_path, DescriptorShape::LocalNonZero)?
        }
        ArchiveVariant::UnknownFlags => unknown_flags_package(program_name, &program)?,
        ArchiveVariant::ImplicitDirectories => {
            implicit_directories_package(program_name, &program, &auxiliary)?
        }
        ArchiveVariant::EmptyMember => {
            empty_member_package(program_name, program_path, EMPTY_MEMBER)?
        }
        ArchiveVariant::SizeMismatch => {
            let bytes = package(program_name, &program, &auxiliary, &agent_control)?;
            let declared = (program.len().saturating_sub(10)) as u32;
            patch_uncompressed_size(&bytes, program_name, declared)?
        }
        ArchiveVariant::Encrypted => encrypted_package(program_name, &program)?,
    };
    let sha256 = hex::encode(Sha256::digest(&bytes));
    let mut members = vec![MemberRecord {
        path: program_name.to_owned(),
        size: program.len() as u64,
        sha256: hex::encode(Sha256::digest(&program)),
        mode: if variant == ArchiveVariant::ProgramNotExecutable {
            0o644
        } else {
            0o755
        },
    }];
    // The peer only reports members the served archive really contains: the
    // hand-built hostile samples carry the program alone, and the empty-member
    // package carries the empty flag instead of the auxiliary asset.
    match variant {
        ArchiveVariant::DataDescriptorZero
        | ArchiveVariant::DataDescriptorLocalNonZero
        | ArchiveVariant::UnknownFlags => {}
        ArchiveVariant::EmptyMember => members.push(MemberRecord {
            path: EMPTY_MEMBER.to_owned(),
            size: 0,
            sha256: hex::encode(Sha256::digest(b"")),
            mode: 0o644,
        }),
        _ => members.push(MemberRecord {
            path: AUXILIARY_MEMBER.to_owned(),
            size: auxiliary.len() as u64,
            sha256: hex::encode(Sha256::digest(&auxiliary)),
            // A plain helper text asset keeps its non-executable mode; only the
            // program entry carries the executable bit.
            mode: 0o644,
        }),
    }
    if serves_agent_control(variant) {
        members.push(MemberRecord {
            path: fixed::AGENT_CONTROL_MEMBER.to_owned(),
            size: agent_control.len() as u64,
            sha256: hex::encode(Sha256::digest(&agent_control)),
            mode: 0o644,
        });
    }
    Ok(ArchiveBuild {
        bytes: Arc::new(bytes),
        sha256,
        members,
        program_member: program_name.to_owned(),
    })
}

fn options(mode: u32) -> SimpleFileOptions {
    SimpleFileOptions::default()
        .compression_method(CompressionMethod::Deflated)
        .unix_permissions(mode)
}

fn writer() -> ZipWriter<Cursor<Vec<u8>>> {
    ZipWriter::new(Cursor::new(Vec::new()))
}

fn finish(writer: ZipWriter<Cursor<Vec<u8>>>) -> Result<Vec<u8>> {
    let cursor = writer
        .finish()
        .context("failed to finish the ZIP package")?;
    Ok(cursor.into_inner())
}

fn package(
    program_name: &str,
    program: &[u8],
    auxiliary: &[u8],
    agent_control: &[u8],
) -> Result<Vec<u8>> {
    package_with_modes(program_name, program, 0o755, auxiliary, agent_control)
}

/// Which contradiction one descriptor sample carries.
#[derive(Clone, Copy, PartialEq, Eq)]
enum DescriptorShape {
    /// The trailing descriptor reports zero CRC/sizes while the central directory,
    /// the local bit-3 placeholder and the payload stay intact.
    ///
    /// Under the confirmed policy the product no longer re-compares the duplicated
    /// tail fields, so this package is a *positive* sample: it must install while
    /// the payload CRC, sizes, receipt and full tree are still verified.
    ZeroFields,
    /// The bit-3 local header carries non-zero, wrong sizes while the descriptor
    /// and the central directory agree.
    LocalNonZero,
}

/// One STORED member written through a non-seekable stream, then patched so the
/// data descriptor (or the local bit-3 placeholder) contradicts the truth.
///
/// The archive itself still comes from the standard-library writer; only one
/// structural field is changed, exactly like the other patched samples, so
/// production keeps parsing the file with its real decoder.
fn descriptor_sample(
    program_name: &str,
    program: &Path,
    shape: DescriptorShape,
) -> Result<Vec<u8>> {
    let directory = tempfile::Builder::new()
        .prefix("acp-install-descriptor-sample-")
        .tempdir()
        .context("failed to create the descriptor sample workspace")?;
    let archive = directory.path().join("package.zip");
    const SCRIPT: &str = r#"
import sys, zipfile
name, program, output = sys.argv[1:4]

class Stream:
    def __init__(self, handle):
        self.handle = handle
    def write(self, data):
        return self.handle.write(data)
    def flush(self):
        self.handle.flush()

with open(output, 'wb') as raw:
    with zipfile.ZipFile(Stream(raw), 'w', zipfile.ZIP_STORED, allowZip64=False) as archive:
        info = zipfile.ZipInfo(name)
        info.external_attr = 0o100755 << 16
        info.compress_type = zipfile.ZIP_STORED
        with archive.open(info, 'w', force_zip64=False) as target, open(program, 'rb') as source:
            while True:
                chunk = source.read(1 << 20)
                if not chunk:
                    break
                target.write(chunk)
"#;
    let output = std::process::Command::new("python3")
        .arg("-c")
        .arg(SCRIPT)
        .arg(program_name)
        .arg(program)
        .arg(&archive)
        .output()
        .context("the standard `python3` tool is required for the descriptor samples")?;
    ensure!(
        output.status.success(),
        "writing the descriptor sample failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    let bytes = fs::read(&archive).context("failed to read the descriptor sample")?;
    patch_descriptor_sample(&bytes, program_name, &fs::read(program)?, shape)
}

/// Applies the contradiction to one single-member STORED sample.
fn patch_descriptor_sample(
    bytes: &[u8],
    member: &str,
    payload: &[u8],
    shape: DescriptorShape,
) -> Result<Vec<u8>> {
    const LOCAL_HEADER: usize = 30;
    const DESCRIPTOR: usize = 16;
    ensure!(
        bytes.len() > LOCAL_HEADER,
        "the descriptor sample is too short to patch"
    );
    let name_len = read_u16(bytes, 26)? as usize;
    let extra_len = read_u16(bytes, 28)? as usize;
    ensure!(
        &bytes[LOCAL_HEADER..LOCAL_HEADER + name_len] == member.as_bytes(),
        "the descriptor sample does not carry the declared member"
    );
    let data_start = LOCAL_HEADER + name_len + extra_len;
    let descriptor_start = data_start + payload.len();
    ensure!(
        bytes.len() >= descriptor_start + DESCRIPTOR
            && bytes[descriptor_start..descriptor_start + 4] == [0x50, 0x4b, 7, 8],
        "the descriptor sample does not carry the expected 32-bit data descriptor"
    );
    let mut patched = bytes.to_vec();
    match shape {
        DescriptorShape::ZeroFields => {
            // Local placeholder stays zero; the descriptor itself lies.
            for offset in [4, 8, 12] {
                patched[descriptor_start + offset..descriptor_start + offset + 4]
                    .copy_from_slice(&0u32.to_le_bytes());
            }
        }
        DescriptorShape::LocalNonZero => {
            // Local bit-3 fields must stay a zero placeholder; write a wrong,
            // non-zero value so neither the placeholder nor the truth is present.
            let crc = read_u32(bytes, LOCAL_HEADER - 16)?;
            let size = read_u32(bytes, LOCAL_HEADER - 12)?;
            write_u32(&mut patched, LOCAL_HEADER - 16, crc.wrapping_add(1))?;
            write_u32(&mut patched, LOCAL_HEADER - 12, size.wrapping_add(1))?;
            write_u32(&mut patched, LOCAL_HEADER - 8, size.wrapping_add(1))?;
        }
    }
    Ok(patched)
}

/// Archive whose general-purpose flags carry patched-data (bit 5), which is not in
/// the supported allowlist, on both the local and the central record.
fn unknown_flags_package(program_name: &str, program: &[u8]) -> Result<Vec<u8>> {
    const PATCHED_DATA: u16 = 0x0020;
    let mut zip = writer();
    zip.start_file(program_name, options(0o755))?;
    zip.write_all(program)?;
    let bytes = finish(zip)?;
    let entries = central_entries(&bytes)?;
    let entry = entries
        .iter()
        .find(|entry| entry.name == program_name)
        .with_context(|| format!("the fixture archive did not contain `{program_name}`"))?;
    let mut patched = bytes.clone();
    // Local header flags at +6, central record flags at +8.
    write_u16(&mut patched, 6, PATCHED_DATA)?;
    write_u16(&mut patched, entry.header_offset + 8, PATCHED_DATA)?;
    Ok(patched)
}

/// Valid package that ships a genuinely empty member next to the program.
///
/// The sample is written through a non-seekable stream so the empty member's
/// local header, data descriptor and central record all carry real zeros: an
/// archive reader must accept it instead of treating "zero sizes" as a lie.
fn empty_member_package(program_name: &str, program: &Path, empty_member: &str) -> Result<Vec<u8>> {
    let directory = tempfile::Builder::new()
        .prefix("acp-install-empty-member-")
        .tempdir()
        .context("failed to create the empty-member workspace")?;
    let archive = directory.path().join("package.zip");
    const SCRIPT: &str = r#"
import sys, zipfile
program_name, program, empty_member, output = sys.argv[1:5]

class Stream:
    def __init__(self, handle):
        self.handle = handle
    def write(self, data):
        return self.handle.write(data)
    def flush(self):
        self.handle.flush()

with open(output, 'wb') as raw:
    with zipfile.ZipFile(Stream(raw), 'w', zipfile.ZIP_STORED, allowZip64=False) as archive:
        info = zipfile.ZipInfo(program_name)
        info.external_attr = 0o100755 << 16
        info.compress_type = zipfile.ZIP_STORED
        with archive.open(info, 'w', force_zip64=False) as target, open(program, 'rb') as source:
            while True:
                chunk = source.read(1 << 20)
                if not chunk:
                    break
                target.write(chunk)
        empty = zipfile.ZipInfo(empty_member)
        empty.external_attr = 0o100644 << 16
        empty.compress_type = zipfile.ZIP_STORED
        archive.writestr(empty, b'')
"#;
    let output = std::process::Command::new("python3")
        .arg("-c")
        .arg(SCRIPT)
        .arg(program_name)
        .arg(program)
        .arg(empty_member)
        .arg(&archive)
        .output()
        .context("the standard `python3` tool is required for the empty-member sample")?;
    ensure!(
        output.status.success(),
        "writing the empty-member sample failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    fs::read(&archive).context("failed to read the empty-member sample")
}

/// Program plus 300 two-level members: 600 implicit directories against 301
/// members, so the directory budget rejects it while the member budget does not.
fn implicit_directories_package(
    program_name: &str,
    program: &[u8],
    auxiliary: &[u8],
) -> Result<Vec<u8>> {
    let mut zip = writer();
    zip.start_file(program_name, options(0o755))?;
    zip.write_all(program)?;
    zip.start_file(AUXILIARY_MEMBER, options(0o644))?;
    zip.write_all(auxiliary)?;
    for index in 0..300 {
        zip.start_file(format!("d{index}/e{index}/payload.txt"), options(0o644))?;
        zip.write_all(format!("directory budget member {index}\n").as_bytes())?;
    }
    finish(zip)
}

fn package_with_modes(
    program_name: &str,
    program: &[u8],
    program_mode: u32,
    auxiliary: &[u8],
    agent_control: &[u8],
) -> Result<Vec<u8>> {
    let mut zip = writer();
    zip.start_file(program_name, options(program_mode))?;
    zip.write_all(program)?;
    zip.start_file(AUXILIARY_MEMBER, options(0o644))?;
    zip.write_all(auxiliary)?;
    // The packaged agent locates its synthetic state directory through this
    // member. It is a real package member: the receipt, the full-tree check and
    // the reuse verification all cover it like any other file.
    zip.start_file(fixed::AGENT_CONTROL_MEMBER, options(0o644))?;
    zip.write_all(agent_control)?;
    finish(zip)
}

/// Writes the real package plus enough extra members to exceed the documented
/// 512-member budget.
fn too_many_members(program_name: &str, program: &[u8], auxiliary: &[u8]) -> Result<Vec<u8>> {
    let mut zip = writer();
    zip.start_file(program_name, options(0o755))?;
    zip.write_all(program)?;
    zip.start_file(AUXILIARY_MEMBER, options(0o644))?;
    zip.write_all(auxiliary)?;
    for index in 0..512 {
        let name = format!("filler/{index:03}.txt");
        zip.start_file(&name, options(0o644))?;
        zip.write_all(b"member\n")?;
    }
    finish(zip)
}

/// Valid package whose members carry ZIP64 extra fields.
fn package_zip64(program_name: &str, program: &[u8], auxiliary: &[u8]) -> Result<Vec<u8>> {
    let mut zip = writer();
    zip.start_file(program_name, options(0o755).large_file(true))?;
    zip.write_all(program)?;
    zip.start_file(AUXILIARY_MEMBER, options(0o644).large_file(true))?;
    zip.write_all(auxiliary)?;
    finish(zip)
}

/// Valid package written as a stream: both members carry ZIP64 metadata and data
/// descriptors, so a reader must use the central directory instead of local sizes.
///
/// The workspace `zip` writer always knows its sizes up front, so this sample is
/// produced by the mature Python standard-library writer through a non-seekable
/// stream (`force_zip64`), mirroring how streaming encoders emit descriptors.
fn data_descriptor_package(
    program_name: &str,
    program: &Path,
    auxiliary: &Path,
) -> Result<Vec<u8>> {
    let directory = tempfile::Builder::new()
        .prefix("acp-install-data-descriptor-")
        .tempdir()
        .context("failed to create the data-descriptor workspace")?;
    let archive = directory.path().join("package.zip");
    const SCRIPT: &str = r#"
import sys, zipfile
program_name, program, auxiliary, output = sys.argv[1:5]

class Stream:
    def __init__(self, handle):
        self.handle = handle
    def write(self, data):
        return self.handle.write(data)
    def flush(self):
        self.handle.flush()

def copy(archive, name, path, mode):
    info = zipfile.ZipInfo(name)
    info.external_attr = mode << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with archive.open(info, 'w', force_zip64=True) as target, open(path, 'rb') as source:
        while True:
            chunk = source.read(1 << 20)
            if not chunk:
                break
            target.write(chunk)

with open(output, 'wb') as raw:
    with zipfile.ZipFile(Stream(raw), 'w', zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
        copy(archive, program_name, program, 0o100755)
        copy(archive, 'localharness_external', auxiliary, 0o100644)
"#;
    let output = std::process::Command::new("python3")
        .arg("-c")
        .arg(SCRIPT)
        .arg(program_name)
        .arg(program)
        .arg(auxiliary)
        .arg(&archive)
        .output()
        .context("the standard `python3` tool is required for the data-descriptor sample")?;
    ensure!(
        output.status.success(),
        "the standard Python ZIP writer failed: {}",
        String::from_utf8_lossy(&output.stderr).trim()
    );
    fs::read(&archive).context("failed to read the data-descriptor archive")
}

fn hostile_member(name: &str, auxiliary: &[u8]) -> Result<Vec<u8>> {
    let mut zip = writer();
    zip.start_file(name, options(0o755))?;
    zip.write_all(auxiliary)?;
    finish(zip)
}

fn symlink_member(auxiliary: &[u8], link: &str) -> Result<Vec<u8>> {
    let mut zip = writer();
    zip.add_symlink(link, "/etc/passwd", options(0o777))?;
    zip.start_file(AUXILIARY_MEMBER, options(0o644))?;
    zip.write_all(auxiliary)?;
    finish(zip)
}

fn add_member(bytes: Vec<u8>, name: &str, data: &[u8], mode: u32) -> Result<Vec<u8>> {
    let archive = ZipArchive::new(Cursor::new(bytes)).context("fixture archive is unreadable")?;
    let mut zip = writer();
    zip.merge_archive(archive)
        .context("failed to merge the fixture archive")?;
    zip.start_file(name, options(mode))?;
    zip.write_all(data)?;
    finish(zip)
}

/// Pushes one structural field past the per-member budget without writing the
/// bytes: the declared expanded size lives in the central directory.
fn patch_uncompressed_size(bytes: &[u8], member: &str, declared: u32) -> Result<Vec<u8>> {
    let mut patched = bytes.to_vec();
    let mut found = false;
    for entry in central_entries(bytes)? {
        if entry.name != member {
            continue;
        }
        let offset = entry.header_offset + 24;
        patched[offset..offset + 4].copy_from_slice(&declared.to_le_bytes());
        found = true;
    }
    ensure!(
        found,
        "the fixture archive did not contain the declared member `{member}`"
    );
    Ok(patched)
}

/// Repeats the central-directory record of `member` so the package declares the
/// same name twice, which a strict extractor must reject.
fn duplicate_central_entry(bytes: &[u8], member: &str) -> Result<Vec<u8>> {
    let entries = central_entries(bytes)?;
    let entry = entries
        .iter()
        .find(|entry| entry.name == member)
        .with_context(|| format!("the fixture archive did not contain `{member}`"))?;
    let eocd = eocd_offset(bytes)?;
    let record = &bytes[entry.header_offset..entry.header_offset + entry.record_len];
    let mut patched = Vec::with_capacity(bytes.len() + record.len());
    patched.extend_from_slice(&bytes[..eocd]);
    patched.extend_from_slice(record);
    patched.extend_from_slice(&bytes[eocd..]);
    let new_eocd = eocd + record.len();
    // EOCD layout: signature (4), disk (2), cd disk (2), entries this disk (2),
    // total entries (2), cd size (4), cd offset (4), comment (2).
    let entries_this_disk = read_u16(&patched, new_eocd + 8)? + 1;
    let total_entries = read_u16(&patched, new_eocd + 10)? + 1;
    let cd_size = read_u32(&patched, new_eocd + 12)? + record.len() as u32;
    write_u16(&mut patched, new_eocd + 8, entries_this_disk)?;
    write_u16(&mut patched, new_eocd + 10, total_entries)?;
    write_u32(&mut patched, new_eocd + 12, cd_size)?;
    Ok(patched)
}

struct CentralEntry {
    name: String,
    header_offset: usize,
    record_len: usize,
}

fn central_entries(bytes: &[u8]) -> Result<Vec<CentralEntry>> {
    let mut entries = Vec::new();
    let eocd = eocd_offset(bytes)?;
    let count = read_u16(bytes, eocd + 10)? as usize;
    let mut cursor = read_u32(bytes, eocd + 16)? as usize;
    for _ in 0..count {
        ensure!(
            cursor + 46 <= bytes.len(),
            "the fixture archive has a truncated central directory"
        );
        let name_len = read_u16(bytes, cursor + 28)? as usize;
        let extra_len = read_u16(bytes, cursor + 30)? as usize;
        let comment_len = read_u16(bytes, cursor + 32)? as usize;
        let name_start = cursor + 46;
        let name_end = name_start + name_len;
        ensure!(
            name_end <= bytes.len(),
            "the fixture archive has a truncated central directory"
        );
        let name = String::from_utf8_lossy(&bytes[name_start..name_end]).into_owned();
        entries.push(CentralEntry {
            name,
            header_offset: cursor,
            record_len: 46 + name_len + extra_len + comment_len,
        });
        cursor += 46 + name_len + extra_len + comment_len;
    }
    ensure!(
        !entries.is_empty(),
        "the fixture archive has no central directory"
    );
    Ok(entries)
}

fn eocd_offset(bytes: &[u8]) -> Result<usize> {
    const SIGNATURE: [u8; 4] = [b'P', b'K', 5, 6];
    let tail = bytes.len().saturating_sub(64);
    for cursor in (tail..bytes.len().saturating_sub(3)).rev() {
        if bytes[cursor..cursor + 4] == SIGNATURE {
            return Ok(cursor);
        }
    }
    bail!("the fixture archive has no end-of-central-directory record")
}

fn read_u16(bytes: &[u8], offset: usize) -> Result<u16> {
    let slice = bytes
        .get(offset..offset + 2)
        .context("fixture archive field is out of bounds")?;
    Ok(u16::from_le_bytes([slice[0], slice[1]]))
}

fn read_u32(bytes: &[u8], offset: usize) -> Result<u32> {
    let slice = bytes
        .get(offset..offset + 4)
        .context("fixture archive field is out of bounds")?;
    Ok(u32::from_le_bytes([slice[0], slice[1], slice[2], slice[3]]))
}

fn write_u16(bytes: &mut [u8], offset: usize, value: u16) -> Result<()> {
    let slice = bytes
        .get_mut(offset..offset + 2)
        .context("fixture archive field is out of bounds")?;
    slice.copy_from_slice(&value.to_le_bytes());
    Ok(())
}

fn write_u32(bytes: &mut [u8], offset: usize, value: u32) -> Result<()> {
    let slice = bytes
        .get_mut(offset..offset + 4)
        .context("fixture archive field is out of bounds")?;
    slice.copy_from_slice(&value.to_le_bytes());
    Ok(())
}

/// Encrypted packages cannot be produced by the workspace `zip` dependency
/// (default features are disabled), so the standard Info-ZIP tool creates one.
/// A missing tool is a fixture error, never a silent "accepted" archive.
fn encrypted_package(program_name: &str, program: &[u8]) -> Result<Vec<u8>> {
    let directory = tempfile::Builder::new()
        .prefix("acp-install-encrypted-")
        .tempdir()
        .context("failed to create the encrypted archive workspace")?;
    let member = directory.path().join(program_name);
    fs::write(&member, program).context("failed to stage the encrypted archive member")?;
    let archive = directory.path().join("encrypted.zip");
    let output = std::process::Command::new("zip")
        .current_dir(directory.path())
        .args(["-q", "-P", "fixture-secret", "-j"])
        .arg(&archive)
        .arg(Path::new(program_name))
        .output()
        .context("the standard `zip` tool is required for the encrypted archive shape")?;
    ensure!(
        output.status.success(),
        "the standard `zip` tool failed to build the encrypted archive: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    fs::read(&archive).context("failed to read the encrypted archive")
}
