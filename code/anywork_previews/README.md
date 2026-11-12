# anywork 组件预览

本开发包持有官方 `@Preview` 入口和合成数据，引用 `anywork` 的生产组件、主题与本地化。
它不启动 AppGraph、FRB 或模型服务。独立分析根使实时预览扫描只遍历预览源码，
应用源码、测试和生成文件继续由应用的完整静态检查覆盖。

从仓库根运行 `cargo xtask preview-gui --headless --no-devtools`。这个入口只做标准 Pub
依赖准备，然后把参数和终端输入输出交给官方 Flutter；不实现预览发现、reload 或交互命令。
依赖已准备后，也可以在本目录直接运行 `flutter widget-preview start --headless --no-devtools`。
清理 scaffold 或调整覆盖后重新运行一次项目准备入口。
只想准备后交给官方 CLI 时，可先从仓库根执行
`cargo xtask preview-gui --no-launch-previewer`；这是透传给 Flutter 的官方参数，项目包装会退出。

预览包和官方生成的 scaffold 都是独立 Pub 根。此包的 `dependency_overrides` 显式选择与
应用相同的本地缓存实现和 diff 版本；项目准备入口仅将预览根的有效覆盖传给 scaffold，
不修改 SDK、缓存 manifest 或全局依赖。两个源码包的 `pubspec.lock` 都纳入版本管理。

应用测试通过 dev dependency 复用这些入口和素材，生产代码不依赖本包。
组件边界和 UI 对 FRB 的隔离检查同样覆盖这里的源码。
