import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 多行输入里唯一需要的局部编辑动作：Shift+Enter 换行。
///
/// Enter 提交不由这里接管：文本框把 `TextInputAction.send` 交给平台文本输入，
/// 引擎把回车翻译成该动作并回调 `onSubmitted`（design/13-plan.md §13.5），
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
          _InsertNewlineIntent: CallbackAction<_InsertNewlineIntent>(
            onInvoke: (_) {
              _insertNewline();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }

  /// 用换行替换当前选区（标准编辑语义），光标落到换行之后。
  ///
  /// 组词中的组合键不改写正文，把这一组合留给输入法。
  void _insertNewline() {
    final value = controller.value;
    if (value.composing.isValid) return;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final replaced = value.replaced(selection, '\n');
    controller.value = TextEditingValue(
      text: replaced.text,
      selection: TextSelection.collapsed(offset: selection.start + 1),
      composing: TextRange.empty,
    );
  }
}

class _InsertNewlineIntent extends Intent {
  const _InsertNewlineIntent();
}
