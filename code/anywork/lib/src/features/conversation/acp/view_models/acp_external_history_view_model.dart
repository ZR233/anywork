import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/client_provider.dart';
import '../state/acp_view_state.dart';
import 'acp_session_view_model.dart';

part 'acp_external_history_view_model.g.dart';

typedef AcpExternalListOperation = Future<AcpListSessionsResponseView> Function(
  String threadId, {
  String? cursor,
});

typedef AcpExternalOpenOperation = Future<AcpConversationSession> Function(
  String sourceThreadId,
  AcpRemoteSessionId remoteSessionId, {
  bool resume,
  String? cwd,
});

/// Narrow test seam; production delegates directly to the Client's ACP session
/// APIs without retaining a parallel cache.
final class AcpExternalHistoryOperations {
  const AcpExternalHistoryOperations({required this.list, required this.open});

  final AcpExternalListOperation list;
  final AcpExternalOpenOperation open;
}

@riverpod
AcpExternalHistoryOperations acpExternalHistoryOperations(Ref ref) {
  final client = ref.watch(anyworkClientProvider);
  return AcpExternalHistoryOperations(
    list: client.listAcpConversations,
    open: client.openExternalAcpConversation,
  );
}

/// Observes ONLY the fields required by the status-bar button so streaming
/// message chunks never rebuild the external-sessions trigger.
@riverpod
AcpExternalHistoryButtonState acpExternalHistoryButtonViewModel(
  Ref ref,
  String threadId,
) {
  final ownerState = ref.watch(acpConversationOwnerProvider(threadId));
  final owner = ownerState.asData?.value;
  final conversation = ref.watch(acpConversationStateProvider(threadId));
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
  return AcpExternalHistoryButtonState(
    status: status,
    canLoad: capabilities?.loadSession == true,
    canResume: capabilities?.resumeSession == true,
  );
}

/// Keyed strictly by `String threadId` so live `AcpConversationSession` owners
/// never cross widget constructor boundaries. Internally verifies that async
/// responses still match the current session owner of [threadId].
@riverpod
class AcpExternalHistoryViewModel extends _$AcpExternalHistoryViewModel {
  late AnyworkClient _client;
  late AcpExternalHistoryOperations _operations;
  AcpConversationSession? _trackedOwner;
  List<AcpSessionInfoView> _rawSessions = const [];
  String? _nextCursor;
  bool _loading = false;
  bool _loadingMore = false;
  String? _listError;
  Map<String, AcpExternalOpenOutcome> _openOutcomes = const {};
  Map<String, String> _openErrors = const {};
  void Function()? _closeUncertainKeepAlive;

  void _releaseKeepAlive() {
    final close = _closeUncertainKeepAlive;
    _closeUncertainKeepAlive = null;
    close?.call();
  }

  @override
  AcpExternalHistoryDialogState build(String threadId) {
    _client = ref.watch(anyworkClientProvider);
    _operations = ref.watch(acpExternalHistoryOperationsProvider);
    final owner = ref
        .watch(acpConversationOwnerProvider(threadId))
        .asData
        ?.value;
    if (!identical(owner, _trackedOwner)) {
      _releaseKeepAlive();
      _trackedOwner = owner;
      _rawSessions = const [];
      _nextCursor = null;
      _loading = false;
      _loadingMore = false;
      _listError = null;
      _openOutcomes = const {};
      _openErrors = const {};
    }
    final button = ref.watch(
      acpExternalHistoryButtonViewModelProvider(threadId),
    );
    return _projectState(button);
  }

  bool _matchesTrackedOwner(AcpConversationSession? expected) =>
      expected != null &&
      identical(_client.acpSessions.conversationForThread(threadId), expected);

  AcpExternalHistoryDialogState _projectState(
    AcpExternalHistoryButtonState button,
  ) {
    final anyOpening = _openOutcomes.values.contains(
      AcpExternalOpenOutcome.opening,
    );
    return AcpExternalHistoryDialogState(
      availability: button.status,
      canLoad: button.canLoad,
      canResume: button.canResume,
      sessions: [
        for (final session in _rawSessions)
          AcpExternalSessionRowPresentation(
            sessionId: session.sessionId.value,
            title: session.title,
            cwd: session.cwd,
            updatedAt: session.updatedAt,
            outcome: _openOutcomes[session.sessionId.value],
            errorMessage: _openErrors[session.sessionId.value],
          ),
      ],
      nextCursor: _nextCursor,
      loading: _loading,
      loadingMore: _loadingMore,
      anyOpening: anyOpening,
      listError: _listError,
    );
  }

  void _emitCurrent() {
    if (!ref.mounted) return;
    state = _projectState(
      ref.read(acpExternalHistoryButtonViewModelProvider(threadId)),
    );
  }

  Future<void> refresh() => _list(cursor: null, replace: true);

  Future<void> loadMore() {
    final cursor = _nextCursor;
    if (cursor == null) return Future.value();
    return _list(cursor: cursor, replace: false);
  }

  Future<void> _list({required String? cursor, required bool replace}) async {
    final owner =
        _trackedOwner ?? _client.acpSessions.conversationForThread(threadId);
    if (_loading || _loadingMore || !_matchesTrackedOwner(owner)) return;
    _trackedOwner = owner;
    _loading = replace;
    _loadingMore = !replace;
    _listError = null;
    _emitCurrent();

    try {
      final response = await _operations.list(threadId, cursor: cursor);
      if (!ref.mounted || !_matchesTrackedOwner(owner)) return;
      _rawSessions = replace
          ? List.unmodifiable(response.sessions)
          : List.unmodifiable([..._rawSessions, ...response.sessions]);
      _nextCursor = response.nextCursor;
      _loading = false;
      _loadingMore = false;
      _listError = null;
      _emitCurrent();
    } catch (error) {
      if (!ref.mounted || !_matchesTrackedOwner(owner)) return;
      _loading = false;
      _loadingMore = false;
      _listError = formatAcpError(error);
      _emitCurrent();
    }
  }

  Future<bool> openSession(String sessionId, {required bool resume}) async {
    final owner =
        _trackedOwner ?? _client.acpSessions.conversationForThread(threadId);
    if (!_matchesTrackedOwner(owner) ||
        _openOutcomes.containsKey(sessionId) ||
        _openOutcomes.values.contains(AcpExternalOpenOutcome.opening) ||
        _loading ||
        _loadingMore) {
      return false;
    }
    final targetSession = _rawSessions
        .where((item) => item.sessionId.value == sessionId)
        .firstOrNull;
    if (targetSession == null) return false;

    final capabilities = owner!.state.capabilities;
    if (!owner.state.ready ||
        (resume
            ? capabilities?.resumeSession != true
            : capabilities?.loadSession != true)) {
      return false;
    }

    _openOutcomes = {
      ..._openOutcomes,
      sessionId: AcpExternalOpenOutcome.opening,
    };
    _emitCurrent();

    try {
      await _operations.open(
        threadId,
        targetSession.sessionId,
        resume: resume,
        cwd: targetSession.cwd,
      );
      if (!ref.mounted || !_matchesTrackedOwner(owner)) return false;
      _openOutcomes = {
        ..._openOutcomes,
        sessionId: AcpExternalOpenOutcome.opened,
      };
      _emitCurrent();
      return true;
    } catch (error) {
      if (!ref.mounted || !_matchesTrackedOwner(owner)) return false;
      _closeUncertainKeepAlive ??= ref.keepAlive().close;
      _openOutcomes = {
        ..._openOutcomes,
        sessionId: AcpExternalOpenOutcome.unknown,
      };
      _openErrors = {..._openErrors, sessionId: formatAcpError(error)};
      _emitCurrent();
      return false;
    }
  }
}
