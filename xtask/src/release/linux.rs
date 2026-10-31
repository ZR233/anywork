//! Debian packaging consumes only prebuilt inputs; dpkg owns archive and dependency semantics.

use super::manifest::sha256_file;
use anyhow::{Context, Result, bail, ensure};
use semver::Version;
use std::collections::BTreeSet;
use std::fs::{self, File};
use std::io::Read;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::process::Command;

const DESKTOP: &str = "share/applications/io.github.zr233.anywork.desktop";
const ICON: &str = "share/icons/hicolor/1024x1024/apps/io.github.zr233.anywork.png";
const LIBRARIES: [&str; 3] = [
    "lib/libflutter_linux_gtk.so",
    "lib/libpl_studio_bridge.so",
    "lib/libapp.so",
];
const HELPERS: [&str; 2] = ["x86_64-unknown-linux-musl", "aarch64-unknown-linux-musl"];

fn asset_name(version: &Version) -> String {
    format!("anywork-{version}-linux-x86_64.deb")
}

fn ensure_platform() -> Result<()> {
    ensure!(
        cfg!(target_arch = "x86_64"),
        "Linux release-gui supports x86_64 only"
    );
    Ok(())
}

pub(super) fn stage(
    workspace: &Path,
    release_dir: &Path,
    version: &Version,
    bundle: &Path,
) -> Result<()> {
    ensure_platform()?;
    ensure!(
        !release_dir.try_exists()? && fs::symlink_metadata(release_dir).is_err(),
        "release staging directory already exists; refusing to overwrite {}",
        release_dir.display()
    );
    validate_bundle(bundle)?;
    // tempfile and dpkg-deb both honor TMPDIR; nothing is installed in user directories.
    let temp = tempfile::Builder::new().prefix("anywork-deb-").tempdir()?;
    let package = temp.path().join("debian/anywork");
    let app = package.join("opt/anywork");
    fs::create_dir_all(&app)?;
    checked(
        Command::new("cp")
            .args(["--archive", "--no-preserve=ownership", "--"])
            .arg(bundle.join("."))
            .arg(&app),
    )?;
    for (source, name) in [
        (workspace.join("LICENSE"), "LICENSE"),
        (
            workspace.join("code/pl-studio-runtime/THIRD_PARTY_NOTICES.md"),
            "THIRD_PARTY_NOTICES.md",
        ),
    ] {
        copy_file(&source, &app.join(name))?;
        copy_file(&source, &package.join("usr/share/doc/anywork").join(name))?;
    }
    for resource in [DESKTOP, ICON] {
        copy_file(&app.join(resource), &package.join("usr").join(resource))?;
    }
    validate_bundle(&app)?;
    fs::create_dir_all(package.join("usr/bin"))?;
    symlink("/opt/anywork/anywork", package.join("usr/bin/anywork"))?;
    fs::create_dir_all(package.join("DEBIAN"))?;
    // dpkg-shlibdeps identifies private libraries belonging to this same package
    // using DEBIAN/control, rather than requiring fabricated shlibs metadata.
    fs::write(package.join("DEBIAN/control"), control(version, None))?;
    fs::write(
        temp.path().join("debian/control"),
        "Source: anywork\nSection: utils\nPriority: optional\nMaintainer: anywork maintainers <maintainers@anywork.invalid>\n\nPackage: anywork\nArchitecture: amd64\nDescription: anywork desktop application\n",
    )?;
    let dynamic = inspect_elfs(&app)?;
    let depends = dependencies(temp.path(), &app, &dynamic)?;
    fs::write(
        package.join("DEBIAN/control"),
        control(version, Some(&depends)),
    )?;
    let name = asset_name(version);
    let deb = temp.path().join(&name);
    checked(
        Command::new("dpkg-deb")
            .args(["--root-owner-group", "--build"])
            .arg(&package)
            .arg(&deb),
    )?;
    let sum = checksum(&deb, &name)?;
    // Reserve the final directory atomically only after all packaging succeeds.
    fs::create_dir_all(
        release_dir
            .parent()
            .context("release directory has no parent")?,
    )?;
    fs::create_dir(release_dir)
        .with_context(|| format!("refusing to overwrite staging {}", release_dir.display()))?;
    fs::copy(&deb, release_dir.join(&name))?;
    fs::write(release_dir.join(format!("{name}.sha256")), sum)?;
    println!("Staged Linux release: {}", release_dir.display());
    Ok(())
}

fn control(version: &Version, depends: Option<&str>) -> String {
    // libepoxy loads these GLVND APIs with dlopen; they are absent from the
    // payload's DT_NEEDED tables and cannot be inferred by dpkg-shlibdeps.
    let depends = depends
        .filter(|value| !value.is_empty())
        .map(|value| format!("{value}, "))
        .unwrap_or_default();
    format!(
        "Package: anywork\nVersion: {version}\nArchitecture: amd64\nSection: utils\nPriority: optional\nMaintainer: anywork maintainers <maintainers@anywork.invalid>\nDepends: {depends}libegl1, libgl1, libgles2\nDescription: anywork desktop application\n"
    )
}

fn copy_file(source: &Path, destination: &Path) -> Result<()> {
    fs::create_dir_all(destination.parent().context("file has no parent")?)?;
    fs::copy(source, destination)
        .with_context(|| format!("copy {} to {}", source.display(), destination.display()))?;
    Ok(())
}

fn checksum(deb: &Path, name: &str) -> Result<String> {
    Ok(format!("{}  {name}\n", sha256_file(deb)?))
}

pub(super) fn verify(release_dir: &Path, version: &Version) -> Result<()> {
    ensure_platform()?;
    let name = asset_name(version);
    let expected = BTreeSet::from([name.clone(), format!("{name}.sha256")]);
    let mut actual = BTreeSet::new();
    for entry in fs::read_dir(release_dir)? {
        let entry = entry?;
        ensure!(
            entry.file_type()?.is_file(),
            "release contains non-file entry"
        );
        actual.insert(
            entry
                .file_name()
                .into_string()
                .map_err(|_| anyhow::anyhow!("release contains a non-UTF-8 filename"))?,
        );
    }
    ensure!(
        actual == expected,
        "Linux release file set mismatch: expected {expected:?}, got {actual:?}"
    );
    let deb = release_dir.join(&name);
    ensure!(
        fs::read_to_string(release_dir.join(format!("{name}.sha256")))? == checksum(&deb, &name)?,
        "Linux release checksum mismatch"
    );
    for (field, expected) in [
        ("Package", "anywork".to_owned()),
        ("Version", version.to_string()),
        ("Architecture", "amd64".to_owned()),
    ] {
        let actual = checked(Command::new("dpkg-deb").arg("--field").arg(&deb).arg(field))?;
        ensure!(
            actual.trim() == expected,
            "Debian {field} mismatch: {actual:?}"
        );
    }
    // dpkg-deb's untrusted-archive extraction boundary handles traversal safely.
    // Do not run maintainer scripts, the application or its desktop installer.
    let temp = tempfile::Builder::new()
        .prefix("anywork-deb-verify-")
        .tempdir()?;
    checked(
        Command::new("dpkg-deb")
            .arg("--extract")
            .arg(&deb)
            .arg(temp.path()),
    )?;
    checked_tree(temp.path(), Some(&temp.path().join("usr/bin/anywork")))?;
    let app = temp.path().join("opt/anywork");
    validate_bundle(&app)?;
    inspect_elfs(&app)?;
    ensure!(
        fs::read_link(temp.path().join("usr/bin/anywork"))? == Path::new("/opt/anywork/anywork"),
        "invalid /usr/bin/anywork symlink"
    );
    for resource in [DESKTOP, ICON] {
        let installed = temp.path().join("usr").join(resource);
        require_file(&installed)?;
        ensure!(
            fs::read(installed)? == fs::read(app.join(resource))?,
            "installed resource differs: {resource}"
        );
    }
    for name in ["LICENSE", "THIRD_PARTY_NOTICES.md"] {
        require_file(&app.join(name))?;
        let doc = temp.path().join("usr/share/doc/anywork").join(name);
        require_file(&doc)?;
        ensure!(
            fs::read(doc)? == fs::read(app.join(name))?,
            "license differs: {name}"
        );
    }
    println!("Verified Linux release: {}", release_dir.display());
    Ok(())
}

fn require_file(path: &Path) -> Result<()> {
    ensure!(
        path.is_file() && fs::metadata(path)?.len() > 0,
        "missing or empty required input: {}",
        path.display()
    );
    Ok(())
}

fn validate_bundle(bundle: &Path) -> Result<()> {
    ensure!(bundle.is_dir(), "bundle not found: {}", bundle.display());
    checked_tree(bundle, None)?;
    for required in ["anywork", "data/icudtl.dat", DESKTOP, ICON]
        .into_iter()
        .chain(LIBRARIES)
    {
        require_file(&bundle.join(required))?;
    }
    let assets = bundle.join("data/flutter_assets");
    ensure!(
        assets.is_dir() && fs::read_dir(&assets)?.next().is_some(),
        "missing or empty flutter_assets"
    );
    for target in HELPERS {
        for file in ["pl-remote-helper.zst", "pl-remote-helper.metadata.json"] {
            require_file(&bundle.join("data/remote-helper").join(target).join(file))?;
        }
    }
    ensure!(
        fs::metadata(bundle.join("anywork"))?.permissions().mode() & 0o111 != 0,
        "anywork must be executable"
    );
    for required in ["anywork"].into_iter().chain(LIBRARIES) {
        ensure!(
            is_elf(&bundle.join(required))?,
            "required ELF missing: {required}"
        );
    }
    Ok(())
}

/// Do not follow directory links or allow a payload link to escape its tree.
/// The sole absolute link is the fixed system command entry, checked separately.
fn checked_tree(root: &Path, command_link: Option<&Path>) -> Result<Vec<PathBuf>> {
    fn visit(
        root: &Path,
        dir: &Path,
        command_link: Option<&Path>,
        files: &mut Vec<PathBuf>,
    ) -> Result<()> {
        for entry in fs::read_dir(dir)? {
            let entry = entry?;
            let path = entry.path();
            let kind = entry.file_type()?;
            if kind.is_symlink() {
                if Some(path.as_path()) == command_link {
                    ensure!(
                        fs::read_link(&path)? == Path::new("/opt/anywork/anywork"),
                        "invalid command link"
                    );
                    continue;
                }
                let target = fs::read_link(&path)?;
                ensure!(
                    !target.is_absolute(),
                    "absolute payload symlink: {}",
                    path.display()
                );
                let resolved = path.canonicalize()?;
                ensure!(
                    resolved.starts_with(root) && resolved.is_file(),
                    "escaping or directory payload symlink: {}",
                    path.display()
                );
                files.push(path);
            } else if kind.is_dir() {
                visit(root, &path, command_link, files)?;
            } else {
                ensure!(kind.is_file(), "special payload file: {}", path.display());
                files.push(path);
            }
        }
        Ok(())
    }
    let root = root.canonicalize()?;
    let command_link = command_link.map(Path::to_path_buf);
    let mut files = Vec::new();
    visit(&root, &root, command_link.as_deref(), &mut files)?;
    files.sort();
    Ok(files)
}

fn is_elf(path: &Path) -> Result<bool> {
    let mut magic = [0; 4];
    let count = File::open(path)?.read(&mut magic)?;
    Ok(count == 4 && magic == *b"\x7fELF")
}

fn inspect_elfs(app: &Path) -> Result<Vec<PathBuf>> {
    let mut dynamic = Vec::new();
    for file in checked_tree(app, None)? {
        if !is_elf(&file)? {
            continue;
        }
        let header = checked(
            Command::new("readelf")
                .args(["--wide", "--file-header"])
                .arg(&file),
        )?;
        ensure!(
            header.lines().any(|line| line
                .trim()
                .strip_prefix("Class:")
                .is_some_and(|value| value.trim() == "ELF64"))
                && header.lines().any(|line| line
                    .trim()
                    .strip_prefix("Machine:")
                    .is_some_and(|value| value.trim() == "Advanced Micro Devices X86-64")),
            "ELF must be 64-bit x86_64: {}",
            file.display()
        );
        let elf_type = header
            .lines()
            .find_map(|line| line.trim().strip_prefix("Type:"))
            .and_then(|value| value.split_whitespace().next())
            .context("ELF header has no type")?;
        ensure!(
            matches!(elf_type, "EXEC" | "DYN"),
            "ELF payload is not a runtime executable/library: {}",
            file.display()
        );
        if LIBRARIES.iter().any(|name| file == app.join(name)) {
            ensure!(
                elf_type == "DYN",
                "required library is not ET_DYN: {}",
                file.display()
            );
        }
        let versions = checked(
            Command::new("readelf")
                .args(["--wide", "--version-info"])
                .arg(&file),
        )?;
        println!("ELF version requirements [{}]:\n{versions}", file.display());
        // Only the version-needs section describes imports, not exported definitions.
        if let Some((_, needs)) = versions.split_once("Version needs section") {
            for line in needs.lines() {
                if let Some((_, name)) = line.split_once("Name: GLIBC_") {
                    let raw = name
                        .split_whitespace()
                        .next()
                        .context("missing GLIBC version")?;
                    let version = raw
                        .split('.')
                        .map(str::parse::<u32>)
                        .collect::<std::result::Result<Vec<_>, _>>()
                        .with_context(|| {
                            format!("unsupported GLIBC requirement {raw} in {}", file.display())
                        })?;
                    ensure!(
                        version.as_slice() <= [2, 35].as_slice(),
                        "GLIBC_{raw} exceeds 2.35: {}",
                        file.display()
                    );
                }
            }
        }
        let info = checked(
            Command::new("readelf")
                .args(["--wide", "--dynamic"])
                .arg(&file),
        )?;
        if info.contains("Dynamic section at") {
            dynamic.push(file);
        }
    }
    ensure!(!dynamic.is_empty(), "bundle has no dynamic ELF payload");
    Ok(dynamic)
}

fn dependencies(work: &Path, app: &Path, dynamic: &[PathBuf]) -> Result<String> {
    let mut command = Command::new("dpkg-shlibdeps");
    command
        .current_dir(work)
        .arg("-O")
        .env_remove("LD_LIBRARY_PATH");
    let mut directories = BTreeSet::from([app.join("lib")]);
    for file in dynamic {
        directories.insert(file.parent().context("ELF has no directory")?.to_path_buf());
    }
    for dir in directories {
        command.arg(format!("-l{}", dir.display()));
    }
    for file in dynamic {
        command.arg(format!("-e{}", file.display()));
    }
    let output = checked_output(&mut command)?;
    // dpkg treats missing *unversioned* SONAMEs as warnings (plugins may do
    // their own resolution). Our complete runtime bundle cannot tolerate
    // that exception. Promote only this diagnostic, not ordinary dpkg warnings.
    let diagnostic = String::from_utf8_lossy(&output.stderr);
    ensure!(
        !diagnostic.contains("dpkg-shlibdeps: warning: cannot find library "),
        "dpkg-shlibdeps unresolved runtime library:\n{diagnostic}"
    );
    let output = String::from_utf8(output.stdout)?;
    let depends = output
        .lines()
        .find_map(|line| line.strip_prefix("shlibs:Depends="))
        .context("dpkg-shlibdeps did not produce shlibs:Depends")?;
    ensure!(!depends.contains(['\r', '\n']), "invalid dependency output");
    Ok(depends.to_owned())
}

fn checked(command: &mut Command) -> Result<String> {
    let output = checked_output(command)?;
    String::from_utf8(output.stdout).with_context(|| format!("non-UTF-8 output from {command:?}"))
}

fn checked_output(command: &mut Command) -> Result<std::process::Output> {
    let display = format!("{command:?}");
    let output = command
        .env("LC_ALL", "C")
        .output()
        .with_context(|| format!("failed to execute {display}"))?;
    if !output.status.success() {
        bail!(
            "{display} failed ({}):\n{}\n{}",
            output.status,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    if !output.stderr.is_empty() {
        eprint!("{}", String::from_utf8_lossy(&output.stderr));
    }
    Ok(output)
}

#[cfg(all(test, target_arch = "x86_64"))]
mod tests {
    use super::*;

    struct Fixture {
        temp: tempfile::TempDir,
        bundle: PathBuf,
        release: PathBuf,
        version: Version,
    }

    impl Fixture {
        fn new() -> Result<Self> {
            let temp = tempfile::Builder::new()
                .prefix("anywork-deb-test-")
                .tempdir()?;
            let root = temp.path();
            let bundle = root.join("bundle");
            fs::create_dir_all(bundle.join("lib"))?;
            fs::write(root.join("LICENSE"), "fixture license\n")?;
            let notice = root.join("code/pl-studio-runtime/THIRD_PARTY_NOTICES.md");
            fs::create_dir_all(notice.parent().unwrap())?;
            fs::write(notice, "fixture third-party notices\n")?;
            // Real libc imports and SONAME-bearing private libraries exercise
            // dpkg's same-package handling, not a mock dependency resolver.
            fs::write(
                root.join("library.c"),
                "#include <stdio.h>\nint fixture(void) { return puts(\"fixture\"); }\n",
            )?;
            for library in LIBRARIES {
                let path = bundle.join(library);
                let soname = if library == "lib/libpl_studio_bridge.so" {
                    "libpl_studio_bridge.so.1"
                } else {
                    path.file_name().unwrap().to_str().unwrap()
                };
                checked(
                    Command::new("cc")
                        .args(["-shared", "-fPIC"])
                        .arg(root.join("library.c"))
                        .arg(format!("-Wl,-soname,{soname}"))
                        .arg("-o")
                        .arg(path),
                )?;
            }
            symlink(
                "libpl_studio_bridge.so",
                bundle.join("lib/libpl_studio_bridge.so.1"),
            )?;
            fs::write(
                root.join("main.c"),
                "extern int fixture(void);\nint main(void) { return fixture(); }\n",
            )?;
            checked(
                Command::new("cc")
                    .arg(root.join("main.c"))
                    .arg("-L")
                    .arg(bundle.join("lib"))
                    .args(["-lpl_studio_bridge", "-Wl,-rpath,$ORIGIN/lib", "-o"])
                    .arg(bundle.join("anywork")),
            )?;
            for (name, data) in [
                ("data/icudtl.dat", "ICU fixture"),
                ("data/flutter_assets/AssetManifest.bin", "asset fixture"),
                (DESKTOP, "[Desktop Entry]\nType=Application\nExec=anywork\n"),
                (ICON, "icon fixture"),
                // Preserved, never executed; a packaging implementation which
                // runs the bundle's installer will fail this fixture.
                ("install-desktop-entry.py", "#!/bin/sh\nexit 99\n"),
                ("lib/native_assets/extra.dat", "native asset fixture"),
            ] {
                let file = bundle.join(name);
                fs::create_dir_all(file.parent().unwrap())?;
                fs::write(file, data)?;
            }
            fs::set_permissions(
                bundle.join("install-desktop-entry.py"),
                fs::Permissions::from_mode(0o755),
            )?;
            for target in HELPERS {
                let dir = bundle.join("data/remote-helper").join(target);
                fs::create_dir_all(&dir)?;
                fs::write(
                    dir.join("pl-remote-helper.zst"),
                    b"compressed helper fixture",
                )?;
                fs::write(dir.join("pl-remote-helper.metadata.json"), "{}\n")?;
            }
            // Retain an internal library symlink rather than flattening it.
            symlink("libpl_studio_bridge.so", bundle.join("lib/bridge-alias.so"))?;
            let release = root.join("release");
            Ok(Self {
                temp,
                bundle,
                release,
                version: Version::new(1, 2, 3),
            })
        }

        fn stage(&self) -> Result<()> {
            stage(self.temp.path(), &self.release, &self.version, &self.bundle)
        }

        fn deb(&self) -> PathBuf {
            self.release.join(asset_name(&self.version))
        }

        fn update_checksum(&self) -> Result<()> {
            let name = asset_name(&self.version);
            fs::write(
                self.release.join(format!("{name}.sha256")),
                checksum(&self.deb(), &name)?,
            )?;
            Ok(())
        }
    }

    #[test]
    fn release_linux_stage_inspect_extract_verify_and_tampering() -> Result<()> {
        let fixture = Fixture::new()?;
        fixture.stage()?;
        verify(&fixture.release, &fixture.version)?;
        let fields = checked(Command::new("dpkg-deb").arg("--field").arg(fixture.deb()))?;
        assert!(fields.contains("Depends: libc6"), "{fields}");
        assert!(!fields.contains("Depends: libpl_studio"), "{fields}");
        assert!(
            fixture
                .stage()
                .unwrap_err()
                .to_string()
                .contains("refusing to overwrite")
        );
        let saved = fs::read(fixture.deb())?;
        fs::write(fixture.deb(), b"tampered")?;
        assert!(
            verify(&fixture.release, &fixture.version)
                .unwrap_err()
                .to_string()
                .contains("checksum mismatch")
        );
        fs::write(fixture.deb(), &saved)?;
        fs::create_dir(fixture.release.join("unexpected"))?;
        assert!(verify(&fixture.release, &fixture.version).is_err());
        fs::remove_dir(fixture.release.join("unexpected"))?;

        let unpack = fixture.temp.path().join("unpack");
        checked(
            Command::new("dpkg-deb")
                .arg("--raw-extract")
                .arg(fixture.deb())
                .arg(&unpack),
        )?;
        assert_eq!(
            fs::read_link(unpack.join("usr/bin/anywork"))?,
            Path::new("/opt/anywork/anywork")
        );
        assert_eq!(
            fs::read_link(unpack.join("opt/anywork/lib/bridge-alias.so"))?,
            Path::new("libpl_studio_bridge.so")
        );
        assert_eq!(
            fs::read(unpack.join("opt/anywork/lib/native_assets/extra.dat"))?,
            b"native asset fixture"
        );
        let original = fs::read_to_string(unpack.join("DEBIAN/control"))?;
        for (from, to, expected) in [
            ("Version: 1.2.3", "Version: 9.0.0", "Version mismatch"),
            (
                "Architecture: amd64",
                "Architecture: arm64",
                "Architecture mismatch",
            ),
            ("Package: anywork", "Package: other", "Package mismatch"),
        ] {
            fs::write(unpack.join("DEBIAN/control"), original.replace(from, to))?;
            checked(
                Command::new("dpkg-deb")
                    .args(["--root-owner-group", "--build"])
                    .arg(&unpack)
                    .arg(fixture.deb()),
            )?;
            fixture.update_checksum()?;
            let error = verify(&fixture.release, &fixture.version)
                .unwrap_err()
                .to_string();
            assert!(error.contains(expected), "{error}");
        }
        fs::write(unpack.join("DEBIAN/control"), original)?;
        fs::remove_file(unpack.join("opt/anywork/lib/libapp.so"))?;
        checked(
            Command::new("dpkg-deb")
                .args(["--root-owner-group", "--build"])
                .arg(&unpack)
                .arg(fixture.deb()),
        )?;
        fixture.update_checksum()?;
        let error = verify(&fixture.release, &fixture.version)
            .unwrap_err()
            .to_string();
        assert!(error.contains("libapp.so"), "{error}");
        Ok(())
    }

    #[test]
    fn release_linux_rejects_missing_resources_architecture_abi_and_escaping_links() -> Result<()> {
        let fixture = Fixture::new()?;
        for name in [
            "data/remote-helper/aarch64-unknown-linux-musl/pl-remote-helper.zst",
            "lib/libflutter_linux_gtk.so",
        ] {
            let path = fixture.bundle.join(name);
            let saved = fs::read(&path)?;
            fs::remove_file(&path)?;
            let error = fixture.stage().unwrap_err().to_string();
            assert!(error.contains(name), "{error}");
            assert!(!fixture.release.exists());
            fs::write(path, saved)?;
        }
        let main = fixture.bundle.join("anywork");
        fs::set_permissions(&main, fs::Permissions::from_mode(0o644))?;
        assert!(
            fixture
                .stage()
                .unwrap_err()
                .to_string()
                .contains("executable")
        );
        fs::set_permissions(&main, fs::Permissions::from_mode(0o755))?;
        let library = fixture.bundle.join("lib/libapp.so");
        let saved = fs::read(&library)?;
        let mut wrong = saved.clone();
        wrong[18..20].copy_from_slice(&183_u16.to_le_bytes()); // EM_AARCH64
        fs::write(&library, wrong)?;
        assert!(
            fixture
                .stage()
                .unwrap_err()
                .to_string()
                .contains("64-bit x86_64")
        );
        let mut future = saved.clone();
        let offset = future
            .windows(b"GLIBC_2.2.5".len())
            .position(|part| part == b"GLIBC_2.2.5")
            .context("fixture must import libc")?;
        future[offset..offset + b"GLIBC_9.9.9".len()].copy_from_slice(b"GLIBC_9.9.9");
        fs::write(&library, future)?;
        let error = fixture.stage().unwrap_err().to_string();
        assert!(error.contains("GLIBC_9.9.9 exceeds 2.35"), "{error}");
        fs::write(&library, saved)?;
        symlink(
            fixture.temp.path().join("LICENSE"),
            fixture.bundle.join("outside"),
        )?;
        assert!(
            fixture
                .stage()
                .unwrap_err()
                .to_string()
                .contains("absolute payload symlink")
        );
        assert!(!fixture.release.exists());
        Ok(())
    }

    #[test]
    fn release_linux_all_dynamic_payloads_participate_in_dependency_resolution() -> Result<()> {
        let fixture = Fixture::new()?;
        let root = fixture.temp.path();
        fs::write(
            root.join("missing.c"),
            "int missing_fixture(void) { return 0; }\n",
        )?;
        checked(
            Command::new("cc")
                .args([
                    "-shared",
                    "-fPIC",
                    "-Wl,-soname,libanywork_missing_fixture.so",
                ])
                .arg(root.join("missing.c"))
                .arg("-o")
                .arg(root.join("libanywork_missing_fixture.so")),
        )?;
        fs::write(
            root.join("plugin.c"),
            "extern int missing_fixture(void);\nint plugin(void) { return missing_fixture(); }\n",
        )?;
        // Only this extra plugin, not main, references the absent library.
        checked(
            Command::new("cc")
                .args(["-shared", "-fPIC"])
                .arg(root.join("plugin.c"))
                .arg("-L")
                .arg(root)
                .args(["-lanywork_missing_fixture", "-o"])
                .arg(fixture.bundle.join("lib/plugin.so")),
        )?;
        let error = fixture.stage().unwrap_err().to_string();
        assert!(
            error.contains("dpkg-shlibdeps") && error.contains("libanywork_missing_fixture.so"),
            "{error}"
        );
        assert!(!fixture.release.exists());
        Ok(())
    }
}
