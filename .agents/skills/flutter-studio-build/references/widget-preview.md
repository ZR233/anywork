# 官方 Widget Previewer 验证

## 按目标选择无头入口

界面设计对齐建议优先使用官方无头工具，不先为纯布局启动 X11/Xvfb：

- `flutter_test`／`WidgetTester` 适合生产组件的布局、溢出、可见性和交互断言；
  从仓库根目录用 `cargo flutter test <相关测试路径>`，需要独立图片回归时使用官方 golden matcher。
- Widget Previewer 适合对照设计参照核查排版、层级、主题和局部交互；当前 CLI 支持时用
  `cargo flutter widget-preview start --headless --no-devtools` 启动官方无头 Chrome，
  再用成熟浏览器工具截图或交互，不另造渲染/截图协议。
- 原生插件、FRB、持久化、真实窗口与进程退出不在上述证明范围内；有这些风险时补相应原生证据，
  不为换阶段或纯样式迭代重跑完整业务旅程。

先匹配参照故事、组件实际约束、字体、主题和展开态；浏览器画布与组件视口分别核对。
截图注明合成组件预览，不能代替明确要求的原生产品画面；测试虚拟时钟和预览耗时不证明原生性能。

官方依据：[Widget Previewer](https://docs.flutter.dev/tools/widget-previewer)、
[Widget 测试](https://docs.flutter.dev/cookbook/testing/widget/introduction)、
[`matchesGoldenFile`](https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html)。

## 入口与边界

- 先查看当前 Flutter 版本及 `cargo flutter widget-preview start --help -v`，核对实际参数，
  不依赖历史截图或别的版本 CLI。沿根目录包装入口运行，不在 Flutter SDK 目录执行项目命令。
- 纯入口只导出生产 View/Widget 与不可变呈现值；通过薄包装注入真实主题、本地化和合成数据，
  不创建 Client、Repository、ProviderScope 或原生 bridge，不复制一套预览 UI。
- 修改 Freezed、Riverpod、l10n 或 FRB 生成输入后先统一 `cargo xtask generate-gui`，
  再定向分析纯视图目录。缺少生成物与真实类型错误分开处理，不手改生成代码。
- 官方 `.widget_preview/` 是工具缓存，不提交截图、VM 地址或其生成源码；截图和探针属于
  当前 Thread 的 artifacts/scratch。临时目录可通过工具支持的参数或 `TMPDIR` 指向本会话目录。

## 依赖解析

预览 scaffold 是独立的 Pub 依赖解析根。Dart 不继承依赖包自身的 `dependency_overrides`，
因此应用能解析不代表预览根也能解析；先检查实际冲突、上游发布和现有补丁，不直接强制不兼容版本。
若需复用应用已批准的本地覆盖，在官方缓存根使用标准 `pubspec_overrides.yaml` 指向同一包，
不复制实现、不修改 Flutter SDK，不为了预览另造 package 或框架。项目当前准备步骤见
`code/anywork/README.md`，不要在 Skill 固化某个暂时的包版本。

首次依赖解析失败可能留下不完整 scaffold。确认无在用服务后使用官方
`cargo flutter widget-preview clean`，重新准备必要的覆盖配置，再启动；不要手改缓存 manifest
的哈希来跳过初始化。缓存根解析成功不证明应用锁文件未变化或应用依赖解析成功。

## 浏览器与热更新

- `--web-server` 适合手动打开实际输出地址，完整调试依赖 Dart Debug Chrome 扩展。
  无扩展的浏览器能显示组件，不等于热重载链路已验证；多个已关闭页面的调试连接超时应如实记录。
- 验证热更新优先让 Flutter 工具启动、连接 Chrome；当前 CLI 支持时，SSH 可用
  `cargo flutter widget-preview start --headless --no-devtools`。需要时将 `CHROME_EXECUTABLE`
  指向已确认的浏览器可执行文件，不能猜安装路径，也不占用 `1420`。
- 使用成熟浏览器工具截图或交互，不自造截图/调试协议。需要附着官方浏览器时，从该次实际
  日志或所属进程参数取得 CDP 地址；附着工具只释放自己的连接，浏览器最终由原启动者关闭。
- 预览是常驻服务：启动后在其运行期间完成浏览器附着、交互和取证，完成后再请求退出并等待终态，
  不先等命令超时再连接。Flutter/Dart 调试服务地址不是 Chrome CDP，须从本次浏览器参数确认。
- 热更新证明应包含实际源码变化、运行页面变化及恢复后的状态；仅重开网页看到新内容不算。
  临时探针修改需限定范围、立即恢复，并核对原文件哈希，不能把测试标记遗留在源码。
- 结束时发送实际支持的退出信号，等待工具终态，并核对所属 Flutter、分析服务、DTD、
  浏览器进程回收。请求取消不等于退出，不能误杀其他会话或用户浏览器。

## 视觉与交互取证

官方预览器自身也有主题和继承组件。若生产浅色主题内出现外层深色 ListTile 或其他样式，
亲读主题优先级和实际祖先链；必要时在薄预览包装中显式建立相应生产主题边界，
不改变产品配色来遮掩宿主样式泄漏，也不只凭 analyze 通过就认定视觉正确。

浏览器自动化应先读取实际 DOM/语义树再选定位器：Flutter 引擎元素名、角色、输入框标签
与菜单项名称随版本和状态变化，不能把脚本选择器错误当成产品缺陷。筛选场景后等待该场景
实际成为唯一预览，而不是只等某个通用按钮出现；截图须人工核对目标、尺寸、主题和布局。
薄包装若持有局部 State，按场景身份隔离；筛选切换不能带入另一场景的旧展示对象。
官方 Hot restart 可用于诊断初始态，但不能拿重启后的正确画面掩盖预览本身的身份复用缺陷。
CanvasKit 的后备字体加载不等同于 `document.fonts.ready`，新汉字短暂缺字时先检查网络和
稳定后的画面，不立刻改生产字体或引入字体包。

记录预览发现、Web 编译、主题/语言/资产、局部输入或回调、热更新与资源退出证据；
合成数据和仅本地动作必须明确标识。浏览器预览截图不是真实项目人工验收的图像证据来源；
原生 API、插件、存储、持久化和进程关闭仍使用 `manual-gui --preset` 或 `test-project`，
PNG 合同是 Flutter 内容捕获（`ext.anywork.capture`）。
