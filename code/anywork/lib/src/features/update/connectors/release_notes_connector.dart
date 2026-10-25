import 'dart:async';

import 'package:anywork_client/updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/release_notes_view_model.dart';
import '../views/release_notes_view.dart';

/// The existing Updates VM retains check/preparation/restart and canonical
/// summary ownership. This connector adds only the platform action surface.
class ReleaseNotesConnector extends ConsumerWidget {
  const ReleaseNotesConnector({required this.summary, super.key});
  final UpdateSummary? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = this.summary;
    if (summary == null || summary.notesUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    final provider = releaseNotesViewModelProvider(summary);
    return ref
        .watch(provider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Text(error.toString()),
          data: (state) {
            final vm = ref.read(provider.notifier);
            return ReleaseNotesView(
              opening: state.opening,
              error: state.error?.message,
              onOpen: () => unawaited(vm.open()),
            );
          },
        );
  }
}
