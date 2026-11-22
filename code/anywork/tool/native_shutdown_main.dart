// Native shutdown setup only. The process owner outside the app judges exit
// and remaining children; this entry does not inject faults or assert UI state.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/main.dart' as studio;
import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork/src/platform/error_log.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/scheduler.dart';

void main() {
  final graph = createProductionAppGraph();
  studio.bootstrapStudio(graph: graph);
  unawaited(
    _prepareAndClose(graph).catchError((Object error, StackTrace stack) async {
      recordDartError(error, stack, stage: 'native-shutdown-setup');
      final coord = Platform.environment['ANYWORK_NATIVE_SHUTDOWN_COORD']!;
      await File('$coord/shutdown-failure.json')
          .writeAsString(jsonEncode({'error': error.toString()}));
      await StudioExitCoordinator.requestExit();
    }),
  );
}

Future<void> _prepareAndClose(AppGraph graph) async {
  final coord = Platform.environment['ANYWORK_NATIVE_SHUTDOWN_COORD']!;
  final project = Platform.environment['ANYWORK_NATIVE_SHUTDOWN_PROJECT']!;
  final prompt = Platform.environment['ANYWORK_NATIVE_SHUTDOWN_PROMPT']!;
  final bootstrap = await graph.client.bootstrapState
      .waitFor(
        (value) =>
            value.phase == StudioBootstrapPhase.ready ||
            value.phase == StudioBootstrapPhase.failed,
      )
      .timeout(const Duration(seconds: 120));
  if (bootstrap.phase == StudioBootstrapPhase.failed) {
    throw StateError('Shutdown setup failed: ${bootstrap.failure}');
  }
  // Let the shell finish its initial navigation before submitting this setup.
  await SchedulerBinding.instance.endOfFrame;
  await SchedulerBinding.instance.endOfFrame;
  await graph.client.directoryCommands.openProject(project);
  final workspaceId = graph.client.selection.state.selectedProjectId!;
  final route = ModelRouteQueries.modeRoute(
    graph.client.settings.state.canonical!.modeModelRoutes,
    ThreadModeId.simple,
  )!;
  final result = await graph.client.threadCommands.submitNewThread(
    workspaceId: workspaceId,
    input: StudioPromptInput(
      inputId: 'native-shutdown-setup',
      text: prompt,
      attachmentDraftIds: const [],
    ),
    mode: ThreadModeId.simple,
    route: route,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    onProgress: (_) {},
  );
  if (result == null) {
    throw StateError('Shutdown setup did not create a Thread');
  }
  await graph.client.directoryCommands.selectThread(result.thread.id);
  final completedTurn = await _waitForCompletedSetupTurn(
    graph,
    result.thread.id,
    inputId: 'native-shutdown-setup',
  );
  final ready = File('$coord/shutdown-ready.tmp');
  await ready.writeAsString(
    jsonEncode({
      'pid': pid,
      'threadId': result.thread.id,
      'turnId': completedTurn.turnId,
      'inputId': completedTurn.inputId,
    }),
  );
  await ready.rename('$coord/shutdown-ready.json');
  await _waitForClose(File('$coord/shutdown-close'))
      .timeout(const Duration(seconds: 120));
  await StudioExitCoordinator.requestExit();
}

Future<HistoryTurnHead> _waitForCompletedSetupTurn(
  AppGraph graph,
  String threadId, {
  required String inputId,
  Duration timeout = const Duration(seconds: 120),
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  final deadline = DateTime.now().add(timeout);
  Duration remaining() {
    final value = deadline.difference(DateTime.now());
    if (value <= Duration.zero) {
      throw TimeoutException('Timed out waiting for shutdown setup History');
    }
    return value;
  }

  final history = await graph.client.conversations
      .openHistoryReader(threadId)
      .timeout(timeout);
  try {
    var cut = await history.capture().timeout(remaining());
    while (true) {
      String? pendingTurnId;
      var cursor = <String>{};
      String? continuation;
      do {
        final page = await history
            .turnsPage(
              cut: cut,
              cursor: continuation,
              demand: const HistoryDemand(maxRows: 128, maxBytes: 1024 * 1024),
            )
            .timeout(remaining());
        for (final entry in page.entries) {
          if (entry.head case TurnHistoryBusinessRow(:final head)
              when head.inputId == inputId) {
            switch (head.state) {
              case HistoryTurnState.completed:
                return head;
              case HistoryTurnState.cancelled:
              case HistoryTurnState.failed:
              case HistoryTurnState.budgetLimited:
                throw StateError(
                  'Shutdown setup Turn ${head.turnId} ended as '
                  '${head.state.name}',
                );
              case HistoryTurnState.unknown:
              case HistoryTurnState.queued:
              case HistoryTurnState.running:
                pendingTurnId = head.turnId;
            }
          }
        }
        continuation = page.next;
        if (continuation != null && !cursor.add(continuation)) {
          throw StateError('Shutdown setup Turn continuation repeated');
        }
      } while (continuation != null);

      final changed = await history.waitChanged(cut).timeout(remaining());
      if (changed == cut) {
        throw StateError(
          pendingTurnId == null
              ? 'Shutdown setup History change did not advance'
              : 'Shutdown setup Turn $pendingTurnId did not advance',
        );
      }
      cut = changed;
    }
  } finally {
    await history.close();
  }
}

Future<void> _waitForClose(File signal) async {
  while (!await signal.exists()) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
