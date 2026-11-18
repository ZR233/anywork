import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_input_state.dart';
import 'package:anywork/src/features/conversation/composer/state/composer_view_state.dart';
import 'package:anywork/src/features/conversation/composer/view_models/composer_actions.dart';
import 'package:anywork/src/features/conversation/composer/views/prompt_composer_view.dart';
import 'package:anywork/src/features/conversation/composer/views/composer_support_views.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:anywork/src/platform/dropped_file.dart';
import 'package:anywork/src/shared/studio_driver_keys.dart';
import 'package:anywork/src/shared/composer_action_button.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final width in [320.0, 800.0]) {
    testWidgets('宽度 $width 主操作原位切换且不重复文字，语义和大字保留', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey<_EditorHostState>();
      await tester.pumpWidget(_host(key, textScale: 2));
      final continuation = ContinuationView(
        id: 'continue',
        sourceTurnId: 'turn',
        reason: ContinuationReason.userStop,
        createdAt: DateTime.utc(2026),
      );
      const running = AgentExecutionView(
        id: 'exec',
        phase: AgentExecutionPhase.running,
      );
      const stopping = AgentExecutionView(
        id: 'exec',
        phase: AgentExecutionPhase.stopping,
      );
      final states = [
        (execution: null, continuation: null, accepted: false, text: ''),
        (execution: running, continuation: null, accepted: false, text: ''),
        (execution: running, continuation: null, accepted: false, text: 'next'),
        (
          execution: stopping,
          continuation: null,
          accepted: false,
          text: 'next',
        ),
        (
          execution: null,
          continuation: continuation,
          accepted: false,
          text: '',
        ),
        (execution: null, continuation: continuation, accepted: true, text: ''),
      ];
      Rect? slot;
      Offset? selector;
      for (final state in states) {
        key.currentState!.show(
          ComposerInputState(
            composer: ComposerThreadState.idle(draft: state.text),
            enabled: true,
            execution: state.execution,
            continuation: state.continuation,
            continuationAccepted: state.accepted,
            nowMs: 0,
          ),
        );
        // Busy indicators deliberately keep animating, so do not pumpAndSettle.
        await tester.pump();
        final button = find.descendant(
          of: find.byType(PromptComposerView),
          matching: find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.style?.fixedSize != null,
          ),
        );
        final widget = tester.widget<IconButton>(button);
        final rect = tester.getRect(button);
        slot ??= rect;
        expect(rect.size, slot.size);
        expect(rect.left, slot.left);
        final circularSurface = find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) => widget is Material && widget.shape is CircleBorder,
          ),
        );
        expect(circularSurface, findsOneWidget);
        final surfaceRect = tester.getRect(circularSurface);
        expect(surfaceRect.size, const Size.square(34));
        final busy = key.currentState!.projection!.action.busy;
        final visual = find.descendant(
          of: button,
          matching: busy
              ? find.byType(CircularProgressIndicator)
              : find.byType(Icon),
        );
        expect(visual, findsOneWidget);
        final visualCenter = tester.getCenter(visual);
        if (!busy) {
          final richText = find.descendant(
            of: visual,
            matching: find.byType(RichText),
          );
          expect(richText, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(richText);
          final painter = TextPainter(
            text: paragraph.text,
            textDirection: paragraph.textDirection,
          )..layout();
          final iconText = paragraph.text.toPlainText();
          final glyphBoxes = painter.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: iconText.length),
          );
          expect(
            glyphBoxes,
            isNotEmpty,
            reason: '主操作 RichText 应包含可测量的字形：${iconText.codeUnits}',
          );
          final glyphRect = glyphBoxes
              .map((box) => box.toRect())
              .reduce((a, b) => a.expandToInclude(b));
          final glyphCenter = paragraph.localToGlobal(glyphRect.center);
          painter.dispose();
          expect(
            glyphCenter.dx,
            closeTo(surfaceRect.center.dx, 0.5),
            reason:
                '字形排版中心 ${surfaceRect.center.dx - glyphCenter.dx}px '
                '偏离 34px 圆面中心',
          );
          expect(
            glyphCenter.dy,
            closeTo(surfaceRect.center.dy, 0.5),
            reason:
                '字形排版中心 ${surfaceRect.center.dy - glyphCenter.dy}px '
                '偏离 34px 圆面中心',
          );
        }
        expect(
          visualCenter.dx,
          closeTo(surfaceRect.center.dx, 0.5),
          reason:
              '主操作图形/进度中心 ${surfaceRect.center.dx - visualCenter.dx}px '
              '偏离 34px 圆面中心',
        );
        expect(
          visualCenter.dy,
          closeTo(surfaceRect.center.dy, 0.5),
          reason:
              '主操作图形/进度中心 ${surfaceRect.center.dy - visualCenter.dy}px '
              '偏离 34px 圆面中心',
        );
        final relativeSelector =
            tester.getTopLeft(find.text('route')) - rect.topLeft;
        selector ??= relativeSelector;
        expect(relativeSelector, selector);
        expect(find.text(widget.tooltip!), findsNothing);
        expect(
          find.semantics.byPredicate(
            (node) => node.getSemanticsData().tooltip == widget.tooltip,
          ),
          findsOne,
        );
        expect(
          find.descendant(
            of: button,
            matching: find.byType(CircularProgressIndicator),
          ),
          key.currentState!.projection!.action.busy
              ? findsOneWidget
              : findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
      // Empty Enter must not invoke continuation; only the explicit button may.
      key.currentState!.show(
        ComposerInputState(
          composer: const ComposerThreadState.idle(),
          enabled: true,
          continuation: continuation,
          nowMs: 0,
        ),
      );
      await tester.pump();
      await tester.showKeyboard(find.byKey(StudioDriverKeys.composerInput));
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(key.currentState!.continues, 0);
      await tester.tap(find.byKey(StudioDriverKeys.composerContinue));
      expect(key.currentState!.continues, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('共享主操作按钮按状态触发回调并提供提示与无障碍语义', (tester) async {
    const cases = [
      (
        state: ComposerActionButtonState.send,
        tooltip: '发送',
        callback: true,
        enabled: true,
        busy: false,
      ),
      (
        state: ComposerActionButtonState.sendAndContinue,
        tooltip: '发送并继续',
        callback: true,
        enabled: true,
        busy: false,
      ),
      (
        state: ComposerActionButtonState.stop,
        tooltip: '停止',
        callback: true,
        enabled: true,
        busy: false,
      ),
      (
        state: ComposerActionButtonState.continueConversation,
        tooltip: '继续',
        callback: true,
        enabled: true,
        busy: false,
      ),
      (
        state: ComposerActionButtonState.send,
        tooltip: '不可用发送',
        callback: false,
        enabled: false,
        busy: false,
      ),
      (
        state: ComposerActionButtonState.busy,
        tooltip: '正在处理',
        callback: true,
        enabled: false,
        busy: true,
      ),
      (
        state: ComposerActionButtonState.readOnly,
        tooltip: '只读',
        callback: true,
        enabled: false,
        busy: false,
      ),
    ];
    for (final item in cases) {
      var calls = 0;
      const buttonKey = ValueKey('shared-composer-action');
      await tester.pumpWidget(
        _app(
          ComposerActionButton(
            state: item.state,
            tooltip: item.tooltip,
            buttonKey: buttonKey,
            onPressed: item.callback ? () => calls++ : null,
          ),
        ),
      );
      final button = find.byKey(buttonKey);
      expect(button, findsOneWidget);
      final semantics = find.semantics.byPredicate((node) {
        final data = node.getSemanticsData();
        return data.tooltip == item.tooltip &&
            data.flagsCollection.isEnabled ==
                (item.enabled ? Tristate.isTrue : Tristate.isFalse);
      });
      expect(semantics, findsOneWidget);
      expect(find.text(item.tooltip), findsNothing);
      final surface = find.descendant(
        of: button,
        matching: find.byWidgetPredicate(
          (widget) => widget is Material && widget.shape is CircleBorder,
        ),
      );
      expect(surface, findsOneWidget);
      final surfaceRect = tester.getRect(surface);
      expect(surfaceRect.size, const Size.square(34));
      final graphic = find.descendant(
        of: button,
        matching: item.busy
            ? find.byType(CircularProgressIndicator)
            : find.byType(Icon),
      );
      expect(graphic, findsOneWidget);
      expect(tester.getCenter(graphic), surfaceRect.center);
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        item.busy ? findsOneWidget : findsNothing,
      );
      await tester.tap(button);
      await tester.pump();
      expect(calls, item.enabled ? 1 : 0, reason: item.state.name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('待决交互停止不重复文字，收束状态有禁用语义和进度', (tester) async {
    await tester.pumpWidget(
      _app(
        const InteractionStopView(
          state: InteractionStopViewState(
            executionId: 'exec',
            pending: false,
            stopping: true,
            failure: null,
          ),
          onStop: null,
        ),
      ),
    );
    final button = find.byKey(StudioDriverKeys.composerStopping);
    final label = tester.widget<IconButton>(button).tooltip!;
    expect(find.text(label), findsNothing);
    expect(
      find.semantics.byPredicate(
        (node) => node.getSemanticsData().tooltip == label,
      ),
      findsOne,
    );
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [320.0, 800.0]) {
    testWidgets('宽度 $width 的输入区使用官方焦点并保持单层整体外框', (tester) async {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_host(GlobalKey<_EditorHostState>()));
      final input = find.byKey(StudioDriverKeys.composerInput);
      final decorators = find.descendant(
        of: find.byType(PromptComposerView),
        matching: find.byType(InputDecorator),
      );
      final frame = decorators.evaluate().singleWhere(
        (element) =>
            (element.widget as InputDecorator).decoration.border
                is OutlineInputBorder,
      );
      final frameFinder = find.byElementPredicate(
        (element) => identical(element, frame),
      );
      final inner = find.descendant(
        of: input,
        matching: find.byType(InputDecorator),
      );
      final editor = tester.widget<EditableText>(find.byType(EditableText));
      void expectSingleFrame({required bool focused}) {
        expect(
          tester
              .widgetList<InputDecorator>(decorators)
              .where((view) => view.decoration.border is OutlineInputBorder),
          hasLength(1),
        );
        expect(editor.focusNode.hasFocus, focused);
        final decoration = tester.widget<InputDecorator>(inner).decoration;
        expect(
          decoration.contentPadding,
          const EdgeInsets.symmetric(vertical: 8),
          reason: '保留重构前输入文字的上下留白',
        );
        expect(decoration.enabledBorder, InputBorder.none);
        expect(decoration.focusedBorder, InputBorder.none);
        expect(decoration.disabledBorder, InputBorder.none);
        expect(
          tester.getRect(frameFinder).contains(tester.getCenter(input)),
          isTrue,
        );
        expect(
          find.descendant(
            of: frameFinder,
            matching: find.byKey(const ValueKey('composer-submit-disabled')),
          ),
          findsOneWidget,
          reason: '唯一外框同时包住编辑区与底部操作栏',
        );
        expect(tester.takeException(), isNull);
      }

      expectSingleFrame(focused: false);
      await tester.showKeyboard(input);
      await tester.pumpAndSettle();
      expectSingleFrame(focused: true);
      editor.focusNode.unfocus();
      await tester.pumpAndSettle();
      expectSingleFrame(focused: false);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Shift Enter 由官方编辑动作替换选区、通知变更并可撤销', (tester) async {
    final key = GlobalKey<_EditorHostState>();
    await tester.pumpWidget(_host(key));
    final input = find.byKey(StudioDriverKeys.composerInput);
    await tester.enterText(input, 'abcd');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump(const Duration(milliseconds: 600));
    final controller = tester.widget<TextField>(input).controller!;
    expect(controller.text, 'a\nd');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(key.currentState!.changes.last, 'a\nd');
    expect(key.currentState!.submits, 0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(controller.text, 'abcd', reason: '换行进入 EditableText 原生 undo 历史');
    expect(key.currentState!.changes.last, 'abcd');
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('异步图片探测后默认文本粘贴仍走官方选区替换并保留焦点', (tester) async {
    final key = GlobalKey<_EditorHostState>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': 'pasted'},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_host(key));
    final input = find.byKey(StudioDriverKeys.composerInput);
    await tester.enterText(input, 'abcd');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'abcd',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      ),
    );
    await tester.pump();
    // The focus context is below EditableText's overridable Actions. Invoking
    // from its widget element instead would bypass the default paste delegate.
    Actions.invoke(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .context!,
      const PasteTextIntent(SelectionChangedCause.keyboard),
    );
    await tester.pump();
    final controller = tester.widget<TextField>(input).controller!;
    expect(controller.text, 'apastedd');
    expect(controller.selection, const TextSelection.collapsed(offset: 7));
    expect(key.currentState!.changes.last, 'apastedd');
    expect(
      tester
          .state<EditableTextState>(find.byType(EditableText))
          .widget
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Widget _host(GlobalKey<_EditorHostState> key, {double textScale = 1}) =>
    _app(_EditorHost(key: key), textScale: textScale);

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
  theme: pureStudioTheme(),
  locale: const Locale('en'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: Center(child: child)),
);

class _EditorHost extends StatefulWidget {
  const _EditorHost({super.key});
  @override
  State<_EditorHost> createState() => _EditorHostState();
}

/// No Client substitute: this fixture only acknowledges View editing intents.
class _EditorHostState extends State<_EditorHost> implements ComposerActions {
  String text = '';
  final changes = <String>[];
  int submits = 0;
  int continues = 0;
  ComposerInputState? projection;
  void show(ComposerInputState value) => setState(() => projection = value);
  @override
  Widget build(BuildContext context) => PromptComposerView(
    targetKey: 'editor-test',
    actions: this,
    selectorBar: const Text('route'),
    state:
        projection ??
        ComposerInputState(
          composer: ComposerThreadState.idle(draft: text),
          enabled: true,
          nowMs: 0,
        ),
  );
  @override
  void updateText(String value) => setState(() {
    text = value;
    changes.add(value);
  });
  @override
  void submit() => submits++;
  @override
  void stop(String expectedExecutionId) {}
  @override
  void continueConversation() => continues++;
  @override
  void addUrl(String url) {}
  @override
  void removeAttachment(String draftId) {}
  @override
  void pickAttachments(
    List<ModelInputCapabilityView> capabilities,
    bool Function() isCurrent,
  ) {}
  @override
  Future<void> dropAttachments(
    List<DroppedFileTransfer> files,
    bool Function() isCurrent,
  ) async {}
  @override
  void paste(ComposerTextPaste textPaste) => unawaited(_paste(textPaste));
  Future<void> _paste(ComposerTextPaste textPaste) async {
    await Future<void>.value();
    if (textPaste.isCurrent()) await textPaste.invoke();
  }
}
