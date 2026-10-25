import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/diagnostics/studio_driver_keys.dart';
import 'package:anywork/src/features/conversation/state/editor_keys.dart';
import 'package:anywork/src/features/conversation/state/interaction_view_state.dart';
import 'package:anywork/src/features/conversation/views/interaction_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Linux plan actions align with the input even when wrapping', (
    tester,
  ) async {
    _useDesktopView(tester);

    for (final layout in const [
      (width: 1100.0, scale: 1.0),
      (width: 360.0, scale: 2.0),
    ]) {
      await _pumpPlan(tester, width: layout.width, scale: layout.scale);
      expect(tester.takeException(), isNull);

      final input = tester.getRect(
        find.byKey(StudioDriverKeys.planFeedbackInput),
      );
      final revise = tester.getRect(
        find.byKey(StudioDriverKeys.planSubmitRevision),
      );
      final approve = tester.getRect(find.byKey(StudioDriverKeys.planApprove));
      expect(
        approve.right,
        closeTo(input.right, 1),
        reason: '${layout.width}px / ${layout.scale}x actions follow input right',
      );
      if (layout.width == 1100) {
        expect(revise.height, closeTo(approve.height, 1));
        expect(revise.center.dy, closeTo(approve.center.dy, 1));
        expect(approve.left - revise.right, closeTo(8, 1));
      } else {
        expect(revise.right, closeTo(input.right, 1));
        expect(approve.top - revise.bottom, greaterThanOrEqualTo(8));
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('Linux compact theme keeps 48px plan action hit targets', (
    tester,
  ) async {
    _useDesktopView(tester);
    var revisionCalls = 0;
    var approveCalls = 0;
    await _pumpPlan(
      tester,
      planFeedback: 'adjust the plan',
      onRequestRevision: () => revisionCalls++,
      onApprove: () => approveCalls++,
    );

    expect(
      Theme.of(tester.element(find.byType(InteractionView))).visualDensity,
      VisualDensity.compact,
      reason: 'The production theme remains compact outside the action styles',
    );
    for (final key in [
      StudioDriverKeys.planSubmitRevision,
      StudioDriverKeys.planApprove,
    ]) {
      final rect = tester.getRect(find.byKey(key));
      expect(
        rect.height,
        closeTo(kMinInteractiveDimension, 1),
        reason: '$key must retain a standard hit target under compact density',
      );
      // Verify that the transparent padding is tappable, not just a larger box.
      await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
      await tester.pump();
      await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
      await tester.pump();
    }
    expect(revisionCalls, 2);
    expect(approveCalls, 2);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}

void _useDesktopView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpPlan(
  WidgetTester tester, {
  double width = 1100,
  double scale = 1,
  String planFeedback = '',
  VoidCallback? onRequestRevision,
  VoidCallback? onApprove,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: pureStudioTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: InteractionView(
              // HEAD 只在反馈非空时允许「提交修改」；布局/命中区用例必须给出
              // 真实可提交状态，否则点到的是禁用按钮，测不到命中区。
              state: _planState.copyWith(planFeedback: planFeedback),
              onShowQuestion: (_) async {},
              onLoadQuestions: () async {},
              onLoadOptions: (_) async {},
              onLoadAnswerEntries: () async {},
              onLoadAnswerValues: (_) async {},
              onLoadText: (_) async {},
              onCompleteRead: () async {},
              onRetryRead: () async {},
              onQuestionText: (_, _) {},
              onOption: (_, _, _) {},
              onFallback: (_) {},
              onReason: (_) {},
              onPlanFeedback: (_) {},
              onRequestPlanRevision: () async => onRequestRevision?.call(),
              onApprovePlan: () async => onApprove?.call(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _planState = InteractionViewState(
  key: InteractionEditorKey(
    threadId: 'layout-thread',
    incarnation: 1,
    interactionId: 'layout-plan',
    revision: 1,
  ),
  sourceCurrent: true,
  header: InteractionReadHeader(
    scope: ReadScopeIdentity(
      scopeId: 'layout-scope',
      runtimeEpoch: 'layout-epoch',
      incarnation: 1,
      sourceRevision: 1,
    ),
    interactionId: InlineReadText(text: 'layout-plan'),
    threadId: InlineReadText(text: 'layout-thread'),
    turnId: InlineReadText(text: 'layout-turn'),
    itemId: null,
    toolId: null,
    agentPath: null,
    revision: 1,
    purpose: PlanConfirmationPurposeRead(
      expectedRevision: 1,
      operationId: InlineReadText(text: 'layout-operation'),
      argumentHash: InlineReadText(text: 'layout-arguments'),
      planHash: InlineReadText(text: 'layout-hash'),
    ),
    continuation: null,
    createdAt: 1,
    updatedAt: 1,
    content: UserInputContentRead(questionCount: 0),
    state: PendingInteractionRead(
      operationId: InlineReadText(text: 'layout-operation'),
    ),
  ),
);
