import '../../../anywork_client.dart';
import '../../../models.dart';
import '../anywork_client.dart';
import '../thread_session_state.dart';

/// Input acceptance and Turn observation belong to their own input identity;
/// neither a Thread revision nor a receipt cursor is a durability proof.
///
/// 耐久性证据来自**内容**：只有同一 input 的权威 Turn 条目真的带上 `saved` 才算落盘。
/// 已加载正文不再属于 Thread 状态镜像，因此这里只按 input 身份保留一份极小的观测记录
/// （身份 + 保存/终态），不复制正文，也不遍历全部已加载历史。
Observation observeSubmittedInput({
  required AnyworkClient client,
  required OperationHandle operation,
  required SubmitPromptReceipt receipt,
}) {
  final stamp = ResourceStamp(
    resourceKey: 'input:${receipt.threadId}:${receipt.inputId}',
    ownerEpoch: receipt.threadId,
    revision: receipt.cursor,
  );
  // Keep the operation state alive while its separate effect/durability
  // observer remains attached, including after the observation barrier passes.
  final retainedOperation = operation.state.watch((_) {});
  ResourcePermit? permit;
  Observation? attached;
  late final _InputObservation observation;
  final observedTurns = <String, _ObservedInputTurn>{};

  StudioTurnStatus? _turnStatus(ThreadItemView? item) {
    if (item == null || item.threadId != receipt.threadId) return null;
    final state = item.state;
    if (state is! ThreadTurnItemStateView) return null;
    if (state.inputId != receipt.inputId) return null;
    return state.state.status;
  }

  void settle() {
    if (observedTurns.isEmpty) return;
    client.mutations.observe(stamp);
    if (observedTurns.values.any(
      (entry) => entry.status != StudioTurnStatus.queued,
    )) {
      operation.markEffective();
    }
    // `cursor` is an input-acceptance cursor, not a content or storage clock.
    // Only the matching Turn item's authoritative `saved` flag proves durable
    // history here; terminal/completed alone cannot satisfy this condition.
    if (observedTurns.values.any((entry) => entry.saved)) {
      operation.markDurable();
    }
    if (operation.state.value.effective && operation.state.value.durable) {
      observation.cancel();
    }
  }

  void mergeState(ThreadSessionState state) {
    if (observation.isCancelled || state.threadId != receipt.threadId) return;
    final turn = state.activeTurn?.inputId == receipt.inputId
        ? state.activeTurn
        : state.workspace?.latestTurn?.inputId == receipt.inputId
        ? state.workspace?.latestTurn
        : null;
    if (turn == null) {
      // 状态流没有该 input 的 Turn 事实时，内容帧仍可能已经交付它。
      if (observedTurns.isEmpty) return;
      settle();
      return;
    }
    final existing = observedTurns[turn.turnId];
    observedTurns[turn.turnId] = _ObservedInputTurn(
      saved: existing?.saved ?? false,
      status: turn.state.status,
    );
    settle();
  }

  void _considerItem(StudioTimelineItem item) {
    final status = _turnStatus(item.item);
    if (status == null) return;
    if (item.item.threadId != receipt.threadId) return;
    observedTurns[item.id] = _ObservedInputTurn(
      saved: item.saved,
      status: status,
    );
  }

  void mergeFrame(StudioTimelineFrame frame) {
    if (observation.isCancelled) return;
    switch (frame) {
      case StudioTimelineBaselineFrame(:final baseline):
        observedTurns.clear();
        for (final item in baseline.items) {
          _considerItem(item);
        }
      case StudioTimelinePatchFrame(:final patch):
        for (final change in patch.changes) {
          switch (change) {
            case StudioTimelineAdd(:final item):
              _considerItem(item);
            case StudioTimelineUpdateItem(
              :final itemId,
              :final saved,
              :final itemShell,
            ):
              final existing = observedTurns[itemId];
              if (existing == null) continue;
              observedTurns[itemId] = _ObservedInputTurn(
                saved: saved,
                status: _turnStatus(itemShell) ?? existing.status,
              );
            case StudioTimelineRemove(:final itemId):
              observedTurns.remove(itemId);
          }
        }
    }
    settle();
  }

  try {
    operation.accept(
      CommitReceipt(
        operationId: operation.id,
        disposition: CommitDisposition.applied,
        targets: [stamp],
        effect: EffectPoint.nextTurn,
      ),
    );
    permit = client.budget.acquire(
      ResourceKind.observer,
      owner: 'input:${operation.id.value}',
    );
    observation = _InputObservation(permit, retainedOperation);
    attached = observation;
    final session = client.session(receipt.threadId);
    final stateSource = session.source.watchLatest(mergeState);
    observation.sources.add(stateSource.observation);
    final contentSource = session.timeline.state.watchLatest((uiState) {
      final StudioTimelineFrame? frame = uiState.snapshot;
      if (frame != null) mergeFrame(frame);
    });
    observation.sources.add(contentSource.observation);
    mergeState(stateSource.value);
    return observation;
  } catch (_) {
    attached?.cancel();
    permit?.release();
    retainedOperation.cancel();
    rethrow;
  }
}

/// 一个 input 的 Turn 最小观测：身份、保存水位与执行状态，不含正文。
final class _ObservedInputTurn {
  const _ObservedInputTurn({required this.saved, required this.status});
  final bool saved;
  final StudioTurnStatus status;
}

/// Owns the source listeners, the operation retention and its explicit budget.
final class _InputObservation implements Observation {
  _InputObservation(this.permit, this.operation);
  final ResourcePermit permit;
  final Observation operation;
  final List<Observation> sources = [];
  @override
  bool isCancelled = false;
  @override
  bool get isPaused => sources.any((source) => source.isPaused);
  @override
  void pause() {
    for (final source in sources) {
      source.pause();
    }
  }

  @override
  void resume() {
    for (final source in sources) {
      source.resume();
    }
  }

  @override
  void cancel() {
    if (isCancelled) return;
    isCancelled = true;
    for (final source in sources) {
      source.cancel();
    }
    sources.clear();
    operation.cancel();
    permit.release();
  }
}

bool isKnownSubmissionRejection(Object error) =>
    error is StudioFailure &&
    switch (error.code) {
      StudioFailureCode.invalidArgument ||
      StudioFailureCode.notFound ||
      StudioFailureCode.busy ||
      StudioFailureCode.conflict ||
      StudioFailureCode.staleRevision ||
      StudioFailureCode.permissionDenied ||
      StudioFailureCode.overloaded => true,
      _ => false,
    };
