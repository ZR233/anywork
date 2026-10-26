import 'dart:convert' show utf8;

import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/products/identity.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/resource_owner.dart';
import 'identity_converters.dart';
import 'product_native_opening.dart';

/// Lifecycle and original identity only. Queries keep their concrete native
/// types; this owner neither materializes nor caches product bodies.
final class ProductReadOwner<N> {
  ProductReadOwner({
    required String resource,
    required this._origin,
    required this._version,
    required Future<N> Function() open,
    required this._identity,
    required void Function(N) requestClose,
    required Future<FeedCloseReport> Function(N) close,
    required Future<FeedCloseReport> Function(N) retryClose,
    required void Function(N) dispose,
  }) {
    owner = AdapterResourceOwner(
      resource: resource,
      requestNativeClose: () {
        if (_opening.handle case final handle?) requestClose(handle);
      },
      closeNative: () => _closeNative(close),
      retryNativeClose: () => _closeNative(retryClose),
      disposeNative: () => dispose(_openedHandle()),
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: bridgeFailure,
      expectedIdentity: () => _scopeId ?? '',
    );
    _opening.start(owner, open, requestClose, attached: _rememberRawScope);
  }

  /// A null handle is a programming error, never a silent no-op: the original
  /// null-check failure stays visible to the owner's dispose diagnostic.
  N _openedHandle() {
    final handle = _opening.handle;
    if (handle == null) {
      throw StateError('Product read has no native handle to dispose.');
    }
    return handle;
  }

  final _opening = ProductNativeOpening<N>();
  final ProductReadOrigin _origin;
  final ProductReadVersion _version;
  final native.BridgeProductReadScopeIdentity Function(N) _identity;
  late final AdapterResourceOwner owner;
  ProductReadScopeIdentity? _scope;
  String? _scopeId;
  Future<N> get ready => _opening.ready;

  void _rememberRawScope(N handle) {
    final raw = _identity(handle).scopeId;
    if (raw.isEmpty || _scopeId != null && raw != _scopeId) {
      throw adapterProtocol('models-read-origin');
    }
    _scopeId ??= raw;
  }

  Future<FeedCloseReport> _closeNative(
    Future<FeedCloseReport> Function(N) close,
  ) async {
    final handle = await _opening.ready;
    if (_scopeId == null) {
      try {
        _rememberRawScope(handle);
      } on Object catch (error, stack) {
        owner.failure(error, stack, source: 'close-identity');
      }
    }
    // Always join the original native scope, even if identity is still unreadable.
    // The owner's independent raw-ID validator then prevents premature disposal.
    return close(handle);
  }

  void _checkIdentity(N handle) {
    _rememberRawScope(handle);
    final scope = productScopeFromBridge(_identity(handle));
    if (scope.scopeId.isEmpty ||
        scope.ownerEpoch.isEmpty ||
        scope.incarnation < 1 ||
        scope.ownerEpoch != _origin.ownerEpoch ||
        scope.incarnation != _origin.incarnation ||
        scope.scopeId != _scopeId ||
        scope.version != _version) {
      throw adapterProtocol('models-read-origin');
    }
    if (_scope case final expected?) requireProductReadScope(scope, expected);
    _scope ??= scope;
  }

  Future<T> query<T>(Future<T> Function(N) action) => owner.query(() async {
    final handle = await _opening.ready;
    owner.ensureOpen();
    _checkIdentity(handle);
    final value = await action(handle);
    _checkIdentity(handle);
    return value;
  });

  Future<T> list<T>(
    int listId,
    int offset,
    int limit,
    Future<T> Function(N, BigInt, BigInt, int) read,
  ) => query((handle) {
    final page = modelPageArguments(offset, limit);
    return read(
      handle,
      nativeU64(listId, 'models list identity'),
      page.offset,
      page.limit,
    );
  });

  void requestClose() => owner.requestClose();
  Future<FeedCloseReport> close() => owner.close();
  Future<FeedCloseReport> retryClose() => owner.retryClose();
}

({BigInt offset, int limit}) modelPageArguments(int offset, int limit) {
  if (limit < 1 || limit > 100) throw _pageArguments;
  return (offset: nativeU64(offset, 'models page offset'), limit: limit);
}

void requireModelPage({
  required int requestedOffset,
  required int limit,
  required int offset,
  required int total,
  required int count,
  required int? nextOffset,
  int? listId,
  int? requestedListId,
}) {
  final end = offset + count;
  if (offset != requestedOffset ||
      offset > total ||
      count > limit ||
      end > total ||
      listId != requestedListId ||
      (offset < total && count == 0) ||
      nextOffset != (end < total ? end : null)) {
    throw adapterProtocol('models-page-binding');
  }
}

void modelTextArguments(int maxBytes) {
  if (maxBytes < 4 || maxBytes > 262144) throw _textArguments;
}

TextChunk requireModelText(
  TextChunk chunk,
  int fieldId,
  int offset,
  int maxBytes,
) {
  final bytes = utf8.encode(chunk.text).length;
  if (chunk.fieldId != fieldId ||
      chunk.offset != offset ||
      bytes > maxBytes ||
      chunk.nextOffset != null &&
          (bytes == 0 || chunk.nextOffset != offset + bytes)) {
    throw adapterProtocol('models-text-binding');
  }
  return chunk;
}

native.BridgeProductEntityRef modelEntityToBridge(ProductEntityRef value) =>
    native.BridgeProductEntityRef(
      entry: nativeU64(value.entry, 'models entity entry'),
      revision: nativeU64(value.revision, 'models entity revision'),
    );

const _pageArguments = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Models page limit must be in 1..100',
  retryable: false,
  correlationId: 'adapter-models-page-limit',
);
const _textArguments = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Models text maxBytes must be in 4..262144',
  retryable: false,
  correlationId: 'adapter-models-text-limit',
);
