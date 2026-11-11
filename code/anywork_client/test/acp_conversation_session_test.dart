import 'dart:async';

import 'package:anywork_client/acp_sessions.dart';
import 'package:test/test.dart';

import 'support/acp_business_port.dart';

final _target = AcpSessionTargetView(
  sessionId: 'session',
  agentId: 'agent',
  threadId: 'thread',
  instance: BigInt.from(91),
);
const _remote = AcpRemoteSessionId('remote');
final _run = AcpRunIdView(instance: BigInt.from(8), sequence: BigInt.one);
final _nextRun = AcpRunIdView(instance: BigInt.from(8), sequence: BigInt.two);
final _permissionId = AcpPermissionIdView(
  instance: BigInt.from(8),
  sequence: BigInt.from(9),
);
final _request = OpenAcpSessionRequestView(
  accountId: 'account',
  expectedConnectionRevision: BigInt.one,
  workspaceId: 'workspace',
  threadId: _target.threadId,
  intent: const AcpLoadIntentView(_remote),
);
final _accepted = AcpAcceptedFrameView(target: _target, hasObservation: true);
const _settled = AcpSettledFrameView(AcpSuccessView<void>(null));
const _capabilities = AcpAgentCapabilitiesView(
  image: true,
  audio: false,
  embeddedContext: true,
  loadSession: true,
  listSessions: false,
  resumeSession: false,
);
const _input = [AcpTextContentView(text: 'question')];
const _configId = AcpConfigId('effort');
const _value = AcpBooleanConfigValueView(true);

AcpSessionFrameView _event(AcpSessionEventView event) =>
    AcpEventFrameView(event);
AcpSessionFrameView _update(AcpSessionUpdateView update) => _event(
  AcpUpdateEventView(
    AcpSessionNotificationView(sessionId: _remote, update: update),
  ),
);
AcpSessionFrameView _text(String text) => _update(
  AcpAgentMessageChunkView(
    AcpContentChunkView(content: AcpTextContentView(text: text)),
  ),
);
AcpSessionFrameView _ready({
  List<AcpSessionConfigOptionView>? configOptions,
  AcpSessionModeStateView? modes,
}) => _event(
  AcpReadyEventView(
    AcpNewSessionResponseView(
      sessionId: _remote,
      configOptions: configOptions,
      modes: modes,
    ),
  ),
);
AcpCompletedRunView _completion(AcpRunIdView run) => AcpCompletedRunView(
  run: run,
  completionSequence: run.sequence,
  result: const AcpSuccessView(
    AcpPromptResponseView(stopReason: AcpStopReasonView.endTurn),
  ),
  summary: 'done',
  truncated: false,
);
AcpPermissionEventView _permission() => AcpPermissionEventView(
  id: _permissionId,
  request: AcpPermissionRequestView(
    sessionId: _remote,
    toolCall: AcpToolCallUpdateView(
      toolCallId: const AcpToolCallId('tool'),
      fields: AcpToolCallUpdateFieldsView(title: 'Run'),
    ),
    options: const [
      AcpPermissionOptionView(
        optionId: AcpPermissionOptionId('once'),
        name: 'Once',
        kind: AcpPermissionOptionKindView.allowOnce,
      ),
      AcpPermissionOptionView(
        optionId: AcpPermissionOptionId('reject'),
        name: 'Reject',
        kind: AcpPermissionOptionKindView.rejectAlways,
      ),
    ],
  ),
);

ControlledAcpBusinessPort _port(ControlledAcpObservation source) =>
    ControlledAcpBusinessPort()
      ..sources.add(source)
      ..run = _run
      ..closeValue = AcpBusinessCloseView(
        localComplete: true,
        sdkFinished: true,
        cleanupTimedOut: false,
        unfinishedControls: false,
      );

void _push(ControlledAcpObservation source, AcpSessionFrameView? frame) {
  final read = source.read;
  if (read != null && !read.isCompleted) {
    read.complete(frame);
  } else if (frame != null) {
    source.frames.add(frame);
  } else {
    source.eof = true;
  }
}

Future<AcpConversationSession> _open(AcpSessionClient client) async {
  final owner = await client.openConversation(_request);
  await owner.source.waitFor((s) => s.ready && !s.openPending);
  return owner;
}

void main() {
  test('formal user echo replaces only the current provisional input and keeps replay and repeated turns', () async {
    final replay = const AcpContentChunkView(
      content: AcpTextContentView(text: 'question'),
      messageId: AcpMessageId('replayed'),
    );
    final source = ControlledAcpObservation([
      _accepted,
      _update(AcpUserMessageChunkView(replay)),
      _ready(),
      _settled,
    ]);
    final port = _port(source)..promptResult = Completer<AcpRunIdView>();
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    final sending = owner.send(_input);
    expect(
      owner.state.content.whereType<AcpConversationMessageItem>(),
      hasLength(2),
    );
    _push(source, _update(AcpAvailableCommandsUpdateView(commands: const [])));
    await owner.source.waitFor(
      (state) => state.content.last is AcpConversationUpdateItem,
    );
    final first = AcpContentChunkView(
      content: const AcpTextContentView(text: 'ques'),
      messageId: const AcpMessageId('official'),
      meta: AcpJsonObject({'original': const AcpJsonString('metadata')}),
    );
    const second = AcpContentChunkView(
      content: AcpTextContentView(text: 'tion'),
      messageId: AcpMessageId('official'),
    );
    _push(source, _update(AcpUserMessageChunkView(first)));
    _push(source, _update(const AcpUserMessageChunkView(second)));
    await owner.source.waitFor((state) {
      final last = state.content.last;
      return last is AcpConversationMessageItem && last.chunks.length == 2;
    });
    final users = owner.state.content
        .whereType<AcpConversationMessageItem>()
        .toList();
    expect(users, hasLength(2));
    expect(users.first.chunks.single, same(replay));
    expect(users.last.chunks, [same(first), same(second)]);
    port.promptResult!.complete(_run);
    expect(await sending, _run);
    _push(source, _text('answer'));
    _push(source, _event(AcpCompletedEventView(_completion(_run))));
    await owner.source.waitFor((state) => state.lastCompleted != null);
    port
      ..promptResult = null
      ..run = _nextRun;
    await owner.send(_input);
    _push(source, _text('answer again without echo'));
    await owner.source.waitFor(
      (state) =>
          state.content.last is AcpConversationMessageItem &&
          (state.content.last as AcpConversationMessageItem).kind ==
              AcpConversationMessageKind.assistant,
    );
    final repeated = owner.state.content
        .whereType<AcpConversationMessageItem>()
        .where((item) => item.kind == AcpConversationMessageKind.user)
        .toList();
    expect(repeated, hasLength(3));
    expect(repeated.last.chunks.single.content, same(_input.single));
  });

  for (final boundary in ['response', 'completion', 'failure']) {
    test(
      'later user updates cannot retire a local input after $boundary',
      () async {
        final source = ControlledAcpObservation([
          _accepted,
          _ready(),
          _settled,
        ]);
        final port = _port(source);
        final client = AcpSessionClient(port: port);
        addTearDown(client.dispose);
        final owner = await _open(client);
        if (boundary == 'failure') {
          port.commandError = StateError('rejected prompt');
          await expectLater(owner.send(_input), throwsStateError);
        } else {
          await owner.send(_input);
          if (boundary == 'response') {
            _push(source, _text('response'));
            await owner.source.waitFor((state) => state.content.length == 2);
          } else {
            _push(source, _event(AcpCompletedEventView(_completion(_run))));
            await owner.source.waitFor((state) => state.lastCompleted != null);
          }
        }
        const later = AcpContentChunkView(
          content: AcpTextContentView(text: 'another user message'),
          messageId: AcpMessageId('later'),
        );
        _push(source, _update(const AcpUserMessageChunkView(later)));
        await owner.source.waitFor((state) {
          final last = state.content.last;
          return last is AcpConversationMessageItem &&
              identical(last.chunks.last, later);
        });
        final users = owner.state.content
            .whereType<AcpConversationMessageItem>()
            .where((item) => item.kind == AcpConversationMessageKind.user)
            .toList();
        expect(users, hasLength(2));
        expect(users.first.chunks.single.content, same(_input.single));
        expect(users.last.chunks.single, same(later));
      },
    );
  }

  test(
    'one owner and shared admission return before replay and Settled',
    () async {
      final source = ControlledAcpObservation([_accepted]);
      final port = _port(source);
      final client = AcpSessionClient(port: port);
      addTearDown(client.dispose);
      final first = client.openConversation(_request);
      final second = client.openConversation(_request);
      expect(second, same(first));
      final owner = await first;
      expect(owner.state.openPending, isTrue);
      expect(owner.state.ready, isFalse);
      expect(owner.state.target, same(_target));
      expect(client.conversationForThread('thread'), same(owner));
      expect(await client.openConversation(_request), same(owner));
      _push(source, _text('load before settled'));
      await owner.source.waitFor((s) => s.content.isNotEmpty);
      expect(owner.state.openPending, isTrue);
      expect(owner.state.history, AcpConversationHistory.loadReplay);
      _push(source, _ready());
      await owner.source.waitFor((s) => s.ready);
      _push(source, _settled);
      await owner.source.waitFor((s) => !s.openPending);
      expect(port.calls.map((c) => c.$1), ['open']);
      final watch = owner.source.watch((_) {});
      watch.cancel();
      _push(source, _text('continues without page'));
      await owner.source.waitFor((s) => s.content.length == 2);
      expect(source.closeSignals, 0);
    },
  );

  test(
    'ordered setup and config replacement preserve unrelated identities',
    () async {
      final modes = AcpSessionModeStateView(
        currentModeId: const AcpModeId('ask'),
        availableModes: const [
          AcpSessionModeView(id: AcpModeId('ask'), name: 'Ask'),
        ],
      );
      final before = AcpConfigOptionsUpdateView(
        configOptions: const [
          AcpSessionConfigOptionView(
            id: _configId,
            name: 'Before',
            kind: AcpBooleanConfigView(currentValue: false),
          ),
        ],
      );
      final source = ControlledAcpObservation([
        _accepted,
        _update(before),
        _ready(configOptions: [], modes: modes),
        _settled,
      ]);
      final port = _port(source);
      final client = AcpSessionClient(port: port);
      addTearDown(client.dispose);
      final owner = await _open(client);
      expect(
        owner.state.configOptions,
        isEmpty,
        reason: 'Ready replaces replay config',
      );
      expect(owner.state.usesLegacyModes, isFalse);
      await expectLater(
        () => owner.setMode(const AcpModeId('ask')),
        throwsA(isA<AcpBusinessFailureView>()),
      );
      final state = owner.state;
      _push(source, _text('body'));
      await owner.source.waitFor((s) => s.content.isNotEmpty);
      expect(owner.state.configOptions, same(state.configOptions));
      expect(owner.state.modes, same(state.modes));
      expect(owner.state.pendingPermissions, same(state.pendingPermissions));
      final content = owner.state.content;
      final plan = AcpPlanView(
        entries: const [
          AcpPlanEntryView(
            content: 'one',
            priority: AcpPlanPriorityView.high,
            status: AcpPlanStatusView.inProgress,
          ),
        ],
      );
      _push(source, _update(plan));
      await owner.source.waitFor((s) => s.plan != null);
      expect(owner.state.plan, same(plan));
      expect(owner.state.content, same(content));
      _push(source, _update(before));
      await owner.source.waitFor(
        (s) => identical(s.configOptions, before.configOptions),
      );
      expect(owner.state.content, same(content));
      expect(owner.state.plan, same(plan));
      expect(() => owner.state.content.clear(), throwsUnsupportedError);
    },
  );

  test(
    'chunks group only adjacent roles and tool patches replace by original ID',
    () async {
      final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
      final client = AcpSessionClient(port: _port(source));
      addTearDown(client.dispose);
      final owner = await _open(client);
      final frames = [
        _text('a'),
        _text('b'),
        _update(
          const AcpAgentThoughtChunkView(
            AcpContentChunkView(content: AcpTextContentView(text: 'think')),
          ),
        ),
        _text('c'),
        _update(
          AcpToolCallSessionUpdateView(
            AcpToolCallView(
              toolCallId: const AcpToolCallId('tool'),
              title: 'Read file',
              kind: AcpToolKindView.read,
              status: AcpToolCallStatusView.pending,
              rawInput: const AcpJsonString('input'),
            ),
          ),
        ),
        _text('after tool'),
        _update(
          AcpToolCallChangedView(
            AcpToolCallUpdateView(
              toolCallId: const AcpToolCallId('tool'),
              fields: AcpToolCallUpdateFieldsView(
                status: AcpToolCallStatusView.completed,
                rawOutput: const AcpJsonString('result'),
              ),
            ),
          ),
        ),
      ];
      source.frames.addAll(frames.skip(1));
      _push(source, frames.first);
      await owner.source.waitFor(
        (s) =>
            s.content
                .whereType<AcpConversationToolItem>()
                .firstOrNull
                ?.fields
                .status ==
            AcpToolCallStatusView.completed,
      );
      expect(owner.state.content.length, 5);
      final messages = owner.state.content
          .whereType<AcpConversationMessageItem>()
          .toList();
      expect(messages.map((m) => m.kind), [
        AcpConversationMessageKind.assistant,
        AcpConversationMessageKind.thought,
        AcpConversationMessageKind.assistant,
        AcpConversationMessageKind.assistant,
      ]);
      expect(
        messages.first.chunks.map(
          (c) => (c.content as AcpTextContentView).text,
        ),
        ['a', 'b'],
      );
      final tool = owner.state.content
          .whereType<AcpConversationToolItem>()
          .single;
      expect(tool.toolCallId, const AcpToolCallId('tool'));
      expect(tool.fields.title, 'Read file');
      expect((tool.fields.rawInput as AcpJsonString).value, 'input');
      expect((tool.fields.rawOutput as AcpJsonString).value, 'result');
    },
  );

  test('config failure retains intervening notification and blocks first send until acknowledged', () async {
    final source = ControlledAcpObservation([
      _accepted,
      _ready(configOptions: []),
      _settled,
    ]);
    final port = _port(source)..configureResult = Completer<void>();
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    final configure = owner.configure(_configId, _value);
    await expectLater(
      () => owner.configure(_configId, _value),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    await expectLater(
      owner.send(_input),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    final pushed = AcpConfigOptionsUpdateView(
      configOptions: const [
        AcpSessionConfigOptionView(
          id: _configId,
          name: 'Pushed',
          kind: AcpBooleanConfigView(currentValue: true),
        ),
      ],
    );
    _push(source, _update(pushed));
    await owner.source.waitFor(
      (s) => identical(s.configOptions, pushed.configOptions),
    );
    final failure = AcpBusinessFailureView(
      kind: AcpBusinessFailureKindView.invalidOption,
      message: 'set rejected',
    );
    final check = expectLater(configure, throwsA(same(failure)));
    port.configureResult!.completeError(failure);
    await check;
    expect(owner.state.configPending, isFalse);
    expect(owner.state.configOptions, same(pushed.configOptions));
    expect(owner.state.configError, same(failure));
    await expectLater(
      owner.send(_input),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    expect(port.calls.where((c) => c.$1 == 'prompt'), isEmpty);
    owner.dismissError();
    expect(await owner.send(_input), same(_run));
    expect((port.calls.last.$2 as AcpPromptRequestView).target, same(_target));
  });

  test('config success waits for ordered result and does not roll back later pushes', () async {
    final source = ControlledAcpObservation([
      _accepted,
      _ready(configOptions: []),
      _settled,
    ]);
    final port = _port(source)..configureResult = Completer<void>();
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    final configured = owner.configure(_configId, _value);
    port.configureResult!.complete();
    await configured;
    expect(
      owner.state.configPending,
      isTrue,
      reason: 'Command Future is not a configuration snapshot',
    );
    await expectLater(
      owner.send(_input),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    final response = AcpConfiguredResponseView(configOptions: []);
    _push(source, _event(AcpConfiguredEventView(response)));
    await owner.source.waitFor((s) => !s.configPending);
    expect(owner.state.configOptions, same(response.configOptions));
    expect(owner.state.configError, isNull);
    final notification = AcpConfigOptionsUpdateView(
      configOptions: const [
        AcpSessionConfigOptionView(
          id: _configId,
          name: 'Newest',
          kind: AcpBooleanConfigView(currentValue: false),
        ),
      ],
    );
    _push(source, _update(notification));
    await owner.source.waitFor(
      (s) => identical(s.configOptions, notification.configOptions),
    );
    expect(await owner.send(_input), _run);
  });

  test('legacy mode uses formal command and notifications only when config is absent', () async {
    final modes = AcpSessionModeStateView(
      currentModeId: const AcpModeId('ask'),
      availableModes: const [
        AcpSessionModeView(id: AcpModeId('act'), name: 'Act'),
      ],
    );
    final source = ControlledAcpObservation([
      _accepted,
      _ready(modes: modes),
      _settled,
    ]);
    final port = _port(source)..modeResult = Completer<void>();
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    expect(owner.state.usesLegacyModes, isTrue);
    final set = owner.setMode(const AcpModeId('act'));
    _push(source, _event(const AcpModeSetEventView(AcpModeId('act'))));
    await owner.source.waitFor(
      (s) => s.modes?.currentModeId == const AcpModeId('act'),
    );
    expect(owner.state.configPending, isTrue);
    port.modeResult!.complete();
    await set;
    expect(owner.state.configPending, isFalse);
    expect(port.calls.last.$1, 'setMode');
    expect((port.calls.last.$2 as AcpSetModeRequestView).target, same(_target));
  });

  test('permission and interrupt continue during set; stale and unoffered answers never cross port', () async {
    final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
    final port = _port(source)..configureResult = Completer<void>();
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    await owner.send(_input);
    final set = owner.configure(_configId, _value);
    final permission = _permission();
    _push(source, _event(permission));
    await owner.source.waitFor((s) => s.pendingPermissions.isNotEmpty);
    expect(owner.state.pendingPermissions.single, same(permission));
    expect(owner.state.pendingPermissions.single.request.options.length, 2);
    await expectLater(
      owner.answerPermission(
        _permissionId,
        const AcpPermissionOptionId('invented'),
      ),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    await owner.answerPermission(
      _permissionId,
      const AcpPermissionOptionId('reject'),
    );
    final answer = port.calls.last.$2 as AcpPermissionAnswerRequestView;
    expect(answer.target, same(_target));
    expect(answer.permissionId, same(_permissionId));
    expect(answer.optionId, const AcpPermissionOptionId('reject'));
    await expectLater(
      owner.answerPermission(_permissionId, null),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    _push(source, _event(permission));
    await owner.source.waitFor((s) => s.pendingPermissions.isNotEmpty);
    await owner.interrupt();
    expect(owner.state.pendingPermissions, isEmpty);
    expect(
      owner.state.activeRun,
      _run,
      reason: 'Interrupt is not prompt completion',
    );
    expect((port.calls.last.$2 as AcpInterruptRequestView).run, _run);
    _push(source, _text('tail while configuring'));
    await owner.source.waitFor((s) => s.content.length == 2);
    _push(
      source,
      _event(
        AcpConfiguredEventView(AcpConfiguredResponseView(configOptions: [])),
      ),
    );
    port.configureResult!.complete();
    await set;
    await owner.source.waitFor((s) => !s.configPending);
  });

  test(
    'Completed before prompt Future and late old Future cannot reset a new run',
    () async {
      final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
      final oldResult = Completer<AcpRunIdView>();
      final port = _port(source)..promptResult = oldResult;
      final client = AcpSessionClient(port: port);
      addTearDown(client.dispose);
      final owner = await _open(client);
      final first = owner.send(_input);
      expect(owner.state.sendPending, isTrue);
      final completed = _completion(_run);
      _push(source, _event(AcpCompletedEventView(completed)));
      await owner.source.waitFor((s) => s.lastCompleted != null);
      expect(owner.state.sendPending, isFalse);
      port.promptResult = null;
      port.run = _nextRun;
      expect(await owner.send(_input), _nextRun);
      oldResult.complete(_run);
      expect(await first, _run);
      expect(owner.state.activeRun, _nextRun);
      expect(owner.state.lastCompleted, same(completed));
      _push(source, _text('not completion'));
      await owner.source.waitFor((s) => s.content.length == 3);
      expect(owner.state.activeRun, _nextRun);
      _push(source, _event(AcpCompletedEventView(_completion(_nextRun))));
      await owner.source.waitFor((s) => s.activeRun == null);
    },
  );

  test('only initialized capabilities enable nontext blocks; capabilities stay nullable', () async {
    final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
    final port = _port(source);
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    expect(owner.state.capabilities, isNull);
    const image = [AcpImageContentView(data: 'base64', mimeType: 'image/png')];
    await expectLater(
      owner.send(image),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    _push(source, _event(const AcpInitializedEventView(_capabilities)));
    await owner.source.waitFor((s) => s.capabilities != null);
    expect(owner.state.capabilities, same(_capabilities));
    await expectLater(
      owner.send(const [
        AcpAudioContentView(data: 'audio', mimeType: 'audio/wav'),
      ]),
      throwsA(isA<AcpBusinessFailureView>()),
    );
    expect(await owner.send(image), _run);
    expect(port.calls.where((c) => c.$1 == 'prompt').length, 1);
  });

  for (final end in ['gap', 'eof', 'failure']) {
    test(
      '$end preserves active run without success or automatic reopen',
      () async {
        final source = ControlledAcpObservation([
          _accepted,
          _ready(),
          _settled,
        ]);
        final port = _port(source);
        final client = AcpSessionClient(port: port);
        addTearDown(client.dispose);
        final owner = await _open(client);
        await owner.send(_input);
        if (end == 'gap') {
          _push(
            source,
            _event(const AcpGapEventView(AcpObservationGapView.windowExceeded)),
          );
        } else if (end == 'eof') {
          _push(source, null);
        } else {
          source.read!.completeError(StateError('disconnected'));
        }
        await owner.source.waitFor((s) => s.disconnected);
        expect(owner.state.history, AcpConversationHistory.incomplete);
        expect(owner.state.activeRun, _run);
        expect(owner.state.lastCompleted, isNull);
        await expectLater(
          owner.send(_input),
          throwsA(isA<AcpBusinessFailureView>()),
        );
        expect(port.calls.map((c) => c.$1), ['open', 'prompt']);
      },
    );
  }

  test('resource links do not require embedded context capability', () async {
    final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
    final port = _port(source);
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    const link = AcpResourceLinkView(name: 'file', uri: 'file:///example');
    expect(await owner.send(const [link]), _run);
    expect(owner.state.capabilities, isNull);
    expect(
      (port.calls.last.$2 as AcpPromptRequestView).content.single,
      same(link),
    );
  });

  test(
    'late interrupt completion cannot clear the next run permission',
    () async {
      final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
      final port = _port(source)..interruptResult = Completer<void>();
      final client = AcpSessionClient(port: port);
      addTearDown(client.dispose);
      final owner = await _open(client);
      await owner.send(_input);
      final interrupting = owner.interrupt();
      _push(source, _event(AcpCompletedEventView(_completion(_run))));
      await owner.source.waitFor((s) => s.lastCompleted != null);
      port.run = _nextRun;
      await owner.send(_input);
      final permission = _permission();
      _push(source, _event(permission));
      await owner.source.waitFor((s) => s.pendingPermissions.isNotEmpty);
      port.interruptResult!.complete();
      await interrupting;
      expect(owner.state.activeRun, _nextRun);
      expect(owner.state.pendingPermissions.single, same(permission));
    },
  );

  test('permission failure retains request and explicit cancellation reaches original responder', () async {
    final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
    final port = _port(source);
    final client = AcpSessionClient(port: port);
    addTearDown(client.dispose);
    final owner = await _open(client);
    final permission = _permission();
    _push(source, _event(permission));
    await owner.source.waitFor((s) => s.pendingPermissions.isNotEmpty);
    final error = StateError('answer failed');
    port.commandError = error;
    await expectLater(
      owner.answerPermission(_permissionId, null),
      throwsA(same(error)),
    );
    expect(owner.state.pendingPermissions.single, same(permission));
    port.commandError = null;
    await owner.answerPermission(_permissionId, null);
    expect(owner.state.pendingPermissions, isEmpty);
    final answer = port.calls.last.$2 as AcpPermissionAnswerRequestView;
    expect(answer.optionId, isNull);
    expect(answer.permissionId, same(_permissionId));
    _push(source, _event(permission));
    await owner.source.waitFor((s) => s.pendingPermissions.isNotEmpty);
    expect(await owner.closeMember(), same(port.closeValue));
    expect(owner.state.pendingPermissions, isEmpty);
    expect(owner.state.ready, isFalse);
    expect(
      source.closeSignals,
      0,
      reason: 'Business close is distinct from observation release',
    );
  });

  test(
    'Completed before same prompt Future cannot resurrect its active run',
    () async {
      final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
      final port = _port(source)..promptResult = Completer<AcpRunIdView>();
      final client = AcpSessionClient(port: port);
      addTearDown(client.dispose);
      final owner = await _open(client);
      final sending = owner.send(_input);
      _push(source, _event(AcpCompletedEventView(_completion(_run))));
      await owner.source.waitFor((s) => s.lastCompleted != null);
      port.promptResult!.complete(_run);
      await sending;
      expect(owner.state.sendPending, isFalse);
      expect(owner.state.activeRun, isNull);
    },
  );

  test(
    'resident without observation makes unavailable temporary history explicit',
    () async {
      final source = ControlledAcpObservation([
        AcpAcceptedFrameView(target: _target, hasObservation: false),
        _settled,
      ])..eof = true;
      final port = _port(source);
      final client = AcpSessionClient(port: port);
      addTearDown(client.dispose);
      final owner = await client.openConversation(_request);
      await owner.source.waitFor((s) => s.observationEnded);
      expect(
        owner.state.history,
        AcpConversationHistory.residentWithoutObservation,
      );
      expect(owner.state.ready, isFalse);
      expect(owner.state.openPending, isFalse);
      expect(owner.state.content, isEmpty);
      expect(owner.state.capabilities, isNull);
      expect(port.calls.map((c) => c.$1), ['open']);
    },
  );

  test('Client dispose joins owner read and retains failed cleanup for retry without closing business', () async {
    final source = ControlledAcpObservation([_accepted, _ready(), _settled]);
    final port = _port(source);
    final client = AcpSessionClient(port: port);
    final owner = await _open(client);
    source.cleanupError = StateError('release failed');
    await expectLater(client.dispose(), throwsStateError);
    expect(client.conversationForThread('thread'), same(owner));
    expect(source.read!.isCompleted, isTrue);
    source.cleanupError = null;
    source.cleanup = Completer<void>();
    var done = false;
    final disposing = client.dispose().then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    source.cleanup!.complete();
    await disposing;
    expect(client.conversationForThread('thread'), isNull);
    expect(port.calls.map((c) => c.$1), ['open']);
    await expectLater(
      owner.send(_input),
      throwsA(isA<AcpObservationDisposed>()),
    );
  });

  test('dispose during admission releases late resource and joins its owner admission', () async {
    final port = ControlledAcpBusinessPort()
      ..admission = Completer<AcpSessionObservationPort>();
    final client = AcpSessionClient(port: port);
    final opening = client.openConversation(_request);
    final rejected = expectLater(
      opening,
      throwsA(isA<AcpObservationDisposed>()),
    );
    final disposing = client.dispose();
    final source = ControlledAcpObservation([_accepted])
      ..cleanup = Completer<void>();
    port.admission!.complete(source);
    await rejected;
    var done = false;
    unawaited(disposing.then((_) => done = true));
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    source.cleanup!.complete();
    await disposing;
    expect(source.closes, 1);
    expect(port.calls.map((c) => c.$1), ['open']);
  });
}
