// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'studio_projection_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ShellChromeView {

 List<StudioRecoveryIssue> get applicationRecoveryIssues; PersistenceStateSnapshot get persistenceState;
/// Create a copy of ShellChromeView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShellChromeViewCopyWith<ShellChromeView> get copyWith => _$ShellChromeViewCopyWithImpl<ShellChromeView>(this as ShellChromeView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ShellChromeView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ShellChromeView&&const DeepCollectionEquality().equals(other.applicationRecoveryIssues, _this.applicationRecoveryIssues)&&(identical(other.persistenceState, _this.persistenceState) || other.persistenceState == _this.persistenceState));
}


@override
int get hashCode {
  final _this = this as ShellChromeView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.applicationRecoveryIssues),_this.persistenceState);
}

@override
String toString() {
  final _this = this as ShellChromeView;
  return 'ShellChromeView(applicationRecoveryIssues: ${_this.applicationRecoveryIssues}, persistenceState: ${_this.persistenceState})';
}


}

/// @nodoc
abstract mixin class $ShellChromeViewCopyWith<$Res>  {
  factory $ShellChromeViewCopyWith(ShellChromeView value, $Res Function(ShellChromeView) _then) = _$ShellChromeViewCopyWithImpl;
@useResult
$Res call({
 List<StudioRecoveryIssue> applicationRecoveryIssues, PersistenceStateSnapshot persistenceState
});




}
/// @nodoc
class _$ShellChromeViewCopyWithImpl<$Res>
    implements $ShellChromeViewCopyWith<$Res> {
  _$ShellChromeViewCopyWithImpl(this._self, this._then);

  final ShellChromeView _self;
  final $Res Function(ShellChromeView) _then;

/// Create a copy of ShellChromeView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? applicationRecoveryIssues = null,Object? persistenceState = null,}) {
  return _then(ShellChromeView(
applicationRecoveryIssues: null == applicationRecoveryIssues ? _self.applicationRecoveryIssues : applicationRecoveryIssues // ignore: cast_nullable_to_non_nullable
as List<StudioRecoveryIssue>,persistenceState: null == persistenceState ? _self.persistenceState : persistenceState // ignore: cast_nullable_to_non_nullable
as PersistenceStateSnapshot,
  ));
}

}


/// Adds pattern-matching-related methods to [ShellChromeView].
extension ShellChromeViewPatterns on ShellChromeView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ShellChromeView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ShellChromeView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ShellChromeView value)  $default,){
final _that = this;
switch (_that) {
case _ShellChromeView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ShellChromeView value)?  $default,){
final _that = this;
switch (_that) {
case _ShellChromeView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<StudioRecoveryIssue> applicationRecoveryIssues,  PersistenceStateSnapshot persistenceState)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ShellChromeView() when $default != null:
return $default(_that.applicationRecoveryIssues,_that.persistenceState);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<StudioRecoveryIssue> applicationRecoveryIssues,  PersistenceStateSnapshot persistenceState)  $default,) {final _that = this;
switch (_that) {
case _ShellChromeView():
return $default(_that.applicationRecoveryIssues,_that.persistenceState);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<StudioRecoveryIssue> applicationRecoveryIssues,  PersistenceStateSnapshot persistenceState)?  $default,) {final _that = this;
switch (_that) {
case _ShellChromeView() when $default != null:
return $default(_that.applicationRecoveryIssues,_that.persistenceState);case _:
  return null;

}
}

}

/// @nodoc


class _ShellChromeView implements ShellChromeView {
  const _ShellChromeView({required  List<StudioRecoveryIssue> applicationRecoveryIssues, required this.persistenceState}): _applicationRecoveryIssues = applicationRecoveryIssues;


 final  List<StudioRecoveryIssue> _applicationRecoveryIssues;
@override List<StudioRecoveryIssue> get applicationRecoveryIssues {
  if (_applicationRecoveryIssues is EqualUnmodifiableListView) return _applicationRecoveryIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_applicationRecoveryIssues);
}

@override final  PersistenceStateSnapshot persistenceState;

/// Create a copy of ShellChromeView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ShellChromeViewCopyWith<_ShellChromeView> get copyWith => __$ShellChromeViewCopyWithImpl<_ShellChromeView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ShellChromeView&&const DeepCollectionEquality().equals(other.applicationRecoveryIssues, _applicationRecoveryIssues)&&(identical(other.persistenceState, persistenceState) || other.persistenceState == persistenceState));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_applicationRecoveryIssues),persistenceState);
}

@override
String toString() {
    return 'ShellChromeView(applicationRecoveryIssues: $applicationRecoveryIssues, persistenceState: $persistenceState)';
}


}

/// @nodoc
abstract mixin class _$ShellChromeViewCopyWith<$Res> implements $ShellChromeViewCopyWith<$Res> {
  factory _$ShellChromeViewCopyWith(_ShellChromeView value, $Res Function(_ShellChromeView) _then) = __$ShellChromeViewCopyWithImpl;
@override @useResult
$Res call({
 List<StudioRecoveryIssue> applicationRecoveryIssues, PersistenceStateSnapshot persistenceState
});




}
/// @nodoc
class __$ShellChromeViewCopyWithImpl<$Res>
    implements _$ShellChromeViewCopyWith<$Res> {
  __$ShellChromeViewCopyWithImpl(this._self, this._then);

  final _ShellChromeView _self;
  final $Res Function(_ShellChromeView) _then;

/// Create a copy of ShellChromeView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? applicationRecoveryIssues = null,Object? persistenceState = null,}) {
  return _then(_ShellChromeView(
applicationRecoveryIssues: null == applicationRecoveryIssues ? _self._applicationRecoveryIssues : applicationRecoveryIssues // ignore: cast_nullable_to_non_nullable
as List<StudioRecoveryIssue>,persistenceState: null == persistenceState ? _self.persistenceState : persistenceState // ignore: cast_nullable_to_non_nullable
as PersistenceStateSnapshot,
  ));
}


}

/// @nodoc
mixin _$SidebarView {

 List<StudioProject> get projects; String? get selectedProjectId; bool get isBusy; Map<String, StudioRecoveryIssue> get projectRecoveryIssues; Map<String, String> get modeDisplayNames;
/// Create a copy of SidebarView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SidebarViewCopyWith<SidebarView> get copyWith => _$SidebarViewCopyWithImpl<SidebarView>(this as SidebarView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SidebarView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SidebarView&&const DeepCollectionEquality().equals(other.projects, _this.projects)&&(identical(other.selectedProjectId, _this.selectedProjectId) || other.selectedProjectId == _this.selectedProjectId)&&(identical(other.isBusy, _this.isBusy) || other.isBusy == _this.isBusy)&&const DeepCollectionEquality().equals(other.projectRecoveryIssues, _this.projectRecoveryIssues)&&const DeepCollectionEquality().equals(other.modeDisplayNames, _this.modeDisplayNames));
}


@override
int get hashCode {
  final _this = this as SidebarView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.projects),_this.selectedProjectId,_this.isBusy,const DeepCollectionEquality().hash(_this.projectRecoveryIssues),const DeepCollectionEquality().hash(_this.modeDisplayNames));
}

@override
String toString() {
  final _this = this as SidebarView;
  return 'SidebarView(projects: ${_this.projects}, selectedProjectId: ${_this.selectedProjectId}, isBusy: ${_this.isBusy}, projectRecoveryIssues: ${_this.projectRecoveryIssues}, modeDisplayNames: ${_this.modeDisplayNames})';
}


}

/// @nodoc
abstract mixin class $SidebarViewCopyWith<$Res>  {
  factory $SidebarViewCopyWith(SidebarView value, $Res Function(SidebarView) _then) = _$SidebarViewCopyWithImpl;
@useResult
$Res call({
 List<StudioProject> projects, String? selectedProjectId, bool isBusy, Map<String, StudioRecoveryIssue> projectRecoveryIssues, Map<String, String> modeDisplayNames
});




}
/// @nodoc
class _$SidebarViewCopyWithImpl<$Res>
    implements $SidebarViewCopyWith<$Res> {
  _$SidebarViewCopyWithImpl(this._self, this._then);

  final SidebarView _self;
  final $Res Function(SidebarView) _then;

/// Create a copy of SidebarView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projects = null,Object? selectedProjectId = freezed,Object? isBusy = null,Object? projectRecoveryIssues = null,Object? modeDisplayNames = null,}) {
  return _then(SidebarView(
projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as List<StudioProject>,selectedProjectId: freezed == selectedProjectId ? _self.selectedProjectId : selectedProjectId // ignore: cast_nullable_to_non_nullable
as String?,isBusy: null == isBusy ? _self.isBusy : isBusy // ignore: cast_nullable_to_non_nullable
as bool,projectRecoveryIssues: null == projectRecoveryIssues ? _self.projectRecoveryIssues : projectRecoveryIssues // ignore: cast_nullable_to_non_nullable
as Map<String, StudioRecoveryIssue>,modeDisplayNames: null == modeDisplayNames ? _self.modeDisplayNames : modeDisplayNames // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [SidebarView].
extension SidebarViewPatterns on SidebarView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SidebarView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SidebarView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SidebarView value)  $default,){
final _that = this;
switch (_that) {
case _SidebarView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SidebarView value)?  $default,){
final _that = this;
switch (_that) {
case _SidebarView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<StudioProject> projects,  String? selectedProjectId,  bool isBusy,  Map<String, StudioRecoveryIssue> projectRecoveryIssues,  Map<String, String> modeDisplayNames)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SidebarView() when $default != null:
return $default(_that.projects,_that.selectedProjectId,_that.isBusy,_that.projectRecoveryIssues,_that.modeDisplayNames);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<StudioProject> projects,  String? selectedProjectId,  bool isBusy,  Map<String, StudioRecoveryIssue> projectRecoveryIssues,  Map<String, String> modeDisplayNames)  $default,) {final _that = this;
switch (_that) {
case _SidebarView():
return $default(_that.projects,_that.selectedProjectId,_that.isBusy,_that.projectRecoveryIssues,_that.modeDisplayNames);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<StudioProject> projects,  String? selectedProjectId,  bool isBusy,  Map<String, StudioRecoveryIssue> projectRecoveryIssues,  Map<String, String> modeDisplayNames)?  $default,) {final _that = this;
switch (_that) {
case _SidebarView() when $default != null:
return $default(_that.projects,_that.selectedProjectId,_that.isBusy,_that.projectRecoveryIssues,_that.modeDisplayNames);case _:
  return null;

}
}

}

/// @nodoc


class _SidebarView extends SidebarView {
  const _SidebarView({required  List<StudioProject> projects, required this.selectedProjectId, required this.isBusy, required  Map<String, StudioRecoveryIssue> projectRecoveryIssues, required  Map<String, String> modeDisplayNames}): _projects = projects,_projectRecoveryIssues = projectRecoveryIssues,_modeDisplayNames = modeDisplayNames,super._();


 final  List<StudioProject> _projects;
@override List<StudioProject> get projects {
  if (_projects is EqualUnmodifiableListView) return _projects;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_projects);
}

@override final  String? selectedProjectId;
@override final  bool isBusy;
 final  Map<String, StudioRecoveryIssue> _projectRecoveryIssues;
@override Map<String, StudioRecoveryIssue> get projectRecoveryIssues {
  if (_projectRecoveryIssues is EqualUnmodifiableMapView) return _projectRecoveryIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_projectRecoveryIssues);
}

 final  Map<String, String> _modeDisplayNames;
@override Map<String, String> get modeDisplayNames {
  if (_modeDisplayNames is EqualUnmodifiableMapView) return _modeDisplayNames;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_modeDisplayNames);
}


/// Create a copy of SidebarView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SidebarViewCopyWith<_SidebarView> get copyWith => __$SidebarViewCopyWithImpl<_SidebarView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SidebarView&&const DeepCollectionEquality().equals(other.projects, _projects)&&(identical(other.selectedProjectId, selectedProjectId) || other.selectedProjectId == selectedProjectId)&&(identical(other.isBusy, isBusy) || other.isBusy == isBusy)&&const DeepCollectionEquality().equals(other.projectRecoveryIssues, _projectRecoveryIssues)&&const DeepCollectionEquality().equals(other.modeDisplayNames, _modeDisplayNames));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_projects),selectedProjectId,isBusy,const DeepCollectionEquality().hash(_projectRecoveryIssues),const DeepCollectionEquality().hash(_modeDisplayNames));
}

@override
String toString() {
    return 'SidebarView(projects: $projects, selectedProjectId: $selectedProjectId, isBusy: $isBusy, projectRecoveryIssues: $projectRecoveryIssues, modeDisplayNames: $modeDisplayNames)';
}


}

/// @nodoc
abstract mixin class _$SidebarViewCopyWith<$Res> implements $SidebarViewCopyWith<$Res> {
  factory _$SidebarViewCopyWith(_SidebarView value, $Res Function(_SidebarView) _then) = __$SidebarViewCopyWithImpl;
@override @useResult
$Res call({
 List<StudioProject> projects, String? selectedProjectId, bool isBusy, Map<String, StudioRecoveryIssue> projectRecoveryIssues, Map<String, String> modeDisplayNames
});




}
/// @nodoc
class __$SidebarViewCopyWithImpl<$Res>
    implements _$SidebarViewCopyWith<$Res> {
  __$SidebarViewCopyWithImpl(this._self, this._then);

  final _SidebarView _self;
  final $Res Function(_SidebarView) _then;

/// Create a copy of SidebarView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projects = null,Object? selectedProjectId = freezed,Object? isBusy = null,Object? projectRecoveryIssues = null,Object? modeDisplayNames = null,}) {
  return _then(_SidebarView(
projects: null == projects ? _self._projects : projects // ignore: cast_nullable_to_non_nullable
as List<StudioProject>,selectedProjectId: freezed == selectedProjectId ? _self.selectedProjectId : selectedProjectId // ignore: cast_nullable_to_non_nullable
as String?,isBusy: null == isBusy ? _self.isBusy : isBusy // ignore: cast_nullable_to_non_nullable
as bool,projectRecoveryIssues: null == projectRecoveryIssues ? _self._projectRecoveryIssues : projectRecoveryIssues // ignore: cast_nullable_to_non_nullable
as Map<String, StudioRecoveryIssue>,modeDisplayNames: null == modeDisplayNames ? _self._modeDisplayNames : modeDisplayNames // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}


}

/// @nodoc
mixin _$HeaderView {

 SessionDirectoryRow? get selectedRootRow; StudioProject? get selectedProject; String? get selectedProjectId; List<SessionDirectoryRow> get workspaceRows; List<StudioAgentView> get agents; String? get selectedThreadId; ThreadRuntimeView get runtime; SessionCostView? get sessionCost; List<PendingInteraction> get pendingInteractions;
/// Create a copy of HeaderView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$HeaderViewCopyWith<HeaderView> get copyWith => _$HeaderViewCopyWithImpl<HeaderView>(this as HeaderView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as HeaderView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is HeaderView&&(identical(other.selectedRootRow, _this.selectedRootRow) || other.selectedRootRow == _this.selectedRootRow)&&(identical(other.selectedProject, _this.selectedProject) || other.selectedProject == _this.selectedProject)&&(identical(other.selectedProjectId, _this.selectedProjectId) || other.selectedProjectId == _this.selectedProjectId)&&const DeepCollectionEquality().equals(other.workspaceRows, _this.workspaceRows)&&const DeepCollectionEquality().equals(other.agents, _this.agents)&&(identical(other.selectedThreadId, _this.selectedThreadId) || other.selectedThreadId == _this.selectedThreadId)&&(identical(other.runtime, _this.runtime) || other.runtime == _this.runtime)&&(identical(other.sessionCost, _this.sessionCost) || other.sessionCost == _this.sessionCost)&&const DeepCollectionEquality().equals(other.pendingInteractions, _this.pendingInteractions));
}


@override
int get hashCode {
  final _this = this as HeaderView;
  return Object.hash(runtimeType,_this.selectedRootRow,_this.selectedProject,_this.selectedProjectId,const DeepCollectionEquality().hash(_this.workspaceRows),const DeepCollectionEquality().hash(_this.agents),_this.selectedThreadId,_this.runtime,_this.sessionCost,const DeepCollectionEquality().hash(_this.pendingInteractions));
}

@override
String toString() {
  final _this = this as HeaderView;
  return 'HeaderView(selectedRootRow: ${_this.selectedRootRow}, selectedProject: ${_this.selectedProject}, selectedProjectId: ${_this.selectedProjectId}, workspaceRows: ${_this.workspaceRows}, agents: ${_this.agents}, selectedThreadId: ${_this.selectedThreadId}, runtime: ${_this.runtime}, sessionCost: ${_this.sessionCost}, pendingInteractions: ${_this.pendingInteractions})';
}


}

/// @nodoc
abstract mixin class $HeaderViewCopyWith<$Res>  {
  factory $HeaderViewCopyWith(HeaderView value, $Res Function(HeaderView) _then) = _$HeaderViewCopyWithImpl;
@useResult
$Res call({
 SessionDirectoryRow? selectedRootRow, StudioProject? selectedProject, String? selectedProjectId, List<SessionDirectoryRow> workspaceRows, List<StudioAgentView> agents, String? selectedThreadId, ThreadRuntimeView runtime, SessionCostView? sessionCost, List<PendingInteraction> pendingInteractions
});




}
/// @nodoc
class _$HeaderViewCopyWithImpl<$Res>
    implements $HeaderViewCopyWith<$Res> {
  _$HeaderViewCopyWithImpl(this._self, this._then);

  final HeaderView _self;
  final $Res Function(HeaderView) _then;

/// Create a copy of HeaderView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selectedRootRow = freezed,Object? selectedProject = freezed,Object? selectedProjectId = freezed,Object? workspaceRows = null,Object? agents = null,Object? selectedThreadId = freezed,Object? runtime = null,Object? sessionCost = freezed,Object? pendingInteractions = null,}) {
  return _then(HeaderView(
selectedRootRow: freezed == selectedRootRow ? _self.selectedRootRow : selectedRootRow // ignore: cast_nullable_to_non_nullable
as SessionDirectoryRow?,selectedProject: freezed == selectedProject ? _self.selectedProject : selectedProject // ignore: cast_nullable_to_non_nullable
as StudioProject?,selectedProjectId: freezed == selectedProjectId ? _self.selectedProjectId : selectedProjectId // ignore: cast_nullable_to_non_nullable
as String?,workspaceRows: null == workspaceRows ? _self.workspaceRows : workspaceRows // ignore: cast_nullable_to_non_nullable
as List<SessionDirectoryRow>,agents: null == agents ? _self.agents : agents // ignore: cast_nullable_to_non_nullable
as List<StudioAgentView>,selectedThreadId: freezed == selectedThreadId ? _self.selectedThreadId : selectedThreadId // ignore: cast_nullable_to_non_nullable
as String?,runtime: null == runtime ? _self.runtime : runtime // ignore: cast_nullable_to_non_nullable
as ThreadRuntimeView,sessionCost: freezed == sessionCost ? _self.sessionCost : sessionCost // ignore: cast_nullable_to_non_nullable
as SessionCostView?,pendingInteractions: null == pendingInteractions ? _self.pendingInteractions : pendingInteractions // ignore: cast_nullable_to_non_nullable
as List<PendingInteraction>,
  ));
}

}


/// Adds pattern-matching-related methods to [HeaderView].
extension HeaderViewPatterns on HeaderView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _HeaderView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _HeaderView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _HeaderView value)  $default,){
final _that = this;
switch (_that) {
case _HeaderView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _HeaderView value)?  $default,){
final _that = this;
switch (_that) {
case _HeaderView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionDirectoryRow? selectedRootRow,  StudioProject? selectedProject,  String? selectedProjectId,  List<SessionDirectoryRow> workspaceRows,  List<StudioAgentView> agents,  String? selectedThreadId,  ThreadRuntimeView runtime,  SessionCostView? sessionCost,  List<PendingInteraction> pendingInteractions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _HeaderView() when $default != null:
return $default(_that.selectedRootRow,_that.selectedProject,_that.selectedProjectId,_that.workspaceRows,_that.agents,_that.selectedThreadId,_that.runtime,_that.sessionCost,_that.pendingInteractions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionDirectoryRow? selectedRootRow,  StudioProject? selectedProject,  String? selectedProjectId,  List<SessionDirectoryRow> workspaceRows,  List<StudioAgentView> agents,  String? selectedThreadId,  ThreadRuntimeView runtime,  SessionCostView? sessionCost,  List<PendingInteraction> pendingInteractions)  $default,) {final _that = this;
switch (_that) {
case _HeaderView():
return $default(_that.selectedRootRow,_that.selectedProject,_that.selectedProjectId,_that.workspaceRows,_that.agents,_that.selectedThreadId,_that.runtime,_that.sessionCost,_that.pendingInteractions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionDirectoryRow? selectedRootRow,  StudioProject? selectedProject,  String? selectedProjectId,  List<SessionDirectoryRow> workspaceRows,  List<StudioAgentView> agents,  String? selectedThreadId,  ThreadRuntimeView runtime,  SessionCostView? sessionCost,  List<PendingInteraction> pendingInteractions)?  $default,) {final _that = this;
switch (_that) {
case _HeaderView() when $default != null:
return $default(_that.selectedRootRow,_that.selectedProject,_that.selectedProjectId,_that.workspaceRows,_that.agents,_that.selectedThreadId,_that.runtime,_that.sessionCost,_that.pendingInteractions);case _:
  return null;

}
}

}

/// @nodoc


class _HeaderView implements HeaderView {
  const _HeaderView({required this.selectedRootRow, required this.selectedProject, required this.selectedProjectId, required  List<SessionDirectoryRow> workspaceRows, required  List<StudioAgentView> agents, required this.selectedThreadId, required this.runtime, required this.sessionCost, required  List<PendingInteraction> pendingInteractions}): _workspaceRows = workspaceRows,_agents = agents,_pendingInteractions = pendingInteractions;


@override final  SessionDirectoryRow? selectedRootRow;
@override final  StudioProject? selectedProject;
@override final  String? selectedProjectId;
 final  List<SessionDirectoryRow> _workspaceRows;
@override List<SessionDirectoryRow> get workspaceRows {
  if (_workspaceRows is EqualUnmodifiableListView) return _workspaceRows;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_workspaceRows);
}

 final  List<StudioAgentView> _agents;
@override List<StudioAgentView> get agents {
  if (_agents is EqualUnmodifiableListView) return _agents;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_agents);
}

@override final  String? selectedThreadId;
@override final  ThreadRuntimeView runtime;
@override final  SessionCostView? sessionCost;
 final  List<PendingInteraction> _pendingInteractions;
@override List<PendingInteraction> get pendingInteractions {
  if (_pendingInteractions is EqualUnmodifiableListView) return _pendingInteractions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_pendingInteractions);
}


/// Create a copy of HeaderView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$HeaderViewCopyWith<_HeaderView> get copyWith => __$HeaderViewCopyWithImpl<_HeaderView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _HeaderView&&(identical(other.selectedRootRow, selectedRootRow) || other.selectedRootRow == selectedRootRow)&&(identical(other.selectedProject, selectedProject) || other.selectedProject == selectedProject)&&(identical(other.selectedProjectId, selectedProjectId) || other.selectedProjectId == selectedProjectId)&&const DeepCollectionEquality().equals(other.workspaceRows, _workspaceRows)&&const DeepCollectionEquality().equals(other.agents, _agents)&&(identical(other.selectedThreadId, selectedThreadId) || other.selectedThreadId == selectedThreadId)&&(identical(other.runtime, runtime) || other.runtime == runtime)&&(identical(other.sessionCost, sessionCost) || other.sessionCost == sessionCost)&&const DeepCollectionEquality().equals(other.pendingInteractions, _pendingInteractions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,selectedRootRow,selectedProject,selectedProjectId,const DeepCollectionEquality().hash(_workspaceRows),const DeepCollectionEquality().hash(_agents),selectedThreadId,runtime,sessionCost,const DeepCollectionEquality().hash(_pendingInteractions));
}

@override
String toString() {
    return 'HeaderView(selectedRootRow: $selectedRootRow, selectedProject: $selectedProject, selectedProjectId: $selectedProjectId, workspaceRows: $workspaceRows, agents: $agents, selectedThreadId: $selectedThreadId, runtime: $runtime, sessionCost: $sessionCost, pendingInteractions: $pendingInteractions)';
}


}

/// @nodoc
abstract mixin class _$HeaderViewCopyWith<$Res> implements $HeaderViewCopyWith<$Res> {
  factory _$HeaderViewCopyWith(_HeaderView value, $Res Function(_HeaderView) _then) = __$HeaderViewCopyWithImpl;
@override @useResult
$Res call({
 SessionDirectoryRow? selectedRootRow, StudioProject? selectedProject, String? selectedProjectId, List<SessionDirectoryRow> workspaceRows, List<StudioAgentView> agents, String? selectedThreadId, ThreadRuntimeView runtime, SessionCostView? sessionCost, List<PendingInteraction> pendingInteractions
});




}
/// @nodoc
class __$HeaderViewCopyWithImpl<$Res>
    implements _$HeaderViewCopyWith<$Res> {
  __$HeaderViewCopyWithImpl(this._self, this._then);

  final _HeaderView _self;
  final $Res Function(_HeaderView) _then;

/// Create a copy of HeaderView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selectedRootRow = freezed,Object? selectedProject = freezed,Object? selectedProjectId = freezed,Object? workspaceRows = null,Object? agents = null,Object? selectedThreadId = freezed,Object? runtime = null,Object? sessionCost = freezed,Object? pendingInteractions = null,}) {
  return _then(_HeaderView(
selectedRootRow: freezed == selectedRootRow ? _self.selectedRootRow : selectedRootRow // ignore: cast_nullable_to_non_nullable
as SessionDirectoryRow?,selectedProject: freezed == selectedProject ? _self.selectedProject : selectedProject // ignore: cast_nullable_to_non_nullable
as StudioProject?,selectedProjectId: freezed == selectedProjectId ? _self.selectedProjectId : selectedProjectId // ignore: cast_nullable_to_non_nullable
as String?,workspaceRows: null == workspaceRows ? _self._workspaceRows : workspaceRows // ignore: cast_nullable_to_non_nullable
as List<SessionDirectoryRow>,agents: null == agents ? _self._agents : agents // ignore: cast_nullable_to_non_nullable
as List<StudioAgentView>,selectedThreadId: freezed == selectedThreadId ? _self.selectedThreadId : selectedThreadId // ignore: cast_nullable_to_non_nullable
as String?,runtime: null == runtime ? _self.runtime : runtime // ignore: cast_nullable_to_non_nullable
as ThreadRuntimeView,sessionCost: freezed == sessionCost ? _self.sessionCost : sessionCost // ignore: cast_nullable_to_non_nullable
as SessionCostView?,pendingInteractions: null == pendingInteractions ? _self._pendingInteractions : pendingInteractions // ignore: cast_nullable_to_non_nullable
as List<PendingInteraction>,
  ));
}


}

/// @nodoc
mixin _$StatusBarView {

 SessionDirectoryRow get row; List<ModelSelectionAccount> get accounts; List<RoleSettingsView> get roles; bool get isBusy; ThreadModelRouteView? get modelRoute; WorkflowRunView? get workflowRun; List<String> get activeSkills; List<String> get activeMcpServers; List<String> get activeLspServers;
/// Create a copy of StatusBarView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatusBarViewCopyWith<StatusBarView> get copyWith => _$StatusBarViewCopyWithImpl<StatusBarView>(this as StatusBarView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatusBarView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatusBarView&&(identical(other.row, _this.row) || other.row == _this.row)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts)&&const DeepCollectionEquality().equals(other.roles, _this.roles)&&(identical(other.isBusy, _this.isBusy) || other.isBusy == _this.isBusy)&&(identical(other.modelRoute, _this.modelRoute) || other.modelRoute == _this.modelRoute)&&(identical(other.workflowRun, _this.workflowRun) || other.workflowRun == _this.workflowRun)&&const DeepCollectionEquality().equals(other.activeSkills, _this.activeSkills)&&const DeepCollectionEquality().equals(other.activeMcpServers, _this.activeMcpServers)&&const DeepCollectionEquality().equals(other.activeLspServers, _this.activeLspServers));
}


@override
int get hashCode {
  final _this = this as StatusBarView;
  return Object.hash(runtimeType,_this.row,const DeepCollectionEquality().hash(_this.accounts),const DeepCollectionEquality().hash(_this.roles),_this.isBusy,_this.modelRoute,_this.workflowRun,const DeepCollectionEquality().hash(_this.activeSkills),const DeepCollectionEquality().hash(_this.activeMcpServers),const DeepCollectionEquality().hash(_this.activeLspServers));
}

@override
String toString() {
  final _this = this as StatusBarView;
  return 'StatusBarView(row: ${_this.row}, accounts: ${_this.accounts}, roles: ${_this.roles}, isBusy: ${_this.isBusy}, modelRoute: ${_this.modelRoute}, workflowRun: ${_this.workflowRun}, activeSkills: ${_this.activeSkills}, activeMcpServers: ${_this.activeMcpServers}, activeLspServers: ${_this.activeLspServers})';
}


}

/// @nodoc
abstract mixin class $StatusBarViewCopyWith<$Res>  {
  factory $StatusBarViewCopyWith(StatusBarView value, $Res Function(StatusBarView) _then) = _$StatusBarViewCopyWithImpl;
@useResult
$Res call({
 SessionDirectoryRow row, List<ModelSelectionAccount> accounts, List<RoleSettingsView> roles, bool isBusy, ThreadModelRouteView? modelRoute, WorkflowRunView? workflowRun, List<String> activeSkills, List<String> activeMcpServers, List<String> activeLspServers
});




}
/// @nodoc
class _$StatusBarViewCopyWithImpl<$Res>
    implements $StatusBarViewCopyWith<$Res> {
  _$StatusBarViewCopyWithImpl(this._self, this._then);

  final StatusBarView _self;
  final $Res Function(StatusBarView) _then;

/// Create a copy of StatusBarView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? row = null,Object? accounts = null,Object? roles = null,Object? isBusy = null,Object? modelRoute = freezed,Object? workflowRun = freezed,Object? activeSkills = null,Object? activeMcpServers = null,Object? activeLspServers = null,}) {
  return _then(StatusBarView(
row: null == row ? _self.row : row // ignore: cast_nullable_to_non_nullable
as SessionDirectoryRow,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionAccount>,roles: null == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as List<RoleSettingsView>,isBusy: null == isBusy ? _self.isBusy : isBusy // ignore: cast_nullable_to_non_nullable
as bool,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as ThreadModelRouteView?,workflowRun: freezed == workflowRun ? _self.workflowRun : workflowRun // ignore: cast_nullable_to_non_nullable
as WorkflowRunView?,activeSkills: null == activeSkills ? _self.activeSkills : activeSkills // ignore: cast_nullable_to_non_nullable
as List<String>,activeMcpServers: null == activeMcpServers ? _self.activeMcpServers : activeMcpServers // ignore: cast_nullable_to_non_nullable
as List<String>,activeLspServers: null == activeLspServers ? _self.activeLspServers : activeLspServers // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [StatusBarView].
extension StatusBarViewPatterns on StatusBarView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatusBarView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatusBarView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatusBarView value)  $default,){
final _that = this;
switch (_that) {
case _StatusBarView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatusBarView value)?  $default,){
final _that = this;
switch (_that) {
case _StatusBarView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionDirectoryRow row,  List<ModelSelectionAccount> accounts,  List<RoleSettingsView> roles,  bool isBusy,  ThreadModelRouteView? modelRoute,  WorkflowRunView? workflowRun,  List<String> activeSkills,  List<String> activeMcpServers,  List<String> activeLspServers)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatusBarView() when $default != null:
return $default(_that.row,_that.accounts,_that.roles,_that.isBusy,_that.modelRoute,_that.workflowRun,_that.activeSkills,_that.activeMcpServers,_that.activeLspServers);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionDirectoryRow row,  List<ModelSelectionAccount> accounts,  List<RoleSettingsView> roles,  bool isBusy,  ThreadModelRouteView? modelRoute,  WorkflowRunView? workflowRun,  List<String> activeSkills,  List<String> activeMcpServers,  List<String> activeLspServers)  $default,) {final _that = this;
switch (_that) {
case _StatusBarView():
return $default(_that.row,_that.accounts,_that.roles,_that.isBusy,_that.modelRoute,_that.workflowRun,_that.activeSkills,_that.activeMcpServers,_that.activeLspServers);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionDirectoryRow row,  List<ModelSelectionAccount> accounts,  List<RoleSettingsView> roles,  bool isBusy,  ThreadModelRouteView? modelRoute,  WorkflowRunView? workflowRun,  List<String> activeSkills,  List<String> activeMcpServers,  List<String> activeLspServers)?  $default,) {final _that = this;
switch (_that) {
case _StatusBarView() when $default != null:
return $default(_that.row,_that.accounts,_that.roles,_that.isBusy,_that.modelRoute,_that.workflowRun,_that.activeSkills,_that.activeMcpServers,_that.activeLspServers);case _:
  return null;

}
}

}

/// @nodoc


class _StatusBarView extends StatusBarView {
  const _StatusBarView({required this.row, required  List<ModelSelectionAccount> accounts, required  List<RoleSettingsView> roles, required this.isBusy, this.modelRoute, this.workflowRun,  List<String> activeSkills = const <String>[],  List<String> activeMcpServers = const <String>[],  List<String> activeLspServers = const <String>[]}): _accounts = accounts,_roles = roles,_activeSkills = activeSkills,_activeMcpServers = activeMcpServers,_activeLspServers = activeLspServers,super._();


@override final  SessionDirectoryRow row;
 final  List<ModelSelectionAccount> _accounts;
@override List<ModelSelectionAccount> get accounts {
  if (_accounts is EqualUnmodifiableListView) return _accounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_accounts);
}

 final  List<RoleSettingsView> _roles;
@override List<RoleSettingsView> get roles {
  if (_roles is EqualUnmodifiableListView) return _roles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_roles);
}

@override final  bool isBusy;
@override final  ThreadModelRouteView? modelRoute;
@override final  WorkflowRunView? workflowRun;
 final  List<String> _activeSkills;
@override@JsonKey() List<String> get activeSkills {
  if (_activeSkills is EqualUnmodifiableListView) return _activeSkills;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeSkills);
}

 final  List<String> _activeMcpServers;
@override@JsonKey() List<String> get activeMcpServers {
  if (_activeMcpServers is EqualUnmodifiableListView) return _activeMcpServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeMcpServers);
}

 final  List<String> _activeLspServers;
@override@JsonKey() List<String> get activeLspServers {
  if (_activeLspServers is EqualUnmodifiableListView) return _activeLspServers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_activeLspServers);
}


/// Create a copy of StatusBarView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatusBarViewCopyWith<_StatusBarView> get copyWith => __$StatusBarViewCopyWithImpl<_StatusBarView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatusBarView&&(identical(other.row, row) || other.row == row)&&const DeepCollectionEquality().equals(other.accounts, _accounts)&&const DeepCollectionEquality().equals(other.roles, _roles)&&(identical(other.isBusy, isBusy) || other.isBusy == isBusy)&&(identical(other.modelRoute, modelRoute) || other.modelRoute == modelRoute)&&(identical(other.workflowRun, workflowRun) || other.workflowRun == workflowRun)&&const DeepCollectionEquality().equals(other.activeSkills, _activeSkills)&&const DeepCollectionEquality().equals(other.activeMcpServers, _activeMcpServers)&&const DeepCollectionEquality().equals(other.activeLspServers, _activeLspServers));
}


@override
int get hashCode {
    return Object.hash(runtimeType,row,const DeepCollectionEquality().hash(_accounts),const DeepCollectionEquality().hash(_roles),isBusy,modelRoute,workflowRun,const DeepCollectionEquality().hash(_activeSkills),const DeepCollectionEquality().hash(_activeMcpServers),const DeepCollectionEquality().hash(_activeLspServers));
}

@override
String toString() {
    return 'StatusBarView(row: $row, accounts: $accounts, roles: $roles, isBusy: $isBusy, modelRoute: $modelRoute, workflowRun: $workflowRun, activeSkills: $activeSkills, activeMcpServers: $activeMcpServers, activeLspServers: $activeLspServers)';
}


}

/// @nodoc
abstract mixin class _$StatusBarViewCopyWith<$Res> implements $StatusBarViewCopyWith<$Res> {
  factory _$StatusBarViewCopyWith(_StatusBarView value, $Res Function(_StatusBarView) _then) = __$StatusBarViewCopyWithImpl;
@override @useResult
$Res call({
 SessionDirectoryRow row, List<ModelSelectionAccount> accounts, List<RoleSettingsView> roles, bool isBusy, ThreadModelRouteView? modelRoute, WorkflowRunView? workflowRun, List<String> activeSkills, List<String> activeMcpServers, List<String> activeLspServers
});




}
/// @nodoc
class __$StatusBarViewCopyWithImpl<$Res>
    implements _$StatusBarViewCopyWith<$Res> {
  __$StatusBarViewCopyWithImpl(this._self, this._then);

  final _StatusBarView _self;
  final $Res Function(_StatusBarView) _then;

/// Create a copy of StatusBarView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? row = null,Object? accounts = null,Object? roles = null,Object? isBusy = null,Object? modelRoute = freezed,Object? workflowRun = freezed,Object? activeSkills = null,Object? activeMcpServers = null,Object? activeLspServers = null,}) {
  return _then(_StatusBarView(
row: null == row ? _self.row : row // ignore: cast_nullable_to_non_nullable
as SessionDirectoryRow,accounts: null == accounts ? _self._accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionAccount>,roles: null == roles ? _self._roles : roles // ignore: cast_nullable_to_non_nullable
as List<RoleSettingsView>,isBusy: null == isBusy ? _self.isBusy : isBusy // ignore: cast_nullable_to_non_nullable
as bool,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as ThreadModelRouteView?,workflowRun: freezed == workflowRun ? _self.workflowRun : workflowRun // ignore: cast_nullable_to_non_nullable
as WorkflowRunView?,activeSkills: null == activeSkills ? _self._activeSkills : activeSkills // ignore: cast_nullable_to_non_nullable
as List<String>,activeMcpServers: null == activeMcpServers ? _self._activeMcpServers : activeMcpServers // ignore: cast_nullable_to_non_nullable
as List<String>,activeLspServers: null == activeLspServers ? _self._activeLspServers : activeLspServers // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
