# 参考依据与适用边界

以下是方法或工具机制的一手资料，按问题核对即可。技能中的双轨路由与取舍是工程约定，
不是这些作者共同规定的强制流程；不引入行业调查数字或其他项目的提速比例作为本项目结论。

| 来源 | 采用的要点与边界 |
| --- | --- |
| [Software Engineering at Google，第 12 章](https://abseil.io/resources/swe-book/html/ch12.html) | 按行为组织、减少无关实现耦合、保持可读；不要求每个函数一条测试，也不意味着契约变化后禁止维护测试。 |
| [第 13 章：Test Doubles](https://abseil.io/resources/swe-book/html/ch13.html) | 权衡真实对象、fake、stub 与交互验证；优先结果并不禁止缓存次数或协议顺序等交互契约。 |
| [matklad：How to Test](https://matklad.github.io/2021/05/31/how-to-test.html) | 数据驱动、check 帮助函数与无 I/O 核心适合稳定规则；作者说明自身主要来自编译器领域，不能推广成所有系统必须单二进制、无 mock 或使用快照。 |
| [Rust Book：Test Organization](https://doc.rust-lang.org/book/ch11-03-test-organization.html) | 模块内测试可访问私有内容，集成测试使用公开接口；两者按被保护的行为选择。 |
| [Cargo Targets](https://doc.rust-lang.org/cargo/reference/cargo-targets.html) | 顶层集成文件是不同目标，可考虑合并以降低开销；具体 feature、harness 与隔离需求仍须核对。 |
| [Rust Book：Controlling How Tests Are Run](https://doc.rust-lang.org/book/ch11-02-running-tests.html) | 原生过滤、并行与 `#[ignore]` / `--ignored`；零用例、被忽略与实际通过应区分。 |
| [Rust 2024：Rustdoc combined tests](https://doc.rust-lang.org/edition-guide/rust-2024/rustdoc-doctests.html) | rustdoc 尝试合并兼容示例；不能继续用每段文档必单独编译作为统一关停依据。 |
| [Cargo Timings](https://doc.rust-lang.org/cargo/reference/timings.html) | 构建计时是瓶颈线索；冷/热构建、测试运行与环境准备仍需分别观察。 |
| [cargo-nextest](https://nexte.st/) | 独立进程与调度可改善运行；当前 doctest 另跑，不保证任意项目都会提速。 |
| [Tokio `time::pause`](https://docs.rs/tokio/latest/tokio/time/fn.pause.html) | 虚拟时间的 feature、runtime 及覆盖范围；不替代真实外部时钟和进程行为。 |
| [Flutter 测试概览](https://docs.flutter.dev/testing/overview) | unit、widget 与 integration 的范围和成本不同，按所需真实性选择。 |
| [Flutter `pumpAndSettle`](https://api.flutter.dev/flutter/flutter_test/WidgetTester/pumpAndSettle.html) / [`runAsync`](https://api.flutter.dev/flutter/flutter_test/WidgetTester/runAsync.html) | 帧收敛与真实异步不是同一件事，按实际调度边界等待。 |

不由这些资料推出固定覆盖率、100 ms 慢测阈值、强制测试数量或“永远不用内部替身”等规则。
工具版本、平台和项目配置可能改变具体机制，实施时以当前官方契约及项目实际配置为准。
返回 [技能正文](../SKILL.md)。
