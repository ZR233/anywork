# 计划工作区：PR 展示与视觉验收

这些图片是计划工作区重构的文档展示资产，不是自动化 golden。全部来自同一次成功的
Linux/X11 原生 `plan-recovery` 流程，使用隔离数据根、真实 bridge 和本地严格 fixture；
界面为中文，计划正文与反馈为合成英文样例，不含真实用户数据、凭据或调试地址。

| 完整窗口截图 | 展示内容 |
| --- | --- |
| [01-pending-split.png](01-pending-split.png) | 待确认计划、独立阅读区与替换式反馈栏 |
| [02-wide-plan.png](02-wide-plan.png) | 计划宽于会话阅读区域的一半，对话仍保留 400px |
| [03-full-width.png](03-full-width.png) | 展开阅读，保留反馈与恢复并排入口 |
| [04-narrow-short.png](04-narrow-short.png) | 640×620 窄短窗，全宽正文与完整底部操作 |
| [05-expanded-receipts.png](05-expanded-receipts.png) | 修改与批准回执同时展开，保留原始修改意见 |
| [06-approved-readonly.png](06-approved-readonly.png) | 从菜单重开已批准计划，只读正文与历史回执并存 |

## 验收结果与边界

主代理已逐张打开以上图片进行视觉复核：标题、状态、正文与操作层级清楚，主题和字体一致，
在所示尺寸中无可见布局溢出或操作遮挡；窄窗仍可输入反馈和批准。修改回执展开后能完整读取
原文，批准后恢复普通 composer，当前计划可按需只读查看。**本次人工视觉复核通过**。

对应原生旅程退出码为 0，first / restart / recheck 分别 7 / 24 / 51 项检查全部通过。
严格 fixture 接受 10 次请求、拒绝 0 次，所有必需步骤消费完成；GUI 未处理异常为 0，三个
生命周期均正常 shutdown，本工作区所属验收进程已回收。修订后还核对到 1 条 pending 计划行
与 1 条保留的旧修改回执行，避免把正确历史误判为重复待确认卡片。

原始证据位于忽略目录 `target/manual-gui/plan-workspace-verified`。harness 的默认
`humanVerdict: pending` 不代表人工判断；上文是独立的视觉复核结论。原始日志、快照、一次性
脚本不随文档提交。

原生交互只在 Linux/X11 实测，本地 fixture 不代表真实线上供应商兼容，也不代表 Windows
GUI 人工验收通过。物理按键和 IBus 组词另在共享 composer 实测；计划反馈栏的 Enter / 换行
由原生框架输入路径与 adapter 回归覆盖，不将前者冒称为后者的独立物理 IME 实测。
