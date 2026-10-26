import 'package:anywork_client/lsp.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../../view_models/collection_values.dart';
import '../state/lsp_view_state.dart';

part 'lsp_view_model.g.dart';

@riverpod
class LspViewModel extends _$LspViewModel {
  late LspRepository _repository;
  late String _projectId;
  final _observations = <(LspActionKind, String?), Observation>{};
  int _lifetime = 0;
  bool _alive = true;
  @override
  Future<LspActionsViewState> build(String projectId) async {
    _alive = true;
    _lifetime++;
    _projectId = projectId;
    _repository = ref.watch(lspRepositoryProvider);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      for (final observation in _observations.values) {
        observation.cancel();
      }
      _observations.clear(); // Commands and global LSP lifecycle stay in Repo.
    });
    return LspActionsViewState(projectId: projectId);
  }

  LspServer? _server(String id) => currentCollectionRow(
    _repository.state.value.servers,
    _repository.state.value.projection.stamp?.origin,
    (server) => server.id == id,
  )?.value;
  Future<void> probe() {
    final repository = _repository;
    final projectId = _projectId;
    return _run(LspActionKind.probe, null, () => repository.probe(projectId));
  }

  Future<void> repair(String id) async {
    final repository = _repository;
    final projectId = _projectId;
    final nativeState = _server(id)?.state;
    if (nativeState is UnavailableLspServerState &&
        nativeState.error.code == 'lspComponentMissing') {
      await _run(
        LspActionKind.repair,
        id,
        () => repository.repair(projectId, id),
      );
    }
  }

  Future<void> resetServer(String id) async {
    final repository = _repository;
    final projectId = _projectId;
    if (_server(id) != null) {
      await _run(
        LspActionKind.resetServer,
        id,
        () => repository.resetServer(projectId, id),
      );
    }
  }

  Future<void> resetWorkspace() {
    final repository = _repository;
    final projectId = _projectId;
    return _run(
      LspActionKind.resetWorkspace,
      null,
      () => repository.resetWorkspace(projectId),
    );
  }

  Future<void> _run(
    LspActionKind kind,
    String? serverId,
    OperationTicket<LspReadTarget> Function() admit,
  ) async {
    if (!_alive || state.asData == null) return;
    final key = (kind, serverId);
    if (state.requireValue.actions[key]?.preventsResubmission ?? false) return;
    if ((kind == LspActionKind.repair || kind == LspActionKind.resetServer) &&
        [LspActionKind.repair, LspActionKind.resetServer].any(
          (other) =>
              state
                  .requireValue
                  .actions[(other, serverId)]
                  ?.preventsResubmission ??
              false,
        )) {
      return;
    }
    final intent = state.requireValue.latestIntent + 1;
    final lifetime = _lifetime;
    final projectId = _projectId;
    state = AsyncData(
      state.requireValue.copyWith(
        latestIntent: intent,
        actions: {
          ...state.requireValue.actions,
          key: SettingsAction(intent: intent, pending: true),
        },
      ),
    );
    bool owns() =>
        _alive &&
        lifetime == _lifetime &&
        _projectId == projectId &&
        state.asData?.value.actions[key]?.intent == intent;
    void update(SettingsAction action) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            actions: {...state.requireValue.actions, key: action},
          ),
        );
      }
    }

    if (!owns()) return;
    OperationTicket<LspReadTarget> ticket;
    try {
      ticket = admit();
    } on StudioFailure catch (error) {
      update(
        SettingsAction(
          intent: intent,
          outcome: SettingsActionOutcome.rejected,
          error: error,
        ),
      );
      return;
    }
    var action = SettingsAction(
      intent: intent,
      pending: true,
      operation: ticket.state.value,
    );
    StudioFailure? observationError;
    if (owns()) {
      _observations.remove(key)?.cancel();
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (owns()) {
            action = action.copyWith(operation: operation);
            update(action);
          }
        });
        if (owns()) {
          _observations[key] = watch.observation;
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
      action = action.copyWith(observationError: observationError);
      update(action);
    }
    final result = await ticket.result;
    action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    update(action);
  }
}
