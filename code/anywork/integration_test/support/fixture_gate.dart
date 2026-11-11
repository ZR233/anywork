import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Controls only the strict loopback provider. It neither reads nor changes
/// product state; assertions still consume the production widgets/controllers.
Future<void> fixtureGate(
  WidgetTester tester,
  Uri provider,
  String stage, {
  bool release = false,
}) async {
  await tester.runAsync(
    () => _fixtureGateRequest(provider, stage, release: release),
  );
}

/// Starts real HTTP I/O without holding a tester guard while frames are sampled.
///
/// Returns a completion future that the caller must join to propagate any
/// request failure.
Future<({Future<void> completed})> beginFixtureGateRelease(
  WidgetTester tester,
  Uri provider,
  String stage, {
  void Function(String phase)? onProgress,
}) async {
  final started = await tester.runAsync(
    () async => (
      completed: _fixtureGateRequest(
        provider,
        stage,
        release: true,
        onProgress: onProgress,
      ),
    ),
  );
  return started!;
}

Future<void> _fixtureGateRequest(
  Uri provider,
  String stage, {
  required bool release,
  void Function(String phase)? onProgress,
}) async {
  final client = HttpClient();
  try {
    onProgress?.call('requestStarted');
    final request = await client.openUrl(
      release ? 'POST' : 'GET',
      provider.resolve('/__timeline_concept/$stage'),
    );
    final response = await request.close().timeout(const Duration(seconds: 35));
    onProgress?.call('responseHeaders');
    await response.drain<void>();
    onProgress?.call('responseDrained');
    if (response.statusCode != HttpStatus.noContent) {
      throw StateError(
        'Strict fixture ${release ? 'release' : 'reach'} $stage: '
        'expected ${HttpStatus.noContent}, actual ${response.statusCode}',
      );
    }
  } finally {
    client.close(force: true);
  }
}
