import 'dart:async';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_views.dart';
import 'package:anywork/src/features/shell/studio_shell.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _openDialog = ValueKey<String>('open-thread-action-dialog');
const _dialog = ValueKey<String>('thread-action-dialog');
const _confirm = ValueKey<String>('thread-action-confirm');
const _project = StudioProject(
  id: 'project',
  name: 'Project',
  path: '/project',
);

SessionDirectoryRow _thread({required String id}) => SessionDirectoryRow(
  sessionId: 'session-$id',
  agentId: 'agent-$id',
  threadId: id,
  workspaceId: _project.id,
  title: 'Session $id',
  mode: ThreadModeId.simple,
  delegationMode: DelegationMode.automatic,
  delegationPreference: DelegationPreference.balanced,
  updatedAt: DateTime.utc(2026),
  workspacePath: _project.path,
);

Widget _host({
  required bool deleting,
  String threadTitle = 'Target session',
  required Future<void> Function() onConfirm,
}) {
  return MaterialApp(
    theme: pureStudioTheme(),
    locale: const Locale('zh'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          key: _openDialog,
          onPressed: () => unawaited(
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (dialogContext) => ThreadDestructiveActionDialog(
                key: _dialog,
                title: deleting
                    ? dialogContext.l10n.sidebarDeleteSessionConfirmTitle(
                        threadTitle,
                      )
                    : dialogContext.l10n.sidebarArchiveSessionConfirmTitle,
                body: deleting
                    ? dialogContext.l10n.sidebarDeleteSessionConfirmBody
                    : dialogContext.l10n.sidebarArchiveSessionConfirmBody,
                actionLabel: deleting
                    ? dialogContext.l10n.sidebarDeleteSessionConfirmAction
                    : dialogContext.l10n.sidebarArchiveSessionConfirmAction,
                confirmKey: _confirm,
                danger: deleting,
                onConfirm: onConfirm,
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

Widget _sidebarRowHost(Widget row) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(width: 560, child: Material(child: row)),
    ),
  ),
);

SidebarThreadRow _sidebarRow({
  required SessionDirectoryRow thread,
  required ValueChanged<SidebarThreadAction> onAction,
  bool archived = false,
}) => SidebarThreadRow(
  row: thread,
  project: _project,
  selected: false,
  pinned: false,
  hostApps: const SidebarHostApps(
    terminalUnavailableReason: 'Unavailable in this test.',
  ),
  onSelect: () {},
  onAction: onAction,
  archived: archived,
  touchMode: true,
);

void main() {
  testWidgets('active session menu deletes with a text-only item', (
    tester,
  ) async {
    final actions = <SidebarThreadAction>[];
    final thread = _thread(id: 'active');
    await tester.pumpWidget(
      _sidebarRowHost(_sidebarRow(thread: thread, onAction: actions.add)),
    );
    final menuTrigger = find.descendant(
      of: find.byKey(StudioDriverKeys.threadMenu(thread.threadId)),
      matching: find.byType(IconButton),
    );
    await tester.tap(menuTrigger);
    await tester.pumpAndSettle();

    expect(
      find.byKey(StudioDriverKeys.deleteThread(thread.threadId)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(StudioDriverKeys.deleteThread(thread.threadId)),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(
      find.byKey(StudioDriverKeys.archiveThread(thread.threadId)),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.deleteThread(thread.threadId)),
    );
    await tester.pumpAndSettle();

    expect(actions, [SidebarThreadAction.delete]);
  });

  testWidgets(
    'archived session has a delete button without replacing restore',
    (tester) async {
      final actions = <SidebarThreadAction>[];
      final thread = _thread(id: 'archived');
      await tester.pumpWidget(
        _sidebarRowHost(
          _sidebarRow(thread: thread, archived: true, onAction: actions.add),
        ),
      );

      final deleteButton = StudioDriverKeys.deleteThread(thread.threadId);
      final restoreButton = ValueKey<String>(
        'thread-restore-${thread.threadId}',
      );
      expect(find.byKey(deleteButton), findsOneWidget);
      expect(find.byKey(restoreButton), findsOneWidget);
      expect(
        find.byKey(StudioDriverKeys.threadMenu(thread.threadId)),
        findsNothing,
      );
      await tester.tap(find.byKey(deleteButton));
      await tester.pump();

      expect(actions, [SidebarThreadAction.delete]);
      expect(find.byKey(restoreButton), findsOneWidget);
    },
  );

  testWidgets(
    'cancel leaves the archive command untouched and shows only archive scope',
    (tester) async {
      var archiveCalls = 0;
      var deleteCalls = 0;
      await tester.pumpWidget(
        _host(
          deleting: false,
          onConfirm: () async {
            archiveCalls++;
          },
        ),
      );
      await tester.tap(find.byKey(_openDialog));
      await tester.pumpAndSettle();

      final l10n = tester.element(find.byKey(_dialog)).l10n;
      expect(find.text(l10n.sidebarArchiveSessionConfirmBody), findsOneWidget);
      expect(find.text(l10n.sidebarDeleteSessionConfirmBody), findsNothing);
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();

      expect(archiveCalls, 0);
      expect(deleteCalls, 0);
      expect(find.byKey(_dialog), findsNothing);
    },
  );

  testWidgets('confirm invokes only delete once while its command is pending', (
    tester,
  ) async {
    var deleteCalls = 0;
    var archiveCalls = 0;
    final command = Completer<void>();
    await tester.pumpWidget(
      _host(
        deleting: true,
        threadTitle: 'The target',
        onConfirm: () {
          deleteCalls++;
          return command.future;
        },
      ),
    );
    await tester.tap(find.byKey(_openDialog));
    await tester.pumpAndSettle();

    final l10n = tester.element(find.byKey(_dialog)).l10n;
    expect(
      find.text(l10n.sidebarDeleteSessionConfirmTitle('The target')),
      findsOneWidget,
    );
    expect(find.text(l10n.sidebarDeleteSessionConfirmBody), findsOneWidget);
    expect(find.text(l10n.sidebarArchiveSessionConfirmBody), findsNothing);
    await tester.tap(find.byKey(_confirm));
    await tester.pump();
    expect(deleteCalls, 1);
    expect(archiveCalls, 0);
    expect(tester.widget<FilledButton>(find.byKey(_confirm)).onPressed, isNull);
    await tester.tap(find.byKey(_confirm));
    expect(deleteCalls, 1);

    command.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(_dialog), findsNothing);
  });

  testWidgets(
    'a failed command keeps its dialog open with the original error',
    (tester) async {
      final failure = StateError('original delete failure');
      await tester.pumpWidget(
        _host(deleting: true, onConfirm: () => Future<void>.error(failure)),
      );
      await tester.tap(find.byKey(_openDialog));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_confirm));
      await tester.pumpAndSettle();

      expect(find.byKey(_dialog), findsOneWidget);
      expect(find.text(failure.toString()), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_confirm)).onPressed,
        isNotNull,
      );
    },
  );
}
