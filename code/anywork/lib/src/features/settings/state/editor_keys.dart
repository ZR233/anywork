import 'package:freezed_annotation/freezed_annotation.dart';

part 'editor_keys.freezed.dart';

@freezed
abstract class AccountEditorKey with _$AccountEditorKey {
  const factory AccountEditorKey({
    required int editorId,
    String? accountId,
    String? initialTemplateId,
  }) = _AccountEditorKey;
}

@freezed
abstract class ProfileEditorKey with _$ProfileEditorKey {
  const factory ProfileEditorKey({required int editorId, String? profileId}) =
      _ProfileEditorKey;
}

@freezed
abstract class SshEditorKey with _$SshEditorKey {
  const factory SshEditorKey({required int editorId, String? alias}) =
      _SshEditorKey;
}
