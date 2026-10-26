import 'package:anywork/src/domain/models/composer_primary_action.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 逐一渲染 typed 原因的文案；每种原因各占一个独立的 Text。
class _LabelProbe extends StatelessWidget {
  const _LabelProbe();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final reason in StudioFailureReason.values)
          Text(
            context.composerFailureReasonLabel(reason),
            key: ValueKey('failure-${reason.name}'),
          ),
        Text(
          context.composerFailureReasonLabel(null),
          key: const ValueKey('failure-none'),
        ),
        for (final reason in ContinuationReason.values)
          Text(
            context.composerContinuationReasonLabel(reason),
            key: ValueKey('continuation-${reason.name}'),
          ),
        Text(
          context.composerContinuationReasonLabel(null),
          key: const ValueKey('continuation-none'),
        ),
        for (final blocker in const <ComposerBlocker>[
          ComposerStorageBlocker(),
          ComposerModelBlocker(),
          ComposerWorkspaceBlocker(),
        ])
          Text(
            context.composerBlockerLabel(blocker),
            key: ValueKey('blocker-${blocker.runtimeType}'),
          ),
        // 侧栏的归档标签是导航文案，不能替代继续/提交被拒绝的原因说明。
        Text(
          context.l10n.sidebarArchived,
          key: const ValueKey('sidebar-archived-label'),
        ),
      ],
    );
  }
}

Future<void> _pump(WidgetTester tester, Locale locale) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: SizedBox(
          width: 1200,
          height: 2000,
          child: SingleChildScrollView(child: _LabelProbe()),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _text(WidgetTester tester, Key key) =>
    tester.widget<Text>(find.byKey(key)).data!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('每个 typed 失败原因都有独立文案，未知原因不伪装成已知', (tester) async {
    await _pump(tester, const Locale('en'));
    final labels = {
      for (final reason in StudioFailureReason.values)
        reason: _text(tester, ValueKey('failure-${reason.name}')),
    };
    expect(
      labels.values.every((label) => label.trim().isNotEmpty),
      isTrue,
      reason: '所有原因都必须有可显示文案',
    );
    expect(
      labels.values.toSet().length,
      StudioFailureReason.values.length,
      reason: '不同原因不能共用同一文案',
    );
    expect(
      labels[StudioFailureReason.childThreadRequiresParentScheduling],
      'A child agent is scheduled by the main agent.',
    );
    expect(
      labels[StudioFailureReason.staleExecution],
      'The observed execution already ended or was replaced.',
    );
    expect(
      _text(tester, const ValueKey('failure-none')),
      'The last action could not be confirmed. Check the session state before retrying.',
    );
    expect(
      _text(tester, const ValueKey('continuation-none')),
      'Execution was interrupted',
      reason: '没有已知原因时使用中性说明，不回填用户停止',
    );
    expect(
      _text(tester, const ValueKey('continuation-userStop')),
      'Stopped by the user',
    );
    expect(
      _text(tester, ValueKey('blocker-$ComposerStorageBlocker')),
      'Saving has not finished yet, so continuing is unavailable.',
    );
    expect(
      _text(tester, ValueKey('blocker-$ComposerModelBlocker')),
      'The current model is unavailable, so continuing is unavailable.',
    );
    expect(
      _text(tester, ValueKey('blocker-$ComposerWorkspaceBlocker')),
      'The session workspace is unavailable, so continuing is unavailable.',
    );
    expect(
      labels[StudioFailureReason.threadArchived],
      'This session is archived, so continuing is unavailable.',
      reason: '归档会话使用专用的阻塞说明',
    );
    expect(
      labels[StudioFailureReason.threadArchived],
      isNot(_text(tester, const ValueKey('sidebar-archived-label'))),
      reason: '不能复用侧栏的「Archived」标签',
    );
    expect(_text(tester, const ValueKey('sidebar-archived-label')), 'Archived');
  });

  testWidgets('同一组 typed 原因在中文界面使用中文文案', (tester) async {
    await _pump(tester, const Locale('zh'));
    expect(
      _text(
        tester,
        const ValueKey('failure-childThreadRequiresParentScheduling'),
      ),
      '子智能体只能由主智能体调度。',
    );
    expect(
      _text(tester, const ValueKey('failure-staleExecution')),
      '观察到的执行已结束或被新的执行替代。',
    );
    expect(
      _text(tester, const ValueKey('failure-none')),
      '上一次操作未能确认，请先核对会话状态再重试。',
    );
    expect(
      _text(tester, const ValueKey('continuation-none')),
      '执行已中断',
      reason: '中性说明不得回填「已被用户停止」',
    );
    expect(_text(tester, const ValueKey('continuation-userStop')), '已被用户停止');
    expect(
      _text(tester, ValueKey('blocker-$ComposerStorageBlocker')),
      '保存尚未完成，暂时不能继续。',
    );
    expect(
      _text(tester, const ValueKey('failure-threadArchived')),
      '该会话已归档，不能继续。',
      reason: '归档会话使用专用的阻塞说明',
    );
    expect(
      _text(tester, const ValueKey('failure-threadArchived')),
      isNot(_text(tester, const ValueKey('sidebar-archived-label'))),
      reason: '不能复用侧栏的「已归档」标签',
    );
    expect(_text(tester, const ValueKey('sidebar-archived-label')), '已归档');
  });
}
