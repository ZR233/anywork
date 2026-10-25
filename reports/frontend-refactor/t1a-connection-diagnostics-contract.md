# T1.A 连接失败只读诊断增量合同 v1

## 1. 授权、目标与非目标

本合同是已批准全链路计划（Plan revision 6 / version 3）内的最窄验收诊断增量，
不是新业务重试策略，也不是 Timeline 阶段完成声明。整体 workflow 仍为 working。
根设计为 `design/26-timeline-content.md` §26.9，root 先同步设计，再委派实现。

已保留的 QA a1 事实为 `connection:failed / generation:0 / ready:false / itemCount:0 /
scroll:null`，但旧 Driver 没保留原因。fixture 正常、native exit 0、a2 或 root 后续旅程通过
都不能反推旧失败原因。本增量让后续实际失败保留安全 typed 元数据；不承诺凭诊断代码
本身修复或重现 a1，不把任意复跑绿色当作根因结论。

不修改 Rust、FRB、SDK owner、TimelineSessionOwner 的业务实现、预算、重试、准入、
关闭流程、GUI 旅程判据、50ms 采样间隔或 90s 超时；不增加依赖、生成输入、缓存或
生产测试 hook。不运行新 GUI、fixture 或全仓门禁；原生取证由 root 后续单独编排。

## 2. 现场基线与所有权

- HEAD：`b98432fa809446d57be87a8b96379455ec8a4828`。
- 分支：`pure-session-thread-65e3ee582f0d4-82`；贡献基线
  `f6cb327ceb3416dca181790575711588571d3ec7`。
- 大量既有未提交前置已完成局部审查，不能恢复、覆盖或顺手重构。
- 唯一执行者拥有下表五文件的本增量；其他代理不并行修改这五文件。
- root 独占 design、此合同、生成、manifest、Git 与最终集成。
- raw QA 只拥有 `t1a-native-acceptance.md`，其 fresh review 与本增量互斥范围独立。

| 文件（均相对 `code/anywork/`） | 派发前 SHA-256 | 职责 |
| --- | --- | --- |
| `lib/src/shared/studio_driver_state.dart` | `c565c7ad1b7f2253550bba57e4630986241a276fd3901fb7e993af359aa405ee` | immutable facts 字段与 JSON |
| `lib/src/shared/studio_driver_projection.dart` | `32ea0755c8e050c97e033726479b3a6ff99ea78bcd3e03b6cefb389030a59759` | 同步读取当前 owner 并提取 typed 元数据 |
| `test_driver/timeline_observation.dart` | `f2d54fdd6298d2990050b9fc3588e37d0019c135353aeee1d5c34992e881525f` | 严格消费新增诊断 schema |
| `test_driver/timeline_streaming_journey.dart` | `71c918fa306a2aa77bbfc636a617a59fe735289aa778e0225e807ed7534253b1` | 既有两个有界诊断 Map 增加四标量 |
| `test/client/studio_driver_query_test.dart` | `c089bb6e76ef2bf28efbd4ad9ebe33b4ae7056ecffc64d3bfd642989a0d3a367` | 经真实 owner→projection→JSON→Driver parser 的回归 |

后两文件已有未提交前置，其合并 binary diff（该顺序的 Git pathspec）SHA 为
`b652798dfecfb2b56878ae85dd01b6ffa024460b0dc8a4a5d556c27bb04ee535`。
交付审查应比较本次输入文件身份与结果，不把全部相对 HEAD 差异当本次新增。

## 3. 架构与完整接口增量

数据流固定为：当前 `TimelineSessionOwner.source.value` 的 `TimelineViewState`
→ `queryStudioDriverFacts` 的现有 `_timelineFacts`
→ `TimelineDisplayFacts` → `StudioDriverState.snapshotJson`
→ `TimelineObservation.optional/parse` → 原超时 `diagnostics`。
这不是新 Repository、日志总线、事件源或错误归一化层。

`TimelineDisplayFacts` 构造函数新增四个 required 命名参数及同名 final 字段：

| 字段 | Facts 类型 | JSON 值类型 | Driver observation 类型 |
| --- | --- | --- | --- |
| `connectionErrorType` | `String?` | string 或 null | `String?` |
| `connectionErrorCode` | `StudioFailureCode?` | 既有领域 enum 的 `.name` 或 null | `String?` |
| `connectionErrorRetryable` | `bool?` | bool 或 null | `bool?` |
| `connectionErrorCorrelationId` | `String?` | string 或 null | `String?` |

`TimelineObservation` 私有构造与 final 字段同步增加同名字段。现有公共函数签名不变：

```dart
StudioDriverFacts queryStudioDriverFacts(
  AnyworkClient client, {required TimelineSessionOwner timeline});
static TimelineObservation? optional(Map<String, dynamic> snapshot);
static TimelineObservation parse(Map<String, dynamic> snapshot);
Future<Map<String, Object?>> observeStreamingHistory(
  FlutterDriverSession driver, Directory output);
```

不新增公共 helper、别名、provider、可写 store、transport 方法或测试专用注入点。
typed 业务值仍使用 SDK 已有 `StudioFailure` / `StudioFailureCode`，不另建错误 enum。

## 4. 字段、错误与隐私语义（必须遵守）

| 当前 `view.connectionError` | Type | Code / Retryable / CorrelationId |
| --- | --- | --- |
| null | null | 三项均 null |
| `StudioFailure` | `error.runtimeType.toString()` | 原 `code` / `retryable` / `correlationId`，不修改 |
| 其他非 null Object | `error.runtimeType.toString()` | 三项均 null，不猜测、不替换为 internal |

四个 JSON 键在 timeline 对象存在时始终存在，即使值为 null。未选择 Thread 或当前
owner Thread 不匹配时保持原有 `timeline:null`；不为诊断建立 owner 或借用旧 Thread。
无展示 lease 但已有匹配的 view 时仍可输出四项；ready 仍是原有 lease 是否存在的事实。
不按 connection 枚举猜 error；始终读取当前 error，不缓存之前的失败。

禁止对 error 调用任意 `toString()`，禁止提取或序列化 `message`、`detailsJson`、堆栈、
正文、凭据和路径；运行时类型名来自 Dart 类型元数据，不是异常正文。
correlationId 仅照录已有 typed 身份，不从 message 解析；不发明新 ID。
false 必须保留为 false，不能与 null 混同；code 不从 retryable 或错误文本推导。

Driver parser 对四项均要求 key 存在；缺键或错误值类型抛 `StateError`，不静默 fallback。
合法 null 是未知或无错误，不是缺键。Type/Code/CorrelationId 非 null 必须为 String，
Retryable 非 null 必须为 bool。Code 为诊断消费中的领域 enum 名，不引入反射或业务分类。
错误消息不得为此新增字段而打印整份原始快照或异常内容。

## 5. 状态、并发、资源与预算

- 所有事实仍在一次同步请求内读取，局部固定当前 view 和其 error；不新增 await、订阅、
  计时器、transport demand、read/query、草稿、展示 lease 或第二份正文。
- 不改变任何业务 owner 生命周期；Driver 只借用，dispose 不关闭业务资源。
- 超时仍只保留 `last` 和 `lastWhileBusy` 两个小 Map，在其现有 timeline 子对象加四字段。
  不另存 ring、完整 snapshot、正文或 stack；不额外调用 `readSnapshot`。
- 不改原 until ready 判定、抛错类型、轮询间隔、上限或旅程动作；没有业务自动重试。
- 未建立新队列或 byte budget，不声称这四字段能证明原因已修复、内部流控或保存完成。

## 6. 迁移与依赖有序步骤

1. 核对 HEAD、五文件 SHA、设计与合同；先在本执行者自己的 artifacts 保留五文件输入
   身份与可比较原件，不写其他会话目录。发现不符暂停向 root 报告。
2. 复用现有 `studio_driver_query_test.dart` 的公开 owner/transport 环境，先建立能在旧
   projection 上真实失败的 regression；不得直接构造新 facts 回读自传字段冒充证明。
3. 同步修改 Facts、唯一生产构造、JSON serializer 和严格 Driver parser；metadata 从同一
   view/error 读取，故障与 null 规则全部固定，不让 private helper 改变契约。
4. 在原超时诊断 Map 增加四值，其他采样、判定和动作原样。
5. 用同一 regression 在修改前非零、修改后通过，记录真实红绿证据；只做目标格式、静态
   检查和此测试文件。修复受影响问题后冻结五文件 hash 和定向 diff，等待 fresh review。

除这五文件外无需迁移调用方；仓库内唯一生产 `TimelineDisplayFacts(...)` 在 projection。
若核查发现其他实际消费者或必须跨文件修改，先报告 root 扩定合同，不保兼容 alias。
root 后续负责官方原生取证、判断实际 failure、阶段跨层验收及必要全量门禁。

## 7. 验收与最小充分测试矩阵

测试目标为**本项目错误元数据适配、隐私与实时读取**，不是复述 DTO 构造或 Dart 自身类型。
优先增强现有完整行为证明，最小层级是进程内、真实 Client/TimelineSessionOwner/projection/
JSON/parser，transport fake 仅提供触发输入，不复制生产映射算法；不冒原生 FRB 证明。

| 风险 | 必须观察的判定 |
| --- | --- |
| 初始失败无 lease 时丢 reason | 经既有 public owner 路径失败，JSON 四键存在；typed code/retryable/correlation 原样，ready 不伪造为 true |
| 错把 message/details 写进诊断 | 合成敏感 sentinel 放入 failure message/details；输出与 parse 后可见元数据不含 sentinel，仅保类型与 typed 身份 |
| 将未知异常吞为 internal 或打印正文 | 经可达真实失败路径提供自定义异常，其 `toString` 可设为抛错或敏感 sentinel；若该路径保持原 Object，只有 runtime type，后三项 null；不添加生产 hook 来强行触达 |
| null/false/缺键混同 | 无错误输出四 null；typed retryable:false 保留 false；parser 缺键及错误类型必须拒绝，而 null 被接受 |
| 读诊断产生需求/保留旧失败 | 复用现有只读 demand/opens 断言；当前 owner/Thread 不匹配仍 timeline null，恢复或新当前值不沿用旧 error |
| 只改 DTO 没改真实链 | 测试从真实 owner/projection/JSON 进入 Driver parser，旧生产投影下同一成功判定非零失败 |

若未知异常在真实现有入口一律已被其他层规范化，报告具体证据；不为填矩阵扩生产接口，
由 root 判定是否复用已有保护。其他接口与错误语义没有未决项，执行者只选择私有组织。

定向命令从 workspace root 执行（仅目标文件，不全仓格式化）：

```bash
cargo dart format --output=none --set-exit-if-changed \
  lib/src/shared/studio_driver_state.dart lib/src/shared/studio_driver_projection.dart \
  test_driver/timeline_observation.dart test_driver/timeline_streaming_journey.dart \
  test/client/studio_driver_query_test.dart
cargo dart analyze lib/src/shared/studio_driver_state.dart \
  lib/src/shared/studio_driver_projection.dart test_driver/timeline_observation.dart \
  test_driver/timeline_streaming_journey.dart test/client/studio_driver_query_test.dart
cargo flutter test test/client/studio_driver_query_test.dart
git diff --check
```

必要可先只格式化上述五文件；不运行 generate-gui/verify-client/verify-gui/manual-gui，
不 stage/commit/push。报告命令、结果、红绿证据、五文件最终 hash、本增量 diff、偏差与
后台/交互状态。停止修改后立即由 root 创建 fresh reviewer，批准只覆盖本合同和当前身份。
