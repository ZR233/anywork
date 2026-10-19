# Timeline 活动分组：原生运行截图

源码提交：[248816e31963711d5efb7f9cb5388356170adbd5](https://github.com/ZR233/anywork/commit/248816e31963711d5efb7f9cb5388356170adbd5)。对应 PR #105。
本分支是独立截图证据，不属于功能 PR 的源码差异。PNG 均为原始窗口截图，无图片合成或裁改。

截图来自清洁源码的 Linux 原生 GUI、真实 Rust bridge 与隔离合成数据根。
重连截图来自 `cargo xtask manual-gui --scenario websocket-recovery`；其余截图来自
该提交冷重开留存的 `tool-scroll` 会话（`cargo xtask run-gui --driver --profile`）。
冷重开先临时移走本次隔离数据根中的合成 PNG 资源，观察真实附件读取失败，再原样恢复并点击重试；
资源内容逐字节核对一致，九次原始工具调用和附件身份保留。所有操作均经 Flutter Driver。

实施期间完整 `tool-scroll` 旅程核对逐调用身份、连续三图、行回收后展开意图、全文读取/复制、
标准反向列表几何、内外滚动与短屏分页。最终提交的 `stress-body` 旅程核对流式长正文、冻结、
选择复制、详情读取及会话往返。重连旅程核对两次 WS 失败后 HTTP 恢复、取消、后续 Turn、
冷重开、持久化原始记录和两个 GUI 生命周期回收。脚本检查通过，人工结论保持待评审。

Linux 本地项目/X11 是本次原生覆盖范围；Windows 原生 GUI、SSH 项目和真实供应商未在此运行。
各 PNG 的 SHA-256 与尺寸见 manifest.json。
