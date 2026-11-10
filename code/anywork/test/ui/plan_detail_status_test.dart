import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('运行态枚举精确映射，不把非 pending 一律当成已批准', () {
    expect(
      planDetailStatusFromRuntime(PlanRuntimePhase.drafting),
      PlanDetailStatus.drafting,
    );
    expect(
      planDetailStatusFromRuntime(PlanRuntimePhase.awaitingConfirmation),
      PlanDetailStatus.awaitingConfirmation,
    );
    expect(
      planDetailStatusFromRuntime(PlanRuntimePhase.revisionRequested),
      PlanDetailStatus.revisionRequested,
    );
    expect(
      planDetailStatusFromRuntime(PlanRuntimePhase.approved),
      PlanDetailStatus.approved,
    );
  });

  Future<void> pumpStatus(
    WidgetTester tester,
    PlanDetailStatus status, {
    Locale locale = const Locale('zh'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        locale: locale,
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlanDetailView(
            identity: 'plan',
            title: 'Delivery',
            status: status,
            onClose: () {},
            body: const Text('plan body'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('等待确认与已批准文案互斥', (tester) async {
    await pumpStatus(tester, PlanDetailStatus.awaitingConfirmation);
    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus)).data,
      '等待确认',
    );
    expect(find.text('已批准'), findsNothing);

    await pumpStatus(tester, PlanDetailStatus.approved);
    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus)).data,
      '已批准',
    );
    expect(find.text('等待确认'), findsNothing);
  });

  testWidgets('起草中与已请求修改不显示已批准', (tester) async {
    await pumpStatus(tester, PlanDetailStatus.drafting);
    expect(find.text('已批准'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus)).data,
      '起草中',
    );

    await pumpStatus(tester, PlanDetailStatus.revisionRequested);
    expect(find.text('已批准'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus)).data,
      '已请求修改',
    );
  });

  testWidgets('没有计划正文时仅显示头部的真实状态', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlanDetailView(
            identity: 'plan',
            title: 'Delivery',
            body: null,
            status: PlanDetailStatus.drafting,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('起草中'), findsOneWidget);
    expect(find.text('计划准备好后会请你确认。'), findsNothing);
    expect(find.text('准备好后，你可以在这里阅读完整计划。'), findsNothing);
  });
}
