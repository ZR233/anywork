import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_input_state.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_view_model.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_content_view.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/interactions/view_models/interaction_command_view_model.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('完整根会话 Composer 在宽窄窗和聚焦时保留配置可达性、单层外框及发送状态', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    for (final width in [800.0, 360.0, 260.0]) {
      tester.view.physicalSize = Size(width, 360);
      await tester.pumpWidget(completeComposerFixture());
      await tester.pumpAndSettle();
      _expectCompleteLayout(tester, wide: width >= 540);
      if (width < 540) {
        final moreVisible = find
            .byKey(ComposerConfigurationBar.moreKey)
            .hitTestable()
            .evaluate()
            .isNotEmpty;
        if (width == 260) expect(moreVisible, isTrue);
        if (moreVisible) {
          await _expectNarrowConfigurationMenu(tester);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
      }

      await tester.tap(find.byKey(StudioDriverKeys.composerInput));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );
      _expectCompleteLayout(tester, wide: width >= 540);
      expect(
        tester
            .widget<IconButton>(find.byKey(StudioDriverKeys.composerSubmit))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }

    // One immutable empty draft proves the disabled presentation at narrow
    // width without assuming that every selector remains inline.
    tester.view.physicalSize = const Size(260, 360);
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
    _expectCompleteLayout(tester, wide: false, enabled: false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}

final _selectorExpectations = <({Key key, String menuLabel, Key optionKey})>[
  (
    key: StudioDriverKeys.sessionMode,
    menuLabel: '会话模式 · 自动',
    optionKey: StudioDriverKeys.sessionModeOption(ThreadModeId.auto.name),
  ),
  (
    key: StudioDriverKeys.model,
    menuLabel: '主智能体模型 · GPT-6.1 Sol',
    optionKey: StudioDriverKeys.modelOption(
      'synthetic-account',
      'synthetic-gpt-6.1-sol',
    ),
  ),
  (
    key: StudioDriverKeys.reasoningEffort,
    menuLabel: '思考强度 · high',
    optionKey: StudioDriverKeys.reasoningEffortOption('high'),
  ),
];

void _expectCompleteLayout(
  WidgetTester tester, {
  required bool wide,
  bool enabled = true,
}) {
  expect(find.byType(ComposerContentView), findsOneWidget);

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
  final inlineSelectors = <Rect>[];
  final hiddenSelectors = <({Key key, String menuLabel, Key optionKey})>[];
  for (final selector in _selectorExpectations) {
    final finder = find.byKey(selector.key);
    final isInline = finder.hitTestable().evaluate().isNotEmpty;
    if (wide) {
      expect(isInline, isTrue, reason: '${selector.menuLabel} 在宽窗应保持行内可达');
    }
    if (!isInline) {
      hiddenSelectors.add(selector);
      continue;
    }
    final rect = tester.getRect(finder.hitTestable());
    expect(rect.left, greaterThanOrEqualTo(panel.left));
    expect(rect.right, lessThanOrEqualTo(panel.right));
    expect(rect.top, greaterThanOrEqualTo(input.bottom));
    expect(rect.bottom, lessThanOrEqualTo(panel.bottom));
    inlineSelectors.add(rect);
    if (wide) {
      expect(find.text(selector.menuLabel.split(' · ').last), findsOneWidget);
    }
  }

  final moreFinder = find.byKey(ComposerConfigurationBar.moreKey);
  final moreVisible = moreFinder.hitTestable().evaluate().isNotEmpty;
  if (wide) {
    expect(moreVisible, isFalse, reason: '宽窗的三个常用配置应直接显示');
    expect(find.text('自动'), findsOneWidget);
    expect(find.text('GPT-6.1 Sol'), findsOneWidget);
    expect(find.text('high'), findsOneWidget);
  } else {
    expect(
      moreVisible,
      hiddenSelectors.isNotEmpty,
      reason: '只有实际未能行内显示的配置才需要更多入口',
    );
  }

  final sendFinder = find.byKey(
    enabled
        ? StudioDriverKeys.composerSubmit
        : const ValueKey('composer-submit-disabled'),
  );
  expect(sendFinder.hitTestable(), findsOneWidget);
  expect(
    tester.widget<IconButton>(sendFinder).onPressed,
    enabled ? isNotNull : isNull,
  );
  final send = tester.getRect(sendFinder);
  expect(send.left, greaterThanOrEqualTo(panel.left));
  expect(send.right, lessThanOrEqualTo(panel.right));
  expect(send.top, greaterThanOrEqualTo(input.bottom));
  expect(send.bottom, lessThanOrEqualTo(panel.bottom));

  if (wide) {
    _expectOneRow([...inlineSelectors, send], send);
  } else {
    final row = <Rect>[
      ...inlineSelectors,
      if (moreVisible) tester.getRect(moreFinder.hitTestable()),
      send,
    ];
    _expectOneRow(row, send);
  }
  expect(tester.takeException(), isNull, reason: '包含 RenderFlex overflow 检查');
}

void _expectOneRow(List<Rect> controls, Rect send) {
  for (final control in controls) {
    expect(control.center.dy, closeTo(send.center.dy, 1));
  }
  for (var index = 1; index < controls.length; index++) {
    expect(controls[index - 1].right, lessThanOrEqualTo(controls[index].left));
  }
}

Future<void> _expectNarrowConfigurationMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
  await tester.pumpAndSettle();

  final hidden = <({Key key, String menuLabel, Key optionKey})>[];
  var previousTop = double.negativeInfinity;
  for (final selector in _selectorExpectations) {
    final label = find.text(selector.menuLabel);
    if (label.evaluate().isEmpty) continue;
    expect(
      find.ancestor(of: label, matching: find.byType(SubmenuButton)),
      findsOneWidget,
      reason: '${selector.menuLabel} 必须作为可展开的真实配置项收纳',
    );
    final top = tester.getTopLeft(label).dy;
    expect(top, greaterThan(previousTop), reason: '收纳项保持模式、模型、强度的顺序');
    previousTop = top;
    hidden.add(selector);
  }
  expect(hidden, isNotEmpty, reason: '窄窗必须将至少一个配置项收纳进更多菜单');

  for (final selector in hidden) {
    if (find.text(selector.menuLabel).evaluate().isEmpty) {
      await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(selector.key));
    await tester.pumpAndSettle();
    final option = find.byKey(selector.optionKey);
    expect(
      option.hitTestable(),
      findsOneWidget,
      reason: '${selector.menuLabel} 能展开当前选项',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }
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
          id: 'mode.auto',
          displayName: '自动',
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
        mode: ThreadModeId.auto,
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
  // This fixture is a root test application, not a scoped production override.
  final container = ProviderContainer.test(
    overrides: [
      interactionCommandViewModelProvider(threadId)
          .overrideWith(_EmptyInteractionCommands.new),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
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
