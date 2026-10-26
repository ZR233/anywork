import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'selector_configuration_port.dart';
import 'selector_conversation_port.dart';

/// A declared native response independent of feed publications. Tests send the
/// response before/after their explicitly declared canonical versions to prove
/// the real VM does not optimistically promote this DTO to current state.
ThreadModelRouteCommandReply selectorRouteReply(
  SelectorRouteCall call,
  ThreadModelRoute route, {
  int settingsRevision = 1,
  bool saved = false,
}) => ThreadModelRouteCommandReply(
  runtime: ThreadRuntimeSnapshot(
    threadId: call.threadId,
    modelRoute: route,
    usage: ThreadRuntimeUsage(
      hasIncompleteUsage: false,
      modelId: route.modelId,
      contextWindow: 4096,
      maxContextWindow: 4096,
      autoCompactLimit: 2048,
      latestContextTokens: 0,
      promptTokens: 0,
      completionTokens: 0,
      cachedPromptTokens: 0,
      cacheWriteTokens: 0,
      reasoningTokens: 0,
      inferenceCount: 0,
      totalTokens: 0,
      cacheUsage: const CacheUsageSummary(
        inputTokens: 0,
        cacheReadTokens: 0,
        hitRate: null,
        hasIncompleteUsage: false,
      ),
      estimatedCosts: [],
      estimatedCacheSavings: [],
      hasUnpricedUsage: false,
      promptGeneration: null,
      promptCachePolicy: null,
      prefixChangedReason: null,
      updatedAt: 1,
    ),
    liveUsage: null,
    turnCompletionTokens: 0,
    turnResponseMillis: 0,
    todo: null,
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
    progress: null,
    mcpHealth: null,
    workflow: null,
    plan: null,
    updatedAt: 1,
  ),
  settings: ThreadSettingsSnapshot(
    config: ThreadSettingsConfigSnapshot(
      revision: settingsRevision,
      updatedAt: 1,
      settings: ThreadSettingsValue(
        defaultAccountId: 'account-0',
        accounts: [],
        modeModelRoutes: [
          ModeModelRoute(
            modeId: 'mode.simple',
            accountId: route.accountId,
            modelId: route.modelId,
            effort: route.effort!,
          ),
        ],
        roles: [],
        permissionMode: 'default',
        instructions: InstructionsSettings(
          baseOverride: '',
          developer: '',
          user: '',
          projectDocMaxBytes: 0,
          projectDocFallbackFilenames: [],
        ),
        skills: SkillsSettings(
          enabled: false,
          autoLearn: false,
          systemEnabled: false,
          projectDir: '',
          userDir: '',
          externalDirs: [],
          disabled: [],
          autoLearnMinToolCalls: 0,
        ),
        mcpServers: [],
        general: GeneralSettings(
          followActiveTurn: false,
          compactTimeline: false,
          sidebarWidth: 336,
          pinnedThreadIds: [],
          pinnedProjectIds: [],
        ),
        delegation: selectorDefaults,
        webSearch: ThreadWebSearchSettings(
          configuration: WebSearchConfiguration(
            configuredMode: 'off',
            contextSize: null,
            allowedDomains: [],
            country: null,
            region: null,
            city: null,
            timezone: null,
          ),
          effective: const EffectiveWebSearch(
            effectiveMode: 'off',
            availability: 'unavailable',
            accountId: null,
            modelId: null,
          ),
        ),
        deepseekWebSearch: const ThreadDeepSeekSearchSettings(
          configuration: DeepSeekSearchConfiguration(
            configuredEnabled: false,
            configuredFetchEnabled: false,
          ),
          effective: EffectiveDeepSeekSearch(
            effectiveEnabled: false,
            effectiveFetchEnabled: false,
            availability: 'unavailable',
            accountId: null,
          ),
        ),
      ),
    ),
    catalog: ThreadSettingsCatalogSnapshot(
      revision: 1,
      updatedAt: 1,
      accounts: [],
    ),
  ),
  modeDefaultSaved: saved,
  warning: null,
  receipt: CommitReceipt(
    operationId: call.operationId,
    disposition: CommitDisposition.applied,
    targets: [
      ResourceStamp(
        resourceKey: 'thread-route:${call.threadId}',
        ownerEpoch: 'selector-native',
        revision: route.revision,
      ),
      if (saved)
        ResourceStamp(
          resourceKey: 'settings',
          ownerEpoch: 'selector-native',
          revision: settingsRevision,
        ),
    ],
    effect: EffectPoint.nextTurn,
    requiresIdentityObservation: true,
  ),
);
