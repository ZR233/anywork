import 'package:anywork_client/studio_client.dart'
    show CanonicalClockState, BotsStateSnapshot, BotsQueryState, BotsSendState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show CanonicalClockState;

part 'bots_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
CanonicalClockState<BotsStateSnapshot> botsStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).bots.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}

@riverpod
BotsQueryState botsQueryStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).botsQueries.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}

@riverpod
BotsSendState botsSendStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).botsSends.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
