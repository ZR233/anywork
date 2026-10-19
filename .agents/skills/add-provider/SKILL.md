---
name: add-provider
description: Use when adding or changing an account template, vendor protocol adapter, or model catalog in 糊来帮's Account and ModelRuntime architecture.
metadata:
  category: guides
  platforms: ["windows", "linux", "macos"]
---

# 扩展账号模板与模型协议

先读取根 AGENTS.md、design/06-model.md 和 design/20-config.md。账号是稳定 ID 的接入实例，
账号模板是创建默认值，厂商协议适配、Wire API（Chat Completions / Responses）与连接方式
（HTTP / WebSocket）是不同维度。不要把模板、显示名、endpoint 或裸 model_id 当成账号身份。

## 选型与分层

优先复用工作区已有 reqwest、SSE、WebSocket、typed codec 和目录能力；按根项目约定核实官方
文档、组件 API、目标平台及错误/取消契约。不能复用时先调研并取得用户对自研范围的明确选择，
不默认新增框架、wrapper、fallback 或 SDK。

模型执行只有 `ResolvedModelRoute -> ModelRuntime` 一条路径。OpenAI、DeepSeek、Zhipu、xAI、
MiMo 和自定义兼容适配是同级封闭变体，通过组合复用 OpenAiBase 的 Chat/Responses 能力。
实际请求准备、事件解释和目录解析经过所选适配；仅给同一 runner 套不同名字不构成协议扩展。
同步窄能力可用 enum_dispatch，异步重试、取消、连接、continuation、流和计量继续由唯一执行器
拥有；不使用 async_trait，不为宏引入 boxed future 或隐藏 Send，也不新增厂商执行器。

原生 thinking、tool_stream、Files、搜索、缓存、余额、配额与远程压缩保留类型化能力边界。
Responses 兼容不自动意味着支持这些能力；自定义地址的服务能力撤销规则遵循权威设计。

## 扩展清单

1. **账号模板**：在唯一模板目录声明默认 endpoint、厂商协议、凭据提示、模型目录和推荐选择。
   现有模板可重复创建账号，账号名默认取模板展示名，账号 ID 只分配一次；不增加第二套 GUI 默认值。
2. **模型定义与绑定**：定义元数据、能力和参数声明；绑定 wire API、连接矩阵、请求/媒体编码、
   参数 wire 与价格。未知值保持未知，不从模型名、URL 或厂商名称猜测能力。
3. **目录解析**：按各家官方接口解释 envelope、字段、单位与明确/缺失/null/空集合。
   OpenAI/Codex 富声明不自动适用于 DeepSeek 或 xAI；无公开列表接口的模板保留明确静态目录。
   保留路径前缀、鉴权、超时/大小限制、合法空名单和最后成功回退，不额外插入 /v1 或推理探针。
4. **账号隔离**：所有可调用成员使用 `(account_id, model_id)`；在线观察、本地覆盖、参数和价格
   只在同账号内合成。可复用内置只读定义，但不再按裸 model_id 跨账号传播观察。
   查询指纹必须覆盖决定解码语义的厂商协议，不仅是 URL、目录或 wire API。指纹升级须显式
   保留旧缓存和最后成功快照，迁移快照不发送旧 ETag，不得因切换协议重新认领同一旧快照。
5. **运行时与原生协议**：复用现有 canonical 请求、工具身份、usage、opaque replay、accumulator、
   重试预算、脱敏和资源释放。新增真实 wire 差异时先更新设计，不建立平行解析/执行路径。
6. **产品消费**：Studio、HTTP、FRB、Client、reducer 和 GUI 消费同一 typed canonical 快照。
   目录 revision 与 desired 设置 revision 独立，启动各账号独立同步一次，在途请求保持冻结。
   文本资格过滤不改写路由，撤下选择保留 unavailable；不在 Flutter 重新合并目录或计算价格。
7. **持久化演进**：按根约定实施配置/Profile/凭据及已有 v2 数据的版本迁移，正常运行不留旧 API
   alias。账号 ID 保值，显示名不改引用；原始厂商 JSON 与其他领域的 provider 术语不做全局替换。
   同步内置 studio-config 指南，迁移失败保留现场，不能用重置代替。

## 验证与交付

先增强已有 pl-model 公开 API 行为测试，验证真实 loopback 请求、各家解析、账号隔离和失败传播；
不要镜像生产模型清单或为每个模板堆默认值测试。Studio 只在项目允许的迁移/历史故障范围加测试。
各执行者只做本范围格式、静态和定向测试；主代理统一执行根 AGENTS.md 的最终门禁及生成检查。

迁移夹具先与基线实际写盘格式核对：SQL 旧列名、JSON casing、版本号、嵌套非空诊断及缺失值
都不能随新术语机械改名。用实际启动、日志解码、存储打开或生产者回执读取入口证明升级，不能
仅调用绕过版本门禁的 helper。新增类型改名后，检查旧版本载荷的嵌套字段是否误用了当前类型；
例如含非空提示词诊断的旧 prepared request 不能只用 `prompt: null` 证明迁移。凭据迁移必须
严格持久写入并回读，进程内 lease 不能作为持久成功证据。

共享绑定的序列化变更须盘点每个生产者格式，不只检查请求/响应回执：已带冻结绑定的原生压缩
checkpoint 也要明确升级版本。模型格式由模型生产者在版本边界转换，产品扩展表示则由唯一
history writer 在恢复 owner 前事务提交；helper 能读旧值不等于检查点已经耐久升级。用真实
旧检查点的重开、写失败回滚与跨账号来源拒绝证明这两种边界，保留不透明密文和冻结隔离事实。

真实接入还须覆盖宿主的完整工具装配及容量预览。按 Mode 隐藏工具时，同步维护可见声明、
独占工具身份和调用模式，不能只以空工具表的模型测试证明集成可用。若失败发生在 attempt 准入前，
调用日志为空不代表无模型错误；先定位准备阶段的原始错误来源，勿以放宽完整性校验代替修复。

GUI 或协议可见行为按 flutter-studio-build 使用真实 bridge 和 Flutter Driver 验收；模拟只能证明
约定样本，真实厂商保持显式、有界的线上观察。报告实际平台、账号/Wire API 覆盖、未验证能力、
脱敏证据及进程回收；不将 demo 或静态分析当作真实调用通过。
