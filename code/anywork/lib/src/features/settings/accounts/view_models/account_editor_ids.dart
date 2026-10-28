import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_editor_ids.g.dart';

/// An application presentation scope's allocator, not a registry of editors.
final class AccountEditorIds {
  BigInt _sequence = BigInt.zero;

  String next() {
    _sequence += BigInt.one;
    return 'account-editor-$_sequence';
  }
}

@Riverpod(keepAlive: true)
AccountEditorIds accountEditorIds(Ref ref) => AccountEditorIds();
