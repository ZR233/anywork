import 'dart:async';
import 'dart:typed_data';

import '../../../resources.dart';
import '../../../resources_ports.dart';
import '../domain/attachment_binary_identity.dart';
import 'attachment_binary_port.dart';

/// One future Repo read, not a partial DraftsRepository or a shared binary cache.
/// The caller supplies its original Repo lifetime; that lifetime owns the actual
/// PinnedReadOwner even if value fails, cleanup is unresolved or this wrapper dies.
final class AttachmentBinaryReadOwner {
  AttachmentBinaryReadOwner.draft({required ResourceLifetime lifetime,
      required AttachmentBinaryPort port, required String draftId, int maxBytes = 65536})
      : this._(lifetime: lifetime, target: AttachmentBinaryTarget.draft(draftId: draftId),
          open: () => port.openDraftBinary(draftId), maxBytes: maxBytes);

  AttachmentBinaryReadOwner.thread({required ResourceLifetime lifetime,
      required AttachmentBinaryPort port, required String threadId, required String attachmentId,
      int maxBytes = 65536})
      : this._(lifetime: lifetime,
          target: AttachmentBinaryTarget.thread(threadId: threadId, attachmentId: attachmentId),
          open: () => port.openThreadBinary(threadId, attachmentId), maxBytes: maxBytes);

  AttachmentBinaryReadOwner._({required this.lifetime, required AttachmentBinaryTarget target,
      required Future<AttachmentBinaryRead> Function() open, required int maxBytes})
      : _target = target, _maxBytes = maxBytes {
    lifetime.admit();
    if (maxBytes < 1 || maxBytes > 262144) throw const StudioFailure(
      code: StudioFailureCode.invalidArgument, message: 'Binary chunk size must be within 1..262144 bytes.',
      retryable: false, correlationId: 'attachment-binary-size');
    final label = target is DraftAttachmentBinaryTarget ? 'attachment-binary:draft' : 'attachment-binary:thread';
    try {
      _scope = PinnedReadOwner<_AttachmentBinaryHandle>(lifetime: lifetime, owner: label,
        open: () => _open(open), request: (handle) => handle.requestClose(),
        closeNative: (handle) => handle.close(retry: false), retryNative: (handle) => handle.close(retry: true));
    } on ResourceBudgetExceeded catch (error, stack) { Error.throwWithStackTrace(error.failure, stack); }
    final completion = Completer<Uint8List>();
    value = completion.future;
    value.ignore();
    try {
      final work = _scope.use(_assemble);
      work.then<void>((bytes) {
        if (!completion.isCompleted) completion.complete(bytes);
      }, onError: (Object error, StackTrace stack) {
        _remember(error, stack);
        if (!completion.isCompleted) completion.completeError(resourceFailure(error), stack);
      });
      // One admitted use spans every chunk. Graceful retirement rejects another
      // use, but only starts native cleanup after this actual use finishes.
      _scope.retire();
    } catch (error, stack) {
      _remember(error, stack);
      requestClose();
      if (!completion.isCompleted) completion.completeError(resourceFailure(error), stack);
    }
  }

  final ResourceLifetime lifetime;
  final AttachmentBinaryTarget _target;
  final int _maxBytes;
  late final PinnedReadOwner<_AttachmentBinaryHandle> _scope;
  late final Future<Uint8List> value;
  final List<({Object cause, StackTrace stack})> _causes = [];
  bool _closing = false;

  bool get released => _scope.released && _scope.issues.isEmpty;

  Future<_AttachmentBinaryHandle> _open(Future<AttachmentBinaryRead> Function() open) async {
    final permit = lifetime.budget.acquire(ResourceKind.pendingOperation, owner: 'attachment-binary:open');
    // Allocate the holder before calling out; never validate/discard a returned
    // native handle before PinnedReadOwner can assume its close responsibility.
    final handle = _AttachmentBinaryHandle(_target, _remember);
    Object? failure;
    StackTrace? failureStack;
    try { handle.attach(await open()); } catch (error, stack) {
      _remember(error, stack); failure = error; failureStack = stack;
    }
    try { permit.release(); } catch (error, stack) {
      _remember(error, stack);
      if (handle.attached) handle.openingFailure = (cause: error, stack: stack);
      else { failure ??= error; failureStack ??= stack; }
    }
    if (handle.attached) return handle;
    Error.throwWithStackTrace(resourceFailure(failure!), failureStack!);
  }

  void _checkOpen() {
    lifetime.admit();
    if (_closing) throw resourceCancelled;
  }

  Future<AttachmentBinaryChunk> _read(_AttachmentBinaryHandle handle, int offset) async {
    _checkOpen();
    final permit = lifetime.budget.acquire(ResourceKind.pendingOperation, owner: 'attachment-binary:read');
    Object? primary;
    try {
      handle.checkStable();
      _checkOpen();
      final chunk = await handle.read(offset: offset, maxBytes: _maxBytes);
      _checkOpen();
      return chunk;
    } catch (error, stack) {
      primary = error; _remember(error, stack);
      rethrow;
    } finally {
      try { permit.release(); } catch (error, stack) {
        _remember(error, stack);
        if (primary == null) Error.throwWithStackTrace(error, stack);
      }
    }
  }

  Future<Uint8List> _assemble(_AttachmentBinaryHandle handle) async {
    _checkOpen();
    final length = handle.describe();
    _checkOpen();
    final bytes = Uint8List(length);
    var offset = 0;
    while (true) {
      final chunk = await _read(handle, offset);
      handle.checkStable();
      final count = chunk.bytes.length;
      // Subtract first: after these bounds hold, offset+count cannot overflow
      // or wrap beyond the original nonnegative, representable file length.
      final remaining = length - offset;
      if (chunk.offset != offset || count > _maxBytes || count > remaining ||
          remaining > 0 && count == 0) throw resourceProtocol('The binary chunk does not continue its original file.');
      final end = offset + count;
      if (end == length ? chunk.nextOffset != null : chunk.nextOffset != end) {
        throw resourceProtocol('The binary chunk has an invalid terminal or continuation offset.');
      }
      bytes.setRange(offset, end, chunk.bytes);
      if (end == length) {
        _checkOpen();
        return bytes;
      }
      offset = end;
    }
  }

  void requestClose() {
    _closing = true;
    _scope.requestClose();
    _scope.cleanup(retry: false).ignore();
  }

  Future<CloseReport> close({DateTime? deadline}) {
    requestClose();
    return _observe(deadline: deadline, retry: false);
  }

  Future<CloseReport> retryCleanup({DateTime? deadline}) {
    requestClose();
    return _observe(deadline: deadline, retry: true);
  }

  Future<CloseReport> _observe({DateTime? deadline, required bool retry}) async {
    final work = _scope.cleanup(retry: retry);
    if (deadline == null) await work;
    else {
      final remaining = deadline.difference(DateTime.now());
      if (remaining > Duration.zero) {
        try { await work.timeout(remaining); } on TimeoutException { /* original scope still owns the join */ }
      }
    }
    return report();
  }

  CloseReport report() {
    final issues = _scope.issues;
    return CloseReport(unresolved: [if (!_scope.released || issues.isNotEmpty)
      UnresolvedResource(owner: _scope.owner, attemptId: AttemptId(_scope.attempt),
        issues: issues.isEmpty ? [resourcePendingIssue('attachmentBinaryPending')] : issues)]);
  }

  void _remember(Object cause, StackTrace stack) {
    _causes.add((cause: cause, stack: stack));
    lifetime.lastCause = cause; lifetime.lastStack = stack;
  }
}

/// Exact handle returned by the original open. Bad read metadata/payload fails
/// the value, not cleanup: a real matching native Clean can still release it.
final class _AttachmentBinaryHandle {
  _AttachmentBinaryHandle(this.target, this.remember);
  final AttachmentBinaryTarget target;
  final void Function(Object, StackTrace) remember;
  AttachmentBinaryRead? _read;
  AttachmentBinaryIdentity? _identity;
  int? _length;
  final List<FeedCloseReport> _receivedCloseReports = [];
  ({Object cause, StackTrace stack})? openingFailure;
  bool get attached => _read != null;
  void attach(AttachmentBinaryRead read) { _read = read; }

  int describe() {
    if (openingFailure case final failure?) Error.throwWithStackTrace(failure.cause, failure.stack);
    final identity = _identity ??= _read!.identity;
    final length = _length ??= _read!.byteLength;
    if (identity.scopeId.isEmpty || identity.runtimeEpoch.isEmpty || identity.incarnation < 0 ||
        identity.target != target || length < 0) {
      throw resourceProtocol('The binary scope identity, target or length is invalid.');
    }
    checkStable();
    return length;
  }

  void checkStable() {
    if (_read!.identity != _identity || _read!.byteLength != _length) {
      throw resourceProtocol('The binary reader replaced its original scope or file length.');
    }
  }

  Future<AttachmentBinaryChunk> read({required int offset, required int maxBytes}) {
    return _read!.read(offset: offset, maxBytes: maxBytes);
  }

  void requestClose() => _read!.requestClose();

  Future<FeedCloseReport> close({required bool retry}) async {
    AttachmentBinaryIdentity? identity;
    Object? identityError;
    StackTrace? identityStack;
    try { identity = _identity ??= _read!.identity; } catch (error, stack) {
      remember(error, stack);
      identityError = error; identityStack = stack;
    }
    try {
      // Even corrupt metadata must not prevent closing the actual returned pin.
      final report = await (retry ? _read!.retryClose() : _read!.close());
      _receivedCloseReports.add(report);
      if (identityError != null) Error.throwWithStackTrace(identityError, identityStack!);
      if (identity!.scopeId.isEmpty || report.feedId != identity.scopeId) {
        throw resourceProtocol('The binary close report belongs to another scope.');
      }
      return report;
    } catch (error, stack) { remember(error, stack); rethrow; }
  }
}
