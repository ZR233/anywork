import 'settings_account_drafts.dart';
import 'settings_acp_account_draft.dart';

/// 账号编辑页的草稿分支。
///
/// Native 模型账号与 ACP 接入共享同一“添加账号/编辑”入口，但草稿与保存语义完全独立：
/// 调用方按 sealed 分支重建对应的表单，不把 ACP 字段塞进 Native 账号草稿。
sealed class AccountEditorDraft {
  const AccountEditorDraft();
}

final class NativeAccountEditorDraft extends AccountEditorDraft {
  const NativeAccountEditorDraft(this.draft);

  final AccountDraft draft;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeAccountEditorDraft && identical(other.draft, draft);

  @override
  int get hashCode => Object.hash(0x0401, identityHashCode(draft));
}

final class AcpAccountEditorDraft extends AccountEditorDraft {
  const AcpAccountEditorDraft(this.draft);

  final AcpAccountDraft draft;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountEditorDraft && identical(other.draft, draft);

  @override
  int get hashCode => Object.hash(0x0402, draft);
}
