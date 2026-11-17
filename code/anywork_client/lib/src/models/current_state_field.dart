import 'chat_models.dart';

/// A State field whose complete JSON value is read through CurrentReader.
///
/// The corresponding inline runtime/activity value is only a bounded
/// placeholder while this head is present.
final class CurrentStateField {
  const CurrentStateField({
    required this.field,
    required this.reference,
    required this.byteLength,
  });

  final String field;
  final CurrentContentRef reference;
  final int byteLength;

  @override
  bool operator ==(Object other) =>
      other is CurrentStateField &&
      field == other.field &&
      reference == other.reference &&
      byteLength == other.byteLength;

  @override
  int get hashCode => Object.hash(field, reference, byteLength);
}
