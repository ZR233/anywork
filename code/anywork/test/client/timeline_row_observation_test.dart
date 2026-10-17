import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/domain/models/studio_models.dart';
import 'package:anywork/src/features/timeline/timeline_session_view.dart';
import 'package:anywork/src/features/timeline/timeline_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_demo_transport.dart';
import 'support/pump_client_future.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'mixed activity stops at text, images, compaction and agent notifications ($brightness)',
      (tester) async {
        final now = DateTime.utc(2026);
        StudioChatItem entry(
          String id,
          int ordinal,
          ThreadItemStateView state,
        ) {
          final item = ThreadItemView(
            id: id,
            threadId: 'thread-main',
            turnId: 'turn',
            ordinal: ordinal,
            revision: 1,
            createdAt: now,
            updatedAt: now,
            state: state,
            saved: true,
          );
          return StudioChatItem(
            item,
            saved: true,
            lifecycle: item.isTerminal
                ? StudioChatLifecycle.terminal
                : StudioChatLifecycle.streaming,
          );
        }

        ThreadToolItemStateView tool(
          String name, {
          ThreadToolLifecycleView? lifecycle,
        }) => ThreadToolItemStateView(
          invocation: ThreadToolInvocationView(
            toolCallId: name,
            name: name,
            arguments: '{}',
          ),
          lifecycle:
              lifecycle ??
              SucceededThreadToolView(
                now,
                ThreadToolOutputView(
                  result: 'result',
                  attachments: name == 'read_alpha'
                      ? const [
                          ThreadAttachmentView(
                            id: 'ordinary-tool-image',
                            modality: AttachmentModalityView.image,
                            mediaType: 'image/png',
                            byteSize: 4,
                          ),
                        ]
                      : const [],
                  outputArtifacts: const [],
                ),
              ),
        );
        ThreadThinkingItemStateView thought(String text) =>
            ThreadThinkingItemStateView(
              summary: [text],
              content: const [],
              lifecycle: CompletedThreadContentView(now),
            );
        final harness = await _mountTimeline(
          tester,
          brightness: brightness,
          initialItems: [
            entry('thinking-a', 0, thought('first thought')),
            entry('read-a', 1, tool('read_alpha')),
            entry('thinking-b', 2, thought('thought after the tool')),
            entry(
              'text',
              3,
              ThreadTextItemStateView(
                channel: ThreadTextChannel.finalAnswer,
                text: 'Visible model narrative',
                attachments: const [],
                lifecycle: CompletedThreadContentView(now),
              ),
            ),
            entry('image', 4, tool('view_image')),
            entry(
              'terminal',
              5,
              const ThreadTurnItemStateView(
                CancelledStudioTurnState(
                  startedAt: 0,
                  requestedAt: 1,
                  completedAt: 2,
                  cause: UserRequestedTurnCancellation(),
                ),
              ),
            ),
            entry(
              'compaction',
              6,
              ThreadContextCompactionItemStateView(120, 40, now),
            ),
            entry(
              'read-b',
              7,
              tool(
                'read_beta',
                lifecycle: FailedThreadToolView(
                  now,
                  const ThreadToolFailureView(
                    kind: ThreadToolFailureKindView.execution,
                    message: 'fixture failed',
                  ),
                  null,
                ),
              ),
            ),
            entry(
              'read-c',
              8,
              tool(
                'read_gamma',
                lifecycle: const RunningThreadToolView('partial result'),
              ),
            ),
            entry(
              'agent',
              9,
              const ThreadAgentItemStateView(
                identity: ThreadAgentIdentityView(
                  id: 'child',
                  path: 'child-alpha',
                  role: 'explorer',
                  task: 'Inspect the fixture',
                  depth: 1,
                ),
                lifecycle: RunningThreadAgentView(),
              ),
            ),
          ],
        );
        final rows = harness.graph.timeline.source.value!.rows;
        expect(rows.map((row) => row.type.name), [
          'activityGroup',
          'finalAnswer',
          'imageRead',
          'turnOutcome',
          'contextCompaction',
          'activityGroup',
          'agentActivity',
        ]);
        expect(
          rows[3].entries.single.id,
          'terminal',
          reason:
              'terminal facts retain their canonical position within a window',
        );
        expect(rows.first.entries.map((part) => part.id), [
          'thinking-a',
          'read-a',
          'thinking-b',
        ]);
        expect(find.textContaining('child-alpha'), findsOneWidget);
        expect(find.text('Context automatically compacted'), findsOneWidget);
        expect(
          find.text('first thought'),
          findsNothing,
          reason: 'activity starts collapsed',
        );
        expect(
          find.textContaining('Failed ·'),
          findsOneWidget,
          reason: 'a later active tool cannot hide an earlier failure',
        );
        final summary = find.byKey(
          StudioDriverKeys.timelineActivitySummary(rows.first.id),
        );
        _timelinePosition(tester).jumpTo(0);
        await tester.pump();
        await tester.ensureVisible(summary);
        await tester.tap(summary);
        await tester.pumpAndSettle();
        expect(find.text('first thought'), findsOneWidget);
        expect(
          find.byKey(StudioDriverKeys.toolImageGallery('read-a')),
          findsOneWidget,
          reason: 'ordinary tools retain their typed image attachments',
        );
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
        await _closeTimeline(tester, harness);
      },
    );
  }

  for (final markdown in [false, true]) {
    testWidgets(
      'tool insertion preserves text order, selection and recycled rows (markdown: $markdown)',
      (tester) async {
        StudioChatItem entry(
          String id,
          int ordinal,
          ThreadItemStateView state, {
          int revision = 1,
        }) => StudioChatItem(
          ThreadItemView(
            id: id,
            threadId: 'thread-main',
            turnId: 'turn',
            ordinal: ordinal,
            revision: revision,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            state: state,
            saved: true,
            executionTerminal:
                state is! ThreadTextItemStateView || state.lifecycle.isTerminal,
          ),
          saved: true,
          lifecycle:
              state is ThreadTextItemStateView && !state.lifecycle.isTerminal
              ? StudioChatLifecycle.streaming
              : StudioChatLifecycle.terminal,
        );
        StudioChatItem tool(String id, int ordinal) => entry(
          id,
          ordinal,
          ThreadToolItemStateView(
            invocation: ThreadToolInvocationView(
              toolCallId: id,
              name: 'read_$id',
              arguments: '{}',
            ),
            lifecycle: SucceededThreadToolView(
              DateTime.utc(2026),
              const ThreadToolOutputView(
                result: 'read completed',
                attachments: [],
                outputArtifacts: [],
              ),
            ),
          ),
        );
        const marker = 'unique-body-selection';
        final bodyText = markdown
            ? '## 中文标题\n\n$marker readable model output with `src/config.dart`\n\n### 后续步骤\n\n第二段正文'
            : '$marker readable model output';
        ThreadTextItemStateView text(String value, {bool complete = false}) =>
            ThreadTextItemStateView(
              channel: ThreadTextChannel.finalAnswer,
              text: value,
              attachments: const [],
              lifecycle: complete
                  ? CompletedThreadContentView(DateTime.utc(2026))
                  : const StreamingThreadContentView(),
            );
        final harness = await _mountTimeline(
          tester,
          height: markdown ? 560 : 320,
          initialItems: [tool('alpha', 0), entry('body', 1, text(bodyText))],
        );
        harness.window.emit(
          StudioChatPatch(
            from: 1,
            to: 2,
            hasNewer: false,
            changes: [
              StudioViewSplice(index: 2, remove: 0, items: [tool('beta', 2)]),
            ],
          ),
        );
        await _pumpVersion(tester, harness.session, harness.window, 2);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        final rows = harness.graph.timeline.source.value!.rows;
        expect(
          rows,
          hasLength(3),
          reason: 'ordinary tools cannot cross model text',
        );
        expect(rows[1].id, 'body');
        final boxes = [
          for (final row in rows)
            tester.getRect(find.byKey(StudioDriverKeys.timelineBlock(row.id))),
        ];
        expect(boxes[0].top, lessThan(boxes[1].top));
        expect(boxes[1].top, lessThan(boxes[2].top));
        harness.window.emit(
          StudioChatPatch(
            from: 2,
            to: 3,
            hasNewer: false,
            changes: [
              StudioViewSplice(
                index: 1,
                remove: 1,
                items: [
                  entry('body', 1, text(bodyText, complete: true), revision: 2),
                ],
              ),
            ],
          ),
        );
        await _pumpVersion(tester, harness.session, harness.window, 3);
        String copied = '';
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        Future<void> copy() async {
          final region = tester.state<SelectableRegionState>(
            find.byType(SelectableRegion).first,
          );
          region.selectAll(SelectionChangedCause.keyboard);
          await tester.pump();
          final copy = region.contextMenuButtonItems.firstWhere(
            (item) => item.type == ContextMenuButtonType.copy,
          );
          expect(copy.onPressed, isNotNull);
          copy.onPressed!();
          await tester.pump();
          expect(tester.takeException(), isNull);
        }

        await copy();
        expect(copied, contains(marker));
        if (markdown) {
          expect(copied.indexOf('中文标题'), lessThan(copied.indexOf(marker)));
          expect(copied.indexOf(marker), lessThan(copied.indexOf('后续步骤')));
          expect(copied, contains('src/config.dart'));
          expect(copied, contains('第二段正文'));
        }
        harness.window.emit(
          StudioChatReset(
            StudioChatSnapshot(
              focusedItemId: null,
              version: 4,
              hasOlder: false,
              hasNewer: false,
              canExtendLatest: false,
              items: [
                for (var i = 0; i < 24; i++)
                  entry(
                    'replacement-$i',
                    i,
                    text('replacement-visible-$i', complete: true),
                  ),
              ],
            ),
          ),
        );
        await _pumpVersion(tester, harness.session, harness.window, 4);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
        expect(find.byType(ErrorWidget), findsNothing);
        await copy();
        expect(copied, contains('replacement-visible-'));
        expect(copied, isNot(contains(marker)));
        await _closeTimeline(tester, harness);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'cleared selection does not offer a stale copy in the context menu',
    (tester) async {
      final harness = await _mountTimeline(tester);
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion).first,
      );
      region.selectAll(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(
        region.contextMenuButtonItems.any(
          (item) => item.type == ContextMenuButtonType.copy,
        ),
        isTrue,
      );
      region.clearSelection();
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.byKey(StudioDriverKeys.timeline)),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Select all'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      region.hideToolbar();
      await _closeTimeline(tester, harness);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('offscreen focused code cannot publish a non-finite anchor', (
    tester,
  ) async {
    final harness = await _mountTimeline(
      tester,
      initialItems: [
        _item('first', text: '```text\nRetained code selection\n```'),
        _item('second', text: _streamingParagraphs(100)),
        _item('third'),
      ],
    );
    final position = _timelinePosition(tester);
    await tester.drag(
      find.byKey(StudioDriverKeys.timeline),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle();
    expect(_publishedScrollDiagnostic()['followingBottom'], isFalse);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    final first = find.byKey(
      StudioDriverKeys.timelineBlock('first'),
      skipOffstage: false,
    );
    expect(first, findsOneWidget);
    await tester.tap(
      find.descendant(of: first, matching: find.byType(SelectableText)).first,
    );
    await tester.pump();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: first, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    harness.commands.clear();
    position.jumpTo(position.maxScrollExtent);
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        first,
        findsOneWidget,
        reason: 'focused code keeps the row mounted',
      );
      expect(tester.getTopLeft(first).dy.isNaN, isTrue);
      final diagnostic = _publishedScrollDiagnostic();
      final anchor = diagnostic['anchor'] as Map?;
      if (anchor != null) {
        expect(anchor['itemId'], isNot('first'));
        expect((anchor['offset'] as num).isFinite, isTrue);
      }
      for (final command
          in harness.commands.whereType<TimelineAnchorChanged>()) {
        expect(command.anchor.offset.isFinite, isTrue);
      }
      final visible = harness.commands.whereType<TimelineVisibleBodies>();
      for (final command in visible) {
        expect(command.itemIds, isNot(contains('first')));
      }
      expect(position.pixels.isFinite, isTrue);
      expect(tester.takeException(), isNull);
    }
    await _closeTimeline(tester, harness);
  });

  testWidgets('initial long streaming body follows the real layout bottom', (
    tester,
  ) async {
    final harness = await _mountTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );

    final position = _timelinePosition(tester);
    expect(position.maxScrollExtent, greaterThan(position.viewportDimension));
    expect(
      position.extentAfter,
      lessThanOrEqualTo(2),
      reason:
          'followLatest must reach the actual bottom before any user scroll',
    );
    await _closeTimeline(tester, harness);
    expect(tester.takeException(), isNull);
  });

  testWidgets('row-only body growth keeps the window and follows the bottom', (
    tester,
  ) async {
    final harness = await _mountTimeline(tester);
    final structure = harness.graph.timeline.source.value!;
    expect(_timelinePosition(tester).extentAfter, lessThanOrEqualTo(2));

    for (var version = 2; version <= 3; version++) {
      harness.window.appendSecond(
        from: version - 1,
        to: version,
        expectedRevision: version - 1,
        text: '\n\n${_streamingParagraphs(80)}',
      );
      await _pumpVersion(tester, harness.session, harness.window, version);
      await tester.pumpAndSettle(const Duration(milliseconds: 16));

      expect(
        harness.graph.timeline.source.value!.orderedIds,
        structure.orderedIds,
        reason: '正文增量不改变窗口结构，只改变行的内容版本',
      );
      final position = _timelinePosition(tester);
      expect(position.maxScrollExtent, greaterThan(position.viewportDimension));
      expect(
        position.extentAfter,
        lessThanOrEqualTo(2),
        reason:
            'row revision $version left followLatest above the actual bottom',
      );
    }
    await _closeTimeline(tester, harness);
    expect(tester.takeException(), isNull);
  });

  testWidgets('body growth after an upward drag preserves the reading anchor', (
    tester,
  ) async {
    final harness = await _mountTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );
    expect(_timelinePosition(tester).extentAfter, lessThanOrEqualTo(2));

    await tester.drag(
      find.byKey(StudioDriverKeys.timeline),
      const Offset(0, 120),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 16));
    final before = _lastPublishedAnchor(harness.commands);
    expect(before.readingIntent, TimelineReadingIntent.browseHistory);
    expect(before.itemId, 'second');
    expect(_timelinePosition(tester).extentAfter, greaterThan(80));
    final rowOffset = _rowViewportOffset(tester, before.itemId);
    expect(before.offset, closeTo(rowOffset, 2));
    final structureIds = harness.graph.timeline.source.value!.orderedIds;

    harness.window.appendSecond(
      from: 1,
      to: 2,
      expectedRevision: 1,
      text: '\n\n${_streamingParagraphs(80)}',
    );
    await _pumpVersion(tester, harness.session, harness.window, 2);
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    final after = _lastPublishedAnchor(harness.commands);
    expect(harness.graph.timeline.source.value!.orderedIds, structureIds);
    expect(after.readingIntent, TimelineReadingIntent.browseHistory);
    expect(after.itemId, before.itemId);
    expect(after.offset, closeTo(before.offset, 2));
    expect(
      _rowViewportOffset(tester, before.itemId),
      closeTo(rowOffset, 2),
      reason: 'continued streaming must preserve the painted item and offset',
    );
    expect(_timelinePosition(tester).extentAfter, greaterThan(80));
    await _closeTimeline(tester, harness);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'row layout cannot cancel a drag before its first scroll update',
    (tester) async {
      var dragStarts = 0;
      var dragUpdates = 0;
      final harness = await _mountTimeline(
        tester,
        secondText: _streamingParagraphs(80),
        onScrollNotification: (notification) {
          if (notification.depth != 0) return;
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            dragStarts++;
          }
          if (notification is ScrollUpdateNotification &&
              notification.dragDetails != null) {
            dragUpdates++;
          }
        },
      );
      final position = _timelinePosition(tester);
      expect(position.extentAfter, lessThanOrEqualTo(2));
      final originalMaxExtent = position.maxScrollExtent;
      final originalUserDragUpdates = _publishedUserDragUpdates();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(StudioDriverKeys.timeline)),
      );
      var released = false;
      try {
        // DragStartBehavior.start consumes the slop-crossing move as onStart.
        // The next pointer event has not yet called applyUserOffset. This is an
        // actual DragScrollActivity, rather than the earlier pointer-down hold.
        await gesture.moveBy(const Offset(0, kTouchSlop + 1));
        expect(dragStarts, 1);
        expect(dragUpdates, 0);
        expect(position.isScrollingNotifier.value, isTrue);

        // Keep the same pointer down while a genuine row-only frame changes the
        // laid-out max extent. No list replacement or synthetic scroll is used.
        harness.window.appendSecond(
          from: 1,
          to: 2,
          expectedRevision: 1,
          text: '\n\n${_streamingParagraphs(80)}',
        );
        await _pumpVersion(tester, harness.session, harness.window, 2);
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(_timelinePosition(tester), same(position));
        expect(position.maxScrollExtent, greaterThan(originalMaxExtent));
        expect(dragUpdates, 0);
        expect(_publishedScrollDiagnostic()['isScrolling'], isTrue);
        final beforeContinuedMove = position.pixels;

        await gesture.moveBy(const Offset(0, 120));
        await tester.pump();

        expect(
          dragUpdates,
          greaterThan(0),
          reason:
              'row layout must retain the established drag until the next move',
        );
        expect(
          _publishedUserDragUpdates(),
          greaterThan(originalUserDragUpdates),
        );
        expect(position.pixels, lessThan(beforeContinuedMove - 80));
        expect(position.extentAfter, greaterThan(80));
        await gesture.up();
        released = true;
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        expect(_publishedScrollDiagnostic()['isScrolling'], isFalse);
        expect(
          _lastPublishedAnchor(harness.commands).readingIntent,
          TimelineReadingIntent.browseHistory,
        );
      } finally {
        if (!released) await gesture.up();
        await tester.pumpAndSettle(const Duration(milliseconds: 16));
        await _closeTimeline(tester, harness);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every held drag step publishes its current geometry', (
    tester,
  ) async {
    final harness = await _mountTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );
    final position = _timelinePosition(tester);
    final initialUpdates = _publishedUserDragUpdates();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(StudioDriverKeys.timeline)),
    );
    try {
      await gesture.moveBy(const Offset(0, kTouchSlop + 1));
      await tester.pump();
      for (var step = 1; step <= 4; step++) {
        final before = position.pixels;
        await gesture.moveBy(const Offset(0, 32));
        await tester.pump();
        expect(position.pixels, lessThan(before - 20));
        final diagnostic = _publishedScrollDiagnostic();
        expect(
          diagnostic['pixels'],
          closeTo(position.pixels, 0.5),
          reason: 'held drag step $step must publish before pointer up',
        );
        expect(diagnostic['userDragUpdates'], initialUpdates + step);
        expect(diagnostic['isScrolling'], isTrue);
      }
    } finally {
      await gesture.up();
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      await _closeTimeline(tester, harness);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a downward wheel at the clamped bottom resumes following', (
    tester,
  ) async {
    final harness = await _mountTimeline(
      tester,
      secondText: _streamingParagraphs(80),
    );
    try {
      await tester.drag(
        find.byKey(StudioDriverKeys.timeline),
        const Offset(0, 120),
      );
      await tester.pumpAndSettle();
      expect(_publishedScrollDiagnostic()['followingBottom'], isFalse);
      harness.window.emit(
        StudioChatPatch(
          from: 1,
          to: 2,
          changes: [
            StudioViewItemUpdate(
              itemId: 'second',
              expectedRevision: 1,
              revision: 2,
              omittedUnits: 0,
              saved: false,
              fields: const [
                StudioFieldUpdateView(
                  field: ThreadTextFieldView(),
                  change: ReplaceThreadFieldChangeView('short replacement'),
                ),
              ],
            ),
          ],
          hasNewer: false,
        ),
      );
      await _pumpVersion(tester, harness.session, harness.window, 2);
      await tester.pumpAndSettle();
      final position = _timelinePosition(tester);
      expect(position.extentAfter, closeTo(0, .5));
      expect(_publishedScrollDiagnostic()['followingBottom'], isFalse);
      final beforePixels = position.pixels;
      harness.commands.clear();

      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(find.byKey(StudioDriverKeys.timeline)),
          scrollDelta: const Offset(0, 200),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        position.pixels,
        beforePixels,
        reason: 'the edge consumes no displacement',
      );
      expect(_publishedScrollDiagnostic()['followingBottom'], isTrue);
      expect(harness.commands.whereType<TimelineJumpToLatest>(), hasLength(1));
    } finally {
      await _closeTimeline(tester, harness);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unchanged plain body keeps its layout under inherited height behavior',
    (tester) async {
      final text = List.generate(
        3000,
        (index) => 'body-${index.toString().padLeft(5, '0')} ${'W' * 20} ',
      ).join();
      final harness = await _mountTimeline(
        tester,
        secondText: text,
        textHeightBehavior: const TextHeightBehavior(
          applyHeightToFirstAscent: false,
          applyHeightToLastDescent: false,
        ),
      );
      final body = find.byKey(const ValueKey('plain-second'));
      final before = tester.getSize(body).height;
      try {
        for (var version = 2; version <= 4; version++) {
          harness.window.appendSecond(
            from: version - 1,
            to: version,
            expectedRevision: version - 1,
            text: '',
          );
          await _pumpVersion(tester, harness.session, harness.window, version);
          await tester.pumpAndSettle();
          expect(harness.session.state.items[1].text, text);
          expect(
            tester.getSize(body).height,
            closeTo(before, .5),
            reason: 'unchanged text moved on row revision $version',
          );
        }
      } finally {
        await _closeTimeline(tester, harness);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('streamed and replaced plain bodies match a fresh layout', (
    tester,
  ) async {
    final text = List.generate(
      1800,
      (index) => 'body-${index.toString().padLeft(5, '0')} ${'W' * 20} ',
    ).join();
    const heightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    );
    final harness = await _mountTimeline(
      tester,
      secondText: text.substring(0, 5200),
      textHeightBehavior: heightBehavior,
    );
    final body = find.byKey(const ValueKey('plain-second'));
    late final double streamedHeight;
    late final double replacedHeight;
    final replacement = text.substring(0, 5100) + 'updated ' * 1100;
    try {
      var start = 5200;
      var version = 1;
      for (final end in [11700, text.length]) {
        harness.window.appendSecond(
          from: version,
          to: version + 1,
          expectedRevision: version,
          text: text.substring(start, end),
        );
        version++;
        start = end;
        await _pumpVersion(tester, harness.session, harness.window, version);
        await tester.pumpAndSettle();
      }
      expect(harness.session.state.items[1].text, text);
      streamedHeight = tester.getSize(body).height;
      harness.window.emit(
        StudioChatPatch(
          from: version,
          to: version + 1,
          changes: [
            StudioViewItemUpdate(
              itemId: 'second',
              expectedRevision: version,
              revision: version + 1,
              omittedUnits: 0,
              saved: false,
              fields: [
                StudioFieldUpdateView(
                  field: const ThreadTextFieldView(),
                  change: ReplaceThreadFieldChangeView(replacement),
                ),
              ],
            ),
          ],
          hasNewer: false,
        ),
      );
      await _pumpVersion(tester, harness.session, harness.window, version + 1);
      await tester.pumpAndSettle();
      expect(harness.session.state.items[1].text, replacement);
      replacedHeight = tester.getSize(body).height;
    } finally {
      await _closeTimeline(tester, harness);
    }

    for (final (canonical, expectedHeight) in [
      (text, streamedHeight),
      (replacement, replacedHeight),
    ]) {
      final fresh = await _mountTimeline(
        tester,
        secondText: canonical,
        textHeightBehavior: heightBehavior,
      );
      try {
        expect(tester.getSize(body).height, closeTo(expectedHeight, .5));
        final rendered = tester
            .widgetList<Text>(
              find.descendant(of: body, matching: find.byType(Text)),
            )
            .map((chunk) => chunk.data ?? chunk.textSpan!.toPlainText())
            .join();
        expect(rendered, canonical, reason: 'partitioning must preserve bytes');
      } finally {
        await _closeTimeline(tester, fresh);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('evicted rows leave the window and the mounted list', (
    tester,
  ) async {
    final transport = RecordingDemoTransport();
    final window = _ControlledWindow();
    transport.chatWindowFactory = (threadId, demoWindow) async {
      demoWindow.requestClose();
      await demoWindow.close();
      return window;
    };
    final graph = AppGraph(transport: transport, clientId: 'row-window');
    addTearDown(
      () => pumpClientFuture(
        tester,
        graph.close(deadline: _deadline()),
        'row teardown close',
      ),
    );
    await pumpClientFuture(tester, graph.client.bootstrap(), 'row bootstrap');
    await pumpClientFuture(
      tester,
      graph.client.directoryCommands.selectThread('thread-main'),
      'row select',
    );
    final session = graph.client.existingSession('thread-main')!;
    await _pumpVersion(tester, session, window, 1);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final latest = ref.watch(timelineSessionWindowProvider)!;
                return TimelineView(
                  threadId: latest.threadId,
                  viewId: latest.viewId,
                  rows: latest.rows,
                  body: latest.history,
                  turn: latest.turn,
                  onCommand: (_) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('first', findRichText: true), findsWidgets);

    window.emit(
      const StudioChatPatch(
        from: 1,
        to: 2,
        changes: [StudioViewSplice(index: 0, remove: 1, items: [])],
        hasNewer: false,
      ),
    );
    await _pumpVersion(tester, session, window, 2);
    await tester.pumpAndSettle();

    expect(graph.timeline.source.value!.orderedIds, [
      'second',
      'third',
    ], reason: '淘汰只由 canonical 窗口决定');
    expect(find.text('first', findRichText: true), findsNothing);
    expect(find.text('second', findRichText: true), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: _deadline()),
      'row close',
    );
    expect(tester.takeException(), isNull);
  });
}

class _ControlledWindow implements StudioChatWindow {
  _ControlledWindow({this.secondText = 'second', this.initialItems});

  final List<StudioChatItem>? initialItems;

  final String secondText;
  Completer<StudioChatFrame?>? _next;
  Completer<void> nextRequested = Completer<void>();
  bool _closed = false;

  @override
  Future<StudioChatSnapshot> initial() async => StudioChatSnapshot(
    focusedItemId: null,
    version: 1,
    items:
        initialItems ??
        [
          for (final id in ['first', 'second', 'third'])
            _item(id, text: id == 'second' ? secondText : null),
        ],
    hasOlder: false,
    hasNewer: false,
    canExtendLatest: false,
  );

  @override
  Future<StudioChatFrame?> next() {
    if (_closed) return Future.value(null);
    if (_next != null) throw StateError('Two unfinished next calls');
    _next = Completer<StudioChatFrame?>();
    nextRequested.complete();
    return _next!.future;
  }

  void emit(StudioChatFrame frame) {
    final pending = _next!;
    _next = null;
    nextRequested = Completer<void>();
    pending.complete(frame);
  }

  void appendSecond({
    required int from,
    required int to,
    required int expectedRevision,
    required String text,
  }) => emit(
    StudioChatPatch(
      from: from,
      to: to,
      changes: [
        StudioViewItemUpdate(
          itemId: 'second',
          expectedRevision: expectedRevision,
          revision: expectedRevision + 1,
          omittedUnits: 0,
          saved: false,
          fields: [
            StudioFieldUpdateView(
              field: const ThreadTextFieldView(),
              change: AppendThreadFieldChangeView(text),
            ),
          ],
        ),
      ],
      hasNewer: false,
    ),
  );

  @override
  void requestClose() {
    _closed = true;
    _next?.complete(null);
    _next = null;
  }

  @override
  Future<void> close() async => requestClose();
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No control commands are used in this row test');
}

StudioChatItem _item(String id, {String? text}) {
  final now = DateTime.utc(2026);
  final streaming = id == 'second';
  return StudioChatItem(
    ThreadItemView(
      id: id,
      threadId: 'thread-main',
      turnId: 'turn',
      ordinal: ['first', 'second', 'third'].indexOf(id),
      revision: 1,
      createdAt: now,
      updatedAt: now,
      state: ThreadTextItemStateView(
        channel: streaming
            ? ThreadTextChannel.finalAnswer
            : ThreadTextChannel.user,
        text: text ?? id,
        attachments: const [],
        lifecycle: streaming
            ? const StreamingThreadContentView()
            : CompletedThreadContentView(now),
      ),
    ),
    saved: !streaming,
    lifecycle: streaming
        ? StudioChatLifecycle.streaming
        : StudioChatLifecycle.terminal,
  );
}

final class _TimelineHarness {
  _TimelineHarness({
    required this.graph,
    required this.window,
    required this.session,
  });

  final AppGraph graph;
  final _ControlledWindow window;
  final StudioThreadSession session;
  final List<TimelineCommand> commands = [];
}

Future<_TimelineHarness> _mountTimeline(
  WidgetTester tester, {
  String secondText = 'second',
  List<StudioChatItem>? initialItems,
  ValueChanged<ScrollNotification>? onScrollNotification,
  TextHeightBehavior textHeightBehavior = const TextHeightBehavior(),
  Brightness brightness = Brightness.light,
  double height = 320,
}) async {
  final transport = RecordingDemoTransport();
  final window = _ControlledWindow(
    secondText: secondText,
    initialItems: initialItems,
  );
  transport.chatWindowFactory = (threadId, demoWindow) async {
    demoWindow.requestClose();
    await demoWindow.close();
    return window;
  };
  final graph = AppGraph(transport: transport, clientId: 'follow-layout');
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: _deadline()),
      'follow-layout teardown close',
    );
  });
  await pumpClientFuture(tester, graph.client.bootstrap(), 'follow bootstrap');
  await pumpClientFuture(
    tester,
    graph.client.directoryCommands.selectThread('thread-main'),
    'follow select',
  );
  final session = graph.client.existingSession('thread-main')!;
  await _pumpVersion(tester, session, window, 1);
  final harness = _TimelineHarness(
    graph: graph,
    window: window,
    session: session,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGraphProvider.overrideWithValue(graph)],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              height: height,
              child: DefaultTextHeightBehavior(
                textHeightBehavior: textHeightBehavior,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    onScrollNotification?.call(notification);
                    return false;
                  },
                  child: Consumer(
                    builder: (context, ref, _) {
                      final latest = ref.watch(timelineSessionWindowProvider)!;
                      return TimelineView(
                        threadId: latest.threadId,
                        viewId: latest.viewId,
                        windowEpoch: latest.history.epoch,
                        rows: latest.rows,
                        body: latest.history,
                        turn: null,
                        onCommand: harness.commands.add,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
  return harness;
}

Future<void> _closeTimeline(
  WidgetTester tester,
  _TimelineHarness harness,
) async {
  // testWidgets checks its pending timers before addTearDown runs. Successful
  // journeys must finish their owner here; teardown remains a failure fallback.
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpClientFuture(
    tester,
    harness.graph.close(deadline: _deadline()),
    'follow-layout close',
  );
}

ScrollPosition _timelinePosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(StudioDriverKeys.timeline),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Map<String, dynamic> _publishedScrollDiagnostic() {
  final snapshot = jsonDecode(
    StudioDriverState.snapshotJson(observed: StudioDriverFacts()),
  ) as Map<String, dynamic>;
  return snapshot['timelineScroll'] as Map<String, dynamic>;
}

int _publishedUserDragUpdates() =>
    _publishedScrollDiagnostic()['userDragUpdates'] as int;

TimelineAnchor _lastPublishedAnchor(List<TimelineCommand> commands) {
  final anchors = commands.whereType<TimelineAnchorChanged>().toList();
  expect(anchors, isNotEmpty, reason: 'a settled drag must publish its anchor');
  return anchors.last.anchor;
}

double _rowViewportOffset(WidgetTester tester, String itemId) =>
    tester.getTopLeft(find.byKey(StudioDriverKeys.timelineBlock(itemId))).dy -
    tester.getTopLeft(find.byKey(StudioDriverKeys.timeline)).dy;

String _streamingParagraphs(int count) => List.generate(
  count,
  (index) => 'Streaming paragraph $index keeps a visible reading anchor.',
).join('\n\n');

Future<void> _pumpVersion(
  WidgetTester tester,
  StudioThreadSession session,
  _ControlledWindow window,
  int version,
) async {
  // Every frame is released by emit, so processing needs microtasks and widget
  // frames, never wall-clock time. A rejected frame must fail with its owner
  // error instead of waiting forever while FakeAsync holds a retry timer.
  for (var frame = 0; frame < 64; frame++) {
    await tester.runAsync(() async {});
    await tester.pump();
    expect(
      tester.takeException(),
      isNull,
      reason: 'version=$version frame=$frame',
    );
    final chat = session.chat.state.value;
    final Object? error = switch (chat) {
      ChatReconnecting<StudioChatSnapshot>(:final error) => error,
      ChatFailed<StudioChatSnapshot>(:final error) => error,
      _ => null,
    };
    if (error != null) {
      fail('ChatView rejected version $version: $error');
    }
    if (session.state.chatVersion == version &&
        window.nextRequested.isCompleted) {
      return;
    }
  }
  fail(
    'ChatView did not deliver version $version; '
    'observed=${session.state.chatVersion}, '
    'sync=${session.state.sync.phase}, '
    'error=${session.state.sync.errorMessage}',
  );
}

DateTime _deadline() => DateTime.now().add(const Duration(seconds: 5));
