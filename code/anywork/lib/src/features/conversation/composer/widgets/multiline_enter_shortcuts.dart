import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// 多行输入里唯一需要的局部编辑动作：Shift+Enter 换行。
///
/// Enter 提交不由这里接管：文本框把 `TextInputAction.send` 交给平台文本输入，
/// 引擎把回车翻译成该动作并回调 `onSubmitted`，
/// 而 IME 组词中的回车先由输入法确认候选，框架根本不参与提交。因此这里只补
/// 官方 `TextField` 样例中的同一条局部 Shortcuts/Actions：监听范围止于该文本框，
/// 不注册全局按键、不抢焦点，也不用延时补丁绕开输入法。
class MultilineEnterShortcuts extends StatelessWidget {
  const MultilineEnterShortcuts({
    required this.controller,
    required this.child,
    super.key,
  });

  final TextEditingController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter, shift: true):
            _InsertNewlineIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
            _InsertNewlineIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _InsertNewlineIntent: _InsertNewlineAction(controller),
        },
        child: child,
      ),
    );
  }
}

/// The shortcut context is the focused EditableText, whose default action owns
/// selection replacement, input formatters, undo history and onChanged.
class _InsertNewlineAction extends ContextAction<_InsertNewlineIntent> {
  _InsertNewlineAction(this.controller);

  final TextEditingController controller;

  @override
  Object? invoke(_InsertNewlineIntent intent, [BuildContext? context]) {
    if (context == null) return null;
    final value = controller.value;
    // Leave composition to the input method.
    if (value.composing.isValid) return null;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    Actions.invoke(
      context,
      ReplaceTextIntent(value, '\n', selection, SelectionChangedCause.keyboard),
    );
    // ReplaceTextIntent preserves the replaced selection. Collapse the resulting
    // selection through EditableText too, without rewriting controller contents.
    final updated = controller.value;
    return Actions.invoke(
      context,
      UpdateSelectionIntent(
        updated,
        TextSelection.collapsed(offset: updated.selection.end),
        SelectionChangedCause.keyboard,
      ),
    );
  }
}

class _InsertNewlineIntent extends Intent {
  const _InsertNewlineIntent();
}
