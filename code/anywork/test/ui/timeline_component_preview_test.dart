import 'dart:ui' as ui;

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_component_previews.dart';
import 'package:anywork/src/features/conversation/timeline/previews/plan_detail_previews.dart';
import 'package:anywork/src/features/conversation/timeline/previews/timeline_preview_fixtures.dart';
import 'package:anywork/src/features/conversation/interactions/views/plan_confirmation_view.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_detail_view.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_document_theme.dart';
import 'package:anywork/src/features/conversation/timeline/views/plan_receipt_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_markdown.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_children_view.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpt_markdown/custom_widgets/custom_divider.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

void main() {
  testWidgets('正文与工作组间距不随作者和时间变化，成员没有重复缩进', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final narrow in [false, true]) {
      tester.view.physicalSize = narrow
          ? const Size(390, 1040)
          : const Size(1040, 680);
      await tester.pumpWidget(
        narrow ? timelineSpacingNarrowPreview() : timelineSpacingPreview(),
      );
      await tester.pumpAndSettle();
      final workHeaders = find.byType(CompletionRunView);
      expect(workHeaders, findsNWidgets(2));
      Finder workHeader(int index) =>
          find.byKey(ValueKey('completion-run-header:spacing-group-$index'));
      for (final work in tester.widgetList<CompletionRunView>(workHeaders)) {
        expect(work.summary.total, 3);
        expect(work.summary.terminal, 3);
        expect(work.summary.elapsedMs, 125000);
        expect(work.location, WorkDisplayLocation.history);
        expect(work.initiallyExpanded, isFalse);
      }
      final items = [
        find.byKey(const ValueKey('chat-item:spacing-intro')),
        find.byKey(const ValueKey('chat-item:spacing-plain')),
        workHeader(0),
        find.byKey(const ValueKey('chat-item:spacing-result-0')),
        workHeader(1),
        find.byKey(const ValueKey('chat-item:spacing-result-1')),
      ];
      final gaps = [
        for (var i = 1; i < items.length; i++)
          tester.getRect(items[i]).top - tester.getRect(items[i - 1]).bottom,
      ];
      expect(gaps.first, inInclusiveRange(8, 16));
      for (final gap in gaps) {
        expect(gap, closeTo(gaps.first, .01), reason: '同作者、跨时间与工作组边界应共享条目间距');
      }
      await tester.tap(items[2]);
      await tester.pumpAndSettle();
      final rows = find.byType(TimelineActivityRow);
      final members = find.descendant(
        of: find.byType(TimelineChildrenView),
        matching: rows,
      );
      expect(members, findsNWidgets(3));
      final rects = [
        for (final element in members.evaluate())
          tester.getRect(find.byWidget(element.widget)),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left, rects.first.left);
        expect(
          rects[i].top,
          closeTo(rects[i - 1].bottom, .01),
          reason: '活动行已有自然行高，成员外壳不能再叠加消息间距',
        );
      }
      final rail = tester.getRect(find.byType(TimelineChildrenView));
      expect(rects.first.left, closeTo(rail.left, .01));
      expect(rects.first.right, closeTo(rail.right, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Plan workspace 工况仅装配生产展示组件，短窗与大字可达', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    for (final (id, size, preview) in [
      ('drafting', const Size(760, 720), planDraftingPreview),
      ('awaiting', const Size(760, 720), planAwaitingPreview),
      ('feedback', const Size(760, 720), planFeedbackPreview),
      ('submitting', const Size(760, 720), planSubmittingPreview),
      ('error', const Size(760, 720), planErrorPreview),
      ('revision', const Size(760, 720), planRevisionPreview),
      ('approved', const Size(760, 720), planApprovedPreview),
      ('full', const Size(1040, 720), planFullPreview),
      ('narrow', const Size(360, 760), planNarrowPreview),
      ('large', const Size(360, 900), planLargePreview),
      ('short', const Size(640, 480), planShortPreview),
      ('history', const Size(760, 720), planHistoryPreview),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ListTileTheme(
          data: const ListTileThemeData(
            tileColor: Colors.black,
            textColor: Colors.white,
            iconColor: Colors.white,
          ),
          child: preview(),
        ),
      );
      if (id == 'submitting') {
        await tester.pump(const Duration(milliseconds: 300));
      } else {
        await tester.pumpAndSettle();
      }
      expect(find.byKey(ValueKey('plan-preview:$id')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: id);
      if (id == 'history') {
        expect(find.byType(PlanReceiptView), findsNWidgets(4));
        expect(find.byType(PlanConfirmationView), findsNothing);
        expect(find.byType(TextField), findsNothing);
        final receipts = tester
            .widgetList<PlanReceiptView>(find.byType(PlanReceiptView))
            .toList();
        expect(receipts.first.initiallyExpanded, isTrue);
        expect(receipts.skip(1).every((r) => !r.initiallyExpanded), isTrue);
        final summary = tester.element(find.text('计划已批准'));
        final theme = Theme.of(summary);
        final tileTheme = ListTileTheme.of(summary);
        expect(theme.brightness, Brightness.light);
        expect(tileTheme.tileColor, theme.listTileTheme.tileColor);
        expect(tileTheme.textColor, theme.listTileTheme.textColor);
        expect(
          tileTheme.iconColor,
          theme.expansionTileTheme.iconColor ?? theme.colorScheme.primary,
          reason: '展开回执使用生产 ExpansionTile 的活动图标色',
        );
      } else {
        expect(find.byType(PlanDetailView), findsOneWidget);
        if (id != 'drafting') {
          final panel = tester.getRect(find.byType(PlanDetailView));
          final document = tester.getRect(find.byType(PlanDocumentTheme));
          final padding = panel.width < 520 ? 20.0 : 24.0;
          expect(
            document.left,
            closeTo(panel.left + padding, 1),
            reason: '$id 的短正文也必须对齐阅读列左缘，不能按内容宽度居中',
          );
          expect(
            document.right,
            closeTo(panel.right - padding, 1),
            reason: '$id 的正文应填满面板实际可用宽度',
          );
        }
      }
      if (id == 'awaiting') {
        final revise = find.byKey(StudioDriverKeys.planSubmitRevision);
        expect(tester.widget<OutlinedButton>(revise).onPressed, isNull);
        await tester.enterText(
          find.byKey(StudioDriverKeys.planFeedbackInput),
          '保留这个预览草稿',
        );
        await tester.pump();
        expect(tester.widget<OutlinedButton>(revise).onPressed, isNotNull);
        await tester.ensureVisible(revise);
        await tester.tap(revise);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Text>(find.byKey(StudioDriverKeys.planDetailsStatus))
              .data,
          '等待确认',
          reason: '预览回调不伪造批准或修订的业务结果',
        );
      }
      if (id == 'submitting') {
        expect(
          tester
              .widget<TextField>(find.byKey(StudioDriverKeys.planFeedbackInput))
              .enabled,
          isFalse,
        );
        expect(
          tester
              .widget<TextField>(find.byKey(StudioDriverKeys.planFeedbackInput))
              .controller!
              .text,
          '请先保留当前选中的会话，再补充空结果提示。',
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(StudioDriverKeys.planApprove))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(StudioDriverKeys.planSubmitRevision),
              )
              .onPressed,
          isNull,
        );
      }
      if (id == 'short' || id == 'large' || id == 'narrow') {
        final approve = find.byKey(StudioDriverKeys.planApprove);
        await tester.ensureVisible(approve);
        await tester.pumpAndSettle();
        expect(approve.hitTestable(), findsOneWidget, reason: id);
        expect(tester.getSize(approve).height, greaterThanOrEqualTo(48));
        final input = tester.getRect(
          find.byKey(StudioDriverKeys.planFeedbackInput),
        );
        expect(tester.getRect(approve).right, closeTo(input.right, 1));
        expect(tester.takeException(), isNull, reason: id);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Plan 正文局部排版同时用于详情和回执，普通 Markdown 保留原主题', (tester) async {
    const headings = ['阅读标题', '实施范围', '步骤', '补充', '细节', '备注'];
    const document =
        '# 阅读标题\n\n## 实施范围\n\n### 步骤\n\n#### 补充\n\n##### 细节\n\n###### 备注\n\n正文内容。';
    Widget markdown(String id) => TimelineMarkdown(
      key: ValueKey(id),
      id: id,
      text: document,
      onLink: (_) {},
      isSafeLink: (_) => false,
      imageBuilder: (_, _) => const SizedBox.shrink(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: pureStudioTheme(),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  height: 400,
                  child: PlanDetailView(
                    identity: 'typography',
                    title: '实施计划',
                    status: PlanDetailStatus.approved,
                    onClose: () {},
                    body: markdown('plan-detail-body'),
                  ),
                ),
                PlanReceiptView(
                  label: '计划已批准',
                  icon: Icons.check,
                  initiallyExpanded: true,
                  children: [markdown('plan-receipt-body')],
                ),
                markdown('ordinary-body'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder renderer(String id) => find.descendant(
      of: find.byKey(ValueKey(id)),
      matching: find.byType(GptMarkdown),
    );
    TextStyle renderedStyle(Finder root, String label) {
      final styles = <TextStyle>[];
      void visit(InlineSpan span, TextStyle inherited) {
        final effective = inherited.merge(span.style);
        if (span is TextSpan) {
          if (span.text == label) styles.add(effective);
          for (final child in span.children ?? const <InlineSpan>[]) {
            visit(child, effective);
          }
        }
      }

      for (final rich in tester.widgetList<RichText>(
        find.descendant(of: root, matching: find.byType(RichText)),
      )) {
        visit(rich.text, const TextStyle());
      }
      expect(styles, hasLength(1), reason: '检查真实渲染的 $label 文本跨度');
      return styles.single;
    }

    final outside = renderer('ordinary-body');
    final base = GptMarkdownTheme.of(tester.element(outside));
    final official = GptMarkdownThemeData(brightness: Brightness.light);
    final officialHeadings = [
      official.h1,
      official.h2,
      official.h3,
      official.h4,
      official.h5,
      official.h6,
    ];
    for (var level = 0; level < headings.length; level++) {
      final actual = renderedStyle(outside, headings[level]);
      expect(actual.fontSize, officialHeadings[level]!.fontSize);
      expect(actual.fontWeight, officialHeadings[level]!.fontWeight);
    }
    expect(
      find.descendant(of: outside, matching: find.byType(CustomDivider)),
      findsOneWidget,
      reason: '同一真实 Markdown 在 Plan 外继续使用原主题的 h1 分隔线',
    );
    for (final id in ['plan-detail-body', 'plan-receipt-body']) {
      final rendered = renderer(id);
      expect(
        find.ancestor(of: rendered, matching: find.byType(PlanDocumentTheme)),
        findsOneWidget,
      );
      final scoped = GptMarkdownTheme.of(tester.element(rendered));
      expect(scoped.h1?.fontSize, 24);
      expect(scoped.h1?.height, 1.4);
      expect(scoped.h2?.fontSize, 18);
      expect(scoped.h3?.fontSize, 16);
      expect(scoped.h1?.fontWeight, FontWeight.w600);
      expect(scoped.h1?.fontFamily, base.h1?.fontFamily);
      expect(scoped.h1?.color, base.h1?.color);
      expect(scoped.linkColor, base.linkColor);
      expect(scoped.inlineCode, same(base.inlineCode));
      expect(scoped.styleSheet, same(base.styleSheet));
      for (var level = 0; level < headings.length; level++) {
        final actual = renderedStyle(rendered, headings[level]);
        expect(actual.fontWeight, FontWeight.w600);
        expect(
          actual.fontSize,
          level < 3 ? [24.0, 18.0, 16.0][level] : lessThanOrEqualTo(16),
        );
      }
      expect(
        find.descendant(of: rendered, matching: find.byType(CustomDivider)),
        findsNothing,
        reason: '$id 的真实 Markdown 渲染不应自动插入 h1 分隔线',
      );
      expect(
        scoped.h1?.fontSize,
        lessThan(base.h1!.fontSize!),
        reason: 'Plan 排版必须局部生效，不改变普通 Markdown 的标题层级',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'public component previews mount production widgets without a runtime',
    (tester) async {
      for (final preview in [
        timelineMarkdownPreview,
        timelinePlainTextPreview,
        timelineActivityRowPreview,
        timelineToolDetailsPreview,
        timelineWebSearchPreview,
        timelineWaitPanelPreview,
        timelineWaitDetailsPreview,
        timelineChildrenPreview,
      ]) {
        await tester.pumpWidget(preview());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('content preview uses production ExpansionTile state', (
    tester,
  ) async {
    await tester.pumpWidget(timelineContentWindowPreview());
    await tester.pumpAndSettle();
    final disclosure = find.byKey(
      StudioDriverKeys.timelineContentOpen('preview-deferred', 'payload'),
    );
    expect(disclosure, findsOneWidget);
    final tile = find.descendant(
      of: disclosure,
      matching: find.byType(ExpansionTile),
    );
    expect(tile, findsOneWidget);

    ExpansibleController controller() {
      final title = find.byWidget(tester.widget<ExpansionTile>(tile).title);
      expect(title, findsOneWidget);
      return ExpansibleController.of(tester.element(title));
    }

    expect(controller().isExpanded, isTrue);
    expect(find.text('复制当前段'), findsOneWidget);
    await tester.tap(find.text('按需查看原文 · 196608 字节'));
    await tester.pumpAndSettle();
    expect(controller().isExpanded, isFalse);
    expect(find.text('复制当前段'), findsNothing);
    await tester.tap(find.text('按需查看原文 · 196608 字节'));
    await tester.pumpAndSettle();
    expect(controller().isExpanded, isTrue);
    expect(find.text('复制当前段'), findsOneWidget);
  });

  testWidgets(
    'synthetic PNG preview decodes at its declared size and opens production dialog',
    (tester) async {
      // Engine image decoding is real asynchronous work, outside fake time.
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(
          TimelinePreviewFixtures.imageBytes,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            expect(
              (frame.image.width, frame.image.height),
              (
                TimelinePreviewFixtures.imageWidth,
                TimelinePreviewFixtures.imageHeight,
              ),
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      });
      await tester.pumpWidget(timelineImagePreview());
      await tester.pumpAndSettle();
      final thumbnail = find.byKey(
        StudioDriverKeys.viewImageThumbnail('preview-image'),
      );
      expect(tester.getSize(thumbnail).width, greaterThan(100));
      expect(tester.getSize(thumbnail).height, greaterThan(100));
      await tester.tap(thumbnail);
      await tester.pumpAndSettle();
      expect(
        find.byKey(StudioDriverKeys.timelineImageDialog('preview-image')),
        findsOneWidget,
      );
      expect(find.text('synthetic-landscape-320x180.png'), findsOneWidget);
      await tester.tap(find.byKey(StudioDriverKeys.timelineImageClose));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
