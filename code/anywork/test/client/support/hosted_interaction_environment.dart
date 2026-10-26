import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/state/conversation_view_state.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../../anywork_client/test/support/drafts_native_fixture.dart';
import '../../../../anywork_client/test/support/profile_native_pin.dart';
import '../../../../anywork_client/test/support/timeline_transport.dart';
import 'conversation_workspace_fixture.dart';
import 'selector_environment.dart' show waitLatest;

const hostedEpoch = 'hosted-native';
const hostedHost = 'thread-main';
const hostedChild = 'thread-reviewer';

final class HostedRead {
  HostedRead(this.host, this.reference, this.origin);
  final String host;
  final InteractionReadRef reference;
  final ThreadFacetStamp origin;
}

final class HostedResponse {
  HostedResponse(this.host, this.interactionId, this.operationId, this.revision, this.resolution);
  final String host, interactionId;
  final OperationId operationId;
  final int revision;
  final InteractionResolutionCommand resolution;
  final reply = Completer<InteractionCommandReply>();
}

final class HostedCommands extends UnscriptedConversationCommands {
  final calls = DraftCalls<HostedResponse>();
  @override
  Future<InteractionCommandReply> respondInteraction(String hostThreadId, String interactionId, {
    required OperationId operationId,
    required int expectedInteractionRevision,
    required InteractionResolutionCommand resolution,
  }) {
    final call = HostedResponse(hostThreadId, interactionId, operationId, expectedInteractionRevision, resolution);
    calls.add(call);
    return call.reply.future;
  }
}

/// Immutable source material only. Replies never publish an index or alter a
/// read: tests explicitly advance each independent native fact/barrier.
final class HostedInteractionEnvironment {
  HostedInteractionEnvironment({this.host = hostedHost}) {
    operations = OperationRegistry(clientId: 'hosted-test', budget: budget);
    port.interactionIndexOpen = (id, reference, origin) async => _Index(this, reference.revision, id);
    port.interactionResolve = (id, interactionId, revision, origin) async => InteractionReadRef(entry: entryFor(interactionId), revision: revision);
    port.interactionOpen = (id, reference, origin) async {
      reads.add(HostedRead(id, reference, origin));
      return _Detail(this, reference, origin, id);
    };
    final assembly = createConversationRepository(
      port: port, context: context, commands: commands, timeline: timeline,
      budget: budget, operations: operations,
      agentDirectory: () => workspaceOwner.workspace.agents,
    );
    conversations = assembly.repository;
    demand = assembly.demand;
    workspaceOwner = ConversationWorkspaceFixture(budget: budget, operations: operations, archive: assembly.archive);
    container = ProviderContainer(retry: (_, _) => null, overrides: [
      conversationRepositoryProvider.overrideWithValue(conversations),
      workspaceRepositoryProvider.overrideWithValue(workspaceOwner.workspace),
    ]);
  }
  String host;
  final budget = ResourceBudget();
  final port = FixtureConversationPort();
  final context = FixtureConversationContext();
  final timeline = TimelineOpenQueue();
  final commands = HostedCommands();
  final reads = DraftCalls<HostedRead>();
  final headerReads = DraftCalls<HostedRead>();
  final gates = <(String, int, int), Completer<void>>{};
  final failures = <(String, int, int), StudioFailure>{};
  final resolutions = <(String, String), InteractionResolutionCommand>{};
  final indexMaterials = <int, List<InteractionBrief>>{};
  final indexHeaderReads = DraftCalls<int>();
  late final OperationRegistry operations;
  late final ConversationRepository conversations;
  late final ConversationDemand demand;
  late final ConversationWorkspaceFixture workspaceOwner;
  late final ProviderContainer container;
  final subscriptions = <ProviderSubscription<AsyncValue<ConversationViewState>>>[];
  int selectionGeneration = 0;
  late FacetOpen<ThreadExecutionFrame> opening;
  int revision = 1;
  final resolvedIds = <String>{};
  ConversationSession get session => conversations.existingSession(host)!;
  ConversationViewModel get vm => container.read(conversationViewModelProvider(host).notifier);
  ThreadFacetStamp get origin => ThreadFacetStamp(runtimeEpoch: hostedEpoch, incarnation: 1, facet: ThreadFacet.execution, revision: revision);

  int entryFor(String id) => const ['qa', 'approval', 'root-qa', 'child-plan'].indexOf(id) + 1;
  String idFor(int entry) => const ['qa', 'approval', 'root-qa', 'child-plan'][entry - 1];
  String target(String id, {String? fromHost}) {
    final owner = fromHost ?? host;
    const targets = {hostedHost: hostedChild, 'thread-alt': 'thread-alt-child'};
    return id == 'root-qa' ? owner : targets[owner]!;
  }
  List<InteractionBrief> briefs() => [
    for (var entry = 1; entry <= 4; entry++) InteractionBrief(
      reference: InteractionReadRef(entry: entry, revision: resolvedIds.contains(idFor(entry)) ? 2 : 1),
      revision: resolvedIds.contains(idFor(entry)) ? 2 : 1,
      kind: entry == 2 ? InteractionKind.toolApproval : InteractionKind.userInput,
      status: resolvedIds.contains(idFor(entry)) ? InteractionStatus.resolved : InteractionStatus.pending,
      createdAt: 1, updatedAt: resolvedIds.contains(idFor(entry)) ? 2 : 1,
    ),
  ];

  Future<void> establish() => selectHost(host);

  Future<void> selectHost(String next) async {
    host = next;
    revision = 1;
    resolvedIds.clear();
    indexMaterials[1] = briefs();
    final openIndex = port.execution.length;
    demand.select(threadId: host, needsOpen: false, selectionGeneration: ++selectionGeneration);
    opening = await port.executionOpened(openIndex);
    await opening.feed.listened.future;
    opening.feed.emit(ThreadExecutionFrame.data(deliverySequence: 1, event: ThreadExecutionEvent.baseline(
      identity: ThreadFeedIdentity(feedId: opening.feed.feedId, runtimeEpoch: hostedEpoch, incarnation: 1, facet: ThreadFacet.execution, mode: ThreadObservationMode.hot),
      stamp: origin,
      value: ThreadExecutionBaseline(status: ThreadStatus.idle, execution: null, continuation: null,
        activeTurn: null, recentTerminalTurn: null,
        interactions: const InteractionIndexHeader(reference: InteractionIndexRef(entry: 10, revision: 1), total: 4, pending: 4), activity: null, storage: null),
    )));
    await opening.feed.acknowledged(1);
    await waitLatest(conversations.active, (value) => identical(value, session));
    subscriptions.add(container.listen(conversationViewModelProvider(host), (_, _) {}));
    await container.read(conversationViewModelProvider(host).future);
    await vm.loadInteractions();
  }

  InteractionEditorKey key(String id) => container.read(conversationViewModelProvider(host)).requireValue.currentEditors.firstWhere((key) => key.interactionId == id);

  Future<void> publishResolved(String id) async {
    resolvedIds.add(id);
    final previous = revision++;
    final material = briefs();
    indexMaterials[revision] = material;
    opening.feed.emit(ThreadExecutionFrame.data(deliverySequence: revision, event: ThreadExecutionEvent.change(
      stamp: origin, baseRevision: previous,
      value: ThreadExecutionChange(status: null, turns: null,
        interactions: InteractionDelta(baseIndexRevision: previous,
          index: InteractionIndexHeader(reference: InteractionIndexRef(entry: 10, revision: revision), total: 4, pending: 4 - resolvedIds.length),
          upserted: material, removedEntries: const [], terminalFacts: [material.firstWhere((brief) => brief.reference.entry == entryFor(id))]),
        activity: const ActivityReplacement.unchanged(), storage: const StorageReplacement.unchanged()),
    )));
    await opening.feed.acknowledged(revision);
  }

  InteractionCommandReply reply(HostedResponse call) {
    final id = call.interactionId;
    return InteractionCommandReply(
      interaction: InteractionSnapshot(interactionId: id,
        scope: InteractionScope(threadId: target(id, fromHost: call.host), turnId: 'turn-$id', itemId: null, toolId: null, agentPath: 'root/reviewer'),
        revision: 2, createdAt: 1, updatedAt: 2,
        content: call.resolution is UserInputResolutionCommand
          ? InteractionSnapshotContent.userInput(questions: [InteractionQuestion(id: 'q', header: 'Direction', question: 'Choose direction', isOther: true, isSecret: false, options: [])], state: UserInputInteractionState.resolved(operationId: 'native-$id', resolvedAt: 2, answers: (call.resolution as UserInputResolutionCommand).answers))
          : InteractionSnapshotContent.toolApproval(name: 'shell', arguments: '{"command":"ls"}', workingDirectory: '/workspace', parentAgentId: call.host, state: ToolApprovalInteractionState.resolved(operationId: 'native-$id', resolvedAt: 2, decision: (call.resolution as ToolApprovalResolutionCommand).decision, reason: (call.resolution as ToolApprovalResolutionCommand).reason)),
      ),
      receipt: CommitReceipt(operationId: call.operationId, disposition: CommitDisposition.applied,
        targets: const [], effect: EffectPoint.immediate, requiresIdentityObservation: true),
    );
  }

  Future<void> close() async {
    for (final gate in gates.values) { if (!gate.isCompleted) gate.complete(); }
    for (final call in commands.calls.values) {
      if (!call.reply.isCompleted) call.reply.completeError(const CommandDispatchFailure.rejected(failure: StudioFailure(code: StudioFailureCode.cancelled, message: 'fixture closed', retryable: false, correlationId: 'hosted-close')));
    }
    for (final subscription in subscriptions) { subscription.close(); }
    container.dispose();
    await workspaceOwner.close();
    final report = await conversations.close(deadline: DateTime.now().add(const Duration(seconds: 3)));
    expectSync(report.unresolved, isEmpty);
    operations.seal();
    expectSync(budget.usage, isEmpty);
  }
}

final class _Index extends ProfileNativePin implements InteractionIndexReadConnection {
  _Index(this.env, this.revision, this.host) : super('$host-index-$revision');
  final HostedInteractionEnvironment env;
  final int revision;
  final String host;
  ReadScopeIdentity get scope => ReadScopeIdentity(scopeId: id, runtimeEpoch: hostedEpoch, incarnation: 1, sourceRevision: revision);
  @override
  Future<InteractionIndexReadHeader> header() async {
    env.indexHeaderReads.add(revision);
    final items = env.indexMaterials[revision]!;
    return InteractionIndexReadHeader(scope: scope, total: items.length, pending: items.where((item) => item.status == InteractionStatus.pending).length);
  }
  @override
  Future<InteractionBriefPage> entries({int offset = 0, int limit = 32}) async => InteractionBriefPage(scope: scope, offset: offset, total: 4, items: env.indexMaterials[revision]!.skip(offset).take(limit).toList(), nextOffset: null);
}

final class _Detail extends ProfileNativePin implements InteractionReadConnection {
  _Detail(this.env, this.reference, this.origin, this.host) : super('$host-detail-${reference.entry}-${reference.revision}');
  final HostedInteractionEnvironment env;
  final InteractionReadRef reference;
  final ThreadFacetStamp origin;
  final String host;
  String get interaction => env.idFor(reference.entry);
  ReadScopeIdentity get scope => ReadScopeIdentity(scopeId: id, runtimeEpoch: hostedEpoch, incarnation: 1, sourceRevision: origin.revision);
  @override
  Future<InteractionReadHeader> header() => reply(Future<InteractionReadHeader>.sync(() async {
    env.headerReads.add(HostedRead(host, reference, origin));
    await env.gates[(host, reference.entry, reference.revision)]?.future;
    if (env.failures[(host, reference.entry, reference.revision)] case final failure?) throw failure;
    final resolved = reference.revision > 1;
    final approval = reference.entry == 2;
    return InteractionReadHeader(scope: scope,
      interactionId: ReadText.inline(text: interaction), threadId: ReadText.inline(text: env.target(interaction, fromHost: host)),
      turnId: ReadText.inline(text: 'turn-$interaction'), itemId: null, toolId: null,
      agentPath: ReadText.inline(text: 'root/reviewer'), revision: reference.revision,
      purpose: reference.entry == 4 ? const InteractionPurposeRead.planConfirmation(expectedRevision: 1, operationId: ReadText.inline(text: 'native-child-plan'), argumentHash: ReadText.inline(text: 'args'), planHash: ReadText.inline(text: 'hash')) : const InteractionPurposeRead.general(),
      continuation: null, createdAt: 1, updatedAt: reference.revision,
      content: approval ? InteractionContentRead.toolApproval(name: ReadText.inline(text: 'shell'), arguments: ReadText.inline(text: '{"command":"ls"}'), workingDirectory: ReadText.inline(text: '/workspace'), parentAgentId: ReadText.inline(text: host)) : const InteractionContentRead.userInput(questionCount: 1),
      state: !resolved ? InteractionStateRead.pending(operationId: ReadText.inline(text: 'native-$interaction')) : approval ? InteractionStateRead.approvalResolved(operationId: ReadText.inline(text: 'native-$interaction'), resolvedAt: 2, decision: (env.resolutions[(host, interaction)] as ToolApprovalResolutionCommand).decision, reason: const ReadText.inline(text: 'reviewed')) : InteractionStateRead.userInputResolved(operationId: ReadText.inline(text: 'native-$interaction'), resolvedAt: 2, answerEntryCount: 1),
    );
  }));
  @override
  Future<QuestionPage> questions({int offset = 0, int limit = 32}) async => QuestionPage(scope: scope, offset: offset, total: 1, nextOffset: null,
    items: [QuestionReadItem(index: 0, id: ReadText.inline(text: reference.entry == 4 ? agentSessionPlanConfirmationQuestionId : 'q'), header: const ReadText.inline(text: 'Direction'), question: const ReadText.inline(text: 'Choose direction'), isOther: true, isSecret: false, optionsCount: 0)]);
  @override
  Future<AnswerEntryPage> answerEntries({int offset = 0, int limit = 32}) async => AnswerEntryPage(scope: scope, offset: offset, total: 1, nextOffset: null, items: const [AnswerEntryReadItem(index: 0, questionId: ReadText.inline(text: 'q'), answerCount: 1)]);
  @override
  Future<AnswerValuePage> answerValues(int index, {int offset = 0, int limit = 32}) async => AnswerValuePage(scope: scope, offset: offset, total: 1, nextOffset: null, items: [AnswerValueReadItem(index: 0, value: ReadText.inline(text: (env.resolutions[(host, interaction)] as UserInputResolutionCommand).answers.single.answers.single))]);
}
