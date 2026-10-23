import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../view_models/settings_workspace_view_model.dart';
import 'settings_failure_text.dart';

/// A read-only Workspace context boundary for the two project-dependent tabs.
/// It never substitutes null for an unknown target or tears down other tabs.
class SettingsProjectContext extends ConsumerWidget {
  const SettingsProjectContext({required this.builder, super.key});
  final Widget Function(String? projectId) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(settingsWorkspaceViewModelProvider);
    final failure = value.asError;
    if (failure != null && failure.error is! StudioFailure) Error.throwWithStackTrace(failure.error, failure.stackTrace);
    final source = value.hasValue ? value.requireValue : null;
    if (source == null) {
      if (failure == null) return const Center(child: CircularProgressIndicator());
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SelectableText(settingsFailureText(failure.error as StudioFailure)),
        TextButton(onPressed: () => ref.invalidate(settingsWorkspaceViewModelProvider), child: Text(context.l10n.runtimeFatalRetry)),
      ]));
    }
    final blocked = value.isLoading || failure != null || !source.observing || source.source.sealed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (blocked) Padding(padding: const EdgeInsets.all(12), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(source.source.sealed ? context.l10n.workflowStateStopped : context.l10n.resourceSourceLastKnown),
          if (value.isLoading) Text(context.l10n.resourceSourceLoading),
          if (failure != null) SelectableText(settingsFailureText(failure.error as StudioFailure)),
          if (source.observationError case final error?) SelectableText(settingsFailureText(error)),
          if (failure != null || source.observationError != null) TextButton(
            onPressed: () {
              if (failure != null) { ref.invalidate(settingsWorkspaceViewModelProvider); }
              else { ref.read(settingsWorkspaceViewModelProvider.notifier).retryObservation(); }
            }, child: Text(context.l10n.runtimeFatalRetry)),
        ])),
      // Keep the same last-known panel mounted while its observation is
      // unavailable. Raw and accepted operations still belong to its VM/Repo;
      // user actions are paused rather than silently retargeted to null.
      Expanded(key: const ValueKey('settings-project-context-panel'), child: IgnorePointer(ignoring: blocked,
        child: ExcludeFocus(excluding: blocked, child: builder(source.projectId)))),
    ]);
  }
}
