# Rust 测试

本文补充 [技能正文](../SKILL.md) 的 Rust 做法。先读当前 workspace、crate、toolchain、feature
和项目命令约定；下面是通用示例，不是所有仓库必须执行的流程。

## 从稳定行为入口测试

模块内 `#[cfg(test)]` 测试适合独立规则、不变量及必要的私有纯逻辑。
`tests/` 集成测试把 crate 当作正常依赖，适合公共能力、真实文件/数据库、CLI 与多组件连接。
不为测试把函数改为 `pub`，不通过 `#[path]` / `include!` 重新编译生产实现来绕开真正入口。
选择模块测试不等于逐个测试私有函数，选择集成测试也不等于必须拉起完整应用。

短测试可内联；较大模块用 `#[cfg(test)] mod tests;` 分离，按可读性和现有布局选择。
外置测试文件可以减少仅编辑测试时对非测试源码输入的影响，但不保证减少所有重编译，
更不会消除同一库的普通构建与 test harness 构建，需用实际目标和计时确认。

## 数据表与故障诊断

例如契约已经明确：“截止时刻到达即过期”。用阈值附近的数据验证该规则，
不要从当前条件表达式反推期望。以下是适配示例，`is_expired` 代表项目真实入口：

```rust
#[test]
fn deadline_is_expired_at_or_after_the_boundary() {
    for (case, now, deadline, expected) in [
        ("before", 9, 10, false),
        ("at", 10, 10, true),
        ("after", 11, 10, true),
    ] {
        assert_eq!(is_expired(now, deadline), expected, "case={case}");
    }
}
```

这里把 `>=` 改成 `>` 会使 `at` 失败。若同一种调用/解析过程在多个用例中重复，
再抽取一个 `check(input, expected)`；帮助函数负责调用和诊断，不负责计算期望。
不同失败需要不同准备或定位时可保留独立用例，不为减少函数数量牺牲诊断。

复杂返回值使用项目已有断言工具比较契约字段；不要为了统一风格添加新依赖。
状态机同时核对有效转移与被拒绝操作后的状态；错误测试核对类型及副作用，不能只匹配任意 `Err`。
对属性测试、快照与变异测试，先确认有明确收益且项目已有工具可复用。

## 可控环境与异步

- 使用每用例独立的临时目录和真实轻量数据库。事务、迁移、约束、锁与崩溃恢复必须在相应真实边界验证，
  内存 fake 不能证明磁盘耐久性；同样不能把内存 SQLite 的通过当作文件锁行为的证明。
- 用端口 `0` 让系统分配可用端口，并持有服务/监听资源到用例结束；不要先找空端口再释放后重新绑定。
- 通过子进程配置环境变量和 cwd；避免并行测试修改进程级全局环境。确需共享资源时局部隔离，
  不默认把整个套件设为单线程。
- 用 channel、barrier、明确完成信号和 join 验证生命周期；超时后报告首个未完成阶段并收束所属资源。
- 使用 Tokio 虚拟时间时核对项目版本与 feature。`pause` 需要 `current_thread` runtime，
  只影响 Tokio 时间，不推进 `std::time`、真实网络或外部进程；不要为真实边界伪造时间通过。
- 重试测试注入可控失败序列，核对最终结果、实际副作用及预算，不靠重复执行期待偶现竞争。

## 测试目标与链接成本

Cargo 会把 `tests/` 下的顶层 Rust 文件作为独立集成目标。大量同依赖的小目标若造成重复链接，
可在**同一 crate、相容 feature 与隔离需求**下合并入口，例如：

```text
tests/
  integration/
    main.rs
    parsing.rs
    persistence.rs
    support/
      mod.rs
```

在 `main.rs` 中声明这些测试模块。共享辅助模块放到入口子目录或 `tests/support/mod.rs`，
不要误放成顶层 `tests/common.rs` 形成空测试目标。核对已有显式 `[[test]]`、`autotests`、
`required-features`、harness、可执行文件环境和工作目录；移动后确认发现集合与失败传播不变。

合并可能扩大单个目标的依赖、feature 和重编译范围。不要强制全 workspace 一个测试 crate，
不要无依据设置 `[lib] test = false`，也不要为少一次链接破坏平台或进程隔离。

## 显式慢测与工具选择

以项目 runner 的显式标签/分组优先；原生 Rust 可用带原因的 `#[ignore = "需要专用环境，见项目运行说明"]`。
忽略测试仍会编译，报告中会显示 ignored。被显式执行时，缺少所需资源须给出明确错误，不能提前返回成功。
平台/feature 的真实编译条件仍使用相应 `cfg` 并安排对应环境验证，不以“慢”作为条件编译理由。

从 crate 根或项目规定入口运行，替换下列占位名称，只选相关目标：

```sh
cargo test --locked -p <crate> --lib <filter>
cargo test --locked -p <crate> --test <target> <filter>
cargo test --locked -p <crate> --test <target> -- --ignored
```

核对输出确有目标用例；`<filter>` 未匹配时零测试退出成功不形成验证。
项目已经使用 nextest 时遵循既有配置；尚未使用时先测量再决定，不把引入它当作测试质量改造的必要步骤。
它的调度优化不自动消除编译/链接成本；当前不执行 doctest，有价值的文档示例另用 `cargo test --doc` 验证。

保留有契约价值的 doctest。Rust 2024 会尝试合并兼容的文档测试，不要依据旧的“每段必单独编译”
假设统一关闭。只在确认无独立证明且有实测成本后调整；`compile_fail` 等特殊用法需单独核对。
测量与来源见 [审计与成本](audit-and-cost.md)、[参考依据](sources.md)。
