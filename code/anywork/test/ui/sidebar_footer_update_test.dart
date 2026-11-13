import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child, {required double width}) => MaterialApp(
  theme: pureStudioTheme(),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SizedBox(width: width, height: 120, child: child),
  ),
);

SidebarFooter _footer({
  required bool hasUpdate,
  bool updateBusy = false,
  VoidCallback? onUpdateNow,
}) => SidebarFooter(
  archived: false,
  hasUpdate: hasUpdate,
  updateBusy: updateBusy,
  onToggleArchived: () {},
  onSettings: () {},
  onUpdateNow: onUpdateNow,
);

Future<({Offset archive, Size archiveSize, Offset settings, Size settingsSize})>
_geometry(WidgetTester tester) async {
  final archive = tester.getTopLeft(
    find.byKey(const ValueKey('sidebar-archived')),
  );
  final archiveSize = tester.getSize(
    find.byKey(const ValueKey('sidebar-archived')),
  );
  final settings = tester.getTopLeft(find.byKey(StudioDriverKeys.settingsOpen));
  final settingsSize = tester.getSize(
    find.byKey(StudioDriverKeys.settingsOpen),
  );
  return (
    archive: archive,
    archiveSize: archiveSize,
    settings: settings,
    settingsSize: settingsSize,
  );
}

void main() {
  for (final width in [300.0, 336.0]) {
    testWidgets('sidebar footer hides update now at ${width}px', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_footer(hasUpdate: false), width: width));
      expect(find.byKey(StudioDriverKeys.sidebarUpdateNow), findsNothing);
    });

    testWidgets(
      'sidebar footer shows update now and keeps geometry at ${width}px',
      (tester) async {
        await tester.pumpWidget(_host(_footer(hasUpdate: false), width: width));
        final withoutUpdate = await _geometry(tester);

        var tapped = false;
        await tester.pumpWidget(
          _host(
            _footer(hasUpdate: true, onUpdateNow: () => tapped = true),
            width: width,
          ),
        );
        expect(find.byKey(StudioDriverKeys.sidebarUpdateNow), findsOneWidget);
        final withUpdate = await _geometry(tester);
        expect(withUpdate.archive, withoutUpdate.archive);
        expect(withUpdate.archiveSize, withoutUpdate.archiveSize);
        expect(withUpdate.settings, withoutUpdate.settings);
        expect(withUpdate.settingsSize, withoutUpdate.settingsSize);

        await tester.tap(find.byKey(StudioDriverKeys.sidebarUpdateNow));
        expect(tapped, isTrue);
      },
    );

    testWidgets('sidebar footer disables update now while busy at ${width}px', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        _host(
          _footer(
            hasUpdate: true,
            updateBusy: true,
            onUpdateNow: () => tapped = true,
          ),
          width: width,
        ),
      );
      final button = tester.widget<FilledButton>(
        find.byKey(StudioDriverKeys.sidebarUpdateNow),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.byKey(StudioDriverKeys.sidebarUpdateNow));
      expect(tapped, isFalse);
    });
  }
}
