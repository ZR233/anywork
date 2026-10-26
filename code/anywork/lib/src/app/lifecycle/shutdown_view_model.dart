import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../app_bindings.dart';
import 'exit_state.dart';

part 'shutdown_view_model.g.dart';

/// Presentation only; the coordinator owns all deadlines, futures and cleanup.
@Riverpod(keepAlive: true)
class ShutdownViewModel extends _$ShutdownViewModel {
  @override
  FutureOr<ApplicationExitState> build() {
    final source = ref.watch(applicationExitCoordinatorProvider).state;
    final watched = source.watchLatest((value) => state = AsyncData(value));
    ref.onDispose(watched.observation.cancel);
    return watched.value;
  }
}
