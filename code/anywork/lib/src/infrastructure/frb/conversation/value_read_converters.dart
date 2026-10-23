import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/read/values.dart' as native;
import '../../../rust/api/studio/types/thread_stream.dart' as legacy;
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import 'identity_converters.dart';
import 'scalar_converters.dart';

MetricsIdentityReadHeader metricsIdentityHeaderFromBridge(native.BridgeMetricsIdentityReadHeader value, {required ReadScopeIdentity expectedScope}) => MetricsIdentityReadHeader(
  scope: checkedReadScope(value.scope, expectedScope), turnId: readTextFromBridge(value.turnId), attemptId: nullableReadText(value.attemptId),
);

ContextReadHeader contextHeaderFromBridge(native.BridgeContextReadHeader value, {required ReadScopeIdentity expectedScope}) => ContextReadHeader(
  scope: checkedReadScope(value.scope, expectedScope),
  frozenModelId: nullableReadText(value.frozenModelId), promptCachePolicy: nullableReadText(value.promptCachePolicy),
  estimatedCostCount: exactU64(value.estimatedCostCount, 'context cost count'),
  estimatedCacheSavingCount: exactU64(value.estimatedCacheSavingCount, 'context saving count'),
);

CostPage costPageFromBridge(native.BridgeCostPage value, {required ReadScopeIdentity expectedScope}) => CostPage(
  scope: checkedReadScope(value.scope, expectedScope), offset: exactU64(value.offset, 'cost page offset'), total: exactU64(value.total, 'cost page total'),
  items: List.unmodifiable([
    for (final item in value.items) CostReadItem(index: exactU64(item.index, 'cost index'), currency: readTextFromBridge(item.currency), amount: item.amount),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next cost page offset'),
);

ThreadConfigurationReadHeader configurationHeaderFromBridge(native.BridgeConfigurationReadHeader value, {required ReadScopeIdentity expectedScope}) => ThreadConfigurationReadHeader(
  scope: checkedReadScope(value.scope, expectedScope),
  route: value.route == null ? null : ModelRouteReadValue(
    accountId: readTextFromBridge(value.route!.accountId), modelId: readTextFromBridge(value.route!.modelId),
    effort: nullableReadText(value.route!.effort), revision: exactU64(value.route!.revision, 'model route revision'),
    available: value.route!.available, unavailableReason: nullableReadText(value.route!.unavailableReason),
  ),
  activeSkillCount: exactU64(value.activeSkillCount, 'active skill count'),
);

SkillNamePage skillNamePageFromBridge(native.BridgeSkillNamePage value, {required ReadScopeIdentity expectedScope}) => SkillNamePage(
  scope: checkedReadScope(value.scope, expectedScope), offset: exactU64(value.offset, 'skill name page offset'), total: exactU64(value.total, 'skill name page total'),
  items: List.unmodifiable([
    for (final item in value.items) SkillNameReadItem(index: exactU64(item.index, 'skill name index'), name: readTextFromBridge(item.name)),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next skill name page offset'),
);

TodoReadHeader todoHeaderFromBridge(native.BridgeTodoReadHeader value, {required ReadScopeIdentity expectedScope}) => TodoReadHeader(
  scope: checkedReadScope(value.scope, expectedScope), callId: nullableReadText(value.callId), agentId: nullableReadText(value.agentId),
  path: nullableReadText(value.path), parentPath: nullableReadText(value.parentPath), explanation: nullableReadText(value.explanation),
  itemCount: exactU64(value.itemCount, 'Todo item count'),
);

TodoItemPage todoItemPageFromBridge(native.BridgeTodoItemPage value, {required ReadScopeIdentity expectedScope}) => TodoItemPage(
  scope: checkedReadScope(value.scope, expectedScope), offset: exactU64(value.offset, 'Todo page offset'), total: exactU64(value.total, 'Todo page total'),
  items: List.unmodifiable([
    for (final item in value.items) TodoReadItem(index: exactU64(item.index, 'Todo index'), step: readTextFromBridge(item.step), status: switch (item.status) {
      legacy.BridgeTodoStatus.pending => TodoItemStatus.pending,
      legacy.BridgeTodoStatus.inProgress => TodoItemStatus.inProgress,
      legacy.BridgeTodoStatus.completed => TodoItemStatus.completed,
    }),
  ]),
  nextOffset: nullableU64(value.nextOffset, 'next Todo page offset'),
);

WorkflowReadHeader workflowHeaderFromBridge(native.BridgeWorkflowReadHeader value, {required ReadScopeIdentity expectedScope}) => WorkflowReadHeader(
  scope: checkedReadScope(value.scope, expectedScope), revision: exactU64(value.revision, 'workflow revision'),
  currentRun: value.currentRun == null ? null : WorkflowRunReadValue(
    lineageId: readTextFromBridge(value.currentRun!.lineageId), runId: readTextFromBridge(value.currentRun!.runId),
    modeId: readTextFromBridge(value.currentRun!.modeId), graphRevision: exactU64(value.currentRun!.graphRevision, 'workflow graph revision'),
    graphHash: readTextFromBridge(value.currentRun!.graphHash), lifecycle: workflowLifecycleFromBridge(value.currentRun!.lifecycle),
    currentStateId: readTextFromBridge(value.currentRun!.currentStateId),
    startedAt: exactI64(value.currentRun!.startedAt, 'workflow started Unix seconds'),
    updatedAt: exactI64(value.currentRun!.updatedAt, 'workflow updated Unix seconds'),
    currentStateTitle: readTextFromBridge(value.currentRun!.currentStateTitle), modeDisplayName: readTextFromBridge(value.currentRun!.modeDisplayName), modeDeleted: value.currentRun!.modeDeleted,
  ),
);

PlanDocumentReadHeader planDocumentHeaderFromBridge(native.BridgePlanDocumentReadHeader value, {required ReadScopeIdentity expectedScope}) => PlanDocumentReadHeader(
  scope: checkedReadScope(value.scope, expectedScope), version: exactU64(value.version, 'Plan document version'), contentHash: value.contentHash,
);

PlanDocumentValue planDocumentFromBridge(native.BridgePlanDocumentValue value, {required ReadScopeIdentity expectedScope}) => PlanDocumentValue(
  scope: checkedReadScope(value.scope, expectedScope), version: exactU64(value.version, 'Plan document version'), contentHash: value.contentHash,
  // Retain the original markdown, including the writer-preserved whitespace.
  markdown: value.markdown,
);
