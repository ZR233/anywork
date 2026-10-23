import 'package:anywork_client/configuration.dart';
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';

String agentWorkspaceLabel(BuildContext context, AgentWorkspaceMode value) => switch (value) {
  AgentWorkspaceMode.unrestricted => context.l10n.settingsAgentWorkspaceModeUnrestricted,
  AgentWorkspaceMode.directory => context.l10n.settingsAgentWorkspaceModeDirectory,
  AgentWorkspaceMode.worktree => context.l10n.settingsAgentWorkspaceModeWorktree,
  AgentWorkspaceMode.review => context.l10n.settingsAgentWorkspaceModeReview,
};
