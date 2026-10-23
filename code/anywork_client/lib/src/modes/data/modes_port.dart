import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../operations.dart';
import '../../../resources.dart';
import '../../../resources_ports.dart' show FeedConnection;
import '../domain/mode_documents.dart';
import '../domain/mode_values.dart';
import '../domain/modes_state.dart';
import 'modes_frames.dart';

part 'modes_port.freezed.dart';

abstract interface class ModesPort {
  Future<FeedConnection<ModeCatalogFrame>> openModeCatalog();
  Future<ModeCatalogReadConnection> openModeCatalogRead(ModeCatalogReadRef reference, {required ProductReadOrigin origin});
  Future<ModeDefinitionSnapshot> readDefinition(String modeId);
  Future<ModeValidationResult> validate(String rawJson);
  Future<String> schema();
  Future<WorkflowPreviewSnapshot> preview(WorkflowPreviewRequest request);
  Future<ModeDefinitionCommandReply> save(ModeDocument document, {required int expectedRevision, required OperationId operationId});
  Future<ModeDefinitionCommandReply> delete(String modeId, {required int expectedRevision, required OperationId operationId});
  Future<ModeDefinitionCommandReply> reload({required int expectedRevision, required OperationId operationId});
}

abstract interface class ModeCatalogReadConnection {
  Future<ModeCatalogReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<ModeCatalogEntryPage> entries({int offset = 0, int limit = 32});
  Future<ModeCatalogEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupMode(ThreadModeId mode);
  Future<ThreadModeDescriptorReadPage> modes(int listId, {int offset = 0, int limit = 32});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

@Freezed(toStringOverride: false)
abstract class ModeDefinitionCommandReply with _$ModeDefinitionCommandReply {
  const factory ModeDefinitionCommandReply({required ModeCatalogReadTarget catalog, required ModeDefinitionSnapshot? definition, required CommitReceipt receipt}) = _ModeDefinitionCommandReply;
}

@freezed
abstract class ModeCatalogReadHeader with _$ModeCatalogReadHeader {
  const factory ModeCatalogReadHeader({required int revision, required TypedListRef modes}) = _ModeCatalogReadHeader;
}

@Freezed(toStringOverride: false)
abstract class ThreadModeDescriptorRead with _$ThreadModeDescriptorRead {
  const factory ThreadModeDescriptorRead({required ThreadModeId id, required ReadText displayName, required ReadText description, required int order, required bool hasWorkflow, required bool readOnly}) = _ThreadModeDescriptorRead;
}

@freezed
abstract class ModeCatalogEntryPage with _$ModeCatalogEntryPage {
  const factory ModeCatalogEntryPage({required ProductCollectionRef collection, required int offset, required List<ProductEntityRef> items, required int? nextOffset}) = _ModeCatalogEntryPage;
}

@Freezed(toStringOverride: false)
abstract class ModeCatalogEntityRead with _$ModeCatalogEntityRead {
  const factory ModeCatalogEntityRead({required ProductEntityRef reference, required ThreadModeDescriptorRead value}) = _ModeCatalogEntityRead;
}

@Freezed(toStringOverride: false)
abstract class ThreadModeDescriptorReadPage with _$ThreadModeDescriptorReadPage {
  const factory ThreadModeDescriptorReadPage({required int listId, required int offset, required int total, required List<ThreadModeDescriptorRead> items, required int? nextOffset}) = _ThreadModeDescriptorReadPage;
}
