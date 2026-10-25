import 'package:anywork_client/resources.dart';

/// Wire measurements/prices keep their original units and sign. Only reject
/// non-finite transport values; do not invent a zero or a business range.
double finiteModelNumber(double value, String field) {
  if (!value.isFinite) {
    throw StudioFailure(
      code: StudioFailureCode.protocol,
      message: 'The $field number must be finite',
      retryable: false,
      correlationId: 'adapter-models-non-finite',
    );
  }
  return value;
}

double? nullableFiniteModelNumber(double? value, String field) =>
    value == null ? null : finiteModelNumber(value, field);
