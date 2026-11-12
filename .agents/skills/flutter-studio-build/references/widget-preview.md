# 项目组件预览入口

## 按目标选择无头入口

纯界面开发、局部交互和截图默认使用官方 Widget Previewer；项目入口为
`cargo xtask preview-gui --headless --no-devtools`，**不编译 Rust bridge**，不装配 Client/AppGraph
或模型服务，也不需要 X11/Xvfb。共同的准备、操作、取证及回收步骤见[无头实验指南](experiments.md)；
本页只维护项目预览适配。截图注明合成组件预览，不冒充原生持久化、系统窗口或性能。

通用 `@Preview`、主题、尺寸与交互方法使用用户级官方 `flutter-add-widget-preview`；
布局问题使用 `flutter-fix-layout-issues`，测试使用 `flutter-add-widget-test`。这里只维护项目差异。

从仓库根目录运行：

```bash
cargo xtask preview-gui --headless --no-devtools
# 查看当前 SDK 支持的参数，不准备依赖或缓存：
cargo xtask preview-gui --help -v
# 只做启动准备和官方发现，不启动浏览器（官方参数，原样透传）：
cargo xtask preview-gui --no-launch-previewer
# 随后也可直接使用官方命令，项目包装不驻留：
cd code/anywork_previews
flutter widget-preview start --headless --no-devtools
```

- `@Preview` 入口和合成数据位于 `code/anywork_previews/lib/`，只引用应用的生产组件、主题与本地化。
  这是独立 Pub 根，避免每次源码修改都对应用、测试和生成文件进行全量预览扫描；不通过增加
  Flutter 的查询超时或排除应用分析来掩盖扫描耗时。应用仅用 dev dependency 复用预览测试素材。
- 入口先以 `pub get --enforce-lockfile` 准备预览包，再将该包的有效 `dependency_overrides`
  写入其官方 `.widget_preview/pubspec_overrides.yaml`，本地包路径转为绝对路径。
  预览包的 `pubspec_overrides.yaml` 遵循 Pub 的字段替换语义。Pub 不继承依赖包的 overrides，
  因此预览包显式声明应用所需的本地 `cross_cache` 和 `diffutil_dart` 版本；不要手改缓存 manifest。
- 已有 scaffold 启动前由官方 Pub 刷新其依赖解析，使覆盖变化实际进入 `package_config.json`；
  只写 YAML 不代表已切换依赖。此步骤保留预览构建缓存，解析失败原样返回。
- 编译、发现、缓存和热更新由官方工具负责。首次失败留下不完整 scaffold 时，在停止所属服务后
  使用 `cargo flutter widget-preview clean ../anywork_previews`，再运行同一入口；不修改 SDK 或 manifest 哈希。
- 启动准备完成后，全部 CLI 参数及终端输入输出直接交给 Flutter，xtask 不处理 DTD 消息或 reload。也可以进入 `code/anywork_previews` 直接执行
  `flutter widget-preview start --headless --no-devtools`；更新依赖或清理 scaffold 后重新准备一次。
  通用 `--packages` 不解决该边界：当前 SDK 的预览编译固定读取 scaffold 自己的 package config。
- 出现 DTD 断连或 live updates 暂停警告时，先区分 daemon 连接与预览清单查询是否超时，
  不把警告文案直接当作进程已死。保留原 stdout/stderr；没有时间戳的双流不能倒推出先后因果。
  按当前 SDK 官方诊断参数有界取证，日志放本会话 scratch，不默认切换 legacy、延长超时或反复清缓存。
- 复用生产纯 View、主题、本地化和不可变合成数据，不在预览创建 AppGraph、Client、FRB 或第二套 UI。
  官方工具会编译全部已发现入口，搜索筛选不能隔离原生依赖。生成输入变化先走 `generate-gui`。
- 核对复合控件的完整外观时，挂载生产装配层或完整公开组件，包含选择器、工具栏和主操作等实际子树。
  未提供可选插槽的裸 View 只能证明局部外观，不能用其截图判定生产控件消失或宣称整体一致。
  重构前后对照固定相同配置、草稿、可用状态、视口、主题和字号，再比较布局与画面。
- 不为一次截图增加环境变量、字体加载脚本或专用测试入口；现有布局/交互回归继续通过
  `test/ui` 的正式装配执行。需要图片回归时使用官方 golden matcher，而不是另造 PNG 落盘协议。
- 官方浏览器模式支持无头运行；浏览器可通过 `CHROME_EXECUTABLE` 指定真实安装路径。
  `--web-server` 是服务模式，其完整热更新调试依赖浏览器扩展，不能仅凭刷新页面证明热重载。
- 先固定场景、实际视口、主题及字号，操作后核对真实画面；中文后备字体需完成加载。
  优先复用同次运行的热更新。验证热更新应观察实际源码改动对应的页面变化，临时探针立即恢复。
  预览壳的 padding、卡片工具栏与组件实际约束分别记录；完整组件预览须容纳真实内容，
  不把外层请求尺寸当作内部可用高度，也不通过裁剪或隐藏错误伪造布局通过。
- 截图使用当前支持的官方能力或成熟浏览器工具，不假定预览注册了 Driver extension。
  纯界面 PR 直接使用本次预览图片，无须额外构建原生程序；真实业务边界另行选择对应入口。
- 正常结束或取消后等待命令终态，核对所属 Flutter、分析服务、DTD 和浏览器退出。
  附着的浏览器工具只关闭自身连接，最终浏览器由启动者回收；不得占用 `1420`。
  当前 SDK 的预览命令未注册 `r`、`R`、`q` 终端处理器；热更新由文件监听或页面按钮触发。
  退出使用终端 `Ctrl+C` 或向已核实归属的 Flutter 进程发送官方退出信号并等待，
  不直接杀浏览器或用无差别进程清理代替启动者收束。
