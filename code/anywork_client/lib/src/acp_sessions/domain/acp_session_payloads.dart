import 'acp_values.dart';

enum AcpConfigCategoryKindView { mode, model, modelConfig, thoughtLevel, other }

final class AcpConfigCategoryView {
  const AcpConfigCategoryView.known(this.kind)
    : other = null,
      assert(kind != AcpConfigCategoryKindView.other);
  const AcpConfigCategoryView.other(this.other)
    : kind = AcpConfigCategoryKindView.other;
  final AcpConfigCategoryKindView kind;
  final String? other;
}

final class AcpSessionConfigOptionView {
  const AcpSessionConfigOptionView({
    required this.id,
    required this.name,
    required this.kind,
    this.description,
    this.category,
    this.meta,
  });
  final AcpConfigId id;
  final String name;
  final String? description;
  final AcpConfigCategoryView? category;
  final AcpSessionConfigKindView kind;
  final AcpJsonObject? meta;
}

sealed class AcpSessionConfigKindView {
  const AcpSessionConfigKindView();
}

final class AcpSelectConfigView extends AcpSessionConfigKindView {
  const AcpSelectConfigView({
    required this.currentValue,
    required this.options,
  });
  final AcpConfigValueId currentValue;
  final AcpSelectOptionsView options;
}

final class AcpBooleanConfigView extends AcpSessionConfigKindView {
  const AcpBooleanConfigView({required this.currentValue});
  final bool currentValue;
}

sealed class AcpSelectOptionsView {
  const AcpSelectOptionsView();
}

final class AcpUngroupedOptionsView extends AcpSelectOptionsView {
  AcpUngroupedOptionsView(Iterable<AcpSelectOptionView> options)
    : options = List.unmodifiable(options);
  final List<AcpSelectOptionView> options;
}

final class AcpGroupedOptionsView extends AcpSelectOptionsView {
  AcpGroupedOptionsView(Iterable<AcpSelectGroupView> groups)
    : groups = List.unmodifiable(groups);
  final List<AcpSelectGroupView> groups;
}

final class AcpSelectOptionView {
  const AcpSelectOptionView({
    required this.value,
    required this.name,
    this.description,
    this.meta,
  });
  final AcpConfigValueId value;
  final String name;
  final String? description;
  final AcpJsonObject? meta;
}

final class AcpSelectGroupView {
  AcpSelectGroupView({
    required this.group,
    required this.name,
    required Iterable<AcpSelectOptionView> options,
    this.meta,
  }) : options = List.unmodifiable(options);
  final AcpConfigGroupId group;
  final String name;
  final List<AcpSelectOptionView> options;
  final AcpJsonObject? meta;
}

sealed class AcpSessionConfigValueView {
  const AcpSessionConfigValueView();
}

final class AcpBooleanConfigValueView extends AcpSessionConfigValueView {
  const AcpBooleanConfigValueView(this.value);
  final bool value;
}

final class AcpSelectConfigValueView extends AcpSessionConfigValueView {
  const AcpSelectConfigValueView(this.value);
  final AcpConfigValueId value;
}

final class AcpConfiguredResponseView {
  AcpConfiguredResponseView({
    required Iterable<AcpSessionConfigOptionView> configOptions,
    this.meta,
  }) : configOptions = List.unmodifiable(configOptions);
  final List<AcpSessionConfigOptionView> configOptions;
  final AcpJsonObject? meta;
}

final class AcpSessionModeView {
  const AcpSessionModeView({
    required this.id,
    required this.name,
    this.description,
    this.meta,
  });
  final AcpModeId id;
  final String name;
  final String? description;
  final AcpJsonObject? meta;
}

final class AcpSessionModeStateView {
  AcpSessionModeStateView({
    required this.currentModeId,
    required Iterable<AcpSessionModeView> availableModes,
    this.meta,
  }) : availableModes = List.unmodifiable(availableModes);
  final AcpModeId currentModeId;
  final List<AcpSessionModeView> availableModes;
  final AcpJsonObject? meta;
}

final class AcpNewSessionResponseView {
  AcpNewSessionResponseView({
    required this.sessionId,
    this.modes,
    Iterable<AcpSessionConfigOptionView>? configOptions,
    this.meta,
  }) : configOptions = configOptions == null
           ? null
           : List.unmodifiable(configOptions);
  final AcpRemoteSessionId sessionId;
  final AcpSessionModeStateView? modes;
  final List<AcpSessionConfigOptionView>? configOptions;
  final AcpJsonObject? meta;
}

final class AcpListSessionsRequestView {
  const AcpListSessionsRequestView({this.cwd, this.cursor, this.meta});
  final String? cwd;
  final String? cursor;
  final AcpJsonObject? meta;
}

final class AcpSessionInfoView {
  AcpSessionInfoView({
    required this.sessionId,
    required this.cwd,
    Iterable<String> additionalDirectories = const [],
    this.title,
    this.updatedAt,
    this.meta,
  }) : additionalDirectories = List.unmodifiable(additionalDirectories);
  final AcpRemoteSessionId sessionId;
  final String cwd;
  final List<String> additionalDirectories;
  final String? title;
  final String? updatedAt;
  final AcpJsonObject? meta;
}

final class AcpListSessionsResponseView {
  AcpListSessionsResponseView({
    required Iterable<AcpSessionInfoView> sessions,
    this.nextCursor,
    this.meta,
  }) : sessions = List.unmodifiable(sessions);
  final List<AcpSessionInfoView> sessions;
  final String? nextCursor;
  final AcpJsonObject? meta;
}

enum AcpStopReasonView {
  endTurn,
  maxTokens,
  maxTurnRequests,
  refusal,
  cancelled,
}

final class AcpPromptResponseView {
  const AcpPromptResponseView({required this.stopReason, this.meta});
  final AcpStopReasonView stopReason;
  final AcpJsonObject? meta;
}
