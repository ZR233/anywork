// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction_snapshot.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InteractionSnapshot {


/// Create a copy of InteractionSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionSnapshotCopyWith<InteractionSnapshot> get copyWith => _$InteractionSnapshotCopyWithImpl<InteractionSnapshot>(this as InteractionSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionSnapshot&&(identical(other.interactionId, _this.interactionId) || other.interactionId == _this.interactionId)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.content, _this.content) || other.content == _this.content)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as InteractionSnapshot;
  return Object.hash(runtimeType,_this.interactionId,_this.scope,_this.revision,_this.content,_this.createdAt,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $InteractionSnapshotCopyWith<$Res>  {
  factory $InteractionSnapshotCopyWith(InteractionSnapshot value, $Res Function(InteractionSnapshot) _then) = _$InteractionSnapshotCopyWithImpl;
@useResult
$Res call({
 String interactionId, InteractionScope scope, int revision, InteractionSnapshotContent content, int createdAt, int updatedAt
});


$InteractionScopeCopyWith<$Res> get scope;$InteractionSnapshotContentCopyWith<$Res> get content;

}
/// @nodoc
class _$InteractionSnapshotCopyWithImpl<$Res>
    implements $InteractionSnapshotCopyWith<$Res> {
  _$InteractionSnapshotCopyWithImpl(this._self, this._then);

  final InteractionSnapshot _self;
  final $Res Function(InteractionSnapshot) _then;

/// Create a copy of InteractionSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? interactionId = null,Object? scope = null,Object? revision = null,Object? content = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(InteractionSnapshot(
interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as InteractionScope,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as InteractionSnapshotContent,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of InteractionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionScopeCopyWith<$Res> get scope {

  return $InteractionScopeCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of InteractionSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionSnapshotContentCopyWith<$Res> get content {

  return $InteractionSnapshotContentCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionSnapshot].
extension InteractionSnapshotPatterns on InteractionSnapshot {
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
mixin _$InteractionScope {


/// Create a copy of InteractionScope
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionScopeCopyWith<InteractionScope> get copyWith => _$InteractionScopeCopyWithImpl<InteractionScope>(this as InteractionScope, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionScope;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionScope&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.itemId, _this.itemId) || other.itemId == _this.itemId)&&(identical(other.toolId, _this.toolId) || other.toolId == _this.toolId)&&(identical(other.agentPath, _this.agentPath) || other.agentPath == _this.agentPath));
}


@override
int get hashCode {
  final _this = this as InteractionScope;
  return Object.hash(runtimeType,_this.threadId,_this.turnId,_this.itemId,_this.toolId,_this.agentPath);
}



}

/// @nodoc
abstract mixin class $InteractionScopeCopyWith<$Res>  {
  factory $InteractionScopeCopyWith(InteractionScope value, $Res Function(InteractionScope) _then) = _$InteractionScopeCopyWithImpl;
@useResult
$Res call({
 String threadId, String turnId, String? itemId, String? toolId, String? agentPath
});




}
/// @nodoc
class _$InteractionScopeCopyWithImpl<$Res>
    implements $InteractionScopeCopyWith<$Res> {
  _$InteractionScopeCopyWithImpl(this._self, this._then);

  final InteractionScope _self;
  final $Res Function(InteractionScope) _then;

/// Create a copy of InteractionScope
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? turnId = null,Object? itemId = freezed,Object? toolId = freezed,Object? agentPath = freezed,}) {
  return _then(InteractionScope(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,itemId: freezed == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String?,toolId: freezed == toolId ? _self.toolId : toolId // ignore: cast_nullable_to_non_nullable
as String?,agentPath: freezed == agentPath ? _self.agentPath : agentPath // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [InteractionScope].
extension InteractionScopePatterns on InteractionScope {
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
mixin _$InteractionSnapshotContent {

 Object get state;



@override
bool operator ==(Object other) {
  final _this = this as InteractionSnapshotContent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionSnapshotContent&&const DeepCollectionEquality().equals(other.state, _this.state));
}


@override
int get hashCode {
  final _this = this as InteractionSnapshotContent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.state));
}



}

/// @nodoc
class $InteractionSnapshotContentCopyWith<$Res>  {
$InteractionSnapshotContentCopyWith(InteractionSnapshotContent _, $Res Function(InteractionSnapshotContent) __);
}


/// Adds pattern-matching-related methods to [InteractionSnapshotContent].
extension InteractionSnapshotContentPatterns on InteractionSnapshotContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UserInputInteractionContent value)?  userInput,TResult Function( ToolApprovalInteractionContent value)?  toolApproval,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UserInputInteractionContent() when userInput != null:
return userInput(_that);case ToolApprovalInteractionContent() when toolApproval != null:
return toolApproval(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UserInputInteractionContent value)  userInput,required TResult Function( ToolApprovalInteractionContent value)  toolApproval,}){
final _that = this;
switch (_that) {
case UserInputInteractionContent():
return userInput(_that);case ToolApprovalInteractionContent():
return toolApproval(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UserInputInteractionContent value)?  userInput,TResult? Function( ToolApprovalInteractionContent value)?  toolApproval,}){
final _that = this;
switch (_that) {
case UserInputInteractionContent() when userInput != null:
return userInput(_that);case ToolApprovalInteractionContent() when toolApproval != null:
return toolApproval(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<InteractionQuestion> questions,  UserInputInteractionState state)?  userInput,TResult Function( String name,  String arguments,  String? workingDirectory,  String? parentAgentId,  ToolApprovalInteractionState state)?  toolApproval,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UserInputInteractionContent() when userInput != null:
return userInput(_that.questions,_that.state);case ToolApprovalInteractionContent() when toolApproval != null:
return toolApproval(_that.name,_that.arguments,_that.workingDirectory,_that.parentAgentId,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<InteractionQuestion> questions,  UserInputInteractionState state)  userInput,required TResult Function( String name,  String arguments,  String? workingDirectory,  String? parentAgentId,  ToolApprovalInteractionState state)  toolApproval,}) {final _that = this;
switch (_that) {
case UserInputInteractionContent():
return userInput(_that.questions,_that.state);case ToolApprovalInteractionContent():
return toolApproval(_that.name,_that.arguments,_that.workingDirectory,_that.parentAgentId,_that.state);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<InteractionQuestion> questions,  UserInputInteractionState state)?  userInput,TResult? Function( String name,  String arguments,  String? workingDirectory,  String? parentAgentId,  ToolApprovalInteractionState state)?  toolApproval,}) {final _that = this;
switch (_that) {
case UserInputInteractionContent() when userInput != null:
return userInput(_that.questions,_that.state);case ToolApprovalInteractionContent() when toolApproval != null:
return toolApproval(_that.name,_that.arguments,_that.workingDirectory,_that.parentAgentId,_that.state);case _:
  return null;

}
}

}



/// @nodoc
mixin _$UserInputInteractionContent {


/// Create a copy of UserInputInteractionContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserInputInteractionContentCopyWith<UserInputInteractionContent> get copyWith => _$UserInputInteractionContentCopyWithImpl<UserInputInteractionContent>(this as UserInputInteractionContent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UserInputInteractionContent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserInputInteractionContent&&const DeepCollectionEquality().equals(other.questions, _this.questions)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as UserInputInteractionContent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.questions),_this.state);
}



}

/// @nodoc
abstract mixin class $UserInputInteractionContentCopyWith<$Res> implements $InteractionSnapshotContentCopyWith<$Res> {
  factory $UserInputInteractionContentCopyWith(UserInputInteractionContent value, $Res Function(UserInputInteractionContent) _then) = _$UserInputInteractionContentCopyWithImpl;
@useResult
$Res call({
 List<InteractionQuestion> questions, UserInputInteractionState state
});


$UserInputInteractionStateCopyWith<$Res> get state;

}
/// @nodoc
class _$UserInputInteractionContentCopyWithImpl<$Res>
    implements $UserInputInteractionContentCopyWith<$Res> {
  _$UserInputInteractionContentCopyWithImpl(this._self, this._then);

  final UserInputInteractionContent _self;
  final $Res Function(UserInputInteractionContent) _then;

/// Create a copy of UserInputInteractionContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? questions = null,Object? state = null,}) {
  return _then(UserInputInteractionContent(
questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<InteractionQuestion>,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as UserInputInteractionState,
  ));
}
/// Create a copy of UserInputInteractionContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UserInputInteractionStateCopyWith<$Res> get state {

  return $UserInputInteractionStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [UserInputInteractionContent].
extension UserInputInteractionContentPatterns on UserInputInteractionContent {
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
mixin _$ToolApprovalInteractionContent {


/// Create a copy of ToolApprovalInteractionContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToolApprovalInteractionContentCopyWith<ToolApprovalInteractionContent> get copyWith => _$ToolApprovalInteractionContentCopyWithImpl<ToolApprovalInteractionContent>(this as ToolApprovalInteractionContent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ToolApprovalInteractionContent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ToolApprovalInteractionContent&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.arguments, _this.arguments) || other.arguments == _this.arguments)&&(identical(other.workingDirectory, _this.workingDirectory) || other.workingDirectory == _this.workingDirectory)&&(identical(other.parentAgentId, _this.parentAgentId) || other.parentAgentId == _this.parentAgentId)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as ToolApprovalInteractionContent;
  return Object.hash(runtimeType,_this.name,_this.arguments,_this.workingDirectory,_this.parentAgentId,_this.state);
}



}

/// @nodoc
abstract mixin class $ToolApprovalInteractionContentCopyWith<$Res> implements $InteractionSnapshotContentCopyWith<$Res> {
  factory $ToolApprovalInteractionContentCopyWith(ToolApprovalInteractionContent value, $Res Function(ToolApprovalInteractionContent) _then) = _$ToolApprovalInteractionContentCopyWithImpl;
@useResult
$Res call({
 String name, String arguments, String? workingDirectory, String? parentAgentId, ToolApprovalInteractionState state
});


$ToolApprovalInteractionStateCopyWith<$Res> get state;

}
/// @nodoc
class _$ToolApprovalInteractionContentCopyWithImpl<$Res>
    implements $ToolApprovalInteractionContentCopyWith<$Res> {
  _$ToolApprovalInteractionContentCopyWithImpl(this._self, this._then);

  final ToolApprovalInteractionContent _self;
  final $Res Function(ToolApprovalInteractionContent) _then;

/// Create a copy of ToolApprovalInteractionContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? arguments = null,Object? workingDirectory = freezed,Object? parentAgentId = freezed,Object? state = null,}) {
  return _then(ToolApprovalInteractionContent(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as String,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String?,parentAgentId: freezed == parentAgentId ? _self.parentAgentId : parentAgentId // ignore: cast_nullable_to_non_nullable
as String?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ToolApprovalInteractionState,
  ));
}
/// Create a copy of ToolApprovalInteractionContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ToolApprovalInteractionStateCopyWith<$Res> get state {

  return $ToolApprovalInteractionStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [ToolApprovalInteractionContent].
extension ToolApprovalInteractionContentPatterns on ToolApprovalInteractionContent {
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
mixin _$InteractionQuestion {


/// Create a copy of InteractionQuestion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionQuestionCopyWith<InteractionQuestion> get copyWith => _$InteractionQuestionCopyWithImpl<InteractionQuestion>(this as InteractionQuestion, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionQuestion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionQuestion&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.question, _this.question) || other.question == _this.question)&&(identical(other.isOther, _this.isOther) || other.isOther == _this.isOther)&&(identical(other.isSecret, _this.isSecret) || other.isSecret == _this.isSecret)&&const DeepCollectionEquality().equals(other.options, _this.options));
}


@override
int get hashCode {
  final _this = this as InteractionQuestion;
  return Object.hash(runtimeType,_this.id,_this.header,_this.question,_this.isOther,_this.isSecret,const DeepCollectionEquality().hash(_this.options));
}



}

/// @nodoc
abstract mixin class $InteractionQuestionCopyWith<$Res>  {
  factory $InteractionQuestionCopyWith(InteractionQuestion value, $Res Function(InteractionQuestion) _then) = _$InteractionQuestionCopyWithImpl;
@useResult
$Res call({
 String id, String header, String question, bool isOther, bool isSecret, List<UserQuestionOptionView>? options
});




}
/// @nodoc
class _$InteractionQuestionCopyWithImpl<$Res>
    implements $InteractionQuestionCopyWith<$Res> {
  _$InteractionQuestionCopyWithImpl(this._self, this._then);

  final InteractionQuestion _self;
  final $Res Function(InteractionQuestion) _then;

/// Create a copy of InteractionQuestion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? header = null,Object? question = null,Object? isOther = null,Object? isSecret = null,Object? options = freezed,}) {
  return _then(InteractionQuestion(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,isOther: null == isOther ? _self.isOther : isOther // ignore: cast_nullable_to_non_nullable
as bool,isSecret: null == isSecret ? _self.isSecret : isSecret // ignore: cast_nullable_to_non_nullable
as bool,options: freezed == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<UserQuestionOptionView>?,
  ));
}

}


/// Adds pattern-matching-related methods to [InteractionQuestion].
extension InteractionQuestionPatterns on InteractionQuestion {
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
mixin _$UserInputInteractionState {

 String get operationId;
/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserInputInteractionStateCopyWith<UserInputInteractionState> get copyWith => _$UserInputInteractionStateCopyWithImpl<UserInputInteractionState>(this as UserInputInteractionState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UserInputInteractionState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserInputInteractionState&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as UserInputInteractionState;
  return Object.hash(runtimeType,_this.operationId);
}



}

/// @nodoc
abstract mixin class $UserInputInteractionStateCopyWith<$Res>  {
  factory $UserInputInteractionStateCopyWith(UserInputInteractionState value, $Res Function(UserInputInteractionState) _then) = _$UserInputInteractionStateCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$UserInputInteractionStateCopyWithImpl<$Res>
    implements $UserInputInteractionStateCopyWith<$Res> {
  _$UserInputInteractionStateCopyWithImpl(this._self, this._then);

  final UserInputInteractionState _self;
  final $Res Function(UserInputInteractionState) _then;

/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,}) {
  return _then(_self.copyWith(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [UserInputInteractionState].
extension UserInputInteractionStatePatterns on UserInputInteractionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PendingUserInputInteraction value)?  pending,TResult Function( ResolvedUserInputInteraction value)?  resolved,TResult Function( CancelledUserInputInteraction value)?  cancelled,TResult Function( ExpiredUserInputInteraction value)?  expired,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PendingUserInputInteraction() when pending != null:
return pending(_that);case ResolvedUserInputInteraction() when resolved != null:
return resolved(_that);case CancelledUserInputInteraction() when cancelled != null:
return cancelled(_that);case ExpiredUserInputInteraction() when expired != null:
return expired(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PendingUserInputInteraction value)  pending,required TResult Function( ResolvedUserInputInteraction value)  resolved,required TResult Function( CancelledUserInputInteraction value)  cancelled,required TResult Function( ExpiredUserInputInteraction value)  expired,}){
final _that = this;
switch (_that) {
case PendingUserInputInteraction():
return pending(_that);case ResolvedUserInputInteraction():
return resolved(_that);case CancelledUserInputInteraction():
return cancelled(_that);case ExpiredUserInputInteraction():
return expired(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PendingUserInputInteraction value)?  pending,TResult? Function( ResolvedUserInputInteraction value)?  resolved,TResult? Function( CancelledUserInputInteraction value)?  cancelled,TResult? Function( ExpiredUserInputInteraction value)?  expired,}){
final _that = this;
switch (_that) {
case PendingUserInputInteraction() when pending != null:
return pending(_that);case ResolvedUserInputInteraction() when resolved != null:
return resolved(_that);case CancelledUserInputInteraction() when cancelled != null:
return cancelled(_that);case ExpiredUserInputInteraction() when expired != null:
return expired(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String operationId)?  pending,TResult Function( String operationId,  int resolvedAt,  List<UserInputAnswerCommand> answers)?  resolved,TResult Function( String operationId,  int cancelledAt,  String reason)?  cancelled,TResult Function( String operationId,  int expiredAt)?  expired,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PendingUserInputInteraction() when pending != null:
return pending(_that.operationId);case ResolvedUserInputInteraction() when resolved != null:
return resolved(_that.operationId,_that.resolvedAt,_that.answers);case CancelledUserInputInteraction() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredUserInputInteraction() when expired != null:
return expired(_that.operationId,_that.expiredAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String operationId)  pending,required TResult Function( String operationId,  int resolvedAt,  List<UserInputAnswerCommand> answers)  resolved,required TResult Function( String operationId,  int cancelledAt,  String reason)  cancelled,required TResult Function( String operationId,  int expiredAt)  expired,}) {final _that = this;
switch (_that) {
case PendingUserInputInteraction():
return pending(_that.operationId);case ResolvedUserInputInteraction():
return resolved(_that.operationId,_that.resolvedAt,_that.answers);case CancelledUserInputInteraction():
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredUserInputInteraction():
return expired(_that.operationId,_that.expiredAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String operationId)?  pending,TResult? Function( String operationId,  int resolvedAt,  List<UserInputAnswerCommand> answers)?  resolved,TResult? Function( String operationId,  int cancelledAt,  String reason)?  cancelled,TResult? Function( String operationId,  int expiredAt)?  expired,}) {final _that = this;
switch (_that) {
case PendingUserInputInteraction() when pending != null:
return pending(_that.operationId);case ResolvedUserInputInteraction() when resolved != null:
return resolved(_that.operationId,_that.resolvedAt,_that.answers);case CancelledUserInputInteraction() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredUserInputInteraction() when expired != null:
return expired(_that.operationId,_that.expiredAt);case _:
  return null;

}
}

}

/// @nodoc


class PendingUserInputInteraction extends UserInputInteractionState {
  const PendingUserInputInteraction({required this.operationId}): super._();


@override final  String operationId;

/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PendingUserInputInteractionCopyWith<PendingUserInputInteraction> get copyWith => _$PendingUserInputInteractionCopyWithImpl<PendingUserInputInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingUserInputInteraction&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $PendingUserInputInteractionCopyWith<$Res> implements $UserInputInteractionStateCopyWith<$Res> {
  factory $PendingUserInputInteractionCopyWith(PendingUserInputInteraction value, $Res Function(PendingUserInputInteraction) _then) = _$PendingUserInputInteractionCopyWithImpl;
@override @useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$PendingUserInputInteractionCopyWithImpl<$Res>
    implements $PendingUserInputInteractionCopyWith<$Res> {
  _$PendingUserInputInteractionCopyWithImpl(this._self, this._then);

  final PendingUserInputInteraction _self;
  final $Res Function(PendingUserInputInteraction) _then;

/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(PendingUserInputInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc


class CancelledUserInputInteraction extends UserInputInteractionState {
  const CancelledUserInputInteraction({required this.operationId, required this.cancelledAt, required this.reason}): super._();


@override final  String operationId;
 final  int cancelledAt;
 final  String reason;

/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledUserInputInteractionCopyWith<CancelledUserInputInteraction> get copyWith => _$CancelledUserInputInteractionCopyWithImpl<CancelledUserInputInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledUserInputInteraction&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,cancelledAt,reason);
}



}

/// @nodoc
abstract mixin class $CancelledUserInputInteractionCopyWith<$Res> implements $UserInputInteractionStateCopyWith<$Res> {
  factory $CancelledUserInputInteractionCopyWith(CancelledUserInputInteraction value, $Res Function(CancelledUserInputInteraction) _then) = _$CancelledUserInputInteractionCopyWithImpl;
@override @useResult
$Res call({
 String operationId, int cancelledAt, String reason
});




}
/// @nodoc
class _$CancelledUserInputInteractionCopyWithImpl<$Res>
    implements $CancelledUserInputInteractionCopyWith<$Res> {
  _$CancelledUserInputInteractionCopyWithImpl(this._self, this._then);

  final CancelledUserInputInteraction _self;
  final $Res Function(CancelledUserInputInteraction) _then;

/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? cancelledAt = null,Object? reason = null,}) {
  return _then(CancelledUserInputInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ExpiredUserInputInteraction extends UserInputInteractionState {
  const ExpiredUserInputInteraction({required this.operationId, required this.expiredAt}): super._();


@override final  String operationId;
 final  int expiredAt;

/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExpiredUserInputInteractionCopyWith<ExpiredUserInputInteraction> get copyWith => _$ExpiredUserInputInteractionCopyWithImpl<ExpiredUserInputInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ExpiredUserInputInteraction&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expiredAt, expiredAt) || other.expiredAt == expiredAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expiredAt);
}



}

/// @nodoc
abstract mixin class $ExpiredUserInputInteractionCopyWith<$Res> implements $UserInputInteractionStateCopyWith<$Res> {
  factory $ExpiredUserInputInteractionCopyWith(ExpiredUserInputInteraction value, $Res Function(ExpiredUserInputInteraction) _then) = _$ExpiredUserInputInteractionCopyWithImpl;
@override @useResult
$Res call({
 String operationId, int expiredAt
});




}
/// @nodoc
class _$ExpiredUserInputInteractionCopyWithImpl<$Res>
    implements $ExpiredUserInputInteractionCopyWith<$Res> {
  _$ExpiredUserInputInteractionCopyWithImpl(this._self, this._then);

  final ExpiredUserInputInteraction _self;
  final $Res Function(ExpiredUserInputInteraction) _then;

/// Create a copy of UserInputInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expiredAt = null,}) {
  return _then(ExpiredUserInputInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,expiredAt: null == expiredAt ? _self.expiredAt : expiredAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ResolvedUserInputInteraction {


/// Create a copy of ResolvedUserInputInteraction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolvedUserInputInteractionCopyWith<ResolvedUserInputInteraction> get copyWith => _$ResolvedUserInputInteractionCopyWithImpl<ResolvedUserInputInteraction>(this as ResolvedUserInputInteraction, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ResolvedUserInputInteraction;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolvedUserInputInteraction&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.resolvedAt, _this.resolvedAt) || other.resolvedAt == _this.resolvedAt)&&const DeepCollectionEquality().equals(other.answers, _this.answers));
}


@override
int get hashCode {
  final _this = this as ResolvedUserInputInteraction;
  return Object.hash(runtimeType,_this.operationId,_this.resolvedAt,const DeepCollectionEquality().hash(_this.answers));
}



}

/// @nodoc
abstract mixin class $ResolvedUserInputInteractionCopyWith<$Res> implements $UserInputInteractionStateCopyWith<$Res> {
  factory $ResolvedUserInputInteractionCopyWith(ResolvedUserInputInteraction value, $Res Function(ResolvedUserInputInteraction) _then) = _$ResolvedUserInputInteractionCopyWithImpl;
@useResult
$Res call({
 String operationId, int resolvedAt, List<UserInputAnswerCommand> answers
});




}
/// @nodoc
class _$ResolvedUserInputInteractionCopyWithImpl<$Res>
    implements $ResolvedUserInputInteractionCopyWith<$Res> {
  _$ResolvedUserInputInteractionCopyWithImpl(this._self, this._then);

  final ResolvedUserInputInteraction _self;
  final $Res Function(ResolvedUserInputInteraction) _then;

/// Create a copy of ResolvedUserInputInteraction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? resolvedAt = null,Object? answers = null,}) {
  return _then(ResolvedUserInputInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,resolvedAt: null == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as int,answers: null == answers ? _self.answers : answers // ignore: cast_nullable_to_non_nullable
as List<UserInputAnswerCommand>,
  ));
}

}


/// Adds pattern-matching-related methods to [ResolvedUserInputInteraction].
extension ResolvedUserInputInteractionPatterns on ResolvedUserInputInteraction {
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
mixin _$ToolApprovalInteractionState {

 String get operationId;
/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToolApprovalInteractionStateCopyWith<ToolApprovalInteractionState> get copyWith => _$ToolApprovalInteractionStateCopyWithImpl<ToolApprovalInteractionState>(this as ToolApprovalInteractionState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ToolApprovalInteractionState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ToolApprovalInteractionState&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as ToolApprovalInteractionState;
  return Object.hash(runtimeType,_this.operationId);
}



}

/// @nodoc
abstract mixin class $ToolApprovalInteractionStateCopyWith<$Res>  {
  factory $ToolApprovalInteractionStateCopyWith(ToolApprovalInteractionState value, $Res Function(ToolApprovalInteractionState) _then) = _$ToolApprovalInteractionStateCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$ToolApprovalInteractionStateCopyWithImpl<$Res>
    implements $ToolApprovalInteractionStateCopyWith<$Res> {
  _$ToolApprovalInteractionStateCopyWithImpl(this._self, this._then);

  final ToolApprovalInteractionState _self;
  final $Res Function(ToolApprovalInteractionState) _then;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,}) {
  return _then(_self.copyWith(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ToolApprovalInteractionState].
extension ToolApprovalInteractionStatePatterns on ToolApprovalInteractionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PendingToolApprovalInteraction value)?  pending,TResult Function( ResolvedToolApprovalInteraction value)?  resolved,TResult Function( CancelledToolApprovalInteraction value)?  cancelled,TResult Function( ExpiredToolApprovalInteraction value)?  expired,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PendingToolApprovalInteraction() when pending != null:
return pending(_that);case ResolvedToolApprovalInteraction() when resolved != null:
return resolved(_that);case CancelledToolApprovalInteraction() when cancelled != null:
return cancelled(_that);case ExpiredToolApprovalInteraction() when expired != null:
return expired(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PendingToolApprovalInteraction value)  pending,required TResult Function( ResolvedToolApprovalInteraction value)  resolved,required TResult Function( CancelledToolApprovalInteraction value)  cancelled,required TResult Function( ExpiredToolApprovalInteraction value)  expired,}){
final _that = this;
switch (_that) {
case PendingToolApprovalInteraction():
return pending(_that);case ResolvedToolApprovalInteraction():
return resolved(_that);case CancelledToolApprovalInteraction():
return cancelled(_that);case ExpiredToolApprovalInteraction():
return expired(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PendingToolApprovalInteraction value)?  pending,TResult? Function( ResolvedToolApprovalInteraction value)?  resolved,TResult? Function( CancelledToolApprovalInteraction value)?  cancelled,TResult? Function( ExpiredToolApprovalInteraction value)?  expired,}){
final _that = this;
switch (_that) {
case PendingToolApprovalInteraction() when pending != null:
return pending(_that);case ResolvedToolApprovalInteraction() when resolved != null:
return resolved(_that);case CancelledToolApprovalInteraction() when cancelled != null:
return cancelled(_that);case ExpiredToolApprovalInteraction() when expired != null:
return expired(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String operationId)?  pending,TResult Function( String operationId,  int resolvedAt,  ToolApprovalDecision decision,  String? reason)?  resolved,TResult Function( String operationId,  int cancelledAt,  String reason)?  cancelled,TResult Function( String operationId,  int expiredAt)?  expired,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PendingToolApprovalInteraction() when pending != null:
return pending(_that.operationId);case ResolvedToolApprovalInteraction() when resolved != null:
return resolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case CancelledToolApprovalInteraction() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredToolApprovalInteraction() when expired != null:
return expired(_that.operationId,_that.expiredAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String operationId)  pending,required TResult Function( String operationId,  int resolvedAt,  ToolApprovalDecision decision,  String? reason)  resolved,required TResult Function( String operationId,  int cancelledAt,  String reason)  cancelled,required TResult Function( String operationId,  int expiredAt)  expired,}) {final _that = this;
switch (_that) {
case PendingToolApprovalInteraction():
return pending(_that.operationId);case ResolvedToolApprovalInteraction():
return resolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case CancelledToolApprovalInteraction():
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredToolApprovalInteraction():
return expired(_that.operationId,_that.expiredAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String operationId)?  pending,TResult? Function( String operationId,  int resolvedAt,  ToolApprovalDecision decision,  String? reason)?  resolved,TResult? Function( String operationId,  int cancelledAt,  String reason)?  cancelled,TResult? Function( String operationId,  int expiredAt)?  expired,}) {final _that = this;
switch (_that) {
case PendingToolApprovalInteraction() when pending != null:
return pending(_that.operationId);case ResolvedToolApprovalInteraction() when resolved != null:
return resolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case CancelledToolApprovalInteraction() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredToolApprovalInteraction() when expired != null:
return expired(_that.operationId,_that.expiredAt);case _:
  return null;

}
}

}

/// @nodoc


class PendingToolApprovalInteraction extends ToolApprovalInteractionState {
  const PendingToolApprovalInteraction({required this.operationId}): super._();


@override final  String operationId;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PendingToolApprovalInteractionCopyWith<PendingToolApprovalInteraction> get copyWith => _$PendingToolApprovalInteractionCopyWithImpl<PendingToolApprovalInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingToolApprovalInteraction&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $PendingToolApprovalInteractionCopyWith<$Res> implements $ToolApprovalInteractionStateCopyWith<$Res> {
  factory $PendingToolApprovalInteractionCopyWith(PendingToolApprovalInteraction value, $Res Function(PendingToolApprovalInteraction) _then) = _$PendingToolApprovalInteractionCopyWithImpl;
@override @useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$PendingToolApprovalInteractionCopyWithImpl<$Res>
    implements $PendingToolApprovalInteractionCopyWith<$Res> {
  _$PendingToolApprovalInteractionCopyWithImpl(this._self, this._then);

  final PendingToolApprovalInteraction _self;
  final $Res Function(PendingToolApprovalInteraction) _then;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(PendingToolApprovalInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ResolvedToolApprovalInteraction extends ToolApprovalInteractionState {
  const ResolvedToolApprovalInteraction({required this.operationId, required this.resolvedAt, required this.decision, required this.reason}): super._();


@override final  String operationId;
 final  int resolvedAt;
 final  ToolApprovalDecision decision;
 final  String? reason;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolvedToolApprovalInteractionCopyWith<ResolvedToolApprovalInteraction> get copyWith => _$ResolvedToolApprovalInteractionCopyWithImpl<ResolvedToolApprovalInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolvedToolApprovalInteraction&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.decision, decision) || other.decision == decision)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,resolvedAt,decision,reason);
}



}

/// @nodoc
abstract mixin class $ResolvedToolApprovalInteractionCopyWith<$Res> implements $ToolApprovalInteractionStateCopyWith<$Res> {
  factory $ResolvedToolApprovalInteractionCopyWith(ResolvedToolApprovalInteraction value, $Res Function(ResolvedToolApprovalInteraction) _then) = _$ResolvedToolApprovalInteractionCopyWithImpl;
@override @useResult
$Res call({
 String operationId, int resolvedAt, ToolApprovalDecision decision, String? reason
});




}
/// @nodoc
class _$ResolvedToolApprovalInteractionCopyWithImpl<$Res>
    implements $ResolvedToolApprovalInteractionCopyWith<$Res> {
  _$ResolvedToolApprovalInteractionCopyWithImpl(this._self, this._then);

  final ResolvedToolApprovalInteraction _self;
  final $Res Function(ResolvedToolApprovalInteraction) _then;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? resolvedAt = null,Object? decision = null,Object? reason = freezed,}) {
  return _then(ResolvedToolApprovalInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,resolvedAt: null == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as int,decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as ToolApprovalDecision,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class CancelledToolApprovalInteraction extends ToolApprovalInteractionState {
  const CancelledToolApprovalInteraction({required this.operationId, required this.cancelledAt, required this.reason}): super._();


@override final  String operationId;
 final  int cancelledAt;
 final  String reason;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledToolApprovalInteractionCopyWith<CancelledToolApprovalInteraction> get copyWith => _$CancelledToolApprovalInteractionCopyWithImpl<CancelledToolApprovalInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledToolApprovalInteraction&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,cancelledAt,reason);
}



}

/// @nodoc
abstract mixin class $CancelledToolApprovalInteractionCopyWith<$Res> implements $ToolApprovalInteractionStateCopyWith<$Res> {
  factory $CancelledToolApprovalInteractionCopyWith(CancelledToolApprovalInteraction value, $Res Function(CancelledToolApprovalInteraction) _then) = _$CancelledToolApprovalInteractionCopyWithImpl;
@override @useResult
$Res call({
 String operationId, int cancelledAt, String reason
});




}
/// @nodoc
class _$CancelledToolApprovalInteractionCopyWithImpl<$Res>
    implements $CancelledToolApprovalInteractionCopyWith<$Res> {
  _$CancelledToolApprovalInteractionCopyWithImpl(this._self, this._then);

  final CancelledToolApprovalInteraction _self;
  final $Res Function(CancelledToolApprovalInteraction) _then;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? cancelledAt = null,Object? reason = null,}) {
  return _then(CancelledToolApprovalInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ExpiredToolApprovalInteraction extends ToolApprovalInteractionState {
  const ExpiredToolApprovalInteraction({required this.operationId, required this.expiredAt}): super._();


@override final  String operationId;
 final  int expiredAt;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExpiredToolApprovalInteractionCopyWith<ExpiredToolApprovalInteraction> get copyWith => _$ExpiredToolApprovalInteractionCopyWithImpl<ExpiredToolApprovalInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ExpiredToolApprovalInteraction&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expiredAt, expiredAt) || other.expiredAt == expiredAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expiredAt);
}



}

/// @nodoc
abstract mixin class $ExpiredToolApprovalInteractionCopyWith<$Res> implements $ToolApprovalInteractionStateCopyWith<$Res> {
  factory $ExpiredToolApprovalInteractionCopyWith(ExpiredToolApprovalInteraction value, $Res Function(ExpiredToolApprovalInteraction) _then) = _$ExpiredToolApprovalInteractionCopyWithImpl;
@override @useResult
$Res call({
 String operationId, int expiredAt
});




}
/// @nodoc
class _$ExpiredToolApprovalInteractionCopyWithImpl<$Res>
    implements $ExpiredToolApprovalInteractionCopyWith<$Res> {
  _$ExpiredToolApprovalInteractionCopyWithImpl(this._self, this._then);

  final ExpiredToolApprovalInteraction _self;
  final $Res Function(ExpiredToolApprovalInteraction) _then;

/// Create a copy of ToolApprovalInteractionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expiredAt = null,}) {
  return _then(ExpiredToolApprovalInteraction(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,expiredAt: null == expiredAt ? _self.expiredAt : expiredAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
