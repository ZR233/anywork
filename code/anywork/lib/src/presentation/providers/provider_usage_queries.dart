import 'package:anywork_client/studio_client.dart' show ProviderUsageQueryState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client_provider.dart';
import 'observe_client.dart';

/// Riverpod owns this display observation; the Client owns in-flight queries.
final providerUsageQueriesProvider =
    Provider.autoDispose<ProviderUsageQueryState>((ref) {
      final source = ref
          .read(anyworkClientProvider)
          .providerUsageQueries
          .source;
      return observeClient(ref, source, (_) => ref.invalidateSelf());
    }, name: 'providerUsageQueriesProvider');
