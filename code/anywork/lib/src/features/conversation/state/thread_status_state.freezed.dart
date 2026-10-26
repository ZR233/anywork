// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_status_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadStatusViewState {

 String get threadId; ThreadExecutionState? get execution; ThreadConfigurationState? get configuration; WorkflowBrief? get workflow; ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> get activityRead; ReadMaterial<StorageReadHeader, Never> get storageRead; ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> get configurationRead; ReadMaterial<WorkflowReadHeader, Never> get workflowRead; ReadMaterial<TurnReadHeader, Never> get turnRead; ReadMaterial<WaitReadValue, WaitTargetReadItem>? get latestWaitTargets; Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> get waitTargetsByTool; bool get detailsVisible;
/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadStatusViewStateCopyWith<ThreadStatusViewState> get copyWith => _$ThreadStatusViewStateCopyWithImpl<ThreadStatusViewState>(this as ThreadStatusViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadStatusViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadStatusViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.execution, _this.execution) || other.execution == _this.execution)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.workflow, _this.workflow) || other.workflow == _this.workflow)&&(identical(other.activityRead, _this.activityRead) || other.activityRead == _this.activityRead)&&(identical(other.storageRead, _this.storageRead) || other.storageRead == _this.storageRead)&&(identical(other.configurationRead, _this.configurationRead) || other.configurationRead == _this.configurationRead)&&(identical(other.workflowRead, _this.workflowRead) || other.workflowRead == _this.workflowRead)&&(identical(other.turnRead, _this.turnRead) || other.turnRead == _this.turnRead)&&(identical(other.latestWaitTargets, _this.latestWaitTargets) || other.latestWaitTargets == _this.latestWaitTargets)&&const DeepCollectionEquality().equals(other.waitTargetsByTool, _this.waitTargetsByTool)&&(identical(other.detailsVisible, _this.detailsVisible) || other.detailsVisible == _this.detailsVisible));
}


@override
int get hashCode {
  final _this = this as ThreadStatusViewState;
  return Object.hash(runtimeType,_this.threadId,_this.execution,_this.configuration,_this.workflow,_this.activityRead,_this.storageRead,_this.configurationRead,_this.workflowRead,_this.turnRead,_this.latestWaitTargets,const DeepCollectionEquality().hash(_this.waitTargetsByTool),_this.detailsVisible);
}



}

/// @nodoc
abstract mixin class $ThreadStatusViewStateCopyWith<$Res>  {
  factory $ThreadStatusViewStateCopyWith(ThreadStatusViewState value, $Res Function(ThreadStatusViewState) _then) = _$ThreadStatusViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadExecutionState? execution, ThreadConfigurationState? configuration, WorkflowBrief? workflow, ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> activityRead, ReadMaterial<StorageReadHeader, Never> storageRead, ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> configurationRead, ReadMaterial<WorkflowReadHeader, Never> workflowRead, ReadMaterial<TurnReadHeader, Never> turnRead, ReadMaterial<WaitReadValue, WaitTargetReadItem>? latestWaitTargets, Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> waitTargetsByTool, bool detailsVisible
});


$ThreadExecutionStateCopyWith<$Res>? get execution;$ThreadConfigurationStateCopyWith<$Res>? get configuration;$WorkflowBriefCopyWith<$Res>? get workflow;$ReadMaterialCopyWith<ActivityReadHeader, IndexedActivityToolReadItem, $Res> get activityRead;$ReadMaterialCopyWith<StorageReadHeader, Never, $Res> get storageRead;$ReadMaterialCopyWith<ThreadConfigurationReadHeader, SkillNameReadItem, $Res> get configurationRead;$ReadMaterialCopyWith<WorkflowReadHeader, Never, $Res> get workflowRead;$ReadMaterialCopyWith<TurnReadHeader, Never, $Res> get turnRead;$ReadMaterialCopyWith<WaitReadValue, WaitTargetReadItem, $Res>? get latestWaitTargets;

}
/// @nodoc
class _$ThreadStatusViewStateCopyWithImpl<$Res>
    implements $ThreadStatusViewStateCopyWith<$Res> {
  _$ThreadStatusViewStateCopyWithImpl(this._self, this._then);

  final ThreadStatusViewState _self;
  final $Res Function(ThreadStatusViewState) _then;

/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? execution = freezed,Object? configuration = freezed,Object? workflow = freezed,Object? activityRead = null,Object? storageRead = null,Object? configurationRead = null,Object? workflowRead = null,Object? turnRead = null,Object? latestWaitTargets = freezed,Object? waitTargetsByTool = null,Object? detailsVisible = null,}) {
  return _then(ThreadStatusViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadExecutionState?,configuration: freezed == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationState?,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowBrief?,activityRead: null == activityRead ? _self.activityRead : activityRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem>,storageRead: null == storageRead ? _self.storageRead : storageRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<StorageReadHeader, Never>,configurationRead: null == configurationRead ? _self.configurationRead : configurationRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem>,workflowRead: null == workflowRead ? _self.workflowRead : workflowRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<WorkflowReadHeader, Never>,turnRead: null == turnRead ? _self.turnRead : turnRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<TurnReadHeader, Never>,latestWaitTargets: freezed == latestWaitTargets ? _self.latestWaitTargets : latestWaitTargets // ignore: cast_nullable_to_non_nullable
as ReadMaterial<WaitReadValue, WaitTargetReadItem>?,waitTargetsByTool: null == waitTargetsByTool ? _self.waitTargetsByTool : waitTargetsByTool // ignore: cast_nullable_to_non_nullable
as Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>>,detailsVisible: null == detailsVisible ? _self.detailsVisible : detailsVisible // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionStateCopyWith<$Res>? get execution {
    if (_self.execution == null) {
    return null;
  }

  return $ThreadExecutionStateCopyWith<$Res>(_self.execution!, (value) {
    return _then(_self.copyWith(execution: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationStateCopyWith<$Res>? get configuration {
    if (_self.configuration == null) {
    return null;
  }

  return $ThreadConfigurationStateCopyWith<$Res>(_self.configuration!, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowBriefCopyWith<$Res>? get workflow {
    if (_self.workflow == null) {
    return null;
  }

  return $WorkflowBriefCopyWith<$Res>(_self.workflow!, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<ActivityReadHeader, IndexedActivityToolReadItem, $Res> get activityRead {

  return $ReadMaterialCopyWith<ActivityReadHeader, IndexedActivityToolReadItem, $Res>(_self.activityRead, (value) {
    return _then(_self.copyWith(activityRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<StorageReadHeader, Never, $Res> get storageRead {

  return $ReadMaterialCopyWith<StorageReadHeader, Never, $Res>(_self.storageRead, (value) {
    return _then(_self.copyWith(storageRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<ThreadConfigurationReadHeader, SkillNameReadItem, $Res> get configurationRead {

  return $ReadMaterialCopyWith<ThreadConfigurationReadHeader, SkillNameReadItem, $Res>(_self.configurationRead, (value) {
    return _then(_self.copyWith(configurationRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<WorkflowReadHeader, Never, $Res> get workflowRead {

  return $ReadMaterialCopyWith<WorkflowReadHeader, Never, $Res>(_self.workflowRead, (value) {
    return _then(_self.copyWith(workflowRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<TurnReadHeader, Never, $Res> get turnRead {

  return $ReadMaterialCopyWith<TurnReadHeader, Never, $Res>(_self.turnRead, (value) {
    return _then(_self.copyWith(turnRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<WaitReadValue, WaitTargetReadItem, $Res>? get latestWaitTargets {
    if (_self.latestWaitTargets == null) {
    return null;
  }

  return $ReadMaterialCopyWith<WaitReadValue, WaitTargetReadItem, $Res>(_self.latestWaitTargets!, (value) {
    return _then(_self.copyWith(latestWaitTargets: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadStatusViewState].
extension ThreadStatusViewStatePatterns on ThreadStatusViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadStatusViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadStatusViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadStatusViewState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadStatusViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadStatusViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadStatusViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  ThreadExecutionState? execution,  ThreadConfigurationState? configuration,  WorkflowBrief? workflow,  ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> activityRead,  ReadMaterial<StorageReadHeader, Never> storageRead,  ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> configurationRead,  ReadMaterial<WorkflowReadHeader, Never> workflowRead,  ReadMaterial<TurnReadHeader, Never> turnRead,  ReadMaterial<WaitReadValue, WaitTargetReadItem>? latestWaitTargets,  Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> waitTargetsByTool,  bool detailsVisible)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadStatusViewState() when $default != null:
return $default(_that.threadId,_that.execution,_that.configuration,_that.workflow,_that.activityRead,_that.storageRead,_that.configurationRead,_that.workflowRead,_that.turnRead,_that.latestWaitTargets,_that.waitTargetsByTool,_that.detailsVisible);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  ThreadExecutionState? execution,  ThreadConfigurationState? configuration,  WorkflowBrief? workflow,  ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> activityRead,  ReadMaterial<StorageReadHeader, Never> storageRead,  ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> configurationRead,  ReadMaterial<WorkflowReadHeader, Never> workflowRead,  ReadMaterial<TurnReadHeader, Never> turnRead,  ReadMaterial<WaitReadValue, WaitTargetReadItem>? latestWaitTargets,  Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> waitTargetsByTool,  bool detailsVisible)  $default,) {final _that = this;
switch (_that) {
case _ThreadStatusViewState():
return $default(_that.threadId,_that.execution,_that.configuration,_that.workflow,_that.activityRead,_that.storageRead,_that.configurationRead,_that.workflowRead,_that.turnRead,_that.latestWaitTargets,_that.waitTargetsByTool,_that.detailsVisible);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  ThreadExecutionState? execution,  ThreadConfigurationState? configuration,  WorkflowBrief? workflow,  ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> activityRead,  ReadMaterial<StorageReadHeader, Never> storageRead,  ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> configurationRead,  ReadMaterial<WorkflowReadHeader, Never> workflowRead,  ReadMaterial<TurnReadHeader, Never> turnRead,  ReadMaterial<WaitReadValue, WaitTargetReadItem>? latestWaitTargets,  Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> waitTargetsByTool,  bool detailsVisible)?  $default,) {final _that = this;
switch (_that) {
case _ThreadStatusViewState() when $default != null:
return $default(_that.threadId,_that.execution,_that.configuration,_that.workflow,_that.activityRead,_that.storageRead,_that.configurationRead,_that.workflowRead,_that.turnRead,_that.latestWaitTargets,_that.waitTargetsByTool,_that.detailsVisible);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadStatusViewState implements ThreadStatusViewState {
  const _ThreadStatusViewState({required this.threadId, this.execution, this.configuration, this.workflow, this.activityRead = const ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem>(), this.storageRead = const ReadMaterial<StorageReadHeader, Never>(), this.configurationRead = const ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem>(), this.workflowRead = const ReadMaterial<WorkflowReadHeader, Never>(), this.turnRead = const ReadMaterial<TurnReadHeader, Never>(), this.latestWaitTargets,  Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> waitTargetsByTool = const {}, this.detailsVisible = false}): _waitTargetsByTool = waitTargetsByTool;


@override final  String threadId;
@override final  ThreadExecutionState? execution;
@override final  ThreadConfigurationState? configuration;
@override final  WorkflowBrief? workflow;
@override@JsonKey() final  ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> activityRead;
@override@JsonKey() final  ReadMaterial<StorageReadHeader, Never> storageRead;
@override@JsonKey() final  ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> configurationRead;
@override@JsonKey() final  ReadMaterial<WorkflowReadHeader, Never> workflowRead;
@override@JsonKey() final  ReadMaterial<TurnReadHeader, Never> turnRead;
@override final  ReadMaterial<WaitReadValue, WaitTargetReadItem>? latestWaitTargets;
 final  Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> _waitTargetsByTool;
@override@JsonKey() Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> get waitTargetsByTool {
  if (_waitTargetsByTool is EqualUnmodifiableMapView) return _waitTargetsByTool;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_waitTargetsByTool);
}

@override@JsonKey() final  bool detailsVisible;

/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadStatusViewStateCopyWith<_ThreadStatusViewState> get copyWith => __$ThreadStatusViewStateCopyWithImpl<_ThreadStatusViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadStatusViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.execution, execution) || other.execution == execution)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.workflow, workflow) || other.workflow == workflow)&&(identical(other.activityRead, activityRead) || other.activityRead == activityRead)&&(identical(other.storageRead, storageRead) || other.storageRead == storageRead)&&(identical(other.configurationRead, configurationRead) || other.configurationRead == configurationRead)&&(identical(other.workflowRead, workflowRead) || other.workflowRead == workflowRead)&&(identical(other.turnRead, turnRead) || other.turnRead == turnRead)&&(identical(other.latestWaitTargets, latestWaitTargets) || other.latestWaitTargets == latestWaitTargets)&&const DeepCollectionEquality().equals(other.waitTargetsByTool, _waitTargetsByTool)&&(identical(other.detailsVisible, detailsVisible) || other.detailsVisible == detailsVisible));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,execution,configuration,workflow,activityRead,storageRead,configurationRead,workflowRead,turnRead,latestWaitTargets,const DeepCollectionEquality().hash(_waitTargetsByTool),detailsVisible);
}



}

/// @nodoc
abstract mixin class _$ThreadStatusViewStateCopyWith<$Res> implements $ThreadStatusViewStateCopyWith<$Res> {
  factory _$ThreadStatusViewStateCopyWith(_ThreadStatusViewState value, $Res Function(_ThreadStatusViewState) _then) = __$ThreadStatusViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, ThreadExecutionState? execution, ThreadConfigurationState? configuration, WorkflowBrief? workflow, ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem> activityRead, ReadMaterial<StorageReadHeader, Never> storageRead, ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem> configurationRead, ReadMaterial<WorkflowReadHeader, Never> workflowRead, ReadMaterial<TurnReadHeader, Never> turnRead, ReadMaterial<WaitReadValue, WaitTargetReadItem>? latestWaitTargets, Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>> waitTargetsByTool, bool detailsVisible
});


@override $ThreadExecutionStateCopyWith<$Res>? get execution;@override $ThreadConfigurationStateCopyWith<$Res>? get configuration;@override $WorkflowBriefCopyWith<$Res>? get workflow;@override $ReadMaterialCopyWith<ActivityReadHeader, IndexedActivityToolReadItem, $Res> get activityRead;@override $ReadMaterialCopyWith<StorageReadHeader, Never, $Res> get storageRead;@override $ReadMaterialCopyWith<ThreadConfigurationReadHeader, SkillNameReadItem, $Res> get configurationRead;@override $ReadMaterialCopyWith<WorkflowReadHeader, Never, $Res> get workflowRead;@override $ReadMaterialCopyWith<TurnReadHeader, Never, $Res> get turnRead;@override $ReadMaterialCopyWith<WaitReadValue, WaitTargetReadItem, $Res>? get latestWaitTargets;

}
/// @nodoc
class __$ThreadStatusViewStateCopyWithImpl<$Res>
    implements _$ThreadStatusViewStateCopyWith<$Res> {
  __$ThreadStatusViewStateCopyWithImpl(this._self, this._then);

  final _ThreadStatusViewState _self;
  final $Res Function(_ThreadStatusViewState) _then;

/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? execution = freezed,Object? configuration = freezed,Object? workflow = freezed,Object? activityRead = null,Object? storageRead = null,Object? configurationRead = null,Object? workflowRead = null,Object? turnRead = null,Object? latestWaitTargets = freezed,Object? waitTargetsByTool = null,Object? detailsVisible = null,}) {
  return _then(_ThreadStatusViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadExecutionState?,configuration: freezed == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationState?,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowBrief?,activityRead: null == activityRead ? _self.activityRead : activityRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<ActivityReadHeader, IndexedActivityToolReadItem>,storageRead: null == storageRead ? _self.storageRead : storageRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<StorageReadHeader, Never>,configurationRead: null == configurationRead ? _self.configurationRead : configurationRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<ThreadConfigurationReadHeader, SkillNameReadItem>,workflowRead: null == workflowRead ? _self.workflowRead : workflowRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<WorkflowReadHeader, Never>,turnRead: null == turnRead ? _self.turnRead : turnRead // ignore: cast_nullable_to_non_nullable
as ReadMaterial<TurnReadHeader, Never>,latestWaitTargets: freezed == latestWaitTargets ? _self.latestWaitTargets : latestWaitTargets // ignore: cast_nullable_to_non_nullable
as ReadMaterial<WaitReadValue, WaitTargetReadItem>?,waitTargetsByTool: null == waitTargetsByTool ? _self._waitTargetsByTool : waitTargetsByTool // ignore: cast_nullable_to_non_nullable
as Map<int, ReadMaterial<WaitReadValue, WaitTargetReadItem>>,detailsVisible: null == detailsVisible ? _self.detailsVisible : detailsVisible // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionStateCopyWith<$Res>? get execution {
    if (_self.execution == null) {
    return null;
  }

  return $ThreadExecutionStateCopyWith<$Res>(_self.execution!, (value) {
    return _then(_self.copyWith(execution: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationStateCopyWith<$Res>? get configuration {
    if (_self.configuration == null) {
    return null;
  }

  return $ThreadConfigurationStateCopyWith<$Res>(_self.configuration!, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowBriefCopyWith<$Res>? get workflow {
    if (_self.workflow == null) {
    return null;
  }

  return $WorkflowBriefCopyWith<$Res>(_self.workflow!, (value) {
    return _then(_self.copyWith(workflow: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<ActivityReadHeader, IndexedActivityToolReadItem, $Res> get activityRead {

  return $ReadMaterialCopyWith<ActivityReadHeader, IndexedActivityToolReadItem, $Res>(_self.activityRead, (value) {
    return _then(_self.copyWith(activityRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<StorageReadHeader, Never, $Res> get storageRead {

  return $ReadMaterialCopyWith<StorageReadHeader, Never, $Res>(_self.storageRead, (value) {
    return _then(_self.copyWith(storageRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<ThreadConfigurationReadHeader, SkillNameReadItem, $Res> get configurationRead {

  return $ReadMaterialCopyWith<ThreadConfigurationReadHeader, SkillNameReadItem, $Res>(_self.configurationRead, (value) {
    return _then(_self.copyWith(configurationRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<WorkflowReadHeader, Never, $Res> get workflowRead {

  return $ReadMaterialCopyWith<WorkflowReadHeader, Never, $Res>(_self.workflowRead, (value) {
    return _then(_self.copyWith(workflowRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<TurnReadHeader, Never, $Res> get turnRead {

  return $ReadMaterialCopyWith<TurnReadHeader, Never, $Res>(_self.turnRead, (value) {
    return _then(_self.copyWith(turnRead: value));
  });
}/// Create a copy of ThreadStatusViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<WaitReadValue, WaitTargetReadItem, $Res>? get latestWaitTargets {
    if (_self.latestWaitTargets == null) {
    return null;
  }

  return $ReadMaterialCopyWith<WaitReadValue, WaitTargetReadItem, $Res>(_self.latestWaitTargets!, (value) {
    return _then(_self.copyWith(latestWaitTargets: value));
  });
}
}

// dart format on
