import 'dart:convert';

import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/acp/connectors/acp_workspace_connector.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import '../test/ui/acp_components_support.dart';
import 'support/presentation_capture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生窗口尺寸传递至 ACP 工作区并保持控件可交互', (tester) async {
    final harness = await AcpComponentHarness.create(
      options: [acpBooleanFixture],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.close(tester);
      expect(harness.source.closes, 1);
      expect(tester.takeException(), isNull);
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: presentationCaptureKey,
        child: harness.scope(const AcpWorkspaceConnector(threadId: 'thread')),
      ),
    );
    await tester.pumpAndSettle();
    final geometry = await configurePresentationWindow(
      tester,
      logicalWidth: 1280,
      logicalHeight: 900,
      requireNativeResize: true,
    );
    debugPrint('ACP native viewport: ${jsonEncode(geometry)}');
    final configOverflow = find.descendant(
      of: find.byKey(const ValueKey(AcpViewKeyValues.configOverflow)),
      matching: find.byType(TextButton),
    );
    expect(configOverflow.hitTestable(), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.tap(configOverflow);
    await tester.pumpAndSettle();
    final booleanConfig = find.byKey(
      ValueKey(AcpViewKeyValues.configControl(acpBooleanFixture.id.value)),
    );
    expect(booleanConfig.hitTestable(), findsOneWidget);
    await tester.tap(booleanConfig);
    await tester.pumpAndSettle();
    final configure =
        harness.port.calls.where((call) => call.$1 == 'configure').single.$2
            as AcpConfigureRequestView;
    expect(configure.configId, acpBooleanFixture.id);
    expect((configure.value as AcpBooleanConfigValueView).value, isTrue);
    expect(tester.takeException(), isNull);
    await capturePresentation(tester, 'acp-native-workspace.png');
  });
}
