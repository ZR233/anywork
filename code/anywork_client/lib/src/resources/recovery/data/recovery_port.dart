import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/recovery_state.dart';
import '../domain/recovery_values.dart';
import 'recovery_frames.dart';
import 'recovery_reads.dart';

abstract interface class RecoveryPort {
  Future<FeedConnection<RecoveryFrame>> openRecovery();
  Future<RecoveryReadConnection> openRecoveryRead(
    RecoveryReadRef reference, {required ProductReadOrigin origin});
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {required ProductReadOrigin origin});
  Future<RecoveryReadTarget> retry();
  Future<void> cleanupWorktree(
    WorktreeOwner ownerKind, String ownerThreadId, int expectedLeaseRevision);
}

abstract interface class RecoveryReadConnection {
  Future<RecoveryReadHeader> header();
  Future<RecoveryEntryPage> entries({int offset = 0, int limit = 32});
  Future<RecoveryEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupIssue(String issueId);
  Future<RecoveryIssueReadPage> issues(int listId, {int offset = 0, int limit = 32});
  Future<TextReadPage> changedFiles(int listId, {int offset = 0, int limit = 32});
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
