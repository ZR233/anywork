/// Pure Dart account-feature selectors for Driver and Widget Previewer.
///
/// Values include account kind so Native and ACP IDs cannot share a target.
/// No Flutter, generated presentation, SDK or application owner dependency.
library;

import 'dart:convert';

abstract final class AccountViewKeyValues {
  static String template(String kind, String id) =>
      'accounts-template:${jsonEncode([kind, id])}';
  static String row(String kind, String id) =>
      'accounts-row:${jsonEncode([kind, id])}';
  static String rowMenu(String kind, String id) =>
      'accounts-row-menu:${jsonEncode([kind, id])}';
  static String modelEnabled(String kind, String accountId, String modelId) =>
      'accounts-model-enabled:${jsonEncode([kind, accountId, modelId])}';
  static String modelDetails(String kind, String accountId, String modelId) =>
      'accounts-model-details:${jsonEncode([kind, accountId, modelId])}';
  static String modelItem(String kind, String accountId, String modelId) =>
      'accounts-model-item:${jsonEncode([kind, accountId, modelId])}';
  static String detailsScroll(String kind, String id) =>
      'accounts-details-scroll:${jsonEncode([kind, id])}';
  static String editorScroll(String kind, String editorId) =>
      'accounts-editor-scroll:${jsonEncode([kind, editorId])}';
  static String manualItem(String editorKey) =>
      'accounts-manual-item:${jsonEncode(editorKey)}';
  static String editorField(String editorId, String field) =>
      'accounts-editor-field:${jsonEncode([editorId, field])}';
  static String manualField(String editorKey, String field) =>
      'accounts-manual-field:${jsonEncode([editorKey, field])}';
  static String acpAction(String action) => 'accounts-acp-action:$action';
}
