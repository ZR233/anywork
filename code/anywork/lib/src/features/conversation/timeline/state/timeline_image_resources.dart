import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';

/// Per-display image bytes. References belong to raw conversation items, not
/// mounted widgets or derived Flyer media siblings.
final class TimelineImageResources {
  TimelineImageResources({required this.threadId});

  final String threadId;
  final Map<String, Set<String>> _itemAttachments = {};
  final Map<String, int> _attachmentRefs = {};
  final Map<String, TimelineImageResource> _resources = {};
  bool _retired = false;
  bool _released = false;

  String _key(String attachmentId) => '$threadId\u0000$attachmentId';

  void retainItem(String itemId, Iterable<ThreadAttachmentView> attachments) {
    if (_released) return;
    final next = <String>{
      for (final attachment in attachments)
        if (attachment.modality == AttachmentModalityView.image) attachment.id,
    };
    final previous = _itemAttachments[itemId] ?? const <String>{};
    if (next.isEmpty) {
      _itemAttachments.remove(itemId);
    } else {
      _itemAttachments[itemId] = next;
    }
    for (final id in previous.difference(next)) {
      final count = _attachmentRefs[id]! - 1;
      if (count == 0) {
        _attachmentRefs.remove(id);
        _resources.remove(_key(id))?._detach();
      } else {
        _attachmentRefs[id] = count;
      }
    }
    for (final id in next.difference(previous)) {
      _attachmentRefs[id] = (_attachmentRefs[id] ?? 0) + 1;
    }
  }

  void dropItem(String itemId) => retainItem(itemId, const []);

  TimelineImageResource borrow(String attachmentId) {
    if (!_attachmentRefs.containsKey(attachmentId)) {
      throw StateError(
        'The image attachment is no longer referenced: '
        '$threadId/$attachmentId',
      );
    }
    final key = _key(attachmentId);
    final existing = _resources[key];
    if (existing != null) return existing;
    if (_retired || _released) {
      throw StateError('The image display generation retired: $threadId');
    }
    final resource = TimelineImageResource._(this, attachmentId);
    _resources[key] = resource;
    return resource;
  }

  bool _canStart(String attachmentId, TimelineImageResource resource) =>
      !_retired &&
      !_released &&
      _attachmentRefs.containsKey(attachmentId) &&
      identical(_resources[_key(attachmentId)], resource);

  void retire() {
    _retired = true;
  }

  void release() {
    if (_released) return;
    _retired = true;
    _released = true;
    final resources = _resources.values.toList(growable: false);
    _resources.clear();
    _itemAttachments.clear();
    _attachmentRefs.clear();
    for (final resource in resources) {
      resource.dispose();
    }
  }
}

/// A shared attachment attempt. One explicit retry replaces the attempt for all
/// mounted consumers of the same lease/thread/attachment identity.
final class TimelineImageResource extends ChangeNotifier {
  TimelineImageResource._(this._owner, this.attachmentId);

  final TimelineImageResources _owner;
  final String attachmentId;
  Future<Uint8List>? _attempt;
  bool _attached = true;

  Future<Uint8List> load(Future<Uint8List> Function() read) {
    final current = _attempt;
    if (current != null) return current;
    if (!_attached || !_owner._canStart(attachmentId, this)) {
      return Future.error(
        StateError('The image resource is no longer active: $attachmentId'),
      );
    }
    return _attempt = Future.sync(read);
  }

  void retry(Future<Uint8List> Function() read) {
    if (!_attached || !_owner._canStart(attachmentId, this)) {
      throw StateError('The image resource is no longer active: $attachmentId');
    }
    final next = Future<Uint8List>.sync(read);
    _attempt = next;
    notifyListeners();
  }

  bool owns(Future<Uint8List> attempt) =>
      _attached &&
      identical(_attempt, attempt) &&
      _owner._canStart(attachmentId, this);

  void _detach() {
    if (!_attached) return;
    _attached = false;
    _attempt = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}
