# v4 命令receipt与canonical观察水位

本册固定[操作合同](./v4-shared-contract.md)的实际source映射，适用R/D0/D1/D2/D3/A/C。
所有ResourceStamp.ownerEpoch继续采用真实runtime.owner_epoch，不从投影incarnation、
delivery sequence或文件hash拼造。ProductReadOrigin保护读取来源，ResourceStamp表达原
canonical业务时钟，二者不可互换。

## 1. 精确资源键与观察来源

| resourceKey | revision的唯一来源 | Dart可确认的canonical观察 |
| --- | --- | --- |
| settings | ConfigRuntimeSnapshot.revision | ConfigurationHeader.configuration_revision有值且同runtime epoch；不是source Observed状态revision |
| agent-profiles | 原AgentProfilesSnapshot.revision | AgentProfilesHeader.profiles_revision；不是单文件Profile.revision字符串，也不是settings revision |
| thread-mode-catalog | ThreadModeRegistry/ThreadModeCatalogSnapshot.revision | ModeCatalogHeader.revision；非产品projection revision |
| thread-directory | ProductEventBus.revisions.thread的DomainRevision，即DirectoryDelta.revision | ThreadDirectoryHeader.directory_revision；与该scope内容同一source水位 |
| thread-mode:{threadId} | 已提交core snapshot中studio.mode extension记录的revision | ThreadConfigurationValue.mode_binding_revision有值 |
| thread-route:{threadId} | studio.model-route extension的真实revision（以原常量键为准） | ThreadConfigurationValue.model_route.revision或同版route详情revision |
| interaction:{wireId} | 原Interaction.revision | 同Thread/interaction身份、精确revision及回应终态事实；另需identity predicate |

threadId/wireId原样构造完整资源key，不按冒号再次拆分，不新增ID长度限制。未取得某来源
value时不发布0水位；last-known旧origin不能冒充当前owner已观察。大于等于比较只对同一
resourceKey/runtime epoch成立；identity-required操作还必须核实际同身份事实。

## 2. 各命令receipt全集

| 命令 | targets | disposition / effect / effective / durable / identity |
| --- | --- | --- |
| saveAccount/setDefault/removeAccount/removeModel/permission | settings | 原changed→Applied或NoChange；futureSession；effective=false；durable=true；identity=false |
| applyField的GeneralFollowActiveTurn/CompactTimeline/SidebarWidth/PinnedThreadIds/PinnedProjectIds | settings | changed决定；immediate；effective=true；durable=true；identity=false |
| applyField其余字段 | settings | changed决定；futureSession；effective=false；durable=true；identity=false |
| saveProfile/setSystemProfileEnabled | settings与agent-profiles（本次新增独立target） | changed决定；futureSession；effective=false；durable=true；identity=false |
| Mode save/delete/reload | thread-mode-catalog | changed决定；nextTurn；effective=false；durable=true；identity=false |
| Thread setMode | thread-mode:{id}与thread-directory | Applied（同Mode重选也真实重建）；immediate；effective=true；durable=false；identity=false |
| Thread setModelRoute | thread-route:{id}，仅modeDefaultSaved=true时再含settings | routeChanged或defaultChanged决定；nextTurn；effective=false；durable=false；identity=false |
| Thread rename | thread-directory | changed决定；immediate；effective=true；durable=false；identity=false |
| Thread archive | thread-directory | Applied；immediate；effective=true；durable=false；identity=false |
| interruptTurn(expected Turn身份) | 空targets | interrupted决定Applied/NoChange；immediate；effective显式false；durable=false；identity=true |
| respondInteraction | interaction:{wireId} | 实际changed决定；immediate；effective=true；新回应durable=false，命中精确已存回执才true；identity=true |

durable=true的Settings/Profile/Mode含义是对应原文件/凭据事务已完成，不声称现有Thread
采用配置。Thread mode/route的持久化仍独立；不能因为它们同步返回成功就标durable。
nextTurn不表示当前模型请求已切换，futureSession不表示已运行child使用了新Profile。

原stop_prompt只有threadId/stopped且无receipt；不能包装成上表interrupt receipt。
UI停止走冻结threadId+turnId的interrupt能力。submitPrompt原无通用native receipt，按
Conversation合同acknowledged(SubmitPromptReceipt)并另观察历史输入身份。手动压缩、
Usage check、SSH、资源retry/reset/probe/discover、Project动作、Updates动作均无原生
通用receipt，不能为统一表格伪造。配置reload也是无receipt的真实磁盘导入动作。

## 3. Thread Mode改用真实binding水位

删除本命令旧`thread-state:{threadId}`/core commit_sequence target，改为本册thread-mode
binding target，不保旧key兼容观察路径。原因不是core commit不真实，而是五域分频后
不能把每个无关core提交强塞configuration feed来满足一个旧聚合水位。

ThreadConfigurationValue新增`mode_binding_revision:Option<u64>`，对应当前studio.mode
extension记录。现有mode_revision明确仍是ModeManager/catalog水位；这两个字段不能
相互代替。缺失extension保None，不能用extension_sequence预测或补0。

R从`ThreadHandle::reconfigure`成功返回的committed snapshot读取实际extension revision。
core stage_extensions对每个Put分配实际新sequence，相同mode重选也有新binding revision，
同时保原重建context/指令/工具的真实行为。若成功commit后读取不到必需extension，这是
已提交后的明确Protocol/同步失败路径，不伪装未受理；保原commit事实，不换ID重试。

configuration只在其实际字段/来源改变时发布；仅token计量或无关core commit不得提升
mode_binding_revision，亦不把全core commit clock添加到所有facet header。

## 4. Profiles独立提交与读取目标

Profile专用port reply（普通Settings reply不增加Profile大桶）：

```text
ProfileCommandReply {
 receipt:CommitReceipt,configuration:ConfigurationReadTarget,
 models:ModelCatalogReadTarget,profiles:AgentProfilesReadTarget
}
ConfigurationReloadResult {
 configuration:ConfigurationReadTarget,models:ModelCatalogReadTarget,
 profiles:AgentProfilesReadTarget
}
```

`ConfigurationPort.saveProfile/setSystemProfileEnabled`返回Future<ProfileCommandReply>；
对应native具体ProfileCommandReplyOutcome。reload返回上述无receipt结果，不造父事务。
各ReadTarget完整携原origin/reference，native注册已捕获的真实source，不从最新feed补身份。

ConfigRuntime在原command_lock覆盖的命令边界内完成保存/更新、adopt_scan后捕获
AgentProfilesSnapshot，同时返回真实ConfigRuntimeSnapshot及changed。系统Profile启停
新增同边界的专用ConfigRuntime能力（或者等价的明确命令结果接口），不能先退出通用
update再在外面读Profiles并宣称是本次结果。save用户Profile与reload同理捕获，closing
必须封这三个入口且等待真实工作。目录内容未变时Profiles revision保持原值，不伪造增长。

R用捕获snapshot登记AgentProfilesReadTarget，并在Profile receipt加入
resource_stamp("agent-profiles", snapshot.revision)。D2在settings和profiles各自真实
source水位满足后才认为必要观察完成；一个settings更大revision不能证明Profile已收敛。
每个Profile源单文件revision/content_hash仍完整可读，与resource revision分开。

## 5. Directory来源与页一致性

ThreadDirectoryHeader新增`directory_revision:Option<u64>`，来源为原ProductEventBus
thread DomainRevision，与DirectoryDelta.revision严格同钟。无value时None；有value时
不能按投影stamp、页加载次数或最后收到的delivery序号构造。

R必须使scope内容与此source水位一致：原query_threads已有捕获thread revision、冷读后
核验的流程；原未筛选baseline/page先冷读再取水位的路径也补同样的捕获/核验，不能把
混合时刻内容标成新source版本。源推进而无法保相容视图时明确StaleRevision/局部resync，
不把旧页强行写成新canonical。实际排序/keyset与大窗口覆盖仍按产品合同。

另一个真实依赖必须同时处理：带search的query还按Project.name/path匹配。原代码先取
project_snapshot，再只校验thread revision，不足以证明该匹配集始终相容。新搜索scope
额外捕获Project目录的真实source revision，冷读后也核验；搜索scope监听Project与Thread
两个原来源。Project名称/路径变化可能使成员跨窗口，按同一查询重算或局部resync，不漏
成员。Header增加`search_project_revision:Option<u64>`，无search依赖时None；这不是
thread-directory receipt的替代时钟，不把Project变更假写成Thread DomainRevision增长。

两个source变化但结果实体/列表相同，稳定正文refs不失效；来源metadata与projection水位
按真实观察更新。不能因此在Dart另造目录谓词、第二index或靠当前显示名字匹配原ID。

## 6. 身份屏障、late evidence与消费者迁移

interrupt空targets不是自动Observed；原同Thread/目标Turn的权威终态才证明observed与
后续effective。respond须匹配原interaction、expected revision与一致回应终态；remove、
Cancelled/Expired不证明回应成功。history保存只从精确版本回执确认，不能latest冒旧版。

D0 OperationRecorder只接本表真实ResourceStamp，D1/D2/D3在各自唯一canonical归并点
发布观察；adapter/VM不手动推进。原result Future只结算一次，晚到真实证据只更新同一
OperationState；未显示页面不解除受理/unknown操作的观察责任。

C迁移所有旧thread-state观察、Profiles“只等settings”的断言及fake receipt source，
不降低identity-required断言。最终验证覆盖同mode重选、Profile source延迟与并发更新、
目录冷读交错/Project搜索变化、无value不伪水位与同数字不同owner；此阶段不执行测试。

实际来源：runtime `command_receipts.rs`、`settings_api/mod.rs`、`thread_mode.rs`、
`mode_definitions.rs`、`prompt_runner/{stop,interaction}.rs`、`thread_service/threads.rs`；
ConfigRuntime `config/runtime/mod.rs`与profiles_resource；Directory `product_event_bus/
thread_directory.rs`；core `thread/handle/operations.rs`与`thread/extensions.rs`。
