import 'package:anywork_client/studio_client.dart' show SettingsStoreState;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/studio_client.dart' show SettingsStoreState;

part 'settings_store.g.dart';

/// Riverpod owns this display observation; the Client owns the resource.
@riverpod
SettingsStoreState settingsStore(Ref ref) {
  final source = ref.read(anyworkClientProvider).settings.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
