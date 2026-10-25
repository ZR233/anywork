import 'dart:async';

import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'profile_native_pin.dart';
import 'scripted_feed.dart';

final class ProfileFirstModelCall {
  ProfileFirstModelCall(this.catalog, this.pin);
  final ModelCatalogReadTarget catalog;
  final ProfileNativePin pin;
  final reply = Completer<ModelSelection?>();
}

final class ProfileEffortCall {
  ProfileEffortCall(this.catalog, this.model, this.candidate);
  final ModelCatalogReadTarget catalog;
  final AccountModelKey model;
  final String? candidate;
  final reply = Completer<String?>();
}

final class ProfileCatalogHeaderCall {
  ProfileCatalogHeaderCall(this.catalog, this.pin, this.value);
  final ModelCatalogReadTarget catalog;
  final ProfileNativePin pin;
  final ModelCatalogReadHeader value;
  final reply = Completer<ModelCatalogReadHeader>();
  void accept() => reply.complete(value);
}

/// Immutable native DTOs plus explicit query replies. There is no Dart
/// implementation of Rust's first-model or effort-default algorithm here.
final class ProfileModelsPort implements ModelsPort {
  ProfileModelsPort({
    required this.origin,
    required List<String> accounts,
    required Set<String> textEligibleAccounts,
  }) : accounts = List.unmodifiable(accounts),
       textEligibleAccounts = Set.unmodifiable(textEligibleAccounts);
  final ProductReadOrigin origin;
  final List<String> accounts;
  final Set<String> textEligibleAccounts;
  final feed = ScriptedFeed<ModelCatalogFrame>(
    feedId: 'profile-models',
    sequenceOf: (frame) =>
        frame is ModelCatalogData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! ModelCatalogData,
  );
  final firstCalls = <ProfileFirstModelCall>[];
  final effortCalls = <ProfileEffortCall>[];
  final lookupCalls = <({ModelCatalogReadTarget catalog, String accountId})>[];
  final pageCalls =
      <({ModelCatalogReadTarget catalog, int offset, int limit})>[];
  final _firstWaiters = <int, Completer<ProfileFirstModelCall>>{};
  final _effortWaiters = <int, Completer<ProfileEffortCall>>{};
  final catalogHeaders = <ProfileCatalogHeaderCall>[];
  final _headerWaiters = <int, Completer<ProfileCatalogHeaderCall>>{};
  final declaredCatalogs = <int>{1};
  bool holdCatalogHeaders = false;
  int _revision = 1;

  Future<ProfileFirstModelCall> firstCalled(int index) =>
      index < firstCalls.length
      ? Future.value(firstCalls[index])
      : _firstWaiters
            .putIfAbsent(index, Completer<ProfileFirstModelCall>.new)
            .future;
  Future<ProfileEffortCall> effortCalled(int index) =>
      index < effortCalls.length
      ? Future.value(effortCalls[index])
      : _effortWaiters
            .putIfAbsent(index, Completer<ProfileEffortCall>.new)
            .future;
  Future<ProfileCatalogHeaderCall> catalogHeaderCalled(int index) =>
      index < catalogHeaders.length
      ? Future.value(catalogHeaders[index])
      : _headerWaiters
            .putIfAbsent(index, Completer<ProfileCatalogHeaderCall>.new)
            .future;

  ModelCatalogHeader _header(int revision) => ModelCatalogHeader(
    source: profileSource(revision),
    catalogRevision: revision,
    updatedAt: revision,
    reference: ModelCatalogReadRef(entry: 1, revision: revision),
  );

  void baseline() => feed.emit(
    ModelCatalogFrame.data(
      deliverySequence: 1,
      event: ModelCatalogEvent.baseline(
        identity: profileIdentity(
          feed.feedId,
          origin,
          ProductResource.modelCatalog,
        ),
        stamp: profileStamp(origin, 1),
        value: ModelCatalogBaseline(
          header: _header(1),
          collection: profileCollection(1, accounts.length),
        ),
      ),
    ),
  );

  Future<void> advanceCatalog() async {
    final previous = _revision++;
    declaredCatalogs.add(_revision);
    // The immutable rows did not change, only this catalog's source/version.
    feed.emit(
      ModelCatalogFrame.data(
        deliverySequence: _revision,
        event: ModelCatalogEvent.change(
          stamp: profileStamp(origin, _revision),
          baseRevision: previous,
          value: ModelCatalogChange(
            header: _header(_revision),
            baseCollectionRevision: previous,
            collection: profileCollection(_revision, accounts.length),
            upserted: const [],
            removedEntries: const [],
          ),
        ),
      ),
    );
    await feed.acknowledged(_revision);
  }

  @override
  Future<FeedConnection<ModelCatalogFrame>> openModelCatalog() async => feed;
  @override
  Future<ModelCatalogReadConnection> openModelCatalogRead(
    ModelCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != this.origin ||
        reference.entry != 1 ||
        !declaredCatalogs.contains(reference.revision)) {
      throw StateError('Unscripted native model catalog target');
    }
    return _CatalogPin(
      this,
      ModelCatalogReadTarget(origin: origin, reference: reference),
    );
  }

  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async {
    if (origin != this.origin || reference.entry != 9)
      throw StateError('Unscripted model source');
    return ProfileSourcePin(reference.revision);
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Profile model capability: ${invocation.memberName}',
  );
}

final class _CatalogPin extends ProfileNativePin
    implements ModelCatalogReadConnection {
  _CatalogPin(this.port, this.target)
    : super('profile-catalog-${target.reference.revision}');
  final ProfileModelsPort port;
  final ModelCatalogReadTarget target;

  ProductEntityRef _entity(int index) =>
      ProductEntityRef(entry: 100 + index, revision: 1);
  @override
  Future<ModelCatalogReadHeader> header() {
    admit();
    final value = ModelCatalogReadHeader(
      accounts: TypedListRef(listId: 1, total: port.accounts.length),
      webSearch: const EffectiveWebSearchRead(
        effectiveMode: ReadText.inline(text: 'off'),
        availability: ReadText.inline(text: 'unavailable'),
        accountId: null,
        modelId: null,
      ),
      deepseekWebSearch: const EffectiveDeepSeekSearchRead(
        effectiveEnabled: false,
        effectiveFetchEnabled: false,
        availability: ReadText.inline(text: 'unavailable'),
        accountId: null,
      ),
    );
    final call = ProfileCatalogHeaderCall(target, this, value);
    port.catalogHeaders.add(call);
    port._headerWaiters.remove(port.catalogHeaders.length - 1)?.complete(call);
    if (!port.holdCatalogHeaders) call.accept();
    return reply(call.reply.future);
  }

  @override
  Future<ModelSelection?> firstTextModel() {
    admit();
    final call = ProfileFirstModelCall(target, this);
    port.firstCalls.add(call);
    port._firstWaiters.remove(port.firstCalls.length - 1)?.complete(call);
    return reply(call.reply.future);
  }

  @override
  Future<String?> effortAfterModelSelection(
    String accountId,
    String modelId, {
    required String? candidate,
  }) {
    admit();
    final call = ProfileEffortCall(
      target,
      AccountModelKey(accountId: accountId, modelId: modelId),
      candidate,
    );
    port.effortCalls.add(call);
    port._effortWaiters.remove(port.effortCalls.length - 1)?.complete(call);
    return reply(call.reply.future);
  }

  @override
  Future<ModelCatalogEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    port.pageCalls.add((catalog: target, offset: offset, limit: limit));
    final end = (offset + limit).clamp(0, port.accounts.length);
    return ModelCatalogEntryPage(
      collection: profileCollection(
        target.reference.revision,
        port.accounts.length,
      ),
      offset: offset,
      items: [for (var index = offset; index < end; index++) _entity(index)],
      nextOffset: end == port.accounts.length ? null : end,
    );
  }

  @override
  Future<ProductEntityRef?> lookupAccount(String accountId) async {
    admit();
    port.lookupCalls.add((catalog: target, accountId: accountId));
    final index = port.accounts.indexOf(accountId);
    return index < 0 ? null : _entity(index);
  }

  @override
  Future<ModelCatalogEntityRead> entity(ProductEntityRef reference) async {
    admit();
    final index = reference.entry - 100;
    if (index < 0 ||
        index >= port.accounts.length ||
        reference != _entity(index))
      throw StateError('Unscripted model row');
    final accountId = port.accounts[index];
    return ModelCatalogEntityRead(
      reference: reference,
      value: AccountCatalogEntryRead(
        accountId: ReadText.inline(text: accountId),
        credentialRequired: false,
        capabilitySource: const ReadText.inline(text: 'bundled'),
        hostedWebSearch: false,
        hostedWebSearchDialect: const ReadText.inline(text: 'none'),
        standaloneWebSearch: null,
        promptCacheDialect: const ReadText.inline(text: 'none'),
        responsesProgrammaticToolCalling: false,
        defaultModelId: const ReadText.inline(text: 'text'),
        effectiveModels: TypedListRef(listId: 1000 + index, total: 1),
        modelCatalog: const ModelCatalogStatusRead(
          supported: true,
          source: ModelCatalogSource.defaultSource,
          probing: false,
          lastSuccessAt: null,
          checkedAt: null,
          error: null,
          cacheWarning: null,
        ),
      ),
    );
  }

  @override
  Future<ModelDescriptorReadPage> models(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    final index = listId - 1000;
    if (index < 0 || index >= port.accounts.length || offset != 0 || limit < 1)
      throw StateError('Unscripted model list');
    final eligible = port.textEligibleAccounts.contains(port.accounts[index]);
    return ModelDescriptorReadPage(
      listId: listId,
      offset: offset,
      total: 1,
      items: [_model(eligible)],
      nextOffset: null,
    );
  }

  @override
  Future<ModelTypeSupportReadPage> typeSupport(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    if ((listId != 20 && listId != 21) || offset != 0 || limit < 1)
      throw StateError('Unscripted type support');
    return ModelTypeSupportReadPage(
      listId: listId,
      offset: offset,
      total: 1,
      items: [
        ModelTypeSupportRead(
          modelType: ModelType.text,
          exclusions: TypedListRef(listId: 22, total: listId == 20 ? 0 : 1),
        ),
      ],
      nextOffset: null,
    );
  }

  @override
  Future<ModelTypeExclusionReadPage> typeExclusions(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    if (listId != 22 || offset != 0 || limit < 1)
      throw StateError('Unscripted text exclusion');
    return ModelTypeExclusionReadPage(
      listId: listId,
      offset: offset,
      total: 1,
      items: const [
        ModelTypeExclusionReadItem(
          value: ModelTypeExclusion.textInputUnsupported,
        ),
      ],
      nextOffset: null,
    );
  }

  @override
  Future<TextReadPage> strings(
    int listId, {
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    const values = ['low', 'high'];
    if (listId != 30) throw StateError('Unscripted effort candidates');
    final end = (offset + limit).clamp(0, values.length);
    return TextReadPage(
      listId: listId,
      offset: offset,
      total: values.length,
      items: [
        for (final value in values.sublist(offset, end))
          TextReadItem(value: ReadText.inline(text: value)),
      ],
      nextOffset: end == values.length ? null : end,
    );
  }
}

ModelDescriptorRead _model(bool eligible) => ModelDescriptorRead(
  modelId: const ReadText.inline(text: 'text'),
  enabled: true,
  typeSupport: TypedListRef(listId: eligible ? 20 : 21, total: 1),
  origin: ModelOrigin.bundled,
  displayName: const ReadText.inline(text: 'Native text model'),
  description: null,
  contextWindow: 4096,
  maxContextWindow: 4096,
  context: const ModelContextResolutionRead(
    unavailable: null,
    contextWindow: 4096,
    inputTokenLimit: 3072,
    autoCompactLimit: 2048,
    adjustment: null,
  ),
  maxOutputTokens: 1024,
  transport: const ModelTransportDescriptorRead(
    protocol: ReadText.inline(text: 'openai'),
    connectionModes: TypedListRef(listId: 0, total: 0),
    defaultConnectionMode: ReadText.inline(text: 'auto'),
  ),
  capabilities: const ModelCapabilitiesRead(
    input: TypedListRef(listId: 0, total: 0),
    output: TypedListRef(listId: 0, total: 0),
    streaming: true,
    temperature: false,
    reasoning: true,
    webSearch: false,
    functionCalling: false,
    parallelToolCalls: false,
    customTools: false,
    freeformTools: false,
    instructionSnapshotOverrides: false,
    nativeContextFamily: null,
  ),
  reasoning: const ModelReasoningDescriptorRead(
    parameter: ReadText.inline(text: 'effort'),
    label: ReadText.inline(text: 'Effort'),
    defaultValue: null,
    candidates: TypedListRef(listId: 30, total: 2),
  ),
  pricing: null,
);
