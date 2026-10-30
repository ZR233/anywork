import 'dart:async';

import 'package:anywork/src/app/anywork_app.dart';
import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/app/routing/app_route.dart';
import 'package:anywork/src/app/studio_host_lifecycle.dart';
import 'package:anywork/src/features/settings/settings_general_tab.dart';
import 'package:anywork/src/features/settings/settings_section.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/pump_client_future.dart';
import 'support/recording_demo_transport.dart';
import 'support/test_statistics_feed.dart';

class _LanguageTransport extends RecordingDemoTransport {
  Completer<void>? gate;
  final entered = Completer<void>();
  bool failNextLanguage = false;

  @override
  Future<SettingsCommandReply> applySettingsField(
    int revision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  }) async {
    if (command is GeneralLanguageCommand) {
      if (!entered.isCompleted) entered.complete();
      await gate?.future;
      if (failNextLanguage) {
        failNextLanguage = false;
        throw const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'language-save-failed',
          retryable: false,
          correlationId: 'language-rejection',
        );
      }
    }
    return super.applySettingsField(
      revision,
      command,
      operationId: operationId,
    );
  }
}

void main() {
  testWidgets(
    'interface language follows canonical saves and resumes system changes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        StudioHostLifecycle.channel,
        (call) async => call.method == 'beginExit' ? 10000 : null,
      );
      final transport = _LanguageTransport();
      final graph = AppGraph(
        transport: transport,
        statisticsFeed: const TestStatisticsFeedPort(),
        clientId: 'ui-language',
      );
      Future<void>? closing;
      var closeSettled = false;
      Future<void> closeOwnedResources() async {
        final gate = transport.gate;
        if (gate != null && !gate.isCompleted) gate.complete();
        // Language behavior uses the real app. At unmount there is no native
        // process to exit: isolate that host hook, then join every app owner
        // explicitly below instead of racing shutdown against widget disposal.
        StudioExitCoordinator.install(
          StudioExitCoordinator(
            transport,
            (_) {},
            shutdownOverride: () async {},
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpClientFuture(
          tester,
          StudioExitCoordinator.requestExit(),
          'exit language fixture',
        );
        final report = await pumpClientFuture(
          tester,
          graph.close(deadline: DateTime.now().add(const Duration(seconds: 5))),
          'close language fixture',
        );
        expect(
          report.unresolved.map(
            (resource) => '${resource.owner}: ${resource.reason}',
          ),
          isEmpty,
        );
        final exit = await pumpClientFuture(
          tester,
          transport.shutdownRuntime(remainingMs: 5000),
          'close language transport',
        );
        expect(exit.shutdown.isClean, isTrue);
        messenger.setMockMethodCallHandler(StudioHostLifecycle.channel, null);
      }

      Future<void> close() =>
          closing ??= closeOwnedResources().whenComplete(() {
            closeSettled = true;
          });
      addTearDown(() async {
        if (!closeSettled) await close();
      });

      await pumpClientFuture(tester, graph.initialize(), 'bootstrap language');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appGraphProvider.overrideWithValue(graph)],
          child: const AnyworkApp(),
        ),
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final router = app.routerConfig! as GoRouter;
      router.go(const SettingsRoute(section: SettingsSection.general).location);
      final menu = find.byType(DropdownMenu<UiLanguage>);
      await pumpClientUntil(
        tester,
        () => menu.evaluate().isNotEmpty,
        'general',
      );
      await tester.pump();

      String currentLanguage() =>
          Localizations.localeOf(tester.element(find.byType(GeneralTab)))
              .languageCode;
      UiLanguage selected() =>
          tester.widget<DropdownMenu<UiLanguage>>(menu).initialSelection!;
      Future<void> choose(String label) async {
        final field = find.descendant(
          of: menu,
          matching: find.byType(TextField),
        );
        await Scrollable.ensureVisible(tester.element(field), alignment: 0.5);
        await tester.pumpAndSettle();
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pump();
      }

      expect(currentLanguage(), 'en');
      expect(selected(), UiLanguage.system);
      transport.gate = Completer<void>();
      await choose('简体中文');
      await pumpClientUntil(
        tester,
        () => transport.entered.isCompleted,
        'pending language save',
      );
      await tester.pump();
      expect(currentLanguage(), 'en');
      expect(selected(), UiLanguage.system);
      expect(tester.widget<DropdownMenu<UiLanguage>>(menu).enabled, isFalse);
      transport.gate!.complete();
      await pumpClientUntil(
        tester,
        () =>
            currentLanguage() == 'zh' &&
            selected() == UiLanguage.zh &&
            tester.widget<DropdownMenu<UiLanguage>>(menu).enabled,
        'confirmed Chinese',
      );
      transport.gate = null;
      expect(find.text('界面语言'), findsWidgets);

      // An explicit selection survives subsequent host locale changes.
      tester.platformDispatcher.localesTestValue = [const Locale('fr', 'FR')];
      await tester.pumpAndSettle();
      expect(currentLanguage(), 'zh');
      tester.platformDispatcher.localesTestValue = [const Locale('zh', 'CN')];
      await tester.pumpAndSettle();
      await choose('English');
      await pumpClientUntil(
        tester,
        () =>
            currentLanguage() == 'en' &&
            selected() == UiLanguage.en &&
            tester.widget<DropdownMenu<UiLanguage>>(menu).enabled,
        'confirmed English',
      );

      transport.failNextLanguage = true;
      await choose('Follow system');
      await pumpClientUntil(
        tester,
        () => find.textContaining('language-save-failed').evaluate().isNotEmpty,
        'failed language save',
      );
      expect(currentLanguage(), 'en');
      expect(selected(), UiLanguage.en);
      expect(tester.widget<DropdownMenu<UiLanguage>>(menu).enabled, isTrue);

      await choose('Follow system');
      await pumpClientUntil(
        tester,
        () => currentLanguage() == 'zh' && selected() == UiLanguage.system,
        'resume system language',
      );
      tester.platformDispatcher.localesTestValue = [const Locale('en', 'US')];
      await tester.pumpAndSettle();
      expect(currentLanguage(), 'en');
      tester.platformDispatcher.localesTestValue = [const Locale('fr', 'FR')];
      await tester.pumpAndSettle();
      expect(currentLanguage(), 'en');
      expect(selected(), UiLanguage.system);
      expect(tester.takeException(), isNull);
      await close();
    },
  );
}
