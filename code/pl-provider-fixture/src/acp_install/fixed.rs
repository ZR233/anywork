//! 产品固定的 Antigravity 1.4.1 发行清单。
//!
//! 运行期不再访问任何 registry 文档：生产只按宿主 target 选一条固定条目，fixture
//! 侧也必须用同一张表核对它服务的 URL、包内入口与版本，避免“测试自己的第二份事实源”。

/// 官方发行前缀（完整 URL = 前缀 + 归档相对路径）。
pub const ARCHIVE_BASE_URL: &str = "https://dl.google.com/agy-extensions/releases/";

/// 唯一允许的 server 版本。
pub const SERVER_VERSION: &str = "1.4.1";

/// Linux 包内入口名。
pub const LINUX_PROGRAM_NAME: &str = "agy_acp_server.par";

/// Windows 包内入口名。
pub const WINDOWS_PROGRAM_NAME: &str = "agy_acp_server.exe";

/// 包内合成控制成员：packaged fixture agent 用它定位安装树之外的 state 目录。
///
/// 该成员只由 fixture 自己打出的包携带，生产不读它、也不为它增加任何开关。
pub const AGENT_CONTROL_MEMBER: &str = "agent-control.json";

/// 固定条目：宿主 target → (归档相对路径, 包内入口)。
///
/// 只包含产品真正支撑的四个 target；其它 target 一律 `None`，让验收明确区分
/// “产品不支持该宿主”与“fixture 少写了一条”。
pub fn entry(target: &str) -> Option<(&'static str, &'static str)> {
    match target {
        "linux-x86_64" => Some((
            "linux/agy-acp-server-1.4.1-linux-x86_64.zip",
            LINUX_PROGRAM_NAME,
        )),
        "linux-aarch64" => Some((
            "linux/agy-acp-server-1.4.1-linux-arm64.zip",
            LINUX_PROGRAM_NAME,
        )),
        "windows-x86_64" => Some((
            "windows/agy-acp-server-1.4.1-windows-x86_64.zip",
            WINDOWS_PROGRAM_NAME,
        )),
        "windows-aarch64" => Some((
            "windows/agy-acp-server-1.4.1-windows-arm64.zip",
            WINDOWS_PROGRAM_NAME,
        )),
        _ => None,
    }
}

/// 固定条目的完整官方归档 URL。
pub fn archive_url(target: &str) -> Option<String> {
    entry(target).map(|(path, _)| format!("{ARCHIVE_BASE_URL}{path}"))
}

/// 固定条目的包内入口名。
pub fn program_member(target: &str) -> Option<&'static str> {
    entry(target).map(|(_, program)| program)
}

/// 固定条目的归档请求路径（含前导 `/`），用于核对 peer 真正服务的路径。
pub fn archive_path(target: &str) -> Option<String> {
    entry(target).map(|(path, _)| format!("/agy-extensions/releases/{path}"))
}
