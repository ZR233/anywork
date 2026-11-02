import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/conversation_current_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_diagnostics.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/conversation_current_owner.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/contracts/stamps.dart';
import 'package:anywork_client/src/conversation/data/conversation_read_scope.dart';
import 'package:anywork_client/src/lifecycle/resource_budget.dart';
import 'package:anywork_client/src/observation/latest_value.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' show Chat;
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show chatMessage;

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
CurrentProjection _projection({
  int effect = 1,
  int revision = 1,
  bool collections = false,
  bool plan = false,
  String collection = 'tools',
  int collectionRevision = 1,
}) => CurrentProjection(
  sourceEffectSeq: effect,
  logicalStatus: ThreadStatusView.running,
  executionPresent: true,
  active: const CurrentActivityHead(
    id: 'active',
    kind: ThreadActivityKind.thinking,
    summary: '思考中',
    toolCount: 0,
    backgroundToolCount: 0,
  ),
  activeTurn: const CurrentTurnHead(
    id: 'turn',
    phase: StudioTurnActivity.thinking,
  ),
  plan: plan
      ? CurrentPlanHead(
          revision: revision,
          phase: PlanRuntimePhase.drafting,
          document: _reference(revision: revision),
        )
      : null,
  previews: plan
      ? const []
      : [
          CurrentContentPreview(
            id: 'reasoning',
            role: CurrentContentRole.reasoning,
            text: '有界预览 $effect',
            reference: _reference(revision: revision),
          ),
        ],
  collections: collections
      ? [
          CurrentCollectionRef(
            databaseId: 'database',
            collection: collection,
            revision: collectionRevision,
          ),
        ]
      : const [],
);
ConversationActivityView _view({bool responding = false}) =>
    ConversationActivityView(
      identity: 'active',
      kind: responding
          ? ConversationActivityKind.responding
          : ConversationActivityKind.thinking,
      summary: '思考中',
      expandable: true,
    );
Widget _host(
  _Content content,
  CurrentProjection current, {
  ConversationActivityView? view,
  VoidCallback Function(TimelineCurrentDisplay)? registerDisplay,
  bool Function()? isDisplayActive,
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ConversationCurrentConnector(
      current: current,
      content: content,
      view: view ?? _view(),
      registerDisplay: registerDisplay,
      isDisplayActive: isDisplayActive,
    ),
  ),
);
Finder get _header => find
    .descendant(
      of: find.byKey(const ValueKey('conversation-activity')),
      matching: find.byType(InkWell),
    )
    .first;
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

  for (final previewRevision in [false, true]) {
    testWidgets(
      'query scope retirement synchronously retires collection state (${previewRevision ? 'preview revision' : 'body next window'})',
      (tester) async {
        final content = _Content();
        final borrow = _DisplayBorrow();
        final requests = <Completer<CurrentCollectionPage>>[];
        final firstPage = CurrentCollectionPage(
          revision: 1,
          continuation: 'next',
          entries: [
            CurrentCollectionEntry(
              id: 'admitted-record',
              position: 1,
              payload: InlinePayload(bytes: utf8.encode('{}')),
            ),
          ],
        );
        content.onPage = (_, continuation, _) {
          if (requests.isEmpty && continuation == null) {
            requests.add(
              Completer<CurrentCollectionPage>()..complete(firstPage),
            );
            return requests.single.future;
          }
          final request = Completer<CurrentCollectionPage>();
          requests.add(request);
          return request.future;
        };
        Widget host(int revision) => _host(
          content,
          _projection(collections: true, revision: revision, effect: revision),
          registerDisplay: borrow.register,
        );
        await tester.pumpWidget(host(1));
        await tester.tap(_header);
        await tester.pump(const Duration(milliseconds: 300));
        final originalScope = content.scopes.single;
        originalScope.watches.single.add(_window('range 1'));
        await tester.pump();
        await tester.tap(
          find.byKey(StudioDriverKeys.currentCollection('tools')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final display = borrow.display!;
        final collection = display.collections.single;
        expect(collection.page, same(firstPage));
        final next = find.byKey(
          StudioDriverKeys.currentCollectionNext('tools'),
        );
        await tester.ensureVisible(next);
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        await tester.pump();
        expect(requests.length, 2);
        expect((collection.loading, collection.page), (true, firstPage));
        final generation = collection.generation;
        originalScope.cancelGate = Completer<void>();
        if (previewRevision) {
          await tester.pumpWidget(host(2));
        } else {
          await tester.ensureVisible(find.text('下一段'));
          expect(find.text('下一段').hitTestable(), findsOneWidget);
          await tester.tap(find.text('下一段'));
        }
        expect(originalScope.isActive, isFalse);
        expect(originalScope.closed, isFalse);
        expect(display.isCurrent, isTrue);
        expect(
          (collection.loading, collection.page, collection.error),
          (false, null, null),
          reason: 'Scope retirement must clear pending and admitted resources synchronously',
        );
        expect(collection.generation, greaterThan(generation));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final reload = find.byKey(
          StudioDriverKeys.currentCollectionReload('tools'),
        );
        expect(reload, findsOneWidget);
        await tester.ensureVisible(reload);
        expect(reload.hitTestable(), findsOneWidget);
        await tester.tap(reload);
        await tester.pump();
        expect((requests.length, collection.loading), (3, true));
        expect(content.scopes.length, 2);
        final replacementScope = content.scopes.last;
        expect(replacementScope.isActive, isTrue);
        if (previewRevision) {
          requests[1].complete(firstPage);
        } else {
          requests[1].completeError(const StaleConversationScope());
        }
        await tester.pump();
        expect(
          (collection.loading, collection.page, collection.error),
          (true, null, null),
          reason: 'The retired request success/error/finally must not release the new pending page',
        );
        originalScope.cancelGate!.complete();
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(originalScope.closed, isTrue);
        expect(originalScope.closeCalls, greaterThan(0));
        expect(
          (collection.loading, collection.page, collection.error),
          (true, null, null),
          reason: 'Joining the old scope cannot retire the new pending page',
        );
        expect(replacementScope.ranges.single.maxBytes, 32 * 1024);
        expect(
          replacementScope.ranges.single.offset,
          previewRevision ? 0 : utf8.encode('range 1').length,
        );
        final freshPage = CurrentCollectionPage(
          revision: 1,
          entries: [
            CurrentCollectionEntry(
              id: 'fresh-record',
              position: 2,
              payload: InlinePayload(bytes: utf8.encode('{"source":"fresh"}')),
            ),
          ],
        );
        requests.last.complete(freshPage);
        await tester.pump();
        expect(collection.page, same(freshPage));
        expect((collection.loading, collection.error), (false, null));
        expect(
          requests.length,
          3,
          reason: 'Retirement never automatically rereads collections',
        );
        expect(replacementScope.lastDemand!.maxBytes, 64 * 1024);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(content.scopes.every((scope) => scope.closed), isTrue);
        expect(borrow.display, isNull);
      },
    );
  }

  testWidgets(
    'expanded window stays on semantic ref and replaces entire range, not deltas',
    (tester) async {
      final content = _Content();
      final borrow = _DisplayBorrow();
      final projection = _projection();
      await tester.pumpWidget(
        _host(content, projection, registerDisplay: borrow.register),
      );
      expect(content.scopes, isEmpty);
      final display = borrow.display!;
      expect(
        (display.turnId, display.activityId, display.expanded),
        ('turn', 'active', false),
      );
      expect(display.windows, isEmpty);
      await tester.tap(_header);
      await tester.pump();
      final scope = content.scopes.single;
      expect(scope.watches.length, 1);
      expect(scope.ranges.single.maxBytes, 32 * 1024);
      final originalWindow = _window('第一片');
      scope.watches.single.add(originalWindow);
      await tester.pump();
      expect(find.text('第一片'), findsOneWidget);
      final observed = display.windows.single;
      expect(observed.window, same(originalWindow));
      expect(observed.window!.bytes, same(originalWindow.bytes));
      expect(observed.reference, same(projection.previews.single.reference));
      expect((observed.id, observed.offset), ('reasoning:reasoning', 0));
      for (var i = 0; i < 5; i++) {
        expect(display.windows.single, same(observed));
        expect(display.collections, isEmpty);
      }
      expect(
        (content.scopes.length, scope.watches.length, scope.pages),
        (1, 1, 0),
      );
      // A new producer snapshot allocates a new reference object with the same
      // stable owner/revision/key. It does not open another watch.
      await tester.pumpWidget(
        _host(
          content,
          _projection(effect: 2),
          registerDisplay: borrow.register,
        ),
      );
      expect(content.scopes, [scope]);
      expect(scope.watches.length, 1);
      scope.watches.single.add(_window('整片替换'));
      await tester.pump();
      expect(find.text('第一片'), findsNothing);
      expect(find.text('整片替换'), findsOneWidget);
      await tester.tap(find.text('下一段'));
      expect(
        observed.window,
        isNull,
        reason: 'The borrowed original window retires synchronously',
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(scope.cancels, 1);
      expect(content.scopes.length, 2);
      expect(
        content.scopes.last.ranges.single.offset,
        utf8.encode('整片替换').length,
      );
      expect(content.scopes.last.ranges.single.maxBytes, 32 * 1024);
      await tester.pumpWidget(const SizedBox());
      expect(borrow.display, isNull);
      expect(display.isCurrent, isFalse);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(content.scopes.every((scope) => scope.closed), isTrue);
    },
  );

  testWidgets(
    'collapse synchronously cancels and joins before reopening a scope',
    (tester) async {
      final content = _Content();
      await tester.pumpWidget(_host(content, _projection()));
      await tester.tap(_header);
      await tester.pump();
      final scope = content.scopes.single;
      scope.cancelGate = Completer<void>();
      scope.watches.single.add(_window('不再显示的窗口'));
      await tester.pump();
      await tester.tap(_header);
      expect(scope.cancels, 1);
      await tester.pump();
      expect(scope.closed, isFalse);
      expect(find.text('不再显示的窗口'), findsNothing);
      await tester.tap(_header);
      await tester.pump();
      expect(content.scopes, [scope]); // No replacement capability before join.
      scope.cancelGate!.complete();
      await tester.pump();
      expect(scope.closed, isTrue);
      expect(content.scopes.length, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'stale non-item revision and real IO failures remain diagnostics',
    (tester) async {
      final content = _Content();
      await tester.pumpWidget(_host(content, _projection()));
      await tester.tap(_header);
      await tester.pump();
      final old = content.scopes.single;
      old.watches.single.add(_window('旧文档'));
      await tester.pump();
      await tester.pumpWidget(
        _host(content, _projection(effect: 2, revision: 2)),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(old.cancels, 1);
      final fresh = content.scopes.last;
      fresh.watches.single.addError(
        StateError('StaleContent: owner revision retired'),
      );
      await tester.pump();
      expect(find.textContaining('StaleContent'), findsOneWidget);
      expect(find.text('旧文档'), findsNothing);
      expect(find.textContaining('不兼容'), findsNothing);
      fresh.watches.single.addError(StateError('database unavailable'));
      await tester.pump();
      expect(find.textContaining('database unavailable'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'A-B-A and late close failure never publish into replacement State',
    (tester) async {
      final a = _Content();
      final b = _Content();
      await tester.pumpWidget(_host(a, _projection()));
      await tester.tap(_header);
      await tester.pump();
      final retired = a.scopes.single;
      retired.cancelGate = Completer<void>();
      await tester.pumpWidget(_host(b, _projection()));
      await tester.tap(_header);
      await tester.pump();
      b.scopes.single.watches.single.add(_window('B内容'));
      await tester.pump();
      expect(find.text('B内容'), findsOneWidget);
      await tester.pumpWidget(_host(a, _projection(effect: 3)));
      await tester.tap(_header);
      await tester.pump();
      final current = a.scopes.last;
      expect(identical(current, retired), isFalse);
      current.watches.single.add(_window('新A内容'));
      retired.closeFailure = StateError('旧A关闭失败');
      retired.cancelGate!.complete();
      await tester.pump();
      expect(find.text('新A内容'), findsOneWidget);
      expect(find.textContaining('旧A关闭失败'), findsNothing);
      expect(retired.closeCalls, greaterThan(0));
      expect(
        retired.closed,
        isFalse,
      ); // The content owner still owns this scope.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'current collection is paged only on explicit collection expansion',
    (tester) async {
      final content = _Content();
      final borrow = _DisplayBorrow();
      final projection = _projection(collections: true);
      final typedWait = {
        'intent': {
          'kind': 'timer',
          'data': {'durationMs': 500},
        },
        'state': 'waiting',
      };
      final payload = InlinePayload(
        bytes: utf8.encode(
          jsonEncode({
            'callId': 'original-call',
            'name': 'not-a-wait-name',
            'state': 'running',
            'wait': typedWait,
          }),
        ),
      );
      final page = CurrentCollectionPage(
        revision: 1,
        continuation: 'page-2',
        entries: [
          CurrentCollectionEntry(id: '工具记录', position: 7, payload: payload),
          CurrentCollectionEntry(
            id: 'sleep-without-typed-wait',
            position: 8,
            payload: InlinePayload(bytes: utf8.encode('{"name":"sleep"}')),
          ),
        ],
      );
      final next = CurrentCollectionPage(
        revision: 1,
        entries: [
          CurrentCollectionEntry(
            id: 'next-record',
            position: 9,
            payload: payload,
          ),
        ],
      );
      final continuations = <String?>[];
      content.onPage = (reference, continuation, _) async {
        expect(reference, same(projection.collections.single));
        continuations.add(continuation);
        return continuation == null ? page : next;
      };
      await tester.pumpWidget(
        _host(content, projection, registerDisplay: borrow.register),
      );
      final display = borrow.display!;
      await tester.tap(_header);
      await tester.pump();
      final scope = content.scopes.single;
      expect(scope.pages, 0);
      expect(display.collections, isEmpty);
      await tester.tap(find.byKey(StudioDriverKeys.currentCollection('tools')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 250));
      expect(scope.pages, 1);
      expect(scope.lastDemand!.maxBytes, 64 * 1024);
      expect(scope.lastDemand!.maxItems, greaterThan(0));
      expect(find.text('工具记录'), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.currentCollectionEntry('tools', '工具记录')),
        findsOneWidget,
      );
      final collection = display.collections.single;
      expect(collection.reference, same(projection.collections.single));
      expect(collection.page, same(page));
      expect(collection.page!.entries.first.payload, same(payload));
      expect(
        (collection.expanded, collection.loading, collection.error),
        (true, false, null),
      );
      for (var i = 0; i < 5; i++) {
        final borrowed = collection.page!;
        expect(borrowed, same(page));
        expect(
          (borrowed.continuation, borrowed.entries.first.position),
          ('page-2', 7),
        );
        expect(
          (borrowed.entries.first.payload as InlinePayload).bytes,
          same(payload.bytes),
        );
        expect(
          (jsonDecode(utf8.decode(payload.bytes)) as Map)['wait'],
          typedWait,
        );
        expect(
          jsonDecode(
            utf8.decode((borrowed.entries.last.payload as InlinePayload).bytes),
          ),
          {'name': 'sleep'},
          reason: 'The borrow must not infer typed wait from a tool name',
        );
      }
      expect(
        (scope.pages, scope.watches.length, content.scopes.length),
        (1, 1, 1),
      );
      expect(continuations, [null]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(
        find.byKey(StudioDriverKeys.currentCollectionNext('tools')),
      );
      expect(
        find
            .byKey(StudioDriverKeys.currentCollectionNext('tools'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(StudioDriverKeys.currentCollectionNext('tools')),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(collection.page, same(next));
      expect(collection.page!.entries.map((entry) => entry.id), [
        'next-record',
      ]);
      expect(continuations, [null, 'page-2']);
      final generation = collection.generation;
      await tester.tap(find.byKey(StudioDriverKeys.currentCollection('tools')));
      expect(display.collections, isEmpty);
      expect(collection.page, isNull);
      expect(collection.generation, greaterThan(generation));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(StudioDriverKeys.currentCollection('tools')));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 300));
      expect(collection.page, same(page));
      await tester.tap(_header);
      expect(display.collections, isEmpty);
      expect(display.windows, isEmpty);
      expect(
        collection.page,
        isNull,
        reason: 'Outer collapse revokes the page before reverse animation',
      );
      await tester.pumpWidget(const SizedBox());
      expect(borrow.display, isNull);
      expect(display.isCurrent, isFalse);
      await tester.pump();
    },
  );

  testWidgets(
    'current Deferred payload borrows only the explicitly expanded real window',
    (tester) async {
      final content = _Content();
      final borrow = _DisplayBorrow();
      final projection = _projection(collections: true);
      final reference = ContentRef(
        databaseId: 'database',
        target: const ItemPayloadTarget(itemId: 'deferred-tool'),
      );
      final entry = CurrentCollectionEntry(
        id: 'deferred-tool',
        position: 1,
        payload: DeferredPayload(reference: reference, byteLength: 100000),
      );
      final page = CurrentCollectionPage(revision: 1, entries: [entry]);
      final requests = <Completer<ContentWindow>>[];
      content.onPage = (_, _, _) async => page;
      content.onRead = (_, _) {
        final request = Completer<ContentWindow>();
        requests.add(request);
        return request.future;
      };
      await tester.pumpWidget(
        _host(content, projection, registerDisplay: borrow.register),
      );
      final display = borrow.display!;
      await tester.tap(_header);
      await tester.pump(const Duration(milliseconds: 300));
      final scope = content.scopes.single;
      await tester.tap(find.byKey(StudioDriverKeys.currentCollection('tools')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final collection = display.collections.single;
      Iterable<TimelineCurrentWindowDisplay> payloadWindows() =>
          display.windows.where(
            (window) =>
                window.id == entry.id && identical(window.reference, reference),
          );
      for (var i = 0; i < 5; i++) {
        expect(collection.page, same(page));
        expect(collection.page!.entries.single, same(entry));
        expect(payloadWindows(), isEmpty);
      }
      expect((scope.reads.length, requests.length), (0, 0));
      expect(
        (content.scopes.length, scope.pages, scope.watches.length),
        (1, 1, 1),
      );
      final open = find.byKey(
        StudioDriverKeys.timelineContentOpen(entry.id, 'payload'),
      );
      await tester.ensureVisible(open);
      expect(open.hitTestable(), findsOneWidget);
      await tester.tap(open);
      await tester.pump();
      expect((scope.reads.length, requests.length), (1, 1));
      expect(scope.reads.single.$1, same(reference));
      expect(
        (scope.reads.single.$2.offset, scope.reads.single.$2.maxBytes),
        (0, 64 * 1024),
      );
      final observed = payloadWindows().single;
      expect((observed.window, observed.error), (null, null));
      const text = '{"输出":"已接纳的工具原文"}';
      final bytes = utf8.encode(text);
      final admitted = ContentWindow(
        offset: 0,
        bytes: bytes,
        generation: 'tool-payload-g1',
        availableThrough: bytes.length,
        sealed: true,
      );
      requests.single.complete(admitted);
      await tester.pump();
      final rendered = find.byKey(
        StudioDriverKeys.timelineContentWindow(entry.id, 'payload'),
      );
      expect(tester.widget<Text>(rendered).data, text);
      for (var i = 0; i < 5; i++) {
        expect(payloadWindows().single, same(observed));
        expect(observed.reference, same(reference));
        expect(observed.window, same(admitted));
        expect(observed.window!.bytes, same(admitted.bytes));
        expect(
          (
            observed.offset,
            observed.window!.generation,
            observed.window!.availableThrough,
            observed.window!.sealed,
          ),
          (0, 'tool-payload-g1', bytes.length, true),
        );
        expect(observed.error, isNull);
      }
      expect((scope.reads.length, requests.length), (1, 1));
      expect(
        (content.scopes.length, scope.pages, scope.watches.length),
        (1, 1, 1),
      );
      await tester.tap(open);
      // No frame or reverse animation may be needed to revoke a borrowed range.
      expect(payloadWindows(), isEmpty);
      expect((observed.window, observed.error), (null, null));
      expect(scope.reads.length, 1);
      await tester.pump();
      expect(rendered, findsNothing);
      await tester.tap(open);
      await tester.pump();
      expect((scope.reads.length, requests.length), (2, 2));
      expect(scope.reads.last.$1, same(reference));
      expect(
        (scope.reads.last.$2.offset, scope.reads.last.$2.maxBytes),
        (0, 64 * 1024),
      );
      final reopened = payloadWindows().single;
      final failure = StateError('explicit payload read failed');
      requests.last.completeError(failure);
      await tester.pump();
      expect(reopened.error, same(failure));
      expect(find.text(failure.toString()), findsOneWidget);
      await tester.tap(open);
      expect(payloadWindows(), isEmpty);
      expect((reopened.window, reopened.error), (null, null));
      expect((scope.reads.length, requests.length), (2, 2));
      expect(
        (content.scopes.length, scope.pages, scope.watches.length),
        (1, 1, 1),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(borrow.display, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current Deferred payload rejects retired success error and finally after explicit reload',
    (tester) async {
      final content = _Content();
      final borrow = _DisplayBorrow();
      final projection = _projection(collections: true);
      final reference = ContentRef(
        databaseId: 'database',
        target: const ItemPayloadTarget(itemId: 'deferred-tool'),
      );
      final entry = CurrentCollectionEntry(
        id: 'deferred-tool',
        position: 1,
        payload: DeferredPayload(reference: reference, byteLength: 100000),
      );
      final pages = <CurrentCollectionPage>[];
      final requests = <Completer<ContentWindow>>[];
      content.onPage = (reference, continuation, _) async {
        expect(reference, same(projection.collections.single));
        expect(continuation, isNull);
        // Explicit reload of the same revision can admit the same entry again;
        // this is not a duplicate id introduced on a continuation page.
        final page = CurrentCollectionPage(
          revision: reference.revision,
          entries: [entry],
        );
        pages.add(page);
        return page;
      };
      content.onRead = (_, _) {
        final request = Completer<ContentWindow>();
        requests.add(request);
        return request.future;
      };
      await tester.pumpWidget(
        _host(content, projection, registerDisplay: borrow.register),
      );
      final display = borrow.display!;
      await tester.tap(_header);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(StudioDriverKeys.currentCollection('tools')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final collection = display.collections.single;
      final open = find.byKey(
        StudioDriverKeys.timelineContentOpen(entry.id, 'payload'),
      );
      final entryView = find.byKey(
        StudioDriverKeys.currentCollectionEntry('tools', entry.id),
      );
      Iterable<TimelineCurrentWindowDisplay> payloadWindows() =>
          display.windows.where(
            (window) =>
                window.id == entry.id && identical(window.reference, reference),
          );
      expect(collection.page, same(pages.single));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump();
      final retired = <TimelineCurrentWindowDisplay>[];
      for (final staleError in [false, true]) {
        final old = payloadWindows().single;
        retired.add(old);
        final oldScope = content.scopes.last;
        final oldRequest = requests.last;
        final oldPage = collection.page!;
        final generation = collection.generation;
        expect(oldScope.reads.single.$1, same(reference));
        expect(
          (oldScope.reads.single.$2.offset, oldScope.reads.single.$2.maxBytes),
          (0, 64 * 1024),
        );
        // Moving the real reasoning window retires its shared query scope and
        // collection page synchronously, while this Deferred read is pending.
        oldScope.watches.single.add(
          _window('reasoning range', offset: oldScope.ranges.single.offset),
        );
        await tester.pump();
        final next = find.text('下一段');
        await tester.ensureVisible(next);
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        expect(oldScope.isActive, isFalse);
        expect(collection.page, isNull);
        expect(collection.generation, greaterThan(generation));
        expect(payloadWindows(), isEmpty);
        expect((old.window, old.error), (null, null));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final reload = find.byKey(
          StudioDriverKeys.currentCollectionReload('tools'),
        );
        await tester.ensureVisible(reload);
        expect(reload.hitTestable(), findsOneWidget);
        await tester.tap(reload);
        await tester.pump();
        expect(collection.reference, same(projection.collections.single));
        expect(collection.page, same(pages.last));
        expect(collection.page, isNot(same(oldPage)));
        expect(collection.page!.entries.single, same(entry));
        expect(payloadWindows(), isEmpty);
        final replacementScope = content.scopes.last;
        expect(replacementScope, isNot(same(oldScope)));
        expect(replacementScope.reads, isEmpty);
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pump();
        final current = payloadWindows().single;
        expect(current, isNot(same(old)));
        expect((current.window, current.error), (null, null));
        expect(replacementScope.reads.single.$1, same(reference));
        if (staleError) {
          oldRequest.completeError(StateError('retired payload failed'));
        } else {
          oldRequest.complete(_window('retired payload success'));
        }
        await tester.pump();
        expect(collection.page, same(pages.last));
        expect(payloadWindows().single, same(current));
        expect((current.window, current.error), (null, null));
        expect((old.window, old.error), (null, null));
        expect(find.text('retired payload success'), findsNothing);
        expect(find.textContaining('retired payload failed'), findsNothing);
        expect(
          tester.widget<TextButton>(open).onPressed,
          isNull,
          reason: 'An old finally must not finish the new pending payload read',
        );
        expect(
          find.descendant(
            of: entryView,
            matching: find.byType(LinearProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(replacementScope.reads.length, 1);
      }
      expect((pages.length, requests.length, content.scopes.length), (3, 3, 3));
      const text = '{"输出":"仅新页的真实窗口"}';
      final bytes = utf8.encode(text);
      final fresh = ContentWindow(
        offset: 0,
        bytes: bytes,
        generation: 'fresh-payload',
        availableThrough: bytes.length,
        sealed: true,
      );
      requests.last.complete(fresh);
      await tester.pump();
      final current = payloadWindows().single;
      expect(current.window, same(fresh));
      expect(current.window!.bytes, same(fresh.bytes));
      expect(current.reference, same(reference));
      expect(current.error, isNull);
      expect(
        tester
            .widget<Text>(
              find.byKey(
                StudioDriverKeys.timelineContentWindow(entry.id, 'payload'),
              ),
            )
            .data,
        text,
      );
      expect(tester.widget<TextButton>(open).onPressed, isNotNull);
      expect(
        find.descendant(
          of: entryView,
          matching: find.byType(LinearProgressIndicator),
        ),
        findsNothing,
      );
      for (final old in retired) {
        expect((old.window, old.error), (null, null));
        expect(display.windows.contains(old), isFalse);
      }
      expect((pages.length, requests.length, content.scopes.length), (3, 3, 3));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(borrow.display, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final staleError in [false, true]) {
    testWidgets(
      'current Deferred reload replaces retained-page state before old read ${staleError ? 'error' : 'success'}',
      (tester) async {
        final content = _Content();
        final borrow = _DisplayBorrow();
        final projection = _projection(collections: true);
        final reference = ContentRef(
          databaseId: 'database',
          target: const ItemPayloadTarget(itemId: 'retained-tool'),
        );
        final entry = CurrentCollectionEntry(
          id: 'retained-tool',
          position: 1,
          payload: DeferredPayload(reference: reference, byteLength: 100000),
        );
        final firstPage = CurrentCollectionPage(
          revision: 1,
          entries: [entry],
          continuation: 'next-page',
        );
        final pageRequests = <Completer<CurrentCollectionPage>>[];
        final continuations = <String?>[];
        final readRequests = <Completer<ContentWindow>>[];
        content.onPage = (reference, continuation, _) {
          expect(reference, same(projection.collections.single));
          continuations.add(continuation);
          final request = Completer<CurrentCollectionPage>();
          pageRequests.add(request);
          return request.future;
        };
        content.onRead = (_, _) {
          final request = Completer<ContentWindow>();
          readRequests.add(request);
          return request.future;
        };
        await tester.pumpWidget(
          _host(content, projection, registerDisplay: borrow.register),
        );
        final display = borrow.display!;
        await tester.tap(_header);
        await tester.pump(const Duration(milliseconds: 300));
        final scope = content.scopes.single;
        await tester.tap(
          find.byKey(StudioDriverKeys.currentCollection('tools')),
        );
        await tester.pump();
        expect(pageRequests.length, 1);
        pageRequests.single.complete(firstPage);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final collection = display.collections.single;
        final open = find.byKey(
          StudioDriverKeys.timelineContentOpen(entry.id, 'payload'),
        );
        final entryView = find.byKey(
          StudioDriverKeys.currentCollectionEntry('tools', entry.id),
        );
        final rendered = find.byKey(
          StudioDriverKeys.timelineContentWindow(entry.id, 'payload'),
        );
        final progress = find.descendant(
          of: entryView,
          matching: find.byType(LinearProgressIndicator),
        );
        Iterable<TimelineCurrentWindowDisplay> payloadWindows() =>
            display.windows.where(
              (window) =>
                  window.id == entry.id &&
                  identical(window.reference, reference),
            );
        expect(collection.page, same(firstPage));
        expect((scope.reads.length, readRequests.length), (0, 0));
        final next = find.byKey(
          StudioDriverKeys.currentCollectionNext('tools'),
        );
        await tester.ensureVisible(next);
        expect(next.hitTestable(), findsOneWidget);
        await tester.tap(next);
        await tester.pump();
        expect(pageRequests.length, 2);
        final pageFailure = StateError('next page failed');
        pageRequests.last.completeError(pageFailure);
        await tester.pump();
        expect(collection.page, same(firstPage));
        expect((collection.loading, collection.error), (false, pageFailure));
        final failedGeneration = collection.generation;
        final reload = find.byKey(
          StudioDriverKeys.currentCollectionReload('tools'),
        );
        await tester.ensureVisible(reload);
        expect(reload.hitTestable(), findsOneWidget);
        await tester.tap(reload);
        await tester.pump();
        expect(pageRequests.length, 3);
        final reloadGeneration = collection.generation;
        expect(reloadGeneration, greaterThan(failedGeneration));
        expect(collection.page, same(firstPage));
        expect((collection.loading, collection.error), (true, null));
        expect(entryView, findsOneWidget);
        await tester.ensureVisible(open);
        expect(open.hitTestable(), findsOneWidget);
        expect(tester.widget<TextButton>(open).onPressed, isNotNull);
        // The retained page is genuinely interactive during this pending reload.
        await tester.tap(open);
        await tester.pump();
        expect((scope.reads.length, readRequests.length), (1, 1));
        expect(scope.reads.single.$1, same(reference));
        expect(
          (scope.reads.single.$2.offset, scope.reads.single.$2.maxBytes),
          (0, 64 * 1024),
        );
        expect(collection.page, same(firstPage));
        expect(collection.loading, isTrue);
        final old = payloadWindows().single;
        expect(progress, findsOneWidget);
        expect(tester.widget<TextButton>(open).onPressed, isNull);
        final replacementPage = CurrentCollectionPage(
          revision: firstPage.revision,
          entries: [entry],
        );
        pageRequests.last.complete(replacementPage);
        await tester.pump();
        expect(collection.page, same(replacementPage));
        expect(collection.page, isNot(same(firstPage)));
        expect(collection.page!.entries.single, same(entry));
        expect(collection.generation, reloadGeneration);
        expect((collection.loading, collection.error), (false, null));
        expect((old.window, old.error), (null, null));
        expect(display.windows.contains(old), isFalse);
        expect(payloadWindows(), isEmpty);
        expect(
          tester.widget<TextButton>(open).onPressed,
          isNotNull,
          reason:
              'Accepting a different page must retire the retained pending range '
              'even with the same generation, entry id and ContentRef',
        );
        expect(progress, findsNothing);
        expect((scope.reads.length, readRequests.length), (1, 1));
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pump();
        expect((scope.reads.length, readRequests.length), (2, 2));
        expect(scope.reads.last.$1, same(reference));
        expect(
          (scope.reads.last.$2.offset, scope.reads.last.$2.maxBytes),
          (0, 64 * 1024),
        );
        final current = payloadWindows().single;
        expect(current, isNot(same(old)));
        if (staleError) {
          readRequests.first.completeError(
            StateError('old retained read failed'),
          );
        } else {
          readRequests.first.complete(_window('old retained read succeeded'));
        }
        await tester.pump();
        expect(collection.page, same(replacementPage));
        expect(payloadWindows().single, same(current));
        expect((old.window, old.error), (null, null));
        expect((current.window, current.error), (null, null));
        expect(display.windows.contains(old), isFalse);
        expect(rendered, findsNothing);
        expect(find.textContaining('old retained read failed'), findsNothing);
        expect(find.text('old retained read succeeded'), findsNothing);
        expect(
          tester.widget<TextButton>(open).onPressed,
          isNull,
          reason:
              'Old success/error/finally cannot finish the new pending read',
        );
        expect(progress, findsOneWidget);
        const text = '{"输出":"reload 新页的真实窗口"}';
        final bytes = utf8.encode(text);
        final fresh = ContentWindow(
          offset: 0,
          bytes: bytes,
          generation: 'reloaded-payload',
          availableThrough: bytes.length,
          sealed: true,
        );
        readRequests.last.complete(fresh);
        await tester.pump();
        expect(tester.widget<Text>(rendered).data, text);
        expect(progress, findsNothing);
        expect(tester.widget<TextButton>(open).onPressed, isNotNull);
        for (var i = 0; i < 5; i++) {
          expect(payloadWindows().single, same(current));
          expect(current.reference, same(reference));
          expect(current.window, same(fresh));
          expect(current.window!.bytes, same(fresh.bytes));
          expect(current.error, isNull);
          expect((old.window, old.error), (null, null));
          expect(display.windows.contains(old), isFalse);
          expect(collection.page, same(replacementPage));
        }
        expect(continuations, [null, 'next-page', null]);
        expect((scope.pages, scope.reads.length), (3, 2));
        expect((pageRequests.length, readRequests.length), (3, 2));
        expect(content.scopes, [scope]);
        expect(scope.isActive, isTrue);
        expect(scope.watches.length, 1);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(borrow.display, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final attemptChange in [false, true]) {
    testWidgets(
      'current diagnostic borrow rejects retired page completion and finally (${attemptChange ? 'attempt/error' : 'revision/success'})',
      (tester) async {
        final content = _Content();
        final borrow = _DisplayBorrow();
        var parentActive = true;
        final requests = <Completer<CurrentCollectionPage>>[];
        content.onPage = (_, _, _) {
          final request = Completer<CurrentCollectionPage>();
          requests.add(request);
          return request.future;
        };
        Widget host(int revision) => _host(
          content,
          _projection(
            effect: revision,
            collections: true,
            collectionRevision: revision,
          ),
          registerDisplay: borrow.register,
          isDisplayActive: () => parentActive,
        );
        await tester.pumpWidget(host(1));
        final display = borrow.display!;
        await tester.tap(_header);
        await tester.pump();
        await tester.tap(
          find.byKey(StudioDriverKeys.currentCollection('tools')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final collection = display.collections.single;
        final initialGeneration = collection.generation;
        expect(
          (requests.length, collection.loading, collection.page),
          (1, true, null),
        );
        final originalScope = content.scopes.single;
        if (attemptChange) {
          content.attempt = const AttemptId(2);
          content.source.publish(
            const ChatOpening<bool>('thread', lastGood: true),
          );
          expect(borrow.display, isNull);
          expect(display.isCurrent, isFalse);
          expect(collection.page, isNull);
          expect(collection.loading, isFalse);
          content.source.publish(const ChatReady<bool>('thread', true));
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
          expect(
            content.scopes,
            [originalScope],
            reason: 'New readiness must not restart watches from the retired snapshot',
          );
          expect(borrow.display, isNull);
        }
        await tester.pumpWidget(host(2));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(borrow.display, same(display));
        expect(collection.generation, greaterThan(initialGeneration));
        expect(collection.page, isNull);
        expect(collection.loading, isFalse);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(
          find.byKey(StudioDriverKeys.currentCollectionReload('tools')),
        );
        expect(
          find
              .byKey(StudioDriverKeys.currentCollectionReload('tools'))
              .hitTestable(),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(StudioDriverKeys.currentCollectionReload('tools')),
        );
        await tester.pump();
        expect((requests.length, collection.loading), (2, true));
        if (attemptChange) {
          requests.first.completeError(StateError('old attempt failed'));
        } else {
          requests.first.complete(
            CurrentCollectionPage(
              revision: 1,
              entries: [
                CurrentCollectionEntry(
                  id: 'retired-record',
                  position: 1,
                  payload: InlinePayload(bytes: utf8.encode('{}')),
                ),
              ],
            ),
          );
        }
        await tester.pump();
        expect(
          (collection.loading, collection.error, collection.page),
          (true, null, null),
          reason:
              'An old success/error/finally cannot alter the new pending page',
        );
        final fresh = CurrentCollectionPage(
          revision: 2,
          entries: [
            CurrentCollectionEntry(
              id: 'fresh-record',
              position: 2,
              payload: InlinePayload(
                bytes: utf8.encode('{"producer":"fresh"}'),
              ),
            ),
          ],
        );
        requests.last.complete(fresh);
        await tester.pump();
        expect(collection.page, same(fresh));
        expect((collection.loading, collection.error), (false, null));
        expect(find.text('retired-record'), findsNothing);
        if (attemptChange) {
          content.source.publish(
            ChatReconnecting<bool>(
              'thread',
              lastGood: true,
              error: StateError('temporarily not ready'),
            ),
          );
          expect(borrow.display, isNull);
          expect(collection.page, isNull);
          content.source.publish(const ChatReady<bool>('thread', true));
          expect(borrow.display, same(display));
          expect(display.isCurrent, isTrue);
          expect(collection.page, isNull);
          expect(
            requests.length,
            2,
            reason: 'Readiness does not itself page a collection',
          );
        }
        final io = (requests.length, content.scopes.length);
        parentActive = false;
        expect(display.isCurrent, isFalse);
        expect(display.collections, isEmpty);
        expect(display.windows, isEmpty);
        expect(collection.page, isNull);
        await tester.pumpWidget(host(2));
        expect(borrow.display, isNull);
        expect((requests.length, content.scopes.length), io);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(display.isCurrent, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('plan document watches a bounded window only while expanded', (
    tester,
  ) async {
    final content = _Content();
    await tester.pumpWidget(_host(content, _projection(plan: true)));
    expect(content.scopes, isEmpty);
    await tester.tap(_header);
    await tester.pump();
    final scope = content.scopes.single;
    expect(scope.ranges.single.maxBytes, 32 * 1024);
    scope.watches.single.add(_window('计划文档范围'));
    await tester.pump();
    expect(find.text('计划文档范围'), findsOneWidget);
    await tester.tap(_header);
    expect(scope.cancels, 1);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(scope.closed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'member page only observes declared body references after member expansion and joins on collapse',
    (tester) async {
      final content = _Content();
      final borrow = _DisplayBorrow();
      await tester.pumpWidget(
        _host(
          content,
          _projection(collections: true, collection: 'members'),
          registerDisplay: borrow.register,
        ),
      );
      await tester.tap(_header);
      await tester.pump();
      final pageScope = content.scopes.single;
      await tester.tap(find.text('当前内容'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 250));
      expect(pageScope.pages, 1);
      expect(content.scopes.length, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text('成员记录'));
      await tester.tap(find.text('成员记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(content.scopes.length, 2);
      final bodyScope = content.scopes.last;
      expect(bodyScope.ranges.single.maxBytes, 32 * 1024);
      bodyScope.watches.single.add(_window('成员范围'));
      await tester.pump();
      expect(find.text('成员范围'), findsOneWidget);
      final observed = borrow.display!.windows.singleWhere(
        (window) =>
            window.reference.target is BodyContentTarget &&
            (window.reference.target as BodyContentTarget).owner
                is ItemContentOwner,
      );
      expect(observed.id, '成员记录');
      expect(utf8.decode(observed.window!.bytes), '成员范围');
      final watchCounts = content.scopes
          .map((scope) => scope.watches.length)
          .toList();
      for (var i = 0; i < 5; i++) {
        expect(borrow.display!.windows.contains(observed), isTrue);
      }
      expect(content.scopes.map((scope) => scope.watches.length), watchCounts);
      await tester.tap(find.text('成员记录'));
      expect(observed.window, isNull);
      expect(borrow.display!.windows.contains(observed), isFalse);
      expect(
        bodyScope.cancels,
        1,
        reason: 'Collapse must revoke before the next animation frame',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(bodyScope.cancels, 1);
      expect(bodyScope.closed, isTrue);
      // Reopen the same admitted member page, then retire its shared page scope
      // through the actual main body range control rather than collapsing it.
      await tester.tap(find.text('成员记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final replacementBodyScope = content.scopes.last;
      expect(replacementBodyScope, isNot(same(bodyScope)));
      replacementBodyScope.cancelGate = Completer<void>();
      replacementBodyScope.watches.single.add(_window('新成员范围'));
      pageScope.watches.single.add(_window('正文范围'));
      await tester.pump();
      final memberWindow = borrow.display!.windows.singleWhere(
        (window) => window.id == '成员记录',
      );
      final collection = borrow.display!.collections.single;
      expect(collection.page, isNotNull);
      final next = find.text('下一段').first;
      await tester.ensureVisible(next);
      expect(next.hitTestable(), findsOneWidget);
      await tester.tap(next);
      expect(pageScope.isActive, isFalse);
      expect(collection.page, isNull);
      expect(memberWindow.window, isNull);
      expect(borrow.display!.windows.contains(memberWindow), isFalse);
      expect(replacementBodyScope.cancels, 1);
      expect(replacementBodyScope.closed, isFalse);
      replacementBodyScope.cancelGate!.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(replacementBodyScope.closed, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(content.scopes.every((scope) => scope.closed), isTrue);
    },
  );

  testWidgets(
    'current completed items open only the supplied parent and admit Children Set then Append while running',
    (tester) async {
      final harness = _CompletedHarness();
      final unknown = _completedProjection();
      await tester.pumpWidget(harness.host(unknown));
      expect(harness.current.display!.childrenParentId, isNull);
      await tester.tap(_header);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已完成成员'), findsNothing);
      expect(harness.builds, isEmpty);
      expect(harness.repository.requests, isEmpty);
      final retiringScope = harness.content.scopes.single;
      final retiringWindow = harness.current.display!.windows.single;
      final mainCancellation = Completer<void>();
      retiringScope.cancelGate = mainCancellation;
      await tester.tap(_header);
      expect(retiringScope.isActive, isFalse);
      expect(retiringScope.cancels, 1);
      expect(retiringScope.closed, isFalse);
      expect(retiringWindow.window, isNull);
      expect(harness.current.display!.windows, isEmpty);
      mainCancellation.complete();
      await tester.pump(const Duration(milliseconds: 300));
      expect(retiringScope.closed, isTrue);

      const parentId = 'producer-parent:α/17';
      final projection = _completedProjection(parentId: parentId);
      await tester.pumpWidget(harness.host(projection));
      final current = harness.current.display!;
      for (var i = 0; i < 5; i++) {
        expect(
          current.childrenParentId,
          projection.activeTurn!.childrenParentId,
        );
        expect(current.turnId, 'running-turn-A');
        expect(current.collections, isEmpty);
      }
      expect(harness.builds, isEmpty);
      expect(harness.repository.requests, isEmpty);
      await tester.tap(_header);
      await tester.pump(const Duration(milliseconds: 300));
      final tile = _completedHeader(parentId);
      expect(tile, findsOneWidget);
      expect(harness.builds, isEmpty);
      expect(harness.repository.requests, isEmpty);
      final currentScope = harness.content.scopes.last;
      expect(currentScope, isNot(same(retiringScope)));
      expect(currentScope.isActive, isTrue);
      final currentWindow = current.windows.single;
      final currentValue = _window('Children 打开前的当前推理窗口');
      currentScope.watches.single.add(currentValue);
      await tester.pump();
      expect(
        currentWindow.reference,
        same(projection.previews.single.reference),
      );
      expect(currentWindow.window, same(currentValue));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      expect(harness.builds, isNotEmpty);
      expect(harness.builds.last.parentId, parentId);
      expect(harness.builds.last.retirement.value, isFalse);
      final request = harness.repository.requests.single;
      expect((request.threadId, request.parentId), ('thread', parentId));
      expect(request.demand.maxItems, greaterThan(0));
      expect(request.demand.maxBytes, 256 * 1024);
      final children = _CompletedContent();
      request.result.complete(children);
      await tester.pump();
      expect(children.consumer, isNotNull);
      await children.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          messages: [chatMessage(id: 'completed-first', body: '首个公开完成结果')],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final display = harness.children.single;
      final controller = tester.widget<Chat>(find.byType(Chat)).chatController;
      expect(display.parentId, parentId);
      expect(display.messages.single, same(controller.messages.single));
      final first = controller.messages.single;
      await children.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.append,
          messages: [chatMessage(id: 'completed-next', body: '后继公开完成结果')],
        ),
      );
      await tester.pump();
      expect(harness.children.single, same(display));
      expect(
        tester.widget<Chat>(find.byType(Chat)).chatController,
        same(controller),
      );
      expect(display.messages.map((message) => message.id), [
        'completed-first',
        'completed-next',
      ]);
      expect(display.messages.first, same(first));
      expect(display.messages.last, same(controller.messages.last));
      expect((display.appliedSets, display.appliedAppends), (1, 1));
      for (var i = 0; i < 5; i++) {
        expect(current.childrenParentId, parentId);
        expect(current.collections, isEmpty);
        expect(current.windows.map((window) => window.id), [
          'reasoning:reasoning',
        ]);
        expect(current.windows.single, same(currentWindow));
        expect(currentWindow.window, same(currentValue));
        expect(currentWindow.window!.bytes, same(currentValue.bytes));
        expect(display.messages.toList(), controller.messages);
      }
      expect(projection.logicalStatus, ThreadStatusView.running);
      expect(currentScope.pages, 0);
      expect(currentScope.reads, isEmpty);
      expect(currentScope.watches.length, 1);
      expect(harness.content.scopes.length, 2);
      expect(harness.content.scopes.last, same(currentScope));
      expect(children.scopes, isEmpty);
      expect(harness.repository.requests.length, 1);
      final retirement = harness.builds.last.retirement;
      await tester.pumpWidget(const SizedBox());
      expect(retirement.value, isTrue);
      expect(harness.children, isEmpty);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current completed fold synchronously retires pending Children reads and reopens an independent display',
    (tester) async {
      final harness = _CompletedHarness();
      const parentId = 'producer-parent:α/17';
      final projection = _completedProjection(parentId: parentId);
      final requests = <Completer<ContentWindow>>[];
      _CompletedContent nextContent() => _CompletedContent()
        ..onRead = (_, _) {
          final request = Completer<ContentWindow>();
          requests.add(request);
          return request.future;
        };
      final reference = ContentRef(
        databaseId: 'database',
        target: const ItemPayloadTarget(itemId: 'completed-body'),
      );
      final message = ChatMessage(
        id: 'completed-body',
        payload: DeferredPayload(reference: reference, byteLength: 100000),
      );
      final open = find.byKey(
        StudioDriverKeys.timelineContentOpen(message.id, 'payload'),
      );
      final rendered = find.byKey(
        StudioDriverKeys.timelineContentWindow(message.id, 'payload'),
      );
      final progress = find.descendant(
        of: find.byType(TimelineChildrenConnector),
        matching: find.byType(LinearProgressIndicator),
      );
      await tester.pumpWidget(harness.host(projection));
      await tester.tap(_header);
      await tester.pump(const Duration(milliseconds: 300));
      var mainScope = harness.content.scopes.single;
      var mainWindow = harness.current.display!.windows.single;
      var mainValue = _window('Children 范围读取前的当前推理窗口');
      mainScope.watches.single.add(mainValue);
      await tester.pump();
      expect(mainWindow.reference, same(projection.previews.single.reference));
      expect(mainWindow.window, same(mainValue));
      await tester.tap(_completedHeader(parentId));
      await tester.pump();
      var children = nextContent();
      harness.repository.requests.last.result.complete(children);
      await tester.pump();
      await children.consumer!.applyBatch(
        ChatBatch(placement: ChatPlacement.set, messages: [message]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pump();
      for (final staleError in [false, true]) {
        final oldContent = children;
        final oldDisplay = harness.children.single;
        final oldState = tester.state(find.byType(TimelineChildrenConnector));
        final oldController = tester
            .widget<Chat>(find.byType(Chat))
            .chatController;
        final admitted = oldController.messages.single;
        final oldScope = oldContent.scopes.single;
        final oldRequest = requests.last;
        final retirement = harness.builds.last.retirement;
        expect(oldRequest.isCompleted, isFalse);
        expect(oldScope.reads.single.$1, same(reference));
        expect(
          (oldScope.reads.single.$2.offset, oldScope.reads.single.$2.maxBytes),
          (0, 64 * 1024),
        );
        expect(oldContent.source.observerCount, 1);
        expect(oldContent.consumerObservation!.isCancelled, isFalse);
        final mainCancellation = staleError ? Completer<void>() : null;
        if (mainCancellation != null) mainScope.cancelGate = mainCancellation;
        final fold = staleError ? _header : _completedHeader(parentId);
        await tester.ensureVisible(fold);
        await tester.tap(fold);
        // These checks precede the next frame and the Children State's disposal.
        expect(oldState.mounted, isTrue);
        expect(retirement.value, isTrue);
        expect(oldScope.isActive, isFalse);
        expect(oldContent.source.observerCount, 0);
        expect(oldContent.consumerObservation!.isCancelled, isTrue);
        expect(harness.children, isEmpty);
        expect(oldDisplay.isCurrent, isFalse);
        expect(oldDisplay.messages, isEmpty);
        if (staleError) {
          expect(mainScope.isActive, isFalse);
          expect(mainScope.cancels, 1);
          expect(mainScope.closed, isFalse);
          expect(mainWindow.window, isNull);
          expect(harness.current.display!.windows, isEmpty);
        } else {
          expect(mainScope.isActive, isTrue);
          expect(mainScope.cancels, 0);
          expect(harness.current.display!.windows.single, same(mainWindow));
          expect(mainWindow.window, same(mainValue));
        }
        await oldContent.consumer!.applyBatch(
          ChatBatch(
            placement: ChatPlacement.set,
            messages: [chatMessage(id: 'folded-late-set')],
          ),
        );
        await oldContent.consumer!.applyBatch(
          ChatBatch(
            placement: ChatPlacement.append,
            messages: [chatMessage(id: 'folded-late-append')],
          ),
        );
        expect(oldState.mounted, isTrue);
        expect(oldController.messages.single, same(admitted));
        expect(harness.children, isEmpty);
        mainCancellation?.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        if (staleError) {
          final retiredMainScope = mainScope;
          expect(retiredMainScope.closed, isTrue);
          await tester.tap(_header);
          await tester.pump(const Duration(milliseconds: 300));
          mainScope = harness.content.scopes.last;
          expect(mainScope, isNot(same(retiredMainScope)));
          expect(mainScope.isActive, isTrue);
          mainWindow = harness.current.display!.windows.single;
          mainValue = _window('整活动重新展开后的当前推理窗口');
          mainScope.watches.single.add(mainValue);
          await tester.pump();
          expect(
            mainWindow.reference,
            same(projection.previews.single.reference),
          );
          expect(mainWindow.window, same(mainValue));
        } else {
          expect(harness.content.scopes.single, same(mainScope));
        }
        final tile = _completedHeader(parentId);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pump();
        final replacementRetirement = harness.builds.last.retirement;
        expect(replacementRetirement, isNot(same(retirement)));
        expect(replacementRetirement.value, isFalse);
        children = nextContent();
        harness.repository.requests.last.result.complete(children);
        await tester.pump();
        await children.consumer!.applyBatch(
          ChatBatch(placement: ChatPlacement.set, messages: [message]),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pump();
        final current = harness.children.single;
        final scope = children.scopes.single;
        expect(current, isNot(same(oldDisplay)));
        expect(current.parentId, parentId);
        expect(scope, isNot(same(oldScope)));
        expect(scope.isActive, isTrue);
        expect(scope.reads.single.$1, same(reference));
        if (staleError) {
          oldRequest.completeError(StateError('retired Children read failed'));
        } else {
          oldRequest.complete(_window('retired Children read succeeded'));
        }
        await tester.pump();
        expect(harness.children.single, same(current));
        expect((current.isCurrent, current.error), (true, null));
        expect(oldDisplay.isCurrent, isFalse);
        expect(oldDisplay.messages, isEmpty);
        expect(rendered, findsNothing);
        expect(
          find.textContaining('retired Children read failed'),
          findsNothing,
        );
        expect(find.text('retired Children read succeeded'), findsNothing);
        expect(
          tester.widget<TextButton>(open).onPressed,
          isNull,
          reason: 'The retired read cannot clear the replacement range loading',
        );
        expect(progress, findsOneWidget);
        expect(requests.last.isCompleted, isFalse);
        expect(scope.reads.length, 1);
        expect(harness.current.display!.windows.single, same(mainWindow));
        expect(mainWindow.window, same(mainValue));
        expect(mainWindow.window!.bytes, same(mainValue.bytes));
        expect(mainScope.watches.length, 1);
        expect(mainScope.pages, 0);
        expect(mainScope.reads, isEmpty);
      }
      const text = '重新展开后读取的真实 Children 窗口';
      final bytes = utf8.encode(text);
      final fresh = ContentWindow(
        offset: 0,
        bytes: bytes,
        generation: 'reopened-children',
        availableThrough: bytes.length,
        sealed: true,
      );
      requests.last.complete(fresh);
      await tester.pump();
      expect(tester.widget<Text>(rendered).data, text);
      expect(progress, findsNothing);
      expect(tester.widget<TextButton>(open).onPressed, isNotNull);
      expect(children.scopes.single.reads.length, 1);
      expect(harness.repository.requests.map((request) => request.parentId), [
        parentId,
        parentId,
        parentId,
      ]);
      expect(requests.length, 3);
      expect(harness.content.scopes.length, 2);
      expect(harness.content.scopes.last, same(mainScope));
      expect(mainScope.isActive, isTrue);
      expect(harness.content.scopes.every((scope) => scope.pages == 0), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(harness.children, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current completed retirement rejects late open failure and isolates late A callbacks from B',
    (tester) async {
      final harness = _CompletedHarness();
      const parentA = 'producer-parent:α/17';
      const parentB = 'producer-parent:β/91';
      final a = _completedProjection(parentId: parentA);
      final b = _completedProjection(
        turnId: 'running-turn-B',
        parentId: parentB,
      );
      await tester.pumpWidget(harness.host(a));
      await tester.tap(_header);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(_completedHeader(parentA));
      await tester.pump();
      final pendingState = tester.state(find.byType(TimelineChildrenConnector));
      final pendingDisplay = pendingState as TimelineChildrenDisplay;
      final failedOpen = harness.repository.requests.single;
      final failedRetirement = harness.builds.last.retirement;
      await tester.tap(_completedHeader(parentA));
      expect(pendingState.mounted, isTrue);
      expect(failedRetirement.value, isTrue);
      failedOpen.result.completeError(StateError('retired open failed'));
      await tester.idle();
      expect(pendingState.mounted, isTrue);
      expect(
        pendingDisplay.error,
        isNull,
        reason: 'A late open catch must check the retired original parent',
      );
      expect(harness.children, isEmpty);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(_completedHeader(parentA));
      await tester.pump();
      final originalA = _CompletedContent();
      harness.repository.requests.last.result.complete(originalA);
      await tester.pump();
      await originalA.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          messages: [chatMessage(id: 'original-A')],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final displayA = harness.children.single;
      final controllerA = tester.widget<Chat>(find.byType(Chat)).chatController;
      expect(displayA.parentId, parentA);
      expect(displayA.messages.single, same(controllerA.messages.single));
      final tileA = _completedHeader(parentA);
      await tester.ensureVisible(tileA);
      await tester.tap(tileA);
      expect(originalA.consumerObservation!.isCancelled, isTrue);
      expect(displayA.isCurrent, isFalse);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(tileA);
      await tester.pump();
      final lateOpen = harness.repository.requests.last;
      final retirementA = harness.builds.last.retirement;
      expect(lateOpen.parentId, parentA);
      expect(lateOpen.result.isCompleted, isFalse);
      await tester.pumpWidget(harness.host(b));
      expect(retirementA.value, isTrue);
      expect(harness.current.display!.childrenParentId, parentB);
      expect(harness.current.display!.turnId, 'running-turn-B');
      expect(harness.children, isEmpty);
      expect(harness.repository.requests.length, 3);
      await tester.tap(_header);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(StudioDriverKeys.currentCompletedItems(parentA)),
        findsNothing,
      );
      expect(harness.repository.requests.length, 3);
      await tester.tap(_completedHeader(parentB));
      await tester.pump();
      final requestB = harness.repository.requests.last;
      expect(requestB.parentId, parentB);
      final contentB = _CompletedContent();
      requestB.result.complete(contentB);
      await tester.pump();
      await contentB.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          messages: [chatMessage(id: 'current-B')],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final displayB = harness.children.single;
      final controllerB = tester.widget<Chat>(find.byType(Chat)).chatController;
      expect(controllerB, isNot(same(controllerA)));
      final lateContent = _CompletedContent();
      lateOpen.result.complete(lateContent);
      await tester.idle();
      expect(lateContent.consumer, isNull);
      expect(lateContent.source.observerCount, 0);
      expect(lateContent.scopes, isEmpty);
      expect(lateContent.closeCalls, 1);
      // Simulate already delivered callbacks, bypassing the cancelled environment
      // observation so the real connector must reject their original parent.
      await originalA.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.set,
          messages: [chatMessage(id: 'late-A-set')],
        ),
      );
      await originalA.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.append,
          messages: [chatMessage(id: 'late-A-append')],
        ),
      );
      originalA.source.publish(
        ChatFailed<bool>('thread', error: StateError('late A state failed')),
      );
      await tester.pump();
      expect(harness.children.single, same(displayB));
      expect(displayB.parentId, parentB);
      expect(displayB.messages.map((message) => message.id), ['current-B']);
      expect(displayB.messages.single, same(controllerB.messages.single));
      expect((displayB.appliedSets, displayB.appliedAppends), (1, 0));
      expect(displayB.error, isNull);
      expect(displayA.messages, isEmpty);
      expect(find.textContaining('late A state failed'), findsNothing);
      expect(harness.repository.requests.map((request) => request.parentId), [
        parentA,
        parentA,
        parentA,
        parentB,
      ]);

      final stateB = tester.state(find.byType(TimelineChildrenConnector));
      final retirementB = harness.builds.last.retirement;
      var retiredBeforeUnmount = false;
      retirementB.addListener(() {
        if (retirementB.value) {
          retiredBeforeUnmount = stateB.mounted && !displayB.isCurrent;
        }
      });
      harness.active = false;
      expect(displayB.isCurrent, isFalse);
      await contentB.consumer!.applyBatch(
        ChatBatch(
          placement: ChatPlacement.append,
          messages: [chatMessage(id: 'retired-B-append')],
        ),
      );
      expect(stateB.mounted, isTrue);
      expect(controllerB.messages.map((message) => message.id), ['current-B']);
      await tester.pumpWidget(harness.host(b));
      expect(retirementB.value, isTrue);
      expect(retiredBeforeUnmount, isTrue);
      expect(harness.current.display, isNull);
      expect(harness.children, isEmpty);
      expect(contentB.consumerObservation!.isCancelled, isTrue);
      expect(contentB.source.observerCount, 0);
      expect(displayB.messages, isEmpty);
      expect(harness.repository.requests.length, 4);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}

CurrentProjection _completedProjection({
  String turnId = 'running-turn-A',
  String? parentId,
}) {
  final source = _projection(collections: true);
  return CurrentProjection(
    sourceEffectSeq: source.sourceEffectSeq,
    logicalStatus: source.logicalStatus,
    executionPresent: source.executionPresent,
    active: source.active,
    activeTurn: CurrentTurnHead(
      id: turnId,
      phase: StudioTurnActivity.thinking,
      childrenParentId: parentId,
    ),
    previews: source.previews,
    collections: source.collections,
  );
}

Finder _completedHeader(String parentId) => find
    .descendant(
      of: find.byKey(StudioDriverKeys.currentCompletedItems(parentId)),
      matching: find.byType(ListTile),
    )
    .first;

final class _CompletedHarness {
  final content = _Content();
  final repository = _CompletedRepository();
  final current = _DisplayBorrow();
  final children = <TimelineChildrenDisplay>{};
  final builds = <({String parentId, ValueListenable<bool> retirement})>[];
  bool active = true;

  VoidCallback _registerChildren(TimelineChildrenDisplay display) {
    children.add(display);
    return () => children.remove(display);
  }

  Widget _completedItems(String parentId, ValueListenable<bool> retirement) {
    builds.add((parentId: parentId, retirement: retirement));
    return TimelineChildrenConnector(
      repository: repository,
      threadId: content.threadId,
      parentId: parentId,
      registerDisplay: _registerChildren,
      isParentActive: () => active,
      parentRetirement: retirement,
    );
  }

  Widget host(CurrentProjection projection) => MaterialApp(
    theme: pureStudioTheme(),
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ConversationCurrentConnector(
        current: projection,
        content: content,
        view: _view(),
        registerDisplay: current.register,
        isDisplayActive: () => active,
        completedItemsBuilder: _completedItems,
      ),
    ),
  );
}

final class _CompletedRepository extends Fake
    implements ConversationRepository {
  final requests =
      <
        ({
          String threadId,
          String parentId,
          ReadDemand demand,
          Completer<ConversationContent> result,
        })
      >[];

  @override
  Future<ConversationContent> openChildren({
    required String threadId,
    required String parentId,
    required ReadDemand demand,
  }) {
    final result = Completer<ConversationContent>();
    requests.add((
      threadId: threadId,
      parentId: parentId,
      demand: demand,
      result: result,
    ));
    return result.future;
  }
}

final class _CompletedContent extends _Content {
  final _attachments = LatestValue<bool>(false);
  ConversationBatchConsumer? consumer;
  Observation? consumerObservation;
  int closeCalls = 0;

  @override
  Observation attachConsumer(
    ConversationBatchConsumer consumer, {
    required ReadDemand demand,
  }) {
    this.consumer = consumer;
    final observation = _attachments.watch((_) {});
    consumerObservation = observation;
    return observation;
  }

  @override
  bool get isClosed => closeCalls != 0;

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    closeCalls++;
    return CloseReport();
  }
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

final class _DisplayBorrow {
  TimelineCurrentDisplay? display;

  VoidCallback register(TimelineCurrentDisplay value) {
    display = value;
    return () => display = null;
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
