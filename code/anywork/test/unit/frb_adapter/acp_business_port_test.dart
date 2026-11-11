import 'dart:async';

import 'package:anywork/src/app/app_composition.dart';
import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/acp_business/feed.dart';
import 'package:anywork/src/rust/api/studio/types/acp_business.dart' as b;
import 'package:anywork/src/rust/api/studio/types/acp_business/content.dart'
    as c;
import 'package:anywork/src/rust/api/studio/types/error.dart' as e;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart'
    show StudioFailure, StudioFailureCode;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException, PanicException;
import 'package:flutter_test/flutter_test.dart';

final _max = (BigInt.one << 64) - BigInt.one;
final _target = AcpSessionTargetView(
  sessionId: 'product-session',
  agentId: 'product-agent',
  threadId: 'product-thread',
  instance: _max,
);
final _run = AcpRunIdView(
  instance: _max - BigInt.one,
  sequence: _max - BigInt.two,
);
final _wireRun = b.BridgeAcpRunId(
  instance: _run.instance,
  sequence: _run.sequence,
);
final _wireTarget = b.BridgeAcpSessionTarget(
  sessionId: _target.sessionId,
  agentId: _target.agentId,
  threadId: _target.threadId,
  instance: _target.instance,
);
final _open = OpenAcpSessionRequestView(
  accountId: 'account',
  expectedConnectionRevision: _max,
  workspaceId: 'workspace',
  threadId: 'product-thread',
  intent: const AcpLoadIntentView(AcpRemoteSessionId('remote-session')),
);
const _failure = b.BridgeAcpBusinessFailure(
  kind: b.BridgeAcpBusinessFailureKind.rpc,
  rpcCode: -32001,
  message: 'known remote rejection',
  rpcData: b.BridgeAcpJsonValue.bool(value: false),
  authMethods: [],
);
const _runtime = e.BridgeError(
  code: e.BridgeErrorCode.staleRevision,
  message: 'known runtime rejection',
  retryable: false,
  correlationId: 'runtime-correlation',
  detailsJson: '{"expected":4,"actual":5}',
);

// A generated-resource fixture, not an AcpBusinessPort. It supplies source
// frames/ACKs and records calls; all mapping and command routing is production.
final class _Observation implements BridgeAcpSessionObservation {
  int reads = 0;
  int closeRequests = 0;
  int closes = 0;
  final frames = <b.BridgeAcpSessionFrame>[];
  Future<b.BridgeAcpSessionFrame?> Function()? read;
  void Function()? request;
  Future<void> Function()? release;

  @override
  Future<b.BridgeAcpSessionFrame?> next() async {
    reads++;
    if (read case final callback?) {
      return callback();
    }
    return frames.isEmpty ? null : frames.removeAt(0);
  }

  @override
  void requestClose() {
    closeRequests++;
    request?.call();
  }

  @override
  Future<void> close() async {
    closes++;
    await release?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected resource call ${invocation.memberName}',
  );
}

final class _BusinessApi implements RustLibApi {
  final observations = <_Observation>[];
  final calls = <({String name, Object request})>[];
  Object? failure;
  late b.BridgeAcpBusinessSnapshot state = b.BridgeAcpBusinessSnapshot(
    target: _wireTarget,
    ready: true,
    closing: false,
    configPending: false,
    activeRun: _wireRun,
    authMethods: const [],
  );
  b.BridgeAcpBusinessClose closed = b.BridgeAcpBusinessClose(
    localComplete: false,
    sdkFinished: true,
    cleanupTimedOut: true,
    remoteCloseError: _failure,
    workerError: 'worker cleanup',
    unfinishedPrompt: _wireRun,
    unfinishedControls: true,
    ownerFailures: const [
      b.BridgeAcpMemberCloseFailure(
        threadId: 'other-thread',
        message: 'owner cleanup',
      ),
    ],
  );

  void record(String name, Object request) {
    calls.add((name: name, request: request));
    if (failure case final error?) {
      throw error;
    }
  }

  @override
  Future<BridgeAcpSessionObservation>
  crateApiStudioHandlersAcpBusinessOpenAcpSession({
    required b.BridgeOpenAcpSessionRequest request,
  }) async {
    record('open', request);
    return observations.removeAt(0);
  }

  @override
  Future<b.BridgeAcpRunId> crateApiStudioHandlersAcpBusinessPromptAcpSession({
    required b.BridgeAcpPromptRequest request,
  }) async {
    record('prompt', request);
    return _wireRun;
  }

  @override
  Future<b.BridgeAcpRunId> crateApiStudioHandlersAcpBusinessReplaceAcpSession({
    required b.BridgeAcpReplaceRequest request,
  }) async {
    record('replace', request);
    return _wireRun;
  }

  @override
  Future<void> crateApiStudioHandlersAcpBusinessInterruptAcpSession({
    required b.BridgeAcpInterruptRequest request,
  }) async => record('interrupt', request);

  @override
  Future<void> crateApiStudioHandlersAcpBusinessConfigureAcpSession({
    required b.BridgeAcpConfigureRequest request,
  }) async => record('configure', request);

  @override
  Future<void> crateApiStudioHandlersAcpBusinessSetAcpSessionMode({
    required b.BridgeAcpSetModeRequest request,
  }) async => record('setMode', request);

  @override
  Future<void> crateApiStudioHandlersAcpBusinessAnswerAcpPermission({
    required b.BridgeAcpPermissionAnswerRequest request,
  }) async => record('answerPermission', request);

  @override
  Future<b.BridgeAcpListResponse>
  crateApiStudioHandlersAcpBusinessListAcpSessions({
    required b.BridgeAcpListRequest request,
  }) async {
    record('list', request);
    return const b.BridgeAcpListResponse(
      sessions: [
        b.BridgeAcpSessionInfo(
          sessionId: b.BridgeAcpRemoteSessionId(value: 'listed-remote'),
          cwd: '/remote',
          additionalDirectories: ['/second', '/first'],
          title: 'Remote title',
        ),
      ],
      nextCursor: 'next',
    );
  }

  @override
  Future<b.BridgeAcpBusinessSnapshot>
  crateApiStudioHandlersAcpBusinessAcpSessionSnapshot({
    required b.BridgeAcpSessionTarget target,
  }) async {
    record('snapshot', target);
    return state;
  }

  @override
  Future<b.BridgeAcpBusinessClose>
  crateApiStudioHandlersAcpBusinessCloseAcpSession({
    required b.BridgeAcpSessionTarget target,
  }) async {
    record('closeMember', target);
    return closed;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected bridge call ${invocation.memberName}');
}

void _expectTarget(b.BridgeAcpSessionTarget value) {
  expect(value.sessionId, 'product-session');
  expect(value.agentId, 'product-agent');
  expect(value.threadId, 'product-thread');
  expect(value.instance, _max);
}

void main() {
  late _BusinessApi api;
  const port = FrbAcpBusinessPort();
  setUp(() {
    api = _BusinessApi();
    RustLib.initMock(api: api);
    FrbStudioTransport.debugOverrideInitialization(() async {});
  });
  tearDown(() {
    FrbStudioTransport.debugOverrideInitialization(null);
    RustLib.dispose();
  });

  test('production Port calls all ten generated APIs with exact independent qualifications', () async {
    final handle = _Observation();
    api.observations.add(handle);
    final observation = await port.open(_open);
    expect(handle.reads, 0, reason: 'Open must not pull or wait for Settled');
    final open = api.calls.single.request as b.BridgeOpenAcpSessionRequest;
    expect(open.accountId, 'account');
    expect(open.expectedConnectionRevision, _max);
    expect(open.workspaceId, 'workspace');
    expect(open.threadId, 'product-thread');
    expect(
      (open.intent as b.BridgeAcpOpenIntent_Load).sessionId.value,
      'remote-session',
    );

    final content = AcpTextContentView(
      text: 'prompt',
      meta: AcpJsonObject({'number': AcpJsonInteger(_max)}),
    );
    final result = await port.prompt(
      AcpPromptRequestView(target: _target, content: [content]),
    );
    expect(result, _run);
    expect(result.instance, isNot(_target.instance));
    final prompt = api.calls.last.request as b.BridgeAcpPromptRequest;
    _expectTarget(prompt.target);
    expect(
      (prompt.content.single as c.BridgeAcpContentBlock_Text).text,
      'prompt',
    );
    expect(
      ((prompt.content.single.meta!['number'] as b.BridgeAcpJsonValue_Number)
                  .value
              as b.BridgeAcpJsonNumber_Unsigned)
          .value,
      _max,
    );

    expect(
      await port.replace(
        AcpReplaceRequestView(
          target: _target,
          run: _run,
          content: const [AcpTextContentView(text: 'replacement')],
        ),
      ),
      _run,
    );
    final replace = api.calls.last.request as b.BridgeAcpReplaceRequest;
    _expectTarget(replace.target);
    expect(replace.run, _wireRun);
    expect(
      (replace.content.single as c.BridgeAcpContentBlock_Text).text,
      'replacement',
    );
    await port.interrupt(AcpInterruptRequestView(target: _target, run: _run));
    final interrupt = api.calls.last.request as b.BridgeAcpInterruptRequest;
    _expectTarget(interrupt.target);
    expect(interrupt.run, _wireRun);

    await port.configure(
      AcpConfigureRequestView(
        target: _target,
        configId: const AcpConfigId('config-id'),
        value: const AcpBooleanConfigValueView(false),
      ),
    );
    final boolean = api.calls.last.request as b.BridgeAcpConfigureRequest;
    _expectTarget(boolean.target);
    expect(boolean.configId.value, 'config-id');
    expect(boolean.value, const b.BridgeAcpConfigValue.boolean(value: false));
    await port.configure(
      AcpConfigureRequestView(
        target: _target,
        configId: const AcpConfigId('select-id'),
        value: const AcpSelectConfigValueView(AcpConfigValueId('false')),
      ),
    );
    final select = api.calls.last.request as b.BridgeAcpConfigureRequest;
    expect(select.configId.value, 'select-id');
    expect(
      select.value,
      const b.BridgeAcpConfigValue.valueId(
        value: b.BridgeAcpConfigValueId(value: 'false'),
      ),
    );
    await port.setMode(
      AcpSetModeRequestView(
        target: _target,
        modeId: const AcpModeId('mode-id'),
      ),
    );
    final mode = api.calls.last.request as b.BridgeAcpSetModeRequest;
    _expectTarget(mode.target);
    expect(mode.modeId.value, 'mode-id');

    final permission = AcpPermissionIdView(
      instance: _max - BigInt.from(3),
      sequence: _max - BigInt.from(4),
    );
    await port.answerPermission(
      AcpPermissionAnswerRequestView(
        target: _target,
        permissionId: permission,
        optionId: const AcpPermissionOptionId('option-id'),
      ),
    );
    final answer = api.calls.last.request as b.BridgeAcpPermissionAnswerRequest;
    _expectTarget(answer.target);
    expect(answer.permissionId.instance, permission.instance);
    expect(answer.permissionId.sequence, permission.sequence);
    expect(answer.permissionId.instance, isNot(_target.instance));
    expect(answer.permissionId.instance, isNot(_run.instance));
    expect(answer.optionId!.value, 'option-id');
    await port.answerPermission(
      AcpPermissionAnswerRequestView(target: _target, permissionId: permission),
    );
    expect(
      (api.calls.last.request as b.BridgeAcpPermissionAnswerRequest).optionId,
      isNull,
    );

    final listed = await port.list(
      AcpListRequestView(
        target: _target,
        request: AcpListSessionsRequestView(
          cwd: '/working',
          cursor: 'cursor',
          meta: AcpJsonObject({'flag': const AcpJsonBool(false)}),
        ),
      ),
    );
    final list = api.calls.last.request as b.BridgeAcpListRequest;
    _expectTarget(list.target);
    expect(list.cwd, '/working');
    expect(list.cursor, 'cursor');
    expect(list.meta!['flag'], const b.BridgeAcpJsonValue.bool(value: false));
    expect(listed.sessions.single.sessionId.value, 'listed-remote');
    expect(listed.sessions.single.additionalDirectories, ['/second', '/first']);
    expect(listed.nextCursor, 'next');
    final snapshot = await port.snapshot(_target);
    _expectTarget(api.calls.last.request as b.BridgeAcpSessionTarget);
    expect(snapshot.target, _target);
    expect(snapshot.activeRun, _run);
    final closed = await port.closeMember(_target);
    _expectTarget(api.calls.last.request as b.BridgeAcpSessionTarget);
    expect(closed.localComplete, false);
    expect(closed.sdkFinished, true);
    expect(closed.cleanupTimedOut, true);
    expect(closed.unfinishedPrompt, _run);
    expect(closed.remoteCloseError!.rpcCode, -32001);
    expect(closed.ownerFailures.single.threadId, 'other-thread');
    expect(api.calls.map((c) => c.name), [
      'open',
      'prompt',
      'replace',
      'interrupt',
      'configure',
      'configure',
      'setMode',
      'answerPermission',
      'answerPermission',
      'list',
      'snapshot',
      'closeMember',
    ]);
    await observation.close();
    expect(handle.closes, 1);
  });

  test('same open handle preserves early events, Settled, gap and EOF without reopening', () async {
    final handle = _Observation()
      ..frames.addAll([
        b.BridgeAcpSessionFrame.accepted(
          target: _wireTarget,
          hasObservation: true,
        ),
        const b.BridgeAcpSessionFrame.event(
          event: b.BridgeAcpSessionEvent.ready(
            response: b.BridgeAcpNewSessionResponse(
              sessionId: b.BridgeAcpRemoteSessionId(value: 'remote'),
            ),
          ),
        ),
        const b.BridgeAcpSessionFrame.settled(
          result: b.BridgeAcpSettlement.succeeded(),
        ),
        const b.BridgeAcpSessionFrame.event(
          event: b.BridgeAcpSessionEvent.gap(
            gap: b.BridgeAcpObservationGap.windowExceeded,
          ),
        ),
      ]);
    api.observations.add(handle);
    final observation = await port.open(_open);
    expect(handle.reads, 0);
    expect((await observation.next() as AcpAcceptedFrameView).target, _target);
    expect(
      (await observation.next() as AcpEventFrameView).event,
      isA<AcpReadyEventView>(),
    );
    expect(
      (await observation.next() as AcpSettledFrameView).result,
      isA<AcpSuccessView<void>>(),
    );
    expect(
      ((await observation.next() as AcpEventFrameView).event as AcpGapEventView)
          .gap,
      AcpObservationGapView.windowExceeded,
    );
    expect(await observation.next(), isNull);
    expect(handle.reads, 5);
    expect(api.calls.map((c) => c.name), ['open']);
    expect(
      handle.closeRequests,
      0,
      reason: 'EOF/gap must not close the source or business',
    );
    expect(handle.closes, 0);
    await observation.close();
  });

  test('resident open returns only original Accepted and Settled, not synthetic Ready', () async {
    final handle = _Observation()
      ..frames.addAll([
        b.BridgeAcpSessionFrame.accepted(
          target: _wireTarget,
          hasObservation: false,
        ),
        const b.BridgeAcpSessionFrame.settled(
          result: b.BridgeAcpSettlement.succeeded(),
        ),
      ]);
    api.observations.add(handle);
    final observation = await port.open(_open);
    expect(
      (await observation.next() as AcpAcceptedFrameView).hasObservation,
      false,
    );
    expect(await observation.next(), isA<AcpSettledFrameView>());
    expect(await observation.next(), isNull);
    expect(api.calls.length, 1);
    await observation.close();
  });

  test('concurrent source Busy and read errors stay visible without a second queue or business command', () async {
    final pending = Completer<b.BridgeAcpSessionFrame?>();
    final entered = Completer<void>();
    final sourceError = AnyhowException('read source failed');
    final handle = _Observation();
    handle.read = () {
      if (handle.reads == 1) {
        entered.complete();
        return pending.future;
      }
      throw const b.BridgeAcpBusinessError.business(
        b.BridgeAcpBusinessFailure(
          kind: b.BridgeAcpBusinessFailureKind.busy,
          message: 'source busy',
          authMethods: [],
        ),
      );
    };
    api.observations.add(handle);
    final observation = await port.open(_open);
    final first = observation.next();
    await entered.future;
    await expectLater(
      observation.next(),
      throwsA(
        isA<AcpBusinessFailureView>().having(
          (e) => e.kind,
          'kind',
          AcpBusinessFailureKindView.busy,
        ),
      ),
    );
    expect(
      handle.reads,
      2,
      reason: 'The bridge sees both calls; adapter does not queue',
    );
    pending.complete(null);
    expect(await first, isNull);
    handle.read = () async => throw sourceError;
    await expectLater(observation.next(), throwsA(same(sourceError)));
    expect(api.calls.map((c) => c.name), ['open']);
    await observation.close();
  });

  test(
    'requestClose and close release and join only their original handle',
    () async {
      final pending = Completer<b.BridgeAcpSessionFrame?>();
      final readStarted = Completer<void>();
      final releaseStarted = Completer<void>();
      final releaseAck = Completer<void>();
      final first = _Observation()
        ..read = () {
          readStarted.complete();
          return pending.future;
        }
        ..request = () {
          pending.complete(null);
        }
        ..release = () {
          releaseStarted.complete();
          return releaseAck.future;
        };
      final second = _Observation();
      api.observations.addAll([first, second]);
      final observation = await port.open(_open);
      final other = await port.open(_open);
      final reading = observation.next();
      await readStarted.future;
      observation.requestClose();
      expect(await reading, isNull);
      var finished = false;
      final closing = observation.close().then((_) => finished = true);
      await releaseStarted.future;
      expect(
        finished,
        false,
        reason: 'close waits for the original release ACK',
      );
      expect(first.closeRequests, 1);
      expect(first.closes, 1);
      expect(second.closeRequests, 0);
      expect(second.closes, 0);
      expect(api.calls.map((c) => c.name), ['open', 'open']);
      releaseAck.complete();
      await closing;
      expect(finished, true);
      await other.close();
      expect(second.closes, 1);
    },
  );

  test('known business/runtime/unsupported errors keep their semantics; only dispatched bridge failures are unknown', () async {
    final request = AcpPromptRequestView(target: _target, content: const []);
    api.failure = const b.BridgeAcpBusinessError.business(_failure);
    await expectLater(
      port.prompt(request),
      throwsA(
        isA<AcpBusinessFailureView>()
            .having((e) => e.rpcCode, 'rpcCode', -32001)
            .having((e) => (e.rpcData as AcpJsonBool).value, 'rpcData', false),
      ),
    );
    api.failure = const b.BridgeAcpBusinessError.runtime(_runtime);
    final runtimeMatcher = isA<StudioFailure>()
        .having((e) => e.code, 'code', StudioFailureCode.staleRevision)
        .having((e) => e.correlationId, 'correlationId', 'runtime-correlation')
        .having((e) => e.detailsJson, 'detailsJson', _runtime.detailsJson)
        .having((e) => e.retryable, 'retryable', false);
    await expectLater(port.prompt(request), throwsA(runtimeMatcher));
    api.failure = _runtime;
    await expectLater(port.prompt(request), throwsA(runtimeMatcher));
    api.failure = const b.BridgeAcpBusinessError.unsupported(
      typeName: 'OfficialFutureVariant',
    );
    await expectLater(
      port.prompt(request),
      throwsA(
        isA<AcpUnsupportedPayload>().having(
          (e) => e.typeName,
          'typeName',
          'OfficialFutureVariant',
        ),
      ),
    );
    for (final failure in [
      AnyhowException('bridge failed after dispatch'),
      PanicException('bridge panicked'),
    ]) {
      api.failure = failure;
      await expectLater(
        port.prompt(request),
        throwsA(
          isA<AcpCommandOutcomeUnknown>()
              .having((e) => e.command, 'command', 'prompt')
              .having((e) => e.cause, 'cause', same(failure)),
        ),
      );
    }
    final programmingError = StateError('local bug');
    api.failure = programmingError;
    await expectLater(port.prompt(request), throwsA(same(programmingError)));
    expect(
      api.calls.length,
      7,
      reason: 'Every failure is one call, never an automatic resend',
    );
    expect(api.calls.every((c) => c.name == 'prompt'), true);
  });

  test('cleanup failures retain identity and retry releases the same original handle', () async {
    final cleanupError = AnyhowException('local cleanup failed');
    final handle = _Observation()..release = () async => throw cleanupError;
    api.observations.add(handle);
    final observation = await port.open(_open);
    await expectLater(observation.close(), throwsA(same(cleanupError)));
    expect(handle.closes, 1);
    handle.release = () async {};
    await observation.close();
    expect(handle.closes, 2);
    expect(api.calls.map((c) => c.name), ['open']);
  });

  test('production AppGraph injects real Port; Client disposal joins only its original observation', () async {
    final releaseStarted = Completer<void>();
    final releaseAck = Completer<void>();
    final handle = _Observation()
      ..release = () {
        releaseStarted.complete();
        return releaseAck.future;
      };
    api.observations.add(handle);
    final graph = createProductionAppGraph();
    final observation = await graph.client.acpSessions.open(_open);
    expect(observation, isA<AcpSessionObservation>());
    expect(handle.reads, 0);
    var finished = false;
    final closing = graph
        .close(deadline: DateTime.now().add(const Duration(seconds: 5)))
        .then((report) {
          finished = true;
          return report;
        });
    await releaseStarted.future;
    expect(finished, false);
    expect(handle.closeRequests, 1);
    expect(handle.closes, 1);
    expect(api.calls.map((c) => c.name), ['open']);
    releaseAck.complete();
    final report = await closing;
    expect(
      report.complete,
      true,
      reason: '${report.unresolved.map((e) => e.reason)}',
    );
    expect(
      handle.closes,
      1,
      reason: 'App disposal must not add another resource owner',
    );
  });

  test('demo composition remains explicitly unsupported, never a fake ACP business session', () async {
    final graph = createDemoAppGraph();
    expect(() => graph.client.acpSessions, throwsUnsupportedError);
    final report = await graph.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
    expect(report.complete, true);
    expect(api.calls, isEmpty);
  });
}
