import 'package:flutter/widgets.dart';

/// The only holder of a bot App Secret while its editor is open.
///
/// The secret never enters the editor's ViewState, a command receipt, a log or
/// a driver projection: the field is obscured, this owner never prints its
/// contents, and [release] scrubs the buffer when the editor saves, cancels or
/// is disposed. The editor's ViewModel only learns whether a value is present.
///
/// It is a UI-only controller: it holds a Widget-layer text controller, has no
/// business capability, and lives in the feature's UI layer next to the Dumb
/// view that receives it as a prop.
final class BotSecretOwner {
  BotSecretOwner({String initial = ''})
    : controller = TextEditingController(text: initial);

  /// The obscured field's controller. Handlers must not read `text` outside
  /// [take], and no projection may serialize it.
  final TextEditingController controller;

  bool get hasValue => controller.text.trim().isNotEmpty;

  /// The trimmed secret for one save command, or null when nothing was typed.
  String? take() {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  /// Drops the secret from memory. Safe to call repeatedly.
  void release() {
    if (controller.text.isNotEmpty) controller.clear();
  }

  void dispose() {
    release();
    controller.dispose();
  }

  @override
  String toString() => 'BotSecretOwner(<redacted>)';
}
