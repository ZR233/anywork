# 23 - anywork 发布与应用内升级

本文定义 `anywork` 稳定版的唯一发布渠道、Windows 打包格式与应用内更新信任边界。首版仅支持 Windows `x64`；候选发布（RC）构建仅作为 CI 构件（artifact），不进入稳定更新源。SSH 远端辅助进程（`pl-remote-helper`）不设独立发布契约，而是以压缩资源随应用发行包（bundle）一并分发（见 [22](./22-ssh-remote.md)）：安装目录包含随包资源，GitHub Release 不提供单独的辅助进程下载项，也不在用户数据目录安装副本。

## 23.1 版本与发布流

### Release Please 版本计算与人工审批

Studio 使用 Release Please 的单一根组件管理版本：根版本文件、发布清单（release manifest）与带版本注解的 Flutter `pubspec.yaml` 由同一个 Release PR 同步更新；Flutter 版本仅允许规范的稳定语义化版本 `x.y.z`，不使用 `+build` 后缀。版本变更从整个仓库的约定式提交（Conventional Commits）收集，自动版本计算采用 `always-bump-minor` 策略：
- **次版本统一递增**：可发布的产品修改统一递增次版本号（minor）并将修订号（patch）归零，`fix:` 提交也不自动递增 patch；携带 `!` 或 `BREAKING CHANGE:` 的提交不自动递增主版本号（major），但必须保留真实的破坏性变更标记与发行说明。
- **非产品提交隐藏**：普通 `docs:`、`chore:` 与 `ci:` 提交隐藏，不进入发行说明，仅包含此类提交的批次不生成 Release PR；但包含真实破坏性变更说明或显式 `Release-As` 人工版本指定的提交不受此过滤影响。
- **主版本人工决策**：主版本号（major）升级必须由维护者明确决定，在合入主分支的提交正文中使用 `Release-As: x.y.z` 指定目标稳定版本，再人工审查并合并生成的 Release PR；显式指定仅作用于当次发布，后续恢复自动递增次版本策略，不在配置文件中长期保留 `release-as` 覆盖。所有版本均以人工审查并合并 Release PR 作为发版批准。

PR 质量门禁（PR Quality Gate）对 PR 头部分支运行 Release Please 演练（dry run）以验证发布配置；仅在 GitHub GraphQL API 返回已知瞬时错误时执行有限重试，其余错误直接判定失败。

### 三阶段发布器（Publisher）与权限分离

发布工作流按 Release Please 官方模式运行，并使用仓库专属的细粒度个人访问令牌（fine-grained PAT，工作流须先校验其归属仓库所有者）创建或更新 Release PR，确保该 PR 及其合并提交能正常触发后续 GitHub Actions。Release PR 合并后，同一工作流运行实例从 Release Please 输出中解析不可变的 `v{x.y.z}` 标签、草稿发布（draft Release）与精确数字 ID，并同步调用可复用的发布器（publisher）；发布器再通过 GitHub API 与 Git 标签独立核验仓库身份、稳定版本号、提交 SHA 与三个版本文件，拒绝任何人工传入的版本号或 SHA 参数。版本回滚仅允许通过发布更高版本的正向修复（forward fix）完成，严禁覆盖既有 Git 标签或已发布的 Release。

发布器分为三个阶段：
1. **Linux 辅助进程交叉构建作业**：从标签对应的精确提交交叉编译两种 `musl` 架构的 `pl-remote-helper` 并生成 SHA-256 摘要，仅作为当次工作流运行实例的内部构件传递。
2. **Windows GUI 构建与验证作业**：消费上述辅助进程构件并打入应用发行包，依次执行 Rust 与 Flutter 静态检查、GUI 确定性构建、代码签名、临时目录静默安装冒烟测试、独立产物核验（verify）与构建溯源证明（provenance attestation）。同一不可变源码的发布构建仅在准备阶段（stage）执行一次权威代码生成与一致性检查；独立核验步骤可复用同一标签提交编译出的核验工具内部构件（消费前核对摘要与编译工作区身份）。
3. **正式发布对账作业（Publish）**：下载最终构件并按精确 Release ID 对账——草稿 Release 可为空或仅含部分资产，但任何已存在资产的文件名、字节长度与 SHA-256 摘要必须与本地文件完全一致，仅允许补传缺失资产而严禁覆盖不同字节；全部资产核对一致后取消草稿状态并标记为 `latest`。失败重跑可复用原构件继续补传，幂等收敛。

若某个未完成发布的草稿 Release 因源码缺陷必须由后续提交修复，维护者可在主分支记录明确的取代（supersede）声明（绑定稳定标签、精确提交 SHA 与原因），使该草稿不再阻塞下一版 Release PR 的生成，同时禁止手动发布该被取代的草稿。构建与发布遵循严格的权限分离：发现与解析草稿的作业虽需仓库写权限（因 GitHub 草稿 Release 仅对具备推送权限的身份可见）但仅执行只读查询；构建作业保持只读权限；唯有最终发布作业执行资产上传与 Release 状态切换。

稳定版 Release 固定包含四项公开资产：Windows 单用户（per-user）安装器、安装器的 `.minisig` 签名文件、`latest.json` 更新清单与 `SHA256SUMS.txt` 校验和文件（不提供便携版压缩包，也不执行 Cargo crate 发布）。

### 工具链固定、构建缓存与 MSVC 环境排障

Flutter 版本与 Rust 工具链版本在仓库中统一固定（以 `rust-toolchain.toml` 为唯一事实源，同时声明 `rustfmt`、`clippy`、`rust-analyzer` 组件以及 `aarch64-unknown-linux-musl`、`x86_64-unknown-linux-musl` 交叉编译目标）。`cargo xtask` 在触发任何 Rust 命令前先于仓库根目录执行 `rustc --version` 以完成固定工具链同步预检。CI 中的第三方生成工具（如 FRB 生成器与 `cargo-expand`）通过固定版本的 `cargo-binstall --force` 安装预编译二进制包，禁止回退至源码编译。构建缓存按宿主平台、实际工具链与产物集合隔离。

Windows 本机编译第三方 C 依赖（如 `zstd-sys`）若遇到 MSVC `D8050` 错误（`cannot execute 'c1xx.dll': failed to get command line into debug records`），属于本机 MSVC 临时目录权限、路径长度或杀毒软件拦截等环境问题，而非代码缺陷。排查时可开启 `CC_ENABLE_DEBUG_OUTPUT` 获取完整编译器输出并修复 `%TMP%`/`%TEMP%` 环境；仅在本机环境短期无法修复时，才可在不入库的 `.cargo/config.local.toml` 中配置 `[profile.dev.package.zstd-sys] debug = 0` 作为个人本地临时绕过。

## 23.2 Windows 安装包与签名信任根

正式打包入口命令（`stage`、`finalize`、`verify`，参数为规范 `x.y.z` 版本号）要求传入版本与 `pubspec.yaml` 完全一致。`stage` 阶段复用 GUI 构建产物生成单用户 Inno Setup 安装器（使用稳定 `AppId`，默认安装至 `LocalAppData`，声明 `CloseApplications` 与 `RestartApplications`，支持英语与随源码固定的简体中文界面，并将 `code/pl-studio-runtime/THIRD_PARTY_NOTICES.md` 与 `LICENSE` 打入发行包根目录）。

发布的安装器不包含调试符号文件（PDB）；Windows 构建会额外生成独立的符号构件（包含与发布版本、提交 SHA 及会话协议版本映射的启动器与 Rust 桥接库 PDB），专门用于崩溃转储分析。升级后的用户数据与配置遵循 [17](./17-studio-storage.md) 与 [20](./20-config.md) 的迁移契约（迁移边界见 [17.7](./17-studio-storage.md#177-大版本隔离与配置迁移)）。

签名信任机制分为两层：
- **Minisign / Ed25519（强制信任根）**：生产环境公钥直接编译进运行时二进制文件，私钥与口令仅保存在 CI 机密存储（secrets）中；轮换私钥时必须先通过仍受旧密钥信任的应用版本发布包含新公钥的客户端。
- **Authenticode（可选系统增强）**：当代码签名证书存在时，依次对主可执行文件、自有动态库与最终安装器进行签名；证书缺失时不阻塞发布。

`finalize` 阶段仅对最终定稿字节生成 SHA-256、Minisign 签名、校验和文件与更新清单；`verify` 阶段独立复核文件集合、版本号、字节长度、哈希摘要、签名与清单一致性。

## 23.3 更新清单（`latest.json`）

发布器按当前 GitHub 仓库名 `ZR233/anywork` 校验发布身份；客户端更新检查 URL 维持已发布版本信任的 `ZR233/pure-lang` 路径（由 GitHub 仓库重命名重定向机制解析至同一发布仓库）。稳定版更新清单固定为 `latest.json`（采用 `camelCase` 类型化 JSON）：

```json
{
  "schemaVersion": 1,
  "version": "1.2.3",
  "publishedAt": 1770000000,
  "notesUrl": "https://github.com/ZR233/pure-lang/releases/tag/v1.2.3",
  "platforms": {
    "windows-x86_64": {
      "url": "https://github.com/ZR233/pure-lang/releases/download/v1.2.3/anywork-1.2.3-windows-x86_64-setup.exe",
      "size": 123456,
      "sha256": "...",
      "signature": "https://github.com/ZR233/pure-lang/releases/download/v1.2.3/anywork-1.2.3-windows-x86_64-setup.exe.minisig"
    }
  }
}
```

其中 `publishedAt` 为 Unix 秒级时间戳（`i64`）。客户端严格拒绝未知 `schemaVersion`、非稳定语义化版本、同版本或降级版本、非 HTTPS 协议、非本仓库资源、异常端口或查询参数，以及标签、版本号与文件名不一致的下载链接。清单与签名下载最多跟随 **5 次**重定向，且重定向目标主机仅限 GitHub Release 与官方 CDN 的 HTTPS 域名。

## 23.4 更新状态机与安装交接

Studio 运行时的更新器所有者（updater owner）在内存中维护权威状态枚举 `UpdaterState`：`Disabled`、`Idle`、`Checking`、`UpToDate`、`Available`、`Downloading`、`Verifying`、`Ready`、`InstallerLaunched`、`CheckFailed` 与 `InstallFailed`（每个状态由独立载荷承载，不设平行的可选字段）：

- **只读查询与后台单次检查**：`readUpdateState()` 仅读取本进程内存所有者而不访问网络，更新状态与下载进度不写入 `config.toml`。桌面应用启动完成后，每个进程仅在后台执行一次 `checkStudioUpdate()`（使用编译进二进制的产品版本）；发现新版本后自动流式下载并校验，验证通过后进入 `Ready` 状态并持有安装包的只读文件租约。
- **断点续传与多重校验**：安装包下载采用 Rust 原生 `reqwest`/`rustls` 与 `downlowd` 库管理 HTTP 断点续传、`ETag`/`Last-Modified` 校验、有界重试及 `.part`/`.downloadinfo` 分片写入（同一版本缓存受操作系统文件锁保护，拒绝跨进程并发下载）。超时与重试限额固定为：更新检查连接超时 **15 秒**、读取停滞超时 **30 秒**、总预算 **60 秒**；安装包下载单文件上限 **512 MiB**、连接与读取停滞超时 **5 秒**、总预算 **15 分钟**、最多 **4 次**传输尝试（重试间隔不超过 2 秒），中间进度合并发布频率上限为每秒 **4 次**。下载完成后必须完整校验字节长度、SHA-256 摘要与内置 Minisign 公钥签名，任一校验不通过立即删除损坏分片并终止，绝不启动未验证的二进制程序。
- **退出协调与安装器交接**：手动点击更新不要求当前会话空闲，下载期间可正常使用应用。当安装包准备完成且进入应用退出流程时，统一走宿主退出协调器（见 [18](./18-studio-state.md) §18.5）：唯有运行时、桥接层与 Dart 外部所有者全部确认收束且关停报告为真实 `Clean` 时，才启动安装器交接；若关停报告为 `Degraded`、保存状态未知或超时，则跳过本次安装并保留已验证缓存供下次启动重试。Windows 安装器通过支持显式脱离（breakaway）的进程交接工厂启动，脱离原应用作业对象（Job Object），禁用 Windows Restart Manager 的自动关闭与重启，等待旧进程真正退出后才开始写入文件，并在手动更新完成后负责拉起新版本应用。

## 23.5 生产诊断日志与后台进程窗口约束

Studio 在用户数据目录的 `anywork/logs` 下写入滚动的 Rust 日志与 Dart 错误日志，崩溃标记（panic marker）与原生转储（minidump）写入 `anywork/crashes`：
- **滚动策略与过期清理**：默认日志级别为 `warn`（命令行 `--log-level` 优先于环境变量 `RUST_LOG`）。Rust 主日志与同步错误日志按日或单文件达到 **16 MiB** 轮转，每类保留当前文件及最多 **7 个**历史归档；启动、每小时定时期与正常关闭时自动清理最后修改时间超过 **48 小时**的自有日志与崩溃文件（旧格式及 Dart 兜底日志总体积超过 **64 MiB** 时从最旧文件开始淘汰）。
- **隐私脱敏与多路退出兜底**：完整提示词、对话上下文、敏感凭据与工具输出正文严禁写入诊断日志（日志仅记录根会话、智能体、会话身份、游标、阶段、条目规模、耗时与结果分类，见 [17](./17-studio-storage.md)）。关停错误通过同步错误日志、临时目录应急文件与标准错误流（`stderr`，Windows 另含调试输出）多路兜底落盘，且日志写入绝不延误 30 秒应用退出硬期限。Windows 构建同时为当前可执行文件配置 WER `LocalDumps` 与进程内未捕获异常小型转储（minidump）兜底。
- **后台子进程无窗口约束**：所有由 GUI 发起的后台 Git、Docker、MCP、LSP、智能体与终止辅助命令在 Windows 上统一使用 `CREATE_NO_WINDOW` 标志启动（见 [05](./05-conventions.md) §5.5）；仅当用户显式点击打开外部交互式终端、编辑器或更新安装器时才显示外部窗口。
