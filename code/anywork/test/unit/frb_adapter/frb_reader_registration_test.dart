import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/chat.dart' as native;
import 'package:anywork/src/rust/api/studio/handlers/chat/timeline.dart'
    as timeline;
import 'package:anywork/src/rust/api/studio/types/chat.dart' as chat;
import 'package:anywork/src/rust/api/studio/types/error.dart' as wire;
import 'package:anywork/src/rust/api/studio/types/presentation.dart'
    as presentation;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/chat_fixtures.dart';

/// Supplies only native creation. Registration and all cleanup run real scopes.
final class _ReaderOpenApi implements RustLibApi {
  late Future<native.BridgeConversationFeed> Function(String) open;
  late timeline.BridgeCurrentReader currentReader;
  final requests = <String>[];

  @override
  Future<native.BridgeConversationFeed>
  crateApiStudioHandlersChatOpenConversationFeed({
    required String threadId,
    required chat.BridgeChatScope scope,
    required chat.BridgeReadDemand demand,
  }) {
    requests.add(threadId);
    return open(threadId);
  }

  @override
  Future<timeline.BridgeCurrentReader>
  crateApiStudioHandlersChatTimelineOpenCurrentReader({
    required String threadId,
    required int currentProtocolVersion,
    required chat.BridgeReadDemand demand,
  }) async => currentReader;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
}

final class _NativeFeed extends Fake implements native.BridgeConversationFeed {
  int identityReads = 0;
  int closeCalls = 0;
  int disposals = 0;
  bool failIdentity = false;
  bool failClose = false;
  @override
  String threadId() {
    identityReads++;
    if (failIdentity) throw StateError('identity getter failed');
    return 'thread';
  }

  @override
  String subscriptionId() => 'subscription';
  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    closeCalls++;
    if (failClose) throw _nativeFailure;
  }

  @override
  void dispose() => disposals++;
}

final class _NativeCurrent extends Fake
    implements timeline.BridgeCurrentReader {
  int closeCalls = 0;
  int disposals = 0;
  bool failClose = true;
  @override
  presentation.BridgeOpenCurrentReader metadata() =>
      throw StateError('metadata getter failed');
  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    closeCalls++;
    if (failClose) throw _nativeFailure;
  }

  @override
  void dispose() => disposals++;
}

const _nativeFailure = wire.BridgeError(
  code: wire.BridgeErrorCode.notFound,
  message: 'The isolated Thread does not exist',
  retryable: false,
  correlationId: 'reader-create-failure',
);

Matcher get _originalFailure => isA<StudioFailure>()
    .having((failure) => failure.code, 'code', StudioFailureCode.notFound)
    .having(
      (failure) => failure.correlationId,
      'correlationId',
      _nativeFailure.correlationId,
    )
    .having((failure) => failure.retryable, 'retryable', false);

void main() {
  late _ReaderOpenApi api;
  late FrbStudioTransport transport;
  late FrbRuntimeOwner runtime;
  late ClientScope root;
  late _NativeFeed handle;
  _NativeCurrent? currentHandle;
  ClientCloseBudget budget() => ClientCloseBudget(const Duration(seconds: 2));

  setUp(() {
    api = _ReaderOpenApi();
    RustLib.initMock(api: api);
    root = ClientScope(owner: 'reader-test');
    runtime = FrbRuntimeOwner(startupScope: root.child('startup'));
    runtime.debugOverrideInitialization(() async {});
    transport = FrbStudioTransport(
      runtime: runtime,
      contentScope: root.child('content'),
      progressScope: root.child('progress'),
    );
    handle = _NativeFeed();
    currentHandle = null;
    api.open = (_) async => handle;
  });

  tearDown(() async {
    handle.failClose = false;
    currentHandle?.failClose = false;
    await root.close(budget: budget());
    expect((await root.retryCleanup(budget: budget())).complete, isTrue);
    RustLib.dispose();
  });

  Future<ConversationFeed> open() => transport.openConversationFeed(
    'thread',
    scope: const ChatScope.conversation(),
    demand: chatDemand,
  );

  test(
    'external reporting declaration cannot authorize an unresolved lifecycle',
    () async {
      final feed = await open();
      handle.failClose = true;
      await expectLater(feed.close(), throwsA(_originalFailure));
      final rootReport = await root.close(budget: budget());
      expect(rootReport.complete, isFalse);
      expect(rootReport.unresolved.single.reason, _originalFailure);
      runtime.recordLifecycleCloseReport(rootReport);
      final result = await transport.shutdownRuntime(
        remainingMs: 1000,
        externalDartResourcesReported: true,
      );
      expect(result.shutdown.outcome, StudioShutdownOutcome.degraded);
      expect(
        result.shutdown.issues,
        contains(
          isA<StudioShutdownIssue>().having(
            (issue) => issue.code,
            'root confirmation gate',
            'lifecycleUnresolved',
          ),
        ),
      );
      expect(result.shutdown.allowsCleanExit, isFalse);
      expect(handle.closeCalls, 1);
      expect(handle.disposals, 0);
      await transport.finishShutdownDiagnostics();
      expect(RustLib.instance.initialized, isTrue);
      expect(handle.disposals, 0);
    },
  );

  test('default shutdown preserves a confirmed clean root outcome', () async {
    final rootReport = await root.close(budget: budget());
    expect(rootReport.complete, isTrue);
    runtime.recordLifecycleCloseReport(rootReport);
    final result = await transport.shutdownRuntime(remainingMs: 1000);
    expect(result.shutdown.outcome, StudioShutdownOutcome.notStarted);
    expect(result.shutdown.issues, isEmpty);
    expect(result.shutdown.allowsCleanExit, isTrue);
  });

  test('initialization is cached before its callback can reenter', () async {
    var calls = 0;
    late Future<void> reentrant;
    runtime.debugOverrideInitialization(() async {
      calls++;
      reentrant = runtime.ensureReady();
    });
    final initializing = runtime.ensureReady();
    await initializing;
    expect(reentrant, same(initializing));
    expect(calls, 1);
  });

  test(
    'exit sealed during initialization cannot start a native resource',
    () async {
      final gate = Completer<void>();
      runtime.debugOverrideInitialization(() => gate.future);
      final opening = open();
      final rejected = expectLater(
        opening,
        throwsA(isA<ClientResourceClosed>()),
      );
      transport.sealForShutdown();
      gate.complete();
      await rejected;
      expect(api.requests, isEmpty);
    },
  );

  test('failed creation preserves the original error without an empty retained owner', () async {
    api.open = (_) => Future.error(_nativeFailure);
    for (var index = 0; index < 3; index++) {
      await expectLater(open(), throwsA(_originalFailure));
    }
    expect(api.requests, ['thread', 'thread', 'thread']);
    expect((await root.close(budget: budget())).complete, isTrue);
    expect(handle.closeCalls, 0);
  });

  test(
    'closing during failed creation retains the creation until it settles',
    () async {
      final entered = Completer<void>();
      final result = Completer<native.BridgeConversationFeed>();
      api.open = (_) {
        entered.complete();
        return result.future;
      };
      final opening = open();
      await entered.future;
      final rejected = expectLater(
        opening,
        throwsA(isA<ClientResourceClosed>()),
      );
      expect(
        (await root.close(budget: ClientCloseBudget(Duration.zero))).complete,
        isFalse,
      );
      result.completeError(_nativeFailure);
      await rejected;
      expect((await root.close(budget: budget())).complete, isTrue);
      expect(handle.closeCalls, 0);
    },
  );

  test('late native handle is canceled without consulting identity or publishing it', () async {
    final entered = Completer<void>();
    final result = Completer<native.BridgeConversationFeed>();
    api.open = (_) {
      entered.complete();
      return result.future;
    };
    final opening = open();
    await entered.future;
    final rejected = expectLater(opening, throwsA(isA<ClientResourceClosed>()));
    expect(
      (await root.close(budget: ClientCloseBudget(Duration.zero))).complete,
      isFalse,
    );
    result.complete(handle);
    await rejected;
    expect((await root.close(budget: budget())).complete, isTrue);
    expect(handle.identityReads, 0);
    expect(handle.closeCalls, 1);
    expect(handle.disposals, 1);
  });

  test('identity failure after creation keeps the same raw handle for cleanup retry', () async {
    handle.failIdentity = true;
    handle.failClose = true;
    await expectLater(open(), throwsA(isA<StudioFailure>()));
    final report = await root.close(budget: budget());
    expect(report.unresolved, hasLength(1));
    expect(report.unresolved.single.reason, _originalFailure);
    expect(report.unresolved.single.resourceId, isNotNull);
    expect(handle.closeCalls, 1);
    expect(handle.disposals, 0);
    handle.failClose = false;
    expect((await root.retryCleanup(budget: budget())).complete, isTrue);
    expect(handle.closeCalls, 2);
    expect(handle.disposals, 1);
    expect(api.requests, ['thread']);
  });

  test(
    'conversation close caches failure until explicit cleanup retry',
    () async {
      final feed = await open();
      handle.failClose = true;
      await expectLater(feed.close(), throwsA(_originalFailure));
      await expectLater(feed.close(), throwsA(_originalFailure));
      expect(handle.closeCalls, 1);
      handle.failClose = false;
      expect((await root.retryCleanup(budget: budget())).complete, isTrue);
      expect(handle.closeCalls, 2);
      expect(handle.disposals, 1);
    },
  );

  test('Current metadata failure occurs after raw entry takeover', () async {
    final native = currentHandle = _NativeCurrent();
    api.currentReader = native;
    await expectLater(
      transport.openCurrentReader(
        'thread',
        currentProtocolVersion: currentProtocolVersion,
        demand: chatDemand,
      ),
      throwsA(isA<StudioFailure>()),
    );
    final report = await root.close(budget: budget());
    expect(report.unresolved, hasLength(1));
    expect(native.closeCalls, 1);
    expect(native.disposals, 0);
    native.failClose = false;
    expect((await root.retryCleanup(budget: budget())).complete, isTrue);
    expect(native.closeCalls, 2);
    expect(native.disposals, 1);
  });
}
