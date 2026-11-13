import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import 'agy_host_trace.dart';
import 'agy_remote_workspace.dart';
import 'agy_submission_evidence.dart';
import 'production_studio_harness.dart';

Future<void> runAgyAcceptancePhases({
  required ProductionStudioScene scene,
  required AcpConversationSession owner,
  required AgyRemoteWorkspace? remote,
  required String? command,
  required String marker,
  required String childProfileId,
  required Map<String, Object?> evidence,
  required Future<void> Function(String) record,
  required Future<void> Function() closeHarness,
}) => _Phases(
  scene,
  owner,
  remote,
  command,
  marker,
  childProfileId,
  evidence,
  record,
  closeHarness,
).run();

final class _Phase {
  const _Phase(this.id, this.marker, this.prompt);
  final String id;
  final String marker;
  final String prompt;
}

final class _Phases {
  _Phases(
    this.scene,
    this.owner,
    this.remote,
    this.command,
    this.marker,
    this.childProfileId,
    this.evidence,
    this.record,
    this.closeHarness,
  );
  final ProductionStudioScene scene;
  final AcpConversationSession owner;
  final AgyRemoteWorkspace? remote;
  final String? command;
  final String marker;
  final String childProfileId;
  final Map<String, Object?> evidence;
  final Future<void> Function(String) record;
  final Future<void> Function() closeHarness;
  final AgyLocalProcesses processes = AgyLocalProcesses();
  final List<Map<String, Object?>> samplingErrors = [];
  final List<Map<String, Object?>> cleanupErrors = [];
  Future<void> samples = Future.value();
  String phase = 'before-first-prompt';
  AcpRunIdView? admittedRun;
  final Set<AcpRunIdView> observedRuns = {};
  AgySubmissionEvidence? submission;
  Object? watchError;
  StackTrace? watchStack;

  void checkWatch() {
    if (watchError case final error?) {
      Error.throwWithStackTrace(error, watchStack!);
    }
  }

  String get threadId => owner.state.target!.threadId;
  Set<String> get markers =>
      remote == null ? {marker} : {'${marker}A', '${marker}B', '${marker}C'};
  Set<String> get safeCommands => remote == null
      ? {}
      : {
          for (final kind in ['stdin', 'cancel', 'shutdown'])
            remote!.processCommand(kind),
          'cat input-token.txt',
          'cat cancel.proc cancel-child.proc',
          'pwd -P > command-cwd.txt; uname -s > command-system.txt',
        };

  Future<void> sample({bool requireAgy = false}) async {
    if (remote == null) return;
    await processes.capture(command!, requireAgy: requireAgy);
  }

  Future<void> snapshot(String name) async {
    final state = owner.state;
    final calls = AgyHostTrace(state.content)
        .diagnostics(safeCommands: safeCommands, markers: markers);
    final pending = calls
        .where(
          (call) =>
              call['status'] == 'pending' || call['status'] == 'inProgress',
        )
        .toList();
    final data = <String, Object?>{
      'phase': phase,
      'checkpoint': name,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'target': {
        'sessionId': state.target?.sessionId,
        'agentId': state.target?.agentId,
        'threadId': state.target?.threadId,
        'instance': state.target?.instance.toString(),
      },
      'acpSessionId': state.remoteSessionId?.value,
      'admittedRun': _run(admittedRun),
      'observedAcceptedRuns': observedRuns.map(_run).toList(),
      'activeRun': _run(state.activeRun),
      'lastCompleted': _completed(state.lastCompleted),
      'sendPending': state.sendPending,
      'configPending': state.configPending,
      'permissionCount': state.pendingPermissions.length,
      'errorType': state.error?.runtimeType.toString(),
      'observationGap': state.observationGap?.name,
      'disconnected': state.disconnected,
      'observationEnded': state.observationEnded,
      'toolCalls': calls,
      'pendingToolCalls': pending,
      'lastInProgressToolCall': pending.isEmpty ? null : pending.last,
      'unknownStatusToolCallIds': [
        for (final call in calls)
          if (call['status'] == null) call['toolCallId'],
      ],
      'lastFormalToolCall': calls.isEmpty ? null : calls.last,
      'localOwnedProcesses': processes.evidence,
      'samplingErrors': samplingErrors,
      'watchErrorType': watchError?.runtimeType.toString(),
      'userInputEvidence': submission?.diagnostics(),
    };
    await File(p.join(scene.harness.artifacts.path, '$name.json'))
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert(data),
          flush: true,
        );
  }

  Future<void> run() async {
    final target = owner.state.target!;
    final session = owner.state.remoteSessionId;
    final observedCalls = <String>{};
    final watch = owner.source.watch((state) {
      try {
        submission?.observe(state);
        if (state.activeRun case final run?) {
          admittedRun ??= run;
          observedRuns.add(run);
        }
        // Event-driven incremental process sampling, including a child while its
        // wait_agent call is in flight. Keep and join every sampling future.
        for (final call in state.content.whereType<AcpConversationToolItem>()) {
          final key = '${call.toolCallId.value}:${call.fields.status?.name}';
          if (!observedCalls.add(key)) continue;
          final sampledPhase = phase;
          samples = samples.then((_) async {
            try {
              await sample();
            } catch (error) {
              samplingErrors.add({
                'phase': sampledPhase,
                'toolCallId': call.toolCallId.value,
                'errorType': error.runtimeType.toString(),
              });
            }
          });
        }
      } catch (error, stack) {
        // LatestValue routes listener exceptions to the Zone. Retain the
        // original failure here and surface it in the awaited phase flow.
        watchError ??= error;
        watchStack ??= stack;
      }
    });
    Object? primary;
    StackTrace? primaryStack;
    try {
      await sample(requireAgy: remote != null);
      await snapshot('before-first-prompt');
      final stages = remote == null
          ? [
              _Phase(
                'text',
                marker,
                scene.graph.client.drafts.composer(threadId).state.draft,
              ),
            ]
          : [
              _Phase('A', '${marker}A', remote!.promptA('${marker}A')),
              _Phase(
                'B',
                '${marker}B',
                remote!.promptB('${marker}B', childProfileId),
              ),
              _Phase('C', '${marker}C', remote!.promptC('${marker}C')),
            ];
      final results = <String, Object?>{};
      evidence['phases'] = results;
      for (final stage in stages) {
        expect(owner.state.target, target);
        expect(owner.state.remoteSessionId, session);
        results[stage.id] = await runPhase(stage);
        expect(cleanupErrors, isEmpty);
      }
      if (remote != null) {
        // Re-check all phase-specific evidence with the original markers, not
        // the latest phase's marker or idle state.
        evidence['finalPhaseAReadback'] = await remote!.verifyPhaseA(
          '${marker}A',
        );
        evidence['finalPhaseBReadback'] = await remote!.verifyPhaseB(
          '${marker}B',
        );
        evidence['runningBeforeClose'] = await remote!.verifyShutdownStarted();
        final trace = AgyHostTrace(owner.state.content);
        evidence['finalHostToolCalls'] = trace.verifyCompletedHostCalls();
        evidence['finalTasks'] = trace.verifyTasks(
          '${marker}A',
          remote!.processCommand,
        );
        evidence['finalChild'] = trace.verifyChild(
          childProfileId,
          '${marker}B',
          target.agentId,
        );
        evidence['finalShutdownTask'] = trace.verifyShutdown(
          remote!.processCommand('shutdown'),
        );
      }
      checkWatch();
      expect(samplingErrors, isEmpty);
      expect(scene.tester.takeException(), isNull);
    } catch (error, stack) {
      primary = error;
      primaryStack = stack;
      evidence['failureType'] = error.runtimeType.toString();
    } finally {
      try {
        watch.cancel();
      } catch (error) {
        cleanupErrors.add({
          'stage': 'stop-process-sampling',
          'errorType': error.runtimeType.toString(),
        });
      }
      await samples;
      await guard('pre-close-sample', () => sample());
      await guard('pre-close-state', () => snapshot('before-member-close'));
      if (remote != null) {
        await guard('pre-close-remote-identities', () async {
          evidence['remoteOwnedBeforeClose'] = await remote!.observeProcesses();
        });
      }
      // A test wait timing out never cancels the accepted business future.
      // Close the actual member and await its public reclamation receipt.
      await guard('close-member', () async {
        final close = await owner.closeMember();
        evidence['acpClose'] = {
          'localComplete': close.localComplete,
          'sdkFinished': close.sdkFinished,
          'cleanupTimedOut': close.cleanupTimedOut,
          'unfinishedControls': close.unfinishedControls,
          'unfinishedPrompt': _run(close.unfinishedPrompt),
          'lastCompleted': _completed(close.lastCompleted),
          'ownerFailureThreadIds': close.ownerFailures
              .map((f) => f.threadId)
              .toList(),
          'remoteCloseErrorPresent': close.remoteCloseError != null,
          'sdkErrorPresent': close.sdkError != null,
          'workerErrorPresent': close.workerError != null,
          'driverErrorPresent': close.driverError != null,
        };
        await record('explicit-acp-close-returned');
        expect(close.localComplete, isTrue);
        expect(close.sdkFinished, isTrue);
        expect(close.cleanupTimedOut, isFalse);
        expect(close.unfinishedControls, isFalse);
        expect(close.unfinishedPrompt, isNull);
        expect(close.ownerFailures, isEmpty);
        // Peer protocol close is capability-dependent; its diagnostic is recorded
        // above and cannot replace or invalidate independently confirmed local cleanup.
        expect(close.sdkError, isNull);
        expect(close.workerError, isNull);
        expect(close.driverError, isNull);
      });
      await guard('dispose-scene', scene.dispose);
      await guard('harness-shutdown', () async {
        await closeHarness();
        evidence['harnessShutdownCompleted'] = true;
      });
      if (remote != null) {
        await guard('remote-process-exit', () async {
          evidence['remoteExitedAfterClose'] = await remote!
              .verifyClosedProcesses(requireShutdown: primary == null);
        });
        await guard('local-process-exit', () async {
          await processes.verifyClosed();
          evidence['localOwnedExited'] = true;
        });
      }
      evidence['localOwnedProcesses'] = processes.evidence;
      evidence['localProcessExitChecks'] = processes.exitEvidence;
      evidence['remoteProcessExitChecks'] = remote?.exitEvidence;
      evidence['cleanupErrors'] = cleanupErrors;
      evidence['samplingErrors'] = samplingErrors;
      evidence['watchErrorType'] = watchError?.runtimeType.toString();
      evidence['verdict'] =
          primary == null &&
              watchError == null &&
              cleanupErrors.isEmpty &&
              samplingErrors.isEmpty
          ? (remote == null
                ? 'text-scenario-passed'
                : 'acp-remote-scenario-passed')
          : 'failed';
      await guard('final-report', () => record('scenario-finally-complete'));
    }
    if (primary != null) Error.throwWithStackTrace(primary, primaryStack!);
    expect(cleanupErrors, isEmpty);
    expect(samplingErrors, isEmpty);
    checkWatch();
  }

  Future<void> guard(String stage, Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      cleanupErrors.add({
        'stage': stage,
        'errorType': error.runtimeType.toString(),
      });
    }
  }

  Future<Map<String, Object?>> runPhase(_Phase spec) async {
    phase = spec.id;
    admittedRun = null;
    observedRuns.clear();
    final before = owner.state.lastCompleted;
    final beforeSequence = before?.completionSequence ?? BigInt.zero;
    final startIndex = owner.state.content.length;
    final previousCalls = owner.state.content
        .whereType<AcpConversationToolItem>()
        .map((call) => call.toolCallId)
        .toSet();
    final draft = scene.graph.client.drafts.composer(threadId);
    final result = <String, Object?>{
      'marker': spec.marker,
      'previousCompleted': _completed(before),
      'deadlineSeconds': remote == null ? 120 : 240,
      'verdict': 'running',
    };
    (evidence['phases'] as Map<String, Object?>)[spec.id] = result;
    try {
      expect(owner.state.activeRun, isNull);
      expect(owner.state.sendPending, isFalse);
      checkWatch();
      submission = AgySubmissionEvidence(
        expectedPrompt: spec.prompt,
        before: owner.state,
      );
      expect(submission!.startIndex, startIndex);
      if (draft.state.draft != spec.prompt) {
        await scene.tester.enterText(
          find.byKey(ValueKey(AcpViewKeyValues.composerInput(threadId))),
          spec.prompt,
        );
        await scene.tester.pumpAndSettle();
      }
      expect(draft.state.draft, spec.prompt);
      await sample();
      await snapshot('phase-${spec.id}-before-send');
      evidence['promptCount'] = (evidence['promptCount'] as int) + 1;
      await record('phase-${spec.id}-dispatch-once');
      await scene.tester.tap(
        find.byKey(ValueKey(AcpViewKeyValues.composerPrimaryAction(threadId))),
      );
      await scene.until(
        () {
          checkWatch();
          final state = owner.state;
          expect(
            state.error == null,
            isTrue,
            reason: 'ACP owner error; see redacted phase state',
          );
          expect(state.observationGap, isNull);
          expect(state.disconnected, isFalse);
          expect(state.observationEnded, isFalse);
          if (state.pendingPermissions.isNotEmpty) {
            throw StateError(
              'Unexpected permission request; no automatic approval',
            );
          }
          final completed = state.lastCompleted;
          if (observedRuns.length > 1) {
            throw StateError('More than one accepted run in phase ${spec.id}');
          }
          return admittedRun != null &&
              admittedRun != before?.run &&
              completed != null &&
              completed.run == admittedRun &&
              completed.completionSequence > beforeSequence &&
              state.activeRun == null;
        },
        'phase ${spec.id} original new-run completion',
        timeout: Duration(seconds: remote == null ? 120 : 240),
      );
      final completed = owner.state.lastCompleted!;
      checkWatch();
      submission!.verify();
      result['userInputEvidence'] = submission!.diagnostics();
      expect(completed.run, admittedRun);
      expect(completed.completionSequence, greaterThan(beforeSequence));
      expect(completed.result, isA<AcpSuccessView<AcpPromptResponseView>>());
      final stop = (completed.result as AcpSuccessView<AcpPromptResponseView>)
          .value
          .stopReason;
      expect(stop, AcpStopReasonView.endTurn);
      expect(owner.state.sendPending, isFalse);
      expect(draft.state.draft, isEmpty);
      final newContent = owner.state.content.skip(startIndex).toList();
      final assistants = newContent
          .whereType<AcpConversationMessageItem>()
          .where(
            (message) => message.kind == AcpConversationMessageKind.assistant,
          )
          .toList();
      expect(assistants, isNotEmpty);
      expect(
        _text(assistants.last).trim() == spec.marker,
        isTrue,
        reason: 'Final assistant marker differs; body not logged',
      );
      final trace = AgyHostTrace(
        owner.state.content.where(
          (item) =>
              item is AcpConversationToolItem &&
              !previousCalls.contains(item.toolCallId),
        ),
      );
      result['completion'] = _completed(completed);
      if (remote != null) {
        result['hostToolCalls'] = trace.verifyCompletedHostCalls();
        switch (spec.id) {
          case 'A':
            result['taskLifecycle'] = trace.verifyTasks(
              spec.marker,
              remote!.processCommand,
            );
            result['readback'] = await remote!.verifyPhaseA(spec.marker);
          case 'B':
            result['childReport'] = trace.verifyChild(
              childProfileId,
              spec.marker,
              owner.state.target!.agentId,
            );
            result['readback'] = await remote!.verifyPhaseB(spec.marker);
          case 'C':
            result['shutdownTask'] = trace.verifyShutdown(
              remote!.processCommand('shutdown'),
            );
            result['readback'] = await remote!.verifyShutdownStarted();
        }
      }
      final assistantIndex = owner.state.content.lastIndexWhere(
        (item) =>
            item is AcpConversationMessageItem &&
            item.kind == AcpConversationMessageKind.assistant,
      );
      final assistantItem = find.byKey(
        ValueKey(AcpViewKeyValues.timelineItem(threadId, assistantIndex)),
      );
      await scene.tester.scrollUntilVisible(
        assistantItem,
        250,
        scrollable: find
            .descendant(
              of: find.byType(AcpConversationContentView),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 20,
      );
      await scene.until(
        () => find
            .descendant(
              of: assistantItem,
              matching: find.textContaining(spec.marker, findRichText: true),
            )
            .evaluate()
            .isNotEmpty,
        'phase ${spec.id} final assistant marker rendered',
      );
      await scene.capture('agy-live-phase-${spec.id.toLowerCase()}-response');
      result['verdict'] = 'passed';
      return result;
    } catch (error) {
      result['verdict'] = 'failed';
      result['failureType'] = error.runtimeType.toString();
      await guard(
        'phase-${spec.id}-failure-state',
        () => snapshot('phase-${spec.id}-timeout-or-error'),
      );
      rethrow;
    } finally {
      evidence['lastPhaseResult'] = result;
      await samples;
      await guard('phase-${spec.id}-final-sample', () => sample());
      if (remote != null) {
        await guard('phase-${spec.id}-remote-identities', () async {
          evidence['remoteOwnedProcesses'] = await remote!.observeProcesses();
        });
      }
      await guard(
        'phase-${spec.id}-final-state',
        () => snapshot('phase-${spec.id}-finally'),
      );
      await guard(
        'phase-${spec.id}-final-report',
        () => record('phase-${spec.id}-finally'),
      );
    }
  }
}

String _text(AcpConversationMessageItem item) => item.chunks
    .map((chunk) => chunk.content)
    .whereType<AcpTextContentView>()
    .map((block) => block.text)
    .join();

Map<String, Object?>? _run(AcpRunIdView? run) => run == null
    ? null
    : {
        'instance': run.instance.toString(),
        'sequence': run.sequence.toString(),
      };

Map<String, Object?>? _completed(AcpCompletedRunView? completed) =>
    completed == null
    ? null
    : {
        'run': _run(completed.run),
        'completionSequence': completed.completionSequence.toString(),
        'resultType': completed.result.runtimeType.toString(),
        'result': switch (completed.result) {
          AcpSuccessView<AcpPromptResponseView>(:final value) => {
            'kind': 'success',
            'stopReason': value.stopReason.name,
          },
          AcpFailureView<AcpPromptResponseView>(:final error) => {
            'kind': 'failure',
            'failureKind': error.kind.name,
            'rpcCode': error.rpcCode,
          },
        },
        'truncated': completed.truncated,
      };
