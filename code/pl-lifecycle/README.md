# 资源生命周期作用域

`ScopeOwner` 持有作用域，通过构造函数把弱 `ScopeHandle` 注入使用方。使用方可以登记
同步解绑回调、打开异步资源和创建子作用域，但不能通过弱句柄关闭祖先。资源构造、
关闭、超时和重试的公开示例见 crate 文档。

`on_close` 只适用于快速、非阻塞的同步解绑。回调由释放作用域或 `Registration` 的
线程直接执行，不为每个监听器创建工作任务；回调开始后不能由截止时刻中断。可能耗时
或阻塞的清理应建模为 `ManagedResource::close`，由受监督工作保留原资源及完成回执。
异步实现不能直接阻塞运行时线程；确有有界阻塞工作时，可使用 Tokio 的阻塞任务池，
但已开始的阻塞任务不能强制取消。

`request_close` 只封门并请求取消；需要确认真实清理结果时，须在运行时关闭前调用
`close(deadline)` 或 `wait_closed()` 并检查报告。等待超时或取消不会取消已经启动的
异步清理。失败成员保留原实例，只有显式 `retry_close` / `retry_cleanup` 才开始下一次
尝试。领域写入器、进程和数据库的关闭顺序由领域所有者决定。

这一边界参考了 [VS Code 同步资源释放](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/lifecycle.ts)、
[Go 异步取消回调](https://pkg.go.dev/context#AfterFunc)、[.NET 异步取消](https://learn.microsoft.com/en-us/dotnet/api/system.threading.cancellationtokensource.cancelasync?view=net-10.0)
以及 [Tokio 阻塞任务的取消与关闭约束](https://docs.rs/tokio/1.54.1/tokio/task/fn.spawn_blocking.html)。
