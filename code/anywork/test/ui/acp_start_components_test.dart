import 'package:anywork/src/features/conversation/acp/state/acp_view_state.dart';
import 'package:anywork/src/features/conversation/acp/views/acp_start_composer_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'acp_components_support.dart';

void main() {
  testWidgets('首条消息才可发送，提交期间仍可拟稿且主按钮尺寸不变', (tester) async {
    var state = const AcpStartComposerViewState(
      workspaceId: 'workspace',
      text: '',
      accountId: 'account',
      serviceName: 'Codex',
      serviceEnabled: true,
      ready: true,
    );
    var sends = 0;
    await tester.pumpWidget(
      acpTestApp(
        StatefulBuilder(
          builder: (context, setState) => AcpStartComposerView(
            state: state,
            onDraftChanged: (value) =>
                setState(() => state = state.copyWith(text: value)),
            onSubmit: () => setState(() {
              sends++;
              state = state.copyWith(submitting: true);
            }),
          ),
        ),
      ),
    );
    final send = find.byKey(
      ValueKey(AcpViewKeyValues.startSubmit('workspace')),
    );
    final size = tester.getSize(send);
    expect(
      tester.getRect(find.byType(AcpStartComposerView)).right -
          tester.getRect(send).right,
      lessThanOrEqualTo(20),
      reason: 'The primary action stays at the trailing edge of the input card',
    );
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '检查当前仓库');
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(sends, 1);
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    expect(tester.getSize(send), size);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    await tester.enterText(find.byType(TextField), '接下来检查错误处理');
    await tester.pump();
    expect(state.text, '接下来检查错误处理');
    expect(sends, 1);
    expect(find.textContaining('协议'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('组词回车不发、Shift+Enter换行，服务状态更新保留选区', (tester) async {
    var state = const AcpStartComposerViewState(
      workspaceId: 'workspace',
      text: '检查仓库',
      accountId: 'account',
      serviceName: 'Codex',
      serviceEnabled: true,
      ready: true,
    );
    late StateSetter rebuild;
    var sends = 0;
    await tester.pumpWidget(
      acpTestApp(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return AcpStartComposerView(
              state: state,
              onDraftChanged: (value) =>
                  setState(() => state = state.copyWith(text: value)),
              onSubmit: () => sends++,
            );
          },
        ),
      ),
    );
    final input = find.byType(TextField);
    await tester.tap(input);
    final controller = tester.widget<TextField>(input).controller!;
    controller.value = const TextEditingValue(
      text: '检查仓库',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(sends, 0);
    controller.value = controller.value.copyWith(composing: TextRange.empty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(controller.text, contains('\n'));
    expect(sends, 0);
    controller.selection = const TextSelection.collapsed(offset: 1);
    rebuild(() => state = state.copyWith(serviceEnabled: false));
    await tester.pump();
    expect(controller.selection.baseOffset, 1);
    final send = find.byKey(
      ValueKey(AcpViewKeyValues.startSubmit('workspace')),
    );
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    rebuild(() => state = state.copyWith(serviceEnabled: true));
    await tester.pump();
    await tester.tap(send);
    expect(sends, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
