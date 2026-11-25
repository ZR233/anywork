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
| `state/account_gemini_connection.dart` | `projectGeminiConnection` 的纯 Dart 呈现转换；只依赖 `account_presentations`，负责 protocol、真实 URI、template 优先级和 preset 分类 |
| `view_models/account_projection.dart` | 保留其他账号业务映射；不再承载 Gemini 呈现转换 |
| `view_models/account_editor_view_model.dart` | 从当前 draft、模板及目录派生资格和能力 |
| `views/native_account_editor_view.dart` | 按可空呈现装配指导区 |
| `widgets/account_editor_fields.dart` | 按类型化 mode 选择凭据标签 |
| `widgets/account_gemini_connection.dart` | 消费类型化值，删除文字分类、URL 常量及标准化 |
| 账号预览 fixture／host／注册入口 | 直接导入同一纯转换；模板或端点编辑后更新合成呈现；增加无模板、自定义和缺失模板场景 |

纯规则测试集中在 `test/unit/account_gemini_connection_test.dart`：`accounts_view_models_test.dart` 保留真实 VM 的 raw／dirty／canSave 与目录能力映射证据，并承载 `ManualModelDraft` 的 wireApi／connection 规则；`gemini_account_editor_test.dart` 只保留真实表单呈现、模板切换、preset 输入、键盘／焦点和品牌资源信号。endpoint 分类及 ManualModelDraft 的纯 `test` 均已从 UI 下沉。当前集成测试目录没有 Gemini 对应重复用例，未删除集成测试。

端点预设使用现有 `material_ui 1.11.0` 的 `ChoiceChip`，保留品牌颜色、圆角和回调；删除手拼 `Semantics`、选中图标和 `InkWell`，选择、禁用及键盘交互交给官方组件实现。已核对锁定源码的 `selected`／`onSelected` 合同，保存中用空回调禁用。保存、删除、dirty、Client 命令和凭据行为不属于此次分类修复的改动。

## 验证状态

修前已运行新增 widget 用例 `Google text outside the host does not identify an official endpoint`：退出码 1，期望“自定义端点”出现一次，实际为零，证明了整段 URL 分类的误判。

迁移后运行 `cargo flutter test --no-pub test/unit/account_gemini_connection_test.dart test/unit/accounts_view_models_test.dart`，退出码 0；根核对原始日志终态为 `+52: All tests passed!`，即 52 项通过。补充真实官方 host 上的 userinfo、query 和显式 `:443` 边界后，仅定向复跑分类用例，1 项通过；该用例与原批次重叠，不累加总数。UI、应用／预览联合分析与真实合并版本验收另由总台账记录。
