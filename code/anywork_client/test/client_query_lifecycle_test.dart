import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class _QueryTransport implements StudioTransport {
  final entered = Completer<void>();
  final reply = Completer<Uint8List>();
  int calls = 0;
  void Function()? onRead;

  @override
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId) {
    calls++;
    entered.complete();
    onRead?.call();
    return reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unused query capability: ${invocation.memberName}',
  );
}

void main() {
  test(
    'synchronous transport reentry cannot escape the query close join',
    () async {
      final transport = _QueryTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'query-reentry',
      );
      late Future<CloseReport> closing;
      transport.onRead = () {
        closing = client.close(deadline: DateTime.utc(2000));
      };
      final reading = client.readAttachmentBytes('thread', 'attachment');
      final report = await closing;
      expect(report.unresolved.any((item) => item.owner == 'queries'), isTrue);
      transport.reply.complete(Uint8List(0));
      await reading;
      expect((await client.retryCleanup()).complete, isTrue);
    },
  );

  test(
    'close retains admitted query and rejects new queries until actual reply',
    () async {
      final transport = _QueryTransport();
      final client = AnyworkClient(
        transport: transport,
        clientId: 'query-close',
      );
      final reading = client.readAttachmentBytes('thread', 'attachment');
      await transport.entered.future;
      expect(client.budget.used(ResourceKind.pendingOperation), 1);
      final closing = client.close(deadline: DateTime.utc(2000));
      expect(
        identical(closing, client.close(deadline: DateTime.utc(2100))),
        isTrue,
      );
      final report = await closing;
      expect(report.unresolved.any((item) => item.owner == 'queries'), isTrue);
      expect(client.budget.used(ResourceKind.pendingOperation), 1);
      await expectLater(
        client.readAttachmentBytes('thread', 'late'),
        throwsStateError,
      );
      expect(transport.calls, 1);
      transport.reply.complete(Uint8List.fromList([7]));
      expect(await reading, [7]);
      expect((await client.retryCleanup()).complete, isTrue);
      expect(client.budget.usage, isEmpty);
    },
  );
}
