import 'package:anywork/src/features/conversation/composer/state/start_backend_view_state.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_route_selectors.dart';
import 'package:anywork/src/features/conversation/composer/views/start_model_selector_view.dart';
import 'package:anywork/src/features/status/session_selectors.dart';
import 'package:anywork/src/shared/widgets/account_brand.dart';
import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/studio_menu_label.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

final _accounts = [
  ModelSelectionAccount(
    id: 'account',
    name: '测试账号',
    brandKey: 'openai',
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
        inputCapabilities: [
          ModelInputCapabilityView(
            modality: ModelModalityView.image,
            sources: [ModelInputSourceView.local],
          ),
        ],
        typeSupport: [ModelTypeSupportView(modelType: ModelType.text)],
      ),
    ],
  ),
];

void main() {
  testWidgets('实际测宽矩阵逐项收纳、保持次序与回调并维持单排', (tester) async {
    const cases = [
      (width: 60.0, visible: <String>[]),
      (width: 111.0, visible: ['first']),
      (width: 145.0, visible: ['first', 'third']),
      (width: 146.0, visible: ['first', 'second']),
      (width: 164.0, visible: ['first', 'second', 'third']),
    ];
    const widths = {'first': 40.0, 'second': 70.0, 'third': 50.0};
    const ids = ['first', 'second', 'third'];

    for (final testCase in cases) {
      final callbacks = <String>[];
      await tester.pumpWidget(
        _testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: testCase.width,
              child: ComposerConfigurationBar(
                moreTooltip: '更多配置',
                entries: [
                  for (final id in ids)
                    ComposerConfigurationEntry(
                      id: id,
                      inline: SizedBox(
                        key: ValueKey('inline-$id'),
                        width: widths[id]!,
                        height: 32,
                        child: InkWell(
                          onTap: () => callbacks.add(id),
                          child: Center(child: Text(id)),
                        ),
                      ),
                      measureInlineWidth: (_) => widths[id]!,
                      menuItem: MenuItemButton(
                        key: ValueKey('menu-$id'),
                        onPressed: () => callbacks.add(id),
                        child: Text('配置 $id · 当前值'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final visible = [
        for (final id in ids)
          if (find
              .byKey(ValueKey('inline-$id'))
              .hitTestable()
              .evaluate()
              .isNotEmpty)
            id,
      ];
      expect(
        visible,
        testCase.visible,
        reason: '可放下的项目按原序逐项填入 ${testCase.width}px',
      );
      final hidden = ids.where((id) => !visible.contains(id)).toList();
      final more = find.byKey(ComposerConfigurationBar.moreKey);
      expect(more.hitTestable().evaluate().isNotEmpty, hidden.isNotEmpty);

      final row = <Rect>[
        for (final id in visible)
          tester.getRect(find.byKey(ValueKey('inline-$id'))),
        if (hidden.isNotEmpty) tester.getRect(more),
      ];
      for (final rect in row.skip(1)) {
        expect(rect.center.dy, closeTo(row.first.center.dy, 1));
      }
      for (var index = 1; index < row.length; index++) {
        expect(row[index - 1].right, lessThanOrEqualTo(row[index].left));
      }
      for (final id in visible) {
        await tester.tap(find.byKey(ValueKey('inline-$id')));
        await tester.pump();
        expect(callbacks, contains(id));
      }

      if (hidden.isNotEmpty) {
        await tester.tap(more);
        await tester.pumpAndSettle();
        final menuRects = <Rect>[];
        for (final id in hidden) {
          final item = find.byKey(ValueKey('menu-$id'));
          expect(item.hitTestable(), findsOneWidget);
          expect(find.text('配置 $id · 当前值'), findsOneWidget);
          menuRects.add(tester.getRect(item));
        }
        for (var index = 1; index < menuRects.length; index++) {
          expect(menuRects[index - 1].top, lessThan(menuRects[index].top));
        }
        for (final id in hidden) {
          if (find
              .byKey(ValueKey('menu-$id'))
              .hitTestable()
              .evaluate()
              .isEmpty) {
            await tester.tap(more);
            await tester.pumpAndSettle();
          }
          final menuItem = find.byKey(ValueKey('menu-$id'));
          expect(
            tester.widget<MenuItemButton>(menuItem).onPressed,
            isNotNull,
            reason: '隐藏项目 $id 必须保留自己的选择回调',
          );
          await tester.tap(menuItem);
          await tester.pump();
          expect(callbacks, contains(id));
        }
      }
      expect(tester.takeException(), isNull, reason: '配置行不得产生布局溢出');
    }
  });

  testWidgets('StudioMenuLabel测宽与真实绘制宽度共享字体、缩放、leading及间距', (tester) async {
    const cases = [
      (label: '短项', scale: 1.0, leading: false),
      (label: '较长的配置名称与当前模型值', scale: 1.0, leading: false),
      (label: '短项', scale: 2.0, leading: true),
      (label: '超长配置名称与大字模型当前值', scale: 2.0, leading: true),
    ];

    for (final testCase in cases) {
      final key = ValueKey('measure-${testCase.label}-${testCase.scale}');
      await tester.pumpWidget(
        _testApp(
          Builder(
            builder: (context) => Center(
              child: StudioMenuLabel(
                key: key,
                label: testCase.label,
                maxWidth: 132,
                leading: testCase.leading
                    ? const Icon(Icons.tune, size: 18)
                    : null,
              ),
            ),
          ),
          textScale: testCase.scale,
        ),
      );
      final finder = find.byKey(key);
      final label = tester.widget<StudioMenuLabel>(finder);
      final measured = label.measureWidth(
        tester.element(finder),
        leadingWidth: testCase.leading ? 18 : 0,
      );
      expect(tester.getSize(finder).width, closeTo(measured, 1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('不改变窗口时标签变长收纳并恢复短标签后回到行内', (tester) async {
    var labelText = '模式';
    late StateSetter rebuild;
    const width = 100.0;

    Widget configurationEntry() {
      final label = StudioMenuLabel(label: labelText, maxWidth: 120);
      return ComposerConfigurationBar(
        moreTooltip: '更多配置',
        entries: [
          ComposerConfigurationEntry(
            id: 'dynamic-mode',
            inline: StudioMenuLabel(
              key: const ValueKey('dynamic-inline'),
              label: labelText,
              maxWidth: 120,
            ),
            measureInlineWidth: (context) => label.measureWidth(context),
            menuItem: MenuItemButton(
              key: const ValueKey('dynamic-menu'),
              child: Text(labelText),
            ),
          ),
        ],
      );
    }

    await tester.pumpWidget(
      _testApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return configurationEntry();
              },
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('dynamic-inline')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(ComposerConfigurationBar.moreKey), findsNothing);

    rebuild(() => labelText = '非常长的配置名称与服务端当前模型值');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dynamic-inline')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(ComposerConfigurationBar.moreKey).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
    await tester.pumpAndSettle();
    expect(find.text('非常长的配置名称与服务端当前模型值'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    rebuild(() => labelText = '模式');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dynamic-inline')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(ComposerConfigurationBar.moreKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [700.0, 90.0]) {
    testWidgets('Native 配置宽度 $width 复用相同候选、稳定 key 与在途选择语义', (tester) async {
      final selections = <Object>[];
      const catalog = ThreadModeCatalogView(
        modes: [
          ThreadModeDescriptorView(
            id: 'mode.auto',
            displayName: '自动',
            description: '自动模式',
            order: 0,
            hasWorkflow: true,
          ),
          ThreadModeDescriptorView(
            id: 'mode.custom',
            displayName: '自定义',
            description: '自定义模式',
            order: 1,
            hasWorkflow: false,
          ),
        ],
      );
      final inlineMode = SessionModeSelector(
        catalog: catalog,
        mode: ThreadModeId.auto,
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
                      catalog: catalog,
                      mode: ThreadModeId.auto,
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
        expect(find.text('自动'), findsOneWidget);
        expect(find.text('low'), findsOneWidget);
        expect(find.text('会话模式 · 自动'), findsNothing);
        expect(find.text('思考强度 · low'), findsNothing);
        expect(find.text('会话模式'), findsNothing);
        expect(find.text('思考强度'), findsNothing);
      }
      Future<void> open(Key key) async {
        if (width == 90) {
          await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.byType(SubmenuButton), findsNWidgets(3));
          for (final title in ['会话模式 · 自动', '思考强度 · low']) {
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
        if (key == StudioDriverKeys.model) {
          expect(
            find.descendant(
              of: find.byKey(key),
              matching: find.byType(AccountBrandMark),
            ),
            findsNothing,
          );
        }
        await tester.tap(find.byKey(key));
        await tester.pump(const Duration(milliseconds: 300));
      }

      await open(StudioDriverKeys.sessionMode);
      await tester.tap(
        find.byKey(StudioDriverKeys.sessionModeOption('mode.custom')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(selections.last, ThreadModeId.fromId('mode.custom'));
      await open(StudioDriverKeys.model);
      expect(
        find.byKey(StudioDriverKeys.modelCapabilityTags('account', 'two')),
        findsOneWidget,
      );
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
      find.byKey(StudioDriverKeys.modelCapabilityTags('account', 'two')),
      findsOneWidget,
    );
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

Widget _testApp(Widget child, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);
