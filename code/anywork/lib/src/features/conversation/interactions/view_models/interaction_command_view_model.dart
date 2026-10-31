import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../state/interaction_payload.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/observe_client.dart';

part 'interaction_command_view_model.g.dart';

final class InteractionActionStatus {
  const InteractionActionStatus({
    this.pending = false,
    this.accepted = false,
    this.blocked = false,
    this.error,
  });

  final bool pending;
  final bool accepted;
  final bool blocked;
  final StudioFailure? error;
}

final class InteractionCommandViewState {
  InteractionCommandViewState([
    Map<String, InteractionActionStatus>? actions,
    this.childNotice,
  ]) : actions = Map.unmodifiable(actions ?? const {});

  final Map<String, InteractionActionStatus> actions;
  final ChildDecisionNotice? childNotice;

  InteractionActionStatus? status(String interactionId) =>
      actions[interactionId];
}

/// SDK status is the durable fact; this notifier only derives a presentation projection
/// and holds a synchronous gate while an SDK call is being entered.
@riverpod
class InteractionCommandViewModel extends _$InteractionCommandViewModel {
  final Map<String, Object> _dispatching = {};
  Object? _lifecycle;
  _ChildDecisionIntent? _childDecision;

  @override
  FutureOr<InteractionCommandViewState> build(String hostThreadId) {
    final lifecycle = Object();
    _lifecycle = lifecycle;
    ref.onDispose(() {
      if (identical(_lifecycle, lifecycle)) {
        _lifecycle = null;
      }
    });
    final client = ref.read(anyworkClientProvider);
    final session = client.conversations.session(hostThreadId);
    final commandState = _observe(lifecycle, client.threadCommands.source);
    final sessionState = _observe(lifecycle, session.source);
    // 只借用 Client 主题需求安装的宿主镜像；不存在时没有可投影的 child 事实。
    final childStore = client.existingChildInteractions(hostThreadId);
    final childClock = childStore == null
        ? null
        : _observe(lifecycle, childStore.source);
    final intent = _childDecision;
    if (intent != null && intent.hostThreadId != hostThreadId) {
      _childDecision = null;
    }
    ChildDecisionNotice? childNotice;
    final current = _childDecision;
    final operation = current?.operation;
    if (current != null && operation != null) {
      // Registration and the initial value are one synchronous observation, so
      // confirmation that arrived before the command future returned is retained.
      final operationState = _observe(lifecycle, operation.state);
      if (operationState.receipt != null &&
          operationState.observed &&
          operationState.failurePhase == null) {
        childNotice = ChildDecisionNotice(
          interactionId: current.interactionId,
          kind: current.kind,
        );
      }
    }

    final commands = commandState.commands;
    final command = commands['interaction:$hostThreadId'];
    final actions = <String, InteractionActionStatus>{};

    for (final interaction in sessionState.interactions) {
      final matches = command?.target.label == interaction.id;
      actions[interaction.id] = _project(command, matches: matches);
    }
    final childItems = childClock?.canonical;
    if (childItems != null &&
        childItems.loaded &&
        childItems.value?.hostThreadId == hostThreadId) {
      for (final child in childItems.value!.items) {
        final matches = command?.target.label == child.interactionId;
        actions[child.interactionId] = _project(command, matches: matches);
      }
    }
    return InteractionCommandViewState(actions, childNotice);
  }

  T _observe<T>(Object lifecycle, ValueObservation<T> source) {
    return observeClient(ref, source, (_) {
      if (ref.mounted && identical(_lifecycle, lifecycle)) {
        ref.invalidateSelf();
      }
    });
  }

  InteractionActionStatus _project(
    CommandStatus? command, {
    required bool matches,
  }) {
    if (command == null) return const InteractionActionStatus();
    final occupied = command.isPending || command.accepted;
    return InteractionActionStatus(
      pending: matches && command.isPending && !command.accepted,
      accepted: matches && command.accepted,
      blocked: !matches && occupied,
      error: matches && command.phase == CommandPhase.failed
          ? command.error
          : null,
    );
  }

  Future<void> resolveActive(
    String threadId,
    String interactionId,
    int expectedRevision,
    InteractionResolutionCommand resolution,
  ) async {
    final client = ref.read(anyworkClientProvider);
    final key = 'interaction:$threadId';
    final lifecycle = _lifecycle;
    if (lifecycle == null || !ref.mounted) return;
    final gate = _beginDispatch(key, lifecycle);
    if (gate == null) return;
    try {
      if (!ref.mounted || !identical(_lifecycle, lifecycle)) return;
      final session = client.conversations.session(threadId).state;
      if (!session.hasSnapshot ||
          !pendingInteractionIsActive(session.interactions, interactionId)) {
        return;
      }
      final current = activePendingInteraction(session.interactions);
      if (current == null ||
          current.id != interactionId ||
          (expectedRevision != 0 && current.revision != expectedRevision)) {
        return;
      }
      await client.threadCommands.resolveActiveInteraction(
        threadId,
        interactionId,
        resolution,
      );
    } finally {
      _releaseGate(key, gate);
    }
  }

  Future<void> resolveChild(
    String hostThreadId,
    ChildInteractionSummary captured,
    InteractionResolutionCommand resolution,
  ) async {
    final client = ref.read(anyworkClientProvider);
    final key = 'interaction:$hostThreadId';
    final lifecycle = _lifecycle;
    if (lifecycle == null || !ref.mounted) return;
    final gate = _beginDispatch(key, lifecycle);
    if (gate == null) return;
    try {
      if (!ref.mounted || !identical(_lifecycle, lifecycle)) return;
      final clock = client
          .existingChildInteractions(hostThreadId)
          ?.state
          .canonical;
      if (clock == null || !clock.loaded || clock.value == null) return;
      final current = clock.value!.items
          .where(
            (item) =>
                item.childThreadId == captured.childThreadId &&
                item.interactionId == captured.interactionId,
          )
          .firstOrNull;
      if (current == null ||
          current.kind != captured.kind ||
          current.revision != captured.revision ||
          current.interaction.isPlanConfirmation) {
        return;
      }
      final intent = _ChildDecisionIntent(
        hostThreadId: hostThreadId,
        interactionId: captured.interactionId,
        kind: captured.kind,
      );
      // Replace the previous UI intent before SDK admission or any reentrant
      // command notification. This object is also the dispatch identity token.
      _childDecision = intent;
      ref.invalidateSelf();
      final operation = await client.threadCommands.resolveChildInteraction(
        hostThreadId,
        captured,
        resolution,
      );
      if (!ref.mounted || !identical(_childDecision, intent)) {
        return;
      }
      intent.operation = operation;
      ref.invalidateSelf();
    } finally {
      _releaseGate(key, gate);
    }
  }

  Object? _beginDispatch(String key, Object lifecycle) {
    if (!ref.mounted || !identical(_lifecycle, lifecycle)) return null;
    if (_dispatching.containsKey(key)) return null;
    final gate = Object();
    _dispatching[key] = gate;
    final client = ref.read(anyworkClientProvider);
    final status = client.threadCommands.state.commands[key];
    if (status != null && (status.isPending || status.accepted)) {
      _releaseGate(key, gate);
      return null;
    }
    return gate;
  }

  void _releaseGate(String key, Object gate) {
    if (identical(_dispatching[key], gate)) _dispatching.remove(key);
  }
}

/// At most one presentation intent and its exact SDK observation resource.
/// SDK command ownership is independent of this notifier and its observers.
final class _ChildDecisionIntent {
  _ChildDecisionIntent({
    required this.hostThreadId,
    required this.interactionId,
    required this.kind,
  });

  final String hostThreadId;
  final String interactionId;
  final InteractionKind kind;
  OperationHandle? operation;
}
