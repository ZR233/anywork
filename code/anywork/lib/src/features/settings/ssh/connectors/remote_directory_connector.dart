import 'dart:async';

import 'package:anywork_client/operations.dart';
import 'package:anywork_client/remote.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../connectors/settings_failure_text.dart';
import '../../presentation_api.dart';
import '../../state/settings_action.dart';
import '../state/remote_directory_view_state.dart';
import '../view_models/remote_directory_view_model.dart';
import '../views/remote_directory_view.dart';
import 'ssh_action_errors.dart';

/// Smart directory picker. Explicit cancel/leave joins this UI borrow; D3
/// remains responsible for native cursors even if the whole route disappears.
class RemoteDirectoryConnector extends ConsumerStatefulWidget {
  const RemoteDirectoryConnector({required this.server, required this.pickerId, required this.onClose,
    this.showProjectNameField = false, super.key});
  final SshServerProfile server;
  final int pickerId;
  final ValueChanged<String?> onClose;
  final bool showProjectNameField;
  @override
  ConsumerState<RemoteDirectoryConnector> createState() => _RemoteDirectoryConnectorState();
}

class _RemoteDirectoryConnectorState extends ConsumerState<RemoteDirectoryConnector> {
  int? _promptedGeneration;
  bool _showingPassword = false;
  bool _finishing = false;
  RemoteDirectoryViewModel get _vm => ref.read(remoteDirectoryViewModelProvider(widget.server.alias, widget.pickerId, widget.showProjectNameField).notifier);
  RemoteDirectoryViewState? get _current => ref.read(remoteDirectoryViewModelProvider(widget.server.alias, widget.pickerId, widget.showProjectNameField)).asData?.value;
  @override
  void initState() { super.initState(); unawaited(_start()); }
  Future<void> _start() async {
    final vm = _vm;
    try { await ref.read(remoteDirectoryViewModelProvider(widget.server.alias, widget.pickerId, widget.showProjectNameField).future); }
    on StudioFailure { return; } // The actual AsyncError stays visible below.
    if (mounted && identical(_vm, vm)) await _browse(vm.start);
  }
  Future<void> _browse(Future<void> Function() action) async {
    final vm = _vm;
    await action();
    if (!mounted || !identical(_vm, vm)) return;
    final value = _current;
    final details = value?.error?.details;
    if (value == null || value.closing || details is! SshAuthenticationFailureDetails || details.passwordOffered != true ||
        _promptedGeneration == value.generation) return;
    _promptedGeneration = value.generation;
    await _password();
  }
  Future<void> _password() async {
    if (_showingPassword || !mounted || _current == null || _current!.busy) return;
    final frozen = _current!;
    _showingPassword = true;
    bool? ready;
    try {
      ready = await showSshPasswordDialog(context, ref, server: widget.server, initialError: frozen.error);
    } finally { _showingPassword = false; }
    if (!mounted || ready != true || _current?.generation != frozen.generation || _current?.closing == true) return;
    await _browse(() => _vm.browse(frozen.pathRaw.trim().isEmpty ? null : frozen.pathRaw.trim()));
  }
  Future<void> _finish({bool retry = false}) async {
    if (_finishing || _showingPassword || _current?.opening == true) return;
    _finishing = true;
    final vm = _vm;
      final path = _current?.completedPath;
    try {
      final complete = await vm.close(retry: retry);
      if (!mounted || !identical(_vm, vm)) return;
      if (!complete) return;
      widget.onClose(path);
    } finally { _finishing = false; }
  }
  Future<void> _open() async {
    if (_finishing || _showingPassword) return;
    final vm = _vm;
    final opened = await vm.openProject();
    if (!mounted) { await vm.close(); return; }
    if (opened) await _finish();
  }
  @override
  Widget build(BuildContext context) {
    final provider = remoteDirectoryViewModelProvider(widget.server.alias, widget.pickerId, widget.showProjectNameField);
    return PopScope(canPop: false, onPopInvokedWithResult: (didPop, result) { if (!didPop) unawaited(_finish()); },
      child: ref.watch(provider).when(
        loading: () => const AlertDialog(content: Center(heightFactor: 2, child: CircularProgressIndicator())),
        error: (error, stack) {
          if (error is! StudioFailure) Error.throwWithStackTrace(error, stack);
          return AlertDialog(content: SelectableText(settingsFailureText(error)), actions: [
            TextButton(onPressed: () => unawaited(_finish()), child: Text(context.l10n.settingsCancel)),
          ]);
        },
        data: (value) {
          final details = value.error?.details;
          final issues = [for (final report in value.cleanupReports) for (final resource in report.unresolved) ...resource.issues];
          return RemoteDirectoryView(state: value, server: widget.server,
            errors: [
              if (value.error case final error?) settingsFailureText(error),
              if (value.observationError case final error?) settingsFailureText(error),
              for (final issue in issues) '${issue.diagnostic.message} [${issue.diagnostic.stage}/${issue.diagnostic.code}: '
                '${issue.diagnostic.correlationId}] · ${issue.recovery.name}',
            ], openMessages: _openMessages(value.openResult),
            canTryPassword: details is SshAuthenticationFailureDetails && details.passwordOffered != false,
            passwordUnavailable: details is SshAuthenticationFailureDetails && details.passwordOffered == false,
            canRetryCleanup: value.closing && issues.any((issue) => issue.recovery != CleanupRecovery.terminal),
            onName: _vm.setName,
            onPath: _vm.setPath, onGo: () => unawaited(_browse(_vm.go)),
            onBrowse: (path) => unawaited(_browse(() => _vm.browse(path))),
            onNextPage: () => unawaited(_browse(_vm.nextPage)),
            onRefresh: () => unawaited(_browse(() => _vm.browse(value.pathRaw.trim().isEmpty ? null : value.pathRaw.trim()))),
            onPassword: () => unawaited(_password()), onRetryCleanup: () => unawaited(_finish(retry: true)),
            onCancel: () => unawaited(_finish()), onOpen: () => unawaited(_open()));
        }));
  }
  List<String> _openMessages(WorkspaceOpenResult? result) => result == null ? [] : [
    for (final step in result.steps) ...switch (step) {
      OpenedWorkspaceOpenStep(:final result) => _command(context.l10n.sidebarOpenProject, result),
      RenamedWorkspaceOpenStep(:final result) => _command(context.l10n.commonSave, result),
      ActivatedWorkspaceOpenStep(:final result) => _command(context.l10n.sidebarContinue, result),
      NotStartedWorkspaceOpenStep(:final stage, :final error) => ['$stage · ${settingsFailureText(error)}'],
    },
    switch (result.selection) {
      AppliedWorkspaceOpenSelection(:final value) => '${context.l10n.sidebarNavigation}: ${value.disposition.name}',
      NotAttemptedWorkspaceOpenSelection(:final reason) => settingsFailureText(reason),
      FailedWorkspaceOpenSelection(:final error) => settingsFailureText(error),
    },
  ];
  List<String> _command<T>(String label, CommandResult<T> result) {
    final action = settledSettingsAction(0, result);
    return ['$label · ${action.outcome?.name}', ...sshActionErrors(action)];
  }
}
