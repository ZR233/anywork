# Flutter 全模块质量审查

本台账记录本次逐模块审读、代码质量提升及历史遗留清理。基线为
`3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`。应用基线共有 507 个手写 Dart
文件，预览包 31 个；生成文件不逐条人工修改，统一核对输入和生成一致性。

状态依次为 **已清点 → 已审读 → 已处理 → 已验证**。目录扫描、行数及导入统计
不能证明读完或测试覆盖；模块明细需列出实际读过的文件、问题依据、处理或保留理由。
验证必须记录实际命令、结果与范围。没有改动的模块同样留下审查结论。

## 模块台账

| 编号 | 范围 | 基线手写文件数 | 状态 | 明细 |
| --- | --- | ---: | --- | --- |
| M01 | 入口、app 装配／生命周期／路由／主题 | 15 | 已审读保留，最终核对无阻塞 | [基础边界](platform/review.md) |
| M02 | capture 调试扩展 | 3 | 已审读保留，最终核对无阻塞 | [基础边界](platform/review.md) |
| M03 | studio_l10n 与 ARB 源文案 | 1 + ARB | 已审读处理，两次统一生成通过 | [基础边界](platform/review.md) |
| M04 | domain/models | 10 | 已审读处理，unit 已通过，完整 UI 已覆盖 | [前端模型](domain-models.md) |
| M05 | presentation/providers 与时间线 owner | 27 | 已处理，冻结诊断返修及独立复核通过 | [时间线](timeline/review.md) |
| M06 | infrastructure/frb | 22 | 已处理，独立复核及 71 项联合回归通过 | [基础设施](infrastructure/m06-m07-frb-demo-cleanup.md) |
| M07 | infrastructure/demo | 8 | 已处理，独立复核及 71 项联合回归通过 | [基础设施](infrastructure/m06-m07-frb-demo-cleanup.md) |
| M08 | platform | 31 | 已审读保留，最终核对无阻塞；平台执行限制见下 | [基础边界](platform/review.md) |
| M09 | shared 组件与 Driver 诊断 | 27 | 全部已审读处理，定向与 unit 通过，完整 UI 已覆盖 | [共享组件](shared-components.md)、[Driver](driver/review.md) |
| M10 | shell（不含 sidebar） | 12 | 已审读处理，最新 deferred/graph 12 项通过 | [壳层](shell/review.md) |
| M11 | shell/sidebar | 12 | 已审读处理，完整 UI 已覆盖 | [壳层](shell/review.md) |
| M12 | conversation/workspace | 4 | 已审读处理，最新 deferred/graph 12 项通过 | [壳层](shell/review.md) |
| M13 | conversation/composer | 26 | 已审读处理，输入交互 33 项分次通过 | [输入交互](conversation-input/README.md) |
| M14 | conversation/interactions | 16 | 已审读处理，输入交互 33 项分次通过 | [输入交互](conversation-input/README.md) |
| M15 | conversation/timeline（不含 tools） | 76 | 已处理，冻结诊断返修及独立复核通过 | [时间线](timeline/review.md) |
| M16 | conversation/timeline/tools | 56 | 已处理，局部回归及独立复核通过 | [时间线](timeline/review.md) |
| M17 | conversation/acp | 36 | 已审读处理，审批异步隔离与输入交互回归通过 | [输入交互](conversation-input/README.md) |
| M18 | status | 8 | 已审读处理，定向测试及官方预览通过 | [壳层](shell/review.md) |
| M19 | todo | 1 | 已审读处理，deferred Todo 定向通过 | [壳层](shell/review.md) |
| M20 | update | 6 | 已审读处理，11 项回归及 320px/1.5× 官方预览通过 | [更新](update.md) |
| M21 | modes | 15 | 已审读处理，79 项联合及官方修后预览通过 | [模式编辑器](modes/quality-review.md) |
| M22 | settings（不含 accounts、statistics） | 36 | 已审读处理，Bot 真实菜单动作在 30 项联合回归通过 | [设置](settings/cleanup-review.md) |
| M23 | settings/accounts | 48 | 已审读处理，Gemini／焦点回归与官方预览通过，长状态候选未复现 | [账号与模型](accounts/review.md) |
| M24 | settings/statistics | 11 | 已审读，保留现有语义 | [统计](statistics/cleanup-review.md) |
| M25 | anywork_previews | 31 | 31 基线全部审读且集合对齐，必要官方观察及三处 host 修后复验通过 | [预览覆盖](previews.md) |
| B01 | packages/cross_cache | 7 | 已审读处理，保留覆写；Web 3 项与官方 6 轮生命周期通过 | [覆写依据](cross-cache.md) |
| B02 | tool / integration_test / test | 4 / 32 / 157 | 全部基线全文审读，T01–T09 已落实，完整 UI 已覆盖 | [测试边界](testing/review.md) |

## 问题与处理

| 编号 | 线索与证据 | 状态 |
| --- | --- | --- |
| F01 | 账号、侧栏、模型和会话菜单重复触发／焦点节点组合 | 已扩展到输入、壳层、状态及 Bot 菜单，菜单交互由 StudioMenuButton 共用官方锚点 |
| F02 | 模式画布 `_syncSelection` 在选择后恢复 `previousFocus` | 已用公开 canRequestFocus 抑制同步请求，较新输入焦点回归通过 |
| F03 | Native 账号编辑外层维护行定位、焦点代次和帧后回调 | 已移入模型行组件并使用官方遍历 helper，重排／IME／目标切换回归通过 |
| F04 | Demo、时间线 owner、FRB 及账号 VM 的多职责大文件 | 按职责审查，行数不作为缺陷依据 |
| F05 | 旧 Composer/Diagnostics/Usage/Activity 投影无生产调用 | 已删除完整旧链及专属自测，见 M04 |
| F06 | 本地 cross_cache 覆写用于 XFile.fileSystem 与解码异常清理 | 最新上游 1.1.1 两处缺口仍在，保留覆写，见 B01 |

## 共同约定与依据

- 组件消费不可变呈现和类型化动作；Client／业务资源的所有权不随纯界面拆分改变。
- 官方组件需要的稳定 FocusNode 属于组件局部资源；清理的是额外的焦点恢复、镜像菜单状态和外层补丁。
- 历史代码删除核对直接及间接使用者。现役数据迁移、外部协议适配和平台条件实现不能按关键词删除。
- 先复用官方组件与现有抽象，核对锁定版本契约。当前基础环境：Flutter 3.50.0 / Dart 3.14.0。
- [Flutter 架构建议](https://docs.flutter.dev/app-architecture/recommendations)、[焦点系统](https://docs.flutter.dev/ui/interactivity/focus)、[MenuAnchor](https://api.flutter.dev/flutter/material/MenuAnchor-class.html)。
- 项目分工及事实源见[前端状态与资源](../../../design/25-frontend-state.md)、[界面契约](../../../design/19-studio-ui.md)。

## 覆盖对照与新增／删除

基线 507 个应用文件、31 个预览文件均能对应模块全文审读记录；B02 的 189 个测试／integration 基线逐项对照 Git 树，无缺项、多记或重复。集合核对只证明记录闭合，全文结论来自各批连续审读。

原交付应用手写文件 516 个（新增 10、删除 1），本次分层后为 519 个（相对原审读基线新增 13、删除 1）；预览仍为 32 个（新增 1）。待办／工作流读取迁到时间线状态适配，图查询、连接器与纯绘图拆分，Gemini 纯转换独立；共享品牌与菜单仅迁移路径，数量不变。原有新增领域下载接口、HistoryWorkRangeMembers、路径复制按钮、LSP 展示 part、更新反馈及 workflow/numeric 转换均保留实际消费者，旧 `timeline_wait_indicator.dart` 已退出。

原交付的高风险差异、删除项及 18 个新增测试／support 文件均已独立复核；原 ACP 取消返修也已接受，证据继续有效。本次新增 4 个单元测试文件，B02 ledger 现为 189 基线 + 22 新增 = 211 条记录，保留两条已删除文件的审读记录，实际文件 209 个；四个 tool 和七个 cross_cache 源文件的原审读不变。本次增量独立复核与合并版本结果以下述后续记录为准，不将原全量执行外推为本次重跑。

## 验证

已完成两次 `cargo xtask generate-gui`，最新一次包含所有 ARB／Freezed／Riverpod 输入，exit 0；FRB 绑定及 Client 源码无差异。依赖版本未升级，应用锁文件只把 cross_cache 的直接依赖分类改为 direct dev，以显式支持新增 Web 回归；预览和 Client 锁文件不变。

| 检查 | 实际结果与边界 |
| --- | --- |
| 完整 `cargo flutter test --no-pub test/unit` | 438 项通过；执行于 T05 新增回归之前，之后以 Native 受影响文件 5 项、ACP 取消验收 3 项分次定向通过补齐。 |
| T05 额度 repository 定向 | `settings_account_usage_queries_adapter_test.dart` 5 项通过。快速完成不依赖 querying 帧，失败和旧配置结果不会复用旧成功。 |
| T05 ACP 取消验收 | `acp_usage_refresh_acceptance_test.dart` 3 项通过，真实服务／命令板驱动两种取消时序及同秒快速成功；helper、测试和真实登录入口三文件 `cargo dart analyze` 为 No issues。 |
| 共享／状态 | 菜单与 Unicode 头像 14 项、Native/ACP 状态另 14 项通过。 |
| 账号／模式 | 六文件首批联合 79 项通过；真实 ACP service 同步失败另 1 项通过。typed Gemini 和 Bot／计划／workflow／completion 等后续 7 文件联合 30 项通过。 |
| 时间线 | 首批 21 项；冻结坏 metadata 修后 18 项通过，独立复核接受。 |
| FRB／Demo | 71 项通过；共享 workflow/numeric 转换与既有 ACP 映射另 30 项通过，独立复核接受。 |
| 输入／交互／ACP | 6 + 25 + 2，共 33 项分次通过；保留首次着色器资产冲突及测试语义读取失败的修复记录。 |
| 壳层异步状态 | deferred Todo/workflow、Native 图乱序、ACP 换 Thread／canonical 图共 12 项通过。 |
| 更新 | 11 项定向通过，官方 320×420／1.5× 预览正常。 |
| Web cache | 真实 Chrome IndexedDB 3 项通过；官方 Previewer 修后连续 6 轮快速卸载无缓存异常。 |
| Linux X11 窗口 helper | 自有隔离窗口的跨 DISPLAY 分配、同 DISPLAY、认证失败三路径均 exit 0，几何和进程回收已独立核验。 |
| 最终应用分析 | `cargo flutter analyze --no-pub`：No issues，exit 0；初次一条多余导入已修。 |
| 完整 UI | 首轮 `cargo flutter test --no-pub test/ui`：580 通过、2 失败；两处旧 finder 已同步，两个完整测试名过滤复验均通过（exit 0），相关文件 LSP 0。失败原日志保留，未重跑其余 580 项。 |
| 最终预览分析 | 官方 `flutter analyze --no-pub`，No issues，exit 0。 |
| 官方 Widget Previewer | Gemini、更新、状态栏、侧栏及工作流已观察；三项 host 修后复验通过，账号长状态候选未复现。截图已核对，服务已回收，见 [预览记录](previews.md)。 |

各定向批次存在覆盖重叠，不相加成独立总测试数。当前 Linux 的 unit/UI/Chrome 证据不外推 Windows、macOS、真实供应商登录／load／计费、系统 IME、托盘或完整原生 GUI。未修改 Client/Rust 业务源码，没有为扩大覆盖另跑真实供应商或全后端套件。X11 窄验证不等同堆泄漏分析；工作流 RPC 无后端图版本回执，当前保护的是本地请求身份与迟到隔离。

## PR #596 后续：前端边界重构与测试下沉

原 CI 的合并版本重复导入已由 `c582c5c37` 修复。随后 run `45636012380` 的前端分析通过，但边界检查报告 8 项 UI-02：延迟字段适配放在纯工作区目录、账号菜单引用未分类的共享路径、三个预览引用业务投影。该轮 Native lifecycle 与三个 Desktop 分片通过；这些原生结果属于该轮版本。

本次沿调用链统一直接／延迟字段选择，分离工作流图的纯 View、状态查询与 Native／ACP Connector；Gemini 纯转换供生产和交互预览直接复用；品牌和菜单迁入受检查的 `shared/widgets/`。检查器沿用现有 AST 及导入闭包，删除品牌单文件例外，并检查共享纯组件自己的传递依赖。旧入口及消费者同时迁移，资源 owner 与 RPC 的既有协议限制不变。

测试按行为下沉与去重，映射见[测试清理](testing-cleanup.md#pr-596-分层后的测试下沉)。首批共享边界／首字母／菜单联合 94 项通过；Gemini 与账号 VM 联合 52 项通过，补强后仅分类用例复验 1 项通过。运行字段与图查询的首轮单元测试还暴露了工作流相等比较忽略图身份字段的真实问题，正在对应状态适配边界修复；该首轮失败不记为通过。

已取得最新主分支 `9445c81de`，原分支 HEAD 与它的真实合并树可正常构造。本次重构最终版本的整合检查、独立复核与远端 CI 仍待完成；品牌资源迁移及主分支全图标加载测试将随实际整合保留。
