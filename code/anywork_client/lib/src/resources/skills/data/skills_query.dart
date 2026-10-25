import 'package:anywork_client/resources_ports.dart';

import '../domain/skills_repository.dart';
import '../domain/skills_state.dart';
import 'skills_field_reads.dart';
import 'skills_mirror.dart';
import 'skills_pages.dart';

/// A UI observation borrow. The Repo, not this borrow, owns feed/read/commands.
/// Forwarding the same immutable snapshot is not another canonical reducer.
final class SkillsQuery implements ProjectSkillsQuery {
  SkillsQuery(this.mirror, this.reads, this.pages, this.onClosed)
    : _source = ResourceSource(
        mirror.source.value,
        mirror.lifetime.budget,
        'skills-query:${mirror.projectId}',
      ) {
    final watch = mirror.source.watchLatest((value) {
      if (!_closed) _source.publish(value);
    });
    _observation = watch.observation;
    _source.publish(watch.value);
  }
  final SkillsMirror mirror;
  final SkillsReads reads;
  final SkillsPages pages;
  final void Function(SkillsQuery) onClosed;
  final ResourceSource<SkillsState> _source;
  Observation? _observation;
  bool _closed = false;

  @override
  String get projectId => mirror.projectId;
  @override
  ReadonlyLatestValue<SkillsState> get state => _source.readonly;

  void _admit() {
    if (_closed) throw resourceCancelled;
    mirror.lifetime.admit();
  }

  @override
  Future<void> loadSkillsPage({int limit = 32}) {
    _admit();
    return pages.load(limit: limit);
  }

  @override
  Future<void> loadWarnings() {
    _admit();
    return reads.warnings();
  }

  @override
  Future<void> loadProjectDirectory() {
    _admit();
    return reads.directory();
  }

  @override
  Future<void> loadConfigFingerprint() {
    _admit();
    return reads.fingerprint();
  }

  @override
  Future<void> loadSourceStatus() {
    _admit();
    return reads.sourceStatus();
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    // Only this bridge, its observers and waiters are ended. In-flight shared
    // reads and Repo-accepted discover/search keep their original responsibility.
    _observation?.cancel();
    _observation = null;
    _source.close();
    onClosed(this);
  }

  @override
  Future<CloseReport> close({DateTime? deadline}) async {
    requestClose();
    return CloseReport(unresolved: const []);
  }

  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      close(deadline: deadline);
}
