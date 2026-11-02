// Thin native-test assembly for shutdown faults and unique lifecycle
// proofs. Product, capture, and release builds keep lib/main.dart.
// Each scene enables only the fault it needs through
// ANYWORK_NATIVE_SHUTDOWN_FAULT; required turns use production Client
// APIs (openProject + composer submit), never FlutterDriver.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/main.dart' as studio;
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork/src/infrastructure/frb/statistics/frb_statistics_feed.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/platform/error_log.dart';
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
    switch (phase) {
      case 'normal':
        await _runSettledTurnThenExit(
          connected: 'normal_connected',
          settled: 'normal_settled',
          observed: 'normal',
          exitRequested: 'normal_exit_requested',
          open: true,
        );
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
    await mark('storage-verify_restored');
    await mark('storage-verify_exit_requested');
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
    await graph.client.directoryCommands.openProject(project);
    await _awaitSelectedThread();
  }

  Future<void> _awaitSelectedThread() async {
    final selection = await _waitValue(
      graph.client.selection.source,
      (state) => state.selectedThreadId != null && !state.needsOpen,
      'selected thread',
    );
    final threadId = selection.selectedThreadId!;
    graph.setConversationPageVisible(true, threadId: threadId);
    await _waitValue(
      graph.client.conversations.session(threadId).source,
      (state) =>
          state.hasSnapshot &&
          state.workspace?.thread.id == threadId &&
          state.modelRoute?.available == true,
      'thread snapshot and model route',
    );
  }

  Future<_SettledTurn> _settle(String text, String label) async {
    final threadId = _threadId;
    final session = graph.client.conversations.session(threadId);
    final previous = session.state.lastTurn?.turnId;
    await _submit(text);
    final settled = await _waitValue(
      session.source,
      (state) {
        final turn = state.lastTurn;
        return turn != null && turn.turnId != previous && turn.state.isTerminal;
      },
      '$label settled turn',
      timeout: const Duration(seconds: 180),
    );
    return _SettledTurn(threadId: threadId, turnId: settled.lastTurn?.turnId);
  }

  Future<void> _submit(String text) async {
    if (text.isEmpty) {
      throw StateError('native assembly prompt is empty');
    }
    final composer = graph.client.drafts.composer(_threadId);
    composer.updateDraft(text);
    await composer.submit();
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
    await File('$output/shutdown-observed-$key.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'threadId': settled.threadId, 'turnId': settled.turnId})}\n',
    );
  }

  void _requireCoord() {
    if (coord.isEmpty) {
      throw StateError('ANYWORK_NATIVE_SHUTDOWN_COORD is required');
    }
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
  final String? turnId;
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
