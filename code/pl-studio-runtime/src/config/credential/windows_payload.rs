//! Windows Credential Manager entries are limited to 2560 bytes (UTF-16 for passwords).
//! Larger OAuth records and transaction snapshots use user-bound DPAPI ciphertext.
//! The keyring marker is the only authority: an unreferenced file is never a credential.
use std::path::{Path, PathBuf};

use keyring::{Entry, Error};
use sha2::{Digest, Sha256};
use windows_sys::Win32::Foundation::LocalFree;
use windows_sys::Win32::Security::Cryptography::{
    CRYPT_INTEGER_BLOB, CRYPTPROTECT_UI_FORBIDDEN, CryptProtectData, CryptUnprotectData,
};
use zeroize::Zeroize;

const MARKER: &str = "!anywork:dpapi:v1";
const MAX_PAYLOAD: usize = 16 * 1024 * 1024;
const MAX_CIPHERTEXT: usize = MAX_PAYLOAD + 8192;

fn invalid(stage: &str) -> Error {
    // Deliberately not PlatformFailure: corrupt or inaccessible payloads must not
    // turn a durable OAuth credential into a process-only fallback lease.
    Error::BadStoreFormat(format!("Windows protected credential {stage} failed"))
}

fn directory() -> Result<PathBuf, Error> {
    dirs::data_local_dir()
        .map(|root| {
            root.join(super::CREDENTIAL_SERVICE)
                .join("credential-payloads")
        })
        .ok_or_else(|| invalid("directory lookup"))
}

fn path(root: &Path, account: &str) -> PathBuf {
    root.join(format!(
        "{}.bin",
        hex::encode(Sha256::digest(account.as_bytes()))
    ))
}

pub(super) fn get(entry: &Entry, account: &str) -> Result<String, Error> {
    let value = entry.get_password()?;
    if value != MARKER {
        return Ok(value);
    }
    read_payload(&directory()?, account)
}

fn read_payload(root: &Path, account: &str) -> Result<String, Error> {
    use std::io::Read;
    let mut ciphertext = Vec::new();
    std::fs::File::open(path(root, account))
        .and_then(|file| {
            file.take((MAX_CIPHERTEXT + 1) as u64)
                .read_to_end(&mut ciphertext)
        })
        .map_err(|_| invalid("read"))?;
    if ciphertext.len() > MAX_CIPHERTEXT {
        return Err(invalid("length validation"));
    }
    let plaintext = crypt(&ciphertext, account, false)?;
    String::from_utf8(plaintext).map_err(|_| invalid("UTF-8 validation"))
}

pub(super) fn set(entry: &Entry, account: &str, secret: &str) -> Result<(), Error> {
    let previous = match entry.get_password() {
        Ok(value) => Some(value),
        Err(Error::NoEntry) => None,
        Err(error) => return Err(error),
    };
    // Once referenced, retain the same owned payload path. Atomic replacement is
    // the mutation point; the existing credential transaction owns compensation.
    // A failed first keyring publication retains a deterministic, recoverable
    // owner path rather than leaking an untracked random file.
    if previous.as_deref() == Some(MARKER)
        || secret == MARKER
        || secret.encode_utf16().count() > 2560 / 2
    {
        let root = directory()?;
        write_payload(&root, account, secret)?;
        entry.set_password(MARKER)?;
    } else {
        entry.set_password(secret)?;
    }
    if get(entry, account)? != secret {
        return Err(invalid("write verification"));
    }
    Ok(())
}

fn write_payload(root: &Path, account: &str, secret: &str) -> Result<(), Error> {
    if secret.len() > MAX_PAYLOAD {
        return Err(invalid("length validation"));
    }
    let ciphertext = crypt(secret.as_bytes(), account, true)?;
    std::fs::create_dir_all(root).map_err(|_| invalid("directory creation"))?;
    pl_tool::workspace::write_file_atomically(&path(root, account), &ciphertext)
        .map_err(|_| invalid("atomic write"))
}

pub(super) fn delete(entry: &Entry, account: &str) -> Result<(), Error> {
    match entry.delete_credential() {
        Ok(()) | Err(Error::NoEntry) => {}
        Err(error) => return Err(error),
    }
    match entry.get_password() {
        Err(Error::NoEntry) => {}
        Ok(_) => return Err(invalid("deletion verification")),
        Err(error) => return Err(error),
    }
    // Also handles an interrupted first publication or prior cleanup failure.
    // The caller still knows the account/transaction alias if removal fails.
    match std::fs::remove_file(path(&directory()?, account)) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(invalid("payload deletion")),
    }
}

/// Owns exactly the allocation returned by DPAPI, including on later validation failure.
struct LocalBlob(CRYPT_INTEGER_BLOB);

impl Drop for LocalBlob {
    fn drop(&mut self) {
        if !self.0.pbData.is_null() {
            // SAFETY: DPAPI returned this LocalAlloc allocation. Its cbData bytes
            // remain exclusively owned by this wrapper until the matching LocalFree.
            unsafe {
                std::slice::from_raw_parts_mut(self.0.pbData, self.0.cbData as usize).zeroize();
                LocalFree(self.0.pbData.cast());
            }
        }
    }
}

fn crypt(input: &[u8], account: &str, protect: bool) -> Result<Vec<u8>, Error> {
    if input.is_empty() || input.len() > MAX_CIPHERTEXT {
        return Err(invalid("length validation"));
    }
    let entropy = format!("{}/{account}", super::CREDENTIAL_SERVICE);
    let input_blob = CRYPT_INTEGER_BLOB {
        cbData: u32::try_from(input.len()).map_err(|_| invalid("input length"))?,
        pbData: input.as_ptr().cast_mut(),
    };
    let entropy_blob = CRYPT_INTEGER_BLOB {
        cbData: u32::try_from(entropy.len()).map_err(|_| invalid("owner length"))?,
        pbData: entropy.as_ptr().cast_mut(),
    };
    let mut output = LocalBlob(CRYPT_INTEGER_BLOB {
        cbData: 0,
        pbData: std::ptr::null_mut(),
    });
    // SAFETY: The synchronous DPAPI functions borrow the live input/entropy
    // buffers without modifying them. Sizes are checked u32 values. No pointer
    // escapes, no UI/description is requested, and LocalBlob owns the output.
    let success = unsafe {
        if protect {
            CryptProtectData(
                &input_blob,
                std::ptr::null(),
                &entropy_blob,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output.0,
            )
        } else {
            CryptUnprotectData(
                &input_blob,
                std::ptr::null_mut(),
                &entropy_blob,
                std::ptr::null(),
                std::ptr::null(),
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut output.0,
            )
        }
    };
    if success == 0 || output.0.pbData.is_null() || output.0.cbData as usize > MAX_CIPHERTEXT {
        return Err(invalid(if protect { "encryption" } else { "decryption" }));
    }
    // SAFETY: A successful DPAPI call returned this owned allocation and byte
    // count. Copy before LocalBlob wipes and frees it; do not return a borrowed slice.
    Ok(unsafe { std::slice::from_raw_parts(output.0.pbData, output.0.cbData as usize) }.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keyring_reference_reopens_large_credentials_and_deletion_reclaims_its_payload() {
        let account = format!("account:dpapi-test-{}", uuid::Uuid::new_v4());
        let entry = Entry::new(super::super::CREDENTIAL_SERVICE, &account).unwrap();
        struct Cleanup<'a>(&'a Entry, &'a str);
        impl Drop for Cleanup<'_> {
            fn drop(&mut self) {
                let _ = delete(self.0, self.1);
            }
        }
        let _cleanup = Cleanup(&entry, &account);
        set(&entry, &account, "original").unwrap();
        assert_eq!(entry.get_password().unwrap(), "original");
        let secret = "oauth-payload-测试".repeat(2048);
        set(&entry, &account, &secret).unwrap();
        assert_eq!(entry.get_password().unwrap(), MARKER);
        let reopened = Entry::new(super::super::CREDENTIAL_SERVICE, &account).unwrap();
        assert_eq!(get(&reopened, &account).unwrap(), secret);
        set(&reopened, &account, "rotated").unwrap();
        assert_eq!(get(&reopened, &account).unwrap(), "rotated");
        delete(&reopened, &account).unwrap();
        assert!(matches!(get(&reopened, &account), Err(Error::NoEntry)));
        assert!(!path(&directory().unwrap(), &account).exists());
        // A first publication interrupted before the marker is not usable;
        // deleting the still-owned alias also cleans its encrypted preparation.
        write_payload(&directory().unwrap(), &account, &secret).unwrap();
        assert!(matches!(get(&reopened, &account), Err(Error::NoEntry)));
        delete(&reopened, &account).unwrap();
        assert!(!path(&directory().unwrap(), &account).exists());
    }

    #[test]
    fn large_oauth_and_transaction_payloads_are_protected_and_owner_bound() {
        let root = tempfile::tempdir().unwrap();
        let account = "account:windows-payload-test";
        let secret = format!("{{\"token\":\"{}\"}}", "private-测试".repeat(2048));
        write_payload(root.path(), account, &secret).unwrap();
        assert_eq!(read_payload(root.path(), account).unwrap(), secret);
        let ciphertext = std::fs::read(path(root.path(), account)).unwrap();
        assert!(!ciphertext.windows(7).any(|bytes| bytes == b"private"));
        assert!(crypt(&ciphertext, "another-account", false).is_err());
        let mut tampered = ciphertext;
        tampered[20] ^= 1;
        std::fs::write(path(root.path(), account), tampered).unwrap();
        assert!(read_payload(root.path(), account).is_err());
        // Atomic replacement, including recovery after an unusable payload.
        write_payload(root.path(), account, "replacement").unwrap();
        assert_eq!(read_payload(root.path(), account).unwrap(), "replacement");
    }
}
