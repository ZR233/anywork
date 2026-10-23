import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/read/execution.dart' as native;
import '../../../rust/api/studio/types/thread_activity.dart' as activity;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'scalar_converters.dart';

ActivityReadHeader activityHeaderFromBridge(native.BridgeActivityReadHeader value, {required ReadScopeIdentity expectedScope}) => ActivityReadHeader(
  scope: checkedReadScope(value.scope, expectedScope),
  threadId: readTextFromBridge(value.threadId), identity: readTextFromBridge(value.identity), turnId: readTextFromBridge(value.turnId),
  revision: exactU64(value.revision, 'activity revision'),
  inputId: nullableReadText(value.inputId), attemptId: nullableReadText(value.attemptId),
  kind: activityKindFromBridge(value.kind), summary: readTextFromBridge(value.summary),
  summaryTruncated: value.summaryTruncated,
  count: value.count, background: value.background,
  activeCount: exactU64(value.activeCount, 'activity active count'),
  latestStarted: value.latestStarted == null ? null : _tool(value.latestStarted!),
);

ActivityToolReadItem _tool(native.BridgeActivityToolReadItem value) => ActivityToolReadItem(
  callId: readTextFromBridge(value.callId), taskId: nullableReadText(value.taskId),
  name: readTextFromBridge(value.name), summary: readTextFromBridge(value.summary),
  arguments: _arguments(value.arguments), state: _state(value.state),
  ordinal: nullableU64(value.ordinal, 'activity tool ordinal'),
  startedAt: nullableI64(value.startedAt, 'activity tool started Unix seconds'),
  wait: value.wait == null ? null : _wait(value.wait!),
);

IndexedActivityToolReadItem _indexedTool(native.BridgeIndexedActivityToolReadItem value) => IndexedActivityToolReadItem(
  index: exactU64(value.index, 'activity tool list index'),
  callId: readTextFromBridge(value.callId), taskId: nullableReadText(value.taskId),
  name: readTextFromBridge(value.name), summary: readTextFromBridge(value.summary),
  arguments: _arguments(value.arguments), state: _state(value.state),
  ordinal: nullableU64(value.ordinal, 'activity tool ordinal'),
  startedAt: nullableI64(value.startedAt, 'activity tool started Unix seconds'),
  wait: value.wait == null ? null : _wait(value.wait!),
);

ThreadActivityArgumentsKind _arguments(activity.BridgeThreadActivityArguments value) => switch (value) {
  activity.BridgeThreadActivityArguments.commandLine => ThreadActivityArgumentsKind.commandLine,
  activity.BridgeThreadActivityArguments.opaque => ThreadActivityArgumentsKind.opaque,
  activity.BridgeThreadActivityArguments.streaming => ThreadActivityArgumentsKind.streaming,
  activity.BridgeThreadActivityArguments.unavailable => ThreadActivityArgumentsKind.unavailable,
};

ThreadActivityToolState _state(activity.BridgeThreadActivityToolState value) => switch (value) {
  activity.BridgeThreadActivityToolState.running => ThreadActivityToolState.running,
  activity.BridgeThreadActivityToolState.awaitingApproval => ThreadActivityToolState.awaitingApproval,
  activity.BridgeThreadActivityToolState.cancelling => ThreadActivityToolState.cancelling,
  activity.BridgeThreadActivityToolState.finished => ThreadActivityToolState.finished,
};

WaitReadValue _wait(native.BridgeWaitReadValue value) => WaitReadValue(
  intent: switch (value.intent) {
    native.BridgeWaitReadIntent_Events(:final targetCount, :final timeoutMs) => WaitReadIntent.events(targetCount: exactU64(targetCount, 'wait target count'), timeoutMs: exactU64(timeoutMs, 'wait timeout milliseconds')),
    native.BridgeWaitReadIntent_Timer(:final durationMs) => WaitReadIntent.timer(durationMs: exactU64(durationMs, 'wait timer milliseconds')),
  },
  state: waitStateFromBridge(value.state),
  messagesReady: value.messagesReady,
);

ActivityToolPage activityToolPageFromBridge(native.BridgeActivityToolPage value, {required ReadScopeIdentity expectedScope}) => ActivityToolPage(
  scope: checkedReadScope(value.scope, expectedScope),
  offset: exactU64(value.offset, 'activity tool page offset'), total: exactU64(value.total, 'activity tool page total'),
  items: List.unmodifiable(value.items.map(_indexedTool)), nextOffset: nullableU64(value.nextOffset, 'next activity tool page offset'),
);

WaitTargetPage waitTargetPageFromBridge(native.BridgeWaitTargetPage value, {required ReadScopeIdentity expectedScope}) => WaitTargetPage(
  scope: checkedReadScope(value.scope, expectedScope),
  offset: exactU64(value.offset, 'wait target page offset'), total: exactU64(value.total, 'wait target page total'),
  items: List.unmodifiable([
    for (final item in value.items) WaitTargetReadItem(
      index: exactU64(item.index, 'wait target index'), taskId: readTextFromBridge(item.taskId),
      toolName: nullableReadText(item.toolName), summary: nullableReadText(item.summary),
      summaryTruncated: item.summaryTruncated, status: item.status == null ? null : waitTargetStatusFromBridge(item.status!),
    ),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next wait target page offset'),
);
