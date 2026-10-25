// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workspace_header_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WorkspaceHeaderState {

 ThreadMetadataState get root; AgentDirectoryState get agents; SessionCostsState get costs; Set<String> get reading; Map<String, StudioFailure> get readErrors;
/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceHeaderStateCopyWith<WorkspaceHeaderState> get copyWith => _$WorkspaceHeaderStateCopyWithImpl<WorkspaceHeaderState>(this as WorkspaceHeaderState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceHeaderState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceHeaderState&&(identical(other.root, _this.root) || other.root == _this.root)&&(identical(other.agents, _this.agents) || other.agents == _this.agents)&&(identical(other.costs, _this.costs) || other.costs == _this.costs)&&const DeepCollectionEquality().equals(other.reading, _this.reading)&&const DeepCollectionEquality().equals(other.readErrors, _this.readErrors));
}


@override
int get hashCode {
  final _this = this as WorkspaceHeaderState;
  return Object.hash(runtimeType,_this.root,_this.agents,_this.costs,const DeepCollectionEquality().hash(_this.reading),const DeepCollectionEquality().hash(_this.readErrors));
}



}

/// @nodoc
abstract mixin class $WorkspaceHeaderStateCopyWith<$Res>  {
  factory $WorkspaceHeaderStateCopyWith(WorkspaceHeaderState value, $Res Function(WorkspaceHeaderState) _then) = _$WorkspaceHeaderStateCopyWithImpl;
@useResult
$Res call({
 ThreadMetadataState root, AgentDirectoryState agents, SessionCostsState costs, Set<String> reading, Map<String, StudioFailure> readErrors
});


$ThreadMetadataStateCopyWith<$Res> get root;$AgentDirectoryStateCopyWith<$Res> get agents;$SessionCostsStateCopyWith<$Res> get costs;

}
/// @nodoc
class _$WorkspaceHeaderStateCopyWithImpl<$Res>
    implements $WorkspaceHeaderStateCopyWith<$Res> {
  _$WorkspaceHeaderStateCopyWithImpl(this._self, this._then);

  final WorkspaceHeaderState _self;
  final $Res Function(WorkspaceHeaderState) _then;

/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? root = null,Object? agents = null,Object? costs = null,Object? reading = null,Object? readErrors = null,}) {
  return _then(WorkspaceHeaderState(
root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as ThreadMetadataState,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as AgentDirectoryState,costs: null == costs ? _self.costs : costs // ignore: cast_nullable_to_non_nullable
as SessionCostsState,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<String>,readErrors: null == readErrors ? _self.readErrors : readErrors // ignore: cast_nullable_to_non_nullable
as Map<String, StudioFailure>,
  ));
}
/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetadataStateCopyWith<$Res> get root {

  return $ThreadMetadataStateCopyWith<$Res>(_self.root, (value) {
    return _then(_self.copyWith(root: value));
  });
}/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryStateCopyWith<$Res> get agents {

  return $AgentDirectoryStateCopyWith<$Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsStateCopyWith<$Res> get costs {

  return $SessionCostsStateCopyWith<$Res>(_self.costs, (value) {
    return _then(_self.copyWith(costs: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceHeaderState].
extension WorkspaceHeaderStatePatterns on WorkspaceHeaderState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceHeaderState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceHeaderState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceHeaderState value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceHeaderState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceHeaderState value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceHeaderState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadMetadataState root,  AgentDirectoryState agents,  SessionCostsState costs,  Set<String> reading,  Map<String, StudioFailure> readErrors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceHeaderState() when $default != null:
return $default(_that.root,_that.agents,_that.costs,_that.reading,_that.readErrors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadMetadataState root,  AgentDirectoryState agents,  SessionCostsState costs,  Set<String> reading,  Map<String, StudioFailure> readErrors)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceHeaderState():
return $default(_that.root,_that.agents,_that.costs,_that.reading,_that.readErrors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadMetadataState root,  AgentDirectoryState agents,  SessionCostsState costs,  Set<String> reading,  Map<String, StudioFailure> readErrors)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceHeaderState() when $default != null:
return $default(_that.root,_that.agents,_that.costs,_that.reading,_that.readErrors);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceHeaderState implements WorkspaceHeaderState {
  const _WorkspaceHeaderState({required this.root, required this.agents, required this.costs, required  Set<String> reading, required  Map<String, StudioFailure> readErrors}): _reading = reading,_readErrors = readErrors;


@override final  ThreadMetadataState root;
@override final  AgentDirectoryState agents;
@override final  SessionCostsState costs;
 final  Set<String> _reading;
@override Set<String> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}

 final  Map<String, StudioFailure> _readErrors;
@override Map<String, StudioFailure> get readErrors {
  if (_readErrors is EqualUnmodifiableMapView) return _readErrors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readErrors);
}


/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceHeaderStateCopyWith<_WorkspaceHeaderState> get copyWith => __$WorkspaceHeaderStateCopyWithImpl<_WorkspaceHeaderState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceHeaderState&&(identical(other.root, root) || other.root == root)&&(identical(other.agents, agents) || other.agents == agents)&&(identical(other.costs, costs) || other.costs == costs)&&const DeepCollectionEquality().equals(other.reading, _reading)&&const DeepCollectionEquality().equals(other.readErrors, _readErrors));
}


@override
int get hashCode {
    return Object.hash(runtimeType,root,agents,costs,const DeepCollectionEquality().hash(_reading),const DeepCollectionEquality().hash(_readErrors));
}



}

/// @nodoc
abstract mixin class _$WorkspaceHeaderStateCopyWith<$Res> implements $WorkspaceHeaderStateCopyWith<$Res> {
  factory _$WorkspaceHeaderStateCopyWith(_WorkspaceHeaderState value, $Res Function(_WorkspaceHeaderState) _then) = __$WorkspaceHeaderStateCopyWithImpl;
@override @useResult
$Res call({
 ThreadMetadataState root, AgentDirectoryState agents, SessionCostsState costs, Set<String> reading, Map<String, StudioFailure> readErrors
});


@override $ThreadMetadataStateCopyWith<$Res> get root;@override $AgentDirectoryStateCopyWith<$Res> get agents;@override $SessionCostsStateCopyWith<$Res> get costs;

}
/// @nodoc
class __$WorkspaceHeaderStateCopyWithImpl<$Res>
    implements _$WorkspaceHeaderStateCopyWith<$Res> {
  __$WorkspaceHeaderStateCopyWithImpl(this._self, this._then);

  final _WorkspaceHeaderState _self;
  final $Res Function(_WorkspaceHeaderState) _then;

/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? root = null,Object? agents = null,Object? costs = null,Object? reading = null,Object? readErrors = null,}) {
  return _then(_WorkspaceHeaderState(
root: null == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as ThreadMetadataState,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as AgentDirectoryState,costs: null == costs ? _self.costs : costs // ignore: cast_nullable_to_non_nullable
as SessionCostsState,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<String>,readErrors: null == readErrors ? _self._readErrors : readErrors // ignore: cast_nullable_to_non_nullable
as Map<String, StudioFailure>,
  ));
}

/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetadataStateCopyWith<$Res> get root {

  return $ThreadMetadataStateCopyWith<$Res>(_self.root, (value) {
    return _then(_self.copyWith(root: value));
  });
}/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryStateCopyWith<$Res> get agents {

  return $AgentDirectoryStateCopyWith<$Res>(_self.agents, (value) {
    return _then(_self.copyWith(agents: value));
  });
}/// Create a copy of WorkspaceHeaderState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsStateCopyWith<$Res> get costs {

  return $SessionCostsStateCopyWith<$Res>(_self.costs, (value) {
    return _then(_self.copyWith(costs: value));
  });
}
}

// dart format on
