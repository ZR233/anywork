import '../../../models.dart';
import '../../../model_directory.dart';
import '../../../conversation.dart';
import '../../../drafts_ports.dart';
import '../../commands/mutation_board.dart';
import '../../lifecycle/resource_budget.dart';
import '../../studio/stores/settings_store.dart';
import '../../studio/stores/project_store.dart';
import '../../studio/stores/selection_store.dart';
import '../../studio/stores/canonical_clock.dart';
import '../domain/draft_owners.dart';
import 'draft_attachment_operations.dart';
import '../../conversation/data/input_turn_facts.dart';

/// Typed, narrow dependencies. The application supplies read observations and
/// command capabilities, never itself or a callback returning the Client.
final class DraftsDependencies {
  DraftsDependencies({
    required this.budget,
    required this.mutations,
    required this.conversations,
    required this.inputFacts,
    required this.settings,
    required this.project,
    required this.selection,
    required this.recovery,
    required this.modelAccounts,
    required this.threads,
    required this.findThread,
    required this.threadCommands,
    required this.transport,
  });
  final ResourceBudget budget;
  final MutationBoard mutations;
  final ConversationRepository conversations;
  final InputTurnFacts inputFacts;
  final ValueObservation<SettingsStoreState> settings;
  final ValueObservation<ProjectStoreState> project;
  final ValueObservation<SelectionStoreState> selection;
  final ValueObservation<CanonicalClockState<RecoveryStateSnapshot>> recovery;
  final List<ModelSelectionAccount> Function() modelAccounts;
  final Iterable<StudioThread> Function() threads;
  final StudioThread? Function(String) findThread;
  final DraftSubmissionCommands threadCommands;
  final AttachmentTransport transport;
  late final DraftAttachmentOperations attachments;
  late final StartSessionDraftOwner startDraft;
  bool isClosed = false;
}
