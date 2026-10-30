# 基础栈与统一路由

文中 `{workspace}` 指当前仓库根，与技能安装位置无关。

## 采用现有基础栈

先查 `{workspace}/code/anywork/pubspec.yaml` 与
`{workspace}/code/anywork/pubspec.lock`、`{workspace}/Cargo.toml`
与 `{workspace}/Cargo.lock`，再查对应版本的官方契约。以下只规定基础能力的分工，
不锁定具体页面组件库，不引入替代框架。

| 能力 | 项目基础栈 | 使用边界 |
| --- | --- | --- |
| 导航 | `go_router`、`go_router_builder` | 单一 `GoRouter`，集中类型化声明与生成式目的地 |
| 呈现观察 | `flutter_riverpod`、`riverpod_annotation`、`riverpod_generator` | 生成式 Notifier／AsyncNotifier，按需观察不可变切片 |
| 呈现值 | `freezed`、`freezed_annotation` | UI 状态和联合类型，不承担业务资源所有权 |
| 领域客户端 | `anywork_client` | 运行期仅依赖 Dart SDK，领域值、端口与 data owner 分离 |
| 跨语言传输 | `flutter_rust_bridge` | typed DTO、Future／Stream 和必要的 native 句柄适配 |
| 异步基础设施 | `tokio`、`tokio-util` | 按语义复用通道、取消、任务跟踪，不新建平行生命周期框架 |
| 存储升级 | SQLite、`sea-orm`、`sea-orm-migration` | 复用已有存储与迁移所有者 |

组件的 `latest` 文档不等于锁定版本。生成式代码的所有权与统一生成入口使用
`flutter-studio-build`；不照抄上游示例绕过项目生成命令。

## 沿调用链确定写入责任

具体依赖方向见 `{workspace}/design/02-crates.md`，客户端所有权见
`{workspace}/design/25-frontend-state.md`。按功能组织模块，新增字段或动作前依次确认：

| 层 | 应承担的工作 | 应避免的工作 |
| --- | --- | --- |
| Rust | 判定业务事实、校验与保存 | 为 Flutter 分组、折叠或布局建立协议 |
| FRB adapter | DTO 与 SDK 类型映射、调用转发、句柄收束 | 业务 reducer、默认业务事实、第二份当前态 |
| SDK domain／data | typed 值与端口；所属 Repository 唯一归约当前态 | Flutter／Riverpod／FRB 生成类型泄漏到领域 |
| ViewModel／呈现 owner | 只读投影、必要的展示选择、UI 资源 | 把领域快照拆成伪事件再归约 |
| Connector／View | 绑定动作与资源／消费不可变 props 和回调 | View 直接读写 Repository、调用 FRB 或在 build 中发业务请求 |
| AppGraph | 应用实例装配和生命周期协调 | 跨实例可变单例或汇集全部业务数据的 store |

命令响应若携带权威快照，也进入同一个 Repository 写入口，不能在 VM 先写一份“成功态”。
草稿允许本地编辑，但保存结果由权威快照／事件确认，不能把本地 draft 当已保存值。
跨语言边界消费 typed DTO／union，不新增运行期 raw JSON 兼容入口。
结构化接口调整同步迁移 Rust protocol、FRB DTO、SDK model、归约／投影、生成物和权威设计；
线协议命名与基础类型直接遵循 `{workspace}/design/05-conventions.md` §5.1。

ViewState 使用可显示文本、按钮状态、加载或失败等 UI 词汇。Session、feed、Future、permit、
附件句柄和 Controller 是资源，不因加上 Freezed 就变成状态值。UI Controller 可以由呈现
owner 持有并借给 View；焦点、展开、动画等局部状态无需搬入领域仓储。
对接外部可变集合时，确认复制／冻结边界与嵌套值；`final List` 或只读视图不保证原集合不会变。

## 导航检查

权威规则及具体目的地见 `{workspace}/design/25-frontend-state.md` §25.4。
开发时检查以下接缝，不复制一份 URI、枚举映射或页面注册表：

- **声明与调用同源**：使用 `GoRouteData`／`TypedGoRoute` 和生成式目的地；
  不手拼路径、不新增通用导航包装或业务页面栈。View 通过回调表达意图，Connector 绑定目的地。
- **只消费已提交路由**：Provider／VM 不再保存当前页面或标签选择；
  视图参数交给官方编解码。区分参数缺失与非法值，错误不静默回退到其他有效目标。
- **路由身份不是草稿身份**：地址只携带资源身份和必要视图选择，不携带凭据、owner 或可变草稿。
  仅查询参数改变不重新分配编辑器；资源不存在交由领域错误呈现，不借用当前选中对象。
- **决议和退役分开**：按实际路由变化使用既有进入／退出边界，不在按钮和多个守卫重复询问。
  异步决议捕获来源路由、业务 owner、草稿修订，返回后复核；新输入不能借用旧决议。
  只有真实移除／替换提交后才释放对应本地资源，拒绝导航不丢输入。
- **挂载不等于仍有资格**：页面仍挂载也可能被新导航覆盖。迟到保存／删除结果可以结算原操作，
  但不能继续发命令或跳转覆盖新页面。官方页面 key、Provider family 和业务 owner 身份不互相代替。
- **可见性单向派生**：已提交路由和窗口可见性决定展示需求，不能反向修补路由。
  对话框、菜单等使用 Flutter 官方局部机制；释放页面观察不停止业务 Session 或后台任务。

## 官方资料

- [go_router 类型化路由](https://pub.dev/documentation/go_router/latest/topics/Type-safe%20routes-topic.html)
  与 [go_router_builder](https://pub.dev/packages/go_router_builder)。
- [Riverpod 使用边界](https://riverpod.dev/docs/root/do_dont)。
- [Freezed](https://pub.dev/packages/freezed)。
- [FRB 流类型](https://cjycode.com/flutter_rust_bridge/guides/types/translatable/stream)。
