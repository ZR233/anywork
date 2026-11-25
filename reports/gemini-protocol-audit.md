# Gemini／Vertex GenerateContent 协议逐项核对

核对日期：2026-11-25。基线：`origin/main` 的 `3db5e10d03db6a13bcc44b37d37555bcaf80e2c7`。
对应修复：[PR #592](https://github.com/ZR233/anywork/pull/592)。

本文件覆盖当前 Gemini／Vertex 适配及其经过的共享执行、历史回放和计量边界。
`[x]` 表示已经按所列来源核实，结果可以是符合、已修复或明确不支持；不表示所有官方功能均已实现，
也不把静态核对、模拟回归和真实账号验证混为一项。待核对或待验证的项目保留 `[ ]`。

## 官方依据与固定 SDK 版本

- [R1：GenerateContent 请求与流式接口](https://aistudio.google.com/api-reference/generate-content/stream-generate-content)。
- [R2：响应、候选、结束原因与用量](https://aistudio.google.com/api-reference/generate-content)。
- [R3：函数调用模式与多轮工具交互](https://aistudio.google.com/docs/function-calling?generate-content=true)。
- [R4：思考签名与完整原始 Parts 回传](https://aistudio.google.com/docs/thought-signatures?generate-content=true)。
- [R5：FunctionDeclaration 与原始 JSON Schema](https://googleapis.github.io/js-genai/release_docs/interfaces/types.FunctionDeclaration.html)。
- [R6：Gemini 模型目录](https://aistudio.google.com/api-reference/models)。
- [R7：Vertex PublisherModel 资源](https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/rest/v1beta1/publishers.models)。
- [R8：思考摘要与思考预算](https://aistudio.google.com/docs/thinking?generate-content=true)。
- [R9：长输出与续接](https://aistudio.google.com/docs/long-decode?generate-content=true)。
- [R10：当前模型规格](https://aistudio.google.com/docs/latest-model?generate-content=true)。
- [R11：当前官方定价](https://aistudio.google.com/docs/pricing)。
- [R12：API 错误与重试边界](https://aistudio.google.com/docs/troubleshooting)。
- [R13：Google 错误信封与标准错误详情](https://google.aip.dev/193)。
- [R14：Vertex Express 接入](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/start/express-mode/overview)。
- [R15：媒体输入方式](https://aistudio.google.com/docs/file-input-methods?generate-content=true)。
- [S1：JavaScript SDK `3445a09ee9f4bb8a11287533c94a0a5d45235ea3`](https://github.com/googleapis/js-genai/tree/3445a09ee9f4bb8a11287533c94a0a5d45235ea3)，重点核对 `src/chats.ts`、`src/models.ts`。
- [S2：Python SDK `36e297073202d937da00829aadbd85e42c32a571`](https://github.com/googleapis/python-genai/tree/36e297073202d937da00829aadbd85e42c32a571)，重点核对 `google/genai/chats.py`、`models.py`、`_transformers.py`、`_api_client.py`。

SDK 的自动函数执行、历史筛选与自动续接是客户端策略；本项目保留自己的统一执行器和成功提交边界。
文档中的 Interactions API、Live API、批处理接口不作为 GenerateContent 的请求／响应契约。

## 请求与能力边界

- [x] A01：API、版本和连接方式。`endpoint.rs`、`request.rs` 使用 Developer API `v1beta`／Vertex Express `v1` 的原生 HTTP SSE 路径；模型名在 URL 中。依据 R1。
- [x] A02：鉴权。默认 `x-goog-api-key`；Vertex 模板是 API Key 的 Express 模式，不宣称已实现 Google Cloud OAuth／ADC。依据 R1，验证见 `gemini_integration`。
- [x] A03：模型名与地址前缀。模型名经过路径段检查，保留账号设置的地址前缀；不把请求正文的 `model` 当成真正发送模型。依据 R1。
- [x] A04：系统指令由 `SystemPrompt` 单独发送；历史 System 消息按普通历史文本处理，不提升权限。已补齐 `system_instruction` 等价拼写的配置注入检查。代码：`request.rs`；依据 R1、S2。
- [x] A05：用户文本与连续普通用户输入按 `user` Content 组合；函数结果单独成批，不与普通文本／媒体混合。依据 R1、R3。
- [x] A06：原生 OpenAI 上下文及远程压缩输入在 Gemini 路径明确拒绝。代码：`codec.rs`、`request.rs`。
- [x] A07：现有累积器只支持一个答案，出站拒绝多个候选，入站拒绝多候选和非零候选索引。已补齐检查，见 `protocol_audit`；依据 R1、R2。
- [x] A08：当前实现单跳 65,536 输出上限，明确拒绝超限和外部续接令牌；`CONTINUATION` 保留为未完成结果。S1／S2 的自动续接不属于本项目已实现能力，不能用重新生成替代续接。依据 R9。
- [x] A09：思考摘要通过 `includeThoughts` 请求，`thought: true` 内容进入推理通道，保持原始回放。代码：`request.rs`、`sse.rs`；依据 R8。
- [x] A10：内置思考级别与当前流式上限符合 R10；已撤销 Gemini 4 上游已忽略的温度能力，并按 R11 修正氩／碳模型提前采用 12 月价格的问题。价格是核对日的标准付费层快照，11 月 30 日后须重新核对官方条目，不代表供应商实际账单。
- [x] A11：`MediaRepresentationPlan` 与 `encode_parts` 复用统一附件准备；内置模型仅声明本地 JPEG／PNG／WEBP／GIF、PDF／纯文本，采用 Base64，按声明执行 15 MiB 单文件及同模态合计限制。这是当前产品边界，没有宣称用尽 R15 的全部媒体能力。现有实际 HTTP 多模态回归覆盖原字节与 MIME。
- [x] A12：当前没有 Files 上传绑定，不声明远程 URL、音视频或生成媒体输入输出；不直接投影 OpenAI 托管工具。生成媒体／服务端工具 Parts 无法进入当前文本执行契约时明确失败。普通额外响应元数据保留在原始记录，不冒充产品工具执行。代码：`adapter.rs`、`models.rs`、`request.rs`、`sse.rs`。

## 函数声明、参数与工具结果

- [x] B01：自动、必选、禁止调用分别映射 `VALIDATED`、`ANY`、`NONE`，不把自动选择变成强制函数调用。代码：`request.rs`；依据 R3。
- [x] B02：`parametersJsonSchema` 在根对象声明命名参数；完整作者声明不变。已修复真实 `skill_manage` 顶层联合导致的服务端拒绝。依据 R5。
- [x] B03：只对闭合对象分支补参数名及共同必填项，原约束和引用留在原位置；分支开放、`patternProperties`、根闭合／未求值字段限制等无法按当前规则证明等价的情形明确拒绝。`protocol_roundtrip` 覆盖正反例，实际 `skill_manage` 的 456 组组合经独立 JSON Schema 校验器核对结果一致。
- [x] B04：完整 JSON Schema 采用 `parametersJsonSchema`；旧 `parameters` 对应的受限 Schema 不能承载相同契约，显式切换旧接口时在发送前报错。依据 R5；`protocol_audit` 回归。
- [x] B05：已删除对数组、标量或非法参数原文的自动补包；解码、公开回放、普通历史出站共同拒绝非对象参数。缺省参数仍按无参数 `{}` 解释，实际增量控制另行拒绝。依据 R3；`protocol_audit`、`protocol_roundtrip` 回归。
- [x] B06：通用历史以 `call_id` 写函数 ID 和结果 ID；`item_id` 仅作条目身份，同批两类身份分别校验。Gemini 原始回放采用原调用的可选 ID。已修复原先用 `item_id` 冒充调用 ID 的问题，见 `protocol_audit`。
- [x] B07：无 ID、空 ID、同名调用按出现顺序绑定；不通过内部字符串前缀推断上游身份。依据 R3；现有 `protocol_roundtrip` 与真实运行时回归。
- [x] B08：一个模型响应是一批调用；结果按原调用顺序紧随其后，拒绝中断、不完整与同批重复身份。依据 R3、R4。
- [x] B09：完整调用依次发布参数完成和调用就绪；调用就绪不等于整个响应成功，不提前执行失败响应中的工具。代码：`sse.rs` 与共享累积器。
- [x] B10：未实现参数增量时，请求与响应明确拒绝实际 `partialArgs`／`willContinue`；同时检查官方等价拼写，不能被原生配置绕过。代码：`request.rs`、共享 `replay.rs`。
- [x] B11：Custom 工具由既有函数投影处理；不把 OpenAI 托管工具直接发送给 Gemini。代码：`request.rs`。
- [x] B12：`functionResponse.response.result` 承载原模型可见结果文本，成功／失败诊断由原工具投影保存，不通过 JSON 字段猜测重新执行；附加工具媒体经独立用户内容准备，不混进函数结果批次。现有 `protocol_roundtrip`、Lua 集成和双步 HTTP 回归覆盖此路径；依据 R3。

## 流式响应、签名与历史

- [x] C01：SSE 终态前不提交成功；`STOP` 后继续消费流至 EOF，保留尾部用量与签名。代码：`sse.rs`；依据 R2、R4。
- [x] C02：缺少成功结束原因、传输截断、非法 JSON 不能因为已出现工具调用就成功。现有 `protocol_roundtrip`、HTTP SSE 集成回归。
- [x] C03：已补齐结构、模型角色、稳定响应 ID、候选索引、Part 类型和同批重复函数 ID 检查；纯空内容或仅推理的 `STOP` 不提交答案，`finish()` 不重复交付成功。代码：`sse.rs`；`protocol_audit` 回归。
- [x] C04：首个并行调用签名、各步签名、空文本尾签名和未知字段原样保存；不从展示文本重建。依据 R4；`ReplayCollector` 与端到端回归。
- [x] C05：带签名的 Part 不与相邻 Part 合并；无签名的同类文本可聚合。代码：共享 `stream/replay.rs`；依据 R4。
- [x] C06：跨凭据所有者的签名回放在请求前拒绝；已将 `thought_signature` 等价拼写纳入不透明状态与隔离判定。旧记录缺少来源证据时沿用原契约，不伪造所有者。代码：`codec.rs`、共享 `replay.rs`；公开回放回归。
- [x] C07：失败尝试的正文、工具和签名不进入成功回放；重试代次与当前展示隔离。真实 HTTP SSE 恢复回归。
- [x] C08：已把用量提取移到帧内失败交付之前；提示词拦截、Google RPC 错误、结构错误和结束失败同帧带来的有效计数保留。原始用量详情与服务层信息也保留。`protocol_audit` 回归。
- [x] C09：已按 R2 的每一个当前结束原因核对：仅 `STOP` 加完整输出并消费完流才成功，`MALFORMED_RESPONSE` 走有保护的重新生成；其余原因及未知值保留原码、用量和失败终态。`other_gemini_finish_reasons_keep_their_terminal_failure_and_usage` 对逐项列表执行实际本地 HTTP 回归。`BLOCK_REASON_UNSPECIFIED` 不伪装成实际拦截。

## 错误、重试、取消与计量

- [x] D01：HTTP 200 流内的 Google RPC 错误仍是失败；保留协议确定的配置、鉴权、权限与容量分类。已修复共享累积器覆盖协议分类的问题。
- [x] D02：已补齐 `INTERNAL` 等标准状态和永久配置失败，支持标准 `RetryInfo.retryDelay`，小数向上取毫秒；HTTP `Retry-After` 不再被空的协议重试提示覆盖，冲突取较长最小等待。未知数值不猜测为外层 HTTP 状态，明确的上下文超限保留原有压缩恢复分类。依据 R12、R13；协议单测与实际 HTTP 错误回归。
- [x] D03：`MALFORMED_RESPONSE` 保留原始原因，归为可重新生成的协议失败；这是产品策略，不声称官方 SDK 会自动重试。依据 R2。
- [x] D04：安全拦截、`MAX_TOKENS`、`MALFORMED_FUNCTION_CALL`、未知原因、客户端解码错误不因本次修复变为通用重试。
- [x] D05：复用冻结输入、原重试预算和退避；最多五次重试，取消不再发下一次请求。HTTP SSE 回归验证预算耗尽与取消。
- [x] D06：已发生托管副作用、原生压缩结果或成功终态仍禁止重放；已收到用量仅在明确的可重新生成协议失败时允许重试。代码：`invocation/attempt.rs`。
- [x] D07：被替换尝试逐次冻结用量和价格，不将多次尝试伪装为一次响应。代码：`InferenceAccounting.retry_attempts`。
- [x] D08：唯一产品计量投影展开失败重试记录，结果、历史重开与导出保留已知消费；未知贡献保持未知。`run_export` 回归。
- [x] D09：失败重试不借用最后一次的模型版本、耗时和上下文用量；传输次数不重复累计。`retry_billing` 回归。
- [x] D10：输入合计提示词及工具提示词，输出合计候选及思考，思考细分另存；总量保留上游值，缓存是输入子集。无计数的中途元数据不生成零用量；有提示词计数而缓存字段省略时按 Proto3 零缓存解释。已补齐工具提示词计数。依据 R2；`usage.rs` 回归。
- [x] D11：非法计数不再被静默忽略，按协议错误终止；已收到的前序用量由共享累积器保留。捕获记录保留原始 `usageMetadata` 及服务层／模态详情，规范费用仍只消费类型化计数，不将未知值补成完整账单。`protocol_audit` 回归。

## 目录、装配与验证

- [x] E01：Gemini 目录按 `pageSize`／`pageToken` 分页，分页结果不冒用单页 ETag；查询有统一超时与容量限制。现有 `gemini_integration`。
- [x] E02：已接受 Proto3 省略空数组的合法 `{}`；缺失能力保持未知、显式非生成方法为空能力，错误信封与错误模型 ID 拒绝。代码：`catalog.rs`；依据 R6。
- [x] E03：已停止根据生成方法推断图像／文件能力，避免覆盖内置 MIME、来源与大小限制；未知模型只保留既有最低文本绑定。目录返回的方法与实际核实的模型能力分开，见目录及集成回归。
- [x] E04：Vertex 目录使用 `name` 资源身份；十进制 `versionId` 只表示资源版本，已删除把它当模型名的路径及错误夹具。API Key 模板继续不启用该目录接口。依据 R7、S2。
- [x] E05：真实账户长任务使用隔离配置，不修改用户原配置或复制凭据；已完成氢模型高思考任务，准确时长 9 分 34 秒、53 次模型调用、36 个实际发现并执行的测试。
- [x] E06：长任务没有自然出现 `MALFORMED_RESPONSE`；该原因的恢复、预算、取消与失败计量由确定性 HTTP SSE 回归证明，不能将二者互相替代。
- [x] E07：六个相关包实际通过 460 项回归，另有 7 项既有外部环境／显式观察测试未执行；相关全部目标 Clippy、格式与文档策略通过。另修复并验证工具测试夹具的目录删除竞态，3 项已有回归通过。原计量历史／导出修复的 20 项和计量展开专项回归沿用本 PR 已完成的实际证据。

远端交付以关联 PR 的当前头提交与质量门禁为准，具体提交、主线和终态在 PR 正文回读后记录；
历史成功的 CI 不作为新增提交的通过证据。

## 问题与处理记录

| 问题 | 处理与证明 |
| --- | --- |
| 自动模式不约束参数、根联合没有命名参数表 | 使用官方 `VALIDATED`；等价补齐根参数名，保留完整分支；18 项真实工具表已被上游接受 |
| 原生失败分类被共享层覆盖；失败重生成丢弃已知消费 | 协议直接交付类型化失败；共享预算与副作用保护；各次尝试独立计量、导出和历史重开回归 |
| 非对象参数被改写、条目 ID 混作调用 ID | 三个公开边界拒绝非法参数；函数与结果均按对应调用身份发送 |
| 多候选／异常 Parts／空 `STOP` 静默通过 | 对当前单答案和文本能力按官方结构校验；异常带用量时仍保留计数 |
| 帧内拦截丢用量、忽略工具提示词计数和原始用量细分 | 提前提取有效报告；补齐计数与原始捕获；非法计数明确失败 |
| Google 标准状态和重试等待不完整 | 补齐状态、标准重试详情和 HTTP 等待提示，保持永久失败不可重试 |
| 目录空页误判、版本号与模型名混淆、生成方法被当成媒体能力 | 按各资源字段解释，保留核实过的绑定与限制 |
| Gemini 4 宣称无效温度参数、提前采用未来价格 | 对照当日官方规格及价格修正，不重算历史快照 |
| `exec` 内嵌结构绕过已有精简投影 | 复用同一投影删除嵌套生成器信息；原字段名、说明、引用和字面数据保留 |
| 工具测试的后台等待子进程可错过释放文件 | 等待条件同时受夹具目录寿命约束；实际清理已核实归属的残留组并重跑原有 3 项回归 |

## 实际发送值与数据量核对

- [x] F01：从真实产品 CLI 的最终请求捕获读取实际值；原始请求、完整 schema、历史及签名保留在本地实验产物，不上传用户账户资料或凭据。
- [x] F02：使用相同真实工具表、`VALIDATED`、65,536 输出上限和高思考设置实际发送精简后的声明，HTTP 200、`STOP`，返回一个完整函数调用；没有执行该探针返回的工具。
- [x] F03：独立 JSON Schema 校验器对真实 `skill_manage` 的 456 组完整／缺项／多项／错误类型组合核对，精简前后接受结果相同。
- [ ] F04：全部实现完成后，以同一构建分别运行氢模型和 `gpt-6-luna` 的八阶段长任务，并独立核对生成项目、实际测试发现、用量与进程退出。

实际 Gemini 请求中的配置值为：

```json
{
  "toolConfig": {"functionCallingConfig": {"mode": "VALIDATED"}},
  "generationConfig": {
    "maxOutputTokens": 65536,
    "thinkingConfig": {"includeThoughts": true, "thinkingLevel": "high"}
  }
}
```

按紧凑 JSON 的 UTF-8 正文字节计量，实际首次请求中的相同 18 项工具表由 **47,897** 字节降至
**46,606** 字节，每次减少 **1,291** 字节（约 **2.70%**）。其中 `skill_manage` 根参数表
省去重复定义 **1,001** 字节，`exec` 内嵌输入／输出 schema 省去嵌套生成器注解及不可达定义
**290** 字节。函数名称、说明、原分支、必填与额外字段限制均保留；不是按字符截短声明。
正文总量还包含不同隔离目录与启动观察，不能把两次不同任务的总量差都归入优化，也不把字节差当成词元或账单节省。

| 请求部分 | 实际值与是否省去 |
| --- | --- |
| 根联合重复参数定义 | 补出的 `properties` 只保留实际参数名和 `{}`，完整定义留在原 `oneOf`；实际发送已验证 |
| 内嵌生成器注解 | 对 schema 位置移除 `title`、`default`、`examples` 等；同名参数和 `enum`／`const` 中的实例数据保留 |
| 系统指令与当前工具说明 | 承载实际权限、工作方式及接口语义，保留；不凭体积裁减 |
| 多轮内容、函数参数／结果与签名 | 官方 REST 要求完整历史和原签名，保留；不靠猜测删旧消息或思考 Part |
| 用量 | 服务端回报，不是请求字段；保留，不能用减少诊断代替减少发送 |

最初 53 次长任务的请求捕获中，内容部分累计 15,920,592 字节，工具部分累计 2,538,541 字节，
系统指令部分累计 2,438,212 字节。这些是各字段值的累计紧凑 JSON 字节，尚未加入字段名和外层标点；
不是网络流量或新增任务之间的词元对照。大头是必须回传的历史，继续由已有有界工具输出和上下文压缩控制。
