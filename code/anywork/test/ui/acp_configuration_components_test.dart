import 'dart:async';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_configuration_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_configuration_view_model.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

void main() {
  testWidgets('配置按服务端顺序完整呈现，不按名称或类别分配槽位', (tester) async {
    await tester.pumpWidget(
      acpTestApp(
        AcpConfigurationBar(
          state: const AcpConfigurationViewState(
            enabled: true,
            controls: [
              AcpConfigControlPresentation.select(
                id: 'z',
                name: '输出格式',
                category: AcpConfigCategoryKind.other,
                currentValue: 'json',
                currentLabel: 'JSON',
              ),
              AcpConfigControlPresentation.boolean(
                id: 'b',
                name: '保留引用',
                category: AcpConfigCategoryKind.model,
                currentValue: true,
              ),
              AcpConfigControlPresentation.select(
                id: 'a',
                name: '审阅方式',
                category: AcpConfigCategoryKind.other,
                currentValue: 'careful',
                currentLabel: '仔细',
              ),
            ],
          ),
          onSelectValue: (_, _) {},
          onBooleanChanged: (_, _) {},
          onSelectLegacyMode: (_) {},
        ),
      ),
    );
    final controls = ['z', 'b', 'a']
        .map((id) => find.byKey(ValueKey(AcpViewKeyValues.configControl(id))))
        .toList();
    for (final control in controls) {
      expect(control, findsOneWidget);
    }
    expect(
      tester.getTopLeft(controls[0]).dx,
      lessThan(tester.getTopLeft(controls[1]).dx),
    );
    expect(
      tester.getTopLeft(controls[1]).dx,
      lessThan(tester.getTopLeft(controls[2]).dx),
    );
    expect(find.text('输出格式 · JSON'), findsOneWidget);
    expect(find.text('审阅方式 · 仔细'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('动态控件禁用时尺寸不变，窄窗大字按原顺序换行', (tester) async {
    const controls = [
      AcpConfigControlPresentation.select(
        id: 'one',
        name: '自定义输出',
        category: AcpConfigCategoryKind.other,
        currentValue: 'one',
        currentLabel: '一',
      ),
      AcpConfigControlPresentation.select(
        id: 'two',
        name: '审阅方式',
        category: AcpConfigCategoryKind.other,
        currentValue: 'two',
        currentLabel: '二',
      ),
      AcpConfigControlPresentation.boolean(
        id: 'three',
        name: '引用',
        category: AcpConfigCategoryKind.unspecified,
        currentValue: true,
      ),
    ];
    Widget bar(bool enabled) => acpTestApp(
      AcpConfigurationBar(
        state: AcpConfigurationViewState(controls: controls, enabled: enabled),
        onSelectValue: (_, _) {},
        onBooleanChanged: (_, _) {},
        onSelectLegacyMode: (_) {},
      ),
    );
    await tester.pumpWidget(bar(true));
    final key = find.byKey(ValueKey(AcpViewKeyValues.configControl('one')));
    final size = tester.getSize(key);
    await tester.pumpWidget(bar(false));
    expect(tester.getSize(key), size);
    for (final button in tester.widgetList<TextButton>(
      find.byType(TextButton),
    )) {
      expect(button.onPressed, isNull);
    }
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await tester.binding.setSurfaceSize(const Size(260, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      acpTestApp(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(260, 680),
            textScaler: TextScaler.linear(2),
          ),
          child: SizedBox(
            width: 120,
            child: AcpConfigurationBar(
              state: const AcpConfigurationViewState(
                controls: controls,
                enabled: true,
              ),
              onSelectValue: (_, _) {},
              onBooleanChanged: (_, _) {},
              onSelectLegacyMode: (_) {},
            ),
          ),
        ),
      ),
    );
    for (final control in controls) {
      expect(
        find.byKey(ValueKey(AcpViewKeyValues.configControl(control.id))),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('长配置列表搜索名称和原始 ID，保留服务端分组及顺序', (tester) async {
    final selected = <(String, String)>[];
    final groups = [
      for (var group = 0; group < 2; group++)
        AcpSelectGroupPresentation(
          id: 'group/$group',
          name: group == 0 ? 'Z 组' : 'A 组',
          options: [
            for (var index = group * 6; index < (group + 1) * 6; index++)
              AcpSelectChoicePresentation(
                value: 'raw/value:$index',
                name: '选择 $index',
              ),
          ],
        ),
    ];
    await tester.pumpWidget(
      acpTestApp(
        AcpConfigurationBar(
          state: AcpConfigurationViewState(
            enabled: true,
            controls: [
              AcpConfigControlPresentation.select(
                id: 'vendor/model',
                name: '模型',
                category: AcpConfigCategoryKind.model,
                currentValue: 'raw/value:0',
                currentLabel: '选择 0',
                groups: groups,
              ),
            ],
          ),
          onSelectValue: (id, value) => selected.add((id, value)),
          onBooleanChanged: (_, _) {},
          onSelectLegacyMode: (_) {},
        ),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(
          ValueKey(AcpViewKeyValues.configControl('vendor/model')),
        ),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('acp-config-search-vendor/model'));
    expect(search, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Z 组')).dy,
      lessThan(tester.getTopLeft(find.text('A 组')).dy),
    );
    await tester.enterText(search, 'Z 组');
    await tester.pumpAndSettle();
    expect(find.text('A 组'), findsNothing);
    expect(find.byType(MenuItemButton), findsNWidgets(6));
    await tester.enterText(search, 'raw/value:10');
    await tester.pumpAndSettle();
    expect(find.text('Z 组'), findsNothing);
    expect(find.byType(MenuItemButton), findsOneWidget);
    await tester.tap(
      find.byKey(
        ValueKey(AcpViewKeyValues.configChoice('vendor/model', 'raw/value:10')),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected.single, ('vendor/model', 'raw/value:10'));
    expect(find.text('模型 · 选择 0'), findsOneWidget);
  });

  testWidgets('窄窗动态配置保留分组、Tooltip 和原始 id/value', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <(String, Object)>[];
    final select = AcpSessionConfigOptionView(
      id: const AcpConfigId('vendor/quality'),
      name: '质量',
      category: const AcpConfigCategoryView.known(
        AcpConfigCategoryKindView.thoughtLevel,
      ),
      description: '服务端优先级说明',
      kind: AcpSelectConfigView(
        currentValue: const AcpConfigValueId('raw:value/1'),
        options: AcpGroupedOptionsView([
          AcpSelectGroupView(
            group: const AcpConfigGroupId('group'),
            name: '服务分组',
            options: const [
              AcpSelectOptionView(
                value: AcpConfigValueId('raw:value/1'),
                name: '标准',
              ),
              AcpSelectOptionView(
                value: AcpConfigValueId('raw:value/2'),
                name: '深入',
                description: '更深入地回答',
              ),
            ],
          ),
        ]),
      ),
    );
    final controls = mapAcpConfigControls(
      options: [select, acpBooleanFixture],
      modes: null,
    );
    await tester.pumpWidget(
      acpTestApp(
        Padding(
          padding: const EdgeInsets.all(16),
          child: AcpConfigurationBar(
            state: AcpConfigurationViewState(controls: controls, enabled: true),
            onSelectValue: (id, value) => selected.add((id, value)),
            onBooleanChanged: (id, value) => selected.add((id, value)),
            onSelectLegacyMode: (_) =>
                fail('configOptions present must not setMode'),
          ),
        ),
      ),
    );

    final selectTrigger = find.descendant(
      of: find.byKey(
        ValueKey(AcpViewKeyValues.configControl('vendor/quality')),
      ),
      matching: find.byType(TextButton),
    );
    await tester.tap(selectTrigger);
    await tester.pumpAndSettle();
    expect(find.byTooltip('质量\n服务端优先级说明'), findsOneWidget);
    expect(find.text('服务分组'), findsWidgets);
    expect(find.text('更深入地回答'), findsNothing);
    expect(find.byTooltip('更深入地回答'), findsOneWidget);
    await tester.tap(
      find.byKey(
        ValueKey(
          AcpViewKeyValues.configChoice('vendor/quality', 'raw:value/2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected.single, ('vendor/quality', 'raw:value/2'));

    expect(find.byTooltip('保留引用\n保留服务器提供的来源'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(selected.last, (acpBooleanFixture.id.value, true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('空 configOptions 不回落 modes，缺失才显示正式 modes', (tester) async {
    final modes = AcpSessionModeStateView(
      currentModeId: const AcpModeId('mode-a'),
      availableModes: const [
        AcpSessionModeView(id: AcpModeId('mode-a'), name: '模式甲'),
        AcpSessionModeView(id: AcpModeId('mode-b'), name: '模式乙'),
      ],
    );
    String? selectedMode;
    Widget bar(List<AcpSessionConfigOptionView>? options) => acpTestApp(
      AcpConfigurationBar(
        state: AcpConfigurationViewState(
          controls: mapAcpConfigControls(options: options, modes: modes),
          enabled: true,
        ),
        onSelectValue: (_, _) => fail('legacy mode is not a config option'),
        onBooleanChanged: (_, _) => fail('legacy mode is not a boolean option'),
        onSelectLegacyMode: (mode) => selectedMode = mode,
      ),
    );
    await tester.pumpWidget(bar([]));
    expect(
      find.byKey(const ValueKey(AcpViewKeyValues.configLegacyMode)),
      findsNothing,
    );
    await tester.pumpWidget(bar(null));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey(AcpViewKeyValues.configLegacyMode)),
        matching: find.byType(TextButton),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey(
          AcpViewKeyValues.configChoice(
            AcpViewKeyValues.configLegacyMode,
            'mode-b',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(selectedMode, 'mode-b');
  });

  for (final legacy in [false, true]) {
    for (final rejected in [true, false]) {
      testWidgets(
        '${legacy ? 'modes' : 'configOptions'} 请求新值${rejected ? '被拒绝' : '成功但仍返回旧值'}时展示权威旧值',
        (tester) async {
          const oldValue = AcpConfigValueId('old');
          const newValue = AcpConfigValueId('new');
          const oldMode = AcpModeId('old-mode');
          const newMode = AcpModeId('new-mode');
          final option = AcpSessionConfigOptionView(
            id: const AcpConfigId('server-choice'),
            name: '服务端选择',
            category: const AcpConfigCategoryView.known(
              AcpConfigCategoryKindView.model,
            ),
            kind: AcpSelectConfigView(
              currentValue: oldValue,
              options: AcpUngroupedOptionsView(const [
                AcpSelectOptionView(value: oldValue, name: '权威旧值'),
                AcpSelectOptionView(value: newValue, name: '请求新值'),
              ]),
            ),
          );
          final modes = AcpSessionModeStateView(
            currentModeId: oldMode,
            availableModes: const [
              AcpSessionModeView(id: oldMode, name: '权威旧值'),
              AcpSessionModeView(id: newMode, name: '请求新值'),
            ],
          );
          final harness = await AcpComponentHarness.create(
            options: legacy ? null : [option],
            modes: legacy ? modes : null,
          );
          addTearDown(() => harness.close(tester));
          final command = Completer<void>();
          if (legacy) {
            harness.port.modeResult = command;
          } else {
            harness.port.configureResult = command;
          }
          await tester.pumpWidget(
            harness.scope(
              const DecoratedBox(
                decoration: BoxDecoration(color: Colors.white),
                child: AcpConfigurationConnector(threadId: 'thread'),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final Key anchorKey = legacy
              ? const ValueKey(AcpViewKeyValues.configLegacyMode)
              : ValueKey(AcpViewKeyValues.configControl('server-choice'));
          await tester.tap(
            find.descendant(
              of: find.byKey(anchorKey),
              matching: find.byType(TextButton),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('请求新值').last);
          await tester.pump();
          expect(harness.owner.state.configPending, isTrue);
          final request = harness.port.calls.last.$2;
          if (legacy) {
            expect((request as AcpSetModeRequestView).modeId, newMode);
          } else {
            final config = request as AcpConfigureRequestView;
            expect(config.configId, option.id);
            expect((config.value as AcpSelectConfigValueView).value, newValue);
          }
          if (rejected) {
            command.completeError(StateError('server rejected selection'));
          } else {
            // Success need not echo the requested value: retain the owner's
            // ordered formal response without optimistic state or rollback.
            harness.emit(
              legacy
                  ? const AcpModeSetEventView(oldMode)
                  : AcpConfiguredEventView(
                      AcpConfiguredResponseView(configOptions: [option]),
                    ),
            );
            command.complete();
          }
          await tester.pumpAndSettle();
          expect(harness.owner.state.configPending, isFalse);
          expect(
            harness.owner.state.configError,
            rejected ? isNotNull : isNull,
          );
          expect(find.textContaining('权威旧值'), findsOneWidget);
          expect(find.textContaining('请求新值'), findsNothing);
        },
      );
    }
  }
}
