import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

import '../domain/recovery_values.dart';

part 'recovery_reads.freezed.dart';

@freezed
abstract class RecoveryReadHeader with _$RecoveryReadHeader {
  const factory RecoveryReadHeader({required TypedListRef issues}) = _RecoveryReadHeader;
}

@Freezed(toStringOverride: false)
abstract class WorktreeRecoveryPreviewRead with _$WorktreeRecoveryPreviewRead {
  const factory WorktreeRecoveryPreviewRead({
    required WorktreeOwner ownerKind,
    required ReadText ownerThreadId,
    required int leaseRevision,
    required ReadText state,
    required ReadText repositoryRoot,
    required ReadText path,
    required ReadText branch,
    required ReadText baseCommit,
    required ReadText? headCommit,
    required bool dirty,
    required TypedListRef changedFiles,
  }) = _WorktreeRecoveryPreviewRead;
}

@Freezed(toStringOverride: false)
abstract class RecoveryIssueRead with _$RecoveryIssueRead {
  const factory RecoveryIssueRead({
    required ReadText id,
    required RecoveryScope scope,
    required RecoveryCategory category,
    required RecoveryAction action,
    required ReadText? projectId,
    required ReadText? threadId,
    required ReadText message,
    required WorktreeRecoveryPreviewRead? worktree,
  }) = _RecoveryIssueRead;
}

@Freezed(toStringOverride: false)
abstract class RecoveryEntityRead with _$RecoveryEntityRead {
  const factory RecoveryEntityRead({
    required ProductEntityRef reference,
    required RecoveryIssueRead value,
  }) = _RecoveryEntityRead;
}

@freezed
final class RecoveryEntryPage with _$RecoveryEntryPage {
  RecoveryEntryPage({
    required this.collection,
    required this.offset,
    required List<ProductEntityRef> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final ProductCollectionRef collection;
  final int offset;
  final List<ProductEntityRef> items;
  final int? nextOffset;
}

@Freezed(toStringOverride: false)
final class RecoveryIssueReadPage with _$RecoveryIssueReadPage {
  RecoveryIssueReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<RecoveryIssueRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<RecoveryIssueRead> items;
  final int? nextOffset;
}
