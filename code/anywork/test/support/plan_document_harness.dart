import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/connectors/plan_detail_connector.dart';
import 'package:anywork/src/features/conversation/timeline/view_models/plan_document_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_fixtures.dart';
import 'plan_document_transport.dart';
import 'pump_client_future.dart';
import 'test_statistics_feed.dart';

class PlanDocumentHarness {
  PlanDocumentHarness._(this.tester, this.transport, this.graph);
  final WidgetTester tester;
  final PlanDocumentTransport transport;
  final AppGraph graph;
  late ProviderContainer container;
  ConversationSession get session =>
      graph.client.conversations.session('thread-main');
  PlanDocumentState get document =>
      container.read(planDocumentViewModelProvider('thread-main'));

  static Future<PlanDocumentHarness> open(
    WidgetTester tester,
    PlanDocumentTransport transport,
  ) async {
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'plan-recovery',
    );
    final h = PlanDocumentHarness._(tester, transport, graph);
    await pumpClientFuture(tester, graph.client.bootstrap(), 'bootstrap');
    graph
      ..timeline.updateReadDemand(chatDemand)
      ..setConversationPageVisible(true);
    await pumpClientFuture(
      tester,
      graph.client.directoryCommands.selectThread('thread-main'),
      'select thread',
    );
    await pumpClientUntil(
      tester,
      () => h.session.state.hasSnapshot,
      'state before content ready',
    );
    return h;
  }

  Future<void> publish(int revision, String markdown) async {
    transport.seedConversationState(
      'thread-main',
      ThreadRuntimeUpdate(
        runtime: session.state.workspace!.runtime.copyWith(
          plan: PlanRuntimeView(
            revision: revision,
            state: PlanRuntimePhase.awaitingConfirmation,
            updatedAt: DateTime.utc(2026, 3, 18),
            document: PlanDocumentView(
              version: revision,
              markdown: markdown,
              contentHash: 'plan-$revision',
            ),
          ),
        ),
        todo: null,
        modelRoute: session.state.modelRoute,
      ),
    );
    await pumpClientUntil(
      tester,
      () => session.state.businessRefs?.plan?.revision == revision,
      'plan reference $revision',
    );
  }

  Future<void> mount({Widget Function(Widget plan)? layout}) async {
    final plan = PlanDetailConnector(
      threadId: 'thread-main',
      identity: 'pending-plan',
      status: PlanDetailStatus.awaitingConfirmation,
      onClose: () {},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: MaterialApp(
          theme: pureStudioTheme(),
          locale: const Locale('zh'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: layout?.call(plan) ?? plan),
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(PlanDetailConnector)),
    );
    await tester.pump();
  }

  Future<void> reads(int count) => pumpClientUntil(
    tester,
    () => transport.reads.length >= count,
    'read $count',
  );

  Future<void> body(String text) => pumpClientUntil(
    tester,
    () =>
        document.window != null &&
        !document.loading &&
        find.textContaining(text, findRichText: true).evaluate().isNotEmpty,
    'body $text',
  );

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    final report = await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'close graph',
    );
    expect(report.complete, isTrue);
  }
}
