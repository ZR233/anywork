import 'dart:convert';

class DriverAttachmentObservation {
  const DriverAttachmentObservation({
    required this.id,
    required this.name,
    required this.modality,
    required this.previewReady,
    this.byteSize,
  });

  final String id;
  final String name;
  final String? modality;
  final bool? previewReady;
  final int? byteSize;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'modality': modality,
    'previewReady': previewReady,
    'byteSize': byteSize,
  };
}

class DriverComposerAttachmentObservation {
  const DriverComposerAttachmentObservation({
    required this.present,
    required this.previewReady,
    required this.attachments,
    this.attachmentGeneration,
    this.submissionPending,
    this.failed,
  });

  final bool? present;
  final bool? previewReady;
  final List<DriverAttachmentObservation> attachments;
  final int? attachmentGeneration;
  final bool? submissionPending;
  final bool? failed;

  Map<String, Object?> toJson() => {
    'present': present,
    'previewReady': previewReady,
    'attachmentGeneration': attachmentGeneration,
    'submissionPending': submissionPending,
    'failed': failed,
    'attachments': [for (final attachment in attachments) attachment.toJson()],
  };
}

DriverComposerAttachmentObservation driverComposerAttachments(
  Map<String, dynamic> snapshot, {
  String target = 'thread',
}) {
  final diagnostics = snapshot['driverDiagnostics'];
  final composer = diagnostics is Map ? diagnostics['composer'] : null;
  final targetValue = composer is Map ? composer[target] : null;
  if (targetValue is! Map) {
    return const DriverComposerAttachmentObservation(
      present: null,
      previewReady: null,
      attachments: [],
    );
  }
  final attachments = <DriverAttachmentObservation>[];
  final rawAttachments = targetValue['attachments'];
  if (rawAttachments is List) {
    for (final raw in rawAttachments) {
      if (raw is! Map || raw['id'] is! String) continue;
      attachments.add(
        DriverAttachmentObservation(
          id: raw['id'] as String,
          name: raw['name'] is String ? raw['name'] as String : '',
          modality: raw['modality'] as String?,
          previewReady: raw['previewReady'] as bool?,
          byteSize: _int(raw['byteSize']),
        ),
      );
    }
  }
  final previewReady = targetValue['previewReady'];
  return DriverComposerAttachmentObservation(
    present: targetValue['present'] as bool? ?? attachments.isNotEmpty,
    previewReady: previewReady is bool
        ? previewReady
        : attachments.isNotEmpty &&
              attachments.every(
                (attachment) => attachment.previewReady == true,
              ),
    attachments: attachments,
    attachmentGeneration: _int(targetValue['attachmentGeneration']),
    submissionPending: targetValue['submissionPending'] as bool?,
    failed: targetValue['failed'] as bool?,
  );
}

List<Map<String, dynamic>> driverAccountListObservation(
  Map<String, dynamic> snapshot,
) {
  final accounts = _accountObservation(snapshot)?['list'];
  if (accounts is! List) return const [];
  return [
    for (final account in accounts)
      if (account is Map) account.cast<String, dynamic>(),
  ];
}

List<Map<String, dynamic>> driverAccountDetailsObservation(
  Map<String, dynamic> snapshot,
) {
  final accounts = _accountObservation(snapshot)?['details'];
  if (accounts is! List) return const [];
  return [
    for (final account in accounts)
      if (account is Map) account.cast<String, dynamic>(),
  ];
}

Map<String, dynamic>? _accountObservation(Map<String, dynamic> snapshot) {
  final diagnostics = snapshot['driverDiagnostics'];
  final accounts = diagnostics is Map ? diagnostics['accounts'] : null;
  return accounts is Map ? accounts.cast<String, dynamic>() : null;
}

/// Verifies the list/detail split without treating a detail model modelId as a
/// list label. The list projection is deliberately metadata-only; model model_ids
/// remain observable only in the detail projection.
void verifyAccountListRedacted(
  Map<String, dynamic> snapshot, {
  required String fixtureModelId,
  String? accountId,
}) {
  final list = driverAccountListObservation(snapshot);
  if (list.isEmpty) {
    throw StateError('account list observation is unavailable');
  }
  final encodedList = jsonEncode(list);
  if (encodedList.contains(fixtureModelId)) {
    throw StateError(
      'account list observation leaked fixture model modelId $fixtureModelId',
    );
  }
  if (RegExp(r'\+\d+').hasMatch(encodedList)) {
    throw StateError('account list observation leaked a +N model label');
  }

  final details = driverAccountDetailsObservation(snapshot);
  final matchingAccount = accountId == null
      ? details
      : details.where((account) => account['id'] == accountId).toList();
  final hasModelDetail = matchingAccount.any((account) {
    final models = account['models'];
    return models is List &&
        models.any(
          (model) => model is Map && model['modelId'] == fixtureModelId,
        );
  });
  if (!hasModelDetail) {
    throw StateError(
      'account detail observation omitted fixture model $fixtureModelId',
    );
  }
}

int? _int(Object? value) => value is num ? value.toInt() : null;
