import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'startup_view.dart';
import 'startup_view_model.dart';

/// Bootstrap is explicitly started by app lifecycle. This boundary observes it;
/// reconstructing or restoring a Router never calls start again.
class ApplicationStartupBoundary extends ConsumerWidget {
  const ApplicationStartupBoundary({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupViewModelProvider);
    void retry() => unawaited(ref.read(startupViewModelProvider.notifier).retry());
    return startup.when(
      data: (value) => value.bootstrapError != null
          ? Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(32),
              child: ApplicationStartupFailureView(failure: value.bootstrapError!,
                retryPending: value.retryPending, onRetry: retry))))
          : value.startup is ReadyStartupState ? child
          : ApplicationStartupView(state: value, onRetry: retry),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(32),
          child: ApplicationStartupFailureView(failure: error, retryPending: false, onRetry: () {
            // The first observer could not be admitted. Recreate only this
            // read-only VM, then use the same explicit bootstrap responsibility.
            ref.invalidate(startupViewModelProvider);
            if (ref.read(startupViewModelProvider).asData != null) retry();
          }))));
      },
    );
  }
}
