import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';

/// Reading title of a Plan document: its first level-1 heading, else [fallback].
///
/// Presentation-only derivation from the already published markdown; it never
/// keeps a second copy of the document or its decision.
String planDocumentTitle(String markdown, {required String fallback}) {
  for (final line in markdown.split('\n')) {
    final value = line.trim();
    if (value.startsWith('# ') && value.substring(2).trim().isNotEmpty) {
      return value.substring(2).trim();
    }
  }
  return fallback.trim();
}

/// Authoritative status text of the published plan phase, or null when the
/// phase carries no reading status yet.
String? planPhaseStatusLabel(BuildContext context, PlanPhase phase) =>
    switch (phase) {
      PlanPhase.awaitingConfirmation || PlanPhase.revisionRequested =>
        context.l10n.interactionPlanAwaitingConfirmation,
      PlanPhase.approved => context.l10n.interactionPlanApproved,
      PlanPhase.drafting => null,
    };
