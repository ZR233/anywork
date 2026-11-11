import 'package:anywork_client/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_directory_store.dart';

enum ConversationBackendKind { loading, native, acp, unresolved }

final conversationBackendViewModelProvider = Provider.autoDispose
    .family<ConversationBackendKind, String>((ref, threadId) {
      final metadata = ref.watch(
        threadMetadataStoreProvider(threadId).select(
          (state) => (
            backend: state.frame?.row?.backend,
            hasFrame: state.frame != null,
            isLoading: state.isLoading,
          ),
        ),
      );
      switch (metadata.backend) {
        case AcpAgentBackendView():
          return ConversationBackendKind.acp;
        case NativeAgentBackendView():
          return ConversationBackendKind.native;
        case null:
          break;
      }
      if (ref.watch(anyworkClientProvider).hasAcpConversation(threadId)) {
        return ConversationBackendKind.acp;
      }
      return metadata.isLoading && !metadata.hasFrame
          ? ConversationBackendKind.loading
          : ConversationBackendKind.unresolved;
    });
