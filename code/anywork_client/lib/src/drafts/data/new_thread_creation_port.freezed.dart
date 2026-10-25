// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'new_thread_creation_port.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$NewThreadCreationRequest {

 String get projectId; StudioPromptInput get input; ThreadModeId get mode; ModelSelection get route; ThreadWorkspaceMode get workspaceMode; DelegationMode get delegationMode; DelegationPreference get delegationPreference;
/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NewThreadCreationRequestCopyWith<NewThreadCreationRequest> get copyWith => _$NewThreadCreationRequestCopyWithImpl<NewThreadCreationRequest>(this as NewThreadCreationRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NewThreadCreationRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NewThreadCreationRequest&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.input, _this.input) || other.input == _this.input)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.route, _this.route) || other.route == _this.route)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode)&&(identical(other.delegationMode, _this.delegationMode) || other.delegationMode == _this.delegationMode)&&(identical(other.delegationPreference, _this.delegationPreference) || other.delegationPreference == _this.delegationPreference));
}


@override
int get hashCode {
  final _this = this as NewThreadCreationRequest;
  return Object.hash(runtimeType,_this.projectId,_this.input,_this.mode,_this.route,_this.workspaceMode,_this.delegationMode,_this.delegationPreference);
}



}

/// @nodoc
abstract mixin class $NewThreadCreationRequestCopyWith<$Res>  {
  factory $NewThreadCreationRequestCopyWith(NewThreadCreationRequest value, $Res Function(NewThreadCreationRequest) _then) = _$NewThreadCreationRequestCopyWithImpl;
@useResult
$Res call({
 String projectId, StudioPromptInput input, ThreadModeId mode, ModelSelection route, ThreadWorkspaceMode workspaceMode, DelegationMode delegationMode, DelegationPreference delegationPreference
});


$StudioPromptInputCopyWith<$Res> get input;$ModelSelectionCopyWith<$Res> get route;

}
/// @nodoc
class _$NewThreadCreationRequestCopyWithImpl<$Res>
    implements $NewThreadCreationRequestCopyWith<$Res> {
  _$NewThreadCreationRequestCopyWithImpl(this._self, this._then);

  final NewThreadCreationRequest _self;
  final $Res Function(NewThreadCreationRequest) _then;

/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? input = null,Object? mode = null,Object? route = null,Object? workspaceMode = null,Object? delegationMode = null,Object? delegationPreference = null,}) {
  return _then(NewThreadCreationRequest(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as StudioPromptInput,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadModeId,route: null == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as ModelSelection,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,
  ));
}
/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioPromptInputCopyWith<$Res> get input {

  return $StudioPromptInputCopyWith<$Res>(_self.input, (value) {
    return _then(_self.copyWith(input: value));
  });
}/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res> get route {

  return $ModelSelectionCopyWith<$Res>(_self.route, (value) {
    return _then(_self.copyWith(route: value));
  });
}
}


/// Adds pattern-matching-related methods to [NewThreadCreationRequest].
extension NewThreadCreationRequestPatterns on NewThreadCreationRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NewThreadCreationRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NewThreadCreationRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NewThreadCreationRequest value)  $default,){
final _that = this;
switch (_that) {
case _NewThreadCreationRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NewThreadCreationRequest value)?  $default,){
final _that = this;
switch (_that) {
case _NewThreadCreationRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  StudioPromptInput input,  ThreadModeId mode,  ModelSelection route,  ThreadWorkspaceMode workspaceMode,  DelegationMode delegationMode,  DelegationPreference delegationPreference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NewThreadCreationRequest() when $default != null:
return $default(_that.projectId,_that.input,_that.mode,_that.route,_that.workspaceMode,_that.delegationMode,_that.delegationPreference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  StudioPromptInput input,  ThreadModeId mode,  ModelSelection route,  ThreadWorkspaceMode workspaceMode,  DelegationMode delegationMode,  DelegationPreference delegationPreference)  $default,) {final _that = this;
switch (_that) {
case _NewThreadCreationRequest():
return $default(_that.projectId,_that.input,_that.mode,_that.route,_that.workspaceMode,_that.delegationMode,_that.delegationPreference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  StudioPromptInput input,  ThreadModeId mode,  ModelSelection route,  ThreadWorkspaceMode workspaceMode,  DelegationMode delegationMode,  DelegationPreference delegationPreference)?  $default,) {final _that = this;
switch (_that) {
case _NewThreadCreationRequest() when $default != null:
return $default(_that.projectId,_that.input,_that.mode,_that.route,_that.workspaceMode,_that.delegationMode,_that.delegationPreference);case _:
  return null;

}
}

}

/// @nodoc


class _NewThreadCreationRequest implements NewThreadCreationRequest {
  const _NewThreadCreationRequest({required this.projectId, required this.input, required this.mode, required this.route, required this.workspaceMode, required this.delegationMode, required this.delegationPreference});


@override final  String projectId;
@override final  StudioPromptInput input;
@override final  ThreadModeId mode;
@override final  ModelSelection route;
@override final  ThreadWorkspaceMode workspaceMode;
@override final  DelegationMode delegationMode;
@override final  DelegationPreference delegationPreference;

/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NewThreadCreationRequestCopyWith<_NewThreadCreationRequest> get copyWith => __$NewThreadCreationRequestCopyWithImpl<_NewThreadCreationRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NewThreadCreationRequest&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.input, input) || other.input == input)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.route, route) || other.route == route)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.delegationMode, delegationMode) || other.delegationMode == delegationMode)&&(identical(other.delegationPreference, delegationPreference) || other.delegationPreference == delegationPreference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,input,mode,route,workspaceMode,delegationMode,delegationPreference);
}



}

/// @nodoc
abstract mixin class _$NewThreadCreationRequestCopyWith<$Res> implements $NewThreadCreationRequestCopyWith<$Res> {
  factory _$NewThreadCreationRequestCopyWith(_NewThreadCreationRequest value, $Res Function(_NewThreadCreationRequest) _then) = __$NewThreadCreationRequestCopyWithImpl;
@override @useResult
$Res call({
 String projectId, StudioPromptInput input, ThreadModeId mode, ModelSelection route, ThreadWorkspaceMode workspaceMode, DelegationMode delegationMode, DelegationPreference delegationPreference
});


@override $StudioPromptInputCopyWith<$Res> get input;@override $ModelSelectionCopyWith<$Res> get route;

}
/// @nodoc
class __$NewThreadCreationRequestCopyWithImpl<$Res>
    implements _$NewThreadCreationRequestCopyWith<$Res> {
  __$NewThreadCreationRequestCopyWithImpl(this._self, this._then);

  final _NewThreadCreationRequest _self;
  final $Res Function(_NewThreadCreationRequest) _then;

/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? input = null,Object? mode = null,Object? route = null,Object? workspaceMode = null,Object? delegationMode = null,Object? delegationPreference = null,}) {
  return _then(_NewThreadCreationRequest(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as StudioPromptInput,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadModeId,route: null == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as ModelSelection,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,delegationMode: null == delegationMode ? _self.delegationMode : delegationMode // ignore: cast_nullable_to_non_nullable
as DelegationMode,delegationPreference: null == delegationPreference ? _self.delegationPreference : delegationPreference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,
  ));
}

/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioPromptInputCopyWith<$Res> get input {

  return $StudioPromptInputCopyWith<$Res>(_self.input, (value) {
    return _then(_self.copyWith(input: value));
  });
}/// Create a copy of NewThreadCreationRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res> get route {

  return $ModelSelectionCopyWith<$Res>(_self.route, (value) {
    return _then(_self.copyWith(route: value));
  });
}
}

// dart format on
