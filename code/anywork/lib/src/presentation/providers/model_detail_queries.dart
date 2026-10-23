import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

/// Display-only observation. The application Client owns queries and joins them.
final modelDetailQueriesProvider =
    Provider.autoDispose<Map<DelegationModelKey, ModelDetailQuery>>((ref) {
      final source = ref.read(anyworkClientProvider).modelDetailQueries.source;
      return observeClient(ref, source, (_) => ref.invalidateSelf());
    }, name: 'modelDetailQueriesProvider');
