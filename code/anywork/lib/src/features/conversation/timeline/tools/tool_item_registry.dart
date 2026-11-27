import 'dart:collection';

import '../state/chat_item_presentation.dart';
import '../state/tool_presentation.dart';
import 'items/acp/acp_tool_item.dart';
import 'items/collaboration/close_agent_tool_item.dart';
import 'items/collaboration/evaluate_agent_tool_item.dart';
import 'items/collaboration/interrupt_agent_tool_item.dart';
import 'items/collaboration/list_agents_tool_item.dart';
import 'items/collaboration/read_agent_session_tool_item.dart';
import 'items/collaboration/send_message_tool_item.dart';
import 'items/collaboration/spawn_agent_tool_item.dart';
import 'items/collaboration/wait_agent_tool_item.dart';
import 'items/command/exec_tool_item.dart';
import 'items/command/write_stdin_tool_item.dart';
import 'items/filesystem/apply_patch_tool_item.dart';
import 'items/filesystem/copy_path_tool_item.dart';
import 'items/filesystem/create_directory_tool_item.dart';
import 'items/filesystem/delete_path_tool_item.dart';
import 'items/filesystem/move_path_tool_item.dart';
import 'items/filesystem/stat_path_tool_item.dart';
import 'items/filesystem/write_file_tool_item.dart';
import 'items/generic/generic_tool_item.dart';
import 'items/lsp/lsp_capabilities_tool_item.dart';
import 'items/lsp/lsp_query_tool_item.dart';
import 'items/lsp/lsp_status_tool_item.dart';
import 'items/media/show_files_tool_item.dart';
import 'items/media/view_image_tool_item.dart';
import 'items/plan/plan_current_tool_item.dart';
import 'items/plan/plan_history_tool_item.dart';
import 'items/plan/plan_next_tool_item.dart';
import 'items/plan/plan_restart_tool_item.dart';
import 'items/plan/plan_submit_tool_item.dart';
import 'items/plan/plan_transition_tool_item.dart';
import 'items/session_note/apply_session_note_patch_tool_item.dart';
import 'items/session_note/read_session_note_tool_item.dart';
import 'items/session_note/search_session_note_tool_item.dart';
import 'items/session_note/write_session_note_tool_item.dart';
import 'items/wait/sleep_tool_item.dart';
import 'items/wait/wait_tool_item.dart';
import 'items/web/deepseek_web_fetch_tool_item.dart';
import 'items/web/deepseek_web_search_tool_item.dart';
import 'items/web/web_search_tool_item.dart';
import 'items/workflow/workflow_current_tool_item.dart';
import 'items/workflow/workflow_graph_tool_item.dart';
import 'items/workflow/workflow_history_tool_item.dart';
import 'items/workflow/workflow_next_tool_item.dart';
import 'items/workflow/workflow_restart_tool_item.dart';
import 'items/workflow/workflow_transition_tool_item.dart';
import 'tool_item_adapter.dart';

/// Central plugin registry resolving [TimelineToolItemAdapter] instances by
/// declarative [TimelineToolMatcher] rules.
///
/// Adding a new tool requires only:
/// 1. Creating one standalone adapter file under `timeline/tools/items/...`.
/// 2. Adding an instance to [timelineToolItemRegistry] below.
class TimelineToolItemRegistry {
  TimelineToolItemRegistry({
    required List<TimelineToolItemAdapter> adapters,
    this.fallback = const GenericToolItem(),
  }) : adapters = UnmodifiableListView([...adapters, fallback]),
       _orderedAdapters = UnmodifiableListView(adapters) {
    final contractIndex = <String, TimelineToolItemAdapter>{};
    void registerContracts(TimelineToolItemAdapter adapter) {
      for (final contract in adapter.matcher.exactContracts) {
        if (contractIndex.containsKey(contract)) {
          throw ArgumentError(
            'Duplicate exact presentationContract "$contract" between '
            '${contractIndex[contract]!.runtimeType} and ${adapter.runtimeType}.',
          );
        }
        contractIndex[contract] = adapter;
      }
    }

    for (final adapter in adapters) {
      registerContracts(adapter);
    }
    registerContracts(fallback);
    _byExactContract = UnmodifiableMapView(contractIndex);
  }

  /// All registered tool adapters including [fallback].
  final List<TimelineToolItemAdapter> adapters;

  /// Registered specialized adapters evaluated before [fallback].
  final List<TimelineToolItemAdapter> _orderedAdapters;

  /// Fallback adapter when no registered matcher claims an item.
  final TimelineToolItemAdapter fallback;

  late final Map<String, TimelineToolItemAdapter> _byExactContract;

  /// Unmodifiable map of exact contract IDs to registered adapters.
  Map<String, TimelineToolItemAdapter> get exactContractIndex =>
      _byExactContract;

  /// All exact contract IDs registered across all adapters (including `generic@1`).
  Set<String> get exactContracts => _byExactContract.keys.toSet();

  /// Direct lookup for exact contract IDs, returning `null` if unknown.
  TimelineToolItemAdapter? lookupExact(String? contract) =>
      contract == null ? null : _byExactContract[contract];

  /// Resolves the matching adapter for [context], falling back to [fallback].
  TimelineToolItemAdapter resolve(TimelineToolMatchContext context) {
    final exact = lookupExact(context.presentationContract);
    if (exact != null && exact.matcher.matches(context)) {
      return exact;
    }
    for (final adapter in _orderedAdapters) {
      if (adapter.matcher.matches(context)) {
        return adapter;
      }
    }
    return fallback;
  }

  TimelineToolItemAdapter resolveForPresentation(
    TimelineToolPresentation item,
  ) => resolve(TimelineToolMatchContext.fromPresentation(item));

  TimelineToolItemAdapter resolveForChatItem(ChatItemPresentation item) =>
      resolve(TimelineToolMatchContext.fromChatItem(item));
}

/// Default application registry of all 42 built-in tools, ACP peer tools,
/// plus `generic@1`.
final TimelineToolItemRegistry timelineToolItemRegistry =
    TimelineToolItemRegistry(
      adapters: const [
        // Command execution
        ExecToolItem(),
        WriteStdinToolItem(),

        // Filesystem
        WriteFileToolItem(),
        ApplyPatchToolItem(),
        StatPathToolItem(),
        CreateDirectoryToolItem(),
        DeletePathToolItem(),
        CopyPathToolItem(),
        MovePathToolItem(),

        // Session note
        ReadSessionNoteToolItem(),
        SearchSessionNoteToolItem(),
        WriteSessionNoteToolItem(),
        ApplySessionNotePatchToolItem(),

        // Media
        ViewImageToolItem(),
        ShowFilesToolItem(),

        // LSP
        LspQueryToolItem(),
        LspCapabilitiesToolItem(),
        LspStatusToolItem(),

        // Collaboration & subagents
        SpawnAgentToolItem(),
        SendMessageToolItem(),
        ReadAgentSessionToolItem(),
        EvaluateAgentToolItem(),
        ListAgentsToolItem(),
        InterruptAgentToolItem(),
        CloseAgentToolItem(),
        WaitAgentToolItem(),

        // Wait & timers
        WaitToolItem(),
        SleepToolItem(),

        // Plan
        PlanCurrentToolItem(),
        PlanNextToolItem(),
        PlanHistoryToolItem(),
        PlanTransitionToolItem(),
        PlanSubmitToolItem(),
        PlanRestartToolItem(),

        // Workflow
        WorkflowCurrentToolItem(),
        WorkflowNextToolItem(),
        WorkflowGraphToolItem(),
        WorkflowHistoryToolItem(),
        WorkflowTransitionToolItem(),
        WorkflowRestartToolItem(),

        // Web
        WebSearchToolItem(),
        DeepseekWebSearchToolItem(),
        DeepseekWebFetchToolItem(),

        // ACP protocol peer tools
        AcpToolItem(),
      ],
    );
