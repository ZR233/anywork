import 'package:material_ui/material_ui.dart';

class ComposerPasteAction extends Action<PasteTextIntent> {
  ComposerPasteAction({required this.canPaste, required this.paste});

  final bool Function() canPaste;
  final void Function(Future<void> Function()) paste;

  @override
  bool isEnabled(PasteTextIntent intent) => canPaste();

  @override
  Object? invoke(PasteTextIntent intent) {
    // EditableText supplies the original overridable action only during invoke.
    // Capture it before the asynchronous image read, rather than looking it up
    // later or duplicating platform shortcuts and text selection edits.
    final defaultPaste = callingAction!;
    paste(() async {
      final result = defaultPaste.invoke(intent);
      if (result is Future) {
        await result;
      }
    });
    return null;
  }
}
