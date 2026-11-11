import 'display_record_observation.dart';

import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const timelineConceptImagePrompt = '读取三张设计截图，并说明无法读取的图片。';

// A nonempty canonical attachment list is required before checking media;
// every() on a Deferred head's empty list must never count as UI evidence.
Future<void> waitForTimelineConceptInputImages(
  WidgetTester tester,
  ChatItemPresentation item, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  expect(item.compatibility, ChatItemCompatibility.current);
  expect(item.atom!.kind, ChatAtomKind.input);
  final attachments = item.attachments;
  expect(attachments, hasLength(3));
  expect(attachments.map((attachment) => attachment.id).toSet(), hasLength(3));
  final card = find.byWidgetPredicate(
    (widget) => widget is ChatItemView && identical(widget.item, item),
  );
  final deadline = tester.binding.clock.fromNowBy(timeout);
  while (true) {
    expect(card, findsOneWidget);
    final views = tester
        .widgetList<TimelineImageView>(
          find.descendant(of: card, matching: find.byType(TimelineImageView)),
        )
        .toList();
    for (final view in views) {
      expect(view.itemId, item.id);
      if (view.error case final error?) throw StateError('$error');
    }
    if (views.length == attachments.length) {
      expect(
        views.map((view) => view.attachment.id),
        orderedEquals(attachments.map((attachment) => attachment.id)),
      );
      if (views.every(
        (view) =>
            view.active &&
            !view.isTool &&
            view.bytes != null &&
            view.bytes!.isNotEmpty &&
            view.width == view.attachment.width &&
            view.height == view.attachment.height,
      )) {
        return;
      }
    }
    if (!tester.binding.clock.now().isBefore(deadline)) {
      fail('Three real input images did not become readable for ${item.id}');
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
  }
}

const _filenames = [
  'concept-input-a.png',
  'concept-input-b.png',
  'concept-input-c.png',
];
const _sides = [512, 256, 128];

/// Identity from the production composer's frozen submission, not a fabricated
/// input/item ID. The native journey must still locate this InputChatSource in
/// its real controller metadata and inspect that single item's attachments.
final class TimelineConceptImageInput {
  TimelineConceptImageInput({
    required this.threadId,
    required this.inputId,
    required List<AttachmentDraftView> drafts,
    this.prompt = timelineConceptImagePrompt,
  }) : drafts = List.unmodifiable(drafts);

  final String threadId;
  final String inputId;
  final List<AttachmentDraftView> drafts;
  final String prompt;

  /// Call with the completed entry and attachment refs from ONE Main message.
  /// Returns identities to archive alongside the later layout assertions.
  Map<String, Object?> verifyItem(
    TimelineDisplayUnit item,
    List<ThreadAttachmentView> attachments,
  ) {
    expect(item.body, isA<SingleDisplayBlock>());
    expect(item.atom!.kind, ChatAtomKind.input);
    expect(item.atom!.source, InputChatSource(inputId: inputId));
    expect(item.id, isNotEmpty);
    expect(
      completedOriginalId((item.body as SingleDisplayBlock).record),
      isNotEmpty,
    );
    expect(item.historyPos, greaterThan(0));
    expect(item.atom!.completionSeq, greaterThan(0));
    expect(attachments, hasLength(3));
    expect(attachments.map((item) => item.id).toSet(), hasLength(3));
    for (var index = 0; index < attachments.length; index++) {
      final actual = attachments[index];
      final draft = drafts[index];
      expect(actual.modality, AttachmentModalityView.image);
      expect(actual.mediaType, draft.mediaType);
      expect(actual.filename, draft.filename);
      expect(actual.byteSize, draft.byteSize);
      expect(actual.width, draft.width);
      expect(actual.height, draft.height);
    }
    return {
      ...toJson(),
      'itemId': item.id,
      'contentItemId': completedOriginalId(
        (item.body as SingleDisplayBlock).record,
      ),
      'historyPos': item.historyPos,
      'completionSeq': item.atom!.completionSeq,
      'attachmentResourceIds': attachments.map((item) => item.id).toList(),
    };
  }

  /// Uses the final journey's production widget finders, scoped to ONE item.
  /// No dependency on an in-flight owner/key/Driver DTO contract.
  Map<String, Object?> verifyHorizontalLayout(
    WidgetTester tester, {
    required TimelineDisplayUnit item,
    required List<ThreadAttachmentView> attachments,
    required Finder itemFinder,
    required Finder Function(String resourceId) thumbnailFinder,
  }) {
    final evidence = verifyItem(item, attachments);
    expect(itemFinder, findsOneWidget);
    final rectangles = <Rect>[];
    for (final attachment in attachments) {
      final thumbnail = find.descendant(
        of: itemFinder,
        matching: thumbnailFinder(attachment.id),
      );
      expect(thumbnail, findsOneWidget);
      final rectangle = tester.getRect(thumbnail);
      expect(rectangle.width, greaterThan(0));
      expect(rectangle.height, greaterThan(0));
      if (rectangles.isNotEmpty) {
        expect(rectangle.top, closeTo(rectangles.first.top, 1));
        expect(rectangle.left, greaterThanOrEqualTo(rectangles.last.right));
      }
      rectangles.add(rectangle);
    }
    return {
      ...evidence,
      'thumbnailRects': [
        for (final rectangle in rectangles)
          {
            'left': rectangle.left,
            'top': rectangle.top,
            'width': rectangle.width,
            'height': rectangle.height,
          },
      ],
    };
  }

  Map<String, Object?> toJson() => {
    'threadId': threadId,
    'inputId': inputId,
    'prompt': prompt,
    'attachments': [
      for (final draft in drafts)
        {
          'draftId': draft.id,
          'filename': draft.filename,
          'mediaType': draft.mediaType,
          'byteSize': draft.byteSize,
          'width': draft.width,
          'height': draft.height,
        },
    ],
  };
}

/// Use for the existing IMAGE_PROMPT step, after the thread has a model route.
/// Imports real local files through the production SDK; does NOT exercise the
/// native file picker. Submits via the production composer widget exactly once.
/// Does not inspect or reproduce the timeline owner's grouping algorithm.
Future<TimelineConceptImageInput> submitTimelineConceptImageInput(
  WidgetTester tester,
  AppGraph graph, {
  required String threadId,
  required String projectPath,
  String prompt = timelineConceptImagePrompt,
  Future<void> Function()? beforeSubmit,
}) async {
  expect(graph.client.selection.state.selectedThreadId, threadId);
  final composer = graph.client.drafts.composer(threadId);
  expect(composer.state, isA<IdleComposerThreadState>());
  expect(composer.state.draft, isEmpty);
  expect(composer.state.attachments, isEmpty);
  expect(composer.state.failure, isNull);
  final paths = [
    for (final name in _filenames) '$projectPath${Platform.pathSeparator}$name',
  ];
  final lengths = [for (final path in paths) await File(path).length()];
  await composer.addLocalAttachments(paths);
  expect(composer.state.failure, isNull);
  final drafts = List<AttachmentDraftView>.of(composer.state.attachments);
  expect(drafts, hasLength(3));
  expect(drafts.map((draft) => draft.id).toSet(), hasLength(3));
  for (var index = 0; index < drafts.length; index++) {
    final draft = drafts[index];
    expect(draft.modality, AttachmentModalityView.image);
    expect(draft.filename, _filenames[index]);
    expect(draft.mediaType, 'image/png');
    expect(draft.byteSize, lengths[index]);
    expect(draft.width, _sides[index]);
    expect(draft.height, _sides[index]);
  }
  await tester.pump();
  expect(find.byKey(StudioDriverKeys.attachmentDraftRail), findsOneWidget);
  for (final draft in drafts) {
    expect(
      find.byKey(StudioDriverKeys.attachmentDraft(draft.id)),
      findsOneWidget,
    );
  }
  final input = find.byKey(const ValueKey('composer-input'));
  expect(input, findsOneWidget);
  await tester.enterText(input, prompt);
  await tester.pump();
  expect(composer.state.draft, prompt);
  expect(graph.client.selection.state.selectedThreadId, threadId);
  if (beforeSubmit != null) await beforeSubmit();

  // The editor immediately becomes the next draft. Observe the handed-off
  // submission instead of waiting for the retired editor Submitting state.
  final existingInputIds = {
    for (final submission in composer.submissions.value) submission.inputId,
  };
  final frozen = <String, ComposerSubmission>{};
  final watch = composer.submissions.watchLatest((submissions) {
    for (final submission in submissions) {
      if (!existingInputIds.contains(submission.inputId)) {
        frozen[submission.inputId] = submission;
      }
    }
  });
  final session = graph.client.conversations.session(threadId);
  bool accepted() =>
      frozen.values.any(
        (submission) => submission.phase == ComposerSubmissionPhase.accepted,
      ) ||
      // Canonical presentation can retire the local item before the RPC
      // receipt. The exact input identity is independent acceptance evidence.
      frozen.containsKey(session.state.lastTurn?.inputId);
  try {
    final send = find.byKey(StudioDriverKeys.composerSubmit);
    expect(send.hitTestable(), findsOneWidget);
    await tester.tap(send);
    final clock = Stopwatch()..start();
    while (frozen.isEmpty || !accepted()) {
      expect(composer.state.failure, isNull);
      for (final submission in frozen.values) {
        expect(
          submission.phase,
          isNot(ComposerSubmissionPhase.failed),
          reason: '${submission.error}',
        );
        expect(
          submission.phase,
          isNot(ComposerSubmissionPhase.unknownOutcome),
          reason: 'The image submission must have confirmed acceptance',
        );
      }
      if (clock.elapsed > const Duration(seconds: 60)) {
        fail('Timed out awaiting one accepted multi-image composer submission');
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    expect(frozen, hasLength(1));
    final submitted = frozen.values.single;
    expect(submitted.inputId, isNotEmpty);
    expect(submitted.text, prompt);
    expect(
      submitted.attachments.map((draft) => draft.id),
      orderedEquals(drafts.map((draft) => draft.id)),
    );
    expect(composer.state.draft, isEmpty);
    expect(composer.state.attachments, isEmpty);
    return TimelineConceptImageInput(
      threadId: threadId,
      inputId: submitted.inputId,
      drafts: drafts,
      prompt: prompt,
    );
  } finally {
    watch.observation.cancel();
  }
}
