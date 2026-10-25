import 'dart:async';

import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/drafts_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/attachment_binary.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/resource_owner.dart';
import 'attachment_binary_values.dart';

/// One original native pin and its actual opening, queries and cleanup.
/// Metadata errors fail reads, not ownership: the returned scope remains
/// closable even when its descriptor cannot be published to the Repository.
final class FrbAttachmentBinaryRead implements AttachmentBinaryRead {
  FrbAttachmentBinaryRead.draft(String draftId)
    : this._(
        target: AttachmentBinaryTarget.draft(draftId: draftId),
        open: () => native.openDraftBinary(draftId: draftId),
      );

  FrbAttachmentBinaryRead.thread(String threadId, String attachmentId)
    : this._(
        target: AttachmentBinaryTarget.thread(
          threadId: threadId,
          attachmentId: attachmentId,
        ),
        open: () => native.openThreadBinary(
          threadId: threadId,
          attachmentId: attachmentId,
        ),
      );

  FrbAttachmentBinaryRead._({
    required this._target,
    required Future<native.BridgeAttachmentBinaryRead> Function() open,
  }) {
    _opening.future.ignore();
    _owner = AdapterResourceOwner(
      resource: 'attachment-binary',
      requestNativeClose: () {
        if (_handle case final handle?) handle.requestClose();
      },
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _handle!.dispose(),
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: bridgeFailure,
      // Never infer the expected scope from a close report. An unavailable or
      // empty native scope must fail validation, not authorize opaque disposal.
      expectedIdentity: () => _scopeId ?? '',
    );
    final finishOpening = _owner.registerOpening();
    Future<native.BridgeAttachmentBinaryRead>.sync(open)
        .then<void>(
          (handle) {
            // Attach BEFORE inspecting sync metadata; even a malformed descriptor
            // must reach the original caller's pinned owner and close/retry path.
            _handle = handle;
            try {
              final nativeIdentity = handle.identity();
              // Closing needs this original scope even if a later descriptor field
              // cannot be represented. Never derive it from the close report.
              _rememberScopeId(nativeIdentity.scopeId);
              _identity = attachmentBinaryIdentityFromBridge(nativeIdentity);
              _byteLength = attachmentBinaryLengthFromBridge(
                handle.byteLength(),
              );
              requireAttachmentBinaryIdentity(_identity!, _target);
            } on Object catch (error, stack) {
              _descriptorFailure = (
                failure: _owner.failure(error, stack, source: 'descriptor'),
                stack: stack,
              );
            }
            if (_owner.isClosing) {
              try {
                handle.requestClose();
              } on Object catch (error, stack) {
                _owner.failure(error, stack, source: 'late-open-close');
              }
            }
            _opening.complete(handle);
          },
          onError: (Object error, StackTrace stack) {
            _opening.completeError(
              _owner.failure(error, stack, source: 'open'),
              stack,
            );
          },
        )
        .whenComplete(finishOpening)
        .ignore();
  }

  final AttachmentBinaryTarget _target;
  final _opening = Completer<native.BridgeAttachmentBinaryRead>();
  late final AdapterResourceOwner _owner;
  native.BridgeAttachmentBinaryRead? _handle;
  String? _scopeId;
  AttachmentBinaryIdentity? _identity;
  int? _byteLength;
  ({StudioFailure failure, StackTrace stack})? _descriptorFailure;

  Future<void> get opened => _opening.future.then<void>((_) {});

  void _rememberScopeId(String value) {
    final original = _scopeId;
    if (value.isEmpty || original != null && value != original) {
      throw adapterProtocol('attachment-binary-scope-identity');
    }
    _scopeId ??= value;
  }

  @override
  String get scopeId {
    final original = _scopeId;
    if (original == null) {
      throw adapterProtocol('attachment-binary-scope-unavailable');
    }
    // This saved native value remains readable after Clean/dispose, without a
    // descriptor conversion or another RPC on an already disposed opaque.
    return original;
  }

  void _requireDescriptor() {
    if (_descriptorFailure case final failure?) {
      Error.throwWithStackTrace(failure.failure, failure.stack);
    }
    if (_identity == null || _byteLength == null) {
      throw adapterProtocol('attachment-binary-descriptor');
    }
  }

  @override
  AttachmentBinaryIdentity get identity {
    // Keep usable original metadata available even if the length/target check
    // failed. read still rejects the entire descriptor; cleanup uses scopeId.
    if (_identity case final value?) return value;
    _requireDescriptor();
    return _identity!;
  }

  @override
  int get byteLength {
    if (_byteLength case final value?) return value;
    _requireDescriptor();
    return _byteLength!;
  }

  void _requireStable(native.BridgeAttachmentBinaryRead handle) {
    _requireDescriptor();
    final originalScope = scopeId;
    final current = attachmentBinaryIdentityFromBridge(handle.identity());
    if (_identity!.scopeId != originalScope ||
        current.scopeId != originalScope ||
        current != _identity ||
        attachmentBinaryLengthFromBridge(handle.byteLength()) != _byteLength) {
      throw adapterProtocol('attachment-binary-scope-binding');
    }
  }

  @override
  Future<AttachmentBinaryChunk> read({
    required int offset,
    int maxBytes = 65536,
  }) => _owner.query(() async {
    final handle = await _opening.future;
    _owner.ensureOpen();
    _requireStable(handle);
    requireAttachmentBinaryArguments(offset, maxBytes, _byteLength!);
    _owner.ensureOpen();
    final chunk = await handle.read(offset: offset, maxBytes: maxBytes);
    // Inspect the original result even when close sealed publication meanwhile.
    // AdapterResourceOwner waits for this work before disposing the opaque.
    _requireStable(handle);
    return attachmentBinaryChunkFromBridge(
      chunk,
      offset: offset,
      maxBytes: maxBytes,
      byteLength: _byteLength!,
    );
  });

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.future;
    // A descriptor query failure is not a cleanup failure. Retry reading only
    // the original scope identity if it was unavailable, but always call the
    // real native closer even when that sync query still fails.
    if (_scopeId == null) {
      try {
        _rememberScopeId(handle.identity().scopeId);
      } on Object catch (error, stack) {
        _owner.failure(error, stack, source: 'close-identity');
      }
    }
    return feedCloseReportFromBridge(
      await (retry ? handle.retryClose() : handle.close()),
    );
  }

  @override
  void requestClose() => _owner.requestClose();

  @override
  Future<FeedCloseReport> close() => _owner.close();

  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
