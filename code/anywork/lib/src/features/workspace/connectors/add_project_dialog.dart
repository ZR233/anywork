import 'dart:async';

import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../platform/error_log.dart';
import '../../../platform/local_file_dialogs.dart';
import '../../../ui/overlays/confirmation_view.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../settings/presentation_api.dart';
import '../state/add_project_state.dart';
import '../view_models/add_project_view_model.dart';
import '../views/add_project_dialog_view.dart';
import '../views/project_path_dialog_view.dart';
import '../widgets/workspace_failure_notice.dart';

Future<void> showAddProjectDialog(BuildContext context) {
  final target = AddProjectDialogKey();
  return showDialog<void>(context: context, barrierDismissible: false,
    builder: (_) => AddProjectDialogConnector(target: target));
}

class AddProjectDialogConnector extends ConsumerStatefulWidget {
  const AddProjectDialogConnector({required this.target, super.key});
  final AddProjectDialogKey target;
  @override
  ConsumerState<AddProjectDialogConnector> createState() => _AddProjectDialogConnectorState();
}

class _AddProjectDialogConnectorState extends ConsumerState<AddProjectDialogConnector> {
  bool _showingChild = false;
  AddProjectViewModel get _vm => ref.read(addProjectViewModelProvider(widget.target).notifier);
  AddProjectState? get _current => ref.read(addProjectViewModelProvider(widget.target)).asData?.value;
  bool _owns(AddProjectViewModel vm) => mounted && identical(_vm, vm);

  void _close() {
    if (!mounted || _showingChild || _current?.pending == true) return;
    if (ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
  }

  Future<void> _continue() async {
    final value = _current;
    if (_showingChild || value == null || value.pending || value.sealed) return;
    final vm = _vm;
    try {
      if (value.step == AddProjectStep.location) {
        if (value.remote == true) {
          await vm.showConnections();
        } else if (value.remote == false) {
          final opened = await vm.openLocal(() => const bool.fromEnvironment('ANYWORK_DRIVER')
              ? _driverPath() : pickLocalProjectDirectory());
          if (_owns(vm) && opened) _close();
        }
        return;
      }
      final server = value.selectedServer;
      if (server == null) return;
      await vm.connect(server);
      if (!_owns(vm)) return;
      final failure = _current?.authenticationFailure;
      if (failure != null) {
        _showingChild = true;
        bool? authenticated;
        try {
          authenticated = await showSshPasswordDialog(context, ref,
            server: server.profile, initialError: failure);
        } finally { _showingChild = false; }
        if (!_owns(vm) || authenticated != true) return;
        vm.passwordAuthenticated(server);
      }
      if (!_owns(vm) || _current?.step != AddProjectStep.directory) return;
      _showingChild = true;
      String? opened;
      try {
        opened = await showRemoteDirectoryDialog(context, ref,
          server: server.profile, showProjectNameField: true);
      } finally { _showingChild = false; }
      if (!_owns(vm)) return;
      if (opened != null) {
        // U1 already completed the one open→rename→activate batch and handed
        // off its original query. Do not open, rename or activate again here.
        _close();
      } else {
        vm.back(); // Retain the original connection selection and raw search.
      }
    } catch (error, stack) {
      _failure(vm, error, stack);
    }
  }

  Future<void> _edit(SshServerRuntimeEntry? frozen) async {
    if (_showingChild || _current?.pending != false || _current?.sealed == true) return;
    final vm = _vm;
    final intent = vm.beginEditorIntent();
    if (intent == null) return;
    _showingChild = true;
    try {
      final saved = await showSshEditorDialog(context, ref, alias: frozen?.profile.alias);
      if (_owns(vm) && saved != null) vm.editorSaved(saved, intent);
    } catch (error, stack) {
      _failure(vm, error, stack);
    } finally { _showingChild = false; }
  }

  Future<void> _delete(SshServerRuntimeEntry frozen) async {
    if (_showingChild || !frozen.managed || _current?.pending != false || _current?.sealed == true) return;
    final vm = _vm;
    _showingChild = true;
    bool? confirmed;
    try {
      confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => ConfirmationView(
        title: context.l10n.settingsSshDeleteTitle,
        body: context.l10n.settingsSshDeleteBody(frozen.profile.alias),
        confirmLabel: context.l10n.settingsSshDelete, cancelLabel: context.l10n.settingsCancel,
        destructive: true, confirmKey: StudioDriverKeys.sshDeleteConfirm,
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false)));
      if (_owns(vm) && confirmed == true) await vm.deleteServer(frozen);
    } catch (error, stack) {
      _failure(vm, error, stack);
    } finally { _showingChild = false; }
  }

  Future<String?> _driverPath() => showDialog<String>(context: context,
    builder: (_) => _DriverProjectPathConnector(target: widget.target));

  void _failure(AddProjectViewModel vm, Object error, StackTrace stack) {
    final correlation = error is StudioFailure && error.correlationId.isNotEmpty
        ? error.correlationId : newStudioCorrelationId();
    // Late UI/platform failures still reach diagnostics; currentness only
    // controls presentation, not whether the original failure is retained.
    recordDartError(error, stack, stage: 'project-dialog', correlationId: correlation);
    if (!_owns(vm)) return;
    if (error is StudioFailure) {
      vm.reportPlatformFailure(error);
      return;
    }
    vm.reportPlatformFailure(StudioFailure(code: StudioFailureCode.internal,
      message: 'The project dialog could not complete.', retryable: true, correlationId: correlation));
  }

  @override
  Widget build(BuildContext context) {
    final provider = addProjectViewModelProvider(widget.target);
    final watched = ref.watch(provider);
    return watched.when(
      loading: () => const AlertDialog(content: Center(heightFactor: 2, child: CircularProgressIndicator())),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return AlertDialog(content: WorkspaceFailureNotice(failure: error), actions: [
          TextButton(onPressed: _close, child: Text(context.l10n.settingsCancel)),
          TextButton(onPressed: () => ref.invalidate(provider), child: Text(context.l10n.sidebarRetry)),
        ]);
      },
      data: (value) {
        final vm = _vm;
        return AddProjectDialogView(state: value,
          onLocation: vm.chooseLocation, onSearch: vm.changeSearch, onSelectServer: vm.chooseServer,
          onContinue: () => unawaited(_continue()), onEditServer: (server) => unawaited(_edit(server)),
          onDeleteServer: (server) => unawaited(_delete(server)), onReload: () => unawaited(vm.reloadServers()),
          onBack: vm.back, onClose: _close, onDismissOpenResult: vm.dismissOpenResult);
      },
    );
  }
}

class _DriverProjectPathConnector extends ConsumerWidget {
  const _DriverProjectPathConnector({required this.target});
  final AddProjectDialogKey target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = addProjectViewModelProvider(target);
    final watched = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    return watched.when(
      loading: () => const AlertDialog(content: Center(heightFactor: 2, child: CircularProgressIndicator())),
      error: (error, stack) {
        if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
        return AlertDialog(content: WorkspaceFailureNotice(failure: error), actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.settingsCancel)),
        ]);
      },
      data: (value) => ProjectPathDialogView(raw: value.localPathRaw, enabled: !value.sealed,
        canSubmit: value.canSubmitLocalPath,
      onChanged: vm.changeLocalPath,
      onSubmit: () { final path = vm.submitLocalPath(); if (path != null) Navigator.of(context).pop(path); },
        onCancel: () => Navigator.of(context).pop()),
    );
  }
}
