import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/features/shell/sidebar/studio_sidebar.dart';
import 'package:anywork/src/features/shell/sidebar/sidebar_models.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/production_studio_harness.dart';
import 'support/sidebar_fixture.dart';

// Real AppGraph/FRB/SQLite, production routes and production Studio shell.
// The caller supplies an isolated ANYWORK_HOME, a disposable project root and
// this Thread's artifact directory. No Driver requestData protocol or copied
// sidebar renderer participates.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  final projectsRoot = Platform.environment['ANYWORK_SIDEBAR_PROJECTS'];
  if (Platform.environment['ANYWORK_HOME'] case final home?
      when home.trim().isNotEmpty) {
    // The production composition consumes this isolated home.
  } else {
    throw StateError('Supply an isolated ANYWORK_HOME');
  }
  if (projectsRoot == null || projectsRoot.trim().isEmpty) {
    throw StateError('Supply ANYWORK_SIDEBAR_PROJECTS');
  }

  late ProductionStudioHarness harness;
  late SidebarFixture fixture;
  late String projectPath;
  var harnessReady = false;
  var fixtureReady = false;
  const longTitle = '侧栏原生集成长标题用于验证抽屉内会话行在放大字体和狭窄窗口下仍保持单行省略且不会产生布局溢出';

  setUpAll(() async {
    final project = Directory(
      '$projectsRoot/sidebar-project-with-a-very-long-visible-name',
    );
    await _prepareSyntheticGitProject(project);
    projectPath = project.absolute.path;
    harness = await ProductionStudioHarness.start(
      binding: binding,
      artifactsEnvironmentVariable: 'ANYWORK_SIDEBAR_ARTIFACTS',
    );
    harnessReady = true;
    fixture = await SidebarFixture.create(
      graph: harness.graph,
      projectPath: projectPath,
    );
    fixtureReady = true;
  });

  tearDownAll(() async {
    try {
      if (fixtureReady) {
        try {
          await fixture.settle(harness.graph);
        } finally {
          await fixture.close();
        }
      }
    } finally {
      if (harnessReady) await harness.close();
    }
  });

  testWidgets('production sidebar interactions update canonical Client state', (
    tester,
  ) async {
    final scene = await harness.mount(tester);
    addTearDown(scene.dispose);
    final project = fixture.project;
    final projectRow = find.byKey(StudioDriverKeys.projectRow(project.id));
    final projectExpand = find.byKey(
      StudioDriverKeys.projectExpand(project.id),
    );
    final threadRow = find.byKey(StudioDriverKeys.threadRow(fixture.thread.id));
    final runningRow = find.byKey(
      StudioDriverKeys.threadRow(fixture.runningThread.id),
    );
    final attentionRow = find.byKey(
      StudioDriverKeys.threadRow(fixture.attentionThread.id),
    );
    await scene.until(
      () {
        final idle = fixture.threadSnapshot(fixture.thread.id);
        final running = fixture.threadSnapshot(fixture.runningThread.id);
        final attention = fixture.threadSnapshot(fixture.attentionThread.id);
        return projectRow.evaluate().length == 1 &&
            idle?.status == ThreadStatusView.idle &&
            idle?.workspaceMode.isWorktree == true &&
            running?.status.isActive == true &&
            running?.status != ThreadStatusView.waitingInteraction &&
            attention?.status == ThreadStatusView.waitingInteraction;
      },
      'canonical idle/worktree, running and attention threads are visible',
      timeout: const Duration(seconds: 60),
    );
    await scene.until(
      () => fixture.provider.requests > 0,
      'root thread exercised the loopback provider',
    );
    expect(
      find.byKey(StudioDriverKeys.threadWorkspaceMode(fixture.thread.id)),
      findsOneWidget,
    );
    await scene.capture('sidebar-wide');

    final search = find.byKey(const ValueKey<String>('sidebar-search'));
    await tester.enterText(search, 'does-not-match-the-project');
    await scene.until(
      () => projectRow.evaluate().isEmpty,
      'search excludes the canonical project',
    );
    await tester.enterText(search, 'long-visible-name');
    await scene.until(
      () => projectRow.evaluate().length == 1,
      'search returns the canonical project',
    );

    final clearSearch = find.byKey(
      const ValueKey<String>('sidebar-search-clear'),
    );
    expect(clearSearch, findsOneWidget);
    await tester.tap(clearSearch);
    await scene.until(
      () =>
          tester.widget<TextField>(search).controller?.text.isEmpty == true &&
          threadRow.evaluate().length == 1,
      'cleared search restores the expanded canonical thread',
    );

    await tester.tap(projectExpand);
    await scene.until(
      () => threadRow.evaluate().isEmpty,
      'collapsed project hides its canonical thread',
    );
    await tester.tap(projectExpand);
    await scene.until(
      () => threadRow.evaluate().length == 1,
      'expanded project restores its canonical thread',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-filter-running')),
    );
    await scene.until(
      () =>
          runningRow.evaluate().length == 1 &&
          threadRow.evaluate().isEmpty &&
          attentionRow.evaluate().isEmpty,
      'running filter is backed by canonical active status',
    );
    final runningFrame = await _queryDirectory(
      scene,
      DirectoryQuery(workspaceId: project.id, filter: DirectoryFilter.running),
    );
    expect(
      runningFrame.threads.map((thread) => thread.id),
      contains(fixture.runningThread.id),
    );
    expect(
      runningFrame.threads.map((thread) => thread.id),
      isNot(contains(fixture.attentionThread.id)),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('sidebar-filter-attention')),
    );
    await scene.until(
      () =>
          attentionRow.evaluate().length == 1 &&
          threadRow.evaluate().isEmpty &&
          runningRow.evaluate().isEmpty,
      'attention filter is backed by waitingInteraction status',
    );
    final attentionFrame = await _queryDirectory(
      scene,
      DirectoryQuery(
        workspaceId: project.id,
        filter: DirectoryFilter.attention,
      ),
    );
    expect(
      attentionFrame.threads.map((thread) => thread.id),
      contains(fixture.attentionThread.id),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-filter-all')));
    await scene.until(
      () =>
          threadRow.evaluate().length == 1 &&
          runningRow.evaluate().length == 1 &&
          attentionRow.evaluate().length == 1,
      'all filter restores all canonical status classes',
    );

    await tester.tap(threadRow);
    await scene.until(
      () =>
          scene.graph.client.selection.state.selectedThreadId ==
          fixture.thread.id,
      'thread row selects the canonical Client thread',
    );

    final pointer = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await pointer.addPointer(location: tester.getCenter(threadRow));
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(threadRow));
    await tester.pump();
    await tester.tap(find.byKey(StudioDriverKeys.pinThread(fixture.thread.id)));
    await scene.until(
      () =>
          scene
              .graph
              .client
              .settings
              .state
              .canonical
              ?.state
              .value
              ?.general
              .pinnedThreadIds
              .contains(fixture.thread.id) ==
          true,
      'pin reaches canonical Client settings',
    );
    await scene.until(
      () => threadRow.evaluate().length == 1,
      'pinned demand renders the canonical thread row',
    );
    await pointer.moveTo(tester.getCenter(threadRow));
    await tester.pump();

    final menu = find.byKey(StudioDriverKeys.threadMenu(fixture.thread.id));
    Finder menuTrigger() =>
        find.descendant(of: menu, matching: find.byType(IconButton));
    await tester.tap(menuTrigger());
    await scene.until(
      () =>
          tester.widget<MenuAnchor>(menu).controller?.isOpen == true &&
          find
                  .byKey(StudioDriverKeys.renameThread(fixture.thread.id))
                  .evaluate()
                  .length ==
              1,
      'Material thread menu opens',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await scene.until(
      () =>
          tester.widget<MenuAnchor>(menu).controller?.isOpen == false &&
          find
              .byKey(StudioDriverKeys.renameThread(fixture.thread.id))
              .evaluate()
              .isEmpty,
      'Escape closes the Material thread menu',
    );

    await tester.tap(menuTrigger());
    await scene.until(
      () =>
          find
              .byKey(StudioDriverKeys.openThreadWorkspace(fixture.thread.id))
              .evaluate()
              .length ==
          1,
      'thread menu reopens for workspace submenu',
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.openThreadWorkspace(fixture.thread.id)),
    );
    await scene.until(
      () =>
          find
                  .byKey(StudioDriverKeys.openThreadVsCode(fixture.thread.id))
                  .evaluate()
                  .length ==
              1 &&
          find
                  .byKey(StudioDriverKeys.openThreadZed(fixture.thread.id))
                  .evaluate()
                  .length ==
              1 &&
          find
                  .byKey(StudioDriverKeys.openThreadTerminal(fixture.thread.id))
                  .evaluate()
                  .length ==
              1,
      'workspace submenu exposes all host application entries',
    );
    await scene.capture('sidebar-menu');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await scene.until(
      () => tester.widget<MenuAnchor>(menu).controller?.isOpen == false,
      'workspace submenu and parent menu close without launching an app',
    );

    await tester.tap(menuTrigger());
    await scene.until(
      () =>
          find
              .byKey(StudioDriverKeys.renameThread(fixture.thread.id))
              .evaluate()
              .length ==
          1,
      'thread menu opens for rename',
    );
    await tester.tap(
      find.byKey(StudioDriverKeys.renameThread(fixture.thread.id)),
    );
    final renameInput = find.byKey(
      StudioDriverKeys.renameThreadInput(fixture.thread.id),
    );
    await scene.until(
      () => renameInput.evaluate().length == 1,
      'rename dialog opens',
    );
    await tester.enterText(renameInput, longTitle);
    await tester.tap(
      find.byKey(StudioDriverKeys.renameThreadSave(fixture.thread.id)),
    );
    await scene.until(
      () => fixture.threadSnapshot(fixture.thread.id)?.title == longTitle,
      'renamed title reaches the canonical directory',
    );

    await pointer.moveTo(tester.getCenter(threadRow));
    await tester.pump();
    await tester.tap(menuTrigger());
    await scene.until(
      () =>
          find
              .byKey(ValueKey('thread-menu-archive-${fixture.thread.id}'))
              .evaluate()
              .length ==
          1,
      'thread menu opens for archive',
    );
    await tester.tap(
      find.byKey(ValueKey('thread-menu-archive-${fixture.thread.id}')),
    );
    await scene.until(
      () =>
          find.byKey(StudioDriverKeys.archiveThreadConfirm).evaluate().length ==
          1,
      'archive confirmation opens',
    );
    await tester.tap(find.byKey(StudioDriverKeys.archiveThreadConfirm));
    await scene.until(
      () => threadRow.evaluate().isEmpty,
      'archived canonical thread leaves the live directory',
    );
    final archivedFrame = await _queryDirectory(
      scene,
      DirectoryQuery(workspaceId: project.id, archived: true),
    );
    expect(
      archivedFrame.threads.map((thread) => thread.id),
      contains(fixture.thread.id),
    );

    await tester.tap(find.byKey(const ValueKey<String>('sidebar-archived')));
    await scene.until(
      () =>
          threadRow.evaluate().length == 1 &&
          find
                  .byKey(
                    ValueKey('thread-archived-workspace-${fixture.thread.id}'),
                  )
                  .evaluate()
                  .length ==
              1,
      'archived view loads the canonical archived thread and workspace',
    );
    await scene.capture('sidebar-archived');
    await pointer.moveTo(tester.getCenter(threadRow));
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('thread-restore-${fixture.thread.id}')),
    );
    await scene.until(
      () => threadRow.evaluate().isEmpty,
      'restore removes the thread from the archived query',
    );
    final afterRestore = await _queryDirectory(
      scene,
      DirectoryQuery(workspaceId: project.id, archived: true),
    );
    expect(
      afterRestore.threads.map((thread) => thread.id),
      isNot(contains(fixture.thread.id)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('sidebar-archived')));
    await scene.until(
      () =>
          threadRow.evaluate().length == 1 &&
          fixture.threadSnapshot(fixture.thread.id)?.archived == false &&
          fixture.threadSnapshot(fixture.thread.id)?.title == longTitle,
      'restored thread returns to the live canonical directory',
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets(
    'sidebar resize drag and keyboard persist through the production Client',
    (tester) async {
      final scene = await harness.mount(tester);
      addTearDown(scene.dispose);
      LogicalKeyboardKey? heldKey;
      addTearDown(() async {
        if (heldKey case final key?) {
          await tester.sendKeyUpEvent(key);
        }
      });
      final shell = find.byKey(StudioDriverKeys.shell);
      final divider = find.byKey(StudioDriverKeys.sidebarResize);
      expect(shell, findsOneWidget);
      expect(divider, findsOneWidget);

      double width() =>
          tester.getTopLeft(divider).dx - tester.getTopLeft(shell).dx;
      int? canonicalWidth() => scene
          .graph
          .client
          .settings
          .state
          .canonical
          ?.state
          .value
          ?.general
          .sidebarWidth;

      final initial = width();
      expect(initial, closeTo(336, 1));
      await scene.until(
        () => canonicalWidth() == 336,
        'default 336px width is canonical before resizing',
      );
      await tester.drag(divider, const Offset(64, 0));
      await scene.until(
        () => (width() - (initial + 64).clamp(300, 440)).abs() <= 1,
        'drag changes the production sidebar width',
      );
      final dragged = width();
      await scene.until(
        () => canonicalWidth() == dragged.round(),
        'dragged width reaches canonical Client settings',
      );

      await tester.drag(divider, const Offset(-300, 0));
      await scene.until(
        () => (width() - 300).abs() <= 1 && canonicalWidth() == 300,
        'drag clamps and saves the 300px lower boundary',
      );
      await tester.drag(divider, const Offset(-64, 0));
      await scene.until(
        () => (width() - 300).abs() <= 1 && canonicalWidth() == 300,
        'drag cannot cross the 300px lower boundary',
      );
      await tester.drag(divider, const Offset(300, 0));
      await scene.until(
        () => (width() - 440).abs() <= 1 && canonicalWidth() == 440,
        'drag clamps and saves the 440px upper boundary',
      );
      await tester.drag(divider, const Offset(64, 0));
      await scene.until(
        () => (width() - 440).abs() <= 1 && canonicalWidth() == 440,
        'drag cannot cross the 440px upper boundary',
      );

      await tester.tap(divider);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await scene.until(
        () => (width() - 336).abs() <= 1 && canonicalWidth() == 336,
        'Home restores and saves the canonical default',
      );

      heldKey = LogicalKeyboardKey.arrowRight;
      await tester.sendKeyDownEvent(heldKey);
      await scene.until(
        () => (width() - 352).abs() <= 1,
        'held Right changes only the draft width',
      );
      expect(
        canonicalWidth(),
        336,
        reason: 'A held key must not save before KeyUp or focus loss',
      );
      await tester.tap(find.byKey(const ValueKey<String>('sidebar-search')));
      await scene.until(
        () => canonicalWidth() == 352,
        'focus loss saves the held keyboard width',
      );
      await tester.sendKeyUpEvent(heldKey);
      heldKey = null;

      await tester.tap(divider);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await scene.until(
        () => (width() - 336).abs() <= 1 && canonicalWidth() == 336,
        'Home restores the default after focus-loss persistence',
      );

      heldKey = LogicalKeyboardKey.arrowLeft;
      await tester.sendKeyDownEvent(heldKey);
      await scene.until(
        () => (width() - 320).abs() <= 1,
        'held Left changes only the draft width',
      );
      expect(
        canonicalWidth(),
        336,
        reason: 'The draft width must remain unsaved before KeyUp',
      );
      await tester.sendKeyUpEvent(heldKey);
      heldKey = null;
      await scene.until(
        () => canonicalWidth() == 320,
        'KeyUp saves the held keyboard width',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'real narrow native window uses drawer without overflow at large text',
    (tester) async {
      final scene = await harness.mount(
        tester,
        textScaler: TextScaler.linear(1.6),
      );
      addTearDown(scene.dispose);

      await tester.binding.setSurfaceSize(const Size(820, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = const Size(820, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pump();
      await File('${harness.artifacts.path}/sidebar-native-window.json')
          .writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'requested': {'width': 820, 'height': 760},
              'view': {
                'physicalWidth': tester.view.physicalSize.width,
                'physicalHeight': tester.view.physicalSize.height,
                'devicePixelRatio': tester.view.devicePixelRatio,
              },
            }),
            flush: true,
          );
      await scene.until(() {
        final view = ui.PlatformDispatcher.instance.views.single;
        return view.physicalSize.width / view.devicePixelRatio < 960;
      }, 'Flutter adopts the compact test surface geometry');

      final shell = find.byKey(StudioDriverKeys.shell);
      final scaffold = find
          .ancestor(of: shell, matching: find.byType(Scaffold))
          .first;
      final scaffoldState = tester.state<ScaffoldState>(scaffold);
      expect(scaffoldState.isDrawerOpen, isFalse);
      expect(find.byKey(StudioDriverKeys.sidebar), findsNothing);
      await tester.tap(find.byKey(const ValueKey<String>('sidebar-toggle')));
      await scene.until(
        () =>
            scaffoldState.isDrawerOpen &&
            find.byKey(StudioDriverKeys.sidebar).evaluate().length == 1,
        'compact shell opens the production navigation drawer',
      );

      final projectRow = find.byKey(
        StudioDriverKeys.projectRow(fixture.project.id),
      );
      final threadRow = find.byKey(
        StudioDriverKeys.threadRow(fixture.thread.id),
      );
      await scene.until(
        () =>
            projectRow.evaluate().length == 1 &&
            threadRow.evaluate().length == 1 &&
            find
                .descendant(of: threadRow, matching: find.text(longTitle))
                .evaluate()
                .isNotEmpty,
        'drawer retains the project tree and long canonical thread title',
      );
      expect(
        MediaQuery.textScalerOf(tester.element(threadRow)).scale(14),
        greaterThanOrEqualTo(22.4),
      );
      expect(tester.takeException(), isNull);
      await scene.capture('sidebar-narrow-drawer');

      final archiveDirectory = Directory(
        '${Directory(projectPath).parent.path}/sidebar-project-close-target',
      );
      await _prepareSyntheticGitProject(archiveDirectory);
      final archiveProject = await harness.openProject(
        scene,
        archiveDirectory.absolute.path,
      );
      final archiveProjectRow = find.byKey(
        StudioDriverKeys.projectRow(archiveProject.id),
      );
      try {
        await scene.until(
          () => archiveProjectRow.evaluate().length == 1,
          'independent canonical project appears in the compact drawer',
        );
      } catch (error, stack) {
        await _writeArchiveTargetDiagnostic(scene, tester, archiveProject.id);
        Error.throwWithStackTrace(error, stack);
      }
      await tester.ensureVisible(archiveProjectRow);
      final projectPointer = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await projectPointer.addPointer(
        location: tester.getCenter(archiveProjectRow),
      );
      addTearDown(projectPointer.removePointer);
      await projectPointer.moveTo(tester.getCenter(archiveProjectRow));
      await tester.pump();

      final projectMenu = find.byKey(
        StudioDriverKeys.projectMenu(archiveProject.id),
      );
      Finder projectMenuTrigger() =>
          find.descendant(of: projectMenu, matching: find.byType(IconButton));
      Future<void> openProjectArchiveDialog() async {
        await tester.tap(projectMenuTrigger());
        await scene.until(
          () =>
              tester.widget<MenuAnchor>(projectMenu).controller?.isOpen ==
                  true &&
              find
                      .byKey(const ValueKey<String>('project-close'))
                      .evaluate()
                      .length ==
                  1,
          'project menu opens for archive',
        );
        await tester.tap(find.byKey(const ValueKey<String>('project-close')));
        await scene.until(
          () =>
              find
                  .byKey(const ValueKey<String>('archive-project-dialog'))
                  .evaluate()
                  .length ==
              1,
          'project archive warning opens',
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('archive-project-dialog')),
            matching: find.textContaining(archiveProject.name),
          ),
          findsWidgets,
        );
      }

      await openProjectArchiveDialog();
      await tester.tap(
        find.byKey(const ValueKey<String>('archive-project-cancel')),
      );
      await scene.until(
        () =>
            find
                .byKey(const ValueKey<String>('archive-project-dialog'))
                .evaluate()
                .isEmpty &&
            (scene.graph.client.project.state.projects?.values ?? const []).any(
              (project) => project.id == archiveProject.id,
            ) &&
            archiveProjectRow.evaluate().length == 1,
        'cancel preserves the canonical project',
      );

      await projectPointer.moveTo(tester.getCenter(archiveProjectRow));
      await tester.pump();
      await openProjectArchiveDialog();
      await tester.tap(
        find.byKey(const ValueKey<String>('archive-project-confirm')),
      );
      await scene.until(
        () =>
            (scene.graph.client.project.state.projects?.values ?? const [])
                .every((project) => project.id != archiveProject.id) &&
            (scene.graph.client.project.state.projects?.values ?? const []).any(
              (project) => project.id == fixture.project.id,
            ) &&
            archiveProjectRow.evaluate().isEmpty,
        'confirm removes only the target from the canonical project directory',
      );
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<ThreadDirectoryFrame> _queryDirectory(
  ProductionStudioScene scene,
  DirectoryQuery query,
) async {
  final observation = scene.graph.client.threadDirectory.observeThreads(
    query,
    DirectoryWindow(),
  );
  try {
    final state = await observation.state
        .waitFor(
          (state) => state.frame != null || state.error != null || state.closed,
        )
        .timeout(const Duration(seconds: 30));
    if (state.error case final error?) {
      throw StateError('Sidebar directory query failed: $error');
    }
    final frame = state.frame;
    if (state.closed || frame == null) {
      throw StateError('Sidebar directory query closed without a frame');
    }
    return frame;
  } finally {
    await observation.release();
  }
}

Future<void> _writeArchiveTargetDiagnostic(
  ProductionStudioScene scene,
  WidgetTester tester,
  String targetProjectId,
) async {
  final canonicalProjects =
      scene.graph.client.project.state.projects?.values ??
      const <StudioProject>[];
  final sidebarFinder = find.byType(StudioSidebar);
  final sidebar = sidebarFinder.evaluate().length == 1
      ? tester.widget<StudioSidebar>(sidebarFinder)
      : null;
  final data = sidebar?.data;
  final filters = find.byType(SidebarFilters);
  final footer = find.byType(SidebarFooter);
  final search = find.byKey(const ValueKey<String>('sidebar-search'));
  Map<String, Object?> windows(Map<String, SidebarWindow> source) => {
    for (final entry in source.entries)
      entry.key: {
        'threadIds': entry.value.threads
            .map((thread) => thread.id)
            .toList(growable: false),
        'loading': entry.value.loading,
        'error': entry.value.error,
        'loaded': entry.value.loaded,
        'hasMore': entry.value.hasMore,
        'hasPrevious': entry.value.hasPrevious,
      },
  };

  await File(
    '${scene.harness.artifacts.path}/sidebar-archive-target-diagnostic.json',
  ).writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'targetProjectId': targetProjectId,
      'canonicalProjectIds': canonicalProjects
          .map((project) => project.id)
          .toList(growable: false),
      'viewProjectIds': data?.projects
          .map((project) => project.id)
          .toList(growable: false),
      'renderedCanonicalProjectIds': canonicalProjects
          .where(
            (project) => find
                .byKey(StudioDriverKeys.projectRow(project.id))
                .evaluate()
                .isNotEmpty,
          )
          .map((project) => project.id)
          .toList(growable: false),
      'selectedProjectId': data?.selectedProjectId,
      'selectedThreadId': data?.selectedThreadId,
      'filter': filters.evaluate().length == 1
          ? tester.widget<SidebarFilters>(filters).selected.name
          : null,
      'archived': footer.evaluate().length == 1
          ? tester.widget<SidebarFooter>(footer).archived
          : null,
      'search': search.evaluate().length == 1
          ? tester.widget<TextField>(search).controller?.text
          : null,
      'windows': windows(data?.windows ?? const {}),
      'pinnedWindows': windows(data?.pinnedWindows ?? const {}),
    }),
    flush: true,
  );
}

Future<void> _prepareSyntheticGitProject(Directory project) async {
  if (await project.exists()) {
    throw StateError('Synthetic project path must be new: ${project.path}');
  }
  await project.create(recursive: true);
  await File('${project.path}/README.md')
      .writeAsString('# Sidebar integration fixture\n', flush: true);
  await _runGit(project, [
    '-c',
    'init.templateDir=',
    'init',
    '--quiet',
    '--initial-branch=main',
  ]);
  await _runGit(project, ['add', 'README.md']);
  await _runGit(project, [
    '-c',
    'user.name=Sidebar Integration',
    '-c',
    'user.email=sidebar-integration.invalid',
    '-c',
    'commit.gpgSign=false',
    '-c',
    'core.hooksPath=/dev/null',
    'commit',
    '--quiet',
    '-m',
    'fixture',
  ]);
}

Future<void> _runGit(Directory project, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: project.path,
  );
  if (result.exitCode == 0) return;
  throw StateError(
    'Synthetic fixture git ${arguments.join(' ')} failed '
    '(${result.exitCode}): ${result.stderr}',
  );
}
