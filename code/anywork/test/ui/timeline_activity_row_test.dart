import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: pureStudioTheme(),
  home: Scaffold(
    body: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 180, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets('窄屏大字号的长活动文案和耗时不产生第二行', (tester) async {
    const label = '已执行一个名称很长但仍应保持单行的命令';
    await tester.pumpWidget(
      _host(
        const TimelineActivityRow(
          icon: Icons.terminal,
          label: label,
          meta: '用时 2 分 30 秒',
        ),
      ),
    );

    final text = tester.widget<Text>(find.text(label));
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    final textRect = tester.getRect(find.text(label));
    final rowRect = tester.getRect(find.byType(TimelineActivityRow));
    expect(rowRect.height, lessThanOrEqualTo(textRect.height + 8));
    expect(find.text('用时 2 分 30 秒'), findsNothing);
    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      contains('用时 2 分 30 秒'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('不可展开的失败行保留图标与唯一主文案而不显示展开入口', (tester) async {
    await tester.pumpWidget(
      _host(
        const TimelineActivityRow(
          icon: Icons.terminal,
          label: '执行失败：权限不足',
          isIssue: true,
          expandable: false,
        ),
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('执行失败：权限不足'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
