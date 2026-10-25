// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'workspace_diagnostics_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StoragePanelTarget {

 String get threadId; int get bindingGeneration; ThreadExecutionState get execution;
/// Create a copy of StoragePanelTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoragePanelTargetCopyWith<StoragePanelTarget> get copyWith => _$StoragePanelTargetCopyWithImpl<StoragePanelTarget>(this as StoragePanelTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StoragePanelTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StoragePanelTarget&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.bindingGeneration, _this.bindingGeneration) || other.bindingGeneration == _this.bindingGeneration)&&(identical(other.execution, _this.execution) || other.execution == _this.execution));
}


@override
int get hashCode {
  final _this = this as StoragePanelTarget;
  return Object.hash(runtimeType,_this.threadId,_this.bindingGeneration,_this.execution);
}



}

/// @nodoc
abstract mixin class $StoragePanelTargetCopyWith<$Res>  {
  factory $StoragePanelTargetCopyWith(StoragePanelTarget value, $Res Function(StoragePanelTarget) _then) = _$StoragePanelTargetCopyWithImpl;
@useResult
$Res call({
 String threadId, int bindingGeneration, ThreadExecutionState execution
});


$ThreadExecutionStateCopyWith<$Res> get execution;

}
/// @nodoc
class _$StoragePanelTargetCopyWithImpl<$Res>
    implements $StoragePanelTargetCopyWith<$Res> {
  _$StoragePanelTargetCopyWithImpl(this._self, this._then);

  final StoragePanelTarget _self;
  final $Res Function(StoragePanelTarget) _then;

/// Create a copy of StoragePanelTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? bindingGeneration = null,Object? execution = null,}) {
  return _then(StoragePanelTarget(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,bindingGeneration: null == bindingGeneration ? _self.bindingGeneration : bindingGeneration // ignore: cast_nullable_to_non_nullable
as int,execution: null == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadExecutionState,
  ));
}
/// Create a copy of StoragePanelTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionStateCopyWith<$Res> get execution {

  return $ThreadExecutionStateCopyWith<$Res>(_self.execution, (value) {
    return _then(_self.copyWith(execution: value));
  });
}
}


/// Adds pattern-matching-related methods to [StoragePanelTarget].
extension StoragePanelTargetPatterns on StoragePanelTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StoragePanelTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StoragePanelTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StoragePanelTarget value)  $default,){
final _that = this;
switch (_that) {
case _StoragePanelTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StoragePanelTarget value)?  $default,){
final _that = this;
switch (_that) {
case _StoragePanelTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  int bindingGeneration,  ThreadExecutionState execution)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StoragePanelTarget() when $default != null:
return $default(_that.threadId,_that.bindingGeneration,_that.execution);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  int bindingGeneration,  ThreadExecutionState execution)  $default,) {final _that = this;
switch (_that) {
case _StoragePanelTarget():
return $default(_that.threadId,_that.bindingGeneration,_that.execution);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  int bindingGeneration,  ThreadExecutionState execution)?  $default,) {final _that = this;
switch (_that) {
case _StoragePanelTarget() when $default != null:
return $default(_that.threadId,_that.bindingGeneration,_that.execution);case _:
  return null;

}
}

}

/// @nodoc


class _StoragePanelTarget implements StoragePanelTarget {
  const _StoragePanelTarget({required this.threadId, required this.bindingGeneration, required this.execution});


@override final  String threadId;
@override final  int bindingGeneration;
@override final  ThreadExecutionState execution;

/// Create a copy of StoragePanelTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StoragePanelTargetCopyWith<_StoragePanelTarget> get copyWith => __$StoragePanelTargetCopyWithImpl<_StoragePanelTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StoragePanelTarget&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.bindingGeneration, bindingGeneration) || other.bindingGeneration == bindingGeneration)&&(identical(other.execution, execution) || other.execution == execution));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,bindingGeneration,execution);
}



}

/// @nodoc
abstract mixin class _$StoragePanelTargetCopyWith<$Res> implements $StoragePanelTargetCopyWith<$Res> {
  factory _$StoragePanelTargetCopyWith(_StoragePanelTarget value, $Res Function(_StoragePanelTarget) _then) = __$StoragePanelTargetCopyWithImpl;
@override @useResult
$Res call({
 String threadId, int bindingGeneration, ThreadExecutionState execution
});


@override $ThreadExecutionStateCopyWith<$Res> get execution;

}
/// @nodoc
class __$StoragePanelTargetCopyWithImpl<$Res>
    implements _$StoragePanelTargetCopyWith<$Res> {
  __$StoragePanelTargetCopyWithImpl(this._self, this._then);

  final _StoragePanelTarget _self;
  final $Res Function(_StoragePanelTarget) _then;

/// Create a copy of StoragePanelTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? bindingGeneration = null,Object? execution = null,}) {
  return _then(_StoragePanelTarget(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,bindingGeneration: null == bindingGeneration ? _self.bindingGeneration : bindingGeneration // ignore: cast_nullable_to_non_nullable
as int,execution: null == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadExecutionState,
  ));
}

/// Create a copy of StoragePanelTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionStateCopyWith<$Res> get execution {

  return $ThreadExecutionStateCopyWith<$Res>(_self.execution, (value) {
    return _then(_self.copyWith(execution: value));
  });
}
}

/// @nodoc
mixin _$WorkspaceDiagnosticsState {

 RecoveryState get recovery; PersistenceState get persistence; PersistenceQueueState get queue; Map<String, WorkspaceActionPresentation> get actions; Map<String, StudioFailure> get readErrors; StoragePanelTarget? get storageTarget; bool get queueExpanded; Set<String> get dismissedRecoveryIssues;
/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkspaceDiagnosticsStateCopyWith<WorkspaceDiagnosticsState> get copyWith => _$WorkspaceDiagnosticsStateCopyWithImpl<WorkspaceDiagnosticsState>(this as WorkspaceDiagnosticsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkspaceDiagnosticsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkspaceDiagnosticsState&&(identical(other.recovery, _this.recovery) || other.recovery == _this.recovery)&&(identical(other.persistence, _this.persistence) || other.persistence == _this.persistence)&&(identical(other.queue, _this.queue) || other.queue == _this.queue)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&const DeepCollectionEquality().equals(other.readErrors, _this.readErrors)&&(identical(other.storageTarget, _this.storageTarget) || other.storageTarget == _this.storageTarget)&&(identical(other.queueExpanded, _this.queueExpanded) || other.queueExpanded == _this.queueExpanded)&&const DeepCollectionEquality().equals(other.dismissedRecoveryIssues, _this.dismissedRecoveryIssues));
}


@override
int get hashCode {
  final _this = this as WorkspaceDiagnosticsState;
  return Object.hash(runtimeType,_this.recovery,_this.persistence,_this.queue,const DeepCollectionEquality().hash(_this.actions),const DeepCollectionEquality().hash(_this.readErrors),_this.storageTarget,_this.queueExpanded,const DeepCollectionEquality().hash(_this.dismissedRecoveryIssues));
}



}

/// @nodoc
abstract mixin class $WorkspaceDiagnosticsStateCopyWith<$Res>  {
  factory $WorkspaceDiagnosticsStateCopyWith(WorkspaceDiagnosticsState value, $Res Function(WorkspaceDiagnosticsState) _then) = _$WorkspaceDiagnosticsStateCopyWithImpl;
@useResult
$Res call({
 RecoveryState recovery, PersistenceState persistence, PersistenceQueueState queue, Map<String, WorkspaceActionPresentation> actions, Map<String, StudioFailure> readErrors, StoragePanelTarget? storageTarget, bool queueExpanded, Set<String> dismissedRecoveryIssues
});


$RecoveryStateCopyWith<$Res> get recovery;$PersistenceStateCopyWith<$Res> get persistence;$PersistenceQueueStateCopyWith<$Res> get queue;$StoragePanelTargetCopyWith<$Res>? get storageTarget;

}
/// @nodoc
class _$WorkspaceDiagnosticsStateCopyWithImpl<$Res>
    implements $WorkspaceDiagnosticsStateCopyWith<$Res> {
  _$WorkspaceDiagnosticsStateCopyWithImpl(this._self, this._then);

  final WorkspaceDiagnosticsState _self;
  final $Res Function(WorkspaceDiagnosticsState) _then;

/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recovery = null,Object? persistence = null,Object? queue = null,Object? actions = null,Object? readErrors = null,Object? storageTarget = freezed,Object? queueExpanded = null,Object? dismissedRecoveryIssues = null,}) {
  return _then(WorkspaceDiagnosticsState(
recovery: null == recovery ? _self.recovery : recovery // ignore: cast_nullable_to_non_nullable
as RecoveryState,persistence: null == persistence ? _self.persistence : persistence // ignore: cast_nullable_to_non_nullable
as PersistenceState,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as PersistenceQueueState,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<String, WorkspaceActionPresentation>,readErrors: null == readErrors ? _self.readErrors : readErrors // ignore: cast_nullable_to_non_nullable
as Map<String, StudioFailure>,storageTarget: freezed == storageTarget ? _self.storageTarget : storageTarget // ignore: cast_nullable_to_non_nullable
as StoragePanelTarget?,queueExpanded: null == queueExpanded ? _self.queueExpanded : queueExpanded // ignore: cast_nullable_to_non_nullable
as bool,dismissedRecoveryIssues: null == dismissedRecoveryIssues ? _self.dismissedRecoveryIssues : dismissedRecoveryIssues // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}
/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryStateCopyWith<$Res> get recovery {

  return $RecoveryStateCopyWith<$Res>(_self.recovery, (value) {
    return _then(_self.copyWith(recovery: value));
  });
}/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceStateCopyWith<$Res> get persistence {

  return $PersistenceStateCopyWith<$Res>(_self.persistence, (value) {
    return _then(_self.copyWith(persistence: value));
  });
}/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueStateCopyWith<$Res> get queue {

  return $PersistenceQueueStateCopyWith<$Res>(_self.queue, (value) {
    return _then(_self.copyWith(queue: value));
  });
}/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StoragePanelTargetCopyWith<$Res>? get storageTarget {
    if (_self.storageTarget == null) {
    return null;
  }

  return $StoragePanelTargetCopyWith<$Res>(_self.storageTarget!, (value) {
    return _then(_self.copyWith(storageTarget: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkspaceDiagnosticsState].
extension WorkspaceDiagnosticsStatePatterns on WorkspaceDiagnosticsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkspaceDiagnosticsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkspaceDiagnosticsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkspaceDiagnosticsState value)  $default,){
final _that = this;
switch (_that) {
case _WorkspaceDiagnosticsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkspaceDiagnosticsState value)?  $default,){
final _that = this;
switch (_that) {
case _WorkspaceDiagnosticsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RecoveryState recovery,  PersistenceState persistence,  PersistenceQueueState queue,  Map<String, WorkspaceActionPresentation> actions,  Map<String, StudioFailure> readErrors,  StoragePanelTarget? storageTarget,  bool queueExpanded,  Set<String> dismissedRecoveryIssues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkspaceDiagnosticsState() when $default != null:
return $default(_that.recovery,_that.persistence,_that.queue,_that.actions,_that.readErrors,_that.storageTarget,_that.queueExpanded,_that.dismissedRecoveryIssues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RecoveryState recovery,  PersistenceState persistence,  PersistenceQueueState queue,  Map<String, WorkspaceActionPresentation> actions,  Map<String, StudioFailure> readErrors,  StoragePanelTarget? storageTarget,  bool queueExpanded,  Set<String> dismissedRecoveryIssues)  $default,) {final _that = this;
switch (_that) {
case _WorkspaceDiagnosticsState():
return $default(_that.recovery,_that.persistence,_that.queue,_that.actions,_that.readErrors,_that.storageTarget,_that.queueExpanded,_that.dismissedRecoveryIssues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RecoveryState recovery,  PersistenceState persistence,  PersistenceQueueState queue,  Map<String, WorkspaceActionPresentation> actions,  Map<String, StudioFailure> readErrors,  StoragePanelTarget? storageTarget,  bool queueExpanded,  Set<String> dismissedRecoveryIssues)?  $default,) {final _that = this;
switch (_that) {
case _WorkspaceDiagnosticsState() when $default != null:
return $default(_that.recovery,_that.persistence,_that.queue,_that.actions,_that.readErrors,_that.storageTarget,_that.queueExpanded,_that.dismissedRecoveryIssues);case _:
  return null;

}
}

}

/// @nodoc


class _WorkspaceDiagnosticsState implements WorkspaceDiagnosticsState {
  const _WorkspaceDiagnosticsState({required this.recovery, required this.persistence, required this.queue, required  Map<String, WorkspaceActionPresentation> actions, required  Map<String, StudioFailure> readErrors, required this.storageTarget, required this.queueExpanded, required  Set<String> dismissedRecoveryIssues}): _actions = actions,_readErrors = readErrors,_dismissedRecoveryIssues = dismissedRecoveryIssues;


@override final  RecoveryState recovery;
@override final  PersistenceState persistence;
@override final  PersistenceQueueState queue;
 final  Map<String, WorkspaceActionPresentation> _actions;
@override Map<String, WorkspaceActionPresentation> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}

 final  Map<String, StudioFailure> _readErrors;
@override Map<String, StudioFailure> get readErrors {
  if (_readErrors is EqualUnmodifiableMapView) return _readErrors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readErrors);
}

@override final  StoragePanelTarget? storageTarget;
@override final  bool queueExpanded;
 final  Set<String> _dismissedRecoveryIssues;
@override Set<String> get dismissedRecoveryIssues {
  if (_dismissedRecoveryIssues is EqualUnmodifiableSetView) return _dismissedRecoveryIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_dismissedRecoveryIssues);
}


/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkspaceDiagnosticsStateCopyWith<_WorkspaceDiagnosticsState> get copyWith => __$WorkspaceDiagnosticsStateCopyWithImpl<_WorkspaceDiagnosticsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkspaceDiagnosticsState&&(identical(other.recovery, recovery) || other.recovery == recovery)&&(identical(other.persistence, persistence) || other.persistence == persistence)&&(identical(other.queue, queue) || other.queue == queue)&&const DeepCollectionEquality().equals(other.actions, _actions)&&const DeepCollectionEquality().equals(other.readErrors, _readErrors)&&(identical(other.storageTarget, storageTarget) || other.storageTarget == storageTarget)&&(identical(other.queueExpanded, queueExpanded) || other.queueExpanded == queueExpanded)&&const DeepCollectionEquality().equals(other.dismissedRecoveryIssues, _dismissedRecoveryIssues));
}


@override
int get hashCode {
    return Object.hash(runtimeType,recovery,persistence,queue,const DeepCollectionEquality().hash(_actions),const DeepCollectionEquality().hash(_readErrors),storageTarget,queueExpanded,const DeepCollectionEquality().hash(_dismissedRecoveryIssues));
}



}

/// @nodoc
abstract mixin class _$WorkspaceDiagnosticsStateCopyWith<$Res> implements $WorkspaceDiagnosticsStateCopyWith<$Res> {
  factory _$WorkspaceDiagnosticsStateCopyWith(_WorkspaceDiagnosticsState value, $Res Function(_WorkspaceDiagnosticsState) _then) = __$WorkspaceDiagnosticsStateCopyWithImpl;
@override @useResult
$Res call({
 RecoveryState recovery, PersistenceState persistence, PersistenceQueueState queue, Map<String, WorkspaceActionPresentation> actions, Map<String, StudioFailure> readErrors, StoragePanelTarget? storageTarget, bool queueExpanded, Set<String> dismissedRecoveryIssues
});


@override $RecoveryStateCopyWith<$Res> get recovery;@override $PersistenceStateCopyWith<$Res> get persistence;@override $PersistenceQueueStateCopyWith<$Res> get queue;@override $StoragePanelTargetCopyWith<$Res>? get storageTarget;

}
/// @nodoc
class __$WorkspaceDiagnosticsStateCopyWithImpl<$Res>
    implements _$WorkspaceDiagnosticsStateCopyWith<$Res> {
  __$WorkspaceDiagnosticsStateCopyWithImpl(this._self, this._then);

  final _WorkspaceDiagnosticsState _self;
  final $Res Function(_WorkspaceDiagnosticsState) _then;

/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recovery = null,Object? persistence = null,Object? queue = null,Object? actions = null,Object? readErrors = null,Object? storageTarget = freezed,Object? queueExpanded = null,Object? dismissedRecoveryIssues = null,}) {
  return _then(_WorkspaceDiagnosticsState(
recovery: null == recovery ? _self.recovery : recovery // ignore: cast_nullable_to_non_nullable
as RecoveryState,persistence: null == persistence ? _self.persistence : persistence // ignore: cast_nullable_to_non_nullable
as PersistenceState,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as PersistenceQueueState,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<String, WorkspaceActionPresentation>,readErrors: null == readErrors ? _self._readErrors : readErrors // ignore: cast_nullable_to_non_nullable
as Map<String, StudioFailure>,storageTarget: freezed == storageTarget ? _self.storageTarget : storageTarget // ignore: cast_nullable_to_non_nullable
as StoragePanelTarget?,queueExpanded: null == queueExpanded ? _self.queueExpanded : queueExpanded // ignore: cast_nullable_to_non_nullable
as bool,dismissedRecoveryIssues: null == dismissedRecoveryIssues ? _self._dismissedRecoveryIssues : dismissedRecoveryIssues // ignore: cast_nullable_to_non_nullable
as Set<String>,
  ));
}

/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryStateCopyWith<$Res> get recovery {

  return $RecoveryStateCopyWith<$Res>(_self.recovery, (value) {
    return _then(_self.copyWith(recovery: value));
  });
}/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceStateCopyWith<$Res> get persistence {

  return $PersistenceStateCopyWith<$Res>(_self.persistence, (value) {
    return _then(_self.copyWith(persistence: value));
  });
}/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueStateCopyWith<$Res> get queue {

  return $PersistenceQueueStateCopyWith<$Res>(_self.queue, (value) {
    return _then(_self.copyWith(queue: value));
  });
}/// Create a copy of WorkspaceDiagnosticsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StoragePanelTargetCopyWith<$Res>? get storageTarget {
    if (_self.storageTarget == null) {
    return null;
  }

  return $StoragePanelTargetCopyWith<$Res>(_self.storageTarget!, (value) {
    return _then(_self.copyWith(storageTarget: value));
  });
}
}

// dart format on
