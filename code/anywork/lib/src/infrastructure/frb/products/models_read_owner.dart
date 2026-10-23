import 'dart:convert' show utf8;

import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/products/identity.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/exact_numbers.dart';
import '../shared/resource_owner.dart';
import 'identity_converters.dart';
import 'models_native_opening.dart';

/// Lifecycle and original identity only. Queries keep their concrete native
/// types; this owner neither materializes nor caches model/template bodies.
final class ModelsReadOwner<N> {
  ModelsReadOwner({required String resource, required ProductReadOrigin origin,
    required int entry, required int revision, required Future<N> Function() open,
    required native.BridgeProductReadScopeIdentity Function(N) identity,
    required void Function(N) requestClose,
    required Future<FeedCloseReport> Function(N) close,
    required Future<FeedCloseReport> Function(N) retryClose,
    required void Function(N) dispose}) : _origin = origin, _entry = entry,
        _revision = revision, _identity = identity {
    owner = AdapterResourceOwner(resource: resource,
      requestNativeClose: () { if (_opening.handle case final handle?) requestClose(handle); },
      closeNative: () async => close(await _opening.ready),
      retryNativeClose: () async => retryClose(await _opening.ready),
      disposeNative: () => dispose(_opening.handle!),
      cancelNativeStream: () => Future<void>.value(), mapFailure: bridgeFailure,
      expectedIdentity: () => _scope?.scopeId);
    _opening.start(owner, open, requestClose);
  }

  final _opening = ModelsNativeOpening<N>();
  final ProductReadOrigin _origin;
  final int _entry;
  final int _revision;
  final native.BridgeProductReadScopeIdentity Function(N) _identity;
  late final AdapterResourceOwner owner;
  ProductReadScopeIdentity? _scope;
  Future<N> get ready => _opening.ready;

  void _checkIdentity(N handle) {
    final scope = productScopeFromBridge(_identity(handle));
    if (scope.scopeId.isEmpty || scope.ownerEpoch.isEmpty || scope.incarnation < 1 ||
        scope.ownerEpoch != _origin.ownerEpoch || scope.incarnation != _origin.incarnation ||
        scope.version != ProductReadVersion.value(entry: _entry, revision: _revision)) {
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

  Future<T> list<T>(int listId, int offset, int limit,
    Future<T> Function(N, BigInt, BigInt, int) read) => query((handle) {
      final page = modelPageArguments(offset, limit);
      return read(handle, nativeU64(listId, 'models list identity'), page.offset, page.limit);
    });

  void requestClose() => owner.requestClose();
  Future<FeedCloseReport> close() => owner.close();
  Future<FeedCloseReport> retryClose() => owner.retryClose();
}

({BigInt offset, int limit}) modelPageArguments(int offset, int limit) {
  if (limit < 1 || limit > 100) throw _pageArguments;
  return (offset: nativeU64(offset, 'models page offset'), limit: limit);
}

void requireModelPage({required int requestedOffset, required int limit,
  required int offset, required int total, required int count, required int? nextOffset,
  int? listId, int? requestedListId}) {
  final end = offset + count;
  if (offset != requestedOffset || offset > total || count > limit || end > total ||
      listId != requestedListId || (offset < total && count == 0) ||
      nextOffset != (end < total ? end : null)) {
    throw adapterProtocol('models-page-binding');
  }
}

void modelTextArguments(int maxBytes) {
  if (maxBytes < 4 || maxBytes > 262144) throw _textArguments;
}

TextChunk requireModelText(TextChunk chunk, int fieldId, int offset, int maxBytes) {
  final bytes = utf8.encode(chunk.text).length;
  if (chunk.fieldId != fieldId || chunk.offset != offset || bytes > maxBytes ||
      chunk.nextOffset != null && (bytes == 0 || chunk.nextOffset != offset + bytes)) {
    throw adapterProtocol('models-text-binding');
  }
  return chunk;
}

native.BridgeProductEntityRef modelEntityToBridge(ProductEntityRef value) => native.BridgeProductEntityRef(
  entry: nativeU64(value.entry, 'models entity entry'), revision: nativeU64(value.revision, 'models entity revision'),
);

const _pageArguments = StudioFailure(code: StudioFailureCode.invalidArgument,
  message: 'Models page limit must be in 1..100', retryable: false,
  correlationId: 'adapter-models-page-limit');
const _textArguments = StudioFailure(code: StudioFailureCode.invalidArgument,
  message: 'Models text maxBytes must be in 4..262144', retryable: false,
  correlationId: 'adapter-models-text-limit');
