import 'dart:async';

import 'package:anywork/src/features/conversation/acp/connectors/acp_configuration_connector.dart';
import 'package:anywork/src/features/conversation/acp/widgets/acp_configuration_panel.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

void main() {
  testWidgets('配置保留未知 category、分组说明和原始 id/value', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final selected = <(AcpConfigId, AcpSessionConfigValueView)>[];
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
    await tester.pumpWidget(
      acpTestApp(
        Padding(
          padding: const EdgeInsets.all(16),
          child: AcpConfigurationPanel(
            options: [select, acpBooleanFixture],
            modes: null,
            pending: false,
            onConfigure: (id, value) => selected.add((id, value)),
            onMode: (_) => fail('configOptions present must not setMode'),
          ),
        ),
      ),
    );
    expect(find.text('服务端优先级说明'), findsOneWidget);
    expect(find.text('保留服务器提供的来源'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<AcpConfigValueId>));
    await tester.pumpAndSettle();
    expect(find.text('服务分组'), findsWidgets);
    await tester.tap(find.text('深入').last);
    await tester.pumpAndSettle();
    expect(selected.single.$1, select.id);
    expect(
      (selected.single.$2 as AcpSelectConfigValueView).value,
      const AcpConfigValueId('raw:value/2'),
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(selected.last.$1, acpBooleanFixture.id);
    expect((selected.last.$2 as AcpBooleanConfigValueView).value, isTrue);
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
    AcpModeId? selected;
    Widget panel(List<AcpSessionConfigOptionView>? options) => acpTestApp(
      AcpConfigurationPanel(
        options: options,
        modes: modes,
        pending: false,
        onConfigure: (_, _) => fail('legacy mode is not a config option'),
        onMode: (mode) => selected = mode,
      ),
    );
    await tester.pumpWidget(panel([]));
    expect(find.byType(DropdownButton<AcpModeId>), findsNothing);
    await tester.pumpWidget(panel(null));
    await tester.tap(find.byType(DropdownButton<AcpModeId>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('模式乙').last);
    await tester.pumpAndSettle();
    expect(selected, const AcpModeId('mode-b'));
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
          final dropdown = legacy
              ? find.byType(DropdownButton<AcpModeId>)
              : find.byType(DropdownButton<AcpConfigValueId>);
          await tester.tap(dropdown);
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
          expect(find.text('权威旧值'), findsOneWidget);
          expect(find.text('请求新值'), findsNothing);
        },
      );
    }
  }
}
