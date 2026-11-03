import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'account_editor_ids.g.dart';

/// An application presentation scope's allocator, not a registry of editors.
final class AccountEditorIds {
  BigInt _sequence = BigInt.zero;
  final Random _random = Random.secure();

  String next() {
    _sequence += BigInt.one;
    return 'account-editor-$_sequence';
  }

  /// Protected credentials share an OS-user namespace across configuration homes.
  /// A template name or a local sequence cannot identify a new durable account.
  String newAccount(String templateId) {
    final suffix = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$templateId-$suffix';
  }
}

@Riverpod(keepAlive: true)
AccountEditorIds accountEditorIds(Ref ref) => AccountEditorIds();
