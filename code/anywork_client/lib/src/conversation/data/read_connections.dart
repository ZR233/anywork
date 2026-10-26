import '../../../resources.dart';
import '../domain/activity_read_values.dart';
import '../domain/interaction_values.dart';
import '../domain/thread_read_values.dart';
import '../domain/turn_values.dart';

abstract interface class ConversationReadConnection {
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class ConversationTextReadConnection
    implements ConversationReadConnection {
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
}

abstract interface class TurnReadConnection
    implements ConversationTextReadConnection {
  Future<TurnReadHeader> header();
}

abstract interface class InteractionIndexReadConnection
    implements ConversationTextReadConnection {
  Future<InteractionIndexReadHeader> header();
  Future<InteractionBriefPage> entries({int offset = 0, int limit = 32});
}

abstract interface class InteractionReadConnection
    implements ConversationTextReadConnection {
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

abstract interface class ActivityReadConnection
    implements ConversationTextReadConnection {
  Future<ActivityReadHeader> header();
  Future<ActivityToolPage> tools({int offset = 0, int limit = 32});
  Future<WaitTargetPage> waitTargets(
    int toolIndex, {
    int offset = 0,
    int limit = 32,
  });
  Future<WaitTargetPage> latestWaitTargets({int offset = 0, int limit = 32});
}

abstract interface class StorageReadConnection
    implements ConversationTextReadConnection {
  Future<StorageReadHeader> header();
}

abstract interface class MetricsIdentityReadConnection
    implements ConversationTextReadConnection {
  Future<MetricsIdentityReadHeader> header();
}

abstract interface class ContextReadConnection
    implements ConversationTextReadConnection {
  Future<ContextReadHeader> header();
  Future<CostPage> costs({int offset = 0, int limit = 32});
  Future<CostPage> cacheSavings({int offset = 0, int limit = 32});
}

abstract interface class ThreadConfigurationReadConnection
    implements ConversationTextReadConnection {
  Future<ThreadConfigurationReadHeader> header();
  Future<SkillNamePage> activeSkills({int offset = 0, int limit = 32});
}

abstract interface class TodoReadConnection
    implements ConversationTextReadConnection {
  Future<TodoReadHeader> header();
  Future<TodoItemPage> items({int offset = 0, int limit = 32});
}

abstract interface class WorkflowReadConnection
    implements ConversationTextReadConnection {
  Future<WorkflowReadHeader> header();
}

abstract interface class PlanDocumentReadConnection
    implements ConversationReadConnection {
  Future<PlanDocumentReadHeader> header();
  Future<PlanDocumentValue> document();
}
