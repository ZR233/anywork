/// A Client-side submission rejection whose command did not invoke transport.
///
/// [error] preserves the original typed diagnostic; callers must inspect it
/// separately from the submission-stage fact carried by this wrapper.
final class SubmissionNotSent implements Exception {
  const SubmissionNotSent(this.error);

  final Object error;

  @override
  String toString() => error.toString();
}
