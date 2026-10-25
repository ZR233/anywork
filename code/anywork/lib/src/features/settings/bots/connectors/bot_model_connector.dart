import 'dart:async';

import 'package:anywork_client/bots.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../status/status.dart';
import '../view_models/bots_settings_view_model.dart';
import '../views/bot_model_view.dart';

/// Connects one bot's model route to the shared selector catalog.
///
/// The catalog is current-material evidence: an option exists only while the
/// account/model pair is published, and the effort candidates belong to the
/// exact model the bot currently names.
class BotModelConnector extends ConsumerStatefulWidget {
  const BotModelConnector({required this.bot, super.key});

  final BotSnapshot bot;

  @override
  ConsumerState<BotModelConnector> createState() => _BotModelConnectorState();
}

class _BotModelConnectorState extends ConsumerState<BotModelConnector> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _requestPage();
  }

  @override
  void didUpdateWidget(covariant BotModelConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bot.id != widget.bot.id) _requestPage();
  }

  /// One bounded page per demand: entering the detail route asks for the next
  /// catalog page instead of deriving options from a partly loaded catalog.
  void _requestPage() {
    if (_requested) return;
    _requested = true;
    unawaited(ref.read(selectorCatalogViewModelProvider.notifier).loadMore());
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(selectorCatalogViewModelProvider).value;
    final bot = widget.bot;
    final route = bot.modelRoute;
    final pending =
        ref
            .watch(botsSettingsViewModelProvider)
            .value
            ?.botActions[bot.id]
            ?.preventsResubmission ??
        false;
    if (catalog == null) {
      return BotModelView(
        role: 'bot-${bot.id}',
        accountId: route?.accountId ?? '',
        modelId: route?.modelId ?? '',
        effort: route?.effort,
        options: const [],
        efforts: const [],
        unresolvedLabel: context.l10n.modelDetailUnknown,
        pending: pending,
        onModel: (_) {},
        onEffort: (_) {},
      );
    }
    final options = selectorModels(catalog);
    final selected = options
        .where(
          (option) =>
              option.accountId == route?.accountId &&
              option.modelId == route?.modelId,
        )
        .firstOrNull;
    final descriptor = route == null
        ? null
        : selectedDescriptor(catalog.models, route.accountId, route.modelId);
    return BotModelView(
      role: 'bot-${bot.id}',
      accountId: route?.accountId ?? '',
      modelId: route?.modelId ?? '',
      effort: route?.effort,
      options: options,
      efforts: descriptor?.reasoning?.candidates ?? const [],
      unresolvedLabel: selected == null
          ? context.l10n.statusModelRouteUnavailable
          : null,
      pending: pending,
      onModel: (option) => _saveRoute(
        accountId: option.accountId,
        modelId: option.modelId,
        effort: _effortAfterSelection(option.descriptor, route?.effort),
      ),
      onEffort: (effort) {
        if (route == null) return;
        unawaited(
          ref
              .read(botsSettingsViewModelProvider.notifier)
              .setModelRoute(
                bot.id,
                accountId: route.accountId,
                modelId: route.modelId,
                effort: effort,
              ),
        );
      },
    );
  }

  /// A route change keeps the effort only while the new model lists it; an
  /// unsupported effort becomes the model default instead of being invented.
  String? _effortAfterSelection(ModelDescriptor descriptor, String? effort) =>
      effort != null &&
          (descriptor.reasoning?.candidates.contains(effort) ?? false)
      ? effort
      : null;

  Future<void> _saveRoute({
    required String accountId,
    required String modelId,
    required String? effort,
  }) => ref
      .read(botsSettingsViewModelProvider.notifier)
      .setModelRoute(
        widget.bot.id,
        accountId: accountId,
        modelId: modelId,
        effort: effort,
      );
}
