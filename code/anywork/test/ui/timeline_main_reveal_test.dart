import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/timeline_message_controller.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_display_unit_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/view_models/timeline_session_owner.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/timeline_observation.dart';
import '../support/chat_fixtures.dart';
import '../support/display_fixtures.dart';

void main() {
  for (final work in [false, true]) {
    testWidgets(
      'Main reveal waits for its ${work ? 'Work' : 'Single'} renderer while another scrollable has the fragment',
      (tester) async {
        final content = _NoQueries();
        final lease = (await tester.runAsync(
          () async => TimelineDisplayLease(
            threadId: 'pending-main-renderer',
            generation: 11,
            demand: chatDemand,
            content: content,
          ),
        ))!..bind();
        final projection = TimelineMessageController(
          lease.controller as InMemoryChatController,
          generation: lease.generation,
        );
        const id = 'canonical:pending-renderer';
        await projection.applyTimeline(
          displayBatch([
            if (work)
              displayWork(id, 1)
            else
              displaySingle(chatMessage(id, body: 'Ready canonical body')),
          ]),
        );
        final presentation = chatItemPresentationOf(
          lease.controller.messages.single,
        )!;
        final unit = presentation.displayUnit!;
        var loadingFrames = 0;
        final otherScroll = ScrollController();
        try {
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
                body: Row(
                  children: [
                    SizedBox(
                      width: 500,
                      height: 240,
                      child: Chat(
                        chatController: lease.controller,
                        currentUserId: 'user',
                        resolveUser: (id) async => User(id: id),
                        builders: Builders(
                          composerBuilder: (_) => const SizedBox.shrink(),
                          scrollToBottomBuilder: (_, _, _) =>
                              const SizedBox.shrink(),
                          chatAnimatedListBuilder: (_, _) =>
                              ChatAnimatedListReversed(
                                scrollController: lease.scrollController,
                                insertAnimationDuration: Duration.zero,
                                removeAnimationDuration: Duration.zero,
                                scrollToEndAnimationDuration: Duration.zero,
                                itemBuilder:
                                    (
                                      context,
                                      message,
                                      index,
                                      animation, {
                                      messagesGroupingMode,
                                      messageGroupingTimeoutInSeconds,
                                      isRemoved,
                                    }) => ChatMessage(
                                      key: StudioDriverKeys.timelineRow(
                                        message.id,
                                      ),
                                      message: message,
                                      index: index,
                                      animation: animation,
                                      padding: EdgeInsets.zero,
                                      child: _FrameDelayedRenderer(
                                        onLoading: () => loadingFrames++,
                                        child: ChatItemView(
                                          item: chatItemPresentationOf(
                                            message,
                                          )!,
                                        ),
                                      ),
                                    ),
                              ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      height: 240,
                      child: ListView(
                        controller: otherScroll,
                        children: [
                          if (work)
                            ChatItemView(item: presentation)
                          else
                            const Text('Ready canonical body'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
          expect(find.byKey(StudioDriverKeys.timelineRow(id)), findsOneWidget);
          final mainRow = find.byKey(StudioDriverKeys.timelineRow(id));
          final mainRenderer = find.descendant(
            of: mainRow,
            matching: find.byType(ChatItemView),
          );
          expect(mainRenderer, findsNothing);
          expect(lease.scrollController.position.maxScrollExtent, 0);
          final observed = TimelineObservation(tester, () => lease);
          final body = work
              ? observed.groupHeader(id)
              : find.text('Ready canonical body');
          expect(body, findsOneWidget);
          expect(
            Scrollable.maybeOf(tester.element(body))!.widget.controller,
            same(otherScroll),
          );
          await observed.reveal(body, id);
          expect(loadingFrames, greaterThan(0));
          expect(body, findsNWidgets(2));
          final mainBody = find.descendant(of: mainRow, matching: body);
          expect(mainBody, findsOneWidget);
          expect(
            work
                ? timelineGroupTitleFinder(tester, mainBody).hitTestable()
                : mainBody.hitTestable(),
            findsOneWidget,
          );
          expect(
            tester.widget<ChatItemView>(mainRenderer).item.displayUnit,
            same(unit),
          );
          expect(lease.scrollController.position.pixels, 0);
          expect(otherScroll.position.pixels, 0);
          expect(content.calls, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            projection.dispose();
            final unbound = lease.unbind();
            await lease.retire();
            await unbound;
            otherScroll.dispose();
          });
        }
        expect(lease.isReleased, isTrue);
      },
    );
  }

  testWidgets(
    'Main reveal ignores offscreen keepalives in both directions and never scrolls Atoms',
    (tester) async {
      final content = _NoQueries();
      var memberOpens = 0;
      // The lease's release Completer and controller stream must belong to the
      // same real-async zone in which their close is joined below.
      final lease = (await tester.runAsync(
        () async => TimelineDisplayLease(
          threadId: 'main-reveal',
          generation: 7,
          demand: chatDemand,
          content: content,
        ),
      ))!..bind();
      final controller = lease.controller;
      // Populate the sole controller with explicit producer block fixtures
      // through the production projection, not an alternate reveal algorithm.
      final projection = TimelineMessageController(
        controller as InMemoryChatController,
        generation: lease.generation,
        onUnitCreated: (unit) {
          unit.expansion.openDisplayMembers = (_, _, _) async {
            memberOpens++;
            throw StateError('Main reveal must not open a member query');
          };
        },
      );
      final ids = [
        for (var i = 0; i < 32; i++) 'main:${(i * 17 + 13) % 37}:opaque',
      ];
      await projection.applyTimeline(
        displayBatch([
          for (var i = 0; i < ids.length; i++)
            if (i == ids.length - 1)
              displayWork(ids[i], i + 1)
            else
              displaySingle(
                chatMessage(ids[i], body: 'Main row $i', completionSeq: i + 1),
              ),
        ]),
      );
      expect(controller.messages.last.id, ids.last);
      final atomScroll = ScrollController();
      var operations = 0;
      final subscription = controller.operationsStream.listen(
        (_) => operations++,
      );
      var mainDrags = 0;
      var phase = 'build';
      addTearDown(
        () => debugPrint('Main reveal regression final phase: $phase'),
      );
      try {
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
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 500,
                      height: 240,
                      child: Chat(
                        chatController: controller,
                        currentUserId: 'user',
                        resolveUser: (id) async => User(id: id),
                        builders: Builders(
                          composerBuilder: (_) => const SizedBox.shrink(),
                          scrollToBottomBuilder: (_, _, _) =>
                              const SizedBox.shrink(),
                          chatAnimatedListBuilder: (_, _) =>
                              NotificationListener<ScrollStartNotification>(
                                onNotification: (notification) {
                                  if (notification.depth == 0 &&
                                      notification.dragDetails != null) {
                                    mainDrags++;
                                  }
                                  return false;
                                },
                                child: ChatAnimatedListReversed(
                                  scrollController: lease.scrollController,
                                  insertAnimationDuration: Duration.zero,
                                  removeAnimationDuration: Duration.zero,
                                  scrollToEndAnimationDuration: Duration.zero,
                                  shouldScrollToEndWhenSendingMessage: false,
                                  handleSafeArea: false,
                                  topPadding: 0,
                                  bottomPadding: 0,
                                  cacheExtent: 120,
                                  itemBuilder:
                                      (
                                        context,
                                        message,
                                        index,
                                        animation, {
                                        messagesGroupingMode,
                                        messageGroupingTimeoutInSeconds,
                                        isRemoved,
                                      }) => _KeptMainRow(
                                        key: ValueKey('main-row:${message.id}'),
                                        keepAlive:
                                            message.id == ids.first ||
                                            message.id == ids.last,
                                        child: ChatMessage(
                                          key: StudioDriverKeys.timelineRow(
                                            message.id,
                                          ),
                                          message: message,
                                          index: index,
                                          animation: animation,
                                          padding: EdgeInsets.zero,
                                          child: SizedBox(
                                            height: 120,
                                            child: ChatItemView(
                                              item: chatItemPresentationOf(
                                                message,
                                              )!,
                                            ),
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 200,
                      height: 240,
                      // A separate real Atom rendering domain, not a fabricated
                      // GroupDisplay. One Atom deliberately shares a Main ID.
                      child: ListView.builder(
                        controller: atomScroll,
                        itemCount: 32,
                        itemBuilder: (_, index) => SizedBox(
                          height: 120,
                          child: ChatItemView(
                            item: ChatItemPresentation.decode(
                              chatAtomMessage(
                                index == 0 ? ids.last : 'atom:$index',
                                body: 'Atom row $index',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final observed = TimelineObservation(tester, () => lease);
        Finder body(int index) => find.descendant(
          of: observed.itemRow(ids[index]),
          matching: find.text('Main row $index'),
        );
        final mainScroll = find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              identical(widget.controller, lease.scrollController),
        );
        expect(mainScroll, findsOneWidget);
        final position = lease.scrollController.position;
        expect(position.axisDirection, AxisDirection.up);
        expect(position.pixels, 0);

        // Visit the oldest end through UI dragging, leaving the newest endpoint
        // alive but offscreen. Targets visited en route must be lazily unmounted.
        phase = 'seed offscreen keepalive';
        await tester.dragUntilVisible(
          body(0),
          mainScroll,
          const Offset(0, 240),
        );
        await tester.pumpAndSettle();
        final dragsAfterSeed = mainDrags;
        expect(dragsAfterSeed, greaterThan(0));
        final newestKept = find.byKey(
          ValueKey('main-row:${ids.last}'),
          skipOffstage: false,
        );
        expect(newestKept, findsOneWidget);
        expect(newestKept.hitTestable(), findsNothing);
        expect(find.byKey(ValueKey('main-row:${ids.last}')), findsNothing);
        // The production text is the actual hit region. A stretched Main
        // container's center may be empty whitespace, not a hit-test target.
        expect(body(0).hitTestable(), findsOneWidget);
        final newerTarget = body(22);
        expect(newerTarget, findsNothing);
        expect(
          find.byKey(ValueKey('main-row:${ids[22]}'), skipOffstage: false),
          findsNothing,
          reason: 'The newer target is not even mounted in cache',
        );
        final oldestPixels = position.pixels;
        final atomPixels = atomScroll.position.pixels;

        // The wanted index is between mounted keepalives 0 and 31. The former
        // allWidgets min/max chose the older direction here and could never reach it.
        phase = 'reveal newer';
        await observed.reveal(newerTarget, ids[22]);
        expect(newerTarget, findsOneWidget);
        expect(newerTarget.hitTestable(), findsOneWidget);
        expect(position.pixels, lessThan(oldestPixels));
        expect(mainDrags, greaterThan(dragsAfterSeed));
        final dragsAfterNewer = mainDrags;
        final newerPixels = position.pixels;

        final oldestKept = find.byKey(
          ValueKey('main-row:${ids.first}'),
          skipOffstage: false,
        );
        expect(oldestKept, findsOneWidget);
        expect(oldestKept.hitTestable(), findsNothing);
        expect(find.byKey(ValueKey('main-row:${ids.first}')), findsNothing);
        expect(newestKept, findsOneWidget);
        expect(newestKept.hitTestable(), findsNothing);
        expect(find.byKey(ValueKey('main-row:${ids.last}')), findsNothing);
        final olderTarget = body(8);
        expect(olderTarget, findsNothing);
        expect(
          find.byKey(ValueKey('main-row:${ids[8]}'), skipOffstage: false),
          findsNothing,
        );
        phase = 'reveal older';
        await observed.reveal(olderTarget, ids[8]);
        expect(olderTarget, findsOneWidget);
        expect(olderTarget.hitTestable(), findsOneWidget);
        expect(position.pixels, greaterThan(newerPixels));
        expect(mainDrags, greaterThan(dragsAfterNewer));

        final groupUnit = chatItemPresentationOf(controller.messages[31])!
            .displayUnit!;
        final cachedGroupRow = find.byWidgetPredicate(
          (widget) =>
              widget is ChatItemView &&
              identical(widget.item.displayUnit, groupUnit),
          skipOffstage: false,
        );
        final groupHeader = observed.groupHeader(ids.last);
        expect(cachedGroupRow, findsOneWidget);
        final groupItem = tester.widget<ChatItemView>(cachedGroupRow).item;
        expect(groupItem.type, 'displayUnit');
        expect(groupItem.compatibility, ChatItemCompatibility.current);
        expect(groupUnit.body, isA<WorkDisplayBlock>());
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is TimelineDisplayUnitView &&
                identical(widget.unit, groupUnit),
            skipOffstage: false,
          ),
          findsOneWidget,
        );
        expect(groupHeader, findsNothing);
        expect(groupHeader.hitTestable(), findsNothing);
        final dragsBeforeCache = mainDrags;
        phase = 'reveal cached canonical group';
        await observed.reveal(groupHeader, ids.last);
        expect(groupHeader, findsOneWidget);
        final headerElement = tester.element(groupHeader);
        final headerBox = tester.renderObject<RenderBox>(groupHeader);
        expect(headerBox.attached, isTrue);
        expect(headerBox.hasSize, isTrue);
        expect(
          tester
              .getRect(groupHeader)
              .intersect(tester.getRect(mainScroll))
              .isEmpty,
          isFalse,
          reason: 'The original header must really intersect its Main viewport',
        );
        expect(
          Scrollable.maybeOf(headerElement),
          same(tester.state<ScrollableState>(mainScroll)),
        );
        expect(
          tester.element(
            find.descendant(of: cachedGroupRow, matching: groupHeader),
          ),
          same(headerElement),
        );
        // Match the existing openGroup/_groupTitle click surface, scoped to
        // this exact header, not the Align/Row/Spacer container's empty centre.
        final groupTitle = find.descendant(
          of: groupHeader,
          matching: find.text(
            AppLocalizations.of(tester.element(groupHeader))
                .timelineGroupWorkedSeconds(1),
          ),
        );
        expect(groupTitle, findsOneWidget);
        expect(groupTitle.hitTestable(), findsOneWidget);
        expect(
          Scrollable.maybeOf(tester.element(groupTitle)),
          same(tester.state<ScrollableState>(mainScroll)),
        );
        expect(
          mainDrags,
          dragsBeforeCache,
          reason: 'An already mounted canonical row needs no further UI drag',
        );
        expect(groupUnit.expansion.expanded ?? false, isFalse);
        final groupDisclosure = find.byKey(
          ValueKey('completion-run-disclosure:${ids.last}'),
        );
        expect(groupDisclosure, findsOneWidget);
        expect(
          tester.widget<Expansible>(groupDisclosure).controller.isExpanded,
          isFalse,
        );

        final typedUnit = chatItemPresentationOf(controller.messages[0])!
            .displayUnit!;
        final cachedTypedRow = find.byWidgetPredicate(
          (widget) =>
              widget is ChatItemView &&
              identical(widget.item.displayUnit, typedUnit),
          skipOffstage: false,
        );
        expect(cachedTypedRow, findsOneWidget);
        final typedItem = tester.widget<ChatItemView>(cachedTypedRow).item;
        expect(typedItem.type, 'text');
        expect(typedItem.compatibility, ChatItemCompatibility.current);
        expect(typedUnit.body, isA<SingleDisplayBlock>());
        final cachedTypedBody = body(0);
        expect(cachedTypedBody, findsNothing);
        expect(cachedTypedBody.hitTestable(), findsNothing);
        phase = 'reveal cached canonical typed body';
        await observed.reveal(cachedTypedBody, ids.first);
        expect(cachedTypedBody, findsOneWidget);
        expect(cachedTypedBody.hitTestable(), findsOneWidget);
        expect(mainDrags, dragsBeforeCache);

        expect(atomScroll.position.pixels, atomPixels);
        expect(lease.controller, same(controller));
        expect(lease.generation, 7);
        expect(controller.messages.map((message) => message.id), ids);
        expect(operations, 0);
        expect(content.calls, 0);
        expect(memberOpens, 0);
        expect(tester.takeException(), isNull);

        // Only after all original zero-IO/Main/Atom guards pass, exercise the
        // same real title tap as openGroup. This fixture has no member builder;
        // expansion proves UI interaction, not GroupMembers query acceptance.
        phase = 'toggle exact group title';
        await observed.reveal(groupHeader, ids.last);
        final titlePixels = position.pixels;
        await observed.tap(groupTitle);
        await tester.pumpAndSettle();
        expect(groupUnit.expansion.expanded, isTrue);
        expect(
          tester.widget<Expansible>(groupDisclosure).controller.isExpanded,
          isTrue,
        );
        await observed.tap(groupTitle);
        await tester.pumpAndSettle();
        expect(groupUnit.expansion.expanded, isFalse);
        expect(
          tester.widget<Expansible>(groupDisclosure).controller.isExpanded,
          isFalse,
        );
        expect(position.pixels, titlePixels);
        expect(mainDrags, dragsBeforeCache);
        expect(atomScroll.position.pixels, atomPixels);
        expect(lease.controller, same(controller));
        expect(lease.generation, 7);
        expect(controller.messages.map((message) => message.id), ids);
        expect(operations, 0);
        expect(content.calls, 0);
        expect(memberOpens, 0);
        expect(tester.takeException(), isNull);
      } finally {
        phase = 'detach';
        await tester.pumpWidget(const SizedBox.shrink());
        phase = 'release';
        // Match the real stream-completion disposal in chat_batch_component_test.
        await tester.runAsync(() async {
          phase = 'release: cancel observer';
          await subscription.cancel();
          projection.dispose();
          final unbound = lease.unbind();
          phase = 'release: retire lease';
          await lease.retire();
          phase = 'release: join unbind';
          await unbound;
          atomScroll.dispose();
        });
        expect(lease.isReleased, isTrue);
        phase = 'complete';
      }
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

/// A metadata renderer may become ready in a later frame while its canonical
/// ChatMessage already exists. This fixture supplies that timing input only.
final class _FrameDelayedRenderer extends StatefulWidget {
  const _FrameDelayedRenderer({required this.onLoading, required this.child});

  final VoidCallback onLoading;
  final Widget child;

  @override
  State<_FrameDelayedRenderer> createState() => _FrameDelayedRendererState();
}

final class _FrameDelayedRendererState extends State<_FrameDelayedRenderer> {
  int _frames = 0;

  @override
  Widget build(BuildContext context) {
    if (_frames >= 3) return widget.child;
    widget.onLoading();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _frames++);
    });
    return const Text('正在读取完成内容…');
  }
}

final class _NoQueries extends Fake implements ConversationContent {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return super.noSuchMethod(invocation);
  }
}

final class _KeptMainRow extends StatefulWidget {
  const _KeptMainRow({super.key, required this.keepAlive, required this.child});

  final bool keepAlive;
  final Widget child;

  @override
  State<_KeptMainRow> createState() => _KeptMainRowState();
}

final class _KeptMainRowState extends State<_KeptMainRow>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
