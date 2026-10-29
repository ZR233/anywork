import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/src/conversation/data/conversation_content_impl.dart';
import 'package:anywork_client/src/conversation/data/input_turn_facts.dart';
import 'package:anywork_client/src/lifecycle/resource_budget.dart';
import 'package:test/test.dart';

import 'support/timeline_transport.dart';

final class _Feed implements ConversationFeed {
  _Feed(this.subscriptionId);
  @override
  final String threadId = 'thread';
  @override
  final String subscriptionId;
  final eventsController = StreamController<ConversationFrame>.broadcast(
    sync: true,
  );
  final acknowledgements = <int>[];
  int sequence = 0;
  bool requested = false;
  @override
  Stream<ConversationFrame> get events => eventsController.stream;
  void send(ConversationEvent event) => eventsController.add(
    ConversationFrame(
      threadId: threadId,
      subscriptionId: subscriptionId,
      deliverySequence: ++sequence,
      event: event,
    ),
  );
  @override
  Future<void> acknowledge(int deliverySequence) async {
    acknowledgements.add(deliverySequence);
  }

  @override
  void requestClose() {
    requested = true;
  }

  @override
  Future<void> close() async {
    await eventsController.close();
  }
}

final class _Transport implements ConversationTransport {
  final feeds = <_Feed>[];
  final resumes = <ConversationCompletionCursor?>[];
  @override
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  }) async {
    resumes.add(resumeAfter);
    final feed = _Feed('sub${feeds.length + 1}');
    feeds.add(feed);
    return feed;
  }

  @override
  Future<ConversationHistoryReader> openHistoryReader(String threadId) =>
      throw UnimplementedError();
}

final class _Consumer implements ConversationCompletionConsumer {
  final frames = <ConversationContentFrame>[];
  Completer<void>? gate;
  @override
  Future<void> accept(ConversationContentFrame frame) async {
    frames.add(frame);
    final current = gate;
    if (current != null) await current.future;
  }
}

Future<void> _pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ConversationBaseline _baseline(
  _Feed feed, {
  String epoch = 'epoch',
  int seq = 0,
}) => ConversationBaseline(
  subscriptionId: feed.subscriptionId,
  timelineEpoch: epoch,
  items: [],
  before: null,
  hasOlder: false,
  completedCursor: ConversationCompletionCursor(
    timelineEpoch: epoch,
    appendSeq: seq,
  ),
);
ConversationContentImpl _owner(_Transport transport) {
  final budget = ResourceBudget();
  return ConversationContentImpl(
    threadId: 'thread',
    transport: transport,
    budget: budget,
    inputFacts: InputFactRegistry(budget, seed: (_, __) {}),
    onState: (_, __) {},
    onFailure: (_, __, ___) {},
    onAttempt: (_) {},
  );
}

void main() {
  for (final domain in ['interaction', 'storage']) {
    test('committed activity survives $domain update until completion acceptance', () async {
      final fixture = ConversationFixture();
      final session = fixture.session();
      final consumer = _Consumer();
      final lease = session.content.attachConsumer(consumer);
      fixture.repository.setVisibleThread('thread');
      await fixture.transport.opened(0);
      final feed = TestConversationFeed();
      fixture.transport.opens.single.result.complete(feed);
      Future<void> deliver(ConversationEvent event) => feed
          .deliver(event)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError(
              'delivery ${event.runtimeType} failed: ${session.content.state.value}',
            ),
          );
      await deliver(
        ConversationBaselineEvent(baseline: baseline(0, items: [])),
      );
      await deliver(
        ConversationStateEvent(
          frame: ThreadSnapshotFrame(
            workspace: ThreadWorkspace(
              thread: StudioThread(
                id: 'thread',
                projectId: 'project',
                title: 'Thread',
                mode: ThreadModeId.simple,
                delegationMode: DelegationMode.profile,
                delegationPreference: DelegationPreference.balanced,
                updatedAt: DateTime.utc(2026),
                workspacePath: '/project',
              ),
              revision: 1,
              interactions: const [],
              runtime: const ThreadRuntimeView(
                modelId: 'model',
                contextTokens: 0,
                contextWindow: 1,
                totalTokens: 0,
                costLabel: '',
                activeSkills: [],
                activeMcpServers: [],
                activeLspServers: [],
              ),
            ),
          ),
        ),
      );
      const reasoning = ActivityRegion(ActivityRegionKind.reasoning, 'reason');
      const response = ActivityRegion(ActivityRegionKind.response, 'answer');
      const output = ActivityRegion.toolOutput(callId: 'call', partId: 'part');
      await deliver(
        ConversationActivityContentEvent(
          frame: ActivityBegin(
            generation: 'generation',
            revision: 1,
            baseRevision: null,
            activity: const ThreadActivityView(
              threadId: 'thread',
              identity: 'live',
              revision: 1,
              turnId: 'turn',
              kind: ThreadActivityKind.responding,
              summary: 'working',
            ),
            reasoning: const [
              ActivityPartMetadata(
                itemId: 'reason',
                complete: false,
                totalBytes: 1,
              ),
            ],
            response: const [
              ActivityPartMetadata(
                itemId: 'answer',
                complete: false,
                totalBytes: 1,
              ),
            ],
            tools: [
              ActivityToolMetadata(
                callId: 'call',
                name: 'exec',
                state: ThreadActivityToolState.running,
                outputBytes: 1,
                outputParts: const [
                  ActivityToolOutputMetadata(partId: 'part', totalBytes: 1),
                ],
              ),
            ],
            totalBytes: 3,
          ),
        ),
      );
      await deliver(
        ConversationActivityContentEvent(
          frame: ActivityText(
            generation: 'generation',
            revision: 1,
            operations: const [
              ActivityReplace(reasoning, 'r'),
              ActivityReplace(response, 'a'),
              ActivityReplace(output, 't'),
            ],
          ),
        ),
      );
      await deliver(
        const ConversationActivityContentEvent(
          frame: ActivityCommit(generation: 'generation', revision: 1),
        ),
      );
      expect(session.currentActivity.value!.activity!.identity, 'live');
      await deliver(
        ConversationActivityContentEvent(
          frame: ActivityBegin(
            generation: 'generation',
            revision: 2,
            baseRevision: 1,
            activity: null,
            reasoning: const [],
            response: const [],
            tools: const [],
            totalBytes: 0,
          ),
        ),
      );
      await deliver(
        ConversationActivityContentEvent(
          frame: ActivityText(
            generation: 'generation',
            revision: 2,
            operations: const [
              ActivityRemove(reasoning),
              ActivityRemove(response),
              ActivityRemove(output),
            ],
          ),
        ),
      );
      consumer.gate = Completer<void>();
      final completionSeq = feed.send(
        ConversationActivityContentEvent(
          frame: const ActivityCommit(generation: 'generation', revision: 2),
          completed: ConversationBatch(
            subscriptionId: 'sub',
            timelineEpoch: 'epoch',
            fromSeq: 0,
            throughSeq: 1,
            items: [timelineItem(1)],
          ),
        ),
      );
      await _pump();
      expect(consumer.frames, hasLength(2));
      const interaction = PendingInteraction(
        id: 'pending',
        threadId: 'thread',
        turnId: 'turn',
        kind: InteractionKind.userInput,
        title: 'Question',
        body: '',
      );
      final update = domain == 'interaction'
          ? const ThreadInteractionUpdate(
              interaction: interaction,
              pending: true,
            )
          : const ThreadStorageUpdate(
              storage: ThreadStorageStateView(pressurePaused: true),
            );
      final stateSeq = feed.send(
        ConversationStateEvent(
          frame: ThreadNotificationFrame(
            threadId: 'thread',
            epoch: 1,
            baseRevision: 1,
            revision: 2,
            update: update,
          ),
        ),
      );
      await session.source
          .waitFor((state) => state.revision == 2)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError(
              'state not committed: ${session.state.sync.errorMessage}',
            ),
          );
      ConversationActivityView? projection() => projectConversationActivity(
        current: session.currentActivity.value,
        interaction: session.state.interactions.firstOrNull,
        storage: session.state.storage,
      );
      final before = projection()!;
      expect(before.identity, 'live');
      expect(before.kind, ConversationActivityKind.responding);
      expect(before.reasoningParts.single.text, 'r');
      expect(before.responseParts.single.text, 'a');
      expect(before.toolDetails.single.outputParts!.single.text, 't');
      expect(feed.acknowledgements, isNot(contains(completionSeq)));
      expect(feed.acknowledgements, isNot(contains(stateSeq)));
      consumer.gate!.complete();
      await feed
          .acknowledged(stateSeq)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw StateError(
              'state ACK not delivered: ${feed.acknowledgements}',
            ),
          );
      expect(session.currentActivity.value!.activity, isNull);
      expect(
        projection()!.kind,
        domain == 'interaction'
            ? ConversationActivityKind.awaitingInput
            : ConversationActivityKind.storageBlocked,
      );
      expect(
        feed.acknowledgements,
        containsAllInOrder([completionSeq, stateSeq]),
      );
      fixture.repository.setVisibleThread(null);
      lease.cancel();
      expect((await fixture.close()).complete, isTrue);
    });
  }
  test('session reconnect accepts an identical snapshot and catches up from accepted cursor', () async {
    final fixture = ConversationFixture();
    final session = fixture.session();
    final consumer = TestCompletionConsumer();
    session.content.attachConsumer(consumer);
    fixture.repository.setVisibleThread('thread');
    await fixture.transport.opened(0);
    final first = TestConversationFeed();
    fixture.transport.opens.single.result.complete(first);
    await first.deliver(
      ConversationBaselineEvent(baseline: baseline(0, items: [])),
    );
    ActivityBegin snapshot() => ActivityBegin(
      generation: 'generation',
      revision: 1,
      baseRevision: null,
      activity: const ThreadActivityView(
        threadId: 'thread',
        identity: 'activity',
        revision: 1,
        turnId: null,
        kind: ThreadActivityKind.responding,
        summary: 'summary',
      ),
      reasoning: const [],
      response: const [
        ActivityPartMetadata(itemId: 'answer', complete: false, totalBytes: 3),
      ],
      tools: const [],
      totalBytes: 3,
    );
    ActivityText chunk(String text) => ActivityText(
      generation: 'generation',
      revision: 1,
      operations: [
        ActivityReplace(
          const ActivityRegion(ActivityRegionKind.response, 'answer'),
          text,
        ),
      ],
    );
    await first.deliver(ConversationActivityContentEvent(frame: snapshot()));
    await first.deliver(ConversationActivityContentEvent(frame: chunk('old')));
    await first.deliver(
      const ConversationActivityContentEvent(
        frame: ActivityCommit(generation: 'generation', revision: 1),
      ),
    );
    final original = session.currentActivity.value;
    var publications = 0;
    final watch = session.currentActivity.watch((_) => publications++);
    session.refresh();
    await fixture.transport.opened(1);
    expect(
      fixture.transport.resumes.last,
      const ConversationCompletionCursor(timelineEpoch: 'epoch', appendSeq: 0),
    );
    final second = TestConversationFeed(subscriptionId: 'new');
    fixture.transport.opens[1].result.complete(second);
    await second.deliver(ConversationActivityContentEvent(frame: snapshot()));
    await second.deliver(ConversationActivityContentEvent(frame: chunk('old')));
    await second.deliver(
      const ConversationActivityContentEvent(
        frame: ActivityCommit(generation: 'generation', revision: 1),
      ),
    );
    expect(session.currentActivity.value, same(original));
    expect(publications, 0);
    await second.deliver(
      ConversationUpdateEvent(
        update: ConversationBatch(
          subscriptionId: 'new',
          timelineEpoch: 'epoch',
          fromSeq: 0,
          throughSeq: 1,
          items: [timelineItem(1)],
        ),
      ),
    );
    expect(consumer.frames.last, isA<ConversationCompletedBatchFrame>());
    expect(second.acknowledgements, [1, 2, 3, 4]);
    watch.cancel();
    expect((await fixture.close()).complete, isTrue);
  });
  test(
    'blocked completion prevents ACK from crossing later ready state',
    () async {
      final transport = _Transport();
      final owner = _owner(transport);
      final consumer = _Consumer()..gate = Completer<void>();
      final lease = owner.attachConsumer(consumer);
      owner.setDemand(true);
      await _pump();
      final feed = transport.feeds.single;
      feed.send(ConversationBaselineEvent(baseline: _baseline(feed)));
      feed.send(
        ConversationStateEvent(
          frame: ThreadResyncRequiredFrame(
            threadId: 'thread',
            dropped: 1,
            epoch: 1,
          ),
        ),
      );
      await _pump();
      expect(consumer.frames, hasLength(1));
      expect(feed.acknowledgements, isEmpty);
      consumer.gate!.complete();
      await _pump();
      expect(feed.acknowledgements, [1, 2]);
      lease.cancel();
      await owner.close();
    },
  );
  test(
    'same frame completion gates activity publish and acknowledgement',
    () async {
      final transport = _Transport();
      final owner = _owner(transport);
      final consumer = _Consumer();
      final lease = owner.attachConsumer(consumer);
      owner.setDemand(true);
      await _pump();
      final feed = transport.feeds.single;
      feed.send(ConversationBaselineEvent(baseline: _baseline(feed)));
      await _pump();
      const activity = ThreadActivityView(
        threadId: 'thread',
        identity: 'pre-turn',
        revision: 1,
        turnId: null,
        executionId: 'execution',
        kind: ThreadActivityKind.responding,
        summary: '',
      );
      feed.send(
        ConversationActivityContentEvent(
          frame: ActivityBegin(
            generation: 'activity',
            revision: 1,
            baseRevision: null,
            activity: activity,
            reasoning: const [
              ActivityPartMetadata(itemId: 'r1', complete: true, totalBytes: 1),
              ActivityPartMetadata(
                itemId: 'r2',
                complete: false,
                totalBytes: 1,
              ),
            ],
            response: const [
              ActivityPartMetadata(itemId: 'o1', complete: true, totalBytes: 1),
              ActivityPartMetadata(
                itemId: 'o2',
                complete: false,
                totalBytes: 1,
              ),
            ],
            tools: const [],
            totalBytes: 4,
          ),
        ),
      );
      await _pump();
      for (final entry in [
        (ActivityRegionKind.reasoning, 'r1', 'a'),
        (ActivityRegionKind.reasoning, 'r2', 'b'),
        (ActivityRegionKind.response, 'o1', 'c'),
        (ActivityRegionKind.response, 'o2', 'd'),
      ]) {
        feed.send(
          ConversationActivityContentEvent(
            frame: ActivityText(
              generation: 'activity',
              revision: 1,
              operations: [
                ActivityReplace(ActivityRegion(entry.$1, entry.$2), entry.$3),
              ],
            ),
          ),
        );
        await _pump();
      }
      consumer.gate = Completer<void>();
      final reset = ConversationReset(_baseline(feed, epoch: 'new'));
      feed.send(
        ConversationActivityContentEvent(
          frame: const ActivityCommit(generation: 'activity', revision: 1),
          completed: reset,
        ),
      );
      await _pump();
      expect(owner.currentActivity.value, isNull);
      expect(feed.acknowledgements, [1, 2, 3, 4, 5, 6]);
      consumer.gate!.complete();
      await _pump();
      expect(owner.currentActivity.value!.revision, 1);
      expect(owner.currentActivity.value!.activity!.turnId, isNull);
      expect(owner.currentActivity.value!.activity!.executionId, 'execution');
      final projection = projectConversationActivity(
        current: owner.currentActivity.value,
      )!;
      expect(projection.reasoningParts.map((p) => (p.itemId, p.text)), [
        ('r1', 'a'),
        ('r2', 'b'),
      ]);
      expect(projection.responseParts.map((p) => (p.itemId, p.text)), [
        ('o1', 'c'),
        ('o2', 'd'),
      ]);
      expect(feed.acknowledgements, [1, 2, 3, 4, 5, 6, 7]);
      lease.cancel();
      await owner.close();
    },
  );
  test('detached pending consumer is joined and cannot acknowledge', () async {
    final transport = _Transport();
    final owner = _owner(transport);
    final consumer = _Consumer()..gate = Completer<void>();
    final lease = owner.attachConsumer(consumer);
    owner.setDemand(true);
    await _pump();
    final feed = transport.feeds.single;
    feed.send(ConversationBaselineEvent(baseline: _baseline(feed)));
    await _pump();
    lease.cancel();
    final report = await owner.close(
      deadline: DateTime.now().add(const Duration(milliseconds: 20)),
    );
    expect(report.complete, isFalse);
    expect(feed.requested, isTrue);
    expect(feed.acknowledgements, isEmpty);
    consumer.gate!.complete();
    await _pump();
    expect(feed.acknowledgements, isEmpty);
    expect((await owner.retryCleanup()).complete, isTrue);
  });
  test(
    'accepted atoms freeze nested descriptor lists while delivery is pending',
    () async {
      final payloads = [
        const ConversationRawPayloadDescriptor(format: 'json', version: 1),
      ];
      final attachments = [
        const ThreadAttachmentView(
          id: 'file',
          modality: AttachmentModalityView.file,
          mediaType: 'text/plain',
          byteSize: 1,
        ),
      ];
      final questions = [
        const ConversationQuestionDescriptor(
          id: 'question',
          isOther: false,
          isSecret: false,
        ),
      ];
      final answers = [
        const ConversationAnswerDescriptor(
          questionId: 'question',
          answerCount: 1,
          redacted: false,
        ),
      ];
      final targets = [
        const ThreadWaitTargetView(taskId: 'task', summary: 'running'),
      ];
      final wait = ThreadWaitPresentationView(
        intent: ThreadWaitEventsIntentView(targets: targets, timeoutMs: 100),
        state: ThreadWaitStateView.waiting,
      );
      final raw = ConversationRawDescriptor(
        origin: ThreadRawItemOrigin.stored,
        payloads: payloads,
        notice: 'notice',
        recordedAt: DateTime.utc(2026),
      );
      final output = ConversationToolOutputDescriptor(attachments: attachments);
      final resolved = ConversationUserInputResolved(answers: answers);
      final input = ConversationUserInputDescriptor(
        interactionId: 'input',
        questions: questions,
        state: resolved,
      );
      final items = [
        ConversationItem(
          header: const ConversationItemHeader(
            id: 'raw',
            threadId: 'thread',
            appendSeq: 1,
          ),
          source: const ConversationContentSource(),
          descriptor: raw,
          fields: const [],
        ),
        ConversationItem(
          header: const ConversationItemHeader(
            id: 'tool',
            threadId: 'thread',
            appendSeq: 2,
          ),
          source: const ConversationContentSource(),
          descriptor: ConversationToolDescriptor(
            invocation: const ConversationToolInvocation(
              toolCallId: 'call',
              name: 'tool',
            ),
            state: ConversationToolSucceeded(
              completedAt: DateTime.utc(2026),
              output: output,
            ),
            userInput: input,
            wait: wait,
          ),
          fields: const [],
        ),
      ];
      final transport = _Transport();
      final owner = _owner(transport);
      final consumer = _Consumer();
      final lease = owner.attachConsumer(consumer);
      owner.setDemand(true);
      await _pump();
      final feed = transport.feeds.single;
      feed.send(ConversationBaselineEvent(baseline: _baseline(feed)));
      await _pump();
      consumer.gate = Completer<void>();
      feed.send(
        ConversationUpdateEvent(
          update: ConversationBatch(
            subscriptionId: feed.subscriptionId,
            timelineEpoch: 'epoch',
            fromSeq: 0,
            throughSeq: 2,
            items: items,
          ),
        ),
      );
      await _pump();
      expect(consumer.frames, hasLength(2));
      expect(feed.acknowledgements, [1]);
      payloads.add(
        ConversationRawPayloadDescriptor(
          format: 'x' * (300 * 1024),
          version: 2,
        ),
      );
      attachments.clear();
      questions.clear();
      answers.clear();
      targets.add(ThreadWaitTargetView(taskId: 'x' * (300 * 1024)));
      targets.first = const ThreadWaitTargetView(taskId: 'replaced');
      final delivered =
          (consumer.frames.last as ConversationCompletedBatchFrame).batch.items;
      final actualRaw = delivered.first.descriptor as ConversationRawDescriptor;
      final actualTool =
          delivered.last.descriptor as ConversationToolDescriptor;
      final actualOutput =
          (actualTool.state as ConversationToolSucceeded).output;
      final actualInput = actualTool.userInput!;
      final actualAnswers =
          (actualInput.state as ConversationUserInputResolved).answers;
      final actualTargets =
          (actualTool.wait!.intent as ThreadWaitEventsIntentView).targets;
      expect(actualRaw.payloads.single.format, 'json');
      expect(actualOutput.attachments.single.id, 'file');
      expect(actualInput.questions.single.id, 'question');
      expect(actualAnswers.single.questionId, 'question');
      expect(actualTargets.single.taskId, 'task');
      expect(() => actualRaw.payloads.clear(), throwsUnsupportedError);
      expect(() => actualOutput.attachments.clear(), throwsUnsupportedError);
      expect(() => actualInput.questions.clear(), throwsUnsupportedError);
      expect(() => actualAnswers.clear(), throwsUnsupportedError);
      expect(() => actualTargets.clear(), throwsUnsupportedError);
      consumer.gate!.complete();
      await _pump();
      expect(feed.acknowledgements, [1, 2]);
      lease.cancel();
      expect((await owner.close()).complete, isTrue);
    },
  );
  test(
    'late old activity commit cannot overwrite a replacement feed',
    () async {
      final transport = _Transport();
      final owner = _owner(transport);
      final oldConsumer = _Consumer();
      final oldLease = owner.attachConsumer(oldConsumer);
      owner.setDemand(true);
      await _pump();
      final first = transport.feeds.single;
      first.send(ConversationBaselineEvent(baseline: _baseline(first)));
      await _pump();
      ActivityBegin begin(String generation) => ActivityBegin(
        generation: generation,
        revision: 1,
        baseRevision: null,
        activity: ThreadActivityView(
          threadId: 'thread',
          identity: generation,
          revision: 1,
          turnId: null,
          kind: ThreadActivityKind.preparing,
          summary: '',
        ),
        reasoning: const [],
        response: const [],
        tools: const [],
        totalBytes: 0,
      );
      first.send(ConversationActivityContentEvent(frame: begin('old')));
      await _pump();
      oldConsumer.gate = Completer<void>();
      first.send(
        ConversationActivityContentEvent(
          frame: const ActivityCommit(generation: 'old', revision: 1),
          completed: ConversationReset(_baseline(first, epoch: 'other')),
        ),
      );
      await _pump();
      expect(oldConsumer.frames, hasLength(2));
      expect(owner.currentActivity.value, isNull);
      oldLease.cancel();
      final nextLease = owner.attachConsumer(_Consumer());
      await _pump();
      final second = transport.feeds.last;
      expect(second, isNot(same(first)));
      second.send(ConversationBaselineEvent(baseline: _baseline(second)));
      await _pump();
      second.send(ConversationActivityContentEvent(frame: begin('new')));
      await _pump();
      second.send(
        const ConversationActivityContentEvent(
          frame: ActivityCommit(generation: 'new', revision: 1),
        ),
      );
      await _pump();
      expect(owner.currentActivity.value!.activity!.identity, 'new');
      oldConsumer.gate!.complete();
      await _pump();
      expect(owner.currentActivity.value!.activity!.identity, 'new');
      expect(first.acknowledgements, [1, 2]);
      nextLease.cancel();
      expect((await owner.close()).complete, isTrue);
    },
  );
  test(
    'reopen resumes accepted cursor and reset is delivered to consumer',
    () async {
      final transport = _Transport();
      final owner = _owner(transport);
      final consumer = _Consumer();
      final lease = owner.attachConsumer(consumer);
      owner.setDemand(true);
      await _pump();
      final first = transport.feeds.single;
      first.send(ConversationBaselineEvent(baseline: _baseline(first, seq: 7)));
      await _pump();
      owner.refresh();
      await _pump();
      expect(
        transport.resumes.last,
        const ConversationCompletionCursor(
          timelineEpoch: 'epoch',
          appendSeq: 7,
        ),
      );
      final second = transport.feeds.last;
      second.send(
        ConversationUpdateEvent(
          update: ConversationReset(_baseline(second, epoch: 'new')),
        ),
      );
      await _pump();
      expect(consumer.frames.last, isA<ConversationResetFrame>());
      expect(second.acknowledgements, [1]);
      lease.cancel();
      await owner.close();
    },
  );
}
