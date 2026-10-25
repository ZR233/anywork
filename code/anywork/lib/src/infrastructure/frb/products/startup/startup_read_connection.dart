import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../rust/api/studio/products/read/startup.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../../shared/resource_owner.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';
import '../product_read_owner.dart';
import 'startup_values.dart';

/// Startup references carry no caller-supplied ProductReadOrigin. The original
/// opaque identity supplies it; lifecycle still uses the shared resource owner.
final class FrbStartupReadConnection implements RuntimeStartupReadConnection {
  FrbStartupReadConnection(this._reference) {
    _owner = AdapterResourceOwner(
      resource: 'startup-read',
      requestNativeClose: () => _opening.handle?.requestClose(),
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _opening.handle!.dispose(),
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: bridgeFailure,
      expectedIdentity: () => _scopeId ?? '',
    );
    _opening.start(
      _owner,
      () =>
          native.openStartupRead(reference: startupReadRefToBridge(_reference)),
      (handle) => handle.requestClose(),
      attached: _rememberRawScope,
    );
  }

  final RuntimeStartupReadRef _reference;
  final _opening = ProductNativeOpening<native.BridgeStartupReadConnection>();
  late final AdapterResourceOwner _owner;
  String? _scopeId;
  ProductReadScopeIdentity? _scope;
  RuntimeStartupScopeIdentity? _headerScope;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawScope(native.BridgeStartupReadConnection handle) {
    final id = handle.identity().scopeId;
    if (id.isEmpty || _scopeId != null && _scopeId != id) {
      throw adapterProtocol('startup-read-identity');
    }
    _scopeId ??= id;
  }

  ProductReadScopeIdentity _identity(
    native.BridgeStartupReadConnection handle,
  ) {
    _rememberRawScope(handle);
    final value = productScopeFromBridge(handle.identity());
    if (value.scopeId != _scopeId ||
        value.ownerEpoch.isEmpty ||
        value.incarnation < 1 ||
        value.version !=
            ProductReadVersion.value(
              entry: _reference.entry,
              revision: _reference.revision,
            )) {
      throw adapterProtocol('startup-read-reference');
    }
    if (_scope case final expected?) requireProductReadScope(value, expected);
    return _scope ??= value;
  }

  Future<T> _query<T>(
    Future<T> Function(native.BridgeStartupReadConnection) action,
  ) => _owner.query(() async {
    final handle = await _opening.ready;
    _owner.ensureOpen();
    _identity(handle);
    final result = await action(handle);
    _identity(handle);
    return result;
  });

  @override
  Future<RuntimeStartupReadHeader> header() => _query((handle) async {
    final value = startupHeaderFromBridge(await handle.header());
    final scope = _identity(handle);
    if (value.reference != _reference ||
        value.scope.scopeId != scope.scopeId ||
        value.scope.ownerEpoch != scope.ownerEpoch ||
        value.scope.attemptId < 1 ||
        value.revision != _reference.revision ||
        value.scope.revision != value.revision ||
        _headerScope != null && _headerScope != value.scope) {
      throw adapterProtocol('startup-read-header');
    }
    _headerScope ??= value.scope;
    return value;
  });

  @override
  Future<StartupActiveTurnReadPage> activeTurns({
    int offset = 0,
    int limit = 32,
  }) => _query((handle) async {
    final request = modelPageArguments(offset, limit);
    final page = startupActiveTurnsFromBridge(
      await handle.activeTurns(offset: request.offset, limit: request.limit),
    );
    requireModelPage(
      requestedOffset: offset,
      limit: limit,
      offset: page.offset,
      total: page.total,
      count: page.items.length,
      nextOffset: page.nextOffset,
    );
    return page;
  });

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'startup text field'),
              offset: nativeU64(offset, 'startup UTF-8 offset'),
              maxBytes: maxBytes,
            ),
          ),
          fieldId,
          offset,
          maxBytes,
        );
      });

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    if (_scopeId == null) {
      try {
        _rememberRawScope(handle);
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
