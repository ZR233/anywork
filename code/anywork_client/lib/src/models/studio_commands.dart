import 'delegation_models.dart';
import 'settings_models.dart';

enum AccountSecretAction { preserve, replace, clear }

class AccountSecretCommand {
  const AccountSecretCommand._(this.action, this.value);

  const AccountSecretCommand.preserve()
    : this._(AccountSecretAction.preserve, null);

  const AccountSecretCommand.replace(String value)
    : this._(AccountSecretAction.replace, value);

  const AccountSecretCommand.clear() : this._(AccountSecretAction.clear, null);

  final AccountSecretAction action;
  final String? value;
}

class AccountModelCommand {
  const AccountModelCommand({
    required this.modelId,
    required this.displayName,
    required this.wireApi,
    required this.contextWindow,
    required this.maxOutputTokens,
  });
  final String modelId;
  final String displayName;
  final String wireApi;
  final int? contextWindow;
  final int? maxOutputTokens;
}

class AccountModelConnectionCommand {
  const AccountModelConnectionCommand({
    required this.modelId,
    required this.connectionMode,
  });

  final String modelId;
  final String connectionMode;
}

/// 某模型上下文压缩阈值用户覆盖的命令项；`limit` 为正整数 tokens。
class AccountModelAutoCompactCommand {
  const AccountModelAutoCompactCommand({
    required this.modelId,
    required this.limit,
  });

  final String modelId;
  final int limit;
}

/// One canonical settings field/resource mutation.
///
/// Each command carries only the value the user changed. The repository and
/// Bridge never receive a stale sibling settings snapshot to merge back.
sealed class SettingsFieldCommand {
  const SettingsFieldCommand();
}

final class DelegationModeCommand extends SettingsFieldCommand {
  const DelegationModeCommand(this.value);
  final DelegationMode value;
}

final class DelegationPreferenceCommand extends SettingsFieldCommand {
  const DelegationPreferenceCommand(this.value);
  final DelegationPreference value;
}

class InstructionBaseOverrideCommand extends SettingsFieldCommand {
  const InstructionBaseOverrideCommand(this.value);
  final String value;
}

class InstructionDeveloperCommand extends SettingsFieldCommand {
  const InstructionDeveloperCommand(this.value);
  final String value;
}

class InstructionUserCommand extends SettingsFieldCommand {
  const InstructionUserCommand(this.value);
  final String value;
}

class ProjectDocMaxBytesCommand extends SettingsFieldCommand {
  const ProjectDocMaxBytesCommand(this.value);
  final int value;
}

class ProjectDocFallbackFilenamesCommand extends SettingsFieldCommand {
  const ProjectDocFallbackFilenamesCommand(this.value);
  final List<String> value;
}

class SkillsEnabledCommand extends SettingsFieldCommand {
  const SkillsEnabledCommand(this.value);
  final bool value;
}

class SkillsAutoLearnCommand extends SettingsFieldCommand {
  const SkillsAutoLearnCommand(this.value);
  final bool value;
}

class SkillsSystemEnabledCommand extends SettingsFieldCommand {
  const SkillsSystemEnabledCommand(this.value);
  final bool value;
}

class SkillsProjectDirCommand extends SettingsFieldCommand {
  const SkillsProjectDirCommand(this.value);
  final String value;
}

class SkillsUserDirCommand extends SettingsFieldCommand {
  const SkillsUserDirCommand(this.value);
  final String value;
}

class SkillsExternalDirsCommand extends SettingsFieldCommand {
  const SkillsExternalDirsCommand(this.value);
  final List<String> value;
}

class SkillsDisabledCommand extends SettingsFieldCommand {
  const SkillsDisabledCommand(this.value);
  final List<String> value;
}

class SkillsAutoLearnMinToolCallsCommand extends SettingsFieldCommand {
  const SkillsAutoLearnMinToolCallsCommand(this.value);
  final int value;
}

class McpServerEnabledCommand extends SettingsFieldCommand {
  const McpServerEnabledCommand({required this.id, required this.value});
  final String id;
  final bool value;
}

class McpServerTransportCommand extends SettingsFieldCommand {
  const McpServerTransportCommand({required this.id, required this.value});
  final String id;
  final String value;
}

class McpServerEndpointCommand extends SettingsFieldCommand {
  const McpServerEndpointCommand({required this.id, required this.value});
  final String id;
  final String value;
}

class GeneralFollowActiveTurnCommand extends SettingsFieldCommand {
  const GeneralFollowActiveTurnCommand(this.value);
  final bool value;
}

class GeneralCompactTimelineCommand extends SettingsFieldCommand {
  const GeneralCompactTimelineCommand(this.value);
  final bool value;
}

class GeneralLanguageCommand extends SettingsFieldCommand {
  const GeneralLanguageCommand(this.value);
  final UiLanguage value;
}

class GeneralSidebarWidthCommand extends SettingsFieldCommand {
  const GeneralSidebarWidthCommand(this.value);
  final int? value;
}

class GeneralPinnedThreadIdsCommand extends SettingsFieldCommand {
  const GeneralPinnedThreadIdsCommand(this.value);
  final List<String> value;
}

class GeneralPinnedProjectIdsCommand extends SettingsFieldCommand {
  const GeneralPinnedProjectIdsCommand(this.value);
  final List<String> value;
}

class WebSearchModeCommand extends SettingsFieldCommand {
  const WebSearchModeCommand(this.value);
  final String value;
}

class WebSearchContextSizeCommand extends SettingsFieldCommand {
  const WebSearchContextSizeCommand(this.value);
  final String? value;
}

class WebSearchAllowedDomainsCommand extends SettingsFieldCommand {
  const WebSearchAllowedDomainsCommand(this.value);
  final List<String> value;
}

class WebSearchCountryCommand extends SettingsFieldCommand {
  const WebSearchCountryCommand(this.value);
  final String? value;
}

class WebSearchRegionCommand extends SettingsFieldCommand {
  const WebSearchRegionCommand(this.value);
  final String? value;
}

class WebSearchCityCommand extends SettingsFieldCommand {
  const WebSearchCityCommand(this.value);
  final String? value;
}

class WebSearchTimezoneCommand extends SettingsFieldCommand {
  const WebSearchTimezoneCommand(this.value);
  final String? value;
}

class DeepSeekWebSearchEnabledCommand extends SettingsFieldCommand {
  const DeepSeekWebSearchEnabledCommand(this.value);
  final bool value;
}

class DeepSeekWebFetchEnabledCommand extends SettingsFieldCommand {
  const DeepSeekWebFetchEnabledCommand(this.value);
  final bool value;
}

class ModeModelCommand extends SettingsFieldCommand {
  const ModeModelCommand({
    required this.modeId,
    required this.accountId,
    required this.modelId,
  });
  final String modeId;
  final String accountId;
  final String modelId;
}

class ModeReasoningEffortCommand extends SettingsFieldCommand {
  const ModeReasoningEffortCommand({required this.modeId, this.effort});
  final String modeId;
  final String? effort;
}

class RoleModelCommand extends SettingsFieldCommand {
  const RoleModelCommand({
    required this.role,
    required this.accountId,
    required this.modelId,
  });
  final String role;
  final String accountId;
  final String modelId;
}

class RoleReasoningEffortCommand extends SettingsFieldCommand {
  const RoleReasoningEffortCommand({required this.role, this.effort});
  final String role;
  final String? effort;
}
