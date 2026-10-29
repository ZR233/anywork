//! Stable declarations for the opaque Thread tool implementations.
use crate::{session_note::SessionNoteToolKind, task_control::TaskControlKind};
use pl_protocol::ToolSpec;

/// Tool-owned schema and descriptions, without provider encoding or mutable task state.
#[derive(Debug, Clone, Copy)]
pub enum ThreadBuiltin {
    ViewImage,
    ShowImage,
    CreateDirectory,
    DeletePath,
    CopyPath,
    MovePath,
    ListTasks,
    Sleep,
    WriteFile,
    StatPath,
    Exec,
    WriteStdin,
    File(crate::workspace_file::WorkspaceFileToolKind),
    FinishTurn,
    AskUser,
    Todo,
    Discover,
    Task(TaskControlKind),
    Note(SessionNoteToolKind),
}

impl ThreadBuiltin {
    /// Returns the deterministic declaration for this implementation's actual input contract.
    pub fn declaration(self) -> ToolSpec {
        match self {
            Self::CreateDirectory => schema::<crate::file::PathInput>(
                "create_directory",
                "Create a directory inside the workspace.",
            ),
            Self::DeletePath => schema::<crate::file::DeletePathInput>(
                "delete_path",
                "Delete a file or directory using an explicit file, emptyDirectory, or recursiveDirectory mode.",
            ),
            Self::CopyPath => schema::<crate::file::CopyMoveInput>(
                "copy_path",
                "Copy a workspace file with explicit destination collision behavior.",
            ),
            Self::MovePath => schema::<crate::file::CopyMoveInput>(
                "move_path",
                "Move a workspace file or directory with explicit destination collision behavior.",
            ),
            Self::ListTasks => crate::task_control::ListTasksTool::declaration(),
            Self::Sleep => crate::session::SleepTool::declaration(),
            Self::ViewImage => schema::<crate::image::ViewImageInput>(
                crate::image::TOOL_VIEW_IMAGE,
                "Open a local or SSH workspace image so you can inspect screenshots and other image files. Pass its path in the current workspace; SSH paths must be workspace-relative POSIX paths. The image is retained for model context and history replay. Requires image input support from the current model.",
            ),
            Self::ShowImage => crate::image_card::ThreadShowImageTool::declaration(),
            Self::StatPath => schema::<crate::file::PathInput>(
                "stat_path",
                "Return metadata for a workspace path, or exists: false when the path is absent.",
            ),
            Self::WriteFile => schema::<crate::file::WriteFileInput>(
                "write_file",
                "Write exact UTF-8 text to a workspace file using create, overwrite, or append mode.",
            ),
            Self::File(kind) => kind.to_spec(),
            Self::WriteStdin => schema::<crate::exec::WriteStdinInput>(
                "write_stdin",
                "Write text to the original exec receipt taskId. closeStdin=true sends EOF after text; empty chars is valid only for EOF. A blocked write returns its own task receipt: cancel that input task to stop writing without stopping exec, then query its result. Accepted bytes and remote ACKs are distinct: never resend accepted input after cancellation. Wait for the input task before actions that require completed delivery.",
            ),
            Self::Exec => schema::<crate::exec::ExecInput>(
                "exec",
                "Execute one independent shell (cwd defaults to workspace root). timeoutSeconds is the total admission-to-exit budget and remains active after a task receipt. maxOutputChars caps combined stdout+stderr text at 65536 UTF-8 bytes; metadata, JSON escaping and protocol wrappers are additional. Results distinguish execution, capture and archive facts. stdoutFile/stderrFile are exact workspace-root-relative paths: read them with cwd omitted or set to '.', even when the original command used another cwd. Never reconstruct paths or repeat side effects to recover output; query the original receipt.",
            ),
            Self::FinishTurn => crate::finish_turn::declaration(),
            Self::AskUser => schema::<crate::ask_user::AskUserInput>(
                "request_user_input",
                "Ask structured questions and suspend until the user answers or cancels.",
            ),
            Self::Todo => schema::<crate::todo::TodoListInput>(
                crate::todo::TOOL_UPDATE_TODO_LIST,
                "Replace the current task checklist; maintain at most one in-progress item.",
            ),
            Self::Discover => schema::<crate::discovery::SearchInput>(
                "discover_tools",
                "Reveal up to 20 tool IDs matching query as one case-insensitive literal ID substring (surrounding whitespace is trimmed). Use an exact ID or a fragment such as 'delegation'; not a natural-language request, description search, or space-separated list. An empty query returns only the first 20 matches, not the full catalog. No match means this substring did not match the current Thread catalog, not that a capability is globally unavailable.",
            ),
            Self::Task(TaskControlKind::Wait) => schema::<crate::task_control::WaitTasksInput>(
                "wait",
                "Call wait ALONE in a model response. Observe exact receipt taskIds (including sleep timers): {\"taskIds\":[\"task:call-id\"]}. Any selected terminal task OR new Thread message returns first, not all tasks; already-ready events return immediately. Empty taskIds wait only for messages, including child reports: {\"taskIds\":[],\"timeoutMs\":300000}. Returns readiness without consuming results; full background results and child Turn reports arrive in your next model context. Match childId, turn and input identity before accepting child work. Never put agentId or bare callId in taskIds. Timeout or cancelling wait does not cancel the selected tasks.",
            ),
            Self::Task(TaskControlKind::Query) => schema::<crate::task_control::QueryTaskInput>(
                "get_tool_task",
                "Read this Thread receipt taskId without consuming events. resultCursor=0 starts UTF-8 byte pages of the immutable payload; follow nextCursor. This cursor does not page raw stdout/stderr files. Finished results remain queryable after resident eviction; never rerun commands to recover output.",
            ),
            Self::Task(TaskControlKind::Cancel) => schema::<crate::task_control::CancelTaskInput>(
                "cancel_tool_task",
                "Request cancellation of one task. The acknowledgement is not proof of process exit; use wait to observe its terminal result.",
            ),
            Self::Note(kind) => {
                ToolSpec::function(kind.name(), kind.description(), kind.input_schema())
            }
        }
    }
}

fn schema<T: schemars::JsonSchema>(name: &str, description: &str) -> ToolSpec {
    ToolSpec::function(name, description, schemars::schema_for!(T).to_value())
}
