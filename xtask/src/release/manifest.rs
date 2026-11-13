use super::asset_name;
use anyhow::{Context, Result, anyhow, bail};
use minisign_verify::{PublicKey, Signature};
use pl_dev_support::process;
use semver::Version;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::env;
use std::ffi::OsString;
use std::fs::{self, File};
use std::io::{BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

const REPOSITORY_RELEASES: &str = "https://github.com/ZR233/pure-lang/releases";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdateManifest {
    schema_version: u32,
    version: String,
    published_at: i64,
    notes_url: String,
    platforms: UpdatePlatforms,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct UpdatePlatforms {
    #[serde(rename = "windows-x86_64")]
    windows_x86_64: UpdateAsset,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdateAsset {
    url: String,
    size: u64,
    sha256: String,
    signature: String,
}

/// Current multi-platform feed. The schema-1 Windows projection above remains
/// solely for already installed external clients which reject unknown fields.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UnifiedManifest {
    schema_version: u32,
    version: String,
    published_at: i64,
    notes_url: String,
    platforms: BTreeMap<String, UpdateAsset>,
}

fn unified_manifest_for(
    directory: &Path,
    version: &Version,
    published_at: i64,
) -> Result<UnifiedManifest> {
    let mut platforms = BTreeMap::new();
    for (platform, name) in [
        ("windows-x86_64", asset_name(version, "setup.exe")),
        (
            "linux-x86_64",
            format!("anywork-{version}-linux-x86_64.deb"),
        ),
    ] {
        let path = directory.join(&name);
        if !path.is_file() {
            continue;
        }
        let url = format!("https://github.com/ZR233/anywork/releases/download/v{version}/{name}");
        platforms.insert(
            platform.to_owned(),
            UpdateAsset {
                signature: format!("{url}.minisig"),
                url,
                size: fs::metadata(&path)?.len(),
                sha256: sha256_file(&path)?,
            },
        );
    }
    Ok(UnifiedManifest {
        schema_version: 2,
        version: version.to_string(),
        published_at,
        notes_url: format!("https://github.com/ZR233/anywork/releases/tag/v{version}"),
        platforms,
    })
}

pub(super) fn finalize(workspace_root: &Path, release_dir: &Path, version: &Version) -> Result<()> {
    if !cfg!(target_os = "windows") {
        bail!(
            "release-gui finalize supports Windows only; Linux/macOS stage produces final assets"
        );
    }
    ensure_staged_assets(release_dir, version)?;
    let setup_name = asset_name(version, "setup.exe");
    let setup_path = release_dir.join(&setup_name);
    let setup_hash = sha256_file(&setup_path)?;

    let secret_key = env::var_os("MINISIGN_SECRET_KEY_FILE")
        .map(PathBuf::from)
        .context("MINISIGN_SECRET_KEY_FILE is required for release-gui finalize")?;
    let password = env::var("MINISIGN_PASSWORD")
        .context("MINISIGN_PASSWORD is required for release-gui finalize")?;
    let password_input = minisign_password_input(&password)?;
    let public_key = env::var_os("MINISIGN_PUBLIC_KEY_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| workspace_root.join("code/pl-studio-update/src/anywork.pub"));
    for name in payload_names(release_dir, version) {
        let path = release_dir.join(name);
        if PathBuf::from(format!("{}.minisig", path.display())).is_file() {
            // Combining platform checkpoints must preserve already signed bytes.
            verify_signature(&public_key, &path)?;
        } else {
            sign_file(&secret_key, &path, version, &password_input)?;
        }
    }
    let timestamp = if release_dir.join("latest.json").is_file() {
        let existing: UpdateManifest =
            serde_json::from_slice(&fs::read(release_dir.join("latest.json"))?)?;
        verify_manifest(&existing, release_dir, version)?;
        existing.published_at
    } else {
        published_at()?
    };

    let manifest = manifest_for(
        version,
        timestamp,
        &setup_name,
        fs::metadata(&setup_path)?.len(),
        setup_hash.clone(),
    );
    let manifest_path = release_dir.join("latest.json");
    fs::write(&manifest_path, serde_json::to_vec_pretty(&manifest)?)
        .with_context(|| format!("failed to write {}", manifest_path.display()))?;

    fs::write(
        release_dir.join("latest-v2.json"),
        serde_json::to_vec_pretty(&unified_manifest_for(release_dir, version, timestamp)?)?,
    )?;
    let sums = payload_names(release_dir, version)
        .into_iter()
        .map(|name| {
            Ok(format!(
                "{}  {name}",
                sha256_file(&release_dir.join(&name))?
            ))
        })
        .collect::<Result<Vec<_>>>()?
        .join("\n")
        + "\n";
    fs::write(release_dir.join("SHA256SUMS.txt"), sums)?;
    verify(workspace_root, release_dir, version)
}

pub(super) fn verify(workspace_root: &Path, release_dir: &Path, version: &Version) -> Result<()> {
    #[cfg(target_os = "linux")]
    if !release_dir.join("latest-v2.json").is_file() {
        return super::linux::verify(release_dir, version);
    }
    #[cfg(target_os = "macos")]
    if !release_dir.join("latest-v2.json").is_file() {
        return super::macos::verify(release_dir, version);
    }
    ensure_staged_assets(release_dir, version)?;
    let expected = expected_files(release_dir, version);
    let mut actual = fs::read_dir(release_dir)
        .with_context(|| format!("failed to read {}", release_dir.display()))?
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_file()))
        .map(|entry| entry.file_name().to_string_lossy().into_owned())
        .collect::<Vec<_>>();
    actual.sort();
    if actual != expected {
        bail!("release file set mismatch; expected {expected:?}, got {actual:?}");
    }

    let manifest_path = release_dir.join("latest.json");
    let manifest: UpdateManifest = serde_json::from_slice(&fs::read(&manifest_path)?)
        .with_context(|| format!("invalid update manifest: {}", manifest_path.display()))?;
    verify_manifest(&manifest, release_dir, version)?;
    let unified: UnifiedManifest =
        serde_json::from_slice(&fs::read(release_dir.join("latest-v2.json"))?)?;
    if unified != unified_manifest_for(release_dir, version, manifest.published_at)? {
        bail!("multi-platform manifest does not match the staged version and bytes");
    }
    verify_sums(release_dir, version)?;
    for name in [
        format!("anywork-{version}-linux-x86_64.deb"),
        format!("anywork-{version}-macos-arm64.zip"),
    ] {
        if release_dir.join(&name).is_file() {
            let expected = format!("{}  {name}\n", sha256_file(&release_dir.join(&name))?);
            if fs::read_to_string(release_dir.join(format!("{name}.sha256")))?.replace("\r\n", "\n")
                != expected
            {
                bail!("package checksum does not match {name}");
            }
        }
    }

    let public_key = env::var_os("MINISIGN_PUBLIC_KEY_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            workspace_root
                .join("code")
                .join("pl-studio-update")
                .join("src")
                .join("anywork.pub")
        });
    for file in payload_names(release_dir, version) {
        verify_signature(&public_key, &release_dir.join(file))?;
    }
    println!("Verified stable release: {}", release_dir.display());
    Ok(())
}

fn ensure_staged_assets(release_dir: &Path, version: &Version) -> Result<()> {
    let path = release_dir.join(asset_name(version, "setup.exe"));
    if !path.is_file() {
        bail!("release asset not found: {}", path.display());
    }
    Ok(())
}

fn manifest_for(
    version: &Version,
    published_at: i64,
    setup_name: &str,
    size: u64,
    sha256: String,
) -> UpdateManifest {
    let tag = format!("v{version}");
    let url = format!("{REPOSITORY_RELEASES}/download/{tag}/{setup_name}");
    UpdateManifest {
        schema_version: 1,
        version: version.to_string(),
        published_at,
        notes_url: format!("{REPOSITORY_RELEASES}/tag/{tag}"),
        platforms: UpdatePlatforms {
            windows_x86_64: UpdateAsset {
                signature: format!("{url}.minisig"),
                url,
                size,
                sha256,
            },
        },
    }
}

fn verify_manifest(manifest: &UpdateManifest, release_dir: &Path, version: &Version) -> Result<()> {
    if manifest.schema_version != 1 || manifest.version != version.to_string() {
        bail!("manifest schema or version mismatch");
    }
    let expected_name = asset_name(version, "setup.exe");
    let expected = manifest_for(
        version,
        manifest.published_at,
        &expected_name,
        manifest.platforms.windows_x86_64.size,
        manifest.platforms.windows_x86_64.sha256.clone(),
    );
    if manifest != &expected {
        bail!("manifest URLs or asset metadata do not match the fixed release contract");
    }
    let path = release_dir.join(expected_name);
    if fs::metadata(&path)?.len() != manifest.platforms.windows_x86_64.size {
        bail!("manifest size does not match installer bytes");
    }
    if sha256_file(&path)? != manifest.platforms.windows_x86_64.sha256 {
        bail!("manifest SHA-256 does not match installer bytes");
    }
    Ok(())
}

fn verify_sums(release_dir: &Path, version: &Version) -> Result<()> {
    let expected = payload_names(release_dir, version)
        .into_iter()
        .map(|name| {
            Ok(format!(
                "{}  {name}",
                sha256_file(&release_dir.join(&name))?
            ))
        })
        .collect::<Result<Vec<_>>>()?
        .join("\n")
        + "\n";
    let actual = fs::read_to_string(release_dir.join("SHA256SUMS.txt"))?;
    if actual.replace("\r\n", "\n") != expected {
        bail!("SHA256SUMS.txt does not match release assets");
    }
    Ok(())
}

fn payload_names(directory: &Path, version: &Version) -> Vec<String> {
    let mut names = vec![asset_name(version, "setup.exe")];
    let linux = format!("anywork-{version}-linux-x86_64.deb");
    if directory.join(&linux).is_file() {
        names.push(linux);
    }
    names
}

fn expected_files(directory: &Path, version: &Version) -> Vec<String> {
    let setup = asset_name(version, "setup.exe");
    let mut files = vec![
        "SHA256SUMS.txt".to_string(),
        format!("{setup}.minisig"),
        setup,
        "latest.json".to_string(),
        "latest-v2.json".to_string(),
    ];
    for name in payload_names(directory, version).into_iter().skip(1) {
        files.extend([
            name.clone(),
            format!("{name}.minisig"),
            format!("{name}.sha256"),
        ]);
    }
    let macos = format!("anywork-{version}-macos-arm64.zip");
    if directory.join(&macos).is_file() {
        files.extend([macos.clone(), format!("{macos}.sha256")]);
    }
    files.sort();
    files
}

pub(super) fn sha256_file(path: &Path) -> Result<String> {
    let mut reader = BufReader::new(
        File::open(path).with_context(|| format!("failed to open {}", path.display()))?,
    );
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = reader.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
    }
    Ok(hex::encode(hasher.finalize()))
}

fn sign_file(
    secret_key: &Path,
    message: &Path,
    version: &Version,
    password_input: &[u8],
) -> Result<()> {
    if !secret_key.is_file() {
        bail!("Minisign secret key not found: {}", secret_key.display());
    }
    let signature = PathBuf::from(format!("{}.minisig", message.display()));
    let args = [
        OsString::from("-S"),
        OsString::from("-s"),
        secret_key.as_os_str().to_owned(),
        OsString::from("-m"),
        message.as_os_str().to_owned(),
        OsString::from("-x"),
        signature.as_os_str().to_owned(),
        OsString::from("-t"),
        OsString::from(format!("anywork {version}")),
    ];
    let mut command = Command::new("minisign");
    command.args(args);
    process::run_checked_with_stdin(
        &mut command,
        &format!("minisign sign {}", message.display()),
        password_input,
    )
}

fn minisign_password_input(password: &str) -> Result<Vec<u8>> {
    if password.is_empty() {
        bail!("MINISIGN_PASSWORD must not be empty");
    }
    if password.contains(['\r', '\n']) {
        bail!("MINISIGN_PASSWORD must be a single line");
    }
    let mut input = Vec::with_capacity(password.len() + 2);
    input.extend_from_slice(password.as_bytes());
    input.extend_from_slice(b"\r\n");
    Ok(input)
}

fn verify_signature(public_key: &Path, message: &Path) -> Result<()> {
    if !public_key.is_file() {
        bail!("Minisign public key not found: {}", public_key.display());
    }
    let signature = PathBuf::from(format!("{}.minisig", message.display()));
    let public_key =
        fs::read_to_string(public_key).context("failed to read Minisign public key")?;
    let signature = fs::read_to_string(signature).context("failed to read Minisign signature")?;
    let message = File::open(message).context("failed to open signed release asset")?;
    verify_signature_reader(&public_key, &signature, message)
}

fn verify_signature_reader(
    public_key: &str,
    signature: &str,
    mut message: impl Read,
) -> Result<()> {
    let public_key =
        PublicKey::decode(public_key).map_err(|error| anyhow!("invalid Minisign key: {error}"))?;
    let signature = Signature::decode(signature)
        .map_err(|error| anyhow!("invalid Minisign signature: {error}"))?;
    let mut verifier = public_key
        .verify_stream(&signature)
        .map_err(|error| anyhow!("failed to initialize Minisign verification: {error}"))?;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let count = message.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        verifier.update(&buffer[..count]);
    }
    verifier
        .finalize()
        .map_err(|error| anyhow!("Minisign verification failed: {error}"))
}

fn published_at() -> Result<i64> {
    if let Ok(value) = env::var("SOURCE_DATE_EPOCH") {
        return value
            .parse::<i64>()
            .context("SOURCE_DATE_EPOCH must be Unix seconds");
    }
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before Unix epoch")?
        .as_secs();
    i64::try_from(seconds).context("current Unix timestamp does not fit i64")
}

#[cfg(test)]
mod feed_tests {
    use super::*;
    #[test]
    fn current_feed_selects_platform_assets_while_legacy_projection_stays_windows_only() {
        let directory = tempfile::tempdir().unwrap();
        let version = Version::new(1, 2, 3);
        let setup = asset_name(&version, "setup.exe");
        let deb = format!("anywork-{version}-linux-x86_64.deb");
        fs::write(directory.path().join(&setup), b"windows payload").unwrap();
        let windows = unified_manifest_for(directory.path(), &version, 123).unwrap();
        assert_eq!(windows.platforms.len(), 1);
        fs::write(directory.path().join(&deb), b"linux payload").unwrap();
        let both = unified_manifest_for(directory.path(), &version, 123).unwrap();
        assert_eq!(both.platforms.len(), 2);
        assert_eq!(
            both.platforms["windows-x86_64"],
            windows.platforms["windows-x86_64"]
        );
        assert_eq!(
            both.platforms["linux-x86_64"].sha256,
            sha256_file(&directory.path().join(&deb)).unwrap()
        );
        let old = manifest_for(&version, 123, &setup, 15, "a".repeat(64));
        let encoded = serde_json::to_value(old).unwrap();
        assert_eq!(encoded["schemaVersion"], 1);
        assert_eq!(encoded["platforms"].as_object().unwrap().len(), 1);
        assert!(encoded["platforms"].get("linux-x86_64").is_none());
        fs::write(directory.path().join(&deb), b"changed").unwrap();
        assert_ne!(
            both,
            unified_manifest_for(directory.path(), &version, 123).unwrap()
        );
    }
}
