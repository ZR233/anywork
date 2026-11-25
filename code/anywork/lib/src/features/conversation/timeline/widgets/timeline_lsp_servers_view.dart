part of 'timeline_lsp_tool_view.dart';

class _LspCapabilitiesCard extends StatelessWidget {
  const _LspCapabilitiesCard({required this.capabilities});

  final TimelineLspCapabilitiesPresentation capabilities;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final header = Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _LspBadge(
          icon: Icons.extension_outlined,
          label: l10n.timelineLspCapabilitiesTitle,
          tone: StudioTone.brand,
        ),
        if (capabilities.fallbackText == null)
          _LspBadge(
            label: l10n.timelineLspCapabilitiesSummary(
              capabilities.servers.length,
            ),
            outlined: true,
          ),
      ],
    );

    final Widget body;
    if (capabilities.fallbackText case final fallback?) {
      body = _LspPlainFallbackView(text: fallback);
    } else if (capabilities.servers.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          l10n.timelineLspCapabilitiesEmpty,
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < capabilities.servers.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: context.colors.outlineVariant.withValues(alpha: 0.65),
              ),
            _CapabilityServerSection(server: capabilities.servers[i]),
          ],
        ],
      );
    }

    return _LspSurfaceCard(
      header: header,
      body: body,
      omittedBytes: capabilities.previewOmittedBytes,
    );
  }
}

class _CapabilityServerSection extends StatelessWidget {
  const _CapabilityServerSection({required this.server});

  final TimelineLspCapabilityServer server;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LspServerHeader(
            id: server.id,
            displayName: server.displayName,
            languageIds: server.languageIds,
            status: _LspBadge(
              icon: server.ready ? Icons.check_circle_outline : null,
              label: server.ready
                  ? l10n.settingsLspPhaseReady
                  : _availabilityLabel(l10n, server.availability),
              tone: server.ready ? StudioTone.success : StudioTone.neutral,
            ),
          ),
          if (server.operations.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final op in server.operations)
                  _LspBadge(
                    icon: _lspOpIcon(op.operation),
                    label: timelineLspOperationLabel(
                      l10n,
                      op.operation,
                      raw: op.raw,
                    ),
                    outlined: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LspStatusCard extends StatelessWidget {
  const _LspStatusCard({required this.status});

  final TimelineLspStatusPresentation status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final readyCount = status.servers
        .where(
          (server) =>
              server.phase == 'ready' && server.availability == 'available',
        )
        .length;
    final configDir = _relativeWorkspacePath(
      status.configurationDirectory,
      status.workspaceRoot,
    );

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LspBadge(
              icon: Icons.dns_outlined,
              label: l10n.timelineLspStatusTitle,
              tone: StudioTone.brand,
            ),
            if (status.fallbackText == null && status.servers.isNotEmpty)
              _LspBadge(
                label: l10n.timelineLspStatusSummary(
                  readyCount,
                  status.servers.length,
                ),
                tone: readyCount == status.servers.length
                    ? StudioTone.success
                    : StudioTone.neutral,
                outlined: readyCount != status.servers.length,
              ),
            if (configDir != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      configDir,
                      style: context.text.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFamily: studioCodeFontFamily,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    final Widget body;
    if (status.fallbackText case final fallback?) {
      body = _LspPlainFallbackView(text: fallback);
    } else if (status.servers.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          l10n.timelineLspStatusEmpty,
          style: context.text.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < status.servers.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.65),
              ),
            _StatusServerSection(
              server: status.servers[i],
              workspaceRoot: status.workspaceRoot,
            ),
          ],
        ],
      );
    }

    return _LspSurfaceCard(
      header: header,
      body: body,
      omittedBytes: status.previewOmittedBytes,
    );
  }
}

class _StatusServerSection extends StatelessWidget {
  const _StatusServerSection({
    required this.server,
    required this.workspaceRoot,
  });

  final TimelineLspServerStatusItem server;
  final String? workspaceRoot;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.colors;
    final (statusLabel, statusTone, statusIcon) = _serverStatusBadge(
      l10n,
      server,
    );
    final configPath = _relativeWorkspacePath(
      server.configurationPath,
      workspaceRoot,
    );
    final activeActivity = server.activity != 'idle';
    final activityDetail = [
      if (server.activityTitle case final title? when title.isNotEmpty) title,
      if (server.activityMessage case final msg? when msg.isNotEmpty) msg,
    ].join(' · ');
    final infoMessage =
        (server.message != null && server.message != server.lastError)
        ? server.message
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LspServerHeader(
            id: server.id,
            displayName: server.displayName,
            languageIds: server.languageIds,
            status: _LspBadge(
              icon: statusIcon,
              label: statusLabel,
              tone: statusTone,
            ),
          ),
          if (activeActivity) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLowest,
                borderRadius: const BorderRadius.all(
                  Radius.circular(StudioRadii.xs),
                ),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            server.activity == 'indexing'
                                ? Icons.manage_search_outlined
                                : Icons.sync,
                            size: 13.5,
                            color: context.statusColors.activeIndicator,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _activityLabel(l10n, server),
                            style: context.text.labelSmall?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (activityDetail.isNotEmpty)
                        Text(
                          activityDetail,
                          style: context.text.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  if (server.activityPercentage case final pct?) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: const BorderRadius.all(
                        Radius.circular(StudioRadii.pill),
                      ),
                      child: LinearProgressIndicator(
                        value: (pct.clamp(0, 100)) / 100.0,
                        minHeight: 3,
                        color: context.statusColors.activeIndicator,
                        backgroundColor: colors.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.tune_outlined,
                size: 12.5,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  configPath ?? l10n.settingsLspConfigurationMissing,
                  style: context.text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: configPath != null
                        ? studioCodeFontFamily
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (infoMessage != null) ...[
            const SizedBox(height: 5),
            Text(
              infoMessage,
              style: context.text.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (server.lastError case final error? when error.isNotEmpty) ...[
            const SizedBox(height: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: StudioTone.error
                    .background(context)
                    .withValues(alpha: 0.65),
                borderRadius: const BorderRadius.all(
                  Radius.circular(StudioRadii.xs),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1.5),
                    child: Icon(
                      Icons.error_outline,
                      size: 14,
                      color: StudioTone.error.foreground(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: context.text.bodySmall?.copyWith(
                        color: StudioTone.error.foreground(context),
                        fontFamily: studioCodeFontFamily,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static (String, StudioTone, IconData) _serverStatusBadge(
    AppLocalizations l10n,
    TimelineLspServerStatusItem server,
  ) {
    if (server.availability == 'missingCommand') {
      return (
        l10n.timelineLspStateMissingCommand,
        StudioTone.error,
        Icons.error_outline,
      );
    }
    if (server.phase == 'failed' || server.availability == 'unavailable') {
      return (
        server.phase == 'failed'
            ? l10n.settingsLspPhaseFailed
            : l10n.settingsStateUnavailable,
        StudioTone.error,
        Icons.error_outline,
      );
    }
    if (server.phase == 'disabled' || server.availability == 'disabled') {
      return (
        l10n.settingsLspPhaseDisabled,
        StudioTone.neutral,
        Icons.block_outlined,
      );
    }
    if (server.phase == 'stopped') {
      return (
        l10n.settingsLspPhaseStopped,
        StudioTone.neutral,
        Icons.stop_circle_outlined,
      );
    }
    if (server.phase == 'ready' && server.availability == 'available') {
      return (
        l10n.settingsLspPhaseReady,
        StudioTone.success,
        Icons.check_circle_outline,
      );
    }
    final phaseLabel = switch (server.phase) {
      'loading' => l10n.settingsLspPhaseLoading,
      'probing' => l10n.settingsLspPhaseProbing,
      'starting' => l10n.settingsLspPhaseStarting,
      'initializing' => l10n.settingsLspPhaseInitializing,
      _ => _availabilityLabel(l10n, server.availability),
    };
    return (phaseLabel, StudioTone.active, Icons.sync);
  }

  static String _activityLabel(
    AppLocalizations l10n,
    TimelineLspServerStatusItem server,
  ) {
    final base = switch (server.activity) {
      'indexing' => l10n.settingsLspActivityIndexing,
      'busy' => l10n.settingsLspActivityBusy,
      _ => l10n.settingsLspActivityIdle,
    };
    final pct = server.activityPercentage;
    if (pct == null) return base;
    return '$base · ${l10n.statusLspActivityPercentage(pct)}';
  }
}

String _availabilityLabel(AppLocalizations l10n, String availability) =>
    switch (availability) {
      'checking' => l10n.settingsStateChecking,
      'available' => l10n.settingsStateAvailable,
      'unavailable' => l10n.settingsStateUnavailable,
      'missingCommand' => l10n.timelineLspStateMissingCommand,
      'disabled' => l10n.settingsStateDisabled,
      _ => availability,
    };

String? _relativeWorkspacePath(String? path, String? workspaceRoot) {
  if (path == null || path.trim().isEmpty) return null;
  final trimmedPath = path.trim();
  if (workspaceRoot == null || workspaceRoot.trim().isEmpty) return trimmedPath;
  final root = workspaceRoot.trim().replaceAll(RegExp(r'[/\\]+$'), '');
  if (root.isEmpty) return trimmedPath;
  if (trimmedPath.startsWith('$root/') || trimmedPath.startsWith('$root\\')) {
    final relative = trimmedPath.substring(root.length + 1);
    return relative.isEmpty ? trimmedPath : relative;
  }
  return trimmedPath;
}

// Shared identity and languages; each server result supplies its own status.
class _LspServerHeader extends StatelessWidget {
  const _LspServerHeader({
    required this.id,
    required this.displayName,
    required this.languageIds,
    required this.status,
  });

  final String id;
  final String displayName;
  final List<String> languageIds;
  final Widget status;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        displayName,
        style: context.text.bodySmall?.copyWith(
          color: context.colors.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (id.isNotEmpty && id != displayName)
        Text(
          id,
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontFamily: studioCodeFontFamily,
          ),
        ),
      status,
      for (final language in languageIds)
        _LspBadge(label: language, monospace: true, outlined: true),
    ],
  );
}
