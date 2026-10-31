# Linux 构建环境

本目录提供项目级 Ubuntu 22.04 / amd64 构建环境。本地开发、其他 CI 系统和
GitHub Actions 使用同一个 Dockerfile；镜像不是应用运行镜像，也不包含项目成品、
用户配置或凭据。

## 本地构建与使用

以下命令从仓库根目录执行，需要 Docker 与 BuildKit：

```sh
docker build -f docker/linux/Dockerfile --target linux-build -t anywork-linux-build:local .
bash docker/linux/scripts/run.sh anywork-linux-build:local cargo test --locked -p pl-xtask
bash docker/linux/scripts/run.sh anywork-linux-build:local cargo xtask build-gui
```

仅验证 Rust 环境时，可构建 `--target rust-env`。完整镜像额外提供 Flutter、
Zig/cargo-zigbuild、GTK/C++ 原生构建和 Debian 打包工具。容器内仍使用仓库正式入口；
不要绕过 xtask 直接构建 Flutter Linux 工程。

运行脚本挂载当前 checkout，并保留其绝对路径和工作目录，便于预构建工具的工作区
身份核验。它不挂载真实 HOME、Docker socket 或个人凭据，也不需要 GitHub 环境变量。
工程产物仍写到仓库既有 `target/`、`dist/` 等位置；按运行脚本的用户映射处理宿主
写权限，不用特权容器解决目录权限问题。不要将镜像发布 token 传给项目构建。

已准备好辅助进程成品时，可以复用它们而不重新编译：

```sh
export PURE_REMOTE_HELPER_PREBUILT_DIR="$PWD/dist/remote-helper"
bash docker/linux/scripts/run.sh anywork-linux-build:local cargo xtask build-gui
```

该目录必须包含两个 musl 架构的可执行文件、SHA-256 和协议元数据。预构建资源缺失或
校验失败直接报错，不回退源码编译。未设置这个变量的普通本地构建仍沿用 xtask 的
辅助进程构建行为。

## 工具链与环境身份

Rust 唯一配置源是根目录 `rust-toolchain.toml`。Dockerfile 原样复制该文件，由
rustup 安装其 channel、profile、components 和 targets，不另设 `RUST_VERSION`。
运行时禁止自动安装其他 Rust 工具链；源码工具链与镜像不匹配时，应制作对应环境，
不能临时安装后继续使用错误镜像。

非 Rust 工具的固定版本和下载摘要集中在 `versions.env`。基础镜像固定 digest。
Flutter 与 Rust 使用独立制作阶段，避免升级 Rust 时无理由重复下载 Flutter。
Flutter SDK 自用的工具依赖及其原生配置随镜像交付，供非 root 用户读取；这不包含本项目的
pub 依赖缓存，也不引用镜像制作者的 `/root` 私有目录。

```sh
python3 docker/linux/scripts/image-key.py
```

环境身份覆盖工具链文件、Dockerfile、忽略规则、版本输入与必要脚本，排除业务源码、
`Cargo.lock` 和本说明。业务代码变化不需要制作新环境；工具链组件或 target 变化也会
改变环境身份。系统环境升级应修改相应固定输入，而不是覆盖既有环境标签。

发布镜像位于 `ghcr.io/zr233/anywork-linux-build`。输入标签 `inputs-<hash>` 用于发现
匹配环境，实际执行应使用解析后的 `@sha256:...` 引用，不依赖 `latest`。开发者也可
完全不使用 registry，直接从对应源码本地构建。

## 镜像制作与 CI

GitHub 的触发、权限、registry 登录和 artifact 交接属于 `.github/workflows/`
的适配层，不是本目录脚本的运行前提。镜像制作监听 `rust-toolchain.toml` 与实际环境
输入：PR 验证自身候选但不发布，受信分支通过验证后发布，不覆盖相同输入标签。
普通消费者直接拉取匹配的 digest；仅未发布的 PR 环境通过当次运行的构件传递候选。
应用发布与 RC 不在构建时补装环境。

镜像检查包含离线 Rust 编译、声明组件和 targets、GTK/C++ 最小编译及 Linux 进程
监督所需能力。这些只证明构建环境可用，不代表应用成品已经通过兼容或业务验收。

## DEB 与兼容范围

```sh
bash docker/linux/scripts/run.sh anywork-linux-build:local \
  cargo xtask release-gui stage --version <x.y.z> --bundle "$PWD/dist/anywork-release"
bash docker/linux/scripts/run.sh anywork-linux-build:local \
  cargo xtask release-gui verify --version <x.y.z>
```

版本必须与源码一致；stage 只消费显式预构建 bundle，不编译 GUI 或 helper，拒绝
覆盖已有发布目录。输出在 `dist/studio-release/<x.y.z>/`：Debian 包及其
`.deb.sha256`。安装使用系统包管理器，例如 `sudo apt install ./anywork-<version>-linux-x86_64.deb`。

首版成品验证目标为 Ubuntu 22.04、24.04 与 Debian 12、13 的 amd64。构建环境固定
Ubuntu 22.04，完整 ELF 的 GLIBC 需求不高于 2.35，其他 ABI 需求也须满足最低环境。
辅助进程使用 musl，不表示 Flutter、GTK 和 Rust bridge 不再依赖 glibc。

兼容检查在干净运行环境安装同一 DEB，不能借用本镜像预装的开发库掩盖漏依赖。
不承诺更旧发行版或全部桌面业务；支持与证据边界见
[发布契约](../../design/23-release-update.md)。
