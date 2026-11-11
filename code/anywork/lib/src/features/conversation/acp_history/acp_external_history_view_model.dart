import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../acp/view_models/acp_conversation_view_model.dart'
    show acpConversationOwnerProvider, acpConversationViewModelProvider;
import '../../../presentation/providers/client_provider.dart';

enum AcpExternalHistoryAvailability {
  loading,
  noOwner,
  unknownCapability,
  unsupported,
  notReady,
  available,
}

typedef AcpExternalHistoryAvailabilityState = ({
  AcpExternalHistoryAvailability status,
  AcpConversationSession? owner,
  bool canLoad,
  bool canResume,
});

/// Reuses the ACP feature's owner and observes only fields needed by the button.
/// The record selection prevents message/content changes from rebuilding it.
final acpExternalHistoryAvailabilityProvider = Provider.autoDispose
    .family<AcpExternalHistoryAvailabilityState, String>((ref, threadId) {
      final ownerState = ref.watch(acpConversationOwnerProvider(threadId));
      final owner = ownerState.asData?.value;
      if (owner != null) {
        ref.watch(
          acpExternalHistoryViewModelProvider((
            threadId: threadId,
            owner: owner,
          )).select((history) => history.openOutcomes),
        );
      }
      return ref.watch(
        acpConversationViewModelProvider(threadId).select((conversation) {
          final state = conversation.asData?.value;
          final capabilities = state?.capabilities;
          final status = ownerState.isLoading || conversation.isLoading
              ? AcpExternalHistoryAvailability.loading
              : owner == null
              ? AcpExternalHistoryAvailability.noOwner
              : capabilities == null
              ? AcpExternalHistoryAvailability.unknownCapability
              : !capabilities.listSessions
              ? AcpExternalHistoryAvailability.unsupported
              : !state!.ready || state.disconnected || state.observationEnded
              ? AcpExternalHistoryAvailability.notReady
              : AcpExternalHistoryAvailability.available;
          return (
            status: status,
            owner: owner,
            canLoad: capabilities?.loadSession == true,
            canResume: capabilities?.resumeSession == true,
          );
        }),
      );
    });

enum AcpExternalOpenOutcome { opening, opened, unknown }

final class AcpExternalHistoryState {
  const AcpExternalHistoryState({
    this.sessions = const [],
    this.nextCursor,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.openOutcomes = const {},
    this.openErrors = const {},
  });

  final List<AcpSessionInfoView> sessions;
  final String? nextCursor;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final Map<String, AcpExternalOpenOutcome> openOutcomes;
  final Map<String, Object> openErrors;

  AcpExternalHistoryState copyWith({
    List<AcpSessionInfoView>? sessions,
    String? nextCursor,
    bool clearCursor = false,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
    Map<String, AcpExternalOpenOutcome>? openOutcomes,
    Map<String, Object>? openErrors,
  }) => AcpExternalHistoryState(
    sessions: sessions ?? this.sessions,
    nextCursor: clearCursor ? null : nextCursor ?? this.nextCursor,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : error ?? this.error,
    openOutcomes: openOutcomes ?? this.openOutcomes,
    openErrors: openErrors ?? this.openErrors,
  );
}

typedef AcpExternalHistoryIdentity = ({
  String threadId,
  AcpConversationSession owner,
});

typedef AcpExternalList = Future<AcpListSessionsResponseView> Function(
  String threadId, {
  String? cursor,
});
typedef AcpExternalOpen = Future<AcpConversationSession> Function(
  String sourceThreadId,
  AcpRemoteSessionId remoteSessionId, {
  bool resume,
  String? cwd,
});

/// Thin test seam; production delegates directly to the Client's narrow APIs.
final class AcpExternalHistoryOperations {
  const AcpExternalHistoryOperations({required this.list, required this.open});

  final AcpExternalList list;
  final AcpExternalOpen open;
}

final acpExternalHistoryOperationsProvider =
    Provider<AcpExternalHistoryOperations>((ref) {
      final client = ref.watch(anyworkClientProvider);
      return AcpExternalHistoryOperations(
        list: client.listAcpConversations,
        open: client.openExternalAcpConversation,
      );
    });

final acpExternalHistoryViewModelProvider = NotifierProvider.autoDispose
    .family<
      AcpExternalHistoryViewModel,
      AcpExternalHistoryState,
      AcpExternalHistoryIdentity
    >(AcpExternalHistoryViewModel.new);

final class AcpExternalHistoryViewModel
    extends Notifier<AcpExternalHistoryState> {
  AcpExternalHistoryViewModel(this.identity);

  final AcpExternalHistoryIdentity identity;
  late AnyworkClient _client;
  late AcpExternalHistoryOperations _operations;
  late final String _threadId = identity.threadId;
  late final AcpConversationSession _owner = identity.owner;

  @override
  AcpExternalHistoryState build() {
    _client = ref.watch(anyworkClientProvider);
    _operations = ref.watch(acpExternalHistoryOperationsProvider);
    return const AcpExternalHistoryState();
  }

  bool get _isCurrentOwner =>
      identical(_client.acpSessions.conversationForThread(_threadId), _owner);

  Future<void> refresh() => _list(cursor: null, replace: true);

  Future<void> loadMore() {
    final cursor = state.nextCursor;
    if (cursor == null) return Future.value();
    return _list(cursor: cursor, replace: false);
  }

  Future<void> _list({required String? cursor, required bool replace}) async {
    if (state.loading || state.loadingMore || !_isCurrentOwner) return;
    state = state.copyWith(
      loading: replace,
      loadingMore: !replace,
      clearError: true,
    );
    try {
      final response = await _operations.list(_threadId, cursor: cursor);
      if (!ref.mounted || !_isCurrentOwner) return;
      state = state.copyWith(
        sessions: replace
            ? response.sessions
            : [...state.sessions, ...response.sessions],
        nextCursor: response.nextCursor,
        clearCursor: response.nextCursor == null,
        loading: false,
        loadingMore: false,
        clearError: true,
      );
    } catch (error) {
      if (!ref.mounted || !_isCurrentOwner) return;
      state = state.copyWith(loading: false, loadingMore: false, error: error);
    }
  }

  Future<void> open(AcpSessionInfoView session, {required bool resume}) async {
    final id = session.sessionId.value;
    if (!_isCurrentOwner ||
        state.openOutcomes.containsKey(id) ||
        state.openOutcomes.values.contains(AcpExternalOpenOutcome.opening) ||
        state.loading ||
        state.loadingMore) {
      return;
    }
    final capabilities = _owner.state.capabilities;
    if (!_owner.state.ready ||
        (resume
            ? capabilities?.resumeSession != true
            : capabilities?.loadSession != true)) {
      return;
    }
    state = state.copyWith(
      openOutcomes: {...state.openOutcomes, id: AcpExternalOpenOutcome.opening},
    );
    try {
      await _operations.open(
        _threadId,
        session.sessionId,
        resume: resume,
        cwd: session.cwd,
      );
      if (!ref.mounted || !_isCurrentOwner) return;
      state = state.copyWith(
        openOutcomes: {
          ...state.openOutcomes,
          id: AcpExternalOpenOutcome.opened,
        },
      );
    } catch (error) {
      if (!ref.mounted || !_isCurrentOwner) return;
      state = state.copyWith(
        openOutcomes: {
          ...state.openOutcomes,
          id: AcpExternalOpenOutcome.unknown,
        },
        openErrors: {...state.openErrors, id: error},
      );
    }
  }
}
