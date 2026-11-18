import 'dart:convert';

import 'chat_models.dart';
import 'thread_activity_models.dart';
import 'thread_directory_models.dart' show ThreadStatusView;
import 'thread_models.dart' show ThreadTextChannel;
import 'timeline_models.dart';
import 'thread_wait_models.dart';
import 'runtime_models.dart';
import '../studio/thread_frames.dart';

const currentProtocolVersion = 1;

final class CurrentRevision {
  const CurrentRevision({required this.ownerId, required this.revision});
  final String ownerId;
  final int revision;
  @override
  bool operator ==(Object other) =>
      other is CurrentRevision &&
      ownerId == other.ownerId &&
      revision == other.revision;
  @override
  int get hashCode => Object.hash(ownerId, revision);
}

enum CurrentContentRole { reasoning, response, toolArguments, toolOutput }

enum CurrentTurnPhase {
  preparing,
  thinking,
  responding,
  planning,
  runningTool,
  persisting,
}

final class CurrentContentPreview {
  const CurrentContentPreview({
    required this.id,
    required this.role,
    this.textChannel,
    required this.text,
    required this.reference,
  });
  final String id;
  final CurrentContentRole role;
  final ThreadTextChannel? textChannel;
  final String text;
  final CurrentContentRef reference;
}

final class CurrentAtom {
  CurrentAtom({
    required this.id,
    required this.source,
    this.sourceState,
    this.sourceOrder,
    required this.kind,
    required this.delivery,
    required this.lifecycle,
    this.turnId,
    this.attemptId,
    this.tool,
    this.wait,
    this.textChannel,
    this.startedAt,
    this.finishedAt,
    this.contentPresent,
    required List<CurrentAtomContent> contents,
  }) : contents = List.unmodifiable(contents);
  final String id;
  final ChatSourceId source;
  final ChatSourceState? sourceState;
  final int? sourceOrder;
  final ChatAtomKind kind;
  final ChatDeliveryKind delivery;
  final ChatAtomLifecycle lifecycle;
  final String? turnId;
  final String? attemptId;
  final ChatToolIdentity? tool;
  final ThreadWaitPresentationView? wait;
  final ThreadTextChannel? textChannel;
  final int? startedAt;
  final int? finishedAt;
  final bool? contentPresent;
  final List<CurrentAtomContent> contents;
}

final class CurrentAtomContent {
  const CurrentAtomContent({required this.role, required this.reference});
  final ChatContentRole role;
  final CurrentContentRef reference;
}

CurrentAtom decodeCurrentAtomPayload(CurrentPayloadData payload) {
  final bytes = switch (payload) {
    InlineCurrentPayload(:final bytes) => bytes,
    DeferredCurrentPayload() => throw const FormatException(
      'Deferred Current atom requires a collection body read',
    ),
  };
  final value = jsonDecode(utf8.decode(bytes));
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Current atom must be an object');
  }
  final lifecycle = _object(value['lifecycle'], 'lifecycle');
  final waitValue = value['wait'];
  final sourceState = value['sourceState'];
  return CurrentAtom(
    id: _string(value['id'], 'id'),
    source: _source(value['source'], 'source'),
    sourceState: sourceState == null
        ? null
        : _sourceState(_object(sourceState, 'sourceState')),
    sourceOrder: value['sourceOrder'] as int?,
    kind: ChatAtomKind.values.byName(_string(value['kind'], 'kind')),
    delivery: ChatDeliveryKind.values.byName(
      _string(value['delivery'], 'delivery'),
    ),
    lifecycle: switch (_string(lifecycle['kind'], 'lifecycle.kind')) {
      'active' => ActiveChatAtom(
        started: _position(lifecycle['started'], 'lifecycle.started'),
        status: ChatActiveStatus.values.byName(
          _string(lifecycle['status'], 'lifecycle.status'),
        ),
      ),
      'terminal' => TerminalChatAtom(
        started: _position(lifecycle['started'], 'lifecycle.started'),
        ended: _position(lifecycle['ended'], 'lifecycle.ended'),
        outcome: ChatTerminalOutcome.values.byName(
          _string(lifecycle['outcome'], 'lifecycle.outcome'),
        ),
      ),
      final kind => throw FormatException('Unknown lifecycle: $kind'),
    },
    turnId: value['turnId'] as String?,
    attemptId: value['attemptId'] as String?,
    tool: switch (value['tool']) {
      null => null,
      final Map<String, dynamic> tool => ChatToolIdentity(
        callId: _string(tool['callId'], 'tool.callId'),
        name: _string(tool['name'], 'tool.name'),
      ),
      _ => throw const FormatException('Invalid tool identity'),
    },
    wait: waitValue == null ? null : _wait(_object(waitValue, 'wait')),
    textChannel: switch (value['textChannel']) {
      null => null,
      'final' => ThreadTextChannel.finalAnswer,
      final String channel => ThreadTextChannel.values.byName(channel),
      _ => throw const FormatException('Invalid text channel'),
    },
    startedAt: value['startedAt'] as int?,
    finishedAt: value['finishedAt'] as int?,
    contentPresent: value['contentPresent'] as bool?,
    contents: [
      for (final content in _list(value['contents'], 'contents'))
        CurrentAtomContent(
          role: ChatContentRole.values.byName(
            _string(_object(content, 'content')['role'], 'content.role'),
          ),
          reference: _currentRef(
            _object(content, 'content')['reference'],
            'content.reference',
          ),
        ),
    ],
  );
}

ChatSourceState decodeCurrentSourcePayload(CurrentPayloadData payload) {
  final bytes = switch (payload) {
    InlineCurrentPayload(:final bytes) => bytes,
    DeferredCurrentPayload() => throw const FormatException(
      'Deferred Current source requires a collection body read',
    ),
  };
  final value = jsonDecode(utf8.decode(bytes));
  return _sourceState(_object(value, 'source'));
}

TimelineTodoListUpdate decodeCurrentTodoState(Object? value) {
  final object = _object(value, 'todo');
  return TimelineTodoListUpdate(
    callId: _string(object['callId'], 'todo.callId'),
    agentId: object['agentId'] as String?,
    path: object['path'] as String?,
    parentPath: object['parentPath'] as String?,
    explanation: object['explanation'] as String?,
    items: [
      for (final item in _list(object['items'], 'todo.items'))
        TimelineTodoItem(
          step: _string(_object(item, 'todo.item')['step'], 'todo.item.step'),
          status: _string(
            _object(item, 'todo.item')['status'],
            'todo.item.status',
          ),
        ),
    ],
  );
}

WorkflowRuntimeView decodeCurrentWorkflowState(Object? value) {
  final object = _object(value, 'workflow');
  final run = object['currentRun'];
  return WorkflowRuntimeView(
    revision: object['revision'] as int,
    currentRun: run == null
        ? null
        : switch (_object(run, 'workflow.currentRun')) {
            final run => WorkflowRunView(
              lineageId: _string(
                run['lineageId'],
                'workflow.currentRun.lineageId',
              ),
              runId: _string(run['runId'], 'workflow.currentRun.runId'),
              modeId: _string(run['modeId'], 'workflow.currentRun.modeId'),
              graphRevision: run['graphRevision'] as int,
              graphHash: _string(
                run['graphHash'],
                'workflow.currentRun.graphHash',
              ),
              currentStateId: _string(
                run['currentStateId'],
                'workflow.currentRun.currentStateId',
              ),
              terminal:
                  _string(run['lifecycle'], 'workflow.currentRun.lifecycle') ==
                  'terminal',
              startedAt: DateTime.fromMillisecondsSinceEpoch(
                (run['startedAt'] as int) * 1000,
              ),
              updatedAt: DateTime.fromMillisecondsSinceEpoch(
                (run['updatedAt'] as int) * 1000,
              ),
              currentStateTitle: run['currentStateTitle'] as String? ?? '',
              modeDisplayName: run['modeDisplayName'] as String? ?? '',
              modeDeleted: run['modeDeleted'] as bool? ?? false,
            ),
          },
  );
}

ThreadActivityToolEntry decodeCurrentActivityToolState(Object? value) {
  final object = _object(value, 'activityTool');
  return ThreadActivityToolEntry(
    callId: _string(object['callId'], 'activityTool.callId'),
    taskId: object['taskId'] as String?,
    name: _string(object['name'], 'activityTool.name'),
    summary: _string(object['summary'], 'activityTool.summary'),
    arguments: ThreadActivityArgumentsKind.values.byName(
      _string(object['arguments'], 'activityTool.arguments'),
    ),
    state: ThreadActivityToolState.values.byName(
      _string(object['state'], 'activityTool.state'),
    ),
    ordinal: object['ordinal'] as int?,
    startedAt: object['startedAt'] as int?,
    wait: object['wait'] == null
        ? null
        : _wait(_object(object['wait'], 'activityTool.wait')),
  );
}

Map<String, dynamic> _object(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$field must be an object');
}

List<dynamic> _list(Object? value, String field) {
  if (value is List<dynamic>) return value;
  throw FormatException('$field must be a list');
}

String _string(Object? value, String field) {
  if (value is String) return value;
  throw FormatException('$field must be a string');
}

ChatSourceId _source(Object? value, String field) {
  final source = _object(value, field);
  return switch (_string(source['kind'], '$field.kind')) {
    'foregroundTurn' => ForegroundTurnChatSource(
      turnId: _string(source['turnId'], '$field.turnId'),
    ),
    'input' => InputChatSource(
      inputId: _string(source['inputId'], '$field.inputId'),
    ),
    'inboxMessage' => InboxMessageChatSource(
      sourceId: _string(source['sourceId'], '$field.sourceId'),
      messageId: _string(source['messageId'], '$field.messageId'),
    ),
    'backgroundResult' => BackgroundResultChatSource(
      messageId: _string(source['messageId'], '$field.messageId'),
    ),
    'operation' => OperationChatSource(
      operationId: _string(source['operationId'], '$field.operationId'),
    ),
    'receipt' => ReceiptChatSource(
      receiptId: _string(source['receiptId'], '$field.receiptId'),
    ),
    final kind => throw FormatException('Unknown source: $kind'),
  };
}

ChatSourceState _sourceState(Map<String, dynamic> value) => ChatSourceState(
  source: _source(value['source'], 'sourceState.source'),
  lifecycle: switch (_object(value['lifecycle'], 'sourceState.lifecycle')) {
    final lifecycle => switch (_string(
      lifecycle['kind'],
      'sourceState.lifecycle.kind',
    )) {
      'unknown' => const UnknownChatSource(),
      'active' => const ActiveChatSource(),
      'ended' => EndedChatSource(
        outcome: ChatTerminalOutcome.values.byName(
          _string(lifecycle['outcome'], 'sourceState.lifecycle.outcome'),
        ),
      ),
      final kind => throw FormatException('Unknown source lifecycle: $kind'),
    },
  },
  started: _position(value['started'], 'sourceState.started'),
  ended: _position(value['ended'], 'sourceState.ended'),
);

ChatFactPosition? _position(Object? value, String field) {
  if (value == null) return null;
  final position = _object(value, field);
  return ChatFactPosition(
    effectSeq: position['effectSeq'] as int,
    suborder: position['suborder'] as int,
  );
}

CurrentContentRef _currentRef(Object? value, String field) {
  final reference = _object(value, field);
  return CurrentContentRef(
    ownerId: _string(reference['ownerId'], '$field.ownerId'),
    domain: _string(reference['domain'], '$field.domain'),
    entityId: _string(reference['entityId'], '$field.entityId'),
    contentKey: _string(reference['contentKey'], '$field.contentKey'),
    generation: _string(reference['generation'], '$field.generation'),
  );
}

ThreadWaitPresentationView _wait(Map<String, dynamic> value) {
  final intent = _object(value['intent'], 'wait.intent');
  final data = _object(intent['data'], 'wait.intent.data');
  return ThreadWaitPresentationView(
    state: ThreadWaitStateView.values.byName(
      _string(value['state'], 'wait.state'),
    ),
    messagesReady: value['messagesReady'] as bool?,
    intent: switch (_string(intent['kind'], 'wait.intent.kind')) {
      'events' => ThreadWaitEventsIntentView(
        timeoutMs: data['timeoutMs'] as int,
        targets: [
          for (final target in _list(data['targets'], 'wait.targets'))
            _waitTarget(_object(target, 'wait.target')),
        ],
      ),
      'timer' => ThreadWaitTimerIntentView(
        durationMs: data['durationMs'] as int,
      ),
      final kind => throw FormatException('Unknown wait intent: $kind'),
    },
  );
}

ThreadWaitTargetView _waitTarget(Map<String, dynamic> value) =>
    ThreadWaitTargetView(
      taskId: _string(value['taskId'], 'wait.target.taskId'),
      toolName: value['toolName'] as String?,
      summary: value['summary'] as String?,
      summaryTruncated: value['summaryTruncated'] as bool? ?? false,
      status: value['status'] == null
          ? null
          : ThreadWaitTargetStatusView.values.byName(
              _string(value['status'], 'wait.target.status'),
            ),
    );

final class CurrentActivityHead {
  const CurrentActivityHead({
    required this.id,
    required this.kind,
    required this.summary,
    this.thinkingSummary,
    this.thinkingSeconds,
    required this.toolCount,
    required this.backgroundToolCount,
    this.latestTool,
  });
  final String id;
  final ThreadActivityKind kind;
  final String summary;
  final String? thinkingSummary;
  final int? thinkingSeconds;
  final int toolCount;
  final int backgroundToolCount;
  final CurrentToolHead? latestTool;
}

final class CurrentToolHead {
  const CurrentToolHead({
    required this.callId,
    required this.name,
    required this.state,
  });
  final String callId;
  final String name;
  final ThreadActivityToolState state;
}

final class CurrentTurnHead {
  const CurrentTurnHead({required this.id, required this.phase});
  final String id;
  final CurrentTurnPhase phase;
}

final class CurrentProjection {
  CurrentProjection({
    required this.logicalStatus,
    required this.executionPresent,
    this.active,
    this.activeTurn,
    required List<ChatSourceState> sources,
    required List<CurrentAtom> atoms,
    this.plan,
    this.interactions,
    required List<CurrentContentPreview> previews,
    required List<CurrentCollectionRef> collections,
  }) : sources = List.unmodifiable(sources),
       atoms = List.unmodifiable(atoms),
       previews = List.unmodifiable(previews),
       collections = List.unmodifiable(collections);
  final ThreadStatusView logicalStatus;
  final bool executionPresent;
  final CurrentActivityHead? active;
  final CurrentTurnHead? activeTurn;
  final List<ChatSourceState> sources;
  final List<CurrentAtom> atoms;
  final CurrentPlanHead? plan;
  final CurrentCollectionRef? interactions;
  final List<CurrentContentPreview> previews;
  final List<CurrentCollectionRef> collections;
}

final class CurrentView {
  const CurrentView({
    required this.revision,
    required this.state,
    required this.projection,
  });
  final CurrentRevision revision;
  final ThreadSnapshotFrame state;
  final CurrentProjection projection;
}

sealed class CurrentFrame {
  const CurrentFrame();
}

final class ResetCurrentFrame extends CurrentFrame {
  const ResetCurrentFrame(this.view);
  final CurrentView view;
}

final class NotificationCurrentFrame extends CurrentFrame {
  const NotificationCurrentFrame({
    required this.revision,
    required this.notification,
  });
  final CurrentRevision revision;
  final ThreadNotificationFrame notification;
}

final class ProjectionCurrentFrame extends CurrentFrame {
  const ProjectionCurrentFrame({
    required this.revision,
    required this.projection,
  });
  final CurrentRevision revision;
  final CurrentProjection projection;
}
