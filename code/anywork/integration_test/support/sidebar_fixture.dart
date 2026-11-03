import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/studio_client.dart';

/// Isolated production fixture for sidebar tests.
///
/// The HTTP server is only the provider-side environment. Project, account and
/// root-thread state are created through the same typed commands as the product.
final class SidebarFixture {
  SidebarFixture._({
    required this.project,
    required this.thread,
    required this.runningThread,
    required this.attentionThread,
    required this.provider,
    required this._accountDemand,
    required Map<String, DirectoryObservation<ThreadMetadataFrame>>
    threadObservations,
  }) : _threadObservations = Map.unmodifiable(threadObservations);

  static const accountId = 'sidebar-integration-fixture';
  static const modelId = 'sidebar-fixture-model';

  final StudioProject project;
  final StudioThread thread;
  final StudioThread runningThread;
  final StudioThread attentionThread;
  final SidebarProviderFixture provider;
  final AccountDemand _accountDemand;
  final Map<String, DirectoryObservation<ThreadMetadataFrame>>
  _threadObservations;

  SessionDirectoryRow? threadSnapshot(String threadId) =>
      _threadObservations[threadId]?.state.value.frame?.row;

  static Future<SidebarFixture> create({
    required AppGraph graph,
    required String projectPath,
  }) async {
    final provider = await SidebarProviderFixture.start();
    final demand = graph.accounts.observeSummaries();
    final threadObservations =
        <String, DirectoryObservation<ThreadMetadataFrame>>{};
    try {
      await graph.accounts.state.waitFor((state) => state.loaded);
      await graph.accounts.loadTemplates();
      final template = graph.accounts.state.value.templates.templates
          .where((candidate) => candidate.protocol == 'open_ai_compatible')
          .single;
      const identity = NativeAccountIdentity(accountId);
      if (graph.accounts.state.value.account(identity) != null) {
        throw StateError('Sidebar fixture account already exists');
      }
      final created = await graph.accounts.create(
        CreateAccountCommand(
          identity: identity,
          name: 'Sidebar integration fixture',
          protocol: template.protocol,
          templateId: template.id,
          baseUrl: '${provider.origin}/v1',
          secret: const AccountSecretCommand.clear(),
          customModels: const [
            AccountModelCommand(
              modelId: modelId,
              displayName: 'Sidebar fixture model',
              wireApi: 'responses',
              contextWindow: 65536,
              maxOutputTokens: 4096,
            ),
          ],
        ),
      );
      if (created.error != null || !created.observed) {
        throw StateError('Fixture account creation failed: ${created.error}');
      }
      final selected = await graph.accounts.setDefault(identity);
      if (selected.error != null) {
        throw StateError(
          'Fixture default account selection failed: ${selected.error}',
        );
      }
      await graph.accounts.state.waitFor(
        (state) => state.account(identity)?.isDefault == true,
      );

      await graph.client.directoryCommands.openProject(projectPath);
      final projects =
          graph.client.project.state.projects?.values ??
          const <StudioProject>[];
      final project = projects.singleWhere(
        (candidate) => candidate.path == projectPath,
      );
      final thread = await _submitRoot(
        graph,
        project,
        inputId: 'sidebar-fixture-root-input',
        prompt: '[[sidebar_idle]]',
        title: 'Sidebar idle fixture',
        workspaceMode: 'worktree',
      );
      await _observeRoot(graph, thread, threadObservations);
      final runningThread = await _submitRoot(
        graph,
        project,
        inputId: 'sidebar-fixture-running-input',
        prompt: '[[sidebar_running]]',
        title: 'Sidebar running fixture',
      );
      await _observeRoot(graph, runningThread, threadObservations);
      await provider.waitForRunning();
      final attentionThread = await _submitRoot(
        graph,
        project,
        inputId: 'sidebar-fixture-attention-input',
        prompt: '[[sidebar_attention]]',
        title: 'Sidebar attention fixture',
      );
      await _observeRoot(graph, attentionThread, threadObservations);
      return SidebarFixture._(
        project: project,
        thread: thread,
        runningThread: runningThread,
        attentionThread: attentionThread,
        provider: provider,
        accountDemand: demand,
        threadObservations: threadObservations,
      );
    } catch (error, stack) {
      await _closeObservations(threadObservations.values);
      await demand.release();
      await provider.close();
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<StudioThread> _submitRoot(
    AppGraph graph,
    StudioProject project, {
    required String inputId,
    required String prompt,
    required String title,
    String? workspaceMode,
  }) async {
    final stages = <ThreadPreparationStage>[];
    const route = ModeModelRouteView(
      modeId: ThreadModeId.simple,
      accountId: accountId,
      modelId: modelId,
      effort: '',
    );
    final artifacts = Platform.environment['ANYWORK_SIDEBAR_ARTIFACTS'];
    if (artifacts == null || artifacts.trim().isEmpty) {
      throw StateError(
        'Supply ANYWORK_SIDEBAR_ARTIFACTS for preparation traces',
      );
    }
    final trace = File('$artifacts/$inputId-preparation.jsonl');
    void record(Map<String, Object?> event) {
      trace.writeAsStringSync(
        '${jsonEncode(event)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    record({
      'event': 'submit',
      'inputId': inputId,
      'workspaceId': project.id,
      'workspaceMode': workspaceMode,
      'route': {
        'modeId': route.modeId.name,
        'accountId': route.accountId,
        'modelId': route.modelId,
        'effort': route.effort,
        'transportEffort': route.effort.isEmpty ? null : route.effort,
      },
    });
    try {
      final result = await graph.client.threadCommands.submitNewThread(
        workspaceId: project.id,
        input: StudioPromptInput(
          inputId: inputId,
          text: prompt,
          attachmentDraftIds: const [],
        ),
        mode: ThreadModeId.simple,
        workspaceMode: workspaceMode,
        route: route,
        delegationMode: DelegationMode.profile,
        delegationPreference: DelegationPreference.balanced,
        onProgress: (progress) {
          stages.add(progress.stage);
          record({'event': 'progress', 'stage': progress.stage.name});
        },
      );
      if (result == null) {
        throw StateError('Fixture root-thread submission was not admitted');
      }
      final renamed = await graph.client.threadCommands.renameThread(
        result.thread.id,
        title,
      );
      return renamed ?? result.thread;
    } catch (error, stack) {
      try {
        record({
          'event': 'failure',
          'stages': stages.map((stage) => stage.name).toList(growable: false),
          'error': error.toString(),
          'stack': stack.toString(),
        });
      } catch (traceError) {
        stderr.writeln('Sidebar preparation trace write failed: $traceError');
      }
      stderr.writeln(
        'sidebar fixture submission $inputId failed after stages '
        '${stages.map((stage) => stage.name).join(' > ')}: $error',
      );
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<void> _observeRoot(
    AppGraph graph,
    StudioThread thread,
    Map<String, DirectoryObservation<ThreadMetadataFrame>> observations,
  ) async {
    final observation = graph.client.threadDirectory.observeThread(thread.id);
    observations[thread.id] = observation;
    final state = await observation.state
        .waitFor(
          (state) => state.frame != null || state.error != null || state.closed,
        )
        .timeout(const Duration(seconds: 30));
    if (state.error case final error?) {
      throw StateError(
        'Fixture root-thread observation failed for ${thread.id}: $error',
      );
    }
    final canonical = state.frame?.row;
    if (state.closed || canonical == null || !canonical.isRootRow) {
      throw StateError('Fixture root thread did not reach the directory');
    }
  }

  static Future<void> _closeObservations(
    Iterable<DirectoryObservation<ThreadMetadataFrame>> observations,
  ) async {
    await Future.wait(observations.map((observation) => observation.release()));
  }

  Future<void> settle(AppGraph graph) async {
    final artifacts = Platform.environment['ANYWORK_SIDEBAR_ARTIFACTS'];
    if (artifacts == null || artifacts.trim().isEmpty) {
      throw StateError('Supply ANYWORK_SIDEBAR_ARTIFACTS for cleanup traces');
    }
    final trace = File('$artifacts/sidebar-fixture-cleanup.jsonl');
    void record(Map<String, Object?> event) {
      trace.writeAsStringSync(
        '${jsonEncode(event)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    final candidates = _captureCleanupTargets(graph, [
      runningThread.id,
      attentionThread.id,
    ]);
    record({
      'event': 'canonicalCandidates',
      'targets': candidates
          .map((candidate) => candidate.diagnostic)
          .toList(growable: false),
    });
    for (final candidate in candidates.where(
      (candidate) => !candidate.hasLiveExecution,
    )) {
      record({
        'event': 'NoLiveExecutionAtCleanupStart',
        'threadId': candidate.threadId,
        'agentId': candidate.agentId,
        'canStop': candidate.canStop,
        'executionId': null,
        'directoryRevision': candidate.directoryRevision,
      });
    }
    final liveTargets = candidates
        .where((candidate) => candidate.hasLiveExecution)
        .map((candidate) => candidate.freeze())
        .toList(growable: false);
    record({
      'event': 'frozen',
      'targets': liveTargets
          .map((target) => target.diagnostic)
          .toList(growable: false),
    });

    late final Future<List<ThreadStopOutcome>> outcomes;
    try {
      final stopFutures = <Future<ThreadStopOutcome>>[
        for (final target in liveTargets)
          graph.client.threadCommands.stopAgent(
            target.threadId,
            expectedExecutionId: target.executionId,
          ),
      ];
      outcomes = Future.wait(stopFutures, eagerError: false);
      record({
        'event': 'registered',
        'targets': liveTargets
            .map((target) => target.diagnostic)
            .toList(growable: false),
      });
    } catch (error, stack) {
      record({
        'event': 'registrationFailure',
        'error': error.toString(),
        'stack': stack.toString(),
      });
      rethrow;
    }

    provider.releaseRunning();
    record({'event': 'providerReleased'});
    try {
      final results = await outcomes;
      await Future.wait([
        for (var index = 0; index < liveTargets.length; index++)
          _confirmStopped(graph, liveTargets[index], results[index], record),
      ]);
      record({'event': 'complete'});
    } catch (error, stack) {
      record({
        'event': 'failure',
        'error': error.toString(),
        'stack': stack.toString(),
      });
      rethrow;
    }
  }

  static List<_CleanupTarget> _captureCleanupTargets(
    AppGraph graph,
    List<String> threadIds,
  ) {
    final directory = graph.client.project.state.agents;
    if (directory == null) {
      throw StateError(
        'Cannot clean up fixture threads: agent directory is not loaded',
      );
    }
    return threadIds
        .map((threadId) {
          final matches = directory.values
              .where((agent) => agent.threadId == threadId)
              .toList(growable: false);
          if (matches.length != 1) {
            throw StateError(
              'Cannot clean up fixture thread $threadId: expected one canonical '
              'agent row, found ${matches.length}',
            );
          }
          final agent = matches.single;
          final execution = agent.execution;
          if ((execution == null) != !agent.canStop) {
            throw StateError(
              'Cannot clean up fixture thread $threadId: inconsistent stop '
              'qualification canStop=${agent.canStop}, execution=${execution?.id}',
            );
          }
          return _CleanupTarget(
            agentId: agent.agentId,
            threadId: threadId,
            executionId: execution?.id,
            executionPhase: execution?.phase.name,
            canStop: agent.canStop,
            stateType: agent.state.runtimeType.toString(),
            directoryRevision: directory.revision,
          );
        })
        .toList(growable: false);
  }

  static Future<void> _confirmStopped(
    AppGraph graph,
    _FrozenStopTarget target,
    ThreadStopOutcome outcome,
    void Function(Map<String, Object?> event) record,
  ) async {
    switch (outcome) {
      case StopRequested():
        if (outcome.threadId != target.threadId ||
            outcome.executionId != target.executionId ||
            outcome.receipt.operationId != outcome.operationId) {
          throw StateError(
            'Stop receipt identity did not match frozen target '
            '${target.threadId}:${target.executionId}',
          );
        }
        final operation = graph.client.mutations.lookup(outcome.operationId);
        if (operation == null) {
          throw StateError(
            'Mutation board lost stop operation ${outcome.operationId.value}',
          );
        }
        record({
          'event': 'requested',
          'threadId': target.threadId,
          'executionId': target.executionId,
          'operationId': outcome.operationId.value,
          'receipt': {
            'disposition': outcome.receipt.disposition.name,
            'effect': outcome.receipt.effect.name,
            'effective': outcome.receipt.effective,
            'durable': outcome.receipt.durable,
            'requiresIdentityObservation':
                outcome.receipt.requiresIdentityObservation,
            'targets': outcome.receipt.targets
                .map(
                  (stamp) => {
                    'resourceKey': stamp.resourceKey,
                    'ownerEpoch': stamp.ownerEpoch,
                    'revision': stamp.revision,
                  },
                )
                .toList(growable: false),
          },
        });
        final state = await operation.state
            .waitFor((state) => state.observed || state.failurePhase != null)
            .timeout(const Duration(seconds: 30));
        record({
          'event': 'operationSettled',
          'threadId': target.threadId,
          'executionId': target.executionId,
          'operationId': state.id.value,
          'phase': state.phase.name,
          'observed': state.observed,
          'effective': state.effective,
          'durable': state.durable,
          'failurePhase': state.failurePhase?.name,
          'errorType': state.error?.runtimeType.toString(),
        });
        if (!state.observed) {
          throw StateError(
            'Stop operation ${state.id.value} failed before observation: '
            '${state.failurePhase}',
          );
        }
      case StopNotQualified():
        final directory = graph.client.project.state.agents;
        if (directory == null) {
          throw StateError(
            'Stop was not qualified and the agent directory is not loaded '
            'for ${target.threadId}',
          );
        }
        final matches = directory.values
            .where((agent) => agent.threadId == target.threadId)
            .toList(growable: false);
        if (matches.length != 1) {
          throw StateError(
            'Stop was not qualified and canonical agent row count is '
            '${matches.length} for ${target.threadId}',
          );
        }
        final currentExecutionId = matches.single.execution?.id;
        record({
          'event': 'notQualified',
          'threadId': target.threadId,
          'frozenExecutionId': target.executionId,
          'currentExecutionId': currentExecutionId,
          'canStop': matches.single.canStop,
          'directoryRevision': directory.revision,
        });
        if (currentExecutionId == null ||
            currentExecutionId == target.executionId) {
          throw StateError(
            'Stop was not qualified without proving execution replacement '
            'for ${target.threadId}: frozen=${target.executionId}, '
            'current=$currentExecutionId',
          );
        }
      case StopNoExecution():
        throw StateError(
          'Exact fixture stop unexpectedly reported no execution for '
          '${target.threadId}',
        );
      case StopQueued():
        throw StateError(
          'Exact fixture stop unexpectedly queued for ${target.threadId}:'
          '${outcome.executionId}',
        );
    }
  }

  Future<void> close() async {
    await _closeObservations(_threadObservations.values);
    await _accountDemand.release();
    await provider.close();
  }
}

final class _CleanupTarget {
  const _CleanupTarget({
    required this.agentId,
    required this.threadId,
    required this.executionId,
    required this.executionPhase,
    required this.canStop,
    required this.stateType,
    required this.directoryRevision,
  });

  final String agentId;
  final String threadId;
  final String? executionId;
  final String? executionPhase;
  final bool canStop;
  final String stateType;
  final int directoryRevision;

  bool get hasLiveExecution => executionId != null;

  _FrozenStopTarget freeze() {
    final frozenExecutionId = executionId;
    if (frozenExecutionId == null || !canStop) {
      throw StateError('Cannot freeze a target without a live execution');
    }
    return _FrozenStopTarget(
      threadId: threadId,
      executionId: frozenExecutionId,
      canStop: canStop,
      directoryRevision: directoryRevision,
    );
  }

  Map<String, Object?> get diagnostic => {
    'agentId': agentId,
    'threadId': threadId,
    'executionId': executionId,
    'executionPhase': executionPhase,
    'canStop': canStop,
    'stateType': stateType,
    'directoryRevision': directoryRevision,
  };
}

final class _FrozenStopTarget {
  const _FrozenStopTarget({
    required this.threadId,
    required this.executionId,
    required this.canStop,
    required this.directoryRevision,
  });

  final String threadId;
  final String executionId;
  final bool canStop;
  final int directoryRevision;

  Map<String, Object?> get diagnostic => {
    'threadId': threadId,
    'executionId': executionId,
    'canStop': canStop,
    'directoryRevision': directoryRevision,
  };
}

/// Minimal OpenAI Responses-compatible loopback peer.
final class SidebarProviderFixture {
  SidebarProviderFixture._(this._server) {
    _serve = _server.forEach((request) {
      late final Future<void> handler;
      handler = _handle(request).whenComplete(() {
        _handlers.remove(handler);
      });
      _handlers.add(handler);
    });
  }

  final HttpServer _server;
  late final Future<void> _serve;
  final Set<Future<void>> _handlers = {};
  int _sequence = 0;
  int requests = 0;
  final Completer<void> _runningReached = Completer<void>();
  final Completer<void> _releaseRunning = Completer<void>();

  String get origin => 'http://${_server.address.address}:${_server.port}';

  static Future<SidebarProviderFixture> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return SidebarProviderFixture._(server);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await utf8.decoder.bind(request).join();
      if (request.method != 'POST' ||
          request.uri.path != '/v1/responses' ||
          body.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }
      requests++;
      final titleRequest = body.contains('Create the session title now');
      if (!titleRequest && body.contains('[[sidebar_running]]')) {
        await _serveRunning(request);
        return;
      }
      if (!titleRequest && body.contains('[[sidebar_attention]]')) {
        await _writeEvents(
          request,
          _responsesToolCall(
            'sidebar-attention-${++_sequence}',
            'sidebar-attention-call',
          ),
        );
        return;
      }
      final text = titleRequest
          ? 'Sidebar Fixture Session'
          : 'Sidebar fixture turn complete.';
      final responseId = 'sidebar-fixture-${++_sequence}';
      await _writeEvents(request, _responsesText(text, responseId));
    } catch (error, stack) {
      stderr.writeln('sidebar provider fixture failed: $error\n$stack');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } on Object {
        // The product may already have closed a failed request.
      }
    }
  }

  Future<void> _serveRunning(HttpRequest request) async {
    final id = 'sidebar-running-${++_sequence}';
    _prepareResponse(request);
    final events = _responsesText('Sidebar running response.', id);
    for (final event in events.take(3)) {
      request.response.write('data: ${jsonEncode(event)}\n\n');
    }
    await request.response.flush();
    if (!_runningReached.isCompleted) _runningReached.complete();
    await _releaseRunning.future;
    for (final event in events.skip(3)) {
      request.response.write('data: ${jsonEncode(event)}\n\n');
    }
    await request.response.close();
  }

  Future<void> _writeEvents(
    HttpRequest request,
    List<Map<String, Object?>> events,
  ) async {
    _prepareResponse(request);
    for (final event in events) {
      request.response.write('data: ${jsonEncode(event)}\n\n');
    }
    await request.response.close();
  }

  void _prepareResponse(HttpRequest request) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      )
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
  }

  List<Map<String, Object?>> _responsesText(String text, String id) => [
    {
      'type': 'response.created',
      'response': {'id': id, 'model': SidebarFixture.modelId},
    },
    {
      'type': 'response.output_item.added',
      'output_index': 0,
      'item': {
        'id': 'message-$id',
        'type': 'message',
        'role': 'assistant',
        'content': <Object?>[],
      },
    },
    {
      'type': 'response.output_text.delta',
      'output_index': 0,
      'item_id': 'message-$id',
      'content_index': 0,
      'delta': text,
    },
    {
      'type': 'response.output_item.done',
      'output_index': 0,
      'item': {
        'id': 'message-$id',
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': text},
        ],
      },
    },
    {
      'type': 'response.completed',
      'response': {
        'id': id,
        'model': SidebarFixture.modelId,
        'output': [
          {
            'type': 'message',
            'role': 'assistant',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          },
        ],
        'usage': {
          'input_tokens': 11,
          'output_tokens': 5,
          'input_tokens_details': {'cached_tokens': 0},
          'output_tokens_details': {'reasoning_tokens': 0},
        },
      },
    },
  ];

  List<Map<String, Object?>> _responsesToolCall(String id, String callId) {
    final arguments = jsonEncode({
      'questions': [
        {
          'id': 'sidebar-attention-question',
          'header': 'Sidebar fixture',
          'question': 'Keep this synthetic thread waiting for attention?',
          'isOther': false,
          'isSecret': false,
          'options': [
            {'label': 'Continue', 'description': 'Fixture option'},
          ],
        },
      ],
    });
    return [
      {
        'type': 'response.created',
        'response': {'id': id, 'model': SidebarFixture.modelId},
      },
      {
        'type': 'response.output_item.added',
        'output_index': 0,
        'item': {
          'id': callId,
          'type': 'function_call',
          'name': 'request_user_input',
          'call_id': callId,
        },
      },
      {
        'type': 'response.function_call_arguments.delta',
        'output_index': 0,
        'item_id': callId,
        'call_id': callId,
        'delta': arguments,
      },
      {
        'type': 'response.output_item.done',
        'output_index': 0,
        'item': {
          'id': callId,
          'type': 'function_call',
          'name': 'request_user_input',
          'call_id': callId,
          'arguments': arguments,
        },
      },
      {
        'type': 'response.completed',
        'response': {
          'id': id,
          'model': SidebarFixture.modelId,
          'usage': {'input_tokens': 11, 'output_tokens': 3},
        },
      },
    ];
  }

  Future<void> waitForRunning() => _runningReached.future.timeout(
    const Duration(seconds: 30),
    onTimeout: () =>
        throw StateError('Running provider request did not arrive'),
  );

  void releaseRunning() {
    if (!_releaseRunning.isCompleted) _releaseRunning.complete();
  }

  Future<void> close() async {
    releaseRunning();
    await _server.close(force: false);
    await _serve;
    await Future.wait(_handlers.toList(growable: false));
  }
}
