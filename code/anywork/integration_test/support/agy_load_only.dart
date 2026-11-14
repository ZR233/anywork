import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'agy_host_trace.dart';
import 'agy_load_sampling.dart';
import 'agy_remote_workspace.dart';
import 'production_studio_harness.dart';

final class AgyLoadRequest {
  const AgyLoadRequest({required this.threadId, required this.sessionId});
  final String threadId;
  final String sessionId;

  static AgyLoadRequest? fromEnvironment(Map<String, String> environment) {
    final thread = environment['ANYWORK_AGY_LOAD_THREAD'];
    final session = environment['ANYWORK_AGY_LOAD_SESSION'];
    if (thread == null && session == null) return null;
    if (environment['ANYWORK_AGY_LIVE'] != '1' ||
        thread == null ||
        thread.trim().isEmpty ||
        session == null ||
        session.trim().isEmpty) {
      throw StateError('Load-only requires explicit live opt-in and both IDs');
    }
    return AgyLoadRequest(threadId: thread, sessionId: session);
  }
}

// An evidence observer of the existing Client, not another session owner.
final class AgyLoadObservation {
  AgyLoadObservation(this.request, this.record);
  final AgyLoadRequest request;
  final void Function(Map<String, Object?>) record;
  Object? failure;
  StackTrace? failureStack;
  int publications = 0;

  void observe(AcpConversationState state) {
    try {
      record({
        'sequence': ++publications,
        'utc': DateTime.now().toUtc().toIso8601String(),
        'target': _target(state.target),
        'acpSessionId': state.remoteSessionId?.value,
        'ready': state.ready,
        'openPending': state.openPending,
        'history': state.history.name,
        'loadSession': state.capabilities?.loadSession,
        'resumeSession': state.capabilities?.resumeSession,
        'capabilities': state.capabilities == null
            ? null
            : {
                'image': state.capabilities!.image,
                'audio': state.capabilities!.audio,
                'embeddedContext': state.capabilities!.embeddedContext,
                'loadSession': state.capabilities!.loadSession,
                'listSessions': state.capabilities!.listSessions,
                'resumeSession': state.capabilities!.resumeSession,
              },
        'hasObservation': state.hasObservation,
        'activeRun': _run(state.activeRun),
        'lastCompletedRun': _run(state.lastCompleted?.run),
        'completionSequence': state.lastCompleted?.completionSequence
            .toString(),
        'sendPending': state.sendPending,
        'configPending': state.configPending,
        'permissionCount': state.pendingPermissions.length,
        'observationGap': state.observationGap?.name,
        'observationEnded': state.observationEnded,
        'disconnected': state.disconnected,
        'error': state.error == null ? null : _error(state.error!),
        'toolCalls': AgyHostTrace(state.content)
            .diagnostics(safeCommands: const {}, markers: const {}),
      });
      final target = state.target;
      if (target != null && target.threadId != request.threadId ||
          state.remoteSessionId != null &&
              state.remoteSessionId!.value != request.sessionId) {
        throw StateError('Load returned a different original identity');
      }
      if (state.sendPending ||
          state.activeRun != null ||
          state.lastCompleted != null ||
          state.configPending ||
          state.pendingPermissions.isNotEmpty) {
        throw StateError('Unexpected active business/control during load-only');
      }
      if (state.capabilities?.loadSession == false) {
        throw StateError('Current peer does not support session/load');
      }
      if (state.error != null ||
          state.observationGap != null ||
          state.observationEnded ||
          state.disconnected) {
        throw StateError('Load observation failed; see redacted events');
      }
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
  }

  void verify() {
    if (failure case final error?) {
      Error.throwWithStackTrace(error, failureStack!);
    }
  }
}

Future<void> runAgyLoadOnly({
  required IntegrationTestWidgetsFlutterBinding binding,
  required AgyLoadRequest request,
}) async {
  String input(String name) {
    final value = Platform.environment[name];
    if (value == null || value.isEmpty) throw StateError('Supply $name');
    return value;
  }

  final sandbox = await Directory(input('ANYWORK_AGY_SANDBOX'))
      .resolveSymbolicLinks();
  final home = await Directory(input('ANYWORK_HOME')).resolveSymbolicLinks();
  final artifacts = Directory(input('ANYWORK_AGY_ARTIFACTS'));
  if (!p.equals(home, p.join(sandbox, 'studio-home')) ||
      p.isWithin(sandbox, p.normalize(p.absolute(artifacts.path))) ||
      !await Directory(p.join(home, 'data')).exists()) {
    throw StateError(
      'Load-only requires the original isolated home and new output',
    );
  }
  if (await artifacts.exists() && !await artifacts.list().isEmpty) {
    throw StateError('Load-only artifacts must be new and empty');
  }
  await artifacts.create(recursive: true);
  if (p.isWithin(sandbox, await artifacts.resolveSymbolicLinks())) {
    throw StateError('Load output resolves into the original sandbox');
  }
  final command = input('ANYWORK_AGY_COMMAND');
  final report = <String, Object?>{
    'kind': 'original-session-load-only',
    'promptCount': 0,
    'openAttempts': 0,
    'ownerAccepted': false,
    'diagnosticStartedUtc': DateTime.now().toUtc().toIso8601String(),
    'intent': 'load',
    'resume': false,
    'requestedThread': request.threadId,
    'requestedSession': request.sessionId,
    'guiPid': pid,
    'home': home,
    'verdict': 'running',
    'observationBoundary': 'Client current value after public admission, then every unpaused watch publication; not wire',
  };
  final errors = <Map<String, Object?>>[];
  final processes = AgyLocalProcesses();
  ProductionStudioHarness? harness;
  AcpConversationSession? owner;
  void Function()? stopWatch;
  Timer? timer;
  Future<void> writes = Future.value();
  var requireAgySample = false;
  var finalSampleTaken = false;
  final samples = AgyLoadSampling(
    () => processes.capture(command, requireAgy: requireAgySample),
  );
  Object? primary;
  StackTrace? primaryStack;
  void sample() => samples.request();

  Future<void> save() => File(p.join(artifacts.path, 'agy-load-report.json'))
      .writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
  Future<void> checkpoint(String stage) async {
    report['stage'] = stage;
    report['sampling'] = samples.diagnostics;
    await save();
  }

  Future<void> finishSamples() async {
    timer?.cancel();
    samples.closeAdmission();
    if (!finalSampleTaken) {
      finalSampleTaken = true;
      await samples.finalSample();
    } else {
      await samples.drain();
    }
  }

  Future<void> cleanup(String stage, Future<void> Function() action) async {
    try {
      await checkpoint('$stage-before');
    } catch (error) {
      errors.add({'stage': '$stage-checkpoint-before', ..._error(error)});
    }
    try {
      await action();
    } catch (error) {
      errors.add({'stage': stage, ..._error(error)});
    }
    try {
      await checkpoint('$stage-after');
    } catch (error) {
      errors.add({'stage': '$stage-checkpoint-after', ..._error(error)});
    }
  }

  try {
    await save();
    sample();
    await checkpoint('initial-process-sample-before');
    await samples.drain();
    await checkpoint('initial-process-sample-after');
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) => sample());
    await checkpoint('harness-start-before');
    harness = await ProductionStudioHarness.start(
      binding: binding,
      artifactsEnvironmentVariable: 'ANYWORK_AGY_ARTIFACTS',
    );
    await checkpoint('harness-start-after');
    // Do not mount navigation: only this original thread may be activated.
    final client = harness.graph.client;
    final demand = client.threadDirectory.observeThread(request.threadId);
    try {
      await checkpoint('directory-read-before');
      final metadata = await demand.state
          .waitFor((s) => s.frame != null || s.error != null || s.closed)
          .timeout(const Duration(seconds: 30));
      await checkpoint('directory-read-after');
      if (metadata.error != null || metadata.closed) {
        throw StateError('Original thread directory is not available');
      }
      final row = metadata.frame!.row;
      if (row == null ||
          row.threadId != request.threadId ||
          row.backend is! AcpAgentBackendView) {
        throw StateError('Original ACP association is missing');
      }
      final reference = (row.backend as AcpAgentBackendView).reference;
      final projects =
          client.project.state.projects?.values
              .where((project) => project.id == row.workspaceId)
              .toList() ??
          [];
      final project = projects.length == 1 ? projects.single : null;
      report['beforeLoad'] = {
        'sessionId': row.sessionId,
        'agentId': row.agentId,
        'threadId': row.threadId,
        'workspaceId': row.workspaceId,
        'archived': row.archived,
        'referenceSession': reference.acpSessionId,
        'accountId': reference.accountId,
        'protocolCwd': reference.cwd,
        'businessRoot': project?.path,
        'sshAlias': project?.sshAlias,
      };
      await save();
      if (reference.acpSessionId != request.sessionId ||
          row.archived ||
          project?.path != input('ANYWORK_AGY_PROJECT') ||
          project?.sshAlias != input('ANYWORK_AGY_SSH_ALIAS') ||
          client.hasAcpConversation(request.threadId)) {
        throw StateError(
          'Original reference/workspace differs or owner is resident',
        );
      }
      report['openAttempts'] = 1;
      await checkpoint('public-load-before');
      owner = await client
          .openAcpConversation(request.threadId, resume: false)
          .timeout(const Duration(seconds: 120));
      final currentOwner = owner;
      report['ownerAccepted'] = true;
      await checkpoint('public-load-after');
      final observer = AgyLoadObservation(request, (event) {
        writes = writes
            .then(
              (_) => File(p.join(artifacts.path, 'agy-load-events.jsonl'))
                  .writeAsString(
                    '${jsonEncode(event)}\n',
                    mode: FileMode.append,
                    flush: true,
                  ),
            )
            .then<void>(
              (_) {},
              onError: (Object error) {
                errors.add({'stage': 'event-write', ..._error(error)});
              },
            );
        sample();
      });
      final watch = currentOwner.source.watch(
        observer.observe,
        fireImmediately: true,
      );
      stopWatch = watch.cancel;
      await checkpoint('ready-wait-before');
      await currentOwner.source
          .waitFor(
            (s) =>
                observer.failure != null ||
                s.ready && !s.openPending ||
                s.error != null ||
                s.observationGap != null ||
                s.disconnected ||
                s.observationEnded,
          )
          .timeout(const Duration(seconds: 120));
      timer.cancel();
      samples.closeAdmission();
      await checkpoint('ready-wait-after');
      observer.verify();
      final state = currentOwner.state;
      expect(state.target!.sessionId, row.sessionId);
      expect(state.target!.agentId, row.agentId);
      expect(state.target!.threadId, request.threadId);
      expect(state.remoteSessionId!.value, request.sessionId);
      expect(state.capabilities!.loadSession, isTrue);
      expect(state.history, AcpConversationHistory.loadReplay);
      expect(state.ready && !state.openPending, isTrue);
      report['loadedTarget'] = _target(state.target);
      report['acpSessionId'] = state.remoteSessionId?.value;
      report['observedPublications'] = observer.publications;
      requireAgySample = true;
      await checkpoint('final-process-sample-before');
      await finishSamples();
      await checkpoint('final-process-sample-after');
      final trace = AgyHostTrace(state.content);
      final host = trace.calls
          .where((call) => AgyHostTrace.canonicalName(call.fields.name) != null)
          .toList();
      report['finalToolCalls'] = trace.diagnostics(
        safeCommands: const {},
        markers: const {},
      );
      if (host.isEmpty) {
        throw StateError('Peer did not replay formal Host tool content');
      }
      for (final call in host) {
        trace.output(call);
      }
      observer.verify();
      report['loadEvidenceAvailable'] = true;
    } finally {
      timer.cancel();
      samples.closeAdmission();
      await cleanup('directory-release', demand.release);
    }
  } catch (error, stack) {
    primary = error;
    primaryStack = stack;
    report['failure'] = _error(error);
  } finally {
    timer?.cancel();
    samples.closeAdmission();
    await cleanup('stop-watch', () async {
      stopWatch?.call();
    });
    await cleanup('join-observation-writes', () async {
      await writes;
    });
    await cleanup('final-process-sample', () async {
      await finishSamples();
    });
    if (owner != null) {
      await cleanup('close-member', () async {
        final close = await owner!.closeMember();
        report['closeMember'] = {
          'localComplete': close.localComplete,
          'sdkFinished': close.sdkFinished,
          'cleanupTimedOut': close.cleanupTimedOut,
          'unfinishedControls': close.unfinishedControls,
          'unfinishedPrompt': _run(close.unfinishedPrompt),
          'ownerFailureThreadIds': close.ownerFailures
              .map((v) => v.threadId)
              .toList(),
          'sdkErrorPresent': close.sdkError != null,
          'workerErrorPresent': close.workerError != null,
          'driverErrorPresent': close.driverError != null,
          'remoteCloseErrorPresent': close.remoteCloseError != null,
        };
        expect(close.localComplete && close.sdkFinished, isTrue);
        expect(close.cleanupTimedOut || close.unfinishedControls, isFalse);
        expect(close.unfinishedPrompt, isNull);
        expect(close.ownerFailures, isEmpty);
        expect(close.sdkError, isNull);
        expect(close.workerError, isNull);
        expect(close.driverError, isNull);
      });
    } else {
      report['closeMember'] = 'no admitted Client owner';
    }
    if (harness != null) {
      await cleanup('harness-shutdown', () async {
        await harness!.close();
        report['harnessShutdownCompleted'] = true;
      });
    }
    await cleanup('independent-local-exit', processes.verifyClosed);
    report['localOwnedProcesses'] = processes.evidence;
    report['processSampleCount'] = samples.diagnostics['started'];
    report['sampling'] = samples.diagnostics;
    report['localProcessExitChecks'] = processes.exitEvidence;
    report['cleanupErrors'] = errors;
    report['verdict'] = primary == null && errors.isEmpty
        ? 'load-evidence-available'
        : 'failed';
    await save();
  }
  if (primary != null) {
    Error.throwWithStackTrace(
      StateError('Load-only failed; see redacted agy-load-report.json'),
      primaryStack!,
    );
  }
  expect(errors, isEmpty);
}

Map<String, Object?>? _target(AcpSessionTargetView? target) => target == null
    ? null
    : {
        'sessionId': target.sessionId,
        'agentId': target.agentId,
        'threadId': target.threadId,
        'instance': target.instance.toString(),
      };
Map<String, Object?>? _run(AcpRunIdView? run) => run == null
    ? null
    : {
        'instance': run.instance.toString(),
        'sequence': run.sequence.toString(),
      };
Map<String, Object?> _error(Object error) {
  final message = error is AcpBusinessFailureView
      ? error.message
      : error.toString();
  return {
    'errorType': error.runtimeType.toString(),
    if (error is AcpBusinessFailureView) 'kind': error.kind.name,
    'messageUtf16Length': message.length,
    'messageSha256': sha256.convert(utf8.encode(message)).toString(),
    'knownErrorTokens': [
      for (final token in [
        'ACP product membership is not executable',
        'not support session/load',
        'Original ACP association is missing',
        'did not replay formal Host tool content',
        'Expected exactly one same-call formal JSON container content block',
      ])
        if (message.contains(token)) token,
    ],
  };
}
