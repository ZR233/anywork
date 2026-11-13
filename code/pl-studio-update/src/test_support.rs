//! Public test vector from minisign-verify 0.3.0's `verify_prehashed` test.
//! https://github.com/jedisct1/rust-minisign-verify (MIT)
pub const PUBLIC_KEY: &str =
    "untrusted comment: test public key\nRWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
pub const SIGNATURE: &str = "untrusted comment: signature from minisign secret key
RUQf6LRCGA9i559r3g7V1qNyJDApGip8MfqcadIgT9CuhV3EMhHoN1mGTkUidF/z7SrlQgXdy8ofjb7bNJJylDOocrCo8KLzZwo=
trusted comment: timestamp:1556193335\tfile:test
y/rUw2y8/hOUYjZU71eHp/Wo1KZ40fGy2VJEDl34XMJM+TX48Ss/17u3IvIfbVR1FkZZSNCisQbuQY+bHwhEBg==";

pub fn update(bytes: &[u8]) -> crate::StudioUpdate {
    use sha2::{Digest, Sha256};
    crate::StudioUpdate {
        version: "1.0.0".into(),
        published_at: 1,
        notes_url: "https://github.com/ZR233/pure-lang/releases/tag/v1.0.0".into(),
        installer: crate::StudioUpdateAsset {
            url: "https://github.com/ZR233/pure-lang/releases/download/v1.0.0/anywork-1.0.0-windows-x86_64-setup.exe".into(),
            signature: "https://github.com/ZR233/pure-lang/releases/download/v1.0.0/anywork-1.0.0-windows-x86_64-setup.exe.minisig".into(),
            size: bytes.len() as u64,
            sha256: hex::encode(Sha256::digest(bytes)),
        },
    }
}
