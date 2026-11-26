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
import 'package:anywork_client/lifecycle.dart';
import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/conversation.dart'
    show ConversationContinuityError, ProtocolVersionMismatch;

import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/accounts_ports.dart';
import 'package:anywork_client/model_directory.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/acp_sessions.dart' as acp_business;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show PanicException, AnyhowException;

import '../../rust/api/studio/handlers/acp_business.dart' as frb_acp_business;
import '../../rust/api/studio/handlers/acp_business/feed.dart' as frb_acp_feed;
import '../../rust/api/studio/types/acp_business.dart' as frb_acp_types;
import 'studio_acp_business_mapper.dart' as acp_mapper;

export 'package:anywork_client/studio_ports.dart';

import '../../platform/error_log.dart';
import 'studio_bridge_api.dart' as frb;
import 'studio_bridge_error.dart';
import 'studio_interaction_converters.dart';
import 'studio_numeric_converters.dart';
import 'studio_workflow_converters.dart';
import '../../rust/api/studio/types/thread_lsp.dart' as frb_thread_lsp_types;
import 'usage_diagnostics.dart';
import '../../rust/api/studio/subscription/product_topic.dart' as frb_topic_sub;
import '../../rust/api/studio/subscription/shutdown.dart' as frb_shutdown_sub;
import '../../rust/api/studio/subscription/startup.dart' as frb_startup_sub;
import '../../rust/api/studio/types/product_topic.dart' as frb_topic_types;
import '../../rust/api/studio/handlers/timeline.dart' as frb_timeline;
import '../../rust/api/studio/handlers/mode_editor.dart' as frb_mode_editor;
import '../../rust/api/studio/types/chat.dart' as frb_chat_types;
import '../../rust/api/studio/types/presentation.dart' as frb_presentation;
import '../../rust/api/studio/types/thread_activity.dart' as frb_activity;
import '../../rust/api/studio/types/command.dart' as frb_command;
import '../../rust/api/studio/handlers/attachment.dart' as frb_attachment;
import '../../rust/api/studio/handlers/ssh.dart' as frb_ssh;
import '../../rust/api/studio/types/attachment.dart' as frb_attachment_types;
import '../../rust/api/studio/types/ssh.dart' as frb_ssh_types;
import '../../rust/api/studio/types/shutdown.dart' as frb_shutdown;
import '../../rust/api/studio/types/thread_stream/item.dart' as frb_item;
import '../../rust/api/studio/types/mode_editor.dart' as frb_mode_types;
import '../../rust/api/studio/handlers/bots.dart' as frb_bots;
import '../../rust/api/studio/accounts/types.dart' as frb_accounts;
import '../../rust/api/studio/accounts/chatgpt.dart' as frb_account_chatgpt;
import '../../rust/api/studio/types/chatgpt_auth.dart' as frb_chatgpt;
import '../../rust/api/studio/accounts/feed.dart' as frb_account_feed;
import '../../rust/api/studio/directory/feed.dart' as frb_directory_feed;
import '../../rust/api/studio/directory/types.dart' as frb_directory_types;
import '../../rust/api/studio/accounts/commands.dart' as frb_account_commands;
import '../../rust/api/studio/types/bots.dart' as frb_bots_types;
import '../../rust/frb_generated.dart';
part 'studio_thread_stream.dart';
part 'studio_thread_preparation.dart';
part 'studio_timeline.dart';
part 'studio_presentation_converters.dart';
part 'studio_api_contract.dart';
part 'frb_runtime_owner.dart';
part 'studio_frb_converters.dart';
part 'studio_state_converters.dart';
part 'studio_settings_converters.dart';
part 'studio_account_catalog_converters.dart';
part 'studio_acp_converters.dart';
part 'studio_acp_business_port.dart';
part 'studio_delegation_converters.dart';
part 'studio_bots_converters.dart';

PermissionMode _permissionMode(String label) => switch (label) {
  'request-approval' => PermissionMode.requestApproval,
  'auto-review' => PermissionMode.autoReview,
  'full-access' => PermissionMode.fullAccess,
  _ => throw FormatException('Unknown permission mode: $label'),
};

String _permissionModeLabel(PermissionMode mode) {
  return switch (mode) {
    PermissionMode.requestApproval => 'request-approval',
    PermissionMode.autoReview => 'auto-review',
    PermissionMode.fullAccess => 'full-access',
  };
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
