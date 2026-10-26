import 'dart:async';
import 'dart:convert' show utf8;

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/identity.dart' as identity;
import '../../../rust/api/studio/observation.dart' as wire;
import '../../../rust/api/studio/types/chat.dart' as lifecycle;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import '../shared/resource_owner.dart';
import 'identity_converters.dart';

/// Common mechanics for immutable Thread reads, not another query pool or
/// material cache. Each concrete reader supplies its original
/// opaque operations; AdapterResourceOwner owns opening/query/cancel/join.
abstract base class FrbThreadReadConnection<H extends Object>
    implements ConversationReadConnection {
  FrbThreadReadConnection({
    required String resource,
    required String diagnosticPrefix,
    required ThreadFacetStamp origin,
    required ThreadFacet facet,
    required int sourceRevision,
    required Future<H> Function() open,
    required identity.BridgeReadScopeIdentity Function(H) identityOf,
    required void Function(H) requestNativeClose,
    required Future<lifecycle.BridgeFeedCloseReport> Function(H) closeNative,
    required Future<lifecycle.BridgeFeedCloseReport> Function(H)
    retryNativeClose,
    required void Function(H) disposeNative,
  }) : _diagnosticPrefix = diagnosticPrefix,
       _identityOf = identityOf {
    _opening.future.ignore();
    _owner = AdapterResourceOwner(
      resource: resource,
      requestNativeClose: () {
        if (_handle case final handle?) requestNativeClose(handle);
      },
      closeNative: () => _closeNative(closeNative),
      retryNativeClose: () => _closeNative(retryNativeClose),
      disposeNative: () => disposeNative(_handle!),
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: bridgeFailure,
      expectedIdentity: () => _scopeId ?? '',
    );
    final finishOpening = _owner.registerOpening();
    Future<H>.sync(open)
        .then<void>(
          (handle) {
            _handle = handle;
            try {
              final raw = identityOf(handle);
              _rememberScopeId(raw.scopeId);
              final scope = readScopeFromBridge(raw);
              // Each native reader chooses its real source clock: ref revision for
              // fact reads, origin facet revision for a PlanDocument scope.
              if (origin.facet != facet ||
                  scope.runtimeEpoch != origin.runtimeEpoch ||
                  scope.incarnation != origin.incarnation ||
                  scope.sourceRevision != sourceRevision) {
                throw adapterProtocol('$diagnosticPrefix-source');
              }
              _scope = scope;
            } on Object catch (error, stack) {
              _descriptorFailure = (
                failure: _owner.failure(error, stack, source: 'descriptor'),
                stack: stack,
              );
            }
            if (_owner.isClosing) {
              try {
                requestNativeClose(handle);
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

  // Stable domain diagnostics must not change when mechanical owners move.
  final String _diagnosticPrefix;
  final identity.BridgeReadScopeIdentity Function(H) _identityOf;
  final _opening = Completer<H>();
  late final AdapterResourceOwner _owner;
  H? _handle;
  String? _scopeId;
  ReadScopeIdentity? _scope;
  ({StudioFailure failure, StackTrace stack})? _descriptorFailure;

  Future<void> get opened => _opening.future.then<void>((_) {});

  void _rememberScopeId(String value) {
    if (value.isEmpty || _scopeId != null && value != _scopeId) {
      throw adapterProtocol('$_diagnosticPrefix-scope-identity');
    }
    _scopeId ??= value;
  }

  /// The entered query remains owned until its original Future and conversion
  /// settle, even if UI publication is fenced. Only identity, never a header
  /// or page body, is retained here.
  Future<T> query<T>(FutureOr<T> Function(H, ReadScopeIdentity) operation) =>
      _owner.query(() async {
        final handle = await _opening.future;
        _owner.ensureOpen();
        if (_descriptorFailure case final failure?) {
          Error.throwWithStackTrace(failure.failure, failure.stack);
        }
        final scope = _scope;
        if (scope == null) {
          throw adapterProtocol('$_diagnosticPrefix-descriptor');
        }
        requireReadScope(readScopeFromBridge(_identityOf(handle)), scope);
        return operation(handle, scope);
      });

  Future<FeedCloseReport> _closeNative(
    Future<lifecycle.BridgeFeedCloseReport> Function(H) closeHandle,
  ) async {
    final handle = await _opening.future;
    if (_scopeId == null) {
      try {
        _rememberScopeId(_identityOf(handle).scopeId);
      } on Object catch (error, stack) {
        _owner.failure(error, stack, source: 'close-identity');
      }
    }
    // Descriptor/query failures do not veto cleanup. A usable raw scope must
    // still match the actual report before the shared owner may dispose.
    return feedCloseReportFromBridge(await closeHandle(handle));
  }

  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}

/// Only text-capable native scopes acquire this API. PlanDocument inherits the
/// non-text owner directly and never fabricates a text/chunk operation.
abstract base class FrbThreadTextReadConnection<H extends Object>
    extends FrbThreadReadConnection<H>
    implements ConversationTextReadConnection {
  FrbThreadTextReadConnection({
    required super.resource,
    required super.diagnosticPrefix,
    required this._diagnosticLabel,
    required super.origin,
    required super.facet,
    required super.sourceRevision,
    required super.open,
    required super.identityOf,
    required super.requestNativeClose,
    required super.closeNative,
    required super.retryNativeClose,
    required super.disposeNative,
    required this._readText,
  });

  final String _diagnosticLabel;
  final Future<wire.BridgeTextChunk> Function(H, BigInt, BigInt, int) _readText;

  StudioFailure get _pageArguments => StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message: '$_diagnosticLabel pages require a limit in 1..100',
    retryable: false,
    correlationId: 'adapter-$_diagnosticPrefix-page-limit',
  );

  StudioFailure get _textArguments => StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message: '$_diagnosticLabel text requires 4..262144 UTF-8 bytes',
    retryable: false,
    correlationId: 'adapter-$_diagnosticPrefix-text-limit',
  );

  Future<T> pageQuery<T>(
    int offset,
    int limit,
    Future<T> Function(H, ReadScopeIdentity, BigInt) operation,
  ) => query((handle, scope) {
    if (limit < 1 || limit > 100) throw _pageArguments;
    return operation(
      handle,
      scope,
      nativeU64(offset, '$_diagnosticLabel page offset'),
    );
  });

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      query((handle, scope) async {
        if (maxBytes < 4 || maxBytes > 262144) throw _textArguments;
        final nativeField = nativeU64(fieldId, '$_diagnosticLabel text field');
        final nativeOffset = nativeU64(
          offset,
          '$_diagnosticLabel UTF-8 offset',
        );
        final chunk = textChunkFromBridge(
          await _readText(handle, nativeField, nativeOffset, maxBytes),
        );
        final bytes = utf8.encode(chunk.text).length;
        if (chunk.fieldId != fieldId ||
            chunk.offset != offset ||
            bytes > maxBytes ||
            chunk.nextOffset != null &&
                (bytes == 0 ||
                    BigInt.from(chunk.nextOffset!) !=
                        BigInt.from(offset) + BigInt.from(bytes))) {
          throw adapterProtocol('$_diagnosticPrefix-text-progress');
        }
        return chunk;
      });
}

/// Native byte-budgeted pages may be shorter than limit, but they must keep
/// their exact requested offset, contiguous indices and real continuation.
void requireThreadReadPage({
  required String diagnosticPrefix,
  required int requestedOffset,
  required int limit,
  required int offset,
  required int total,
  required int count,
  required int? nextOffset,
  Iterable<int>? indices,
}) {
  final end = BigInt.from(offset) + BigInt.from(count);
  final totalValue = BigInt.from(total);
  if (offset != requestedOffset ||
      count > limit ||
      end > totalValue ||
      count == 0 && offset < total ||
      (end < totalValue
          ? nextOffset == null || BigInt.from(nextOffset) != end
          : nextOffset != null)) {
    throw adapterProtocol('$diagnosticPrefix-page-progress');
  }
  if (indices != null) {
    var expected = BigInt.from(offset);
    for (final index in indices) {
      if (BigInt.from(index) != expected) {
        throw adapterProtocol('$diagnosticPrefix-page-index');
      }
      expected += BigInt.one;
    }
    if (expected != end) throw adapterProtocol('$diagnosticPrefix-page-count');
  }
}
