import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:anywork_client/resources.dart';

import '../domain/directory_values.dart';

part 'directory_reads.freezed.dart';

@freezed
abstract class ProjectDirectoryReadHeader with _$ProjectDirectoryReadHeader {
  const factory ProjectDirectoryReadHeader({required TypedListRef projects}) = _ProjectDirectoryReadHeader;
}

@freezed
abstract class ThreadDirectoryReadHeader with _$ThreadDirectoryReadHeader {
  const factory ThreadDirectoryReadHeader({required TypedListRef threads,
    required ReadText? nextCursor, required bool hasMore}) = _ThreadDirectoryReadHeader;
}

@freezed
abstract class AgentDirectoryReadHeader with _$AgentDirectoryReadHeader {
  const factory AgentDirectoryReadHeader({required TypedListRef agents}) = _AgentDirectoryReadHeader;
}

@Freezed(toStringOverride: false)
abstract class ProjectRecordRead with _$ProjectRecordRead {
  const factory ProjectRecordRead({required ReadText id, required ReadText name,
    required ReadText path, required ReadText? sshAlias, required int updatedAt}) = _ProjectRecordRead;
}

@Freezed(toStringOverride: false)
abstract class WorkspaceThreadRecordRead with _$WorkspaceThreadRecordRead {
  const factory WorkspaceThreadRecordRead({required ReadText id, required ReadText projectId,
    required ReadText title, required ReadText mode, required ThreadWorkspaceMode workspaceMode,
    required ReadText workspacePath, required ReadText rootThreadId, required ReadText? parentThreadId,
    required ReadText role, required ReadText agentPath, required ThreadStatus status,
    required int createdAt, required int updatedAt, required int? lastUserMessageAt,
    required bool archived}) = _WorkspaceThreadRecordRead;
}

@Freezed(toStringOverride: false)
abstract class AgentBudgetPauseRead with _$AgentBudgetPauseRead {
  const factory AgentBudgetPauseRead({required ReadText turnId, required BudgetLimitSnapshot limit,
    required int pausedAt}) = _AgentBudgetPauseRead;
}

@Freezed(toStringOverride: false)
sealed class AgentStateRead with _$AgentStateRead {
  const factory AgentStateRead.idle({required AgentBudgetPauseRead? budgetPause}) = IdleAgentStateRead;
  const factory AgentStateRead.queued({required ReadText turnId}) = QueuedAgentStateRead;
  const factory AgentStateRead.running({required ReadText turnId}) = RunningAgentStateRead;
  const factory AgentStateRead.waitingTool({required ReadText turnId}) = WaitingToolAgentStateRead;
  const factory AgentStateRead.waitingInteraction({required ReadText turnId,
    required ReadText interactionId}) = WaitingInteractionAgentStateRead;
  const factory AgentStateRead.cancelling({required ReadText turnId}) = CancellingAgentStateRead;
  const factory AgentStateRead.closing({required AgentWorkspaceDisposition workspaceDisposition,
    required ReadText? turnId, required SourceStateErrorRead? error}) = ClosingAgentStateRead;
  const factory AgentStateRead.closed() = ClosedAgentStateRead;
  const factory AgentStateRead.faulted({required SourceStateErrorRead error, required ReadText? turnId,
    required AgentFaultClassification classification}) = FaultedAgentStateRead;
}

@Freezed(toStringOverride: false)
abstract class AgentDirectoryEntryRead with _$AgentDirectoryEntryRead {
  const factory AgentDirectoryEntryRead({required ReadText id, required ReadText threadId,
    required ReadText rootThreadId, required ReadText path, required ReadText? parentPath,
    required ReadText role, required ReadText task, required ReadText? summary,
    required int depth, required AgentStateRead state, required int updatedAt}) = _AgentDirectoryEntryRead;
}

@Freezed(toStringOverride: false)
abstract class ProjectDirectoryEntityRead with _$ProjectDirectoryEntityRead {
  const factory ProjectDirectoryEntityRead({required ProductEntityRef reference,
    required ProjectRecordRead value}) = _ProjectDirectoryEntityRead;
}

@Freezed(toStringOverride: false)
abstract class ThreadDirectoryEntityRead with _$ThreadDirectoryEntityRead {
  const factory ThreadDirectoryEntityRead({required ProductEntityRef reference,
    required WorkspaceThreadRecordRead value}) = _ThreadDirectoryEntityRead;
}

@Freezed(toStringOverride: false)
abstract class AgentDirectoryEntityRead with _$AgentDirectoryEntityRead {
  const factory AgentDirectoryEntityRead({required ProductEntityRef reference,
    required AgentDirectoryEntryRead value}) = _AgentDirectoryEntityRead;
}

@freezed
final class ProjectDirectoryEntryPage with _$ProjectDirectoryEntryPage {
  ProjectDirectoryEntryPage({required this.collection, required this.offset,
    required List<ProductEntityRef> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@freezed
final class ThreadDirectoryEntryPage with _$ThreadDirectoryEntryPage {
  ThreadDirectoryEntryPage({required this.collection, required List<ProductEntityRef> items,
    required this.nextCursor, required this.hasMore}) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final List<ProductEntityRef> items;
  final ReadText? nextCursor;
  final bool hasMore;
}

@freezed
final class AgentDirectoryEntryPage with _$AgentDirectoryEntryPage {
  AgentDirectoryEntryPage({required this.collection, required this.offset,
    required List<ProductEntityRef> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class ProjectRecordReadPage with _$ProjectRecordReadPage {
  ProjectRecordReadPage({required this.listId, required this.offset, required this.total,
    required List<ProjectRecordRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<ProjectRecordRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class WorkspaceThreadRecordReadPage with _$WorkspaceThreadRecordReadPage {
  WorkspaceThreadRecordReadPage({required this.listId, required this.offset, required this.total,
    required List<WorkspaceThreadRecordRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<WorkspaceThreadRecordRead> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class AgentDirectoryEntryReadPage with _$AgentDirectoryEntryReadPage {
  AgentDirectoryEntryReadPage({required this.listId, required this.offset, required this.total,
    required List<AgentDirectoryEntryRead> items, required this.nextOffset}) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<AgentDirectoryEntryRead> items;
  final int? nextOffset;
}
