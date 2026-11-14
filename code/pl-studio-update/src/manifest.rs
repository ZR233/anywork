use super::error::{StudioUpdateError, StudioUpdateErrorCode};
use super::types::{StudioUpdate, StudioUpdateAsset, StudioUpdateCheck};
use crate::StudioUpdatePlatform;
use semver::Version;
use serde::Deserialize;
use std::collections::BTreeMap;
use url::Url;

pub(super) const LATEST_MANIFEST_URL: &str =
    "https://github.com/ZR233/anywork/releases/latest/download/latest-v2.json";
pub(super) const MAX_INSTALLER_BYTES: u64 = 512 * 1024 * 1024;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct UpdateManifest {
    schema_version: u32,
    version: String,
    published_at: i64,
    notes_url: String,
    platforms: BTreeMap<String, UpdateAssetManifest>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct UpdateAssetManifest {
    url: String,
    size: u64,
    sha256: String,
    signature: String,
}

pub(super) fn evaluate_manifest(
    bytes: &[u8],
    current_version: &str,
    platform: StudioUpdatePlatform,
) -> Result<StudioUpdateCheck, StudioUpdateError> {
    let manifest: UpdateManifest = serde_json::from_slice(bytes)
        .map_err(|error| invalid_manifest(format!("invalid update manifest JSON: {error}")))?;
    if manifest.schema_version != 2 {
        return Err(invalid_manifest(format!(
            "unsupported update schema {}",
            manifest.schema_version
        )));
    }
    let current = stable_version(current_version, "current application version")?;
    let available = stable_version(&manifest.version, "manifest version")?;
    if available <= current {
        return Ok(StudioUpdateCheck::UpToDate);
    }
    validate_notes_url(&manifest.notes_url, &available)?;
    let asset = manifest.platforms.get(platform.key()).ok_or_else(|| {
        StudioUpdateError::new(
            StudioUpdateErrorCode::UnsupportedPlatform,
            format!("release {} has no {} asset", available, platform.key()),
        )
    })?;
    let asset = validate_asset(asset, &available, platform)?;
    Ok(StudioUpdateCheck::Available(StudioUpdate {
        platform,
        version: available.to_string(),
        published_at: manifest.published_at,
        notes_url: manifest.notes_url,
        installer: asset,
    }))
}

pub(super) fn validate_update(update: &StudioUpdate) -> Result<(), StudioUpdateError> {
    let version = stable_version(&update.version, "update version")?;
    validate_notes_url(&update.notes_url, &version)?;
    validate_asset(
        &UpdateAssetManifest {
            url: update.installer.url.clone(),
            size: update.installer.size,
            sha256: update.installer.sha256.clone(),
            signature: update.installer.signature.clone(),
        },
        &version,
        update.platform,
    )?;
    Ok(())
}

pub(super) fn validate_redirect_url(url: &Url) -> Result<(), StudioUpdateError> {
    validate_https_basics(url, /*allow_query*/ true)?;
    let host = url.host_str().unwrap_or_default();
    let allowed = host.eq_ignore_ascii_case("github.com")
        || host.eq_ignore_ascii_case("objects.githubusercontent.com")
        || host.eq_ignore_ascii_case("release-assets.githubusercontent.com");
    if !allowed {
        return Err(invalid_manifest(format!(
            "update redirect host is not allowed: {host}"
        )));
    }
    Ok(())
}

fn validate_asset(
    asset: &UpdateAssetManifest,
    version: &Version,
    platform: StudioUpdatePlatform,
) -> Result<StudioUpdateAsset, StudioUpdateError> {
    if asset.size == 0 || asset.size > MAX_INSTALLER_BYTES {
        return Err(StudioUpdateError::new(
            StudioUpdateErrorCode::DownloadTooLarge,
            format!("installer size {} is outside the allowed range", asset.size),
        ));
    }
    if asset.sha256.len() != 64 || !asset.sha256.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err(invalid_manifest(
            "installer SHA-256 is not 64 hexadecimal characters",
        ));
    }
    let expected_name = platform.asset_name(&version.to_string());
    let expected_path = format!("/ZR233/anywork/releases/download/v{version}/{expected_name}");
    let url = parse_stable_url(&asset.url)?;
    if url.host_str() != Some("github.com") || url.path() != expected_path {
        return Err(invalid_manifest(
            "installer URL does not match version, tag, and asset name",
        ));
    }
    let signature = parse_stable_url(&asset.signature)?;
    if signature.host_str() != Some("github.com")
        || signature.path() != format!("{expected_path}.minisig")
    {
        return Err(invalid_manifest(
            "signature URL does not match installer URL",
        ));
    }
    Ok(StudioUpdateAsset {
        url: url.into(),
        size: asset.size,
        sha256: asset.sha256.to_ascii_lowercase(),
        signature: signature.into(),
    })
}

fn validate_notes_url(raw: &str, version: &Version) -> Result<(), StudioUpdateError> {
    let url = parse_stable_url(raw)?;
    let expected = format!("/ZR233/anywork/releases/tag/v{version}");
    if url.host_str() != Some("github.com") || url.path() != expected {
        return Err(invalid_manifest(
            "release notes URL does not match manifest version",
        ));
    }
    Ok(())
}

fn parse_stable_url(raw: &str) -> Result<Url, StudioUpdateError> {
    let url = Url::parse(raw)
        .map_err(|error| invalid_manifest(format!("invalid update URL: {error}")))?;
    validate_https_basics(&url, /*allow_query*/ false)?;
    Ok(url)
}

fn validate_https_basics(url: &Url, allow_query: bool) -> Result<(), StudioUpdateError> {
    if url.scheme() != "https"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.port().is_some()
        || url.fragment().is_some()
        || (!allow_query && url.query().is_some())
        || url.host_str().is_none()
    {
        return Err(invalid_manifest(
            "update URL violates the HTTPS origin policy",
        ));
    }
    Ok(())
}

fn stable_version(raw: &str, label: &str) -> Result<Version, StudioUpdateError> {
    let version = Version::parse(raw)
        .map_err(|error| invalid_manifest(format!("invalid {label}: {error}")))?;
    if !version.pre.is_empty() || !version.build.is_empty() || raw.starts_with('v') {
        return Err(invalid_manifest(format!("{label} must be stable SemVer")));
    }
    Ok(version)
}

fn invalid_manifest(message: impl Into<String>) -> StudioUpdateError {
    StudioUpdateError::new(StudioUpdateErrorCode::InvalidManifest, message)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn manifest() -> serde_json::Value {
        let update = crate::test_support::update(b"test");
        serde_json::json!({
            "schemaVersion": 2,
            "version": update.version,
            "publishedAt": update.published_at,
            "notesUrl": update.notes_url,
            "platforms": {"windows-x86_64": update.installer},
        })
    }

    #[test]
    fn stable_manifest_admits_only_a_newer_version_and_validates_its_assets() {
        let bytes = serde_json::to_vec(&manifest()).unwrap();
        assert_eq!(
            evaluate_manifest(&bytes, "1.0.0", StudioUpdatePlatform::WindowsX86_64).unwrap(),
            StudioUpdateCheck::UpToDate
        );
        assert_eq!(
            evaluate_manifest(&bytes, "2.0.0", StudioUpdatePlatform::WindowsX86_64).unwrap(),
            StudioUpdateCheck::UpToDate
        );
        assert_eq!(
            evaluate_manifest(&bytes, "0.9.0", StudioUpdatePlatform::WindowsX86_64).unwrap(),
            StudioUpdateCheck::Available(crate::test_support::update(b"test"))
        );
        for (pointer, value, expected) in [
            (
                "/schemaVersion",
                serde_json::json!(1),
                StudioUpdateErrorCode::InvalidManifest,
            ),
            (
                "/version",
                serde_json::json!("1.0.0-rc.1"),
                StudioUpdateErrorCode::InvalidManifest,
            ),
            (
                "/platforms/windows-x86_64/size",
                serde_json::json!(0),
                StudioUpdateErrorCode::DownloadTooLarge,
            ),
            (
                "/platforms/windows-x86_64/sha256",
                serde_json::json!("bad"),
                StudioUpdateErrorCode::InvalidManifest,
            ),
            (
                "/platforms/windows-x86_64/url",
                serde_json::json!("https://example.com/installer.exe"),
                StudioUpdateErrorCode::InvalidManifest,
            ),
            (
                "/platforms/windows-x86_64/signature",
                serde_json::json!("https://github.com/wrong.minisig"),
                StudioUpdateErrorCode::InvalidManifest,
            ),
            (
                "/notesUrl",
                serde_json::json!("https://github.com/ZR233/anywork/releases/tag/v2.0.0"),
                StudioUpdateErrorCode::InvalidManifest,
            ),
        ] {
            let mut input = manifest();
            *input.pointer_mut(pointer).unwrap() = value;
            assert_eq!(
                evaluate_manifest(
                    &serde_json::to_vec(&input).unwrap(),
                    "0.9.0",
                    StudioUpdatePlatform::WindowsX86_64
                )
                .unwrap_err()
                .code(),
                expected,
                "{pointer}"
            );
        }
    }

    #[test]
    fn redirect_policy_allows_signed_cdn_queries_without_allowing_other_origins() {
        assert!(
            validate_redirect_url(
                &Url::parse("https://release-assets.githubusercontent.com/asset?token=temporary")
                    .unwrap()
            )
            .is_ok()
        );
        for url in [
            "http://github.com/asset",
            "https://example.com/asset",
            "https://user:secret@github.com/asset",
            "https://github.com/asset#fragment",
            "https://github.com:444/asset",
        ] {
            assert_eq!(
                validate_redirect_url(&Url::parse(url).unwrap())
                    .unwrap_err()
                    .code(),
                StudioUpdateErrorCode::InvalidManifest
            );
        }
    }
}

#[cfg(test)]
mod platform_tests {
    use super::*;

    #[test]
    fn each_platform_selects_and_validates_only_its_own_asset() {
        let windows = crate::test_support::update(b"test");
        let mut linux = windows.clone();
        linux.platform = StudioUpdatePlatform::LinuxX86_64;
        linux.installer.url = format!(
            "https://github.com/ZR233/anywork/releases/download/v1.0.0/{}",
            linux.platform.asset_name("1.0.0")
        );
        linux.installer.signature = format!("{}.minisig", linux.installer.url);
        let manifest = serde_json::json!({"schemaVersion": 2, "version": "1.0.0", "publishedAt": 1,
            "notesUrl": windows.notes_url,
            "platforms": {"windows-x86_64": windows.installer, "linux-x86_64": linux.installer}});
        let bytes = serde_json::to_vec(&manifest).unwrap();
        for update in [windows, linux] {
            assert_eq!(
                evaluate_manifest(&bytes, "0.9.0", update.platform).unwrap(),
                StudioUpdateCheck::Available(update)
            );
        }
        let mut missing = manifest.clone();
        missing["platforms"]
            .as_object_mut()
            .unwrap()
            .remove("linux-x86_64");
        assert_eq!(
            evaluate_manifest(
                &serde_json::to_vec(&missing).unwrap(),
                "0.9.0",
                StudioUpdatePlatform::LinuxX86_64
            )
            .unwrap_err()
            .code(),
            StudioUpdateErrorCode::UnsupportedPlatform
        );
        let mut mismatched = manifest;
        mismatched["platforms"]["linux-x86_64"] = mismatched["platforms"]["windows-x86_64"].clone();
        assert_eq!(
            evaluate_manifest(
                &serde_json::to_vec(&mismatched).unwrap(),
                "0.9.0",
                StudioUpdatePlatform::LinuxX86_64
            )
            .unwrap_err()
            .code(),
            StudioUpdateErrorCode::InvalidManifest
        );
    }
}
