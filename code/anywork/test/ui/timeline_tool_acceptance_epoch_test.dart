import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/timeline_owned_body_connector.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/pump_client_future.dart';

ContentWindow _full(String text) {
  final bytes = utf8.encode(text);
  return ContentWindow(
    offset: 0,
    bytes: bytes,
    generation: 'g',
    availableThrough: bytes.length,
    sealed: true,
  );
}

Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

TimelineDisplayUnit _displayUnit(TimelineExpansionIntent intent) =>
    TimelineDisplayUnit(
      expansion: intent,
      block: DisplayBlock(
        id: 'item',
        blockOrder: 1,
        body: SingleDisplayBlock(
          visibility: HistorySingleVisibility.content,
          record: DisplayRecord(
            atom: ChatAtom(
              id: 'item',
              source: const ForegroundTurnChatSource(turnId: 'turn'),
              sourceOrder: 1,
              kind: ChatAtomKind.text,
              delivery: ChatDeliveryKind.foreground,
              lifecycle: const ActiveChatAtom(
                started: null,
                status: ChatActiveStatus.running,
              ),
              turnId: 'turn',
              contentPresent: true,
              contents: const [],
            ),
            contentSource: const CurrentAtomSource(),
          ),
        ),
      ),
    );

TimelineExpansionIntent _bodyOwner() {
  final intent = TimelineExpansionIntent();
  intent.setBodyVisible(Object(), true);
  intent.current = _displayUnit(intent);
  return intent;
}

Widget _historyScene(
  TimelineExpansionIntent intent,
  HistoryEventBodyRef reference,
) => _host(
  TimelineGroupBodyIntent(
    intent: intent,
    child: TimelineOwnedBodyConnector(
      itemId: 'item',
      contentKey: reference.bodyKey,
      label: 'result',
      historyReference: reference,
      disclosed: true,
      witness: (text, _) => Text(text),
    ),
  ),
);

Widget _currentScene(
  TimelineExpansionIntent intent,
  CurrentContentRef reference,
) => _host(
  TimelineGroupBodyIntent(
    intent: intent,
    child: TimelineOwnedBodyConnector(
      itemId: reference.entityId,
      contentKey: reference.contentKey,
      label: 'result',
      currentReference: reference,
      disclosed: true,
      witness: (text, _) => Text(text),
    ),
  ),
);

TimelineActivityRow _row(WidgetTester tester) =>
    tester.widget<TimelineActivityRow>(find.byType(TimelineActivityRow).first);

final class _FixtureCurrentBodyWatch implements CurrentBodyWatch {
  final StreamController<ContentWindow> _output =
      StreamController<ContentWindow>.broadcast(sync: true);
  Future<void>? _closing;
  int opens = 0;
  bool requested = false;

  @override
  Stream<ContentWindow> get windows => _output.stream;

  void add(ContentWindow window) => _output.add(window);

  @override
  void requestClose() {
    if (requested) return;
    requested = true;
    unawaited(_output.close());
  }

  @override
  Future<void> close() => _closing ??= () async {
    requestClose();
    await _output.done;
  }();
}

void main() {
  testWidgets(
    'retired History body owner keeps its in-flight page out of the replacement',
    (tester) async {
      const reference = HistoryEventBodyRef(
        databaseId: 'db',
        ownerEventId: 'event',
        bodyKey: 'tool.result',
        bodyId: 'event:tool.result',
        byteStart: 0,
        byteLength: 24,
      );
      final retired = Completer<ContentWindow>();
      final active = Completer<ContentWindow>();
      var reads = 0;
      Future<ContentWindow> read(
        Object _,
        HistoryEventBodyRef actualReference,
        ContentRange _,
      ) {
        expect(actualReference, reference);
        reads++;
        return reads == 1 ? retired.future : active.future;
      }

      final first = _bodyOwner()..readHistoryBody = read;
      final second = _bodyOwner()..readHistoryBody = read;
      await tester.pumpWidget(_historyScene(first, reference));
      await tester.pump();
      expect(reads, 1);

      await tester.pumpWidget(_historyScene(second, reference));
      await tester.pump();
      expect(reads, 2);
      retired.complete(_full('{"accepted":true}'));
      await tester.pump();
      await tester.pump();
      expect(find.text('{"accepted":true}'), findsNothing);

      active.complete(_full('{"accepted":false,"code":"staleRevision"}'));
      await tester.pumpAndSettle();
      expect(
        find.text('{"accepted":false,"code":"staleRevision"}'),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      first.retirement.dispose();
      second.dispose();
      second.retirement.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement Current body owner closes its watch before accepting frames',
    (tester) async {
      const reference = CurrentContentRef(
        ownerId: 'owner',
        domain: 'thread',
        entityId: 'item',
        contentKey: 'tool.result',
        generation: '1',
      );
      final retired = _FixtureCurrentBodyWatch();
      final active = _FixtureCurrentBodyWatch();
      final first = _bodyOwner()
        ..watchCurrentBody = (_, _, _) {
          retired.opens++;
          return retired;
        };
      final second = _bodyOwner()
        ..watchCurrentBody = (_, _, _) {
          active.opens++;
          return active;
        };

      await tester.pumpWidget(_currentScene(first, reference));
      await tester.pump();
      expect(retired.opens, 1);

      await tester.pumpWidget(_currentScene(second, reference));
      await pumpClientUntil(
        tester,
        () => active.opens == 1 && active._output.hasListener,
        'replacement Current body watch',
      );
      expect(retired.requested, isTrue);
      expect(active.opens, 1);

      active.add(_full('current result'));
      await tester.pump();
      expect(find.text('current result'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(active.requested, isTrue);
      first.dispose();
      first.retirement.dispose();
      second.dispose();
      second.retirement.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'acceptance epoch rejects a callback retained by the previous frame',
    (tester) async {
      const rejected =
          '{"accepted":false,"code":"staleRevision","recoveryAction":"Qualified rejection"}';
      ValueChanged<ContentWindow>? callback;
      Widget owner(String contract, String call) => _host(
        TimelineToolDetails(
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
          declaredContentIdentity: (contract, call),
          declaredContentBuilder: (onRead, _) {
            callback = onRead;
            return const [Text('Declared range')];
          },
        ),
      );

      await tester.pumpWidget(
        owner('builtin.workflow_transition@1', 'call-old'),
      );
      await tester.pumpAndSettle();
      final previous = callback!;
      previous(_full(rejected));
      await tester.pumpAndSettle();
      expect(_row(tester).isIssue, isTrue);

      await tester.pumpWidget(owner('builtin.workflow_restart@1', 'call-new'));
      await tester.pumpAndSettle();
      expect(_row(tester).label, contains('结果待确认'));
      previous(_full(rejected));
      await tester.pumpAndSettle();
      expect(
        _row(tester).isIssue,
        isFalse,
        reason: 'A prior frame cannot acquire the replacement acceptance epoch',
      );

      callback!(_full(rejected));
      await tester.pumpAndSettle();
      expect(_row(tester).isIssue, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
