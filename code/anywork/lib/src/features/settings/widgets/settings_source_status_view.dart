import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';

/// Displays actual Observed metadata, independently of transport sync and local
/// command pending. Previous material keeps its identity and is labelled as
/// last-known; it is never promoted to the current header's source evidence.
class SettingsSourceStatusView extends StatelessWidget {
  const SettingsSourceStatusView({required this.title, required this.brief,
    required this.read, required this.origin, required this.reference,
    this.readError, this.onRetry, super.key});
  final String title;
  final ObservedBrief? brief;
  final ReadValue<ProductSourceStatus, ProductSourceStatusRef>? read;
  final ProductReadOrigin? origin;
  final ProductSourceStatusRef? reference;
  final String? readError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final material = switch (read) {
      ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef>(:final current) => current,
      LoadingReadValue<ProductSourceStatus, ProductSourceStatusRef>(:final previous) ||
      FailedReadValue<ProductSourceStatus, ProductSourceStatusRef>(:final previous) => previous,
      _ => null,
    };
    final current = read is ReadyReadValue<ProductSourceStatus, ProductSourceStatusRef> &&
      material?.origin == origin && reference != null && material?.reference == reference;
    final readFailure = switch (read) {
      FailedReadValue<ProductSourceStatus, ProductSourceStatusRef>(:final origin, :final reference, :final error) =>
        (origin, reference, error),
      _ => null,
    };
    final diagnostic = readError ?? (readFailure == null ? null
      : '${readFailure.$1 == origin && readFailure.$2 == reference ? '' : '${context.l10n.resourceSourceLastKnown} · '}'
        '${readFailure.$3.message} [${readFailure.$3.code.name}: ${readFailure.$3.correlationId}]');
    final header = switch (brief) {
      UninitializedObservedBrief(:final revision, :final updatedAt) => (context.l10n.resourceSourceUninitialized, revision, updatedAt, null),
      LoadingObservedBrief(:final revision, :final startedAt) => (context.l10n.resourceSourceLoading, revision, startedAt, null),
      ReadyObservedBrief(:final revision, :final updatedAt, :final lastCheckedAt) => (context.l10n.settingsReadyBadge, revision, updatedAt, lastCheckedAt),
      RefreshingObservedBrief(:final revision, :final startedAt, :final lastCheckedAt) => (context.l10n.resourceSourceRefreshing, revision, startedAt, lastCheckedAt),
      StaleObservedBrief(:final revision, :final staleAt, :final lastCheckedAt) => (context.l10n.resourceSourceStale, revision, staleAt, lastCheckedAt),
      DegradedObservedBrief(:final revision, :final failedAt, :final lastCheckedAt) => (context.l10n.resourceSourceDegraded, revision, failedAt, lastCheckedAt),
      FailedObservedBrief(:final revision, :final failedAt) => (context.l10n.toolStatusFailed, revision, failedAt, null),
      StoppedObservedBrief(:final revision, :final stoppedAt) => (context.l10n.workflowStateStopped, revision, stoppedAt, null),
      null => null,
    };
    final value = material?.value;
    final error = switch (value) {
      DegradedProductSourceStatus(:final error) || FailedProductSourceStatus(:final error) => error,
      _ => null,
    };
    final operation = switch (value) {
      LoadingProductSourceStatus(:final operation, :final operationId) ||
      RefreshingProductSourceStatus(:final operation, :final operationId) => '${operation.name} · $operationId',
      DegradedProductSourceStatus(:final operation) || FailedProductSourceStatus(:final operation) => operation.name,
      _ => null,
    };
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('$title · ${header == null ? '—' : '${header.$1} · r${header.$2} · ${_time(header.$3)}'}',
          style: Theme.of(context).textTheme.bodySmall),
        if (header?.$4 case final checked?) Text('${context.l10n.settingsModelCatalogChecked}: ${_time(checked)}'),
        if (material != null && !current) Text('${context.l10n.resourceSourceLastKnown} · ${material.origin.ownerEpoch}/${material.origin.incarnation} · r${material.reference.revision}',
          style: Theme.of(context).textTheme.bodySmall),
        if (operation != null) SelectableText(operation, style: Theme.of(context).textTheme.bodySmall),
        if (error != null) SelectableText('${error.message} [${error.code}]',
          style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (diagnostic != null) SelectableText(diagnostic, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (diagnostic != null && onRetry != null) Align(alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onRetry, child: Text(context.l10n.runtimeFatalRetry))),
      ]));
  }
  String _time(int value) => DateTime.fromMillisecondsSinceEpoch(value * 1000).toLocal().toIso8601String();
}
