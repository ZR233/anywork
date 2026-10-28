import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/account_editor_session_view_model.dart';
import '../view_models/account_editor_view_model.dart';
import '../view_models/account_models_view_model.dart';
import '../views/account_dialogs.dart';

/// Only the Router's source entry is inspected. Permission never retires a
/// resource or changes location; actual entry disposal applies the resolution.
Future<bool> confirmLeaveAccountEditorEntry(
  BuildContext context,
  AccountEditorEntryKey entry,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final provider = accountEditorSessionViewModelProvider(entry);
  if (!container.exists(provider)) return false;
  final slot = container.read(provider.notifier);
  final session = slot.currentOwner();
  if (session == null || !slot.isCurrentOwner(session) || !session.isActive) {
    return false;
  }
  final source = session.currentEditor;
  final drafts = _ExistingDrafts.capture(container, source, switch (entry) {
    EditingAccountEditorEntryKey(:final account) => account,
    CreatingAccountEditorEntryKey() => source?.target,
  });
  if (drafts == null) return false;
  // Before the first await, invalidate pending template/default callbacks.
  final decision = session.beginLeaveDecision();
  bool current() =>
      container.exists(provider) &&
      identical(container.read(provider.notifier), slot) &&
      slot.isCurrentOwner(session) &&
      session.isActive &&
      session.isLeaveDecisionCurrent(decision) &&
      drafts.isCurrent;
  final permitted = await _confirmDrafts(
    context,
    drafts,
    isCurrent: current,
    resolve: (discard) =>
        current() &&
        session.resolveLeaveDecision(
          decision,
          source: source,
          editorToken: drafts.editorToken,
          models: drafts.models,
          compactToken: drafts.compactToken,
          discardCompact: discard,
        ),
  );
  final allowed = permitted && current();
  if (!allowed) session.cancelLeaveDecision(decision);
  return allowed;
}

/// A template replacement has its own finite source-draft intent. Beginning a
/// route leave decision would supersede that intent; both share the same modal
/// and draft checks, not a second page-selection or navigation protocol.
Future<AccountLeaveChoice?> confirmAccountTemplateReplacement(
  BuildContext context,
  AccountEditorEntryKey entry, {
  required AccountEditorKey? source,
  required Object replacement,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final provider = accountEditorSessionViewModelProvider(entry);
  if (!container.exists(provider)) return null;
  final slot = container.read(provider.notifier);
  final session = slot.currentOwner();
  if (session == null || !slot.isCurrentOwner(session) || !session.isActive) {
    return null;
  }
  final drafts = _ExistingDrafts.capture(container, source, source?.target);
  if (drafts == null) return null;
  bool current() =>
      container.exists(provider) &&
      identical(container.read(provider.notifier), slot) &&
      slot.isCurrentOwner(session) &&
      session.isActive &&
      session.isTemplateReplacementCurrent(source, replacement) &&
      drafts.isCurrent;
  var choice = AccountLeaveChoice.save;
  final permitted = await _confirmDrafts(
    context,
    drafts,
    isCurrent: current,
    resolve: (discard) {
      choice = discard ? AccountLeaveChoice.discard : AccountLeaveChoice.save;
      return current();
    },
  );
  return permitted && current() ? choice : null;
}

Future<bool> confirmLeaveAccountContext(
  BuildContext context,
  AccountDisplayKey account, {
  AccountEditorEntryKey? guardedEditorEntry,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (guardedEditorEntry != null) {
    // The Router established this exact old edit match. A stale/missing child
    // resolution is rejection, never an unconditional parent skip.
    if (guardedEditorEntry is! EditingAccountEditorEntryKey ||
        guardedEditorEntry.account != account) {
      return false;
    }
    final provider = accountEditorSessionViewModelProvider(guardedEditorEntry);
    if (!container.exists(provider)) return false;
    final slot = container.read(provider.notifier);
    final session = slot.currentOwner();
    return session != null &&
        slot.isCurrentOwner(session) &&
        session.isActive &&
        session.hasCurrentLeaveDecision;
  }
  final drafts = _ExistingDrafts.capture(container, null, account);
  if (drafts == null) return false;
  return _confirmDrafts(
    context,
    drafts,
    isCurrent: () => drafts.isCurrent,
    resolve: (_) => drafts.isCurrent && !drafts.blocked,
  );
}

/// Captured existing display owners only. This never observes a repository or
/// instantiates a provider to fill a missing diagnostic/guard field.
final class _ExistingDrafts {
  _ExistingDrafts(
    this.container,
    this.source,
    this.account,
    this.editor,
    this.editorToken,
    this.models,
    this.compactToken,
  );
  final ProviderContainer container;
  final AccountEditorKey? source;
  final AccountDisplayKey? account;
  final AccountEditorViewModel? editor;
  final Object? editorToken;
  final AccountModelsViewModel? models;
  final Object? compactToken;

  static _ExistingDrafts? capture(
    ProviderContainer container,
    AccountEditorKey? source,
    AccountDisplayKey? account,
  ) {
    AccountEditorViewModel? editor;
    if (source != null) {
      final provider = accountEditorViewModelProvider(source);
      if (!container.exists(provider) ||
          container.read(provider).asData == null) {
        return null;
      }
      editor = container.read(provider.notifier);
    }
    AccountModelsViewModel? models;
    if (account?.kind == AccountKind.native) {
      final provider = accountModelsViewModelProvider(account!);
      if (container.exists(provider)) {
        if (container.read(provider).asData == null) return null;
        models = container.read(provider.notifier);
      }
    }
    return _ExistingDrafts(
      container,
      source,
      account,
      editor,
      editor?.leaveToken(),
      models,
      models?.compactLeaveToken(),
    );
  }

  bool get isCurrent {
    if (source != null) {
      final provider = accountEditorViewModelProvider(source!);
      if (!container.exists(provider) ||
          !identical(container.read(provider.notifier), editor) ||
          !editor!.matchesLeaveToken(editorToken!)) {
        return false;
      }
    }
    if (account?.kind == AccountKind.native) {
      final provider = accountModelsViewModelProvider(account!);
      if (models == null) return !container.exists(provider);
      return container.exists(provider) &&
          identical(container.read(provider.notifier), models) &&
          models!.matchesCompactLeaveToken(compactToken!);
    }
    return true;
  }

  AccountEditorViewState? get value => source == null
      ? null
      : container.read(accountEditorViewModelProvider(source!)).asData?.value;
  bool get dirty =>
      value?.dirty == true || (models?.hasCompactDrafts() ?? false);
  bool get unconfirmed =>
      (editor?.hasUnconfirmedSave() ?? false) ||
      (models?.hasUnconfirmedCompactSave() ?? false);
  bool get blocked =>
      (editor?.leaveBlocked() ?? false) ||
      (models?.compactLeaveBlocked() ?? false);
}

Future<bool> _confirmDrafts(
  BuildContext context,
  _ExistingDrafts drafts, {
  required bool Function() isCurrent,
  required bool Function(bool discard) resolve,
}) async {
  if (!isCurrent()) return false;
  if (!drafts.dirty && !drafts.unconfirmed && !drafts.blocked) {
    return resolve(false);
  }
  var cancelled = false;
  var deciding = false;
  bool current() => !cancelled && isCurrent();
  final warning = AppLocalizations.of(context)
      .accountsUnconfirmedSaveDiscardWarning;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (_, setDialogState) => Consumer(
        builder: (_, dialogRef, _) {
          final valid = current();
          if (valid && drafts.source != null) {
            dialogRef.watch(accountEditorViewModelProvider(drafts.source!));
          }
          if (valid && drafts.models != null) {
            dialogRef.watch(accountModelsViewModelProvider(drafts.account!));
          }
          final waiting = valid && drafts.blocked;
          final value = valid ? drafts.value : null;
          final messages = valid
              ? [?value?.error, ?drafts.models?.compactLeaveError()]
              : <String>[];
          return AccountUnsavedChangesDialog(
            canSave:
                valid &&
                !deciding &&
                !waiting &&
                !drafts.unconfirmed &&
                drafts.dirty &&
                (value?.dirty != true || value?.canSave == true) &&
                (!(drafts.models?.hasCompactDrafts() ?? false) ||
                    drafts.models!.canSaveCompactDrafts()),
            canDiscard: valid && !deciding && !waiting,
            saving: deciding || waiting,
            warning: valid && drafts.unconfirmed ? warning : null,
            error: messages.isEmpty ? null : messages.join('\n'),
            onChoice: (choice) async {
              if (choice == AccountLeaveChoice.cancel) {
                cancelled = true;
                Navigator.of(dialogContext).pop(false);
                return;
              }
              if (deciding || !current() || drafts.blocked) return;
              setDialogState(() => deciding = true);
              try {
                if (drafts.editor != null &&
                    !await drafts.editor!.requestLeave(choice)) {
                  return;
                }
                if (!current() || !dialogContext.mounted) return;
                if (drafts.models != null &&
                    !await drafts.models!.requestLeaveCompact(choice)) {
                  return;
                }
                if (!current() || !dialogContext.mounted || drafts.blocked) {
                  return;
                }
                if (choice == AccountLeaveChoice.save &&
                    (drafts.dirty || drafts.unconfirmed)) {
                  return;
                }
                if (resolve(choice == AccountLeaveChoice.discard)) {
                  Navigator.of(dialogContext).pop(true);
                }
              } finally {
                if (dialogContext.mounted) {
                  setDialogState(() => deciding = false);
                }
              }
            },
          );
        },
      ),
    ),
  );
  cancelled = true;
  return result ?? false;
}
