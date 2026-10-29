import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_graph.dart';
import '../../../../presentation/providers/observe_client.dart';
import '../../../../presentation/view_models/timeline_session_owner.dart';

part 'timeline_view_model.g.dart';

final timelineSessionOwnerProvider = Provider<TimelineSessionOwner>(
  (ref) => ref.read(appGraphProvider).timeline,
);

@riverpod
class TimelineViewModel extends _$TimelineViewModel {
  @override
  FutureOr<TimelineSessionViewState?> build(String threadId) {
    final owner = ref.read(timelineSessionOwnerProvider);
    TimelineSessionViewState? matching(TimelineSessionViewState? value) =>
        value?.threadId == threadId ? value : null;
    final initial = observeClient(ref, owner.source, (value) {
      if (ref.mounted) state = AsyncData(matching(value));
    });
    return matching(initial);
  }
}
