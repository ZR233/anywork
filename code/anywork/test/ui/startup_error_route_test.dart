import '../support/test_statistics_feed.dart';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/pump_client_future.dart';
import '../support/recording_demo_transport.dart';

void main() {
  testWidgets('startup failure renders an explicit retry', (tester) async {
    final failure = StudioFailure(
      code: StudioFailureCode.internal,
      message: 'startup failed before any baseline',
      retryable: true,
      correlationId: 'startup-route-failure',
    );
    final transport = _StartupFailureTransport(failure);
    final graph = AppGraph(
      statisticsFeed: const TestStatisticsFeedPort(),
      transport: transport,
      clientId: 'startup-route',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpClientFuture(
        tester,
        graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
        'startup failure teardown',
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appGraphProvider.overrideWithValue(graph)],
        child: const AnyworkApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l10n.runtimeFatalTitle), findsOneWidget);
    expect(transport.attempts, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final retry = find.byKey(const ValueKey('runtime-fatal-retry'));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await pumpClientUntil(
      tester,
      () => graph.client.settings.state.configLoaded,
      'explicit startup retry',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.startPage), findsOneWidget);
    expect(transport.attempts, 2);
    expect(tester.takeException(), isNull);
    // testWidgets 在测试体结束后才检查未完成定时器；主题订阅的稳定窗口必须在此之前关闭。
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpClientFuture(
      tester,
      graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
      'startup failure close',
    );
  });
}

final class _StartupFailureTransport extends RecordingDemoTransport {
  _StartupFailureTransport(this.failure);

  final StudioFailure failure;
  int attempts = 0;

  @override
  Future<StudioBootstrap> readBootstrap() {
    if (++attempts == 1) return Future.error(failure);
    return super.readBootstrap();
  }
}
