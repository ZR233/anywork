# v4 设计进度checkpoint

## 第二次文档进度保存

用户再次要求推送当前进度并持续完成。此次沿用已批准v4，不提交未完成的生产实现：

- 推送前本地、远端任务分支与PR head均为
  `9e00fb0ee2ab4b9ddbe3e379d545e1679d4393c6`；本次为其后续普通快进文档提交，不再重写历史。
- 新增产品完整字段册、产品读取port/Repository state、receipt来源观察、HTTP运输和Workspace
  合同；同步共享/Thread/产品合同与设计18/25。读取目标保留原owner/incarnation，Profiles与
  Thread Mode采用实际提交来源水位，目录search明确依赖Project来源。
- [9e00对应CI](https://github.com/ZR233/anywork/actions/runs/39731824372)已完成，五个job
  全部success。该结果仅覆盖9e00已提交tree，不证明后续合同或工作区生产overlay。
- 当前仍在完整接口冻结：目录窗口扩展、完整Turn历史、附件/创建进度、Updates操作owner、
  剩余领域动作、所有VM/props、新文件/导出与最终验收矩阵尚未全部闭合。不将局部合同
  定稿或文档CI成功当作全量实现准入与验收。
- 源码输入身份仍为78a加已保全overlay，贡献基线仍为b3。提交前重新核对1043路径身份、
  文档链接/空白与精确暂存范围；不执行编译、测试、格式化、生成或GUI。

以下保留第一次文档checkpoint的授权、范围与证据，不把历史推送前身份当作当前head。

## 推送授权与范围

用户追加要求“推送远端当前进度，并继续，直到计划完整完成”。本checkpoint保存当前设计、
工程合同、源码输入所有权和已有静态证据，不是实现交付；v4的业务目标、安全不变量和
全手写完成后才统一生成/测试的节奏不变，不重新请求同一实施授权。

本次提交仅包含`design/18-studio-state.md`、`design/25-frontend-state.md`、
`design/26-timeline-content.md`以及`reports/frontend-refactor`的Markdown/JSON文档。
既有生产/测试/CI/生成输入与源码计数Python脚本留在工作区，不混入文档提交，最终随完整
实现与适用门禁交付。旧overlay、stash、隔离同步worktree和用户数据继续保全。

## 身份与进度

- 冻结main：`b3f22b8f651816851852582a10a970fe25af3ae6`。
- 重放后的源码输入HEAD：`78a2762495772d7fe416faaf5f14876cf46597c4`。
- 本次核对的推送前远端任务分支/PR head：`b98432fa809446d57be87a8b96379455ec8a4828`。
- 任务分支：`pure-session-thread-65e3ee582f0d4-82`；不推main、不合并PR、不发布。
- [Draft PR #120](https://github.com/ZR233/anywork/pull/120)继续表示未完成重构。
- 批准计划v4 SHA-256：`f8b26bdc7c55994ad3beb154fbcdffe57a81509f2ec2b5c515d3c9f1259727c8`。

由于已授权的主线rebase改变历史，任务分支推送使用上述实核旧head的精确force-with-lease；
若远端已被其他写入推进则停止并核对，绝不无条件force覆盖。最终commit/远端ref/PR身份
以实际Git与GitHub回执记录，不在提交前伪填本提交hash或宣称推送已经成功。

本阶段已明确五域typed Thread feed、关闭恢复能力、产品metadata/正文版本分离、配置与
模型真正拆域、typed错误/dispatch结果、冻结草稿、真实输入身份durable和显式启动退出。
完整产品字段册、部分领域动作/按需读取、全部VM精确state/props、公共新文件和HTTP/SSE/
OpenAPI迁移仍在定稿；这些缺口未关闭前不释放全量新编码。

## 验证边界

最近一次静态审计核对1043源码输入hash不变、115相对文件链接目标存在（未检查anchors）、
合同尾空白/索引/冲突与git diff --check通过。该证据绑定推送前合同版本，新增本文件和
README修改在提交前另做文档静态核对。未运行本次实现的编译、测试、生成或GUI。

PR原有五项成功CI仅覆盖旧b984文档head，不能证明本次合同或工作区生产overlay；本checkpoint
触发的CI同样只覆盖已提交文档tree，不代表全量重构验收。最终实现完成后仍必须取得对应
真实提交的全门禁、原生旅程、可复算对比与CI终态。
