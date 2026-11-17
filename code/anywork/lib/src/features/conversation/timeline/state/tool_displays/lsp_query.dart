import '../../../../../l10n/app_localizations.dart';
import '../tool_display.dart';
import '../tool_presentation.dart';
import '../../../../../shared/typed_json.dart';
import '../lsp_presentation.dart';

final class LspQueryToolDisplay extends ToolDisplaySpec {
  const LspQueryToolDisplay()
    : super(
        'builtin.lsp_query@1',
        ToolDisplayCategory.lsp,
        kind: ToolDetailKind.lspQuery,
        outputFormat: ToolOutputFormat.lsp,
        targetFields: const ['filePath', 'query', 'languageId'],
      );

  @override
  String displayName(AppLocalizations l10n, TimelineToolPresentation item) {
    final data = decodeJsonObject(item.arguments);
    final raw = jsonStringValue(data['operation']);
    final detail =
        [
              if (raw != null)
                timelineLspOperationLabel(
                  l10n,
                  TimelineLspOperation.fromWire(raw),
                  raw: raw,
                ),
              jsonStringValue(data['languageId']),
              jsonStringValue(data['filePath']),
              jsonStringValue(data['query']),
            ]
            .map((value) => value?.trim() ?? '')
            .where((value) => value.isNotEmpty)
            .join(' · ');
    return detail.isEmpty
        ? l10n.timelineLspQueryTitle
        : l10n.timelineLspQueryTitleWithDetail(detail);
  }

  @override
  String? verb(AppLocalizations l10n, TimelineToolPresentation item) {
    final running = const {
      'running',
      'streaming',
      'approved',
      'started',
    }.contains(item.statusString);
    final failed = item.statusString == 'failed';
    if (!running && !failed && item.statusString != 'succeeded') return null;
    return switch (TimelineLspOperation.fromWire(
      jsonStringValue(decodeJsonObject(item.arguments)['operation']),
    )) {
      TimelineLspOperation.goToDefinition =>
        running
            ? l10n.timelineLspOpDefinitionRunning
            : failed
            ? l10n.timelineLspOpDefinitionFailed
            : l10n.timelineLspOpDefinitionSucceeded,
      TimelineLspOperation.goToImplementation =>
        running
            ? l10n.timelineLspOpImplementationRunning
            : failed
            ? l10n.timelineLspOpImplementationFailed
            : l10n.timelineLspOpImplementationSucceeded,
      TimelineLspOperation.findReferences =>
        running
            ? l10n.timelineLspOpReferencesRunning
            : failed
            ? l10n.timelineLspOpReferencesFailed
            : l10n.timelineLspOpReferencesSucceeded,
      TimelineLspOperation.hover =>
        running
            ? l10n.timelineLspOpHoverRunning
            : failed
            ? l10n.timelineLspOpHoverFailed
            : l10n.timelineLspOpHoverSucceeded,
      TimelineLspOperation.documentSymbol =>
        running
            ? l10n.timelineLspOpDocumentSymbolRunning
            : failed
            ? l10n.timelineLspOpDocumentSymbolFailed
            : l10n.timelineLspOpDocumentSymbolSucceeded,
      TimelineLspOperation.workspaceSymbol =>
        running
            ? l10n.timelineLspOpWorkspaceSymbolRunning
            : failed
            ? l10n.timelineLspOpWorkspaceSymbolFailed
            : l10n.timelineLspOpWorkspaceSymbolSucceeded,
      TimelineLspOperation.prepareCallHierarchy ||
      TimelineLspOperation.incomingCalls ||
      TimelineLspOperation.outgoingCalls =>
        running
            ? l10n.timelineLspOpCallHierarchyRunning
            : failed
            ? l10n.timelineLspOpCallHierarchyFailed
            : l10n.timelineLspOpCallHierarchySucceeded,
      TimelineLspOperation.diagnostics =>
        running
            ? l10n.timelineLspOpDiagnosticsRunning
            : failed
            ? l10n.timelineLspOpDiagnosticsFailed
            : l10n.timelineLspOpDiagnosticsSucceeded,
      TimelineLspOperation.unknown =>
        running
            ? l10n.timelineToolLspRunning
            : failed
            ? l10n.timelineToolLspFailed
            : l10n.timelineToolLspSucceeded,
    };
  }

  @override
  ToolRowTarget rowTarget(
    AppLocalizations l10n,
    TimelineToolPresentation item,
  ) {
    final args = decodeJsonObject(item.arguments);
    final filePath = toolFirstLine(jsonStringValue(args['filePath']));
    final line = switch (args['line']) {
      final int n => n,
      final num n => n.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    final character = switch (args['character']) {
      final int n => n,
      final num n => n.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (filePath != null) {
      final shortName = toolPathBasename(filePath) ?? filePath;
      final lineSuffix = (line != null && line > 0) ? ':$line' : '';
      final fullCoord = (line != null && line > 0)
          ? (character != null && character > 0
                ? ':$line:$character'
                : ':$line')
          : '';
      return (label: '$shortName$lineSuffix', tooltip: '$filePath$fullCoord');
    }
    final query = toolFirstLine(jsonStringValue(args['query']));
    if (query != null) {
      return (label: query, tooltip: query);
    }
    final languageId = toolFirstLine(jsonStringValue(args['languageId']));
    if (languageId != null) {
      return (label: languageId, tooltip: languageId);
    }
    return (label: null, tooltip: null);
  }
}
