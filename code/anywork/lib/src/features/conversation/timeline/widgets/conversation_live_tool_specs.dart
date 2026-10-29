import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import 'conversation_live_status_models.dart';

/// 二级工具详情区的统一无框纯文本引导容器：
/// 左侧 `1px` 竖向细导引线 + 纯文本/等宽行，不使用任何嵌套卡片边框、底色盒或胶囊徽章。
class LiveToolDetailRail extends StatelessWidget {
  const LiveToolDetailRail({
    required this.children,
    this.elapsedSeconds,
    super.key,
  });

  final List<Widget> children;
  final int? elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final railColor = scheme.outlineVariant.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.only(left: 7, top: 3, bottom: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: railColor, width: 1)),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 11, top: 1, bottom: 1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (elapsedSeconds != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '已执行 ${elapsedSeconds}s',
                    style: context.text.labelSmall?.copyWith(
                      fontFamily: studioCodeFontFamily,
                      fontSize: 11,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
                      height: 1.3,
                    ),
                  ),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _monoDetailLine(
  BuildContext context,
  String text, {
  Color? color,
  int? maxLines,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Text(
    text,
    maxLines: maxLines,
    overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
    style: context.text.bodySmall?.copyWith(
      fontFamily: studioCodeFontFamily,
      fontSize: 11.5,
      height: 1.42,
      color: color ?? scheme.onSurfaceVariant,
    ),
  );
}

Widget _metaDetailLine(BuildContext context, String label, String value) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: RichText(
      text: TextSpan(
        style: context.text.bodySmall?.copyWith(
          fontSize: 11.5,
          height: 1.38,
          color: scheme.onSurfaceVariant,
        ),
        children: [
          TextSpan(
            text: '$label  ',
            style: TextStyle(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
            ),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(fontFamily: studioCodeFontFamily),
          ),
        ],
      ),
    ),
  );
}

// ============================================================================
// 1. 命令执行工具 (`exec` / `write_stdin`)
// ============================================================================

class CommandLiveToolState {
  const CommandLiveToolState({
    required this.command,
    this.workingDirectory,
    this.stdout = '',
    this.stdinInput,
    this.isWriteStdin = false,
  });

  final String command;
  final String? workingDirectory;
  final String stdout;
  final String? stdinInput;
  final bool isWriteStdin;

  CommandLiveToolState copyWith({
    String? command,
    String? workingDirectory,
    String? stdout,
    String? stdinInput,
    bool? isWriteStdin,
  }) {
    return CommandLiveToolState(
      command: command ?? this.command,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      stdout: stdout ?? this.stdout,
      stdinInput: stdinInput ?? this.stdinInput,
      isWriteStdin: isWriteStdin ?? this.isWriteStdin,
    );
  }
}

sealed class CommandLiveToolEvent {
  const CommandLiveToolEvent();
}

final class CommandStdoutAppendEvent extends CommandLiveToolEvent {
  const CommandStdoutAppendEvent(this.chunk);
  final String chunk;
}

final class CommandStdoutReplaceEvent extends CommandLiveToolEvent {
  const CommandStdoutReplaceEvent(this.stdout);
  final String stdout;
}

final class CommandArgumentsUpdatedEvent extends CommandLiveToolEvent {
  const CommandArgumentsUpdatedEvent({
    this.command,
    this.workingDirectory,
    this.stdinInput,
  });

  final String? command;
  final String? workingDirectory;
  final String? stdinInput;
}

final class CommandLiveToolSpec
    implements LiveToolSpec<CommandLiveToolState, CommandLiveToolEvent> {
  const CommandLiveToolSpec();

  @override
  CommandLiveToolState reduce(
    CommandLiveToolState state,
    CommandLiveToolEvent message,
  ) {
    return switch (message) {
      CommandStdoutAppendEvent(:final chunk) => state.copyWith(
        stdout: '${state.stdout}$chunk',
      ),
      CommandStdoutReplaceEvent(:final stdout) => state.copyWith(
        stdout: stdout,
      ),
      CommandArgumentsUpdatedEvent(
        :final command,
        :final workingDirectory,
        :final stdinInput,
      ) =>
        state.copyWith(
          command: command,
          workingDirectory: workingDirectory,
          stdinInput: stdinInput,
        ),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, CommandLiveToolState state) {
    final cmd = state.command.trim();
    if (state.isWriteStdin) {
      final input = state.stdinInput?.trim();
      return input != null && input.isNotEmpty
          ? 'stdin · $input'
          : (cmd.isEmpty ? 'write_stdin' : cmd);
    }
    return cmd.isEmpty ? 'exec' : cmd;
  }

  @override
  String? buildSubtitleLabel(BuildContext context, CommandLiveToolState state) {
    final cwd = state.workingDirectory?.trim();
    return cwd == null || cwd.isEmpty ? null : cwd;
  }

  @override
  Widget buildLeading(BuildContext context, CommandLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      state.isWriteStdin ? '›' : r'$',
      style: context.text.labelSmall?.copyWith(
        fontFamily: studioCodeFontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        color: scheme.primary,
      ),
    );
  }

  @override
  bool isExpandable(CommandLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    CommandLiveToolState state, {
    required int elapsedSeconds,
  }) {
    final cwd = state.workingDirectory;
    final stdout = state.stdout;
    final cmd = state.command;
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        if (cwd != null && cwd.isNotEmpty) _metaDetailLine(context, 'cwd', cwd),
        if (cmd.isNotEmpty) _monoDetailLine(context, '\$ $cmd'),
        if (state.stdinInput != null && state.stdinInput!.isNotEmpty)
          _metaDetailLine(context, 'stdin', state.stdinInput!),
        if (stdout.isNotEmpty) ...[
          const SizedBox(height: 3),
          _monoDetailLine(context, stdout),
        ],
      ],
    );
  }
}

// ============================================================================
// 2. 现役文件写入、目录、复制移动与 apply_patch 工具
// ============================================================================

class FileLiveToolState {
  const FileLiveToolState({
    required this.operation,
    required this.path,
    this.destinationPath,
    this.lineRange,
    this.diffPreview = '',
  });

  final String operation;
  final String path;
  final String? destinationPath;
  final String? lineRange;
  final String diffPreview;

  FileLiveToolState copyWith({
    String? operation,
    String? path,
    String? destinationPath,
    String? lineRange,
    String? diffPreview,
  }) {
    return FileLiveToolState(
      operation: operation ?? this.operation,
      path: path ?? this.path,
      destinationPath: destinationPath ?? this.destinationPath,
      lineRange: lineRange ?? this.lineRange,
      diffPreview: diffPreview ?? this.diffPreview,
    );
  }
}

sealed class FileLiveToolEvent {
  const FileLiveToolEvent();
}

final class FileDiffAppendEvent extends FileLiveToolEvent {
  const FileDiffAppendEvent(this.chunk);
  final String chunk;
}

final class FileDiffReplaceEvent extends FileLiveToolEvent {
  const FileDiffReplaceEvent(this.diffPreview);
  final String diffPreview;
}

final class FileTargetUpdatedEvent extends FileLiveToolEvent {
  const FileTargetUpdatedEvent({
    this.path,
    this.destinationPath,
    this.lineRange,
  });

  final String? path;
  final String? destinationPath;
  final String? lineRange;
}

final class FileLiveToolSpec
    implements LiveToolSpec<FileLiveToolState, FileLiveToolEvent> {
  const FileLiveToolSpec();

  @override
  FileLiveToolState reduce(FileLiveToolState state, FileLiveToolEvent message) {
    return switch (message) {
      FileDiffAppendEvent(:final chunk) => state.copyWith(
        diffPreview: '${state.diffPreview}$chunk',
      ),
      FileDiffReplaceEvent(:final diffPreview) => state.copyWith(
        diffPreview: diffPreview,
      ),
      FileTargetUpdatedEvent(
        :final path,
        :final destinationPath,
        :final lineRange,
      ) =>
        state.copyWith(
          path: path,
          destinationPath: destinationPath,
          lineRange: lineRange,
        ),
    };
  }

  String _verb(String op) => switch (op) {
    'write_file' => 'Write',
    'create_directory' => 'Create directory',
    'delete_path' => 'Delete',
    'copy_path' => 'Copy',
    'move_path' => 'Move',
    'apply_patch' => 'Patch',
    _ => op,
  };

  @override
  String buildSummaryLabel(BuildContext context, FileLiveToolState state) {
    final verb = _verb(state.operation);
    final path = state.path.trim();
    if (path.isEmpty) return verb;
    final range = state.lineRange?.trim();
    if (range != null && range.isNotEmpty) {
      return '$verb · $path ($range)';
    }
    return '$verb · $path';
  }

  @override
  String? buildSubtitleLabel(BuildContext context, FileLiveToolState state) {
    final dest = state.destinationPath?.trim();
    return dest == null || dest.isEmpty ? null : '→ $dest';
  }

  @override
  Widget buildLeading(BuildContext context, FileLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (state.operation) {
      'write_file' || 'apply_patch' => Icons.edit_outlined,
      'create_directory' => Icons.create_new_folder_outlined,
      'delete_path' => Icons.delete_outline,
      'copy_path' || 'move_path' => Icons.drive_file_move_outline,
      _ => Icons.insert_drive_file_outlined,
    };
    return Icon(icon, size: 13, color: scheme.onSurfaceVariant);
  }

  @override
  bool isExpandable(FileLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    FileLiveToolState state, {
    required int elapsedSeconds,
  }) {
    final diff = state.diffPreview;
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        if (state.path.trim().isNotEmpty)
          _metaDetailLine(context, _verb(state.operation), state.path.trim()),
        if (state.destinationPath != null &&
            state.destinationPath!.trim().isNotEmpty)
          _metaDetailLine(context, 'target', state.destinationPath!.trim()),
        if (state.lineRange != null && state.lineRange!.trim().isNotEmpty)
          _metaDetailLine(context, 'lines', state.lineRange!.trim()),
        if (diff.isNotEmpty) ...[
          const SizedBox(height: 3),
          _monoDetailLine(context, diff),
        ],
      ],
    );
  }
}

// ============================================================================
// 3. 搜索工具 (`web_search` / `deepseek_web_search` / `search_session_note`)
// ============================================================================

class WebSearchLiveToolState {
  const WebSearchLiveToolState({
    required this.toolName,
    this.queries = const [],
    this.resultsPreview = '',
  });

  final String toolName;
  final List<String> queries;
  final String resultsPreview;

  WebSearchLiveToolState copyWith({
    String? toolName,
    List<String>? queries,
    String? resultsPreview,
  }) {
    return WebSearchLiveToolState(
      toolName: toolName ?? this.toolName,
      queries: queries ?? this.queries,
      resultsPreview: resultsPreview ?? this.resultsPreview,
    );
  }
}

sealed class WebSearchLiveToolEvent {
  const WebSearchLiveToolEvent();
}

final class WebSearchQueryAddedEvent extends WebSearchLiveToolEvent {
  const WebSearchQueryAddedEvent(this.query);
  final String query;
}

final class WebSearchResultsUpdatedEvent extends WebSearchLiveToolEvent {
  const WebSearchResultsUpdatedEvent(this.resultsPreview);
  final String resultsPreview;
}

final class WebSearchLiveToolSpec
    implements LiveToolSpec<WebSearchLiveToolState, WebSearchLiveToolEvent> {
  const WebSearchLiveToolSpec();

  @override
  WebSearchLiveToolState reduce(
    WebSearchLiveToolState state,
    WebSearchLiveToolEvent message,
  ) {
    return switch (message) {
      WebSearchQueryAddedEvent(:final query) => state.copyWith(
        queries: [...state.queries, query],
      ),
      WebSearchResultsUpdatedEvent(:final resultsPreview) => state.copyWith(
        resultsPreview: resultsPreview,
      ),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, WebSearchLiveToolState state) {
    final prefix = state.toolName == 'search_session_note'
        ? 'NoteSearch'
        : 'Search';
    if (state.queries.isEmpty) return prefix;
    final first = state.queries.first.trim();
    final extra = state.queries.length > 1
        ? ' (+${state.queries.length - 1})'
        : '';
    return '$prefix · "$first"$extra';
  }

  @override
  String? buildSubtitleLabel(
    BuildContext context,
    WebSearchLiveToolState state,
  ) => null;

  @override
  Widget buildLeading(BuildContext context, WebSearchLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(
      Icons.travel_explore_outlined,
      size: 13,
      color: scheme.onSurfaceVariant,
    );
  }

  @override
  bool isExpandable(WebSearchLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    WebSearchLiveToolState state, {
    required int elapsedSeconds,
  }) {
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        for (final query in state.queries)
          _metaDetailLine(context, 'query', query),
        if (state.resultsPreview.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          _monoDetailLine(context, state.resultsPreview),
        ],
      ],
    );
  }
}

// ============================================================================
// 4. 网页抓取工具 (`deepseek_web_fetch` / `web_fetch`)
// ============================================================================

class WebFetchLiveToolState {
  const WebFetchLiveToolState({
    required this.url,
    this.prompt,
    this.responsePreview = '',
  });

  final String url;
  final String? prompt;
  final String responsePreview;

  WebFetchLiveToolState copyWith({
    String? url,
    String? prompt,
    String? responsePreview,
  }) {
    return WebFetchLiveToolState(
      url: url ?? this.url,
      prompt: prompt ?? this.prompt,
      responsePreview: responsePreview ?? this.responsePreview,
    );
  }
}

sealed class WebFetchLiveToolEvent {
  const WebFetchLiveToolEvent();
}

final class WebFetchProgressEvent extends WebFetchLiveToolEvent {
  const WebFetchProgressEvent(this.responsePreview);
  final String responsePreview;
}

final class WebFetchLiveToolSpec
    implements LiveToolSpec<WebFetchLiveToolState, WebFetchLiveToolEvent> {
  const WebFetchLiveToolSpec();

  @override
  WebFetchLiveToolState reduce(
    WebFetchLiveToolState state,
    WebFetchLiveToolEvent message,
  ) {
    return switch (message) {
      WebFetchProgressEvent(:final responsePreview) => state.copyWith(
        responsePreview: responsePreview,
      ),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, WebFetchLiveToolState state) {
    final url = state.url.trim();
    return url.isEmpty ? 'Fetch' : 'Fetch · $url';
  }

  @override
  String? buildSubtitleLabel(
    BuildContext context,
    WebFetchLiveToolState state,
  ) => state.prompt?.trim();

  @override
  Widget buildLeading(BuildContext context, WebFetchLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(
      Icons.public_outlined,
      size: 13,
      color: scheme.onSurfaceVariant,
    );
  }

  @override
  bool isExpandable(WebFetchLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    WebFetchLiveToolState state, {
    required int elapsedSeconds,
  }) {
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        if (state.url.trim().isNotEmpty)
          _metaDetailLine(context, 'url', state.url.trim()),
        if (state.prompt != null && state.prompt!.trim().isNotEmpty)
          _metaDetailLine(context, 'prompt', state.prompt!.trim()),
        if (state.responsePreview.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          _monoDetailLine(context, state.responsePreview),
        ],
      ],
    );
  }
}

// ============================================================================
// 5. 子代理协同工具 (`spawn_agent` / `send_message`)
// ============================================================================

class SubagentLiveToolState {
  const SubagentLiveToolState({
    required this.toolName,
    this.role,
    this.targetAgent,
    this.taskPrompt,
    this.latestOutput = '',
  });

  final String toolName;
  final String? role;
  final String? targetAgent;
  final String? taskPrompt;
  final String latestOutput;

  SubagentLiveToolState copyWith({
    String? toolName,
    String? role,
    String? targetAgent,
    String? taskPrompt,
    String? latestOutput,
  }) {
    return SubagentLiveToolState(
      toolName: toolName ?? this.toolName,
      role: role ?? this.role,
      targetAgent: targetAgent ?? this.targetAgent,
      taskPrompt: taskPrompt ?? this.taskPrompt,
      latestOutput: latestOutput ?? this.latestOutput,
    );
  }
}

sealed class SubagentLiveToolEvent {
  const SubagentLiveToolEvent();
}

final class SubagentOutputUpdatedEvent extends SubagentLiveToolEvent {
  const SubagentOutputUpdatedEvent(this.latestOutput);
  final String latestOutput;
}

final class SubagentLiveToolSpec
    implements LiveToolSpec<SubagentLiveToolState, SubagentLiveToolEvent> {
  const SubagentLiveToolSpec();

  @override
  SubagentLiveToolState reduce(
    SubagentLiveToolState state,
    SubagentLiveToolEvent message,
  ) {
    return switch (message) {
      SubagentOutputUpdatedEvent(:final latestOutput) => state.copyWith(
        latestOutput: latestOutput,
      ),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, SubagentLiveToolState state) {
    final target = (state.role ?? state.targetAgent ?? '').trim();
    final action = state.toolName == 'send_message' ? 'Message' : 'Subagent';
    final task = state.taskPrompt?.trim() ?? '';
    if (target.isNotEmpty && task.isNotEmpty) {
      return '$action · $target · $task';
    }
    if (target.isNotEmpty) return '$action · $target';
    if (task.isNotEmpty) return '$action · $task';
    return action;
  }

  @override
  String? buildSubtitleLabel(
    BuildContext context,
    SubagentLiveToolState state,
  ) => null;

  @override
  Widget buildLeading(BuildContext context, SubagentLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(Icons.hub_outlined, size: 13, color: scheme.onSurfaceVariant);
  }

  @override
  bool isExpandable(SubagentLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    SubagentLiveToolState state, {
    required int elapsedSeconds,
  }) {
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        if (state.role != null && state.role!.trim().isNotEmpty)
          _metaDetailLine(context, 'role', state.role!.trim()),
        if (state.targetAgent != null && state.targetAgent!.trim().isNotEmpty)
          _metaDetailLine(context, 'target', state.targetAgent!.trim()),
        if (state.taskPrompt != null && state.taskPrompt!.trim().isNotEmpty)
          _metaDetailLine(context, 'task', state.taskPrompt!.trim()),
        if (state.latestOutput.trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          _monoDetailLine(context, state.latestOutput),
        ],
      ],
    );
  }
}

// ============================================================================
// 6. 等待与计时工具 (`wait` / `sleep`)
// ============================================================================

class WaitLiveToolState {
  const WaitLiveToolState({
    required this.toolName,
    this.waitPresentation,
    this.fallbackSummary = '',
    this.outputPreview = '',
  });

  final String toolName;
  final ThreadWaitPresentationView? waitPresentation;
  final String fallbackSummary;
  final String outputPreview;

  WaitLiveToolState copyWith({
    String? toolName,
    ThreadWaitPresentationView? waitPresentation,
    String? fallbackSummary,
    String? outputPreview,
  }) {
    return WaitLiveToolState(
      toolName: toolName ?? this.toolName,
      waitPresentation: waitPresentation ?? this.waitPresentation,
      fallbackSummary: fallbackSummary ?? this.fallbackSummary,
      outputPreview: outputPreview ?? this.outputPreview,
    );
  }
}

sealed class WaitLiveToolEvent {
  const WaitLiveToolEvent();
}

final class WaitPresentationUpdatedEvent extends WaitLiveToolEvent {
  const WaitPresentationUpdatedEvent(this.waitPresentation);
  final ThreadWaitPresentationView waitPresentation;
}

final class WaitOutputUpdatedEvent extends WaitLiveToolEvent {
  const WaitOutputUpdatedEvent(this.outputPreview);
  final String outputPreview;
}

final class WaitLiveToolSpec
    implements LiveToolSpec<WaitLiveToolState, WaitLiveToolEvent> {
  const WaitLiveToolSpec();

  @override
  WaitLiveToolState reduce(WaitLiveToolState state, WaitLiveToolEvent message) {
    return switch (message) {
      WaitPresentationUpdatedEvent(:final waitPresentation) => state.copyWith(
        waitPresentation: waitPresentation,
      ),
      WaitOutputUpdatedEvent(:final outputPreview) => state.copyWith(
        outputPreview: outputPreview,
      ),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, WaitLiveToolState state) {
    final wait = state.waitPresentation;
    if (wait != null) {
      switch (wait.intent) {
        case ThreadWaitEventsIntentView(:final targets, :final timeoutMs):
          for (final target in targets) {
            final summary = target.summary?.trim();
            if (summary != null && summary.isNotEmpty) {
              return target.summaryTruncated ? '$summary…' : summary;
            }
            final toolName = target.toolName?.trim();
            if (toolName != null && toolName.isNotEmpty) {
              return 'Wait · $toolName';
            }
          }
          final secs = (timeoutMs / 1000).round();
          return 'Wait · ${secs}s';
        case ThreadWaitTimerIntentView(:final durationMs):
          final secs = (durationMs / 1000).round();
          final fallback = state.fallbackSummary.trim();
          if (fallback.isNotEmpty && fallback != state.toolName) {
            return 'Sleep ${secs}s · $fallback';
          }
          return 'Sleep · ${secs}s';
      }
    }
    final fallback = state.fallbackSummary.trim();
    return fallback.isEmpty ? state.toolName : fallback;
  }

  @override
  String? buildSubtitleLabel(BuildContext context, WaitLiveToolState state) =>
      null;

  @override
  Widget buildLeading(BuildContext context, WaitLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    final icon = state.toolName == 'sleep'
        ? Icons.schedule_outlined
        : Icons.hourglass_bottom_rounded;
    return Icon(icon, size: 13, color: scheme.onSurfaceVariant);
  }

  @override
  bool isExpandable(WaitLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    WaitLiveToolState state, {
    required int elapsedSeconds,
  }) {
    final wait = state.waitPresentation;
    final children = <Widget>[];
    if (wait != null) {
      switch (wait.intent) {
        case ThreadWaitEventsIntentView(:final targets, :final timeoutMs):
          children.add(_metaDetailLine(context, 'timeout', '${timeoutMs}ms'));
          for (final target in targets) {
            final label = target.toolName?.trim() ?? target.taskId;
            final summary =
                target.summary?.trim() ?? target.status?.name ?? 'waiting';
            children.add(_metaDetailLine(context, label, summary));
          }
        case ThreadWaitTimerIntentView(:final durationMs):
          final secs = (durationMs / 1000).round();
          children.add(_metaDetailLine(context, 'duration', '${secs}s'));
      }
    }
    if (state.outputPreview.trim().isNotEmpty) {
      children.add(_monoDetailLine(context, state.outputPreview));
    } else if (children.isEmpty && state.fallbackSummary.trim().isNotEmpty) {
      children.add(_monoDetailLine(context, state.fallbackSummary.trim()));
    }
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: children,
    );
  }
}

// ============================================================================
// 7. 图像查看工具 (`view_image`)
// ============================================================================

class ImageLiveToolState {
  const ImageLiveToolState({required this.path, this.detail});

  final String path;
  final String? detail;

  ImageLiveToolState copyWith({String? path, String? detail}) {
    return ImageLiveToolState(
      path: path ?? this.path,
      detail: detail ?? this.detail,
    );
  }
}

sealed class ImageLiveToolEvent {
  const ImageLiveToolEvent();
}

final class ImageDetailUpdatedEvent extends ImageLiveToolEvent {
  const ImageDetailUpdatedEvent(this.detail);
  final String detail;
}

final class ImageLiveToolSpec
    implements LiveToolSpec<ImageLiveToolState, ImageLiveToolEvent> {
  const ImageLiveToolSpec();

  @override
  ImageLiveToolState reduce(
    ImageLiveToolState state,
    ImageLiveToolEvent message,
  ) {
    return switch (message) {
      ImageDetailUpdatedEvent(:final detail) => state.copyWith(detail: detail),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, ImageLiveToolState state) {
    final path = state.path.trim();
    return path.isEmpty ? 'Image' : 'Image · $path';
  }

  @override
  String? buildSubtitleLabel(BuildContext context, ImageLiveToolState state) =>
      null;

  @override
  Widget buildLeading(BuildContext context, ImageLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(Icons.image_outlined, size: 13, color: scheme.onSurfaceVariant);
  }

  @override
  bool isExpandable(ImageLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    ImageLiveToolState state, {
    required int elapsedSeconds,
  }) {
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        if (state.path.trim().isNotEmpty)
          _metaDetailLine(context, 'image', state.path.trim()),
        if (state.detail != null && state.detail!.trim().isNotEmpty)
          _monoDetailLine(context, state.detail!),
      ],
    );
  }
}

// ============================================================================
// 8. 代码智能工具 (`lsp_*`)
// ============================================================================

class CodeIntelligenceLiveToolState {
  const CodeIntelligenceLiveToolState({
    required this.toolName,
    this.filePath = '',
    this.symbolOrPosition,
    this.outputPreview = '',
  });

  final String toolName;
  final String filePath;
  final String? symbolOrPosition;
  final String outputPreview;

  CodeIntelligenceLiveToolState copyWith({
    String? toolName,
    String? filePath,
    String? symbolOrPosition,
    String? outputPreview,
  }) {
    return CodeIntelligenceLiveToolState(
      toolName: toolName ?? this.toolName,
      filePath: filePath ?? this.filePath,
      symbolOrPosition: symbolOrPosition ?? this.symbolOrPosition,
      outputPreview: outputPreview ?? this.outputPreview,
    );
  }
}

sealed class CodeIntelligenceLiveToolEvent {
  const CodeIntelligenceLiveToolEvent();
}

final class CodeIntelligenceOutputEvent extends CodeIntelligenceLiveToolEvent {
  const CodeIntelligenceOutputEvent(this.outputPreview);
  final String outputPreview;
}

final class CodeIntelligenceLiveToolSpec
    implements
        LiveToolSpec<
          CodeIntelligenceLiveToolState,
          CodeIntelligenceLiveToolEvent
        > {
  const CodeIntelligenceLiveToolSpec();

  @override
  CodeIntelligenceLiveToolState reduce(
    CodeIntelligenceLiveToolState state,
    CodeIntelligenceLiveToolEvent message,
  ) {
    return switch (message) {
      CodeIntelligenceOutputEvent(:final outputPreview) => state.copyWith(
        outputPreview: outputPreview,
      ),
    };
  }

  @override
  String buildSummaryLabel(
    BuildContext context,
    CodeIntelligenceLiveToolState state,
  ) {
    final op = state.toolName.replaceFirst('lsp_', 'LSP ');
    final file = state.filePath.trim();
    return file.isEmpty ? op : '$op · $file';
  }

  @override
  String? buildSubtitleLabel(
    BuildContext context,
    CodeIntelligenceLiveToolState state,
  ) => state.symbolOrPosition?.trim();

  @override
  Widget buildLeading(
    BuildContext context,
    CodeIntelligenceLiveToolState state,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(Icons.code_rounded, size: 13, color: scheme.onSurfaceVariant);
  }

  @override
  bool isExpandable(CodeIntelligenceLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    CodeIntelligenceLiveToolState state, {
    required int elapsedSeconds,
  }) {
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        _metaDetailLine(context, 'tool', state.toolName),
        if (state.filePath.trim().isNotEmpty)
          _metaDetailLine(context, 'file', state.filePath.trim()),
        if (state.symbolOrPosition != null &&
            state.symbolOrPosition!.trim().isNotEmpty)
          _metaDetailLine(context, 'symbol', state.symbolOrPosition!.trim()),
        if (state.outputPreview.trim().isNotEmpty)
          _monoDetailLine(context, state.outputPreview),
      ],
    );
  }
}

// ============================================================================
// 9. 计划与工作流工具 (`plan_*` / `workflow_*` / `update_plan` / `todo_write`)
// ============================================================================

class PlanWorkflowLiveToolState {
  const PlanWorkflowLiveToolState({
    required this.toolName,
    this.actionSummary = '',
    this.markdownPreview = '',
  });

  final String toolName;
  final String actionSummary;
  final String markdownPreview;

  PlanWorkflowLiveToolState copyWith({
    String? toolName,
    String? actionSummary,
    String? markdownPreview,
  }) {
    return PlanWorkflowLiveToolState(
      toolName: toolName ?? this.toolName,
      actionSummary: actionSummary ?? this.actionSummary,
      markdownPreview: markdownPreview ?? this.markdownPreview,
    );
  }
}

sealed class PlanWorkflowLiveToolEvent {
  const PlanWorkflowLiveToolEvent();
}

final class PlanWorkflowPreviewUpdatedEvent extends PlanWorkflowLiveToolEvent {
  const PlanWorkflowPreviewUpdatedEvent(this.markdownPreview);
  final String markdownPreview;
}

final class PlanWorkflowLiveToolSpec
    implements
        LiveToolSpec<PlanWorkflowLiveToolState, PlanWorkflowLiveToolEvent> {
  const PlanWorkflowLiveToolSpec();

  @override
  PlanWorkflowLiveToolState reduce(
    PlanWorkflowLiveToolState state,
    PlanWorkflowLiveToolEvent message,
  ) {
    return switch (message) {
      PlanWorkflowPreviewUpdatedEvent(:final markdownPreview) => state.copyWith(
        markdownPreview: markdownPreview,
      ),
    };
  }

  @override
  String buildSummaryLabel(
    BuildContext context,
    PlanWorkflowLiveToolState state,
  ) {
    final summary = state.actionSummary.trim();
    return summary.isEmpty ? state.toolName : '${state.toolName} · $summary';
  }

  @override
  String? buildSubtitleLabel(
    BuildContext context,
    PlanWorkflowLiveToolState state,
  ) => null;

  @override
  Widget buildLeading(BuildContext context, PlanWorkflowLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(
      Icons.checklist_rtl_outlined,
      size: 13,
      color: scheme.onSurfaceVariant,
    );
  }

  @override
  bool isExpandable(PlanWorkflowLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    PlanWorkflowLiveToolState state, {
    required int elapsedSeconds,
  }) {
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        _metaDetailLine(context, 'tool', state.toolName),
        if (state.actionSummary.trim().isNotEmpty)
          _metaDetailLine(context, 'action', state.actionSummary.trim()),
        if (state.markdownPreview.trim().isNotEmpty)
          _monoDetailLine(context, state.markdownPreview),
      ],
    );
  }
}

// ============================================================================
// 10. 通用扩展/MCP 工具兜底 (`GenericLiveToolSpec`)
// ============================================================================

class GenericLiveToolState {
  const GenericLiveToolState({
    required this.toolName,
    this.summary = '',
    this.argumentsText,
    this.outputText,
  });

  final String toolName;
  final String summary;
  final String? argumentsText;
  final String? outputText;

  GenericLiveToolState copyWith({
    String? toolName,
    String? summary,
    String? argumentsText,
    String? outputText,
  }) {
    return GenericLiveToolState(
      toolName: toolName ?? this.toolName,
      summary: summary ?? this.summary,
      argumentsText: argumentsText ?? this.argumentsText,
      outputText: outputText ?? this.outputText,
    );
  }
}

sealed class GenericLiveToolEvent {
  const GenericLiveToolEvent();
}

final class GenericLiveToolUpdatedEvent extends GenericLiveToolEvent {
  const GenericLiveToolUpdatedEvent({
    this.summary,
    this.argumentsText,
    this.outputText,
  });

  final String? summary;
  final String? argumentsText;
  final String? outputText;
}

final class GenericLiveToolSpec
    implements LiveToolSpec<GenericLiveToolState, GenericLiveToolEvent> {
  const GenericLiveToolSpec();

  @override
  GenericLiveToolState reduce(
    GenericLiveToolState state,
    GenericLiveToolEvent message,
  ) {
    return switch (message) {
      GenericLiveToolUpdatedEvent(
        :final summary,
        :final argumentsText,
        :final outputText,
      ) =>
        state.copyWith(
          summary: summary,
          argumentsText: argumentsText,
          outputText: outputText,
        ),
    };
  }

  @override
  String buildSummaryLabel(BuildContext context, GenericLiveToolState state) {
    final trimmed = state.summary.trim();
    if (trimmed.isEmpty || trimmed == state.toolName) return state.toolName;
    return '${state.toolName} · $trimmed';
  }

  @override
  String? buildSubtitleLabel(
    BuildContext context,
    GenericLiveToolState state,
  ) => null;

  @override
  Widget buildLeading(BuildContext context, GenericLiveToolState state) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(Icons.build_outlined, size: 13, color: scheme.onSurfaceVariant);
  }

  @override
  bool isExpandable(GenericLiveToolState state) => true;

  @override
  Widget buildExpandedDetails(
    BuildContext context,
    GenericLiveToolState state, {
    required int elapsedSeconds,
  }) {
    final args = state.argumentsText;
    final out = state.outputText;
    return LiveToolDetailRail(
      elapsedSeconds: elapsedSeconds,
      children: [
        _metaDetailLine(context, 'tool', state.toolName),
        if (args != null && args.isNotEmpty) _monoDetailLine(context, args),
        if (out != null && out.isNotEmpty) ...[
          const SizedBox(height: 3),
          _monoDetailLine(context, out),
        ],
      ],
    );
  }
}
