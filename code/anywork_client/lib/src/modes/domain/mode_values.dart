import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../resources.dart';

part 'mode_values.freezed.dart';

@Freezed(copyWith: false)
abstract class ThreadModeId with _$ThreadModeId {
  const ThreadModeId._();
  const factory ThreadModeId._value({required String id}) = _ThreadModeId;

  factory ThreadModeId(String id) {
    final match = RegExp(r'mode\.[a-z0-9_-]+').matchAsPrefix(id);
    if (match == null || match.end != id.length || id.length > 64) {
      throw const StudioFailure(code: StudioFailureCode.invalidArgument, message: 'Invalid Thread Mode ID', retryable: false, correlationId: 'mode-id');
    }
    return ThreadModeId._value(id: id);
  }

  static const simple = ThreadModeId._value(id: 'mode.simple');
  static const task = ThreadModeId._value(id: 'mode.task');
}

@freezed
abstract class ThreadModeDescriptor with _$ThreadModeDescriptor {
  const factory ThreadModeDescriptor({required ThreadModeId id, required String displayName, required String description, required int order, required bool hasWorkflow, required bool readOnly}) = _ThreadModeDescriptor;
}

@freezed
abstract class ModesValue with _$ModesValue {
  const factory ModesValue({required int revision, required List<ThreadModeDescriptor> modes}) = _ModesValue;
}
