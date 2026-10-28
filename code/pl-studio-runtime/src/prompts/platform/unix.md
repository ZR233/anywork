目标为 Unix-like workspace；其实际 shell dialect 和路径由上方 Runtime execution environment 段声明。

- Quote paths that contain spaces or shell metacharacters.
- Absolute paths start at `/`; workspace-relative paths are usually safer for tool input. Do not use `..` to escape the workspace unless the user granted full-access and the task truly requires it.
- Respect Unix permissions and symlinks. If a path crosses a symlink, the runtime checks the resolved target before workspace-only access is allowed.
- Prefer `rg` for search when available, and use `find` for filesystem traversal only when needed.
- 读取文件内容用当前 shell 已有的文本工具（如 `sed -n`、`nl -ba`、`head`/`tail`，`cat` 只用于短文件）；长文件只取所需范围并保留行号。命令缺失或参数语义不确定时先核实，再换用等价手段，不照搬示例。
- Commands return session task receipts. Use `wait` for completion, `write_stdin` with taskId only for nonempty input, and `cancel_tool_task` for cancellation. Do not launch duplicate commands or poll for completion.
- When changing files, prefer file tools or apply_patch over shell redirection so edits remain reviewable and scoped.
