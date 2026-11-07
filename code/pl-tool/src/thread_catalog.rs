//! Stable declarations for the opaque Thread tool implementations.
use crate::{session_note::SessionNoteToolKind, task_control::TaskControlKind};
use pl_agent_tool::ToolDefinition;

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
    pub fn declaration(self) -> ToolDefinition {
        match self {
            Self::CreateDirectory => crate::file::create_directory_tool_definition(),
            Self::DeletePath => crate::file::delete_path_tool_definition(),
            Self::CopyPath => crate::file::copy_path_tool_definition(),
            Self::MovePath => crate::file::move_path_tool_definition(),
            Self::ListTasks => crate::task_control::ListTasksTool::declaration(),
            Self::Sleep => crate::session::SleepTool::declaration(),
            Self::ViewImage => crate::image::thread_view_image_tool_definition(),
            Self::ShowImage => crate::image_card::ThreadShowImageTool::declaration(),
            Self::StatPath => crate::workspace_file::thread_stat_path_tool_definition(),
            Self::WriteFile => crate::workspace_file::thread_write_file_tool_definition(),
            Self::File(kind) => kind.definition(),
            Self::WriteStdin => crate::exec::write_stdin_definition(),
            Self::Exec => crate::exec::exec_definition(),
            Self::FinishTurn => crate::finish_turn::declaration(),
            Self::AskUser => crate::ask_user::ask_user_tool_definition(),
            Self::Todo => crate::todo::todo_update_tool_definition(),
            Self::Discover => crate::discovery::discover_tools_definition(),
            Self::Task(TaskControlKind::Wait) => crate::task_control::wait_definition(),
            Self::Task(TaskControlKind::Query) => crate::task_control::query_definition(),
            Self::Task(TaskControlKind::Cancel) => crate::task_control::cancel_definition(),
            Self::Note(kind) => {
                ToolDefinition::json(kind.name(), kind.description(), kind.input_schema())
                    .expect("valid tool definition")
            }
        }
    }
}
