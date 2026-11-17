import 'package:anywork/src/features/conversation/composer/state/start_backend_view_state.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_route_selectors.dart';
import 'package:anywork/src/features/conversation/composer/views/start_model_selector_view.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

final _accounts = [
  ModelSelectionAccount(
    id: 'account',
    name: '测试账号',
    billingKind: null,
    models: const [
      AccountModelView(
        modelId: 'one',
        displayName: '模型一',
        reasoningEfforts: ['low', 'high'],
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      ),
      AccountModelView(
        modelId: 'two',
        displayName: '模型二',
        reasoningEfforts: ['low', 'high'],
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      ),
    ],
  ),
];

void main() {
  for (final width in [700.0, 90.0]) {
    testWidgets('Native 配置宽度 $width 复用相同候选、稳定 key 与在途选择语义', (tester) async {
      final selections = <Object>[];
      final inlineMode = SessionModeSelector(
        catalog: const ThreadModeCatalogView(),
        mode: ThreadModeId.task,
        onSelected: selections.add,
      );
      await tester.pumpWidget(
        acpTestApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ComposerConfigurationBar(
                moreTooltip: '更多设置',
                entries: [
                  ComposerConfigurationEntry(
                    id: 'mode',
                    inline: inlineMode,
                    measureInlineWidth: inlineMode.measureInlineWidth,
                    menuItem: SessionModeSelector(
                      inMenu: true,
                      catalog: const ThreadModeCatalogView(),
                      mode: ThreadModeId.task,
                      onSelected: selections.add,
                    ),
                  ),
                  ...modelRouteConfigurationEntries(
                    accounts: _accounts,
                    pending: true,
                    accountId: 'account',
                    modelId: 'one',
                    effort: 'low',
                    unavailableReason: '不可用',
                    onModelSelected: (account, model) =>
                        selections.add((account, model)),
                    onEffortSelected: selections.add,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (width == 700) {
        expect(find.text('任务'), findsOneWidget);
        expect(find.text('low'), findsOneWidget);
        expect(find.text('会话模式 · 任务'), findsNothing);
        expect(find.text('思考强度 · low'), findsNothing);
        expect(find.text('会话模式'), findsNothing);
        expect(find.text('思考强度'), findsNothing);
      }
      Future<void> open(Key key) async {
        if (width == 90) {
          await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SubmenuButton), findsNWidgets(3));
          for (final title in ['会话模式 · 任务', '思考强度 · low']) {
            final label = find.text(title);
            expect(label, findsOneWidget);
            expect(tester.widget<Text>(label).maxLines, 1);
            expect(
              find.ancestor(of: label, matching: find.byType(SubmenuButton)),
              findsOneWidget,
            );
          }
          expect(find.text('主智能体模型 · 模型一'), findsOneWidget);
        }
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 300));
      }

      await open(StudioDriverKeys.sessionMode);
      await tester.tap(
        find.byKey(
          StudioDriverKeys.sessionModeOption(ThreadModeId.simple.name),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(selections.last, ThreadModeId.simple);
      await open(StudioDriverKeys.model);
      await tester.tap(
        find.byKey(StudioDriverKeys.modelOption('account', 'two')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(selections.last, ('account', 'two'));
      await open(StudioDriverKeys.reasoningEffort);
      await tester.tap(
        find.byKey(StudioDriverKeys.reasoningEffortOption('high')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(selections.last, 'high');
      expect(selections, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('新会话更多菜单保留服务、模型候选及禁用服务，不嵌套根锚点', (tester) async {
    final selections = <Object?>[];
    await tester.pumpWidget(
      acpTestApp(
        MenuAnchor(
          menuChildren: [
            StartModelSelectorView(
              inMenu: true,
              state: StartBackendViewState(
                modelAccounts: _accounts,
                modelAccountId: 'account',
                modelId: 'one',
                accountId: 'agy',
                services: const [
                  StartBackendServiceItem(
                    id: 'agy',
                    name: 'Antigravity 合成服务',
                    enabled: true,
                  ),
                  StartBackendServiceItem(
                    id: 'disabled',
                    name: '已禁用服务',
                    enabled: false,
                  ),
                ],
                nativeEnabled: true,
                enabled: true,
                loading: false,
              ),
              onSelectModel: (account, model) =>
                  selections.add((account, model)),
              onSelectService: selections.add,
              onManageServices: () => selections.add('manage'),
            ),
          ],
          builder: (context, controller, _) =>
              TextButton(onPressed: controller.open, child: const Text('更多设置')),
        ),
      ),
    );
    await tester.tap(find.text('更多设置'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SubmenuButton), findsOneWidget);
    await tester.tap(find.byKey(StudioDriverKeys.model));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<MenuItemButton>(
            find.byKey(const ValueKey(('start-acp-service', 'disabled'))),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey(('start-acp-service', 'agy'))));
    await tester.pump(const Duration(milliseconds: 300));
    expect(selections.single, 'agy');
  });
}
