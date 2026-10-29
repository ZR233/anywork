import 'dart:async';

import 'package:anywork/src/infrastructure/frb/studio_api.dart';
import 'package:anywork/src/rust/api/studio/handlers/history/timeline_reader.dart'
    as native;
import 'package:anywork/src/rust/api/studio/types/error.dart' as wire;
import 'package:anywork/src/rust/frb_generated.dart' show RustLib, RustLibApi;
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supplies only the generated native creation boundary; the real transport
/// owns registration, late creation, cancellation and forgetting.
final class _ReaderOpenApi implements RustLibApi {
  late Future<native.BridgeTimelineReader> Function(String) open;
  final requests = <String>[];

  @override
  Future<native.BridgeTimelineReader>
  crateApiStudioHandlersHistoryTimelineReaderOpenTimelineReader({
    required String threadId,
  }) {
    requests.add(threadId);
    return open(threadId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected ${invocation.memberName}');
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

  setUp(() {
    api = _ReaderOpenApi();
    RustLib.initMock(api: api);
    FrbStudioTransport.debugOverrideInitialization(() async {});
    transport = FrbStudioTransport();
  });

  tearDown(() async {
    // Red runs must also release their empty registrations before the next case.
    await transport.cancelDartSubscriptions(budgetMs: 1000);
    FrbStudioTransport.debugOverrideInitialization(null);
    RustLib.dispose();
  });

  test(
    'failed reader creation leaves no empty registrations before shutdown',
    () async {
      api.open = (_) => Future.error(_nativeFailure);
      for (var index = 0; index < 3; index++) {
        await expectLater(
          transport.openHistoryReader('missing-$index'),
          throwsA(_originalFailure),
        );
      }
      expect(api.requests, ['missing-0', 'missing-1', 'missing-2']);
      // The existing initialization override rejects any still-owned registration.
      // Use that guard before cancelDartSubscriptions, not a newly exposed counter
      // or shutdown silently removing the leaked entries for this assertion.
      expect(
        () => FrbStudioTransport.debugOverrideInitialization(() async {}),
        returnsNormally,
      );
    },
  );

  test(
    'close retains a creating reader until its native failure settles',
    () async {
      final entered = Completer<void>();
      final result = Completer<native.BridgeTimelineReader>();
      api.open = (_) {
        entered.complete();
        return result.future;
      };
      final opening = transport.openHistoryReader('late-missing');
      final rejected = expectLater(opening, throwsA(_originalFailure));
      await entered.future;
      var closed = false;
      final closing = transport.cancelDartSubscriptions(budgetMs: 10000).then((
        issues,
      ) {
        closed = true;
        return issues;
      });
      await Future<void>.value();
      expect(
        closed,
        isFalse,
        reason: 'native creation still owns its registration',
      );
      result.completeError(_nativeFailure);
      await rejected;
      expect(await closing, isEmpty);
      expect(closed, isTrue);
      expect(
        () => FrbStudioTransport.debugOverrideInitialization(() async {}),
        returnsNormally,
      );
    },
  );
}
