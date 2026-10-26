import 'package:anywork_client/bots.dart';
import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';
import 'bots_settings_view_state.dart';

part 'bot_setup_state.freezed.dart';

/// Creation starts from local defaults; editing starts from one canonical
/// snapshot and never invents a field the Repository did not publish.
enum BotSetupMode { create, edit }

enum BotSetupField { name, appId, secret }

enum BotSetupValidation { required }

/// Availability of the secret is a draft fact; the secret text itself is not.
/// Only the editor's local `BotSecretOwner` holds it, and it enters the save
/// command as transient input.
enum BotSecretIntent { preserve, replace, clear }

/// One editor instance. Reopening the same bot is a different editor.
@freezed
abstract class BotSetupKey with _$BotSetupKey {
  const factory BotSetupKey({required int editorId, String? botId}) =
      _BotSetupKey;
}

/// No JSON and no generated `toString`: nothing in this state may echo a
/// secret, a command payload or a verification URL.
@Freezed(toStringOverride: false)
abstract class BotSetupViewState with _$BotSetupViewState {
  const BotSetupViewState._();

  const factory BotSetupViewState({
    required BotSetupKey key,
    required BotSetupMode mode,
    required BotsState source,
    BotSnapshot? canonical,
    @Default('') String name,
    @Default('') String appId,
    @Default('') String projectId,
    @Default(false) bool canChangeAppId,
    @Default(false) bool riskAcknowledged,
    @Default(false) bool manualOpen,
    @Default(BotSecretIntent.preserve) BotSecretIntent secretIntent,
    @Default(0) int draftRevision,
    @Default({}) Map<BotSetupField, BotSetupValidation> validation,
    SettingsAction? saveAction,
    StudioFailure? sourceError,
  }) = _BotSetupViewState;

  bool get create => mode == BotSetupMode.create;
  bool get saving => saveAction?.pending ?? false;
  bool get blocked => saveAction?.preventsResubmission ?? false;
  bool get editable => !saving && !blocked;
  bool get snapshotCurrent => isCurrentBotsSnapshot(source);

  /// A create cannot preserve an absent secret, so an acknowledged risk and a
  /// name are its real preconditions; an edit needs its canonical bot.
  bool get canSave =>
      editable &&
      name.trim().isNotEmpty &&
      snapshotCurrent &&
      (create ? riskAcknowledged : canonical != null);
  bool get canStartRegistration =>
      editable && snapshotCurrent && riskAcknowledged;

  BotSetupValidation? get nameIssue => validation[BotSetupField.name];
  BotSetupValidation? get appIdIssue => validation[BotSetupField.appId];
  BotSetupValidation? get secretIssue => validation[BotSetupField.secret];
}
