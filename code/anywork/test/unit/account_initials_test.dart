import 'package:anywork/src/shared/account_brand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, initials) in const [
    ('', '?'),
    ('  \t\n', '?'),
    ('a', 'A'),
    ('openai', 'OP'),
    ('  azure   openai third  ', 'AO'),
    ('中文账号', '中文'),
    ('👩🏽‍💻开发', '👩🏽‍💻开'),
    ('👩🏽‍💻 team', '👩🏽‍💻T'),
    ('🇨🇳', '🇨🇳'),
    ('e\u0301clair', 'E\u0301C'),
    ('e\u0301quipe locale', 'E\u0301L'),
  ]) {
    test('account initials preserve visible characters in "$name"', () {
      expect(accountInitials(name), initials);
    });
  }
}
