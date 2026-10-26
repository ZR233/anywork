import '../../../resources.dart';
import '../domain/thread_identity.dart';

/// Per-attempt transport continuity. It carries no business clock or body cache.
final class FacetCursor {
  FacetCursor(this.facet, this.mode);

  final ThreadFacet facet;
  final ThreadObservationMode mode;
  ThreadFeedIdentity? _identity;
  ThreadFacetStamp? _stamp;
  int _nextSequence = 1;

  ThreadFeedIdentity? get identity => _identity;
  ThreadFacetStamp? get stamp => _stamp;

  void baseline(
    int sequence,
    ThreadFeedIdentity identity,
    ThreadFacetStamp stamp,
  ) {
    validateBaseline(sequence, identity, stamp);
    _identity = identity;
    _stamp = stamp;
    _nextSequence++;
  }

  void validateBaseline(
    int sequence,
    ThreadFeedIdentity identity,
    ThreadFacetStamp stamp,
  ) {
    _checkSequence(sequence);
    if (_identity != null) throw protocol('A baseline was delivered twice.');
    _checkIdentity(identity);
    _checkStamp(identity, stamp);
  }

  void change(int sequence, ThreadFacetStamp stamp, {int? baseRevision}) {
    validateChange(sequence, stamp, baseRevision: baseRevision);
    _stamp = stamp;
    _nextSequence++;
  }

  void validateChange(
    int sequence,
    ThreadFacetStamp stamp, {
    int? baseRevision,
  }) {
    _checkSequence(sequence);
    final identity = _identity;
    final previous = _stamp;
    if (identity == null || previous == null) {
      throw protocol('The first Data must be a baseline.');
    }
    _checkStamp(identity, stamp);
    if (stamp.revision <= previous.revision ||
        (baseRevision != null && baseRevision != previous.revision)) {
      throw protocol('The facet revision is not continuous.');
    }
  }

  void control(ThreadFeedIdentity identity) {
    _checkIdentity(identity);
    final known = _identity;
    if (known != null && identity != known) {
      throw protocol('The terminal frame belongs to another feed.');
    }
  }

  void _checkSequence(int sequence) {
    if (sequence < 1 || sequence != _nextSequence) {
      throw protocol('The delivery sequence must continue strictly from one.');
    }
  }

  void _checkIdentity(ThreadFeedIdentity identity) {
    if (identity.feedId.isEmpty ||
        identity.runtimeEpoch.isEmpty ||
        identity.incarnation <= 0 ||
        identity.facet != facet ||
        identity.mode != mode) {
      throw protocol('The feed identity does not match the original open.');
    }
  }

  void _checkStamp(ThreadFeedIdentity identity, ThreadFacetStamp stamp) {
    if (stamp.runtimeEpoch != identity.runtimeEpoch ||
        stamp.incarnation != identity.incarnation ||
        stamp.facet != facet ||
        stamp.revision < 0) {
      throw protocol('The facet stamp belongs to another projection.');
    }
  }

  StudioFailure protocol(String message) => StudioFailure(
    code: StudioFailureCode.protocol,
    message: message,
    retryable: false,
    correlationId: 'thread-${facet.name}-continuity',
  );
}
