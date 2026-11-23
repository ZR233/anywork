import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_route_selectors.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _tiers = ModelServiceTierParameterView(
  defaultCandidate: 'priority',
  candidates: [
    ModelServiceTierView(id: 'priority', displayName: 'Fast'),
    ModelServiceTierView(id: 'opaque/raw-tier'),
    ModelServiceTierView(id: 'empty-name', displayName: ''),
    ModelServiceTierView(id: 'exact-name', displayName: '  Unmodified Name  '),
  ],
);

List<ComposerConfigurationEntry> _entries({
  ModelServiceTierParameterView? tiers = _tiers,
  String? selected,
  ValueChanged<String?>? onSelected,
}) => modelRouteConfigurationEntries(
  accounts: [
    ModelSelectionAccount(
      id: 'account',
      name: 'Account',
      billingKind: null,
      models: [
        AccountModelView(
          modelId: 'model',
          displayName: 'Demo GPT-6.2 Sol',
          reasoningEfforts: const ['high'],
          typeSupport: const [ModelTypeSupportView(modelType: ModelType.text)],
          serviceTiers: tiers,
        ),
      ],
    ),
  ],
  accountId: 'account',
  modelId: 'model',
  effort: 'high',
  serviceTier: selected,
  pending: false,
  unavailableReason: 'Unavailable',
  onServiceTierSelected: onSelected,
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  theme: pureStudioTheme(locale: const Locale('en')),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(alignment: Alignment.topLeft, child: child),
  ),
);

bool _selected(WidgetTester tester, String? id) => tester
    .widget<Semantics>(
      find.descendant(
        of: find.byKey(ServiceTierSelector.optionKey(id)),
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected != null,
        ),
      ),
    )
    .properties
    .selected!;

void main() {
  testWidgets(
    'speed follows effort and uses only the published single-line names',
    (tester) async {
      expect(_entries().map((entry) => entry.id), [
        'native-model',
        'native-effort',
        'native-speed',
      ]);
      expect(_entries(tiers: null).map((entry) => entry.id), [
        'native-model',
        'native-effort',
      ]);
      expect(
        _entries(tiers: const ModelServiceTierParameterView(candidates: []))
            .length,
        2,
      );
      String? selected;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, rebuild) => ComposerConfigurationBar(
              moreTooltip: 'More',
              entries: _entries(
                selected: selected,
                onSelected: (value) => rebuild(() => selected = value),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byKey(ServiceTierSelector.labelKey)).dx,
        greaterThan(tester.getCenter(find.byType(ReasoningEffortSelector)).dx),
      );
      await tester.tap(find.byKey(ServiceTierSelector.labelKey));
      await tester.pumpAndSettle();
      expect(
        _selected(tester, null),
        isTrue,
        reason: 'The catalog default does not select acceleration',
      );
      for (final (id, label) in [
        ('priority', 'Fast'),
        ('opaque/raw-tier', 'opaque/raw-tier'),
        ('empty-name', 'empty-name'),
        ('exact-name', '  Unmodified Name  '),
      ]) {
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byKey(ServiceTierSelector.optionKey(id)),
            matching: find.byType(Text),
          ),
        );
        expect(text.data, label);
        expect(text.maxLines, 1);
      }
      await tester.tap(find.byKey(ServiceTierSelector.optionKey('priority')));
      await tester.pumpAndSettle();
      expect(selected, 'priority');
      expect(find.text('Fast'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'withdrawn saved tier stays unavailable and standard explicitly repairs it',
    (tester) async {
      String? selected = 'retired/raw-tier';
      final changes = <String?>[];
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, rebuild) => ComposerConfigurationBar(
              moreTooltip: 'More',
              entries: _entries(
                tiers: null,
                selected: selected,
                onSelected: (value) {
                  changes.add(value);
                  rebuild(() => selected = value);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('retired/raw-tier'), findsOneWidget);
      expect(find.text('Standard'), findsNothing);
      await tester.tap(find.byKey(ServiceTierSelector.labelKey));
      await tester.pumpAndSettle();
      final withdrawn = find.byKey(
        ServiceTierSelector.optionKey('retired/raw-tier'),
      );
      expect(tester.widget<MenuItemButton>(withdrawn).onPressed, isNull);
      expect(_selected(tester, 'retired/raw-tier'), isTrue);
      expect(_selected(tester, null), isFalse);
      await tester.tap(find.byKey(ServiceTierSelector.optionKey(null)));
      await tester.pumpAndSettle();
      expect(changes, [null]);
      expect(selected, isNull);
      expect(
        find.byKey(ServiceTierSelector.selectorKey),
        findsNothing,
        reason: 'No saved acceleration or published candidates remains',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow composer exposes speed through its production overflow menu',
    (tester) async {
      String? selected = 'retired/raw-tier';
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, rebuild) => SizedBox(
              width: 100,
              child: ComposerConfigurationBar(
                moreTooltip: 'More',
                entries: _entries(
                  selected: selected,
                  onSelected: (value) => rebuild(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ServiceTierSelector.labelKey).hitTestable());
      await tester.pumpAndSettle();
      expect(
        find
            .byKey(ServiceTierSelector.optionKey('opaque/raw-tier'))
            .hitTestable(),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(ServiceTierSelector.optionKey('opaque/raw-tier')),
      );
      await tester.pumpAndSettle();
      expect(selected, 'opaque/raw-tier');
      await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ServiceTierSelector.labelKey).hitTestable(),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
