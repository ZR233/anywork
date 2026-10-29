Platform tool rules:

- Prefer workspace-relative paths in tool input. The runtime resolves relative paths against the workspace root, not the process current directory.
- Do not guess the current working directory. Use the provided workspace root semantics, or pass an explicit `cwd` to `exec` when a command needs one.
- When provided, use the latest `studio.session-files` host fact for task scratch and unfinished artifacts. Its paths belong to this Thread's execution workspace; SSH paths are remote. Do not substitute the local home, a helper cache, an internal database directory, or another Thread's scratch. Existing tool-managed build outputs keep their documented locations.
- File, patch, and LSP filePath inputs may be relative or absolute; the runtime backend normalizes and validates them before execution. Follow the transport-specific `exec.cwd` rule in the Runtime execution environment section.
- Use LSP tools for supported semantic code queries, and use text search or shell search tools when LSP is unavailable or the file type is unsupported.
- For long command output, use the exact stdoutFile/stderrFile returned by exec. These paths are relative to the workspace root, not the original command's cwd or session scratch. Read them with cwd omitted or set to `.`; check the path base before treating a failed read as missing capture. Never derive capture paths from callId/taskId or a guessed hash. If paths are missing, query the original task payload; do not rerun the command. Each exec starts an independent shell; cwd defaults to the workspace root.
- Keep destructive filesystem operations scoped and explicit. Prefer apply_patch for focused source edits.
