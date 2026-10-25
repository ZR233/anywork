import 'dart:convert';
import 'dart:math' as math;

import '../../../resources.dart';
import '../../../resources_ports.dart' show resourceProtocol;
import '../domain/model_values.dart';
import 'model_read_pages.dart';
import 'model_reads.dart';
import 'model_field_read_connection.dart';
import 'models_port.dart';

/// Typed mechanical field reads shared by the original native scopes. This
/// reader owns no catalog policy, resource owner, cache or query lifetime.
base class ModelFieldReadAccess {
  ModelFieldReadAccess(ModelFieldReadConnection scope)
    : text = scope.text,
      strings = scope.strings,
      typeSupport = scope.typeSupport,
      typeExclusions = scope.typeExclusions,
      connectionModes = scope.connectionModes,
      inputCapabilities = scope.inputCapabilities,
      inputSources = scope.inputSources,
      modalities = scope.modalities,
      priceTiers = scope.priceTiers;

  final Future<TextChunk> Function(int, {int offset, int maxBytes}) text;
  final Future<TextReadPage> Function(int, {int offset, int limit}) strings;
  final Future<ModelTypeSupportReadPage> Function(int, {int offset, int limit})
  typeSupport;
  final Future<ModelTypeExclusionReadPage> Function(
    int, {
    int offset,
    int limit,
  })
  typeExclusions;
  final Future<ConnectionModeReadPage> Function(int, {int offset, int limit})
  connectionModes;
  final Future<ModelInputCapabilityReadPage> Function(
    int, {
    int offset,
    int limit,
  })
  inputCapabilities;
  final Future<ModelInputSourceReadPage> Function(int, {int offset, int limit})
  inputSources;
  final Future<ModelModalityReadPage> Function(int, {int offset, int limit})
  modalities;
  final Future<ModelPriceTierReadPage> Function(int, {int offset, int limit})
  priceTiers;

  Future<String> string(ReadText value) => readModelText(value, text);
  Future<String?> optional(ReadText? value) async =>
      value == null ? null : await string(value);

  Future<List<String>> stringList(TypedListRef reference) async {
    final items = await readModelList<TextReadItem>(reference, (offset) async {
      final page = await strings(reference.listId, offset: offset, limit: 32);
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return List.unmodifiable([
      for (final item in items) await string(item.value),
    ]);
  }

  Future<ModelDescriptor> model(ModelDescriptorRead value) async {
    final support = await readModelList<ModelTypeSupportRead>(
      value.typeSupport,
      (offset) async {
        final page = await typeSupport(
          value.typeSupport.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    final modes = await readModelList<ConnectionModeRead>(
      value.transport.connectionModes,
      (offset) async {
        final page = await connectionModes(
          value.transport.connectionModes.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    final inputs = await readModelList<ModelInputCapabilityRead>(
      value.capabilities.input,
      (offset) async {
        final page = await inputCapabilities(
          value.capabilities.input.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    final outputs = await readModelList<ModelModalityReadItem>(
      value.capabilities.output,
      (offset) async {
        final page = await modalities(
          value.capabilities.output.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    final reasoning = value.reasoning;
    final pricing = value.pricing;
    return ModelDescriptor(
      modelId: await string(value.modelId),
      enabled: value.enabled,
      typeSupport: List.unmodifiable([
        for (final item in support) await _support(item),
      ]),
      origin: value.origin,
      displayName: await string(value.displayName),
      description: await optional(value.description),
      contextWindow: value.contextWindow,
      maxContextWindow: value.maxContextWindow,
      context: ModelContextResolution(
        unavailable: value.context.unavailable,
        contextWindow: value.context.contextWindow,
        inputTokenLimit: value.context.inputTokenLimit,
        autoCompactLimit: value.context.autoCompactLimit,
        adjustment: value.context.adjustment,
      ),
      maxOutputTokens: value.maxOutputTokens,
      transport: ModelTransportDescriptor(
        protocol: await string(value.transport.protocol),
        connectionModes: List.unmodifiable([
          for (final mode in modes)
            ConnectionMode(
              id: await string(mode.id),
              displayName: await string(mode.displayName),
            ),
        ]),
        defaultConnectionMode: await string(
          value.transport.defaultConnectionMode,
        ),
      ),
      capabilities: ModelCapabilities(
        input: List.unmodifiable([
          for (final input in inputs) await inputCapability(input),
        ]),
        output: List.unmodifiable([for (final item in outputs) item.value]),
        streaming: value.capabilities.streaming,
        temperature: value.capabilities.temperature,
        reasoning: value.capabilities.reasoning,
        webSearch: value.capabilities.webSearch,
        functionCalling: value.capabilities.functionCalling,
        parallelToolCalls: value.capabilities.parallelToolCalls,
        customTools: value.capabilities.customTools,
        freeformTools: value.capabilities.freeformTools,
        instructionSnapshotOverrides:
            value.capabilities.instructionSnapshotOverrides,
        nativeContextFamily: await optional(
          value.capabilities.nativeContextFamily,
        ),
      ),
      reasoning: reasoning == null
          ? null
          : ModelReasoningDescriptor(
              parameter: await string(reasoning.parameter),
              label: await string(reasoning.label),
              defaultValue: await optional(reasoning.defaultValue),
              candidates: await stringList(reasoning.candidates),
            ),
      pricing: pricing == null ? null : await _pricing(pricing),
    );
  }

  Future<ModelTypeSupport> _support(ModelTypeSupportRead value) async {
    final items = await readModelList<ModelTypeExclusionReadItem>(
      value.exclusions,
      (offset) async {
        final page = await typeExclusions(
          value.exclusions.listId,
          offset: offset,
          limit: 32,
        );
        return (
          listId: page.listId,
          offset: page.offset,
          total: page.total,
          items: page.items,
          nextOffset: page.nextOffset,
        );
      },
    );
    return ModelTypeSupport(
      modelType: value.modelType,
      exclusions: List.unmodifiable([for (final item in items) item.value]),
    );
  }

  Future<ModelInputCapability> inputCapability(
    ModelInputCapabilityRead value,
  ) async {
    final items = await readModelList<ModelInputSourceReadItem>(value.sources, (
      offset,
    ) async {
      final page = await inputSources(
        value.sources.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return ModelInputCapability(
      modality: value.modality,
      sources: List.unmodifiable([for (final item in items) item.value]),
      maxCount: value.maxCount,
      maxBytes: value.maxBytes,
      maxTotalBytes: value.maxTotalBytes,
      maxWidth: value.maxWidth,
      maxHeight: value.maxHeight,
      mediaTypes: await stringList(value.mediaTypes),
    );
  }

  Future<ModelPricing> _pricing(ModelPricingRead value) async {
    final items = await readModelList<ModelPriceTierRead>(value.tiers, (
      offset,
    ) async {
      final page = await priceTiers(
        value.tiers.listId,
        offset: offset,
        limit: 32,
      );
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return ModelPricing(
      currency: await string(value.currency),
      tiers: List.unmodifiable([
        for (final item in items)
          ModelPriceTier(
            label: await string(item.label),
            inputPerMtok: item.inputPerMtok,
            outputPerMtok: item.outputPerMtok,
            cacheReadPerMtok: item.cacheReadPerMtok,
            cacheWritePerMtok: item.cacheWritePerMtok,
          ),
      ]),
      source: await string(value.source),
      verifiedAt: value.verifiedAt,
    );
  }
}

/// Collection materialization is only available to catalog/template scopes,
/// never faked for an exact-model reference query.
final class ModelReadAccess extends ModelFieldReadAccess {
  ModelReadAccess.catalog(ModelCatalogReadConnection scope)
    : models = scope.models,
      super(scope);
  ModelReadAccess.templates(AccountTemplatesReadConnection scope)
    : models = scope.models,
      super(scope);

  final Future<ModelDescriptorReadPage> Function(int, {int offset, int limit})
  models;

  Future<List<ModelDescriptor>> modelList(TypedListRef reference) async {
    final items = await readModelList<ModelDescriptorRead>(reference, (
      offset,
    ) async {
      final page = await models(reference.listId, offset: offset, limit: 32);
      return (
        listId: page.listId,
        offset: page.offset,
        total: page.total,
        items: page.items,
        nextOffset: page.nextOffset,
      );
    });
    return List.unmodifiable([for (final item in items) await model(item)]);
  }

  Future<AccountCatalogEntry> account(AccountCatalogEntryRead value) async =>
      AccountCatalogEntry(
        accountId: await string(value.accountId),
        credentialRequired: value.credentialRequired,
        capabilitySource: await string(value.capabilitySource),
        hostedWebSearch: value.hostedWebSearch,
        hostedWebSearchDialect: await string(value.hostedWebSearchDialect),
        standaloneWebSearch: await optional(value.standaloneWebSearch),
        promptCacheDialect: await string(value.promptCacheDialect),
        responsesProgrammaticToolCalling:
            value.responsesProgrammaticToolCalling,
        defaultModelId: await string(value.defaultModelId),
        effectiveModels: await modelList(value.effectiveModels),
        modelCatalog: ModelCatalogStatus(
          supported: value.modelCatalog.supported,
          source: value.modelCatalog.source,
          probing: value.modelCatalog.probing,
          lastSuccessAt: value.modelCatalog.lastSuccessAt,
          checkedAt: value.modelCatalog.checkedAt,
          error: value.modelCatalog.error,
          cacheWarning: value.modelCatalog.cacheWarning,
        ),
      );
}

typedef ModelListPage<T> = ({
  int listId,
  int offset,
  int total,
  List<T> items,
  int? nextOffset,
});

Future<List<T>> readModelList<T>(
  TypedListRef reference,
  Future<ModelListPage<T>> Function(int) read,
) async {
  if (reference.total < 0)
    throw resourceProtocol('A typed model list has a negative length.');
  final items = <T>[];
  var offset = 0;
  while (offset < reference.total) {
    final page = await read(offset);
    final end = offset + page.items.length;
    if (page.listId != reference.listId ||
        page.offset != offset ||
        page.total != reference.total ||
        page.items.length > 32 ||
        end < offset ||
        end > reference.total ||
        page.items.isEmpty ||
        page.nextOffset != (end == reference.total ? null : end)) {
      throw resourceProtocol(
        'A typed model list page does not belong to its pinned field.',
      );
    }
    items.addAll(page.items);
    offset = end;
  }
  return List.unmodifiable(items);
}

Future<String> readModelText(
  ReadText value,
  Future<TextChunk> Function(int, {int offset, int maxBytes}) read,
) async {
  if (value case InlineReadText(:final text)) {
    if (utf8.encode(text).length > 4096)
      throw resourceProtocol(
        'An inline model text exceeds the native inline limit.',
      );
    return text;
  }
  final deferred = value as DeferredReadText;
  if (deferred.utf8Bytes < 0)
    throw resourceProtocol('A deferred model text has an invalid length.');
  final text = StringBuffer();
  var offset = 0;
  while (offset < deferred.utf8Bytes) {
    final maximum = math.min(65536, deferred.utf8Bytes - offset);
    final chunk = await read(
      deferred.fieldId,
      offset: offset,
      maxBytes: maximum,
    );
    final bytes = utf8.encode(chunk.text).length;
    final end = offset + bytes;
    if (chunk.fieldId != deferred.fieldId ||
        chunk.offset != offset ||
        bytes == 0 ||
        bytes > maximum ||
        end < offset ||
        end > deferred.utf8Bytes ||
        chunk.nextOffset != (end == deferred.utf8Bytes ? null : end)) {
      throw resourceProtocol(
        'A model text chunk does not belong to its pinned field.',
      );
    }
    text.write(chunk.text);
    offset = end;
  }
  return text.toString();
}
