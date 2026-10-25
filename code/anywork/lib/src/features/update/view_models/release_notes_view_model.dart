import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../platform/error_log.dart';
import '../../../platform/external_url_launcher.dart';
import '../state/release_notes_state.dart';

part 'release_notes_view_model.g.dart';

@riverpod
class ReleaseNotesViewModel extends _$ReleaseNotesViewModel {
  @override
  FutureOr<ReleaseNotesState> build(UpdateSummary summary) =>
      const ReleaseNotesState();

  /// The Smart caller supplies a canonical summary, not an asset/download URL.
  /// Freeze the original URL and launcher before the first platform await.
  Future<void> open() async {
    if (!ref.mounted ||
        state.requireValue.opening ||
        summary.notesUrl.isEmpty) {
      return;
    }
    final url = summary.notesUrl;
    final launch = ref.read(externalUrlLauncherProvider);
    state = const AsyncData(ReleaseNotesState(opening: true));
    try {
      await launch(url);
    } catch (error, stack) {
      recordDartError(error, stack, stage: 'release-notes-launch');
      if (ref.mounted) {
        state = const AsyncData(
          ReleaseNotesState(
            opening: true,
            error: StudioFailure(
              code: StudioFailureCode.unavailable,
              message: 'The system could not open release notes',
              retryable: true,
              correlationId: 'release-notes-launch',
            ),
          ),
        );
      }
    } finally {
      if (ref.mounted) {
        state = AsyncData(state.requireValue.copyWith(opening: false));
      }
    }
  }
}
