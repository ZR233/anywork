// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'shell_chrome_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShellChromeState {

 WorkspaceState get workspace; String? get activeThreadId; String? get rootThreadId; ProjectRecord? get project; WorkspaceThreadRecord? get root; bool get projectCurrent; bool get rootCurrent; bool get directoryCurrent; bool get configurationCurrent; List<AgentDirectoryEntry> get agents; ReadValue<DelegationSettings, ConfigurationReadRef>? get delegationDefaults; SessionCostsState? get costs; Set<String> get reading; Map<String, StudioFailure> get failures;
/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShellChromeStateCopyWith<ShellChromeState> get copyWith => _$ShellChromeStateCopyWithImpl<ShellChromeState>(this as ShellChromeState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShellChromeState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellChromeState&&(identical(other.workspace, _this.workspace) || other.workspace == _this.workspace)&&(identical(other.activeThreadId, _this.activeThreadId) || other.activeThreadId == _this.activeThreadId)&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&(identical(other.project, _this.project) || other.project == _this.project)&&(identical(other.root, _this.root) || other.root == _this.root)&&(identical(other.projectCurrent, _this.projectCurrent) || other.projectCurrent == _this.projectCurrent)&&(identical(other.rootCurrent, _this.rootCurrent) || other.rootCurrent == _this.rootCurrent)&&(identical(other.directoryCurrent, _this.directoryCurrent) || other.directoryCurrent == _this.directoryCurrent)&&(identical(other.configurationCurrent, _this.configurationCurrent) || other.configurationCurrent == _this.configurationCurrent)&&const DeepCollectionEquality().equals(other.agents, _this.agents)&&(identical(other.delegationDefaults, _this.delegationDefaults) || other.delegationDefaults == _this.delegationDefaults)&&(identical(other.costs, _this.costs) || other.costs == _this.costs)&&const DeepCollectionEquality().equals(other.reading, _this.reading)&&const DeepCollectionEquality().equals(other.failures, _this.failures));
}


@override
int get hashCode {
  final _this = this as ShellChromeState;
  return Object.hash(runtimeType,_this.workspace,_this.activeThreadId,_this.rootThreadId,_this.project,_this.root,_this.projectCurrent,_this.rootCurrent,_this.directoryCurrent,_this.configurationCurrent,const DeepCollectionEquality().hash(_this.agents),_this.delegationDefaults,_this.costs,const DeepCollectionEquality().hash(_this.reading),const DeepCollectionEquality().hash(_this.failures));
}



}

/// @nodoc
abstract mixin class $ShellChromeStateCopyWith<$Res>  {
  factory $ShellChromeStateCopyWith(ShellChromeState value, $Res Function(ShellChromeState) _then) = _$ShellChromeStateCopyWithImpl;
@useResult
$Res call({
 WorkspaceState workspace, String? activeThreadId, String? rootThreadId, ProjectRecord? project, WorkspaceThreadRecord? root, bool projectCurrent, bool rootCurrent, bool directoryCurrent, bool configurationCurrent, List<AgentDirectoryEntry> agents, ReadValue<DelegationSettings, ConfigurationReadRef>? delegationDefaults, SessionCostsState? costs, Set<String> reading, Map<String, StudioFailure> failures
});


$WorkspaceStateCopyWith<$Res> get workspace;$ProjectRecordCopyWith<$Res>? get project;$WorkspaceThreadRecordCopyWith<$Res>? get root;$ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>? get delegationDefaults;$SessionCostsStateCopyWith<$Res>? get costs;

}
/// @nodoc
class _$ShellChromeStateCopyWithImpl<$Res>
    implements $ShellChromeStateCopyWith<$Res> {
  _$ShellChromeStateCopyWithImpl(this._self, this._then);

  final ShellChromeState _self;
  final $Res Function(ShellChromeState) _then;

/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? workspace = null,Object? activeThreadId = freezed,Object? rootThreadId = freezed,Object? project = freezed,Object? root = freezed,Object? projectCurrent = null,Object? rootCurrent = null,Object? directoryCurrent = null,Object? configurationCurrent = null,Object? agents = null,Object? delegationDefaults = freezed,Object? costs = freezed,Object? reading = null,Object? failures = null,}) {
  return _then(ShellChromeState(
workspace: null == workspace ? _self.workspace : workspace // ignore: cast_nullable_to_non_nullable
as WorkspaceState,activeThreadId: freezed == activeThreadId ? _self.activeThreadId : activeThreadId // ignore: cast_nullable_to_non_nullable
as String?,rootThreadId: freezed == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String?,project: freezed == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as ProjectRecord?,root: freezed == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecord?,projectCurrent: null == projectCurrent ? _self.projectCurrent : projectCurrent // ignore: cast_nullable_to_non_nullable
as bool,rootCurrent: null == rootCurrent ? _self.rootCurrent : rootCurrent // ignore: cast_nullable_to_non_nullable
as bool,directoryCurrent: null == directoryCurrent ? _self.directoryCurrent : directoryCurrent // ignore: cast_nullable_to_non_nullable
as bool,configurationCurrent: null == configurationCurrent ? _self.configurationCurrent : configurationCurrent // ignore: cast_nullable_to_non_nullable
as bool,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as List<AgentDirectoryEntry>,delegationDefaults: freezed == delegationDefaults ? _self.delegationDefaults : delegationDefaults // ignore: cast_nullable_to_non_nullable
as ReadValue<DelegationSettings, ConfigurationReadRef>?,costs: freezed == costs ? _self.costs : costs // ignore: cast_nullable_to_non_nullable
as SessionCostsState?,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<String>,failures: null == failures ? _self.failures : failures // ignore: cast_nullable_to_non_nullable
as Map<String, StudioFailure>,
  ));
}
/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get workspace {

  return $WorkspaceStateCopyWith<$Res>(_self.workspace, (value) {
    return _then(_self.copyWith(workspace: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectRecordCopyWith<$Res>? get project {
    if (_self.project == null) {
    return null;
  }

  return $ProjectRecordCopyWith<$Res>(_self.project!, (value) {
    return _then(_self.copyWith(project: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<$Res>? get root {
    if (_self.root == null) {
    return null;
  }

  return $WorkspaceThreadRecordCopyWith<$Res>(_self.root!, (value) {
    return _then(_self.copyWith(root: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>? get delegationDefaults {
    if (_self.delegationDefaults == null) {
    return null;
  }

  return $ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>(_self.delegationDefaults!, (value) {
    return _then(_self.copyWith(delegationDefaults: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsStateCopyWith<$Res>? get costs {
    if (_self.costs == null) {
    return null;
  }

  return $SessionCostsStateCopyWith<$Res>(_self.costs!, (value) {
    return _then(_self.copyWith(costs: value));
  });
}
}


/// Adds pattern-matching-related methods to [ShellChromeState].
extension ShellChromeStatePatterns on ShellChromeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShellChromeState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShellChromeState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShellChromeState value)  $default,){
final _that = this;
switch (_that) {
case _ShellChromeState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShellChromeState value)?  $default,){
final _that = this;
switch (_that) {
case _ShellChromeState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceState workspace,  String? activeThreadId,  String? rootThreadId,  ProjectRecord? project,  WorkspaceThreadRecord? root,  bool projectCurrent,  bool rootCurrent,  bool directoryCurrent,  bool configurationCurrent,  List<AgentDirectoryEntry> agents,  ReadValue<DelegationSettings, ConfigurationReadRef>? delegationDefaults,  SessionCostsState? costs,  Set<String> reading,  Map<String, StudioFailure> failures)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShellChromeState() when $default != null:
return $default(_that.workspace,_that.activeThreadId,_that.rootThreadId,_that.project,_that.root,_that.projectCurrent,_that.rootCurrent,_that.directoryCurrent,_that.configurationCurrent,_that.agents,_that.delegationDefaults,_that.costs,_that.reading,_that.failures);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceState workspace,  String? activeThreadId,  String? rootThreadId,  ProjectRecord? project,  WorkspaceThreadRecord? root,  bool projectCurrent,  bool rootCurrent,  bool directoryCurrent,  bool configurationCurrent,  List<AgentDirectoryEntry> agents,  ReadValue<DelegationSettings, ConfigurationReadRef>? delegationDefaults,  SessionCostsState? costs,  Set<String> reading,  Map<String, StudioFailure> failures)  $default,) {final _that = this;
switch (_that) {
case _ShellChromeState():
return $default(_that.workspace,_that.activeThreadId,_that.rootThreadId,_that.project,_that.root,_that.projectCurrent,_that.rootCurrent,_that.directoryCurrent,_that.configurationCurrent,_that.agents,_that.delegationDefaults,_that.costs,_that.reading,_that.failures);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceState workspace,  String? activeThreadId,  String? rootThreadId,  ProjectRecord? project,  WorkspaceThreadRecord? root,  bool projectCurrent,  bool rootCurrent,  bool directoryCurrent,  bool configurationCurrent,  List<AgentDirectoryEntry> agents,  ReadValue<DelegationSettings, ConfigurationReadRef>? delegationDefaults,  SessionCostsState? costs,  Set<String> reading,  Map<String, StudioFailure> failures)?  $default,) {final _that = this;
switch (_that) {
case _ShellChromeState() when $default != null:
return $default(_that.workspace,_that.activeThreadId,_that.rootThreadId,_that.project,_that.root,_that.projectCurrent,_that.rootCurrent,_that.directoryCurrent,_that.configurationCurrent,_that.agents,_that.delegationDefaults,_that.costs,_that.reading,_that.failures);case _:
  return null;

}
}

}

/// @nodoc


class _ShellChromeState extends ShellChromeState {
  const _ShellChromeState({required this.workspace, this.activeThreadId, this.rootThreadId, this.project, this.root, this.projectCurrent = false, this.rootCurrent = false, this.directoryCurrent = false, this.configurationCurrent = false,  List<AgentDirectoryEntry> agents = const [], this.delegationDefaults, this.costs,  Set<String> reading = const {},  Map<String, StudioFailure> failures = const {}}): _agents = agents,_reading = reading,_failures = failures,super._();


@override final  WorkspaceState workspace;
@override final  String? activeThreadId;
@override final  String? rootThreadId;
@override final  ProjectRecord? project;
@override final  WorkspaceThreadRecord? root;
@override@JsonKey() final  bool projectCurrent;
@override@JsonKey() final  bool rootCurrent;
@override@JsonKey() final  bool directoryCurrent;
@override@JsonKey() final  bool configurationCurrent;
 final  List<AgentDirectoryEntry> _agents;
@override@JsonKey() List<AgentDirectoryEntry> get agents {
  if (_agents is EqualUnmodifiableListView) return _agents;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_agents);
}

@override final  ReadValue<DelegationSettings, ConfigurationReadRef>? delegationDefaults;
@override final  SessionCostsState? costs;
 final  Set<String> _reading;
@override@JsonKey() Set<String> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}

 final  Map<String, StudioFailure> _failures;
@override@JsonKey() Map<String, StudioFailure> get failures {
  if (_failures is EqualUnmodifiableMapView) return _failures;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_failures);
}


/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShellChromeStateCopyWith<_ShellChromeState> get copyWith => __$ShellChromeStateCopyWithImpl<_ShellChromeState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShellChromeState&&(identical(other.workspace, workspace) || other.workspace == workspace)&&(identical(other.activeThreadId, activeThreadId) || other.activeThreadId == activeThreadId)&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&(identical(other.project, project) || other.project == project)&&(identical(other.root, root) || other.root == root)&&(identical(other.projectCurrent, projectCurrent) || other.projectCurrent == projectCurrent)&&(identical(other.rootCurrent, rootCurrent) || other.rootCurrent == rootCurrent)&&(identical(other.directoryCurrent, directoryCurrent) || other.directoryCurrent == directoryCurrent)&&(identical(other.configurationCurrent, configurationCurrent) || other.configurationCurrent == configurationCurrent)&&const DeepCollectionEquality().equals(other.agents, _agents)&&(identical(other.delegationDefaults, delegationDefaults) || other.delegationDefaults == delegationDefaults)&&(identical(other.costs, costs) || other.costs == costs)&&const DeepCollectionEquality().equals(other.reading, _reading)&&const DeepCollectionEquality().equals(other.failures, _failures));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspace,activeThreadId,rootThreadId,project,root,projectCurrent,rootCurrent,directoryCurrent,configurationCurrent,const DeepCollectionEquality().hash(_agents),delegationDefaults,costs,const DeepCollectionEquality().hash(_reading),const DeepCollectionEquality().hash(_failures));
}



}

/// @nodoc
abstract mixin class _$ShellChromeStateCopyWith<$Res> implements $ShellChromeStateCopyWith<$Res> {
  factory _$ShellChromeStateCopyWith(_ShellChromeState value, $Res Function(_ShellChromeState) _then) = __$ShellChromeStateCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceState workspace, String? activeThreadId, String? rootThreadId, ProjectRecord? project, WorkspaceThreadRecord? root, bool projectCurrent, bool rootCurrent, bool directoryCurrent, bool configurationCurrent, List<AgentDirectoryEntry> agents, ReadValue<DelegationSettings, ConfigurationReadRef>? delegationDefaults, SessionCostsState? costs, Set<String> reading, Map<String, StudioFailure> failures
});


@override $WorkspaceStateCopyWith<$Res> get workspace;@override $ProjectRecordCopyWith<$Res>? get project;@override $WorkspaceThreadRecordCopyWith<$Res>? get root;@override $ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>? get delegationDefaults;@override $SessionCostsStateCopyWith<$Res>? get costs;

}
/// @nodoc
class __$ShellChromeStateCopyWithImpl<$Res>
    implements _$ShellChromeStateCopyWith<$Res> {
  __$ShellChromeStateCopyWithImpl(this._self, this._then);

  final _ShellChromeState _self;
  final $Res Function(_ShellChromeState) _then;

/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? workspace = null,Object? activeThreadId = freezed,Object? rootThreadId = freezed,Object? project = freezed,Object? root = freezed,Object? projectCurrent = null,Object? rootCurrent = null,Object? directoryCurrent = null,Object? configurationCurrent = null,Object? agents = null,Object? delegationDefaults = freezed,Object? costs = freezed,Object? reading = null,Object? failures = null,}) {
  return _then(_ShellChromeState(
workspace: null == workspace ? _self.workspace : workspace // ignore: cast_nullable_to_non_nullable
as WorkspaceState,activeThreadId: freezed == activeThreadId ? _self.activeThreadId : activeThreadId // ignore: cast_nullable_to_non_nullable
as String?,rootThreadId: freezed == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String?,project: freezed == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as ProjectRecord?,root: freezed == root ? _self.root : root // ignore: cast_nullable_to_non_nullable
as WorkspaceThreadRecord?,projectCurrent: null == projectCurrent ? _self.projectCurrent : projectCurrent // ignore: cast_nullable_to_non_nullable
as bool,rootCurrent: null == rootCurrent ? _self.rootCurrent : rootCurrent // ignore: cast_nullable_to_non_nullable
as bool,directoryCurrent: null == directoryCurrent ? _self.directoryCurrent : directoryCurrent // ignore: cast_nullable_to_non_nullable
as bool,configurationCurrent: null == configurationCurrent ? _self.configurationCurrent : configurationCurrent // ignore: cast_nullable_to_non_nullable
as bool,agents: null == agents ? _self._agents : agents // ignore: cast_nullable_to_non_nullable
as List<AgentDirectoryEntry>,delegationDefaults: freezed == delegationDefaults ? _self.delegationDefaults : delegationDefaults // ignore: cast_nullable_to_non_nullable
as ReadValue<DelegationSettings, ConfigurationReadRef>?,costs: freezed == costs ? _self.costs : costs // ignore: cast_nullable_to_non_nullable
as SessionCostsState?,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<String>,failures: null == failures ? _self._failures : failures // ignore: cast_nullable_to_non_nullable
as Map<String, StudioFailure>,
  ));
}

/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get workspace {

  return $WorkspaceStateCopyWith<$Res>(_self.workspace, (value) {
    return _then(_self.copyWith(workspace: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectRecordCopyWith<$Res>? get project {
    if (_self.project == null) {
    return null;
  }

  return $ProjectRecordCopyWith<$Res>(_self.project!, (value) {
    return _then(_self.copyWith(project: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceThreadRecordCopyWith<$Res>? get root {
    if (_self.root == null) {
    return null;
  }

  return $WorkspaceThreadRecordCopyWith<$Res>(_self.root!, (value) {
    return _then(_self.copyWith(root: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>? get delegationDefaults {
    if (_self.delegationDefaults == null) {
    return null;
  }

  return $ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>(_self.delegationDefaults!, (value) {
    return _then(_self.copyWith(delegationDefaults: value));
  });
}/// Create a copy of ShellChromeState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsStateCopyWith<$Res>? get costs {
    if (_self.costs == null) {
    return null;
  }

  return $SessionCostsStateCopyWith<$Res>(_self.costs!, (value) {
    return _then(_self.copyWith(costs: value));
  });
}
}

/// @nodoc
mixin _$ShellBotsEntry {

 bool get current; String? get summary; StudioFailure? get failure;
/// Create a copy of ShellBotsEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShellBotsEntryCopyWith<ShellBotsEntry> get copyWith => _$ShellBotsEntryCopyWithImpl<ShellBotsEntry>(this as ShellBotsEntry, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShellBotsEntry;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellBotsEntry&&(identical(other.current, _this.current) || other.current == _this.current)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.failure, _this.failure) || other.failure == _this.failure));
}


@override
int get hashCode {
  final _this = this as ShellBotsEntry;
  return Object.hash(runtimeType,_this.current,_this.summary,_this.failure);
}



}

/// @nodoc
abstract mixin class $ShellBotsEntryCopyWith<$Res>  {
  factory $ShellBotsEntryCopyWith(ShellBotsEntry value, $Res Function(ShellBotsEntry) _then) = _$ShellBotsEntryCopyWithImpl;
@useResult
$Res call({
 bool current, String? summary, StudioFailure? failure
});


$StudioFailureCopyWith<$Res>? get failure;

}
/// @nodoc
class _$ShellBotsEntryCopyWithImpl<$Res>
    implements $ShellBotsEntryCopyWith<$Res> {
  _$ShellBotsEntryCopyWithImpl(this._self, this._then);

  final ShellBotsEntry _self;
  final $Res Function(ShellBotsEntry) _then;

/// Create a copy of ShellBotsEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? current = null,Object? summary = freezed,Object? failure = freezed,}) {
  return _then(ShellBotsEntry(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as bool,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ShellBotsEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}


/// Adds pattern-matching-related methods to [ShellBotsEntry].
extension ShellBotsEntryPatterns on ShellBotsEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShellBotsEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShellBotsEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShellBotsEntry value)  $default,){
final _that = this;
switch (_that) {
case _ShellBotsEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShellBotsEntry value)?  $default,){
final _that = this;
switch (_that) {
case _ShellBotsEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool current,  String? summary,  StudioFailure? failure)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShellBotsEntry() when $default != null:
return $default(_that.current,_that.summary,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool current,  String? summary,  StudioFailure? failure)  $default,) {final _that = this;
switch (_that) {
case _ShellBotsEntry():
return $default(_that.current,_that.summary,_that.failure);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool current,  String? summary,  StudioFailure? failure)?  $default,) {final _that = this;
switch (_that) {
case _ShellBotsEntry() when $default != null:
return $default(_that.current,_that.summary,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class _ShellBotsEntry implements ShellBotsEntry {
  const _ShellBotsEntry({this.current = false, this.summary, this.failure});


@override@JsonKey() final  bool current;
@override final  String? summary;
@override final  StudioFailure? failure;

/// Create a copy of ShellBotsEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShellBotsEntryCopyWith<_ShellBotsEntry> get copyWith => __$ShellBotsEntryCopyWithImpl<_ShellBotsEntry>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShellBotsEntry&&(identical(other.current, current) || other.current == current)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,current,summary,failure);
}



}

/// @nodoc
abstract mixin class _$ShellBotsEntryCopyWith<$Res> implements $ShellBotsEntryCopyWith<$Res> {
  factory _$ShellBotsEntryCopyWith(_ShellBotsEntry value, $Res Function(_ShellBotsEntry) _then) = __$ShellBotsEntryCopyWithImpl;
@override @useResult
$Res call({
 bool current, String? summary, StudioFailure? failure
});


@override $StudioFailureCopyWith<$Res>? get failure;

}
/// @nodoc
class __$ShellBotsEntryCopyWithImpl<$Res>
    implements _$ShellBotsEntryCopyWith<$Res> {
  __$ShellBotsEntryCopyWithImpl(this._self, this._then);

  final _ShellBotsEntry _self;
  final $Res Function(_ShellBotsEntry) _then;

/// Create a copy of ShellBotsEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? current = null,Object? summary = freezed,Object? failure = freezed,}) {
  return _then(_ShellBotsEntry(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as bool,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ShellBotsEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

// dart format on
