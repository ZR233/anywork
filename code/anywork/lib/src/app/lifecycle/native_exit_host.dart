import 'dart:async';

import 'package:flutter/services.dart';

import '../../platform/error_log.dart';

/// Instance-scoped binding to the existing native host protocol. In particular
/// showMainWindow/setTrayAvailable are visibility operations, not shutdown.
final class NativeExitHost {
  NativeExitHost({
    MethodChannel channel = const MethodChannel(
      'io.github.zr233.anywork/host_lifecycle',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;
  Object? _binding;

  Future<int> beginExit() async {
    final remainder = await _channel
        .invokeMethod<int>('beginExit')
        .timeout(const Duration(seconds: 2));
    if (remainder == null || remainder < 0 || remainder > 30000) {
      throw const FormatException('Invalid native exit remainder');
    }
    return remainder;
  }

  void bind(Object owner, Future<void> Function() requestExit) {
    if (_binding != null && !identical(_binding, owner)) {
      throw StateError('The native host already has an application owner');
    }
    _binding = owner;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'requestExit') throw MissingPluginException();
      await requestExit();
    });
  }

  void unbind(Object owner) {
    if (!identical(_binding, owner)) return;
    _binding = null;
    _channel.setMethodCallHandler(null);
  }

  Future<void> configureDiagnostics() async {
    final directory = studioLogDirectory();
    if (directory == null) return;
    await _channel.invokeMethod<void>('configureDiagnostics', {
      'directory': directory,
    }).timeout(const Duration(seconds: 2));
  }

  Future<void> setTrayAvailable(bool available) => _channel.invokeMethod<void>(
    'setTrayAvailable',
    {'available': available},
  ).timeout(const Duration(seconds: 2));

  Future<void> showMainWindow() => _channel
      .invokeMethod<void>('showMainWindow')
      .timeout(const Duration(seconds: 2));

  Future<void> updateDiagnostics({
    required String stage,
    String? code,
    String? correlationId,
    int? pendingCommits,
    required Duration remaining,
  }) => _boundedSend('updateExitDiagnostics', {
    'stage': stage,
    if (code != null) 'code': code,
    if (correlationId != null) 'correlationId': correlationId,
    if (pendingCommits != null) 'pendingCommits': pendingCommits,
  }, remaining);

  Future<void> finishExit({
    required int exitCode,
    required Duration remaining,
  }) => _boundedSend('finishExit', {'exitCode': exitCode}, remaining);

  Future<void> _boundedSend(
    String method,
    Map<String, Object?> arguments,
    Duration remaining,
  ) async {
    final call = _channel.invokeMethod<void>(method, arguments);
    if (remaining <= Duration.zero) {
      // Sending at the end of the existing deadline must not create a new one.
      unawaited(call.catchError((Object error, StackTrace stack) {
        recordDartError(error, stack, stage: 'host-exit');
      }));
      return;
    }
    await call.timeout(remaining);
  }
}
