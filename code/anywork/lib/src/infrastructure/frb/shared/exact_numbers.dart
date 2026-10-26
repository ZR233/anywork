import 'package:anywork_client/resources.dart';

final _u64Maximum = (BigInt.one << 64) - BigInt.one;

/// FRB's u64 is BigInt. toInt alone can clamp/truncate on a target platform.
int exactU64(BigInt value, String field) {
  if (value.isNegative || value > _u64Maximum) {
    throw _numberFailure(StudioFailureCode.protocol, field);
  }
  final converted = value.toInt();
  if (converted < 0 || BigInt.from(converted) != value) {
    throw _numberFailure(StudioFailureCode.overloaded, field);
  }
  return converted;
}

int exactI64(BigInt value, String field) {
  final minimum = -(BigInt.one << 63);
  final maximum = (BigInt.one << 63) - BigInt.one;
  if (value < minimum || value > maximum) {
    throw _numberFailure(StudioFailureCode.protocol, field);
  }
  final converted = value.toInt();
  if (BigInt.from(converted) != value) {
    throw _numberFailure(StudioFailureCode.overloaded, field);
  }
  return converted;
}

BigInt nativeU64(int value, String field) {
  final converted = BigInt.from(value);
  if (value < 0 || converted > _u64Maximum) {
    throw _numberFailure(StudioFailureCode.invalidArgument, field);
  }
  return converted;
}

StudioFailure _numberFailure(StudioFailureCode code, String field) =>
    StudioFailure(
      code: code,
      message: 'The $field integer cannot be represented exactly',
      retryable: false,
      correlationId: 'adapter-integer-range',
    );
