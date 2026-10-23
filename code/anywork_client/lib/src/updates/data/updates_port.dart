import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/updates_state.dart';
import 'update_task.dart';
import 'updates_frames.dart';
import 'updates_reads.dart';

abstract interface class UpdatesPort {
  Future<FeedConnection<UpdatesFrame>> openUpdates();
  Future<UpdatesReadConnection> openUpdatesRead(UpdatesReadRef reference, {required ProductReadOrigin origin});
  Future<UpdateSummaryReadConnection> openSummary(UpdateSummaryReadRef reference, {required ProductReadOrigin origin});
  Future<UpdateOperationReadConnection> openOperation(UpdateOperationReadRef reference, {required ProductReadOrigin origin});
  Future<UpdateErrorReadConnection> openError(UpdateErrorReadRef reference, {required ProductReadOrigin origin});
  Future<UpdateDetailsReadConnection> openDetails(UpdateDetailsReadRef reference, {required ProductReadOrigin origin});
  Future<UpdateTaskConnection> openUpdateCheck(OperationId operationId);
  Future<UpdateTaskConnection> openAutomaticUpdate(OperationId operationId);
  Future<UpdateTaskConnection> openUpdatePreparation(OperationId operationId,
    {required int expectedRevision, required String version});
}

abstract interface class UpdatesReadConnection {
  Future<UpdatesReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class UpdateSummaryReadConnection {
  Future<UpdateSummaryRead> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class UpdateOperationReadConnection {
  Future<UpdateOperationReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class UpdateErrorReadConnection {
  Future<SourceStateErrorRead> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class UpdateDetailsReadConnection {
  Future<UpdateDetailsRead> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
