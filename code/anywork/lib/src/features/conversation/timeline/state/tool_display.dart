import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../../../l10n/app_localizations.dart';
import '../../../../shared/typed_json.dart';
import 'tool_presentation.dart';

enum ToolDisplayCategory {
  read,
  edit,
  create,
  delete,
  copy,
  move,
  command,
  stdin,
  search,
  fetch,
  agent,
  message,
  plan,
  planRead,
  workflow,
  workflowRead,
  lsp,
  image,
  wait,
  generic,
}

enum ToolDetailKind {
  standard,
  patch,
  lspQuery,
  lspCapabilities,
  lspStatus,
  web,
  image,
}

enum ToolInputBody { none, patch, fileContent }

enum ToolOutputFormat { structured, text, lsp }

enum ToolAcceptance { pending, accepted, rejected }

final class ToolAcceptanceProjection {
  const ToolAcceptanceProjection(this.state, {this.code, this.reason});
  final ToolAcceptance state;
  final String? code;
  final String? reason;
}

sealed class ToolDetailValue {
  const ToolDetailValue();
}

final class ToolDetailText extends ToolDetailValue {
  const ToolDetailText(this.title, this.text, {this.code = false});
  final String title;
  final String text;
  final bool code;
}

final class ToolDetailLink extends ToolDetailValue {
  const ToolDetailLink(this.title, this.url);
  final String title;
  final String url;
}

final class ToolDetailUnavailable extends ToolDetailValue {
  const ToolDetailUnavailable(this.reason);
  final String reason;
}

typedef ToolRowTarget = ({String? label, String? tooltip});

// A strategy owns display semantics, never content readers or acceptance epochs.
abstract class ToolDisplaySpec {
  const ToolDisplaySpec(
    this.contract,
    this.category, {
    this.kind = ToolDetailKind.standard,
    this.inputBody = ToolInputBody.none,
    this.outputFormat = ToolOutputFormat.structured,
    this.omitSuccessOutput = false,
    this.targetFields = const [],
    this.fileTarget = false,
    this.elapsed = false,
    this.circularProgress = false,
  });

  final String contract;
  final ToolDisplayCategory category;
  final ToolDetailKind kind;
  final ToolInputBody inputBody;
  final ToolOutputFormat outputFormat;
  final bool omitSuccessOutput;
  final List<String> targetFields;
  final bool fileTarget;
  final bool elapsed;
  final bool circularProgress;

  String displayName(AppLocalizations l10n, TimelineToolPresentation item);

  IconData get icon => toolCategoryIcon(category);
  bool get requiresAcceptance => false;
  bool get isLsp => switch (kind) {
    ToolDetailKind.lspQuery ||
    ToolDetailKind.lspCapabilities ||
    ToolDetailKind.lspStatus => true,
    _ => false,
  };

  String rejectionLabel(AppLocalizations l10n) =>
      l10n.timelineToolOperationRejected;

  String? verb(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolCategoryVerb(l10n, category, item.statusString);

  String? target(TimelineToolPresentation item) {
    final arguments = decodeJsonObject(item.arguments);
    for (final key in targetFields) {
      final value = toolFirstLine(jsonStringValue(arguments[key]));
      if (value != null) return value;
    }
    return null;
  }

  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) {
    final value = target(item);
    return (
      label: fileTarget ? toolPathBasename(value) : value,
      tooltip: value,
    );
  }

  String statusTitle(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolStatusTitle(l10n, item.statusString, displayName(l10n, item));

  String title(
    AppLocalizations l10n,
    TimelineToolPresentation item, {
    ToolAcceptanceProjection? acceptance,
  }) => _acceptanceLabel(l10n, item, acceptance) ?? statusTitle(l10n, item);

  String rowLabel(
    AppLocalizations l10n,
    TimelineToolPresentation item,
    String? target, {
    ToolAcceptanceProjection? acceptance,
  }) {
    final label = _acceptanceLabel(l10n, item, acceptance);
    if (label != null) return [label, ?target].join(' ');
    final action = verb(l10n, item);
    if (action == null) {
      return [
        statusTitle(l10n, item),
        if (target != null && target.isNotEmpty) target,
      ].join(' · ');
    }
    return target == null || target.isEmpty ? action : '$action $target';
  }

  String? _acceptanceLabel(
    AppLocalizations l10n,
    TimelineToolPresentation item,
    ToolAcceptanceProjection? acceptance,
  ) {
    if (!requiresAcceptance || item.statusString != 'succeeded') return null;
    return switch ((acceptance ?? decodeAcceptance(item.output)).state) {
      ToolAcceptance.pending => l10n.timelineToolResultPending,
      ToolAcceptance.rejected => rejectionLabel(l10n),
      ToolAcceptance.accepted => null,
    };
  }

  bool readsOutput(String status, {String output = ''}) =>
      !omitSuccessOutput ||
      status != 'succeeded' ||
      (requiresAcceptance &&
          decodeAcceptance(output).state != ToolAcceptance.accepted);

  ToolAcceptanceProjection acceptanceFromResult(Object? result) =>
      const ToolAcceptanceProjection(ToolAcceptance.pending);

  ToolAcceptanceProjection decodeAcceptance(String text) {
    if (text.trim().isEmpty || !requiresAcceptance) {
      return const ToolAcceptanceProjection(ToolAcceptance.pending);
    }
    try {
      final result = jsonDecode(text);
      return result is Map<String, dynamic> || result is List
          ? acceptanceFromResult(result)
          : const ToolAcceptanceProjection(ToolAcceptance.pending);
    } on FormatException {
      return const ToolAcceptanceProjection(ToolAcceptance.pending);
    }
  }

  List<ToolDetailValue> acceptanceDetails(
    AppLocalizations l10n,
    ToolAcceptanceProjection projection,
  ) => switch (projection.state) {
    ToolAcceptance.pending => [
      ToolDetailUnavailable(l10n.timelineToolAcceptanceUnavailable),
    ],
    ToolAcceptance.accepted => const [],
    ToolAcceptance.rejected => List.unmodifiable([
      ToolDetailText(
        rejectionLabel(l10n),
        projection.code ?? projection.reason ?? rejectionLabel(l10n),
      ),
      if (projection.code != null && projection.reason != null)
        ToolDetailText(l10n.timelineToolDetailReason, projection.reason!),
    ]),
  };

  List<ToolDetailValue> input(AppLocalizations l10n, String text) => const [];
  List<ToolDetailValue> output(AppLocalizations l10n, Object? result) =>
      toolProject(l10n, result, const {});
  List<ToolDetailValue> artifacts(AppLocalizations l10n, String text) =>
      const [];

  List<ToolDetailValue> decodeInput(AppLocalizations l10n, String text) =>
      _decode(l10n, () => input(l10n, text));

  List<ToolDetailValue> decodeOutput(AppLocalizations l10n, String text) {
    if (text.trim().isEmpty) return const [];
    return _decode(l10n, () {
      final result = switch (outputFormat) {
        ToolOutputFormat.text => text,
        ToolOutputFormat.structured => toolStructuredResult(l10n, text),
        ToolOutputFormat.lsp => _lspResult(text),
      };
      final projection = requiresAcceptance
          ? acceptanceFromResult(result)
          : null;
      return projection != null && projection.state != ToolAcceptance.pending
          ? acceptanceDetails(l10n, projection)
          : output(l10n, result);
    });
  }

  List<ToolDetailValue> _decode(
    AppLocalizations l10n,
    List<ToolDetailValue> Function() decode,
  ) {
    try {
      return List.unmodifiable(decode());
    } on FormatException catch (error) {
      return [
        ToolDetailUnavailable(l10n.timelineToolContentMalformed(error.message)),
      ];
    } on RangeError {
      return [ToolDetailUnavailable(l10n.timelineToolNumberOutOfRange)];
    }
  }
}

Map<String, ToolDisplaySpec> buildToolDisplayRegistry(
  Iterable<ToolDisplaySpec> displays,
) {
  final registry = <String, ToolDisplaySpec>{};
  for (final display in displays) {
    if (registry.containsKey(display.contract)) {
      throw ArgumentError.value(
        display.contract,
        'contract',
        'Duplicate tool display contract',
      );
    }
    registry[display.contract] = display;
  }
  return Map.unmodifiable(registry);
}

Object? _lspResult(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

Object toolStructuredResult(AppLocalizations l10n, String text) {
  final Object? result;
  try {
    result = jsonDecode(text);
  } on FormatException {
    throw FormatException(l10n.timelineToolStructuredUnavailable);
  }
  if (result is Map<String, dynamic> || result is List) return result!;
  throw FormatException(l10n.timelineToolExpectedStructured);
}

Map<String, dynamic> toolArguments(AppLocalizations l10n, String text) {
  return switch (jsonDecode(text)) {
    final Map<String, dynamic> result => result,
    _ => throw FormatException(l10n.timelineToolExpectedObject),
  };
}

List<ToolDetailValue> toolField(
  AppLocalizations l10n,
  Map<String, dynamic> data,
  String key,
  String title, {
  bool code = false,
  bool required = false,
}) => switch (data[key]) {
  final String value when value.trim().isNotEmpty || key == 'content' => [
    ToolDetailText(title, value, code: code),
  ],
  null || '' when !required => const [],
  _ => throw FormatException(l10n.timelineToolInvalidField(title)),
};

Map<String, String> toolDiagnosticFields(AppLocalizations l10n) => {
  'error': l10n.timelineToolDetailError,
  'message': l10n.timelineToolDetailDescription,
  'reason': l10n.timelineToolDetailReason,
  'diagnostic': l10n.timelineToolDetailDiagnostic,
  'detail': l10n.timelineToolDetailDiagnosticDetail,
  'code': l10n.timelineToolDetailDiagnosticCode,
};

List<ToolDetailValue> toolTextResult(AppLocalizations l10n, Object? result) =>
    switch (result) {
      final String text when text.trim().isNotEmpty => [
        ToolDetailText(l10n.timelineToolDetailResult, text),
      ],
      null || '' => const [],
      _ => throw FormatException(l10n.timelineToolExpectedText),
    };

List<ToolDetailValue> toolProject(
  AppLocalizations l10n,
  Object? result,
  Map<String, String> fields,
) => toolResultFields(l10n, result, {...fields, ...toolDiagnosticFields(l10n)});

List<ToolDetailValue> toolResultFields(
  AppLocalizations l10n,
  Object? result,
  Map<String, String> fields, {
  bool unavailableWhenEmpty = true,
}) {
  if (result == null) return const [];
  if (result is String) return toolTextResult(l10n, result);
  if (result is List) {
    return [
      for (final entry in result) ...toolResultFields(l10n, entry, fields),
    ];
  }
  if (result is! Map<String, dynamic>) {
    return [ToolDetailUnavailable(l10n.timelineToolResultMalformed)];
  }
  final values = <ToolDetailValue>[];
  for (final MapEntry(key: key, value: title) in fields.entries) {
    switch (result[key]) {
      case final String text when text.trim().isNotEmpty:
        values.add(
          key == 'url'
              ? ToolDetailLink(title, text)
              : ToolDetailText(title, text),
        );
      case final num number:
        values.add(ToolDetailText(title, '$number'));
      case final bool flag:
        values.add(
          ToolDetailText(
            title,
            flag ? l10n.timelineToolDetailYes : l10n.timelineToolDetailNo,
          ),
        );
      case final List entries:
        if (entries.isEmpty) {
          values.add(ToolDetailText(title, l10n.timelineToolDetailNone));
        }
        for (final entry in entries) {
          values.addAll(toolResultFields(l10n, entry, fields));
        }
      case final Map<String, dynamic> nested:
        values.addAll(toolResultFields(l10n, nested, fields));
      case null:
        break;
      default:
        values.add(
          ToolDetailUnavailable(l10n.timelineToolFieldMalformed(title)),
        );
    }
  }
  if (unavailableWhenEmpty && values.isEmpty && result.isNotEmpty) {
    values.add(ToolDetailUnavailable(l10n.timelineToolNoSemanticContent));
  }
  return values;
}

String? toolFirstLine(String? value) {
  final line = value?.split('\n').first.trim();
  return line == null || line.isEmpty ? null : line;
}

String? toolPathBasename(String? value) {
  if (value == null) return null;
  // A remote Windows path must remain readable on a Linux display host.
  final segment = (value.contains(r'\') ? p.windows : p.posix)
      .basename(value)
      .trim();
  return segment.isEmpty ? value : segment;
}

String toolStatusTitle(AppLocalizations l10n, String status, String name) {
  final label = name.trim().isEmpty ? l10n.timelineToolFallback : name;
  return switch (status) {
    'queued' => l10n.timelineToolQueued(label),
    'cancelling' => l10n.timelineToolCancelling(label),
    'interrupted' => l10n.timelineToolInterrupted(label),
    'succeeded' => l10n.timelineToolCompleted(label),
    'failed' => l10n.timelineToolFailed(label),
    'denied' => l10n.timelineToolDenied(label),
    'cancelled' => l10n.timelineToolCancelled(label),
    'awaitingApproval' => l10n.timelineToolAwaitingApproval(label),
    'running' ||
    'streaming' ||
    'approved' ||
    'started' => l10n.timelineToolRunning(label),
    _ =>
      status.trim().isEmpty
          ? label
          : l10n.timelineToolUnknownStatus(label, status),
  };
}

IconData toolCategoryIcon(ToolDisplayCategory category) => switch (category) {
  ToolDisplayCategory.read => Icons.menu_book_outlined,
  ToolDisplayCategory.edit => Icons.edit_outlined,
  ToolDisplayCategory.create => Icons.create_new_folder_outlined,
  ToolDisplayCategory.delete => Icons.delete_outline,
  ToolDisplayCategory.copy => Icons.content_copy_outlined,
  ToolDisplayCategory.move => Icons.drive_file_move_outline,
  ToolDisplayCategory.command => Icons.terminal,
  ToolDisplayCategory.stdin => Icons.terminal,
  ToolDisplayCategory.search => Icons.search,
  ToolDisplayCategory.fetch => Icons.public,
  ToolDisplayCategory.agent => Icons.account_tree_outlined,
  ToolDisplayCategory.message => Icons.send_outlined,
  ToolDisplayCategory.plan => Icons.checklist_rtl,
  ToolDisplayCategory.planRead => Icons.checklist_rtl,
  ToolDisplayCategory.workflow => Icons.route_outlined,
  ToolDisplayCategory.workflowRead => Icons.route_outlined,
  ToolDisplayCategory.lsp => Icons.code,
  ToolDisplayCategory.image => Icons.image_outlined,
  ToolDisplayCategory.wait => Icons.hourglass_empty,
  ToolDisplayCategory.generic => Icons.build_outlined,
};

String? toolCategoryVerb(
  AppLocalizations l10n,
  ToolDisplayCategory category,
  String status,
) {
  final running = const {
    'running',
    'streaming',
    'approved',
    'started',
  }.contains(status);
  final failed = status == 'failed';
  if (!running && !failed && status != 'succeeded') return null;
  return switch (category) {
    ToolDisplayCategory.read =>
      running
          ? l10n.timelineToolReadReading
          : failed
          ? l10n.timelineToolReadFailed
          : l10n.timelineToolReadCompleted,
    ToolDisplayCategory.edit =>
      running
          ? l10n.timelineToolEditRunning
          : failed
          ? l10n.timelineToolEditFailed
          : l10n.timelineToolEditSucceeded,
    ToolDisplayCategory.create =>
      running
          ? l10n.timelineToolCreateRunning
          : failed
          ? l10n.timelineToolCreateFailed
          : l10n.timelineToolCreateSucceeded,
    ToolDisplayCategory.delete =>
      running
          ? l10n.timelineToolDeleteRunning
          : failed
          ? l10n.timelineToolDeleteFailed
          : l10n.timelineToolDeleteSucceeded,
    ToolDisplayCategory.copy =>
      running
          ? l10n.timelineToolCopyRunning
          : failed
          ? l10n.timelineToolCopyFailed
          : l10n.timelineToolCopySucceeded,
    ToolDisplayCategory.move =>
      running
          ? l10n.timelineToolMoveRunning
          : failed
          ? l10n.timelineToolMoveFailed
          : l10n.timelineToolMoveSucceeded,
    ToolDisplayCategory.command =>
      running
          ? l10n.timelineToolCommandRunning
          : failed
          ? l10n.timelineToolCommandFailed
          : l10n.timelineToolCommandSucceeded,
    // 写标准输入不是执行新命令，独立文案也不附加调用耗时。
    ToolDisplayCategory.stdin =>
      running
          ? l10n.timelineToolStdinRunning
          : failed
          ? l10n.timelineToolStdinFailed
          : l10n.timelineToolStdinSucceeded,
    ToolDisplayCategory.search =>
      running
          ? l10n.timelineToolSearchRunning
          : failed
          ? l10n.timelineToolSearchFailed
          : l10n.timelineToolSearchSucceeded,
    ToolDisplayCategory.fetch =>
      running
          ? l10n.timelineToolFetchRunning
          : failed
          ? l10n.timelineToolFetchFailed
          : l10n.timelineToolFetchSucceeded,
    ToolDisplayCategory.agent =>
      running
          ? l10n.timelineToolAgentRunning
          : failed
          ? l10n.timelineToolAgentFailed
          : l10n.timelineToolAgentSucceeded,
    ToolDisplayCategory.message =>
      running
          ? l10n.timelineToolMessageRunning
          : failed
          ? l10n.timelineToolMessageFailed
          : l10n.timelineToolMessageSucceeded,
    ToolDisplayCategory.plan =>
      running
          ? l10n.timelineToolPlanRunning
          : failed
          ? l10n.timelineToolPlanFailed
          : l10n.timelineToolPlanSucceeded,
    ToolDisplayCategory.workflow =>
      running
          ? l10n.timelineToolWorkflowRunning
          : failed
          ? l10n.timelineToolWorkflowFailed
          : l10n.timelineToolWorkflowSucceeded,
    ToolDisplayCategory.lsp =>
      running
          ? l10n.timelineToolLspRunning
          : failed
          ? l10n.timelineToolLspFailed
          : l10n.timelineToolLspSucceeded,
    ToolDisplayCategory.image =>
      running
          ? l10n.timelineViewImageReading
          : failed
          ? l10n.timelineViewImageFailed
          : l10n.timelineViewImageRead,
    ToolDisplayCategory.wait =>
      running
          ? l10n.timelineToolWaitRunning
          : failed
          ? l10n.timelineToolWaitFailed
          : l10n.timelineToolWaitSucceeded,
    // 只读的计划/工作流查询与未知工具沿用“名称＋真实状态”，不猜测成变更。
    ToolDisplayCategory.planRead ||
    ToolDisplayCategory.workflowRead ||
    ToolDisplayCategory.generic => null,
  };
}
