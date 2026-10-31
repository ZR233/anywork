import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../domain/models/timeline_commands.dart';

part 'timeline_view_state.freezed.dart';

/// Presentation metadata only. Loaded content belongs to the Flyer controller.
@freezed
abstract class TimelineSessionViewState with _$TimelineSessionViewState {
  const factory TimelineSessionViewState({
    required String threadId,
    required int generation,
    required TimelineDisplayMode mode,
    required TimelineConnectionPhase connection,
    Object? connectionError,
    String? olderCursor,
    @Default(false) bool hasOlder,
    @Default(false) bool isLoadingOlder,
    Object? olderError,
    @Default(false) bool hasNewOutput,
  }) = _TimelineSessionViewState;
}
