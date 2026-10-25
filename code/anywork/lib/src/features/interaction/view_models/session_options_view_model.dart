import 'dart:async';

import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../app/app_bindings.dart';
import '../state/session_options_state.dart';

part 'session_options_view_model.g.dart';

// A disposed observer must not retain a VM until an unbounded SDK observation
// finishes. The loser remains handled and the original Repository owns join.
Future<CommandResult<T>?> _observeOptionsResult<T>(
  Future<CommandResult<T>> result,
  Future<void> disposed,
) => Future.any<CommandResult<T>?>([
  result,
  disposed.then<CommandResult<T>?>((_) => null),
]);

/// Presentation for an explicit draft/default edit, not a configuration store.
@riverpod
class SessionOptionsViewModel extends _$SessionOptionsViewModel {
  Observation? _observation;
  Object _lifetime = Object();
  late Completer<void> _disposed;
  ModelSelection? _threadRoute;

  /// A rejected intent survives canonical updates until a deliberate new
  /// choice/retry. It is never used as the selector's displayed canonical route.
  ModelSelection? get attemptedThreadRoute => _threadRoute;
  bool get canRetryThreadRoute {
    final view = state.value;
    return _threadRoute != null &&
        view != null &&
        !view.pending &&
        view.error?.retryable == true &&
        (view.operation == null ||
            view.operation?.failurePhase == OperationFailurePhase.rejected);
  }

  @override
  FutureOr<SessionOptionsState> build(String projectId) {
    _lifetime = Object();
    final disposed = _disposed = Completer<void>();
    ref.onDispose(() {
      if (!disposed.isCompleted) disposed.complete();
      final observation = _observation;
      _observation = null;
      observation?.cancel();
    });
    return const SessionOptionsState();
  }

  void explain(String? message) {
    state = AsyncData(state.requireValue.copyWith(explanation: message));
  }

  // Null remains a real follow-default intent until D1 freezes submission.
  // Disposing this VM never discards the original project draft.
  void chooseDelegationMode(DelegationMode? mode) {
    _editDraft(
      () => ref
          .read(draftsRepositoryProvider)
          .start(projectId)
          .setDelegationMode(mode),
    );
  }

  void chooseDelegationPreference(DelegationPreference? preference) {
    _editDraft(
      () => ref
          .read(draftsRepositoryProvider)
          .start(projectId)
          .setDelegationPreference(preference),
    );
  }

  void _editDraft(void Function() edit) {
    if (!ref.mounted) return;
    try {
      edit();
      if (ref.mounted) {
        state = AsyncData(state.requireValue.copyWith(error: null));
      }
    } on StudioFailure catch (error) {
      if (ref.mounted) {
        state = AsyncData(state.requireValue.copyWith(error: error));
      }
    }
  }

  Future<void> saveDefaultMode(DelegationMode mode) =>
      _write(SettingsFieldUpdate.delegationMode(value: mode));

  Future<void> saveDefaultPreference(DelegationPreference preference) =>
      _write(SettingsFieldUpdate.delegationPreference(value: preference));

  Future<void> chooseThreadModel({
    required String accountId,
    required String modelId,
    required ThreadModelRoute current,
    required OperationTicket<ThreadModelRouteCommandReply> Function(
      ModelSelection,
    )
    write,
  }) {
    // None asks native to apply this model's real default effort. Never choose
    // the first local candidate or normalize policy in a Widget.
    final effort = accountId == current.accountId && modelId == current.modelId
        ? current.effort
        : null;
    return _writeThreadRoute(
      ModelSelection(
        model: AccountModelKey(accountId: accountId, modelId: modelId),
        effort: effort,
      ),
      write,
    );
  }

  Future<void> chooseThreadEffort({
    required String effort,
    required ThreadModelRoute current,
    required OperationTicket<ThreadModelRouteCommandReply> Function(
      ModelSelection,
    )
    write,
  }) => _writeThreadRoute(
    ModelSelection(
      model: AccountModelKey(
        accountId: current.accountId,
        modelId: current.modelId,
      ),
      effort: effort,
    ),
    write,
  );

  Future<void> retryThreadRoute(
    OperationTicket<ThreadModelRouteCommandReply> Function(ModelSelection)
    write,
  ) {
    final selection = _threadRoute;
    if (!canRetryThreadRoute || selection == null) return Future<void>.value();
    // The Smart seam supplies a newly captured writer: same desired route,
    // current original source and newly frozen CAS versions, only on this tap.
    return _writeThreadRoute(selection, write);
  }

  Future<void> _writeThreadRoute(
    ModelSelection selection,
    OperationTicket<ThreadModelRouteCommandReply> Function(ModelSelection)
    write,
  ) {
    if (!ref.mounted || !state.hasValue || state.requireValue.pending) {
      return Future<void>.value();
    }
    _threadRoute = selection;
    return _perform(() => write(selection));
  }

  Future<void> _write(SettingsFieldUpdate update) => _perform(
    () => ref.read(configurationRepositoryProvider).applyField(update),
  );

  Future<void> _perform<T>(OperationTicket<T> Function() command) async {
    if (!ref.mounted || state.requireValue.pending) return;
    final lifetime = _lifetime;
    final disposed = _disposed.future;
    final intent = state.requireValue.intent + 1;
    state = AsyncData(
      state.requireValue.copyWith(
        intent: intent,
        waiting: true,
        operation: null,
        error: null,
      ),
    );
    try {
      _observation?.cancel();
      _observation = null;
      final ticket = command();
      final watched = ticket.state.watchLatest((operation) {
        if (_current(intent, lifetime)) {
          state = AsyncData(state.requireValue.copyWith(operation: operation));
        }
      });
      if (!_current(intent, lifetime)) {
        watched.observation.cancel();
        return;
      }
      _observation = watched.observation;
      state = AsyncData(state.requireValue.copyWith(operation: watched.value));
      final result = await _observeOptionsResult(ticket.result, disposed);
      if (result == null || !_current(intent, lifetime)) return;
      final error = switch (result) {
        RejectedCommandResult<T>(:final error) ||
        UnknownOutcomeCommandResult<T>(:final error) ||
        SyncFailedCommandResult<T>(:final error) ||
        AcknowledgedSyncFailedCommandResult<T>(:final error) => error,
        CommittedCommandResult<T>() || AcknowledgedCommandResult<T>() => null,
      };
      state = AsyncData(state.requireValue.copyWith(error: error));
      // Neither the requested default/route nor the reply is written into a
      // display mirror. The original canonical feeds alone update selectors.
    } on StudioFailure catch (error) {
      if (_current(intent, lifetime)) {
        state = AsyncData(state.requireValue.copyWith(error: error));
      }
    } finally {
      if (_current(intent, lifetime)) {
        state = AsyncData(state.requireValue.copyWith(waiting: false));
      }
    }
  }

  bool _current(int intent, Object lifetime) =>
      ref.mounted &&
      identical(_lifetime, lifetime) &&
      state.hasValue &&
      state.requireValue.intent == intent;
}
