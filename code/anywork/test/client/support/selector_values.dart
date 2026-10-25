import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';

// Controlled View props only. No Repository, fallback or effort policy lives
// here; the keyboard tests exercise the real production selectors.
const selectorModes = [
  ThreadModeDescriptor(
    id: ThreadModeId.simple,
    displayName: '简洁',
    description: 'Simple',
    order: 0,
    hasWorkflow: false,
    readOnly: true,
  ),
  ThreadModeDescriptor(
    id: ThreadModeId.task,
    displayName: '任务',
    description: 'Task',
    order: 1,
    hasWorkflow: true,
    readOnly: true,
  ),
];

ModelDescriptor selectorModel({String id = 'model', String name = 'Model'}) =>
    ModelDescriptor(
      modelId: id,
      enabled: true,
      typeSupport: [ModelTypeSupport(modelType: ModelType.text, exclusions: [])],
      origin: ModelOrigin.manual,
      displayName: name,
      description: null,
      contextWindow: 4096,
      maxContextWindow: 4096,
      context: const ModelContextResolution(
        unavailable: null,
        contextWindow: 4096,
        inputTokenLimit: 3072,
        autoCompactLimit: 2048,
        adjustment: null,
      ),
      maxOutputTokens: 1024,
      transport: ModelTransportDescriptor(
        protocol: 'openai',
        connectionModes: [],
        defaultConnectionMode: 'auto',
      ),
      capabilities: ModelCapabilities(
        input: [],
        output: [ModelModality.text],
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
      reasoning: ModelReasoningDescriptor(
        parameter: 'effort',
        label: 'Effort',
        defaultValue: 'medium',
        candidates: ['medium', 'high'],
      ),
      pricing: null,
    );
