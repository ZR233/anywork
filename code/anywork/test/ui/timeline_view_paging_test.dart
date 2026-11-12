import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';

void main() {
  testWidgets(
    'composer submission is visible in the chat sliver and stays separate from draft text',
    (tester) async {
      final h = await _Harness.open(tester);
      await h.owner.dispatch('a', const TimelineEnterHistory());
      expect(h.owner.source.value!.mode, TimelineDisplayMode.history);
      h.showSubmission(
        ComposerSubmission(
          inputId: 'input-pending',
          text: '冻结的消息',
          attachments: const [
            AttachmentDraftView(
              id: 'file-1',
              modality: AttachmentModalityView.file,
              mediaType: 'text/plain',
              filename: 'draft.txt',
              byteSize: 12,
            ),
          ],
          phase: ComposerSubmissionPhase.sending,
        ),
      );
      await tester.pump();
      expect(h.owner.source.value!.mode, TimelineDisplayMode.live);
      expect(h.lease.scrollController.hasClients, isTrue);
      expect(find.text('冻结的消息'), findsOneWidget);
      expect(find.text('draft.txt'), findsOneWidget);
      expect(find.text('正在发送'), findsNothing);
      expect(
        find.semantics.byPredicate(
          (node) => node.getSemanticsData().tooltip == '正在发送',
        ),
        findsOne,
      );
      expect(
        find.byKey(const ValueKey('composer-submission:input-pending')),
        findsOneWidget,
      );
      expect(find.text('editable draft'), findsNothing);

      h.showSubmission(
        ComposerSubmission(
          inputId: 'input-pending',
          text: '冻结的消息',
          attachments: const [],
          phase: ComposerSubmissionPhase.accepted,
        ),
      );
      await _frames(tester);
      expect(find.text('已收到，等待同步'), findsNothing);
      expect(
        find.semantics.byPredicate(
          (node) => node.getSemanticsData().tooltip == '已收到，等待同步',
        ),
        findsOne,
      );

      h.showSubmission(null);
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('composer-submission:input-pending')),
        findsNothing,
      );
      await _frames(tester);
      await h.drainPages(tester);
      await h.close(tester);
    },
  );

  testWidgets(
    'submission intersects the viewport on the first frame from a real history offset',
    (tester) async {
      final composer = _SubmissionOwner();
      final h = await _Harness.open(tester, composer: composer);
      await h.content.deliver(
        _timelineBatch(
          [
            for (var i = 1; i <= 28; i++)
              chatMessage(
                'long:$i',
                body: 'history row $i',
                completionSeq: 1000 + i,
              ),
          ],
          placement: ChatPlacement.append,
          from: 1000,
        ),
      );
      await _frames(tester);
      final scroll = h.lease.scrollController;
      final min = scroll.position.minScrollExtent;
      final max = scroll.position.maxScrollExtent;
      expect(max, greaterThan(min + 100));
      scroll.jumpTo(min + (max - min) / 2);
      await tester.pump();
      expect(scroll.position.pixels, greaterThan(min + 1));

      composer.publish([
        ComposerSubmission(
          inputId: 'input-first-frame',
          text: '首帧必须可见',
          attachments: const [],
          phase: ComposerSubmissionPhase.sending,
        ),
      ]);
      h.owner.prepareComposerSubmissionDisplay('a', lease: h.lease);
      await tester.pump();

      final submission = find.byKey(
        const ValueKey('composer-submission:input-first-frame'),
        skipOffstage: false,
      );
      expect(submission, findsOneWidget);
      final viewport = find
          .descendant(
            of: find.byType(ChatAnimatedListReversed),
            matching: find.byType(Viewport),
          )
          .first;
      expect(
        tester.getRect(viewport).overlaps(tester.getRect(submission)),
        isTrue,
        reason: 'the frozen input must intersect the Chat viewport in its first painted frame',
      );

      await _frames(tester);
      await h.drainPages(tester);
      await h.close(tester);
    },
  );

  testWidgets('canonical input takes over the temporary item by inputId', (
    tester,
  ) async {
    final template = chatAtomMessage('input-record', body: '规范消息正文');
    final atom = ChatAtom(
      id: template.id,
      completionItemId: template.completionItemId,
      completionSeq: 2,
      source: const InputChatSource(inputId: 'input-canonical'),
      sourceOrder: template.sourceOrder,
      kind: template.kind,
      delivery: template.delivery,
      lifecycle: template.lifecycle,
      contents: template.contents,
      payload: template.payload,
    );
    final composer = _SubmissionOwner();
    final h = await _Harness.open(tester, composer: composer);
    composer.publish([
      ComposerSubmission(
        inputId: 'input-canonical',
        text: '规范消息正文',
        attachments: const [],
        phase: ComposerSubmissionPhase.sending,
      ),
    ]);
    await _frames(tester);
    await h.content.deliver(
      _timelineBatch([statusItem(atom, completionSeq: 2)]),
    );
    await _frames(tester);
    expect(composer.presented, ['input-canonical']);
    expect(
      find.byKey(const ValueKey('composer-submission:input-canonical')),
      findsNothing,
    );
    expect(h.lease.loadedCount, 1);
    expect(
      h.lease.controller.messages.map((message) => message.id),
      contains('input-record'),
    );
    await _frames(tester);
    await h.drainPages(tester);
    await h.close(tester);
  });

  testWidgets(
    'first page is visible while fill waits; every short page yields layout',
    (tester) async {
      final h = await _Harness.open(tester);
      expect(find.text('first body'), findsOneWidget);
      expect(h.requests, hasLength(1));
      final range = h.lease.scrollController.position.maxScrollExtent;
      // Empty/byte-limited pages are not EOF. The real owner publishes metadata,
      // but its unchanged Flyer projection emits no operations.
      var operations = 0;
      final subscription = h.lease.controller.operationsStream.listen(
        (_) => operations++,
      );
      addTearDown(subscription.cancel);
      for (var i = 1; i <= 12; i++) {
        final request = h.requests.last;
        final loading = h.owner.loadOlder('a', generation: h.lease.generation);
        expect(request.before, 'page:${i - 1}');
        expect(request.demand, chatDemand);
        request.reply.complete(
          _timelineBatch(
            const [],
            placement: ChatPlacement.prepend,
            before: i == 12 ? null : 'page:$i',
          ),
        );
        await request.finished.future;
        await loading;
        // Neither SDK acceptance nor the owner page Future needs another frame.
        expect(h.requests, hasLength(i));
        await _frames(tester);
        expect(h.requests, hasLength(i == 12 ? 12 : i + 1));
        expect(h.lease.scrollController.position.maxScrollExtent, range);
      }
      expect(operations, 0);
      expect(h.lease.loadedCount, 1);
      expect(h.owner.source.value!.hasOlder, isFalse);
      expect(range, h.lease.scrollController.position.minScrollExtent);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(h.requests, hasLength(12));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await h.close(tester);
    },
  );

  testWidgets(
    'owner error pauses fill and explicit retry resumes through EOF',
    (tester) async {
      final h = await _Harness.open(tester);
      h.requests.single.reply.completeError(StateError('page failed'));
      await _frames(tester);
      expect(h.owner.source.value!.olderError, isA<StateError>());
      expect(h.lease.olderCursor, 'page:0');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(h.requests, hasLength(1));

      await tester.tap(find.byKey(StudioDriverKeys.timelineRetryOlder));
      await _frames(tester);
      expect(h.requests, hasLength(2));
      expect(h.requests.last.before, 'page:0');
      h.requests.last.reply.complete(
        _timelineBatch(
          const [],
          placement: ChatPlacement.prepend,
          before: 'page:1',
        ),
      );
      await _frames(tester);
      expect(h.owner.source.value!.olderError, isNull);
      expect(h.requests, hasLength(3));
      expect(h.requests.last.before, 'page:1');
      h.requests.last.reply.complete(
        _timelineBatch(const [], placement: ChatPlacement.prepend),
      );
      await tester.pumpAndSettle();
      expect(h.owner.source.value!.hasOlder, isFalse);
      expect(h.requests, hasLength(3));
      await h.close(tester);
    },
  );

  testWidgets(
    'same cursor remains an owner protocol error, not EOF or retry loop',
    (tester) async {
      final h = await _Harness.open(tester);
      h.requests.single.reply.complete(
        _timelineBatch(
          const [],
          placement: ChatPlacement.prepend,
          before: 'page:0',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        h.owner.source.value!.olderError,
        isA<ConversationContinuityError>(),
      );
      expect(h.owner.source.value!.hasOlder, isTrue);
      expect(h.lease.olderCursor, 'page:0');
      await tester.pump(const Duration(seconds: 1));
      expect(h.requests, hasLength(1));
      expect(find.byKey(StudioDriverKeys.timelineRetryOlder), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'zero chat viewport resumes on layout; input resize uses chat not window',
    (tester) async {
      final h = await _Harness.open(tester, height: 0);
      expect(h.lease.scrollController.position.viewportDimension, 0);
      expect(h.requests, isEmpty);
      await h.initialEndReached!();
      await _frames(tester);
      expect(h.requests, isEmpty, reason: 'Flyer also pauses at zero viewport');
      h.resize(height: 180);
      await _frames(tester);
      expect(h.requests, hasLength(1));
      h.requests.last.reply.complete(
        _timelineBatch(
          [
            for (var i = 0; i < 5; i++)
              chatMessage('older:$i', completionSeq: 10 + i),
          ],
          placement: ChatPlacement.prepend,
          before: 'page:1',
        ),
      );
      await tester.pumpAndSettle();
      final position = h.lease.scrollController.position;
      final viewport = find.descendant(
        of: find.byType(ChatAnimatedListReversed),
        matching: find.byType(Viewport),
      );
      expect(position.viewportDimension, tester.getSize(viewport).height);
      expect(position.viewportDimension, inExclusiveRange(0, 180));
      expect(position.maxScrollExtent, greaterThan(position.minScrollExtent));
      expect(position.pixels, 0, reason: 'Reversed latest is pixels zero');
      expect(
        h.requests,
        hasLength(1),
        reason: 'Already fills actual chat viewport',
      );

      h.resize(height: 550);
      await _frames(tester);
      expect(
        h.requests,
        hasLength(2),
        reason: 'Larger chat viewport needs another page',
      );
      expect(position.viewportDimension, lessThanOrEqualTo(550));
      h.requests.last.reply.complete(
        _timelineBatch(const [], placement: ChatPlacement.prepend),
      );
      await tester.pumpAndSettle();
      await h.close(tester);
    },
  );

  testWidgets(
    'content-only layout changes resume fill; nested scroll does not express chat intent',
    (tester) async {
      final h = await _Harness.open(tester, summaryHeight: 550);
      final position = h.lease.scrollController.position;
      expect(position.maxScrollExtent, greaterThan(position.minScrollExtent));
      expect(h.requests, isEmpty);
      await tester.drag(
        find.byKey(const ValueKey('nested-summary')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(h.owner.source.value!.mode, TimelineDisplayMode.live);
      expect(h.requests, isEmpty);

      // This rebuilds only the live/summary child, not TimelineView or its
      // controller. The real outer ScrollMetricsNotification resumes demand.
      h.summaryHeight.value = 0;
      await _frames(tester);
      expect(h.requests, hasLength(1));
      h.summaryHeight.value = 550;
      h.requests.last.reply.complete(
        _timelineBatch(
          const [],
          placement: ChatPlacement.prepend,
          before: 'page:1',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        h.requests,
        hasLength(1),
        reason: 'Live growth already fills viewport',
      );
      h.summaryHeight.value = 0;
      await _frames(tester);
      expect(h.requests, hasLength(2));
      h.requests.last.reply.complete(
        _timelineBatch(const [], placement: ChatPlacement.prepend),
      );
      await tester.pumpAndSettle();
      await h.close(tester);
    },
  );

  testWidgets(
    'hidden and inactive display pause; real widget updates resume demand',
    (tester) async {
      final h = await _Harness.open(tester, offstage: true);
      expect(h.requests, isEmpty);
      h.resize(offstage: false, active: false);
      await _frames(tester);
      expect(h.requests, isEmpty);
      h.resize(active: true);
      await _frames(tester);
      expect(h.requests, hasLength(1));
      h.requests.last.reply.complete(
        _timelineBatch(const [], placement: ChatPlacement.prepend),
      );
      await tester.pumpAndSettle();
      await h.close(tester);
    },
  );

  testWidgets(
    'retained chat subtree resumes on Offstage reveal without widget or size updates',
    (tester) async {
      final h = await _Harness.open(tester, hidden: true);
      final timeline = find.byType(TimelineView, skipOffstage: false);
      final hiddenView = tester.widget<TimelineView>(timeline);
      expect(h.requests, isEmpty);
      expect(tester.binding.hasScheduledFrame, isFalse);

      h.outerOffstage.value = false;
      await tester.pump();
      expect(tester.widget<TimelineView>(timeline), same(hiddenView));
      expect(h.requests, hasLength(1));
      await _frames(tester);

      // A second reveal reuses an already-painted RepaintBoundary. Completing
      // its pending page while hidden must not issue another read.
      h.outerOffstage.value = true;
      await _frames(tester);
      h.requests.last.reply.complete(
        _timelineBatch(
          const [],
          placement: ChatPlacement.prepend,
          before: 'page:1',
        ),
      );
      await _frames(tester);
      expect(h.requests, hasLength(1));
      final cachedView = tester.widget<TimelineView>(timeline);
      h.outerOffstage.value = false;
      await tester.pump();
      expect(tester.widget<TimelineView>(timeline), same(cachedView));
      expect(h.requests, hasLength(2));
      h.requests.last.reply.complete(
        _timelineBatch(const [], placement: ChatPlacement.prepend),
      );
      await tester.pumpAndSettle();
      expect(h.requests, hasLength(2));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await h.close(tester);
    },
  );

  testWidgets(
    'scroll, Flyer and retry share owner flight; append preserves before',
    (tester) async {
      final h = await _Harness.open(tester, joinFlyer: true);
      final lease = h.lease;
      final flyerRequest = h.flyerLoad!;
      final loading = h.owner.loadOlder('a', generation: lease.generation);
      final retry = h.owner.retryOlder('a', generation: lease.generation);
      expect(identical(loading, retry), isTrue);
      await h.content.deliver(
        _timelineBatch(
          [
            for (var i = 0; i < 18; i++)
              chatMessage('append:$i', completionSeq: 2000 + i),
          ],
          placement: ChatPlacement.append,
          from: 1000,
        ),
      );
      await _frames(tester);
      expect(lease.olderCursor, 'page:0');
      expect(
        lease.loadedCount,
        19,
        reason: 'Append does not wait for history IO',
      );
      await tester.drag(
        find.byType(ChatAnimatedListReversed),
        const Offset(0, 400),
      );
      await _frames(tester);
      expect(h.requests, hasLength(1));
      h.requests.single.reply.complete(
        _timelineBatch(
          [chatMessage('older', completionSeq: 10)],
          placement: ChatPlacement.prepend,
          before: 'page:1',
        ),
      );
      await loading;
      await retry;
      await flyerRequest;
      await tester.pumpAndSettle();
      expect(
        h.requests,
        hasLength(1),
        reason: 'Full viewport needs no group-head read',
      );
      expect(lease.olderCursor, 'page:1');
      expect(
        lease.controller.messages.map((message) => message.id),
        containsAll(['older', 'first', 'append:17']),
      );
      await h.close(tester);
    },
  );

  testWidgets(
    'retired page and old callbacks cannot page or mutate new generation',
    (tester) async {
      final h = await _Harness.open(tester);
      final oldLease = h.lease;
      final oldEndReached = h.initialEndReached!;
      final oldRequest = h.requests.single;
      await h.content.deliver(
        _timelineBatch([
          for (var i = 0; i < 18; i++)
            chatMessage('new:$i', completionSeq: 3000 + i),
        ], before: 'new-before'),
      );
      await _frames(tester);
      expect(oldLease.isRetired, isTrue);
      expect(h.lease, isNot(same(oldLease)));
      oldRequest.reply.complete(
        _timelineBatch(
          [chatMessage('stale')],
          placement: ChatPlacement.prepend,
          before: 'stale-before',
        ),
      );
      await oldRequest.finished.future;
      await oldEndReached();
      await tester.pumpAndSettle();
      expect(h.requests, hasLength(1));
      expect(h.lease.olderCursor, 'new-before');
      expect(h.lease.loadedCount, 18);
      expect(
        h.lease.controller.messages.any((message) => message.id == 'stale'),
        isFalse,
      );
      await oldLease.released;
      await h.close(tester);
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  // Allow publication, its layout, and the one follow-up demand frame. Unlike
  // pumpAndSettle this also works while the real loading indicator is animating.
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

TimelineBatch _timelineBatch(
  List<CompletedEntry> entries, {
  ChatPlacement placement = ChatPlacement.set,
  String? before,
  int? from,
}) {
  final through = entries.lastOrNull?.completionSeq ?? 0;
  return displayBatch(
    [for (final entry in entries) displaySingle(entry)],
    placement: placement,
    before: before,
    from: from,
    through: through,
    live: placement == ChatPlacement.prepend
        ? null
        : LiveDisplayWindow(
            revision: 0,
            historyThrough: through,
            executionPresent: false,
            blocks: const [],
          ),
  );
}

final class _Harness {
  _Harness({
    required this.height,
    required this.offstage,
    required double summaryHeight,
    required bool hidden,
    _SubmissionOwner? composer,
  }) : summaryHeight = ValueNotifier(summaryHeight),
       outerOffstage = ValueNotifier(hidden) {
    owner = TimelineSessionOwner(
      client: _Client(_Repository(_Session(content)), composer),
    );
    owner.updateReadDemand(chatDemand);
    owner.select('a');
  }

  final content = _Content();
  late final TimelineSessionOwner owner;
  Observation? _observation;
  StateSetter? _rebuild;
  double height;
  bool offstage;
  bool active = true;
  final ValueNotifier<double> summaryHeight;
  final ValueNotifier<bool> outerOffstage;
  List<ComposerSubmission> submissions = const [];
  Observation? _composerObservation;
  _SubmissionOwner? _composer;
  Future<void> Function()? initialEndReached;
  Future<void>? flyerLoad;
  TimelineDisplayLease get lease => owner.lease('a')!;
  List<_PageRequest> get requests => [
    for (final scope in content.scopes) ...scope.requests,
  ];

  static Future<_Harness> open(
    WidgetTester tester, {
    double height = 550,
    bool offstage = false,
    double summaryHeight = 0,
    bool joinFlyer = false,
    bool hidden = false,
    _SubmissionOwner? composer,
  }) async {
    final h = _Harness(
      height: height,
      offstage: offstage,
      summaryHeight: summaryHeight,
      hidden: hidden,
      composer: composer,
    );
    await h.content.deliver(
      _timelineBatch([
        chatMessage('first', body: 'first body', completionSeq: 1000),
      ], before: 'page:0'),
    );
    h._observation = h.owner.source.watch((_) => h._rebuild?.call(() {}));
    h._composer = composer;
    h._composerObservation = composer?.submissions.watch((_) {
      h._rebuild?.call(() {});
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: h.outerOffstage,
            builder: (_, hidden, child) =>
                Offstage(offstage: hidden, child: child),
            child: RepaintBoundary(
              child: StatefulBuilder(
                builder: (_, setState) {
                  h._rebuild = setState;
                  final lease = h.lease;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: Offstage(
                      offstage: h.offstage,
                      child: SizedBox(
                        height: h.height,
                        child: TimelineView(
                          key: lease.chatKey,
                          threadId: 'a',
                          controls: lease,
                          view: h.owner.source.value!,
                          submissions:
                              h._composer?.submissions.value ?? h.submissions,
                          onLoadOlder: () => h.owner.loadOlder(
                            'a',
                            generation: lease.generation,
                          ),
                          onRetryOlder: () => h.owner.retryOlder(
                            'a',
                            generation: lease.generation,
                          ),
                          onReturnLive: () => h.owner.returnToLive('a'),
                          onEnterHistory: () => h.owner.dispatch(
                            'a',
                            const TimelineEnterHistory(),
                          ),
                          onRetryConnection: () {},
                          onLink: (_) {},
                          isSafeLink: (_) => false,
                          remoteImageBuilder: (_, _) => const SizedBox.shrink(),
                          isDisplayActive: () => h.active && !lease.isRetired,
                          planSummary: ValueListenableBuilder<double>(
                            valueListenable: h.summaryHeight,
                            builder: (_, height, _) => SizedBox(
                              height: height,
                              child: height == 0
                                  ? null
                                  : ListView(
                                      key: const ValueKey('nested-summary'),
                                      primary: false,
                                      children: [
                                        for (var i = 0; i < 30; i++)
                                          const SizedBox(height: 40),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    h.initialEndReached = tester
        .widget<ChatAnimatedListReversed>(
          find.byType(ChatAnimatedListReversed, skipOffstage: false),
        )
        .onEndReached;
    if (joinFlyer) {
      expect(h.initialEndReached, isNotNull);
      h.flyerLoad = h.initialEndReached!();
    }
    await _frames(tester);
    return h;
  }

  void resize({double? height, bool? offstage, bool? active}) {
    _rebuild!(() {
      this.height = height ?? this.height;
      this.offstage = offstage ?? this.offstage;
      this.active = active ?? this.active;
    });
  }

  void showSubmission(ComposerSubmission? submission) {
    _rebuild!(() {
      submissions = submission == null ? const [] : [submission];
    });
  }

  Future<void> drainPages(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      final pending = requests.where((request) => !request.reply.isCompleted);
      if (pending.isEmpty) return;
      final request = pending.last;
      request.reply.complete(
        _timelineBatch(const [], placement: ChatPlacement.prepend),
      );
      await request.finished.future;
      await _frames(tester);
    }
  }

  Future<void> close(WidgetTester tester) async {
    _observation?.cancel();
    _composerObservation?.cancel();
    await tester.pumpWidget(const SizedBox());
    final closing = owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(seconds: 1));
    final report = await closing;
    expect(report.unresolved, isEmpty);
    summaryHeight.dispose();
    outerOffstage.dispose();
    expect(tester.takeException(), isNull);
  }
}

final class _Client extends Fake implements AnyworkClient {
  _Client(this.conversations, this._composer);
  @override
  final ConversationRepository conversations;
  final _SubmissionOwner? _composer;
  @override
  DraftsRepository get drafts => _DraftsRepository(_composer);
}

final class _DraftsRepository extends Fake implements DraftsRepository {
  _DraftsRepository(this.composerOwner);
  final _SubmissionOwner? composerOwner;
  @override
  final StartSessionDraftOwner startDraft = _StartSubmissionOwner();
  @override
  ComposerDraftOwner? existingComposer(String threadId) =>
      threadId == 'a' ? composerOwner : null;
}

final class _StartSubmissionOwner extends Fake
    implements StartSessionDraftOwner {
  @override
  void markInputsPresented(Iterable<String> inputIds) {}
}

final class _SubmissionOwner extends Fake implements ComposerDraftOwner {
  final LatestValue<List<ComposerSubmission>> _submissions = LatestValue(
    const [],
  );
  final List<String> presented = [];

  @override
  ValueObservation<List<ComposerSubmission>> get submissions => _submissions;

  void publish(List<ComposerSubmission> value) =>
      _submissions.publish(List.unmodifiable(value));

  @override
  void markInputsPresented(Iterable<String> inputIds) {
    presented.addAll(inputIds);
    final settled = inputIds.toSet();
    publish([
      for (final submission in _submissions.value)
        if (!settled.contains(submission.inputId)) submission,
    ]);
  }
}

final class _Repository extends Fake implements ConversationRepository {
  _Repository(this.value);
  final ConversationSession value;
  @override
  ConversationSession? existingSession(String threadId) => value;
}

final class _Session extends Fake implements ConversationSession {
  _Session(this.content);
  @override
  String get threadId => 'a';
  @override
  final TimelineContent content;
}

final class _Content extends Fake implements TimelineContent {
  @override
  String get threadId => 'a';
  @override
  final state = LatestValue<ChatUiState<bool>>(const ChatReady('a', true));
  @override
  final LatestValue<LiveDisplayWindow?> live = LatestValue(null);
  TimelineBatchConsumer? consumer;
  final scopes = <_Scope>[];

  @override
  Observation attachTimelineConsumer(
    TimelineBatchConsumer consumer, {
    required ReadDemand demand,
  }) {
    this.consumer = consumer;
    return _Observation(() => this.consumer = null);
  }

  Future<void> deliver(TimelineBatch batch) async {
    final acceptedLive = batch.live ?? live.value!;
    await consumer!.applyTimeline(batch, acceptedLive);
    if (batch.placement != ChatPlacement.prepend) live.publish(acceptedLive);
  }

  @override
  TimelineQueryScope openScope({required int generation}) {
    final scope = _Scope(this, consumer!, generation);
    scopes.add(scope);
    return scope;
  }
}

final class _Observation extends Fake implements Observation {
  _Observation(this.onCancel);
  final VoidCallback onCancel;
  @override
  void cancel() => onCancel();
}

final class _PageRequest {
  _PageRequest(this.before, this.demand);
  final String before;
  final ReadDemand demand;
  final reply = Completer<TimelineBatch>();
  final finished = Completer<void>();
}

// Only transport and admission barriers are doubled. All pagination, cursor,
// error, single-flight, projection and layout behavior belongs to production.
final class _Scope extends Fake implements TimelineQueryScope {
  _Scope(this.content, this.consumer, this.generation);
  final _Content content;
  final TimelineBatchConsumer consumer;
  @override
  final int generation;
  @override
  String get threadId => 'a';
  @override
  bool isActive = true;
  final requests = <_PageRequest>[];

  @override
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) async {
    final request = _PageRequest(before, demand);
    requests.add(request);
    try {
      final batch = await request.reply.future;
      if (isActive) await consumer.applyTimeline(batch, content.live.value!);
      return batch;
    } finally {
      request.finished.complete();
    }
  }

  @override
  void retire() => isActive = false;
  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    retire();
    await Future.wait([
      for (final request in requests) request.finished.future,
    ]);
    return CloseReport();
  }
}
