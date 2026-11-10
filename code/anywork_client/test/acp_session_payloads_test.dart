import 'dart:convert' show utf8;

import 'package:anywork_client/acp_sessions.dart';
import 'package:test/test.dart';

import 'support/acp_business_port.dart';

final _target = AcpSessionTargetView(
  sessionId: 'product',
  agentId: 'agent',
  threadId: 'thread',
  instance: BigInt.from(900),
);
final _run = AcpRunIdView(instance: BigInt.from(8), sequence: BigInt.from(2));
const _remote = AcpRemoteSessionId('remote');
final _meta = AcpJsonObject({
  'extension': AcpJsonArray([
    const AcpJsonNull(),
    const AcpJsonBool(false),
    const AcpJsonString('opaque'),
    AcpJsonInteger(BigInt.parse('18446744073709551615')),
    AcpJsonDecimal(0.125),
    AcpJsonObject({'nested': const AcpJsonString('preserved')}),
  ]),
});
final _request = OpenAcpSessionRequestView(
  accountId: 'account',
  expectedConnectionRevision: BigInt.one,
  workspaceId: 'workspace',
  intent: const AcpNewIntentView(),
);

List<AcpSessionConfigOptionView> _configs() => [
  AcpSessionConfigOptionView(
    id: const AcpConfigId('model'),
    name: 'Model',
    description: 'Model description',
    category: const AcpConfigCategoryView.known(
      AcpConfigCategoryKindView.model,
    ),
    kind: AcpSelectConfigView(
      currentValue: const AcpConfigValueId('second'),
      options: AcpGroupedOptionsView([
        AcpSelectGroupView(
          group: const AcpConfigGroupId('group-z'),
          name: 'Z',
          options: [
            AcpSelectOptionView(
              value: const AcpConfigValueId('second'),
              name: 'Second',
              description: 'not sorted',
              meta: _meta,
            ),
            const AcpSelectOptionView(
              value: AcpConfigValueId('first'),
              name: 'First',
            ),
          ],
          meta: _meta,
        ),
        AcpSelectGroupView(
          group: const AcpConfigGroupId('group-a'),
          name: 'A',
          options: [],
        ),
      ]),
    ),
    meta: _meta,
  ),
  const AcpSessionConfigOptionView(
    id: AcpConfigId('safe'),
    name: 'Safe',
    kind: AcpBooleanConfigView(currentValue: false),
  ),
  AcpSessionConfigOptionView(
    id: const AcpConfigId('thought'),
    name: 'Thought',
    category: const AcpConfigCategoryView.other('vendor-category'),
    kind: AcpSelectConfigView(
      currentValue: const AcpConfigValueId('false'),
      options: AcpUngroupedOptionsView([
        const AcpSelectOptionView(
          value: AcpConfigValueId('false'),
          name: 'False string',
        ),
      ]),
    ),
  ),
];

Future<void> _throughClient(List<AcpSessionEventView> events) async {
  final frames = [
    AcpAcceptedFrameView(target: _target, hasObservation: true),
    for (final event in events) AcpEventFrameView(event),
    const AcpSettledFrameView(AcpSuccessView<void>(null)),
  ];
  final source = ControlledAcpObservation(frames)..eof = true;
  final port = ControlledAcpBusinessPort()..sources.add(source);
  final client = AcpSessionClient(port: port);
  final observation = await client.open(_request);
  for (final frame in frames) {
    expect(await observation.next(), same(frame));
  }
  expect(await observation.next(), isNull);
  expect(port.calls.single.$2, same(_request));
  await client.dispose();
}

void main() {
  test(
    'launch failure kinds remain distinct through payload and Client',
    () async {
      const kinds = [
        AcpBusinessFailureKindView.installRequired,
        AcpBusinessFailureKindView.installationInvalid,
        AcpBusinessFailureKindView.unsupportedPlatform,
        AcpBusinessFailureKindView.missingExecutable,
        AcpBusinessFailureKindView.invalidWorkingDirectory,
        AcpBusinessFailureKindView.invalidDefinition,
        AcpBusinessFailureKindView.io,
        AcpBusinessFailureKindView.cancelled,
      ];
      final receivedKinds = <AcpBusinessFailureKindView>[];
      for (final kind in kinds) {
        final error = AcpBusinessFailureView(
          kind: kind,
          message: 'Launch unavailable',
          rpcData: _meta,
        );
        final accepted = AcpAcceptedFrameView(
          target: _target,
          hasObservation: false,
        );
        final settled = AcpSettledFrameView(AcpFailureView<void>(error));
        final source = ControlledAcpObservation([accepted, settled])
          ..eof = true;
        final port = ControlledAcpBusinessPort()..sources.add(source);
        final client = AcpSessionClient(port: port);
        final observation = await client.open(_request);
        expect(await observation.next(), same(accepted));
        final frame = await observation.next() as AcpSettledFrameView;
        final failure = (frame.result as AcpFailureView<void>).error;
        expect(failure, same(error));
        expect(failure.message, 'Launch unavailable');
        expect(failure.rpcData, same(_meta));
        receivedKinds.add(failure.kind);
        expect(await observation.next(), isNull);
        expect(port.calls.map((call) => call.$1), ['open']);
        await client.dispose();
      }
      expect(receivedKinds, orderedEquals(kinds));
      expect(
        receivedKinds[0],
        isNot(receivedKinds[3]),
        reason: 'Installation required is not a missing executable',
      );
    },
  );

  test('config absence, empty list, grouped select and boolean stay distinct and ordered', () async {
    final none = AcpNewSessionResponseView(sessionId: _remote);
    final empty = AcpNewSessionResponseView(
      sessionId: _remote,
      configOptions: [],
    );
    final configs = _configs();
    final full = AcpNewSessionResponseView(
      sessionId: _remote,
      configOptions: configs,
      meta: _meta,
      modes: AcpSessionModeStateView(
        currentModeId: const AcpModeId('legacy'),
        availableModes: [
          AcpSessionModeView(
            id: const AcpModeId('legacy'),
            name: 'Legacy',
            meta: _meta,
          ),
        ],
        meta: _meta,
      ),
    );
    final configured = AcpConfiguredResponseView(
      configOptions: configs,
      meta: _meta,
    );
    final changed = AcpConfigOptionsUpdateView(
      configOptions: configs,
      meta: _meta,
    );
    configs.clear();
    await _throughClient([AcpReadyEventView(none)]);
    await _throughClient([AcpReadyEventView(empty)]);
    await _throughClient([
      AcpReadyEventView(full),
      AcpConfiguredEventView(configured),
      AcpUpdateEventView(
        AcpSessionNotificationView(sessionId: _remote, update: changed),
      ),
    ]);
    expect(none.configOptions, isNull);
    expect(empty.configOptions, isEmpty);
    expect(full.configOptions!.map((c) => c.id.value), [
      'model',
      'safe',
      'thought',
    ]);
    expect(configured.configOptions, orderedEquals(full.configOptions!));
    expect(changed.configOptions, orderedEquals(full.configOptions!));
    final model = full.configOptions!.first;
    expect(model.name, 'Model');
    expect(model.description, 'Model description');
    expect(model.category!.kind, AcpConfigCategoryKindView.model);
    expect(model.meta, same(_meta));
    final select = model.kind as AcpSelectConfigView;
    expect(select.currentValue, const AcpConfigValueId('second'));
    final groups = (select.options as AcpGroupedOptionsView).groups;
    expect(groups.map((g) => g.group.value), ['group-z', 'group-a']);
    expect(groups.first.options.map((o) => o.value.value), ['second', 'first']);
    expect(groups.first.options.first.meta, same(_meta));
    expect(groups.first.options.first.description, 'not sorted');
    expect(
      (full.configOptions![1].kind as AcpBooleanConfigView).currentValue,
      isFalse,
    );
    final ungrouped = full.configOptions!.last.kind as AcpSelectConfigView;
    expect(ungrouped.currentValue.value, 'false');
    expect(full.configOptions!.last.category!.other, 'vendor-category');
    expect(() => full.configOptions!.clear(), throwsUnsupportedError);
    expect(() => groups.clear(), throwsUnsupportedError);
    expect(() => groups.first.options.clear(), throwsUnsupportedError);
  });

  test('stable official update union preserves tool fields, metadata and omission semantics', () async {
    final text = AcpTextContentView(
      text: 'payload',
      meta: _meta,
      annotations: AcpAnnotationsView(
        audience: [AcpContentRoleView.assistant, AcpContentRoleView.user],
        lastModified: '2026-08-01T00:00:00Z',
        priority: 0.5,
        meta: _meta,
      ),
    );
    final tool = AcpToolCallView(
      toolCallId: const AcpToolCallId('call'),
      title: 'Tool',
      name: 'tool-name',
      kind: AcpToolKindView.execute,
      status: AcpToolCallStatusView.inProgress,
      rawInput: _meta,
      rawOutput: const AcpJsonNull(),
      meta: _meta,
      locations: [
        AcpToolCallLocationView(path: '/workspace/file', line: 42, meta: _meta),
      ],
      content: [
        AcpToolContentView(content: text, meta: _meta),
        AcpToolDiffView(
          path: '/workspace/file',
          oldText: 'old',
          newText: 'new',
          meta: _meta,
        ),
        AcpToolTerminalView(
          terminalId: const AcpTerminalId('terminal'),
          meta: _meta,
        ),
      ],
    );
    final toolUpdate = AcpToolCallUpdateView(
      toolCallId: tool.toolCallId,
      meta: _meta,
      fields: AcpToolCallUpdateFieldsView(
        title: 'done',
        name: tool.name,
        kind: tool.kind,
        status: AcpToolCallStatusView.completed,
        content: [],
        locations: tool.locations,
        rawInput: _meta,
        rawOutput: const AcpJsonNull(),
      ),
    );
    final updates = <AcpSessionUpdateView>[
      AcpUserMessageChunkView(
        AcpContentChunkView(
          content: text,
          messageId: const AcpMessageId('user'),
          meta: _meta,
        ),
      ),
      AcpAgentMessageChunkView(AcpContentChunkView(content: text)),
      AcpAgentThoughtChunkView(AcpContentChunkView(content: text)),
      AcpToolCallSessionUpdateView(tool),
      AcpToolCallChangedView(toolUpdate),
      AcpPlanView(
        entries: [
          AcpPlanEntryView(
            content: 'step',
            priority: AcpPlanPriorityView.high,
            status: AcpPlanStatusView.inProgress,
            meta: _meta,
          ),
        ],
        meta: _meta,
      ),
      AcpAvailableCommandsUpdateView(
        commands: [
          AcpAvailableCommandView(
            name: 'compact',
            description: 'Compact',
            input: AcpUnstructuredCommandInputView(
              hint: 'summary',
              meta: _meta,
            ),
            meta: _meta,
          ),
        ],
        meta: _meta,
      ),
      AcpCurrentModeUpdateView(
        currentModeId: const AcpModeId('mode'),
        meta: _meta,
      ),
      AcpConfigOptionsUpdateView(configOptions: _configs(), meta: _meta),
      AcpSessionInfoUpdateView(
        title: const AcpFieldNull(),
        updatedAt: const AcpFieldAbsent(),
        meta: _meta,
      ),
      AcpUsageUpdateView(
        used: BigInt.from(12),
        size: BigInt.from(100),
        cost: AcpCostView(amount: 0.125, currency: 'USD', meta: _meta),
        meta: _meta,
      ),
      AcpNoticeView(
        severity: const AcpNoticeSeverityView.other('vendor-notice'),
        title: 'Notice',
        description: 'Detail',
        meta: _meta,
      ),
      AcpCompactionUpdateView(
        compactionId: const AcpCompactionId('compact'),
        status: const AcpCompactionStatusView.other('vendor-status'),
        summary: AcpFieldValue([text]),
        error: const AcpFieldNull(),
        meta: AcpFieldValue(_meta),
      ),
      AcpCompactionSummaryChunkView(
        compactionId: const AcpCompactionId('compact'),
        content: text,
        meta: _meta,
      ),
    ];
    await _throughClient([
      for (final update in updates)
        AcpUpdateEventView(
          AcpSessionNotificationView(
            sessionId: _remote,
            update: update,
            meta: _meta,
          ),
        ),
      AcpPermissionEventView(
        id: AcpPermissionIdView(
          instance: BigInt.from(8),
          sequence: BigInt.from(11),
        ),
        request: AcpPermissionRequestView(
          sessionId: _remote,
          toolCall: toolUpdate,
          options: [
            AcpPermissionOptionView(
              optionId: const AcpPermissionOptionId('allow'),
              name: 'Allow',
              kind: AcpPermissionOptionKindView.allowOnce,
              meta: _meta,
            ),
          ],
          meta: _meta,
        ),
      ),
      const AcpModeSetEventView(AcpModeId('mode')),
    ]);
    expect(tool.rawInput, same(_meta));
    expect(tool.rawOutput, isA<AcpJsonNull>());
    expect(toolUpdate.fields.content, isEmpty);
    expect(toolUpdate.fields.locations!.single.line, 42);
    final info = updates.whereType<AcpSessionInfoUpdateView>().single;
    expect(info.title, isA<AcpFieldNull<String>>());
    expect(info.updatedAt, isA<AcpFieldAbsent<String>>());
    final compaction = updates.whereType<AcpCompactionUpdateView>().single;
    expect(
      (compaction.summary as AcpFieldValue<List<AcpContentBlockView>>)
          .value
          .single,
      same(text),
    );
    expect(compaction.error, isA<AcpFieldNull<String>>());
    expect(
      (compaction.meta as AcpFieldValue<AcpJsonObject>).value,
      same(_meta),
    );
  });

  test('RPC failure auth guidance and every partial close fact pass through Client intact', () async {
    final failure = AcpBusinessFailureView(
      kind: AcpBusinessFailureKindView.rpc,
      rpcCode: -32000,
      message: 'Authentication required: follow agent guidance',
      rpcData: _meta,
      authMethods: [
        const AcpBusinessAuthMethodView(
          id: 'login',
          name: 'Agent login',
          description: 'Use official CLI',
          kind: AcpAuthMethodKindView.agent,
        ),
        const AcpBusinessAuthMethodView(
          id: 'terminal',
          name: 'Terminal login',
          kind: AcpAuthMethodKindView.terminal,
        ),
      ],
    );
    final completed = AcpCompletedRunView(
      run: _run,
      completionSequence: BigInt.from(4),
      result: AcpFailureView(failure),
      summary: 'failed',
      truncated: true,
    );
    final close = AcpBusinessCloseView(
      localComplete: false,
      sdkFinished: false,
      cleanupTimedOut: true,
      remoteCloseError: failure,
      sdkError: failure,
      workerError: 'worker join',
      driverError: 'driver EOF',
      unfinishedPrompt: _run,
      unfinishedControls: true,
      lastCompleted: completed,
      ownerFailures: [
        const AcpMemberCloseFailureView(
          threadId: 'thread',
          message: 'owner join',
        ),
      ],
    );
    final snapshot = AcpBusinessSnapshotView(
      target: _target,
      ready: false,
      closing: true,
      configPending: true,
      acpSessionId: _remote,
      configOptions: [],
      activeRun: _run,
      lastCompleted: completed,
      observationGap: AcpObservationGapView.disconnected,
      authMethods: failure.authMethods,
    );
    final list = AcpListSessionsResponseView(
      sessions: [
        AcpSessionInfoView(
          sessionId: _remote,
          cwd: '/workspace',
          additionalDirectories: ['/second', '/first'],
          title: 'title',
          updatedAt: '2026-08-01T00:00:00Z',
          meta: _meta,
        ),
      ],
      nextCursor: 'next',
      meta: _meta,
    );
    final port = ControlledAcpBusinessPort()
      ..closeValue = close
      ..snapshotValue = snapshot
      ..listValue = list;
    final client = AcpSessionClient(port: port);
    expect(await client.closeMember(_target), same(close));
    expect(await client.snapshot(_target), same(snapshot));
    expect(
      await client.list(
        AcpListRequestView(
          target: _target,
          request: const AcpListSessionsRequestView(cursor: 'previous'),
        ),
      ),
      same(list),
    );
    await _throughClient([
      AcpFailedEventView(failure),
      AcpCompletedEventView(completed),
    ]);
    expect(close.localComplete, isFalse);
    expect(close.sdkFinished, isFalse);
    expect(close.cleanupTimedOut, isTrue);
    expect(close.unfinishedControls, isTrue);
    expect(close.unfinishedPrompt, same(_run));
    expect(close.lastCompleted, same(completed));
    expect(close.ownerFailures.single.message, 'owner join');
    expect(close.remoteCloseError, same(failure));
    expect(close.sdkError, same(failure));
    expect(close.workerError, 'worker join');
    expect(close.driverError, 'driver EOF');
    expect(failure.rpcCode, -32000);
    expect(failure.rpcData, same(_meta));
    expect(failure.authMethods.map((m) => m.id), ['login', 'terminal']);
    expect(failure.authMethods.first.description, 'Use official CLI');
    expect(list.sessions.single.additionalDirectories, ['/second', '/first']);
    expect(port.calls.map((c) => c.$1), ['closeMember', 'snapshot', 'list']);
    await client.dispose();
  });

  test(
    'Settled failure and bounded real completion result remain separate',
    () async {
      final error = AcpBusinessFailureView(
        kind: AcpBusinessFailureKindView.publication,
        message: 'publish failed',
      );
      final settled = AcpSettledFrameView(AcpFailureView<void>(error));
      final response = AcpPromptResponseView(
        stopReason: AcpStopReasonView.cancelled,
        meta: _meta,
      );
      final completed = AcpCompletedRunView(
        run: _run,
        completionSequence: BigInt.from(12),
        result: AcpSuccessView(response),
        summary: '字' * 5461 + 'a',
        truncated: true,
      );
      expect(utf8.encode(completed.summary).length, 16384);
      final accepted = AcpAcceptedFrameView(
        target: _target,
        hasObservation: true,
      );
      final source = ControlledAcpObservation([accepted, settled]);
      final port = ControlledAcpBusinessPort()..sources.add(source);
      final client = AcpSessionClient(port: port);
      final observation = await client.open(_request);
      expect(await observation.next(), same(accepted));
      expect(await observation.next(), same(settled));
      expect((settled.result as AcpFailureView<void>).error, same(error));
      await client.dispose();
      expect(
        (completed.result as AcpSuccessView<AcpPromptResponseView>).value,
        same(response),
      );
      expect(
        () => AcpCompletedRunView(
          run: _run,
          completionSequence: BigInt.one,
          result: AcpSuccessView(response),
          summary: '${completed.summary}x',
          truncated: false,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'unsupported official variants fail explicitly rather than vanish',
    () async {
      const unsupported = AcpUnsupportedPayload('SessionUpdate.futureVariant');
      final source = ControlledAcpObservation()..readError = unsupported;
      final port = ControlledAcpBusinessPort()..sources.add(source);
      final client = AcpSessionClient(port: port);
      final observation = await client.open(_request);
      await expectLater(observation.next(), throwsA(same(unsupported)));
      expect(port.calls.map((c) => c.$1), ['open']);
      await client.dispose();
    },
  );
}
