import 'package:flutter_test/flutter_test.dart';

import '../support/acp_install_contract.dart';

Map<String, dynamic> _snapshot({
  String accountId = 'fixture-account',
  int connectionRevision = 12,
  int percentage = 91,
  int nextResetAt = 1790929320,
  bool includeDisabledLimit = true,
  String authKind = 'verified',
}) => {
  'settings': {
    'acpAccounts': [
      {
        'accountId': accountId,
        'name': 'Fixture',
        'provider': 'antigravity',
        'connectionRevision': connectionRevision,
      },
    ],
    'acpAuth': {
      'loaded': true,
      'accounts': [
        {
          'accountId': accountId,
          'connectionRevision': connectionRevision,
          'state': {'kind': authKind},
          'usage': {
            'checkedAt': 1790000000,
            'state': {
              'kind': 'ready',
              'groups': [
                {
                  'name': 'Gemini Models',
                  'limits': [
                    {
                      'label': 'Weekly Limit Remaining',
                      'remaining': {'kind': 'percentage', 'value': percentage},
                      'nextResetAt': nextResetAt,
                    },
                    {
                      'label': 'Burst Limit',
                      'remaining': {'kind': 'units', 'value': 1234},
                      'nextResetAt': null,
                    },
                  ],
                },
                {
                  'name': 'Disabled Models',
                  'limits': [
                    if (includeDisabledLimit)
                      {
                        'label': 'Legacy Limit',
                        'remaining': {'kind': 'disabled'},
                        'nextResetAt': null,
                      },
                  ],
                },
              ],
            },
          },
        },
      ],
    },
  },
};

void main() {
  test(
    'usage query stays busy until verified, newer revision and usage exist',
    () {
      bool ready(String? kind, {int revision = 2, bool hasUsage = true}) =>
          acpUsageQueryReady(
            kind,
            revision: revision,
            afterRevision: 1,
            hasUsage: hasUsage,
          );
      for (final phase in ['checking', 'verifying', 'closing']) {
        expect(ready(phase), isFalse, reason: phase);
      }
      expect(ready('verified'), isTrue);
      expect(ready('verified', revision: 1), isFalse);
      expect(ready('verified', hasUsage: false), isFalse);
      for (final terminal in ['required', 'failed', 'cancelled', null]) {
        expect(() => ready(terminal), throwsStateError, reason: '$terminal');
      }
    },
  );

  test('fixture usage binds quota to the saved identity and rejects drift', () {
    const identity = (accountId: 'fixture-account', connectionRevision: 12);
    final usage = requireAcpFixtureUsage(_snapshot(), identity);
    expect(usage['checkedAt'], 1790000000);
    expect((usage['state'] as Map)['kind'], 'ready');
    expect(
      () => requireAcpFixtureUsage(_snapshot(authKind: 'required'), identity),
      throwsStateError,
    );
    expect(
      () => requireAcpFixtureUsage(
        _snapshot(accountId: 'different-account'),
        identity,
      ),
      throwsStateError,
    );
    expect(
      () => requireAcpFixtureUsage(_snapshot(connectionRevision: 13), identity),
      throwsStateError,
    );
    expect(
      () => requireAcpFixtureUsage(_snapshot(percentage: 90), identity),
      throwsStateError,
    );
    expect(
      () =>
          requireAcpFixtureUsage(_snapshot(nextResetAt: 1790929321), identity),
      throwsStateError,
    );
    expect(
      () => requireAcpFixtureUsage(
        _snapshot(includeDisabledLimit: false),
        identity,
      ),
      throwsStateError,
    );
  });
}
