import 'dart:convert' show utf8;

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';

import '../../../rust/api/studio/conversation/read/metrics.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/exact_numbers.dart';
import '../shared/read_converters.dart';
import '../shared/resource_owner.dart';
import 'identity_converters.dart';
import 'value_read_converters.dart';

/// One native immutable identity scope. No header/text body cache or feed owner.
final class FrbMetricsIdentityReadConnection
    implements MetricsIdentityReadConnection {
  FrbMetricsIdentityReadConnection({
    required native.BridgeMetricsIdentityReadConnection handle,
    required this._origin,
  }) : _handle = handle {
    _owner = AdapterResourceOwner(
      resource: 'metrics-identity-read',
      requestNativeClose: handle.requestClose,
      closeNative: () async => feedCloseReportFromBridge(await handle.close()),
      retryNativeClose: () async =>
          feedCloseReportFromBridge(await handle.retryClose()),
      disposeNative: handle.dispose,
      // This native read handle has queries but no forwarding subscription.
      cancelNativeStream: () => Future<void>.value(),
      mapFailure: bridgeFailure,
      expectedIdentity: () => _scope?.scopeId,
    );
  }

  final native.BridgeMetricsIdentityReadConnection _handle;
  final ThreadFacetStamp _origin;
  late final AdapterResourceOwner _owner;
  ReadScopeIdentity? _scope;

  @override
  Future<MetricsIdentityReadHeader> header() => _owner.query(_readHeader);

  Future<MetricsIdentityReadHeader> _readHeader() async {
    final value = await _handle.header();
    final scope = readScopeFromBridge(value.scope);
    if (_origin.facet != ThreadFacet.metrics ||
        scope.runtimeEpoch != _origin.runtimeEpoch ||
        scope.incarnation != _origin.incarnation ||
        scope.sourceRevision != _origin.revision) {
      throw adapterProtocol('metrics-identity-source');
    }
    final header = metricsIdentityHeaderFromBridge(
      value,
      expectedScope: _scope ?? scope,
    );
    _scope ??= header.scope;
    return header;
  }

  @override
  Future<TextChunk> text(
    int fieldId, {
    int offset = 0,
    int maxBytes = 65536,
  }) => _owner.query(() async {
    // owner.query checks closing before argument conversion or native dispatch.
    if (maxBytes < 4 || maxBytes > 262144) throw _textArguments;
    final nativeField = nativeU64(fieldId, 'metrics identity field');
    final nativeOffset = nativeU64(offset, 'metrics identity UTF-8 offset');
    if (_scope == null) await _readHeader();
    _owner.ensureOpen();
    final chunk = textChunkFromBridge(
      await _handle.text(
        fieldId: nativeField,
        offset: nativeOffset,
        maxBytes: maxBytes,
      ),
    );
    final bytes = utf8.encode(chunk.text).length;
    if (chunk.fieldId != fieldId ||
        chunk.offset != offset ||
        bytes > maxBytes ||
        chunk.nextOffset != null &&
            (bytes == 0 || chunk.nextOffset != offset + bytes)) {
      throw adapterProtocol('metrics-identity-text-progress');
    }
    return chunk;
  });

  @override
  void requestClose() => _owner.requestClose();
  @override
  Future<FeedCloseReport> close() => _owner.close();
  @override
  Future<FeedCloseReport> retryClose() => _owner.retryClose();
}

const _textArguments = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'Metrics identity text requires 4..262144 UTF-8 bytes',
  retryable: false,
  correlationId: 'adapter-metrics-identity-text-limit',
);
