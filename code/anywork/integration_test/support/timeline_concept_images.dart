import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const timelineConceptImagePrompt = '读取三张设计截图，并说明无法读取的图片。';
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
  }) : drafts = List.unmodifiable(drafts);

  final String threadId;
  final String inputId;
  final List<AttachmentDraftView> drafts;

  /// Call with the completed entry and attachment refs from ONE Main message.
  /// Returns identities to archive alongside the later layout assertions.
  Map<String, Object?> verifyItem(
    CompletedEntry item,
    List<ThreadAttachmentView> attachments,
  ) {
    expect(item.mainPresentation, MainPresentation.single);
    expect(item.atom.kind, ChatAtomKind.input);
    expect(item.atom.source, InputChatSource(inputId: inputId));
    expect(item.recordId, isNotNull);
    expect(item.recordId, isNotEmpty);
    expect(item.completionSeq, greaterThan(0));
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
      'itemId': item.recordId,
      'contentItemId': item.recordId,
      'attachmentResourceIds': attachments.map((item) => item.id).toList(),
    };
  }

  /// Uses the final journey's production widget finders, scoped to ONE item.
  /// No dependency on an in-flight owner/key/Driver DTO contract.
  Map<String, Object?> verifyHorizontalLayout(
    WidgetTester tester, {
    required CompletedEntry item,
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
    'prompt': timelineConceptImagePrompt,
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
  await tester.enterText(input, timelineConceptImagePrompt);
  await tester.pump();
  expect(composer.state.draft, timelineConceptImagePrompt);
  expect(graph.client.selection.state.selectedThreadId, threadId);

  // Register before the tap: a fast submit can return to Idle before a pump.
  // Observe the existing source synchronously, without a test product API.
  final frozen = <SubmittingComposerThreadState>[];
  final watch = composer.source.watchLatest((state) {
    if (state is SubmittingComposerThreadState) frozen.add(state);
  });
  try {
    await tester.tap(find.byKey(const ValueKey('composer-submit')));
    final clock = Stopwatch()..start();
    while (frozen.isEmpty || composer.state is! IdleComposerThreadState) {
      expect(composer.state.failure, isNull);
      if (clock.elapsed > const Duration(seconds: 60)) {
        fail('Timed out awaiting one accepted multi-image composer submission');
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    expect(frozen.map((state) => state.inputId).toSet(), hasLength(1));
    final submitted = frozen.first;
    expect(submitted.inputId, isNotEmpty);
    expect(submitted.draft, timelineConceptImagePrompt);
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
    );
  } finally {
    watch.observation.cancel();
  }
}
