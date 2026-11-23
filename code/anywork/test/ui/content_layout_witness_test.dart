import 'package:anywork/src/features/conversation/timeline/widgets/content_layout_witness.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('growing visible text keeps its first layout until replaced', (
    tester,
  ) async {
    final events = <String>[];
    var layoutSamples = 0;

    Widget view(String text, {int offset = 0, int update = 0}) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 260,
              height: 90,
              child: SingleChildScrollView(
                reverse: true,
                child: ContentLayoutWitness(
                  key: ValueKey(offset),
                  itemId: 'reply',
                  monotonicMicros: () => ++layoutSamples,
                  onContentLayout: (id, _) => events.add('visible:$id:$offset'),
                  onContentUnmounted: (id) =>
                      events.add('retired:$id:$offset:$update'),
                  isDisplayActive: () => true,
                  child: Text(text),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(view('first line'));
    expect(events, ['visible:reply:0']);

    var text = 'first line';
    for (var update = 1; update <= 10; update++) {
      text += '\n${'streaming words ' * 12}';
      await tester.pumpWidget(view(text, update: update));
    }
    expect(find.text(text), findsOneWidget);
    expect(layoutSamples, 1);
    expect(events, ['visible:reply:0']);

    await tester.pumpWidget(view('next window', offset: 100));
    expect(events, [
      'visible:reply:0',
      'retired:reply:0:10',
      'visible:reply:100',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(events.last, 'retired:reply:100:0');
  });
}
