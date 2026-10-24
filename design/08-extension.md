# 08 - 扩展点索引

扩展优先数据化：新能力尽量表现为 catalog、template 或配置数据，而不是新的代码分支；不猜测厂商
能力。各扩展方向的完整合同见对应专篇，本文只给入口与边界。

| 扩展方向 | 边界摘要 | 专篇 |
| --- | --- | --- |
| 账号与厂商协议 | 账号模板提供创建默认值；同级厂商协议适配通过组合复用 OpenAI base 的 Chat/Responses 能力，并保留原生特性和各自目录解析。模型声明与账号覆盖仍数据驱动；实例成功缓存由 Studio 管理，不写用户 desired 配置。 | [06](./06-model.md)、[20](./20-config.md) |
| 普通 Skill | 按优先级目录发现，`skill_list` / `skill_view` 按需加载；frontmatter 与正文由 pl-skill-core 统一解析，非法资源只产生自身诊断；普通 Skill 不得使用 `mode.` 前缀。 | [10](./10-skills.md) |
| Thread Mode | 注册制扩展，不复用 Skill、Account 或发现目录。内置 `mode.simple` 与 `mode.task` 随二进制发布；未来文件加载器只把外部配置转换为相同的所有权结构后按来源原子注册，不同来源不能注册同一 ID，内置 ID 不可覆盖。注册输入可携带预设图，runtime 在发布目录前完成编译；模型只能用拆分后的查询与转换工具读取和推进图。 | [11](./11-thread-mode.md) |
| Agent 定义与 Profile | 所有 root/child 使用同一声明模型；内置定义由随包声明与提示词资源提供，产品入口绑定可信身份。仅 child 开放用户 TOML 配置及派发，目录是共同定义的可派发视图。新增角色不改框架角色枚举或快照特判；系统 child 的专属路由缺省继承默认模型。协作工具只接受 profileId，不暴露任意临时 system prompt 注入入口。 | [12](./12-collaboration.md)、[20](./20-config.md) |
| 工具 | 新增持久状态工具应采用 typed args/result、稳定错误码、显式 CAS 与 operation identity，并在 working-state 克隆上计算后进入统一 checkpoint；批处理声明 Coexist 或 Solo。业务工具不得绕开 Thread owner 写第二套事实。 | [09](./09-tool-runtime.md) |
