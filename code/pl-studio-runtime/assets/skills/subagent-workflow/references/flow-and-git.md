# 工作流与 Git 研究依据

仅在解释协作方法的取舍时阅读。以下基于公开章节、作者摘录和官方研究，不表示全文研究或对本产品的性能证明；执行方法以技能正文为准，不在这里复制检查清单。

## 信息密度与协调成本

Anthropic 的 [Effective context engineering for AI agents](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents)（2025-09-29）主张最小充分的高信号上下文，避免脆弱的细节脚本和过于空泛的指令两个极端。这里采用按职责分层、按需加载方法和证据索引；不能为了字数更少而删除权限、终态或依赖信息。

## 流动效率而非忙碌率

Nicole Forsgren、Jez Humble、Gene Kim 的《Accelerate》（2018），[作者公开摘录](https://nicolefv.com/s/accelerate-book-excerpt.pdf)第 2 章，讨论交付前置时间、小批量与反馈，并同时关注交付稳定性。DORA 的[小批量](https://dora.dev/capabilities/working-in-small-batches/)和[在制品限制](https://dora.dev/capabilities/wip-limits/)进一步解释减少排队与交接的实践。

这里据此考虑在途任务数量、关键依赖和就绪成果，不把代理数或工具次数当效率目标。小批量也有启动与交接成本，不意味着每个文件都要派一个代理；集中验证可减少重复构建，但不应无理由拖延独立成果的反馈。组织研究不是模型行为实验，不能据此承诺固定提速比例。

## 分支与集成责任

Scott Chacon、Ben Straub 的《Pro Git》第二版，[第 3.4 节](https://git-scm.com/book/en/v2/Git-Branching-Branching-Workflows)说明主题分支如何隔离相关工作，[第 5.1 节](https://git-scm.com/book/en/v2/Distributed-Git-Distributed-Workflows)说明不同协作和集成方式。

这里借鉴清晰的版本与责任边界，不将某一种人类团队分支模式照搬成代理固定流程。共享目录与独立工作树的实际差别必须保留；分支短期化不授权删除未交付提交、强推或提前清理返工现场。

## 测试价值与证据复用

《Software Engineering at Google》[第 12 章](https://abseil.io/resources/swe-book/html/ch12.html)强调测试行为和公共接口，避免把测试绑定到实现组织。这里用于区分有独特失败信号的证明与重复检查，不据此删除所有错误路径或把两个样例当成全面覆盖。

观察效率时同时记录实际结果、耗时与返修等事实，并标明模型、环境、人工等待和覆盖限制。单次运行更快或提示字符更少都不是因果证明；必要的安全与交付检查不能用速度指标替代。
