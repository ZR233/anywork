import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../view_models/workspace_view_model.dart';
import '../views/workspace_name_dialog_view.dart';

class WorkspaceNameDialog extends ConsumerWidget {
  const WorkspaceNameDialog({required this.serial, super.key});
  final int serial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editor = ref.watch(
      workspaceViewModelProvider.select((value) {
        final editor = value.asData?.value.nameEditor;
        return editor?.serial == serial ? editor : null;
      }),
    );
    ref.listen(
      workspaceViewModelProvider.select(
        (value) => value.asData?.value.nameEditor,
      ),
      (before, after) {
        if (before?.serial == serial &&
            after?.serial != serial &&
            context.mounted) {
          Navigator.of(context).pop();
        }
      },
    );
    if (editor == null) return const SizedBox.shrink();
    final vm = ref.read(workspaceViewModelProvider.notifier);
    return WorkspaceNameDialogView(
      state: editor,
      onChanged: vm.changeName,
      onCancel: () => vm.cancelNameEditor(serial),
      onSave: () => unawaited(vm.saveName()),
    );
  }
}
