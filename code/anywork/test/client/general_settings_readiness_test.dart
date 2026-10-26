import 'dart:async';

import 'package:anywork/src/app/app_bindings.dart';
import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/settings/general/connectors/general_settings_connector.dart';
import 'package:anywork/src/features/settings/general/state/general_settings_state.dart';
import 'package:anywork/src/features/settings/general/view_models/general_settings_view_model.dart';
import 'package:anywork/src/features/settings/general/view_models/settings_readiness_view_model.dart';
import 'package:anywork/src/features/settings/general/views/general_settings_view.dart';
import 'package:anywork/src/features/settings/connectors/settings_navigation_connector.dart';
import 'package:anywork/src/features/settings/settings_screen.dart';
import 'package:anywork/src/features/settings/state/settings_navigation_state.dart';
import 'package:anywork/src/features/settings/view_models/settings_navigation_view_model.dart';
import 'package:anywork/src/features/settings/views/settings_view.dart';
import 'package:anywork/src/features/settings/widgets/settings_pane.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../anywork_client/test/support/profile_model_port.dart';
import '../../../anywork_client/test/support/profile_native_pin.dart';
import 'support/pump_client_future.dart';
import 'support/selector_configuration_port.dart';

void main() {
  testWidgets(
    'Settings navigation readiness never exposes tabs or default controls before public configuration',
    (tester) async {
      final env = await _environment(tester);
      late WidgetRef routeRef;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: FilledButton(
                key: const ValueKey('open-settings'),
                onPressed: () => GoRouter.of(context).push<void>('/settings'),
                child: const Text('Open Settings'),
              ),
            ),
            routes: [
              GoRoute(
                path: 'settings',
                builder: (_, state) =>
                    const SettingsScreen(initialTab: SettingsTab.security),
                onExit: (context, state) =>
                    confirmLeaveSettings(context, routeRef),
              ),
            ],
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: env.container,
          child: Consumer(
            builder: (context, ref, child) {
              routeRef = ref;
              return MaterialApp.router(
                theme: pureStudioTheme(),
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routerConfig: router,
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await pumpClientFuture(
        tester,
        env.port.gate(1).entered.future,
        'first public configuration read',
      );
      await tester.pump();
      expect(
        env.container
            .read(settingsNavigationViewModelProvider)
            .requireValue
            .visible,
        isTrue,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SettingsView), findsNothing);
      expect(find.byKey(StudioDriverKeys.settingsPage), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(SettingsPane), findsNothing);
      expect(env.modelsPort.pageCalls, isEmpty);

      env.port.gate(1).reply.completeError(_failure);
      await pumpClientUntil(
        tester,
        () => find.textContaining(_failure.message).evaluate().isNotEmpty,
        'whole-page configuration failure',
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SettingsView), findsNothing);
      expect(find.byType(SettingsPane), findsNothing);
      expect(
        find.ancestor(
          of: find.textContaining(_failure.message),
          matching: find.byType(Center),
        ),
        findsOneWidget,
      );
      final page = find.byType(SettingsScreen);
      expect(
        find.descendant(of: page, matching: find.byType(TextButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: page, matching: find.byType(FilledButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: page, matching: find.byType(ElevatedButton)),
        findsNothing,
      );
      final owner = env.container.read(
        settingsReadinessViewModelProvider.notifier,
      );
      final failedReads = env.port.gate(1).reads;
      await tester.pump();
      await tester.pump();
      expect(
        env.port.gate(1).reads,
        failedReads,
        reason: 'Ordinary notifications/frames do not retry',
      );
      final pop = tester.widget<PopScope<void>>(
        find.descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(PopScope<void>),
        ),
      );
      pop.onPopInvokedWithResult!(false, null);
      await pumpClientUntil(
        tester,
        () => find.byKey(const ValueKey('open-settings')).evaluate().isNotEmpty,
        'leave failed Settings',
      );
      await tester.pumpAndSettle();
      final retryGate = env.port.resetGate(1);
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await pumpClientFuture(
        tester,
        retryGate.entered.future,
        'explicit same-source reentry',
      );
      expect(
        env.container.read(settingsReadinessViewModelProvider.notifier),
        same(owner),
      );
      expect(find.byType(SettingsView), findsNothing);
      final joined = owner.enter(Object());
      final joinedAgain = owner.enter(Object());
      expect(identical(joined, joinedAgain), isTrue);
      final pendingReads = retryGate.reads;
      await tester.pump();
      expect(
        retryGate.reads,
        pendingReads,
        reason: 'In-flight entries join instead of duplicating the first read',
      );
      retryGate.reply.complete();
      await pumpClientFuture(tester, joined, 'joined reentry read');
      await pumpClientUntil(
        tester,
        () => find.byType(SettingsView).evaluate().isNotEmpty,
        'same-source recovery ready',
      );
      expect(
        env.container
            .read(settingsReadinessViewModelProvider)
            .requireValue
            .readyOrigin,
        selectorOrigin,
      );
      expect(
        env.configuration.state.value.general,
        isA<ReadyReadValue<GeneralSettings, ConfigurationReadRef>>(),
      );
      expect(
        env.configuration.state.value.projection.header!.reference,
        const ConfigurationReadRef(entry: 1, revision: 1),
      );
    },
  );

  testWidgets(
    'a new complete origin cannot borrow old previous material or the old ready record',
    (tester) async {
      final env = await _environment(tester);
      env.port.gate(1).reply.complete();
      await pumpClientFuture(
        tester,
        Future.wait([
          env.configuration.loadGeneralSettings(),
          env.configuration.loadWebSearchSettings(),
          env.configuration.loadDeepSeekSettings(),
        ]),
        'original source material',
      );
      final provider = settingsReadinessViewModelProvider;
      final watch = env.container.listen(provider, (_, _) {});
      addTearDown(watch.close);
      await pumpClientFuture(
        tester,
        env.container.read(provider.future),
        'original ready proof',
      );
      final owner = env.container.read(provider.notifier);
      var entry = Object();
      await owner.enter(entry);
      expect(
        env.container.read(provider).requireValue.readyOrigin,
        selectorOrigin,
      );
      var previousOrigin = selectorOrigin;
      var feed = env.port.base.base.feed;
      final replacements = [
        ProductReadOrigin(
          ownerEpoch: selectorOrigin.ownerEpoch,
          incarnation: selectorOrigin.incarnation + 1,
        ),
        const ProductReadOrigin(
          ownerEpoch: 'replacement-settings-owner',
          incarnation: 1,
        ),
      ];
      for (var index = 0; index < replacements.length; index++) {
        final origin = replacements[index];
        env.port.origins.add(origin);
        feed.emit(
          ConfigurationFrame.closed(
            identity: profileIdentity(
              feed.feedId,
              previousOrigin,
              ProductResource.configuration,
            ),
            reason: ProductFeedCloseReason.ownerReplaced,
          ),
        );
        final opening = await pumpClientFuture(
          tester,
          env.port.base.base.configurationOpened(index + 1),
          'replacement source open',
        );
        feed = opening.acceptNew('general-origin-${index + 1}');
        await pumpClientFuture(
          tester,
          env.port.base.base.publishCasBaseline(feed, 1, sourceOrigin: origin),
          'replacement source baseline',
        );
        final gate = env.port.gate(1, origin: origin);
        await pumpClientFuture(
          tester,
          gate.entered.future,
          'replacement exact fields',
        );
        final originalReading = owner.enter(entry);
        expect(
          env.configuration.state.value.general,
          isA<LoadingReadValue<GeneralSettings, ConfigurationReadRef>>().having(
            (read) => read.previous?.origin,
            'original previous owner',
            previousOrigin,
          ),
        );
        expect(env.container.read(provider).requireValue.ready, isFalse);
        gate.reply.completeError(_failure);
        await pumpClientFuture(
          tester,
          originalReading,
          'original replacement failure settled',
        );
        await pumpClientUntil(
          tester,
          () => env.container.read(provider).value?.error != null,
          'replacement read failure',
        );
        expect(env.container.read(provider).requireValue.ready, isFalse);
        expect(env.container.read(provider).requireValue.readyOrigin, isNull);
        expect(
          env.configuration.state.value.general,
          isA<FailedReadValue<GeneralSettings, ConfigurationReadRef>>().having(
            (read) => read.previous?.origin,
            'last-known original owner',
            previousOrigin,
          ),
        );
        final ready = env.port.resetGate(1, origin: origin);
        owner.leave(entry);
        entry = Object();
        final reading = owner.enter(entry);
        await pumpClientFuture(
          tester,
          ready.entered.future,
          'explicit replacement read',
        );
        expect(env.container.read(provider).requireValue.ready, isFalse);
        ready.reply.complete();
        await pumpClientFuture(tester, reading, 'replacement current material');
        await pumpClientUntil(
          tester,
          () => env.container.read(provider).value?.ready == true,
          'replacement ready proof',
        );
        expect(env.container.read(provider).requireValue.readyOrigin, origin);
        expect(
          env.configuration.state.value.general,
          isA<ReadyReadValue<GeneralSettings, ConfigurationReadRef>>()
              .having(
                (read) => read.current.origin,
                'actual current owner',
                origin,
              )
              .having(
                (read) => read.current.reference,
                'actual current reference',
                const ConfigurationReadRef(entry: 1, revision: 1),
              ),
        );
        previousOrigin = origin;
      }
      owner.leave(entry);
    },
  );

  testWidgets(
    'the public configuration gate reaches ready without mounting hidden General or Updates work',
    (tester) async {
      final env = await _environment(tester);
      await tester.pumpWidget(
        _harness(env, const SettingsScreen(initialTab: SettingsTab.security)),
      );
      await pumpClientFuture(
        tester,
        env.port.gate(1).entered.future,
        'public configuration preparation',
      );
      env.port.gate(1).reply.complete();
      await pumpClientUntil(
        tester,
        () => find.byType(SettingsView).evaluate().isNotEmpty,
        'ready Settings shell',
      );
      expect(
        env.container
            .read(settingsReadinessViewModelProvider)
            .requireValue
            .ready,
        isTrue,
      );
      expect(find.byType(SettingsView), findsOneWidget);
      expect(find.byType(GeneralSettingsView), findsNothing);
      expect(
        env.configuration.state.value.delegation,
        isNot(isA<ReadyReadValue<DelegationSettings, ConfigurationReadRef>>()),
      );
      expect(env.modelsPort.pageCalls, isEmpty);
      expect(
        env.modelsPort.catalogHeaders,
        isEmpty,
        reason: 'A shell placeholder must not start hidden model policy reads',
      );
    },
  );

  testWidgets(
    'General has no title, fake appearance values or sections before its first canonical value',
    (tester) async {
      final env = await _environment(tester);
      await tester.pumpWidget(_harness(env, const GeneralSettingsConnector()));
      await pumpClientFuture(
        tester,
        env.port.gate(1).entered.future,
        'initial General query',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SettingsPane), findsNothing);
      expect(find.byType(SettingsSection), findsNothing);
      expect(find.byType(Switch), findsNothing);
      env.port.gate(1).reply.completeError(_failure);
      await pumpClientUntil(
        tester,
        () => find.textContaining(_failure.message).evaluate().isNotEmpty,
        'General initial failure',
      );
      expect(find.byType(SettingsPane), findsNothing);
      expect(find.byType(SettingsSection), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'ready General hides missing delegation, adopts actual defaults in order and retains dirty content during failed refresh',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final env = await _environment(tester);
      env.port.gate(1).reply.complete();
      // General is not visible yet: its independent delegation demand must not
      // turn an unread field into a default-valued section.
      await tester.pumpWidget(_harness(env, const _GeneralContent()));
      await pumpClientFuture(
        tester,
        env.container.read(generalSettingsViewModelProvider.future),
        'initial General values',
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(GeneralSettingsView)),
      );
      expect(find.text(l10n.delegationSettingsTitle), findsNothing);
      expect(find.byKey(StudioDriverKeys.defaultDelegationMode), findsNothing);
      final follow = find.descendant(
        of: find.byKey(const ValueKey('general-follow-active-turn')),
        matching: find.byType(Switch),
      );
      final compact = find.descendant(
        of: find.byKey(const ValueKey('general-compact-timeline')),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(follow).value, isTrue);
      expect(tester.widget<Switch>(compact).value, isTrue);
      final readiness = env.container.listen(
        settingsReadinessViewModelProvider,
        (_, _) {},
      );
      addTearDown(readiness.close);
      await pumpClientFuture(
        tester,
        env.container.read(settingsReadinessViewModelProvider.future),
        'public configuration ready',
      );
      await pumpClientFuture(
        tester,
        env.configuration.loadDelegationSettings(),
        'actual delegation defaults',
      );
      await tester.pumpAndSettle();
      final headings = [
        l10n.delegationSettingsTitle,
        l10n.settingsAppearanceGroup,
        l10n.settingsNetworkGroup,
        l10n.settingsUpdatesGroup,
      ];
      for (var index = 0; index < headings.length - 1; index++) {
        expect(
          tester.getTopLeft(find.text(headings[index])).dy,
          lessThan(tester.getTopLeft(find.text(headings[index + 1])).dy),
        );
      }
      expect(
        find.byKey(StudioDriverKeys.defaultDelegationMode),
        findsOneWidget,
      );

      final navigation = env.container.read(
        settingsNavigationViewModelProvider.notifier,
      );
      navigation.enter(SettingsTab.general);
      final vm = env.container.read(generalSettingsViewModelProvider.notifier);
      vm.setDomains('kept.example');
      await tester.pump();
      await pumpClientFuture(
        tester,
        env.port.base.base.publishSettings(2),
        'new configuration version',
      );
      await pumpClientFuture(
        tester,
        env.port.gate(2).entered.future,
        'visible refresh entered',
      );
      expect(find.byType(GeneralSettingsView), findsOneWidget);
      expect(tester.widget<Switch>(follow).value, isTrue);
      expect(
        env.container
            .read(generalSettingsViewModelProvider)
            .requireValue
            .webSearch!
            .domains,
        'kept.example',
      );
      env.port.gate(2).reply.completeError(_failure);
      await pumpClientUntil(
        tester,
        () =>
            env.container
                .read(generalSettingsViewModelProvider)
                .value
                ?.readIssues
                .isNotEmpty ==
            true,
        'failed refresh diagnosis',
      );
      final refreshed = env.container
          .read(generalSettingsViewModelProvider)
          .requireValue;
      expect(refreshed.canonical!.followActiveTurn, isTrue);
      expect(refreshed.canonical!.compactTimeline, isTrue);
      expect(refreshed.webSearch!.domains, 'kept.example');
      expect(
        refreshed.webSearch!.dirtyFields,
        contains(WebSearchField.domains),
      );
      expect(find.byType(GeneralSettingsView), findsOneWidget);
      expect(tester.widget<Switch>(follow).value, isTrue);
      expect(
        env.container
            .read(settingsReadinessViewModelProvider)
            .requireValue
            .ready,
        isTrue,
      );
      expect(find.textContaining(_failure.message), findsWidgets);
    },
  );
}

const _failure = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The original configuration could not be read.',
  retryable: true,
  correlationId: 'general-readiness-test',
);

/// Only assembly: the real VM still owns drafts, observations and failure
/// retention; the view gets immutable values/actions and inert update content.
class _GeneralContent extends ConsumerWidget {
  const _GeneralContent();
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(generalSettingsViewModelProvider)
      .when(
        loading: () => const CircularProgressIndicator(),
        error: (error, stack) => Text(error.toString()),
        data: (state) {
          final vm = ref.read(generalSettingsViewModelProvider.notifier);
          return GeneralSettingsView(
            state: state,
            errors: [
              for (final error in state.readIssues.values) error.message,
            ],
            webErrors: const [],
            deepSeekErrors: const [],
            onFollow: (value) => vm.setFollowActiveTurn(value).ignore(),
            onCompact: (value) => vm.setCompactTimeline(value).ignore(),
            onSearch: (value) => vm.setDeepSeekSearch(value).ignore(),
            onFetch: (value) => vm.setDeepSeekFetch(value).ignore(),
            onMode: vm.setWebMode,
            onContextSize: vm.setWebContextSize,
            onDomains: vm.setDomains,
            onCountry: vm.setCountry,
            onRegion: vm.setRegion,
            onCity: vm.setCity,
            onTimezone: vm.setTimezone,
            onSaveWeb: () => vm.saveWebSearch().ignore(),
            onRetryRead: vm.retryRead,
            onDelegationMode: (value) => vm.setDelegationMode(value).ignore(),
            onDelegationPreference: (value) =>
                vm.setDelegationPreference(value).ignore(),
            delegationReadError:
                state.readIssues[GeneralReadField.delegation]?.message,
            delegationModeErrors: const [],
            delegationPreferenceErrors: const [],
            updates: const Text('Actual updates slot'),
          );
        },
      );
}

Widget _harness(_GeneralEnvironment env, Widget child) =>
    UncontrolledProviderScope(
      container: env.container,
      child: MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

Future<_GeneralEnvironment> _environment(WidgetTester tester) async {
  final env = _GeneralEnvironment();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    env.container.dispose();
    for (final gate in env.port.gates.values) {
      if (!gate.reply.isCompleted) gate.reply.complete();
    }
    final reports = await pumpClientFuture(
      tester,
      Future.wait([env.configuration.close(), env.models.close()]),
      'General owners close',
    );
    expect([for (final report in reports) ...report.unresolved], isEmpty);
    env.operations.seal();
    expect(env.budget.usage, isEmpty);
  });
  await pumpClientFuture(tester, env.establish(), 'General fixture sources ready');
  return env;
}

final class _GeneralEnvironment {
  _GeneralEnvironment() {
    operations = OperationRegistry(
      clientId: 'general-readiness',
      budget: budget,
    );
    final assembly = createModelsRepository(port: modelsPort, budget: budget);
    models = assembly.repository;
    configuration = createConfigurationRepository(
      port: port,
      budget: budget,
      operations: operations,
      modelTargets: assembly.targets,
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        configurationRepositoryProvider.overrideWithValue(configuration),
        modelsRepositoryProvider.overrideWithValue(models),
      ],
    );
  }
  final budget = ResourceBudget();
  final port = _GeneralPort();
  final modelsPort = ProfileModelsPort(
    origin: selectorOrigin,
    accounts: const ['account-0', 'account-1'],
    textEligibleAccounts: const {'account-0', 'account-1'},
  );
  late final OperationRegistry operations;
  late final ModelsRepository models;
  late final ConfigurationRepository configuration;
  late final ProviderContainer container;

  Future<void> establish() async {
    final reads = Future.wait([
      configuration.loadSourceStatus(),
      models.loadSourceStatus(),
    ]);
    await Future.wait([
      port.base.base.feed.listened.future,
      modelsPort.feed.listened.future,
    ]);
    // General demands Configuration, not the paired Profiles feed.
    final configurationBaseline = port.base.base.publishCasBaseline(
      port.base.base.feed,
      1,
    );
    modelsPort.baseline();
    await configurationBaseline;
    await reads;
  }
}

final class _HeaderGate {
  int reads = 0;
  final entered = Completer<void>();
  final reply = Completer<void>();
}

/// Declared native material and a reply barrier only. It does not reduce events,
/// decide readiness, retain last-good data or merge a General editing draft.
final class _GeneralPort implements ConfigurationPort {
  final base = SelectorConfigurationPort();
  final origins = <ProductReadOrigin>{selectorOrigin};
  final gates = <({ProductReadOrigin origin, int revision}), _HeaderGate>{};
  _HeaderGate gate(int revision, {ProductReadOrigin origin = selectorOrigin}) =>
      gates.putIfAbsent((origin: origin, revision: revision), _HeaderGate.new);
  _HeaderGate resetGate(
    int revision, {
    ProductReadOrigin origin = selectorOrigin,
  }) => gates[(origin: origin, revision: revision)] = _HeaderGate();
  @override
  Future<FeedConnection<ConfigurationFrame>> openConfiguration() =>
      base.openConfiguration();
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) {
    if (!origins.contains(origin)) {
      throw StateError('Undeclared General source');
    }
    return base.openSourceStatus(reference, origin: selectorOrigin);
  }

  @override
  Future<ConfigurationReadConnection> openConfigurationRead(
    ConfigurationReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (!origins.contains(origin)) {
      throw StateError('Undeclared General source');
    }
    return _GeneralPin(
      await base.openConfigurationRead(reference, origin: selectorOrigin),
      () => gate(reference.revision, origin: origin),
    );
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted General request: ${invocation.memberName}',
  );
}

final class _GeneralPin extends ProfileNativePin
    implements ConfigurationReadConnection {
  _GeneralPin(this.base, this.gate) : super('general-configuration-material');
  final ConfigurationReadConnection base;
  final _HeaderGate Function() gate;
  @override
  Future<ConfigurationReadHeader> header() => reply(() async {
    final gate = this.gate();
    gate.reads++;
    if (!gate.entered.isCompleted) gate.entered.complete();
    await gate.reply.future;
    final header = await base.header();
    return header.copyWith(
      general: header.general.copyWith(
        followActiveTurn: true,
        compactTimeline: true,
      ),
    );
  }());
  @override
  void requestClose() {
    super.requestClose();
    base.requestClose();
  }

  @override
  Future<FeedCloseReport> close() async {
    final report = await super.close();
    final original = await base.close();
    expectSync(original.outcome, isA<CleanFeedCloseOutcome>());
    return report;
  }
}
