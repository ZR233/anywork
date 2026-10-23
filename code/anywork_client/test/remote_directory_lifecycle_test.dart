import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/remote_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:test/test.dart';

const _cancelled = TypeMatcher<StudioFailure>();
const _closeFailure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'Native cursor close unavailable',
  retryable: true,
  correlationId: 'original-cursor-close',
);

final class _OpenRequest {
  _OpenRequest(this.alias, this.path, this.cursor);
  final String alias;
  final String? path;
  final String? cursor;
  final reply = Completer<RemoteDirectoryReadConnection>();
}

/// The fake supplies native pages and real pending cleanup receipts. Cursor
/// ownership, continuation and late-result policy are the production Repo's.
final class _DirectoryPort implements RemotePort {
  final opened = <_OpenRequest>[];
  final closed = <(String, String)>[];
  Completer<_OpenRequest>? _nextOpen;
  Completer<(String, String)>? _nextClose;
  Completer<void>? cursorCloseReceipt;
  StudioFailure? closeFailure;

  Future<_OpenRequest> expectOpen() {
    if (_nextOpen != null) throw StateError('An open waiter already exists');
    final result = Completer<_OpenRequest>();
    _nextOpen = result;
    return result.future;
  }

  Future<(String, String)> expectCursorClose() {
    if (_nextClose != null) throw StateError('A cursor-close waiter already exists');
    final result = Completer<(String, String)>();
    _nextClose = result;
    return result.future;
  }

  @override
  Future<RemoteDirectoryReadConnection> openDirectory(
    String alias, {
    String? path,
    String? cursor,
  }) {
    final request = _OpenRequest(alias, path, cursor);
    opened.add(request);
    final waiter = _nextOpen;
    _nextOpen = null;
    waiter?.complete(request);
    return request.reply.future;
  }

  @override
  Future<void> closeDirectory(String alias, String cursor) async {
    closed.add((alias, cursor));
    final waiter = _nextClose;
    _nextClose = null;
    waiter?.complete((alias, cursor));
    if (closeFailure case final error?) throw error;
    await cursorCloseReceipt?.future;
  }

  @override
  Future<List<SshServerRuntimeEntry>> reloadServers() =>
      throw UnsupportedError('Unexpected server reload');
  @override
  Future<SshServerRuntimeEntry> save(SshServerProfile profile, SshPasswordUpdate password) =>
      throw UnsupportedError('Unexpected SSH save');
  @override
  Future<void> delete(String alias) => throw UnsupportedError('Unexpected SSH delete');
  @override
  Future<SshConnectionSnapshot> authenticate(String alias, String password, {
    required bool rememberPassword,
  }) => throw UnsupportedError('Unexpected SSH authentication');
  @override
  Future<SshConnectionSnapshot> test(String alias) =>
      throw UnsupportedError('Unexpected SSH test');
  @override
  Future<SshConnectionSnapshot> reconnect(String alias) =>
      throw UnsupportedError('Unexpected SSH reconnect');
}

/// Pins one synthetic native page. Its offset only indexes that page; it does
/// not implement remote continuation or replace any production query behavior.
final class _DirectoryPage implements RemoteDirectoryReadConnection {
  _DirectoryPage(this.scopeId, this.cursor, this.names);
  final String scopeId;
  final String? cursor;
  final List<String> names;
  final offsets = <int>[];
  int closeCalls = 0;
  bool closeRequested = false;

  void _ensureReadable() {
    if (closeRequested) {
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'Native page is sealed',
        retryable: false,
        correlationId: 'page-sealed',
      );
    }
  }

  @override
  Future<RemoteDirectoryReadHeader> header() async {
    _ensureReadable();
    return RemoteDirectoryReadHeader(
      scopeId: scopeId,
      path: const ReadText.inline(text: '/workspace'),
      parent: const ReadText.inline(text: '/'),
      // Deferred on purpose: late cleanup must retain the original readable
      // scope until its cursor has actually been recovered and handed off.
      nextCursor: cursor == null ? null : ReadText.deferred(
        fieldId: 101, utf8Bytes: utf8.encode(cursor!).length,
      ),
      pageEntryCount: names.length,
    );
  }

  @override
  Future<RemoteDirectoryEntryPage> entries({int offset = 0, int limit = 32}) async {
    _ensureReadable();
    offsets.add(offset);
    final end = (offset + limit).clamp(0, names.length);
    return RemoteDirectoryEntryPage(
      scopeId: scopeId,
      offset: offset,
      items: [
        for (final name in names.sublist(offset, end))
          RemoteDirectoryEntryRead(
            name: ReadText.inline(text: name),
            path: ReadText.inline(text: '/workspace/$name'),
            isDirectory: true,
            isSymlink: false,
          ),
      ],
      nextOffset: end < names.length ? end : null,
    );
  }

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) async {
    _ensureReadable();
    if (fieldId != 101 || offset != 0 || cursor == null ||
        utf8.encode(cursor!).length > maxBytes) {
      throw StateError('Unexpected native-page text request');
    }
    return TextChunk(fieldId: fieldId, offset: offset, text: cursor!, nextOffset: null);
  }

  @override
  void requestClose() => closeRequested = true;
  @override
  Future<FeedCloseReport> close() async {
    closeCalls++;
    requestClose();
    return FeedCloseReport(feedId: scopeId, outcome: const FeedCloseOutcome.clean());
  }
  @override
  Future<FeedCloseReport> retryClose() => close();
}

({RemoteRepository repository, ResourceBudget budget}) _remote(_DirectoryPort port) {
  final budget = ResourceBudget();
  return (
    repository: createRemoteRepository(
      port: port,
      budget: budget,
      operations: OperationRegistry(clientId: 'remote-directory', budget: budget),
    ),
    budget: budget,
  );
}

void main() {
  test('repository close joins a late native cursor and its actual close receipt', () async {
    final port = _DirectoryPort();
    final owner = _remote(port);
    final requested = port.expectOpen();
    final opening = owner.repository.openDirectory('host');
    final openingRejected = expectLater(opening, throwsA(
      _cancelled.having((failure) => failure.code, 'code', StudioFailureCode.cancelled),
    ));
    final request = await requested;
    final closeEntered = port.expectCursorClose();
    port.cursorCloseReceipt = Completer<void>();
    var closed = false;
    final closing = owner.repository.close().then((report) {
      closed = true;
      return report;
    });
    expect(() => owner.repository.openDirectory('other'), throwsA(
      _cancelled.having((failure) => failure.code, 'code', StudioFailureCode.cancelled),
    ));
    final page = _DirectoryPage('late-page', 'late-cursor', const ['unpublished']);
    request.reply.complete(page);
    await openingRejected;
    expect(await closeEntered, ('host', 'late-cursor'));
    expect(closed, isFalse, reason: 'Requesting cursor close is not its receipt');
    expect(page.closeCalls, 1);
    expect(owner.budget.used(ResourceKind.readModel), greaterThan(0));
    port.cursorCloseReceipt!.complete();
    expect((await closing).complete, isTrue);
    expect(closed, isTrue);
    expect(port.closed, [('host', 'late-cursor')]);
    expect(port.opened, hasLength(1), reason: 'Unknown/late opening is never replayed');
    expect(owner.budget.used(ResourceKind.readModel), 0);
  });

  test('native continuation replaces the page and failed cursor ownership survives final close and retry', () async {
    final port = _DirectoryPort();
    final owner = _remote(port);
    final firstRequested = port.expectOpen();
    final opening = owner.repository.openDirectory('host', path: '/workspace');
    final firstRequest = await firstRequested;
    final first = _DirectoryPage('first-page', 'first-cursor', const ['alpha']);
    firstRequest.reply.complete(first);
    final query = await opening;
    final nextRequested = port.expectOpen();
    final next = query.loadMore();
    final nextRequest = await nextRequested;
    expect((nextRequest.alias, nextRequest.path, nextRequest.cursor),
        ('host', '/workspace', 'first-cursor'));
    final second = _DirectoryPage('second-page', 'second-cursor', const ['beta']);
    nextRequest.reply.complete(second);
    await next;
    expect(query.state.value.entries.map((entry) => entry.name), ['beta'],
        reason: 'A native continuation replaces the current page, not a full scan');
    expect(query.state.value.nextCursor, 'second-cursor');
    expect(first.offsets, [0]);
    expect(second.offsets, [0], reason: 'Offsets only materialize each native page');
    expect(first.closeCalls, 1);
    expect(second.closeCalls, 1);
    port.closeFailure = _closeFailure;
    final failed = await query.close();
    expect(failed.complete, isFalse);
    expect(failed.unresolved.expand((entry) => entry.issues), contains(
      const FeedCloseIssue(
        diagnostic: StudioShutdownIssue(
          stage: 'remote-directory-cursor',
          code: 'unavailable',
          message: 'Native cursor close unavailable',
          retryable: true,
          correlationId: 'original-cursor-close',
        ),
        recovery: CleanupRecovery.retryClose,
      ),
    ));
    expect(owner.budget.used(ResourceKind.readModel), greaterThan(0));
    expect(port.closed, [('host', 'second-cursor')]);
    expect((await owner.repository.close()).complete, isFalse);
    port.closeFailure = null;
    expect((await owner.repository.retryCleanup()).complete, isTrue,
        reason: 'Completed Unresolved must not permanently cache its old Future');
    expect(port.closed, [
      ('host', 'second-cursor'),
      ('host', 'second-cursor'),
      ('host', 'second-cursor'),
    ]);
    expect(port.opened, hasLength(2), reason: 'Cleanup never browses the directory again');
    expect(owner.budget.used(ResourceKind.readModel), 0);
  });

  test('a closing query hands off its late continuation cursor without publishing the new page', () async {
    final port = _DirectoryPort();
    final owner = _remote(port);
    final requested = port.expectOpen();
    final opening = owner.repository.openDirectory('host');
    (await requested).reply.complete(_DirectoryPage('first', 'old-cursor', const ['old']));
    final query = await opening;
    final seen = <RemoteDirectoryState>[];
    final observation = query.state.watchLatest(seen.add);
    final nextRequested = port.expectOpen();
    final next = query.loadMore();
    final nextRejected = expectLater(next, throwsA(
      _cancelled.having((failure) => failure.code, 'code', StudioFailureCode.cancelled),
    ));
    final nextRequest = await nextRequested;
    query.requestClose();
    expect(observation.observation.isCancelled, isTrue);
    final cursorCloseEntered = port.expectCursorClose();
    port.cursorCloseReceipt = Completer<void>();
    final closing = owner.repository.close();
    nextRequest.reply.complete(_DirectoryPage('late-next', 'new-cursor', const ['late']));
    await nextRejected;
    expect(await cursorCloseEntered, ('host', 'new-cursor'));
    expect(seen.every((state) => state.entries.every((entry) => entry.name != 'late')), isTrue);
    expect(port.closed, [('host', 'new-cursor')],
        reason: 'The consumed old cursor is replaced even when the page is no longer visible');
    port.cursorCloseReceipt!.complete();
    expect((await closing).complete, isTrue);
    expect(owner.budget.used(ResourceKind.readModel), 0);
  });
}
