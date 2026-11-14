# 23 - anywork 发布与应用内升级

本文定义 `anywork` 稳定版的唯一发布渠道、Windows / Linux `x64` 与 macOS `arm64` 打包格式及 Windows / Linux 应用内更新信任边界。Linux 提供标准 Debian 包与系统授权安装，macOS 提供手动安装的完整 `.app` ZIP；候选发布（RC）构建仅作为 CI 构件（artifact），不进入稳定更新源。SSH 远端辅助进程（`pl-remote-helper`）不设独立发布契约，而是以压缩资源随应用发行包（bundle）一并分发（见 [22](./22-ssh-remote.md)）：安装目录包含随包资源，GitHub Release 不提供单独的辅助进程下载项，也不在用户数据目录安装副本。

macOS 当前提供从源码构建当前宿主架构的 `.app`：bridge 动态库位于包内 Frameworks，SSH helper 位于包内 Resources，完整保留 framework 的版本符号链接。应用为访问用户工作区及启动工具而不启用 App Sandbox；本地构建采用 ad-hoc 签名。稳定版与 RC 使用 GitHub 的 `macos-15` Apple Silicon runner，首版仅分发 `arm64`；不包含 Developer ID 签名、公证或应用内更新。

## 23.1 版本与发布流

### Release Please 版本计算与人工审批

Studio 使用 Release Please 的单一根组件管理版本：根版本文件、发布清单（release manifest）与带版本注解的 Flutter `pubspec.yaml` 由同一个 Release PR 同步更新；组件预览包依赖锁中的本地应用版本也由官方 YAML 定点更新能力同步，保持严格依赖解析有效，不重新选择其他依赖版本。Flutter 版本仅允许规范的稳定语义化版本 `x.y.z`，不使用 `+build` 后缀。版本变更从整个仓库的约定式提交（Conventional Commits）收集，自动版本计算采用 `always-bump-minor` 策略：
- **次版本统一递增**：可发布的产品修改统一递增次版本号（minor）并将修订号（patch）归零，`fix:` 提交也不自动递增 patch；携带 `!` 或 `BREAKING CHANGE:` 的提交不自动递增主版本号（major），但必须保留真实的破坏性变更标记与发行说明。
- **非产品提交隐藏**：普通 `docs:`、`chore:` 与 `ci:` 提交隐藏，不进入发行说明，仅包含此类提交的批次不生成 Release PR；但包含真实破坏性变更说明或显式 `Release-As` 人工版本指定的提交不受此过滤影响。
- **主版本人工决策**：主版本号（major）升级必须由维护者明确决定，在合入主分支的提交正文中使用 `Release-As: x.y.z` 指定目标稳定版本，再人工审查并合并生成的 Release PR；显式指定仅作用于当次发布，后续恢复自动递增次版本策略，不在配置文件中长期保留 `release-as` 覆盖。所有版本均以人工审查并合并 Release PR 作为发版批准。

PR 质量门禁（PR Quality Gate）对 PR 头部分支运行 Release Please 演练（dry run）以验证发布配置；仅在 GitHub GraphQL API 返回已知瞬时错误时执行有限重试，其余错误直接判定失败。

现有 PR 质量工作流由 cheap `changes` 计划作业，始终运行的 `ci-gate` 汇总；包含格式、静态分析、Linux workspace `cargo test --locked --workspace --features pl-core/sqlite`、Flutter UI `flutter test --no-pub test/ui`、桌面 `test-project` 与受影响平台的 native 套件，以及生成文件一致性检查。稳定发布与 RC 构建直接消费已提交的生成文件，并与当次已验证的构建/测试过程共享同一 SHA。发布器的确定性构建、签名、安装和完整性验证属于最终产物的信任边界，不由源码检查替代。人工批准是发布授权，不是对未执行检查的成功证明；本文不另设本地提交前测试流程。

### 分阶段发布器（Publisher）与权限分离

发布工作流按 Release Please 官方模式运行，并使用仓库专属的细粒度个人访问令牌（fine-grained PAT，工作流须先校验其归属仓库所有者）创建或更新 Release PR，确保该 PR 及其合并提交能正常触发后续 GitHub Actions。Release PR 合并后，同一工作流运行实例从 Release Please 输出中解析不可变的 `v{x.y.z}` 标签、草稿发布（draft Release）与精确数字 ID，并同步调用可复用的发布器（publisher）；发布器再通过 GitHub API 与 Git 标签独立核验仓库身份、稳定版本号、提交 SHA 与三个版本文件，拒绝任何人工传入的版本号或 SHA 参数。版本回滚仅允许通过发布更高版本的正向修复（forward fix）完成，严禁覆盖既有 Git 标签或已发布的 Release。

发布器按可恢复边界划分以下阶段：
1. **Linux 辅助进程交叉构建作业**：从标签对应的精确提交，以单一作业定义的架构矩阵在两个 Linux runner 上并行编译两种 `musl` 架构的 `pl-remote-helper`。各实例分别生成二进制、SHA-256 摘要与协议元数据，仅作为当次工作流运行实例的内部构件传递，构件身份按架构隔离。RC 沿用相同矩阵构建契约。
2. **Windows GUI 编译作业**：仅在辅助进程矩阵全部成功后，下载并校验两种架构的构件，执行消费已提交生成文件的确定性构建。编译成功即分别归档运行 bundle 与同一源码提交编译的小型发布工具，不等待后续下载、签名或外部溯源服务。运行 bundle 不包含调试符号或编译中间物；发布作业无需为取得工具而再次下载整个 bundle。缺少任一辅助进程构件或校验失败均终止构建。
3. **Windows 打包与签名作业**：下载并强校验编译构件，显式使用其中的预构建发行包准备安装器（stage），不再编译 Flutter、Rust bridge 或发布工具。阶段内完成可选 Authenticode、Minisign 定稿、独立产物核验及临时目录静默安装冒烟，成功后归档最终资产。缺失输入或校验失败直接终止，不回退编译。
4. **Linux GUI 编译与预构建打包作业**：与 Windows 编译并行，消费同一次辅助进程矩阵的两个不可变构件身份及既有预构建资源入口，不再次编译辅助进程。编译成功即归档完整 Linux 运行 bundle 和同源码发布工具；打包仅消费校验过的预构建输入，生成 Debian 包及独立校验和，不回退编译。
5. **Linux 成品兼容验证作业**：在目标发行版的干净运行环境中安装同一个归档 Debian 包，检查依赖解算、文件布局、动态加载及启动边界。它不使用预装全部开发依赖的构建环境，避免掩盖包依赖缺失；重试仅消费同一成品，不重新编译。
6. **macOS GUI 编译与预构建打包作业**：复用稳定版与 RC 的 `macos-release-build.yml`，消费同次辅助进程矩阵的两个构件，分别归档完整 `.app` 与同源码发布工具。下游核对构件 ID、生产者摘要及工具工作区后，通过 Apple `ditto` 生成保留签名、权限与 framework 符号链接的 ZIP；解包复核版本、架构、资源与完整签名，不重新编译、不修改已签名的应用。
7. **独立构建溯源作业**：仅消费已经归档并校验的最终 Windows 安装器、Linux Debian 包或 macOS ZIP，分别生成构建溯源证明（provenance attestation）。适用平台的证明均是正式发布必需前置条件；外部服务失败不得降级为跳过，但可独立重跑而不重复编译、打包或签名。
8. **正式发布对账作业（Publish）**：等待适用平台的验证与溯源，下载最终构件并按精确 Release ID 对账——草稿 Release 可为空或仅含部分资产，但任何已存在资产的文件名、字节长度与 SHA-256 摘要必须与本地文件完全一致，仅允许补传缺失资产而严禁覆盖不同字节；全部资产核对一致后取消草稿状态并标记为 `latest`。失败重跑可复用原构件继续补传，幂等收敛。

跨作业构件只在同一工作流运行实例内传递，使用不可变构件身份并由受控源码检出、发布解析结果及生产者输出绑定来源。消费者对每份有效载荷核对一次生产者提供的 SHA-256；独立工具执行前还须核对编译工作区身份。不额外保存重复这些身份的自述清单或符号协议映射。不得跨运行实例、跨 PR 借用构件或以重新编译掩盖构件缺失。归档后仅重跑失败或指定的下游作业可复用成功前置作业的原构件；完整重跑不属于该续跑保证，构件过期后也不能保证恢复。

验证按信任边界分工：定稿（finalize）负责签名与完整本地自检，同一作业内不再对未改变的资产重复执行相同核验；构件下载负责有效载荷完整性与工具身份；安装冒烟负责实际安装结果；正式发布前保留资产签名核验及远端逐资产对账。在线溯源独立执行，不能替代任何签名或安装检查。

RC/手动构建沿用编译构件交接与预构建打包契约，并在无生产签名凭据、无 Release/tag 写入的路径执行安装器打包和静默安装冒烟。macOS 同样完成预构建打包、解包与签名校验，结果仅存为 CI 构件。此路径不证明生产 Minisign 签名、在线溯源或正式发布已经通过。

若某个未完成发布的草稿 Release 因源码缺陷必须由后续提交修复，维护者可在主分支记录明确的取代（supersede）声明（绑定稳定标签、精确提交 SHA 与原因），使该草稿不再阻塞下一版 Release PR 的生成，同时禁止手动发布该被取代的草稿。构建与发布遵循严格的权限分离：发现与解析草稿的作业虽需仓库写权限（因 GitHub 草稿 Release 仅对具备推送权限的身份可见）但仅执行只读查询；编译作业保持只读权限且不接触生产签名凭据；签名凭据只在打包签名作业使用并清理；独立溯源作业持有 OIDC/attestation 权限；唯有最终发布作业执行 Release 资产上传与状态切换。

稳定版 Release 的资产集合由不可变发布源码的契约决定。当前版本提供十项公开资产：Windows 单用户（per-user）安装器及其 `.minisig`、`latest.json`、`latest-v2.json`、跨平台安装包 `SHA256SUMS.txt`，以及 `anywork-<version>-linux-x86_64.deb`、同名 `.deb.sha256` 与 `.deb.minisig`、`anywork-<version>-macos-arm64.zip` 和同名 `.zip.sha256`。平台构件先按各自检查点严格核验，最终汇合后签名 Linux 安装包并核验完整资产集合；保留已有 Windows 签名字节和清单时间戳，重试不能改变已上传资产。历史已发布版本按其原有资产契约验证，不补包、不覆盖；不提供 Windows 便携版压缩包，也不执行 Cargo crate 发布。

### 工具链固定、构建缓存与 MSVC 环境排障

Flutter 版本与 Rust 工具链版本在仓库中统一固定（以 `rust-toolchain.toml` 为唯一事实源，同时声明 `rustfmt`、`clippy`、`rust-analyzer` 组件以及 `aarch64-unknown-linux-musl`、`x86_64-unknown-linux-musl` 交叉编译目标）。`cargo xtask` 在触发任何 Rust 命令前先于仓库根目录执行 `rustc --version` 以完成固定工具链同步预检。CI 中的第三方生成工具（如 FRB 生成器与 `cargo-expand`）通过固定版本的 `cargo-binstall --force` 安装预编译二进制包，禁止回退至源码编译。构建缓存按宿主平台、实际工具链与产物集合隔离。

生成检查在同一已解析镜像的独立安装容器中，使用作业的只读 GitHub 令牌下载固定生成工具，避免匿名接口限流。安装容器仅挂载工具输出目录；后续源码生成只消费安装结果，不接收下载令牌。

依赖缓存优先用于 Windows，Linux 构建与测试不读写持久依赖缓存；Windows Rust 缓存仅由默认分支运行保存，PR 与非默认分支只恢复可访问的基线缓存。Flutter SDK/pub 沿用固定组件的原生缓存契约，不额外维护平行缓存。缓存丢失只能影响速度，不能影响确定性或绕过验证；不依赖自动删除旧缓存或提高配额保证容量。工作流构件是有期限的交付检查点，与依赖缓存分离，不受依赖缓存命中与否控制。直接执行已校验发布工具进行预构建打包、定稿与核验时不再触发 Rust 工具链同步。

Windows 本机编译第三方 C 依赖（如 `zstd-sys`）若遇到 MSVC `D8050` 错误（`cannot execute 'c1xx.dll': failed to get command line into debug records`），属于本机 MSVC 临时目录权限、路径长度或杀毒软件拦截等环境问题，而非代码缺陷。排查时可开启 `CC_ENABLE_DEBUG_OUTPUT` 获取完整编译器输出并修复 `%TMP%`/`%TEMP%` 环境；仅在本机环境短期无法修复时，才可在不入库的 `.cargo/config.local.toml` 中配置 `[profile.dev.package.zstd-sys] debug = 0` 作为个人本地临时绕过。

### 项目级 Linux 构建环境

Linux 工程环境属于项目，不依赖 GitHub Actions 的变量、凭据或仓库身份；本地开发与 CI 共享同一 Docker 定义和正式工程入口。环境固定 Ubuntu 22.04 `amd64` 基础镜像及非 Rust 工具下载身份。Rust 版本、profile、组件与 targets 仅由根 `rust-toolchain.toml` 定义，由 rustup 原生读取安装，不维护镜像专属版本副本。运行时核对工具链输入，禁止以自动安装另一工具链掩盖镜像与源码不匹配。

环境身份由完整构建输入决定，包含工具链文件、Docker 定义及必要的版本、摘要和脚本；业务源码、项目依赖快照和说明文档不无理由使环境失效。已发布环境以输入标签发现，再解析不可变 manifest digest 消费；同一输入标签不覆盖。源码升级选择新环境，旧源码保留原环境，不消费漂移的 `latest`。开发者可直接构建相同定义，无须 registry 或 CI 凭据。

PR 中可复用的工程工具和 remote helper 资源使用同次运行的明确产物身份交接，消费者校验归档摘要及适用的源码、平台、构建环境和工具编译工作区约束。工具二进制不跨操作系统复用，Debug/Release bridge 不互相代用；helper 的 Linux 目标资源可作为各桌面平台相同的 bundle 输入。归档保留执行权限与必要符号链接，不传递整个 Cargo 编译目录。缓存只加速构建，不能代替本次输入身份；缺失或不匹配直接失败，不静默重建掩盖交接错误。

镜像构建、冒烟与发布权限分离。PR 只能使用匹配的公开镜像或制作并验证自身候选，不持有镜像发布权限；跨作业候选只通过当前运行实例的不可变构件身份、归档摘要和 image ID 传递。受信分支在验证后以最小 package 写权限发布；正式应用发布及 RC 仅消费匹配源码的已发布环境，缺失时失败而非临时补装工具。构建环境不包含产品成品、用户数据、凭据或项目依赖缓存，不要求特权容器或宿主 Docker socket。它可供 Linux 服务端检查、辅助进程构建和 GUI 打包复用，不改变 Windows 或轻量发布策略作业的宿主。

构建环境中的 Git 与 OpenSSH 必须满足现有工作树和 SSH 消费者的真实能力要求，不能仅以命令存在或基础发行版的默认版本作为验收依据。运行容器保留宿主 UID/GID；该身份不必预置在镜像账户中。需要身份解析的系统工具通过容器内、无特权、临时的用户与组映射运行，不修改或挂载宿主账户文件，不以 root、扩大挂载或放宽权限规避身份问题。相关能力应在镜像冒烟中直接验证，而不是由 CI 消费者临时安装修补。

## 23.2 Windows 安装包与签名信任根

正式打包入口命令（`stage`、`finalize`、`verify`，参数为规范 `x.y.z` 版本号）要求传入版本与 `pubspec.yaml` 完全一致。`stage` 必须显式提供预构建 bundle，不隐式构建、不解析构建依赖；消费方先验证构件来源与版本，再生成单用户 Inno Setup 安装器（使用稳定 `AppId`，默认安装至 `LocalAppData`，声明 `CloseApplications` 与 `RestartApplications`，支持英语与随源码固定的简体中文界面，并将 `code/pl-studio-runtime/THIRD_PARTY_NOTICES.md` 与 `LICENSE` 打入发行包根目录）。

Windows 安装器固定使用 `PrivilegesRequired=lowest`，不主动启用 `RedirectionGuard`。在受影响的 Windows 版本上，安装器启用的重定向信任策略会随安装后启动或更新重启传入应用及其命令子进程，阻止普通用户创建的目录链接，破坏 Flutter 等开发工具链。安装器显式使用 Inno Setup 的 `RedirectionGuard=no`，避免在安装链主动附加此策略；不修改系统缓解策略、提权或在运行时尝试撤销已经继承的策略。已受限的旧版应用启动更新时，限制仍可能沿更新进程链继承；升级后须完全退出，再从开始菜单或快捷方式启动一次。由外部宿主或系统配置施加的策略仍由其管理。此选择只适用于当前不提权的单用户安装边界；若未来引入管理员安装，必须重新评估安装器的路径重定向防护与应用启动隔离。

Windows 运行 bundle 统一由工程入口收集：包含应用可执行文件、Flutter/bridge/插件与原生资源所需的动态库及完整数据目录；正式打包阶段再追加许可证和第三方许可说明。数据目录包含 Dart AOT 产物、ICU 数据、Flutter 资源与两个架构的远端辅助进程资源，不因文件后缀或宿主平台而删减。所需 VC++ Release 运行库采用应用目录部署，由 CMake 官方运行库安装能力从当前工具链的可再分发目录提供，不复制系统目录中的 DLL，也不要求普通用户安装器额外提权。

调试符号、导入库、链接中间文件、对象文件、源码及 Cargo 构建脚本/过程宏产物不属于运行 bundle，不进入安装器或 CI 恢复构件；发布不再收集独立符号归档，也不以符号存在或匹配作为门禁。原始编译目录中的符号可供本地诊断，不因发布精简而删除。升级后的用户数据与配置遵循 [17](./17-studio-storage.md) 与 [20](./20-config.md) 的迁移契约（迁移边界见 [17.7](./17-studio-storage.md#177-大版本隔离与配置迁移)）。

签名信任机制分为两层：
- **Minisign / Ed25519（强制信任根）**：生产环境公钥直接编译进运行时二进制文件，私钥与口令仅保存在 CI 机密存储（secrets）中；轮换私钥时必须先通过仍受旧密钥信任的应用版本发布包含新公钥的客户端。
- **Authenticode（可选系统增强）**：当代码签名证书存在时，依次对主可执行文件、自有动态库与最终安装器进行签名；证书缺失时不阻塞发布。

`finalize` 阶段仅对最终定稿字节生成 SHA-256、Minisign 签名、校验和文件与更新清单；`verify` 阶段独立复核文件集合、版本号、字节长度、哈希摘要、签名与清单一致性。

打包编译器至少使用 Inno Setup 6.7.0（`RedirectionGuard` 指令自该版本提供），CI 缺少编译器时安装固定的 6.7.1。Windows 安装器仍接纳已发布客户端的 `/ANYWORKUPDATE=exit`，等待其 `/ANYWORKWAITPID` 退出后覆盖文件且不重启；新客户端仅发送 `/ANYWORKUPDATE=1`，安装后重启。此边界服务旧客户端升级，不恢复新客户端的普通退出安装行为。

### Linux Debian 包与兼容边界

Linux `stage` 同样显式消费版本匹配的预构建 bundle，不隐式执行 Flutter、Rust bridge 或辅助进程编译。使用 Debian 官方打包与共享库依赖分析能力，拒绝缺少输入、架构错误、无法解析的系统库及已有 staging 覆盖。包架构为 `amd64`；应用完整安装于 `/opt/anywork`，由 `/usr/bin/anywork` 提供命令入口，系统桌面目录安装既有应用入口与图标。完整数据目录、Flutter/bridge/插件运行库、两种架构的辅助进程资源、许可证与第三方许可说明一并交付，不写用户配置或在用户目录注册另一份安装。

桌面入口使用稳定图标名 `io.github.zr233.anywork`，对应的 512×512 PNG 安装到系统 `hicolor/512x512/apps` 标准目录；bundle 的相对资源布局保持一致。图标尺寸目录必须由系统主题登记，不能仅因文件存在就视为桌面环境可发现。安装冒烟须从已安装桌面入口读取图标名，通过 GTK 的主题查找与图片解码确认其可用。

Debian 包使用 GNU/glibc 桌面链路；只有独立辅助进程采用 musl，不能据此宣称整包摆脱 glibc。首版构建基线为 Ubuntu 22.04，目标运行环境为 Ubuntu 22.04、24.04 与 Debian 12、13 的 `amd64`。对所有 ELF 有效载荷检查 ABI 需求：GLIBC 不高于 2.35，GLIBCXX/CXXABI 等不超出最低支持环境实际提供的能力。系统库依赖由成品推导，发行版包名迁移以实际包关系与原生包管理器解算为依据，不私带或替换 glibc、不忽略缺库、不降低依赖声明伪造兼容。

ELF 依赖分析不能发现运行时动态加载的库。Flutter/GTK 图形栈通过 libepoxy 加载的 GL、EGL 与 GLES 调度库必须显式列入产品依赖，不能依赖开发包、测试工具或宿主桌面的偶然安装。具体驱动由操作系统及用户的图形环境提供，包不绑定某一家 GPU 驱动。PackageKit 识别本地安装包还需要标准 MIME 数据，因此显式依赖 `shared-mime-info`；该数据依赖不能从 ELF 推导。独立库的链接分析可显式使用随包私有库目录模拟主进程已加载的依赖；主程序分析与真实启动不注入额外加载路径，不放宽缺库、符号或版本错误。

Debian 打包与依赖解算断言（`release::linux::tests`）由 workspace 测试覆盖，在具备真实发行版依赖信息（官方 `dpkg-dev` 与 `libc6:amd64.symbols`）的项目 Docker 构建环境或 Debian/Ubuntu 宿主中运行。测试实际执行 `.deb` 包布局、解包提取校验、字段与文件篡改检测，以及缺失动态载荷库时的 `dpkg-shlibdeps` 依赖解析失败断言；不注入机器专用库路径、不模拟依赖解析，也不放宽依赖与篡改断言。

同一个归档成品在各目标发行版验证依赖安装、布局与动态加载，并执行隔离启动冒烟；构建成功、解包成功或单平台结果不能替代其他目标的证据，也不代表完整业务或真实供应商验收。更旧发行版不在首版支持范围内；扩展时须重新评估构建基线与完整依赖链。

安装后的产品沿用系统工具的既有所有权：本地 Git 项目的工作树管理与恢复诊断使用 `PATH` 中的 Git，SSH 远程能力使用系统 OpenSSH 并复用用户配置与凭据设施（见 [22](./22-ssh-remote.md)）。这些功能要求用户提供满足命令能力的工具，不把构建镜像内的 Git/OpenSSH 当作 Debian 包已交付内容，也不由安装器添加第三方软件源。当前本地恢复审计需要 `git worktree list --porcelain -z`，这是 Git 2.36 起文档化的能力；Ubuntu 22.04 默认 Git 2.34 不满足该调用，使用相关功能前须按 [Git 官方安装说明](https://git-scm.com/install/linux) 更新系统 Git。该能力要求不是对所有 Git 功能的统一最低版本审计结论。SSH 远程功能另需安装系统 OpenSSH 客户端，Debian/Ubuntu 包名为 `openssh-client`。共享库与首帧兼容通过不能替代这些外部工具和业务路径的独立验证。

Linux 的 `.deb.sha256` 描述最终 Debian 包字节；汇合发布时使用同一 Minisign 信任根生成 `.deb.minisig` 并加入多平台更新清单。首次安装使用系统包管理器，后续可在应用内更新；不添加 APT 仓库。系统安装目录仍为 `/opt/anywork`，用户配置与凭据仍在原用户目录。标准 `.deb` 安装需要系统授权，应用不要求用户手动运行 `sudo`。

### macOS Apple Silicon 归档与兼容边界

macOS 的 `release-gui stage` 显式消费 `dist/anywork-release` 格式的预构建 bundle，通过 Apple 官方 `ditto -c -k --sequesterRsrc --keepParent` 生成 `anywork-<version>-macos-arm64.zip` 与严格绑定文件名和字节摘要的 `.sha256`。归档包含单个完整 `anywork.app`；许可证、Flutter/bridge/插件和两个 Linux helper 资源均随应用保留。`verify` 严格检查两项资产、校验和，并使用 `ditto` 解包后复核应用版本、主程序与 bridge 的 `arm64` 架构、必要资源及 `codesign --verify --deep --strict`。这些检查不启动应用，不代表完整 GUI 或供应商业务验收。

最低系统版本为 macOS 13；CI 原生构建与打包使用 `macos-15`，不据此宣称已在所有 macOS 版本实机验证。当前应用使用 ad-hoc 签名，尚未配置 Developer ID 和 Apple 公证，GitHub 构建溯源不能替代它们；下载后的系统信任判定仍遵循 Gatekeeper。用户解压并将 `.app` 放入 Applications，更新使用同样的手动替换方式，不写入 Windows 更新清单。本次不提供 Intel 或 Universal 包。

## 23.3 多平台更新清单（`latest-v2.json`）

发布器按 `ZR233/anywork` 校验发布身份。当前客户端只读取 `https://github.com/ZR233/anywork/releases/latest/download/latest-v2.json`（schema 2），由 Rust 按构建平台选择 `windows-x86_64` 或 `linux-x86_64`，检查资产的版本、文件名与签名 URL。缺少本平台资产时返回不支持该平台，不能误报已是最新。

发布端继续输出 schema 1 的 `latest.json`，仅含 Windows，并保留旧客户端信任的 `ZR233/pure-lang` URL。该投影仅服务已发布外部客户端；新客户端没有旧格式解析或回退。新版本统一清单示例：

```json
{
  "schemaVersion": 2,
  "version": "1.2.3",
  "publishedAt": 1770000000,
  "notesUrl": "https://github.com/ZR233/anywork/releases/tag/v1.2.3",
  "platforms": {
    "windows-x86_64": {
      "url": "https://github.com/ZR233/anywork/releases/download/v1.2.3/anywork-1.2.3-windows-x86_64-setup.exe",
      "size": 123456,
      "sha256": "...",
      "signature": "https://github.com/ZR233/anywork/releases/download/v1.2.3/anywork-1.2.3-windows-x86_64-setup.exe.minisig"
    },
    "linux-x86_64": {
      "url": "https://github.com/ZR233/anywork/releases/download/v1.2.3/anywork-1.2.3-linux-x86_64.deb",
      "size": 123456789,
      "sha256": "<64 hex characters>",
      "signature": "https://github.com/ZR233/anywork/releases/download/v1.2.3/anywork-1.2.3-linux-x86_64.deb.minisig"
    }
  }
}
```

其中 `publishedAt` 为 Unix 秒级时间戳（`i64`）。客户端严格拒绝未知 `schemaVersion`、非稳定语义化版本、同版本或降级版本、非 HTTPS 协议、非本仓库资源、异常端口或查询参数，以及标签、版本号与文件名不一致的下载链接。清单与签名下载最多跟随 **5 次**重定向，且重定向目标主机仅限 GitHub Release 与官方 CDN 的 HTTPS 域名。

## 23.4 更新状态机与安装交接

更新传输、验证和安装包租约由独立的 `pl-studio-update` 提供；Studio 保留产品状态、事件发布和退出协调的唯一所有权，职责边界见 [02](./02-crates.md)。缓存验证区分内容损坏与存储失败：长度、摘要或签名不符才允许重新准备，读取或锁定失败保留原文件并向调用方报告，不以删除和重下载掩盖磁盘错误。

Studio 运行时的更新器所有者（updater owner）在内存中维护权威快照，其中当前活动为 `StudioUpdateActivity` 枚举：`Disabled`、`Idle`、`Checking`、`UpToDate`、`Available`、`Downloading`、`Verifying`、`Ready`、`InstallerLaunched`、`CheckFailed` 与 `InstallFailed`（每个状态由独立载荷承载，不设平行的可选字段）：

- **后台周期检查与事件交付**：Windows 与 Linux x86_64 正式版桌面应用就绪后，每个进程幂等启动一个 Rust 后台调度器，立即检查一次，此后每 **20 分钟**检查稳定版本；使用 Tokio `interval` 与 `MissedTickBehavior::Skip`，休眠后不集中补跑，手动操作不重置周期。检查、下载、校验和投影的单轮错误与可捕获 panic 发布失败状态并记录诊断，收束该轮后继续下一周期。当前轮次忙时跳过定时准入，不并行下载。只有应用关停停止调度，并等待当前轮次真实完成；用户取消只影响其选中的当前轮次，下一周期仍可重新下载。
- **活动与已验证安装包**：`StudioUpdateStateSnapshot` 同时承载当前 `activity` 与独立的 `readyUpdate`，共用活动 revision；状态仅在内存中维护，不写入 `config.toml`。已有安装包时仍检查更高版本，同版或更低版本不重复下载；新版完整校验成功后才原子替换旧文件租约。新版失败、取消或检查失败均保留旧安装包及其可安装资格。手动安装先冻结选中版本，加入当前准备任务或取消新候选并使用已有安装包，完成回执只描述 `Ready(version)`、取消或失败，不等待常驻调度退出，也不允许后台在退出交接前替换选中版本。
- **统一 GUI 状态来源**：bootstrap 与 `UpdaterTopic` 基线、`UpdaterStateChanged` 事件进入 Client `UpdaterStore` 的唯一接纳入口，Riverpod 向侧栏、设置页等组件分发只读投影。手动检查只返回命令完成，安装操作只返回准备结果，不另开进度流、不用命令回执回灌状态，也不在失败后额外回读。组件销毁不取消后台任务；后台错误在更新区域显示，不主动弹出通知。
- **断点续传与多重校验**：安装包下载采用 Rust 原生 `reqwest`/`rustls` 与 `downlowd` 库管理 HTTP 断点续传、`ETag`/`Last-Modified` 校验、有界重试及 `.part`/`.downloadinfo` 分片写入（同一版本缓存受操作系统文件锁保护，拒绝跨进程并发下载）。超时与重试限额固定为：更新检查连接超时 **15 秒**、读取停滞超时 **30 秒**、总预算 **60 秒**；安装包下载单文件上限 **512 MiB**、连接与读取停滞超时 **5 秒**、总预算 **15 分钟**、最多 **4 次**传输尝试（重试间隔不超过 2 秒），中间进度合并发布频率上限为每秒 **4 次**。下载完成后必须完整校验字节长度、SHA-256 摘要与内置 Minisign 公钥签名，任一校验不通过立即删除损坏分片并终止，绝不启动未验证的二进制程序。
- **手动更新入口**：Windows / Linux 应用内更新的手动入口包括设置页的检查／下载并重启／安装并重启，以及主界面侧栏底栏设置旁的短按钮「更新」（英文 `Update`）。侧栏入口仅在 Client `hasUpdate` 为真时显示（发现新版本、正在下载或校验、安装包已就绪、或安装失败可重试）；没有已验证安装包时，检查中或已是最新不显示；已有安装包时，即使后续检查或新版下载失败仍保留入口。更新关闭或已启动安装器时不显示。点击「更新」与设置页安装并重启走同一命令：准备安装包后由退出协调器以更新后重启意图关停并交接安装器，不另开设置页、不另造安装 API。进度、发行说明与取消仍只在设置页。macOS 保持手动更新。普通退出不安装已下载包，只有用户明确点击更新才进入安装交接。
- **退出协调与安装器交接**：手动点击更新不要求当前会话空闲，下载期间可正常使用应用。当安装包准备完成且进入应用退出流程时，统一走宿主退出协调器（见 [18](./18-studio-state.md) §18.5）：唯有运行时、桥接层与 Dart 外部所有者全部确认收束且关停报告为真实 `Clean` 时，才启动安装器交接；若关停报告为 `Degraded`、保存状态未知或超时，则跳过本次安装并保留已验证缓存供下次启动重试。Windows 安装器通过支持显式脱离（breakaway）的进程交接工厂启动，脱离原应用作业对象（Job Object），禁用 Windows Restart Manager 的自动关闭与重启，等待旧进程真正退出后才开始写入文件，并在手动更新完成后负责拉起新版本应用。

### Linux 系统授权与可靠交接

更新准备阶段先请求 Polkit 授权，再关闭应用。`.deb` 随包提供 root 所有的独立更新辅助程序及固定 action；`pkexec` 只运行该程序，图形应用和重启监督进程保持原用户身份。未授权、取消、缺少系统服务或预检失败时，原应用继续运行，并发布安装失败状态。

用户缓存不是提权后的信任来源。准备任务从文件租约创建封印快照，辅助程序在 root 私有暂存目录再次验证内置公钥签名、摘要、包名、版本及架构。它收到真实 `Clean` 关闭提交后，仍通过 pidfd 等待旧应用退出；未提交时通道关闭只代表撤销，不能触发安装。普通退出及失败关闭均撤销交接并等待所属进程，安装阶段不占用应用的 30 秒关停预算。

PackageKit 负责 `.deb` 及依赖安装，辅助程序订阅事务信号后才提交安装，只有 `Finished(success)` 且没有 `ErrorCode` 才算成功。Minisign 信任不冒充仓库 GPG 信任。安装终态写入原用户的一次性结果文件，由下一次 bootstrap 纳入同一更新快照；安装错误独立保留，立即首检不会覆盖它。监督进程随后以原用户重启当前安装的应用；失败不承诺回滚，不伪报成功，缓存保留以便重试。

## 23.5 生产诊断日志与后台进程窗口约束

Studio 在用户数据目录的 `anywork/logs` 下写入滚动的 Rust 日志与 Dart 错误日志，崩溃标记（panic marker）与原生转储（minidump）写入 `anywork/crashes`：
- **滚动策略与过期清理**：默认日志级别为 `warn`（命令行 `--log-level` 优先于环境变量 `RUST_LOG`）。Rust 主日志与同步错误日志按日或单文件达到 **16 MiB** 轮转，每类保留当前文件及最多 **7 个**历史归档；启动、每小时定时期与正常关闭时自动清理最后修改时间超过 **48 小时**的自有日志与崩溃文件（旧格式及 Dart 兜底日志总体积超过 **64 MiB** 时从最旧文件开始淘汰）。
- **隐私脱敏与多路退出兜底**：完整提示词、对话上下文、敏感凭据与工具输出正文严禁写入诊断日志（日志仅记录根会话、智能体、会话身份、游标、阶段、条目规模、耗时与结果分类，见 [17](./17-studio-storage.md)）。关停错误通过同步错误日志、临时目录应急文件与标准错误流（`stderr`，Windows 另含调试输出）多路兜底落盘，且日志写入绝不延误 30 秒应用退出硬期限。Windows 构建同时为当前可执行文件配置 WER `LocalDumps` 与进程内未捕获异常小型转储（minidump）兜底。
- **后台子进程无窗口约束**：所有由 GUI 发起的后台 Git、Docker、MCP、LSP、智能体与终止辅助命令在 Windows 上统一使用 `CREATE_NO_WINDOW` 标志启动（见 [05](./05-conventions.md) §5.5）；仅当用户显式点击打开外部交互式终端、编辑器或更新安装器时才显示外部窗口。
