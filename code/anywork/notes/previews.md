# M25 独立预览覆盖与实际观察

基线 `code/anywork_previews/lib/` 共 31 个 Dart 文件，已按下表归属全文审读。与 Git 基线逐个核对文件名，未发现缺项；基线无删除文件。新增 `conversation/interactions/previews/interaction_previews.dart` 单独记录，不计入 31 的分母。官方工具报告的 21 个带注册入口的文件不等于整个预览包的文件数，合成数据与 host 文件也属于审读范围。

| 路径（相对 `lib/src/features/`） | 基线文件数 | 全文审读记录 |
| --- | ---: | --- |
| conversation/acp/previews | 5 | [输入交互](conversation-input/review.md) |
| conversation/composer/previews | 1 | [输入交互](conversation-input/review.md) |
| conversation/timeline/previews | 10 | [时间线预览](timeline/previews.md) |
| conversation/workspace/previews | 1 | [壳层](shell/review.md) |
| modes/previews | 1 | [模式编辑器](modes/quality-review.md) |
| settings/accounts/previews | 7 | [账号](accounts/review.md) |
| settings/statistics/previews | 2 | [统计](statistics/cleanup-review.md) |
| shell/previews | 2 | [壳层](shell/review.md) |
| status/previews | 1 | [壳层](shell/review.md) |
| update/previews | 1 | [更新](update.md) |

新增交互预览装配真实 `UserInputView`，只持合成输入与局部启用开关，不创建 Client/AppGraph。生产菜单、问题选择及模式表单继续使用同一公开组件。

## 官方 Widget Previewer 实际证据

载体为 Linux 上的官方 `cargo xtask preview-gui --headless --no-devtools` 与 Chrome。成熟浏览器工具仅通过 CDP 附着 Flutter 持有的浏览器。场景均为合成组件，不覆盖真实 bridge、持久化、供应商登录、系统窗口或其他平台。截图与完整日志保留于会话交付物，不提交源码。

| 场景 | 尺寸／字号 | 实际结果 |
| --- | --- | --- |
| Gemini 无模板、自定义 endpoint | 420px，1.3× | 真实 URL host 与 query 中 Google 文本正确区分；点击官方预设后 URL、指导组和 ChoiceChip 勾选一致，主代理已核对前后图。 |
| 可安装更新 | 320×420，1.5× | 说明、错误与两项操作完整，无溢出；主代理已核对截图。 |
| 底部状态栏窄窗 | 320×560 | context 环、吞吐量与操作条正常，无溢出或运行时错误。 |
| 底部状态栏深色组件压力场景 | 800×560 | 环及已启动项菜单正常，Escape 关闭；这是借用暗色基础 Theme 的合成检查，现有亮色产品语义色在暗底偏暗，不作为完整产品深色主题验收。 |
| 问题多选窄窗大字 | 360×720，1.6× | 首次本地化 delegate 缺失已修；复验正常，鼠标多选、Shift+Tab／Space 切换及禁用再启用后的文字／选择保留均实际观察。 |
| Composer 运行期附件菜单 | 380×460，2× | 外层预览壳 ListTileTheme 漏入问题已修；复验菜单文字与亮底清晰，Escape 关闭正常，无溢出。 |
| 侧栏紧凑 | 300×900 | 行、筛选与底栏可读；会话菜单打开及 Escape 关闭正常，无溢出。 |
| 模式阶段编辑 | 360×760 | ListTileTheme 漏入已修，复验 SwitchListTile／转换行恢复亮底，输入与 Tab 聚焦正常；当前初始阶段开关按场景禁用。 |
| ACP 账号英文状态 | 960px，1.0×／1.3× | “Preparing managed connection” 在两组均单行完整可读、无溢出；未复现静态审读候选，不据此修改生产布局。 |
| Native 工作流分栏 | 1280×800 | 节点、连接、当前阶段和切换条完整，无溢出。该图不是模式编辑器画布；后者焦点语义由真实 widget 回归保护。 |

预览壳可以在内层 `MaterialApp` 之外提供显式 `ListTileTheme`。仅设置内层 `ThemeData` 无法覆盖该 inherited widget，因此相关 host 在 `MaterialApp.builder` 内重设 `Theme.of(context).listTileTheme`，保持产品主题归属；没有改生产颜色或另造 UI。

切换筛选还发现本地 Web cache 打开期间关闭产生未处理错误。已修原生命周期，真实 Chrome 的 3 项 IndexedDB 回归通过；浏览器确认加载新产物后连续 6 轮快速筛选/卸载，CDP 异常和页面错误均为 0，详见 [缓存边界](cross-cache.md)。预览进程各轮均有终态及后代回收核查，不以浏览器窗口消失代替服务退出。

修后四组截图已由主代理逐图核对，浏览器错误记录为空。最初自动化曾因 Flutter 动态语义搜索框焦点定位失败而超时，并把搜索文字输入另一合成预览的临时文本框；修正实际聚焦后重新取得目标证据，该工具失败不冒称组件缺陷。最后一轮官方入口正常 exit 0，输出 Application finished，核对所属 PID/starttime 和三个端口均已回收。
