use serde::{Deserialize, Serialize};

/// Supported release assets. Platform selection belongs to the update owner.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum StudioUpdatePlatform {
    #[serde(rename = "windows-x86_64")]
    WindowsX86_64,
    #[serde(rename = "linux-x86_64")]
    LinuxX86_64,
}

impl StudioUpdatePlatform {
    pub fn current() -> Option<Self> {
        match (std::env::consts::OS, std::env::consts::ARCH) {
            ("windows", "x86_64") => Some(Self::WindowsX86_64),
            ("linux", "x86_64") => Some(Self::LinuxX86_64),
            _ => None,
        }
    }

    pub const fn key(self) -> &'static str {
        match self {
            Self::WindowsX86_64 => "windows-x86_64",
            Self::LinuxX86_64 => "linux-x86_64",
        }
    }

    pub fn asset_name(self, version: &str) -> String {
        match self {
            Self::WindowsX86_64 => format!("anywork-{version}-windows-x86_64-setup.exe"),
            Self::LinuxX86_64 => format!("anywork-{version}-linux-x86_64.deb"),
        }
    }
}
