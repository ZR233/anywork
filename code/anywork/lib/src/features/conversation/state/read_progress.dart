import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'read_progress.freezed.dart';

@Freezed(toStringOverride: false)
abstract class TextReadProgress with _$TextReadProgress {
  const factory TextReadProgress({
    required int fieldId,
    required int totalUtf8Bytes,
    @Default(0) int loadedUtf8Bytes,
    @Default('') String text,
    @Default(false) bool complete,
    @Default(false) bool loading,
    StudioFailure? error,
  }) = _TextReadProgress;
}
