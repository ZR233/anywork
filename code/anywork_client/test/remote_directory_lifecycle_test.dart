import 'dart:async';

import 'package:anywork_client/studio_client.dart';
import 'package:test/test.dart';

final class DirectoryTransport implements StudioTransport {
  final pending = <Completer<RemoteDirectoryListing>>[];
  final closed = <(String, String)>[];
  Completer<void>? closeReceipt;
  bool failClose = false;
  @override
  Future<RemoteDirectoryListing> browseRemoteDirectories(
    String alias, {
    String? path,
    String? cursor,
  }) {
    final result = Completer<RemoteDirectoryListing>();
    pending.add(result);
    return result.future;
  }

  @override
  Future<void> closeRemoteDirectory(String alias, String cursor) async {
    closed.add((alias, cursor));
    if (failClose) throw StateError('close unavailable');
    await closeReceipt?.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

RemoteDirectoryListing page(String? cursor) => RemoteDirectoryListing(
  path: '/workspace',
  entries: const [],
  nextCursor: cursor,
);

void main() {
  test(
    'client close joins a late directory and its actual close receipt',
    () async {
      final transport = DirectoryTransport();
      final remote = RemoteActions(transport);
      final opening = remote.browseRemoteDirectories('host');
      var closed = false;
      final closing = remote.close().then((_) => closed = true);
      transport.closeReceipt = Completer<void>();
      transport.pending.single.complete(page('cursor'));
      await opening;
      expect(closed, isFalse);
      await Future<void>.value();
      expect(transport.closed, [('host', 'cursor')]);
      transport.closeReceipt!.complete();
      await closing;
      expect(closed, isTrue);
    },
  );
  test(
    'continuation replaces ownership and failure retains it for final close',
    () async {
      final transport = DirectoryTransport();
      final remote = RemoteActions(transport);
      final initial = remote.browseRemoteDirectories('host');
      transport.pending.last.complete(page('first'));
      await initial;
      final next = remote.browseRemoteDirectories(
        'host',
        path: '/workspace',
        cursor: 'first',
      );
      transport.pending.last.complete(page('second'));
      await next;
      transport.failClose = true;
      await expectLater(
        remote.closeRemoteDirectory('host', 'second'),
        throwsStateError,
      );
      transport.failClose = false;
      await remote.close();
      expect(transport.closed, [('host', 'second'), ('host', 'second')]);
    },
  );
}
