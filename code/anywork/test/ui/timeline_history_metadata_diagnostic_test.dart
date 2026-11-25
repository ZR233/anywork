import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_history_projection.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_image_resources.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

HistoryEventRecord _event({
  required int seq,
  required String kind,
  bool malformed = false,
  bool unavailable = false,
}) => HistoryEventRecord(
  seq: seq,
  eventId: 'event-$seq',
  entityId: 'entity-$seq',
  kind: kind,
  timelineRole: HistoryTimelineRole.boundary,
  recordedAt: 1000,
  occurredAt: 1000,
  payloadSchema: 'anywork.event/1',
  payloadJson: jsonEncode({
    'contract': 'anywork.event/1',
    'type': 'text',
    if (kind != 'text_completed') 'capturedAt': 6000,
    'meta': {
      'entityId': 'entity-$seq',
      'contentPresent': malformed ? 'yes' : !unavailable,
      'textChannel': 'final',
    },
    'data': {'channel': 'final', 'legacyUnavailable': unavailable},
    'bodies': [
      if (!unavailable)
        {'key': 'body', 'byteLength': 15, 'inlineText': '正常后续行'},
    ],
  }),
);

Widget _host(List<Widget> rows) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    ),
  ),
);

void main() {
  for (final route in ['forUnit', 'member']) {
    for (final kind in ['boundary_observed', 'legacy_observed']) {
      testWidgets(
        '$route $kind malformed frozen metadata exposes its diagnostic',
        (tester) async {
          final damaged = _event(seq: 1, kind: kind, malformed: true);
          final blocks = TimelineHistoryProjection.blocksFromEntries([
            HistoryTimelineEntry(event: damaged, hasFoldedAfter: false),
            HistoryTimelineEntry(
              event: _event(seq: 2, kind: 'text_completed'),
              hasFoldedAfter: false,
            ),
          ], cut: const HistoryCut('fixed-cut'));
          final resources = TimelineImageResources(threadId: 'thread');
          addTearDown(resources.release);
          final units = [
            for (final block in blocks) TimelineDisplayUnit(block: block),
          ];
          Widget row(TimelineDisplayUnit unit) {
            if (route == 'forUnit') {
              return ChatItemView(
                item: ChatItemPresentation.forUnit(unit),
                bodyBuilder: (_, text) => Text(text),
              );
            }
            return TimelineMemberAtom(
              record: (unit.body as SingleDisplayBlock).record,
              displayId: unit.id,
              threadId: 'thread',
              isActive: () => true,
              images: resources,
              readAttachment: null,
            );
          }

          await tester.pumpWidget(_host([for (final unit in units) row(unit)]));
          await tester.pumpAndSettle();

          expect(find.text('内容格式错误'), findsOneWidget);
          await tester.tap(find.text('内容格式错误'));
          await tester.pumpAndSettle();
          expect(find.text('Invalid meta.contentPresent'), findsOneWidget);
          final raw = tester.widget<SelectableText>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is SelectableText &&
                  widget.data == damaged.payloadJson,
            ),
          );
          expect(raw.data, damaged.payloadJson);
          expect(find.text('正常后续行'), findsOneWidget);
          expect(find.text('旧边界观察不可用'), findsNothing);
          final record = (blocks.first.body as SingleDisplayBlock).record;
          expect(record.atom.id, 'entity-1');
          expect(record.historyDetailEventId, damaged.eventId);
          expect(record.isFrozenHistory, isTrue);
          final frozen = record.contentSource as FrozenObservation;
          expect(frozen.available, isFalse);
          expect(frozen.capturedAt, 6000);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          for (final unit in units) {
            unit.expansion.dispose();
          }
        },
      );

      testWidgets(
        '$route $kind genuine unavailable observation keeps its meaning',
        (tester) async {
          final block = TimelineHistoryProjection.directBlock(
            _event(seq: 1, kind: kind, unavailable: true),
          );
          final unit = TimelineDisplayUnit(block: block);
          final record = (block.body as SingleDisplayBlock).record;
          final resources = TimelineImageResources(threadId: 'thread');
          addTearDown(resources.release);
          await tester.pumpWidget(
            _host([
              if (route == 'forUnit')
                ChatItemView(item: ChatItemPresentation.forUnit(unit))
              else
                TimelineMemberAtom(
                  record: record,
                  displayId: unit.id,
                  threadId: 'thread',
                  isActive: () => true,
                  images: resources,
                  readAttachment: null,
                ),
            ]),
          );
          await tester.pumpAndSettle();
          expect(find.text('旧边界观察不可用'), findsOneWidget);
          expect(find.text('内容格式错误'), findsNothing);
          expect(find.byType(SelectableText), findsNothing);
          expect(
            (record.contentSource as FrozenObservation).available,
            isFalse,
          );
          expect((record.contentSource as FrozenObservation).capturedAt, 6000);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          unit.expansion.dispose();
        },
      );
    }
  }
}
