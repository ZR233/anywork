import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/thread_directory_store.dart';

final conversationBackendViewModelProvider = Provider.autoDispose
    .family<AgentBackendView?, String>((ref, threadId) {
      return ref.watch(
        threadMetadataStoreProvider(threadId)
            .select((state) => state.frame?.row?.backend),
      );
    });
