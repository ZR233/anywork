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
  await tester.runAsync(() async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        release ? 'POST' : 'GET',
        provider.resolve('/__timeline_concept/$stage'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 35),
      );
      await response.drain<void>();
      expect(
        response.statusCode,
        HttpStatus.noContent,
        reason: 'Strict fixture ${release ? 'release' : 'reach'} $stage',
      );
    } finally {
      client.close(force: true);
    }
  });
}
