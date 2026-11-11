import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';

part 'acp_session_view_model.g.dart';

/// Admits through the application's exact directory identity. Re-entering a
/// page borrows the existing Client owner; Ref never closes business membership.
@riverpod
Future<AcpConversationSession> acpConversationOwner(Ref ref, String threadId) {
  final client = ref.watch(anyworkClientProvider);
  final existing = client.acpSessions.conversationForThread(threadId);
  return existing == null
      ? client.openAcpConversation(threadId)
      : Future.value(existing);
}

/// Shared single-subscription observation of [AcpConversationState] for one
/// [threadId]. Downstream component ViewModels use `.select(...)` so streaming
/// message chunks only notify the active item rather than configuration, plan,
/// or composer controls.
@riverpod
AsyncValue<AcpConversationState> acpConversationState(
  Ref ref,
  String threadId,
) {
  final owner = ref.watch(acpConversationOwnerProvider(threadId));
  return owner.whenData(
    (session) =>
        observeClient(ref, session.source, (_) => ref.invalidateSelf()),
  );
}

String formatAcpError(Object error) {
  if (error is AcpBusinessFailureView) {
    final trimmed = error.message.trim();
    return trimmed.isEmpty ? error.toString() : trimmed;
  }
  if (error is StudioFailure) {
    final trimmed = error.message.trim();
    return trimmed.isEmpty ? error.toString() : trimmed;
  }
  return error.toString();
}

Future<void> coordinateAcpSessionCommand(
  AnyworkClient client,
  String threadId,
  Future<void> Function(AcpConversationSession owner) operation,
) async {
  final draft = client.drafts.composer(threadId);
  try {
    final owner = client.acpSessions.conversationForThread(threadId);
    if (owner == null) {
      throw StateError('ACP 会话尚未打开');
    }
    await operation(owner);
  } catch (error) {
    draft.reportFailure(error);
  }
}
