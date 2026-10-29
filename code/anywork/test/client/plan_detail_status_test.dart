import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
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
}
