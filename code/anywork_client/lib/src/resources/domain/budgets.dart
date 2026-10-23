import 'package:freezed_annotation/freezed_annotation.dart';

part 'budgets.freezed.dart';

enum ResourceKind {
  chatHandle,
  pendingOperation,
  draft,
  attachment,
  observer,
  readModel,
}

enum ResourcePhase { opening, active, retiring, unresolved }

@freezed
abstract class ResourceUsage with _$ResourceUsage {
  const factory ResourceUsage({
    required ResourceKind kind,
    required String owner,
    required ResourcePhase phase,
  }) = _ResourceUsage;
}

enum BudgetLimitKind {
  modelStep,
  toolCall,
  wait,
  wallClock,
  agentCount,
  agentDepth,
  finalization,
}

@freezed
abstract class BudgetUsage with _$BudgetUsage {
  const factory BudgetUsage({
    required int modelSteps,
    required int toolCalls,
    required int waitCalls,
    required int elapsedMs,
  }) = _BudgetUsage;
}

@freezed
abstract class BudgetLimitSnapshot with _$BudgetLimitSnapshot {
  const factory BudgetLimitSnapshot({
    required BudgetLimitKind kind,
    required BudgetUsage usage,
  }) = _BudgetLimitSnapshot;
}
