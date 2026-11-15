import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_content_range_view.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_content_connector.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const ref = ContentRef(
  databaseId: 'db',
  target: BodyContentTarget(
    owner: ItemContentOwner(itemId: 'item'),
    key: 'tool.result',
  ),
);
ContentWindow full(String text) {
  final bytes = utf8.encode(text);
  return ContentWindow(
    offset: 0,
    bytes: bytes,
    generation: 'g',
    availableThrough: bytes.length,
    sealed: true,
  );
}

Widget scene(
  String contract,
  Future<ContentWindow> Function(ContentRef, ContentRange) read, {
  String call = 'call',
  String identity = 'same-ref',
}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: TimelineToolDetails(
        item: TimelineToolPresentation(
          id: 'item',
          toolCallId: call,
          name: 'tool',
          presentationContract: contract,
          statusString: 'succeeded',
          arguments: '{"completion":{"reason":"ready","summary":"done","evidence":[]}}',
          output: '',
        ),
        initiallyExpanded: true,
        declaredContentIdentity: identity,
        declaredContentBuilder: (onRead, acceptance) => [
          TimelineBodyReadIntent(
            scrollable: true,
            onRead: onRead,
            bodyBuilder: (text) => timelineToolWindowBody(
              TimelineToolPresentation(
                id: 'item',
                toolCallId: call,
                name: 'tool',
                presentationContract: contract,
                statusString: 'succeeded',
                arguments: '{}',
                output: '',
              ),
              text,
              input: false,
              acceptance: acceptance,
            ),
            child: TimelineContentRangeConnector(
              itemId: 'item',
              contentKey: 'toolOutput',
              label: 'result',
              reference: ref,
              witness: (_, child) => child,
              readContent: read,
            ),
          ),
        ],
      ),
    ),
  ),
);
TimelineActivityRow row(WidgetTester t) =>
    t.widget<TimelineActivityRow>(find.byType(TimelineActivityRow));
void main() {
  testWidgets(
    'in-flight connector result must not acquire replacement body owner epoch',
    (t) async {
      final a = TimelineExpansionIntent();
      final b = TimelineExpansionIntent();
      a.setBodyVisible(Object(), true);
      b.setBodyVisible(Object(), true);
      final pending = Completer<ContentWindow>();
      final fresh = Completer<ContentWindow>();
      var reads = 0;
      Future<ContentWindow> read(ContentRef _, ContentRange _) {
        reads++;
        expect(reads, lessThanOrEqualTo(2));
        return reads == 1 ? pending.future : fresh.future;
      }

      Widget body(TimelineExpansionIntent group) => TimelineGroupBodyIntent(
        intent: group,
        child: scene('builtin.workflow_transition@1', read),
      );
      await t.pumpWidget(body(a));
      await t.pump();
      expect(reads, 1);
      final connector = t.state(find.byType(TimelineContentRangeConnector));
      await t.pumpWidget(body(b));
      await t.pump();
      expect(
        t.state(find.byType(TimelineContentRangeConnector)),
        same(connector),
      );
      expect(row(t).label, contains('结果待确认'));
      pending.complete(full('{"accepted":true}'));
      await t.pump();
      await t.pump();
      expect(reads, 2);
      final actual = row(t).label;
      fresh.complete(full('{"accepted":false,"code":"staleRevision"}'));
      await t.pumpAndSettle();
      expect(row(t).isIssue, isTrue);
      await t.pumpWidget(const SizedBox.shrink());
      a.dispose();
      a.retirement.dispose();
      b.dispose();
      b.retirement.dispose();
      expect(
        actual,
        contains('结果待确认'),
        reason:
            'An old request cannot inherit the replacement body owner epoch',
      );
    },
  );
  testWidgets(
    'unrelated rebuild retains admitted rejection without another read',
    (t) async {
      var reads = 0;
      Future<ContentWindow> read(ContentRef _, ContentRange _) async {
        reads++;
        return full('{"accepted":false,"code":"staleRevision"}');
      }

      await t.pumpWidget(scene('builtin.workflow_transition@1', read));
      await t.pumpAndSettle();
      expect(row(t).isIssue, isTrue);
      final owner = t.state(find.byType(TimelineToolDetails));
      await t.pumpWidget(scene('builtin.workflow_transition@1', read));
      await t.pumpAndSettle();
      expect(t.state(find.byType(TimelineToolDetails)), same(owner));
      expect(row(t).isIssue, isTrue);
      expect(reads, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'in-flight connector result must not acquire replacement contract epoch',
    (t) async {
      final pending = Completer<ContentWindow>();
      final fresh = Completer<ContentWindow>();
      var reads = 0;
      Future<ContentWindow> read(ContentRef _, ContentRange _) {
        reads++;
        expect(reads, lessThanOrEqualTo(2));
        return reads == 1 ? pending.future : fresh.future;
      }

      await t.pumpWidget(scene('builtin.workflow_transition@1', read));
      await t.pump();
      expect(reads, 1);
      expect(row(t).label, contains('结果待确认'));
      final connector = t.state(find.byType(TimelineContentRangeConnector));
      await t.pumpWidget(scene('builtin.workflow_restart@1', read));
      await t.pump();
      expect(
        t.state(find.byType(TimelineContentRangeConnector)),
        same(connector),
      );
      expect(row(t).label, contains('结果待确认'));
      pending.complete(full('{"accepted":true}'));
      await t.pump();
      await t.pump();
      expect(reads, 2);
      expect(
        row(t).label,
        contains('结果待确认'),
        reason:
            'An old request cannot inherit the replacement presentation epoch',
      );
      fresh.complete(full('{"accepted":false,"code":"staleRevision"}'));
      await t.pumpAndSettle();
      expect(row(t).isIssue, isTrue);
    },
  );
  testWidgets(
    'in-flight connector result must not acquire replacement call epoch',
    (t) async {
      final pending = Completer<ContentWindow>();
      final fresh = Completer<ContentWindow>();
      var reads = 0;
      Future<ContentWindow> read(ContentRef _, ContentRange _) {
        reads++;
        expect(reads, lessThanOrEqualTo(2));
        return reads == 1 ? pending.future : fresh.future;
      }

      await t.pumpWidget(
        scene('builtin.workflow_transition@1', read, call: 'call-old'),
      );
      await t.pump();
      expect(reads, 1);
      await t.pumpWidget(
        scene('builtin.workflow_transition@1', read, call: 'call-new'),
      );
      await t.pump();
      expect(row(t).label, contains('结果待确认'));
      pending.complete(full('{"accepted":true}'));
      await t.pump();
      await t.pump();
      expect(reads, 2);
      expect(
        row(t).label,
        contains('结果待确认'),
        reason: 'An old request cannot inherit the replacement call epoch',
      );
      fresh.complete(full('{"accepted":false,"code":"staleRevision"}'));
      await t.pumpAndSettle();
      expect(row(t).isIssue, isTrue);
    },
  );
}
