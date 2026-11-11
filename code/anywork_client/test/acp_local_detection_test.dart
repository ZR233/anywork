import 'dart:async';

import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

import 'support/accounts_test_runtime.dart';

final class _DetectionTransport extends AccountsTestTransport {
  final starts = <OperationId>[];
  final cancels = <OperationId>[];
  Completer<AcpLocalDetectionCommandReply>? pending;
  Object? startFailure;
  int revision = 0;

  AcpLocalDetectionCommandReply reply(
    OperationId operation, {
    String? target,
    AcpLocalDetectionPhaseView state = AcpLocalDetectionPhaseView.checking,
  }) {
    revision++;
    final snapshot = AcpLocalDetectionSnapshotView(
      revision: revision,
      operationId: target ?? operation.value,
      state: state,
    );
    return AcpLocalDetectionCommandReply(
      receipt: StudioCommandReceipt(
        operationId: operation,
        disposition: CommitDisposition.applied,
        targets: [testStamp('acp-local-detection', revision, epoch: epoch)],
        effect: EffectPoint.immediate,
        effective: true,
        durable: false,
      ),
      snapshot: snapshot,
    );
  }

  @override
  Future<AcpLocalDetectionCommandReply> startAcpLocalDetection({
    required OperationId operationId,
  }) async {
    starts.add(operationId);
    if (startFailure case final failure?) throw failure;
    return pending?.future ?? reply(operationId);
  }

  @override
  Future<AcpLocalDetectionCommandReply> cancelAcpLocalDetection({
    required OperationId operationId,
    required OperationId targetOperationId,
  }) async {
    cancels.add(targetOperationId);
    return reply(
      operationId,
      target: targetOperationId.value,
      state: AcpLocalDetectionPhaseView.cancelling,
    );
  }
}

AccountsTestRuntime _client(_DetectionTransport transport) {
  final client = AccountsTestRuntime(transport);
  addTearDown(client.close);
  return client;
}

void main() {
  test('closing the Client joins an admitted detection request before reporting completion', () async {
    final transport = _DetectionTransport()..pending = Completer();
    final client = _client(transport);
    final request = client.domains.acp.startLocalDetection(
      const OperationId('joining'),
    );
    await Future<void>(() {});
    var closed = false;
    final closing = client.domains.close(
      deadline: DateTime.now().add(const Duration(seconds: 2)),
    );
    unawaited(
      closing.then((_) {
        closed = true;
      }),
    );
    await Future<void>(() {});
    expect(closed, isFalse);
    transport.pending!.complete(transport.reply(const OperationId('joining')));
    await request;
    expect((await closing).unresolved, isEmpty);
    expect(closed, isTrue);
  });

  test('read and shared observation never start detection; revision zero is a baseline', () async {
    final transport = _DetectionTransport();
    final client = _client(transport);
    expect(client.domains.acp.localDetection.value.value, isNull);
    final first = client.domains.acp.observeLocalDetection();
    final second = client.domains.acp.observeLocalDetection();
    await transport.attachedAccount(const AcpLocalDetectionTarget());
    final baseline = const AcpLocalDetectionSnapshotView.idle();
    transport.emitAccount(
      AcpLocalDetectionFrame(testStamp('acp-local-detection', 0), baseline),
    );
    await client.domains.acp.localDetection.waitFor((value) => value.loaded);
    expect(client.domains.acp.localDetection.value.value, same(baseline));
    expect(transport.starts, isEmpty);
    await first.release();
    expect(
      transport.observations[const AcpLocalDetectionTarget()],
      hasLength(1),
    );
    await second.release();
  });

  test('commands and events reduce the same Host snapshot; older receipt cannot overwrite a terminal event', () async {
    final transport = _DetectionTransport()..pending = Completer();
    final client = _client(transport);
    final request = client.domains.acp.startLocalDetection(
      const OperationId('probe'),
    );
    await Future<void>(() {});
    final terminal = AcpLocalDetectionSnapshotView(
      revision: 3,
      operationId: 'probe',
      state: AcpLocalDetectionPhaseView.available,
      program: '/tools/agy',
      version: '1.2.3',
    );
    client.domains.acceptFrame(
      AcpLocalDetectionFrame(testStamp('acp-local-detection', 3), terminal),
    );
    transport.pending!.complete(transport.reply(const OperationId('probe')));
    await request;
    expect(client.domains.acp.localDetection.value.value, same(terminal));
    expect(client.domains.acp.auth.value.value, isNull);
    final reply = await client.domains.acp.cancelLocalDetection(
      operationId: const OperationId('cancel'),
      targetOperationId: const OperationId('probe'),
    );
    expect(transport.cancels, [const OperationId('probe')]);
    expect(reply.snapshot.state, AcpLocalDetectionPhaseView.cancelling);
    expect(transport.starts, [const OperationId('probe')]);
  });

  test(
    'unknown detection result is exposed once without implicit resend',
    () async {
      final failure = StateError('reply lost');
      final transport = _DetectionTransport()..startFailure = failure;
      final client = _client(transport);
      await expectLater(
        client.domains.acp.startLocalDetection(const OperationId('unknown')),
        throwsA(same(failure)),
      );
      expect(transport.starts, [const OperationId('unknown')]);
      expect(client.domains.acp.localDetection.value.value, isNull);
      transport.startFailure = null;
      await client.domains.acp.startLocalDetection(
        const OperationId('explicit-new'),
      );
      expect(transport.starts, [
        const OperationId('unknown'),
        const OperationId('explicit-new'),
      ]);
    },
  );

  test('owner replacement rejects a late reply and leaves the current observation intact', () async {
    final transport = _DetectionTransport()..pending = Completer();
    final client = _client(transport);
    final request = client.domains.acp.startLocalDetection(
      const OperationId('old'),
    );
    final failure = expectLater(
      request,
      throwsA(isA<SettingsWriteOwnerChanged>()),
    );
    await Future<void>(() {});
    final reply = transport.reply(const OperationId('old'));
    client.domains.adoptOwnerEpoch('next');
    final current = AcpLocalDetectionSnapshotView(
      revision: 0,
      operationId: 'new',
      state: AcpLocalDetectionPhaseView.missing,
    );
    client.domains.acceptFrame(
      AcpLocalDetectionFrame(
        testStamp('acp-local-detection', 0, epoch: 'next'),
        current,
      ),
    );
    transport.pending!.complete(reply);
    await failure;
    expect(client.domains.acp.localDetection.value.value, same(current));
  });
}
