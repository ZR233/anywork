import 'package:anywork_client/studio_client.dart';

/// ACP 接入的新建/编辑草稿。
///
/// 草稿只保存表单意图：显示名、server 程序路径与高级 argv。认证状态、连接身份与
/// 保存结果都不在草稿里，避免把“已登录”写成本地事实。
enum AcpAccountDraftMode { create, edit }

class AcpAccountDraft {
  const AcpAccountDraft({
    required this.mode,
    required this.accountId,
    required this.template,
    required this.name,
    required this.program,
    required this.args,
    this.connectionRevision = 0,
  });

  /// 以目录模板创建草稿：显示名与默认 argv 都来自 backend typed catalog。
  factory AcpAccountDraft.create({
    required AcpAccountTemplateView template,
    required String accountId,
  }) {
    return AcpAccountDraft(
      mode: AcpAccountDraftMode.create,
      accountId: accountId,
      template: template,
      name: template.displayName,
      program: '',
      args: template.defaultArgs,
    );
  }

  /// 以已保存的接入创建编辑草稿；目录暂不可用时仍保持 provider 身份。
  factory AcpAccountDraft.edit({
    required AcpAccountSettingsView account,
    AcpAccountTemplateView? template,
  }) {
    return AcpAccountDraft(
      mode: AcpAccountDraftMode.edit,
      accountId: account.accountId,
      template:
          template ??
          AcpAccountTemplateView(
            provider: account.provider,
            displayName: account.name,
          ),
      name: account.name,
      program: account.program,
      args: account.args,
      connectionRevision: account.connectionRevision,
    );
  }

  final AcpAccountDraftMode mode;
  final String accountId;
  final AcpAccountTemplateView template;
  final String name;
  final String program;
  final List<String> args;
  final int connectionRevision;

  bool get isCreate => mode == AcpAccountDraftMode.create;

  AcpAccountDraft copyWith({
    String? name,
    String? program,
    List<String>? args,
  }) {
    return AcpAccountDraft(
      mode: mode,
      accountId: accountId,
      template: template,
      name: name ?? this.name,
      program: program ?? this.program,
      args: args ?? this.args,
      connectionRevision: connectionRevision,
    );
  }

  /// 提交给 Client 的写入意图；空 argv 项被丢弃，避免产生空参数。
  AcpAccountUpdateView toUpdate() => AcpAccountUpdateView(
    accountId: accountId,
    name: name.trim().isEmpty ? template.displayName : name.trim(),
    provider: template.provider,
    program: program.trim(),
    args: [
      for (final arg in args)
        if (arg.trim().isNotEmpty) arg,
    ],
  );
}
