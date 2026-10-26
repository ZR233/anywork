import 'package:anywork/src/features/conversation/presentation/artifact_links.dart';
import 'package:anywork_client/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opaque artifacts preserve ordered value traversal, prefix-only URLs, trim, deduplication and the six-link bound', () {
    final links = extractArtifactLinks(const [
      OpaqueArtifactJson(
        json: '''
{
  "http://a-key-is-not-a-link": [
    "  http://  ", " https://first.example/path ",
    {"nested": [false, null, 7, "HTTPS://not-selected", "http://two.example/"]}
  ],
  "next": ["https://first.example/path", "https://three.example/with a space"]
}
''',
      ),
      OpaqueArtifactJson(
        json: '''
[" https://three.example/with a space ", "http://four.example/", "https://five.example/", "https://outside-limit.example/"]
''',
      ),
    ]);
    expect(
      links,
      [
        'http://',
        'https://first.example/path',
        'http://two.example/',
        'https://three.example/with a space',
        'http://four.example/',
        'https://five.example/',
      ],
      reason: 'Do not add URL validation, key traversal or normalization at this presentation seam',
    );
  });

  test('malformed explicit artifact JSON is a visible decode failure without exposing its payload', () {
    const sentinel = 'synthetic-private-payload-not-for-errors';
    Object? failure;
    try {
      extractArtifactLinks(const [
        OpaqueArtifactJson(json: '{"secret":"$sentinel"'),
      ]);
    } catch (error) {
      failure = error;
    }
    expect(
      failure,
      isA<ArtifactLinksDecodeFailure>(),
      reason: 'Malformed JSON must not silently become a successful empty artifact list',
    );
    expect(failure.toString(), isNot(contains(sentinel)));
  });
}
