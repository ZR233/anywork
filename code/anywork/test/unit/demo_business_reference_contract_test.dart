import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/features/conversation/timeline/state/chat_item_presentation.dart';
import 'package:anywork/src/infrastructure/demo/studio_demo_api.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_fixtures.dart';
import '../support/test_statistics_feed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Demo interaction collection carries the canonical InteractionRequest envelope', () async {
    final (graph, transport) = await _open();
    final session = graph.client.conversations.session('thread-main');
    final previous = session.state.businessRefs!.interactions;
    transport.seedConversationState(
      'thread-main',
      const ThreadInteractionUpdate(
        interaction: PendingInteraction(
          id: 'canonical-question',
          threadId: 'thread-main',
          turnId: 'turn-question',
          revision: 3,
          kind: InteractionKind.userInput,
          title: '问题',
          body: '公开问题',
          payload: UserInputInteractionPayload(
            questions: [
              UserQuestionView(
                id: 'q',
                header: '问题',
                question: '公开问题',
                isOther: true,
                isSecret: false,
                options: [],
              ),
            ],
          ),
        ),
        pending: true,
      ),
    );
    await session.source.waitFor(
      (state) => state.businessRefs?.interactions != previous,
    );
    final scope = session.content.openScope(generation: 102);
    try {
      final page = await scope.pageCurrent(
        reference: session.state.businessRefs!.interactions!,
        demand: chatDemand,
      );
      final request = jsonDecode(
        utf8.decode((page.entries.single.payload as InlinePayload).bytes),
      ) as Map;
      expect(request['interactionId'], 'canonical-question');
      expect(request['scope'], {
        'threadId': 'thread-main',
        'turnId': 'turn-question',
      });
      expect(request['revision'], 3);
      final content = request['content'] as Map;
      expect(content['kind'], 'userInput');
      final data = content['data'] as Map;
      expect((data['questions'] as List).single['question'], '公开问题');
      expect((data['state'] as Map)['kind'], 'pending');
      expect(request.containsKey('title'), isFalse);
      expect(request.containsKey('body'), isFalse);
      expect(request['createdAt'], isA<int>());
      expect(request['updatedAt'], isA<int>());
    } finally {
      expect((await scope.close()).complete, isTrue);
    }
  });

  test('Demo publishes changed State refs, not token-driven replacement or Main refresh', () async {
    final (graph, transport) = await _open();
    final session = graph.client.conversations.session('thread-main');
    final lease = graph.timeline.lease('thread-main')!;
    final firstMessage = lease.controller.messages.first;
    final scope = session.content.openScope(generation: 100);
    addTearDown(() async => expect((await scope.close()).complete, isTrue));
    final runtime = session.state.runtime!;
    final route = session.state.modelRoute;
    final plan = PlanRuntimeView(
      revision: 7,
      state: PlanRuntimePhase.awaitingConfirmation,
      updatedAt: DateTime.utc(2026),
      document: const PlanDocumentView(
        version: 7,
        markdown: '计划正文 v7',
        contentHash: 'plan-v7',
      ),
    );
    transport.seedConversationState(
      'thread-main',
      ThreadRuntimeUpdate(
        runtime: runtime.copyWith(plan: plan),
        todo: null,
        modelRoute: route,
      ),
    );
    await session.source
        .waitFor((state) => state.businessRefs?.plan?.revision == 7)
        .timeout(const Duration(seconds: 3));
    final references = session.state.businessRefs!;
    expect(await scope.readBusinessRefs(), references);
    final document = references.plan!.document!;
    final body = await scope.readContent(
      reference: document,
      range: const ContentRange(offset: 0, maxBytes: 65536),
    );
    expect(utf8.decode(body.bytes), '计划正文 v7');
    expect(body.sealed, isTrue);
    expect(references.interactions, isNotNull);
    final page = await scope.pageCurrent(
      reference: references.interactions!,
      demand: chatDemand,
    );
    expect(page.entries, isEmpty);
    final nextTokens = session.state.runtime!.totalTokens + 1;
    transport.seedConversationState(
      'thread-main',
      ThreadRuntimeUpdate(
        runtime: session.state.runtime!.copyWith(totalTokens: nextTokens),
        todo: null,
        modelRoute: route,
      ),
    );
    await session.source.waitFor(
      (state) => state.runtime?.totalTokens == nextTokens,
    );
    expect(session.state.businessRefs, references);
    expect(await scope.readBusinessRefs(), references);
    expect(graph.timeline.lease('thread-main'), same(lease));
    expect(lease.controller.messages.first, same(firstMessage));
    transport.seedConversationState(
      'thread-main',
      ThreadRuntimeUpdate(
        runtime: session.state.runtime!.copyWith(
          plan: plan.copyWith(
            revision: 8,
            document: const PlanDocumentView(
              version: 8,
              markdown: '计划正文 v8',
              contentHash: 'plan-v8',
            ),
          ),
        ),
        todo: null,
        modelRoute: route,
      ),
    );
    await session.source.waitFor(
      (state) => state.businessRefs?.plan?.revision == 8,
    );
    expect(session.state.businessRefs!.interactions, references.interactions);
    final nextBody = await scope.readContent(
      reference: session.state.businessRefs!.plan!.document!,
      range: const ContentRange(offset: 0, maxBytes: 65536),
    );
    expect(utf8.decode(nextBody.bytes), '计划正文 v8');
    await expectLater(
      scope.readContent(
        reference: document,
        range: const ContentRange(offset: 0, maxBytes: 65536),
      ),
      throwsA(isA<StudioFailure>()),
    );
  });

  test(
    'Demo accepted composer input appears exactly once through Chat admission',
    () async {
      final (graph, _) = await _open();
      final session = graph.client.conversations.session('thread-main');
      final lease = graph.timeline.lease('thread-main')!;
      final admitted = Completer<void>();
      final observed = lease.controller.operationsStream.listen((_) {
        if (!admitted.isCompleted &&
            lease.controller.messages.any(
              (message) => message.id == 'unique-user-input',
            )) {
          admitted.complete();
        }
      });
      addTearDown(observed.cancel);
      final receipt = await graph.client.threadCommands.submitComposer(
        'thread-main',
        const StudioPromptInput(
          inputId: 'unique-user-input',
          text: '唯一用户输入',
          attachmentDraftIds: [],
        ),
        expectedModelRouteRevision: session.state.modelRoute!.revision,
      );
      expect(receipt.inputId, 'unique-user-input');
      await admitted.future.timeout(const Duration(seconds: 3));
      final messages = lease.controller.messages.where(
        (message) => message.id == receipt.inputId,
      );
      expect(messages, hasLength(1));
      final item = chatItemPresentationOf(messages.single)!;
      expect(
        item.atom!.source,
        const InputChatSource(inputId: 'unique-user-input'),
      );
      expect(item.displayUnit!.entry.mainPresentation, MainPresentation.single);
      final scope = session.content.openScope(generation: 101);
      try {
        final completed = await scope.readCompleted(
          recordId: receipt.inputId,
          demand: chatDemand,
        );
        expect(completed.recordId, receipt.inputId);
        expect(completed.atom.source, item.atom!.source);
        expect(
          ChatItemPresentation.decode(completed.atom).inlineText('body'),
          '唯一用户输入',
        );
      } finally {
        expect((await scope.close()).complete, isTrue);
      }
    },
  );
}

Future<(AppGraph, DemoStudioTransport)> _open() async {
  final transport = DemoStudioTransport();
  final graph = AppGraph(
    statisticsFeed: const TestStatisticsFeedPort(),
    transport: transport,
    clientId: 'demo-business-reference-contract',
  );
  addTearDown(() async {
    expect(
      (await graph.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      )).complete,
      isTrue,
    );
  });
  await graph.client.bootstrap();
  graph.timeline.updateReadDemand(chatDemand);
  graph.setConversationPageVisible(true);
  await graph.client.directoryCommands.selectThread('thread-main');
  await graph.client.conversations.session('thread-main').content.ready;
  return (graph, transport);
}
