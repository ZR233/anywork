import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../app/app_graph.dart';
import '../../presentation/providers/observe_client.dart';
import '../../presentation/view_models/timeline_session_owner.dart';

export '../../presentation/view_models/timeline_session_owner.dart'
    show TimelineSessionOwner, TimelineSessionViewState, TimelineDisplayLease;

part 'timeline_session_view.g.dart';

/// The application graph owns the projection and session leases. This provider
/// exposes that owner without opening or retiring a business resource.
final timelineSessionOwnerProvider = Provider<TimelineSessionOwner>(
  (ref) => ref.read(appGraphProvider).timeline,
);

@riverpod
TimelineSessionViewState? timelineDisplayState(Ref ref) {
  final owner = ref.read(timelineSessionOwnerProvider);
  return observeClient(ref, owner.source, (_) {
    if (ref.mounted) ref.invalidateSelf();
  });
}
