import 'package:flutter/widgets.dart';

import '../state/account_view_state.dart';
import 'account_editor_connector.dart';

class AccountCreateConnector extends StatelessWidget {
  const AccountCreateConnector({required this.entry, super.key});
  final AccountEditorEntryKey entry;

  @override
  Widget build(BuildContext context) =>
      AccountEditorEntryConnector(key: ValueKey(entry), entry: entry);
}
