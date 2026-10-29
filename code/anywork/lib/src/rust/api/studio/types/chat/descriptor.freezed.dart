// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'descriptor.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeTimelineDescriptor {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineDescriptor()';
}


}

/// @nodoc
class $BridgeTimelineDescriptorCopyWith<$Res>  {
$BridgeTimelineDescriptorCopyWith(BridgeTimelineDescriptor _, $Res Function(BridgeTimelineDescriptor) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineDescriptor].
extension BridgeTimelineDescriptorPatterns on BridgeTimelineDescriptor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineDescriptor_Text value)?  text,TResult Function( BridgeTimelineDescriptor_Thinking value)?  thinking,TResult Function( BridgeTimelineDescriptor_Tool value)?  tool,TResult Function( BridgeTimelineDescriptor_Raw value)?  raw,TResult Function( BridgeTimelineDescriptor_Agent value)?  agent,TResult Function( BridgeTimelineDescriptor_Turn value)?  turn,TResult Function( BridgeTimelineDescriptor_Inference value)?  inference,TResult Function( BridgeTimelineDescriptor_Skill value)?  skill,TResult Function( BridgeTimelineDescriptor_File value)?  file,TResult Function( BridgeTimelineDescriptor_ContextCompaction value)?  contextCompaction,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that);case BridgeTimelineDescriptor_File() when file != null:
return file(_that);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineDescriptor_Text value)  text,required TResult Function( BridgeTimelineDescriptor_Thinking value)  thinking,required TResult Function( BridgeTimelineDescriptor_Tool value)  tool,required TResult Function( BridgeTimelineDescriptor_Raw value)  raw,required TResult Function( BridgeTimelineDescriptor_Agent value)  agent,required TResult Function( BridgeTimelineDescriptor_Turn value)  turn,required TResult Function( BridgeTimelineDescriptor_Inference value)  inference,required TResult Function( BridgeTimelineDescriptor_Skill value)  skill,required TResult Function( BridgeTimelineDescriptor_File value)  file,required TResult Function( BridgeTimelineDescriptor_ContextCompaction value)  contextCompaction,}){
final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text():
return text(_that);case BridgeTimelineDescriptor_Thinking():
return thinking(_that);case BridgeTimelineDescriptor_Tool():
return tool(_that);case BridgeTimelineDescriptor_Raw():
return raw(_that);case BridgeTimelineDescriptor_Agent():
return agent(_that);case BridgeTimelineDescriptor_Turn():
return turn(_that);case BridgeTimelineDescriptor_Inference():
return inference(_that);case BridgeTimelineDescriptor_Skill():
return skill(_that);case BridgeTimelineDescriptor_File():
return file(_that);case BridgeTimelineDescriptor_ContextCompaction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineDescriptor_Text value)?  text,TResult? Function( BridgeTimelineDescriptor_Thinking value)?  thinking,TResult? Function( BridgeTimelineDescriptor_Tool value)?  tool,TResult? Function( BridgeTimelineDescriptor_Raw value)?  raw,TResult? Function( BridgeTimelineDescriptor_Agent value)?  agent,TResult? Function( BridgeTimelineDescriptor_Turn value)?  turn,TResult? Function( BridgeTimelineDescriptor_Inference value)?  inference,TResult? Function( BridgeTimelineDescriptor_Skill value)?  skill,TResult? Function( BridgeTimelineDescriptor_File value)?  file,TResult? Function( BridgeTimelineDescriptor_ContextCompaction value)?  contextCompaction,}){
final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that);case BridgeTimelineDescriptor_File() when file != null:
return file(_that);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeTimelineTextDescriptor field0)?  text,TResult Function( BridgeTimelineThinkingDescriptor field0)?  thinking,TResult Function( BridgeTimelineToolDescriptor field0)?  tool,TResult Function( BridgeTimelineRawDescriptor field0)?  raw,TResult Function( BridgeThreadAgentIdentity identity,  BridgeThreadAgentState state)?  agent,TResult Function( BridgeTurnState state,  String? inputId)?  turn,TResult Function( String inferenceId,  String model,  BridgeThreadInferenceState state)?  inference,TResult Function( String name,  String source,  String providerId,  BridgeSkillResourceBase resourceBase,  BridgeSkillActivationCause cause,  PlatformInt64 activatedAt)?  skill,TResult Function( String path,  String? mediaType,  PlatformInt64 completedAt)?  file,TResult Function( BigInt? beforeTokens,  BigInt? afterTokens,  PlatformInt64 compactedAt)?  contextCompaction,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that.field0);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that.field0);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that.field0);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that.field0);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that.identity,_that.state);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that.state,_that.inputId);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that.inferenceId,_that.model,_that.state);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case BridgeTimelineDescriptor_File() when file != null:
return file(_that.path,_that.mediaType,_that.completedAt);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeTimelineTextDescriptor field0)  text,required TResult Function( BridgeTimelineThinkingDescriptor field0)  thinking,required TResult Function( BridgeTimelineToolDescriptor field0)  tool,required TResult Function( BridgeTimelineRawDescriptor field0)  raw,required TResult Function( BridgeThreadAgentIdentity identity,  BridgeThreadAgentState state)  agent,required TResult Function( BridgeTurnState state,  String? inputId)  turn,required TResult Function( String inferenceId,  String model,  BridgeThreadInferenceState state)  inference,required TResult Function( String name,  String source,  String providerId,  BridgeSkillResourceBase resourceBase,  BridgeSkillActivationCause cause,  PlatformInt64 activatedAt)  skill,required TResult Function( String path,  String? mediaType,  PlatformInt64 completedAt)  file,required TResult Function( BigInt? beforeTokens,  BigInt? afterTokens,  PlatformInt64 compactedAt)  contextCompaction,}) {final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text():
return text(_that.field0);case BridgeTimelineDescriptor_Thinking():
return thinking(_that.field0);case BridgeTimelineDescriptor_Tool():
return tool(_that.field0);case BridgeTimelineDescriptor_Raw():
return raw(_that.field0);case BridgeTimelineDescriptor_Agent():
return agent(_that.identity,_that.state);case BridgeTimelineDescriptor_Turn():
return turn(_that.state,_that.inputId);case BridgeTimelineDescriptor_Inference():
return inference(_that.inferenceId,_that.model,_that.state);case BridgeTimelineDescriptor_Skill():
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case BridgeTimelineDescriptor_File():
return file(_that.path,_that.mediaType,_that.completedAt);case BridgeTimelineDescriptor_ContextCompaction():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineTextDescriptor field0)?  text,TResult? Function( BridgeTimelineThinkingDescriptor field0)?  thinking,TResult? Function( BridgeTimelineToolDescriptor field0)?  tool,TResult? Function( BridgeTimelineRawDescriptor field0)?  raw,TResult? Function( BridgeThreadAgentIdentity identity,  BridgeThreadAgentState state)?  agent,TResult? Function( BridgeTurnState state,  String? inputId)?  turn,TResult? Function( String inferenceId,  String model,  BridgeThreadInferenceState state)?  inference,TResult? Function( String name,  String source,  String providerId,  BridgeSkillResourceBase resourceBase,  BridgeSkillActivationCause cause,  PlatformInt64 activatedAt)?  skill,TResult? Function( String path,  String? mediaType,  PlatformInt64 completedAt)?  file,TResult? Function( BigInt? beforeTokens,  BigInt? afterTokens,  PlatformInt64 compactedAt)?  contextCompaction,}) {final _that = this;
switch (_that) {
case BridgeTimelineDescriptor_Text() when text != null:
return text(_that.field0);case BridgeTimelineDescriptor_Thinking() when thinking != null:
return thinking(_that.field0);case BridgeTimelineDescriptor_Tool() when tool != null:
return tool(_that.field0);case BridgeTimelineDescriptor_Raw() when raw != null:
return raw(_that.field0);case BridgeTimelineDescriptor_Agent() when agent != null:
return agent(_that.identity,_that.state);case BridgeTimelineDescriptor_Turn() when turn != null:
return turn(_that.state,_that.inputId);case BridgeTimelineDescriptor_Inference() when inference != null:
return inference(_that.inferenceId,_that.model,_that.state);case BridgeTimelineDescriptor_Skill() when skill != null:
return skill(_that.name,_that.source,_that.providerId,_that.resourceBase,_that.cause,_that.activatedAt);case BridgeTimelineDescriptor_File() when file != null:
return file(_that.path,_that.mediaType,_that.completedAt);case BridgeTimelineDescriptor_ContextCompaction() when contextCompaction != null:
return contextCompaction(_that.beforeTokens,_that.afterTokens,_that.compactedAt);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineDescriptor_Text extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Text(this.field0): super._();


 final  BridgeTimelineTextDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_TextCopyWith<BridgeTimelineDescriptor_Text> get copyWith => _$BridgeTimelineDescriptor_TextCopyWithImpl<BridgeTimelineDescriptor_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Text&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.text(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_TextCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_TextCopyWith(BridgeTimelineDescriptor_Text value, $Res Function(BridgeTimelineDescriptor_Text) _then) = _$BridgeTimelineDescriptor_TextCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineTextDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_TextCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_TextCopyWith<$Res> {
  _$BridgeTimelineDescriptor_TextCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Text _self;
  final $Res Function(BridgeTimelineDescriptor_Text) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Text(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineTextDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Thinking extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Thinking(this.field0): super._();


 final  BridgeTimelineThinkingDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_ThinkingCopyWith<BridgeTimelineDescriptor_Thinking> get copyWith => _$BridgeTimelineDescriptor_ThinkingCopyWithImpl<BridgeTimelineDescriptor_Thinking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Thinking&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.thinking(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_ThinkingCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_ThinkingCopyWith(BridgeTimelineDescriptor_Thinking value, $Res Function(BridgeTimelineDescriptor_Thinking) _then) = _$BridgeTimelineDescriptor_ThinkingCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineThinkingDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_ThinkingCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_ThinkingCopyWith<$Res> {
  _$BridgeTimelineDescriptor_ThinkingCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Thinking _self;
  final $Res Function(BridgeTimelineDescriptor_Thinking) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Thinking(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineThinkingDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Tool extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Tool(this.field0): super._();


 final  BridgeTimelineToolDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_ToolCopyWith<BridgeTimelineDescriptor_Tool> get copyWith => _$BridgeTimelineDescriptor_ToolCopyWithImpl<BridgeTimelineDescriptor_Tool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Tool&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.tool(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_ToolCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_ToolCopyWith(BridgeTimelineDescriptor_Tool value, $Res Function(BridgeTimelineDescriptor_Tool) _then) = _$BridgeTimelineDescriptor_ToolCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineToolDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_ToolCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_ToolCopyWith<$Res> {
  _$BridgeTimelineDescriptor_ToolCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Tool _self;
  final $Res Function(BridgeTimelineDescriptor_Tool) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Tool(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineToolDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Raw extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Raw(this.field0): super._();


 final  BridgeTimelineRawDescriptor field0;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_RawCopyWith<BridgeTimelineDescriptor_Raw> get copyWith => _$BridgeTimelineDescriptor_RawCopyWithImpl<BridgeTimelineDescriptor_Raw>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Raw&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.raw(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_RawCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_RawCopyWith(BridgeTimelineDescriptor_Raw value, $Res Function(BridgeTimelineDescriptor_Raw) _then) = _$BridgeTimelineDescriptor_RawCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineRawDescriptor field0
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_RawCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_RawCopyWith<$Res> {
  _$BridgeTimelineDescriptor_RawCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Raw _self;
  final $Res Function(BridgeTimelineDescriptor_Raw) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeTimelineDescriptor_Raw(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeTimelineRawDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_Agent extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Agent({required this.identity, required this.state}): super._();


 final  BridgeThreadAgentIdentity identity;
 final  BridgeThreadAgentState state;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_AgentCopyWith<BridgeTimelineDescriptor_Agent> get copyWith => _$BridgeTimelineDescriptor_AgentCopyWithImpl<BridgeTimelineDescriptor_Agent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Agent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,state);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.agent(identity: $identity, state: $state)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_AgentCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_AgentCopyWith(BridgeTimelineDescriptor_Agent value, $Res Function(BridgeTimelineDescriptor_Agent) _then) = _$BridgeTimelineDescriptor_AgentCopyWithImpl;
@useResult
$Res call({
 BridgeThreadAgentIdentity identity, BridgeThreadAgentState state
});


$BridgeThreadAgentStateCopyWith<$Res> get state;

}
/// @nodoc
class _$BridgeTimelineDescriptor_AgentCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_AgentCopyWith<$Res> {
  _$BridgeTimelineDescriptor_AgentCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Agent _self;
  final $Res Function(BridgeTimelineDescriptor_Agent) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? state = null,}) {
  return _then(BridgeTimelineDescriptor_Agent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeThreadAgentIdentity,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeThreadAgentState,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeThreadAgentStateCopyWith<$Res> get state {

  return $BridgeThreadAgentStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_Turn extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Turn({required this.state, this.inputId}): super._();


 final  BridgeTurnState state;
 final  String? inputId;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_TurnCopyWith<BridgeTimelineDescriptor_Turn> get copyWith => _$BridgeTimelineDescriptor_TurnCopyWithImpl<BridgeTimelineDescriptor_Turn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Turn&&(identical(other.state, state) || other.state == state)&&(identical(other.inputId, inputId) || other.inputId == inputId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state,inputId);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.turn(state: $state, inputId: $inputId)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_TurnCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_TurnCopyWith(BridgeTimelineDescriptor_Turn value, $Res Function(BridgeTimelineDescriptor_Turn) _then) = _$BridgeTimelineDescriptor_TurnCopyWithImpl;
@useResult
$Res call({
 BridgeTurnState state, String? inputId
});


$BridgeTurnStateCopyWith<$Res> get state;

}
/// @nodoc
class _$BridgeTimelineDescriptor_TurnCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_TurnCopyWith<$Res> {
  _$BridgeTimelineDescriptor_TurnCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Turn _self;
  final $Res Function(BridgeTimelineDescriptor_Turn) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,Object? inputId = freezed,}) {
  return _then(BridgeTimelineDescriptor_Turn(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeTurnState,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeTurnStateCopyWith<$Res> get state {

  return $BridgeTurnStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_Inference extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Inference({required this.inferenceId, required this.model, required this.state}): super._();


 final  String inferenceId;
 final  String model;
 final  BridgeThreadInferenceState state;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_InferenceCopyWith<BridgeTimelineDescriptor_Inference> get copyWith => _$BridgeTimelineDescriptor_InferenceCopyWithImpl<BridgeTimelineDescriptor_Inference>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Inference&&(identical(other.inferenceId, inferenceId) || other.inferenceId == inferenceId)&&(identical(other.model, model) || other.model == model)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inferenceId,model,state);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.inference(inferenceId: $inferenceId, model: $model, state: $state)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_InferenceCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_InferenceCopyWith(BridgeTimelineDescriptor_Inference value, $Res Function(BridgeTimelineDescriptor_Inference) _then) = _$BridgeTimelineDescriptor_InferenceCopyWithImpl;
@useResult
$Res call({
 String inferenceId, String model, BridgeThreadInferenceState state
});


$BridgeThreadInferenceStateCopyWith<$Res> get state;

}
/// @nodoc
class _$BridgeTimelineDescriptor_InferenceCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_InferenceCopyWith<$Res> {
  _$BridgeTimelineDescriptor_InferenceCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Inference _self;
  final $Res Function(BridgeTimelineDescriptor_Inference) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? inferenceId = null,Object? model = null,Object? state = null,}) {
  return _then(BridgeTimelineDescriptor_Inference(
inferenceId: null == inferenceId ? _self.inferenceId : inferenceId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeThreadInferenceState,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeThreadInferenceStateCopyWith<$Res> get state {

  return $BridgeThreadInferenceStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_Skill extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_Skill({required this.name, required this.source, required this.providerId, required this.resourceBase, required this.cause, required this.activatedAt}): super._();


 final  String name;
 final  String source;
 final  String providerId;
 final  BridgeSkillResourceBase resourceBase;
 final  BridgeSkillActivationCause cause;
 final  PlatformInt64 activatedAt;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_SkillCopyWith<BridgeTimelineDescriptor_Skill> get copyWith => _$BridgeTimelineDescriptor_SkillCopyWithImpl<BridgeTimelineDescriptor_Skill>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_Skill&&(identical(other.name, name) || other.name == name)&&(identical(other.source, source) || other.source == source)&&(identical(other.providerId, providerId) || other.providerId == providerId)&&(identical(other.resourceBase, resourceBase) || other.resourceBase == resourceBase)&&(identical(other.cause, cause) || other.cause == cause)&&(identical(other.activatedAt, activatedAt) || other.activatedAt == activatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,source,providerId,resourceBase,cause,activatedAt);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.skill(name: $name, source: $source, providerId: $providerId, resourceBase: $resourceBase, cause: $cause, activatedAt: $activatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_SkillCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_SkillCopyWith(BridgeTimelineDescriptor_Skill value, $Res Function(BridgeTimelineDescriptor_Skill) _then) = _$BridgeTimelineDescriptor_SkillCopyWithImpl;
@useResult
$Res call({
 String name, String source, String providerId, BridgeSkillResourceBase resourceBase, BridgeSkillActivationCause cause, PlatformInt64 activatedAt
});


$BridgeSkillResourceBaseCopyWith<$Res> get resourceBase;$BridgeSkillActivationCauseCopyWith<$Res> get cause;

}
/// @nodoc
class _$BridgeTimelineDescriptor_SkillCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_SkillCopyWith<$Res> {
  _$BridgeTimelineDescriptor_SkillCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_Skill _self;
  final $Res Function(BridgeTimelineDescriptor_Skill) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? source = null,Object? providerId = null,Object? resourceBase = null,Object? cause = null,Object? activatedAt = null,}) {
  return _then(BridgeTimelineDescriptor_Skill(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as String,resourceBase: null == resourceBase ? _self.resourceBase : resourceBase // ignore: cast_nullable_to_non_nullable
as BridgeSkillResourceBase,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as BridgeSkillActivationCause,activatedAt: null == activatedAt ? _self.activatedAt : activatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeSkillResourceBaseCopyWith<$Res> get resourceBase {

  return $BridgeSkillResourceBaseCopyWith<$Res>(_self.resourceBase, (value) {
    return _then(_self.copyWith(resourceBase: value));
  });
}/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeSkillActivationCauseCopyWith<$Res> get cause {

  return $BridgeSkillActivationCauseCopyWith<$Res>(_self.cause, (value) {
    return _then(_self.copyWith(cause: value));
  });
}
}

/// @nodoc


class BridgeTimelineDescriptor_File extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_File({required this.path, this.mediaType, required this.completedAt}): super._();


 final  String path;
 final  String? mediaType;
 final  PlatformInt64 completedAt;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_FileCopyWith<BridgeTimelineDescriptor_File> get copyWith => _$BridgeTimelineDescriptor_FileCopyWithImpl<BridgeTimelineDescriptor_File>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_File&&(identical(other.path, path) || other.path == path)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path,mediaType,completedAt);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.file(path: $path, mediaType: $mediaType, completedAt: $completedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_FileCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_FileCopyWith(BridgeTimelineDescriptor_File value, $Res Function(BridgeTimelineDescriptor_File) _then) = _$BridgeTimelineDescriptor_FileCopyWithImpl;
@useResult
$Res call({
 String path, String? mediaType, PlatformInt64 completedAt
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_FileCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_FileCopyWith<$Res> {
  _$BridgeTimelineDescriptor_FileCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_File _self;
  final $Res Function(BridgeTimelineDescriptor_File) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? mediaType = freezed,Object? completedAt = null,}) {
  return _then(BridgeTimelineDescriptor_File(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,mediaType: freezed == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeTimelineDescriptor_ContextCompaction extends BridgeTimelineDescriptor {
  const BridgeTimelineDescriptor_ContextCompaction({this.beforeTokens, this.afterTokens, required this.compactedAt}): super._();


 final  BigInt? beforeTokens;
 final  BigInt? afterTokens;
 final  PlatformInt64 compactedAt;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineDescriptor_ContextCompactionCopyWith<BridgeTimelineDescriptor_ContextCompaction> get copyWith => _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl<BridgeTimelineDescriptor_ContextCompaction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineDescriptor_ContextCompaction&&(identical(other.beforeTokens, beforeTokens) || other.beforeTokens == beforeTokens)&&(identical(other.afterTokens, afterTokens) || other.afterTokens == afterTokens)&&(identical(other.compactedAt, compactedAt) || other.compactedAt == compactedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,beforeTokens,afterTokens,compactedAt);
}

@override
String toString() {
    return 'BridgeTimelineDescriptor.contextCompaction(beforeTokens: $beforeTokens, afterTokens: $afterTokens, compactedAt: $compactedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineDescriptor_ContextCompactionCopyWith<$Res> implements $BridgeTimelineDescriptorCopyWith<$Res> {
  factory $BridgeTimelineDescriptor_ContextCompactionCopyWith(BridgeTimelineDescriptor_ContextCompaction value, $Res Function(BridgeTimelineDescriptor_ContextCompaction) _then) = _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl;
@useResult
$Res call({
 BigInt? beforeTokens, BigInt? afterTokens, PlatformInt64 compactedAt
});




}
/// @nodoc
class _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl<$Res>
    implements $BridgeTimelineDescriptor_ContextCompactionCopyWith<$Res> {
  _$BridgeTimelineDescriptor_ContextCompactionCopyWithImpl(this._self, this._then);

  final BridgeTimelineDescriptor_ContextCompaction _self;
  final $Res Function(BridgeTimelineDescriptor_ContextCompaction) _then;

/// Create a copy of BridgeTimelineDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? beforeTokens = freezed,Object? afterTokens = freezed,Object? compactedAt = null,}) {
  return _then(BridgeTimelineDescriptor_ContextCompaction(
beforeTokens: freezed == beforeTokens ? _self.beforeTokens : beforeTokens // ignore: cast_nullable_to_non_nullable
as BigInt?,afterTokens: freezed == afterTokens ? _self.afterTokens : afterTokens // ignore: cast_nullable_to_non_nullable
as BigInt?,compactedAt: null == compactedAt ? _self.compactedAt : compactedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineToolState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState()';
}


}

/// @nodoc
class $BridgeTimelineToolStateCopyWith<$Res>  {
$BridgeTimelineToolStateCopyWith(BridgeTimelineToolState _, $Res Function(BridgeTimelineToolState) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineToolState].
extension BridgeTimelineToolStatePatterns on BridgeTimelineToolState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineToolState_Queued value)?  queued,TResult Function( BridgeTimelineToolState_Cancelling value)?  cancelling,TResult Function( BridgeTimelineToolState_Started value)?  started,TResult Function( BridgeTimelineToolState_Streaming value)?  streaming,TResult Function( BridgeTimelineToolState_AwaitingApproval value)?  awaitingApproval,TResult Function( BridgeTimelineToolState_Approved value)?  approved,TResult Function( BridgeTimelineToolState_Running value)?  running,TResult Function( BridgeTimelineToolState_Interrupted value)?  interrupted,TResult Function( BridgeTimelineToolState_Succeeded value)?  succeeded,TResult Function( BridgeTimelineToolState_Failed value)?  failed,TResult Function( BridgeTimelineToolState_Denied value)?  denied,TResult Function( BridgeTimelineToolState_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineToolState_Queued() when queued != null:
return queued(_that);case BridgeTimelineToolState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeTimelineToolState_Started() when started != null:
return started(_that);case BridgeTimelineToolState_Streaming() when streaming != null:
return streaming(_that);case BridgeTimelineToolState_AwaitingApproval() when awaitingApproval != null:
return awaitingApproval(_that);case BridgeTimelineToolState_Approved() when approved != null:
return approved(_that);case BridgeTimelineToolState_Running() when running != null:
return running(_that);case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineToolState_Queued value)  queued,required TResult Function( BridgeTimelineToolState_Cancelling value)  cancelling,required TResult Function( BridgeTimelineToolState_Started value)  started,required TResult Function( BridgeTimelineToolState_Streaming value)  streaming,required TResult Function( BridgeTimelineToolState_AwaitingApproval value)  awaitingApproval,required TResult Function( BridgeTimelineToolState_Approved value)  approved,required TResult Function( BridgeTimelineToolState_Running value)  running,required TResult Function( BridgeTimelineToolState_Interrupted value)  interrupted,required TResult Function( BridgeTimelineToolState_Succeeded value)  succeeded,required TResult Function( BridgeTimelineToolState_Failed value)  failed,required TResult Function( BridgeTimelineToolState_Denied value)  denied,required TResult Function( BridgeTimelineToolState_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineToolState_Queued():
return queued(_that);case BridgeTimelineToolState_Cancelling():
return cancelling(_that);case BridgeTimelineToolState_Started():
return started(_that);case BridgeTimelineToolState_Streaming():
return streaming(_that);case BridgeTimelineToolState_AwaitingApproval():
return awaitingApproval(_that);case BridgeTimelineToolState_Approved():
return approved(_that);case BridgeTimelineToolState_Running():
return running(_that);case BridgeTimelineToolState_Interrupted():
return interrupted(_that);case BridgeTimelineToolState_Succeeded():
return succeeded(_that);case BridgeTimelineToolState_Failed():
return failed(_that);case BridgeTimelineToolState_Denied():
return denied(_that);case BridgeTimelineToolState_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineToolState_Queued value)?  queued,TResult? Function( BridgeTimelineToolState_Cancelling value)?  cancelling,TResult? Function( BridgeTimelineToolState_Started value)?  started,TResult? Function( BridgeTimelineToolState_Streaming value)?  streaming,TResult? Function( BridgeTimelineToolState_AwaitingApproval value)?  awaitingApproval,TResult? Function( BridgeTimelineToolState_Approved value)?  approved,TResult? Function( BridgeTimelineToolState_Running value)?  running,TResult? Function( BridgeTimelineToolState_Interrupted value)?  interrupted,TResult? Function( BridgeTimelineToolState_Succeeded value)?  succeeded,TResult? Function( BridgeTimelineToolState_Failed value)?  failed,TResult? Function( BridgeTimelineToolState_Denied value)?  denied,TResult? Function( BridgeTimelineToolState_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case BridgeTimelineToolState_Queued() when queued != null:
return queued(_that);case BridgeTimelineToolState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeTimelineToolState_Started() when started != null:
return started(_that);case BridgeTimelineToolState_Streaming() when streaming != null:
return streaming(_that);case BridgeTimelineToolState_AwaitingApproval() when awaitingApproval != null:
return awaitingApproval(_that);case BridgeTimelineToolState_Approved() when approved != null:
return approved(_that);case BridgeTimelineToolState_Running() when running != null:
return running(_that);case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  queued,TResult Function()?  cancelling,TResult Function()?  started,TResult Function()?  streaming,TResult Function()?  awaitingApproval,TResult Function()?  approved,TResult Function()?  running,TResult Function( PlatformInt64 interruptedAt,  String reason)?  interrupted,TResult Function( PlatformInt64 completedAt,  BridgeTimelineToolOutputDescriptor output)?  succeeded,TResult Function( PlatformInt64 failedAt,  BridgeThreadToolFailure failure,  BridgeTimelineToolOutputDescriptor? output)?  failed,TResult Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineToolState_Queued() when queued != null:
return queued();case BridgeTimelineToolState_Cancelling() when cancelling != null:
return cancelling();case BridgeTimelineToolState_Started() when started != null:
return started();case BridgeTimelineToolState_Streaming() when streaming != null:
return streaming();case BridgeTimelineToolState_AwaitingApproval() when awaitingApproval != null:
return awaitingApproval();case BridgeTimelineToolState_Approved() when approved != null:
return approved();case BridgeTimelineToolState_Running() when running != null:
return running();case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that.interruptedAt,_that.reason);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.output);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that.failedAt,_that.failure,_that.output);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  queued,required TResult Function()  cancelling,required TResult Function()  started,required TResult Function()  streaming,required TResult Function()  awaitingApproval,required TResult Function()  approved,required TResult Function()  running,required TResult Function( PlatformInt64 interruptedAt,  String reason)  interrupted,required TResult Function( PlatformInt64 completedAt,  BridgeTimelineToolOutputDescriptor output)  succeeded,required TResult Function( PlatformInt64 failedAt,  BridgeThreadToolFailure failure,  BridgeTimelineToolOutputDescriptor? output)  failed,required TResult Function( PlatformInt64 deniedAt,  String reason)  denied,required TResult Function( PlatformInt64 cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineToolState_Queued():
return queued();case BridgeTimelineToolState_Cancelling():
return cancelling();case BridgeTimelineToolState_Started():
return started();case BridgeTimelineToolState_Streaming():
return streaming();case BridgeTimelineToolState_AwaitingApproval():
return awaitingApproval();case BridgeTimelineToolState_Approved():
return approved();case BridgeTimelineToolState_Running():
return running();case BridgeTimelineToolState_Interrupted():
return interrupted(_that.interruptedAt,_that.reason);case BridgeTimelineToolState_Succeeded():
return succeeded(_that.completedAt,_that.output);case BridgeTimelineToolState_Failed():
return failed(_that.failedAt,_that.failure,_that.output);case BridgeTimelineToolState_Denied():
return denied(_that.deniedAt,_that.reason);case BridgeTimelineToolState_Cancelled():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  queued,TResult? Function()?  cancelling,TResult? Function()?  started,TResult? Function()?  streaming,TResult? Function()?  awaitingApproval,TResult? Function()?  approved,TResult? Function()?  running,TResult? Function( PlatformInt64 interruptedAt,  String reason)?  interrupted,TResult? Function( PlatformInt64 completedAt,  BridgeTimelineToolOutputDescriptor output)?  succeeded,TResult? Function( PlatformInt64 failedAt,  BridgeThreadToolFailure failure,  BridgeTimelineToolOutputDescriptor? output)?  failed,TResult? Function( PlatformInt64 deniedAt,  String reason)?  denied,TResult? Function( PlatformInt64 cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case BridgeTimelineToolState_Queued() when queued != null:
return queued();case BridgeTimelineToolState_Cancelling() when cancelling != null:
return cancelling();case BridgeTimelineToolState_Started() when started != null:
return started();case BridgeTimelineToolState_Streaming() when streaming != null:
return streaming();case BridgeTimelineToolState_AwaitingApproval() when awaitingApproval != null:
return awaitingApproval();case BridgeTimelineToolState_Approved() when approved != null:
return approved();case BridgeTimelineToolState_Running() when running != null:
return running();case BridgeTimelineToolState_Interrupted() when interrupted != null:
return interrupted(_that.interruptedAt,_that.reason);case BridgeTimelineToolState_Succeeded() when succeeded != null:
return succeeded(_that.completedAt,_that.output);case BridgeTimelineToolState_Failed() when failed != null:
return failed(_that.failedAt,_that.failure,_that.output);case BridgeTimelineToolState_Denied() when denied != null:
return denied(_that.deniedAt,_that.reason);case BridgeTimelineToolState_Cancelled() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineToolState_Queued extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Queued(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Queued);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState.queued()';
}


}




/// @nodoc


class BridgeTimelineToolState_Cancelling extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Cancelling(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Cancelling);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState.cancelling()';
}


}




/// @nodoc


class BridgeTimelineToolState_Started extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Started(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Started);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState.started()';
}


}




/// @nodoc


class BridgeTimelineToolState_Streaming extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Streaming(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Streaming);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState.streaming()';
}


}




/// @nodoc


class BridgeTimelineToolState_AwaitingApproval extends BridgeTimelineToolState {
  const BridgeTimelineToolState_AwaitingApproval(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_AwaitingApproval);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState.awaitingApproval()';
}


}




/// @nodoc


class BridgeTimelineToolState_Approved extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Approved(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Approved);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState.approved()';
}


}




/// @nodoc


class BridgeTimelineToolState_Running extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Running(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Running);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineToolState.running()';
}


}




/// @nodoc


class BridgeTimelineToolState_Interrupted extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Interrupted({required this.interruptedAt, required this.reason}): super._();


 final  PlatformInt64 interruptedAt;
 final  String reason;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_InterruptedCopyWith<BridgeTimelineToolState_Interrupted> get copyWith => _$BridgeTimelineToolState_InterruptedCopyWithImpl<BridgeTimelineToolState_Interrupted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Interrupted&&(identical(other.interruptedAt, interruptedAt) || other.interruptedAt == interruptedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,interruptedAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineToolState.interrupted(interruptedAt: $interruptedAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_InterruptedCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_InterruptedCopyWith(BridgeTimelineToolState_Interrupted value, $Res Function(BridgeTimelineToolState_Interrupted) _then) = _$BridgeTimelineToolState_InterruptedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 interruptedAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineToolState_InterruptedCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_InterruptedCopyWith<$Res> {
  _$BridgeTimelineToolState_InterruptedCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Interrupted _self;
  final $Res Function(BridgeTimelineToolState_Interrupted) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? interruptedAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineToolState_Interrupted(
interruptedAt: null == interruptedAt ? _self.interruptedAt : interruptedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Succeeded extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Succeeded({required this.completedAt, required this.output}): super._();


 final  PlatformInt64 completedAt;
 final  BridgeTimelineToolOutputDescriptor output;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_SucceededCopyWith<BridgeTimelineToolState_Succeeded> get copyWith => _$BridgeTimelineToolState_SucceededCopyWithImpl<BridgeTimelineToolState_Succeeded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Succeeded&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,output);
}

@override
String toString() {
    return 'BridgeTimelineToolState.succeeded(completedAt: $completedAt, output: $output)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_SucceededCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_SucceededCopyWith(BridgeTimelineToolState_Succeeded value, $Res Function(BridgeTimelineToolState_Succeeded) _then) = _$BridgeTimelineToolState_SucceededCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 completedAt, BridgeTimelineToolOutputDescriptor output
});




}
/// @nodoc
class _$BridgeTimelineToolState_SucceededCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_SucceededCopyWith<$Res> {
  _$BridgeTimelineToolState_SucceededCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Succeeded _self;
  final $Res Function(BridgeTimelineToolState_Succeeded) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? output = null,}) {
  return _then(BridgeTimelineToolState_Succeeded(
completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as BridgeTimelineToolOutputDescriptor,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Failed extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Failed({required this.failedAt, required this.failure, this.output}): super._();


 final  PlatformInt64 failedAt;
 final  BridgeThreadToolFailure failure;
 final  BridgeTimelineToolOutputDescriptor? output;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_FailedCopyWith<BridgeTimelineToolState_Failed> get copyWith => _$BridgeTimelineToolState_FailedCopyWithImpl<BridgeTimelineToolState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Failed&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,failure,output);
}

@override
String toString() {
    return 'BridgeTimelineToolState.failed(failedAt: $failedAt, failure: $failure, output: $output)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_FailedCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_FailedCopyWith(BridgeTimelineToolState_Failed value, $Res Function(BridgeTimelineToolState_Failed) _then) = _$BridgeTimelineToolState_FailedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 failedAt, BridgeThreadToolFailure failure, BridgeTimelineToolOutputDescriptor? output
});




}
/// @nodoc
class _$BridgeTimelineToolState_FailedCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_FailedCopyWith<$Res> {
  _$BridgeTimelineToolState_FailedCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Failed _self;
  final $Res Function(BridgeTimelineToolState_Failed) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? failure = null,Object? output = freezed,}) {
  return _then(BridgeTimelineToolState_Failed(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeThreadToolFailure,output: freezed == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as BridgeTimelineToolOutputDescriptor?,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Denied extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Denied({required this.deniedAt, required this.reason}): super._();


 final  PlatformInt64 deniedAt;
 final  String reason;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_DeniedCopyWith<BridgeTimelineToolState_Denied> get copyWith => _$BridgeTimelineToolState_DeniedCopyWithImpl<BridgeTimelineToolState_Denied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Denied&&(identical(other.deniedAt, deniedAt) || other.deniedAt == deniedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deniedAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineToolState.denied(deniedAt: $deniedAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_DeniedCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_DeniedCopyWith(BridgeTimelineToolState_Denied value, $Res Function(BridgeTimelineToolState_Denied) _then) = _$BridgeTimelineToolState_DeniedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 deniedAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineToolState_DeniedCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_DeniedCopyWith<$Res> {
  _$BridgeTimelineToolState_DeniedCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Denied _self;
  final $Res Function(BridgeTimelineToolState_Denied) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deniedAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineToolState_Denied(
deniedAt: null == deniedAt ? _self.deniedAt : deniedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineToolState_Cancelled extends BridgeTimelineToolState {
  const BridgeTimelineToolState_Cancelled({required this.cancelledAt, required this.reason}): super._();


 final  PlatformInt64 cancelledAt;
 final  String reason;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineToolState_CancelledCopyWith<BridgeTimelineToolState_Cancelled> get copyWith => _$BridgeTimelineToolState_CancelledCopyWithImpl<BridgeTimelineToolState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineToolState_Cancelled&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeTimelineToolState.cancelled(cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineToolState_CancelledCopyWith<$Res> implements $BridgeTimelineToolStateCopyWith<$Res> {
  factory $BridgeTimelineToolState_CancelledCopyWith(BridgeTimelineToolState_Cancelled value, $Res Function(BridgeTimelineToolState_Cancelled) _then) = _$BridgeTimelineToolState_CancelledCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 cancelledAt, String reason
});




}
/// @nodoc
class _$BridgeTimelineToolState_CancelledCopyWithImpl<$Res>
    implements $BridgeTimelineToolState_CancelledCopyWith<$Res> {
  _$BridgeTimelineToolState_CancelledCopyWithImpl(this._self, this._then);

  final BridgeTimelineToolState_Cancelled _self;
  final $Res Function(BridgeTimelineToolState_Cancelled) _then;

/// Create a copy of BridgeTimelineToolState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeTimelineToolState_Cancelled(
cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineUserInputState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUserInputState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineUserInputState()';
}


}

/// @nodoc
class $BridgeTimelineUserInputStateCopyWith<$Res>  {
$BridgeTimelineUserInputStateCopyWith(BridgeTimelineUserInputState _, $Res Function(BridgeTimelineUserInputState) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineUserInputState].
extension BridgeTimelineUserInputStatePatterns on BridgeTimelineUserInputState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineUserInputState_Pending value)?  pending,TResult Function( BridgeTimelineUserInputState_Cancelled value)?  cancelled,TResult Function( BridgeTimelineUserInputState_Resolved value)?  resolved,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Pending() when pending != null:
return pending(_that);case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineUserInputState_Pending value)  pending,required TResult Function( BridgeTimelineUserInputState_Cancelled value)  cancelled,required TResult Function( BridgeTimelineUserInputState_Resolved value)  resolved,}){
final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Pending():
return pending(_that);case BridgeTimelineUserInputState_Cancelled():
return cancelled(_that);case BridgeTimelineUserInputState_Resolved():
return resolved(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineUserInputState_Pending value)?  pending,TResult? Function( BridgeTimelineUserInputState_Cancelled value)?  cancelled,TResult? Function( BridgeTimelineUserInputState_Resolved value)?  resolved,}){
final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Pending() when pending != null:
return pending(_that);case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  pending,TResult Function()?  cancelled,TResult Function( List<BridgeTimelineAnswerDescriptor> answers)?  resolved,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Pending() when pending != null:
return pending();case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled();case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that.answers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  pending,required TResult Function()  cancelled,required TResult Function( List<BridgeTimelineAnswerDescriptor> answers)  resolved,}) {final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Pending():
return pending();case BridgeTimelineUserInputState_Cancelled():
return cancelled();case BridgeTimelineUserInputState_Resolved():
return resolved(_that.answers);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  pending,TResult? Function()?  cancelled,TResult? Function( List<BridgeTimelineAnswerDescriptor> answers)?  resolved,}) {final _that = this;
switch (_that) {
case BridgeTimelineUserInputState_Pending() when pending != null:
return pending();case BridgeTimelineUserInputState_Cancelled() when cancelled != null:
return cancelled();case BridgeTimelineUserInputState_Resolved() when resolved != null:
return resolved(_that.answers);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineUserInputState_Pending extends BridgeTimelineUserInputState {
  const BridgeTimelineUserInputState_Pending(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUserInputState_Pending);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineUserInputState.pending()';
}


}




/// @nodoc


class BridgeTimelineUserInputState_Cancelled extends BridgeTimelineUserInputState {
  const BridgeTimelineUserInputState_Cancelled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUserInputState_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineUserInputState.cancelled()';
}


}




/// @nodoc


class BridgeTimelineUserInputState_Resolved extends BridgeTimelineUserInputState {
  const BridgeTimelineUserInputState_Resolved({required  List<BridgeTimelineAnswerDescriptor> answers}): _answers = answers,super._();


 final  List<BridgeTimelineAnswerDescriptor> _answers;
 List<BridgeTimelineAnswerDescriptor> get answers {
  if (_answers is EqualUnmodifiableListView) return _answers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_answers);
}


/// Create a copy of BridgeTimelineUserInputState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineUserInputState_ResolvedCopyWith<BridgeTimelineUserInputState_Resolved> get copyWith => _$BridgeTimelineUserInputState_ResolvedCopyWithImpl<BridgeTimelineUserInputState_Resolved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUserInputState_Resolved&&const DeepCollectionEquality().equals(other.answers, _answers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_answers));
}

@override
String toString() {
    return 'BridgeTimelineUserInputState.resolved(answers: $answers)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineUserInputState_ResolvedCopyWith<$Res> implements $BridgeTimelineUserInputStateCopyWith<$Res> {
  factory $BridgeTimelineUserInputState_ResolvedCopyWith(BridgeTimelineUserInputState_Resolved value, $Res Function(BridgeTimelineUserInputState_Resolved) _then) = _$BridgeTimelineUserInputState_ResolvedCopyWithImpl;
@useResult
$Res call({
 List<BridgeTimelineAnswerDescriptor> answers
});




}
/// @nodoc
class _$BridgeTimelineUserInputState_ResolvedCopyWithImpl<$Res>
    implements $BridgeTimelineUserInputState_ResolvedCopyWith<$Res> {
  _$BridgeTimelineUserInputState_ResolvedCopyWithImpl(this._self, this._then);

  final BridgeTimelineUserInputState_Resolved _self;
  final $Res Function(BridgeTimelineUserInputState_Resolved) _then;

/// Create a copy of BridgeTimelineUserInputState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? answers = null,}) {
  return _then(BridgeTimelineUserInputState_Resolved(
answers: null == answers ? _self._answers : answers // ignore: cast_nullable_to_non_nullable
as List<BridgeTimelineAnswerDescriptor>,
  ));
}


}

// dart format on
