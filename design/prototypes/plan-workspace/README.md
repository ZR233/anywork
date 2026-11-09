# 实施计划交互设计稿

[打开原型](index.html)。直接用浏览器打开，无构建、CDN 或原生依赖。
本页沿用 `conversation-shared/preview.css` 的暹罗浅色主题变量，仅使用标准 HTML
表单、`details` 和 CSS 布局；不是第二套产品状态机，也不连接真实会话。
产品事实与授权边界以 [计划契约](../../13-plan.md) 为准。

## 设计重点

- 阅读和决定分开：详情只有阅读/关闭动作；待确认时才出现独立反馈栏。
- 待确认入口使用整卡可点击的文档卡，包含完整标题、阅读提示、图文状态和查看／收起动作；不在卡片重复放批准按钮。
- 完整会话工况不显示工具等待条和通用「交互详情」，卡片与底部反馈栏各司其职；关闭正文不会丢失修改草稿。
- 通用的「实施计划」头部与 Markdown 文档标题分层，避免同一标题重复出现。
- 状态徽标附带图形与文字，不只靠颜色区分。辅助说明短而明确，不暴露内部工具或阶段名。
- 输入与按钮共用边界，主次操作同高同基线；不足以同排时自然换行。
- 暖米色阅读面、棕色文字、细边框、既有系统字体，不增加装饰性阴影或新的品牌色。
- HTML 的导航、工况标题、设计注解和模拟数据说明位于组件外，生产界面不复制。

## 工况与可复现尺寸

使用 `?scenario=<id>&embed=1` 可隐藏设计页外框，只保留固定尺寸组件，供实际渲染对照。
配对截图固定合成正文、主题与字号；截图不是自动化 golden，也不证明原生持久化或审批成功。

| id | 工况 | 组件画布 |
| --- | --- | --- |
| `workspace` | 完整会话、计划卡与并排阅读，可收起重开 | 1200 × 820 |
| `drafting` | 起草、尚无正文 | 760 × 720 |
| `awaiting` | 等待确认、空修改意见 | 760 × 720 |
| `feedback` | 非空修改意见 | 760 × 720 |
| `submitting` | 在途禁用、原意见保留 | 760 × 720 |
| `error` | 原因可见、意见可重试 | 760 × 720 |
| `revision` | 请求修改、旧稿只读 | 760 × 720 |
| `approved` | 已批准、只读重开 | 760 × 720 |
| `full` | 全宽、舒适阅读列 | 1040 × 720 |
| `narrow` | 窄窗、自然换行 | 360 × 760 |
| `large` | 窄窗、1.5 倍文字 | 360 × 900 |
| `short` | 短窗、阅读与反馈可达 | 640 × 480 |
| `history` | 批准／修改／取消／其他已回答回执 | 760 × 720 |

设计说明中的尺寸是复现样例，不是设备类型或产品断点契约。原生页面仍由实际父约束布局；
生产主题、Markdown 排版与标准 Material 命中区域优先于浏览器控件的逐像素一致。

浏览器原生表单与折叠语义参考 [HTML Standard](https://html.spec.whatwg.org/multipage/interactive-elements.html)；
生产组件使用 Flutter 官方 [LayoutBuilder](https://api.flutter.dev/flutter/widgets/LayoutBuilder-class.html)、
[Wrap](https://api.flutter.dev/flutter/widgets/Wrap-class.html) 与
[Widget Previewer](https://docs.flutter.dev/tools/widget-previewer)，不引入新的布局库。
文档卡复用官方 [Card](https://api.flutter.dev/flutter/material/Card-class.html) 与
[InkWell](https://api.flutter.dev/flutter/material/InkWell-class.html) 的整卡交互语义。
