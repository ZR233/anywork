import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/resources.dart';

part 'lsp_reads.freezed.dart';

@freezed
abstract class LspReadHeader with _$LspReadHeader {
  const factory LspReadHeader({
    required TypedListRef lspServers,
    required TypedListRef activeLspServers,
  }) = _LspReadHeader;
}

@Freezed(toStringOverride: false)
sealed class LspActivityRead with _$LspActivityRead {
  const factory LspActivityRead.idle() = IdleLspActivityRead;
  const factory LspActivityRead.busy({
    required ReadText? title,
    required ReadText? message,
    required int? percentage,
  }) = BusyLspActivityRead;
  const factory LspActivityRead.indexing({
    required ReadText? title,
    required ReadText? message,
    required int? percentage,
  }) = IndexingLspActivityRead;
}

@Freezed(toStringOverride: false)
sealed class LspServerStateRead with _$LspServerStateRead {
  const factory LspServerStateRead.checking({required ReadText message}) =
      CheckingLspServerStateRead;
  const factory LspServerStateRead.disabled({required ReadText message}) =
      DisabledLspServerStateRead;
  const factory LspServerStateRead.unavailable({
    required int checkedAt,
    required SourceStateErrorRead error,
  }) = UnavailableLspServerStateRead;
  const factory LspServerStateRead.available({
    required int checkedAt,
    required int diagnosticCount,
    required LspActivityRead activity,
  }) = AvailableLspServerStateRead;
}

@Freezed(toStringOverride: false)
abstract class LspServerRead with _$LspServerRead {
  const factory LspServerRead({
    required ReadText id,
    required ReadText displayName,
    required TypedListRef extensions,
    required TypedListRef languageIds,
    required LspServerStateRead state,
  }) = _LspServerRead;
}

@Freezed(toStringOverride: false)
abstract class LspEntityRead with _$LspEntityRead {
  const factory LspEntityRead({
    required ProductEntityRef reference,
    required LspServerRead value,
  }) = _LspEntityRead;
}

@freezed
final class LspEntryPage with _$LspEntryPage {
  LspEntryPage({
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
final class LspServerReadPage with _$LspServerReadPage {
  LspServerReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<LspServerRead> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);
  final int listId;
  final int offset;
  final int total;
  final List<LspServerRead> items;
  final int? nextOffset;
}
