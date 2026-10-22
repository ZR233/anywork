# 飞书 Markdown / 流式卡片：本地原生界面证据

本分支只保存已脱敏的合成截图，不包含应用源码、原始日志、凭据、二维码或私聊内容，不参与产品分发。

环境：Linux / Xvfb，`cargo xtask manual-gui --scenario gui --bots-fixture`，真实 Flutter/FRB/Studio runtime 与本地隔离模型/飞书 peer。截图通过 Flutter Driver 获取并实际查看。

| 图片 | 证明范围 |
| --- | --- |
| [01-permissions.png](01-permissions.png) | 新建机器人显示七项权限，保留 `im:resource` 并新增 `cardkit:card:write` |
| [03-streaming.png](03-streaming.png) | 同一回复正文生成中；截图前后快照均为非终态，界面仍为 Responding |
| [04-completed.png](04-completed.png) | 同一回复完成，261 UTF-8 字节已保存，标题、粗体、链接、列表、代码块和表格可见 |

流程包括模拟注册连接、未授权输入仅配对、GUI 显式批准、独立新输入执行、Markdown 生成中与完成态。正常退出报告 `clean`、`persistence=drained`、`issues=[]`；peer listener/socket 已 join，模型请求 2 accepted / 0 rejected。

这些是 **anywork 本地界面截图**，不是飞书客户端截图，不证明真实租户授权或客户端渲染兼容。CardKit 创建、一次发送、递增更新、最终关闭与故障恢复由对应 PR 的独立协议观察记录证明，不能仅凭截图推断。
