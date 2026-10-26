import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/skills_repository.dart';
import '../domain/skills_state.dart';
import '../domain/skills_values.dart';
import 'skills_actions.dart';
import 'skills_field_reads.dart';
import 'skills_mirror.dart';
import 'skills_pages.dart';
import 'skills_port.dart';
import 'skills_query.dart';

SkillsRepository createSkillsRepository({
  required SkillsPort port,
  required ResourceBudget budget,
  required OperationRecorder operations,
}) => _SkillsRepository(port, ResourceLifetime(budget), operations);

final class _SkillsRepository implements SkillsRepository {
  _SkillsRepository(
    SkillsPort port,
    ResourceLifetime lifetime,
    OperationRecorder operations,
  ) : _port = port,
      _lifetime = lifetime,
      _actions = SkillsActions(port, lifetime, operations) {
    _lifetime.onSeal(() {
      for (final query in List.of(_queries)) {
        query.requestClose();
      }
    });
  }
  final SkillsPort _port;
  final ResourceLifetime _lifetime;
  final SkillsActions _actions;
  final Map<String, _ProjectSkills> _projects = {};
  final Set<SkillsQuery> _queries = Set.identity();
  bool _closed = false;

  void _admitProject(String projectId) {
    _lifetime.admit();
    if (projectId.trim().isEmpty)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A Skills project ID must not be empty.',
        retryable: false,
        correlationId: 'skills',
      );
  }

  _ProjectSkills _project(String projectId) => _projects.putIfAbsent(
    projectId,
    () => _ProjectSkills(projectId, _port, _lifetime),
  );

  @override
  ProjectSkillsQuery project(String projectId) {
    _admitProject(projectId);
    final owner = _project(projectId);
    final query = SkillsQuery(owner.mirror, owner.reads, owner.pages, (value) {
      _queries.remove(value);
    });
    _queries.add(query);
    try {
      owner.mirror.capture();
      _lifetime.admit();
      return query;
    } catch (_) {
      query.requestClose();
      rethrow;
    }
  }

  @override
  OperationTicket<SkillsReadTarget> discover(String projectId) {
    _admitProject(projectId);
    return _actions.discover(_project(projectId).mirror);
  }

  @override
  Future<SkillSearchResult> search(
    String projectId,
    String query, {
    int limit = 50,
  }) {
    _admitProject(projectId);
    if (query.trim().isEmpty || limit < 1 || limit > 50) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Skills search needs a nonempty query and a limit between 1 and 50.',
        retryable: false,
        correlationId: 'skills',
      );
    }
    // Strings/limit are the exact frozen inputs. No discovery, lane or selection
    // lookup intervenes; the whole read is registered before calling the port.
    return _lifetime.run('skills-search:$projectId', () async {
      final value = await _port.search(projectId, query, limit: limit);
      if (value.projectId != projectId ||
          value.catalogRevision < 0 ||
          value.matches.length > limit) {
        throw resourceProtocol(
          'Skills search returned another project or an invalid page.',
        );
      }
      return value.copyWith(
        matches: List.unmodifiable([
          for (final match in value.matches)
            match.copyWith(platforms: List.unmodifiable(match.platforms)),
        ]),
      );
    });
  }

  @override
  void seal() => _lifetime.seal();
  @override
  Future<CloseReport> close({DateTime? deadline}) =>
      _close(deadline, retry: false);
  @override
  Future<CloseReport> retryCleanup({DateTime? deadline}) =>
      _close(deadline, retry: true);

  Future<CloseReport> _close(DateTime? deadline, {required bool retry}) async {
    final resources = await _lifetime.close(deadline: deadline, retry: retry);
    final report = CloseReport(
      unresolved: [...resources.unresolved, ..._actions.unresolved],
    );
    if (report.complete && !_closed) {
      _closed = true;
      for (final owner in _projects.values) {
        owner.mirror.source.close();
      }
    }
    return report;
  }
}

final class _ProjectSkills {
  _ProjectSkills(String projectId, SkillsPort port, ResourceLifetime lifetime) {
    mirror = SkillsMirror(projectId, port, lifetime);
    reads = SkillsReads(port, mirror, lifetime);
    pages = SkillsPages(mirror, reads, lifetime);
    mirror.adopted = (binding) {
      reads.adopted(binding);
      pages.adopted(binding);
    };
  }
  late final SkillsMirror mirror;
  late final SkillsReads reads;
  late final SkillsPages pages;
}
