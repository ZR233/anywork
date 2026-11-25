import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('sidebar header shows and clears an edited search locally', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SidebarHeader(
            searchController: controller,
            filter: DirectoryFilter.all,
            onSearchChanged: changes.add,
            onClearSearch: controller.clear,
            onFilterChanged: (_) {},
          ),
        ),
      ),
    );
    final search = find.byKey(const ValueKey('sidebar-search'));
    final clear = find.byKey(const ValueKey('sidebar-search-clear'));
    expect(clear, findsNothing);

    await tester.enterText(search, 'workspace');
    await tester.pump();
    expect(changes, ['workspace']);
    expect(clear, findsOneWidget);

    await tester.tap(clear);
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(clear, findsNothing);
    expect(changes, ['workspace']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
