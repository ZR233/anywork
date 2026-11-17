import 'package:anywork/src/shared/composer_configuration_bar.dart';
import 'package:anywork/src/shared/studio_menu_label.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('实际测宽矩阵逐项收纳、保持次序与回调并维持单排', (tester) async {
    const cases = [
      (width: 60.0, visible: <String>[]),
      (width: 111.0, visible: ['first']),
      (width: 145.0, visible: ['first', 'third']),
      (width: 146.0, visible: ['first', 'second']),
      (width: 164.0, visible: ['first', 'second', 'third']),
    ];
    const widths = {'first': 40.0, 'second': 70.0, 'third': 50.0};
    const ids = ['first', 'second', 'third'];

    for (final testCase in cases) {
      final callbacks = <String>[];
      await tester.pumpWidget(
        _testApp(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: testCase.width,
              child: ComposerConfigurationBar(
                moreTooltip: '更多配置',
                entries: [
                  for (final id in ids)
                    ComposerConfigurationEntry(
                      id: id,
                      inline: SizedBox(
                        key: ValueKey('inline-$id'),
                        width: widths[id]!,
                        height: 32,
                        child: InkWell(
                          onTap: () => callbacks.add(id),
                          child: Center(child: Text(id)),
                        ),
                      ),
                      measureInlineWidth: (_) => widths[id]!,
                      menuItem: MenuItemButton(
                        key: ValueKey('menu-$id'),
                        onPressed: () => callbacks.add(id),
                        child: Text('配置 $id · 当前值'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final visible = [
        for (final id in ids)
          if (find
              .byKey(ValueKey('inline-$id'))
              .hitTestable()
              .evaluate()
              .isNotEmpty)
            id,
      ];
      expect(
        visible,
        testCase.visible,
        reason: '可放下的项目按原序逐项填入 ${testCase.width}px',
      );
      final hidden = ids.where((id) => !visible.contains(id)).toList();
      final more = find.byKey(ComposerConfigurationBar.moreKey);
      expect(more.hitTestable().evaluate().isNotEmpty, hidden.isNotEmpty);

      final row = <Rect>[
        for (final id in visible)
          tester.getRect(find.byKey(ValueKey('inline-$id'))),
        if (hidden.isNotEmpty) tester.getRect(more),
      ];
      for (final rect in row.skip(1)) {
        expect(rect.center.dy, closeTo(row.first.center.dy, 1));
      }
      for (var index = 1; index < row.length; index++) {
        expect(row[index - 1].right, lessThanOrEqualTo(row[index].left));
      }
      for (final id in visible) {
        await tester.tap(find.byKey(ValueKey('inline-$id')));
        await tester.pump();
        expect(callbacks, contains(id));
      }

      if (hidden.isNotEmpty) {
        await tester.tap(more);
        await tester.pumpAndSettle();
        final menuRects = <Rect>[];
        for (final id in hidden) {
          final item = find.byKey(ValueKey('menu-$id'));
          expect(item.hitTestable(), findsOneWidget);
          expect(find.text('配置 $id · 当前值'), findsOneWidget);
          menuRects.add(tester.getRect(item));
        }
        for (var index = 1; index < menuRects.length; index++) {
          expect(menuRects[index - 1].top, lessThan(menuRects[index].top));
        }
        for (final id in hidden) {
          if (find
              .byKey(ValueKey('menu-$id'))
              .hitTestable()
              .evaluate()
              .isEmpty) {
            await tester.tap(more);
            await tester.pumpAndSettle();
          }
          final menuItem = find.byKey(ValueKey('menu-$id'));
          expect(
            tester.widget<MenuItemButton>(menuItem).onPressed,
            isNotNull,
            reason: '隐藏项目 $id 必须保留自己的选择回调',
          );
          await tester.tap(menuItem);
          await tester.pump();
          expect(callbacks, contains(id));
        }
      }
      expect(tester.takeException(), isNull, reason: '配置行不得产生布局溢出');
    }
  });

  testWidgets('StudioMenuLabel测宽与真实绘制宽度共享字体、缩放、leading及间距', (tester) async {
    const cases = [
      (label: '短项', scale: 1.0, leading: false),
      (label: '较长的配置名称与当前模型值', scale: 1.0, leading: false),
      (label: '短项', scale: 2.0, leading: true),
      (label: '超长配置名称与大字模型当前值', scale: 2.0, leading: true),
    ];

    for (final testCase in cases) {
      final key = ValueKey('measure-${testCase.label}-${testCase.scale}');
      await tester.pumpWidget(
        _testApp(
          Builder(
            builder: (context) => Center(
              child: StudioMenuLabel(
                key: key,
                label: testCase.label,
                maxWidth: 132,
                leading: testCase.leading
                    ? const Icon(Icons.tune, size: 18)
                    : null,
              ),
            ),
          ),
          textScale: testCase.scale,
        ),
      );
      final finder = find.byKey(key);
      final label = tester.widget<StudioMenuLabel>(finder);
      final measured = label.measureWidth(
        tester.element(finder),
        leadingWidth: testCase.leading ? 18 : 0,
      );
      expect(tester.getSize(finder).width, closeTo(measured, 1));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('不改变窗口时标签变长收纳并恢复短标签后回到行内', (tester) async {
    var labelText = '模式';
    late StateSetter rebuild;
    const width = 100.0;

    Widget configurationEntry() {
      final label = StudioMenuLabel(label: labelText, maxWidth: 120);
      return ComposerConfigurationBar(
        moreTooltip: '更多配置',
        entries: [
          ComposerConfigurationEntry(
            id: 'dynamic-mode',
            inline: StudioMenuLabel(
              key: const ValueKey('dynamic-inline'),
              label: labelText,
              maxWidth: 120,
            ),
            measureInlineWidth: (context) => label.measureWidth(context),
            menuItem: MenuItemButton(
              key: const ValueKey('dynamic-menu'),
              child: Text(labelText),
            ),
          ),
        ],
      );
    }

    await tester.pumpWidget(
      _testApp(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return configurationEntry();
              },
            ),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('dynamic-inline')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(ComposerConfigurationBar.moreKey), findsNothing);

    rebuild(() => labelText = '非常长的配置名称与服务端当前模型值');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dynamic-inline')).hitTestable(),
      findsNothing,
    );
    expect(
      find.byKey(ComposerConfigurationBar.moreKey).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.byKey(ComposerConfigurationBar.moreKey));
    await tester.pumpAndSettle();
    expect(find.text('非常长的配置名称与服务端当前模型值'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    rebuild(() => labelText = '模式');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('dynamic-inline')).hitTestable(),
      findsOneWidget,
    );
    expect(find.byKey(ComposerConfigurationBar.moreKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(Widget child, {double textScale = 1}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);
