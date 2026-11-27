import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/chat_item_presentation.dart';
import '../state/timeline_display_unit.dart';
import '../state/tool_presentation.dart';
import '../widgets/timeline_activity_row.dart';
import 'support/tool_detail_values.dart';
import 'support/tool_status_labels.dart';

/// Markdown renderer callback injected by parent timeline views.
typedef TimelineToolMarkdownBuilder = Widget Function(String id, String text);

/// Lightweight context evaluated by [TimelineToolMatcher] to decide whether an
/// adapter handles a given tool item.
@immutable
class TimelineToolMatchContext {
  const TimelineToolMatchContext({
    required this.toolName,
    this.presentationContract,
    this.hasWaitPayload = false,
  });

  factory TimelineToolMatchContext.fromPresentation(
    TimelineToolPresentation item,
  ) {
    return TimelineToolMatchContext(
      toolName: item.name,
      presentationContract: item.presentationContract,
      hasWaitPayload: item.wait != null,
    );
  }

  factory TimelineToolMatchContext.fromChatItem(ChatItemPresentation item) {
    final invocation = item.data['invocation'];
    final name =
        invocation is Map<String, Object?> && invocation['name'] is String
        ? invocation['name'] as String
        : '';
    return TimelineToolMatchContext(
      toolName: name,
      presentationContract: item.presentationContract,
      hasWaitPayload: item.data['wait'] != null,
    );
  }

  /// Protocol contract identifier (for example `builtin.exec@2`).
  final String? presentationContract;

  /// Raw tool name from invocation or live atom.
  final String toolName;

  /// Whether a structured wait payload accompanies the item (used for live
  /// uncontracted wait/sleep atoms).
  final bool hasWaitPayload;
}

/// Declarative matching rule declared by a single [TimelineToolItemAdapter].
@immutable
abstract class TimelineToolMatcher {
  const TimelineToolMatcher();

  /// Matches an exact `presentationContract` value.
  const factory TimelineToolMatcher.contract(String contract) =
      _ExactContractMatcher;

  /// Matches any exact contract in [contracts].
  const factory TimelineToolMatcher.contracts(Set<String> contracts) =
      _ContractSetMatcher;

  /// Matches when `presentationContract` starts with [prefix].
  const factory TimelineToolMatcher.contractPrefix(String prefix) =
      _ContractPrefixMatcher;

  /// Matches by [toolName], optionally requiring empty/absent contract or a
  /// wait payload.
  const factory TimelineToolMatcher.toolName(
    String toolName, {
    bool requireEmptyContract,
    bool requireWaitPayload,
  }) = _ToolNameMatcher;

  /// Matches when any child matcher succeeds.
  const factory TimelineToolMatcher.anyOf(List<TimelineToolMatcher> matchers) =
      _AnyOfMatcher;

  /// Matches using a custom predicate.
  const factory TimelineToolMatcher.custom(
    bool Function(TimelineToolMatchContext context) predicate, {
    Set<String> exactContracts,
  }) = _CustomMatcher;

  /// Exact contract strings claimed by this matcher for duplicate validation
  /// and direct index lookup.
  Set<String> get exactContracts => const <String>{};

  bool matches(TimelineToolMatchContext context);
}

final class _ExactContractMatcher extends TimelineToolMatcher {
  const _ExactContractMatcher(this.contract);

  final String contract;

  @override
  Set<String> get exactContracts => {contract};

  @override
  bool matches(TimelineToolMatchContext context) =>
      context.presentationContract == contract;
}

final class _ContractSetMatcher extends TimelineToolMatcher {
  const _ContractSetMatcher(this.contracts);

  final Set<String> contracts;

  @override
  Set<String> get exactContracts => contracts;

  @override
  bool matches(TimelineToolMatchContext context) =>
      contracts.contains(context.presentationContract);
}

final class _ContractPrefixMatcher extends TimelineToolMatcher {
  const _ContractPrefixMatcher(this.prefix);

  final String prefix;

  @override
  bool matches(TimelineToolMatchContext context) {
    final contract = context.presentationContract;
    return contract != null && contract.startsWith(prefix);
  }
}

final class _ToolNameMatcher extends TimelineToolMatcher {
  const _ToolNameMatcher(
    this.toolName, {
    this.requireEmptyContract = false,
    this.requireWaitPayload = false,
  });

  final String toolName;
  final bool requireEmptyContract;
  final bool requireWaitPayload;

  @override
  bool matches(TimelineToolMatchContext context) {
    if (context.toolName != toolName) return false;
    if (requireEmptyContract &&
        context.presentationContract != null &&
        context.presentationContract!.isNotEmpty) {
      return false;
    }
    if (requireWaitPayload && !context.hasWaitPayload) {
      return false;
    }
    return true;
  }
}

final class _AnyOfMatcher extends TimelineToolMatcher {
  const _AnyOfMatcher(this.matchers);

  final List<TimelineToolMatcher> matchers;

  @override
  Set<String> get exactContracts {
    final result = <String>{};
    for (final matcher in matchers) {
      result.addAll(matcher.exactContracts);
    }
    return result;
  }

  @override
  bool matches(TimelineToolMatchContext context) {
    for (final matcher in matchers) {
      if (matcher.matches(context)) return true;
    }
    return false;
  }
}

final class _CustomMatcher extends TimelineToolMatcher {
  const _CustomMatcher(
    this.predicate, {
    this.exactContracts = const <String>{},
  });

  final bool Function(TimelineToolMatchContext context) predicate;

  @override
  final Set<String> exactContracts;

  @override
  bool matches(TimelineToolMatchContext context) => predicate(context);
}

/// Snapshot passed to custom stateful icon builders inside the 20px icon slot.
@immutable
class TimelineToolRowIconState {
  const TimelineToolRowIconState({
    required this.active,
    required this.expanded,
    required this.isIssue,
    required this.isStopped,
    required this.staticObservation,
    required this.statusString,
  });

  final bool active;
  final bool expanded;
  final bool isIssue;
  final bool isStopped;
  final bool staticObservation;
  final String statusString;
}

/// Widget builder rendering a stateful or animated custom icon inside
/// [TimelineActivityRow]'s leading icon slot.
typedef TimelineToolIconWidgetBuilder = Widget Function(
  BuildContext context,
  TimelineToolRowIconState state,
);

/// Icon configuration for a single-line tool activity row.
///
/// Supports both static/indicator-driven vector icons via [TimelineToolIcon.data]
/// and arbitrary stateful widgets via [TimelineToolIcon.widget].
sealed class TimelineToolIcon {
  const TimelineToolIcon();

  const factory TimelineToolIcon.data(
    IconData icon, {
    Color? color,
    TimelineActivityIndicatorStyle activeIndicatorStyle,
    TimelineActivityIndicatorStyle idleIndicatorStyle,
    bool preserveWhenStopped,
    bool preserveWhenIssue,
  }) = TimelineToolIconData;

  const factory TimelineToolIcon.widget(
    TimelineToolIconWidgetBuilder builder, {
    IconData fallbackIcon,
  }) = TimelineToolIconWidget;
}

final class TimelineToolIconData extends TimelineToolIcon {
  const TimelineToolIconData(
    this.icon, {
    this.color,
    this.activeIndicatorStyle = TimelineActivityIndicatorStyle.restingCat,
    this.idleIndicatorStyle = TimelineActivityIndicatorStyle.restingCat,
    this.preserveWhenStopped = false,
    this.preserveWhenIssue = false,
  });

  final IconData icon;
  final Color? color;
  final TimelineActivityIndicatorStyle activeIndicatorStyle;
  final TimelineActivityIndicatorStyle idleIndicatorStyle;
  final bool preserveWhenStopped;
  final bool preserveWhenIssue;
}

final class TimelineToolIconWidget extends TimelineToolIcon {
  const TimelineToolIconWidget(
    this.builder, {
    this.fallbackIcon = Icons.build_outlined,
  });

  final TimelineToolIconWidgetBuilder builder;
  final IconData fallbackIcon;
}

/// Collapsed single-line visual presentation produced by a tool adapter.
@immutable
class TimelineToolRowSummary {
  const TimelineToolRowSummary({
    required this.icon,
    required this.label,
    this.meta,
    this.active = false,
    this.isIssue = false,
    this.isStopped = false,
    this.cardKey,
    this.disclosureKey,
    this.semanticsLabel,
  });

  final TimelineToolIcon icon;
  final String label;
  final String? meta;
  final bool active;
  final bool isIssue;
  final bool isStopped;

  /// Optional driver/test key wrapped outside [TimelineActivityDisclosure].
  final Key? cardKey;

  /// Optional key attached to [TimelineActivityDisclosure].
  final Key? disclosureKey;

  /// Optional semantic label wrapped around the card.
  final String? semanticsLabel;
}

/// Policy controlling payload argument validation and on-demand body window
/// requests in timeline connectors and readers.
@immutable
class TimelineToolBodyPolicy {
  const TimelineToolBodyPolicy({
    this.requiresJsonObjectArguments = true,
    this.readsArgumentsWindow = false,
    this.omitSuccessOutput = false,
    this.readsStructuredOutput = true,
    this.requiresAcceptance = false,
  });

  /// Whether non-empty JSON arguments must decode to a JSON object.
  final bool requiresJsonObjectArguments;

  /// Whether large `tool.arguments` bodies should open a window reader.
  final bool readsArgumentsWindow;

  /// Whether succeeded calls with no rejection omit the `tool.result` window.
  final bool omitSuccessOutput;

  /// Whether `tool.result` requires strict JSON object/list parsing rather
  /// than plain text presentation.
  final bool readsStructuredOutput;

  /// Whether completion depends on semantic acceptance decoded from output.
  final bool requiresAcceptance;
}

/// Per-item controller mounted in [TimelineToolItemScope] for each rendered
/// [TimelineToolItemView].
///
/// Supports programmatic dynamic icon changes via [setIcon]/[clearIconOverride]
/// and owns callback-epoch gating across WorkGroup body generation updates.
class TimelineToolItemController extends ChangeNotifier {
  TimelineToolItemController(this._item);

  TimelineToolPresentation _item;
  TimelineToolIcon? _iconOverride;
  Object _callbackEpoch = Object();

  TimelineToolPresentation get item => _item;

  /// Current frame epoch token bound to declared-content callbacks.
  Object get callbackEpoch => _callbackEpoch;

  /// Dynamic icon override set programmatically by this tool or its widgets.
  TimelineToolIcon? get iconOverride => _iconOverride;

  /// Optional semantic acceptance projection owned by subclasses.
  ToolAcceptanceProjection? get acceptance => null;

  /// Overrides the adapter's declarative row icon for this tool item instance.
  void setIcon(TimelineToolIcon icon) {
    if (_iconOverride == icon) return;
    _iconOverride = icon;
    notifyListeners();
  }

  /// Clears any programmatic icon override, falling back to the adapter icon.
  void clearIconOverride() {
    if (_iconOverride == null) return;
    _iconOverride = null;
    notifyListeners();
  }

  /// Updates the current [TimelineToolPresentation] without retiring state.
  void updateItem(TimelineToolPresentation nextItem) {
    _item = nextItem;
    onItemUpdated();
  }

  /// Retires the active callback epoch, resets programmatic icon override and
  /// subclass transient state.
  void retireTransientState({bool notify = true}) {
    _callbackEpoch = Object();
    _iconOverride = null;
    onRetireTransientState();
    if (notify) notifyListeners();
  }

  /// Validates and delivers an output window snapshot against [epoch] and
  /// the enclosing [group] lifecycle.
  void notifyOutputWindowRead(
    Object epoch,
    BodyWindow window, {
    TimelineExpansionIntent? group,
  }) {
    if (!identical(epoch, _callbackEpoch) ||
        (group != null && (!group.bodyActive || group.isRetired)) ||
        !window.eof ||
        window.offset != 0) {
      return;
    }
    onAcceptedOutputWindow(window);
  }

  @protected
  void onItemUpdated() {}

  @protected
  void onAcceptedOutputWindow(BodyWindow window) {}

  @protected
  void onRetireTransientState() {}
}

/// Exposes the current item's [TimelineToolItemController] to icon builders
/// and expanded body widgets.
class TimelineToolItemScope
    extends InheritedNotifier<TimelineToolItemController> {
  const TimelineToolItemScope({
    required TimelineToolItemController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static TimelineToolItemController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<TimelineToolItemScope>();
    assert(
      scope != null,
      'TimelineToolItemScope.of() called outside TimelineToolItemView.',
    );
    return scope!.notifier!;
  }

  static TimelineToolItemController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TimelineToolItemScope>()
        ?.notifier;
  }
}

/// Expanded detail slots constructed uniformly by [TimelineToolItemView].
class TimelineToolExpandedSlots {
  const TimelineToolExpandedSlots({this.declaredContents, this.standardPanel});

  /// On-demand window readers when `declaredContentBuilder` was supplied, or
  /// `null` on inline-only paths.
  final List<Widget>? declaredContents;

  /// Uniform [TimelineToolDetailPanel] wrapped in
  /// `TimelineBodyReadQualification`, or `null` when empty.
  final Widget? standardPanel;
}

/// Context passed into adapter presentation methods.
class TimelineToolItemContext {
  const TimelineToolItemContext({
    required this.buildContext,
    required this.l10n,
    required this.item,
    required this.controller,
    this.markdownBuilder,
    this.additionalContentBuilder,
    this.staticObservation = false,
  });

  final BuildContext buildContext;
  final AppLocalizations l10n;
  final TimelineToolPresentation item;
  final TimelineToolItemController controller;
  final TimelineToolMarkdownBuilder? markdownBuilder;
  final WidgetBuilder? additionalContentBuilder;
  final bool staticObservation;
}

/// Single-file interface defining a timeline tool item's matching, icon,
/// collapsed single-line label, and expanded body presentation.
abstract class TimelineToolItemAdapter {
  const TimelineToolItemAdapter();

  /// Unique stable identifier for this adapter (typically the contract name).
  String get id;

  /// Rule deciding which tool calls or live atoms route to this adapter.
  TimelineToolMatcher get matcher;

  /// Argument decoding and body-window reading rules for this tool.
  TimelineToolBodyPolicy get bodyPolicy => const TimelineToolBodyPolicy();

  /// Whether attachments are backed by `tool.output-artifacts` media records.
  bool get usesFileArtifactsMedia => false;

  /// Whether declared-window expansion prepends decoded arguments inline.
  bool get showsDeclaredPrefixInput => !bodyPolicy.readsArgumentsWindow;

  /// Whether [item] promotes its artifacts as a standalone timeline media group
  /// instead of a standard inline tool disclosure row.
  bool presentsStandaloneMedia(ChatItemPresentation item) => false;

  /// Creates the per-instance controller mounted around each rendered item.
  TimelineToolItemController createController(TimelineToolPresentation item) =>
      TimelineToolItemController(item);

  /// Localized human-readable display name for headers, diagnostics, and tests.
  String displayName(AppLocalizations l10n, TimelineToolPresentation item);

  String statusTitle(AppLocalizations l10n, TimelineToolPresentation item) =>
      toolStatusTitle(l10n, item.statusString, displayName(l10n, item));

  String rejectionLabel(AppLocalizations l10n) =>
      l10n.timelineToolOperationRejected;

  /// Resolves the canonical localized title considering acceptance state.
  String title(
    AppLocalizations l10n,
    TimelineToolPresentation item, {
    ToolAcceptanceProjection? acceptance,
  }) => acceptanceLabel(l10n, item, acceptance) ?? statusTitle(l10n, item);

  String? acceptanceLabel(
    AppLocalizations l10n,
    TimelineToolPresentation item,
    ToolAcceptanceProjection? acceptance,
  ) {
    if (!bodyPolicy.requiresAcceptance || item.statusString != 'succeeded') {
      return null;
    }
    return switch ((acceptance ?? decodeAcceptance(item.output)).state) {
      ToolAcceptance.pending => l10n.timelineToolResultPending,
      ToolAcceptance.rejected => rejectionLabel(l10n),
      ToolAcceptance.accepted => null,
    };
  }

  /// Decodes semantic acceptance projection from serialized output text.
  ToolAcceptanceProjection decodeAcceptance(String text) =>
      const ToolAcceptanceProjection(ToolAcceptance.pending);

  /// Builds acceptance explanation rows when accepted output is pending or
  /// rejected.
  List<ToolDetailValue> acceptanceDetails(
    AppLocalizations l10n,
    ToolAcceptanceProjection projection,
  ) => switch (projection.state) {
    ToolAcceptance.pending => [
      ToolDetailUnavailable(l10n.timelineToolAcceptanceUnavailable),
    ],
    ToolAcceptance.accepted => const [],
    ToolAcceptance.rejected => List.unmodifiable([
      ToolDetailText(
        rejectionLabel(l10n),
        projection.code ?? projection.reason ?? rejectionLabel(l10n),
      ),
      if (projection.code != null && projection.reason != null)
        ToolDetailText(l10n.timelineToolDetailReason, projection.reason!),
    ]),
  };

  /// Whether a declared `tool.result` window should be opened for [statusString].
  bool readsOutput(String statusString, {String output = ''}) =>
      !bodyPolicy.omitSuccessOutput ||
      statusString != 'succeeded' ||
      (bodyPolicy.requiresAcceptance &&
          decodeAcceptance(output).state != ToolAcceptance.accepted);

  /// Safely decodes raw arguments into immutable semantic detail values.
  List<ToolDetailValue> decodeInput(AppLocalizations l10n, String text) =>
      const [];

  /// Safely decodes raw output into immutable semantic detail values.
  List<ToolDetailValue> decodeOutput(AppLocalizations l10n, String text) =>
      const [];

  /// Safely decodes artifact payload summaries into immutable detail values.
  List<ToolDetailValue> decodeArtifacts(AppLocalizations l10n, String text) =>
      const [];

  /// Builds the single-line collapsed row presentation (icon, title, meta,
  /// active/issue flags).
  TimelineToolRowSummary buildRowSummary(TimelineToolItemContext context);

  /// Builds expanded disclosure children using uniform [slots].
  List<Widget> buildExpandedChildren(
    TimelineToolItemContext context,
    TimelineToolExpandedSlots slots,
  );

  /// Builds inline semantic body when no declared content windows are present.
  Widget? buildInlineBody(
    TimelineToolItemContext context, {
    ToolAcceptanceProjection? acceptance,
  });

  /// Builds window body content when an on-demand declared content reader loads.
  Widget buildWindowBody(
    TimelineToolItemContext context,
    String windowText, {
    required bool isInput,
    ToolAcceptanceProjection? acceptance,
  });
}
