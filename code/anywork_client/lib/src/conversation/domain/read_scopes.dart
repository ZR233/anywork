import '../../../resources.dart';
import 'activity_read_values.dart';
import 'interaction_values.dart';
import 'thread_read_values.dart';
import 'turn_values.dart';

/// A borrowed immutable native version; closing it never closes its Session.
abstract interface class ConversationReadScope {
  void requestClose();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class ConversationTextReadScope
    implements ConversationReadScope {
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
}

abstract interface class TurnReadScope implements ConversationTextReadScope {
  Future<TurnReadHeader> header();
}

abstract interface class InteractionReadScope
    implements ConversationTextReadScope {
  Future<InteractionReadHeader> header();
  Future<QuestionPage> questions({int offset = 0, int limit = 32});
  Future<OptionPage> options(
    int questionIndex, {
    int offset = 0,
    int limit = 32,
  });
  Future<AnswerEntryPage> answerEntries({int offset = 0, int limit = 32});
  Future<AnswerValuePage> answerValues(
    int entryIndex, {
    int offset = 0,
    int limit = 32,
  });
}

abstract interface class ActivityReadScope
    implements ConversationTextReadScope {
  Future<ActivityReadHeader> header();
  Future<ActivityToolPage> tools({int offset = 0, int limit = 32});
  Future<WaitTargetPage> waitTargets(
    int toolIndex, {
    int offset = 0,
    int limit = 32,
  });
  Future<WaitTargetPage> latestWaitTargets({int offset = 0, int limit = 32});
}

abstract interface class StorageReadScope implements ConversationTextReadScope {
  Future<StorageReadHeader> header();
}

abstract interface class MetricsIdentityReadScope
    implements ConversationTextReadScope {
  Future<MetricsIdentityReadHeader> header();
}

abstract interface class ContextReadScope implements ConversationTextReadScope {
  Future<ContextReadHeader> header();
  Future<CostPage> costs({int offset = 0, int limit = 32});
  Future<CostPage> cacheSavings({int offset = 0, int limit = 32});
}

abstract interface class ThreadConfigurationReadScope
    implements ConversationTextReadScope {
  Future<ThreadConfigurationReadHeader> header();
  Future<SkillNamePage> activeSkills({int offset = 0, int limit = 32});
}

abstract interface class TodoReadScope implements ConversationTextReadScope {
  Future<TodoReadHeader> header();
  Future<TodoItemPage> items({int offset = 0, int limit = 32});
}

abstract interface class WorkflowReadScope
    implements ConversationTextReadScope {
  Future<WorkflowReadHeader> header();
}

abstract interface class PlanDocumentReadScope
    implements ConversationReadScope {
  Future<PlanDocumentReadHeader> header();
  Future<PlanDocumentValue> document();
}
