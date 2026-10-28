import 'package:anywork/src/features/conversation/state/plan_confirmation_ownership.dart';

import 'dart:async';
import 'dart:convert';

import 'package:anywork/src/diagnostics/contracts/timeline_diagnostics.dart';
import 'package:anywork/src/features/conversation/state/read_material.dart';
import 'package:anywork/src/features/conversation/state/thread_status_state.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/state/interaction_view_state.dart';
import 'package:anywork/src/features/conversation/view_models/interaction_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/conversation_view_model.dart';
import 'package:anywork/src/features/conversation/view_models/thread_status_view_model.dart';
import 'package:anywork/src/features/workspace/view_models/workspace_view_model.dart';
import 'package:anywork/src/features/settings/accounts/view_models/accounts_view_model.dart';
import 'package:anywork/src/features/settings/accounts/state/accounts_state.dart';
import 'package:anywork/src/shared/driver_projection.dart';
import 'package:anywork/src/shared/driver_snapshot.dart';
import 'package:anywork/src/shared/driver_snapshot_json.dart';
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart' show AttachmentModality;
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/statistics_ports.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/conversation_fixture.dart'
    show fixtureThread;
import '../../../anywork_client/test/support/timeline_transport.dart';
import '../../../anywork_client/test/support/statistics_test_port.dart';
import '../../test_driver/driver_inspection.dart';
import '../../test_driver/driver_product_requests.dart';
import '../../test_driver/timeline_observation.dart';
import 'support/driver_environment.dart';
import 'support/driver_interaction_native.dart';
import 'support/selector_conversation_port.dart';
import 'support/selector_directory_port.dart';

Future<DriverTestEnvironment> _environment({
  List<WorkspaceThreadRecord>? threads,
  List<AgentDirectoryEntry>? agents,
  List<RecoveryIssueRead> recoveryIssues = const [],
}) async {
  final env = DriverTestEnvironment();
  addTearDown(env.close);
  await env.establish(
    threads: threads ?? [_factsThread()],
    agents: agents,
    recoveryIssues: recoveryIssues,
  );
  return env;
}

Future<void> _driverConversation(DriverTestEnvironment env) async {
  final container = env.application.container;
  const host = 'thread-main';
  if (env.application.graph.conversation.active.value?.threadId != host) {
    await env.mountDirectory();
    await env.openContent(baseline(1, items: const []), threadId: host);
  }
  final provider = conversationViewModelProvider(host);
  if (!container.exists(provider)) {
    final hold = container.listen(provider, (_, _) {});
    addTearDown(hold.close);
    await container.read(provider.future);
  }
  await container.read(provider.notifier).loadInteractions();
}

Future<InteractionViewState> _driverEditorState(
  DriverTestEnvironment env,
  InteractionEditorKey key,
  bool Function(InteractionViewState) matches,
) {
  final done = Completer<InteractionViewState>();
  final watch = env.application.container.listen(
    interactionViewModelProvider(key),
    (_, next) {
      final value = next.asData?.value;
      if (!done.isCompleted && value != null && matches(value)) {
        done.complete(value);
      }
    },
    fireImmediately: true,
  );
  return done.future.whenComplete(watch.close);
}

Future<InteractionEditorKey> _driverEditor(
  DriverTestEnvironment env,
  String id, {
  bool complete = true,
}) async {
  final container = env.application.container;
  final key = container
      .read(conversationViewModelProvider('thread-main'))
      .requireValue
      .currentEditors
      .singleWhere((key) => key.interactionId == id);
  final provider = interactionViewModelProvider(key);
  final hold = container.listen(provider, (_, _) {});
  addTearDown(hold.close);
  await container.read(provider.future);
  if (complete) {
    await container.read(provider.notifier).completeRead();
  } else {
    await _driverEditorState(env, key, (state) => state.header != null);
  }
  return key;
}

DriverSnapshot _passiveDriverCapture(
  DriverTestEnvironment env,
  DriverInteractionNative native,
) {
  final container = env.application.container;
  final graph = env.application.graph;
  final session = graph.conversation.existingSession('thread-main');
  final commands = env.application.domains.commands;
  List<int?> observerCounts() => [
    graph.conversation.active.observerCount,
    graph.conversation.activationFailure.observerCount,
    session?.execution.observerCount,
    session?.metrics.observerCount,
    session?.context.observerCount,
    session?.configuration.observerCount,
    session?.authoring.observerCount,
    session?.interactions.observerCount,
    graph.workspace.state.observerCount,
    graph.workspace.projects.observerCount,
    graph.workspace.agents.observerCount,
    graph.drafts.startRoutes.observerCount,
    graph.operations.records.observerCount,
  ];
  List<int> commandCounts() => [
    commands.routes.values.length,
    commands.modes.values.length,
    commands.prompts.values.length,
    commands.acceptances.values.length,
    commands.interrupts.values.length,
    commands.continues.values.length,
    commands.continuationReads.values.length,
  ];
  final conversation = conversationViewModelProvider('thread-main');
  final conversationExisted = container.exists(conversation);
  final keys = container.exists(conversation)
      ? container.read(conversation).asData?.value.currentEditors.toList() ??
            <InteractionEditorKey>[]
      : <InteractionEditorKey>[];
  final existed = [
    for (final key in keys) container.exists(interactionViewModelProvider(key)),
  ];
  final permits = List.of(env.application.graph.budget.usage);
  final requests = (env.nativeActivity, native.activity);
  final observers = observerCounts();
  final commandCalls = commandCounts();
  final operations = List.of(graph.operations.records.value);
  final snapshot = DriverInspection(
    graph: env.application.graph,
    container: container,
  ).capture();
  snapshot.toJson();
  expect([
    for (final key in keys) container.exists(interactionViewModelProvider(key)),
  ], existed);
  expect(container.exists(conversation), conversationExisted);
  expect(env.application.graph.budget.usage, permits);
  expect((env.nativeActivity, native.activity), requests);
  expect(observerCounts(), observers);
  expect(commandCounts(), commandCalls);
  expect(graph.operations.records.value, operations);
  return snapshot;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Driver borrows mounted Plan/Approval/question owners: exact typed purpose/body, no drafts or new demand', () async {
    final env = await _environment(threads: [fixtureThread('thread-main')]);
    final native = DriverInteractionNative(
      env.application.domains.conversationPort,
    );
    final container = env.application.container;
    await env.mountDirectory();
    await env.openContent(
      baseline(1, items: const []),
      threadId: 'thread-main',
    );
    expect(
      container.exists(conversationViewModelProvider('thread-main')),
      isFalse,
    );
    expect(_passiveDriverCapture(env, native).interactionEditors, isNull);
    expect(
      container.exists(conversationViewModelProvider('thread-main')),
      isFalse,
    );
    await _driverConversation(env);
    const planBody =
        '# Actual native plan\n\n1. Preserve the original scope.\n2. Keep the exact body.';
    await native.publish(const [
      DriverInteractionMaterial(
        entry: 1,
        id: 'plan-live',
        targetThreadId: 'thread-main',
        kind: DriverInteractionMaterialKind.plan,
        title: 'Actual plan',
        body: planBody,
        questionId: agentSessionPlanConfirmationQuestionId,
      ),
    ]);
    await _driverConversation(env);
    final planKey = container
        .read(conversationViewModelProvider('thread-main'))
        .requireValue
        .currentEditors
        .single;
    expect(container.exists(interactionViewModelProvider(planKey)), isFalse);
    expect(
      _passiveDriverCapture(env, native).interactionEditors,
      isNull,
      reason: 'A current key is not mounted material',
    );
    await _driverEditor(env, 'plan-live');
    container
        .read(interactionViewModelProvider(planKey).notifier)
        .setPlanFeedback('SYNTHETIC-PLAN-DRAFT-NOT-FOR-DRIVER');
    final snapshot = _passiveDriverCapture(env, native);
    final workspace = snapshot.toJson()['workspace'] as Map;
    final plan = workspace['activeInteraction'] as Map;
    expect(plan['id'], 'plan-live');
    expect(plan['threadId'], 'thread-main');
    expect(plan['hostThreadId'], 'thread-main');
    expect(plan['turnId'], 'turn-plan-live');
    expect(plan['kind'], 'userInput');
    expect(plan['title'], 'Actual plan');
    expect(plan['body'], planBody);
    expect(plan['purpose'], {
      'kind': 'planConfirmation',
      'expectedRevision': 7,
      'operationId': 'native-plan-op',
      'argumentHash': 'args-hash',
      'planHash': 'plan-hash',
    });
    expect(
      jsonEncode(snapshot.toJson()),
      isNot(contains('SYNTHETIC-PLAN-DRAFT-NOT-FOR-DRIVER')),
    );
    expect(() => snapshot.interactionEditors!.clear(), throwsUnsupportedError);

    const arguments = '{"command":"printf driver-proof","cwd":"/workspace"}';
    await native.publish(const [
      DriverInteractionMaterial(
        entry: 2,
        id: 'approval-live',
        targetThreadId: 'thread-main',
        kind: DriverInteractionMaterialKind.approval,
        title: 'shell',
        body: arguments,
      ),
    ]);
    await _driverConversation(env);
    final approvalKey = await _driverEditor(env, 'approval-live');
    container
        .read(interactionViewModelProvider(approvalKey).notifier)
        .setApprovalReason('SYNTHETIC-APPROVAL-DRAFT-NOT-FOR-DRIVER');
    final approvalSnapshot = _passiveDriverCapture(env, native);
    final approval =
        (approvalSnapshot.toJson()['workspace'] as Map)['activeInteraction']
            as Map;
    expect(
      (
        approval['id'],
        approval['turnId'],
        approval['kind'],
        approval['title'],
        approval['body'],
      ),
      (
        'approval-live',
        'turn-approval-live',
        'toolApproval',
        'shell',
        arguments,
      ),
    );
    expect(approval['content'], {
      'name': 'shell',
      'arguments': arguments,
      'workingDirectory': '/workspace',
      'parentAgentId': 'thread-main',
    });
    expect(approval['purpose'], {'kind': 'general'});
    expect(
      jsonEncode(approvalSnapshot.toJson()),
      isNot(contains('SYNTHETIC-APPROVAL-DRAFT-NOT-FOR-DRIVER')),
    );

    await native.publish(const [
      DriverInteractionMaterial(
        entry: 3,
        id: 'ordinary-reserved-id',
        targetThreadId: 'thread-main',
        kind: DriverInteractionMaterialKind.question,
        title: 'Plan review',
        body: '# This is a normal question',
        questionId: agentSessionPlanConfirmationQuestionId,
        optionsCount: 2,
        options: [
          OptionReadItem(
            index: 0,
            label: ReadText.inline(text: 'Native first choice'),
            description: ReadText.inline(text: 'Keep the original owner'),
          ),
          OptionReadItem(
            index: 1,
            label: ReadText.inline(text: 'Native second choice'),
            description: ReadText.inline(text: 'Use another native route'),
          ),
        ],
      ),
    ]);
    await _driverConversation(env);
    final ordinaryKey = await _driverEditor(env, 'ordinary-reserved-id');
    await _driverEditorState(
      env,
      ordinaryKey,
      (state) =>
          state.sourceCurrent &&
          state.questions[0]?.options.length == 2 &&
          !state.questions[0]!.optionsLoading &&
          state.questions[0]!.nextOptionOffset == null,
    );
    container
        .read(interactionViewModelProvider(ordinaryKey).notifier)
        .setQuestionText(0, 'SYNTHETIC-ANSWER-DRAFT-NOT-FOR-DRIVER');
    container
        .read(interactionViewModelProvider(ordinaryKey).notifier)
        .setOptionSelected(0, 'Native first choice', true);
    expect(
      container
          .read(interactionViewModelProvider(ordinaryKey))
          .requireValue
          .answers[0]!
          .selectedLabels,
      ['Native first choice'],
    );
    final ordinarySnapshot = _passiveDriverCapture(env, native);
    final ordinary =
        (ordinarySnapshot.toJson()['workspace'] as Map)['activeInteraction']
            as Map;
    expect(
      ordinary['purpose'],
      {'kind': 'general'},
      reason: 'Purpose comes from the typed header, never a reserved question ID or title',
    );
    expect(ordinary['body'], '# This is a normal question');
    final ordinaryQuestion =
        ((ordinary['content'] as Map)['questions'] as List).single as Map;
    expect(ordinaryQuestion['optionsCount'], 2);
    expect(ordinaryQuestion['options'], [
      {
        'index': 0,
        'label': 'Native first choice',
        'description': 'Keep the original owner',
      },
      {
        'index': 1,
        'label': 'Native second choice',
        'description': 'Use another native route',
      },
    ]);
    expect(ordinaryQuestion['optionsComplete'], isTrue);
    expect(native.optionReads.single, (
      host: 'thread-main',
      reference: const InteractionReadRef(entry: 3, revision: 1),
      questionIndex: 0,
      offset: 0,
      limit: 32,
    ));
    expect(
      jsonEncode(ordinarySnapshot.toJson()),
      isNot(contains('SYNTHETIC-ANSWER-DRAFT-NOT-FOR-DRIVER')),
    );
    expect(ordinary.keys, isNot(contains('answers')));
    expect(ordinary.keys, isNot(contains('approvalReason')));
    expect(ordinary.keys, isNot(contains('planFeedback')));
    for (final field in [
      'answers',
      'selectedLabels',
      'approvalReason',
      'planFeedback',
    ]) {
      expect(
        jsonEncode(ordinarySnapshot.toJson()),
        isNot(contains('"$field":')),
      );
    }
  });

  test('Driver keeps host scope and child target distinct, rejects retained old keys and foreign target/scope material', () async {
    final env = await _environment(threads: [fixtureThread('thread-main')]);
    final native = DriverInteractionNative(
      env.application.domains.conversationPort,
    );
    final container = env.application.container;
    await _driverConversation(env);
    const original = DriverInteractionMaterial(
      entry: 1,
      id: 'hosted-live',
      targetThreadId: 'cold-child',
      kind: DriverInteractionMaterialKind.question,
      title: 'Child question',
      body: 'Original child body',
    );
    await native.publish(const [original]);
    await _driverConversation(env);
    final oldKey = await _driverEditor(env, 'hosted-live');
    final oldValue = container
        .read(interactionViewModelProvider(oldKey))
        .requireValue;
    expect(oldKey.isHosted, isTrue);
    expect(
      oldValue.header!.threadId,
      const ReadText.inline(text: 'cold-child'),
    );
    final captured = _passiveDriverCapture(env, native);
    final hosted =
        (captured.toJson()['workspace'] as Map)['activeInteraction'] as Map;
    expect(
      (hosted['hostThreadId'], hosted['threadId'], hosted['body']),
      ('thread-main', 'cold-child', 'Original child body'),
    );
    expect(native.reads.last.host, 'thread-main');
    expect(
      env.application.graph.conversation.existingSession('cold-child'),
      isNull,
    );

    await native.publish(const [
      DriverInteractionMaterial(
        entry: 1,
        id: 'hosted-live',
        revision: 2,
        targetThreadId: 'cold-child',
        kind: DriverInteractionMaterialKind.question,
        title: 'Child question',
        body: 'New authoritative child body',
      ),
    ]);
    await _driverConversation(env);
    final currentConversation = container
        .read(conversationViewModelProvider('thread-main'))
        .requireValue;
    final newKey = currentConversation.currentEditors.single;
    expect(newKey, isNot(oldKey));
    expect(
      _passiveDriverCapture(env, native).interactionEditors,
      isNull,
      reason: 'The old mounted owner cannot fill a current same-ID key',
    );
    DriverSnapshot captureMaterials(List<InteractionViewState> values) =>
        captureDriverSnapshot(
          env.application.graph,
          visible: DriverViewFacts(
            conversation: container
                .read(conversationViewModelProvider('thread-main'))
                .requireValue,
            interactionEditors: values,
          ),
          bots: const DriverBotsUnknown('not mounted'),
        );
    expect(captureMaterials([oldValue]).interactionEditors, isNull);
    await _driverEditor(env, 'hosted-live');
    final current = container
        .read(interactionViewModelProvider(newKey))
        .requireValue;
    expect(current.scope!.sourceRevision, 2);
    final supplied = [current];
    final immutableCapture = captureMaterials(supplied);
    supplied.clear();
    expect(immutableCapture.interactionEditors, [
      current,
    ], reason: 'Snapshot takes an immutable request-local copy');
    expect(
      (immutableCapture.toJson()['workspace'] as Map)['activeInteraction'],
      isA<Map>().having(
        (value) => value['body'],
        'body',
        'New authoritative child body',
      ),
    );
    expect(
      captureMaterials([
        current.copyWith(
          header: current.header!.copyWith(
            threadId: const ReadText.inline(text: 'foreign-target'),
          ),
        ),
      ]).interactionEditors,
      isNull,
    );
    expect(
      captureMaterials([current.copyWith(scope: oldValue.scope)])
          .interactionEditors,
      isNull,
    );
    expect(
      captureMaterials([
        current.copyWith(
          key: newKey.copyWith(sourceGeneration: newKey.sourceGeneration + 1),
        ),
      ]).interactionEditors,
      isNull,
    );
    native.failures.add((1, 2));
    await container
        .read(interactionViewModelProvider(newKey).notifier)
        .retryRead();
    expect(
      container
          .read(interactionViewModelProvider(newKey))
          .requireValue
          .readIssues,
      isNotEmpty,
    );
    expect(
      _passiveDriverCapture(env, native).interactionEditors,
      isNull,
      reason: 'A failed real reread cannot expose retained last-good material',
    );
    expect(
      env.application.graph.conversation.existingSession('cold-child'),
      isNull,
    );
  });

  test('Driver distinguishes unopened and partial editors, undeclared/empty/unread options and deferred prefixes without reading during capture', () async {
    final env = await _environment(threads: [fixtureThread('thread-main')]);
    final native = DriverInteractionNative(
      env.application.domains.conversationPort,
    );
    addTearDown(native.releaseHeldResponses);
    final container = env.application.container;
    await _driverConversation(env);
    const first = DriverInteractionMaterial(
      entry: 1,
      id: 'first',
      targetThreadId: 'thread-main',
      kind: DriverInteractionMaterialKind.question,
      title: 'First',
      body: 'First exact body',
      optionsCount: null,
    );
    const second = DriverInteractionMaterial(
      entry: 2,
      id: 'second',
      targetThreadId: 'thread-main',
      kind: DriverInteractionMaterialKind.question,
      title: 'Second',
      body: 'Second exact body',
    );
    await native.publish(const [first, second]);
    await _driverConversation(env);
    final keys = container
        .read(conversationViewModelProvider('thread-main'))
        .requireValue
        .currentEditors;
    expect(keys, hasLength(2));
    expect(_passiveDriverCapture(env, native).interactionEditors, isNull);
    await _driverEditor(env, 'first');
    final partial = _passiveDriverCapture(env, native);
    expect(partial.conversation!.interactions!.current!.complete, isTrue);
    expect(partial.conversation!.currentEditors, hasLength(2));
    expect(partial.interactionEditors!.single.key.interactionId, 'first');
    final partialWorkspace = partial.toJson()['workspace'] as Map;
    expect(
      (partialWorkspace['activeInteractions'] as List).single,
      isA<Map>().having((value) => value['id'], 'mounted member', 'first'),
    );
    expect(
      partialWorkspace['activeInteraction'],
      isNull,
      reason:
          'One mounted member out of two is not a unique active interaction',
    );
    final secondKey = keys.singleWhere((key) => key.interactionId == 'second');
    expect(container.exists(interactionViewModelProvider(secondKey)), isFalse);
    final undeclared =
        (((partialWorkspace['activeInteractions'] as List).single['content']
                        as Map)['questions']
                    as List)
                .single
            as Map;
    expect(
      undeclared.keys,
      containsAll(['optionsCount', 'options', 'optionsComplete']),
    );
    expect(
      (
        undeclared['optionsCount'],
        undeclared['options'],
        undeclared['optionsComplete'],
      ),
      (null, null, null),
    );
    await _driverEditor(env, 'second');
    final both =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteractions']
            as List;
    final knownEmpty =
        ((both.cast<Map>().singleWhere(
                          (value) => value['id'] == 'second',
                        )['content']
                        as Map)['questions']
                    as List)
                .single
            as Map;
    expect(knownEmpty['optionsCount'], 0);
    expect(knownEmpty['options'], <Object?>[]);
    expect(knownEmpty['optionsComplete'], isTrue);
    expect(
      native.optionReads,
      isEmpty,
      reason: 'Undeclared and known-empty options do not require native option reads',
    );

    const exactBody =
        '# Deferred native body\n\nThe entire original material must be consumed before this is visible.';
    const exactLabel = 'Deferred exact label';
    const exactDescription = 'Deferred exact description';
    const chunked = DriverInteractionMaterial(
      entry: 3,
      id: 'chunked',
      targetThreadId: 'thread-main',
      kind: DriverInteractionMaterialKind.question,
      title: 'Deferred material',
      body: exactBody,
      deferredBody: true,
      optionsCount: 2,
      optionPageSize: 1,
      options: [
        OptionReadItem(
          index: 0,
          label: ReadText.deferred(fieldId: 43, utf8Bytes: 20),
          description: ReadText.inline(text: 'First native description'),
        ),
        OptionReadItem(
          index: 1,
          label: ReadText.inline(text: 'Second native label'),
          description: ReadText.deferred(fieldId: 44, utf8Bytes: 26),
        ),
      ],
      deferredTexts: {43: exactLabel, 44: exactDescription},
    );
    final firstOptions = native.holdOptions(chunked.reference);
    final secondOptions = native.holdOptions(chunked.reference, offset: 1);
    final bodyRemainder = native.holdText(chunked.reference, 42, offset: 8);
    final labelRemainder = native.holdText(chunked.reference, 43, offset: 8);
    final descriptionStart = native.holdText(chunked.reference, 44);
    await native.publish(const [chunked]);
    await _driverConversation(env);
    final chunkKey = await _driverEditor(env, 'chunked', complete: false);
    final reader = container.read(
      interactionViewModelProvider(chunkKey).notifier,
    );
    await firstOptions.entered.future;
    final unreadState = await _driverEditorState(
      env,
      chunkKey,
      (state) => state.questions[0]?.optionsLoading == true,
    );
    expect(unreadState.questions[0]!.options, isEmpty);
    expect(unreadState.questions[0]!.nextOptionOffset, 0);
    final unread =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    final unreadQuestion =
        ((unread['content'] as Map)['questions'] as List).single as Map;
    expect(unreadQuestion['optionsCount'], 2);
    expect(unreadQuestion['options'], <Object?>[]);
    expect(unreadQuestion['optionsComplete'], isFalse);

    firstOptions.release();
    await secondOptions.entered.future;
    final pageState = await _driverEditorState(
      env,
      chunkKey,
      (state) =>
          state.questions[0]?.options.length == 1 &&
          state.questions[0]!.optionsLoading,
    );
    expect(pageState.questions[0]!.nextOptionOffset, 1);
    final page =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    final pageQuestion =
        ((page['content'] as Map)['questions'] as List).single as Map;
    expect(pageQuestion['optionsCount'], 2);
    expect(pageQuestion['options'], [
      {'index': 0, 'label': null, 'description': 'First native description'},
    ]);
    expect(pageQuestion['optionsComplete'], isFalse);
    expect(
      native.textReads,
      isEmpty,
      reason: 'The original mount reader is still waiting on its second options page',
    );

    secondOptions.release();
    await bodyRemainder.entered.future;
    final bodyState = await _driverEditorState(
      env,
      chunkKey,
      (state) =>
          state.texts[42]?.loadedUtf8Bytes == 8 && state.texts[42]!.loading,
    );
    expect(bodyState.texts[42]!.complete, isFalse);
    expect(bodyState.questions[0]!.nextOptionOffset, isNull);
    expect(bodyState.questions[0]!.optionsLoading, isFalse);
    final incomplete =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    expect(incomplete['body'], isNull);
    final incompleteQuestion =
        ((incomplete['content'] as Map)['questions'] as List).single as Map;
    expect(incompleteQuestion['question'], isNull);
    expect(incompleteQuestion['options'], [
      {'index': 0, 'label': null, 'description': 'First native description'},
      {'index': 1, 'label': 'Second native label', 'description': null},
    ]);
    expect(
      incompleteQuestion['optionsComplete'],
      isFalse,
      reason: 'A complete options page is not complete deferred text',
    );
    final readsBefore = native.textReads.length;
    _passiveDriverCapture(env, native);
    expect(
      native.textReads,
      hasLength(readsBefore),
      reason: 'Driver cannot finish a deferred field',
    );

    bodyRemainder.release();
    await labelRemainder.entered.future;
    final labelState = await _driverEditorState(
      env,
      chunkKey,
      (state) =>
          state.texts[43]?.loadedUtf8Bytes == 8 && state.texts[43]!.loading,
    );
    expect(labelState.texts[43]!.text, 'Deferred');
    expect(labelState.texts[43]!.complete, isFalse);
    final labelPrefix =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    expect(labelPrefix['body'], exactBody);
    final prefixQuestion =
        ((labelPrefix['content'] as Map)['questions'] as List).single as Map;
    expect(prefixQuestion['options'], [
      {'index': 0, 'label': null, 'description': 'First native description'},
      {'index': 1, 'label': 'Second native label', 'description': null},
    ]);
    expect(prefixQuestion['optionsComplete'], isFalse);

    labelRemainder.release();
    await descriptionStart.entered.future;
    await _driverEditorState(
      env,
      chunkKey,
      (state) =>
          state.texts[43]?.complete == true && state.texts[44]?.loading == true,
    );
    final descriptionPending =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    final pendingQuestion =
        ((descriptionPending['content'] as Map)['questions'] as List).single
            as Map;
    expect(pendingQuestion['options'], [
      {
        'index': 0,
        'label': exactLabel,
        'description': 'First native description',
      },
      {'index': 1, 'label': 'Second native label', 'description': null},
    ]);
    expect(
      pendingQuestion['optionsComplete'],
      isFalse,
      reason: 'Both labels alone are not complete option material',
    );

    descriptionStart.release();
    await _driverEditorState(
      env,
      chunkKey,
      (state) =>
          state.texts[42]?.complete == true &&
          state.texts[43]?.complete == true &&
          state.texts[44]?.complete == true &&
          !state.texts[44]!.loading,
    );
    await reader.completeRead();
    final complete =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    expect(complete['body'], exactBody);
    final completeQuestion =
        ((complete['content'] as Map)['questions'] as List).single as Map;
    expect(completeQuestion['question'], exactBody);
    expect(completeQuestion['optionsCount'], 2);
    expect(completeQuestion['options'], [
      {
        'index': 0,
        'label': exactLabel,
        'description': 'First native description',
      },
      {
        'index': 1,
        'label': 'Second native label',
        'description': exactDescription,
      },
    ]);
    expect(completeQuestion['optionsComplete'], isTrue);
    expect(native.optionReads, [
      (
        host: 'thread-main',
        reference: chunked.reference,
        questionIndex: 0,
        offset: 0,
        limit: 32,
      ),
      (
        host: 'thread-main',
        reference: chunked.reference,
        questionIndex: 0,
        offset: 1,
        limit: 32,
      ),
    ]);
    expect(native.textReads.length, greaterThan(readsBefore));
    await native.publish(const []);
    await _driverConversation(env);
    final empty = _passiveDriverCapture(env, native);
    expect(empty.conversation!.interactions!.current!.complete, isTrue);
    expect(empty.conversation!.currentEditors, isEmpty);
    expect(empty.interactionEditors, isEmpty);
    expect((empty.toJson()['workspace'] as Map)['activeInteractions'], isEmpty);
    expect((empty.toJson()['workspace'] as Map)['activeInteraction'], isNull);
    await env.close();
    expect(native.pins, isNotEmpty);
    expect(
      native.pins.every((pin) => pin.closed),
      isTrue,
      reason: 'Application close joins every original native read owner',
    );
  });

  test('Driver options stay incomplete for a deferred label alone after pages and descriptions complete', () async {
    final env = await _environment(threads: [fixtureThread('thread-main')]);
    final native = DriverInteractionNative(
      env.application.domains.conversationPort,
    );
    addTearDown(native.releaseHeldResponses);
    await _driverConversation(env);
    const exactBody = 'Inline body with complete option description.';
    const exactLabel = 'Deferred exact label';
    const exactDescription = 'The entire description is already available.';
    const material = DriverInteractionMaterial(
      entry: 1,
      id: 'label-only',
      targetThreadId: 'thread-main',
      kind: DriverInteractionMaterialKind.question,
      title: 'Label-only read',
      body: exactBody,
      optionsCount: 1,
      options: [
        OptionReadItem(
          index: 0,
          label: ReadText.deferred(fieldId: 43, utf8Bytes: 20),
          description: ReadText.inline(text: exactDescription),
        ),
      ],
      deferredTexts: {43: exactLabel},
    );
    final labelRemainder = native.holdText(material.reference, 43, offset: 8);
    await native.publish(const [material]);
    await _driverConversation(env);
    final key = await _driverEditor(env, 'label-only', complete: false);
    await labelRemainder.entered.future;
    final pending = await _driverEditorState(
      env,
      key,
      (state) =>
          state.sourceCurrent &&
          state.texts[43]?.loadedUtf8Bytes == 8 &&
          state.texts[43]!.loading,
    );
    final question = pending.questions[0]!;
    expect(pending.readIssues, isEmpty);
    expect(pending.questionPageLoading, isFalse);
    expect(pending.nextQuestionOffset, isNull);
    expect(question.question.optionsCount, 1);
    expect(question.options.map((option) => option.index), [0]);
    expect(question.optionsLoading, isFalse);
    expect(question.optionsError, isNull);
    expect(question.nextOptionOffset, isNull);
    expect(
      pending.texts.keys.toList(),
      [43],
      reason: 'Only the label is deferred; body, description and identity texts are inline',
    );
    expect(pending.texts[43]!.text, 'Deferred');
    expect(pending.texts[43]!.complete, isFalse);
    expect(pending.texts[43]!.error, isNull);
    expect(native.optionReads.single, (
      host: 'thread-main',
      reference: material.reference,
      questionIndex: 0,
      offset: 0,
      limit: 32,
    ));
    expect(native.textReads.map((call) => (call.field, call.offset)), [
      (43, 0),
      (43, 8),
    ]);
    final incomplete =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    expect(incomplete['body'], exactBody);
    expect(((incomplete['content'] as Map)['questions'] as List).single, {
      'index': 0,
      'id': 'q',
      'header': 'Label-only read',
      'question': exactBody,
      'isOther': true,
      'isSecret': false,
      'optionsCount': 1,
      'options': [
        {'index': 0, 'label': null, 'description': exactDescription},
      ],
      'optionsComplete': false,
    });

    final openedReads = native.reads.length;
    labelRemainder.release();
    final ready = await _driverEditorState(
      env,
      key,
      (state) => state.texts[43]?.complete == true && !state.texts[43]!.loading,
    );
    expect(
      ready.scope,
      pending.scope,
      reason: 'The same original reader completes the label',
    );
    expect(native.reads, hasLength(openedReads));
    final complete =
        (_passiveDriverCapture(env, native).toJson()['workspace']
                as Map)['activeInteraction']
            as Map;
    expect(complete['body'], exactBody);
    final completeQuestion =
        ((complete['content'] as Map)['questions'] as List).single as Map;
    expect(completeQuestion['options'], [
      {'index': 0, 'label': exactLabel, 'description': exactDescription},
    ]);
    expect(completeQuestion['optionsComplete'], isTrue);
    await env.close();
    expect(native.pins, isNotEmpty);
    expect(
      native.pins.every((pin) => pin.closed),
      isTrue,
      reason: 'Application close joins the original label read owner',
    );
  });

  test('Driver keeps Recovery actions/unknown inspection and cold preparing directory facts without opening the child', () async {
    final root = fixtureThread('thread-main');
    final child = fixtureThread(
      'cold-child',
      parentThreadId: root.id,
      role: 'reviewer',
    );
    const issue = RecoveryIssueRead(
      id: ReadText.inline(text: 'worktree-driver'),
      scope: RecoveryScope.thread,
      category: RecoveryCategory.repository,
      availableActions: [RecoveryAction.retry, RecoveryAction.cleanupWorktree],
      projectId: ReadText.inline(text: 'project'),
      threadId: ReadText.inline(text: 'unselected-thread'),
      message: ReadText.inline(text: 'Original inspection unavailable'),
      worktree: WorktreeRecoveryPreviewRead(
        inspection: WorktreeInspection.unavailable,
        ownerKind: WorktreeOwner.child,
        ownerThreadId: ReadText.inline(text: 'cold-child'),
        leaseRevision: 23,
        state: ReadText.inline(text: 'preserved'),
        repositoryRoot: ReadText.inline(text: '/repo'),
        path: ReadText.inline(text: '/repo/.anywork/cold-child/session'),
        branch: ReadText.inline(text: 'preserved-branch'),
        baseCommit: ReadText.inline(text: 'base-commit'),
        headCommit: null,
        dirty: null,
        changedFiles: null,
      ),
    );
    final env = await _environment(
      threads: [root],
      agents: [
        SelectorDirectoryPort.agentEntry(root),
        SelectorDirectoryPort.agentEntry(child).copyWith(
          execution: const AgentExecution(
            id: 'cold-preparing',
            phase: AgentExecutionPhase.preparing,
            turnId: null,
          ),
          canStop: true,
          awaitingScheduling: true,
        ),
      ],
      recoveryIssues: const [issue],
    );
    await env.mountDirectory();
    await env.openContent(
      baseline(1, items: const []),
      threadId: 'thread-main',
    );
    await env.application.domains.conversationPort.publishExecution(
      selectorExecution(status: ThreadStatus.waitingInteraction),
    );
    final nativeBefore = env.nativeActivity;
    final permits = List.of(env.application.graph.budget.usage);
    final captured = DriverInspection(
      graph: env.application.graph,
      container: env.application.container,
    ).capture();
    final json = captured.toJson();
    final recovery = (json['recoveryIssues'] as List).single as Map;
    expect(recovery['availableActions'], ['retry', 'cleanupWorktree']);
    expect(recovery.containsKey('actions'), isFalse);
    expect(recovery['worktree'], {
      'inspection': 'unavailable',
      'ownerKind': 'child',
      'ownerThreadId': 'cold-child',
      'leaseRevision': 23,
      'state': 'preserved',
      'repositoryRoot': '/repo',
      'path': '/repo/.anywork/cold-child/session',
      'branch': 'preserved-branch',
      'baseCommit': 'base-commit',
      'headCommit': null,
      'dirty': null,
      'changedFiles': null,
    });
    final workspace = json['workspace'] as Map;
    expect(
      workspace['isBusy'],
      isFalse,
      reason: 'Ready waitingInteraction without execution is not busy',
    );
    final cold = (workspace['agents'] as List).cast<Map>().singleWhere(
      (row) => row['threadId'] == 'cold-child',
    );
    expect(cold['execution'], {
      'id': 'cold-preparing',
      'phase': 'preparing',
      'turnId': null,
    });
    expect((cold['canStop'], cold['awaitingScheduling']), (true, true));
    expect(
      env.application.graph.conversation.existingSession('cold-child'),
      isNull,
    );
    expect(env.nativeActivity, nativeBefore);
    expect(env.application.graph.budget.usage, permits);
  });

  test('Driver statistics JSON exposes the true paired identity/references; releasing the request does not close another visible demand', () async {
    const origin = ProductReadOrigin(
      ownerEpoch: 'driver-paired-statistics',
      incarnation: 5,
    );
    const summaries = PerformanceSummariesReadRef(entry: 71, revision: 61);
    const history = PerformanceHistoryReadRef(entry: 81, revision: 73);
    const summaryCollection = ProductCollectionRef(
      entry: 91,
      revision: 61,
      total: 0,
    );
    const historyCollection = ProductCollectionRef(
      entry: 92,
      revision: 73,
      total: 0,
    );
    final native = ScriptedStatisticsPort(
      origin: origin,
      summariesFeedId: 'real-summary-feed',
      historyFeedId: 'real-history-feed',
      summaryScripts: {
        summaries: SummariesMaterialScript(
          collection: summaryCollection,
          entries: const [],
          entities: const {},
        ),
      },
      historyScripts: {
        history: HistoryMaterialScript(
          collection: historyCollection,
          entries: const [],
          entities: const {},
        ),
      },
    );
    final env = DriverTestEnvironment(statisticsPort: native);
    addTearDown(env.close);
    await env.establish(threads: [fixtureThread('thread-main')]);
    final repository = env.application.graph.statistics;
    final pageDemand = repository.acquireVisibleDemand();
    var pageReleased = false;
    addTearDown(() {
      if (!pageReleased) pageDemand.release();
    });
    final output = DriverProductRequests(env.application.graph).statistics();
    final summaryFeed = await native.summariesAt(1);
    final historyFeed = await native.historyAt(1);
    await Future.wait([
      summaryFeed.listened.future,
      historyFeed.listened.future,
    ]);
    summaryFeed.emit(
      summariesBaseline(
        feedId: 'real-summary-feed',
        origin: origin,
        revision: 19,
        reference: summaries,
        collection: summaryCollection,
      ),
    );
    historyFeed.emit(
      historyBaseline(
        feedId: 'real-history-feed',
        origin: origin,
        revision: 19,
        reference: history,
        collection: historyCollection,
      ),
    );
    await Future.wait([
      summaryFeed.acknowledged(1),
      historyFeed.acknowledged(1),
    ]);
    final json = jsonDecode(await output) as Map;
    expect(
      (json['ownerEpoch'], json['incarnation'], json['revision']),
      ('driver-paired-statistics', 5, 19),
    );
    expect(json['summariesReference'], {'entry': 71, 'revision': 61});
    expect(json['historyReference'], {'entry': 81, 'revision': 73});
    for (final key in ['feedId', 'summariesRevision', 'historyRevision']) {
      expect(
        json.containsKey(key),
        isFalse,
        reason: 'No invented legacy identity placeholder: $key',
      );
    }
    expect(json['loaded'], isTrue);
    expect(json['summaries'], isEmpty);
    expect(json['history'], isEmpty);
    expect(summaryFeed.closeCalls, 0);
    expect(historyFeed.closeCalls, 0);
    expect(repository.state.value.snapshot, isNotNull);
    expect(repository.state.value.sync.phase, ResourceSyncPhase.ready);
    pageReleased = true;
    pageDemand.release();
    await env.close();
    expect(summaryFeed.closeCalls, 1);
    expect(historyFeed.closeCalls, 1);
  });

  // ACP 认证/安装事实的 Driver 覆盖：
  //
  // `DriverSnapshot.acpAuth`/`acpInstall` 是 `graph.acpAuth`/`graph.acpInstall`
  // canonical 镜像的可空读取入口（未加载即 null），`settingsDiagnostic` 发布
  // `acpAuthLoaded` 与 `acpInstall{loaded, revision, installations[...]}`，失败类别
  // 由 typed 枚举静态解析。下面两组断言锁定安装失败终态与关闭中的 cancelled 失败，
  // 并核对“投影只读现有镜像、不建立业务 demand”。

  test('canonical cold and closed members survive a root-only Thread page and cold selection', () async {
    final root = _factsThread();
    final other = root.copyWith(
      id: 'other-root',
      rootThreadId: 'other-root',
      projectId: 'foreign-project',
      title: 'Other project',
      workspacePath: '/other',
    );
    AgentDirectoryEntry agent(
      String id, {
      required String rootId,
      String? parent,
      AgentState state = const AgentState.idle(budgetPause: null),
      int depth = 0,
    }) => AgentDirectoryEntry(
      id: id,
      threadId: id,
      path: 'path-$id',
      parentPath: parent,
      rootThreadId: rootId,
      depth: depth,
      role: parent == null ? 'planner' : 'reviewer',
      task: 'Task $id',
      summary: null,
      state: state,
      updatedAt: root.updatedAt,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.economy,
      frozenModel: parent == null
          ? null
          : const ModelSelection(
              model: AccountModelKey(
                accountId: 'saved-account',
                modelId: 'saved-model',
              ),
              effort: 'high',
            ),
    );
    final members = [
      agent(root.id, rootId: root.id),
      agent(
        'cold-executor',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.running(turnId: 'executor-turn'),
      ),
      agent(
        'cold-closed',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.closed(),
      ),
      // The new native directory supplies the canonical root explicitly, while
      // preserving the exact opaque parent link and the original expected order.
      agent(
        'nested',
        rootId: root.id,
        parent: 'path-cold-closed',
        depth: 2,
        state: const AgentState.running(turnId: 'nested-turn'),
      ),
      agent(
        'faulted',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.faulted(
          error: SourceStateError(
            code: 'saved-failure',
            message: 'Saved failure',
            retryable: false,
          ),
          turnId: null,
          classification: AgentFaultClassification.legacyUnknown,
        ),
      ),
      // Waiting for the SDK fix: this duplicate remains in the native input and
      // the old unique-member expectations below are not weakened or skipped.
      agent(
        'cold-closed',
        rootId: root.id,
        parent: 'path-${root.id}',
        depth: 1,
        state: const AgentState.closed(),
      ),
      agent(other.id, rootId: other.id),
      agent(
        'other-child',
        rootId: other.id,
        parent: 'path-${other.id}',
        depth: 1,
      ),
    ];
    final env = await _environment(threads: [root, other], agents: members);
    final graph = env.application.graph;
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: root.projectId,
        threadId: root.id,
        needsOpen: true,
      ),
    );
    await env.mountDirectory();
    final before = env.nativeActivity;
    final facts = env.capture();
    expect(
      facts.agents?.map((a) => a.threadId),
      [root.id, 'cold-executor', 'cold-closed', 'nested', 'faulted'],
      reason: 'Waiting for SDK duplicate-member recovery; do not report Unknown as a successful empty directory',
    );
    expect(
      facts.directory!.where((t) => t.rootThreadId == root.id).map((t) => t.id),
      [root.id],
      reason: 'Member enumeration never fabricates missing Thread metadata',
    );
    expect(facts.agents!.first.frozenModel, isNull);
    expect(facts.agents![1].frozenModel?.model.modelId, 'saved-model');
    expect(
      AgentDirectoryQueries.menuOrder(facts.agents!).map((a) => a.threadId),
      ['cold-executor', 'nested', 'faulted', root.id, 'cold-closed'],
      reason: 'Status grouping keeps stable canonical order inside each group',
    );
    expect(env.capture().agents!.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ]);
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: root.projectId,
        threadId: 'cold-closed',
        needsOpen: true,
      ),
    );
    final cold = env.capture();
    expect(
      cold.directory!.where((t) => t.id == cold.rootThreadId).single.id,
      root.id,
      reason: 'Typed agent root identity is sufficient even before child Thread metadata arrives',
    );
    expect(cold.selection.threadId, 'cold-closed');
    expect(
      AgentDirectoryQueries.rootThreadId(
        threadId: cold.selection.threadId,
        directory: graph.workspace.agents.value,
      ),
      root.id,
    );
    expect(cold.agents!.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ]);
    expect(env.knownSessions, isEmpty);
    expect(
      env.nativeActivity,
      before,
      reason:
          'Enumeration and cold navigation restore cannot load child sessions',
    );
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: other.projectId,
        threadId: other.id,
        needsOpen: true,
      ),
    );
    expect(env.capture().agents!.map((a) => a.threadId), [
      other.id,
      'other-child',
    ]);
    graph.workspace.restoreSelection(
      WorkspaceSelection(
        projectId: root.projectId,
        threadId: 'cold-closed',
        needsOpen: true,
      ),
    );
    await env.removeDirectoryThread(root.id);
    final removed = env.capture();
    expect(removed.directory!.where((t) => t.id == root.id), isEmpty);
    expect(removed.directory!.where((t) => t.rootThreadId == root.id), isEmpty);
    expect(removed.agents!.map((a) => a.threadId), [
      root.id,
      'cold-executor',
      'cold-closed',
      'nested',
      'faulted',
    ], reason: 'Even root metadata availability is not a membership condition');
    expect(removed.rootThreadId, root.id);
    expect(env.knownSessions, isEmpty);
    expect(env.nativeActivity, before);
  });

  test(
    'canonical saved agent routes retain selection without activating children',
    () async {
      const frozen = ModelSelection(
        model: AccountModelKey(accountId: 'account-b', modelId: 'shared'),
        effort: 'high',
      );
      final root = _factsThread();
      final child =
          fixtureThread(
            'child',
            parentThreadId: root.id,
            role: 'reviewer',
          ).copyWith(
            title: 'Review final changes',
            mode: ThreadModeId.task,
            delegationMode: DelegationMode.automatic,
            delegationPreference: DelegationPreference.economy,
            frozenModel: frozen,
            workspacePath: '/project',
          );
      final savedRoot = SelectorDirectoryPort.agentEntry(root);
      AgentDirectoryEntry saved(AgentState state) =>
          SelectorDirectoryPort.agentEntry(
            child,
          ).copyWith(path: child.id, parentPath: root.agentPath, state: state);
      final env = await _environment(
        threads: [root, child],
        agents: [savedRoot, saved(const AgentState.idle(budgetPause: null))],
      );
      final graph = env.application.graph;
      graph.workspace.restoreSelection(
        WorkspaceSelection(
          projectId: root.projectId,
          threadId: child.id,
          needsOpen: true,
        ),
      );
      final before = env.nativeActivity;
      final facts = env.capture();
      expect(
        facts.agents!.where((a) => a.threadId == child.id).single.frozenModel,
        frozen,
      );
      expect(graph.conversation.existingSession(child.id), isNull);
      final cold = AgentDirectoryQueries.forRoot(
        rootThreadId: root.id,
        directory: graph.workspace.agents.value,
      ).where((a) => a.threadId == child.id).single;
      await env.application.domains.directory.publishAgents([
        savedRoot,
        saved(const AgentState.running(turnId: 'turn')),
      ]);
      await env.waitAgents();
      expect(
        AgentDirectoryQueries.forRoot(
          rootThreadId: root.id,
          directory: graph.workspace.agents.value,
        ).where((a) => a.threadId == child.id).single.frozenModel,
        frozen,
      );
      await env.application.domains.directory.publishAgents([
        savedRoot,
        saved(const AgentState.closed()),
      ]);
      await env.waitAgents();
      final closed = AgentDirectoryQueries.forRoot(
        rootThreadId: root.id,
        directory: graph.workspace.agents.value,
      ).where((a) => a.threadId == child.id).single;
      expect(cold.frozenModel, frozen);
      expect(closed.frozenModel, frozen);
      expect(closed.delegationPreference, DelegationPreference.economy);
      expect(graph.workspace.state.value.selection.threadId, child.id);
      expect(
        env.nativeActivity,
        before,
        reason: 'Fallback/Driver reads cannot fetch or activate a cold child',
      );
      expect(
        AgentDirectoryQueries.forRoot(
          rootThreadId: root.id,
          directory: graph.workspace.agents.value,
        ).first.frozenModel,
        isNull,
        reason: 'No saved model remains genuinely unknown, never filled from a current Profile',
      );
    },
  );

  test(
    'workspace and Driver join current directory identity after a Turn',
    () async {
      final thread = _factsThread().copyWith(
        id: 'thread-main',
        rootThreadId: 'thread-main',
      );
      final env = await _environment(threads: [thread]);
      final domains = env.application.domains;
      final graph = env.application.graph;
      domains.conversationPort.initialStatus = ThreadStatus.running;
      await env.openContent(
        baseline(1, items: [timelineItem(1, threadId: thread.id)]),
        threadId: thread.id,
      );
      await env.mountDirectory();
      final container = env.application.container;
      final conversation = container.listen(
        conversationViewModelProvider(thread.id),
        (_, _) {},
      );
      final status = container.listen(
        threadStatusViewModelProvider(thread.id),
        (_, _) {},
      );
      addTearDown(conversation.close);
      addTearDown(status.close);
      await container.read(conversationViewModelProvider(thread.id).future);
      await container.read(threadStatusViewModelProvider(thread.id).future);
      final canonical = thread.copyWith(
        title: 'Completed canonical title',
        mode: ThreadModeId.task,
        status: ThreadStatus.idle,
        updatedAt: thread.updatedAt,
      );
      await domains.directory.publishThread(canonical);
      await env.waitDirectory(
        (facts) =>
            facts.thread?.title == canonical.title &&
            facts.thread?.mode == canonical.mode &&
            facts.conversation?.thread == canonical,
      );
      await domains.conversationPort.publishExecution(
        selectorExecution(status: ThreadStatus.running),
      );
      final workspaceRead =
          (container
                      .read(workspaceViewModelProvider)
                      .requireValue
                      .selectedMetadata!
                      .value!
                  as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
              .current;
      final conversationRead =
          (conversation.read().requireValue.metadata!.value!
                  as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
              .current;
      final current = workspaceRead.value;
      expect(
        current,
        canonical,
        reason: 'The canonical immutable native read has all original values',
      );
      expect(
        (
          conversationRead.origin,
          conversationRead.reference,
          conversationRead.value,
        ),
        (workspaceRead.origin, workspaceRead.reference, workspaceRead.value),
        reason: 'Independent metadata borrows retain the same current source, entity revision and full value',
      );
      final facts = env.capture();
      final json = jsonDecode(env.snapshotJson()) as Map;
      expect((json['workspace'] as Map)['threadStatus'], 'idle');
      expect(facts.display.timeline, isNotNull);
      expect(facts.display.timeline!.threadId, 'thread-main');
      expect(
        (json['timeline'] as Map)['itemCount'],
        facts.display.timeline!.items.length,
      );
      expect(facts.display.timeline!.ready, isTrue);
      expect(facts.display.timelineScroll, isNotNull);
      expect(facts.display.timelineScroll!.threadId, 'thread-main');
      expect(
        facts.display.timelineScroll!.generation,
        facts.display.timeline!.generation,
      );
      expect(facts.display.timelineScroll!.pixels, isNull);
      expect(facts.display.timelineScroll!.maxScrollExtent, isNull);
      expect(facts.display.timelineScroll!.atLiveEdge, isFalse);
      expect(facts.display.timelineScroll!.isScrolling, isFalse);
      expect((json['timelineScroll'] as Map)['isScrolling'], isFalse);
      final generation = facts.display.timeline!.generation;
      final returning = graph.timeline.returnLive(thread.id);
      final replacement = await domains.timeline.opened(1);
      replacement.result.complete(
        TestTimelineConnection(
          initial: baseline(
            2,
            subscriptionId: 'replacement',
            items: [timelineItem(2, threadId: thread.id)],
          ),
        ),
      );
      await returning;
      final switched = env.capture();
      expect(switched.display.timeline!.generation, greaterThan(generation));
      expect(switched.display.timeline!.threadId, 'thread-main');
      expect(switched.display.timelineScroll, isNotNull);
      expect(
        switched.display.timelineScroll!.generation,
        switched.display.timeline!.generation,
      );
      expect(switched.display.timelineScroll!.threadId, 'thread-main');
      expect(facts.thread, same(current));
      expect(
        (container
                    .read(workspaceViewModelProvider)
                    .requireValue
                    .selectedMetadata!
                    .value!
                as ReadyReadValue<WorkspaceThreadRecord, ProductEntityRef>)
            .current
            .value,
        same(current),
      );
      expect(
        container
            .read(threadStatusViewModelProvider(thread.id).notifier)
            .modelRouteProps(conversation.read().requireValue.metadata)
            .thread,
        same(conversationRead.value),
      );
      // ConversationInputConnector now owns metadata; ComposerVM intentionally
      // owns only its Draft. Its actual ConversationVM input must use this same
      // current metadata rather than an execution snapshot's stale Thread copy.
      expect(
        conversation.read().requireValue.thread,
        same(conversationRead.value),
      );
    },
  );

  test(
    'Driver reads current Client facts without creating any owner or lease',
    () async {
      final thread = _factsThread().copyWith(title: 'Original title');
      final env = await _environment(threads: [thread]);
      final graph = env.application.graph;
      graph.workspace.restoreSelection(
        const WorkspaceSelection(
          projectId: 'project',
          threadId: 'thread',
          needsOpen: true,
        ),
      );
      await env.mountDirectory();
      await pumpEventQueue();
      final usageBefore = graph.budget.usage.length;
      final nativeBefore = env.nativeActivity;
      final original = env.capture();
      expect(original.directory!.single.title, 'Original title');
      expect(original.display.timeline, isNull);
      expect(
        original.display.timelineScroll,
        isNull,
        reason: '没有展示 lease 就没有几何，也不回放上一代',
      );
      expect(graph.timeline.display('thread'), isNull);
      expect(env.knownSessions, isEmpty);
      expect(
        graph.budget.usage.where((usage) => usage.kind == ResourceKind.draft),
        isEmpty,
      );
      expect(env.application.skillsPort.openedProjects, isEmpty);
      expect(
        graph.budget.usage.where(
          (usage) => usage.owner.contains('session-cost'),
        ),
        isEmpty,
      );
      expect(env.nativeActivity, nativeBefore);
      await env.application.domains.directory.publishThread(
        thread.copyWith(title: 'Updated canonical title'),
      );
      await env.waitDirectory(
        (facts) =>
            facts.directory?.singleOrNull?.title == 'Updated canonical title',
      );
      await pumpEventQueue();
      final currentNativeBefore = env.nativeActivity;
      final current = env.capture();
      expect(current.directory!.single.title, 'Updated canonical title');
      expect(original.directory!.single.title, 'Original title');
      expect(() => current.directory!.add(thread), throwsUnsupportedError);
      final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
      expect(json.containsKey('timelineScroll'), isTrue);
      expect(json['timelineScroll'], isNull);
      final directory = json['sidebarDirectory'] as Map<String, dynamic>;
      expect(directory['titles'], {'thread': 'Updated canonical title'});
      env.capture();
      expect(env.knownSessions, isEmpty);
      expect(
        graph.budget.usage.where((usage) => usage.kind == ResourceKind.draft),
        isEmpty,
      );
      expect(graph.budget.usage.length, usageBefore);
      expect(
        env.nativeActivity,
        currentNativeBefore,
        reason: 'snapshot queries never create transport demand',
      );
      await env.close();
      expect(graph.budget.usage, isEmpty);
    },
  );

  test('timeline facts expose authoritative text channel and plan-confirmation bool', () async {
    final env = await _environment();
    await env.openContent(_factsBaseline());
    final timeline = env.application.graph.timeline;
    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
    final items = (json['timeline'] as Map<String, dynamic>)['items'] as List;
    Map<String, dynamic> itemOf(String id) => items
        .cast<Map<String, dynamic>>()
        .firstWhere((item) => item['id'] == id);
    Map<String, dynamic>? userInputOf(String id) =>
        itemOf(id)['userInput'] as Map<String, dynamic>?;

    // 文本频道是权威判别事实：commentary 与 finalAnswer 不混，非文本为 null。
    expect(itemOf('cm')['channel'], 'commentary');
    expect(itemOf('fa')['channel'], 'finalAnswer');
    expect(itemOf('cm')['channel'], isNot(itemOf('fa')['channel']));
    expect(itemOf('tool')['channel'], isNull);
    // 两个文本条目的 kind 相同也必须靠 channel 区分，不能从 kind/文本推测。
    expect(itemOf('cm')['kind'], itemOf('fa')['kind']);

    // 普通问答：false + 无决定。
    expect(userInputOf('qa-normal')!['isPlanConfirmation'], isFalse);
    expect(userInputOf('qa-normal')!['planDecision'], isNull);
    // 待确认的计划同样是计划确认，且决定来自权威 getter。
    expect(userInputOf('qa-plan-pending')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-pending')!['planDecision'], 'pending');
    // cancelled / approved 按权威 getter 直出。
    expect(userInputOf('qa-plan-cancelled')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-cancelled')!['planDecision'], 'cancelled');
    expect(userInputOf('qa-plan-approved')!['isPlanConfirmation'], isTrue);
    expect(userInputOf('qa-plan-approved')!['planDecision'], 'approved');
    // 旧普通问答复用保留 ID：归属只看工具名，仍是普通问答。
    expect(userInputOf('qa-plan-legacy')!['isPlanConfirmation'], isFalse);
    expect(userInputOf('qa-plan-legacy')!['planDecision'], isNull);
    // 每个问答条目都始终输出该键（固定 schema）。
    for (final id in const [
      'qa-normal',
      'qa-plan-pending',
      'qa-plan-cancelled',
      'qa-plan-approved',
      'qa-plan-legacy',
    ]) {
      expect(userInputOf(id)!.containsKey('isPlanConfirmation'), isTrue);
      expect(userInputOf(id)!.containsKey('planDecision'), isTrue);
    }

    await timeline.close(
      deadline: DateTime.now().add(const Duration(seconds: 5)),
    );
  });

  test(
    'attachment facts keep canonical modality for user and tool items',
    () async {
      final env = await _environment();
      await env.openContent(_attachmentBaseline());
      final timeline = env.application.graph.timeline;
      final opensBefore = env.application.domains.timeline.requests.length;
      final facts = env.capture();
      expect(facts.display.timeline, isNotNull);
      final items = facts.display.timeline!.items;
      TimelineItemFacts itemOf(String id) =>
          items.firstWhere((item) => item.id == id);

      // 用户文本条目的附件：canonical enum 名、真实文件名与字节数，且不冒充工具产出。
      final userItem = itemOf('user');
      expect(userItem.tool, isNull);
      expect(userItem.attachments.map((attachment) => attachment.id), [
        'user-image',
        'user-file',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.modality), [
        'image',
        'file',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.filename), [
        'chart.png',
        'notes.txt',
      ]);
      expect(userItem.attachments.map((attachment) => attachment.byteSize), [
        2048,
        15,
      ]);
      expect(userItem.attachments.map((attachment) => attachment.source), [
        null,
        null,
      ]);

      // 工具条目的顶层附件行带工具来源标记；nested 工具诊断给同一批附件的原始事实。
      final toolItem = itemOf('tool-output');
      expect(toolItem.attachments.map((attachment) => attachment.id), [
        'tool-image',
        'tool-video',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.modality), [
        'image',
        'video',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.filename), [
        'shot.png',
        'clip.mp4',
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.byteSize), [
        4096,
        8192,
      ]);
      expect(toolItem.attachments.map((attachment) => attachment.source), [
        'tool',
        'tool',
      ]);
      final tool = toolItem.tool!;
      expect(tool.name, 'bash');
      expect(tool.attachments.map((attachment) => attachment.id), [
        'tool-image',
        'tool-video',
      ]);
      expect(tool.attachments.map((attachment) => attachment.modality), [
        'image',
        'video',
      ]);
      expect(tool.attachments.map((attachment) => attachment.filename), [
        'shot.png',
        'clip.mp4',
      ]);
      expect(tool.attachments.map((attachment) => attachment.byteSize), [
        4096,
        8192,
      ]);
      expect(tool.attachments.map((attachment) => attachment.source), [
        null,
        null,
      ]);
      // 用户与工具附件身份不串：两侧 id 无交集。
      expect(
        toolItem.attachments
            .map((attachment) => attachment.id)
            .toSet()
            .intersection(
              userItem.attachments.map((attachment) => attachment.id).toSet(),
            ),
        isEmpty,
      );

      // 序列化诊断给同一批 canonical 值，键名保持不变。
      final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
      final jsonItems =
          ((json['timeline'] as Map<String, dynamic>)['items'] as List)
              .cast<Map<String, dynamic>>();
      Map<String, dynamic> jsonItemOf(String id) =>
          jsonItems.firstWhere((item) => item['id'] == id);
      expect(jsonItemOf('user')['attachments'], [
        {
          'id': 'user-image',
          'modality': 'image',
          'filename': 'chart.png',
          'byteSize': 2048,
        },
        {
          'id': 'user-file',
          'modality': 'file',
          'filename': 'notes.txt',
          'byteSize': 15,
        },
      ]);
      final jsonTool =
          jsonItemOf('tool-output')['tool'] as Map<String, dynamic>;
      expect(jsonItemOf('tool-output')['attachments'], [
        {
          'id': 'tool-image',
          'modality': 'image',
          'filename': 'shot.png',
          'byteSize': 4096,
          'source': 'tool',
        },
        {
          'id': 'tool-video',
          'modality': 'video',
          'filename': 'clip.mp4',
          'byteSize': 8192,
          'source': 'tool',
        },
      ]);
      expect(jsonTool['attachments'], [
        {
          'id': 'tool-image',
          'modality': 'image',
          'filename': 'shot.png',
          'byteSize': 4096,
        },
        {
          'id': 'tool-video',
          'modality': 'video',
          'filename': 'clip.mp4',
          'byteSize': 8192,
        },
      ]);
      final history =
          ((json['workspace'] as Map<String, dynamic>)['historyAttachments']
                  as List)
              .cast<Map<String, dynamic>>();
      expect(history.map((attachment) => attachment['id']), [
        'user-image',
        'user-file',
        'tool-image',
        'tool-video',
      ]);
      // 读诊断不制造新的内容订阅或 transport demand。
      expect(env.application.domains.timeline.requests.length, opensBefore);

      // 释放展示后诊断读不到上一代附件。
      await timeline.close(
        deadline: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(timeline.display('thread'), isNull);
      final retired = env.capture();
      expect(retired.display.timeline, isNull);
      final retiredJson =
          jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
      expect(retiredJson['timeline'], isNull);
      expect(
        ((retiredJson['workspace']
                    as Map<String, dynamic>)['historyAttachments']
                as List)
            .isEmpty,
        isTrue,
      );
      expect(env.application.domains.timeline.requests.length, opensBefore);
    },
  );

  test(
    'workspace 模型诊断按已解析 route 的 accountId 与 modelId 选账号，不按裸 model id 猜',
    () async {
      final env = await _environment();
      final base = env.capture();
      Map<String, dynamic> workspaceJsonFor(ModelRouteReadValue? route) =>
          jsonDecode(
                jsonEncode(_identitySnapshot(base, route).toJson()),
              )['workspace']
              as Map<String, dynamic>;

      // 两个账号共用同一 modelId；只有 route 能说明当前模型属于哪个账号。
      final routed = workspaceJsonFor(_sharedModelRoute(accountId: 'acct-b'));
      expect(routed['modelAccount'], {
        'id': 'acct-b',
        'hasBearerToken': true,
        'credentialEnv': 'ACCT_B_KEY',
      });
      expect(routed['modelCapabilities'], ['text', 'image']);

      // 路由暂不可用仍保留身份：可用性不是身份选择依据。
      final unavailable = workspaceJsonFor(
        _sharedModelRoute(accountId: 'acct-b', available: false),
      );
      expect(
        (unavailable['modelAccount'] as Map<String, dynamic>)['id'],
        'acct-b',
      );
      expect(unavailable['modelCapabilities'], ['text', 'image']);

      // 路由缺失：保持 unknown，不按裸 model id 猜任意账号。
      final unrouted = workspaceJsonFor(null);
      expect(unrouted['modelAccount'], isNull);
      expect(unrouted['modelCapabilities'], isEmpty);

      // 未知账号：保持 unknown。
      final unknownAccount = workspaceJsonFor(
        _sharedModelRoute(accountId: 'acct-missing'),
      );
      expect(unknownAccount['modelAccount'], isNull);
      expect(unknownAccount['modelCapabilities'], isEmpty);

      // 路由指向的账号不含该模型：保持 unknown，不借用另一账号的同名模型。
      final crossAccount = workspaceJsonFor(
        _sharedModelRoute(accountId: 'acct-a'),
      );
      expect(crossAccount['modelAccount'], isNull);
      expect(crossAccount['modelCapabilities'], isEmpty);
    },
  );

  test('初始连接失败保留安全 typed 诊断，不需要展示 lease', () async {
    final env = await _environment();
    final timeline = env.application.graph.timeline;
    await env.failOpening(
      const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'sentinel-message-must-not-leak',
        retryable: false,
        correlationId: 'corr-a1',
        details: StudioFailureDetails.reason(reason: 'details-must-not-leak'),
      ),
    );
    // 首基线前的真实失败：连接 failed、代次 0、没有展示 lease、没有条目。
    final failed = await env.timelineWhere(
      (state) => state?.connectionPhase == TimelineConnectionPhase.failed,
    );
    expect(failed!.generation, 0);
    expect(failed.connectionError, isNotNull);
    expect(timeline.display('thread'), isNull);

    final opens = env.application.domains.timeline.requests.length;
    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
    final plain = json['timeline'] as Map<String, dynamic>;
    // 四个键在 timeline 对象存在时始终存在，缺键不是合法 null。
    for (final key in _connectionErrorKeys) {
      expect(plain.containsKey(key), isTrue, reason: '$key 必须在 timeline 中始终存在');
    }
    expect(plain['connection'], 'failed');
    expect(plain['generation'], 0);
    expect(plain['ready'], isFalse);
    expect(plain['itemCount'], 0);
    expect(plain['connectionErrorType'], 'StudioFailure');
    expect(plain['connectionErrorCode'], 'unavailable');
    expect(plain['connectionErrorRetryable'], isFalse);
    expect(plain['connectionErrorCorrelationId'], 'corr-a1');
    // 隐私边界：message 与 detailsJson 不进入诊断。
    final encoded = jsonEncode(plain);
    expect(encoded.contains('sentinel-message-must-not-leak'), isFalse);
    expect(encoded.contains('details-must-not-leak'), isFalse);
    // 同一份真实快照进入严格 Driver parser，不另建 facts 回读。
    final observation = TimelineObservation.parse(json);
    expect(observation.ready, isFalse);
    expect(observation.connection, 'failed');
    expect(observation.generation, 0);
    expect(observation.itemCount, 0);
    // typed 身份原样来自当前 error：false 不降级为 null，correlation 不重新发明。
    expect(observation.connectionErrorType, 'StudioFailure');
    expect(observation.connectionErrorCode, 'unavailable');
    expect(observation.connectionErrorRetryable, isFalse);
    expect(observation.connectionErrorCorrelationId, 'corr-a1');

    // 读诊断不制造 transport demand 或会话。
    env.capture();
    expect(env.application.domains.timeline.requests.length, opens);

    // 选择离开当前 Thread 后诊断不残留上一次失败。
    env.application.graph.workspace.restoreSelection(
      const WorkspaceSelection(
        projectId: 'project',
        threadId: null,
        needsOpen: false,
      ),
    );
    final cleared = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
    expect(cleared['timeline'], isNull);
  });

  test('未知连接异常只保留运行时类型，不调用其 toString 或替身 typed 身份', () async {
    final env = await _environment();
    final timeline = env.application.graph.timeline;
    final original = _UnprintableTimelineFailure();
    await env.failOpening(original);
    // 未知异常不是 typed 失败：通道按可重试收束，最终仍以同一对象 failed。
    final failed = await env.timelineWhere(
      (state) => state?.connectionPhase == TimelineConnectionPhase.failed,
    );
    expect(failed!.connectionError, isA<_UnprintableTimelineFailure>());
    expect(failed.connectionError, same(original));
    expect(timeline.display('thread'), isNull);

    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
    final plain = json['timeline'] as Map<String, dynamic>;
    // 运行时类型名来自 Dart 类型元数据；异常自身的 toString 必须不被调用。
    expect(plain['connectionErrorType'], '_UnprintableTimelineFailure');
    expect(plain['connectionErrorCode'], isNull);
    expect(plain['connectionErrorRetryable'], isNull);
    expect(plain['connectionErrorCorrelationId'], isNull);
    final observation = TimelineObservation.parse(json);
    expect(observation.connection, 'failed');
    expect(observation.connectionErrorType, '_UnprintableTimelineFailure');
    expect(observation.connectionErrorCode, isNull);
    expect(observation.connectionErrorRetryable, isNull);
    expect(observation.connectionErrorCorrelationId, isNull);
  });

  test('无连接错误时四项为 null，parser 拒绝缺键与类型错误并接受 null', () async {
    final env = await _environment();
    await env.openContent(_factsBaseline());
    final opens = env.application.domains.timeline.requests.length;
    final json = jsonDecode(env.snapshotJson()) as Map<String, dynamic>;
    final plain = json['timeline'] as Map<String, dynamic>;
    for (final key in _connectionErrorKeys) {
      expect(plain.containsKey(key), isTrue, reason: '$key 必须在 timeline 中始终存在');
      expect(plain[key], isNull, reason: '无错误时 $key 是未知，不是 internal');
    }

    // 同一份真实快照的负向矩阵：缺键与错误类型都是观测失败。
    final missing = Map<String, dynamic>.from(plain)
      ..remove('connectionErrorCode');
    expect(
      () => TimelineObservation.parse(_withTimeline(json, missing)),
      throwsStateError,
      reason: '缺键不能静默当作 null',
    );
    final mismatched = <String, Object?>{
      'connectionErrorType': 7,
      'connectionErrorCode': 5,
      'connectionErrorRetryable': 'false',
      'connectionErrorCorrelationId': 1.5,
    };
    for (final entry in mismatched.entries) {
      final mutated = Map<String, dynamic>.from(plain)
        ..[entry.key] = entry.value;
      expect(
        () => TimelineObservation.parse(_withTimeline(json, mutated)),
        throwsStateError,
        reason: '${entry.key} 的类型不符必须拒绝',
      );
    }
    // 合法 null 被接受：未知或无错误不等于缺键。
    final nulled = Map<String, dynamic>.from(plain)
      ..['connectionErrorType'] = null
      ..['connectionErrorCode'] = null
      ..['connectionErrorRetryable'] = null
      ..['connectionErrorCorrelationId'] = null;
    final parsed = TimelineObservation.parse(_withTimeline(json, nulled));
    expect(parsed.connection, 'ready');
    expect(parsed.ready, isTrue);
    expect(parsed.connectionErrorType, isNull);
    expect(parsed.connectionErrorCode, isNull);
    expect(parsed.connectionErrorRetryable, isNull);
    expect(parsed.connectionErrorCorrelationId, isNull);
    expect(env.application.domains.timeline.requests.length, opens);
  });

  test('ACP 安装失败是终态：phase=failed、阶段为 null，失败类别由 typed 枚举解析', () async {
    final env = await _environment();
    final base = env.capture();

    // 真实装配尚未加载 acpInstall：既不伪造 loaded，也不用空集合冒充“已加载”。
    final unpublished = base.toJson()['settings'] as Map;
    expect(unpublished['acpAuthLoaded'], isFalse);
    expect(unpublished['acpInstall'], {
      'loaded': false,
      'revision': null,
      'installations': null,
    });
    // 认证、ACP 账号目录与 Native 模板同样是“没读到就是 null”，不用空集合冒充。
    expect(unpublished['acpAuth'], {
      'loaded': false,
      'revision': null,
      'updatedAt': null,
      'accounts': null,
    });
    expect(unpublished['acpAccounts'], isNull);
    expect(unpublished['nativeTemplates'], isNull);

    // baseline 含 revision 0 必达：revision 0 是合法的“已加载”水位，和被当成
    // 缺失是两个不同的结论，不能因为水位为 0 就退回 `loaded=false`。
    final baseline = _acpSnapshot(
      base,
      auth: AcpAuthSnapshot.empty,
      install: AcpInstallSnapshot.empty,
    );
    final baselineSettings = baseline.toJson()['settings'] as Map;
    expect(baselineSettings['acpAuthLoaded'], isTrue);
    final baselineInstall = baselineSettings['acpInstall'] as Map;
    expect(baselineInstall['loaded'], isTrue);
    expect(baselineInstall['revision'], 0);
    // 已加载且确实没有任何安装条目是真实空集合，与未加载的 null 语义不同。
    expect(baselineInstall['installations'], isNotNull);
    expect(baselineInstall['installations'], isEmpty);
    // 同一个 revision 0 的认证盒子：已加载、没有任何账号观察。
    expect(baselineSettings['acpAuth'], {
      'loaded': true,
      'revision': 0,
      'updatedAt': 0,
      'accounts': <Object?>[],
    });

    // Failed 是终态：状态层没有“当前阶段”，失败发生在哪一步由 failure 携带。
    final failed = _acpSnapshot(
      base,
      auth: AcpAuthSnapshot.empty,
      install: AcpInstallSnapshot(
        revision: 7,
        updatedAt: 1760000000,
        installations: [
          AcpInstallEntry(
            provider: AcpProvider.antigravity,
            state: const AcpInstallState.failed(
              operationId: 'op-failed',
              failure: AcpInstallFailure(
                code: AcpInstallFailureCode.checksumMismatch,
                stage: AcpInstallStage.verify,
                message: 'checksum mismatch',
                retryable: true,
              ),
            ),
          ),
        ],
      ),
    );
    final settings = failed.toJson()['settings'] as Map;
    expect(settings['acpAuthLoaded'], isTrue);
    final install = settings['acpInstall'] as Map;
    expect(install['loaded'], isTrue);
    expect(install['revision'], 7);
    final entry = (install['installations'] as List).single as Map;
    expect(entry['provider'], 'antigravity');
    expect(entry['phase'], 'failed');
    expect(entry['operationId'], 'op-failed');
    // 终态没有“当前阶段”；失败发生在 verify 由 failure 自己携带。
    expect(entry['stage'], isNull);
    // 终态没有进度、发行描述符与就绪结果，这些字段必须如实为 null。
    expect(entry['progress'], isNull);
    expect(entry['release'], isNull);
    expect(entry['program'], isNull);
    expect(entry['reused'], isNull);
    expect(entry['retryCount'], 0);
    expect(entry['failure'], {
      'code': 'checksumMismatch',
      'stage': 'verify',
      'message': 'checksum mismatch',
      'retryable': true,
    });

    // 投影是 typed 镜像的纯函数：同一事实重复序列化不会推进状态机或改写结果。
    expect(jsonEncode(failed.toJson()), jsonEncode(failed.toJson()));
  });

  test('ACP 安装关闭中保留 cancelled 失败且不被 Ready 吞掉，投影不建立业务 demand', () async {
    final env = await _environment();
    final graph = env.application.graph;
    final authObservers = graph.acpAuth.state.observerCount;
    final installObservers = graph.acpInstall.state.observerCount;
    // 完整 usage 集合而不是条数：新增、释放或换阶段都会改变 permit 事实。
    List<ResourceUsage> permits() => graph.budget.usage.toList();
    final permitsBefore = permits();
    final base = env.capture();

    final closing = _acpSnapshot(
      base,
      install: AcpInstallSnapshot(
        revision: 8,
        updatedAt: 1760000010,
        installations: [
          AcpInstallEntry(
            provider: AcpProvider.antigravity,
            state: const AcpInstallState.closing(
              operationId: 'op-closing',
              failure: AcpInstallFailure(
                code: AcpInstallFailureCode.cancelled,
                stage: AcpInstallStage.download,
                message: 'cancelled by user',
                retryable: true,
              ),
            ),
          ),
        ],
      ),
    );

    // 序列化后再核对：Driver 消费的是 JSON 里的真实失败事实。
    final json =
        jsonDecode(jsonEncode(closing.toJson())) as Map<String, dynamic>;
    final install =
        (json['settings'] as Map<String, dynamic>)['acpInstall']
            as Map<String, dynamic>;
    expect(install['loaded'], isTrue);
    expect(install['revision'], 8);
    final entry =
        (install['installations'] as List).single as Map<String, dynamic>;
    // 关闭中是物理收束非终态：阶段是 close，而不是失败来源的 download。
    expect(entry['phase'], 'closing');
    expect(entry['phase'], isNot('ready'));
    expect(entry['stage'], 'close');
    expect(entry['operationId'], 'op-closing');
    expect(entry['failure'], {
      'code': 'cancelled',
      'stage': 'download',
      'message': 'cancelled by user',
      'retryable': true,
    });

    // 投影只读现有镜像：没有观察租约、没有占用 permit，也没有让未加载的领域
    // 变成已加载（`synchronize()` 才是业务 demand，本路径不调用）。
    expect(graph.acpAuth.state.observerCount, authObservers);
    expect(graph.acpInstall.state.observerCount, installObservers);
    expect(authObservers, 0, reason: '本装配不打开 ACP 认证订阅');
    expect(installObservers, 0, reason: '本装配不打开 ACP 安装订阅');
    expect(permits(), permitsBefore, reason: '投影不占用或释放任何预算 permit');
    // 与集合是否为空无关的固定事实：诊断路径从不取得 ACP 域的任何 permit。
    expect(
      permits().where((usage) => usage.owner.startsWith('acp')),
      isEmpty,
      reason: 'ACP permit 只由订阅/命令产生，只读投影不产生',
    );
    expect(graph.acpAuth.state.value.canonical, isNull);
    expect(graph.acpInstall.state.value.canonical, isNull);
    final reread = env.capture();
    expect(reread.acpAuth, isNull);
    expect(reread.acpInstall, isNull);
  });

  test('ACP 认证按账号与连接代次发布，安装条目带 typed 进度/发行描述符/就绪结果', () async {
    final env = await _environment();
    final base = env.capture();

    final observed = _acpSnapshot(
      base,
      auth: AcpAuthSnapshot(
        revision: 3,
        updatedAt: 30,
        accounts: [
          AcpAuthAccount(
            accountId: 'acct-antigravity',
            connectionRevision: 5,
            state: const AcpAuthState.verified(
              checkedAt: 1760000000,
              server: AcpServerInfo(name: 'agy', title: null, version: '1.4.1'),
            ),
          ),
          AcpAuthAccount(
            accountId: 'acct-other',
            connectionRevision: 1,
            state: const AcpAuthState.required(
              server: null,
              methods: [
                AcpAuthMethod(
                  id: 'm1',
                  name: 'Login',
                  description: null,
                  kind: AcpAuthMethodKind.agent,
                ),
              ],
            ),
          ),
        ],
      ),
      // 来源三键取自本用例真实捕获的当前 Settings 目标：不假造空 owner，也不把
      // 材料引用版本当成 Settings 业务版本。
      accounts: AcpAccountDirectory(
        origin: base.configuration.projection.stamp!.origin,
        reference: base.configuration.projection.header!.reference!,
        revision: base.configuration.projection.header!.configurationRevision!,
        updatedAt: base.configuration.projection.header!.updatedAt ?? 0,
        accounts: [
          AcpAccountSettings(
            accountId: 'acct-antigravity',
            name: 'Antigravity',
            provider: AcpProvider.antigravity,
            connectionRevision: 5,
          ),
        ],
      ),
      templates: _nativeTemplates(['native-fixture']),
      install: AcpInstallSnapshot(
        revision: 4,
        updatedAt: 40,
        installations: [
          AcpInstallEntry(
            provider: AcpProvider.antigravity,
            state: AcpInstallState.downloading(
              operationId: 'op-download',
              release: _fixedRelease,
              progress: const AcpInstallProgress(
                completedBytes: 120,
                totalBytes: null,
                bytesPerSecond: 40,
              ),
              retryCount: 2,
            ),
          ),
        ],
      ),
    );

    final settings = observed.toJson()['settings'] as Map;
    expect(settings['acpAuthLoaded'], isTrue);
    final auth = settings['acpAuth'] as Map;
    expect(auth['revision'], 3);
    expect(auth['updatedAt'], 30);
    final authAccounts = (auth['accounts'] as List).cast<Map>();
    expect(authAccounts.map((row) => row['accountId']), [
      'acct-antigravity',
      'acct-other',
    ]);
    // 认证观察必须带连接代次：只有同代次才能与配置身份配对。
    expect(authAccounts.first['connectionRevision'], 5);
    expect(authAccounts.first['state'], {
      'kind': 'verified',
      'checkedAt': 1760000000,
      'server': {'name': 'agy', 'title': null, 'version': '1.4.1'},
    });
    final required = authAccounts[1]['state'] as Map;
    expect(required['kind'], 'required');
    expect(required['server'], isNull);
    expect((required['methods'] as List).single, {
      'id': 'm1',
      'name': 'Login',
      'kind': 'agent',
      'description': null,
    });
    // ACP 账号配置身份与 Native 模板身份各自发布，顺序即 canonical 顺序。
    expect(settings['acpAccounts'], [
      {
        'accountId': 'acct-antigravity',
        'name': 'Antigravity',
        'provider': 'antigravity',
        'connectionRevision': 5,
      },
    ]);
    expect(settings['nativeTemplates'], ['native-fixture']);
    final entry =
        ((settings['acpInstall'] as Map)['installations'] as List).single
            as Map;
    expect(entry['phase'], 'downloading');
    expect(entry['stage'], 'download');
    expect(entry['progress'], {
      'completedBytes': 120,
      'totalBytes': null,
      'bytesPerSecond': 40,
    });
    expect(entry['retryCount'], 2);
    expect(entry['release'], _fixedReleaseJson);
    // 未就绪时没有 program/reused；失败为空也不能伪造。
    expect(entry['program'], isNull);
    expect(entry['reused'], isNull);
    expect(entry['failure'], isNull);
  });

  test('ACP 目录投影三键校验：当前 Settings 输出 []，来源推进后必须 null，重新读到当前才再现', () async {
    final env = await _environment();
    final graph = env.application.graph;

    await _waitUntil(
      () =>
          graph
              .configuration
              .state
              .value
              .projection
              .header
              ?.configurationRevision !=
          null,
      reason: 'initial configuration header',
    );
    // 真实配置领域读取：目录的 origin/reference/revision 由 SDK mirror 冻结，
    // 测试不手工构造目录，也不替换 repository。
    final directory = await graph.configuration.loadAcpAccounts();
    expect(
      directory.accounts,
      isEmpty,
      reason: '本环境 header 声明 acpAccounts.total = 0',
    );

    DriverSnapshot captureWith(AcpAccountDirectory? borrowed) =>
        captureDriverSnapshot(
          graph,
          visible: DriverViewFacts(acpAccounts: borrowed),
          bots: const DriverBotsUnknown('not mounted in this scenario'),
        );
    Map settingsOf(DriverSnapshot snapshot) =>
        snapshot.toJson()['settings'] as Map;

    // 三键与当前 Settings 一致 → 真实空目录输出 []（不是 null，也不是缺省）。
    final current = captureWith(directory);
    expect(settingsOf(current)['acpAccounts'], isEmpty);
    expect(current.acpAccounts, same(directory));

    // 推进真实 Settings 源：新的材料引用与 configurationRevision。
    await env.application.domains.configurationPort.base.publishSettings(2);
    await _waitUntil(
      () =>
          graph
              .configuration
              .state
              .value
              .projection
              .header
              ?.configurationRevision ==
          2,
      reason: 'configuration revision 2',
    );

    // 旧目录的来源已过期：Driver 不得把它当成 current，也不降级成空集合。
    final stale = captureWith(directory);
    expect(settingsOf(stale)['acpAccounts'], isNull);
    expect(stale.acpAccounts, isNull);

    // 在新源上重新真实读取成功后再次可见，仍然只是 []。
    final refreshed = await graph.configuration.loadAcpAccounts();
    expect(refreshed.revision, 2);
    expect(refreshed.accounts, isEmpty);
    expect(settingsOf(captureWith(refreshed))['acpAccounts'], isEmpty);
  });

  test('未挂载账号页时不实例化 owner：Driver 的 ACP 目录与模板保持 null 且不占新 permit', () async {
    final env = await _environment();
    final container = env.application.container;
    final inspection = DriverInspection(
      graph: env.application.graph,
      container: container,
    );

    final permitsBefore = env.application.graph.budget.usage.toList();
    final settings = inspection.capture().toJson()['settings'] as Map;

    expect(settings['acpAccounts'], isNull);
    expect(settings['nativeTemplates'], isNull);
    // exists() 不实例化 owner：未打开账号页就没有该 VM，也没有新的读取。
    expect(container.exists(accountsViewModelProvider), isFalse);
    expect(env.application.graph.budget.usage.toList(), permitsBefore);
  });

  test('已挂 AccountsVM：读取失败→null、成功空目录→[]、来源变更→null 且 last-good 仍在', () async {
    final env = await _environment();
    final container = env.application.container;
    final graph = env.application.graph;
    final port = env.application.acpPort;
    final inspection = DriverInspection(graph: graph, container: container);

    /// 标量 scope 计数：ACP 观察者与三侧真实读取次数。
    ///
    /// budget permit 必须做集合深度比较，不能放进 record：record 按字段 `==`
    /// 比较，而每次 `usage.toList()` 都是新 List，恒等比较必然失败。
    ({
      int authObservers,
      int installObservers,
      int catalogReads,
      int authReads,
      int installReads,
    })
    scopeCounts() => (
      authObservers: graph.acpAuth.state.observerCount,
      installObservers: graph.acpInstall.state.observerCount,
      catalogReads: port.catalogReads.length,
      authReads: port.authReads.length,
      installReads: port.installReads.length,
    );

    /// 每次 capture 前后精确比对 scope：Driver 不得新增 query/observer/permit。
    Map settingsOfCapture() {
      final permitsBefore = graph.budget.usage.toList();
      final countsBefore = scopeCounts();
      final settings = inspection.capture().toJson()['settings'] as Map;
      expect(
        graph.budget.usage.toList(),
        permitsBefore,
        reason: '投影不占用或释放任何预算 permit',
      );
      expect(
        scopeCounts(),
        countsBefore,
        reason: '投影不新增 query/observer/permit',
      );
      return settings;
    }

    var answeredCatalogReads = 0;

    /// 只应答**一条**尚未结算的 catalog 请求；有界等待它真实出现。
    ///
    /// 不批量应答、不自动成功：某一阶段多出来的请求由该阶段的精确计数断言暴露成
    /// 失败，而不是被顺手答掉。
    Future<void> answerNextCatalogRead(
      AcpAccountCatalog? catalog, {
      Object? error,
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (answeredCatalogReads == port.catalogReads.length) {
        if (!DateTime.now().isBefore(deadline)) {
          throw StateError('no ACP catalog read arrived');
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final reply = port.catalogReads[answeredCatalogReads++];
      if (error != null) {
        reply.completeError(error);
      } else {
        reply.complete(catalog!);
      }
    }

    /// 目录是否已满足 Driver 侧 guard 的**全部**条件：本次读取完成（目录非 null）、
    /// 该字段 issue 已清除、且来源三键仍指向当前 Settings 目标。
    ///
    /// 只判断 `acpAccounts != null` 是不够的：① 里目录在 catalog 失败前已部分成功，
    /// 于是它一开始就非空，而 `readIssues` 仍存在——Driver 会正确返回 null。
    bool acpDirectoryIsCurrent() {
      final state = container.read(accountsViewModelProvider).asData?.value;
      final directory = state?.acpAccounts;
      if (state == null ||
          directory == null ||
          state.readIssues.containsKey(AccountsReadField.acpAccounts)) {
        return false;
      }
      final projection = graph.configuration.state.value.projection;
      if (projection.sync.phase != ResourceSyncPhase.ready) return false;
      return directory.origin == projection.stamp?.origin &&
          directory.reference == projection.header?.reference &&
          directory.revision == projection.header?.configurationRevision;
    }

    /// 有界等待上述真实状态成立；沿用 `_waitUntil` 原有的 5s 上限。
    ///
    /// 这里**不再代为应答**任何 catalog 请求：该出现的请求由各阶段显式应答并计数，
    /// 意外请求直接让计数断言失败。
    Future<void> waitAcpDirectoryReady({required String reason}) => _waitUntil(
      acpDirectoryIsCurrent,
      reason: 'ACP directory current: $reason',
    );

    final listen = container.listen(accountsViewModelProvider, (_, _) {});
    addTearDown(listen.close);

    // ① 真实读取失败（catalog 侧抛 typed 失败）：VM 记录 readIssues，Driver 不得输出。
    await answerNextCatalogRead(
      null,
      error: const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'acp catalog read failed for this cycle',
        retryable: true,
        correlationId: 'driver-acp-catalog-failure',
      ),
    );
    await _waitUntil(
      () =>
          container
              .read(accountsViewModelProvider)
              .asData
              ?.value
              .readIssues
              .containsKey(AccountsReadField.acpAccounts) ??
          false,
      reason: 'acpAccounts read issue recorded by the mounted accounts page',
    );
    // 计数取样放在该阶段真正完成之后：issue 已被记录，说明这次失败读取已结算。
    expect(port.catalogReads.length, 1, reason: '① 只允许一次 catalog 读取');
    final failedState = container.read(accountsViewModelProvider).requireValue;
    expect(
      failedState.readIssues.containsKey(AccountsReadField.acpAccounts),
      isTrue,
      reason: '本次 refresh 失败必须被 VM 记录',
    );
    expect(settingsOfCapture()['acpAccounts'], isNull);

    // ② 显式重试后真实成功：有效空目录输出 []，不是 null。
    final notifier = container.read(accountsViewModelProvider.notifier);
    notifier.setVisible(true);
    notifier.retryRead();
    await answerNextCatalogRead(AcpAccountCatalog.empty);
    // 必须等到该次读取真的完成、issue 清除且来源仍是当前目标：
    // 仅 `acpAccounts != null` 在 ① 部分成功后立刻成立，会让 Driver 按残留 issue
    // 正确返回 null（不是生产缺陷）。
    await waitAcpDirectoryReady(
      reason: 'ACP directory loaded through the mounted accounts page',
    );
    expect(
      port.catalogReads.length,
      2,
      reason: '② 重试只允许一次追加 catalog 读取（实测 1→2）',
    );
    final loadedState = container.read(accountsViewModelProvider).requireValue;
    expect(loadedState.acpAccounts, isNotNull);
    expect(loadedState.acpAccounts!.accounts, isEmpty);
    final validEmpty = settingsOfCapture();
    expect(validEmpty['acpAccounts'], isEmpty);

    // ③ 推进真实 Settings 源：VM 仍保留旧目录（不清 UI last-good），Driver 必须 null。
    await env.application.domains.configurationPort.base.publishSettings(2);
    await _waitUntil(
      () =>
          graph
              .configuration
              .state
              .value
              .projection
              .header
              ?.configurationRevision ==
          2,
      reason: 'configuration revision 2',
    );
    final staleState = container.read(accountsViewModelProvider).requireValue;
    expect(
      staleState.acpAccounts,
      isNotNull,
      reason: 'Driver 不自作主张清空 UI 的 last-good 目录',
    );
    final stale = settingsOfCapture();
    expect(stale['acpAccounts'], isNull);

    // ④ 在新源上重新真实读取成功后再次可见，仍然只是 []。
    final catalogReadsBeforeRefresh = port.catalogReads.length;
    await notifier.refreshAcpAccounts('acct-none');
    // 同一真实屏障：读取完成 + issue 清除 + 目录已是当前 revision 2 的目标。
    await waitAcpDirectoryReady(reason: 'ACP directory re-read at revision 2');
    expect(
      port.catalogReads.length,
      catalogReadsBeforeRefresh,
      reason: '④ refreshAcpAccounts 只做配置读取，不得新发起 catalog 读取',
    );
    final refreshed = settingsOfCapture();
    expect(refreshed['acpAccounts'], isEmpty);

    // ⑤ 同一 source / 当前 target 下让 Settings header 读取真实失败：VM 保留
    //    last-good（仍是 revision 2 的目录），Driver 必须输出 null。
    env.application.domains.configurationPort.configurationHeaderFailure =
        const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'settings header read failed for this cycle',
          retryable: true,
          correlationId: 'driver-acp-refresh-failure',
        );
    await notifier.refreshAcpAccounts('acct-none');
    await _waitUntil(
      () =>
          container
              .read(accountsViewModelProvider)
              .asData
              ?.value
              .readIssues
              .containsKey(AccountsReadField.acpAccounts) ??
          false,
      reason: 'ACP refresh failure recorded for this cycle',
    );
    final failedRefresh = container
        .read(accountsViewModelProvider)
        .requireValue;
    expect(
      failedRefresh.acpAccounts,
      isNotNull,
      reason: 'VM 仍保留 last-good 目录，Driver 只决定自己的输出',
    );
    expect(failedRefresh.acpAccounts!.revision, 2);
    expect(settingsOfCapture()['acpAccounts'], isNull);

    // ⑥ 清除故障后显式重试：同一 source guard 仍匹配，目录再次输出 []。
    //    catalog 在 ② 成功时已缓存（VM 用 `??=`），同 target 恢复不应再产生
    //    catalog 读取：先记基线，等真实完成屏障后断言计数未增、无悬空 reply。
    final catalogReadsBeforeRetry = port.catalogReads.length;
    env.application.domains.configurationPort.configurationHeaderFailure = null;
    notifier.retryRead();
    // 同一真实屏障：恢复后仍要求 issue 清除、读取完成且来源三键指向当前目标。
    await waitAcpDirectoryReady(
      reason: 'ACP directory recovered after clearing the failure',
    );
    expect(
      port.catalogReads.length,
      catalogReadsBeforeRetry,
      reason: 'catalog 已缓存，同 target 的显式重试不应再发起 catalog 读取',
    );
    final recovered = settingsOfCapture();
    expect(recovered['acpAccounts'], isEmpty);

    // 收尾责任：本条用例产生的每个 catalog 读取都已结算，没有悬空 reply。
    expect(
      answeredCatalogReads,
      port.catalogReads.length,
      reason: '所有 catalog reply 都必须已结算',
    );
  });
}

const _connectionErrorKeys = <String>[
  'connectionErrorType',
  'connectionErrorCode',
  'connectionErrorRetryable',
  'connectionErrorCorrelationId',
];

/// 替换诊断快照里的 `timeline` 对象，用于严格 parser 的负向矩阵。
Map<String, dynamic> _withTimeline(
  Map<String, dynamic> snapshot,
  Map<String, dynamic> timeline,
) => Map<String, dynamic>.from(snapshot)..['timeline'] = timeline;

/// 非 typed 连接异常：任何对它的 `toString()` 都是正文泄漏或额外推断。
final class _UnprintableTimelineFailure implements Exception {
  @override
  String toString() => throw StateError('sentinel-message-must-not-be-read');
}

WorkspaceThreadRecord _factsThread() => fixtureThread('thread').copyWith(
  title: 'Thread',
  delegationMode: DelegationMode.profile,
  workspacePath: '/thread',
);

ModelRouteReadValue _sharedModelRoute({
  required String accountId,
  bool available = true,
}) => ModelRouteReadValue(
  botId: null,
  accountId: ReadText.inline(text: accountId),
  modelId: const ReadText.inline(text: 'shared-model'),
  effort: const ReadText.inline(text: 'high'),
  revision: 3,
  available: available,
  unavailableReason: null,
);

/// 有界等待一个真实投影条件成立；超时即失败，不用固定 sleep 掩盖时序。
Future<void> _waitUntil(
  bool Function() ready, {
  required String reason,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('timed out waiting for $reason');
}

/// 产品固定的受管发行描述符：1.4.1 清单没有发布方摘要，`sha256` 必须保持 null。
const _fixedRelease = AcpInstallRelease(
  version: '1.4.1',
  target: 'linux-x86_64',
  archiveUrl:
      'https://dl.google.com/agy-extensions/releases/linux/'
      'agy-acp-server-1.4.1-linux-x86_64.zip',
  sha256: null,
);

/// 同一描述符的投影形状；消费者按字段读，不解析 URL 推断目标。
const _fixedReleaseJson = <String, Object?>{
  'version': '1.4.1',
  'target': 'linux-x86_64',
  'archiveUrl':
      'https://dl.google.com/agy-extensions/releases/linux/'
      'agy-acp-server-1.4.1-linux-x86_64.zip',
  'sha256': null,
};

/// Native 模板目录的最小真实构造：只提供投影需要的稳定身份。
AccountTemplatesValue _nativeTemplates(List<String> ids) =>
    AccountTemplatesValue(
      schemaVersion: 1,
      revision: '1',
      templates: [
        for (final id in ids)
          AccountTemplate(
            id: id,
            displayName: id,
            description: null,
            baseUrl: 'https://fixture.invalid/v1',
            credential: const CredentialDescriptor(
              label: 'API key',
              envVar: null,
            ),
            modelCatalogId: 'catalog',
            protocol: 'openai',
            suggestedModelId: 'model',
            iconKey: null,
            serviceCapabilities: const AccountServiceCapabilities(
              webSearch: WebSearchServiceCapabilities(
                hostedResponses: false,
                hostedDialect: 'none',
                standalone: null,
              ),
              promptCacheDialect: 'none',
              responsesProgrammaticToolCalling: false,
            ),
          ),
      ],
      modelCatalogs: const {},
    );

/// Immutable published input to the production Driver serializer: the two ACP
/// canonical mirrors are supplied as values instead of a fake Repository, while
/// every unrelated fact is borrowed from a fully real application assembly.
DriverSnapshot _acpSnapshot(
  DriverSnapshot base, {
  AcpAuthSnapshot? auth,
  AcpInstallSnapshot? install,
  AcpAccountDirectory? accounts,
  AccountTemplatesValue? templates,
}) => DriverSnapshot(
  selection: base.selection,
  project: base.project,
  thread: base.thread,
  rootThreadId: base.rootThreadId,
  directory: base.directory,
  directoryHasMore: base.directoryHasMore,
  agents: base.agents,
  agentDirectoryError: base.agentDirectoryError,
  execution: base.execution,
  metrics: base.metrics,
  context: base.context,
  threadConfiguration: base.threadConfiguration,
  authoring: base.authoring,
  interactions: base.interactions,
  startDraft: base.startDraft,
  composer: base.composer,
  configuration: base.configuration,
  models: base.models,
  operations: base.operations,
  persistence: base.persistence,
  recovery: base.recovery,
  updates: base.updates,
  startup: base.startup,
  display: base.display,
  conversation: base.conversation,
  status: base.status,
  plan: base.plan,
  bots: base.bots,
  acpAuth: auth,
  acpInstall: install,
  acpAccounts: accounts,
  templates: templates,
);

/// Immutable published input to the production Driver serializer, just as the
/// old identity test supplied a value projection rather than a fake Repository.
/// Unrelated values are borrowed from a fully real application assembly.
DriverSnapshot _identitySnapshot(
  DriverSnapshot base,
  ModelRouteReadValue? route,
) {
  final account = base.configuredAccounts!.first;
  final catalog = base.catalogAccounts!.first;
  final model = catalog.effectiveModels.first;
  final textInput = ModelInputCapability(
    modality: ModelModality.text,
    sources: const [ModelInputSource.local],
    maxCount: null,
    maxBytes: null,
    maxTotalBytes: null,
    maxWidth: null,
    maxHeight: null,
    mediaTypes: const [],
  );
  final imageInput = textInput.copyWith(modality: ModelModality.image);
  final configuration = base.configuration.copyWith(
    accounts: _publishedRows([
      account.copyWith(
        accountId: 'acct-a',
        name: 'Account A',
        bearerTokenEnv: 'ACCT_A_KEY',
      ),
      account.copyWith(
        accountId: 'acct-b',
        name: 'Account B',
        bearerTokenEnv: 'ACCT_B_KEY',
        hasBearerToken: true,
      ),
    ], base.configuration.projection.stamp!.origin),
  );
  final models = base.models.copyWith(
    accounts: _publishedRows([
      catalog.copyWith(
        accountId: 'acct-a',
        effectiveModels: [
          model.copyWith(
            modelId: 'a-only',
            capabilities: model.capabilities.copyWith(input: [textInput]),
          ),
        ],
      ),
      catalog.copyWith(
        accountId: 'acct-b',
        effectiveModels: [
          model.copyWith(
            modelId: 'shared-model',
            capabilities: model.capabilities.copyWith(
              input: [textInput, imageInput],
            ),
          ),
        ],
      ),
    ], base.models.projection.stamp!.origin),
  );
  final status = ThreadStatusViewState(
    threadId: 'thread',
    configurationRead: ReadMaterial(
      header: ThreadConfigurationReadHeader(
        scope: const ReadScopeIdentity(
          scopeId: 'driver-route',
          runtimeEpoch: 'driver-native',
          incarnation: 1,
          sourceRevision: 3,
        ),
        route: route,
        activeSkillCount: 0,
      ),
    ),
  );
  return DriverSnapshot(
    selection: const WorkspaceSelection(
      projectId: 'project',
      threadId: 'thread',
      needsOpen: false,
    ),
    project: base.project,
    thread: _factsThread(),
    rootThreadId: 'thread',
    directory: base.directory,
    directoryHasMore: base.directoryHasMore,
    agents: base.agents,
    agentDirectoryError: base.agentDirectoryError,
    execution: base.execution,
    metrics: base.metrics,
    context: base.context,
    threadConfiguration: base.threadConfiguration,
    authoring: base.authoring,
    interactions: base.interactions,
    startDraft: base.startDraft,
    composer: base.composer,
    configuration: configuration,
    models: models,
    operations: base.operations,
    persistence: base.persistence,
    recovery: base.recovery,
    updates: base.updates,
    startup: base.startup,
    display: base.display,
    conversation: base.conversation,
    status: status,
    plan: base.plan,
    bots: base.bots,
    acpAuth: base.acpAuth,
    acpInstall: base.acpInstall,
  );
}

CollectionMirror<T> _publishedRows<T>(
  List<T> values,
  ProductReadOrigin origin,
) {
  final references = [
    for (var index = 0; index < values.length; index++)
      ProductEntityRef(entry: index + 1, revision: 1),
  ];
  return CollectionMirror.current(
    window: CollectionWindow(
      origin: origin,
      reference: ProductCollectionRef(
        entry: 1,
        revision: 1,
        total: values.length,
      ),
      entries: references,
      rows: {
        for (var index = 0; index < values.length; index++)
          references[index].entry: ReadValue.ready(
            current: Materialized(
              origin: origin,
              reference: references[index],
              value: values[index],
            ),
          ),
      },
      continuation: const CollectionContinuation.end(),
      complete: true,
      loading: false,
      error: null,
    ),
  );
}

UserQuestionView _factsQuestion({required String id, String text = 'Q'}) =>
    UserQuestionView(
      id: id,
      header: 'Header',
      question: text,
      isOther: false,
      isSecret: false,
      options: const [],
    );

StudioTimelineItem _textItem(
  String id,
  int ordinal,
  ThreadTextChannel channel, {
  List<ThreadAttachmentView> attachments = const [],
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: 1767225600,
    updatedAt: 1767225600,
    saved: true,
    executionTerminal: true,
    state: ThreadTextItemStateView(
      channel: channel,
      text: 'body-$id',
      attachments: attachments,
      lifecycle: CompletedThreadContentView(1767225600),
    ),
  ),
  saved: true,
  lifecycle: StudioTimelineLifecycle.terminal,
  omittedBytes: 0,
  details: const [],
);

StudioTimelineItem _toolItem(
  String id,
  int ordinal, {
  ThreadToolUserInputView? userInput,
  ThreadToolLifecycleView lifecycle = const RunningThreadToolView(''),
  StudioTimelineLifecycle itemLifecycle = StudioTimelineLifecycle.streaming,
  String name = 'ask_user',
}) => StudioTimelineItem(
  item: ThreadItemView(
    id: id,
    threadId: 'thread',
    turnId: 'turn',
    ordinal: ordinal,
    revision: 1,
    createdAt: 1767225600,
    updatedAt: 1767225600,
    saved: true,
    executionTerminal: true,
    state: ThreadToolItemStateView(
      invocation: ThreadToolInvocationView(
        toolCallId: id,
        callId: id,
        name: name,
        arguments: '{}',
      ),
      lifecycle: lifecycle,
      userInput: userInput,
    ),
  ),
  saved: true,
  lifecycle: itemLifecycle,
  omittedBytes: 0,
  details: const [],
);

StudioTimelineBaseline _factsBaseline() => StudioTimelineBaseline(
  subscriptionId: 'facts',
  version: 1,
  before: null,
  hasOlder: false,
  items: [
    _textItem('cm', 1, ThreadTextChannel.commentary),
    _textItem('fa', 2, ThreadTextChannel.finalAnswer),
    _toolItem('tool', 3),
    _toolItem(
      'qa-normal',
      4,
      userInput: ThreadToolUserInputView(
        interactionId: 'normal',
        questions: [_factsQuestion(id: 'q1')],
        state: ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(questionId: 'q1', answers: ['A']),
        ]),
      ),
    ),
    _toolItem(
      'qa-plan-pending',
      5,
      name: planSubmitToolName,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-pending',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const PendingThreadToolUserInputView(),
      ),
    ),
    _toolItem(
      'qa-plan-cancelled',
      6,
      name: planSubmitToolName,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-cancelled',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: const CancelledThreadToolUserInputView(),
      ),
    ),
    _toolItem(
      'qa-plan-approved',
      7,
      name: planSubmitToolName,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-approved',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: agentSessionPlanConfirmationQuestionId,
            answers: [agentSessionPlanApproveAnswer],
          ),
        ]),
      ),
    ),
    // 旧历史的普通问答工具复用过保留的问题 ID：它仍必须报告为普通问答。
    _toolItem(
      'qa-plan-legacy',
      8,
      userInput: ThreadToolUserInputView(
        interactionId: 'plan-legacy',
        questions: [
          _factsQuestion(
            id: agentSessionPlanConfirmationQuestionId,
            text: '# Plan',
          ),
        ],
        state: ResolvedThreadToolUserInputView([
          ThreadUserInputAnswerView(
            questionId: agentSessionPlanConfirmationQuestionId,
            answers: [agentSessionPlanApproveAnswer],
          ),
        ]),
      ),
    ),
  ],
);

/// 用户输入附件与工具输出附件都用 SDK 的 typed DTO 准备，不做 dynamic 替身。
const _userImage = ThreadAttachmentView(
  id: 'user-image',
  modality: AttachmentModality.image,
  mediaType: 'image/png',
  byteSize: 2048,
  filename: 'chart.png',
);

const _userFile = ThreadAttachmentView(
  id: 'user-file',
  modality: AttachmentModality.file,
  mediaType: 'text/plain',
  byteSize: 15,
  filename: 'notes.txt',
);

const _toolImage = ThreadAttachmentView(
  id: 'tool-image',
  modality: AttachmentModality.image,
  mediaType: 'image/png',
  byteSize: 4096,
  filename: 'shot.png',
);

const _toolVideo = ThreadAttachmentView(
  id: 'tool-video',
  modality: AttachmentModality.video,
  mediaType: 'video/mp4',
  byteSize: 8192,
  filename: 'clip.mp4',
);

/// 用户条目带图片/文件附件，工具条目带真实成功输出附件：投影必须同时保留
/// 顶层附件行与 nested 工具附件，且 modality 是 canonical enum 名。
StudioTimelineBaseline _attachmentBaseline() => StudioTimelineBaseline(
  subscriptionId: 'attachments',
  version: 1,
  before: null,
  hasOlder: false,
  items: [
    _textItem(
      'user',
      1,
      ThreadTextChannel.user,
      attachments: const [_userImage, _userFile],
    ),
    _toolItem(
      'tool-output',
      2,
      name: 'bash',
      itemLifecycle: StudioTimelineLifecycle.terminal,
      lifecycle: SucceededThreadToolView(
        1767225600,
        ThreadToolOutput(
          result: 'ok',
          attachments: [_toolImage, _toolVideo],
          outputArtifacts: [],
        ),
      ),
    ),
  ],
);
