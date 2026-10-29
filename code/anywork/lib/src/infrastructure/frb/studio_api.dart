import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show visibleForTesting, ValueNotifier, debugPrint;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

import '../../domain/models/studio_models.dart';

import 'package:anywork_client/studio_ports.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/conversation_ports.dart';

import '../../rust/api/studio/types/chat/descriptor.dart' as frb_descriptor;

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp_ports.dart';
export 'package:anywork_client/studio_ports.dart';

import '../../platform/error_log.dart';
import 'studio_bridge_api.dart' as frb;
import 'usage_diagnostics.dart';
import '../../rust/api/studio/subscription/product_topic.dart' as frb_topic_sub;
import '../../rust/api/studio/subscription/shutdown.dart' as frb_shutdown_sub;
import '../../rust/api/studio/subscription/startup.dart' as frb_startup_sub;
import '../../rust/api/studio/types/product_topic.dart' as frb_topic_types;
import '../../rust/api/studio/handlers/chat.dart' as frb_chat;
import '../../rust/api/studio/handlers/mode_editor.dart' as frb_mode_editor;
import '../../rust/api/studio/types/chat.dart' as frb_chat_types;
import '../../rust/api/studio/types/command.dart' as frb_command;
import '../../rust/api/studio/handlers/attachment.dart' as frb_attachment;
import '../../rust/api/studio/handlers/ssh.dart' as frb_ssh;
import '../../rust/api/studio/types/attachment.dart' as frb_attachment_types;
import '../../rust/api/studio/types/ssh.dart' as frb_ssh_types;
import '../../rust/api/studio/types/shutdown.dart' as frb_shutdown;
import '../../rust/api/studio/types/thread_stream/item.dart' as frb_item;
import '../../rust/api/studio/types/thread_activity.dart' as frb_activity;
import '../../rust/api/studio/types/mode_editor.dart' as frb_mode_types;
import '../../rust/api/studio/handlers/bots.dart' as frb_bots;
import '../../rust/api/studio/accounts/types.dart' as frb_accounts;
import '../../rust/api/studio/accounts/feed.dart' as frb_account_feed;
import '../../rust/api/studio/accounts/commands.dart' as frb_account_commands;
import '../../rust/api/studio/types/bots.dart' as frb_bots_types;
import '../../rust/frb_generated.dart';
import '../demo/accounts/demo_account_observation.dart';

part 'studio_thread_stream.dart';
part 'studio_thread_preparation.dart';
part 'studio_conversation.dart';
part 'studio_conversation_descriptor.dart';
part 'studio_conversation_tool.dart';
part 'studio_demo_conversation.dart';
part 'studio_api_contract.dart';
part 'studio_frb_converters.dart';
part 'studio_state_converters.dart';
part 'studio_settings_converters.dart';
part 'studio_account_catalog_converters.dart';
part 'studio_acp_converters.dart';
part 'studio_delegation_converters.dart';
part 'studio_bots_converters.dart';
part 'studio_demo_api.dart';
part 'studio_demo_settings.dart';

PermissionMode _permissionMode(Object? value) {
  return switch (_string(value)) {
    'request-approval' => PermissionMode.requestApproval,
    'auto-review' => PermissionMode.autoReview,
    'full-access' => PermissionMode.fullAccess,
    final label => throw FormatException('Unknown permission mode: $label'),
  };
}

String _permissionModeLabel(PermissionMode mode) {
  return switch (mode) {
    PermissionMode.requestApproval => 'request-approval',
    PermissionMode.autoReview => 'auto-review',
    PermissionMode.fullAccess => 'full-access',
  };
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  if (value is String) {
    return value.isEmpty ? fallback : value;
  }
  return value.toString();
}

int _frbInt(Object value) {
  if (value is BigInt) {
    return value.toInt();
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.parse(value.toString());
}

int? _frbNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  return _frbInt(value);
}

DateTime _dateFromUnix(Object seconds) {
  final value = switch (seconds) {
    final BigInt value => value,
    final int value => BigInt.from(value),
    _ => throw const StudioFailure(
      code: StudioFailureCode.internal,
      message: 'The bridge timestamp is not an integer',
      retryable: false,
      correlationId: 'client-timestamp-type',
    ),
  };
  final milliseconds = value * BigInt.from(1000);
  final converted = milliseconds.toInt();
  if (BigInt.from(converted) == milliseconds) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(converted);
    } on ArgumentError {
      // A valid native timestamp must not wrap into another instant.
    }
  }
  throw const StudioFailure(
    code: StudioFailureCode.overloaded,
    message: 'The bridge timestamp cannot be represented exactly',
    retryable: false,
    correlationId: 'client-timestamp-range',
  );
}

ThreadRuntimeView _emptyRuntimeView() {
  return const ThreadRuntimeView(
    modelId: '',
    contextTokens: 0,
    contextWindow: 0,
    totalTokens: 0,
    costLabel: '',
    activeSkills: [],
    activeMcpServers: [],
    activeLspServers: [],
  );
}

String _jsonText(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}
