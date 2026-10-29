import 'package:flutter/widgets.dart';

import '../state/account_view_state.dart';
import 'account_editor_connector.dart';

class AccountEditConnector extends StatelessWidget {
  const AccountEditConnector({
    required this.entry,
    this.focusModelId,
    this.addModel = false,
    super.key,
  });
  final AccountEditorEntryKey entry;
  final String? focusModelId;
  final bool addModel;

  @override
  Widget build(BuildContext context) => AccountEditorEntryConnector(
    key: ValueKey(entry),
    entry: entry,
    focusModelId: focusModelId,
    addModel: addModel,
  );
}
