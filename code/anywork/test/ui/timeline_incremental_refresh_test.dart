import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/domain/models/timeline_commands.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_ui_controllers.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_view_state.dart';
import 'package:anywork/src/features/conversation/timeline/views/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('incremental timeline operations leave other rows intact', (
    tester,
  ) async {
    final history = _message('history', 'Earlier response');
    final target = _message('target', 'Initial response');
    final controls = _TimelineControls([history, target]);
    final builds = <String, int>{};
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controls.controller.dispose();
      controls.scrollController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme().copyWith(platform: TargetPlatform.linux),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TimelineView(
            threadId: 'thread',
            view: const TimelineSessionViewState(
              threadId: 'thread',
              generation: 1,
              mode: TimelineDisplayMode.live,
              connection: TimelineConnectionPhase.ready,
            ),
            controls: controls,
            onLoadOlder: () async {},
            onRetryOlder: () async {},
            onReturnLive: () async => true,
            onEnterHistory: () {},
            onRetryConnection: () {},
            onLink: (_) {},
            isSafeLink: (_) => false,
            remoteImageBuilder: (_, _) => const SizedBox.shrink(),
            canonicalPresentationBuilder: (item, _) {
              builds.update(item.id, (count) => count + 1, ifAbsent: () => 1);
              return Text(item.data['text']! as String);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Earlier response'), findsOneWidget);
    expect(find.text('Initial response'), findsOneWidget);
    final historyBuilds = builds['history']!;
    final targetBuilds = builds['target']!;

    await controls.controller.insertAllMessages([
      _message('appended', 'New response'),
    ], animated: false);
    await tester.pumpAndSettle();
    expect(find.text('New response'), findsOneWidget);
    expect(builds['history'], historyBuilds);
    expect(builds['target'], targetBuilds);
    final appendedBuilds = builds['appended']!;

    await controls.controller.updateMessage(
      target,
      _message('target', 'Updated response'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Updated response'), findsOneWidget);
    expect(find.text('Initial response'), findsNothing);
    expect(builds['target'], greaterThan(targetBuilds));
    expect(builds['history'], historyBuilds);
    expect(builds['appended'], appendedBuilds);

    await controls.controller.insertAllMessages([
      for (var i = 0; i < 30; i++) _message('row-$i', 'Response $i'),
    ], animated: false);
    await tester.pumpAndSettle();
    final viewport = find.byType(CustomScrollView);
    final scrollbar = find.descendant(
      of: viewport,
      matching: find.byWidgetPredicate((widget) => widget is RawScrollbar),
    );
    expect(scrollbar, findsOneWidget);
    final paint = find.descendant(
      of: scrollbar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.foregroundPainter is ScrollbarPainter,
      ),
    );
    final painter =
        tester.widget<CustomPaint>(paint).foregroundPainter!
            as ScrollbarPainter;
    expect(painter.fadeoutOpacityAnimation.value, 0);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(viewport),
        scrollDelta: const Offset(0, -240),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(controls.scrollController.offset, greaterThan(0));
    expect(painter.fadeoutOpacityAnimation.value, greaterThan(0));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(painter.fadeoutOpacityAnimation.value, 0);
  });
}

Message _message(String id, String text) => Message.custom(
  id: id,
  authorId: 'assistant',
  metadata: {
    chatItemPresentationKey: ChatItemPresentation(
      id: id,
      compatibility: ChatItemCompatibility.current,
      type: 'text',
      data: {'text': text},
      bodies: [
        ChatBodyPresentation(
          key: 'body',
          byteLength: text.length,
          inlineText: text,
        ),
      ],
      authorId: 'assistant',
    ),
  },
);

final class _TimelineControls implements TimelineUiControllers {
  _TimelineControls(List<Message> messages)
    : controller = InMemoryChatController(messages: messages);

  @override
  final Key chatKey = const ValueKey('incremental-timeline');

  @override
  final InMemoryChatController controller;

  @override
  final ScrollController scrollController = ScrollController();

  @override
  bool get isRetired => false;

  @override
  void bind() {}

  @override
  Future<void> unbind() async {}
}
