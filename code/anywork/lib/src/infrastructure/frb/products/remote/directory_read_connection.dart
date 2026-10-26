import 'package:anywork_client/remote_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../../rust/api/studio/products/read/remote_directory.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';
import '../../shared/resource_owner.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';
import '../product_read_owner.dart';

/// One immutable native page. Offsets address that page, never restart or
/// continue the remote scan. The Repository separately owns its next cursor.
final class FrbRemoteDirectoryReadConnection
    implements RemoteDirectoryReadConnection {
  FrbRemoteDirectoryReadConnection(
    String alias, {
    String? path,
    String? cursor,
  }) {
    _owner = AdapterResourceOwner(
      resource: 'remote-directory-read',
      mapFailure: bridgeFailure,
      requestNativeClose: () => _opening.handle?.requestClose(),
      closeNative: () => _closeNative(retry: false),
      retryNativeClose: () => _closeNative(retry: true),
      disposeNative: () => _opening.handle!.dispose(),
      cancelNativeStream: () => Future<void>.value(),
      expectedIdentity: () => _scopeId,
    );
    _opening.start(
      _owner,
      () => native.openDirectory(alias: alias, path: path, cursor: cursor),
      (handle) => handle.requestClose(),
      attached: _rememberRawScope,
    );
  }

  final _opening =
      ProductNativeOpening<native.BridgeRemoteDirectoryReadConnection>();
  late final AdapterResourceOwner _owner;
  String? _scopeId;
  ProductReadScopeIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawScope(native.BridgeRemoteDirectoryReadConnection handle) {
    final raw = handle.identity().scopeId;
    if (raw.isEmpty || _scopeId != null && raw != _scopeId) {
      throw adapterProtocol('remote-directory-read-identity');
    }
    _scopeId ??= raw;
  }

  void _checkIdentity(native.BridgeRemoteDirectoryReadConnection handle) {
    _rememberRawScope(handle);
    final identity = productScopeFromBridge(handle.identity());
    if (identity.scopeId != _scopeId ||
        identity.ownerEpoch.isEmpty ||
        identity.incarnation < 1) {
      throw adapterProtocol('remote-directory-read-identity');
    }
    if (_identity case final expected?) {
      requireProductReadScope(identity, expected);
    }
    _identity ??= identity;
  }

  Future<T> _query<T>(
    Future<T> Function(native.BridgeRemoteDirectoryReadConnection) action,
  ) => _owner.query(() async {
    final handle = await _opening.ready;
    _owner.ensureOpen();
    _checkIdentity(handle);
    final value = await action(handle);
    _checkIdentity(handle);
    return value;
  });

  RemoteDirectoryReadHeader _header(
    native.BridgeRemoteDirectoryReadHeader value,
  ) {
    if (value.scopeId != _scopeId) {
      throw adapterProtocol('remote-directory-header-scope');
    }
    return RemoteDirectoryReadHeader(
      scopeId: value.scopeId,
      path: readTextFromBridge(value.path),
      parent: nullableReadText(value.parent),
      nextCursor: nullableReadText(value.nextCursor),
      pageEntryCount: exactU64(value.pageEntryCount, 'remote page entry count'),
    );
  }

  @override
  Future<RemoteDirectoryReadHeader> header() =>
      _query((handle) async => _header(await handle.header()));

  @override
  Future<RemoteDirectoryEntryPage> entries({int offset = 0, int limit = 32}) =>
      _query((handle) async {
        final request = modelPageArguments(offset, limit);
        final value = await handle.entries(
          offset: request.offset,
          limit: request.limit,
        );
        if (value.scopeId != _scopeId) {
          throw adapterProtocol('remote-directory-page-scope');
        }
        final page = RemoteDirectoryEntryPage(
          scopeId: value.scopeId,
          offset: exactU64(value.offset, 'remote entries offset'),
          items: value.items
              .map(
                (entry) => RemoteDirectoryEntryRead(
                  name: readTextFromBridge(entry.name),
                  path: readTextFromBridge(entry.path),
                  isDirectory: entry.isDirectory,
                  isSymlink: entry.isSymlink,
                ),
              )
              .toList(growable: false),
          nextOffset: nullableU64(
            value.nextOffset,
            'remote next entries offset',
          ),
        );
        // The Repository already owns the page header and validates its total.
        // Do not add another native read or retain a second header cache here.
        if (page.offset != offset ||
            page.items.length > limit ||
            page.nextOffset != null &&
                (page.items.isEmpty ||
                    page.nextOffset != offset + page.items.length)) {
          throw adapterProtocol('remote-directory-page-binding');
        }
        return page;
      });

  @override
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536}) =>
      _query((handle) async {
        modelTextArguments(maxBytes);
        return requireModelText(
          textChunkFromBridge(
            await handle.text(
              fieldId: nativeU64(fieldId, 'remote directory text field'),
              offset: nativeU64(offset, 'remote directory UTF-8 offset'),
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
    // Even a malformed descriptor cannot skip the original scope's native join.
    final report = feedCloseReportFromBridge(
      await (retry ? handle.retryClose() : handle.close()),
    );
    if (_scopeId == null || report.feedId != _scopeId) {
      throw adapterProtocol('remote-directory-close-scope');
    }
    return report;
  }

  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}
