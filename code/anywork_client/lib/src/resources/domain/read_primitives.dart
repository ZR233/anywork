import 'package:freezed_annotation/freezed_annotation.dart';

part 'read_primitives.freezed.dart';

/// Text offsets and lengths are UTF-8 bytes in the original immutable scope.
@Freezed(toStringOverride: false)
sealed class ReadText with _$ReadText {
  const factory ReadText.inline({required String text}) = InlineReadText;
  const factory ReadText.deferred({
    required int fieldId,
    required int utf8Bytes,
  }) = DeferredReadText;
}

@Freezed(toStringOverride: false)
abstract class TextChunk with _$TextChunk {
  const factory TextChunk({
    required int fieldId,
    required int offset,
    required String text,
    required int? nextOffset,
  }) = _TextChunk;
}

@freezed
abstract class TypedListRef with _$TypedListRef {
  const factory TypedListRef({required int listId, required int total}) =
      _TypedListRef;
}

@Freezed(toStringOverride: false)
abstract class TextReadItem with _$TextReadItem {
  const factory TextReadItem({required ReadText value}) = _TextReadItem;
}

@Freezed(toStringOverride: false)
final class TextReadPage with _$TextReadPage {
  TextReadPage({
    required this.listId,
    required this.offset,
    required this.total,
    required List<TextReadItem> items,
    required this.nextOffset,
  }) : items = List.unmodifiable(items);

  final int listId;
  final int offset;
  final int total;
  final List<TextReadItem> items;
  final int? nextOffset;
}
