import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'mcp_reads.freezed.dart';

@freezed
abstract class McpHealthRead with _$McpHealthRead {
  const factory McpHealthRead({
    required TypedListRef mcpServers,
    required TypedListRef activeMcpServers,
  }) = _McpHealthRead;
}

@Freezed(toStringOverride: false)
abstract class McpReadHeader with _$McpReadHeader {
  const factory McpReadHeader({
    required ReadText desiredConfigFingerprint,
    required ReadText appliedConfigFingerprint,
    required McpHealthRead health,
  }) = _McpReadHeader;
}

@Freezed(toStringOverride: false)
sealed class McpServerStateRead with _$McpServerStateRead {
  const factory McpServerStateRead.disabled({required ReadText message}) =
      DisabledMcpServerStateRead;
  const factory McpServerStateRead.missingCredential({required ReadText message}) =
      MissingCredentialMcpServerStateRead;
  const factory McpServerStateRead.checking({required ReadText message}) =
      CheckingMcpServerStateRead;
  const factory McpServerStateRead.available({
    required int checkedAt,
    required int toolCount,
  }) = AvailableMcpServerStateRead;
  const factory McpServerStateRead.unavailable({
    required int checkedAt,
    required SourceStateErrorRead error,
  }) = UnavailableMcpServerStateRead;
}

@Freezed(toStringOverride: false)
abstract class McpServerRead with _$McpServerRead {
  const factory McpServerRead({
    required ReadText id,
    required ReadText transport,
    required ReadText endpoint,
    required ReadText sourceKind,
    required ReadText mutationPolicy,
    required McpServerStateRead state,
  }) = _McpServerRead;
}

@Freezed(toStringOverride: false)
abstract class McpEntityRead with _$McpEntityRead {
  const factory McpEntityRead({
    required ProductEntityRef reference,
    required McpServerRead value,
  }) = _McpEntityRead;
}

@freezed
final class McpEntryPage with _$McpEntryPage {
  McpEntryPage({
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
final class McpServerReadPage with _$McpServerReadPage {
  McpServerReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<McpServerRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<McpServerRead> items;
  final int? nextOffset;
}
