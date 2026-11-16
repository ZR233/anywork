import 'package:anywork_client/lifecycle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_graph.dart';

/// Binds one provider's demand to the application's retained UI resources.
///
/// Disposal synchronously requests retirement; the scope owns the asynchronous
/// cleanup and retains failures for application shutdown or explicit retry.
T useClientResource<T extends ClientLease>(
  Ref ref,
  T Function() acquire, {
  required String owner,
}) {
  final scope = ref.watch(appGraphProvider).uiResources.child(owner);
  ref.onDispose(scope.requestClose);
  return scope.acquireLease(owner, acquire);
}
