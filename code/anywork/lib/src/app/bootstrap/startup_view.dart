import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';

import '../../l10n/studio_l10n.dart';
import 'startup_view_state.dart';

class ApplicationStartupView extends StatelessWidget {
  const ApplicationStartupView({required this.state, required this.onRetry, super.key});
  final StartupViewState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final startup = state.startup;
    final failure = startup is FailedStartupState ? startup.error : null;
    return Scaffold(
      key: const ValueKey('studio-startup'),
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset(MediaQuery.disableAnimationsOf(context)
                ? 'assets/branding/anywork-startup-cat.png'
                : 'assets/branding/anywork-startup-cat.webp',
              key: const ValueKey('studio-startup-animation'),
              width: 160, height: 160, fit: BoxFit.contain,
              filterQuality: FilterQuality.high, excludeFromSemantics: true),
            const SizedBox(height: 24),
            Text(context.l10n.appTitle, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            if (failure != null) ...[
              ApplicationStartupFailureView(failure: failure,
                retryPending: state.retryPending, onRetry: onRetry),
            ] else ...[
              Semantics(liveRegion: true, child: Text(_phaseLabel(context, startup),
                textAlign: TextAlign.center)),
              const SizedBox(height: 24),
              const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2.4)),
            ],
          ]),
        ),
      ))),
    );
  }

  String _phaseLabel(BuildContext context, StartupState value) {
    final l10n = context.l10n;
    final phase = value is StartingStartupState ? value.phase : null;
    // Native phases are not enum-monotonic. Display the actual event without
    // sorting, synthesizing intermediate phases, or equating stage Ready to a
    // successful start result.
    return switch (phase) {
      NativeStartupPhase(:final stage) => switch (stage) {
        StartupStage.preparing => l10n.startupPreparing,
        StartupStage.waitingForSteps => l10n.startupWaiting,
        StartupStage.closingResources => l10n.startupClosing,
        StartupStage.backingUp => l10n.startupBackingUp,
        StartupStage.resetting => l10n.startupResetting,
        StartupStage.startingServices => l10n.startupServices,
        StartupStage.openingStorage => l10n.startupStorage,
        StartupStage.loadingConfiguration => l10n.startupConfiguration,
        StartupStage.readingProjects => l10n.startupProjects,
        StartupStage.preparingResources => l10n.startupResources,
        StartupStage.ready => l10n.startupState,
        StartupStage.failed => l10n.runtimeFatalTitle,
      },
      _ => l10n.startupPreparing,
    };
  }
}

class ApplicationStartupFailureView extends StatelessWidget {
  const ApplicationStartupFailureView({
    required this.failure, required this.retryPending, required this.onRetry, super.key,
  });
  final StudioFailure failure;
  final bool retryPending;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
    const SizedBox(height: 12),
    Text(context.l10n.runtimeFatalTitle, style: Theme.of(context).textTheme.titleMedium),
    const SizedBox(height: 10),
    SelectableText('${failure.message}\n${failure.code.name}'
      '${failure.correlationId.isEmpty ? '' : ' · ${failure.correlationId}'}',
      textAlign: TextAlign.center),
    const SizedBox(height: 20),
    FilledButton.icon(key: const ValueKey('runtime-fatal-retry'),
      onPressed: retryPending ? null : onRetry,
      icon: const Icon(Icons.refresh), label: Text(context.l10n.runtimeFatalRetry)),
  ]);
}
