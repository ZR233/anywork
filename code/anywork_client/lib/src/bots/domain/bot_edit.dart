import 'package:freezed_annotation/freezed_annotation.dart';

import 'bot_values.dart';

part 'bot_edit.freezed.dart';

/// A transient command input. No secret buffer or editable draft is owned by
/// the Repository, and Replace never enters its canonical snapshots.
@Freezed(toStringOverride: false)
sealed class BotSecretUpdate with _$BotSecretUpdate {
  const BotSecretUpdate._();

  const factory BotSecretUpdate.preserve() = BotSecretPreserve;
  const factory BotSecretUpdate.replace({required String value}) =
      BotSecretReplace;
  const factory BotSecretUpdate.clear() = BotSecretClear;

  @override
  String toString() => 'BotSecretUpdate(<redacted>)';
}

@Freezed(toStringOverride: false)
abstract class BotEdit with _$BotEdit {
  const factory BotEdit({
    required String? botId,
    required int expectedConfigRevision,
    required String name,
    required String projectId,
    required String appId,
    required BotSecretUpdate secret,
    required bool enabled,
    required bool toolsEnabled,
    required BotModelRoute? modelRoute,
  }) = _BotEdit;
}
