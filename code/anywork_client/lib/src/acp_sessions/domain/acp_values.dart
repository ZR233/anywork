// Value-only boundary for open ACP metadata and tool/RPC data. No JSON-RPC codec.
sealed class AcpJsonValue {
  const AcpJsonValue();
}

final class AcpJsonNull extends AcpJsonValue {
  const AcpJsonNull();
}

final class AcpJsonBool extends AcpJsonValue {
  const AcpJsonBool(this.value);
  final bool value;
}

final class AcpJsonInteger extends AcpJsonValue {
  const AcpJsonInteger(this.value);
  final BigInt value;
}

final class AcpJsonDecimal extends AcpJsonValue {
  AcpJsonDecimal(this.value) {
    if (!value.isFinite)
      throw ArgumentError.value(value, 'value', 'JSON number must be finite');
  }
  final double value;
}

final class AcpJsonString extends AcpJsonValue {
  const AcpJsonString(this.value);
  final String value;
}

final class AcpJsonArray extends AcpJsonValue {
  AcpJsonArray(Iterable<AcpJsonValue> values)
    : values = List.unmodifiable(values);
  final List<AcpJsonValue> values;
}

final class AcpJsonObject extends AcpJsonValue {
  AcpJsonObject(Map<String, AcpJsonValue> values)
    : values = Map.unmodifiable(values);
  final Map<String, AcpJsonValue> values;
}

// SessionInfoUpdate/CompactionUpdate distinguish omitted fields from explicit null.
sealed class AcpOptionalField<T> {
  const AcpOptionalField();
}

final class AcpFieldAbsent<T> extends AcpOptionalField<T> {
  const AcpFieldAbsent();
}

final class AcpFieldNull<T> extends AcpOptionalField<T> {
  const AcpFieldNull();
}

final class AcpFieldValue<T> extends AcpOptionalField<T> {
  const AcpFieldValue(this.value);
  final T value;
}

sealed class AcpStringId {
  const AcpStringId(this.value);
  final String value;
  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is AcpStringId &&
      value == other.value;
  @override
  int get hashCode => Object.hash(runtimeType, value);
}

final class AcpRemoteSessionId extends AcpStringId {
  const AcpRemoteSessionId(super.value);
}

final class AcpConfigId extends AcpStringId {
  const AcpConfigId(super.value);
}

final class AcpConfigValueId extends AcpStringId {
  const AcpConfigValueId(super.value);
}

final class AcpConfigGroupId extends AcpStringId {
  const AcpConfigGroupId(super.value);
}

final class AcpPermissionOptionId extends AcpStringId {
  const AcpPermissionOptionId(super.value);
}

final class AcpModeId extends AcpStringId {
  const AcpModeId(super.value);
}

final class AcpToolCallId extends AcpStringId {
  const AcpToolCallId(super.value);
}

final class AcpTerminalId extends AcpStringId {
  const AcpTerminalId(super.value);
}

final class AcpMessageId extends AcpStringId {
  const AcpMessageId(super.value);
}

final class AcpCompactionId extends AcpStringId {
  const AcpCompactionId(super.value);
}
