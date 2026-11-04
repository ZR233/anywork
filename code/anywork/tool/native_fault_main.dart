// Thin native-test assembly for shutdown faults and unique lifecycle
// proofs. Product, capture, and release builds keep lib/main.dart.
// Each scene enables only the fault it needs through
// ANYWORK_NATIVE_SHUTDOWN_FAULT; required turns use production Client
// APIs (openProject + start draft / composer submit), never a FlutterDriver journey.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/main.dart' as studio;
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/infrastructure/frb/statistics/frb_statistics_feed.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/platform/error_log.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/scheduler.dart';

void main() {
  if (const bool.fromEnvironment('dart.vm.product')) {
    throw StateError('Native fault assembly is unavailable in product builds');
  }
  if (const bool.fromEnvironment('ANYWORK_CAPTURE')) {
    throw StateError('Native fault assembly must not enable capture');
  }
  final fault = Platform.environment['ANYWORK_NATIVE_SHUTDOWN_FAULT'];
  final phase = Platform.environment['ANYWORK_NATIVE_SHUTDOWN_PHASE'];
  switch (fault) {
    case 'pending-init':
      FrbStudioTransport.debugOverrideInitialization(
        () => Completer<void>().future,
      );
      studio.bootstrapStudio();
    case 'bridge-load-error':
      FrbStudioTransport.debugOverrideInitialization(() async {
        throw StateError('native-test bridge load failure');
      });
      studio.bootstrapStudio();
    case 'subscription':
      _bootstrapPhase(
        graph: AppGraph(
          transport: _FaultSubscriptionTransport(),
          statisticsFeed: const FrbStatisticsFeedPort(),
        ),
        phase: phase,
        fault: fault,
      );
    default:
      if ((phase == null || phase.isEmpty) &&
          (fault == null || fault.isEmpty)) {
        throw StateError(
          'ANYWORK_NATIVE_SHUTDOWN_FAULT must name pending-init, '
          'bridge-load-error, subscription, or hang; or '
          'ANYWORK_NATIVE_SHUTDOWN_PHASE must name a lifecycle scene',
        );
      }
      if (fault != null &&
          fault.isNotEmpty &&
          fault != 'hang' &&
          (phase == null || phase.isEmpty)) {
        throw StateError('Unknown native shutdown fault: $fault');
      }
      _bootstrapPhase(
        graph: createProductionAppGraph(),
        phase: phase,
        fault: fault,
      );
  }
}

void _bootstrapPhase({
  required AppGraph graph,
  required String? phase,
  required String? fault,
}) {
  unawaited(
    _runPhase(graph, phase, fault).catchError((Object error, StackTrace stack) {
      recordDartError(error, stack, stage: 'native-shutdown-assembly');
    }),
  );
  studio.bootstrapStudio(graph: graph);
}

Future<void> _runPhase(AppGraph graph, String? phase, String? fault) async {
  await Future<void>.delayed(Duration.zero);
  await SchedulerBinding.instance.endOfFrame;
  await SchedulerBinding.instance.endOfFrame;
  if (phase == null || phase.isEmpty) {
    if (fault == 'hang') {
      await _waitReady(graph);
      await _hangIsolate();
    }
    return;
  }
  await _waitReady(graph);
  await _NativeLifecycleAssembly(graph).run(phase);
}

Future<void> _waitReady(AppGraph graph) async {
  final state = await graph.client.bootstrapState
      .waitFor(
        (value) =>
            value.phase == StudioBootstrapPhase.ready ||
            value.phase == StudioBootstrapPhase.failed,
      )
      .timeout(const Duration(seconds: 120));
  if (state.phase == StudioBootstrapPhase.failed) {
    throw StateError('native assembly bootstrap failed: ${state.failure}');
  }
}

Future<Never> _hangIsolate() async {
  await StudioHostLifecycle.beginExit();
  await StudioHostLifecycle.updateExitDiagnostics(stage: 'native-hang');
  await StudioHostLifecycle.updateExitDiagnostics(stage: 'native-hang-blocked');
  sleep(const Duration(minutes: 5));
  throw StateError('native hang finished unexpectedly');
}

Future<void> _requestExit() => StudioExitCoordinator.requestExit();

final class _NativeLifecycleAssembly {
  _NativeLifecycleAssembly(this.graph);

  final AppGraph graph;
  final String coord =
      Platform.environment['ANYWORK_NATIVE_SHUTDOWN_COORD'] ?? '';
  final String output =
      Platform.environment['ANYWORK_NATIVE_SHUTDOWN_OUTPUT'] ?? '';
  final String project =
      Platform.environment['ANYWORK_NATIVE_SHUTDOWN_PROJECT'] ?? '';
  final String prompt =
      Platform.environment['ANYWORK_NATIVE_SHUTDOWN_PROMPT'] ?? '';
  final String secondPrompt =
      Platform.environment['ANYWORK_NATIVE_SHUTDOWN_SECOND_PROMPT'] ?? '';

  Future<void> run(String phase) async {
    try {
      await _run(phase);
    } catch (error, stack) {
      try {
        _recordState('failed');
      } catch (diagnosticError, diagnosticStack) {
        recordDartError(
          diagnosticError,
          diagnosticStack,
          stage: 'native-shutdown-state-diagnostic',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _run(String phase) async {
    switch (phase) {
      case 'normal':
        await _runSettledTurnThenExit(
          connected: 'normal_connected',
          settled: 'normal_settled',
          observed: 'normal',
          exitRequested: 'normal_exit_requested',
          open: true,
        );
      case 'reopen':
        await _runReopen('normal', 'reopen');
      case 'busy-reopen':
        await _runReopen('busy_continue', 'busy-reopen');
      case 'busy-hold':
        await _runBusyHold();
      case 'duplicate':
        await _runSettledTurnThenExit(
          connected: 'duplicate_connected',
          settled: 'duplicate_settled',
          observed: 'duplicate',
          exitRequested: 'duplicate_exit_requested',
          open: true,
          twice: true,
        );
      case 'hang':
        await _runHang();
      case 'storage-lock':
        await _runStorageLock();
      case 'storage-verify':
        await _runStorageVerify();
      case 'service-unresponsive':
        await _runServiceUnresponsive();
      case 'mcp-reclamation':
        await _runSubtreeReclamation(
          connected: 'mcp-reclamation_connected',
          coordFile: 'shutdown-mcp-coord.json',
          served: 'mcp-reclamation_served',
          armed: 'mcp-reclamation-armed',
          exitRequested: 'mcp-reclamation_exit_requested',
        );
      case 'lsp-reclamation':
        await _runSubtreeReclamation(
          connected: 'lsp-reclamation_connected',
          coordFile: 'shutdown-lsp-coord.json',
          served: 'lsp-reclamation_served',
          armed: 'lsp-reclamation-armed',
          exitRequested: 'lsp-reclamation_exit_requested',
        );
      case 'tool-reclamation':
        await _runSubtreeReclamation(
          connected: 'tool-reclamation_connected',
          coordFile: 'shutdown-tool-coord.json',
          served: 'tool-reclamation_served',
          armed: 'tool-reclamation-armed',
          exitRequested: 'tool-reclamation_exit_requested',
        );
      case 'concurrent-stop':
        await _runConcurrentStop();
      default:
        throw StateError('Unknown native shutdown phase: $phase');
    }
  }

  Future<void> _runSettledTurnThenExit({
    required String connected,
    required String settled,
    required String observed,
    required String exitRequested,
    required bool open,
    bool twice = false,
  }) async {
    await mark(connected);
    if (open) {
      await _openProject();
    } else {
      await _awaitSelectedThread();
    }
    final turn = await _settle(prompt, settled);
    await _writeObserved(observed, turn);
    await mark(settled);
    await mark(exitRequested);
    await _requestExit();
    if (twice) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _requestExit();
    }
  }

  Future<void> _runBusyHold() async {
    await mark('busy_hold_connected');
    await _awaitSelectedThread();
    await mark('busy_hold_reopened');
    await _awaitSignal('busy-second-redirected', const Duration(seconds: 600));
    final continued = await _settle(prompt, 'busy_continue');
    await _writeObserved('busy_continue', continued);
    await mark('busy_continued');
    await mark('busy_exit_requested');
    await _requestExit();
  }

  Future<void> _runHang() async {
    await mark('hang_connected');
    await _openProject();
    final settled = await _settle(prompt, 'hang');
    await _writeObserved('hang', settled);
    await mark('hang_settled');
    await mark('hang_exit_requested');
    await _hangIsolate();
  }

  Future<void> _runStorageLock() async {
    await mark('storage_lock_connected');
    await _openProject();
    final settled = await _settle(prompt, 'storage_prime');
    await _writeObserved('storage', settled);
    await mark('storage_prime_settled');
    await _awaitSignal('storage-lock-held', const Duration(seconds: 300));
    await _submit(secondPrompt);
    await _waitBusy('storage_blocked_inflight');
    await mark('storage_blocked');
    await _awaitSignal('storage-exit', const Duration(seconds: 300));
    await mark('storage_exit_requested');
    await _requestExit();
  }

  Future<void> _runStorageVerify() async {
    await mark('storage-verify_connected');
    await _openProject();
    await _verifyRestored('storage');
    await mark('storage-verify_restored');
    await mark('storage-verify_exit_requested');
    await _requestExit();
  }

  Future<void> _runReopen(String key, String phase) async {
    await mark('${phase}_connected');
    await _openProject();
    await _verifyRestored(key);
    await mark('${phase}_restored');
    await mark('${phase}_exit_requested');
    await _requestExit();
  }

  Future<void> _runServiceUnresponsive() async {
    await mark('service_connected');
    await _openProject();
    await _submit(prompt);
    await _waitBusy('service_inflight');
    await mark('service_inflight');
    await _awaitSignal('service-frozen', const Duration(seconds: 180));
    await mark('service_exit_requested');
    await _requestExit();
  }

  Future<void> _runSubtreeReclamation({
    required String connected,
    required String coordFile,
    required String served,
    required String armed,
    required String exitRequested,
  }) async {
    await mark(connected);
    await _openProject();
    await _submit(prompt);
    await _awaitFile(coordFile, const Duration(seconds: 240));
    await mark(served);
    await _awaitSignal(armed, const Duration(seconds: 180));
    await mark(exitRequested);
    await _hangIsolate();
  }

  Future<void> _runConcurrentStop() async {
    await mark('concurrent-stop_connected');
    await _openProject();
    await _submit(prompt);
    await _awaitFile(
      'shutdown-concurrent-mcp-coord.json',
      const Duration(seconds: 240),
    );
    await _awaitFile(
      'shutdown-concurrent-tool-coord.json',
      const Duration(seconds: 240),
    );
    await mark('concurrent-stop_served');
    await _awaitSignal('concurrent-stop-armed', const Duration(seconds: 240));
    await mark('concurrent-stop_exit_requested');
    await _requestExit();
  }

  Future<void> _openProject() async {
    if (project.isEmpty) {
      throw StateError('ANYWORK_NATIVE_SHUTDOWN_PROJECT is required');
    }
    _recordState('opening project');
    await graph.client.directoryCommands.openProject(project);
    _recordState('project opened');
    if (graph.client.selection.state.selectedProjectId == null) {
      throw StateError('native assembly openProject did not select a project');
    }
    // Empty projects are a new-session destination, not an existing Thread.
    // The first prompt must create its Thread through the production start draft.
    if (graph.client.selection.state.selectedThreadId != null) {
      await _awaitSelectedThread();
    }
  }

  Future<void> _awaitSelectedThread() async {
    _recordState('awaiting selected thread: selectedThreadId != null');
    final selection = await _waitValue(
      graph.client.selection.source,
      (state) => state.selectedThreadId != null,
      'selectedThreadId != null',
    );
    if (selection.needsOpen) {
      // Startup restoration deliberately requires the same explicit open intent
      // as the production "open selected Thread" action.
      await graph.client.directoryCommands.openSelectedThread();
    }
    await _waitValue(
      graph.client.selection.source,
      (state) =>
          state.selectedThreadId == selection.selectedThreadId &&
          !state.needsOpen,
      'selected thread opened (same identity, needsOpen == false)',
    );
    final threadId = selection.selectedThreadId!;
    // Studio follows canonical selection; only bot routes pin an explicit ID.
    graph.setConversationPageVisible(true);
    _recordState('awaiting visible thread snapshot and available model route');
    final state = await _waitValue(
      graph.client.conversations.session(threadId).source,
      (state) =>
          state.sync.phase == DomainSyncPhase.failed ||
          (state.hasSnapshot &&
              state.workspace?.thread.id == threadId &&
              state.modelRoute?.available == true),
      'thread snapshot and model route',
    );
    if (state.sync.phase == DomainSyncPhase.failed) {
      throw StateError(
        'native assembly thread $threadId state source failed: '
        '${state.sync.errorMessage}',
      );
    }
    _recordState('selected thread ready');
  }

  Future<_SettledTurn> _settle(String text, String label) async {
    final previousThreadId = graph.client.selection.state.selectedThreadId;
    final previous = previousThreadId == null
        ? null
        : graph.client.conversations
              .existingSession(previousThreadId)
              ?.state
              .lastTurn
              ?.turnId;
    final threadId = await _submit(text);
    final session = graph.client.conversations.session(threadId);
    final settled = await _waitValue(
      session.source,
      (state) {
        final turn = state.lastTurn;
        return turn != null && turn.turnId != previous && turn.state.isTerminal;
      },
      '$label settled turn',
      timeout: const Duration(seconds: 180),
    );
    final turn = settled.lastTurn!;
    if (turn.state is! CompletedStudioTurnState) {
      throw StateError(
        '$label turn ${turn.turnId} did not complete: '
        '${turn.state.status.name}: ${turn.state.reason}',
      );
    }
    _recordState('$label turn completed');
    return _SettledTurn(threadId: threadId, turnId: turn.turnId);
  }

  Future<String> _submit(String text) async {
    if (text.isEmpty) {
      throw StateError('native assembly prompt is empty');
    }
    _recordState('submitting prompt');
    final selection = graph.client.selection.state;
    if (selection.selectedThreadId == null) {
      final workspaceId = selection.selectedProjectId;
      if (workspaceId == null) {
        throw StateError('native assembly has no new-session project');
      }
      final draft = graph.client.drafts.startDraft;
      draft.updateDraft(workspaceId, text);
      if (!await draft.submit(workspaceId)) {
        throw graph.client.drafts.attachments.state
                .newThread(workspaceId)
                .failure ??
            StateError(
              'native assembly new-session submission was not accepted',
            );
      }
      await _awaitSelectedThread();
      _recordState('new-session prompt accepted');
      return _threadId;
    }
    await _awaitSelectedThread();
    final threadId = _threadId;
    final composer = graph.client.drafts.composer(threadId);
    composer.updateDraft(text);
    await composer.submit();
    if (composer.state.failure case final error?) throw error;
    _recordState('existing-thread prompt accepted');
    return threadId;
  }

  Future<void> _waitBusy(String label) async {
    await _waitValue(
      graph.client.conversations.session(_threadId).source,
      (state) => state.lastTurn?.state.isBusy == true,
      label,
      timeout: const Duration(seconds: 60),
    );
  }

  String get _threadId {
    final threadId = graph.client.selection.state.selectedThreadId;
    if (threadId == null) {
      throw StateError('native assembly has no selected thread');
    }
    return threadId;
  }

  Future<void> mark(String value) async {
    _requireCoord();
    _recordState(value);
    await File('$coord/shutdown-stage-$value').writeAsString(value);
    await File('$coord/shutdown-stage').writeAsString(value);
  }

  Future<void> _awaitSignal(String name, Duration timeout) async {
    _requireCoord();
    await _awaitPath('$coord/shutdown-signal-$name', timeout, 'signal $name');
  }

  Future<void> _awaitFile(String name, Duration timeout) async {
    _requireCoord();
    await _awaitPath('$coord/$name', timeout, 'file $name');
  }

  Future<void> _writeObserved(String key, _SettledTurn settled) async {
    if (output.isEmpty) return;
    if (key == 'normal' || key == 'busy_continue' || key == 'storage') {
      final inventory = await _inventory(settled);
      final expected = switch (key) {
        'normal' => 'shutdown normal exit answer',
        'busy_continue' => 'shutdown second instance answer',
        'storage' => 'shutdown storage lock prime answer',
        _ => throw StateError('Unknown saved-turn inventory: $key'),
      };
      if (!inventory.any(
        (item) =>
            item['channel'] == ThreadTextChannel.finalAnswer.name &&
            item['key'] == 'body' &&
            item['body'] == expected,
      )) {
        throw StateError(
          '$key saved turn did not contain the exact fixture answer',
        );
      }
      await File('$output/shutdown-inventory-$key.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(inventory)}\n',
      );
    }
    await File('$output/shutdown-observed-$key.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'threadId': settled.threadId, 'turnId': settled.turnId})}\n',
    );
  }

  Future<void> _verifyRestored(String key) async {
    final observed = jsonDecode(
      await File('$output/shutdown-observed-$key.json').readAsString(),
    ) as Map<String, dynamic>;
    final threadId = observed['threadId'] as String;
    final turnId = observed['turnId'] as String;
    await _awaitSelectedThread();
    if (_threadId != threadId) {
      throw StateError(
        '$key restored a different Thread: $_threadId != $threadId',
      );
    }
    if (key != 'storage') {
      final turn = graph.client.conversations.session(threadId).state.lastTurn;
      if (turn?.turnId != turnId || turn?.state is! CompletedStudioTurnState) {
        throw StateError('$key did not restore the completed turn $turnId');
      }
    }
    final inventory = await _inventory(
      _SettledTurn(threadId: threadId, turnId: turnId),
    );
    final expected = jsonDecode(
      await File('$output/shutdown-inventory-$key.json').readAsString(),
    );
    if (jsonEncode(inventory) != jsonEncode(expected)) {
      throw StateError(
        '$key restored content inventory differs from the saved turn',
      );
    }
    await File('$output/shutdown-restored-$key.json').writeAsString(
      '${jsonEncode(<String, Object?>{'threadId': threadId, 'turnId': turnId, 'contentItems': inventory.length, 'inventoryMatched': true})}\n',
    );
    _recordState('$key saved turn and content inventory restored');
  }

  Future<List<Map<String, Object?>>> _inventory(_SettledTurn settled) async {
    // Reliable Items live in the original Main controller. Their current
    // counterparts retire at handoff; liveUnits is only a diagnostic surface.
    final deadline = DateTime.now().add(const Duration(seconds: 120));
    TimelineDisplayLease? lease;
    List<TimelineItem> items = const [];
    try {
      while (DateTime.now().isBefore(deadline)) {
        final error = graph.timeline.source.value?.connectionError;
        if (error != null) throw error;
        lease ??= graph.timeline.lease(settled.threadId);
        if (lease != null) {
          _requireInventoryOwner(settled, lease);
          items = _mainItems(lease)
              .where((item) => item.turnId == settled.turnId)
              .toList();
          if (items.any((item) => _isInventoryFinal(item, settled))) break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (lease == null ||
          !items.any((item) => _isInventoryFinal(item, settled))) {
        throw TimeoutException(
          'saved turn ${settled.turnId} has no qualified completed final Main Item; '
          'see shutdown-assembly-$pid.jsonl inventory metadata',
        );
      }
      _requireInventoryOwner(settled, lease);
      _recordInventory('Main inventory ready', settled, lease);
      final scope = lease.openDetailQueries();
      if (scope == null) {
        throw StateError('Saved-turn original Main reader is unavailable');
      }
      try {
        if (scope.threadId != settled.threadId ||
            scope.generation != lease.generation) {
          throw StateError('Saved-turn original Main reader identity changed');
        }
        final inventory = <Map<String, Object?>>[];
        for (final item in items) {
          final itemId = item.contentItemId;
          if (itemId == null) {
            if (item.kind == TimelineItemKind.text) {
              throw StateError(
                'Saved Main text ${item.id} has no content identity',
              );
            }
            continue;
          }
          _requireInventoryOwner(settled, lease);
          final manifest = await scope.listContents(
            itemId: itemId,
            demand: lease.demand,
          );
          if (manifest.continuation != null) {
            throw StateError(
              'Native fixture content inventory exceeded one bounded page',
            );
          }
          if (item.kind == TimelineItemKind.text &&
              manifest.entries.where((entry) => entry.key == 'body').length !=
                  1) {
            throw StateError('Saved Main text $itemId has no unique body');
          }
          for (final entry in manifest.entries) {
            final target = entry.reference.target;
            if (target is! BodyContentTarget ||
                target.owner is! ItemContentOwner ||
                (target.owner as ItemContentOwner).itemId != itemId ||
                target.key != entry.key) {
              throw StateError(
                'Manifest reference does not own $itemId/${entry.key}',
              );
            }
            final byteLength = switch (jsonDecode(utf8.decode(entry.payload))) {
              {'byteLength': final int length} when length >= 0 => length,
              _ => throw StateError('Saved body has no valid byte length'),
            };
            _requireInventoryOwner(settled, lease);
            final window = await scope.readContent(
              reference: entry.reference,
              range: ContentRange(offset: 0, maxBytes: lease.demand.maxBytes),
            );
            if (window.offset != 0 ||
                !window.sealed ||
                window.availableThrough != byteLength ||
                window.bytes.length > lease.demand.maxBytes ||
                window.bytes.length != byteLength) {
              throw StateError(
                'Native fixture content is not fully sealed in range: '
                '$itemId/${entry.key}',
              );
            }
            inventory.add({
              'timelineItemId': item.id,
              'itemId': itemId,
              'source': _inventorySource(item.source),
              'turnId': item.turnId,
              'position': item.position,
              'key': entry.key,
              'databaseId': entry.reference.databaseId,
              'channel': item.textChannel?.name,
              'body': utf8.decode(window.bytes),
            });
          }
        }
        if (inventory.isEmpty) {
          throw StateError('Native fixture content inventory is empty');
        }
        inventory.sort(
          (a, b) => '${a['itemId']}/${a['key']}'.compareTo(
            '${b['itemId']}/${b['key']}',
          ),
        );
        return inventory;
      } finally {
        await lease.closeDetailQueries(scope);
      }
    } catch (error, stack) {
      try {
        _recordInventory('Main inventory failed', settled, lease);
      } catch (diagnosticError, diagnosticStack) {
        recordDartError(
          diagnosticError,
          diagnosticStack,
          stage: 'native-shutdown-inventory-diagnostic',
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Iterable<TimelineItem> _mainItems(TimelineDisplayLease lease) sync* {
    for (final message in lease.controller.messages) {
      final unit = message.metadata?[timelineDisplayUnitKey];
      if (unit is! TimelineDisplayUnit ||
          message.id != unit.id ||
          unit.live ||
          unit.item.position == null) {
        throw StateError(
          'Original Main message ${message.id} has no reliable Item',
        );
      }
      yield unit.item;
    }
  }

  void _requireInventoryOwner(
    _SettledTurn settled,
    TimelineDisplayLease lease,
  ) {
    if (lease.isRetired ||
        lease.isReleased ||
        !identical(graph.timeline.lease(settled.threadId), lease) ||
        graph.client.selection.state.selectedThreadId != settled.threadId ||
        graph.client.conversations.visibleThreadId.value != settled.threadId) {
      throw StateError('Saved-turn original Main lease is no longer selected');
    }
  }

  Map<String, bool> _inventoryPredicates(
    TimelineItem item,
    _SettledTurn settled,
  ) => {
    'sameTurn': item.turnId == settled.turnId,
    'sameSource':
        item.source == ForegroundTurnChatSource(turnId: settled.turnId),
    'text': item.kind == TimelineItemKind.text,
    'textAtom': item.atomKind == ChatAtomKind.text,
    'finalAnswer': item.textChannel == ThreadTextChannel.finalAnswer,
    'completed': item.outcome == ChatTerminalOutcome.completed,
    'reliablePosition': item.position != null,
    'contentIdentity': item.contentItemId != null,
  };

  bool _isInventoryFinal(TimelineItem item, _SettledTurn settled) =>
      _inventoryPredicates(item, settled).values.every((value) => value);

  Map<String, String> _inventorySource(ChatSourceId source) => switch (source) {
    ForegroundTurnChatSource(:final turnId) => {'foregroundTurn': turnId},
    InputChatSource(:final inputId) => {'input': inputId},
    BackgroundResultChatSource(:final messageId) => {
      'backgroundResult': messageId,
    },
    OperationChatSource(:final operationId) => {'operation': operationId},
    ReceiptChatSource(:final receiptId) => {'receipt': receiptId},
  };

  void _recordInventory(
    String event,
    _SettledTurn settled,
    TimelineDisplayLease? lease,
  ) {
    Map<String, Object?> describe(TimelineDisplayUnit unit) {
      final item = unit.item;
      return {
        'id': item.id,
        'kind': item.kind.name,
        'live': unit.live,
        'source': _inventorySource(item.source),
        'turnId': item.turnId,
        'channel': item.textChannel?.name,
        'outcome': item.outcome?.name,
        'position': item.position,
        'contentItemId': item.contentItemId,
        'contentReferences': [
          for (final content in item.contents)
            {
              'role': content.role.name,
              'targetKind': content.reference.target.runtimeType.toString(),
              'itemOwned': switch (content.reference.target) {
                BodyContentTarget(owner: ItemContentOwner(:final itemId)) =>
                  itemId == item.contentItemId,
                _ => false,
              },
            },
        ],
        'predicates': _inventoryPredicates(item, settled),
      };
    }

    final readable = lease != null && !lease.isReleased;
    final snapshot = {
      'at': DateTime.now().toUtc().toIso8601String(),
      'pid': pid,
      'event': event,
      'threadId': settled.threadId,
      'turnId': settled.turnId,
      'leasePresent': lease != null,
      'leaseThreadId': lease?.threadId,
      'generation': lease?.generation,
      'selectionId': lease?.selectionId,
      'retired': lease?.isRetired,
      'released': lease?.isReleased,
      'selected':
          lease != null &&
          identical(graph.timeline.lease(settled.threadId), lease),
      'selectedThreadId': graph.client.selection.state.selectedThreadId,
      'visibleThreadId': graph.client.conversations.visibleThreadId.value,
      'main': [
        if (readable)
          for (final message in lease.controller.messages)
            if (message.metadata?[timelineDisplayUnitKey]
                case final TimelineDisplayUnit unit)
              {'messageId': message.id, ...describe(unit)}
            else
              {'messageId': message.id, 'unitPresent': false},
      ],
      'live': [
        if (readable)
          for (final unit in lease.liveUnits.value) describe(unit),
      ],
    };
    _requireCoord();
    File('$coord/shutdown-assembly-$pid.jsonl').writeAsStringSync(
      '${jsonEncode(snapshot)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  void _requireCoord() {
    if (coord.isEmpty) {
      throw StateError('ANYWORK_NATIVE_SHUTDOWN_COORD is required');
    }
  }

  // Read only existing owners. Diagnostics must not allocate a session, draft,
  // query, lease or permit and must never serialize config, prompts or VM URLs.
  void _recordState(String event) {
    _requireCoord();
    final client = graph.client;
    final selection = client.selection.state;
    final threadId = selection.selectedThreadId;
    final session = threadId == null
        ? null
        : client.conversations.existingSession(threadId);
    final state = session?.state;
    final contentState = session?.content.state.value;
    Object? contentError;
    if (contentState is ChatFailed<bool>) contentError = contentState.error;
    if (contentState is ChatReconnecting<bool>) {
      contentError = contentState.error;
    }
    final workspaceId = selection.selectedProjectId;
    final snapshot = <String, Object?>{
      'at': DateTime.now().toUtc().toIso8601String(),
      'pid': pid,
      'phase': Platform.environment['ANYWORK_NATIVE_SHUTDOWN_PHASE'],
      'event': event,
      'bootstrap': client.bootstrapState.value.phase.name,
      'clientClosed': client.isClosed,
      'selectedProjectId': workspaceId,
      'selectedThreadId': threadId,
      'needsOpen': selection.needsOpen,
      'visibleThreadId': client.conversations.visibleThreadId.value,
      'sessionExists': session != null,
      'sessionActive': session?.isActive,
      'sessionClosed': session?.isClosed,
      'contentHasDemand': session?.content.hasDemand,
      'contentState': contentState.runtimeType.toString(),
      'contentError': contentError?.toString(),
      'hasSnapshot': state?.hasSnapshot,
      'snapshotThreadId': state?.workspace?.thread.id,
      'modelRouteAvailable': state?.modelRoute?.available,
      'stateSourcePhase': state?.sync.phase.name,
      'stateSourceError': state?.sync.errorMessage,
      'lastTurnId': state?.lastTurn?.turnId,
      'lastTurnState': state?.lastTurn?.state.status.name,
      'lastTurnReason': state?.lastTurn?.state.reason,
      'composerFailure': threadId == null
          ? null
          : client.drafts.existingComposer(threadId)?.state.failure?.toString(),
      'startDraftFailure': workspaceId == null
          ? null
          : client.drafts.attachments.state
                .newThread(workspaceId)
                .failure
                ?.toString(),
    };
    File('$coord/shutdown-assembly-$pid.jsonl').writeAsStringSync(
      '${jsonEncode(snapshot)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }
}

Future<T> _waitValue<T>(
  ValueObservation<T> source,
  bool Function(T) predicate,
  String label, {
  Duration timeout = const Duration(seconds: 120),
}) {
  return source
      .waitFor(predicate)
      .timeout(
        timeout,
        onTimeout: () =>
            throw TimeoutException('timed out waiting for $label', timeout),
      );
}

Future<void> _awaitPath(String path, Duration timeout, String label) async {
  final file = File(path);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await file.exists()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('timed out waiting for $label', timeout);
}

class _SettledTurn {
  const _SettledTurn({required this.threadId, required this.turnId});

  final String threadId;
  final String turnId;
}

/// Real FRB transport whose shutdown-progress subscription is faulty.
final class _FaultSubscriptionTransport extends FrbStudioTransport {
  @override
  Stream<StudioShutdownProgress> subscribeShutdownProgress() {
    late final StreamController<StudioShutdownProgress> controller;
    controller = StreamController<StudioShutdownProgress>(
      onListen: () {
        controller.addError(
          StateError('native-test shutdown progress subscription failure'),
          StackTrace.current,
        );
      },
      onCancel: () => Completer<void>().future,
    );
    return controller.stream;
  }
}
