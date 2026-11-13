use super::*;

fn manifest() -> serde_json::Value {
    let update = crate::test_support::update(b"test");
    serde_json::json!({
        "schemaVersion": 1,
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
        evaluate_manifest(&bytes, "1.0.0").unwrap(),
        StudioUpdateCheck::UpToDate
    );
    assert_eq!(
        evaluate_manifest(&bytes, "2.0.0").unwrap(),
        StudioUpdateCheck::UpToDate
    );
    assert_eq!(
        evaluate_manifest(&bytes, "0.9.0").unwrap(),
        StudioUpdateCheck::Available(crate::test_support::update(b"test"))
    );
    for (pointer, value, expected) in [
        (
            "/schemaVersion",
            serde_json::json!(2),
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
            serde_json::json!("https://github.com/ZR233/pure-lang/releases/tag/v2.0.0"),
            StudioUpdateErrorCode::InvalidManifest,
        ),
    ] {
        let mut input = manifest();
        *input.pointer_mut(pointer).unwrap() = value;
        assert_eq!(
            evaluate_manifest(&serde_json::to_vec(&input).unwrap(), "0.9.0")
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
