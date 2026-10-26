// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bots_settings_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotsSettingsViewState {


/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsSettingsViewStateCopyWith<BotsSettingsViewState> get copyWith => _$BotsSettingsViewStateCopyWithImpl<BotsSettingsViewState>(this as BotsSettingsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotsSettingsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsSettingsViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.messages, _this.messages) || other.messages == _this.messages)&&(identical(other.sends, _this.sends) || other.sends == _this.sends)&&(identical(other.selectedBotId, _this.selectedBotId) || other.selectedBotId == _this.selectedBotId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.messageDraft, _this.messageDraft) || other.messageDraft == _this.messageDraft)&&(identical(other.draftRevision, _this.draftRevision) || other.draftRevision == _this.draftRevision)&&(identical(other.visible, _this.visible) || other.visible == _this.visible)&&(identical(other.synchronizing, _this.synchronizing) || other.synchronizing == _this.synchronizing)&&(identical(other.readingStatus, _this.readingStatus) || other.readingStatus == _this.readingStatus)&&(identical(other.readingMessages, _this.readingMessages) || other.readingMessages == _this.readingMessages)&&(identical(other.syncIssue, _this.syncIssue) || other.syncIssue == _this.syncIssue)&&(identical(other.statusIssue, _this.statusIssue) || other.statusIssue == _this.statusIssue)&&(identical(other.observationIssue, _this.observationIssue) || other.observationIssue == _this.observationIssue)&&(identical(other.messageIssue, _this.messageIssue) || other.messageIssue == _this.messageIssue)&&(identical(other.draftIssue, _this.draftIssue) || other.draftIssue == _this.draftIssue)&&(identical(other.registrationAction, _this.registrationAction) || other.registrationAction == _this.registrationAction)&&const DeepCollectionEquality().equals(other.botActions, _this.botActions)&&const DeepCollectionEquality().equals(other.messageActions, _this.messageActions));
}


@override
int get hashCode {
  final _this = this as BotsSettingsViewState;
  return Object.hashAll([runtimeType,_this.source,_this.messages,_this.sends,_this.selectedBotId,_this.chatId,_this.messageDraft,_this.draftRevision,_this.visible,_this.synchronizing,_this.readingStatus,_this.readingMessages,_this.syncIssue,_this.statusIssue,_this.observationIssue,_this.messageIssue,_this.draftIssue,_this.registrationAction,const DeepCollectionEquality().hash(_this.botActions),const DeepCollectionEquality().hash(_this.messageActions)]);
}



}

/// @nodoc
abstract mixin class $BotsSettingsViewStateCopyWith<$Res>  {
  factory $BotsSettingsViewStateCopyWith(BotsSettingsViewState value, $Res Function(BotsSettingsViewState) _then) = _$BotsSettingsViewStateCopyWithImpl;
@useResult
$Res call({
 BotsState source, BotMessagesState messages, BotSendsState sends, String? selectedBotId, String chatId, String messageDraft, int draftRevision, bool visible, bool synchronizing, bool readingStatus, bool readingMessages, StudioFailure? syncIssue, StudioFailure? statusIssue, StudioFailure? observationIssue, StudioFailure? messageIssue, StudioFailure? draftIssue, SettingsAction? registrationAction, Map<String, SettingsAction> botActions, Map<BotsChatTarget, BotsMessageAction> messageActions
});


$BotsStateCopyWith<$Res> get source;$BotMessagesStateCopyWith<$Res> get messages;$BotSendsStateCopyWith<$Res> get sends;$StudioFailureCopyWith<$Res>? get syncIssue;$StudioFailureCopyWith<$Res>? get statusIssue;$StudioFailureCopyWith<$Res>? get observationIssue;$StudioFailureCopyWith<$Res>? get messageIssue;$StudioFailureCopyWith<$Res>? get draftIssue;$SettingsActionCopyWith<$Res>? get registrationAction;

}
/// @nodoc
class _$BotsSettingsViewStateCopyWithImpl<$Res>
    implements $BotsSettingsViewStateCopyWith<$Res> {
  _$BotsSettingsViewStateCopyWithImpl(this._self, this._then);

  final BotsSettingsViewState _self;
  final $Res Function(BotsSettingsViewState) _then;

/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? messages = null,Object? sends = null,Object? selectedBotId = freezed,Object? chatId = null,Object? messageDraft = null,Object? draftRevision = null,Object? visible = null,Object? synchronizing = null,Object? readingStatus = null,Object? readingMessages = null,Object? syncIssue = freezed,Object? statusIssue = freezed,Object? observationIssue = freezed,Object? messageIssue = freezed,Object? draftIssue = freezed,Object? registrationAction = freezed,Object? botActions = null,Object? messageActions = null,}) {
  return _then(BotsSettingsViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as BotsState,messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as BotMessagesState,sends: null == sends ? _self.sends : sends // ignore: cast_nullable_to_non_nullable
as BotSendsState,selectedBotId: freezed == selectedBotId ? _self.selectedBotId : selectedBotId // ignore: cast_nullable_to_non_nullable
as String?,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,messageDraft: null == messageDraft ? _self.messageDraft : messageDraft // ignore: cast_nullable_to_non_nullable
as String,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,synchronizing: null == synchronizing ? _self.synchronizing : synchronizing // ignore: cast_nullable_to_non_nullable
as bool,readingStatus: null == readingStatus ? _self.readingStatus : readingStatus // ignore: cast_nullable_to_non_nullable
as bool,readingMessages: null == readingMessages ? _self.readingMessages : readingMessages // ignore: cast_nullable_to_non_nullable
as bool,syncIssue: freezed == syncIssue ? _self.syncIssue : syncIssue // ignore: cast_nullable_to_non_nullable
as StudioFailure?,statusIssue: freezed == statusIssue ? _self.statusIssue : statusIssue // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationIssue: freezed == observationIssue ? _self.observationIssue : observationIssue // ignore: cast_nullable_to_non_nullable
as StudioFailure?,messageIssue: freezed == messageIssue ? _self.messageIssue : messageIssue // ignore: cast_nullable_to_non_nullable
as StudioFailure?,draftIssue: freezed == draftIssue ? _self.draftIssue : draftIssue // ignore: cast_nullable_to_non_nullable
as StudioFailure?,registrationAction: freezed == registrationAction ? _self.registrationAction : registrationAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,botActions: null == botActions ? _self.botActions : botActions // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsAction>,messageActions: null == messageActions ? _self.messageActions : messageActions // ignore: cast_nullable_to_non_nullable
as Map<BotsChatTarget, BotsMessageAction>,
  ));
}
/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsStateCopyWith<$Res> get source {

  return $BotsStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotMessagesStateCopyWith<$Res> get messages {

  return $BotMessagesStateCopyWith<$Res>(_self.messages, (value) {
    return _then(_self.copyWith(messages: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSendsStateCopyWith<$Res> get sends {

  return $BotSendsStateCopyWith<$Res>(_self.sends, (value) {
    return _then(_self.copyWith(sends: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get syncIssue {
    if (_self.syncIssue == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.syncIssue!, (value) {
    return _then(_self.copyWith(syncIssue: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get statusIssue {
    if (_self.statusIssue == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.statusIssue!, (value) {
    return _then(_self.copyWith(statusIssue: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationIssue {
    if (_self.observationIssue == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationIssue!, (value) {
    return _then(_self.copyWith(observationIssue: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get messageIssue {
    if (_self.messageIssue == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.messageIssue!, (value) {
    return _then(_self.copyWith(messageIssue: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get draftIssue {
    if (_self.draftIssue == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.draftIssue!, (value) {
    return _then(_self.copyWith(draftIssue: value));
  });
}/// Create a copy of BotsSettingsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get registrationAction {
    if (_self.registrationAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.registrationAction!, (value) {
    return _then(_self.copyWith(registrationAction: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotsSettingsViewState].
extension BotsSettingsViewStatePatterns on BotsSettingsViewState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

// dart format on
