// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_content.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadItemStateView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadItemStateView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadItemStateViewCopyWith<$Res>  {
$ThreadItemStateViewCopyWith(ThreadItemStateView _, $Res Function(ThreadItemStateView) __);
}


/// Adds pattern-matching-related methods to [ThreadItemStateView].
extension ThreadItemStateViewPatterns on ThreadItemStateView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadRawItemStateView value)?  raw,TResult Function( ThreadTextItemStateView value)?  text,TResult Function( ThreadThinkingItemStateView value)?  thinking,TResult Function( ThreadToolItemStateView value)?  tool,TResult Function( ThreadAgentItemStateView value)?  agent,TResult Function( ThreadTurnItemStateView value)?  turn,TResult Function( ThreadInferenceItemStateView value)?  inference,TResult Function( ThreadSkillItemStateView value)?  skill,TResult Function( ThreadFileItemStateView value)?  file,TResult Function( ThreadContextCompactionItemStateView value)?  contextCompaction,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadRawItemStateView() when raw != null:
return raw(_that);case ThreadTextItemStateView() when text != null:
return text(_that);case ThreadThinkingItemStateView() when thinking != null:
return thinking(_that);case ThreadToolItemStateView() when tool != null:
return tool(_that);case ThreadAgentItemStateView() when agent != null:
return agent(_that);case ThreadTurnItemStateView() when turn != null:
return turn(_that);case ThreadInferenceItemStateView() when inference != null:
return inference(_that);case ThreadSkillItemStateView() when skill != null:
return skill(_that);case ThreadFileItemStateView() when file != null:
return file(_that);case ThreadContextCompactionItemStateView() when contextCompaction != null:
return contextCompaction(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadRawItemStateView value)  raw,required TResult Function( ThreadTextItemStateView value)  text,required TResult Function( ThreadThinkingItemStateView value)  thinking,required TResult Function( ThreadToolItemStateView value)  tool,required TResult Function( ThreadAgentItemStateView value)  agent,required TResult Function( ThreadTurnItemStateView value)  turn,required TResult Function( ThreadInferenceItemStateView value)  inference,required TResult Function( ThreadSkillItemStateView value)  skill,required TResult Function( ThreadFileItemStateView value)  file,required TResult Function( ThreadContextCompactionItemStateView value)  contextCompaction,}){
final _that = this;
switch (_that) {
case ThreadRawItemStateView():
return raw(_that);case ThreadTextItemStateView():
return text(_that);case ThreadThinkingItemStateView():
return thinking(_that);case ThreadToolItemStateView():
return tool(_that);case ThreadAgentItemStateView():
return agent(_that);case ThreadTurnItemStateView():
return turn(_that);case ThreadInferenceItemStateView():
return inference(_that);case ThreadSkillItemStateView():
return skill(_that);case ThreadFileItemStateView():
return file(_that);case ThreadContextCompactionItemStateView():
return contextCompaction(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadRawItemStateView value)?  raw,TResult? Function( ThreadTextItemStateView value)?  text,TResult? Function( ThreadThinkingItemStateView value)?  thinking,TResult? Function( ThreadToolItemStateView value)?  tool,TResult? Function( ThreadAgentItemStateView value)?  agent,TResult? Function( ThreadTurnItemStateView value)?  turn,TResult? Function( ThreadInferenceItemStateView value)?  inference,TResult? Function( ThreadSkillItemStateView value)?  skill,TResult? Function( ThreadFileItemStateView value)?  file,TResult? Function( ThreadContextCompactionItemStateView value)?  contextCompaction,}){
final _that = this;
switch (_that) {
case ThreadRawItemStateView() when raw != null:
return raw(_that);case ThreadTextItemStateView() when text != null:
return text(_that);case ThreadThinkingItemStateView() when thinking != null:
return thinking(_that);case ThreadToolItemStateView() when tool != null:
return tool(_that);case ThreadAgentItemStateView() when agent != null:
return agent(_that);case ThreadTurnItemStateView() when turn != null:
return turn(_that);case ThreadInferenceItemStateView() when inference != null:
return inference(_that);case ThreadSkillItemStateView() when skill != null:
return skill(_that);case ThreadFileItemStateView() when file != null:
return file(_that);case ThreadContextCompactionItemStateView() when contextCompaction != null:
return contextCompaction(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<RawHistoryPayload> payloads,  String notice,  int recordedAt,  ThreadRawItemOrigin origin)?  raw,TResult Function( ThreadTextChannel channel,  String text,  List<ThreadAttachmentView> attachments,  ThreadContentLifecycleView lifecycle)?  text,TResult Function( List<String> summary,  List<String> content,  ThreadContentLifecycleView lifecycle,  int summaryChunkBase,  int contentChunkBase)?  thinking,TResult Function( ThreadToolInvocationView invocation,  ThreadToolLifecycleView lifecycle,  ThreadToolUserInputView? userInput,  ThreadWaitPresentationView? wait)?  tool,TResult Function( ThreadAgentIdentityView identity,  ThreadAgentLifecycleView lifecycle)?  agent,TResult Function( TurnState state,  String? inputId)?  turn,TResult Function( String inferenceId,  String model,  ThreadInferenceLifecycleView lifecycle)?  inference,TResult Function( String name,  String source,  String providerId,  SkillResourceBaseView resourceBase,  SkillActivationCauseView cause,  int activatedAt)?  skill,TResult Function( String path,  String? mediaType,  int completedAt)?  file,TResult Function( int? beforeTokens,  int? afterTokens,  int compactedAt)?  contextCompaction,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadRawItemStateView() when raw != null:
return raw(_that.payloads,_that.notice,_that.recordedAt,_that.origin);case ThreadTextItemStateView() when text != null:
return text(_that.channel,_that.text,_that.attachments,_that.lifecycle);case ThreadThinkingItemStateView() when thinking != null:
return thinking(_that.summary,_that.content,_that.lifecycle,_that.summaryChunkBase,_that.contentChunkBase);case ThreadToolItemStateView() when tool != null:
return tool(_that.invocation,_that.lifecycle,_that.userInput,_that.wait);case ThreadAgentItemStateView() when agent != null:
return agent(_that.identity,_that.lifecycle);case ThreadTurnItemStateView() when turn != null:
return turn(_that.state,_that.inputId);case ThreadInferenceItemStateView() when inference != null:
return inference(_that.inferenceId,_that.model,_that.lifecycle);case ThreadSkillItemStateView() when skill != null:
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case ThreadFileItemStateView() when file != null:
return file(_that.path,_that.mediaType,_that.completedAt);case ThreadContextCompactionItemStateView() when contextCompaction != null:
return contextCompaction(_that.beforeTokens,_that.afterTokens,_that.compactedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<RawHistoryPayload> payloads,  String notice,  int recordedAt,  ThreadRawItemOrigin origin)  raw,required TResult Function( ThreadTextChannel channel,  String text,  List<ThreadAttachmentView> attachments,  ThreadContentLifecycleView lifecycle)  text,required TResult Function( List<String> summary,  List<String> content,  ThreadContentLifecycleView lifecycle,  int summaryChunkBase,  int contentChunkBase)  thinking,required TResult Function( ThreadToolInvocationView invocation,  ThreadToolLifecycleView lifecycle,  ThreadToolUserInputView? userInput,  ThreadWaitPresentationView? wait)  tool,required TResult Function( ThreadAgentIdentityView identity,  ThreadAgentLifecycleView lifecycle)  agent,required TResult Function( TurnState state,  String? inputId)  turn,required TResult Function( String inferenceId,  String model,  ThreadInferenceLifecycleView lifecycle)  inference,required TResult Function( String name,  String source,  String providerId,  SkillResourceBaseView resourceBase,  SkillActivationCauseView cause,  int activatedAt)  skill,required TResult Function( String path,  String? mediaType,  int completedAt)  file,required TResult Function( int? beforeTokens,  int? afterTokens,  int compactedAt)  contextCompaction,}) {final _that = this;
switch (_that) {
case ThreadRawItemStateView():
return raw(_that.payloads,_that.notice,_that.recordedAt,_that.origin);case ThreadTextItemStateView():
return text(_that.channel,_that.text,_that.attachments,_that.lifecycle);case ThreadThinkingItemStateView():
return thinking(_that.summary,_that.content,_that.lifecycle,_that.summaryChunkBase,_that.contentChunkBase);case ThreadToolItemStateView():
return tool(_that.invocation,_that.lifecycle,_that.userInput,_that.wait);case ThreadAgentItemStateView():
return agent(_that.identity,_that.lifecycle);case ThreadTurnItemStateView():
return turn(_that.state,_that.inputId);case ThreadInferenceItemStateView():
return inference(_that.inferenceId,_that.model,_that.lifecycle);case ThreadSkillItemStateView():
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case ThreadFileItemStateView():
return file(_that.path,_that.mediaType,_that.completedAt);case ThreadContextCompactionItemStateView():
return contextCompaction(_that.beforeTokens,_that.afterTokens,_that.compactedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<RawHistoryPayload> payloads,  String notice,  int recordedAt,  ThreadRawItemOrigin origin)?  raw,TResult? Function( ThreadTextChannel channel,  String text,  List<ThreadAttachmentView> attachments,  ThreadContentLifecycleView lifecycle)?  text,TResult? Function( List<String> summary,  List<String> content,  ThreadContentLifecycleView lifecycle,  int summaryChunkBase,  int contentChunkBase)?  thinking,TResult? Function( ThreadToolInvocationView invocation,  ThreadToolLifecycleView lifecycle,  ThreadToolUserInputView? userInput,  ThreadWaitPresentationView? wait)?  tool,TResult? Function( ThreadAgentIdentityView identity,  ThreadAgentLifecycleView lifecycle)?  agent,TResult? Function( TurnState state,  String? inputId)?  turn,TResult? Function( String inferenceId,  String model,  ThreadInferenceLifecycleView lifecycle)?  inference,TResult? Function( String name,  String source,  String providerId,  SkillResourceBaseView resourceBase,  SkillActivationCauseView cause,  int activatedAt)?  skill,TResult? Function( String path,  String? mediaType,  int completedAt)?  file,TResult? Function( int? beforeTokens,  int? afterTokens,  int compactedAt)?  contextCompaction,}) {final _that = this;
switch (_that) {
case ThreadRawItemStateView() when raw != null:
return raw(_that.payloads,_that.notice,_that.recordedAt,_that.origin);case ThreadTextItemStateView() when text != null:
return text(_that.channel,_that.text,_that.attachments,_that.lifecycle);case ThreadThinkingItemStateView() when thinking != null:
return thinking(_that.summary,_that.content,_that.lifecycle,_that.summaryChunkBase,_that.contentChunkBase);case ThreadToolItemStateView() when tool != null:
return tool(_that.invocation,_that.lifecycle,_that.userInput,_that.wait);case ThreadAgentItemStateView() when agent != null:
return agent(_that.identity,_that.lifecycle);case ThreadTurnItemStateView() when turn != null:
return turn(_that.state,_that.inputId);case ThreadInferenceItemStateView() when inference != null:
return inference(_that.inferenceId,_that.model,_that.lifecycle);case ThreadSkillItemStateView() when skill != null:
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case ThreadFileItemStateView() when file != null:
return file(_that.path,_that.mediaType,_that.completedAt);case ThreadContextCompactionItemStateView() when contextCompaction != null:
return contextCompaction(_that.beforeTokens,_that.afterTokens,_that.compactedAt);case _:
  return null;

}
}

}




/// @nodoc


class ThreadToolItemStateView extends ThreadItemStateView {
  const ThreadToolItemStateView({required this.invocation, required this.lifecycle, this.userInput, this.wait}): super._();


 final  ThreadToolInvocationView invocation;
 final  ThreadToolLifecycleView lifecycle;
 final  ThreadToolUserInputView? userInput;
 final  ThreadWaitPresentationView? wait;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadToolItemStateViewCopyWith<ThreadToolItemStateView> get copyWith => _$ThreadToolItemStateViewCopyWithImpl<ThreadToolItemStateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolItemStateView&&(identical(other.invocation, invocation) || other.invocation == invocation)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&(identical(other.userInput, userInput) || other.userInput == userInput)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode {
    return Object.hash(runtimeType,invocation,lifecycle,userInput,wait);
}



}

/// @nodoc
abstract mixin class $ThreadToolItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadToolItemStateViewCopyWith(ThreadToolItemStateView value, $Res Function(ThreadToolItemStateView) _then) = _$ThreadToolItemStateViewCopyWithImpl;
@useResult
$Res call({
 ThreadToolInvocationView invocation, ThreadToolLifecycleView lifecycle, ThreadToolUserInputView? userInput, ThreadWaitPresentationView? wait
});


$ThreadToolInvocationViewCopyWith<$Res> get invocation;$ThreadToolLifecycleViewCopyWith<$Res> get lifecycle;$ThreadToolUserInputViewCopyWith<$Res>? get userInput;$ThreadWaitPresentationViewCopyWith<$Res>? get wait;

}
/// @nodoc
class _$ThreadToolItemStateViewCopyWithImpl<$Res>
    implements $ThreadToolItemStateViewCopyWith<$Res> {
  _$ThreadToolItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadToolItemStateView _self;
  final $Res Function(ThreadToolItemStateView) _then;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? invocation = null,Object? lifecycle = null,Object? userInput = freezed,Object? wait = freezed,}) {
  return _then(ThreadToolItemStateView(
invocation: null == invocation ? _self.invocation : invocation // ignore: cast_nullable_to_non_nullable
as ThreadToolInvocationView,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as ThreadToolLifecycleView,userInput: freezed == userInput ? _self.userInput : userInput // ignore: cast_nullable_to_non_nullable
as ThreadToolUserInputView?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as ThreadWaitPresentationView?,
  ));
}

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolInvocationViewCopyWith<$Res> get invocation {

  return $ThreadToolInvocationViewCopyWith<$Res>(_self.invocation, (value) {
    return _then(_self.copyWith(invocation: value));
  });
}/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolLifecycleViewCopyWith<$Res> get lifecycle {

  return $ThreadToolLifecycleViewCopyWith<$Res>(_self.lifecycle, (value) {
    return _then(_self.copyWith(lifecycle: value));
  });
}/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolUserInputViewCopyWith<$Res>? get userInput {
    if (_self.userInput == null) {
    return null;
  }

  return $ThreadToolUserInputViewCopyWith<$Res>(_self.userInput!, (value) {
    return _then(_self.copyWith(userInput: value));
  });
}/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadWaitPresentationViewCopyWith<$Res>? get wait {
    if (_self.wait == null) {
    return null;
  }

  return $ThreadWaitPresentationViewCopyWith<$Res>(_self.wait!, (value) {
    return _then(_self.copyWith(wait: value));
  });
}
}

/// @nodoc


class ThreadAgentItemStateView extends ThreadItemStateView {
  const ThreadAgentItemStateView({required this.identity, required this.lifecycle}): super._();


 final  ThreadAgentIdentityView identity;
 final  ThreadAgentLifecycleView lifecycle;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAgentItemStateViewCopyWith<ThreadAgentItemStateView> get copyWith => _$ThreadAgentItemStateViewCopyWithImpl<ThreadAgentItemStateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAgentItemStateView&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,lifecycle);
}



}

/// @nodoc
abstract mixin class $ThreadAgentItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadAgentItemStateViewCopyWith(ThreadAgentItemStateView value, $Res Function(ThreadAgentItemStateView) _then) = _$ThreadAgentItemStateViewCopyWithImpl;
@useResult
$Res call({
 ThreadAgentIdentityView identity, ThreadAgentLifecycleView lifecycle
});


$ThreadAgentIdentityViewCopyWith<$Res> get identity;$ThreadAgentLifecycleViewCopyWith<$Res> get lifecycle;

}
/// @nodoc
class _$ThreadAgentItemStateViewCopyWithImpl<$Res>
    implements $ThreadAgentItemStateViewCopyWith<$Res> {
  _$ThreadAgentItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadAgentItemStateView _self;
  final $Res Function(ThreadAgentItemStateView) _then;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? lifecycle = null,}) {
  return _then(ThreadAgentItemStateView(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadAgentIdentityView,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as ThreadAgentLifecycleView,
  ));
}

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadAgentIdentityViewCopyWith<$Res> get identity {

  return $ThreadAgentIdentityViewCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadAgentLifecycleViewCopyWith<$Res> get lifecycle {

  return $ThreadAgentLifecycleViewCopyWith<$Res>(_self.lifecycle, (value) {
    return _then(_self.copyWith(lifecycle: value));
  });
}
}

/// @nodoc


class ThreadTurnItemStateView extends ThreadItemStateView {
  const ThreadTurnItemStateView(this.state, {this.inputId}): super._();


 final  TurnState state;
 final  String? inputId;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadTurnItemStateViewCopyWith<ThreadTurnItemStateView> get copyWith => _$ThreadTurnItemStateViewCopyWithImpl<ThreadTurnItemStateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadTurnItemStateView&&(identical(other.state, state) || other.state == state)&&(identical(other.inputId, inputId) || other.inputId == inputId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state,inputId);
}



}

/// @nodoc
abstract mixin class $ThreadTurnItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadTurnItemStateViewCopyWith(ThreadTurnItemStateView value, $Res Function(ThreadTurnItemStateView) _then) = _$ThreadTurnItemStateViewCopyWithImpl;
@useResult
$Res call({
 TurnState state, String? inputId
});


$TurnStateCopyWith<$Res> get state;

}
/// @nodoc
class _$ThreadTurnItemStateViewCopyWithImpl<$Res>
    implements $ThreadTurnItemStateViewCopyWith<$Res> {
  _$ThreadTurnItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadTurnItemStateView _self;
  final $Res Function(ThreadTurnItemStateView) _then;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,Object? inputId = freezed,}) {
  return _then(ThreadTurnItemStateView(
null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnState,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnStateCopyWith<$Res> get state {

  return $TurnStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class ThreadInferenceItemStateView extends ThreadItemStateView {
  const ThreadInferenceItemStateView({required this.inferenceId, required this.model, required this.lifecycle}): super._();


 final  String inferenceId;
 final  String model;
 final  ThreadInferenceLifecycleView lifecycle;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadInferenceItemStateViewCopyWith<ThreadInferenceItemStateView> get copyWith => _$ThreadInferenceItemStateViewCopyWithImpl<ThreadInferenceItemStateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadInferenceItemStateView&&(identical(other.inferenceId, inferenceId) || other.inferenceId == inferenceId)&&(identical(other.model, model) || other.model == model)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inferenceId,model,lifecycle);
}



}

/// @nodoc
abstract mixin class $ThreadInferenceItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadInferenceItemStateViewCopyWith(ThreadInferenceItemStateView value, $Res Function(ThreadInferenceItemStateView) _then) = _$ThreadInferenceItemStateViewCopyWithImpl;
@useResult
$Res call({
 String inferenceId, String model, ThreadInferenceLifecycleView lifecycle
});


$ThreadInferenceLifecycleViewCopyWith<$Res> get lifecycle;

}
/// @nodoc
class _$ThreadInferenceItemStateViewCopyWithImpl<$Res>
    implements $ThreadInferenceItemStateViewCopyWith<$Res> {
  _$ThreadInferenceItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadInferenceItemStateView _self;
  final $Res Function(ThreadInferenceItemStateView) _then;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? inferenceId = null,Object? model = null,Object? lifecycle = null,}) {
  return _then(ThreadInferenceItemStateView(
inferenceId: null == inferenceId ? _self.inferenceId : inferenceId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as ThreadInferenceLifecycleView,
  ));
}

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadInferenceLifecycleViewCopyWith<$Res> get lifecycle {

  return $ThreadInferenceLifecycleViewCopyWith<$Res>(_self.lifecycle, (value) {
    return _then(_self.copyWith(lifecycle: value));
  });
}
}

/// @nodoc


class ThreadSkillItemStateView extends ThreadItemStateView {
  const ThreadSkillItemStateView({required this.name, required this.source, required this.providerId, required this.resourceBase, required this.cause, required this.activatedAt}): super._();


 final  String name;
 final  String source;
 final  String providerId;
 final  SkillResourceBaseView resourceBase;
 final  SkillActivationCauseView cause;
 final  int activatedAt;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadSkillItemStateViewCopyWith<ThreadSkillItemStateView> get copyWith => _$ThreadSkillItemStateViewCopyWithImpl<ThreadSkillItemStateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadSkillItemStateView&&(identical(other.name, name) || other.name == name)&&(identical(other.source, source) || other.source == source)&&(identical(other.providerId, providerId) || other.providerId == providerId)&&(identical(other.resourceBase, resourceBase) || other.resourceBase == resourceBase)&&(identical(other.cause, cause) || other.cause == cause)&&(identical(other.activatedAt, activatedAt) || other.activatedAt == activatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,source,providerId,resourceBase,cause,activatedAt);
}



}

/// @nodoc
abstract mixin class $ThreadSkillItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadSkillItemStateViewCopyWith(ThreadSkillItemStateView value, $Res Function(ThreadSkillItemStateView) _then) = _$ThreadSkillItemStateViewCopyWithImpl;
@useResult
$Res call({
 String name, String source, String providerId, SkillResourceBaseView resourceBase, SkillActivationCauseView cause, int activatedAt
});


$SkillResourceBaseViewCopyWith<$Res> get resourceBase;$SkillActivationCauseViewCopyWith<$Res> get cause;

}
/// @nodoc
class _$ThreadSkillItemStateViewCopyWithImpl<$Res>
    implements $ThreadSkillItemStateViewCopyWith<$Res> {
  _$ThreadSkillItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadSkillItemStateView _self;
  final $Res Function(ThreadSkillItemStateView) _then;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? source = null,Object? providerId = null,Object? resourceBase = null,Object? cause = null,Object? activatedAt = null,}) {
  return _then(ThreadSkillItemStateView(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as String,resourceBase: null == resourceBase ? _self.resourceBase : resourceBase // ignore: cast_nullable_to_non_nullable
as SkillResourceBaseView,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as SkillActivationCauseView,activatedAt: null == activatedAt ? _self.activatedAt : activatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillResourceBaseViewCopyWith<$Res> get resourceBase {

  return $SkillResourceBaseViewCopyWith<$Res>(_self.resourceBase, (value) {
    return _then(_self.copyWith(resourceBase: value));
  });
}/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillActivationCauseViewCopyWith<$Res> get cause {

  return $SkillActivationCauseViewCopyWith<$Res>(_self.cause, (value) {
    return _then(_self.copyWith(cause: value));
  });
}
}

/// @nodoc


class ThreadFileItemStateView extends ThreadItemStateView {
  const ThreadFileItemStateView(this.path, this.mediaType, this.completedAt): super._();


 final  String path;
 final  String? mediaType;
 final  int completedAt;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadFileItemStateViewCopyWith<ThreadFileItemStateView> get copyWith => _$ThreadFileItemStateViewCopyWithImpl<ThreadFileItemStateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadFileItemStateView&&(identical(other.path, path) || other.path == path)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,mediaType,completedAt);
}



}

/// @nodoc
abstract mixin class $ThreadFileItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadFileItemStateViewCopyWith(ThreadFileItemStateView value, $Res Function(ThreadFileItemStateView) _then) = _$ThreadFileItemStateViewCopyWithImpl;
@useResult
$Res call({
 String path, String? mediaType, int completedAt
});




}
/// @nodoc
class _$ThreadFileItemStateViewCopyWithImpl<$Res>
    implements $ThreadFileItemStateViewCopyWith<$Res> {
  _$ThreadFileItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadFileItemStateView _self;
  final $Res Function(ThreadFileItemStateView) _then;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? mediaType = freezed,Object? completedAt = null,}) {
  return _then(ThreadFileItemStateView(
null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,freezed == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String?,null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ThreadContextCompactionItemStateView extends ThreadItemStateView {
  const ThreadContextCompactionItemStateView(this.beforeTokens, this.afterTokens, this.compactedAt): super._();


 final  int? beforeTokens;
 final  int? afterTokens;
 final  int compactedAt;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextCompactionItemStateViewCopyWith<ThreadContextCompactionItemStateView> get copyWith => _$ThreadContextCompactionItemStateViewCopyWithImpl<ThreadContextCompactionItemStateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextCompactionItemStateView&&(identical(other.beforeTokens, beforeTokens) || other.beforeTokens == beforeTokens)&&(identical(other.afterTokens, afterTokens) || other.afterTokens == afterTokens)&&(identical(other.compactedAt, compactedAt) || other.compactedAt == compactedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,beforeTokens,afterTokens,compactedAt);
}



}

/// @nodoc
abstract mixin class $ThreadContextCompactionItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadContextCompactionItemStateViewCopyWith(ThreadContextCompactionItemStateView value, $Res Function(ThreadContextCompactionItemStateView) _then) = _$ThreadContextCompactionItemStateViewCopyWithImpl;
@useResult
$Res call({
 int? beforeTokens, int? afterTokens, int compactedAt
});




}
/// @nodoc
class _$ThreadContextCompactionItemStateViewCopyWithImpl<$Res>
    implements $ThreadContextCompactionItemStateViewCopyWith<$Res> {
  _$ThreadContextCompactionItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadContextCompactionItemStateView _self;
  final $Res Function(ThreadContextCompactionItemStateView) _then;

/// Create a copy of ThreadItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? beforeTokens = freezed,Object? afterTokens = freezed,Object? compactedAt = null,}) {
  return _then(ThreadContextCompactionItemStateView(
freezed == beforeTokens ? _self.beforeTokens : beforeTokens // ignore: cast_nullable_to_non_nullable
as int?,freezed == afterTokens ? _self.afterTokens : afterTokens // ignore: cast_nullable_to_non_nullable
as int?,null == compactedAt ? _self.compactedAt : compactedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadRawItemStateView {


/// Create a copy of ThreadRawItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadRawItemStateViewCopyWith<ThreadRawItemStateView> get copyWith => _$ThreadRawItemStateViewCopyWithImpl<ThreadRawItemStateView>(this as ThreadRawItemStateView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadRawItemStateView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadRawItemStateView&&const DeepCollectionEquality().equals(other.payloads, _this.payloads)&&(identical(other.notice, _this.notice) || other.notice == _this.notice)&&(identical(other.recordedAt, _this.recordedAt) || other.recordedAt == _this.recordedAt)&&(identical(other.origin, _this.origin) || other.origin == _this.origin));
}


@override
int get hashCode {
  final _this = this as ThreadRawItemStateView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.payloads),_this.notice,_this.recordedAt,_this.origin);
}



}

/// @nodoc
abstract mixin class $ThreadRawItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadRawItemStateViewCopyWith(ThreadRawItemStateView value, $Res Function(ThreadRawItemStateView) _then) = _$ThreadRawItemStateViewCopyWithImpl;
@useResult
$Res call({
 List<RawHistoryPayload> payloads, String notice, int recordedAt, ThreadRawItemOrigin origin
});




}
/// @nodoc
class _$ThreadRawItemStateViewCopyWithImpl<$Res>
    implements $ThreadRawItemStateViewCopyWith<$Res> {
  _$ThreadRawItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadRawItemStateView _self;
  final $Res Function(ThreadRawItemStateView) _then;

/// Create a copy of ThreadRawItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? payloads = null,Object? notice = null,Object? recordedAt = null,Object? origin = null,}) {
  return _then(ThreadRawItemStateView(
null == payloads ? _self.payloads : payloads // ignore: cast_nullable_to_non_nullable
as List<RawHistoryPayload>,null == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String,null == recordedAt ? _self.recordedAt : recordedAt // ignore: cast_nullable_to_non_nullable
as int,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadRawItemOrigin,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadRawItemStateView].
extension ThreadRawItemStateViewPatterns on ThreadRawItemStateView {
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

/// @nodoc
mixin _$ThreadTextItemStateView {


/// Create a copy of ThreadTextItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadTextItemStateViewCopyWith<ThreadTextItemStateView> get copyWith => _$ThreadTextItemStateViewCopyWithImpl<ThreadTextItemStateView>(this as ThreadTextItemStateView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadTextItemStateView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadTextItemStateView&&(identical(other.channel, _this.channel) || other.channel == _this.channel)&&(identical(other.text, _this.text) || other.text == _this.text)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle));
}


@override
int get hashCode {
  final _this = this as ThreadTextItemStateView;
  return Object.hash(runtimeType,_this.channel,_this.text,const DeepCollectionEquality().hash(_this.attachments),_this.lifecycle);
}



}

/// @nodoc
abstract mixin class $ThreadTextItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadTextItemStateViewCopyWith(ThreadTextItemStateView value, $Res Function(ThreadTextItemStateView) _then) = _$ThreadTextItemStateViewCopyWithImpl;
@useResult
$Res call({
 ThreadTextChannel channel, String text, List<ThreadAttachmentView> attachments, ThreadContentLifecycleView lifecycle
});


$ThreadContentLifecycleViewCopyWith<$Res> get lifecycle;

}
/// @nodoc
class _$ThreadTextItemStateViewCopyWithImpl<$Res>
    implements $ThreadTextItemStateViewCopyWith<$Res> {
  _$ThreadTextItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadTextItemStateView _self;
  final $Res Function(ThreadTextItemStateView) _then;

/// Create a copy of ThreadTextItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? channel = null,Object? text = null,Object? attachments = null,Object? lifecycle = null,}) {
  return _then(ThreadTextItemStateView(
channel: null == channel ? _self.channel : channel // ignore: cast_nullable_to_non_nullable
as ThreadTextChannel,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<ThreadAttachmentView>,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as ThreadContentLifecycleView,
  ));
}
/// Create a copy of ThreadTextItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentLifecycleViewCopyWith<$Res> get lifecycle {

  return $ThreadContentLifecycleViewCopyWith<$Res>(_self.lifecycle, (value) {
    return _then(_self.copyWith(lifecycle: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadTextItemStateView].
extension ThreadTextItemStateViewPatterns on ThreadTextItemStateView {
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

/// @nodoc
mixin _$ThreadThinkingItemStateView {


/// Create a copy of ThreadThinkingItemStateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadThinkingItemStateViewCopyWith<ThreadThinkingItemStateView> get copyWith => _$ThreadThinkingItemStateViewCopyWithImpl<ThreadThinkingItemStateView>(this as ThreadThinkingItemStateView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadThinkingItemStateView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadThinkingItemStateView&&const DeepCollectionEquality().equals(other.summary, _this.summary)&&const DeepCollectionEquality().equals(other.content, _this.content)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle)&&(identical(other.summaryChunkBase, _this.summaryChunkBase) || other.summaryChunkBase == _this.summaryChunkBase)&&(identical(other.contentChunkBase, _this.contentChunkBase) || other.contentChunkBase == _this.contentChunkBase));
}


@override
int get hashCode {
  final _this = this as ThreadThinkingItemStateView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.summary),const DeepCollectionEquality().hash(_this.content),_this.lifecycle,_this.summaryChunkBase,_this.contentChunkBase);
}



}

/// @nodoc
abstract mixin class $ThreadThinkingItemStateViewCopyWith<$Res> implements $ThreadItemStateViewCopyWith<$Res> {
  factory $ThreadThinkingItemStateViewCopyWith(ThreadThinkingItemStateView value, $Res Function(ThreadThinkingItemStateView) _then) = _$ThreadThinkingItemStateViewCopyWithImpl;
@useResult
$Res call({
 List<String> summary, List<String> content, ThreadContentLifecycleView lifecycle, int summaryChunkBase, int contentChunkBase
});


$ThreadContentLifecycleViewCopyWith<$Res> get lifecycle;

}
/// @nodoc
class _$ThreadThinkingItemStateViewCopyWithImpl<$Res>
    implements $ThreadThinkingItemStateViewCopyWith<$Res> {
  _$ThreadThinkingItemStateViewCopyWithImpl(this._self, this._then);

  final ThreadThinkingItemStateView _self;
  final $Res Function(ThreadThinkingItemStateView) _then;

/// Create a copy of ThreadThinkingItemStateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summary = null,Object? content = null,Object? lifecycle = null,Object? summaryChunkBase = null,Object? contentChunkBase = null,}) {
  return _then(ThreadThinkingItemStateView(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as List<String>,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as List<String>,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as ThreadContentLifecycleView,summaryChunkBase: null == summaryChunkBase ? _self.summaryChunkBase : summaryChunkBase // ignore: cast_nullable_to_non_nullable
as int,contentChunkBase: null == contentChunkBase ? _self.contentChunkBase : contentChunkBase // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ThreadThinkingItemStateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentLifecycleViewCopyWith<$Res> get lifecycle {

  return $ThreadContentLifecycleViewCopyWith<$Res>(_self.lifecycle, (value) {
    return _then(_self.copyWith(lifecycle: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadThinkingItemStateView].
extension ThreadThinkingItemStateViewPatterns on ThreadThinkingItemStateView {
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

/// @nodoc
mixin _$ThreadItemView {

 String get id; String get threadId; String get turnId; int get ordinal; int get revision; int get createdAt; int get updatedAt; ThreadItemStateView get state; ThreadContextDisposition get contextDisposition; int get bodyOmittedUnits; bool get executionTerminal; bool get saved;
/// Create a copy of ThreadItemView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadItemViewCopyWith<ThreadItemView> get copyWith => _$ThreadItemViewCopyWithImpl<ThreadItemView>(this as ThreadItemView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadItemView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadItemView&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.ordinal, _this.ordinal) || other.ordinal == _this.ordinal)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.contextDisposition, _this.contextDisposition) || other.contextDisposition == _this.contextDisposition)&&(identical(other.bodyOmittedUnits, _this.bodyOmittedUnits) || other.bodyOmittedUnits == _this.bodyOmittedUnits)&&(identical(other.executionTerminal, _this.executionTerminal) || other.executionTerminal == _this.executionTerminal)&&(identical(other.saved, _this.saved) || other.saved == _this.saved));
}


@override
int get hashCode {
  final _this = this as ThreadItemView;
  return Object.hash(runtimeType,_this.id,_this.threadId,_this.turnId,_this.ordinal,_this.revision,_this.createdAt,_this.updatedAt,_this.state,_this.contextDisposition,_this.bodyOmittedUnits,_this.executionTerminal,_this.saved);
}



}

/// @nodoc
abstract mixin class $ThreadItemViewCopyWith<$Res>  {
  factory $ThreadItemViewCopyWith(ThreadItemView value, $Res Function(ThreadItemView) _then) = _$ThreadItemViewCopyWithImpl;
@useResult
$Res call({
 String id, String threadId, String turnId, int ordinal, int revision, int createdAt, int updatedAt, ThreadItemStateView state, ThreadContextDisposition contextDisposition, int bodyOmittedUnits, bool executionTerminal, bool saved
});


$ThreadItemStateViewCopyWith<$Res> get state;

}
/// @nodoc
class _$ThreadItemViewCopyWithImpl<$Res>
    implements $ThreadItemViewCopyWith<$Res> {
  _$ThreadItemViewCopyWithImpl(this._self, this._then);

  final ThreadItemView _self;
  final $Res Function(ThreadItemView) _then;

/// Create a copy of ThreadItemView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? threadId = null,Object? turnId = null,Object? ordinal = null,Object? revision = null,Object? createdAt = null,Object? updatedAt = null,Object? state = null,Object? contextDisposition = null,Object? bodyOmittedUnits = null,Object? executionTerminal = null,Object? saved = null,}) {
  return _then(ThreadItemView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,ordinal: null == ordinal ? _self.ordinal : ordinal // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadItemStateView,contextDisposition: null == contextDisposition ? _self.contextDisposition : contextDisposition // ignore: cast_nullable_to_non_nullable
as ThreadContextDisposition,bodyOmittedUnits: null == bodyOmittedUnits ? _self.bodyOmittedUnits : bodyOmittedUnits // ignore: cast_nullable_to_non_nullable
as int,executionTerminal: null == executionTerminal ? _self.executionTerminal : executionTerminal // ignore: cast_nullable_to_non_nullable
as bool,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ThreadItemView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadItemStateViewCopyWith<$Res> get state {

  return $ThreadItemStateViewCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadItemView].
extension ThreadItemViewPatterns on ThreadItemView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadItemView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadItemView() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadItemView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadItemView():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadItemView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadItemView() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String threadId,  String turnId,  int ordinal,  int revision,  int createdAt,  int updatedAt,  ThreadItemStateView state,  ThreadContextDisposition contextDisposition,  int bodyOmittedUnits,  bool executionTerminal,  bool saved)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadItemView() when $default != null:
return $default(_that.id,_that.threadId,_that.turnId,_that.ordinal,_that.revision,_that.createdAt,_that.updatedAt,_that.state,_that.contextDisposition,_that.bodyOmittedUnits,_that.executionTerminal,_that.saved);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String threadId,  String turnId,  int ordinal,  int revision,  int createdAt,  int updatedAt,  ThreadItemStateView state,  ThreadContextDisposition contextDisposition,  int bodyOmittedUnits,  bool executionTerminal,  bool saved)  $default,) {final _that = this;
switch (_that) {
case _ThreadItemView():
return $default(_that.id,_that.threadId,_that.turnId,_that.ordinal,_that.revision,_that.createdAt,_that.updatedAt,_that.state,_that.contextDisposition,_that.bodyOmittedUnits,_that.executionTerminal,_that.saved);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String threadId,  String turnId,  int ordinal,  int revision,  int createdAt,  int updatedAt,  ThreadItemStateView state,  ThreadContextDisposition contextDisposition,  int bodyOmittedUnits,  bool executionTerminal,  bool saved)?  $default,) {final _that = this;
switch (_that) {
case _ThreadItemView() when $default != null:
return $default(_that.id,_that.threadId,_that.turnId,_that.ordinal,_that.revision,_that.createdAt,_that.updatedAt,_that.state,_that.contextDisposition,_that.bodyOmittedUnits,_that.executionTerminal,_that.saved);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadItemView extends ThreadItemView {
  const _ThreadItemView({required this.id, required this.threadId, required this.turnId, required this.ordinal, required this.revision, required this.createdAt, required this.updatedAt, required this.state, this.contextDisposition = ThreadContextDisposition.active, this.bodyOmittedUnits = 0, this.executionTerminal = false, this.saved = true}): super._();


@override final  String id;
@override final  String threadId;
@override final  String turnId;
@override final  int ordinal;
@override final  int revision;
@override final  int createdAt;
@override final  int updatedAt;
@override final  ThreadItemStateView state;
@override@JsonKey() final  ThreadContextDisposition contextDisposition;
@override@JsonKey() final  int bodyOmittedUnits;
@override@JsonKey() final  bool executionTerminal;
@override@JsonKey() final  bool saved;

/// Create a copy of ThreadItemView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadItemViewCopyWith<_ThreadItemView> get copyWith => __$ThreadItemViewCopyWithImpl<_ThreadItemView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadItemView&&(identical(other.id, id) || other.id == id)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.ordinal, ordinal) || other.ordinal == ordinal)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.state, state) || other.state == state)&&(identical(other.contextDisposition, contextDisposition) || other.contextDisposition == contextDisposition)&&(identical(other.bodyOmittedUnits, bodyOmittedUnits) || other.bodyOmittedUnits == bodyOmittedUnits)&&(identical(other.executionTerminal, executionTerminal) || other.executionTerminal == executionTerminal)&&(identical(other.saved, saved) || other.saved == saved));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,threadId,turnId,ordinal,revision,createdAt,updatedAt,state,contextDisposition,bodyOmittedUnits,executionTerminal,saved);
}



}

/// @nodoc
abstract mixin class _$ThreadItemViewCopyWith<$Res> implements $ThreadItemViewCopyWith<$Res> {
  factory _$ThreadItemViewCopyWith(_ThreadItemView value, $Res Function(_ThreadItemView) _then) = __$ThreadItemViewCopyWithImpl;
@override @useResult
$Res call({
 String id, String threadId, String turnId, int ordinal, int revision, int createdAt, int updatedAt, ThreadItemStateView state, ThreadContextDisposition contextDisposition, int bodyOmittedUnits, bool executionTerminal, bool saved
});


@override $ThreadItemStateViewCopyWith<$Res> get state;

}
/// @nodoc
class __$ThreadItemViewCopyWithImpl<$Res>
    implements _$ThreadItemViewCopyWith<$Res> {
  __$ThreadItemViewCopyWithImpl(this._self, this._then);

  final _ThreadItemView _self;
  final $Res Function(_ThreadItemView) _then;

/// Create a copy of ThreadItemView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? threadId = null,Object? turnId = null,Object? ordinal = null,Object? revision = null,Object? createdAt = null,Object? updatedAt = null,Object? state = null,Object? contextDisposition = null,Object? bodyOmittedUnits = null,Object? executionTerminal = null,Object? saved = null,}) {
  return _then(_ThreadItemView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,ordinal: null == ordinal ? _self.ordinal : ordinal // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadItemStateView,contextDisposition: null == contextDisposition ? _self.contextDisposition : contextDisposition // ignore: cast_nullable_to_non_nullable
as ThreadContextDisposition,bodyOmittedUnits: null == bodyOmittedUnits ? _self.bodyOmittedUnits : bodyOmittedUnits // ignore: cast_nullable_to_non_nullable
as int,executionTerminal: null == executionTerminal ? _self.executionTerminal : executionTerminal // ignore: cast_nullable_to_non_nullable
as bool,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ThreadItemView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadItemStateViewCopyWith<$Res> get state {

  return $ThreadItemStateViewCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

// dart format on
