import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

final clientBootstrapProvider = Provider.autoDispose<StudioBootstrapState>((
  ref,
) {
  final source = ref.read(anyworkClientProvider).bootstrapState;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
});
