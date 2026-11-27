import '../../../../../l10n/app_localizations.dart';
import 'tool_detail_values.dart';

String? _stream(AppLocalizations l10n, Object? value) => switch (value) {
  null => null,
  final String text => text,
  _ => throw FormatException(l10n.timelineToolStreamMalformed),
};

/// Projects structured `exec` / `write_stdin` result payloads while keeping
/// technical task IDs and unmapped keys hidden.
List<ToolDetailValue> toolExecutionResult(
  AppLocalizations l10n,
  Object? value,
) {
  if (value is! Map<String, dynamic>) {
    return [ToolDetailUnavailable(l10n.timelineToolExecutionMalformed)];
  }
  final stdout = _stream(l10n, value['stdout']);
  final stderr = _stream(l10n, value['stderr']);
  return [
    if (stdout != null && stdout.isNotEmpty)
      ToolDetailText(l10n.timelineToolDetailStdout, stdout, code: true),
    if (stderr != null && stderr.isNotEmpty)
      ToolDetailText(l10n.timelineToolDetailStderr, stderr, code: true),
    ...toolResultFields(
      l10n,
      value,
      toolDiagnosticFields(l10n),
      unavailableWhenEmpty: false,
    ),
    if (value['inputReceipt'] case final Map<String, dynamic> receipt)
      ...toolResultFields(l10n, _inputReceipt(l10n, receipt), {
        'acceptedBytes': l10n.timelineToolDetailAcceptedBytes,
        'closeState': l10n.timelineToolDetailInputCloseState,
        'outcome': l10n.timelineToolDetailInputOutcome,
        'detail': l10n.timelineToolDetailInputDiagnostic,
      }),
    if (value['exitCode'] case final int code)
      ToolDetailText(l10n.timelineToolDetailExitCode, '$code'),
    if (value['signal'] case final Object signal)
      ToolDetailText(l10n.timelineToolDetailSignal, '$signal'),
    if (value['timedOut'] == true)
      ToolDetailText(
        l10n.timelineToolDetailStatus,
        l10n.timelineToolStatusTimedOut,
      ),
  ];
}

Map<String, dynamic> _inputReceipt(
  AppLocalizations l10n,
  Map<String, dynamic> receipt,
) => {
  ...receipt,
  if (receipt['closeState'] case final String state)
    'closeState': switch (state) {
      'open' => l10n.timelineToolInputOpen,
      'closing' => l10n.timelineToolInputClosing,
      'closed' => l10n.timelineToolInputClosed,
      _ => state,
    },
  if (receipt['outcome'] case final String outcome)
    'outcome': switch (outcome) {
      'complete' => l10n.timelineToolInputComplete,
      'cancelled' => l10n.timelineToolInputCancelled,
      'partial' => l10n.timelineToolInputPartial,
      'failed' => l10n.timelineToolInputFailed,
      _ => outcome,
    },
};
