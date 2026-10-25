import 'dart:async';

import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import 'drafts_native_fixture.dart';
import 'profile_native_pin.dart';
import 'workspace_port_fixture.dart';

const draftDirectoryOrigin = ProductReadOrigin(
  ownerEpoch: 'draft-directory-native',
  incarnation: 1,
);
const draftProject = ProjectRecord(
  id: 'project',
  name: 'Project',
  path: '/workspace',
  sshAlias: null,
  updatedAt: 1,
);
const draftOtherProject = ProjectRecord(
  id: 'other',
  name: 'Other',
  path: '/other',
  sshAlias: null,
  updatedAt: 1,
);

ProductProjectionStamp draftDirectoryStamp(int revision) =>
    ProductProjectionStamp(
      ownerEpoch: draftDirectoryOrigin.ownerEpoch,
      incarnation: draftDirectoryOrigin.incarnation,
      revision: revision,
    );
ProductFeedIdentity draftDirectoryIdentity(
  String id,
  ProductResource resource,
) => ProductFeedIdentity(
  feedId: id,
  ownerEpoch: draftDirectoryOrigin.ownerEpoch,
  incarnation: draftDirectoryOrigin.incarnation,
  resource: resource,
);
ObservedHeader get draftDirectorySource => const ObservedHeader(
  brief: ObservedBrief.ready(revision: 1, updatedAt: 1, lastCheckedAt: null),
  status: ProductSourceStatusRef(entry: 9, revision: 1),
);

final class DraftThreadMaterial {
  DraftThreadMaterial(this.record);
  final WorkspaceThreadRecord record;
  final entityEntered = Completer<void>();
  final closeEntered = Completer<void>();
  Completer<ThreadDirectoryEntityRead>? entityReply;
  Completer<FeedCloseReport>? closeReply;
  int closes = 0;
}

/// Only immutable native directory material. No selection/membership policy or
/// Repository is implemented here. Tests explicitly supply each thread scope.
final class DraftWorkspacePort implements WorkspacePort {
  final native = ScriptedWorkspacePort();
  final projectOpens = DraftCalls<WorkspaceProjectOpen>();
  final threadOpens = DraftCalls<WorkspaceThreadOpen>();
  final materials = <int, DraftThreadMaterial>{};
  final projects = const [draftProject, draftOtherProject];
  final activations = <String>[];
  @override
  Future<FeedConnection<ProjectDirectoryFrame>> openProjectDirectory() {
    final result = native.openProjectDirectory();
    projectOpens.add(native.projects.last);
    return result;
  }

  @override
  Future<ThreadDirectoryConnection> openThreadDirectory(
    ThreadDirectoryScope scope,
  ) {
    final result = native.openThreadDirectory(scope);
    threadOpens.add(native.threads.last);
    return result;
  }

  @override
  Future<ProjectDirectoryReadConnection> openProjectDirectoryRead(
    ProjectDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != draftDirectoryOrigin ||
        reference != const ProjectDirectoryReadRef(entry: 1, revision: 1)) {
      throw StateError('Unscripted original project material');
    }
    return _Projects(projects);
  }

  @override
  Future<ThreadDirectoryReadConnection> openThreadDirectoryRead(
    ThreadDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final material = materials[reference.entry];
    if (origin != draftDirectoryOrigin ||
        reference.revision != 1 ||
        material == null) {
      throw StateError('Unscripted original Thread material');
    }
    return _Thread(material, reference.entry);
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != draftDirectoryOrigin ||
        reference != const ProductSourceStatusRef(entry: 9, revision: 1)) {
      throw StateError('Unscripted native directory status');
    }
    return ProfileSourcePin(1);
  }

  @override
  Future<void> activateProject(String projectId) async =>
      activations.add(projectId);

  Future<void> projectsBaseline() async {
    final opening = await projectOpens.at(0);
    final feed = opening.accept();
    await feed.listened.future;
    feed.emit(
      ProjectDirectoryFrame.data(
        deliverySequence: 1,
        event: ProjectDirectoryEvent.baseline(
          identity: draftDirectoryIdentity(
            feed.feedId,
            ProductResource.projectDirectory,
          ),
          stamp: draftDirectoryStamp(1),
          value: ProjectDirectoryBaseline(
            header: ProjectDirectoryHeader(
              source: draftDirectorySource,
              reference: const ProjectDirectoryReadRef(entry: 1, revision: 1),
            ),
            collection: ProductCollectionRef(
              entry: 2,
              revision: 1,
              total: projects.length,
            ),
          ),
        ),
      ),
    );
    await feed.acknowledged(1);
  }

  Future<DraftThreadMaterial> threadBaseline(
    int index,
    WorkspaceThreadRecord record, {
    Completer<ThreadDirectoryEntityRead>? entityReply,
    Completer<FeedCloseReport>? closeReply,
  }) async {
    final opening = await threadOpens.at(index);
    final material = materials[100 + index] = DraftThreadMaterial(record);
    material.entityReply = entityReply;
    material.closeReply = closeReply;
    final feed = opening.accept().feed;
    await feed.listened.future;
    feed.emit(
      ThreadDirectoryFrame.data(
        deliverySequence: 1,
        event: ThreadDirectoryEvent.baseline(
          identity: draftDirectoryIdentity(
            feed.feedId,
            ProductResource.threadDirectory,
          ),
          stamp: draftDirectoryStamp(1),
          value: ThreadDirectoryBaseline(
            header: ThreadDirectoryHeader(
              source: draftDirectorySource,
              reference: ThreadDirectoryReadRef(
                entry: 100 + index,
                revision: 1,
              ),
              directoryRevision: 1,
              searchProjectRevision: null,
              hasMore: false,
              nextCursor: null,
            ),
            collection: const ProductCollectionRef(
              entry: 2,
              revision: 1,
              total: 1,
            ),
          ),
        ),
      ),
    );
    await feed.acknowledged(1);
    return material;
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Drafts directory read: ${invocation.memberName}',
  );
}

final class _Projects extends ProfileNativePin
    implements ProjectDirectoryReadConnection {
  _Projects(this.values) : super('draft-project-material');
  final List<ProjectRecord> values;
  @override
  Future<ProjectDirectoryReadHeader> header() async =>
      ProjectDirectoryReadHeader(
        projects: TypedListRef(listId: 1, total: values.length),
      );
  @override
  Future<ProjectDirectoryEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    final end = (offset + limit).clamp(0, values.length);
    return ProjectDirectoryEntryPage(
      collection: ProductCollectionRef(
        entry: 2,
        revision: 1,
        total: values.length,
      ),
      offset: offset,
      items: [
        for (var i = offset; i < end; i++)
          ProductEntityRef(entry: i + 10, revision: 1),
      ],
      nextOffset: end == values.length ? null : end,
    );
  }

  @override
  Future<ProductEntityRef?> lookupProject(String id) async {
    final index = values.indexWhere((item) => item.id == id);
    return index < 0 ? null : ProductEntityRef(entry: index + 10, revision: 1);
  }

  @override
  Future<ProjectDirectoryEntityRead> entity(ProductEntityRef reference) async {
    final value = values[reference.entry - 10];
    return ProjectDirectoryEntityRead(
      reference: reference,
      value: ProjectRecordRead(
        id: ReadText.inline(text: value.id),
        name: ReadText.inline(text: value.name),
        path: ReadText.inline(text: value.path),
        sshAlias: null,
        updatedAt: value.updatedAt,
      ),
    );
  }
}

final class _Thread extends ProfileNativePin
    implements ThreadDirectoryReadConnection {
  _Thread(this.material, this.entry) : super('draft-thread-material-$entry');
  final DraftThreadMaterial material;
  final int entry;
  @override
  Future<ThreadDirectoryReadHeader> header() async =>
      const ThreadDirectoryReadHeader(
        threads: TypedListRef(listId: 1, total: 1),
        nextCursor: null,
        hasMore: false,
      );
  @override
  Future<ProductEntityRef?> lookupThread(String id) async =>
      id == material.record.id
      ? const ProductEntityRef(entry: 5, revision: 1)
      : null;
  @override
  Future<ThreadDirectoryEntityRead> entity(ProductEntityRef reference) {
    if (!material.entityEntered.isCompleted) material.entityEntered.complete();
    return material.entityReply?.future ??
        Future.value(
          ThreadDirectoryEntityRead(
            reference: reference,
            value: draftThreadRead(material.record),
          ),
        );
  }

  @override
  Future<FeedCloseReport> close() {
    requestClose();
    material.closes++;
    if (!material.closeEntered.isCompleted) material.closeEntered.complete();
    return material.closeReply?.future ?? super.close();
  }

  @override
  Future<FeedCloseReport> retryClose() => close();
}

WorkspaceThreadRecordRead draftThreadRead(WorkspaceThreadRecord value) =>
    WorkspaceThreadRecordRead(
      id: ReadText.inline(text: value.id),
      projectId: ReadText.inline(text: value.projectId),
      title: ReadText.inline(text: value.title),
      mode: ReadText.inline(text: value.mode.id),
      workspaceMode: value.workspaceMode,
      delegationMode: value.delegationMode,
      delegationPreference: value.delegationPreference,
      frozenModel: value.frozenModel == null
          ? null
          : FrozenModelSelectionRead(
              accountId: ReadText.inline(
                text: value.frozenModel!.model.accountId,
              ),
              modelId: ReadText.inline(text: value.frozenModel!.model.modelId),
              effort: value.frozenModel!.effort == null
                  ? null
                  : ReadText.inline(text: value.frozenModel!.effort!),
            ),
      workspacePath: ReadText.inline(text: value.workspacePath),
      rootThreadId: ReadText.inline(text: value.rootThreadId),
      parentThreadId: value.parentThreadId == null
          ? null
          : ReadText.inline(text: value.parentThreadId!),
      role: ReadText.inline(text: value.role),
      agentPath: ReadText.inline(text: value.agentPath),
      status: value.status,
      createdAt: value.createdAt,
      updatedAt: value.updatedAt,
      lastUserMessageAt: value.lastUserMessageAt,
      archived: value.archived,
    );
