import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';

/// Typed, bounded feedback. Do not format arbitrary exceptions or raw inputs.
class WorkspaceFailureNotice extends StatelessWidget {
  const WorkspaceFailureNotice({
    required this.failure,
    this.onRetry,
    super.key,
  });

  final StudioFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Icon(
          Icons.error_outline,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            '${failure.message}\n${failure.code.name}'
            '${failure.correlationId.isEmpty ? '' : ' · ${failure.correlationId}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (onRetry != null)
          IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh)),
      ],
    ),
  );
}

/// SourceStateError has no correlationId. Preserve its three source fields
/// rather than inventing a StudioFailure or a diagnostic identifier for it.
class WorkspaceSourceFailureNotice extends StatelessWidget {
  const WorkspaceSourceFailureNotice({required this.failure, super.key});
  final SourceStateError failure;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Icon(
          Icons.error_outline,
          size: 18,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            '${failure.message}\n${failure.code}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}
