//! Isolated TLS material for the acceptance proxy.
//!
//! Certificates are produced by the standard OpenSSL tool (no hand-written X.509
//! or TLS code): one throwaway CA plus one leaf valid for the single fixed host
//! the product is allowed to contact. Only the leaf certificate and key are
//! loaded into the proxy; the CA PEM is exported so the acceptance harness can
//! point the isolated child process at it. Nothing here touches the system trust
//! store, hosts file or the operator's environment.
//!
//! `openssl` runs with `current_dir(directory)` and only receives the fixed
//! basenames (`ca.key`, `ca.pem`, `leaf.csr`, …). The state directory of a real
//! acceptance lifecycle can be far longer than 360 bytes, and OpenSSL's own
//! `-CAcreateserial` path handling fails with `File name too long` on such
//! absolute arguments; the relative names keep every artifact inside the
//! requested directory while the tool never sees the long prefix.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, ensure};

/// Throwaway CA private key inside the lifecycle directory.
const CA_KEY: &str = "ca.key";
/// Throwaway CA certificate inside the lifecycle directory.
const CA_PEM: &str = "ca.pem";
/// Leaf private key inside the lifecycle directory.
const LEAF_KEY: &str = "leaf.key";
/// Leaf certificate request inside the lifecycle directory.
const LEAF_CSR: &str = "leaf.csr";
/// Signed leaf certificate inside the lifecycle directory.
const LEAF_PEM: &str = "leaf.pem";
/// DER-encoded leaf certificate read by the proxy.
const LEAF_DER: &str = "leaf.der";
/// PKCS#8 DER leaf private key read by the proxy.
const KEY_DER: &str = "leaf.key.der";
/// OpenSSL extension file for the leaf certificate.
const EXTENSIONS: &str = "leaf.ext";

/// Official distribution host.
pub const DISTRIBUTION_HOST: &str = "dl.google.com";

/// Resulting material for one fixture lifecycle.
pub struct Certs {
    pub ca_pem: PathBuf,
    pub leaf_der: Vec<u8>,
    pub key_der: Vec<u8>,
}

/// Generates the throwaway CA and leaf inside `directory`.
pub fn generate(directory: &Path) -> Result<Certs> {
    fs::create_dir_all(directory).with_context(|| {
        format!(
            "failed to create certificate directory: {}",
            directory.display()
        )
    })?;
    let ca_pem = directory.join(CA_PEM);
    let leaf_der = directory.join(LEAF_DER);
    let key_der = directory.join(KEY_DER);
    fs::write(
        directory.join(EXTENSIONS),
        "basicConstraints=critical,CA:FALSE\n\
         keyUsage=critical,digitalSignature\n\
         extendedKeyUsage=serverAuth\n\
         subjectAltName=DNS:dl.google.com\n",
    )
    .context("failed to write the leaf certificate extensions")?;

    openssl(
        directory,
        &[
            "req",
            "-x509",
            "-newkey",
            "ec",
            "-pkeyopt",
            "ec_paramgen_curve:P-256",
            "-nodes",
            "-days",
            "2",
            "-subj",
            "/CN=anywork-acp-install-fixture-ca",
            "-addext",
            "basicConstraints=critical,CA:TRUE",
            "-addext",
            "keyUsage=critical,keyCertSign,cRLSign",
            "-keyout",
            CA_KEY,
            "-out",
            CA_PEM,
        ],
    )?;
    openssl(
        directory,
        &[
            "req",
            "-new",
            "-newkey",
            "ec",
            "-pkeyopt",
            "ec_paramgen_curve:P-256",
            "-nodes",
            "-subj",
            "/CN=dl.google.com",
            "-keyout",
            LEAF_KEY,
            "-out",
            LEAF_CSR,
        ],
    )?;
    openssl(
        directory,
        &[
            "x509",
            "-req",
            "-in",
            LEAF_CSR,
            "-CA",
            CA_PEM,
            "-CAkey",
            CA_KEY,
            "-CAcreateserial",
            "-days",
            "2",
            "-sha256",
            "-extfile",
            EXTENSIONS,
            "-out",
            LEAF_PEM,
        ],
    )?;
    openssl(
        directory,
        &["x509", "-in", LEAF_PEM, "-outform", "DER", "-out", LEAF_DER],
    )?;
    openssl(
        directory,
        &[
            "pkcs8", "-topk8", "-nocrypt", "-in", LEAF_KEY, "-outform", "DER", "-out", KEY_DER,
        ],
    )?;
    ensure!(
        ca_pem.is_file() && leaf_der.is_file() && key_der.is_file(),
        "the standard OpenSSL tool did not produce the fixture TLS material"
    );
    Ok(Certs {
        ca_pem,
        leaf_der: fs::read(&leaf_der).context("failed to read the leaf certificate")?,
        key_der: fs::read(&key_der).context("failed to read the leaf private key")?,
    })
}

fn openssl(directory: &Path, args: &[&str]) -> Result<()> {
    let output = Command::new("openssl")
        .current_dir(directory)
        .args(args)
        .output()
        .context("the standard `openssl` tool is required to build the fixture TLS material")?;
    ensure!(
        output.status.success(),
        "`openssl {}` failed with {}: {}",
        args.join(" "),
        output.status,
        String::from_utf8_lossy(&output.stderr).trim()
    );
    Ok(())
}
