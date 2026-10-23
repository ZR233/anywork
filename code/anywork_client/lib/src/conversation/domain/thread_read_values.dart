import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';
import 'authoring_values.dart';

part 'thread_read_values.freezed.dart';

@Freezed(toStringOverride: false)
abstract class StorageReadHeader with _$StorageReadHeader {
  const factory StorageReadHeader({
    required ReadScopeIdentity scope,
    required HistoryFault? fault,
    required int faultGeneration,
    required int? acceptedSequence,
    required int? durableSequence,
    required ThreadStorageExecution execution,
    required bool pressurePaused,
    required bool resumeRequired,
    required bool canResume,
    required ReadText? lastError,
  }) = _StorageReadHeader;
}

@Freezed(toStringOverride: false)
abstract class MetricsIdentityReadHeader with _$MetricsIdentityReadHeader {
  const factory MetricsIdentityReadHeader({required ReadScopeIdentity scope, required ReadText turnId, required ReadText? attemptId}) = _MetricsIdentityReadHeader;
}

@Freezed(toStringOverride: false)
abstract class ContextReadHeader with _$ContextReadHeader {
  const factory ContextReadHeader({required ReadScopeIdentity scope, required ReadText? frozenModelId, required ReadText? promptCachePolicy, required int estimatedCostCount, required int estimatedCacheSavingCount}) = _ContextReadHeader;
}

@Freezed(toStringOverride: false)
abstract class CostReadItem with _$CostReadItem {
  const factory CostReadItem({required int index, required ReadText currency, required double amount}) = _CostReadItem;
}

@Freezed(toStringOverride: false)
final class CostPage with _$CostPage {
  CostPage({required this.scope, required this.offset, required this.total,
    required List<CostReadItem> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<CostReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class ModelRouteReadValue with _$ModelRouteReadValue {
  const factory ModelRouteReadValue({required ReadText accountId, required ReadText modelId, required ReadText? effort, required int revision, required bool available, required ReadText? unavailableReason}) = _ModelRouteReadValue;
}

@Freezed(toStringOverride: false)
abstract class ThreadConfigurationReadHeader with _$ThreadConfigurationReadHeader {
  const factory ThreadConfigurationReadHeader({required ReadScopeIdentity scope, required ModelRouteReadValue? route, required int activeSkillCount}) = _ThreadConfigurationReadHeader;
}

@Freezed(toStringOverride: false)
abstract class SkillNameReadItem with _$SkillNameReadItem {
  const factory SkillNameReadItem({required int index, required ReadText name}) = _SkillNameReadItem;
}

@Freezed(toStringOverride: false)
final class SkillNamePage with _$SkillNamePage {
  SkillNamePage({required this.scope, required this.offset, required this.total,
    required List<SkillNameReadItem> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<SkillNameReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class TodoReadHeader with _$TodoReadHeader {
  const factory TodoReadHeader({required ReadScopeIdentity scope, required ReadText? callId, required ReadText? agentId, required ReadText? path, required ReadText? parentPath, required ReadText? explanation, required int itemCount}) = _TodoReadHeader;
}

@Freezed(toStringOverride: false)
abstract class TodoReadItem with _$TodoReadItem {
  const factory TodoReadItem({required int index, required ReadText step, required TodoItemStatus status}) = _TodoReadItem;
}

@Freezed(toStringOverride: false)
final class TodoItemPage with _$TodoItemPage {
  TodoItemPage({required this.scope, required this.offset, required this.total,
    required List<TodoReadItem> items, required this.nextOffset})
      : items = List.unmodifiable(items);
  final ReadScopeIdentity scope;
  final int offset;
  final int total;
  final List<TodoReadItem> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
abstract class WorkflowRunReadValue with _$WorkflowRunReadValue {
  const factory WorkflowRunReadValue({
    required ReadText lineageId,
    required ReadText runId,
    required ReadText modeId,
    required int graphRevision,
    required ReadText graphHash,
    required WorkflowLifecycle lifecycle,
    required ReadText currentStateId,
    required int startedAt,
    required int updatedAt,
    required ReadText currentStateTitle,
    required ReadText modeDisplayName,
    required bool modeDeleted,
  }) = _WorkflowRunReadValue;
}

@Freezed(toStringOverride: false)
abstract class WorkflowReadHeader with _$WorkflowReadHeader {
  const factory WorkflowReadHeader({required ReadScopeIdentity scope, required int revision, required WorkflowRunReadValue? currentRun}) = _WorkflowReadHeader;
}

@freezed
abstract class PlanDocumentReadHeader with _$PlanDocumentReadHeader {
  const factory PlanDocumentReadHeader({required ReadScopeIdentity scope, required int version, required String contentHash}) = _PlanDocumentReadHeader;
}

@Freezed(toStringOverride: false)
abstract class PlanDocumentValue with _$PlanDocumentValue {
  const factory PlanDocumentValue({required ReadScopeIdentity scope, required int version, required String contentHash, required String markdown}) = _PlanDocumentValue;
}
