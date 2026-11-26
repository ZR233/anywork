import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/interaction_details_connector.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/timeline_transport.dart'
    show TestCurrentReader;

const _reference = CurrentCollectionRef(
  ownerId: 'owner',
  collection: 'interactions',
  revision: 3,
);

CurrentCollectionPage _page() => CurrentCollectionPage(
  revision: _reference.revision,
  entries: [
    CurrentCollectionEntry(
      id: 'interaction',
      position: 1,
      payload: InlineCurrentPayload(
        bytes: utf8.encode(
          jsonEncode({
            'interactionId': 'interaction',
            'scope': {'threadId': 'thread', 'turnId': 'turn'},
            'revision': 3,
            'content': {
              'kind': 'userInput',
              'data': {
                'questions': [
                  {
                    'id': 'public',
                    'header': '公开问题',
                    'question': '公开详情',
                    'isSecret': false,
                  },
                  {
                    'id': 'secret',
                    'header': '秘密问题',
                    'question': '秘密详情',
                    'isSecret': true,
                  },
                ],
                'state': {
                  'kind': 'resolved',
                  'data': {
                    'operationId': 'resolved',
                    'answers': {
                      'secret': {
                        'answers': ['秘密答案'],
                      },
                    },
                    'resolvedAt': 2,
                  },
                },
              },
            },
            'createdAt': 1,
            'updatedAt': 2,
          }),
        ),
      ),
    ),
  ],
);

CurrentReadScope _scope(TestCurrentReader reader) => CurrentReadScope(
  threadId: 'thread',
  generation: 1,
  reader: reader,
  isEligible: () => !reader.requested,
);

Widget _host(CurrentQueryScope Function() openCurrent) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: InteractionDetailsConnector(
        openCurrent: openCurrent,
        reference: _reference,
        isCurrent: () => true,
      ),
    ),
  ),
);

void main() {
  testWidgets('interaction details page only public Current payload fields', (
    tester,
  ) async {
    final reader = TestCurrentReader();
    reader.onPage = (reference, continuation, demand) async {
      expect(reference, _reference);
      expect(continuation, isNull);
      expect(demand.maxItems, 20);
      return _page();
    };
    await tester.pumpWidget(_host(() => _scope(reader)));
    final title = AppLocalizations.of(tester.element(find.byType(Scaffold)))
        .interactionDetailsTitle;
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();

    expect(find.text('公开问题'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('公开详情'), findsOneWidget);
    expect(find.text('秘密问题'), findsNothing);
    expect(find.textContaining('秘密详情'), findsNothing);
    expect(find.textContaining('秘密答案'), findsNothing);
    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(InteractionDetailsConnector)),
        ).interactionDetailsSecretQuestionHidden,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsing revokes and drops a late interaction page', (
    tester,
  ) async {
    final reader = TestCurrentReader();
    final late = Completer<CurrentCollectionPage>();
    reader.onPage = (_, _, _) => late.future;
    await tester.pumpWidget(_host(() => _scope(reader)));
    final title = AppLocalizations.of(tester.element(find.byType(Scaffold)))
        .interactionDetailsTitle;
    await tester.tap(find.text(title));
    await tester.pump();
    await tester.tap(find.text(title));
    await tester.pump();

    late.complete(_page());
    await tester.pumpAndSettle();
    expect(find.text('公开问题'), findsNothing);
    expect(
      find.textContaining(StaleConversationScope().toString()),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
