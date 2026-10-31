import 'acp_install_journey.dart';

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

void _expectStateError(void Function() body, String description) {
  try {
    body();
  } on StateError {
    return;
  }
  throw StateError('expected rejection: $description');
}

void main() {
  bool ready(String? kind, {int revision = 2, bool hasUsage = true}) =>
      acpUsageQueryReady(
        kind,
        revision: revision,
        afterRevision: 1,
        hasUsage: hasUsage,
      );
  for (final phase in ['checking', 'verifying', 'closing']) {
    if (ready(phase)) {
      throw StateError('query completed before cleanup: $phase');
    }
  }
  if (!ready('verified') ||
      ready('verified', revision: 1) ||
      ready('verified', hasUsage: false)) {
    throw StateError('query completion lost its revision or usage barrier');
  }
  for (final terminal in ['required', 'failed', 'cancelled', null]) {
    _expectStateError(() => ready(terminal), 'unsuccessful terminal $terminal');
  }

  const identity = (accountId: 'fixture-account', connectionRevision: 12);
  final usage = requireAcpFixtureUsage(_snapshot(), identity);
  if (usage['checkedAt'] != 1790000000 ||
      (usage['state'] as Map)['kind'] != 'ready') {
    throw StateError('complete fixture usage did not pass');
  }
  _expectStateError(
    () => requireAcpFixtureUsage(_snapshot(authKind: 'required'), identity),
    'retained quota after authentication was revoked',
  );

  _expectStateError(
    () => requireAcpFixtureUsage(
      _snapshot(accountId: 'different-account'),
      identity,
    ),
    'different account id',
  );
  _expectStateError(
    () => requireAcpFixtureUsage(_snapshot(connectionRevision: 13), identity),
    'different connection revision',
  );
  _expectStateError(
    () => requireAcpFixtureUsage(_snapshot(percentage: 90), identity),
    'changed percentage',
  );
  _expectStateError(
    () => requireAcpFixtureUsage(_snapshot(nextResetAt: 1790929321), identity),
    'changed reset time',
  );
  _expectStateError(
    () => requireAcpFixtureUsage(
      _snapshot(includeDisabledLimit: false),
      identity,
    ),
    'omitted disabled limit',
  );
}
