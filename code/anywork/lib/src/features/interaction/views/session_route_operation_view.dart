import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../state/session_options_state.dart';

/// Rendering only. Retry eligibility and the retained rejected target belong
/// to the VM; unknown/observation failures are never offered as write retries.
class SessionRouteOperationView extends StatelessWidget {
  const SessionRouteOperationView({
    required this.state,
    required this.attempted,
    required this.reading,
    this.readError,
    this.onRetryRead,
    this.onRetry,
    super.key,
  });
  final SessionOptionsState? state;
  final ModelSelection? attempted;
  final bool reading;
  final StudioFailure? readError;
  final VoidCallback? onRetryRead;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final operation = state?.operation;
    final unknown =
        operation?.failurePhase == OperationFailurePhase.unknownOutcome;
    final phase = operation == null
        ? null
        : unknown
        ? OperationFailurePhase.unknownOutcome.name
        : operation.durable
        ? 'durable'
        : operation.effective
        ? 'effective'
        : operation.observed
        ? 'observed'
        : operation.receipt != null
        ? 'awaitingObservation'
        : operation.failurePhase?.name;
    final failures = {
      ?state?.error,
      ?operation?.error,
      ?operation?.evidenceError,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reading || state?.pending == true && !unknown)
          const LinearProgressIndicator(),
        if (phase != null)
          Text(phase, key: const ValueKey('session-model-route-operation')),
        for (final failure in failures)
          Text(
            '${failure.message} (${failure.code.name}; ${failure.correlationId})',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (attempted case final selection? when onRetry != null)
          TextButton(
            onPressed: onRetry,
            key: const ValueKey('session-model-route-retry'),
            child: Text(
              '${context.l10n.runtimeFatalRetry} · ${selection.model.modelId}'
              '${selection.effort == null ? '' : ' · ${selection.effort}'}',
            ),
          ),
        if (readError case final error?) ...[
          Text('${error.message} (${error.code.name}; ${error.correlationId})'),
          TextButton(
            onPressed: reading ? null : onRetryRead,
            child: Text(context.l10n.runtimeFatalRetry),
          ),
        ],
      ],
    );
  }
}
