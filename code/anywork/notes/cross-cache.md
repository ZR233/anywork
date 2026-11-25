# B01 本地 cross_cache 覆写

本地包的 7 个 Dart 文件已全部全文审读，另读 pubspec 与 MIT LICENSE。保留现有覆写，并修复官方预览实际暴露的 Web 缓存关闭竞态。应用为浏览器回归显式声明同版本的测试依赖；没有升级包版本，锁文件仅改变该包的依赖分类。

## 逐文件决定

路径相对于 `packages/cross_cache/`。

| 文件 | 审读结论 |
| --- | --- |
| lib/cross_cache.dart | 两个现役导出，flutter_chat_ui 通过此入口消费；保留。 |
| lib/src/cross_cache.dart | 缓存读取、asset/data URI/网络/本地文件/base64 分流，以及显式 Dio 与 Cache 释放。保留上游流程；本地 XFile.fileSystem 适配当前 cross_file 0.4 API。 |
| lib/src/cached_network_image.dart | ImageProvider 下载、chunk stream、图片解码与异常缓存清理。保留 `return await decode(...)`：让异步解码失败进入本方法 catch，触发 imageCache.evict；finally 在解码结算后关闭 chunk stream。 |
| lib/src/cache/base_cache.dart | 各平台存储接口，均被条件实现使用，保留。 |
| lib/src/cache/cache.dart | 不支持平台的明确失败实现，属于条件导入边界，不能按无普通调用删除。 |
| lib/src/cache/io.dart | 当前桌面使用的 SHA-256 文件缓存、缺失异常、删除与重命名。与上游逐字相同；本轮保持既有缓存位置及内容，避免给薄适配额外扩张维护面。 |
| lib/src/cache/html.dart | IndexedDB 的初始化、事务和释放，属于预览/web 条件边界。修复构造时无消费者的打开任务及关闭后的迟到连接；保留平台实现。 |

## 上游与真实消费者

- 应用不直接 import cross_cache，但锁定的 `flutter_chat_ui 2.12.0` 的 `chat.dart` 与 `avatar.dart` 直接导入。Chat 初始化真实 CrossCache，故不能因为应用目录无 import 就移除依赖链。
- 实际读取 [pub.dev API](https://pub.dev/api/packages/cross_cache) 和当前镜像 API，两者最新版本均为 **1.1.1**，发布包清单仍声明 `cross_file: ^0.3.5+1`。
- 下载 [官方 1.1.1 发布归档](https://pub.dev/api/archives/cross_cache-1.1.1.tar.gz)，核对包 API 给出的 SHA-256 后只读比较七文件；临时包保留会话 scratch，不提交。
- 官方 changelog 的 1.1.1 说明是 Material UI import 与依赖调整；实际 `lib/src/cross_cache.dart` 仍调用 `XFile(source)`。本地该文件与发布包的唯一差异为 `XFile.fileSystem(path: source)`。
- 初次比较时，本地 `cached_network_image.dart` 与上游的唯一差异是解码 `return await`，其余五个 Dart 文件逐字一致。后续浏览器观察又确认 `html.dart` 的生命周期缺陷，处理见下文。
- 当前 `desktop_drop 0.9.2` 的已安装 pubspec 明确要求 `cross_file: ^0.4.0`。与上游 cross_cache 的 `^0.3.5+1` 无交集；不能直接删除 path override，也不能只覆写版本并保留旧构造调用。

## Web 打开与关闭的生命周期

官方 Widget Previewer 切换过滤条件、卸载 Chat 时，原实现在 `dispose` 中给可能无人等待的 Completer 调用 `completeError`，产生未处理的 `Cache disposed during open`。正在打开的 IndexedDB 连接迟到后，还会写回已经关闭的缓存对象。`flutter_chat_ui` 按自身拥有权释放内部 CrossCache 是正确调用方，不能通过取消释放或屏蔽浏览器错误规避。

现改为首次真实读写才打开数据库，并由这些操作共享打开 Future、接收原始失败。关闭只撤销使用资格并关闭已有连接；迟到的连接立即关闭，再将 disposed 错误返回等待操作。升级回调只创建 store，不提前发布尚未打开完成的数据库。事务使用操作取得的连接，继续遵循锁定 `idb_shim 2.11.3` 的 `Database.close` 契约：已启动事务完成后关闭，关闭后拒绝新事务。未增加缓存框架、重试或静默 fallback。

## 验证与后续删除条件

本次完成实际逐文件审读、发布 API 与归档核对、已解析依赖和消费者核查。新增 `test/web/cross_cache_lifecycle_test.dart` 使用真实浏览器 IndexedDB，覆盖未使用即关闭、打开中关闭的多个等待者、关闭后拒绝重开，以及读写/重命名/删除。`CHROME_EXECUTABLE=/usr/bin/google-chrome cargo flutter test --no-pub --platform chrome test/web/cross_cache_lifecycle_test.dart` 实际 exit 0，3 项通过。官方 Previewer 先复现原未处理错误，再核对浏览器加载的新产物，并连续 6 轮筛选/快速卸载；CDP 异常和页面错误均为 0。未运行跨平台磁盘缓存验收。

当上游正式支持 cross_file 0.4，并具备异步解码失败清理与 Web 打开/关闭的正确生命周期后，可以同时移除应用和预览包的 path override、删除本地副本，并通过标准 Pub 解析更新两份锁文件。不能仅根据版本号增加就假定这些缺口均已修复。
