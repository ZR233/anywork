import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_state.dart';
import '../view_models/accounts_view_model.dart';
import '../view_models/account_editor_view_model.dart';
import '../views/account_dialogs.dart';
import '../views/accounts_list_view.dart';
import 'account_actions.dart';
import 'account_details_connector.dart';
import 'account_editor_connector.dart';
import 'account_navigation.dart';
import 'account_strings.dart';

class AccountsConnector extends ConsumerStatefulWidget {
  const AccountsConnector({required this.visible, super.key});
  final bool visible;
  @override
  ConsumerState<AccountsConnector> createState() => _AccountsConnectorState();
}

class _AccountsConnectorState extends ConsumerState<AccountsConnector> {
  final _listScroll = ScrollController();
  String? _locale;
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() {
      if (mounted) {
        ref.read(accountsViewModelProvider.notifier).setVisible(widget.visible);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = AppLocalizations.of(context);
    if (_locale == l10n.localeName) return;
    _locale = l10n.localeName;
    scheduleMicrotask(() {
      if (mounted) {
        ref
            .read(accountsViewModelProvider.notifier)
            .setStrings(accountStrings(l10n));
      }
    });
  }

  @override
  void didUpdateWidget(covariant AccountsConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      scheduleMicrotask(() {
        if (mounted) {
          ref
              .read(accountsViewModelProvider.notifier)
              .setVisible(widget.visible);
        }
      });
    }
  }

  @override
  void dispose() {
    _listScroll.dispose();
    super.dispose();
  }

  Future<void> _navigate(void Function(AccountsViewModel owner) action) async {
    if (!await confirmLeaveAccountsEditor(context, ref) || !mounted) return;
    action(ref.read(accountsViewModelProvider.notifier));
  }

  @override
  Widget build(BuildContext context) => ref
      .watch(accountsViewModelProvider)
      .when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(AppLocalizations.of(context).accountsQueryFailed),
        ),
        data: (AccountsViewState value) {
          final owner = ref.read(accountsViewModelProvider.notifier);
          if (value.editor case final key?) {
            return AccountEditorConnector(
              key: ValueKey<String>(key.editorId),
              editor: key,
            );
          }
          if (value.selected case final key?) {
            return AccountDetailsConnector(
              key: ValueKey<String>(
                'account-details:${key.kind.name}:${key.id}',
              ),
              account: key,
            );
          }
          if (value.choosingTemplate) {
            return Column(
              children: [
                if (value.templatesLoading) const LinearProgressIndicator(),
                if (value.templateError case final error?)
                  ListTile(
                    title: Text(error),
                    trailing: TextButton(
                      onPressed: owner.chooseTemplate,
                      child: Text(AppLocalizations.of(context).accountsRetry),
                    ),
                  ),
                Expanded(
                  child: AccountTemplatePickerView(
                    templates: value.templates,
                    onCancel: owner.cancelTemplate,
                    onSelected: (template) async {
                      final editor = owner.create(template);
                      if (editor == null ||
                          editor.target.kind != AccountKind.acp) {
                        return;
                      }
                      // Selecting a template is the explicit preparation intent. Nothing
                      // in a provider build, locale change or rebuild starts preparation.
                      await ref.read(
                        accountEditorViewModelProvider(editor).future,
                      );
                      if (mounted) {
                        await ref
                            .read(
                              accountEditorViewModelProvider(editor).notifier,
                            )
                            .prepareSelectedTemplate();
                      }
                    },
                  ),
                ),
              ],
            );
          }
          return AccountsListView(
            value: value.list,
            scrollController: _listScroll,
            onSearchChanged: owner.search,
            onAdd: () =>
                _navigate((owner) => unawaited(owner.chooseTemplate())),
            onRefreshAll: owner.refreshAll,
            onRetry: owner.retryObservation,
            onOpen: (key) => _navigate((owner) => owner.open(key)),
            onRowAction: (key, action) {
              switch (action) {
                case AccountRowAction.refresh:
                  unawaited(owner.refresh(key));
                case AccountRowAction.setDefault:
                  unawaited(owner.setDefault(key));
                case AccountRowAction.edit:
                  unawaited(_navigate((owner) => owner.edit(key)));
                case AccountRowAction.delete:
                  unawaited(deleteAccount(context, ref, key));
              }
            },
          );
        },
      );
}
