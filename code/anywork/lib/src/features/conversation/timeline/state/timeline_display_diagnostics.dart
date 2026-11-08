import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

/// Actual mounted expanded Run window. No query is started by these
/// synchronous borrows; business Children keeps its independent parent domain.
abstract interface class TimelineGroupDisplay {
  String get unitId;
  bool get isCurrent;
  bool get expanded;
  CompletionRunRef? get runReference;
  String? get before;
  bool get loading;
  Object? get error;
  Iterable<ChatAtom> get atoms;
  Iterable<TimelineCurrentWindowDisplay> get windows;
}

/// A borrow of the real expanded Children display, never a second message collection.
///
/// Getters are synchronous and perform no IO. The display owns registration, eligibility and
/// teardown; the Main display lease only lends these current facts to an explicit Driver query.
abstract interface class TimelineChildrenDisplay {
  String get parentId;
  int get generation;
  bool get isCurrent;
  bool get ready;
  String? get olderCursor;
  bool get loadingOlder;
  Object? get error;
  Iterable<Message> get messages;
  int get appliedSets;
  int get appliedPrepends;
  int get appliedAppends;
  Iterable<TimelineCurrentWindowDisplay> get windows;
}

/// A borrow of a mounted member renderer's actual body resources.
abstract interface class TimelineMemberDisplay {
  Iterable<TimelineCurrentWindowDisplay> get windows;
}

/// A borrow of the mounted current display and its already admitted bounded resources.
///
/// These getters never expand, page or watch. A retired source must expose no old page/window.
abstract interface class TimelineCurrentDisplay {
  bool get isCurrent;
  String? get turnId;
  String? get activityId;
  bool get expanded;
  Iterable<TimelineCurrentCollectionDisplay> get collections;
  Iterable<TimelineCurrentWindowDisplay> get windows;
}

abstract interface class TimelineCurrentCollectionDisplay {
  bool get isCurrent;
  CurrentCollectionRef get reference;
  int get generation;
  bool get expanded;
  bool get loading;
  Object? get error;
  CurrentCollectionPage? get page;
}

abstract interface class TimelineCurrentWindowDisplay {
  String get id;
  ContentRef get reference;
  int get offset;
  ContentWindow? get window;
  Object? get error;
}

/// One actual content layout, measured on the selection owner's single monotonic clock.
final class TimelineContentLayout {
  const TimelineContentLayout({
    required this.selectionId,
    required this.generation,
    required this.itemId,
    required this.selectionStartedMicros,
    required this.layoutCompletedMicros,
  });

  final int selectionId;
  final int generation;
  final String itemId;
  final int selectionStartedMicros;
  final int layoutCompletedMicros;
  int get elapsedMicros => layoutCompletedMicros - selectionStartedMicros;
}
