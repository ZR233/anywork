import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_input_state.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_content_view.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/interactions/view_models/interaction_command_view_model.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('完整根会话 Composer 在宽窄窗和聚焦时保留有序选择器、单层外框及发送状态', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final width in [800.0, 360.0]) {
      tester.view.physicalSize = Size(width, 360);
      await tester.pumpWidget(completeComposerFixture());
      await tester.pumpAndSettle();
      _expectCompleteLayout(tester, wide: width >= 540);

      await tester.tap(find.byKey(StudioDriverKeys.composerInput));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      _expectCompleteLayout(tester, wide: width >= 540, focused: true);
      await tester.pumpWidget(const SizedBox.shrink());
    }

    // One immutable empty draft proves the disabled presentation; selector
    // switching itself is already covered by session_selector_sync_test.dart.
    await tester.pumpWidget(completeComposerFixture(draft: ''));
    await tester.pumpAndSettle();
    expect(find.byKey(StudioDriverKeys.composerSubmit), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('composer-submit-disabled')),
          )
          .onPressed,
      isNull,
    );
    expect(find.byType(SessionModeSelector), findsOneWidget);
    expect(find.byType(ModelRoleSelector), findsOneWidget);
    expect(find.byType(ReasoningEffortSelector), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

void _expectCompleteLayout(
  WidgetTester tester, {
  required bool wide,
  bool focused = false,
}) {
  expect(find.byType(ComposerContentView), findsOneWidget);
  expect(find.byType(SessionModeSelector), findsOneWidget);
  expect(find.byType(ModelRoleSelector), findsOneWidget);
  expect(find.byType(ReasoningEffortSelector), findsOneWidget);
  expect(find.text('任务'), findsOneWidget);
  expect(find.text('GPT-6.1 Sol'), findsOneWidget);
  expect(find.text('high'), findsOneWidget);

  final prompt = find.byType(PromptComposerView);
  final outlined = find.descendant(
    of: prompt,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is InputDecorator &&
          widget.decoration.border is OutlineInputBorder,
    ),
  );
  expect(outlined, findsOneWidget, reason: '输入区和底栏必须共用唯一整体外框');
  expect(tester.widget<InputDecorator>(outlined).isFocused, focused);
  final decoration = tester
      .widget<TextField>(find.byKey(StudioDriverKeys.composerInput))
      .decoration!;
  for (final border in [
    decoration.border,
    decoration.enabledBorder,
    decoration.focusedBorder,
    decoration.disabledBorder,
  ]) {
    expect(border, InputBorder.none, reason: '编辑器不得在聚焦或禁用时重建第二层边框');
  }

  final panel = tester.getRect(outlined);
  final input = tester.getRect(find.byKey(StudioDriverKeys.composerInput));
  final selectors =
      [
        StudioDriverKeys.sessionMode,
        StudioDriverKeys.model,
        StudioDriverKeys.reasoningEffort,
      ].map((key) {
        final finder = find.byKey(key);
        expect(finder, findsOneWidget);
        expect(finder.hitTestable(), findsOneWidget, reason: '选择器不能被裁剪或遮挡');
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(panel.left));
        expect(rect.right, lessThanOrEqualTo(panel.right));
        expect(rect.top, greaterThanOrEqualTo(input.bottom));
        expect(rect.bottom, lessThanOrEqualTo(panel.bottom));
        return rect;
      }).toList();
  final sendFinder = find.byKey(StudioDriverKeys.composerSubmit);
  expect(sendFinder.hitTestable(), findsOneWidget);
  expect(tester.widget<IconButton>(sendFinder).onPressed, isNotNull);
  final send = tester.getRect(sendFinder);
  expect(send.right, lessThanOrEqualTo(panel.right));
  expect(send.bottom, lessThanOrEqualTo(panel.bottom));

  for (var i = 1; i < selectors.length; i++) {
    final previous = selectors[i - 1];
    final next = selectors[i];
    if ((next.center.dy - previous.center.dy).abs() < 1) {
      expect(previous.right, lessThanOrEqualTo(next.left));
    } else {
      expect(previous.bottom, lessThanOrEqualTo(next.top));
    }
  }
  if (wide) {
    for (final selector in selectors) {
      expect(selector.center.dy, closeTo(send.center.dy, 1));
      expect(selector.right, lessThanOrEqualTo(send.left));
    }
  } else {
    for (final selector in selectors) {
      expect(selector.bottom, lessThanOrEqualTo(send.top));
    }
  }
  expect(tester.takeException(), isNull, reason: '包含 RenderFlex overflow 检查');
}

// Shared by the one-off screenshot probe. This is a synthetic typed snapshot,
// not a live account, model availability claim, or a replacement state machine.
Widget completeComposerFixture({
  String draft = '请检查当前项目的布局，并保留完整的模式、模型和强度选择器。',
}) {
  const threadId = 'complete-composer-layout';
  final composer = ComposerThreadState.idle(draft: draft);
  final state = ComposerViewState(
    input: ComposerInputState(composer: composer, enabled: true, nowMs: 0),
    modeCatalog: const ThreadModeCatalogView(
      revision: 1,
      modes: [
        ThreadModeDescriptorView(
          id: 'mode.task',
          displayName: '任务',
          description: '合成布局场景',
          order: 0,
          hasWorkflow: true,
        ),
      ],
    ),
    thread: ComposerDockViewState(
      row: SessionDirectoryRow(
        sessionId: 'layout-session',
        agentId: 'layout-root',
        threadId: threadId,
        workspaceId: 'layout-workspace',
        title: '完整 Composer 布局样例',
        mode: ThreadModeId.task,
        delegationMode: DelegationMode.automatic,
        delegationPreference: DelegationPreference.balanced,
        workspacePath: 'synthetic-layout-workspace',
        backend: const NativeAgentBackendView(
          config: NativeAgentConfigView(),
          status: ThreadStatusView.idle,
        ),
        updatedAt: DateTime.utc(2026),
      ),
      hasSnapshot: true,
      revision: 1,
      composer: composer,
      activeInteraction: null,
      turn: null,
      execution: null,
      continuation: null,
      stopCommand: null,
      continueCommand: null,
      saveBlocked: false,
      recoveryIssue: null,
      executionClosed: false,
      childInteractions: const [],
      childInteractionSync: null,
      childInteractionSources: const {},
      modelRoute: const ThreadModelRouteView(
        accountId: 'synthetic-account',
        modelId: 'synthetic-gpt-6.1-sol',
        effort: 'high',
        revision: 1,
        available: true,
      ),
      routePending: false,
      routeFailure: null,
      workflow: null,
      accounts: [
        ModelSelectionAccount(
          id: 'synthetic-account',
          name: '合成布局账号',
          billingKind: null,
          models: const [
            AccountModelView(
              modelId: 'synthetic-gpt-6.1-sol',
              displayName: 'GPT-6.1 Sol',
              reasoningEfforts: ['low', 'medium', 'high'],
              typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
            ),
          ],
        ),
      ],
      settingsLoaded: true,
      targetDiagnostic: null,
      additionalDiagnostics: const [],
    ),
  );
  return ProviderScope(
    overrides: [
      interactionCommandViewModelProvider(threadId)
          .overrideWith(_EmptyInteractionCommands.new),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: pureStudioTheme(locale: const Locale('zh')),
      locale: const Locale('zh'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ComposerContentView(
          target: const ComposerTarget.thread(threadId: threadId),
          state: state,
          actions: _UnexpectedComposerActions(),
        ),
      ),
    ),
  );
}

class _UnexpectedComposerActions extends Fake implements ComposerViewModel {}

class _EmptyInteractionCommands extends InteractionCommandViewModel {
  @override
  InteractionCommandViewState build(String hostThreadId) =>
      InteractionCommandViewState();
}
