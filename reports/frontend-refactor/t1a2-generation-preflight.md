# T1.A2 — SDK Freezed 与统一生成前置证据

本记录只证明 A2 的依赖、分层许可与生成前置，不表示 Timeline 消费闭环、Native R2、
全量门禁或 GUI 验收通过。比较基线仍为 `f6cb327ceb3416dca181790575711588571d3ec7`，
检查现场为 `b98432fa809446d57be87a8b96379455ec8a4828` 上的未提交工作区。

## 1. 设计先行与组件选择

先同步 [25](../../design/25-frontend-state.md) 的只读观察／可靠正文消费者、ACK、typed close、
双包生成及依赖约定，以及 [26](../../design/26-timeline-content.md) 的可等待展示写入与候选
lease 发布边界，再修改 manifest、xtask 与 AST 门禁。完整消费接口仍以
[A2 合同](./t1a2-dart-timeline-contract.md) 为准，不能由本前置推断剩余实现已完成。

复用应用已经使用的组件和版本，不引入第二套值生成、状态管理或 codec：

| SDK 直接依赖 | 范围 | 锁定版本 |
| --- | --- | --- |
| freezed_annotation | runtime | 3.1.0 |
| freezed | dev | 4.0.2 |
| build_runner | dev | 2.16.2 |
| test | 既有 dev | 保留 `^1.33.0` 约束及原解析版本 |

已查官方文档及锁定版本源码／manifest／许可：

- [Freezed 4.0.2](https://pub.dev/packages/freezed/versions/4.0.2)：支持纯 Dart 安装，annotation
  为运行依赖、生成工具为 dev dependency；模型采用官方 factory／part 路线。其源码要求
  Dart `>=3.13.0 <4.0.0`，当前 SDK 为 3.13.5；Freezed 采用 MIT 许可。
- [freezed_annotation 3.1.0](https://pub.dev/packages/freezed_annotation/versions/3.1.0)：只有
  public annotation 入口可以由领域包直接导入；传递的 collection、meta、json_annotation
  不代表允许直接依赖它们或新增 JSON 编解码。
- [build_runner 2.16.2](https://pub.dev/packages/build_runner/versions/2.16.2)：在所属 package
  根目录运行官方单次 build，不使用实验性多 package workspace 模式；沿用 Dart 项目 BSD 许可。
- [pub get](https://dart.dev/tools/pub/cmd/pub-get)：`--enforce-lockfile` 拒绝无效解析或 hosted
  包摘要变化。生成与检查均锁定两包快照，不由 canonical 检查升级版本。

SDK lock 新增 17 个包，所有新增版本及 hosted digest 均与应用 lock 对应项相同；既有 SDK
包的版本／digest 没有变化。应用 `pubspec.lock` 与 `Cargo.lock` 没有变化。
实际 SDK package_config 不含 Flutter、Riverpod 或 FRB。

## 2. 实现范围

- `xtask/src/client.rs`：精确校验唯一 runtime 依赖 `freezed_annotation: 3.1.0`，拒绝 override，
  在 SDK 目录从其 lockfile 准备依赖。应用的 path dependency 不会带入 SDK 的 dev 工具。
- `xtask/src/flutter/codegen.rs`：两包分别运行官方 build_runner；共同维护生成 part 的
  canonical 内容／集合、规范化、格式化及孤儿清理；FRB／l10n 仍为应用独有。
  `build-gui --check-generated` 复用应用已锁定配置，再按 SDK 的 lockfile准备其 dev 工具。
- `xtask/dart/client_boundary_check.dart`：只精确放行
  `package:freezed_annotation/freezed_annotation.dart`，不放行 annotation 私有路径或其它包；
  feature 同时禁止新的 `conversation_ports.dart` transport 入口。
- `code/anywork/test/client/client_boundary_check_test.dart`：扩充正／反例，保留 Flutter、
  Riverpod、FRB、私有导入和资源生命周期的原拒绝规则。

未手改生成文件，未直接调用单个生成器，未从 SDK 安装目录运行项目命令。

## 3. 实际验证

### 3.1 静态检查与现有行为

| 实际命令／边界 | 结果 |
| --- | --- |
| `rustfmt --edition 2024 --check xtask/src/client.rs xtask/src/flutter/codegen.rs` | exit 0 |
| `cargo clippy -p pl-xtask --all-targets -- -D warnings` | exit 0 |
| SDK `dart format --output=none --set-exit-if-changed lib test` | 108 文件，0 改动 |
| SDK `dart analyze --fatal-infos` | No issues found |
| SDK `dart test --reporter=expanded` | 190 passed |
| `cargo flutter test --no-pub --reporter=expanded test/client/client_boundary_check_test.dart` | 最终版本 27 passed |
| `cargo dart --packages=.dart_tool/package_config.json ../../xtask/dart/client_boundary_check.dart ../..` | 294 手写源文件通过 |
| AST 工具及专属 fixture 的 Dart 格式检查 | 2 文件，0 改动 |
| `git diff --check`、文档相对引用、UTF-8／LF／末行与 skill frontmatter | 通过 |

SDK 命令在 `code/anywork_client` 执行；Flutter／AST 命令由根包装入口切换到应用目录。
未将 SDK 检查冒充完整 `verify-client`：当前旧 Dart adapter 尚待 A2 迁移，不能提交删除 native
API 而调用方未迁移的中间代码阶段。

### 3.2 门禁缺陷敏感度

1. 在同一真实 AST 检查函数中临时恢复旧零第三方许可条件，运行相同的 Freezed 合法导入
   正例，实际 exit 1，错误定位为 `OWN-01`。恢复精确公共入口许可后，同一正例和全部反例
   通过；没有另写错误算法复制品制造“绿色红证据”。
2. 临时将实际 SDK manifest 的 `3.1.0` 改为 `^3.1.0`，运行真实
   `cargo xtask verify-client`，实际 exit 1，明确拒绝非精确许可；随后恢复原 manifest。
   这是预期拒绝，不是完整 verify-client 通过记录。

### 3.3 双包生成与文件集合

在 Native 手写输入冻结、reviewer 已结束的窗口，以临时 SDK Freezed 手写输入
`lib/src/codegen_boundary_probe.dart` 进行以下真实统一入口检查：

| 顺序 | 操作 | canonical 实际结果 |
| --- | --- | --- |
| 1 | 新增临时手写输入，运行 `cargo xtask check-gui-generated` | exit 1，唯一变化为新增 SDK `codegen_boundary_probe.freezed.dart` |
| 2 | 相同输入重复运行同一入口 | exit 0，生成稳定 |
| 3 | 只删除临时手写输入，运行同一入口 | exit 1，唯一变化为统一入口移除该 SDK 孤儿生成 part |
| 4 | 无临时输入重复运行同一入口 | exit 0，生成再次稳定，无 probe 源码／产物残留 |

两个非零结果是 canonical 检查按设计拒绝文件集合变化，不是生成器失败。日志确认每轮 SDK
与应用都使用 `--enforce-lockfile`，SDK 官方 Freezed 实际生成过值；全过程没有手工删除或修改
生成 part。正常 build_runner 缓存下完成本探针，冷缓存场景不在本记录中冒称已执行。

前后核对 151 项冻结的 native 手写输入、应用生成文件及 manifest／lock 身份，均未变化。
FRB 仍只导出合同方法，没有 `FrbTimelineSink`／`TimelineFrameSink`，也没有退役的
`subscription/timeline.dart` 产物。
前后身份表与完整原始日志留在忽略的 `target/refactor-evidence/`／任务日志目录，不提交机器路径。

## 4. 内容身份与后续边界

| 文件 | SHA-256 |
| --- | --- |
| xtask/src/client.rs | 913762f1bea710bb8eb5a833f1bae295b1bb0e86647ffed2faf612552cc9724e |
| xtask/src/flutter/codegen.rs | fc97792a53a8cb6be6a9af63195122b08a8ac97c278b641bfbfb8cadfdb626b9 |
| xtask/dart/client_boundary_check.dart | c4bc85c1e9bb7f88724a37eb474fdf8e3310b9518edc2493f64741ffcada521e |
| code/anywork/test/client/client_boundary_check_test.dart | 27a3f9047b113615938fa3c6d1e2ee38248fa2d2c9914f73b9c758d9467e030a |
| code/anywork_client/pubspec.yaml | 72987a62240196246b88c1b6c82e687070ae19a84c4f7674f83666d4d73a9f67 |
| code/anywork_client/pubspec.lock | 1211428b48e28c83bfe6006c7af271a3091986c8bc0c54502f273d65b502c4b2 |

本前置取证时 Native Timeline 仍在 R2 返工／复审链，A2 手写消费实现未派发；之后的局部批准
范围见 [阶段记录](./README.md)。上述 SDK 证据本身不能批准 native 并发、FFI、真实展示 ACK
或资源回收。后续生成输入变化后仍须统一生成与 canonical 检查；
跨层阶段提交前由 root 完成适用的全量、native／GUI 和 CI 验收。
