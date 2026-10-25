import 'package:flutter/material.dart';

/// A modal surface only. The Smart owner decides what confirmation means and
/// handles navigation, barrier dismissal and any asynchronous operation result.
class ConfirmationView extends StatelessWidget {
  const ConfirmationView({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
    this.destructive = false,
    this.confirmKey,
    this.cancelKey,
    super.key,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(body)),
      actions: [
        TextButton(
          key: cancelKey,
          onPressed: onCancel,
          child: Text(cancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: onConfirm,
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
