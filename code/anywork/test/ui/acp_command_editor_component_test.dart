import 'package:anywork/src/features/settings/accounts/accounts_views.dart';
import 'package:anywork_previews/src/features/settings/accounts/previews/account_preview_fixtures.dart';
import 'package:anywork_previews/src/features/settings/accounts/previews/account_preview_host.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [408.0, 1280.0]) {
    testWidgets(
      'local detection keeps a long path, version and refresh on one row at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const program =
            '/synthetic/workspaces/long-project-directory/'
            'another-long-directory/isolated-command-fixture/bin/agy';
        const version = '1.5.4';
        var refreshes = 0;
        final value = AccountPreviewFixtures.acpEditor.copyWith(
          source: AcpAccountSource.local,
          detectionPhase: AcpDetectionPhase.available,
          detectedProgram: program,
          detectedVersion: version,
        );
        await tester.pumpWidget(
          accountPreviewHost(
            (_) => AcpAccountEditorView(
              value: value,
              onNameChanged: (_) {},
              onAction: (_) {},
              onLoginMethodChanged: (_) {},
              onSave: () {},
              onCancel: () {},
              onRefreshDetection: () => refreshes++,
            ),
            scenarioIdentity: value,
          ),
        );
        await tester.pumpAndSettle();
        final path = find.text(program);
        final versionText = find.text(version);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(AcpAccountEditorView)),
        );
        final refresh = find.byTooltip(l10n.acpDetectionRefresh);
        final pathWidget = tester.widget<Text>(path);
        expect(pathWidget.maxLines, 1);
        expect(pathWidget.softWrap, isFalse);
        expect(pathWidget.overflow, TextOverflow.ellipsis);
        expect(find.byTooltip(program), findsOneWidget);
        expect(versionText, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(versionText).didExceedMaxLines,
          isFalse,
        );
        final pathRect = tester.getRect(path);
        final versionRect = tester.getRect(versionText);
        final refreshRect = tester.getRect(refresh);
        expect(pathRect.center.dy, closeTo(versionRect.center.dy, 0.1));
        expect(versionRect.center.dy, closeTo(refreshRect.center.dy, 0.1));
        expect(pathRect.right, lessThan(versionRect.left));
        expect(versionRect.right, lessThanOrEqualTo(refreshRect.left));
        expect(refreshRect.right, lessThanOrEqualTo(width));
        if (width == 408) {
          expect(
            tester.renderObject<RenderParagraph>(path).didExceedMaxLines,
            isTrue,
          );
        }
        await tester.tap(refresh);
        expect(refreshes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('other detection facts keep the full message in a tooltip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(408, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const message =
        'Synthetic probe cleanup failed for a long isolated command path; '
        'refresh only after cleanup has completed.';
    final value = AccountPreviewFixtures.acpEditor.copyWith(
      source: AcpAccountSource.local,
      detectionPhase: AcpDetectionPhase.failed,
      detectionError: message,
      detectedVersion: null,
    );
    await tester.pumpWidget(accountAcpEditorPreviewHost(value));
    await tester.pumpAndSettle();
    final fact = tester.widget<Text>(find.text(message));
    expect(fact.maxLines, 1);
    expect(fact.softWrap, isFalse);
    expect(fact.overflow, TextOverflow.ellipsis);
    expect(find.byTooltip(message), findsOneWidget);
    expect(
      tester
          .renderObject<RenderParagraph>(find.text(message))
          .didExceedMaxLines,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'command editor emits independent arguments and environment values and hides install controls',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final value = AccountPreviewFixtures.acpEditor.copyWith(
        source: AcpAccountSource.command,
        command: '/tools/agent',
        args: const ['--label', 'two words'],
        environment: const [
          AcpEnvironmentEntry(key: 'WORK', value: 'tree one'),
        ],
        canSave: true,
        saveAndConnect: true,
      );
      await tester.pumpWidget(accountAcpEditorPreviewHost(value));
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(AcpAccountEditorView)),
      );
      expect(find.text(l10n.acpInstallStart), findsNothing);
      expect(find.text(l10n.acpEditorStepBasicSubtitle), findsNothing);
      expect(find.text(l10n.acpEditorStepPrepareSubtitle), findsNothing);
      expect(find.text(l10n.acpAccountSaveAndConnect), findsOneWidget);
      expect(find.text('tree one'), findsNothing);
      final argument = find.descendant(
        of: find.byKey(
          ValueKey(AccountViewKeyValues.editorField(value.editorId, 'arg:1')),
        ),
        matching: find.byType(TextField),
      );
      await tester.enterText(argument, 'one argument with spaces');
      await tester.pump();
      final editor = tester.widget<AcpAccountEditorView>(
        find.byType(AcpAccountEditorView),
      );
      expect(editor.value.args, ['--label', 'one argument with spaces']);
      await tester.tap(find.text(l10n.acpEnvironmentLabel));
      await tester.pumpAndSettle();
      final environment = find.descendant(
        of: find.byKey(
          ValueKey(
            AccountViewKeyValues.editorField(value.editorId, 'env-value:0'),
          ),
        ),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(environment);
      await tester.enterText(environment, 'value with spaces');
      await tester.pump();
      expect(
        tester
            .widget<AcpAccountEditorView>(find.byType(AcpAccountEditorView))
            .value
            .environment
            .single
            .value,
        'value with spaces',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
