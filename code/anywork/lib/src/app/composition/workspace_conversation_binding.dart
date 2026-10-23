import 'package:anywork_client/conversation_ports.dart' show ConversationDemand;
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';

/// Mechanical composition-only forwarding of D3's unique selection to D1.
/// Owns its observer, not a selected ID, Session or activation-error mirror.
final class WorkspaceConversationBinding {
  WorkspaceConversationBinding({required WorkspaceRepository workspace, required ConversationDemand demand})
      : _workspace = workspace, _demand = demand;

  final WorkspaceRepository _workspace;
  final ConversationDemand _demand;
  Observation? _observation;
  bool _started = false;
  bool _sealed = false;

  void start() {
    if (_sealed) throw const StudioFailure(code: StudioFailureCode.cancelled,
      message: 'Conversation selection binding is sealed.', retryable: false, correlationId: '');
    if (_started) return;
    _started = true;
    try {
      final watched = _workspace.state.watchLatest(_forward);
      _observation = watched.observation;
      if (_sealed) {
        watched.observation.cancel();
        _observation = null;
        return;
      }
      // No await between registration and current demand. Never keep a second
      // copy of selection or substitute an ID after an asynchronous callback.
      _forward(_workspace.state.value);
    } catch (error, stack) {
      _observation?.cancel();
      _observation = null;
      _started = false;
      Error.throwWithStackTrace(error, stack);
    }
  }

  void _forward(WorkspaceState value) {
    if (_sealed || value.sealed) return;
    final selection = value.selection;
    _demand.select(threadId: selection.threadId, needsOpen: selection.needsOpen,
      selectionGeneration: value.selectionGeneration);
  }

  void seal() {
    _sealed = true;
    _observation?.cancel();
    _observation = null;
  }

  Future<CloseReport> close({DateTime? deadline}) {
    seal();
    return Future.value(CloseReport(unresolved: const []));
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) => close(deadline: deadline);
}
