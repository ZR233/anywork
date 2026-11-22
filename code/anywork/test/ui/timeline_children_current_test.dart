import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_children_connector.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_member_atom.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/chat_item_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show ConversationFixture, TestHistoryReader;
import '../support/pump_client_future.dart';

HistoryEventRecord _record(String id, int seq) => HistoryEventRecord(
  seq: seq,
  eventId: 'event:$id',
  kind: 'text_completed',
  timelineRole: HistoryTimelineRole.hidden,
  recordedAt: seq,
  entityId: id,
  rowKey: 'row:$id',
  source: const ReceiptChatSource(receiptId: 'receipt'),
  payloadSchema: 'anywork.event/1',
  payloadJson: jsonEncode({
    'contract': 'anywork.event/1',
    'type': 'text',
    'meta': {
      'entityId': id,
      'entityKind': 'text',
      'delivery': 'independent',
      'state': {'kind': 'knownTerminal', 'outcome': 'completed'},
      'contentPresent': false,
    },
    'data': {'channel': 'final'},
    'bodies': <Object?>[],
  }),
);

Widget _host(ConversationFixture fixture, {required String parentId}) =>
    MaterialApp(
      key: ValueKey('children-host:$parentId'),
      theme: pureStudioTheme(),
      locale: const Locale('zh'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: TimelineChildrenConnector(
          key: ValueKey(parentId),
          repository: fixture.repository,
          threadId: 'thread',
          parentId: parentId,
        ),
      ),
    );

List<String> _rowIds(WidgetTester tester) => tester
    .widgetList<Widget>(
      find.byWidgetPredicate(
        (widget) => widget is ChatItemView || widget is TimelineMemberAtom,
        // These deliberately empty text heads have zero paint extent. This case checks
        // admitted row identity; real content layout is covered by its own widget tests.
        skipOffstage: false,
      ),
    )
    .map(
      (widget) => widget is ChatItemView
          ? widget.item.id
          : (widget as TimelineMemberAtom).displayId,
    )
    .toList();

void main() {
  testWidgets('children retain one fixed cut and reject a retired older page', (
    tester,
  ) async {
    final fixture = ConversationFixture();
    addTearDown(fixture.close);
    final readers = <TestHistoryReader>[];
    final olderA = Completer<HistoryEventsPage>();
    fixture.transport.historyReaderFactory = (threadId, index) {
      final reader = TestHistoryReader(threadId: threadId);
      readers.add(reader);
      reader.onEvents = (query, cut, cursor, demand) async {
        expect(query, isA<OriginalsHistoryEvents>());
        if (index == 0) {
          if (cursor == null) {
            return HistoryEventsPage(
              cut: reader.cut,
              entries: [_record('A-initial', 2)],
              next: 'older-a',
            );
          }
          expect(cut, same(reader.cut));
          return olderA.future;
        }
        expect(cursor, isNull);
        return HistoryEventsPage(
          cut: reader.cut,
          entries: [_record('B-initial', 4)],
        );
      };
      return reader;
    };

    await tester.pumpWidget(_host(fixture, parentId: 'parent-a'));
    await pumpClientUntil(tester, () {
      final ids = _rowIds(tester);
      return ids.length == 1 && ids.single == 'row:A-initial';
    }, 'first children page');
    expect(_rowIds(tester), ['row:A-initial']);
    await tester.tap(
      find.byKey(const ValueKey('timeline-children-load-older')),
    );
    await tester.pump();

    await tester.pumpWidget(_host(fixture, parentId: 'parent-b'));
    await pumpClientUntil(tester, () {
      final ids = _rowIds(tester);
      return ids.length == 1 && ids.single == 'row:B-initial';
    }, 'replacement children page');
    expect(_rowIds(tester), ['row:B-initial']);

    olderA.complete(
      HistoryEventsPage(
        cut: readers.first.cut,
        entries: [_record('A-late', 1)],
      ),
    );
    await tester.pumpAndSettle();
    expect(_rowIds(tester), ['row:B-initial']);
    expect(readers.first.requestCloseCalls, greaterThanOrEqualTo(1));
    expect(readers.first.closeCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
