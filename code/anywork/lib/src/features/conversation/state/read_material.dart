import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'read_progress.dart';

part 'read_material.freezed.dart';

/// Bounded, explicitly requested presentation material, never a canonical cache.
@Freezed(toStringOverride: false)
abstract class ReadMaterial<H, I> with _$ReadMaterial<H, I> {
  const ReadMaterial._();
  const factory ReadMaterial({
    H? header,
    @Default([]) List<I> items,
    @Default({}) Map<int, TextReadProgress> texts,
    int? nextOffset,
    @Default(false) bool loading,
    StudioFailure? error,
  }) = _ReadMaterial<H, I>;

  String? textOf(ReadText? value) => switch (value) {
    null => null,
    InlineReadText(:final text) => text,
    DeferredReadText(:final fieldId) =>
      texts[fieldId]?.complete == true ? texts[fieldId]!.text : null,
  };
}
