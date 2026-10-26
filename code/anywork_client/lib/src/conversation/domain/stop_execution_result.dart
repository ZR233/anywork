import '../../../operations.dart';

/// Synchronous stop admission. This is a borrowed capability result, not a
/// serializable value or ViewState: only admitted work has an operation ticket.
sealed class StopExecutionResult {
  const StopExecutionResult();
}

final class StopNoExecution extends StopExecutionResult {
  const StopNoExecution(this.threadId);
  final String threadId;
}

final class StopExecutionOperation extends StopExecutionResult {
  const StopExecutionOperation({required this.ticket});
  final OperationTicket<Unit> ticket;
}
