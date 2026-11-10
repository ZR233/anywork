import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:material_ui/material_ui.dart';

import '../state/chat_item_presentation.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import 'timeline_children_connector.dart';

/// Mounted only by an expanded group. It borrows diagnostics from the real
/// member window, never retains a second list of atoms or changes Main state.
class CompletionRunConnector extends StatefulWidget {
  const CompletionRunConnector({
    required this.unit,
    required this.threadId,
    this.readAttachment,
    this.monotonicMicros,
    this.onContentLayout,
    super.key,
  });
  final TimelineDisplayUnit unit;
  final String threadId;
  final Future<Uint8List> Function(String)? readAttachment;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;
  @override
  State<CompletionRunConnector> createState() => _MembersState();
}

class _MembersState extends State<CompletionRunConnector>
    implements TimelineGroupDisplay {
  TimelineChildrenDisplay? _display;
  VoidCallback? _unregister;
  late final Object _bodyGeneration;
  TimelineExpansionIntent get _intent => widget.unit.expansion;
  @override
  String get unitId => widget.unit.id;
  @override
  CompletionRunRef? get runReference => widget.unit.run?.reference;
  @override
  bool get isCurrent =>
      mounted &&
      !_intent.isRetired &&
      _intent.bodyActive &&
      identical(_bodyGeneration, _intent.bodyGeneration) &&
      (_intent.isDisplayActive?.call() ?? true);
  @override
  bool get expanded => isCurrent;
  @override
  String? get before => isCurrent ? _display?.olderCursor : null;
  @override
  bool get loading {
    if (!isCurrent) return false;
    final display = _display;
    return display == null || !display.isCurrent || display.loadingOlder;
  }

  @override
  Object? get error => isCurrent ? _display?.error : null;
  @override
  Iterable<ChatAtom> get atoms sync* {
    final display = _display;
    if (!isCurrent || display == null || !display.isCurrent) return;
    for (final message in display.messages) {
      final atom = chatItemPresentationOf(message)?.atom;
      if (atom != null) yield atom;
    }
  }

  @override
  Iterable<TimelineCurrentWindowDisplay> get windows =>
      isCurrent ? _display?.windows ?? const [] : const [];

  @override
  void initState() {
    super.initState();
    _bodyGeneration = _intent.bodyGeneration;
    _unregister = _intent.registerDisplay?.call(this);
  }

  @override
  void dispose() {
    _display = null;
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reference = runReference;
    final open = _intent.openRun;
    if (reference == null || open == null) return const Text('成员读取尚未就绪');
    return TimelineGroupBodyIntent(
      intent: _intent,
      child: TimelineChildrenConnector(
        key: ValueKey((_intent, reference, _intent.bodyGeneration)),
        threadId: widget.threadId,
        parentId: unitId,
        runReference: reference,
        openRun: open,
        parentRetirement: _intent.retirement,
        isParentActive: () => isCurrent,
        readAttachment: widget.readAttachment,
        monotonicMicros: widget.monotonicMicros,
        onContentLayout: (_, micros) =>
            widget.onContentLayout?.call(unitId, micros),
        registerDisplay: (display) {
          _display = display;
          return () {
            if (identical(_display, display)) _display = null;
          };
        },
      ),
    );
  }
}
