import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../view_models/instructions_view_model.dart';
import '../views/instructions_view.dart';

class InstructionsConnector extends ConsumerWidget {
  const InstructionsConnector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(instructionsViewModelProvider);
    return value.when(
      data: (state) {
        final vm = ref.read(instructionsViewModelProvider.notifier);
        return InstructionsView(
          state: state,
          onSection: vm.setSection,
          onEdit: vm.edit,
          errors: [
            if (state.source.projection.sync.error case final error?)
              settingsFailureText(error),
            for (final error in state.readIssues.values)
              settingsFailureText(error),
            for (final draft in [state.base, state.developer, state.user]) ...[
              if (draft.action?.error case final error?)
                settingsFailureText(error),
              if (draft.action?.observationError case final error?)
                settingsFailureText(error),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(settingsFailureText(error)),
              TextButton(
                onPressed: () => ref.invalidate(instructionsViewModelProvider),
                child: Text(context.l10n.sidebarRetry),
              ),
            ],
          ),
        );
      },
    );
  }
}
