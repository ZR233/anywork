// Host-side Flutter content capture. Connects with the locked vm_service
// client and writes PNG bytes returned by ext.anywork.capture.
//
// Run with the app package_config so native build hooks are not re-entered:
// cargo dart --packages=.dart_tool/package_config.json tool/capture_ui.dart \
//   --run-info <file> --view <id> --output <png>
// cargo dart --packages=.dart_tool/package_config.json tool/capture_ui.dart \
//   --vm-url <uri> --output <png> [--exit]
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/capture/capture_protocol.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _usage =
    'usage: tool/capture_ui.dart (--run-info <file> --view <id> --output <png> | '
    '--vm-url <uri> [--output <png>]) [--exit]';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final runInfo = options.runInfo == null
      ? _RunInfo(
          vmServiceUri: options.vmUrl!,
          sourceSha: 'acceptance',
          buildMode: 'debug',
          runId: 'capture',
        )
      : _readRunInfo(File(options.runInfo!));
  final output = options.output == null ? null : File(options.output!);
  VmService? service;
  try {
    service = await vmServiceConnectUri(_webSocketUri(runInfo.vmServiceUri));
    final isolateId = await _isolateForView(service, runInfo, options.view);
    if (output != null) {
      final response = await service
          .callServiceExtension(kCaptureExtensionName, isolateId: isolateId)
          .timeout(const Duration(seconds: 12));
      final payload = response.json;
      if (payload == null) {
        throw StateError(
          'Capture extension returned no payload for $isolateId',
        );
      }
      if (payload['type'] == 'Error' || payload.containsKey('code')) {
        throw StateError(
          'Capture extension failed for $isolateId: ${payload['message'] ?? payload}',
        );
      }
      final encoded = payload['pngBase64'];
      if (encoded is! String || encoded.isEmpty) {
        throw StateError('Capture extension returned no PNG for $isolateId');
      }
      final png = base64Decode(encoded);
      if (png.isEmpty) {
        throw StateError(
          'Capture extension returned an empty PNG for $isolateId',
        );
      }
      final capturedAt = DateTime.now().toUtc().toIso8601String();
      final appMeta = payload['meta'];
      final meta = <String, Object?>{
        'sourceSha': runInfo.sourceSha,
        'buildMode': runInfo.buildMode,
        'runId': runInfo.runId,
        'caseId': runInfo.caseId,
        'capturedAt': capturedAt,
        'isolateId': isolateId,
        'viewId': options.view,
        'route': runInfo.route,
        if (appMeta is Map) ...Map<String, Object?>.from(appMeta),
        'scope': 'flutter-content',
      };
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(png);
      File('${output.path}.meta.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(meta)}\n',
      );
    }
    if (options.exitApp) {
      final exitResponse = await service
          .callServiceExtension(kRequestExitExtensionName, isolateId: isolateId)
          .timeout(const Duration(seconds: 12));
      final exitPayload = exitResponse.json;
      if (exitPayload == null ||
          exitPayload['type'] == 'Error' ||
          exitPayload.containsKey('code')) {
        throw StateError(
          'requestExit failed: ${exitPayload?['message'] ?? exitPayload}',
        );
      }
    }
  } finally {
    await service?.dispose();
  }
}

final class _Options {
  const _Options({
    required this.runInfo,
    required this.vmUrl,
    required this.view,
    required this.output,
    required this.exitApp,
  });

  final String? runInfo;
  final String? vmUrl;
  final String? view;
  final String? output;
  final bool exitApp;
}

final class _RunInfo {
  const _RunInfo({
    required this.vmServiceUri,
    required this.sourceSha,
    required this.buildMode,
    required this.runId,
    this.isolateId,
    this.caseId,
    this.route,
  });

  final String vmServiceUri;
  final String sourceSha;
  final String buildMode;
  final String runId;
  final String? isolateId;
  final String? caseId;
  final String? route;
}

_Options? _parseArgs(List<String> args) {
  String? runInfo;
  String? vmUrl;
  String? view;
  String? output;
  var exitApp = false;
  for (var i = 0; i < args.length; i++) {
    final flag = args[i];
    switch (flag) {
      case '--exit':
        exitApp = true;
      case '--run-info':
      case '--vm-url':
      case '--view':
      case '--output':
        if (i + 1 >= args.length) return null;
        final value = args[++i];
        switch (flag) {
          case '--run-info':
            runInfo = value;
          case '--vm-url':
            vmUrl = value;
          case '--view':
            view = value;
          case '--output':
            output = value;
        }
      default:
        return null;
    }
  }
  final hasRunInfo =
      runInfo != null &&
      runInfo.isNotEmpty &&
      view != null &&
      view.isNotEmpty &&
      output != null &&
      output.isNotEmpty;
  final hasVmUrl =
      vmUrl != null && vmUrl.isNotEmpty && runInfo == null && view == null;
  if (hasRunInfo == hasVmUrl) return null;
  if (!hasRunInfo && (output == null || output.isEmpty) && !exitApp) {
    return null;
  }
  return _Options(
    runInfo: runInfo,
    vmUrl: vmUrl,
    view: view,
    output: output,
    exitApp: exitApp,
  );
}

_RunInfo _readRunInfo(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    throw StateError('run-info must be a JSON object: ${file.path}');
  }
  final uri = decoded['vmServiceUri'];
  final sha = decoded['sourceSha'];
  final mode = decoded['buildMode'];
  final runId = decoded['runId'];
  if (uri is! String || uri.isEmpty) {
    throw StateError('run-info is missing vmServiceUri');
  }
  if (sha is! String || sha.isEmpty) {
    throw StateError('run-info is missing sourceSha');
  }
  if (mode is! String || mode.isEmpty) {
    throw StateError('run-info is missing buildMode');
  }
  if (runId is! String || runId.isEmpty) {
    throw StateError('run-info is missing runId');
  }
  return _RunInfo(
    vmServiceUri: uri,
    sourceSha: sha,
    buildMode: mode,
    runId: runId,
    isolateId: decoded['isolateId'] is String
        ? decoded['isolateId'] as String
        : null,
    caseId: decoded['caseId'] is String ? decoded['caseId'] as String : null,
    route: decoded['route'] is String ? decoded['route'] as String : null,
  );
}

String _webSocketUri(String raw) {
  final uri = Uri.parse(raw);
  final scheme = switch (uri.scheme) {
    'http' => 'ws',
    'https' => 'wss',
    'ws' || 'wss' => uri.scheme,
    _ => throw StateError('Unsupported VM service URI scheme: ${uri.scheme}'),
  };
  var path = uri.path;
  if (!path.endsWith('/ws')) {
    path = path.endsWith('/') ? '${path}ws' : '$path/ws';
  }
  return uri.replace(scheme: scheme, path: path).toString();
}

Future<String> _isolateForView(
  VmService service,
  _RunInfo runInfo,
  String? viewId,
) async {
  if (viewId != null) {
    final listed = await _flutterViews(service);
    if (listed != null) {
      final match = listed.where((view) => view.id == viewId).toList();
      if (match.length != 1) {
        throw StateError(
          'Unknown Flutter view $viewId; known: ${listed.map((view) => view.id).join(', ')}',
        );
      }
      final isolateId = match.single.isolateId;
      if (isolateId == null || isolateId.isEmpty) {
        throw StateError('Flutter view $viewId has no isolate');
      }
      return isolateId;
    }
    if (runInfo.isolateId case final recorded?
        when recorded.isNotEmpty && recorded == viewId) {
      return recorded;
    }
  }
  if (runInfo.isolateId case final recorded? when recorded.isNotEmpty) {
    return recorded;
  }
  final vm = await service.getVM();
  final isolates = vm.isolates ?? const <IsolateRef>[];
  final withCapture = <String>[];
  for (final isolate in isolates) {
    final id = isolate.id;
    if (id == null) continue;
    final detail = await service.getIsolate(id);
    final rpcs = detail.extensionRPCs ?? const <String>[];
    if (rpcs.contains(kCaptureExtensionName) ||
        rpcs.contains(kRequestExitExtensionName)) {
      withCapture.add(id);
    }
  }
  if (withCapture.length == 1) return withCapture.single;
  throw StateError(
    'Could not resolve an isolate with ext.anywork.capture or ext.anywork.requestExit',
  );
}

Future<List<_FlutterView>?> _flutterViews(VmService service) async {
  try {
    final response = await service.callMethod('_flutter.listViews');
    final views = response.json?['views'];
    if (views is! List) return const [];
    return [
      for (final view in views)
        if (view is Map)
          _FlutterView(
            id: view['id'] as String? ?? '',
            isolateId: (view['isolate'] as Map?)?['id'] as String?,
          ),
    ];
  } on RPCError catch (error) {
    if (error.code == RPCErrorKind.kMethodNotFound.code) return null;
    rethrow;
  }
}

final class _FlutterView {
  const _FlutterView({required this.id, required this.isolateId});

  final String id;
  final String? isolateId;
}
