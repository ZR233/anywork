import 'dart:convert';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_preview_fixtures.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_patch_diff_view.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _multiFilePatch =
    '*** Begin Patch\n'
    '*** Environment ID: env-1\n'
    '*** Add File: lib/new.dart\n'
    '+class New {\n'
    '+  final int value = 1;\n'
    '+}\n'
    '*** Update File: lib/old.dart\n'
    '*** Move to: lib/moved.dart\n'
    '@@ class Old {\n'
    '   int keep = 0;\n'
    '-  int removed = 2;\n'
    '+  int added = 3;\n'
    '+\n'
    '+  void method() {}\n'
    ' }\n'
    '*** Update File: lib/second.dart\n'
    '@@\n'
    '-sole removal\n'
    '@@ another anchor\n'
    '+sole addition\n'
    '*** End of File\n'
    '*** Delete File: docs/old.md\n'
    '*** End Patch';

Widget _host(
  Widget child, {
  Size surface = const Size(800, 600),
  TextScaler? textScaler,
}) => MaterialApp(
  locale: const Locale('zh'),
  theme: pureStudioTheme(),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: textScaler ?? MediaQuery.textScalerOf(context)),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox.fromSize(
        size: surface,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

TimelinePatchDiffView _view(String patch) =>
    TimelinePatchDiffView(document: parseTimelinePatch(patch)!);

List<({TimelinePatchLineKind kind, String text})> _kinds(
  TimelinePatchChunk chunk,
) => [for (final line in chunk.lines) (kind: line.kind, text: line.text)];

List<Color> _rowBackgrounds(WidgetTester tester) => [
  for (final row in tester.widgetList<ColoredBox>(
    find.descendant(
      of: find.byType(TimelinePatchDiffView),
      matching: find.byType(ColoredBox),
    ),
  ))
    if (row.color.a != 0) row.color,
];

void main() {
  test('official patch preview supplies complete multi-file fragments', () {
    final document = parseTimelinePatch(TimelinePreviewFixtures.applyPatchText);
    expect(document, isNotNull);
    final files = document!.files;
    expect(files.map((file) => file.op), [
      TimelinePatchFileOp.add,
      TimelinePatchFileOp.update,
      TimelinePatchFileOp.delete,
    ]);
    expect(files.first.chunks.single.lines, isNotEmpty);
    expect(
      files.first.chunks.single.lines.every(
        (line) => line.kind == TimelinePatchLineKind.addition,
      ),
      isTrue,
    );
    expect(files[1].moveTo, isNotNull);
    expect(files[1].chunks, hasLength(2));
  });

  group('parseTimelinePatch', () {
    test('parses multi-file patch with envelope, move, chunks and EOF', () {
      final document = parseTimelinePatch(_multiFilePatch);
      expect(document, isNotNull);
      final files = document!.files;
      expect(files, hasLength(4));

      expect(files[0].op, TimelinePatchFileOp.add);
      expect(files[0].path, 'lib/new.dart');
      expect(files[0].moveTo, isNull);
      expect(files[0].chunks, hasLength(1));
      expect(files[0].chunks[0].context, isNull);
      expect(_kinds(files[0].chunks[0]), [
        (kind: TimelinePatchLineKind.addition, text: 'class New {'),
        (kind: TimelinePatchLineKind.addition, text: '  final int value = 1;'),
        (kind: TimelinePatchLineKind.addition, text: '}'),
      ]);

      expect(files[1].op, TimelinePatchFileOp.update);
      expect(files[1].path, 'lib/old.dart');
      expect(files[1].moveTo, 'lib/moved.dart');
      expect(files[1].chunks, hasLength(1));
      expect(files[1].chunks[0].context, 'class Old {');
      expect(_kinds(files[1].chunks[0]), [
        (kind: TimelinePatchLineKind.context, text: '  int keep = 0;'),
        (kind: TimelinePatchLineKind.deletion, text: '  int removed = 2;'),
        (kind: TimelinePatchLineKind.addition, text: '  int added = 3;'),
        (kind: TimelinePatchLineKind.addition, text: ''),
        (kind: TimelinePatchLineKind.addition, text: '  void method() {}'),
        (kind: TimelinePatchLineKind.context, text: '}'),
      ]);

      expect(files[2].op, TimelinePatchFileOp.update);
      expect(files[2].path, 'lib/second.dart');
      expect(files[2].moveTo, isNull);
      expect(files[2].chunks, hasLength(2));
      expect(files[2].chunks[0].context, isNull);
      expect(_kinds(files[2].chunks[0]), [
        (kind: TimelinePatchLineKind.deletion, text: 'sole removal'),
      ]);
      expect(files[2].chunks[1].context, 'another anchor');
      expect(_kinds(files[2].chunks[1]), [
        (kind: TimelinePatchLineKind.addition, text: 'sole addition'),
      ]);

      expect(files[3].op, TimelinePatchFileOp.delete);
      expect(files[3].path, 'docs/old.md');
      expect(files[3].chunks, isEmpty);
    });

    test('marker-like source text stays content instead of control lines', () {
      const patch =
          '*** Begin Patch\n'
          '*** Update File: lib/a.dart\n'
          '@@ fn() {\n'
          "   print('*** End Patch');\n"
          "+  print('*** Begin Patch');\n"
          "  const doc = '*** Update File: trap.dart';\n"
          ' }\n'
          '*** End Patch';
      final document = parseTimelinePatch(patch);
      expect(document, isNotNull);
      final file = document!.files.single;
      expect(file.op, TimelinePatchFileOp.update);
      expect(file.path, 'lib/a.dart');
      expect(file.chunks, hasLength(1));
      expect(file.chunks[0].context, 'fn() {');
      expect(_kinds(file.chunks[0]), [
        (
          kind: TimelinePatchLineKind.context,
          text: "  print('*** End Patch');",
        ),
        (
          kind: TimelinePatchLineKind.addition,
          text: "  print('*** Begin Patch');",
        ),
        (
          kind: TimelinePatchLineKind.context,
          text: " const doc = '*** Update File: trap.dart';",
        ),
        (kind: TimelinePatchLineKind.context, text: '}'),
      ]);
    });

    test('rejects text outside the patch block boundaries', () {
      expect(
        parseTimelinePatch(
          'prefix\n*** Begin Patch\n*** Delete File: a\n*** End Patch',
        ),
        isNull,
      );
      expect(
        parseTimelinePatch(
          '*** Begin Patch\n*** Delete File: a\n*** End Patch\nsuffix',
        ),
        isNull,
      );
      expect(
        parseTimelinePatch(
          '*** Begin Patch\n*** Delete File: a\n*** End Patch\n'
          '*** Begin Patch\n*** End Patch',
        ),
        isNull,
      );
    });

    test('rejects truncated, empty and unsupported shapes', () {
      expect(parseTimelinePatch(''), isNull);
      expect(parseTimelinePatch('*** Begin Patch\n'), isNull);
      expect(
        parseTimelinePatch(
          '*** Begin Patch\n*** Update File: a\n@@ -1 +1\n-x\n*** End Patch',
        ),
        isNull,
      );
      expect(
        parseTimelinePatch(
          '*** Begin Patch\n*** Update File: a\n*** End Patch',
        ),
        isNull,
      );
      expect(parseTimelinePatch('*** Begin Patch\n*** End Patch'), isNull);
      expect(
        parseTimelinePatch(
          '*** Begin Patch\n*** Environment ID: \n'
          '*** Delete File: a\n*** End Patch',
        ),
        isNull,
      );
    });

    test('accepts move-only update and empty add content', () {
      final moveOnly = parseTimelinePatch(
        '*** Begin Patch\n*** Update File: a\n*** Move to: b\n*** End Patch',
      );
      expect(moveOnly?.files.single.moveTo, 'b');
      expect(moveOnly?.files.single.chunks, isEmpty);

      final emptyAdd = parseTimelinePatch(
        '*** Begin Patch\n*** Add File: a\n*** End Patch',
      );
      expect(emptyAdd?.files.single.chunks.single.lines, isEmpty);
    });

    test('accepts a headerless chunk and tolerates surrounding whitespace', () {
      const patch =
          '\n*** Begin Patch  \n*** Update File: a\n-removed\n kept\n*** End Patch\t\n';
      final document = parseTimelinePatch(patch);
      expect(document, isNotNull);
      final chunk = document!.files.single.chunks.single;
      expect(chunk.context, isNull);
      expect(_kinds(chunk), [
        (kind: TimelinePatchLineKind.deletion, text: 'removed'),
        (kind: TimelinePatchLineKind.context, text: 'kept'),
      ]);
    });
  });

  group('timelineApplyPatchSource', () {
    test('reads the JSON input envelope without guessing other fields', () {
      expect(timelineApplyPatchSource(_multiFilePatch), _multiFilePatch);
      final envelope = jsonEncode({'input': _multiFilePatch});
      expect(timelineApplyPatchSource(envelope), _multiFilePatch);
      final other = jsonEncode({'patch': _multiFilePatch});
      expect(timelineApplyPatchSource(other), other);
      expect(parseTimelinePatch(timelineApplyPatchSource(envelope)), isNotNull);
      expect(parseTimelinePatch(timelineApplyPatchSource(other)), isNull);
    });
  });

  group('timelineApplyPatchBody', () {
    test('empty stays absent and unparseable turns into the explicit hint', () {
      expect(timelineApplyPatchBody('  '), isNull);
      final hint = timelineApplyPatchBody(
        '*** Begin Patch\n*** Delete File: a',
      );
      expect(hint, isA<TimelinePatchUnavailableHint>());
      expect(
        timelineApplyPatchBody(_multiFilePatch),
        isA<TimelinePatchDiffView>(),
      );
      expect(
        timelineApplyPatchWindowBody(''),
        isA<TimelinePatchUnavailableHint>(),
      );
    });
  });

  group('TimelinePatchDiffView', () {
    const panelPatch =
        '*** Begin Patch\n'
        '*** Update File: lib/old.dart\n'
        '*** Move to: lib/moved.dart\n'
        '@@ class Old {\n'
        '   int keep = 0;\n'
        '-  int removed = 2;\n'
        '+  int added = 3;\n'
        ' }\n'
        '*** End Patch';

    testWidgets('renders headers, full-row backgrounds and selection', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_view(panelPatch)));
      expect(tester.takeException(), isNull);
      expect(find.text('更新'), findsOneWidget);
      expect(find.text('lib/old.dart → lib/moved.dart'), findsOneWidget);

      // 删除、新增各占整行背景；上下文行保持中性面板底色。
      final backgrounds = _rowBackgrounds(tester);
      expect(backgrounds, hasLength(2));
      expect(backgrounds[0], isNot(backgrounds[1]));

      // 行背景铺满代码面板宽度（远宽于最短代码行），而不是只覆盖字形。
      final rowWidths = tester
          .renderObjectList<RenderBox>(
            find.descendant(
              of: find.byType(TimelinePatchDiffView),
              matching: find.byWidgetPredicate(
                (widget) => widget is ColoredBox && widget.color.a != 0,
              ),
            ),
          )
          .map((box) => box.size.width);
      expect(rowWidths, everyElement(greaterThan(600)));

      final plainText = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((rich) => rich.text.toPlainText())
          .join('\n');
      expect(plainText, contains('+   int added = 3;'));
      expect(plainText, contains('-   int removed = 2;'));
      expect(plainText, contains('   int keep = 0;'));
      expect(find.text('⋯'), findsNothing);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('separates bare multiple chunks without line numbers', (
      tester,
    ) async {
      const twoChunks =
          '*** Begin Patch\n'
          '*** Update File: a\n'
          '@@\n'
          '-first\n'
          '@@\n'
          '+second\n'
          '*** End Patch';
      await tester.pumpWidget(_host(_view(twoChunks)));
      expect(tester.takeException(), isNull);
      expect(find.text('⋯'), findsOneWidget);
    });

    testWidgets('dark theme resolves the other background set', (tester) async {
      await tester.pumpWidget(_host(_view(panelPatch)));
      final light = _rowBackgrounds(tester);
      await tester.pumpWidget(
        _host(
          Theme(
            data: pureStudioTheme().copyWith(brightness: Brightness.dark),
            child: _view(panelPatch),
          ),
        ),
      );
      final dark = _rowBackgrounds(tester);
      expect(dark.toSet(), isNot(light.toSet()));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'long lines scroll horizontally without overflow in narrow and large text',
      (tester) async {
        final longLine = '+${'x' * 400}';
        final patch =
            '*** Begin Patch\n*** Update File: a\n@@\n$longLine\n*** End Patch';
        await tester.pumpWidget(
          _host(_view(patch), surface: const Size(360, 600)),
        );
        expect(tester.takeException(), isNull);
        final scroll = find.descendant(
          of: find.byType(TimelinePatchDiffView),
          matching: find.byType(SingleChildScrollView),
        );
        expect(
          tester.widget<SingleChildScrollView>(scroll).scrollDirection,
          Axis.horizontal,
        );

        await tester.pumpWidget(
          _host(
            _view(patch),
            surface: const Size(360, 600),
            textScaler: TextScaler.linear(1.6),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
