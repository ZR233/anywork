import 'dart:async';

import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:anywork/src/shared/studio_menu_label.dart';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_configuration_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_configuration_view_model.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

void main() {
  const common = [
    AcpConfigControlPresentation.select(
      id: 'mode',
      name: '模式',
      category: AcpConfigCategoryKind.mode,
      currentValue: 'agent',
      currentLabel: '执行',
      flatOptions: [AcpSelectChoicePresentation(value: 'agent', name: '执行')],
    ),
    AcpConfigControlPresentation.select(
      id: 'model',
      name: '模型',
      category: AcpConfigCategoryKind.model,
      currentValue: 'pro',
      currentLabel: '专业模型',
      flatOptions: [AcpSelectChoicePresentation(value: 'pro', name: '专业模型')],
    ),
    AcpConfigControlPresentation.select(
      id: 'thought',
      name: '思考',
      category: AcpConfigCategoryKind.thoughtLevel,
      currentValue: 'high',
      currentLabel: 'high',
      flatOptions: [AcpSelectChoicePresentation(value: 'high', name: 'high')],
    ),
  ];
  Finder control(String id) =>
      find.byKey(ValueKey(AcpViewKeyValues.configControl(id)));
  Future<void> more(WidgetTester tester) async {
    await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
    await tester.pumpAndSettle();
  }

  testWidgets('仅明确常用类别内联，未知与布尔在更多中保留服务端顺序', (tester) async {
    await tester.pumpWidget(
      acpTestApp(
        AcpConfigurationBar(
          state: AcpConfigurationViewState(
            enabled: true,
            controls: [
              const AcpConfigControlPresentation.select(
                id: 'vendor/mode',
                name: '输出格式',
                category: AcpConfigCategoryKind.unspecified,
                currentValue: 'json',
                currentLabel: 'JSON',
                flatOptions: [
                  AcpSelectChoicePresentation(value: 'json', name: 'JSON'),
                ],
              ),
              common[1],
              const AcpConfigControlPresentation.boolean(
                id: 'b',
                name: '保留引用',
                category: AcpConfigCategoryKind.model,
                currentValue: true,
              ),
              const AcpConfigControlPresentation.select(
                id: 'a',
                name: '审阅方式',
                category: AcpConfigCategoryKind.modelConfig,
                currentValue: 'careful',
                currentLabel: '仔细',
                flatOptions: [
                  AcpSelectChoicePresentation(value: 'careful', name: '仔细'),
                ],
              ),
              const AcpConfigControlPresentation.select(
                id: 'second-model',
                name: '额外模型',
                category: AcpConfigCategoryKind.model,
                currentValue: 'extra',
                currentLabel: '额外值',
                flatOptions: [
                  AcpSelectChoicePresentation(value: 'extra', name: '额外值'),
                ],
              ),
            ],
          ),
          onSelectValue: (_, _) {},
          onBooleanChanged: (_, _) {},
          onSelectLegacyMode: (_) {},
        ),
      ),
    );
    expect(find.text('专业模型'), findsOneWidget);
    expect(find.text('模型'), findsNothing);
    expect(control('vendor/mode'), findsNothing);
    expect(control('second-model'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    await more(tester);
    expect(
      tester.getTopLeft(control('vendor/mode')).dy,
      lessThan(tester.getTopLeft(control('b')).dy),
    );
    expect(
      tester.getTopLeft(control('b')).dy,
      lessThan(tester.getTopLeft(control('a')).dy),
    );
    expect(
      tester.getTopLeft(control('a')).dy,
      lessThan(tester.getTopLeft(control('second-model')).dy),
    );
    expect(
      tester
          .widget<CheckboxMenuButton>(
            find.descendant(
              of: control('b'),
              matching: find.byType(CheckboxMenuButton),
            ),
          )
          .value,
      isTrue,
    );
    await tester.tap(control('vendor/mode'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        ValueKey(AcpViewKeyValues.configChoice('vendor/mode', 'json')),
      ),
      findsOneWidget,
    );
  });

  for (final (width, scale) in [(700.0, 1.0), (330.0, 1.0), (260.0, 2.0)]) {
    testWidgets('单排宽度 $width 字号 $scale 按真实宽度收纳且不丢选项', (tester) async {
      await tester.pumpWidget(
        acpTestApp(
          MediaQuery(
            data: MediaQueryData(
              size: const Size(800, 600),
              textScaler: TextScaler.linear(scale),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: AcpConfigurationBar(
                  state: const AcpConfigurationViewState(
                    enabled: true,
                    controls: common,
                  ),
                  onSelectValue: (_, _) {},
                  onBooleanChanged: (_, _) {},
                  onSelectLegacyMode: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final visible = <AcpConfigControlPresentation>[];
      final hidden = <AcpConfigControlPresentation>[];
      for (final item in common) {
        if (control(item.id).hitTestable().evaluate().isNotEmpty) {
          visible.add(item);
        } else {
          hidden.add(item);
        }
      }
      expect(
        find
            .byKey(ComposerConfigurationBar.moreKey)
            .hitTestable()
            .evaluate()
            .isNotEmpty,
        hidden.isNotEmpty,
      );
      if (width == 700) {
        expect(visible, hasLength(common.length));
      }
      for (var index = 1; index < visible.length; index++) {
        expect(
          tester.getCenter(control(visible[index].id)).dy,
          closeTo(tester.getCenter(control(visible.first.id)).dy, 1),
        );
        expect(
          tester.getRect(control(visible[index - 1].id)).right,
          lessThanOrEqualTo(tester.getRect(control(visible[index].id)).left),
        );
      }
      if (hidden.isNotEmpty) {
        expect(
          tester.getSize(
            find.byKey(ComposerConfigurationBar.moreKey).hitTestable(),
          ),
          const Size.square(32),
        );
        if (visible.isNotEmpty) {
          expect(
            tester.getCenter(find.byKey(ComposerConfigurationBar.moreKey)).dy,
            closeTo(tester.getCenter(control(visible.first.id)).dy, 1),
          );
        }
        await more(tester);
        for (final item in hidden) {
          expect(
            tester
                .widget<SubmenuButton>(
                  find.descendant(
                    of: control(item.id),
                    matching: find.byType(SubmenuButton),
                  ),
                )
                .menuChildren,
            isNotEmpty,
          );
        }
      } else {
        expect(find.byKey(ComposerConfigurationBar.moreKey), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('分组逐级打开保持顺序、当前值和原始 ID，布尔走官方菜单', (tester) async {
    final selected = <(String, Object)>[];
    await tester.pumpWidget(
      acpTestApp(
        AcpConfigurationBar(
          state: const AcpConfigurationViewState(
            enabled: true,
            controls: [
              AcpConfigControlPresentation.select(
                id: 'vendor/model',
                name: '模型',
                category: AcpConfigCategoryKind.model,
                description: '服务端说明',
                currentValue: 'raw/1',
                currentLabel: '模型一',
                groups: [
                  AcpSelectGroupPresentation(
                    id: 'z',
                    name: 'Z 系列',
                    options: [
                      AcpSelectChoicePresentation(value: 'raw/1', name: '模型一'),
                    ],
                  ),
                  AcpSelectGroupPresentation(
                    id: 'a',
                    name: 'A 系列',
                    options: [
                      AcpSelectChoicePresentation(
                        value: 'raw:2',
                        name: '模型二',
                        description: '选项说明',
                      ),
                    ],
                  ),
                ],
              ),
              AcpConfigControlPresentation.boolean(
                id: 'bool/id',
                name: '保留引用',
                category: AcpConfigCategoryKind.other,
                currentValue: false,
              ),
            ],
          ),
          onSelectValue: (id, value) => selected.add((id, value)),
          onBooleanChanged: (id, value) => selected.add((id, value)),
          onSelectLegacyMode: (_) {},
        ),
      ),
    );
    expect(find.byTooltip('模型\n服务端说明'), findsOneWidget);
    await tester.tap(control('vendor/model'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Z 系列')).dy,
      lessThan(tester.getTopLeft(find.text('A 系列')).dy),
    );
    expect(find.text('模型二'), findsNothing);
    await tester.tap(find.text('Z 系列'));
    await tester.pumpAndSettle();
    final current = find.byKey(
      ValueKey(AcpViewKeyValues.configChoice('vendor/model', 'raw/1')),
    );
    expect(
      find.descendant(of: current, matching: find.byIcon(Icons.check_rounded)),
      findsOneWidget,
    );
    await tester.tap(find.text('A 系列'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('选项说明'), findsOneWidget);
    await tester.tap(
      find.byKey(
        ValueKey(AcpViewKeyValues.configChoice('vendor/model', 'raw:2')),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected.single, ('vendor/model', 'raw:2'));
    expect(find.text('模型一'), findsOneWidget);
    await more(tester);
    await tester.tap(control('bool/id'));
    await tester.pumpAndSettle();
    expect(selected.last, ('bool/id', true));
  });

  for (final pending in [false, true]) {
    testWidgets('${pending ? '在途' : '禁用'}配置保持当前值、更多可访问及失败原因', (tester) async {
      await tester.pumpWidget(
        acpTestApp(
          AcpConfigurationBar(
            state: AcpConfigurationViewState(
              enabled: pending,
              pending: pending,
              errorMessage: 'server rejected',
              controls: [
                common.first,
                const AcpConfigControlPresentation.boolean(
                  id: 'b',
                  name: '引用',
                  category: AcpConfigCategoryKind.other,
                  currentValue: true,
                ),
                const AcpConfigControlPresentation.select(
                  id: 'extra',
                  name: '策略',
                  category: AcpConfigCategoryKind.other,
                  currentValue: 'safe',
                  currentLabel: '安全',
                  flatOptions: [
                    AcpSelectChoicePresentation(value: 'safe', name: '安全'),
                  ],
                ),
              ],
            ),
            onSelectValue: (_, _) => fail('locked'),
            onBooleanChanged: (_, _) => fail('locked'),
            onSelectLegacyMode: (_) => fail('locked'),
          ),
        ),
      );
      expect(find.textContaining('server rejected'), findsOneWidget);
      expect(find.text('执行'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.descendant(
                of: control('mode'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
      await more(tester);
      expect(
        tester
            .widget<CheckboxMenuButton>(
              find.descendant(
                of: control('b'),
                matching: find.byType(CheckboxMenuButton),
              ),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SubmenuButton>(
              find.descendant(
                of: control('extra'),
                matching: find.byType(SubmenuButton),
              ),
            )
            .menuChildren,
        isEmpty,
      );
    });
  }

  testWidgets('空动态配置仍保留新会话服务入口', (tester) async {
    final serviceLabel = StudioMenuLabel(label: '服务选择');
    await tester.pumpWidget(
      acpTestApp(
        AcpConfigurationBar(
          leadingEntries: [
            ComposerConfigurationEntry(
              id: 'service',
              inline: serviceLabel,
              measureInlineWidth: (context) =>
                  serviceLabel.measureWidth(context),
              menuItem: MenuItemButton(
                onPressed: () {},
                child: const Text('服务选择'),
              ),
            ),
          ],
          state: const AcpConfigurationViewState(),
          onSelectValue: (_, _) {},
          onBooleanChanged: (_, _) {},
          onSelectLegacyMode: (_) {},
        ),
      ),
    );
    expect(find.text('服务选择'), findsOneWidget);
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
