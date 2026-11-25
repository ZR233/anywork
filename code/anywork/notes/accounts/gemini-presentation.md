# Gemini 连接指导的类型化呈现

本记录属于 M23 账号模块。基线为 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`。账号执行者已全文审读账号生产和预览文件，父代理沿真实草稿、目录、View 与预览调用链完成本项收束。

## 问题与最终决定

原 View 通过展示用的协议文字和整段 URL 的 `contains` 判断 Gemini／Vertex 及官方端点。这样 `https://proxy.example/v1?upstream=aiplatform.googleapis.com` 也会被认为是 Google 官方地址。展示文字不是协议身份，URL 参数也不能证明实际主机。

现在 View 只消费 `AccountGeminiConnectionPresentation`。现有 editor VM 从当前草稿和规范目录派生这个不可变值，不增加草稿仓储、独立 Provider 或第二份业务状态。它描述连接指导和可用预设，不声称已经验证服务器、凭据或连接能力。

- `AccountGeminiGuidanceMode`：AI Studio 或 Vertex AI 的指导组。
- `AccountGeminiEndpointKind`：受支持的官方地址形式或自定义地址。
- `AccountGeminiEndpointPreset`：当前五个明确预设及其端点。
- `canSwitchMode`、`supportsModelDiscovery` 和 `hasBundledCatalog`：来自现有编辑资格和真实目录，View 不再从指导组名称猜能力。

## 派生规则与边界

| 输入 | 呈现规则 | 保留的业务行为 |
| --- | --- | --- |
| `protocol == 'gemini'` | 提供类型化 Gemini 指导；相似文案／相似 wire 不激活 | 不修改协议或保存资格 |
| 已知 `gemini`／`vertex-ai` 模板 ID | 保持对应指导组，即使当前端点自定义 | 模板切换仍走原 Connector／草稿命令 |
| 无模板或未知模板 ID | 根据 `Uri.tryParse` 的真实 host 选择指导组；未知主机沿用 AI Studio 指导 | 不把显示默认值写入草稿，不推导认证成功 |
| 官方地址 | HTTPS、无 userInfo、443、无 query／fragment，并匹配明确主机与 API 路径 | 未匹配时只显示自定义，不新增保存校验 |
| 无模板的现役 Gemini 账号 | 保留指导、凭据输入、预设及手动模型编辑 | 仍可按原规则保存 |
| 指定模板已从目录消失 | 保留原始草稿和指导 | 原 unknownTemplate 错误及不可保存资格保留 |

AI Studio 主机精确为 `generativelanguage.googleapis.com`，路径为 `/v1beta` 或 `/v1`。Vertex 支持 global 或合法区域形态的 `aiplatform.googleapis.com` 主机，路径为 `/v1/publishers/google` 或 `/v1beta1/publishers/google`。路径、查询、userinfo 或仿冒主机中的 Google 字样不会获得官方分类。

trim 和尾斜线归一化只用于预设选中和显示判断。端点原文、cursor／composing、dirty 判断及保存输入不被改写。此判断不检查网络或 DNS，也不是安全认证结果。

## 能力文案

模型发现来自模板的 `supportsModelDiscovery`；内置模型来自模板的 `modelCatalogId` 及真实目录内容。缺少模板时不凭指导组补造这些能力。

删除了由“官方端点”直接推导的隐式缓存 badge 及两语言无消费者文案。Client 中确实存在 `promptCacheDialect`，但它不等于当前端点、模型和请求必然使用隐式缓存；本次没有把它挪作端点分类依据，也没有修改协议缓存行为。

## 变更和调用方

| 文件 | 职责 |
| --- | --- |
| `state/account_presentations.dart` | 指导枚举、端点预设、Freezed 呈现输入及 editor 的可空连接呈现 |
| `view_models/account_projection.dart` | `projectGeminiConnection` 纯转换，唯一显示分类位置 |
| `view_models/account_editor_view_model.dart` | 从当前 draft、模板及目录派生资格和能力 |
| `views/native_account_editor_view.dart` | 按可空呈现装配指导区 |
| `widgets/account_editor_fields.dart` | 按类型化 mode 选择凭据标签 |
| `widgets/account_gemini_connection.dart` | 消费类型化值，删除文字分类、URL 常量及标准化 |
| 账号预览 fixture／host／注册入口 | 复用同一纯转换，模板或端点编辑后更新合成呈现；增加无模板、自定义和缺失模板场景 |

端点预设使用现有 `material_ui 1.11.0` 的 `ChoiceChip`，保留品牌颜色、圆角和回调；删除手拼 `Semantics`、选中图标和 `InkWell`，选择、禁用及键盘交互交给官方组件实现。已核对锁定源码的 `selected`／`onSelected` 合同，保存中用空回调禁用。保存、删除、dirty、Client 命令和凭据行为不属于此次分类修复的改动。

## 验证状态

修前已运行新增 widget 用例 `Google text outside the host does not identify an official endpoint`：退出码 1，期望“自定义端点”出现一次，实际为零，证明了整段 URL 分类的误判。

修后新增覆盖包括：真实 VM 的无模板／缺失模板账号、raw 与 dirty／canSave 保留、不产生写命令；纯转换覆盖多个结构化 URL、相似协议 wire 及模板指导优先。统一生成已成功。账号 VM/projector 所在测试在定向与完整 unit 438 项运行中通过；Gemini 编辑器、ChoiceChip 键盘/保存禁用回归在七文件联合 30 项运行中通过。官方预览的无模板/自定义端点场景（420px、1.3 倍文字）及预设点击后的 URL/指导组/选中态均已观察并由主代理核对。此前账号首批 79 项联合通过属于焦点、草稿及模式改动，不能代替本项修后证据。
