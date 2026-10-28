// 受众条的持续显示契约（design/27 §27.8、design/29 §29.5）。
//
// 覆盖：普通未绑定会话不出现任何受众或绑定入口；已核实目标在无授权头时只提供携带空
// 授权头 CAS 的显式启用；各同步状态与积压摘要持续可见；无法证明归属时不退化成可绑定
// 界面。像素布局与截图由 Driver 人工证据覆盖。
import 'dart:async';

import 'package:anywork/src/features/status/thread_audience_notice.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/presentation/providers/client_provider.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/audience_fixture.dart';

Widget _host(AnyworkClient client, {bool controls = true}) => ProviderScope(
  overrides: [anyworkClientProvider.overrideWithValue(client)],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ThreadAudienceNotice(threadId: 'thread', controls: controls),
    ),
  ),
);

/// Unmount first so the scope releases its own observation, then join the owner
/// inside the test body: `testWidgets` runs on a fake clock, so an awaited
/// shutdown in `tearDown` could never advance its timers.
Future<void> _close(WidgetTester tester, AnyworkClient client) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await client.close(deadline: DateTime.now().add(const Duration(seconds: 5)));
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(ThreadAudienceNotice)));

Finder _action(BotThreadSyncAction action) =>
    find.byKey(ValueKey('audience-${action.name}:thread'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an ordinary unbound Thread shows no audience strip at all', (
    tester,
  ) async {
    final transport = AudienceTransport();
    final client = audienceClient(transport);
    addTearDown(() => unawaited(client.close()));
    client
        .session('thread')
        .applySnapshot(audienceWorkspace(const ThreadAudienceUnbound()));
    await tester.pumpWidget(_host(client));
    await tester.pump();
    // No target, no phase and no arbitrary bind/broadcast entry: unbound is not
    // a state the user can act on from here.
    expect(
      find.descendant(
        of: find.byType(ThreadAudienceNotice),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(find.byType(TextButton), findsNothing);
    expect(transport.controls, isEmpty);
    await _close(tester, client);
  });

  testWidgets(
    'a verified target without an authorization head offers only the empty-head Enable',
    (tester) async {
      final transport = AudienceTransport();
      final client = audienceClient(transport);
      addTearDown(() => unawaited(client.close()));
      final session = client.session('thread');
      session.applySnapshot(
        audienceWorkspace(
          knownAudience(phase: 'closed', neverAuthorized: true),
        ),
      );
      await tester.pumpWidget(_host(client));
      await tester.pump();
      final l10n = _l10n(tester);
      expect(find.text(l10n.audienceClosed), findsOneWidget);
      expect(find.text(l10n.audienceGroup), findsOneWidget);
      expect(
        find.textContaining(audienceTarget.chatName!),
        findsOneWidget,
        reason: 'the verified target stays visible without an authorization',
      );
      expect(_action(BotThreadSyncAction.enable), findsOneWidget);
      for (final action in [
        BotThreadSyncAction.pause,
        BotThreadSyncAction.resume,
        BotThreadSyncAction.close,
      ]) {
        expect(
          _action(action),
          findsNothing,
          reason: 'a closed target without a head has no other control',
        );
      }
      await tester.tap(_action(BotThreadSyncAction.enable));
      await tester.pump();
      final call = await transport.nextControl();
      expect(
        call.request.expected,
        const BotSyncCas(
          bindingRevision: 3,
          authorizationHead: BotAuthorizationHeadNone(),
        ),
        reason: 'the first authorization is created from the empty head',
      );
      expect(call.request.action, BotThreadSyncAction.enable);
      expect(call.request.threadId, 'thread');
      // The durable prepare is reported as pending, never as an effective
      // boundary or a platform delivery.
      call.complete(
        knownAudience(generation: 1, phase: 'pending'),
        pending: true,
        effective: false,
      );
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.audienceOperationPending), findsOneWidget);
      await tester.tap(
        _action(BotThreadSyncAction.enable),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(
        transport.controls,
        hasLength(1),
        reason: 'a pending intent cannot be re-submitted as a new operation',
      );
      expect(session.state.audience.known!.latestClosed, isNull);
      await _close(tester, client);
    },
  );

  testWidgets(
    'every resolved sync state keeps naming target, phase and backlog',
    (tester) async {
      final transport = AudienceTransport();
      final client = audienceClient(transport);
      addTearDown(() => unawaited(client.close()));
      final session = client.session('thread');
      session.applySnapshot(audienceWorkspace(knownAudience(phase: 'pending')));
      await tester.pumpWidget(_host(client));
      await tester.pump();
      var l10n = _l10n(tester);
      expect(find.text(l10n.audiencePendingStart), findsOneWidget);
      expect(find.textContaining(l10n.audiencePendingItems), findsOneWidget);
      expect(find.text(l10n.audienceGroup), findsOneWidget);
      expect(_action(BotThreadSyncAction.close), findsOneWidget);
      expect(
        _action(BotThreadSyncAction.enable),
        findsNothing,
        reason: 'PendingStart may not be re-enabled',
      );
      session.applySnapshot(audienceWorkspace(knownAudience(), revision: 2));
      await tester.pump();
      l10n = _l10n(tester);
      expect(find.text(l10n.audienceActive), findsOneWidget);
      expect(_action(BotThreadSyncAction.pause), findsOneWidget);
      expect(_action(BotThreadSyncAction.close), findsOneWidget);
      session.applySnapshot(
        audienceWorkspace(knownAudience(phase: 'paused'), revision: 3),
      );
      await tester.pump();
      l10n = _l10n(tester);
      expect(
        find.text(l10n.audiencePaused),
        findsOneWidget,
        reason: 'paused states the resend obligation instead of looking idle',
      );
      expect(_action(BotThreadSyncAction.resume), findsOneWidget);
      // Unproven ownership is not a bindable unbound conversation, and it must
      // not keep offering controls for a target it can no longer prove.
      session.applySnapshot(
        audienceWorkspace(
          const ThreadAudienceUnavailable(
            reason: ThreadAudienceUnavailableReason.ownershipUnproven,
          ),
          revision: 4,
        ),
      );
      await tester.pump();
      l10n = _l10n(tester);
      expect(find.text(l10n.audienceUnavailable), findsOneWidget);
      expect(
        find.textContaining(
          ThreadAudienceUnavailableReason.ownershipUnproven.name,
        ),
        findsOneWidget,
      );
      expect(find.byType(TextButton), findsNothing);
      expect(transport.controls, isEmpty);
      expect(transport.reads, isEmpty);
      await _close(tester, client);
    },
  );
}
