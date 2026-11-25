---
name: add-provider
description: Use when adding or changing an account template, vendor protocol adapter, or model catalog in 糊来帮's Account and ModelRuntime architecture.
metadata:
  category: guides
  platforms: ["windows", "linux", "macos"]
---

# 扩展账号模板与模型协议

相关入口为 AGENTS.md、design/06-model.md 和 design/20-config.md。账号是稳定 ID 的接入实例，
账号模板是创建默认值，厂商协议适配、Wire API（Chat Completions / Responses）与连接方式
（HTTP / WebSocket）是不同维度。不要把模板、显示名、endpoint 或裸 model_id 当成账号身份。

## 选型与分层

优先复用工作区已有 reqwest、SSE、WebSocket、typed codec 和目录能力；按根项目约定核实官方
文档、组件 API、目标平台及错误/取消契约。不能复用时先调研并取得用户对自研范围的明确选择，
不默认新增框架、wrapper、fallback 或 SDK。

模型执行只有 `ResolvedModelRoute -> ModelRuntime` 一条路径。`ProtocolId` 是开放的稳定标识，
产品通过静态 `ProtocolRegistry` 选择厂商 `Adapter`。派生协议在自己的 crate 声明端点默认值、
目录解析与归一化策略、指令角色、原生请求选项及服务。新增派生协议时在产品装配注册，
共享类型与执行器只消费已冻结的通用契约。Chat Completions 和 Responses 的线协议类型由
`pl-model-openai-wire` 持有。通用兼容端点用 OpenAI crate，端点能力独立声明。
异步重试、取消、连接、continuation、流和计量由唯一执行流程拥有；不使用 async_trait 或
隐藏 Future 的 Send。普通完成与原生压缩仅携带各自的调用级用途材料。

错误识别与 wire 编码通过 `Adapter` 组合：新供应商实现 `ProviderErrorPolicy` 并注册
`error_policy`；只有新增 wire 格式才扩展 `WireCodec`／`WireStreamDecoder`。策略借用载荷，
用供应商本地 typed DTO 解码，分别返回已识别分类、未识别和损坏结构；不能把三者压成 `None`。
HTTP、SSE、WS 都使用同一绑定策略。兼容协议不自动继承其他供应商的业务码，具体永久原因
优先于宽泛 HTTP 状态；不靠 URL、模型名或自然语言猜余额、权限或临时性质。
同时存在 `code` 与 `error.type` 时，应检查各字段中已识别的业务原因，不能用
`code.or(error_type)` 让未知子码遮住明确的永久类型；两个原始诊断字段都要保留。

完整且不依赖请求现场的本地错误转换可以实现 `From<LocalError> for ClassifiedProviderError`；
可能失败的结构解析返回 `Result`，阶段、请求标识、脱敏和接收时刻显式传给边界装配入口。
归一化后只传递 `ProviderFailure`，通过 `From<ProviderFailure>` 进入 `PureError`，上层不再
按原始 code 二次分类。不要用有损 `From` 丢弃用量、原失败或恢复失败，也不要使同步解码上下文
跨过不必要的异步等待。

供应商策略不等待、不发送请求、不操作预算。收到等待提示时固定单调 deadline，传递、连接
修复和回退不能重新计时或截短有效长提示。Usage 说明已知消耗，不单独决定外部副作用；
普通生成重试前必须按稳定子尝试身份交付已知事实，并在持久会话获得原 writer 保存确认。
托管动作、未知上传结果和已收到压缩结果仍按运行时资格停止重放。累计用量帧更新同一尝试
样本，失败代次的结算不能被最后成功结果覆盖。
用量是否终态来自 wire 事件的明确事实，不能从请求成功、字段齐全或非零计数推导；失败终态
可以包含最终用量，成功结果也可能没有用量。先提取坏帧中仍可独立解码的有效用量，再交付
协议失败；不要让空对象覆盖已有样本。标题、评审等辅助请求也须逐次结算并取得自身保存确认。
上传错误分类与提交结果分别表达：暂时服务错误不证明文件未创建；边界只在明确拒绝时释放
Pending，断联、读体失败和未知结果保留防重复提交保护，不能通过改写原 retry 性质表达停止。

`pl-model-auth::chatgpt` 持有 OAuth/OIDC、身份类型和刷新会话；OpenAI 协议持有 Codex wire 和配额查询。
Studio 拥有登录操作与受保护存储，协议在发送前使用已绑定的凭据能力。

原生 thinking、tool_stream、Files、搜索、缓存、余额、配额与远程压缩保留类型化能力边界。
Responses 兼容不自动意味着支持这些能力；自定义地址的服务能力撤销规则遵循权威设计。

## 扩展涉及的边界

以下按职责组织，不是每次修改都要依次执行的步骤。

1. **账号模板**：在唯一模板目录声明默认 endpoint、厂商协议、凭据提示、模型目录和推荐选择。
   现有模板可重复创建账号，账号名默认取模板展示名，账号 ID 只分配一次；不增加第二套 GUI 默认值。
2. **模型定义与绑定**：定义元数据、能力和参数声明；绑定 wire API、连接矩阵、请求/媒体编码、
   参数 wire 与价格。内置目录用 Rust 类型声明，共用家族预设。较多模型放在 `models/`，每个模型一个模块。
   未知值保持未知，不从模型名、URL 或厂商名称猜测能力。
3. **目录解析**：按各家官方接口解释 envelope、字段、单位与明确/缺失/null/空集合。
   OpenAI/Codex 富声明不自动适用于 DeepSeek 或 xAI；无公开列表接口的模板保留明确静态目录。
   保留路径前缀、鉴权、超时/大小限制、合法空名单和最后成功回退，不额外插入 /v1 或推理探针。
4. **账号隔离**：所有可调用成员使用 `(account_id, model_id)`；在线观察、本地覆盖、参数和价格
   只在同账号内合成。可复用内置只读定义，但不再按裸 model_id 跨账号传播观察。
   查询指纹必须覆盖决定解码语义的厂商协议，不仅是 URL、目录或 wire API。指纹升级须显式
   保留旧缓存和最后成功快照，迁移快照不发送旧 ETag，不得因切换协议重新认领同一旧快照。
5. **运行时与原生协议**：复用现有 canonical 请求、工具身份、usage、opaque replay、accumulator、
   重试预算、脱敏和资源释放。真实 wire 差异与设计保持一致，不建立平行解析/执行路径。
6. **产品消费**：Studio、HTTP、FRB、Client、reducer 和 GUI 消费同一 typed canonical 快照。
   目录 revision 与 desired 设置 revision 独立，启动各账号独立同步一次，在途请求保持冻结。
   文本资格过滤不改写路由，撤下选择保留 unavailable；不在 Flutter 重新合并目录或计算价格。
7. **持久化演进**：按根约定实施配置/Profile/凭据及已有 v2 数据的版本迁移，正常运行不留旧 API
   alias。账号 ID 保值，显示名不改引用；原始厂商 JSON 与其他领域的 provider 术语不做全局替换。
   同步 [配置契约](../../../design/20-config.md) 与内置 `studio-config` 指南，迁移失败保留现场，不能用重置代替。

## 验证与交付

用 [协议示例](../../../code/model-protocols/README.md) 手动调试真实端点。协议集成测试通过 `tests/` 调用公开 API，账号装配测试通过 `pl-model` 入口验证。内部编解码规则放在源码末尾的单元测试。

调查厂商契约时先固定实际 API、版本和连接模式；同厂商不同 API 的结果结构不能混用。
用对应官方 schema 与固定版本 SDK 源码交叉核对，区分协议要求、SDK 便捷行为和本项目的成功提交边界。
普通响应分块不等于工具参数增量；未支持的增量模式须在请求开启与响应解码两端明确拒绝。

完整工具调用应在解码处发布既有调用就绪事实，不能依赖流尾无序集合恢复顺序。分别核对
参数完成、调用就绪与整次响应成功；就绪事件不得使失败响应中的工具提前执行。可选上游 ID
与内部任务身份分开，出站身份以原始回放为准，不按内部字符串前缀猜来源。多调用回归应经过
真实解码、运行时收集和下一请求构造，覆盖同名调用、缺省或空 ID、逆序完成与签名原样保留。
同一约束还须覆盖公开请求构造与历史回放入口，不能只依赖直播解码或上层上下文检查；原生
请求选项允许厂商等价字段名时，禁止能力的检查须覆盖这些拼写，不能被原样合并的选项绕过。

错误策略扩展复用 `pl-model/tests/integration/protocol_extension.rs` 的公开 Registry/Adapter 与 loopback
装配，证明同一 HTTP 状态的暂时／永久业务原因、流内同义错误、未知与坏结构、等待提示能穿过
真实运行时。等待用虚拟时间和明确通知验证，不能用真实长 sleep；产品字段用生产 Rust serde
结果与 Client／Flutter 共同夹具对照，避免只测手写 camelCase JSON 而漏掉 enum 字段命名。
若 JSON 数值需跨 JavaScript 边界，使用生产序列化验证超过 `2^53` 的值和类型最大值；FRB
大整数通过不代表分页或历史 JSON 也无损。取消验证须覆盖收到失败后、保存确认期间及等待
期间等有不同已知事实的窗口，不能只从预填恢复记录的 UI 夹具推断整条链路正确。
分类矩阵覆盖同一 HTTP 状态下的永久／临时原因，以及未知子码与已知永久类型并存的情况；
可复用 `pl-model/tests/integration/provider_error_matrix.rs` 的公开装配入口，不能只用单个字段证明优先级。

迁移夹具先与基线实际写盘格式核对：SQL 旧列名、JSON casing、版本号、嵌套非空诊断及缺失值
都不能随新术语机械改名。用实际启动、日志解码、存储打开或生产者回执读取入口证明升级，不能
仅调用绕过版本门禁的 helper。新增类型改名后，检查旧版本载荷的嵌套字段是否误用了当前类型；
例如含非空提示词诊断的旧 prepared request 不能只用 `prompt: null` 证明迁移。凭据迁移必须
严格持久写入并回读，进程内 lease 不能作为持久成功证据。

共享绑定的序列化变更须盘点每个生产者格式，不只检查请求/响应回执：已带冻结绑定的原生压缩
checkpoint 也要明确升级版本。模型格式由模型生产者在版本边界转换，产品扩展表示则由唯一
history writer 在恢复 owner 前事务提交；helper 能读旧值不等于检查点已经耐久升级。用真实
旧检查点的重开、写失败回滚与跨账号来源拒绝证明这两种边界，保留不透明密文和冻结隔离事实。

空工具表的模型测试不能证明宿主的完整工具装配及容量预览。按 Mode 隐藏工具时，可见声明、
独占工具身份和调用模式保持一致。若失败发生在 attempt 准入前，
调用日志为空不代表无模型错误；先定位准备阶段的原始错误来源，勿以放宽完整性校验代替修复。

`flutter-studio-build` 提供真实 bridge、内容捕获与人工观察方法；模拟只能证明约定样本，
不能证明线上厂商兼容性。任何真实账号操作仍需授权，报告区分实际平台、账号/Wire API 覆盖、
未验证能力和资源结果，不将 demo 或静态分析当作真实调用通过。
