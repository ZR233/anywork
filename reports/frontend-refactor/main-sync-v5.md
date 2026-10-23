# v5 最新主线同步与实施起点

## 第三次同步：已保全当前重写成果后更新主线

用户再次要求先rebase最新代码后继续，本次冻结main为
`d3bc74189b81dd8ad50ce71caa8aaaef4e3db525`，当前重构输入HEAD为
`657126a36b2cce49f82d872147209b3248f7cfcf`加全部未提交重写成果；以下第二次同步记录保留
为历史，不再作为当前HEAD。最终贡献比较基线同步为d3bc，不把上游CI/版本变化算作任务收益。

- 本次上游仅新增CI预编译工具/并行质量job和6.25.0发布记录，共9路径。
- 三份文档提交rebase后为d69958f7/1ba6eefe/657126a3，range-diff均为等值补丁；没有把未验收
  实现提交作备份。发布版本原样采用上游，不自行选版本或发布。
- 同步前完整保全782变更路径，其中524个现存文件与258个缺失；全部415个untracked新实现
  均保留。隔离执行、fresh静态审查批准后，root串行整合并再次核对全部2329路径。
- 522个现存dirty文件字节不变，仅pr-quality与design/24合并上游增量；其它7个上游文件
  原样更新，86个生成文件全部不变。没有重跑旧删除清单、恢复旧facade或apply旧stash。
- CI保留三个独立质量job、固定预编译工具和禁止源码fallback，以及本任务已有bridge检查；
  所有lockfile保留同步前身份。index/unmerged为空，git diff --check通过。
- 只做静态同步核验，未编译、测试、格式化、生成、GUI或运行CI；当前本地HEAD尚未推送，
  PR已发布的c262文档CI成功不代表当前实现通过。

同步完成后继续原11组模块任务与局部静态审查，批准v5不变；不因rebase重新冻结全部合同。

## 第二次同步记录

按用户“先rebase一次最新代码，再继续”完成第二次安全同步。当前批准计划仍为v5，正文
SHA-256 `8a2ca6788466623b70f526ab6781477f21359e9306b887a64f53f956c0fb12d1`；其中先前基线
记录是批准时事实，以下更新实际实施起点和最终贡献比较基线，不重新开启合同冻结。

- 新冻结main：`80a51e78b9e37ba90e4206c30a5afaf7af54013c`。
- 当前重构输入HEAD：`e44f41ccb2491d08feb8db2b410ae7cd07d93912`，再叠加已保全overlay。
- 三份纯文档提交由78a/9e00/c262变为d503/f19c/e44；后二补丁不变，第一份按root决定保留
  上游设计与目标分域架构，远端查询归RemoteRepository/RemoteDirectoryQuery。
- 隔离执行与fresh静态审查通过后，root串行整合并实核309路径身份、776保留源码和86生成物；
  index/unmerged为空，差异空白检查通过。未编译、测试、格式化、生成或GUI。
- 已保全删除前1040文件，264明确待重写手写Dart继续保持删除；Rust/测试/平台/资源未扩大删除。
  9个被新main修改的已删文件另存完整上游参考，供D3/U1/A/C移植新功能。快照和清单均在
  本次执行artifact，由派发给出实际读取路径，不将机器路径作为项目接口。
- 新main的统计pending仅抑制过早空态、不形成可见状态行；SSH/HTTP2 v9、目录nextCursor/
  实际游标关闭、动态lease和物理清理语义必须保留。远端目录不再从offset重新扫描。
- SDK lockfile保留原未提交overlay；App lockfile及Cargo文件保留新main。没有重新解析依赖。
- 已发布PR head暂仍c262，对应五job CI全部success，只覆盖文档提交；rebase成果尚未推送。

同步不是重写完成。现在按v5派发互斥模块：D0共享基础及根barrel、D1会话/草稿、D2配置/
模型/额度/模式、D3工作区/资源/更新、R必要Rust/Server接缝、A adapter/demo/fake、U0公共UI、
U1设置、U2会话、U3 app/workspace、C消费者。未确定架构由执行者报告root，只暂停受影响
部分；各任务不得用旧facade或兼容alias维持中间可编译状态。
