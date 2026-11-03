import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/features/conversation/timeline/view_models/conversation_current_owner.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:anywork_client/src/conversation/data/conversation_read_scope.dart';
import 'package:anywork_client/src/lifecycle/resource_budget.dart';
import 'package:anywork_client/src/observation/latest_value.dart';
import 'package:flutter_test/flutter_test.dart';

// The current UI consumes typed live atoms, not Turn Children, preview or
// collection heuristics. Its window/Deferred/ABA assertions now live in
// atomic_current_connector_test.dart. Keep the original owner's real SDK join
// and retry proofs here; genuine Children retain their own component tests.
ContentRef _reference({int revision = 1}) => ContentRef(
  databaseId: 'database',
  target: BodyContentTarget(
    owner: CurrentContentOwner(
      domain: 'execution',
      id: 'current-document',
      revision: revision,
    ),
    key: 'body',
  ),
);
ContentWindow _window(String text, {int offset = 0, int available = 100000}) =>
    ContentWindow(
      offset: offset,
      bytes: utf8.encode(text),
      generation: 'g1',
      availableThrough: available,
      sealed: false,
    );

void main() {
  test('owner close joins real SDK scopes retired during an existing join', () async {
    final content = _RealScopeContent();
    final owner = ConversationCurrentOwner(content);
    owner.synchronizeSources([
      CurrentWindowSource(id: 'body', reference: _reference(), text: ''),
    ]);
    final original = owner.queryScope;
    final collection = CurrentCollectionRef(
      databaseId: 'database',
      collection: 'tools',
      revision: 1,
    );
    const demand = ReadDemand(maxItems: 1, maxBytes: 64 * 1024);
    Future<void> page(ConversationQueryScope scope) => scope
        .pageCurrent(reference: collection, demand: demand)
        .then<void>(
          (_) => fail('A retired SDK scope must not admit its page'),
          onError: (Object error) =>
              expect(error, isA<StaleConversationScope>()),
        );
    content.reader.watch.events.add(_window('first'));
    await Future<void>.delayed(Duration.zero);
    final observed = owner.windows.single;
    final first = page(original);
    owner.nextWindow(observed);
    expect(original.isActive, isFalse);
    await content.reader.watch.closed.future;
    // Flush the SDK cancellation chain: the old join now waits inside the real
    // scope.close on its still-pending page, after taking its scope snapshot.
    await Future<void>.delayed(Duration.zero);
    final replacement = owner.queryScope;
    final second = page(replacement);
    expect(replacement.pendingQueries, 1);
    var closeReturned = false;
    late int pendingWhenCloseReturned;
    late int permitsWhenCloseReturned;
    final closing = owner.close();
    final observedClose = closing.then((_) {
      closeReturned = true;
      pendingWhenCloseReturned = content.scopes.fold<int>(
        0,
        (sum, scope) => sum + scope.pendingQueries,
      );
      permitsWhenCloseReturned = content.budget.used(
        ResourceKind.pendingOperation,
      );
    });
    expect(
      owner.close(),
      same(closing),
      reason: 'Callers share the actual in-flight join',
    );
    expect(replacement.isActive, isFalse);
    expect(() => owner.queryScope, throwsA(isA<StaleConversationScope>()));
    content.reader.requests.first.complete(
      CurrentCollectionPage(revision: 1, entries: const []),
    );
    await first;
    await Future<void>.delayed(Duration.zero);
    final returnedBeforeReplacementIO = closeReturned;
    final pendingBeforeReplacementIO = replacement.pendingQueries;
    final permitsBeforeReplacementIO = content.budget.used(
      ResourceKind.pendingOperation,
    );
    // Always release independent IO before asserting the recorded early-return
    // observation, so the red test also leaves no pending operations behind.
    content.reader.requests.last.complete(
      CurrentCollectionPage(revision: 1, entries: const []),
    );
    await second;
    await observedClose;
    await replacement.close();
    owner.dispose();
    await content.reader.watch.events.close();
    expect(
      returnedBeforeReplacementIO,
      isFalse,
      reason:
          'Owner close must also join scopes retired after the old snapshot',
    );
    expect((pendingBeforeReplacementIO, permitsBeforeReplacementIO), (1, 1));
    expect((pendingWhenCloseReturned, permitsWhenCloseReturned), (0, 0));
    expect(owner.cleanupError, isNull);
  });

  test(
    'owner close leaves failures for explicit retry without looping',
    () async {
      final content = _Content();
      final owner = ConversationCurrentOwner(content);
      owner.synchronizeSources([
        CurrentWindowSource(id: 'body', reference: _reference(), text: ''),
      ]);
      final original = content.scopes.single;
      original.closeFailure = StateError('native close failed');
      await owner.close();
      expect(original.closeCalls, 1);
      expect(original.closed, isFalse);
      expect(owner.cleanupError, isA<CloseReport>());
      original.closeFailure = null;
      await owner.close();
      expect(original.closeCalls, 2);
      expect(original.closed, isTrue);
      owner.dispose();
      await original.watches.single.close();
    },
  );
}

final class _RealScopeContent implements ConversationContent {
  final source = LatestValue<ChatUiState<bool>>(
    const ChatReady<bool>('thread', true),
  );
  final reader = _RealScopeReader();
  final budget = ResourceBudget();
  final scopes = <ConversationReadScope>[];

  @override
  ValueObservation<ChatUiState<bool>> get state => source;
  @override
  AttemptId get currentAttemptId => const AttemptId(1);
  @override
  bool get isClosed => false;
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = ConversationReadScope(
      threadId: 'thread',
      generation: generation,
      reader: reader,
      budget: budget,
      isEligible: () => true,
      applyOlder: (_) async {},
    );
    scopes.add(scope);
    return scope;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

final class _RealScopeReader implements ConversationReader {
  final watch = _RealScopeWatch();
  final requests = <Completer<CurrentCollectionPage>>[];

  @override
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) => watch;
  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) {
    final request = Completer<CurrentCollectionPage>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

final class _RealScopeWatch implements ConversationContentWatch {
  final events = StreamController<ContentWindow>();
  final closed = Completer<void>();

  @override
  Stream<ContentWindow> get windows => events.stream;
  @override
  void requestClose() {}
  @override
  Future<void> close() async {
    if (!closed.isCompleted) closed.complete();
  }
}

final class _Content implements ConversationContent {
  final source = LatestValue<ChatUiState<bool>>(
    const ChatReady<bool>('thread', true),
  );
  final projection = LatestValue<CurrentProjection?>(null);
  final scopes = <_Scope>[];
  AttemptId attempt = const AttemptId(1);
  Future<CurrentCollectionPage> Function(
    CurrentCollectionRef,
    String?,
    ReadDemand,
  )?
  onPage;
  Future<ContentWindow> Function(ContentRef, ContentRange)? onRead;
  @override
  String get threadId => 'thread';
  @override
  ValueObservation<ChatUiState<bool>> get state => source;
  @override
  ValueObservation<CurrentProjection?> get current => projection;
  @override
  bool get hasDemand => true;
  @override
  bool get isClosed => false;
  @override
  AttemptId get currentAttemptId => attempt;
  @override
  int get ownedAttemptCount => 1;
  @override
  Future<void> get ready async {}
  @override
  Observation attachConsumer(
    ConversationBatchConsumer consumer, {
    required ReadDemand demand,
  }) => throw UnimplementedError();
  @override
  ConversationQueryScope openScope({required int generation}) {
    final scope = _Scope(generation, onPage: onPage, onRead: onRead);
    scopes.add(scope);
    return scope;
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async => CloseReport();
  @override
  Future<CloseReport> joinRetired({DateTime? deadline}) async => CloseReport();
  @override
  void refresh() {}
}

final class _Scope implements ConversationQueryScope {
  _Scope(this.generation, {this.onPage, this.onRead});
  final Future<CurrentCollectionPage> Function(
    CurrentCollectionRef,
    String?,
    ReadDemand,
  )?
  onPage;
  final Future<ContentWindow> Function(ContentRef, ContentRange)? onRead;
  @override
  final int generation;
  @override
  String get threadId => 'thread';
  @override
  int get pendingQueries => 0;
  @override
  bool isActive = true;
  final watches = <StreamController<ContentWindow>>[];
  final ranges = <ContentRange>[];
  final reads = <(ContentRef, ContentRange)>[];
  int cancels = 0;
  int pages = 0;
  int closeCalls = 0;
  bool closed = false;
  ReadDemand? lastDemand;
  Completer<void>? cancelGate;
  Object? closeFailure;
  @override
  Stream<ContentWindow> watchContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    ranges.add(range);
    final controller = StreamController<ContentWindow>(
      onCancel: () {
        cancels++;
        return cancelGate?.future;
      },
    );
    watches.add(controller);
    return controller.stream;
  }

  @override
  void retire() {
    isActive = false;
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closeCalls++;
    await cancelGate?.future;
    final failure = closeFailure;
    if (failure != null) {
      return CloseReport(
        unresolved: [
          UnresolvedResource(
            owner: 'scope',
            attemptId: AttemptId(generation),
            reason: failure,
          ),
        ],
      );
    }
    closed = true;
    return CloseReport();
  }

  @override
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  }) => throw UnimplementedError();
  @override
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  }) => throw UnimplementedError();
  @override
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  }) {
    reads.add((reference, range));
    if (onRead case final read?) return read(reference, range);
    throw UnimplementedError();
  }

  @override
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) async {
    pages++;
    lastDemand = demand;
    if (onPage case final read?) return read(reference, continuation, demand);
    return CurrentCollectionPage(
      revision: reference.revision,
      entries: [
        CurrentCollectionEntry(
          id: reference.collection == 'members' ? '成员记录' : '工具记录',
          position: 1,
          payload: InlinePayload(
            bytes: utf8.encode(
              reference.collection == 'members'
                  ? jsonEncode([
                      {
                        'reference': {
                          'databaseId': 'database',
                          'target': {
                            'kind': 'body',
                            'owner': {'kind': 'item', 'itemId': 'member'},
                            'key': 'body',
                          },
                        },
                        'byteLength': 100000,
                        'generation': 'g1',
                      },
                    ])
                  : '公开的单页记录',
            ),
          ),
        ),
      ],
    );
  }
}
