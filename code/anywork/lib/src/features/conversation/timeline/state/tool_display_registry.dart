import 'tool_display.dart';
import 'tool_displays/apply_patch.dart';
import 'tool_displays/apply_session_note_patch.dart';
import 'tool_displays/copy_path.dart';
import 'tool_displays/create_directory.dart';
import 'tool_displays/deepseek_web_fetch.dart';
import 'tool_displays/deepseek_web_search.dart';
import 'tool_displays/delete_path.dart';
import 'tool_displays/exec.dart';
import 'tool_displays/generic.dart';
import 'tool_displays/lsp_capabilities.dart';
import 'tool_displays/lsp_query.dart';
import 'tool_displays/lsp_status.dart';
import 'tool_displays/move_path.dart';
import 'tool_displays/plan_current.dart';
import 'tool_displays/plan_history.dart';
import 'tool_displays/plan_next.dart';
import 'tool_displays/plan_restart.dart';
import 'tool_displays/plan_submit.dart';
import 'tool_displays/read_session_note.dart';
import 'tool_displays/search_session_note.dart';
import 'tool_displays/send_message.dart';
import 'tool_displays/show_files.dart';
import 'tool_displays/sleep.dart';
import 'tool_displays/spawn_agent.dart';
import 'tool_displays/stat_path.dart';
import 'tool_displays/view_image.dart';
import 'tool_displays/wait.dart';
import 'tool_displays/web_search.dart';
import 'tool_displays/workflow_current.dart';
import 'tool_displays/workflow_graph.dart';
import 'tool_displays/workflow_history.dart';
import 'tool_displays/workflow_next.dart';
import 'tool_displays/workflow_restart.dart';
import 'tool_displays/workflow_transition.dart';
import 'tool_displays/write_file.dart';
import 'tool_displays/write_session_note.dart';
import 'tool_displays/write_stdin.dart';

final toolDisplayRegistry = buildToolDisplayRegistry(const [
  GenericToolDisplay(),
  ExecToolDisplay(),
  WriteStdinToolDisplay(),
  ReadSessionNoteToolDisplay(),
  SearchSessionNoteToolDisplay(),
  WriteSessionNoteToolDisplay(),
  ApplySessionNotePatchToolDisplay(),
  StatPathToolDisplay(),
  WriteFileToolDisplay(),
  ApplyPatchToolDisplay(),
  CreateDirectoryToolDisplay(),
  DeletePathToolDisplay(),
  CopyPathToolDisplay(),
  MovePathToolDisplay(),
  SpawnAgentToolDisplay(),
  SendMessageToolDisplay(),
  WaitToolDisplay(),
  SleepToolDisplay(),
  ViewImageToolDisplay(),
  ShowFilesToolDisplay(),
  LspQueryToolDisplay(),
  LspCapabilitiesToolDisplay(),
  LspStatusToolDisplay(),
  PlanCurrentToolDisplay(),
  PlanNextToolDisplay(),
  PlanHistoryToolDisplay(),
  PlanSubmitToolDisplay(),
  PlanRestartToolDisplay(),
  WorkflowCurrentToolDisplay(),
  WorkflowNextToolDisplay(),
  WorkflowGraphToolDisplay(),
  WorkflowHistoryToolDisplay(),
  WorkflowTransitionToolDisplay(),
  WorkflowRestartToolDisplay(),
  WebSearchToolDisplay(),
  DeepseekWebSearchToolDisplay(),
  DeepseekWebFetchToolDisplay(),
]);
