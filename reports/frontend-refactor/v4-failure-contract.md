# v4 错误类型与写入结果证据

适用R/D0/D1/D2/D3/A/U/C。错误code与native写入是否发生是两条轴，不能根据
Unavailable/Storage/Protocol或message推断可安全重发。以下是共享边界，不增加错误总线。

## 1. StudioFailure

Rust StudioError/BridgeError及Dart StudioFailure继续保留code、message、retryable、
correlationId四项；details改成下面封闭typed值，不保留Dart detailsJson解码/文案fallback。
内部cause/stack只由原owner持有。Dart值Freezed并实现Exception；生成FRB异常不出adapter。

```text
StudioFailure {
 code:StudioFailureCode,message:String,retryable:bool,correlationId:String,
 details:StudioFailureDetails?
}
StudioFailureCode = notInitialized|runtimeStopped|instanceBusy|invalidArgument|notFound|
 busy|conflict|staleRevision|superseded|permissionDenied|cancelled|cancellationTooLate|
 overloaded|unavailable|protocol|storage|update|internal

StudioFailureDetails =
 startup{step:String,kind:StartupFailureKind}
 | revision{expected:int,actual:int}
 | sshAuthentication{passwordOffered:bool?}
 | reason{reason:String}
 | identity{identity:String}
 | timelineRevision{itemId:String,field:String,revision:int}
 | validation{issues:List<ValidationIssue>}
 | thread{threadId:String}
 | resourceLimit{resource:String,capacity:int}
StartupFailureKind = modeDefinitions|migration|persistentData|environment|cancelled|internal
ValidationIssue {code:String,path:String,message:String}
```

superseded是新增稳定错误类别：已知旧读取版本不可取得，HTTP 409；不替代命令CAS的
staleRevision，也不是事实不存在的notFound。旧可重试读取错误如Timeline ReadInvalidated
仍按原Busy/retryable处理；关闭Cancelled优先。Mode结果/VM的原ModeValidationIssue在Dart
统一用resources域ValidationIssue，字段不变，删除旧同构类型/别名；Rust原Mode issue类型
仍由protocol自己的Mode模块拥有，adapter逐字段转为这一Dart值。

上列details对应当前error_mapping.rs、Mode validation及thread cleanup的实际producer：
startupStep/startupKind、expected/actualRevision、sshErrorKind/passwordOffered、reason、
identity、itemId/field/revision、issues、threadId。迁移所有producer与server OpenAPI，
不保留任意JSON Map入口让UI猜结构。resourceLimit用于真实预算拒绝，不扩充允许资源数量。
timelineRevision.field保原诊断字段值，不从它的文本推导业务动作。

SSH只匹配typed sshAuthentication，删除`Permission denied`等字符串contains判断。
passwordOffered=true允许密码提示，false不提示；None明确未知，可保留原“允许用户显式
尝试密码”的UI路径，但不能把未知显示成服务端已声明支持，更不能自动重试/保存密码。
失败后是否恢复旧密码、何时记住密码仍由原Remote owner负责。

## 2. Query失败与写入失败分开

纯read/page/validate/search失败抛StudioFailure，表示读取失败，不改canonical事实、不创建
operation。query参数/UTF8边界非法为invalidArgument，版本丢失superseded，来源损坏storage/
protocol，关闭cancelled，预算overloaded；无正文不能冒空结果。每个query仍join实际底层工作。

所有mutation port保持`Future<具体Reply>`形状，但只允许下列typed exception表达写入结果：

```text
CommandDispatchFailure =
 rejected{failure:StudioFailure}
 | unknownOutcome{failure:StudioFailure}
 | committedButUnobserved{receipt:CommitReceipt,failure:StudioFailure}
 | confirmedWithoutUsableReceipt{failure:StudioFailure}
```

这个Freezed exception只从operations_ports公开给adapter/Repository，不给VM；VM收到的
是共享CommandResult。普通query不会抛它。判断依据为真实dispatch/commit阶段：

- rejected：没有native dispatch，或native明确证明没有受理/提交；不是“任何BridgeError”。
- unknownOutcome：请求已经可能被受理，但没有足够证据判定；断线、缺终态EOF、无法识别
  响应、commit前后界限不明均属此类。原ID/payload/目标保留，不自动重发。
- committedButUnobserved：原native commit已知并有可用真实receipt，后续投影/读取/交接失败。
  Repository返回syncFailed，不能把它当rejected，也不能为修观察问题再写一次。
- confirmedWithoutUsableReceipt：native成功确有证据，但该接口没有receipt，或外层成功
  已可靠识别而原receipt在adapter中无法无损表达；返回acknowledgedSyncFailed。不从
  诊断文字猜成功，不能用无法解码的整包响应走这条分支。

adapter对“已可靠识别native成功，但Dart receipt转换失败”的情况保留原typed native证据
和诊断到原请求owner收束，不通过舍入u64或伪造revision构造可用receipt。此处acknowledged
只证明真实成功确认，不证明不存在native receipt、observed/effective/durable或完整业务结果。
普通成功的acknowledged(T)仍只用于原本无receipt的接口，不能随意丢掉正常可映射的receipt。

## 3. Native明确交付命令结果，不让adapter猜测

R为每个具体命令reply声明具体typed outcome，FRB对每个reply生成具体枚举，不通过一个
万能payload union包装全业务。相同语义模板如下（T替换为该接口确定的Reply）：

```text
<Reply>Outcome =
 returned{value:T}
 | rejected{error:StudioError}
 | unknownOutcome{error:StudioError}
 | committedButUnobserved{receipt:StudioCommandReceipt,error:StudioError}
 | confirmedWithoutReceipt{error:StudioError}
```

正常native handler外围Result错误仅处理未能交付此typed outcome的边界错误；adapter在已
dispatch后无法确认结果时保守unknown，不把外围错误自动当rejected。明确尚未初始化/
已封准入也应从native的已知拒绝路径交付rejected，不让业务调用方解析error字符串。

各权威writer必须在真实commit点区分“写入未发生”与“写入已发生但后处理失败”，使用原
commit/CAS结果/持久化返回，不新建operation去重账本。若原依赖只能报告结果未知，就保持
unknown；不能为了减少unknown把after-commit错误伪装成before-commit。原有幂等读取路径
按真实身份/原决定返回NoChange，不额外声称外部operation ID已被持久化。

Stream型创建/preparation同理：明确失败终态只有在owner证明未成功或已完成规定补偿时
才是rejected；缺终态/断流是unknown。accepted句柄/open guard在报告结果前真实登记，
响应丢失不许可放弃native资源责任。

## 4. Repository到ViewModel的最终结果

共享CommandResult的syncFailed允许`value:T?`（读取未组装完完整T时为None），receipt仍必需。
acknowledgedSyncFailed已有value:T?和error，无伪receipt。OperationState失败phase保持
rejected/unknownOutcome/syncFailed三类，acknowledged与有效receipt互斥：

| 实际结果 | CommandResult | OperationState |
| --- | --- | --- |
| 已知未受理 | rejected(error) | rejected，无receipt，不因UIdispose重试 |
| 结果不明 | unknownOutcome(error) | unknownOutcome，保冻结输入/原ID |
| 有receipt且必要观察完成 | committed(value,receipt) | 保receipt及独立observed/effective/durable |
| 无receipt真实成功且所需归并完成 | acknowledged(value) | acknowledged=true；其它事实不伪造 |
| 已知有receipt、后续同步失败 | syncFailed(value?,receipt,error) | receipt保留，syncFailed |
| 成功已确认但没有可用Dart receipt、后续失败 | acknowledgedSyncFailed(value?,error) | acknowledged=true，syncFailed |

这不是retryable布尔值到“可重试写入”的映射。explicit retry查询/close可基于对应能力，
unknown写入只能按原身份核对真实后续事实或用户明确决定；不换OperationId自动重发。
batch保留每步独立结果与notStarted，账号save/default两步不合并成一份成功或回滚。

## 5. 关闭与诊断边界

source ObservedResourceError仍只有code/message/retryable；StudioShutdownIssue仍完整五字段。
两者不因改错误模型互相冒充。CleanupRecovery正交表示真实await/retry/terminal能力，不能
改变原错误retryable来假装可恢复。原cause和秘密不进入Freezed值、Driver快照或日志；
Driver只保既定安全nullable诊断元数据，不为解释新错误增加明文token/密码/答案字段。

最终须迁移所有穷尽匹配、FRB DTO、server状态码/OpenAPI、fake/demo、测试和UI；任何新
unknown enum或未识别typed payload都明确Protocol，不能恢复旧detailsJson/文案兼容兜底。
本节仅冻结契约，尚无编译、测试或原生通过证据。
