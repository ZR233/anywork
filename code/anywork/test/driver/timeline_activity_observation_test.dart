import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../test_driver/timeline_observation.dart';

Map<String, Object?> _textPart(
  String id,
  String text, {
  bool complete = false,
}) => {
  'itemId': id,
  'text': text,
  'byteLength': utf8.encode(text).length,
  'complete': complete,
};

Map<String, Object?> _tool(
  String callId,
  List<(String, String)> parts, {
  String state = 'running',
}) => {
  'callId': callId,
  'state': state,
  'outputParts': [
    for (final (partId, text) in parts)
      {'partId': partId, 'text': text, 'byteLength': utf8.encode(text).length},
  ],
};

String _observe({
  String identity = 'activity',
  String turnId = 'turn',
  String executionId = 'execution',
  List<Map<String, Object?>> responses = const [],
  List<Map<String, Object?>> reasoning = const [],
  List<Map<String, Object?>> tools = const [],
}) => conversationActivityContentObservation({
  'conversationActivity': {
    'identity': identity,
    'turnId': turnId,
    'executionId': executionId,
    'responseParts': responses,
    'reasoningParts': reasoning,
    'toolDetails': tools,
  },
})!;

void main() {
  test('new text sources establish a baseline before counting progress', () {
    final initial = _observe(responses: [_textPart('a', 'unchanged')]);
    expect(
      conversationActivityContentChanged(
        _observe(),
        _observe(responses: [_textPart('a', 'first observation')]),
      ),
      isFalse,
    );
    expect(
      conversationActivityContentChanged(
        initial,
        _observe(
          responses: [
            _textPart('a', 'unchanged'),
            _textPart('b', 'new source'),
          ],
        ),
      ),
      isFalse,
    );
    expect(
      conversationActivityContentChanged(
        initial,
        _observe(responses: [_textPart('b', 'different source')]),
      ),
      isFalse,
    );
    expect(
      conversationActivityContentChanged(
        initial,
        _observe(
          identity: 'another activity',
          responses: [_textPart('a', 'different text')],
        ),
      ),
      isFalse,
    );
  });

  test('tool progress requires the same call and part in both samples', () {
    final initial = _observe(
      tools: [
        _tool('call-a', [('stdout', 'unchanged')]),
      ],
    );
    for (final tool in [
      _tool('call-a', [('stdout', 'unchanged'), ('stderr', 'new part')]),
      _tool('call-b', [('stdout', 'different call')]),
    ]) {
      expect(
        conversationActivityContentChanged(initial, _observe(tools: [tool])),
        isFalse,
      );
    }
    expect(
      conversationActivityContentChanged(
        initial,
        _observe(
          tools: [
            _tool('call-a', [('stdout', 'changed')]),
          ],
        ),
      ),
      isTrue,
    );
  });

  test('same-source text changes count even with an unchanged byte length', () {
    expect(
      conversationActivityContentChanged(
        _observe(responses: [_textPart('a', '甲')]),
        _observe(responses: [_textPart('a', '乙')]),
      ),
      isTrue,
    );
    expect(
      conversationActivityContentChanged(
        _observe(reasoning: [_textPart('r', 'before')]),
        _observe(reasoning: [_textPart('r', 'after!')]),
      ),
      isTrue,
    );
  });

  test('status and structural changes cannot stand in for text progress', () {
    final initial = _observe(
      responses: [_textPart('a', 'one'), _textPart('b', 'two')],
      tools: [
        _tool('call', [('stdout', 'same')]),
      ],
    );
    final changedStructure = _observe(
      responses: [
        _textPart('b', 'two', complete: true),
        _textPart('a', 'one', complete: true),
      ],
      tools: [
        _tool('call', [('stdout', 'same')], state: 'completed'),
      ],
    );
    expect(initial, isNot(changedStructure));
    expect(
      conversationActivityContentChanged(initial, changedStructure),
      isFalse,
    );
  });

  test('evidence preserves raw text, part completion and tool state', () {
    final observation = jsonDecode(
      _observe(
        responses: [_textPart('a', '甲🐱', complete: true)],
        reasoning: [_textPart('r', '思考')],
        tools: [
          _tool('call', [('stdout', '原始\n输出')], state: 'completed'),
        ],
      ),
    ) as Map<String, dynamic>;
    final response = (observation['responseParts'] as List).single as Map;
    expect(response['complete'], isTrue);
    expect(response['text'], '甲🐱');
    expect(response['byteLength'], utf8.encode('甲🐱').length);
    final reasoning = (observation['reasoningParts'] as List).single as Map;
    expect(reasoning['complete'], isFalse);
    final tool = (observation['tools'] as List).single as Map;
    expect(tool['state'], 'completed');
    final output = (tool['outputParts'] as List).single as Map;
    expect(output['partId'], 'stdout');
    expect(output['text'], '原始\n输出');
    expect(output.containsKey('complete'), isFalse);
    expect(
      () => _observe(
        responses: [
          {..._textPart('a', '甲'), 'byteLength': 1},
        ],
      ),
      throwsStateError,
    );
  });
}
