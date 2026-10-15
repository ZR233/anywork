import 'package:anywork_client/studio_client.dart' show UpdaterStateSnapshot;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

part 'studio_update_controller.g.dart';

const _compiledStudioVersion = String.fromEnvironment(
  'ANYWORK_VERSION',
  defaultValue: '1.0.0',
);

final studioVersionProvider = Provider<String>((ref) => _compiledStudioVersion);

/// Update startup and installation survive observer and route lifetimes.
@riverpod
UpdaterStateSnapshot studioUpdateController(Ref ref) {
  final owner = ref.read(anyworkClientProvider).updates;
  observeClient(ref, owner.source, (_) => ref.invalidateSelf());
  return owner.state;
}
