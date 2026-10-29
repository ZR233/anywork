import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

import 'conversation_live_status_models.dart';
import 'conversation_live_tool_specs.dart';

/// 将 `ConversationActivityView` 转换为 `ConversationLiveStatusMessage` 序列并同步到
/// [ConversationLiveStatusController]。
final class ConversationLiveStatusAdapter {
  const ConversationLiveStatusAdapter._();

  /// 将后端投影的 [ConversationActivityView] 同步喂入 [controller]。
  static void syncFromView(
    ConversationLiveStatusController controller,
    ConversationActivityView? view,
  ) {
    if (view == null) {
      controller.ingest(
        const ConversationLivePhaseMessage(phase: ConversationLivePhase.idle),
      );
      return;
    }
    final messages = messagesFromView(
      view,
      existingCallIds: {for (final slot in controller.activeTools) slot.callId},
    );
    controller.ingestAll(messages);
  }

  /// 将 [ConversationActivityView] 转化为纯 Dart [ConversationLiveStatusMessage] 列表。
  static List<ConversationLiveStatusMessage> messagesFromView(
    ConversationActivityView view, {
    Set<String> existingCallIds = const <String>{},
  }) {
    final messages = <ConversationLiveStatusMessage>[];
    final phase = _mapPhase(view.kind);
    final extraDetails = _extractNonToolAndNonStreamDetails(view, phase);

    messages.add(
      ConversationLivePhaseMessage(
        identity: view.identity,
        phase: phase,
        turnId: view.turnId,
        summary: view.summary,
        errorMessage: view.errorMessage,
        storage: view.storage,
        wait: view.wait,
        details: extraDetails,
        detailsLoading: view.detailsLoading,
        detailsError: view.detailsError,
        expandableOverride: view.expandable,
        backgroundToolCount: view.backgroundToolCount,
      ),
    );

    if (view.thinkingSummary != null &&
        view.thinkingSummary!.trim().isNotEmpty) {
      messages.add(
        ConversationLiveThinkingSummaryMessage(
          summaryMarkdown: view.thinkingSummary!.trim(),
          elapsedSeconds: view.thinkingSeconds,
          turnId: view.turnId,
        ),
      );
    }

    if (view.reasoningText != null && view.reasoningText!.trim().isNotEmpty) {
      messages.add(
        ConversationLiveThinkingStreamMessage.replace(view.reasoningText!),
      );
    } else if (phase == ConversationLivePhase.thinking &&
        view.summary != null &&
        view.summary!.trim().isNotEmpty &&
        (view.thinkingSummary == null ||
            view.thinkingSummary!.trim().isEmpty)) {
      messages.add(
        ConversationLiveThinkingStreamMessage.replace(view.summary!),
      );
    }

    if (phase == ConversationLivePhase.responding) {
      final response =
          (view.responseText != null && view.responseText!.trim().isNotEmpty)
          ? view.responseText!
          : (view.summary ?? '');
      messages.add(ConversationLiveResponseStreamMessage.replace(response));
    }

    final detailByCallId = <String, ThreadActivityToolDetail>{
      for (final tool in view.toolDetails) tool.callId: tool,
    };
    final activeCallIds = <String>{
      for (final entry in view.activeTools) entry.callId,
    };

    for (final oldCallId in existingCallIds) {
      if (!activeCallIds.contains(oldCallId)) {
        messages.add(ConversationLiveToolFinishedMessage(callId: oldCallId));
      }
    }

    for (final entry in view.activeTools) {
      final detail = detailByCallId[entry.callId];
      messages.add(createToolStartedMessage(entry, detail: detail));
    }

    return messages;
  }

  static ConversationLivePhase _mapPhase(ConversationActivityKind kind) =>
      switch (kind) {
        ConversationActivityKind.preparing => ConversationLivePhase.preparing,
        ConversationActivityKind.compacting => ConversationLivePhase.compacting,
        ConversationActivityKind.thinking => ConversationLivePhase.thinking,
        ConversationActivityKind.responding => ConversationLivePhase.responding,
        ConversationActivityKind.planning => ConversationLivePhase.planning,
        ConversationActivityKind.runningTool =>
          ConversationLivePhase.runningTool,
        ConversationActivityKind.awaitingApproval =>
          ConversationLivePhase.awaitingApproval,
        ConversationActivityKind.awaitingInput =>
          ConversationLivePhase.awaitingInput,
        ConversationActivityKind.stopping => ConversationLivePhase.stopping,
        ConversationActivityKind.storageBlocked =>
          ConversationLivePhase.storageBlocked,
      };

  static List<ConversationActivityDetail> _extractNonToolAndNonStreamDetails(
    ConversationActivityView view,
    ConversationLivePhase phase,
  ) {
    final hasActiveTools = view.activeTools.isNotEmpty;
    final hasReasoningText =
        view.reasoningText != null && view.reasoningText!.trim().isNotEmpty;
    final out = <ConversationActivityDetail>[];
    for (final detail in view.details) {
      if (hasActiveTools && detail.id.startsWith('tool:')) {
        continue;
      }
      if (hasReasoningText && detail.id.startsWith('reasoning:')) {
        continue;
      }
      if (phase == ConversationLivePhase.responding &&
          detail.id.startsWith('response:')) {
        continue;
      }
      out.add(detail);
    }
    return out;
  }

  /// 根据活跃工具条目与可选详情创建泛型 [ConversationLiveToolStartedMessage]。
  static ConversationLiveStatusMessage createToolStartedMessage(
    ThreadActivityToolEntry entry, {
    ThreadActivityToolDetail? detail,
    DateTime? fallbackStartedAt,
  }) {
    final startedAt = entry.startedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(
            entry.startedAt! * 1000,
            isUtc: true,
          )
        : fallbackStartedAt;
    final executionState = switch (entry.state) {
      ThreadActivityToolState.running =>
        ConversationLiveToolExecutionState.running,
      ThreadActivityToolState.awaitingApproval =>
        ConversationLiveToolExecutionState.awaitingApproval,
      ThreadActivityToolState.cancelling =>
        ConversationLiveToolExecutionState.cancelling,
      ThreadActivityToolState.finished =>
        ConversationLiveToolExecutionState.finished,
    };
    final argsMap = _tryDecodeJsonObject(detail?.arguments);
    final output = detail?.output ?? '';
    final name = entry.name.trim();

    switch (name) {
      case 'exec':
      case 'write_stdin':
        final cmd =
            _stringField(argsMap, 'command') ??
            (entry.arguments == ThreadActivityArgumentsKind.commandLine
                ? entry.summary
                : '');
        final cwd =
            _stringField(argsMap, 'workdir') ??
            _stringField(argsMap, 'cwd') ??
            _stringField(argsMap, 'working_directory');
        final stdinInput =
            _stringField(argsMap, 'chars') ?? _stringField(argsMap, 'input');
        return ConversationLiveToolStartedMessage<
          CommandLiveToolState,
          CommandLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const CommandLiveToolSpec(),
          initialState: CommandLiveToolState(
            command: cmd,
            workingDirectory: cwd,
            stdout: output,
            stdinInput: stdinInput,
            isWriteStdin: name == 'write_stdin',
          ),
          startedAt: startedAt,
          executionState: executionState,
        );

      case 'read':
      case 'edit':
      case 'create':
      case 'delete':
      case 'copy':
      case 'move':
      case 'apply_patch':
        final path =
            _stringField(argsMap, 'file_path') ??
            _stringField(argsMap, 'path') ??
            _stringField(argsMap, 'source') ??
            (entry.summary != name ? entry.summary : '');
        final dest =
            _stringField(argsMap, 'destination') ??
            _stringField(argsMap, 'to') ??
            _stringField(argsMap, 'target_path');
        final startLine =
            _intField(argsMap, 'offset') ?? _intField(argsMap, 'start_line');
        final endLine =
            _intField(argsMap, 'limit') ?? _intField(argsMap, 'end_line');
        final lineRange = startLine != null
            ? (endLine != null ? 'L$startLine-$endLine' : 'L$startLine')
            : null;
        return ConversationLiveToolStartedMessage<
          FileLiveToolState,
          FileLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const FileLiveToolSpec(),
          initialState: FileLiveToolState(
            operation: name,
            path: path,
            destinationPath: dest,
            lineRange: lineRange,
            diffPreview: output.isNotEmpty
                ? output
                : (_stringField(argsMap, 'patch') ?? ''),
          ),
          startedAt: startedAt,
          executionState: executionState,
        );

      case 'web_search':
      case 'deepseek_web_search':
      case 'search_session_note':
        final queries = <String>[
          ?_stringField(argsMap, 'query'),
          if (argsMap?['queries'] case final List<Object?> list)
            for (final item in list)
              if (item is String && item.trim().isNotEmpty) item.trim(),
        ];
        if (queries.isEmpty &&
            entry.summary.trim().isNotEmpty &&
            entry.summary.trim() != name) {
          queries.add(entry.summary.trim());
        }
        return ConversationLiveToolStartedMessage<
          WebSearchLiveToolState,
          WebSearchLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const WebSearchLiveToolSpec(),
          initialState: WebSearchLiveToolState(
            toolName: name,
            queries: queries,
            resultsPreview: output,
          ),
          startedAt: startedAt,
          executionState: executionState,
        );

      case 'deepseek_web_fetch':
      case 'web_fetch':
        final url =
            _stringField(argsMap, 'url') ??
            (entry.summary != name ? entry.summary : '');
        final prompt = _stringField(argsMap, 'prompt');
        return ConversationLiveToolStartedMessage<
          WebFetchLiveToolState,
          WebFetchLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const WebFetchLiveToolSpec(),
          initialState: WebFetchLiveToolState(
            url: url,
            prompt: prompt,
            responsePreview: output,
          ),
          startedAt: startedAt,
          executionState: executionState,
        );

      case 'spawn_agent':
      case 'send_message':
        final role =
            _stringField(argsMap, 'role') ??
            _stringField(argsMap, 'agent_type');
        final target =
            _stringField(argsMap, 'recipient') ??
            _stringField(argsMap, 'agent_id');
        final prompt =
            _stringField(argsMap, 'prompt') ??
            _stringField(argsMap, 'message') ??
            (entry.summary != name ? entry.summary : null);
        return ConversationLiveToolStartedMessage<
          SubagentLiveToolState,
          SubagentLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const SubagentLiveToolSpec(),
          initialState: SubagentLiveToolState(
            toolName: name,
            role: role,
            targetAgent: target,
            taskPrompt: prompt,
            latestOutput: output,
          ),
          startedAt: startedAt,
          executionState: executionState,
        );

      case 'wait':
      case 'sleep':
        return ConversationLiveToolStartedMessage<
          WaitLiveToolState,
          WaitLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const WaitLiveToolSpec(),
          initialState: WaitLiveToolState(
            toolName: name,
            waitPresentation: detail?.wait ?? entry.wait,
            fallbackSummary: entry.summary,
            outputPreview: output,
          ),
          startedAt: startedAt,
          executionState: executionState,
        );

      case 'view_image':
        final path =
            _stringField(argsMap, 'path') ??
            _stringField(argsMap, 'image_path') ??
            (entry.summary != name ? entry.summary : '');
        return ConversationLiveToolStartedMessage<
          ImageLiveToolState,
          ImageLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const ImageLiveToolSpec(),
          initialState: ImageLiveToolState(
            path: path,
            detail: output.isNotEmpty ? output : detail?.arguments,
          ),
          startedAt: startedAt,
          executionState: executionState,
        );

      default:
        if (name.startsWith('lsp_')) {
          final file =
              _stringField(argsMap, 'file_path') ??
              _stringField(argsMap, 'path') ??
              '';
          final symbol =
              _stringField(argsMap, 'symbol') ?? _stringField(argsMap, 'query');
          return ConversationLiveToolStartedMessage<
            CodeIntelligenceLiveToolState,
            CodeIntelligenceLiveToolEvent
          >(
            callId: entry.callId,
            toolName: name,
            spec: const CodeIntelligenceLiveToolSpec(),
            initialState: CodeIntelligenceLiveToolState(
              toolName: name,
              filePath: file,
              symbolOrPosition: symbol,
              outputPreview: output,
            ),
            startedAt: startedAt,
            executionState: executionState,
          );
        }
        if (name.startsWith('plan_') ||
            name.startsWith('workflow_') ||
            name == 'update_plan' ||
            name == 'todo_write') {
          final summary =
              _stringField(argsMap, 'title') ??
              _stringField(argsMap, 'summary') ??
              (entry.summary != name ? entry.summary : '');
          return ConversationLiveToolStartedMessage<
            PlanWorkflowLiveToolState,
            PlanWorkflowLiveToolEvent
          >(
            callId: entry.callId,
            toolName: name,
            spec: const PlanWorkflowLiveToolSpec(),
            initialState: PlanWorkflowLiveToolState(
              toolName: name,
              actionSummary: summary,
              markdownPreview: output.isNotEmpty
                  ? output
                  : (detail?.arguments ?? ''),
            ),
            startedAt: startedAt,
            executionState: executionState,
          );
        }
        return ConversationLiveToolStartedMessage<
          GenericLiveToolState,
          GenericLiveToolEvent
        >(
          callId: entry.callId,
          toolName: name,
          spec: const GenericLiveToolSpec(),
          initialState: GenericLiveToolState(
            toolName: name,
            summary: entry.summary,
            argumentsText: detail?.arguments,
            outputText: output.isEmpty ? null : output,
          ),
          startedAt: startedAt,
          executionState: executionState,
        );
    }
  }

  static Map<String, Object?>? _tryDecodeJsonObject(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static String? _stringField(Map<String, Object?>? map, String key) {
    final value = map?[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  static int? _intField(Map<String, Object?>? map, String key) {
    final value = map?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}
