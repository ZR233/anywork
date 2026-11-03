# 项目组件预览入口

通用 `@Preview`、主题、尺寸与交互方法使用用户级官方 `flutter-add-widget-preview`；
布局问题使用 `flutter-fix-layout-issues`，测试使用 `flutter-add-widget-test`。这里只维护项目差异。

从仓库根目录运行：

```bash
cargo xtask preview-gui --headless --no-devtools
# 查看当前 SDK 支持的参数，不准备依赖或缓存：
cargo xtask preview-gui --help -v
```

- 入口先以 `pub get --enforce-lockfile` 准备应用，再将应用的有效 `dependency_overrides`
  写入官方 `.widget_preview/pubspec_overrides.yaml`，本地包路径转为绝对路径。
  应用 `pubspec_overrides.yaml` 中显式覆盖的字段遵循 Pub 的替换语义；不要手改生成的缓存配置。
- 编译、发现、缓存和热更新由官方工具负责。首次失败留下不完整 scaffold 时，在停止所属服务后
  使用 `cargo flutter widget-preview clean`，再运行同一入口；不修改 SDK 或 manifest 哈希。
- 复用生产纯 View、主题、本地化和不可变合成数据，不在预览创建 AppGraph、Client、FRB 或第二套 UI。
  官方工具会编译全部已发现入口，搜索筛选不能隔离原生依赖。生成输入变化先走 `generate-gui`。
- 官方浏览器模式支持无头运行；浏览器可通过 `CHROME_EXECUTABLE` 指定真实安装路径。
  `--web-server` 是服务模式，其完整热更新调试依赖浏览器扩展，不能仅凭刷新页面证明热重载。
- 先固定场景、实际视口、主题及字号，操作后核对真实画面；中文后备字体需完成加载。
  优先复用同次运行的热更新。验证热更新应观察实际源码改动对应的页面变化，临时探针立即恢复。
- 截图使用当前可用浏览器工具，产物留在本次证据目录。组件预览是合成视觉证据；业务、原生插件
  和持久化使用 `manual-gui --preset gui --inspect` 或 `test-project`，不把概念稿当实现证据。
- 正常结束或取消后等待命令终态，核对所属 Flutter、分析服务、DTD 和浏览器退出。
  附着的浏览器工具只关闭自身连接，最终浏览器由启动者回收；不得占用 `1420`。
