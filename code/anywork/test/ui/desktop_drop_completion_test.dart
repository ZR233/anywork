import 'dart:async';

import 'package:anywork/src/platform/desktop_drop_adapter.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('拖放适配器保留异步完成责任，不提前结束文件借用', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DesktopFileDropTarget(
          enabled: true,
          onEnter: () {},
          onLeave: () {},
          onDrop: (_) => gate.future,
          child: const SizedBox(width: 100, height: 100),
        ),
      ),
    );
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    final completion = target.onDrop(
      DropDetails(
        items: const [],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
        operation: DropOperation.copy,
      ),
    );
    expect(completion, isA<Future<void>>());
    var completed = false;
    final observed = Future<void>.value(completion)
        .then((_) => completed = true);
    await tester.pump();
    expect(completed, isFalse);
    gate.complete();
    await observed;
    expect(completed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
