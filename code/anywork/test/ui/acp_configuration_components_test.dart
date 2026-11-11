import 'dart:async';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_configuration_connector.dart';
import 'package:anywork/src/features/conversation/acp/view_models/acp_configuration_view_model.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

void main() {
  testWidgets('窄窗配置栏收纳更多设置，保留未知 category、分组说明和原始 id/value', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <(String, Object)>[];
    final select = AcpSessionConfigOptionView(
      id: const AcpConfigId('vendor/quality'),
      name: '质量',
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
    expect(find.text('服务端优先级说明'), findsOneWidget);
    expect(find.text('服务分组'), findsWidgets);
    expect(find.text('更深入地回答'), findsOneWidget);
    await tester.tap(
      find.byKey(
        ValueKey(
          AcpViewKeyValues.configChoice('vendor/quality', 'raw:value/2'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(selected.single, ('vendor/quality', 'raw:value/2'));

    // At 320px width, the second option moves cleanly into the overflow menu.
    final overflowTrigger = find.descendant(
      of: find.byKey(const ValueKey(AcpViewKeyValues.configOverflow)),
      matching: find.byType(TextButton),
    );
    await tester.tap(overflowTrigger);
    await tester.pumpAndSettle();
    expect(find.text('保留服务器提供的来源'), findsOneWidget);
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
