# 20 - Studio 持久化配置

本文是配置文件 schema、account/model 结构、提示词分层、MCP/Skills/LSP 配置与凭据策略的
唯一权威源；权限语义见 [04](./04-security.md)，模型层机制见 [06](./06-model.md)，设置页
UI 见 [19](./19-studio-ui.md)，Agent Profile 体系见 [12](./12-collaboration.md)。

## 20.1 配置位置与产品身份

anywork 使用独立产品身份，默认仅访问 `~/.anywork`，凭据服务名为 `anywork`，产品环境变量
前缀为 `ANYWORK_`。产品与用户数据的版本演进以 anywork 为起点；显式指定的数据根目录
仍遵循既有参数优先级。

配置文件固定为 `~/.anywork/config.toml`（Windows 下 `%USERPROFILE%\.anywork\config.toml`）。
会话、产品库与调试日志的数据布局由 [存储契约](./17-studio-storage.md) 统一定义。用户 Agent Profile
单独保存到 `~/.anywork/agents/*.toml`。schema 版本以代码常量为准。

机器人 desired 配置独立保存于 `<StudioHome>/v2/bots/<bot-id>/config.toml`，拥有自己的
schema 和 `configRevision`，不在主配置里新增 Node/MCP/provider 伪配置。App Secret 使用
独立 `bot:<bot-id>` 凭据 scope；字段、首配与在线应用边界见 [27](./27-bots.md)，物理布局
见 [17](./17-studio-storage.md)。机器人版本演进不通过改写主配置版本号代替迁移。
机器人配置可以保存非敏感的所选凭据版本引用，不包含凭据本身；它不改变 Provider 主配置
不保存凭据引用的约定。所选引用、候选材料及提交待确认的恢复由机器人 owner 统一协调。

配置运行时在 Studio 启动时读取配置；此后普通对话和设置查询只读内存 canonical snapshot；
配置文件不存在时设置页展示内存中的默认配置；外部文件变化只有显式重载命令才能应用。
支持在线模型探测的 account 只在程序启动的初始化阶段各探测一次，各实例任务并行提交、互不等待，
任一失败只写该实例状态；设置查询不触发额外联网，运行期也没有第二次自动同步。首屏先使用成功
缓存或默认模型定义，不等待所有网络结果；模型观察不写回 config.toml。完整语义见 20.5。
普通设置项在用户修改后即时写入配置；独立新增/编辑页面保留本地草稿，必须点击页面内保存
按钮才写入，取消则丢弃草稿。模型启用与压缩阈值从账号详情卡的模型列表即时修改，不属于账号
编辑页草稿；交互与失败反馈见 [19](./19-studio-ui.md)。

配置版本演进必须满足以下迁移契约；会话和产品数据的隔离与布局演进另见
[17.7](./17-studio-storage.md#177-大版本隔离与配置迁移)，不能把会话大版本隔离用作配置重置的理由。
本文定义目标契约，实际完成情况以迁移验证为准。

- 启动时在产品发布前识别配置版本，使用明确的版本转换路径将 anywork 历史配置与用户
  Agent Profile 转为当前结构，支持跨版本升级；保留用户选择、account 身份与凭据关联。
- 转换前备份原始文件且不覆盖已有备份，转换后执行完整校验，通过原子替换或可恢复步骤
  提交。涉及多个配置
  文件、数据库关联或凭据时由 Studio 协调，不能发布新旧结构混合的 canonical snapshot。
- 新增字段只能使用该版本迁移明确规定的默认值；旧字段在迁移边界转换，不能用重建整份
  默认配置、猜测模型路由或运行时兼容补齐代替迁移。正常读写只使用当前 schema。
- 未来或未知版本、无法解析、无效引用或缺失迁移路径返回无法恢复的数据错误，由统一启动
  协调器按 [17.2](./17-studio-storage.md#172-启动与按需激活) 完整备份后重建初始状态。
  配置模块自身不静默覆盖默认值。凭据或 IO 环境失败保留现场并报告，不触发重置。
  配置缺失判定只依据路径条目；权限、元数据及符号链接异常不能冒充缺失。
  已知版本转换优先保全；支持路径上的迁移、提交或凭据失败须停止启动并保留现场，不能转为
  全局损坏恢复或默认初始化。解析诊断只含路径、类别和行/列位置，不回显原文或凭据。
- 中断后可安全重试或恢复一致状态；运行期显式重载只接受当前有效结构，失败保留已有
  canonical snapshot，不在查询或重载中隐式迁移。迁移结果与失败通过脱敏诊断报告。

迁移验证应覆盖版本跳跃、字段重命名、路由与 Profile 关联、凭据标识变化、未知版本、
损坏配置、备份或提交失败及重启恢复，证明用户选择与凭据可用性得到保留。

启动支持明确的 18→19 迁移：仅从 `disabled_system_agents` 移除 `planner` 并提升版本，
保留五条模型路由、其他设置和 account 凭据关联。19→20 迁移把旧 `planner` route 复制为
`mode.simple` 与 `mode.task` 的默认 route，从 `models.routes` 删除 `planner`，并保留四个系统
子代理 route、account、其他设置和凭据关联。两步都先校验和备份，再原子替换；迁移失败
保留原文件并向协调器返回明确错误。没有转换路径的版本保留原字节进入统一备份恢复，
环境失败则停止启动。正常运行不接受禁用主智能体或以该标识保存用户 Profile。

20→21 迁移在旧 TOML 表上先把 provider 显式能力里的方言标识
`models.providers.<id>.capabilities.web_search.standalone = "deep_seek_anthropic_messages"`
改写为 `deep_seek_tools_api`（旧方言标识已不可解析，只在迁移边界转换）。唯一权威路径是
`capabilities`：`AccountConfig` 没有 `service_capabilities` 键，手写的同形表是未知键，typed
parse 忽略、canonical 落盘丢弃，迁移只把其中的旧标识字符串一并改写以免留下已失效标识，
不改变解析结果。改写只针对该路径上的字符串值：其它位置的同名文本不动，`web_search` 缺失或
形态不符时不猜测补齐，交给 typed parse 报错。随后按当前结构 typed parse、
`validate_declarations()`、备份原字节、原子写入并回读凭据；`[deepseek_web_search]` 的
`fetch_enabled` 由该版本的默认值补齐：迁移不推断用户对「网页抓取」的意图，原本只关闭
`enabled` 的配置升级后仍会得到一个新启用的抓取工具。18/19 存量配置中的同一 token 在同一步
改写，迁移失败保留原字节且不落盘。迁移的诊断定位基于改写后的 canonical 文本，而不是用户
原始文件的行列，因此只用于定位失败原因，不承诺与原文件行号一致。

21→22 将旧模型声明中的 `slug` 转为 `model_id`；旧新键同时存在但不一致时拒绝，不以覆盖丢弃选择。
22→23 将模型接入领域的 Provider/Preset 转为 Account/AccountTemplate：`models.providers` 转为
`models.accounts`，账号 `preset` 转为 `template`、`adapter` 转为 `protocol`，角色、Mode 与用户
Agent Profile 的 `provider`/`model` 转为 `account_id`/`model_id`。账号 ID 和模板 ID 原值保留，
endpoint、headers、价格开关、模型声明、连接与压缩覆盖、环境变量引用和其它用户设置保留。
18 至 21 先执行其既有转换，再执行账号转换；正常读写只消费当前结构，拒绝已退役的模型接入键，
不保留 serde alias 或运行期双轨解析。

主配置与用户 Profile 的转换在同一个可恢复操作内准备：备份原字节、验证候选和引用、完成凭据
复制与回读后，记录提交意图并逐资源原子替换。中断后必须先接续同一操作，不发布新旧混合状态。
操作记录只保存身份、版本、步骤及校验信息，不保存密钥；受保护的原件和已验证候选保留到操作
确认完成。任一步失败均保留原件或可恢复步骤，不通过重置绕过。凭据命名空间转换见 20.11；
已有 v2 产品扩展和调用记录转换由 [17](./17-studio-storage.md) 定义，不要求扫描激活全部会话。

所有 Settings command 必须携带 `expectedSettingsRevision`，成功返回新的
`SettingsConfigSnapshot`；目录发生变化时另返回 `ModelCatalogSnapshot`，并分别发布
`SettingsConfigStateChanged` 与 `ModelCatalogStateChanged`。前者表示用户 desired 设置，后者
使用独立目录水位，不推进 desired revision。直接响应为 `SettingsStateResponse`，只是为了让
调用方一次得到两个独立资源，消费方仍按各自 revision 幂等合并；不得返回聚合状态、raw JSON
或 raw map。CAS 或校验失败时保留当前 canonical 状态，不覆盖新配置。

### 20.1.1 设置 mutation 的资源边界

模型接入的当前 typed wire 使用 accounts、accountId、modelId 和 templateId；模板目录使用
templates，与实例目录分离。配置中的 template 是可选模板引用，protocol 是明确的厂商适配。
账号编辑使用 id 定位同一资源，不提供 originalId 重命名路径。模型选择、Mode/角色和会话路由
使用 accountId/modelId；defaultModelId、suggestedModelId 仅为目录或创建路由的投影，不是
账号 runtime 的第二份模型选择。HTTP 与 FRB 同步切换，旧模型接入 endpoint 不保留转发别名。

写入接口按业务资源划分，而不是把整个 `StudioSettings` 快照作为 patch。标量设置、列表设置、
每个 MCP 字段、每个 Mode 的模型/思考强度以及每个 Agent role 的模型/思考强度，分别使用一个
typed mutation；请求只携带目标标识和新值，其他字段由配置 owner 从最新 canonical state 解析。
因此连续选择模型、思考强度或快速返回设置页不会把旧 selector 快照写回，也不会因为目录刷新
重放其它设置。

Account 编辑和已有 Thread 的 model route 是有意保留的资源级原子接口。Account 的 endpoint、
凭据、模型声明和连接覆盖需要联合校验，Thread route 的模型、思考强度和 runtime route 也必须
同时满足能力与活动状态约束；把它们拆成多个可独立落盘的请求会允许半个无效资源被观察到。
它们仍各自拥有独立的 mutation key、CAS、pending、重试和失败状态，并且不会携带其它 account、
Mode 或 role 的旧快照。读响应可以为了减少往返同时返回 config/catalog 两个快照，但消费端必须
按各自 revision 合并，读聚合不改变写入粒度。

模型压缩阈值的内联自动保存仍属于上述 account 原子资源，不另设字段级协议。提交时从最新
canonical account 构造目标模型的覆盖变更，保留其余模型、连接覆盖、目录声明与凭据关联；
凭据使用 Preserve，不把目录默认值写成用户覆盖。相同 account 的写入串行，CAS 冲突后重试
必须在最新 canonical 状态上重新应用目标意图，不重放旧 account 快照；其他设置不被改写。

所有 account template 使用相同的配置提交边界：凭据与 desired config 提交、canonical 状态发布
后即可返回，不等待 MCP 连接、模型发现或额度网络请求。后续服务可用性由相应领域 owner 独立
发布，不把服务探测失败改报为已提交配置的保存失败；删除、设默认和显式重载同样不串联服务
联网等待。账号页自动额度查询的需求与失效规则见 [25](./25-frontend-state.md#2571-账号用量需求)。

## 20.2 配置职责

### ACP 接入配置

账号设置入口以 Native/Acp 类型化分支汇集两类接入。Native 的 `models.accounts`、路由与
凭据合同不变；Studio 独立拥有 `acp.accounts`，每个稳定 ID 只保存名称、接入类型，
不使用空 base URL 或空模型目录伪装 Native 账号。Antigravity 仅运行产品固定的 1.4.1
受管安装，program/argv 由安装与认证边界产生，不属于用户配置或保存请求。
ACP 不进入 Native 默认账号或模型路由候选。

配置 schema 25 的转换链为更早配置保留或增加 ACP 集合；24→25 显式移除旧 ACP program/args，
保留账号 ID、provider、名称、路由、Profile、所有无关设置与凭据关联。旧执行字段只在迁移
边界解码，现役 schema 和 API 不保留兼容执行入口；沿用本章的备份、校验和原子提交，不
通过默认配置重建绕过迁移，不删除旧安装或官方凭据。

同为 schema 24 的历史配置可能已有 ACP 接入，也可能已有模型启用、计费类别与分发设置；
迁移不能按版本号选择其中一组字段覆盖另一组。统一的 schema 25 保留两组显式值：ACP
集合缺失时为空；分发模式与偏好缺失时分别为 `profile`、`balanced`；模型禁用集合缺失时
为空；计费类别覆盖缺失时保持未指定，由当前规则推导。字段级缺省不替换显式值，不从金额
统计开关推导计费意图。已经使用 schema 25 的配置同样接受这些可选字段的当前缺省表示，
不回退版本或重做历史转换；当前 ACP 结构仍拒绝 `program`/`args`，缺省语义不是旧执行入口。

18 至 22 的账号、路由与 Profile 键转换沿原版本边界执行；23 及以上的规范化 Profile 保留
原字节，不重复访问旧 provider 凭据命名空间。中断的迁移若以 schema 23 或 24 为目标，先按
原日志的候选、摘要与提交步骤完成该操作，再从已提交版本继续到 25；不得改写旧候选摘要、
伪改日志目标或发布中间配置。每段升级保留对应原件和恢复责任，失败不转成默认初始化。

ACP 保存/删除使用 Settings revision CAS，成功返回 canonical 设置，且不等待进程启动或
认证。认证是独立显式操作，不推进 Settings 或模型目录水位，详见 [28](./28-acp.md)。

自动下载是显式的服务器准备意图，准备完成后再显式保存账号。固定发行清单和安装回执
拥有启动命令、版本与完整性事实，账号不存第二份来源或版本选择，不通过路径前缀或名称
推断资格。迁移或改名不下载、不启动认证；旧自定义路径不再执行，缺少固定受管安装时
保留账号并明确提示准备。下载失败不保存，保存失败不删除安装；连接仍须验证实际安装。

Google 凭据继续由官方程序管理，不经过 Native API-key 凭据接口，不复制到 anywork 的
TOML、数据库或 keyring。删除 ACP 配置只移除本地接入并取消所属操作，不注销 Google 或
删除官方凭据；多个配置可能共享同一官方凭据环境，不能因配置 ID 不同宣称账号隔离。

每个 account 的模型目录独立保存按模型 model_id 索引的压缩阈值覆盖值，bundled、附加与 explicit
模型使用同一解析规则。覆盖值为正整数 tokens，缺省表示使用解析后的模型默认值（目录预设或
安全输入容量推导）；恢复默认仅删除对应模型覆盖项，显式选择与非空默认值相等时也归一化为
缺省。每项覆盖以可选语义读取，缺键为 `None`，无覆盖的集合不序列化；该布局保持不变，
不需要配置版本迁移。完整账号编辑同样委托 `pl-model` 原子校验和归一化覆盖集合，Studio 配置编辑器
不比较模型默认值。最终上下文解析由 [06](./06-model.md) 定义，不复制进用户配置作为第二事实源。
用户新保存的无效值和不存在的模型引用在发布配置前拒绝，失败不改变 canonical snapshot。在线
目录变化使既有引用不可用时保留选择并报告 unavailable，见 20.5。新增可选覆盖
集合缺省为空，已有配置和凭据保持原样；既有模型默认阈值字段继续保持默认元信息语义。
Settings 命令携带 revision 并返回完整 canonical snapshot，保留未修改的模型和 account 数据。
模型刷新将覆盖值纳入冻结配置身份，新建、恢复和后续安全刷新使用最新解析值，不改写已发请求。

pl-model 拥有产品无关的模型配置值对象：角色路由配置（account_id/model_id/effort 校验与解析）、
account 配置与模型路由配置，负责把路由解析为运行时 endpoint 和唯一选中的不可变模型信息。
pl-studio-runtime 拥有：Studio 配置 schema 与启动期版本迁移、配置文件路径、
TOML 解析、原子保存和默认值、instructions/skills/MCP/runtime/disabled_system_agents 与
UI 配置、Agent Profile 文件的逐文件解析与原子保存，以及 Thread 首轮固定 instruction
snapshot 的生成。pl-model 只消费已经解析好的 account 和模型信息，不负责文件 IO 或路径
定位。
配置 owner 在同一发布边界区分磁盘 desired config 与非持久模型目录 overlay；解析视图合成两者，
所有 route、Profile、标题与 Settings 展示消费同一有效目录。保存只序列化 desired，不能把发现模型
塞进 additional_models 后随其他设置写回，也不能将其投影为可编辑 custom model。
Account 编辑提交只发送既有或用户显式修改的连接覆盖，不把在线模型的当前默认连接方式
转成持久覆盖。更换地址或凭据会失效旧目录观察；未改动的连接覆盖与路由仍按既有 desired
选择保留，不能因此次保存制造对旧在线名单的新引用。

`[ui]` 仅保留 `follow_active_turn`（默认 true）和 `compact_timeline`（默认 false）；主题不
属于持久化设置。未知 UI 字段按既有规则忽略，正常保存后不再输出；启动不因未知字段重写
配置、触发恢复或提升 schema。

### 20.2.1 模型启用、计费类别与分发默认

账号的 `disabled_models` 是精确 model_id 的禁用集合，缺省为空；可选 `billing_kind` 是
`metered | subscription | noCharge | unknown` 的显式覆盖，也是账号计费意图的唯一持久
事实源，不另存估算开关或免费布尔值。省略时只按明确
模板与 canonical endpoint 推导生效类别，不匹配则未知；显式值优先且不被地址修改
静默替换，推导结果不写回为显式意图。它们属于 desired 配置，不是
在线观察。新增模型默认启用，目录撤回保留禁用覆盖，恢复同一模型后继续应用；管理页仍
读取完整目录。普通选模、固定 Profile 和自动分发的统一资格与准入见 [06](./06-model.md)。

模型启用使用独立 typed mutation，携带 `operationId`、`expectedSettingsRevision`、`accountId`、
`modelId`、`enabled`。配置 owner 在最新账号上应用单一字段意图，保留凭据、其他模型、
连接和压缩覆盖；在线成员不转成手工成员。提交推进设置水位，并在同一发布边界更新目录
资格水位；失败不发布候选。禁用导致已有路由不可用不是配置损坏，不自动改写选择。
管理页切换立即保存，Client 的串行与失败规则见 [25](./25-frontend-state.md)。

计费类别使用独立账号级 typed mutation，携带 `operationId`、expected revision、`accountId` 和可空
`billingKind`：非空为显式类别（包括显式 `unknown`），空值清除覆盖并恢复模板推导。
canonical Settings 同时投影生效 `billingKind` 与可空 `billingKindOverride`，前者
用于展示和过滤，后者表达用户意图；不能将推导值回写为覆盖。普通账号编辑保留未修改
的覆盖，新建账号没有显式选择时保持缺省，地址变化只影响未覆盖时的推导结果。
账号页“不计费”开关是该类别的投影：开启写入显式 `noCharge`，关闭清除覆盖并恢复自动
推导，文案明确关闭方向；显式订阅、按量或未知仍由类别选择提供。已有账号使用上述窄命令，
普通连接及凭据编辑不回传或覆盖计费类别；新账号的初始类别意图随创建原子提交。
不计费只改变后续调用的计量结果，不清空模型参考价格；请求冻结和用量契约见 [06](./06-model.md)。
这些窄命令沿用设置命令的操作身份约定：请求必须提供有效 `operationId`，owner 在修改
配置前验证，并在 Applied/NoChange 回执中原样返回；不能用目标字段的固定描述替代一次
提交身份。HTTP 与 FRB 使用同一契约，不为缺失身份请求生成兼容 ID。

`[delegation]` 保存 `mode = profile | automatic` 和
`preference = economy | balanced | fast`，默认 `profile` 与 `balanced`。两个字段各自
使用 typed 设置命令，只改变未来会话默认；偏好在固定模式中保存但不生效。新建会话请求
携带草稿同步解析后的 `delegationMode` 和 `delegationPreference`，已有会话不回读默认。
提示词、工具与冻结边界见 [12](./12-collaboration.md) §12.7。

外部创建 API 的这两个字段允许分别省略，表示在本次创建准入时继承对应全局默认，
而不是将缺字段解码为显式固定/平衡。GUI 已同步冻结有效值，因此始终显式传入；
持久化的会话与目录事实保存解析后的非空枚举，重开不重新解释省略或全局默认。

引入这些字段时执行明确配置版本升级：旧模型全部启用、旧默认固定/平衡，旧账号没有
显式计费类别覆盖，生效类别由上述 canonical 推导给出，不把旧金额统计开关转换为类别。
保持账号、路由、
Profile、凭据关联及其他覆盖原值；先备份、校验、原子提交，失败保留现场。新增字段不在
运行期借旧结构或重建默认配置补齐。当前 v2 会话的对应升级归 [17](./17-studio-storage.md)。

移除金额估算设置执行下一版本的可恢复升级：只在版本迁移边界读取并删除账号旧
`pricing_mode`，保留既有 `billing_kind` 及其他设置与凭据关联，不把旧 `disabled` 转为
`noCharge`。旧值表达“未估算”而非“不计费”；升级后非不计费账号的后续调用依据可用价格
与用量估算。当前配置、API 与 GUI 不再提供金额估算开关，历史冻结账单与累计费用不重算。
中断的旧版本迁移先按其原候选和日志完成，再继续升级，不改写已持久化候选或发布中间状态。

## 20.3 根路由与系统 Profile

配置不使用 `active_account`。root Agent 的 desired route 属于各自 Thread；主配置以
`mode_model_routes` 保存各 Mode 的新建/切换默认 selector。`mode.simple` 与 `mode.task`
必须存在并独立保存 account_id/model_id/effort；合法自定义 Mode ID 可以持久化，尚无条目时继承
`mode.simple`，首次显式选择后形成自己的条目。Mode 默认值不反向修改其他现有 Thread。

`models.routes` 保存系统子代理 Profile 的显式路由覆盖；用户 Profile 的路由直接保存在
各自 TOML 中，不再写入该表。现有内置预设的配置 key 如下，实际集合由统一 Agent 声明
的 child 视图决定，不是框架的固定枚举：

| 配置 key | 中文角色 | 用途 |
| --- | --- | --- |
| `explorer` | 探索者 | 代码现状、文档、网络资源和上下文的只读探索 |
| `executor` | 执行者 | 实施修改和验证 |
| `worktree_executor` | Worktree 执行者 | 在独立 Git worktree 实施修改和验证 |
| `reviewer` | 审查者 | 代码审查和结果检查 |

探索协作由共用系统提示词统一约定：主代理在只读调查和 Task 的 planning 阶段也建议
按需委派 explorer，不以实施计划批准为探索前提；多个独立问题可按可用容量并行探索，
真实依赖保持串行。派发须提供自包含的背景、问题、范围、检索线索、来源要求及完成标准，
探索者返回结论、可追溯证据和不确定项，由主代理综合判断，减少原始检索材料占用主上下文。
该建议不扩大阶段或工具权限，不授权修改文件、Git 或外部状态，也不要求所有任务强制并行。

所有内置 Agent 由编译进二进制的代码声明表与 `include_str!` 提示词提供，不生成或修改
用户 Profile 文件；共同定义与可配置范围见 [12](./12-collaboration.md)。系统 child 的身份、用途、指令和工作区模式
不可编辑、不可删除，可通过主配置 `disabled_system_agents` 禁用。主智能体在会话起始页与
会话状态栏选择模型，不在 Agents 页配置；系统 child route 在子代理区域配置。用户 Profile
的文件名 stem 是 Agent ID。
`list_agent_profiles` 在固定模式只返回启用且路由可解析的 Profile；自动模式返回启用的
角色声明，不以其固定路由判定资格（见 [12](./12-collaboration.md) §12.7）。`spawn_agent` 创建 child 时冻结
系统指令、最终 account、model 与 effort，此后文件变化不改变既有 child；设置页另读完整
catalog，被禁用的用户 Profile 仍可编辑并重新启用。

系统 child 缺少专属路由时，整体继承 `mode.simple` 的 `account_id`、`model_id` 与 `effort`；
显式覆盖优先，覆盖失效不回退。继承由同一解析边界供 catalog、设置、固定派发及辅助消费者
使用，不因查询、启动、刷新或普通保存补写成持久覆盖。新增内置角色因此不要求升级主配置
或补齐路由；未知或 root 身份的 child route key 仍拒绝。用户 Profile 继续要求明确路由，
自动派发的显式选模规则不变。创建前冻结最终选择，默认值变化不改写已有 child。

显式设置系统 child 的模型或 effort 时，只保存该角色的完整覆盖，不改变其他角色或默认
选择；只改 effort 时以当前有效路由为基础。已有显式覆盖及禁用选择原样保留。每个实际
模型绑定都包含 `account_id`、`model_id` 和可选 `effort`。`effort` 使用字符串，校验对象是
对应模型 parameters 中 `name = "effort"` 参数的候选值：模型声明非空候选时，角色必须选择
一个合法候选；模型没有声明该参数时，角色必须省略 `effort`。候选、默认值和 wire 规则只
来自模型目录（见 [06](./06-model.md)），角色配置不保存第二份候选或默认值。account 不
保存 `default_model`，模型选择只由路由决定；历史结构按 20.1 转换，缺失必需路由或无效
引用明确报错，不能静默重置用户选择。
保存 account 字段时，未改动的 Mode 与 child route 原样提交，包括暂不可用的模型和 effort。
只有显式选择默认 account 或删除路由所属 account 才重新选择相应模型与默认 effort；实例
显示名变更不改变 ID、凭据和引用；账号 ID 不提供编辑重命名入口。编辑命令的空 effort 表示省略该选择，不从当前目录补入默认候选。
完整 child route 提交不构造备用路由，也不补写未配置角色的继承结果。
未承担新路由的在线实例允许其展示默认模型为空，不能让其合法空目录阻塞其他实例保存。

## 20.4 TOML 示例

本地 TOML 使用 `snake_case`，不同于 API wire 格式。精简示例：

```toml
schema_version = 25

disabled_system_agents = []

[runtime]
# 字段保留；当前版本执行路径固定 full-access，该值不影响执行（见 [04](./04-security.md)）。
permission_mode = "request-approval"
active_skills = ["rust", "git", "doc"]
active_mcp_servers = ["github", "filesystem"]

[instructions]
base_override = ""
developer = ""
user = ""
project_doc_max_bytes = 65536

[mcp.servers.filesystem]
enabled = true
transport = "stdio"
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "D:/workspace"]
env = {}

[skills]
enabled = true
auto_learn = true
project_dir = ".agents/skills"
user_dir = "~/.anywork/skills"

[mode_model_routes."mode.simple"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.task"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[models.routes.explorer]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[models.accounts.deepseek]
name = "DeepSeek"
base_url = "https://api.deepseek.com"
# API token 由系统凭据库保存，TOML 中不出现明文 secret。
tool_wire_policy = "function_fallback"
template = "deepseek"
protocol = "deep_seek"

[models.accounts.deepseek.catalog]
source = "bundled"
catalog = "deepseek"
```

## 20.5 Account 与模型目录

`models.accounts` 可保存多个 account，相同 template 可重复使用；唯一性只约束 map key。
每个 account 实例持久化：明确的 `protocol` 厂商适配选择、可选 `template` 身份（完全自定义账号可不保存 template）、实例
字段（`name`、`base_url`、`bearer_token_env`、`http_headers`、`tool_wire_policy` 与
`apply_patch_tool_type`）、catalog（`Bundled { catalog, additional_models,
connection_overrides }` 或 `Explicit { models, connection_overrides }`）与 capabilities
（`TemplateDefaults` 或显式服务能力：template 实例默认继承 canonical template 的服务能力，
custom 实例默认显式无能力）。

模板默认服务能力在当前配置中的判别值为 `capabilities.source = "template_defaults"`；旧
`preset_defaults` 只在 22→23 的版本转换中解码，不作为当前类型的别名保留。

Account 保存厂商协议适配，但不统一规定全部模型的 wire API 或连接方式。路由解析从当前 route
选择的模型绑定和目录 override 得到 wire API 与最终连接方式，再与账号所选厂商适配、endpoint、凭证、wire policy 和服务能力组合成
runtime 路由；模型 transport 是必填字段，合法矩阵为 Responses+WS/HTTP、Chat+HTTP。

服务能力不是模型能力的别名：account 服务能力表示 endpoint 可以执行 Responses hosted
tools、hosted 或 standalone Web Search（hosted search 还携带 OpenAIResponses 或
DeepSeekResponses 方言）以及图像生成（Images 方言与生图模型前缀），模型能力仍表示当前模型
能否使用 native search 或 function tools；核心编排必须同时检查 endpoint 服务能力、模型能力
与模型 request profile。官方
OpenAI endpoint 默认开启 Responses hosted tools；覆盖自定义 `base_url` 后默认关闭，只有
显式配置才能重新开启。产品 UI 从 catalog 的无密钥 descriptor 渲染预设和模型选项，不识别
具体厂商 id。OpenAI、MiMo API、MiMo Token Plan、DeepSeek、xAI、Zhipu 与 Zhipu Coding Plan 都
是账号模板，不是协议变体；明确的 protocol 选择装配厂商适配，两个 MiMo 模板共享同一
catalog，而 Zhipu（通用 Chat API）与 Zhipu Coding Plan（官方 OpenAI Responses 协议端点）
各引用与端点形态匹配的目录。xAI 引用独立的 Responses/HTTP 目录，canonical endpoint 继承
`prompt_cache_key`；覆盖非 canonical `base_url` 时由 TemplateDefaults 撤销该缓存方言。xAI
不声明 hosted search。当前不保留 Anthropic 占位：只有实现第二种协议族的
typed codec、能力模型与测试后，才可写入配置或 catalog。

canonical catalog 与自定义/附加模型使用同一个模型信息结构：model_id、display_name、
description、context_window、max_context_window、auto_compact_token_limit、
default_temperature、max_output_tokens、pricing、parameters、binding（transport 与协议
适用 request 配置）、capabilities、truncation_policy 与 base_instructions。capabilities
是结构化能力矩阵（见 [06](./06-model.md)）：每个 input capability 显式声明 modality、
允许来源和限制；两者不完整或无法把持久快照重新编码时该 modality 校验失败；未知模型
默认 text-only；非视觉模型即使 account wire API 接受图片字段，也会在任何附件 IO 和
凭据读取前被拒绝；PDF 使用 file modality。
Settings 的自定义模型快照必须携带同源的 typed input capabilities（modality、来源和限制），
经 FRB 投影到 Flutter，与内置 catalog 共用转换逻辑。附件入口不能因自定义模型元数据
在展示链路中丢失而退化为 text-only；本地和 SSH 项目使用同一能力判断。

ModelPricing 明确区分未知价格与包含费率的定义：货币不做汇率转换；输入、缓存读、缓存写
与输出按互斥类别计费，reasoning 已包含在输出内；非不计费调用的用量或费率缺失时标记未计价；
显式不计费、历史关闭估算与估算零费用分别表示；每次请求冻结价格定义、计量策略和发送时间，最终账单按最终用量
选择长度档位，跨时段请求不拆分 token（本地估算口径，见 [06](./06-model.md)）。内置价格
来源、核对日期及完整档位保存在后端目录，设置页直接展示后端提供的行；文档不保存价格
快照。

Bundled 默认定义只读；本账号显式配置的同 ID 模型定义优先于绑定的内置定义。
在线名单与手工配置共同决定该账号成员，定义和观察仅在 (account_id, model_id) 范围合成，
不从其它账号同名模型补全能力、参数、价格或绑定。同 ID 在线明确字段优先于本账号本地补全。
手动模型及其连接、压缩覆盖沿用既有增删边界，不改写历史账单。

### 在线模型观察与配置校验

目录同步只发生在程序启动的初始化阶段：对每个声明了发现能力的实例各提交一个独立任务，循环
只负责启动而不等待网络；各实例并行执行，互不持锁等待。每个实例拥有自己的查询身份（base URL
路径、适配器、影响查询的 header 与凭据身份）、请求超时、成功缓存文件与状态，任一实例的凭据
缺失、超时、协议错误或缓存损坏只写该实例状态，不影响其他实例、不阻塞首屏、不改写全局
revision，也不触发数据重置。运行期不存在第二次自动同步，也没有手动刷新命令；HTTP 与原生桥接
只提供同一 canonical snapshot 的只读观察。

目录状态由同一 canonical snapshot 发布：每个 account 的完整有效模型（含来源）与状态
（是否支持发现、来源 `default`/`cached`/`online`、检查时间、最后成功时间、类型化错误与缓存
警告）。界面只读展示该状态并提示“重启应用可重新同步”，不提供刷新按钮或本地补回。GUI 不从
预设补回在线名单中缺失的模型，合法空名单保持为空；旧选择以不可用状态保留。

配置解析先恢复该实例同身份成功声明或默认定义，再验证模型声明、结构与用户 Profile。支持在线
目录的既有 route/effort/connection override 因缓存缺失或服务撤下模型/候选而不可用时，保持用户
选择并返回外部绑定 unavailable，不自动猜模型、删覆盖值或触发全局数据重置。显式手工目录、
缺失 account、坏 schema 与声明本身继续严格校验；用户新保存/切换的选择须在当前有效目录中合法。
已知旧 schema 接续数据保全迁移到当前账号结构；模型观察缓存独立升级并保留未知来源旧快照。
解析规则升级保留旧成功快照，但在新规则成功获取正文前不发送旧 ETag；失败继续使用旧快照，
不能用清空缓存完成升级。模型类型只是最终目录查询条件，不写入账号配置或改写已有路由。

各实例探测按自身 generation/查询身份裁决结果，并合并到当前 desired 状态，不以开始时的旧全局
Settings revision 提交。别家成功不得使本家 stale；用户更换地址、headers、凭据或目录来源、删除
实例后，旧结果丢弃。等待网络不持全局配置锁。
账号字段变化在一次目录 revision 通知本账号受影响的绑定消费者：在途请求保持冻结，
后续安全边界 deferred 重绑或明确 unavailable；不因目录观察重装无关 account 的工具或重算历史费用。

有效目录的每条成员携带来源：`online`（本次或同身份最后成功的在线名单）、`bundled`（尚无成功
观察时的内置默认定义）、`manual`（用户手动添加）。来源由后端解析并随 descriptor 发布，界面
据此分组与标注，不按配置差集或 template 自行推导。删除手动模型使用独立命令
（`removeAccountModel`，携带 `operationId`、expected revision 与 account_id/model_id，回执原样
返回该操作身份）：只接受手动条目，删除后同步
清除该 model_id 的连接覆盖与压缩阈值覆盖；若它是该实例的默认模型，保留字段并沿用“选择以不可用
保留”的语义。目录观察、模型来源与手动模型增删都不改变 desired route 的其他字段。

## 20.6 提示词配置

`[instructions]` 保存供应商无关提示词来源的用户可配置部分，缺失整个表或字段时使用默认
值：

- `base_override`：完整替换当前模型的 `base_instructions`。仅用于需要完全接管系统提示词的
  高级场景；普通长期偏好不应写在这里。
- `developer`：追加受信规则，适合本地运行约束、协作偏好和稳定行为规则。该配置名称不指定
  API role；实际发送方式由模型协议分发契约决定。
- `user`：追加到 user context 层，适合用户背景、项目上下文和非强制偏好。
- `project_doc_max_bytes`：AGENTS 项目文档总读取上限，默认 `65536`，设为 `0` 表示禁用项目
  文档注入。
- `project_doc_fallback_filenames`：除 `AGENTS.override.md`、`AGENTS.md`、`Agents.md` 外
  额外尝试的项目文档文件名。

运行时会在 Thread 首轮固定基础、受信规则、user context blocks 与 AGENTS source paths；
已有 Thread 后续不会因配置或项目文档变化自动改变提示词，新 Thread 才使用新配置。
基础来源优先使用显式 `base_override`，其次模型基础提示词，缺失时使用产品内置基础提示词。
统一组合按基础、Agent、Mode、分发偏好、平台、配置规则、Skills 与其它约束的固定来源顺序
渲染，创建、Mode 更新、请求准备和压缩恢复共享正文与分隔规则，不在不同入口重复拼接。
结果以类型化系统提示词交给模型层，具体 `developer`/`system` role 及缓存更新策略见
[06](./06-model.md)。项目文档、用户背景与动态事实继续使用 user/runtime-fact 路径。

instruction snapshot 同时保存共同 Agent 定义身份、适用范围、来源与修订，以及角色指令
形状和内容身份、独立的 Agent/Mode 指令来源（职责见 [12](./12-collaboration.md)）。普通
root、飞书 root 和 child 统一消费此快照，角色正文只由 Agent 来源拥有，不额外维护一份
可变提示词。新建普通 root 同样有明确的 Agent 正文；base override 或模型 base 不覆盖
该来源。root 路由与 child Profile 的原有配置所有权不变。
Mode 的合法更新只变更 Mode 来源，模型基础指令重绑定只变更模型来源；恢复、压缩和工具
刷新不能以当前 catalog 重建 Agent 指令。
自动分发偏好作为独立的指令来源随同一快照保存，与 Agent、Mode 来源并列；它来自会话
已冻结的分发策略，不因 Mode 切换、压缩、模型重绑或恢复重新继承全局默认。旧快照迁移
保留已有偏好正文及来源，不将其误归入 Agent 或 Mode，也不向固定模式补入自动偏好。

旧版混用的 execution-profile 来源在显式快照版本迁移中区分：root 依据保存的 Mode 转为
Mode 来源，child 依据冻结 Profile 转为 Agent 来源。迁移保留原角色/模式正文、其他指令块
和历史请求，不为旧飞书会话补入新专用指令。新定义的身份与迁移后保留的旧指令版本必须
可区分，不伪称旧快照已经采用最新角色；缺失或冲突身份明确失败，不清空快照或恢复默认。
迁移与当前结构的读写共用现有保存边界，重启可核实并继续，不在每次模型请求里兼容旧格式。
旧根会话尚无独立 Agent 定义时，目录中的 root 身份与保存的 Mode/指令可证明原来的通用
根角色；若没有可验证的渠道归属，只能保存明确的迁移来源、渠道未指定的 legacy-root
定义身份，不能据“没有 bot owner”宣称它原本是普通渠道，也不能为此阻断全部旧普通会话。
此身份只由迁移产生，不是可新建或派发的预设。已存在的 bot owner 必须解码并验证，不能
仅凭同名扩展存在判定归属；缺失必要的 root/child、Mode/Profile 或指令事实仍须失败。
当前快照恢复校验冻结定义 ID、scope 与来源/修订的合法组合；迁移身份可以保留旧版本，
不要求与最新内置提示词版本相等，也不能借保留旧版本接受另一个 Profile 的身份。

包含具体 root 角色形状规则的旧表示在明确版本边界升级：先按旧规则校验，再从保存的
Agent 块推导当前形状与内容身份。旧普通 root 的无 Agent 块状态保留，不补入新角色正文；
已存在的定义修订不因补充形状字段改写为通用 legacy 修订。旧格式已允许且没有相反归属
证据的身份仍可恢复，不能从缺少机器人归属推定它必然属于普通渠道。迁移前后有效正文、
顺序、标签和 user source IDs 保持一致。正常结构校验只消费已冻结的
形状、内容身份与作用域，不再按具体角色 ID 或当前声明推断。迁移的事务与失败保全见
[17.7](./17-studio-storage.md#177-大版本隔离与配置迁移)。

上述冻结规则不冻结宿主运行事实：Platform、工作区绑定及 `studio.session-files` 在当前安全
边界由实际服务提供，恢复/刷新后按同 source 更新，压缩保留最新值。会话文件路径、权限与
helper 传输约定见 [14](./14-runtime-host.md)、[17](./17-studio-storage.md) 和
[22](./22-ssh-remote.md)，不写入用户配置作为第二份事实源。项目/会话归属清单也不是新增的
account 或模型设置入口，本次布局调整不改变全局配置 schema 与凭据解析。

## 20.7 运行态声明

`[runtime]` 保存本地 Studio 运行态展示所需的可选声明：`permission_mode`、
`active_skills` 与 `active_mcp_servers`。`permission_mode` 的字段与缺失时按
`request-approval` 处理的语义按 [04](./04-security.md) 保留，但当前版本执行路径固定
`full-access`：写入该字段不改变执行结果，GUI 也不提供读取或修改入口。
`active_skills` 与 `active_mcp_servers` 只声明启动时预选项，不作为真实发现来源：MCP
server 的用户启用意图来源为 `[mcp.servers.<id>].enabled`，真实可用性由进程内 registry
探测，不写回配置；真实 skills 能力由 `[skills]` 配置和项目目录驱动，当前 Thread 的
activeSkills 由后端持久化的 Thread 级激活扩展派生，其压缩重置与恢复契约见
[10](./10-skills.md) §10.6，不由启动声明或历史 Item 重新激活。

## 20.8 MCP 配置

MCP server 配置保存在 `[mcp.servers.<server_id>]` 表。`server_id` 必须非空，且只能包含
ASCII 字母、数字、`_` 和 `-`，因为它参与模型可见工具名；用户配置不得占用内置保留 id。
Pure 运行时还会合成一组内置 MCP server：内置 server 不写入 `mcp.servers`，但出现在设置页
和状态栏中，其 UI toggle 状态保存在 `[mcp.builtin_servers.<server_id>]`（该表不描述
transport 或 endpoint，也不允许新增 server）。

每个 MCP server 必须配置 `enabled`（默认 true）与 `transport`（`stdio` 或
`streamableHttp`）。stdio server 必须配置 `command`、`args`、`env`，可选 `cwd`；
streamableHttp server 必须配置 `url` 与 `headers`，可选 `bearer_token_env_var`。

启动后由 MCP runtime owner 观察 canonical 配置并后台 reconcile 启用且凭据完整的 server：连接建立由 connector
负责，PL 统一维护配置 fingerprint、增量 reconcile、工具命名、冲突检查、健康状态和
generation 原子替换；Studio 只负责组合配置。相同 effective fingerprint 的 reconcile 完全
no-op；手动重连走独立的单 server/All reset；reset 候选失败时保留当前 live generation；
shutdown 是不可恢复终止态。配置观察覆盖启动、保存、删除、凭据清空/轮换与显式重载；
在途准备期间的新变化可合并，但必须最终收敛到最新配置，不能因已有任务而漏掉变化。
协调任务由 runtime 持有并参与停止与 join，失败只进入 MCP 领域的可观察状态。它不属于
账号保存事务，也不要求任何模型 Thread 存在或使用特定 account。

内置 Zhipu Coding Plan MCP server 固定为：`zhipu_search`、`zhipu_reader`、`zhipu_zread`
（Streamable HTTP，官方对应 endpoint）与 `zhipu_vision`（stdio，经 npm 启动，Windows 运行
时从标准 npm 安装布局解析 node + CLI，配置和状态中不写平台后缀）。这些内置 server
只复用 `template = zhipu-coding-plan` 的有效 bearer token 作为 Coding Plan key；
存在多个实例时按 account ID 稳定排序选择首个有有效凭据的实例，不从普通 Zhipu template、
域名或 Thread route 推断凭据来源。解析优先级遵循 20.11。缺少可用 token 时内置 server
显示缺少凭据，不连接、不发现，也不向模型注册可调用工具；检测到 token 时，未显式配置
状态的内置 server 默认启用并进入通用后台探测，已被用户禁用的保持禁用。系统 MCP 与用户
MCP 共用同一运行时、健康、generation 和租约机制，不建立厂商专用 Thread 或搜索后端。

模型可见的 MCP tool 名称形如 `mcp__{server_id}__{tool_name}`。PL 对 server id 和远端
tool name 统一规范化，合成名称最长 64 个字符，冲突时追加稳定 hash 后缀；命名规则属于
公共 MCP runtime，产品 Host 和 UI 不重复实现。每个 turn 从 runtime 获取固定 generation
的轮次租约后再安装工具；新 generation 完全 ready 前不对新 turn 可见，旧 generation 在
最后一个租约释放后异步关闭（租约合同见 [09](./09-tool-runtime.md)）。

## 20.9 Skills 配置

`[skills]` 控制本地 skills 系统：

- `enabled`：是否启用 skills 目录、prompt 注入、工具注册和用户 `/name` 手势，默认 `true`；
  关闭时 Studio 仍可保留已发布 catalog 供设置页只读展示。
- `auto_learn`：是否在 Studio 主 turn 结束后启动后台 reviewer 自动沉淀项目 skill，默认
  `true`。
- `project_dir`：项目级 skills 目录，相对 workspace root 解析，默认 `.agents/skills`。
- `user_dir`：用户级只读 skills 目录，默认 `~/.anywork/skills`。
- `system.enabled`：是否启用内置系统 skills，默认 `true`。
- `external_dirs`：额外只读 skills 目录列表，默认空。
- `disabled`：禁用的 skill 名称列表，默认空。
- `auto_learn_min_tool_calls`：触发自学习 review 的最少工具调用数，默认 `5`。

目录优先级、frontmatter 格式、工具合同与自学习语义的唯一权威源见
[10](./10-skills.md)。系统内置 `studio-config` skill 是面向 agent 的 anywork 配置指南，
覆盖配置文件位置、当前 schema、常用配置段、凭据处理和安全编辑行为；任何改变配置路径、
schema 版本、配置段或字段及其默认值、凭据解析优先级、加载/保存/重载语义或最小有效配置
的变更，都必须在同一变更中同步更新该 skill，并复核 skill、本文档与运行时行为一致。

## 20.10 配置草稿与校验

anywork 设置页先加载 canonical account catalog，再构造产品草稿：默认选中 Studio 产品
默认 template，也可选择 catalog 返回的任意 template 或 Custom account；至少配置一个
account；可继续添加多个 account 实例，允许同类 account 重复，每个 account key 唯一。
template、endpoint、凭证提示、协议、允许连接模式、suggested model 和 bundled catalog 全部
来自 catalog 快照，Flutter 不保存生产目录副本。创建界面明确选择账号模板，草稿名默认取模板
展示名，切换模板以新模板完整重建草稿，用户可编辑名称。同模板账号可重复创建，每个账号只分配
一次稳定 ID；显示名、模板或 endpoint 均不充当身份。默认账号选择仅按既有作用域更新 Mode/角色
route，不给账号 runtime 写入第二份默认模型。

静态 account catalog 由启动事实加载器写入 `SettingsStore`，不属于 `readStudioState`
聚合快照。空 revision 或无 template 的目录只表示未初始化，不能覆盖已有目录；设置页、状态
栏和其他产品投影必须通过同一个 catalog selector 取得 Logo 与 template 元数据。

内置目录装配失败必须沿目录查询、模板选择和草稿构造接口返回原始错误，不得静默使用空目录
或触发 panic；此类错误属于程序定义故障，不进入用户配置损坏的重置流程。

设置项写入前必须完成本地校验并由 Studio 统一执行完整校验，失败时只在 UI 展示错误，不
写入磁盘：

- account key 非空且唯一；template 引用必须存在；Custom account 必须显式选择 wire
  protocol。
- Responses + WebSocket/Http 合法，ChatCompletions + Http 合法，ChatCompletions +
  WebSocket 在发起网络请求前拒绝。
- API key 非空（本地无鉴权服务允许省略）。
- 每个角色 route 的 model 必须存在于对应 account 的有效模型集合；同一 account 下模型
  model_id 不重复。
- 角色引用的默认模型必须声明 effort 参数且至少一个候选值，用于生成角色 effort。

## 20.11 凭据策略

Account 的 API token 保存到操作系统凭据库，service 固定为 `anywork`，account 为
`account:{account_id}`；`config.toml` 不保存 token、凭据引用或可逆密文。Account 仍可
保存 `bearer_token_env` 环境变量名。配置加载后，Studio 在 Rust 内存中注入系统凭据；运行
时按"系统凭据优先，其次读取非空环境变量值，空白值和缺失环境变量都视为无凭据"解析。

设置页的 Preserve/Replace/Clear 语义保持不变：Preserve 不改系统凭据，Replace 在配置提交
前写入并回读，Clear 删除凭据。凭据操作和 TOML 原子替换作为一个 fail-closed 提交流程；
凭据阶段失败时不得覆盖配置文件。版本迁移需要改变 account 标识时，须按明确映射保留
凭据关联：目标凭据写入并回读验证后才提交配置引用，旧关联在整个迁移成功前保持可恢复，
不能仅按默认 account id 加载凭据。账号迁移从 `provider:<id>` 复制到 `account:<id>`，目标存在
不同密钥时明确拒绝，不覆盖；相同值可幂等接续。旧项保留为迁移前凭据，不在正常运行回退读取，
本次升级不自动删除。没有系统项时保留环境变量引用，不伪造空密钥。历史内联凭据仅能在迁移边界转入系统凭据库，不进入
当前配置、日志或 UI；包含敏感内容的原始备份必须受保护。安全边界见 [04](./04-security.md)。
迁移的系统凭据复制要求持久服务成功写入并回读；不可访问不能被解释为“原项不存在”，也不能
用进程内 lease 的回读通过耐久校验。普通进程临时 secret 的生命周期不因此扩大为持久承诺。

机器人沿用同一系统凭据服务与进程 lease，不新建独立密码库。每个 `bot:<bot-id>` 账户保存
版本化受保护材料，机器人配置引用精确版本；读取时同时核对机器人、应用与版本，不以
系统中任意旧值覆盖新 lease，也不以 lease 的存在冒充系统已持久保存。候选准备、引用提交
和未引用材料回收遵循 [27.2](./27-bots.md#272-管理配置与凭据)；版本迁移保留原配置与
凭据关联，服务不可访问不等于原值不存在，不能通过默认值或清空完成迁移。该契约不扩大
Provider、SSH 或 MCP 的凭据格式及修改范围。

MCP stdio server 的 `env` 按配置原样传给子进程，可能包含明文凭据。Streamable HTTP 的
`bearer_token_env_var` 只保存环境变量名，运行时从 Pure 进程环境读取对应 token 并构造
Authorization header。

## 20.12 Web 搜索配置与凭据门控

Studio 保留两段互不混用的顶层配置。`[web_search]` 只配置 OpenAI 搜索：`mode` 为
`disabled | cached | indexed | live`，默认 `cached`；`context_size`、`allowed_domains` 和
近似位置均可省略。`[deepseek_web_search]` 只有两个开关：`enabled` 表示联网搜索、
`fetch_enabled` 表示网页抓取，都默认 `true`；缺失整段或单键时同样按启用处理。结果条数、
正文开关与官方其它可选请求参数是代码内的固定部署值，不进入配置；DeepSeek 也不接受
cached/indexed、域名、位置或 context size 等 OpenAI 专属字段。

搜索不是单选：`StudioWebSearchSettings` 暴露 configured/effective/availability、
account_id/model 与原配置开关 `mode`；`StudioDeepSeekWebSearchSettings` 暴露
configured/effective/availability、account_id 与 `enabled` / `fetch_enabled` 两组配置位，
不含模型字段。两者都没有 `selected` 字段，也不存在互斥的 exclusive 路线；
`effective_* = configured_* && availability == available`。canonical DeepSeek template 声明
`DeepSeekToolsApi` 独立能力；template 实例覆盖非 canonical base_url 时由 TemplateDefaults 仅撤销
该 DeepSeek 方言（连同其它 hosted/Responses 能力），非 canonical DeepSeek endpoint 必须显式
声明该方言。此撤销同时关闭继承的 prompt cache dialect，不改变既有 OpenAI `OpenAiSearchApi`
继承语义：覆盖非 canonical base_url 的 OpenAI endpoint 仍保留 `/alpha/search` standalone。
显式 capability 仍可重新声明。

设置页运行独立的 service planner，不依赖会话、route 或当前模型：每条后端只按 account
capability 与凭据解析 configured/effective/availability、account_id 与 model。OpenAI
standalone 服务优先使用该 account catalog 的 `gpt-6-sol`，否则用该 account 首个有效模型；
account 之间按 ID 稳定排序。DeepSeek standalone 服务不解析模型：它直接命中原生工具接口，
线程内优先声明该能力的 DeepSeek account，否则同样按 ID 排序。服务模型与会话模型独立，不再按
explorer / planner / executor / worktree_executor / reviewer role route 选模型。

实际 thread 消费时才用当前模型是否支持 function calling 决定本轮是否注册对应 standalone
搜索工具，它不改变设置里已解析的服务可用性。OpenAI standalone、DeepSeek 原生 standalone 与
可用的 hosted 搜索互不抢占，也不隐藏 MCP、LSP、文件和命令工具；只有 DeepSeek 搜索工具的
两个工具描述写明按请求次数计费与兜底条件，其他搜索不分优先级、不按 account 排序、不自动跨
账号回退，也不因某一路可用而停用另一路。

配置值与生效值必须分离：缺少有凭据的 account 时保留 configured mode，但 effective mode
为 `disabled`——此状态下不得注册对应 standalone 或 hosted 搜索工具，也不得为它创建客户端。
DeepSeek 两个开关同构：account 不可用时保留 configured 值而 effective 位为 `false`，两个开关
各自独立解析，不合并成单一状态。
服务 planner 的每后端可用性只看 account capability 与凭据（`disabled` / `missingCredential` /
`accountUnsupported`），不因当前会话角色或模型不可用而降级；当前模型能力只在真实 thread
消费时生效。`cached` 映射为禁止外部实时访问；`indexed` 映射为显式 indexed 访问；`live` 允许
实时外网；`disabled` 完全关闭该路径。两张卡片的保存命令都携带 Settings CAS revision，成功后
以完整 canonical snapshot 回写（多后端仲裁见 [06](./06-model.md)）。

## 20.13 LSP 自定义 server 配置

自定义语言服务器声明在 `[lsp.servers.<server_id>]` 表。每个条目必须配置 `command` 与
非空 `language_ids`，可选 `args`、`detection`（workspace 检测文件名/glob，缺省总是匹配）、
`extensions`（文件扩展名，缺省为空）、`display_name`（缺省使用 server id）和
`operations`（`lsp_query` 操作子集，缺省支持全部）。示例：

```toml
[lsp.servers.purelang]
command = "purelang-lsp"
args = ["--stdio"]
language_ids = ["purelang"]
detection = ["pure.toml"]
extensions = [".purelang"]
```

该段与 pl-lsp 内置 catalog 合并；重复 server id 或 language id 与内置/其他自定义 server
冲突时，配置校验以类型化错误 fail-loud，保留原配置，版本处理遵循 20.1。自定义 server
使用通用命令 driver（`<command> --version` 探测，无 repair 语义），运行行为与路由合同
见 [21](./21-lsp.md)。Studio 项目激活时把该段应用进 LSP registry catalog，并纳入激活
fingerprint。

## 20.14 独立设置命令

配置 mutation 按最小业务资源拆分：account 实例、默认 account、account 删除、单个 Mode
route 的 model、单个 Mode route 的 reasoning effort、单个 Agent role 的 model、单个 Agent
role 的 reasoning effort、permission、instructions 字段、skills 字段、单个 MCP server、
general 字段、web search 字段和 DeepSeek 的搜索/抓取两个开关各自有 typed command。每个开关
命令只改自己的布尔值，另一开关与其它字段由配置 owner 从最新 canonical state 解析。所有 command
携带当前 `expectedSettingsRevision`，由同一 runtime command lock 做 CAS；成功返回新的 canonical
Settings snapshot 并发布设置事件。Bridge 与 loopback HTTP 均使用 `PUT /api/v1/settings/field`
承载 `SettingsFieldUpdate`，FRB 只暴露同一 typed handler。一个 command 不得把页面当前完整 account、roles、mode
routes 或其它字段的旧副本作为无条件替换值；需要迁移引用时必须在删除命令中显式给出替换目标。
这里的“同一 handler”只表示传输入口稳定；请求体的 `kind` 是单字段/单资源类型，服务端
不得根据一个字段请求顺带修改其它设置。Account 与 existing Thread route 仍是资源级原子
接口，因为 endpoint/凭据/模型声明或 runtime route 需要联合校验；它们不会把其它 account、
Mode、role 的旧快照带入提交。

启动期目录观察属于另一个水位与 command lane，只推进 `modelCatalogRevision`、account catalog
状态和有效模型描述。它不会修改 desired route，也不会阻塞配置 command。route 指向被撤下的
模型时保留 desired 值并返回 unavailable；用户显式选择的新 route 仍需按当前有效目录校验。
删除手动模型的命令走配置 lane（canonical-CAS 与联合校验），与目录观察互不代替。

## 20.15 模型标识与账号目录

配置 schema 22 将模型对象中的 `slug` 迁移为 `model_id`，保留标识值、账号与凭据关联、连接和压缩覆盖。
旧字段只在版本化迁移边界解码；冲突或校验失败保留原文件。账号隔离目录以 [模型契约](./06-model.md)
为准，Mode 不再限制模型；请求准备校验保留。
已知版本迁移失败以独立的 Migration 错误沿启动链路传播，不能进入持久化数据损坏的自动重置流程；
界面报告迁移失败与原文件保留，修正配置后可重新启动。

## 20.14 自定义工作模式

自定义工作模式位于数据根的 modes 目录，每个 `<mode-id>.json` 保存一份完整 Mode 文档；
默认根为 `~/.anywork`。执行字段和图约束见 [11](./11-thread-mode.md)，布局元数据独立于执行定义。
提供 JSON Schema 和显式校验命令；JSON 输入只用于配置创作，运行态和 transport 投影使用 typed DTO。

配置 owner 在启动、保存、删除和显式重载时访问目录；查询只读取已发布的不可变快照。保存与删除
使用目录 revision 比较交换、同一命令串行通道和原子文件替换；内置 ID 受 owner 保护。重载先完整
读取和校验所有文件，失败保留上一份有效目录，不静默跳过坏文件。外部文件变化只通过显式重载生效。
保存返回 canonical 定义和目录、命令回执；产品事件和命令响应由同一 Client reducer 合并。

自定义模式最多 128 个；每份 JSON 最大 256 KiB。布局最多 32 个节点，坐标必须有限且绝对值
不超过 1,000,000。坏文件阻止启动并保留原文件及其他配置，不进入产品数据库的自动重置流程。

## 20.16 图像生成配置边界

图像生成能力不是用户配置项：它由目录声明的协议 endpoint 服务能力（Images 方言、生图模型 slug
前缀与首选模型）、当前在线目录观察和账号凭据可用性共同决定，语义见 [06](./06-model.md) §6.13。
本版本不提供独立开关、模型选择、尺寸/质量偏好或代理地址；配置中也不保存第二份生图模型名单。

覆盖 `base_url` 的 account 继续沿用目录声明：Images 路径追加到该 `base_url` 前缀，与
standalone Web Search 一致；凭据复用同一 account 的显式 secret 或 `bearer_token_env`，遵循
20.11 的注入、脱敏与不回显规则。凭据缺失只让生图工具不注册，不改写配置、不产生错误弹窗，
也不影响该 account 的对话模型与其他工具。

目录观察不进入配置 command lane：它只推进 `modelCatalogRevision` 与有效目录，热刷新据此重新
规划工具装配；删除或更换 account 后，原工具目录按撤销语义失效，配置只保留用户显式写入的
account 与路由事实。
