# 原生崩溃取证边界

只在真实信号、退出或资源行为需要原生证据时使用本指南。仍由 xtask 构建并启动应用；
不要以直接运行 native binary、修改 SDK、放宽退出断言或更换故障输入代替取证。

## 先保留事实

- 固定实际源码树、相关文件与模块摘要。CI 可能运行 PR 合并提交；本地 HEAD 相同不代表
  合并树、未提交差异、构建特性或环境相同。阶段诊断是时间边界，不是故障函数或崩溃时刻。
- 区分 wrapper、launcher 与 native root 的 PID、startTicks、退出码、signal、取消和后代回收。
  重开成功不能抵消旧进程崩溃；初始化应答、退出请求应答也不能代替 wait 终态。
- 精简或脱敏日志可能过滤原生 stderr。仅在本次工具明确创建的输出目录内定位原始日志，
  必要时在临时环境清理前只读持有文件描述符并留存增量；Linux 文件取消链接后仍可从原
  描述符排空。不得扫描用户 home、全局临时目录或把精简日志冒称原始输出。

## Linux 调试器与信号

先核实调试器、`ptrace_scope`、core limit 和 core 收集方式。没有保留的 core 文件时，
OS wait status 的 “core dumped” 不是可交付转储；不要为取证修改全局 sysctl 或提权。

`ptrace_scope=1` 默认允许祖先调试自己的后代。可让 GDB 的 Python 子进程入口启动原
xtask 命令，使目标 native PID 是 GDB 的后代，保持原启动及进程 owner；先用自己创建的
短命子进程验证 attach/detach 与清理。不能据此假定其他平台、权限模式或进程也允许附加。
GDB 的 Python 不得覆盖其 `SIGCHLD`、`SIGINT` 处理；线程使用也应遵守官方 API 契约。

附加前核实本次 native PID/startTicks 与祖先链。保存故障线程及所有线程回溯、寄存器、
模块映射和匹配的模块摘要。优先文本证据，不默认采集可能含凭据、模型内容且体积巨大的 core。

调试器捕获的首次 `SIGSEGV` 可能被运行时处理。记录停止后，应按原信号策略传回程序，
再由真实 wait/launcher 报告判断是否 fatal；不要吞信号或把它转换为预期退出码。
附加与采栈暂停会改变调度，本轮耗时不能外推为正常退出期限的性能证据。

## 跨动态库与补验

- 栈同时出现不同动态库的展开函数时，先核实实际调用和重定位提供者。普通 `dlsym` 的查询
  结果不一定等于对象实际绑定；必要时用平台 loader 的原始绑定诊断交叉核对。
- 若需控制探针，使用同一小型、已定义的 C ABI，在独立短子进程中逐一改变库加载条件，
  保留超时、真实 signal 和 wait 结果。不得跨 FFI 返回 Rust 内部对象或故意制造未定义行为。
- `RTLD_DEEPBIND` 等加载策略通过控制探针，不等于已证明真实 bridge 的所有依赖、回调和
  资源生命周期安全。不要把试验选项直接沉淀为生产 shim、SDK 补丁或全局环境设置。
- 诊断动作自身失败与原业务失败分别裁定。修复应保留原错误分类、关联与保存事实和原退出
  判据；不能把删除错误、变成 Clean 或自动重试当作修复。产品关闭约束见 `design/18-studio-state.md`。
- 只重验失败及实际受影响路径。完成或失败后，汇合观察器、调试器与正式任务，核对所有
  明确所属进程；没有权限或没有原始栈时保留具体缺口，不猜测根因。

官方参考：[Linux Yama](https://docs.kernel.org/admin-guide/LSM/Yama.html)、
[GDB Python 基础契约](https://sourceware.org/gdb/current/onlinedocs/gdb.html/Basic-Python.html)。
