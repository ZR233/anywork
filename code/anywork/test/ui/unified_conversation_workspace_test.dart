import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_workspace_connector.dart';
import 'package:anywork/src/features/conversation/interactions/views/plan_confirmation_view.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/features/conversation/workspace/conversation_workspace.dart';
import 'package:anywork/src/features/todo/todo_panel.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/models.dart' hide PlanConfirmationView;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

Widget _zhApp(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('ConversationWorkspaceShell & ConversationRightSidebar', () {
    testWidgets(
      'split mode extends sidebar to status bar top, compresses left dock, and preserves state across modes',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final state = ConversationSidebarState<String>();
        final composerController = TextEditingController(text: '保留输入草稿');
        addTearDown(composerController.dispose);
        double? reportedCustomWidth;

        const todo = TimelineTodoListUpdate(
          callId: 'todo-1',
          items: [
            TimelineTodoItem(step: '统一右侧边栏壳层', status: 'completed'),
            TimelineTodoItem(step: '对齐底部状态栏', status: 'inProgress'),
          ],
        );

        Widget buildHarness() => _zhApp(
          StatefulBuilder(
            builder: (context, setState) {
              final entries = <ConversationSidebarPanelEntry>[
                ConversationSidebarPanelEntry(
                  kind: ConversationSidebarPanelKind.todo,
                  icon: Icons.checklist_outlined,
                  label: '待办',
                  defaultLayoutMode: ConversationSidebarLayoutMode.split,
                  expandedDockBehavior:
                      ConversationExpandedDockBehavior.coverAll,
                  defaultWidthBuilder: (_) => 380.0,
                  builder: (_) => const TodoPanel(todo: todo),
                ),
                ConversationSidebarPanelEntry(
                  kind: ConversationSidebarPanelKind.file,
                  icon: Icons.article_outlined,
                  label: 'notes.md',
                  onDismiss: () => setState(() => state.closeFile()),
                  builder: (_) => const Center(child: Text('Markdown 文档内容')),
                ),
              ];
              final activeKind = state.isOpen ? state.activeKind : null;
              final activeEntry = activeKind == null
                  ? null
                  : entries.firstWhere(
                      (entry) => entry.kind == activeKind,
                      orElse: () => entries.first,
                    );
              final activeLayoutMode = activeEntry == null
                  ? ConversationSidebarLayoutMode.split
                  : state.layoutModeFor(
                      activeEntry.kind,
                      defaultMode: activeEntry.defaultLayoutMode,
                    );
              return ConversationWorkspaceShell(
                readingArea: const SizedBox.expand(
                  key: ValueKey('unified-reading-area'),
                ),
                footerDockBuilder: (_, _) => Padding(
                  key: const ValueKey('unified-footer-dock'),
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    key: const ValueKey('unified-composer-field'),
                    controller: composerController,
                  ),
                ),
                statusBar: Container(
                  key: const ValueKey('unified-status-bar'),
                  height: 38,
                  color: Colors.grey.shade200,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ConversationSidebarToggleButton(
                        available: entries.isNotEmpty,
                        expanded: state.isOpen,
                        onPressed: () => setState(
                          () => state.toggleSidebar(
                            availableOrder: [for (final e in entries) e.kind],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                sidebarBuilder: activeEntry == null
                    ? null
                    : (_, presentation) => ConversationRightSidebar(
                        entries: entries,
                        activeKind: activeEntry.kind,
                        presentation: presentation,
                        onSelectKind: (kind) =>
                            setState(() => state.openPanel(kind)),
                        onToggleLayoutMode: () => setState(
                          () => state.toggleLayoutMode(
                            activeEntry.kind,
                            defaultMode: activeEntry.defaultLayoutMode,
                          ),
                        ),
                        onCollapse: () => setState(state.collapse),
                      ),
                sidebarExpanded:
                    activeEntry != null &&
                    activeLayoutMode == ConversationSidebarLayoutMode.expanded,
                expandedDockBehavior:
                    activeEntry?.expandedDockBehavior ??
                    ConversationExpandedDockBehavior.coverAll,
                sidebarCustomWidth: reportedCustomWidth,
                sidebarDefaultWidthBuilder: activeEntry?.defaultWidthBuilder,
                onSidebarWidthChanged: (w) => reportedCustomWidth = w,
                onCollapseSidebar: () => setState(state.collapse),
              );
            },
          ),
        );

        await tester.pumpWidget(buildHarness());
        await tester.pumpAndSettle();

        final statusBarFinder = find.byKey(
          const ValueKey('unified-status-bar'),
        );
        expect(tester.getRect(statusBarFinder).width, closeTo(1280, 1));
        expect(find.byKey(StudioDriverKeys.rightSidebar), findsNothing);
        final composerElement = tester.element(
          find.byKey(const ValueKey('unified-composer-field')),
        );
        final timelineElement = tester.element(
          find.byKey(const ValueKey('unified-reading-area')),
        );

        // Open sidebar in split mode.
        await tester.tap(find.byKey(StudioDriverKeys.rightSidebarToggle));
        await tester.pumpAndSettle();

        final sidebarRect = tester.getRect(
          find.byKey(StudioDriverKeys.rightSidebar),
        );
        final statusRect = tester.getRect(statusBarFinder);
        final footerRect = tester.getRect(
          find.byKey(const ValueKey('unified-footer-dock')),
        );
        final readingRect = tester.getRect(
          find.byKey(const ValueKey('unified-reading-area')),
        );

        expect(statusRect.width, closeTo(1280, 1));
        expect(sidebarRect.bottom, closeTo(statusRect.top, 1.0));
        expect(sidebarRect.width, closeTo(380, 1.0));
        expect(footerRect.right, lessThanOrEqualTo(sidebarRect.left + 1.0));
        expect(readingRect.right, lessThanOrEqualTo(sidebarRect.left + 1.0));
        expect(
          tester.element(find.byKey(const ValueKey('unified-composer-field'))),
          same(composerElement),
        );
        expect(
          tester.element(find.byKey(const ValueKey('unified-reading-area'))),
          same(timelineElement),
        );
        expect(composerController.text, '保留输入草稿');

        // Drag divider left to widen sidebar, then double-tap to reset.
        final divider = find.byKey(StudioDriverKeys.rightSidebarResizeHandle);
        await tester.drag(divider, const Offset(-80, 0));
        await tester.pumpAndSettle();
        final draggedWidth = tester
            .getRect(find.byKey(StudioDriverKeys.rightSidebar))
            .width;
        expect(draggedWidth, closeTo(460, 2.0));
        expect(reportedCustomWidth, closeTo(460, 2.0));

        // Double-tap resets to default width (380).
        await tester.tap(divider);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(divider);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(StudioDriverKeys.rightSidebar)).width,
          closeTo(380, 2.0),
        );
        expect(reportedCustomWidth, isNull);

        // Semantics increase/decrease adjusts width by resizeStep (24px).
        final resizeSemantics = find.semantics.byLabel(
          tester.element(divider).l10n.rightSidebarResize,
        );
        tester.semantics.increase(resizeSemantics);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(StudioDriverKeys.rightSidebar)).width,
          closeTo(404, 2.0),
        );
        tester.semantics.decrease(resizeSemantics);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(StudioDriverKeys.rightSidebar)).width,
          closeTo(380, 2.0),
        );

        // Switch tab inside header & dismiss file tab.
        await tester.tap(find.byKey(StudioDriverKeys.rightSidebarTab('file')));
        await tester.pumpAndSettle();
        expect(find.text('Markdown 文档内容'), findsOneWidget);
        await tester.tap(find.byKey(StudioDriverKeys.rightSidebarFileClose));
        await tester.pumpAndSettle();
        expect(find.byKey(StudioDriverKeys.rightSidebar), findsNothing);

        // Reopen & toggle coverAll full width, keeping status bar visible below.
        await tester.tap(find.byKey(StudioDriverKeys.rightSidebarToggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(StudioDriverKeys.rightSidebarExpandMode));
        await tester.pumpAndSettle();
        final fullSidebarRect = tester.getRect(
          find.byKey(StudioDriverKeys.rightSidebar),
        );
        expect(fullSidebarRect.width, closeTo(1280, 1.0));
        expect(fullSidebarRect.bottom, closeTo(statusRect.top, 1.0));
        expect(tester.getRect(statusBarFinder).width, closeTo(1280, 1.0));
      },
      semanticsEnabled: true,
    );

    testWidgets(
      'pending plan defaults to expanded with confirmation bar below, and compresses confirmation left in split',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final state = ConversationSidebarState<String>()
          ..observePlan(identity: 'interaction:1', pending: true);

        await tester.pumpWidget(
          _zhApp(
            StatefulBuilder(
              builder: (context, setState) {
                final entry = ConversationSidebarPanelEntry(
                  kind: ConversationSidebarPanelKind.plan,
                  icon: Icons.description_outlined,
                  label: '实施计划',
                  badge: const PlanDetailStatusBadge(
                    status: PlanDetailStatus.awaitingConfirmation,
                  ),
                  defaultLayoutMode: ConversationSidebarLayoutMode.expanded,
                  expandedDockBehavior:
                      ConversationExpandedDockBehavior.keepFooterBelow,
                  defaultWidthBuilder: (w) => (w * 0.48).clamp(360.0, 620.0),
                  builder: (_) => const PlanDetailView(
                    identity: 'interaction:1',
                    body: Text('Full blueprint body'),
                  ),
                );
                final mode = state.layoutModeFor(
                  entry.kind,
                  defaultMode: entry.defaultLayoutMode,
                );
                return ConversationWorkspaceShell(
                  readingArea: const SizedBox.expand(),
                  footerDockBuilder: (_, _) => PlanConfirmationView(
                    interactionId: 'interaction:1',
                    available: true,
                    enabled: true,
                    error: null,
                    onSubmitRevision: (_) {},
                    onApprove: () {},
                  ),
                  sidebarBuilder: !state.isOpen
                      ? null
                      : (_, presentation) => ConversationRightSidebar(
                          entries: [entry],
                          activeKind: entry.kind,
                          presentation: presentation,
                          onSelectKind: (_) {},
                          onToggleLayoutMode: () => setState(
                            () => state.toggleLayoutMode(
                              entry.kind,
                              defaultMode: entry.defaultLayoutMode,
                            ),
                          ),
                          onCollapse: () => setState(state.collapse),
                        ),
                  sidebarExpanded:
                      state.isOpen &&
                      mode == ConversationSidebarLayoutMode.expanded,
                  expandedDockBehavior: entry.expandedDockBehavior,
                  sidebarDefaultWidthBuilder: entry.defaultWidthBuilder,
                  statusBar: Container(
                    key: const ValueKey('plan-status-bar'),
                    height: 38,
                    alignment: Alignment.centerRight,
                    child: ConversationSidebarToggleButton(
                      available: true,
                      expanded: state.isOpen,
                      onPressed: () => setState(
                        () => state.toggleSidebar(
                          availableOrder: const [
                            ConversationSidebarPanelKind.plan,
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final sidebarRectExpanded = tester.getRect(
          find.byKey(StudioDriverKeys.rightSidebar),
        );
        final confirmRectExpanded = tester.getRect(
          find.byType(PlanConfirmationView),
        );
        final statusRect = tester.getRect(
          find.byKey(const ValueKey('plan-status-bar')),
        );
        expect(sidebarRectExpanded.width, closeTo(1280, 1.0));
        expect(confirmRectExpanded.width, closeTo(1280, 1.0));
        expect(
          sidebarRectExpanded.bottom,
          lessThanOrEqualTo(confirmRectExpanded.top + 1.0),
        );
        expect(confirmRectExpanded.bottom, closeTo(statusRect.top, 1.0));

        // Enter draft feedback and switch to split mode.
        await tester.enterText(
          find.byKey(StudioDriverKeys.planFeedbackInput),
          '请保留分栏输入',
        );
        final confirmState = tester.state(find.byType(PlanConfirmationView));
        await tester.tap(find.byKey(StudioDriverKeys.rightSidebarExpandMode));
        await tester.pumpAndSettle();

        final sidebarRectSplit = tester.getRect(
          find.byKey(StudioDriverKeys.rightSidebar),
        );
        final confirmRectSplit = tester.getRect(
          find.byType(PlanConfirmationView),
        );
        expect(
          confirmRectSplit.right,
          lessThanOrEqualTo(sidebarRectSplit.left + 1.0),
        );
        expect(sidebarRectSplit.bottom, closeTo(statusRect.top, 1.0));
        expect(confirmRectSplit.bottom, closeTo(statusRect.top, 1.0));
        expect(
          tester.state(find.byType(PlanConfirmationView)),
          same(confirmState),
        );
        expect(find.text('请保留分栏输入'), findsOneWidget);

        // Narrow window switches pending plan back to full-width reading above footer.
        await tester.binding.setSurfaceSize(const Size(640, 800));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(StudioDriverKeys.rightSidebar)).width,
          closeTo(640, 1.0),
        );
        expect(
          tester.getRect(find.byType(PlanConfirmationView)).width,
          closeTo(640, 1.0),
        );
      },
    );

    testWidgets(
      'narrow viewport mounts coverAll overlay above status bar and closes via scrim or Escape',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(640, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final state = ConversationSidebarState<String>()
          ..openPanel(ConversationSidebarPanelKind.todo);
        const todo = TimelineTodoListUpdate(
          callId: 'todo-narrow',
          items: [TimelineTodoItem(step: '检查窄窗浮层', status: 'inProgress')],
        );

        await tester.pumpWidget(
          _zhApp(
            StatefulBuilder(
              builder: (context, setState) => ConversationWorkspaceShell(
                readingArea: const SizedBox.expand(),
                footerDockBuilder: (_, _) => const SizedBox(height: 64),
                sidebarBuilder: !state.isOpen
                    ? null
                    : (_, presentation) => ConversationRightSidebar(
                        entries: [
                          ConversationSidebarPanelEntry(
                            kind: ConversationSidebarPanelKind.todo,
                            icon: Icons.checklist_outlined,
                            label: '待办',
                            builder: (_) => const Column(
                              children: [
                                TextField(
                                  key: ValueKey('overlay-focus-target'),
                                ),
                                Expanded(child: TodoPanel(todo: todo)),
                              ],
                            ),
                          ),
                        ],
                        activeKind: ConversationSidebarPanelKind.todo,
                        presentation: presentation,
                        onSelectKind: (_) {},
                        onCollapse: () => setState(state.collapse),
                      ),
                onCollapseSidebar: () => setState(state.collapse),
                statusBar: Container(
                  key: const ValueKey('narrow-status-bar'),
                  height: 38,
                  alignment: Alignment.centerRight,
                  child: ConversationSidebarToggleButton(
                    available: true,
                    expanded: state.isOpen,
                    onPressed: () => setState(
                      () => state.toggleSidebar(
                        availableOrder: const [
                          ConversationSidebarPanelKind.todo,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final overlayRect = tester.getRect(
          find.byKey(StudioDriverKeys.rightSidebar),
        );
        final statusRect = tester.getRect(
          find.byKey(const ValueKey('narrow-status-bar')),
        );
        expect(overlayRect.width, closeTo(440, 1.0));
        expect(overlayRect.bottom, lessThanOrEqualTo(statusRect.top + 1.0));
        expect(
          find.byKey(StudioDriverKeys.rightSidebarOverlayScrim),
          findsOneWidget,
        );

        // Tap scrim closes overlay.
        await tester.tapAt(const Offset(40, 200));
        await tester.pumpAndSettle();
        expect(find.byKey(StudioDriverKeys.rightSidebar), findsNothing);

        // Reopen overlay, focus inside overlay, and press Escape to close.
        await tester.tap(find.byKey(StudioDriverKeys.rightSidebarToggle));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('overlay-focus-target')));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(StudioDriverKeys.rightSidebar), findsNothing);
      },
    );
  });

  group('ACP unified sidebar connector', () {
    testWidgets(
      'guards uninitialized host plan, opens initialized plan and steps in sidebar, and opens embedded markdown resource',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final harness = await AcpComponentHarness.create();
        await tester.pumpWidget(
          harness.scope(
            const SizedBox.expand(
              child: AcpWorkspaceConnector(threadId: 'thread'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        harness.emit(
          const AcpInitializedEventView(
            AcpAgentCapabilitiesView(
              image: false,
              audio: false,
              embeddedContext: true,
              loadSession: true,
              listSessions: true,
              resumeSession: true,
            ),
          ),
        );
        // Uninitialized sentinel host plan (`revision == 0 && document == null`)
        // must not expose a Plan tab or status bar pill.
        harness.emit(
          AcpWorkflowStateUpdatedEventView(
            AcpWorkflowStateView(
              modeId: 'mode.auto',
              modeDisplayName: '自动',
              plan: PlanRuntimeView(
                revision: 0,
                state: PlanRuntimePhase.drafting,
                updatedAt: DateTime.utc(2026),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(StudioDriverKeys.statusPlanEntry), findsNothing);
        expect(find.byKey(StudioDriverKeys.rightSidebarToggle), findsOneWidget);

        // Emit initialized host MCP plan + ACP steps + embedded Markdown resource.
        harness.emit(
          AcpWorkflowStateUpdatedEventView(
            AcpWorkflowStateView(
              modeId: 'mode.auto',
              modeDisplayName: '自动',
              plan: PlanRuntimeView(
                revision: 1,
                state: PlanRuntimePhase.approved,
                updatedAt: DateTime.utc(2026),
                document: const PlanDocumentView(
                  version: 1,
                  markdown: '# ACP Host Plan\n\nAligned with Native sidebar.',
                  contentHash: 'acp-plan-h1',
                ),
              ),
            ),
          ),
        );
        harness.update(
          AcpPlanView(
            entries: const [
              AcpPlanEntryView(
                content: '准备统一工作区外壳',
                priority: AcpPlanPriorityView.high,
                status: AcpPlanStatusView.completed,
              ),
              AcpPlanEntryView(
                content: '迁入 ACP 执行步骤',
                priority: AcpPlanPriorityView.medium,
                status: AcpPlanStatusView.inProgress,
              ),
            ],
          ),
        );
        harness.update(
          const AcpAgentMessageChunkView(
            AcpContentChunkView(
              content: AcpEmbeddedResourceView(
                resource: AcpTextResourceContentsView(
                  uri: 'file:///docs/spec.md',
                  mimeType: 'text/markdown',
                  text: '# Spec Preview\n\nOpened inside unified sidebar.',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open host Plan via status bar pill.
        expect(find.byKey(StudioDriverKeys.statusPlanEntry), findsOneWidget);
        await tester.tap(find.byKey(StudioDriverKeys.statusPlanEntry));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus))
              .data,
          '已批准',
        );
        expect(
          find.textContaining('ACP Host Plan', findRichText: true),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byKey(StudioDriverKeys.rightSidebar)).width,
          lessThan(1280),
        );

        // Toggle steps panel via status bar steps pill.
        expect(
          find.byKey(const ValueKey('acp-plan-status-pill')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('acp-plan-status-pill')));
        await tester.pumpAndSettle();
        expect(find.byType(AcpPlanPanel), findsOneWidget);
        expect(find.text('迁入 ACP 执行步骤'), findsOneWidget);

        // Verify left composer is compressed alongside the right sidebar.
        final sidebarRect = tester.getRect(
          find.byKey(StudioDriverKeys.rightSidebar),
        );
        final statusBarRect = tester.getRect(find.byType(AcpStatusBarView));
        final composerRect = tester.getRect(
          find.byType(AcpConversationComposerView),
        );
        expect(statusBarRect.width, closeTo(1280, 1.0));
        expect(sidebarRect.bottom, closeTo(statusBarRect.top, 1.0));
        expect(composerRect.right, lessThanOrEqualTo(sidebarRect.left + 1.0));

        // Open embedded Markdown resource in unified sidebar.
        await tester.tap(
          find.byKey(const ValueKey('acp-open-markdown:file:///docs/spec.md')),
        );
        await tester.pumpAndSettle();
        expect(find.text('spec.md'), findsWidgets);
        expect(
          find.textContaining('Spec Preview', findRichText: true),
          findsOneWidget,
        );

        await harness.close(tester);
      },
    );
  });
}
