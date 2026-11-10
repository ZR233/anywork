import 'dart:async';

import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/studio_client.dart' show AnyworkClient;
import 'package:test/test.dart';

import 'support/acp_business_port.dart';
import 'support/timeline_transport.dart' show TestConversationTransport;

final _target = AcpSessionTargetView(
  sessionId: 'product-session',
  agentId: 'product-agent',
  threadId: 'product-thread',
  instance: BigInt.from(901),
);
final _run = AcpRunIdView(instance: BigInt.from(7), sequence: BigInt.from(3));
final _permission = AcpPermissionIdView(
  instance: BigInt.from(7),
  sequence: BigInt.from(5),
);
const _remoteId = AcpRemoteSessionId('remote-session');
final _request = OpenAcpSessionRequestView(
  accountId: 'account',
  expectedConnectionRevision: BigInt.from(14),
  workspaceId: 'workspace',
  threadId: _target.threadId,
  intent: const AcpLoadIntentView(_remoteId),
);
final _accepted = AcpAcceptedFrameView(target: _target, hasObservation: true);
const _settled = AcpSettledFrameView(AcpSuccessView<void>(null));

ControlledAcpBusinessPort _port() => ControlledAcpBusinessPort()
  ..run = _run
  ..snapshotValue = AcpBusinessSnapshotView(
    target: _target,
    ready: true,
    closing: false,
    configPending: false,
    acpSessionId: _remoteId,
    activeRun: _run,
  )
  ..listValue = AcpListSessionsResponseView(sessions: [])
  ..closeValue = AcpBusinessCloseView(
    localComplete: true,
    sdkFinished: true,
    cleanupTimedOut: false,
    unfinishedControls: false,
  );

void main() {
  group('public ACP Client boundary', () {
    test('delivers Accepted and load updates before product Settled', () async {
      final replay = AcpEventFrameView(
        AcpUpdateEventView(
          AcpSessionNotificationView(
            sessionId: _remoteId,
            update: const AcpAgentMessageChunkView(
              AcpContentChunkView(content: AcpTextContentView(text: 'history')),
            ),
          ),
        ),
      );
      final ready = AcpEventFrameView(
        AcpReadyEventView(AcpNewSessionResponseView(sessionId: _remoteId)),
      );
      final source = ControlledAcpObservation([
        _accepted,
        replay,
        ready,
        _settled,
      ]);
      final port = _port()..sources.add(source);
      final client = AcpSessionClient(port: port);
      final observation = await client.open(_request);
      expect(source.reads, 0, reason: 'No producer or eager Settled wait');
      expect(port.calls.single.$2, same(_request));
      for (final frame in [_accepted, replay, ready, _settled]) {
        expect(await observation.next(), same(frame));
      }
      expect(port.calls.map((c) => c.$1), ['open']);
      await client.dispose();
    });

    test(
      'resident open has only Accepted and original Settled, no replay',
      () async {
        final resident = AcpAcceptedFrameView(
          target: _target,
          hasObservation: false,
        );
        final source = ControlledAcpObservation([resident, _settled])
          ..eof = true;
        final port = _port()..sources.add(source);
        final client = AcpSessionClient(port: port);
        final observation = await client.open(_request);
        expect(await observation.next(), same(resident));
        expect(await observation.next(), same(_settled));
        expect(await observation.next(), isNull);
        expect(port.calls.map((c) => c.$1), ['open']);
        await client.dispose();
      },
    );

    test('Busy rejects a second pending next without queueing or extra pull', () async {
      final source = ControlledAcpObservation();
      final port = _port()..sources.add(source);
      final client = AcpSessionClient(port: port);
      final observation = await client.open(_request);
      final first = observation.next();
      await source.enteredRead.future;
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
      expect(source.reads, 1);
      // Ignoring first would not cancel its Future. Explicit release wakes it.
      await observation.close();
      expect(await first, isNull);
      expect(source.closeSignals, 1);
      expect(source.closes, 1);
      expect(port.calls.map((c) => c.$1), ['open']);
      await client.dispose();
      expect(source.closes, 1);
    });

    test('gap, source error and EOF never close, interrupt, retry or complete a prompt', () async {
      const gap = AcpEventFrameView(
        AcpGapEventView(AcpObservationGapView.windowExceeded),
      );
      final source = ControlledAcpObservation([_accepted, gap]);
      final port = _port()..sources.add(source);
      final client = AcpSessionClient(port: port);
      final observation = await client.open(_request);
      expect(await observation.next(), same(_accepted));
      expect(await observation.next(), same(gap));
      const error = AcpCommandOutcomeUnknown(
        command: 'next',
        cause: 'disconnected',
      );
      source.readError = error;
      await expectLater(observation.next(), throwsA(same(error)));
      source.readError = null;
      source.eof = true;
      expect(await observation.next(), isNull);
      expect(source.closes, 0);
      expect(port.calls.map((c) => c.$1), ['open']);
      await client.dispose();
    });

    test(
      'all command requests and results retain product and SDK qualifications',
      () async {
        final port = _port();
        final client = AcpSessionClient(port: port);
        final content = <AcpContentBlockView>[
          const AcpTextContentView(text: 'hello'),
          const AcpImageContentView(data: 'AQ==', mimeType: 'image/png'),
          const AcpAudioContentView(data: 'Ag==', mimeType: 'audio/wav'),
          AcpResourceLinkView(
            name: 'file',
            uri: 'file:///a',
            size: BigInt.from(8),
          ),
          const AcpEmbeddedResourceView(
            resource: AcpTextResourceContentsView(
              uri: 'file:///b',
              text: 'source',
              mimeType: 'text/plain',
            ),
          ),
          const AcpEmbeddedResourceView(
            resource: AcpBlobResourceContentsView(
              uri: 'file:///c',
              blob: 'Aw==',
            ),
          ),
        ];
        final prompt = AcpPromptRequestView(target: _target, content: content);
        final replace = AcpReplaceRequestView(
          target: _target,
          run: _run,
          content: content,
        );
        final interrupt = AcpInterruptRequestView(target: _target, run: _run);
        const configId = AcpConfigId('config-not-permission');
        final configure = AcpConfigureRequestView(
          target: _target,
          configId: configId,
          value: const AcpBooleanConfigValueView(false),
        );
        final select = AcpConfigureRequestView(
          target: _target,
          configId: configId,
          value: const AcpSelectConfigValueView(AcpConfigValueId('false')),
        );
        final mode = AcpSetModeRequestView(
          target: _target,
          modeId: const AcpModeId('legacy'),
        );
        final answer = AcpPermissionAnswerRequestView(
          target: _target,
          permissionId: _permission,
          optionId: const AcpPermissionOptionId('permission-not-config'),
        );
        final cancelled = AcpPermissionAnswerRequestView(
          target: _target,
          permissionId: _permission,
        );
        final list = AcpListRequestView(
          target: _target,
          request: AcpListSessionsRequestView(
            cwd: '/workspace',
            cursor: 'opaque-cursor',
            meta: AcpJsonObject({'extension': const AcpJsonBool(true)}),
          ),
        );
        expect(await client.prompt(prompt), same(_run));
        expect(await client.replace(replace), same(_run));
        await client.interrupt(interrupt);
        await client.configure(configure);
        await client.configure(select);
        await client.setMode(mode);
        await client.answerPermission(answer);
        await client.answerPermission(cancelled);
        expect(await client.list(list), same(port.listValue));
        expect(await client.snapshot(_target), same(port.snapshotValue));
        expect(await client.closeMember(_target), same(port.closeValue));
        final expected = <(String, Object)>[
          ('prompt', prompt),
          ('replace', replace),
          ('interrupt', interrupt),
          ('configure', configure),
          ('configure', select),
          ('setMode', mode),
          ('answerPermission', answer),
          ('answerPermission', cancelled),
          ('list', list),
          ('snapshot', _target),
          ('closeMember', _target),
        ];
        expect(port.calls.length, expected.length);
        for (var i = 0; i < expected.length; i++) {
          expect(port.calls[i].$1, expected[i].$1);
          expect(port.calls[i].$2, same(expected[i].$2));
        }
        expect(_run.instance, isNot(_target.instance));
        expect(_permission.instance, isNot(_target.instance));
        expect(replace.run, same(_run));
        expect(answer.permissionId, same(_permission));
        expect(cancelled.optionId, isNull);
        expect(prompt.content, orderedEquals(content));
        content.clear();
        expect(
          prompt.content.length,
          6,
          reason: 'Immutable request retains original blocks',
        );
        await client.dispose();
      },
    );

    test('unknown command outcomes and typed failures propagate once without fallback', () async {
      final port = _port();
      final client = AcpSessionClient(port: port);
      const unknown = AcpCommandOutcomeUnknown(
        command: 'prompt',
        cause: 'lost response',
      );
      port.commandError = unknown;
      await expectLater(
        client.prompt(AcpPromptRequestView(target: _target, content: [])),
        throwsA(same(unknown)),
      );
      final failure = AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.unsupported,
        message: 'select unavailable',
      );
      port.commandError = failure;
      await expectLater(
        client.configure(
          AcpConfigureRequestView(
            target: _target,
            configId: const AcpConfigId('model'),
            value: const AcpSelectConfigValueView(AcpConfigValueId('x')),
          ),
        ),
        throwsA(same(failure)),
      );
      expect(port.calls.map((c) => c.$1), ['prompt', 'configure']);
      await client.dispose();
    });

    test('observer release and application dispose affect only their own resources', () async {
      final first = ControlledAcpObservation();
      final second = ControlledAcpObservation();
      final foreign = ControlledAcpObservation();
      final port = _port()..sources.addAll([first, second, foreign]);
      final client = AcpSessionClient(port: port);
      final other = AcpSessionClient(port: port);
      final one = await client.open(_request);
      final two = await client.open(_request);
      await other.open(_request);
      await one.close();
      expect(first.closes, 1);
      expect(second.closes, 0);
      expect(foreign.closes, 0);
      final read = two.next();
      await second.enteredRead.future;
      await client.dispose();
      expect(await read, isNull);
      expect(first.closes, 1);
      expect(second.closes, 1);
      expect(foreign.closes, 0);
      expect(
        () => client.snapshot(_target),
        throwsA(isA<AcpObservationDisposed>()),
      );
      await expectLater(
        client.open(_request),
        throwsA(isA<AcpObservationDisposed>()),
      );
      expect(port.calls.map((c) => c.$1), ['open', 'open', 'open']);
      await other.dispose();
      expect(foreign.closes, 1);
    });

    test('dispose joins a late open and real cleanup rather than cancelling Future', () async {
      final port = _port()..admission = Completer<AcpSessionObservationPort>();
      final source = ControlledAcpObservation()..cleanup = Completer<void>();
      final client = AcpSessionClient(port: port);
      final open = expectLater(
        client.open(_request),
        throwsA(isA<AcpObservationDisposed>()),
      );
      var disposed = false;
      final disposal = client.dispose().then((_) => disposed = true);
      expect(disposed, isFalse);
      port.admission!.complete(source);
      await open;
      expect(disposed, isFalse);
      source.cleanup!.complete();
      await disposal;
      expect(source.closes, 1);
      expect(port.calls.map((c) => c.$1), ['open']);
    });

    test(
      'failed initial cleanup does not skip a late observation release',
      () async {
        final error = StateError('first release failed');
        final first = ControlledAcpObservation()..cleanupError = error;
        final late = ControlledAcpObservation();
        final port = _port()..sources.add(first);
        final client = AcpSessionClient(port: port);
        await client.open(_request);
        port.admission = Completer<AcpSessionObservationPort>();
        final admission = expectLater(
          client.open(_request),
          throwsA(isA<AcpObservationDisposed>()),
        );
        final disposal = expectLater(client.dispose(), throwsA(same(error)));
        port.admission!.complete(late);
        await admission;
        await disposal;
        expect(first.closes, 1, reason: 'No implicit cleanup retry');
        expect(
          late.closes,
          1,
          reason: 'Late resource is released despite first failure',
        );
        first.cleanupError = null;
        await client.dispose();
        expect(first.closes, 2);
        expect(late.closes, 1);
        expect(port.calls.map((c) => c.$1), ['open', 'open']);
      },
    );

    test(
      'failed open admission settles disposal without inventing success',
      () async {
        final error = StateError('admission disconnected');
        final port = _port()
          ..admission = Completer<AcpSessionObservationPort>();
        final client = AcpSessionClient(port: port);
        final admission = expectLater(
          client.open(_request),
          throwsA(same(error)),
        );
        final disposal = client.dispose();
        port.admission!.completeError(error);
        await admission;
        await disposal;
        expect(port.calls.map((c) => c.$1), ['open']);
      },
    );

    test(
      'cleanup failure is retained and explicit dispose retries only release',
      () async {
        final error = StateError('release failed');
        final source = ControlledAcpObservation()..cleanupError = error;
        final port = _port()..sources.add(source);
        final client = AcpSessionClient(port: port);
        await client.open(_request);
        await expectLater(client.dispose(), throwsA(same(error)));
        expect(source.closes, 1);
        source.cleanupError = null;
        await client.dispose();
        expect(source.closes, 2);
        expect(source.closeSignals, 1);
        expect(port.calls.map((c) => c.$1), ['open']);
      },
    );

    test('AnyworkClient owns optional assembly and joins observation-only shutdown', () async {
      final source = ControlledAcpObservation();
      final port = _port()..sources.add(source);
      final app = AnyworkClient(
        transport: TestConversationTransport(),
        clientId: 'app',
        acpBusinessPort: port,
      );
      final observation = await app.acpSessions.open(_request);
      final read = observation.next();
      await source.enteredRead.future;
      expect((await app.close()).complete, isTrue);
      expect(await read, isNull);
      expect(source.closes, 1);
      expect(port.calls.map((c) => c.$1), ['open']);
      final native = AnyworkClient(
        transport: TestConversationTransport(),
        clientId: 'native',
      );
      expect(() => native.acpSessions, throwsUnsupportedError);
      expect((await native.close()).complete, isTrue);
    });

    test(
      'AnyworkClient reports and retries failed ACP observation cleanup',
      () async {
        final source = ControlledAcpObservation()
          ..cleanupError = StateError('cleanup');
        final port = _port()..sources.add(source);
        final app = AnyworkClient(
          transport: TestConversationTransport(),
          clientId: 'app',
          acpBusinessPort: port,
        );
        await app.acpSessions.open(_request);
        final report = await app.close();
        expect(report.complete, isFalse);
        expect(
          report.unresolved.map((e) => e.owner),
          contains('acp-observations'),
        );
        source.cleanupError = null;
        expect((await app.retryCleanup()).complete, isTrue);
        expect(source.closes, 2);
        expect(port.calls.map((c) => c.$1), ['open']);
      },
    );
  });
}
