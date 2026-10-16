enum SshPasswordAction { preserve, replace, clear }

class SshPasswordUpdate {
  const SshPasswordUpdate._(this.action, this.value);

  const SshPasswordUpdate.preserve() : this._(SshPasswordAction.preserve, null);

  const SshPasswordUpdate.replace(String value)
    : this._(SshPasswordAction.replace, value);

  const SshPasswordUpdate.clear() : this._(SshPasswordAction.clear, null);

  final SshPasswordAction action;
  final String? value;
}

/// `~/.ssh/config` 中的一个 Host 条目；别名即服务器身份。
class SshServer {
  const SshServer({
    required this.alias,
    required this.hostName,
    required this.port,
    required this.username,
    required this.managed,
    this.identityFile,
    this.hasPassword = false,
  });

  final String alias;
  final String hostName;
  final int port;
  final String username;
  final String? identityFile;

  /// 是否为 anywork 管理块；用户手写条目只读，不可编辑或删除。
  final bool managed;

  /// 系统凭据库或当前会话是否已配置 SSH 密码（不携带明文）。
  final bool hasPassword;
}

class SaveSshServerCommand {
  const SaveSshServerCommand({
    required this.alias,
    required this.hostName,
    required this.port,
    required this.username,
    this.identityFile,
    this.password = const SshPasswordUpdate.preserve(),
  });

  final String alias;
  final String hostName;
  final int port;
  final String username;
  final String? identityFile;
  final SshPasswordUpdate password;
}

class AuthenticateSshServerCommand {
  const AuthenticateSshServerCommand({
    required this.alias,
    required this.password,
    this.rememberPassword = true,
  });

  final String alias;
  final String password;
  final bool rememberPassword;
}

/// 判断异常是否表示 SSH 认证失败（需要输入或更新密码）。
bool isSshAuthenticationError(Object error) {
  final text = error.toString();
  return text.contains('SSH authentication required or failed') ||
      text.contains('sshAuthFailed') ||
      text.contains('authenticationFailed') ||
      text.contains('Permission denied');
}

class SshConnectionView {
  const SshConnectionView({
    required this.alias,
    required this.state,
    this.helperVersion,
    this.architecture,
    this.attempt,
    this.delaySeconds,
    this.errorCode,
    this.errorMessage,
  });

  final String alias;
  final String state;
  final String? helperVersion;
  final String? architecture;
  final int? attempt;
  final int? delaySeconds;
  final String? errorCode;
  final String? errorMessage;
}

class RemoteDirectoryListing {
  const RemoteDirectoryListing({
    required this.path,
    required this.entries,
    this.parent,
  });

  final String path;
  final String? parent;
  final List<RemoteDirectoryEntry> entries;
}

class RemoteDirectoryEntry {
  const RemoteDirectoryEntry({required this.name, required this.path});
  final String name;
  final String path;
}
