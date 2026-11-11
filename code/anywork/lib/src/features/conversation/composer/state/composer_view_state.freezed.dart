// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'composer_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ComposerTarget {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ComposerTarget);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ComposerTarget()';
}


}

/// @nodoc
class $ComposerTargetCopyWith<$Res>  {
$ComposerTargetCopyWith(ComposerTarget _, $Res Function(ComposerTarget) __);
}


/// Adds pattern-matching-related methods to [ComposerTarget].
extension ComposerTargetPatterns on ComposerTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadComposerTarget value)?  thread,TResult Function( StartComposerTarget value)?  start,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadComposerTarget() when thread != null:
return thread(_that);case StartComposerTarget() when start != null:
return start(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadComposerTarget value)  thread,required TResult Function( StartComposerTarget value)  start,}){
final _that = this;
switch (_that) {
case ThreadComposerTarget():
return thread(_that);case StartComposerTarget():
return start(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadComposerTarget value)?  thread,TResult? Function( StartComposerTarget value)?  start,}){
final _that = this;
switch (_that) {
case ThreadComposerTarget() when thread != null:
return thread(_that);case StartComposerTarget() when start != null:
return start(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String threadId)?  thread,TResult Function( String workspaceId)?  start,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadComposerTarget() when thread != null:
return thread(_that.threadId);case StartComposerTarget() when start != null:
return start(_that.workspaceId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String threadId)  thread,required TResult Function( String workspaceId)  start,}) {final _that = this;
switch (_that) {
case ThreadComposerTarget():
return thread(_that.threadId);case StartComposerTarget():
return start(_that.workspaceId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String threadId)?  thread,TResult? Function( String workspaceId)?  start,}) {final _that = this;
switch (_that) {
case ThreadComposerTarget() when thread != null:
return thread(_that.threadId);case StartComposerTarget() when start != null:
return start(_that.workspaceId);case _:
  return null;

}
}

}

/// @nodoc


class ThreadComposerTarget implements ComposerTarget {
  const ThreadComposerTarget({required this.threadId});


 final  String threadId;

/// Create a copy of ComposerTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadComposerTargetCopyWith<ThreadComposerTarget> get copyWith => _$ThreadComposerTargetCopyWithImpl<ThreadComposerTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadComposerTarget&&(identical(other.threadId, threadId) || other.threadId == threadId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId);
}

@override
String toString() {
    return 'ComposerTarget.thread(threadId: $threadId)';
}


}

/// @nodoc
abstract mixin class $ThreadComposerTargetCopyWith<$Res> implements $ComposerTargetCopyWith<$Res> {
  factory $ThreadComposerTargetCopyWith(ThreadComposerTarget value, $Res Function(ThreadComposerTarget) _then) = _$ThreadComposerTargetCopyWithImpl;
@useResult
$Res call({
 String threadId
});




}
/// @nodoc
class _$ThreadComposerTargetCopyWithImpl<$Res>
    implements $ThreadComposerTargetCopyWith<$Res> {
  _$ThreadComposerTargetCopyWithImpl(this._self, this._then);

  final ThreadComposerTarget _self;
  final $Res Function(ThreadComposerTarget) _then;

/// Create a copy of ComposerTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,}) {
  return _then(ThreadComposerTarget(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class StartComposerTarget implements ComposerTarget {
  const StartComposerTarget({required this.workspaceId});


 final  String workspaceId;

/// Create a copy of ComposerTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartComposerTargetCopyWith<StartComposerTarget> get copyWith => _$StartComposerTargetCopyWithImpl<StartComposerTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartComposerTarget&&(identical(other.workspaceId, workspaceId) || other.workspaceId == workspaceId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspaceId);
}

@override
String toString() {
    return 'ComposerTarget.start(workspaceId: $workspaceId)';
}


}

/// @nodoc
abstract mixin class $StartComposerTargetCopyWith<$Res> implements $ComposerTargetCopyWith<$Res> {
  factory $StartComposerTargetCopyWith(StartComposerTarget value, $Res Function(StartComposerTarget) _then) = _$StartComposerTargetCopyWithImpl;
@useResult
$Res call({
 String workspaceId
});




}
/// @nodoc
class _$StartComposerTargetCopyWithImpl<$Res>
    implements $StartComposerTargetCopyWith<$Res> {
  _$StartComposerTargetCopyWithImpl(this._self, this._then);

  final StartComposerTarget _self;
  final $Res Function(StartComposerTarget) _then;

/// Create a copy of ComposerTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? workspaceId = null,}) {
  return _then(StartComposerTarget(
workspaceId: null == workspaceId ? _self.workspaceId : workspaceId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ComposerViewState {

 ComposerInputState get input; ComposerDockViewState? get thread; StartPageComposerViewState? get start; List<ComposerSubmission> get submissions; Set<String> get submissionOperations; Map<String, Object> get submissionFailures; Object? get actionFailure; List<StudioProject> get projects; DelegationSettingsView? get delegation; ThreadModeCatalogView get modeCatalog; bool get standalonePreparing;
/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComposerViewStateCopyWith<ComposerViewState> get copyWith => _$ComposerViewStateCopyWithImpl<ComposerViewState>(this as ComposerViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ComposerViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComposerViewState&&(identical(other.input, _this.input) || other.input == _this.input)&&(identical(other.thread, _this.thread) || other.thread == _this.thread)&&(identical(other.start, _this.start) || other.start == _this.start)&&const DeepCollectionEquality().equals(other.submissions, _this.submissions)&&const DeepCollectionEquality().equals(other.submissionOperations, _this.submissionOperations)&&const DeepCollectionEquality().equals(other.submissionFailures, _this.submissionFailures)&&const DeepCollectionEquality().equals(other.actionFailure, _this.actionFailure)&&const DeepCollectionEquality().equals(other.projects, _this.projects)&&(identical(other.delegation, _this.delegation) || other.delegation == _this.delegation)&&(identical(other.modeCatalog, _this.modeCatalog) || other.modeCatalog == _this.modeCatalog)&&(identical(other.standalonePreparing, _this.standalonePreparing) || other.standalonePreparing == _this.standalonePreparing));
}


@override
int get hashCode {
  final _this = this as ComposerViewState;
  return Object.hash(runtimeType,_this.input,_this.thread,_this.start,const DeepCollectionEquality().hash(_this.submissions),const DeepCollectionEquality().hash(_this.submissionOperations),const DeepCollectionEquality().hash(_this.submissionFailures),const DeepCollectionEquality().hash(_this.actionFailure),const DeepCollectionEquality().hash(_this.projects),_this.delegation,_this.modeCatalog,_this.standalonePreparing);
}

@override
String toString() {
  final _this = this as ComposerViewState;
  return 'ComposerViewState(input: ${_this.input}, thread: ${_this.thread}, start: ${_this.start}, submissions: ${_this.submissions}, submissionOperations: ${_this.submissionOperations}, submissionFailures: ${_this.submissionFailures}, actionFailure: ${_this.actionFailure}, projects: ${_this.projects}, delegation: ${_this.delegation}, modeCatalog: ${_this.modeCatalog}, standalonePreparing: ${_this.standalonePreparing})';
}


}

/// @nodoc
abstract mixin class $ComposerViewStateCopyWith<$Res>  {
  factory $ComposerViewStateCopyWith(ComposerViewState value, $Res Function(ComposerViewState) _then) = _$ComposerViewStateCopyWithImpl;
@useResult
$Res call({
 ComposerInputState input, ComposerDockViewState? thread, StartPageComposerViewState? start, List<ComposerSubmission> submissions, Set<String> submissionOperations, Map<String, Object> submissionFailures, Object? actionFailure, List<StudioProject> projects, DelegationSettingsView? delegation, ThreadModeCatalogView modeCatalog, bool standalonePreparing
});


$ComposerDockViewStateCopyWith<$Res>? get thread;$StartPageComposerViewStateCopyWith<$Res>? get start;

}
/// @nodoc
class _$ComposerViewStateCopyWithImpl<$Res>
    implements $ComposerViewStateCopyWith<$Res> {
  _$ComposerViewStateCopyWithImpl(this._self, this._then);

  final ComposerViewState _self;
  final $Res Function(ComposerViewState) _then;

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? input = null,Object? thread = freezed,Object? start = freezed,Object? submissions = null,Object? submissionOperations = null,Object? submissionFailures = null,Object? actionFailure = freezed,Object? projects = null,Object? delegation = freezed,Object? modeCatalog = null,Object? standalonePreparing = null,}) {
  return _then(ComposerViewState(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as ComposerInputState,thread: freezed == thread ? _self.thread : thread // ignore: cast_nullable_to_non_nullable
as ComposerDockViewState?,start: freezed == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as StartPageComposerViewState?,submissions: null == submissions ? _self.submissions : submissions // ignore: cast_nullable_to_non_nullable
as List<ComposerSubmission>,submissionOperations: null == submissionOperations ? _self.submissionOperations : submissionOperations // ignore: cast_nullable_to_non_nullable
as Set<String>,submissionFailures: null == submissionFailures ? _self.submissionFailures : submissionFailures // ignore: cast_nullable_to_non_nullable
as Map<String, Object>,actionFailure: freezed == actionFailure ? _self.actionFailure : actionFailure ,projects: null == projects ? _self.projects : projects // ignore: cast_nullable_to_non_nullable
as List<StudioProject>,delegation: freezed == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettingsView?,modeCatalog: null == modeCatalog ? _self.modeCatalog : modeCatalog // ignore: cast_nullable_to_non_nullable
as ThreadModeCatalogView,standalonePreparing: null == standalonePreparing ? _self.standalonePreparing : standalonePreparing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerDockViewStateCopyWith<$Res>? get thread {
    if (_self.thread == null) {
    return null;
  }

  return $ComposerDockViewStateCopyWith<$Res>(_self.thread!, (value) {
    return _then(_self.copyWith(thread: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartPageComposerViewStateCopyWith<$Res>? get start {
    if (_self.start == null) {
    return null;
  }

  return $StartPageComposerViewStateCopyWith<$Res>(_self.start!, (value) {
    return _then(_self.copyWith(start: value));
  });
}
}


/// Adds pattern-matching-related methods to [ComposerViewState].
extension ComposerViewStatePatterns on ComposerViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ComposerViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ComposerViewState value)  $default,){
final _that = this;
switch (_that) {
case _ComposerViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ComposerViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ComposerInputState input,  ComposerDockViewState? thread,  StartPageComposerViewState? start,  List<ComposerSubmission> submissions,  Set<String> submissionOperations,  Map<String, Object> submissionFailures,  Object? actionFailure,  List<StudioProject> projects,  DelegationSettingsView? delegation,  ThreadModeCatalogView modeCatalog,  bool standalonePreparing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
return $default(_that.input,_that.thread,_that.start,_that.submissions,_that.submissionOperations,_that.submissionFailures,_that.actionFailure,_that.projects,_that.delegation,_that.modeCatalog,_that.standalonePreparing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ComposerInputState input,  ComposerDockViewState? thread,  StartPageComposerViewState? start,  List<ComposerSubmission> submissions,  Set<String> submissionOperations,  Map<String, Object> submissionFailures,  Object? actionFailure,  List<StudioProject> projects,  DelegationSettingsView? delegation,  ThreadModeCatalogView modeCatalog,  bool standalonePreparing)  $default,) {final _that = this;
switch (_that) {
case _ComposerViewState():
return $default(_that.input,_that.thread,_that.start,_that.submissions,_that.submissionOperations,_that.submissionFailures,_that.actionFailure,_that.projects,_that.delegation,_that.modeCatalog,_that.standalonePreparing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ComposerInputState input,  ComposerDockViewState? thread,  StartPageComposerViewState? start,  List<ComposerSubmission> submissions,  Set<String> submissionOperations,  Map<String, Object> submissionFailures,  Object? actionFailure,  List<StudioProject> projects,  DelegationSettingsView? delegation,  ThreadModeCatalogView modeCatalog,  bool standalonePreparing)?  $default,) {final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
return $default(_that.input,_that.thread,_that.start,_that.submissions,_that.submissionOperations,_that.submissionFailures,_that.actionFailure,_that.projects,_that.delegation,_that.modeCatalog,_that.standalonePreparing);case _:
  return null;

}
}

}

/// @nodoc


class _ComposerViewState implements ComposerViewState {
  const _ComposerViewState({required this.input, this.thread, this.start,  List<ComposerSubmission> submissions = const [],  Set<String> submissionOperations = const {},  Map<String, Object> submissionFailures = const {}, this.actionFailure,  List<StudioProject> projects = const [], this.delegation, this.modeCatalog = const ThreadModeCatalogView(), this.standalonePreparing = false}): _submissions = submissions,_submissionOperations = submissionOperations,_submissionFailures = submissionFailures,_projects = projects;


@override final  ComposerInputState input;
@override final  ComposerDockViewState? thread;
@override final  StartPageComposerViewState? start;
 final  List<ComposerSubmission> _submissions;
@override@JsonKey() List<ComposerSubmission> get submissions {
  if (_submissions is EqualUnmodifiableListView) return _submissions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_submissions);
}

 final  Set<String> _submissionOperations;
@override@JsonKey() Set<String> get submissionOperations {
  if (_submissionOperations is EqualUnmodifiableSetView) return _submissionOperations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_submissionOperations);
}

 final  Map<String, Object> _submissionFailures;
@override@JsonKey() Map<String, Object> get submissionFailures {
  if (_submissionFailures is EqualUnmodifiableMapView) return _submissionFailures;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_submissionFailures);
}

@override final  Object? actionFailure;
 final  List<StudioProject> _projects;
@override@JsonKey() List<StudioProject> get projects {
  if (_projects is EqualUnmodifiableListView) return _projects;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_projects);
}

@override final  DelegationSettingsView? delegation;
@override@JsonKey() final  ThreadModeCatalogView modeCatalog;
@override@JsonKey() final  bool standalonePreparing;

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ComposerViewStateCopyWith<_ComposerViewState> get copyWith => __$ComposerViewStateCopyWithImpl<_ComposerViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ComposerViewState&&(identical(other.input, input) || other.input == input)&&(identical(other.thread, thread) || other.thread == thread)&&(identical(other.start, start) || other.start == start)&&const DeepCollectionEquality().equals(other.submissions, _submissions)&&const DeepCollectionEquality().equals(other.submissionOperations, _submissionOperations)&&const DeepCollectionEquality().equals(other.submissionFailures, _submissionFailures)&&const DeepCollectionEquality().equals(other.actionFailure, actionFailure)&&const DeepCollectionEquality().equals(other.projects, _projects)&&(identical(other.delegation, delegation) || other.delegation == delegation)&&(identical(other.modeCatalog, modeCatalog) || other.modeCatalog == modeCatalog)&&(identical(other.standalonePreparing, standalonePreparing) || other.standalonePreparing == standalonePreparing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,input,thread,start,const DeepCollectionEquality().hash(_submissions),const DeepCollectionEquality().hash(_submissionOperations),const DeepCollectionEquality().hash(_submissionFailures),const DeepCollectionEquality().hash(actionFailure),const DeepCollectionEquality().hash(_projects),delegation,modeCatalog,standalonePreparing);
}

@override
String toString() {
    return 'ComposerViewState(input: $input, thread: $thread, start: $start, submissions: $submissions, submissionOperations: $submissionOperations, submissionFailures: $submissionFailures, actionFailure: $actionFailure, projects: $projects, delegation: $delegation, modeCatalog: $modeCatalog, standalonePreparing: $standalonePreparing)';
}


}

/// @nodoc
abstract mixin class _$ComposerViewStateCopyWith<$Res> implements $ComposerViewStateCopyWith<$Res> {
  factory _$ComposerViewStateCopyWith(_ComposerViewState value, $Res Function(_ComposerViewState) _then) = __$ComposerViewStateCopyWithImpl;
@override @useResult
$Res call({
 ComposerInputState input, ComposerDockViewState? thread, StartPageComposerViewState? start, List<ComposerSubmission> submissions, Set<String> submissionOperations, Map<String, Object> submissionFailures, Object? actionFailure, List<StudioProject> projects, DelegationSettingsView? delegation, ThreadModeCatalogView modeCatalog, bool standalonePreparing
});


@override $ComposerDockViewStateCopyWith<$Res>? get thread;@override $StartPageComposerViewStateCopyWith<$Res>? get start;

}
/// @nodoc
class __$ComposerViewStateCopyWithImpl<$Res>
    implements _$ComposerViewStateCopyWith<$Res> {
  __$ComposerViewStateCopyWithImpl(this._self, this._then);

  final _ComposerViewState _self;
  final $Res Function(_ComposerViewState) _then;

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? input = null,Object? thread = freezed,Object? start = freezed,Object? submissions = null,Object? submissionOperations = null,Object? submissionFailures = null,Object? actionFailure = freezed,Object? projects = null,Object? delegation = freezed,Object? modeCatalog = null,Object? standalonePreparing = null,}) {
  return _then(_ComposerViewState(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as ComposerInputState,thread: freezed == thread ? _self.thread : thread // ignore: cast_nullable_to_non_nullable
as ComposerDockViewState?,start: freezed == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as StartPageComposerViewState?,submissions: null == submissions ? _self._submissions : submissions // ignore: cast_nullable_to_non_nullable
as List<ComposerSubmission>,submissionOperations: null == submissionOperations ? _self._submissionOperations : submissionOperations // ignore: cast_nullable_to_non_nullable
as Set<String>,submissionFailures: null == submissionFailures ? _self._submissionFailures : submissionFailures // ignore: cast_nullable_to_non_nullable
as Map<String, Object>,actionFailure: freezed == actionFailure ? _self.actionFailure : actionFailure ,projects: null == projects ? _self._projects : projects // ignore: cast_nullable_to_non_nullable
as List<StudioProject>,delegation: freezed == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as DelegationSettingsView?,modeCatalog: null == modeCatalog ? _self.modeCatalog : modeCatalog // ignore: cast_nullable_to_non_nullable
as ThreadModeCatalogView,standalonePreparing: null == standalonePreparing ? _self.standalonePreparing : standalonePreparing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerDockViewStateCopyWith<$Res>? get thread {
    if (_self.thread == null) {
    return null;
  }

  return $ComposerDockViewStateCopyWith<$Res>(_self.thread!, (value) {
    return _then(_self.copyWith(thread: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartPageComposerViewStateCopyWith<$Res>? get start {
    if (_self.start == null) {
    return null;
  }

  return $StartPageComposerViewStateCopyWith<$Res>(_self.start!, (value) {
    return _then(_self.copyWith(start: value));
  });
}
}

/// @nodoc
mixin _$StartPageComposerViewState {

 StudioProject? get project; List<ModelSelectionAccount> get accounts; List<ModeModelRouteView> get modeModelRoutes; bool get settingsLoaded;/// Recovery 已判为访问受阻时不允许编辑；执行阻塞只禁提交。
 bool get canEdit; bool get canSubmit;/// 同目标规则选出的最高优先级执行阻塞 issue；`null` 表示没有。
 StudioRecoveryIssue? get recoveryIssue; Map<String, CommandStatus> get commands; List<ComposerTargetDiagnostic> get diagnostics; ThreadModeCatalogView? get modeCatalog; StartSessionDraft get sessionDraft; ComposerThreadState get composer; ComposerTargetDiagnostic? get targetDiagnostic;
/// Create a copy of StartPageComposerViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartPageComposerViewStateCopyWith<StartPageComposerViewState> get copyWith => _$StartPageComposerViewStateCopyWithImpl<StartPageComposerViewState>(this as StartPageComposerViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartPageComposerViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartPageComposerViewState&&(identical(other.project, _this.project) || other.project == _this.project)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts)&&const DeepCollectionEquality().equals(other.modeModelRoutes, _this.modeModelRoutes)&&(identical(other.settingsLoaded, _this.settingsLoaded) || other.settingsLoaded == _this.settingsLoaded)&&(identical(other.canEdit, _this.canEdit) || other.canEdit == _this.canEdit)&&(identical(other.canSubmit, _this.canSubmit) || other.canSubmit == _this.canSubmit)&&(identical(other.recoveryIssue, _this.recoveryIssue) || other.recoveryIssue == _this.recoveryIssue)&&const DeepCollectionEquality().equals(other.commands, _this.commands)&&const DeepCollectionEquality().equals(other.diagnostics, _this.diagnostics)&&(identical(other.modeCatalog, _this.modeCatalog) || other.modeCatalog == _this.modeCatalog)&&(identical(other.sessionDraft, _this.sessionDraft) || other.sessionDraft == _this.sessionDraft)&&(identical(other.composer, _this.composer) || other.composer == _this.composer)&&(identical(other.targetDiagnostic, _this.targetDiagnostic) || other.targetDiagnostic == _this.targetDiagnostic));
}


@override
int get hashCode {
  final _this = this as StartPageComposerViewState;
  return Object.hash(runtimeType,_this.project,const DeepCollectionEquality().hash(_this.accounts),const DeepCollectionEquality().hash(_this.modeModelRoutes),_this.settingsLoaded,_this.canEdit,_this.canSubmit,_this.recoveryIssue,const DeepCollectionEquality().hash(_this.commands),const DeepCollectionEquality().hash(_this.diagnostics),_this.modeCatalog,_this.sessionDraft,_this.composer,_this.targetDiagnostic);
}

@override
String toString() {
  final _this = this as StartPageComposerViewState;
  return 'StartPageComposerViewState(project: ${_this.project}, accounts: ${_this.accounts}, modeModelRoutes: ${_this.modeModelRoutes}, settingsLoaded: ${_this.settingsLoaded}, canEdit: ${_this.canEdit}, canSubmit: ${_this.canSubmit}, recoveryIssue: ${_this.recoveryIssue}, commands: ${_this.commands}, diagnostics: ${_this.diagnostics}, modeCatalog: ${_this.modeCatalog}, sessionDraft: ${_this.sessionDraft}, composer: ${_this.composer}, targetDiagnostic: ${_this.targetDiagnostic})';
}


}

/// @nodoc
abstract mixin class $StartPageComposerViewStateCopyWith<$Res>  {
  factory $StartPageComposerViewStateCopyWith(StartPageComposerViewState value, $Res Function(StartPageComposerViewState) _then) = _$StartPageComposerViewStateCopyWithImpl;
@useResult
$Res call({
 StudioProject? project, List<ModelSelectionAccount> accounts, List<ModeModelRouteView> modeModelRoutes, bool settingsLoaded, bool canEdit, bool canSubmit, StudioRecoveryIssue? recoveryIssue, Map<String, CommandStatus> commands, List<ComposerTargetDiagnostic> diagnostics, ThreadModeCatalogView? modeCatalog, StartSessionDraft sessionDraft, ComposerThreadState composer, ComposerTargetDiagnostic? targetDiagnostic
});




}
/// @nodoc
class _$StartPageComposerViewStateCopyWithImpl<$Res>
    implements $StartPageComposerViewStateCopyWith<$Res> {
  _$StartPageComposerViewStateCopyWithImpl(this._self, this._then);

  final StartPageComposerViewState _self;
  final $Res Function(StartPageComposerViewState) _then;

/// Create a copy of StartPageComposerViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? project = freezed,Object? accounts = null,Object? modeModelRoutes = null,Object? settingsLoaded = null,Object? canEdit = null,Object? canSubmit = null,Object? recoveryIssue = freezed,Object? commands = null,Object? diagnostics = null,Object? modeCatalog = freezed,Object? sessionDraft = null,Object? composer = null,Object? targetDiagnostic = freezed,}) {
  return _then(StartPageComposerViewState(
project: freezed == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as StudioProject?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionAccount>,modeModelRoutes: null == modeModelRoutes ? _self.modeModelRoutes : modeModelRoutes // ignore: cast_nullable_to_non_nullable
as List<ModeModelRouteView>,settingsLoaded: null == settingsLoaded ? _self.settingsLoaded : settingsLoaded // ignore: cast_nullable_to_non_nullable
as bool,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canSubmit: null == canSubmit ? _self.canSubmit : canSubmit // ignore: cast_nullable_to_non_nullable
as bool,recoveryIssue: freezed == recoveryIssue ? _self.recoveryIssue : recoveryIssue // ignore: cast_nullable_to_non_nullable
as StudioRecoveryIssue?,commands: null == commands ? _self.commands : commands // ignore: cast_nullable_to_non_nullable
as Map<String, CommandStatus>,diagnostics: null == diagnostics ? _self.diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<ComposerTargetDiagnostic>,modeCatalog: freezed == modeCatalog ? _self.modeCatalog : modeCatalog // ignore: cast_nullable_to_non_nullable
as ThreadModeCatalogView?,sessionDraft: null == sessionDraft ? _self.sessionDraft : sessionDraft // ignore: cast_nullable_to_non_nullable
as StartSessionDraft,composer: null == composer ? _self.composer : composer // ignore: cast_nullable_to_non_nullable
as ComposerThreadState,targetDiagnostic: freezed == targetDiagnostic ? _self.targetDiagnostic : targetDiagnostic // ignore: cast_nullable_to_non_nullable
as ComposerTargetDiagnostic?,
  ));
}

}


/// Adds pattern-matching-related methods to [StartPageComposerViewState].
extension StartPageComposerViewStatePatterns on StartPageComposerViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartPageComposerViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartPageComposerViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartPageComposerViewState value)  $default,){
final _that = this;
switch (_that) {
case _StartPageComposerViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartPageComposerViewState value)?  $default,){
final _that = this;
switch (_that) {
case _StartPageComposerViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StudioProject? project,  List<ModelSelectionAccount> accounts,  List<ModeModelRouteView> modeModelRoutes,  bool settingsLoaded,  bool canEdit,  bool canSubmit,  StudioRecoveryIssue? recoveryIssue,  Map<String, CommandStatus> commands,  List<ComposerTargetDiagnostic> diagnostics,  ThreadModeCatalogView? modeCatalog,  StartSessionDraft sessionDraft,  ComposerThreadState composer,  ComposerTargetDiagnostic? targetDiagnostic)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartPageComposerViewState() when $default != null:
return $default(_that.project,_that.accounts,_that.modeModelRoutes,_that.settingsLoaded,_that.canEdit,_that.canSubmit,_that.recoveryIssue,_that.commands,_that.diagnostics,_that.modeCatalog,_that.sessionDraft,_that.composer,_that.targetDiagnostic);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StudioProject? project,  List<ModelSelectionAccount> accounts,  List<ModeModelRouteView> modeModelRoutes,  bool settingsLoaded,  bool canEdit,  bool canSubmit,  StudioRecoveryIssue? recoveryIssue,  Map<String, CommandStatus> commands,  List<ComposerTargetDiagnostic> diagnostics,  ThreadModeCatalogView? modeCatalog,  StartSessionDraft sessionDraft,  ComposerThreadState composer,  ComposerTargetDiagnostic? targetDiagnostic)  $default,) {final _that = this;
switch (_that) {
case _StartPageComposerViewState():
return $default(_that.project,_that.accounts,_that.modeModelRoutes,_that.settingsLoaded,_that.canEdit,_that.canSubmit,_that.recoveryIssue,_that.commands,_that.diagnostics,_that.modeCatalog,_that.sessionDraft,_that.composer,_that.targetDiagnostic);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StudioProject? project,  List<ModelSelectionAccount> accounts,  List<ModeModelRouteView> modeModelRoutes,  bool settingsLoaded,  bool canEdit,  bool canSubmit,  StudioRecoveryIssue? recoveryIssue,  Map<String, CommandStatus> commands,  List<ComposerTargetDiagnostic> diagnostics,  ThreadModeCatalogView? modeCatalog,  StartSessionDraft sessionDraft,  ComposerThreadState composer,  ComposerTargetDiagnostic? targetDiagnostic)?  $default,) {final _that = this;
switch (_that) {
case _StartPageComposerViewState() when $default != null:
return $default(_that.project,_that.accounts,_that.modeModelRoutes,_that.settingsLoaded,_that.canEdit,_that.canSubmit,_that.recoveryIssue,_that.commands,_that.diagnostics,_that.modeCatalog,_that.sessionDraft,_that.composer,_that.targetDiagnostic);case _:
  return null;

}
}

}

/// @nodoc


class _StartPageComposerViewState extends StartPageComposerViewState {
  const _StartPageComposerViewState({required this.project, required  List<ModelSelectionAccount> accounts, required  List<ModeModelRouteView> modeModelRoutes, required this.settingsLoaded, required this.canEdit, required this.canSubmit, required this.recoveryIssue, required  Map<String, CommandStatus> commands, required  List<ComposerTargetDiagnostic> diagnostics, required this.modeCatalog, required this.sessionDraft, required this.composer, required this.targetDiagnostic}): _accounts = accounts,_modeModelRoutes = modeModelRoutes,_commands = commands,_diagnostics = diagnostics,super._();


@override final  StudioProject? project;
 final  List<ModelSelectionAccount> _accounts;
@override List<ModelSelectionAccount> get accounts {
  if (_accounts is EqualUnmodifiableListView) return _accounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_accounts);
}

 final  List<ModeModelRouteView> _modeModelRoutes;
@override List<ModeModelRouteView> get modeModelRoutes {
  if (_modeModelRoutes is EqualUnmodifiableListView) return _modeModelRoutes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modeModelRoutes);
}

@override final  bool settingsLoaded;
/// Recovery 已判为访问受阻时不允许编辑；执行阻塞只禁提交。
@override final  bool canEdit;
@override final  bool canSubmit;
/// 同目标规则选出的最高优先级执行阻塞 issue；`null` 表示没有。
@override final  StudioRecoveryIssue? recoveryIssue;
 final  Map<String, CommandStatus> _commands;
@override Map<String, CommandStatus> get commands {
  if (_commands is EqualUnmodifiableMapView) return _commands;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_commands);
}

 final  List<ComposerTargetDiagnostic> _diagnostics;
@override List<ComposerTargetDiagnostic> get diagnostics {
  if (_diagnostics is EqualUnmodifiableListView) return _diagnostics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_diagnostics);
}

@override final  ThreadModeCatalogView? modeCatalog;
@override final  StartSessionDraft sessionDraft;
@override final  ComposerThreadState composer;
@override final  ComposerTargetDiagnostic? targetDiagnostic;

/// Create a copy of StartPageComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartPageComposerViewStateCopyWith<_StartPageComposerViewState> get copyWith => __$StartPageComposerViewStateCopyWithImpl<_StartPageComposerViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartPageComposerViewState&&(identical(other.project, project) || other.project == project)&&const DeepCollectionEquality().equals(other.accounts, _accounts)&&const DeepCollectionEquality().equals(other.modeModelRoutes, _modeModelRoutes)&&(identical(other.settingsLoaded, settingsLoaded) || other.settingsLoaded == settingsLoaded)&&(identical(other.canEdit, canEdit) || other.canEdit == canEdit)&&(identical(other.canSubmit, canSubmit) || other.canSubmit == canSubmit)&&(identical(other.recoveryIssue, recoveryIssue) || other.recoveryIssue == recoveryIssue)&&const DeepCollectionEquality().equals(other.commands, _commands)&&const DeepCollectionEquality().equals(other.diagnostics, _diagnostics)&&(identical(other.modeCatalog, modeCatalog) || other.modeCatalog == modeCatalog)&&(identical(other.sessionDraft, sessionDraft) || other.sessionDraft == sessionDraft)&&(identical(other.composer, composer) || other.composer == composer)&&(identical(other.targetDiagnostic, targetDiagnostic) || other.targetDiagnostic == targetDiagnostic));
}


@override
int get hashCode {
    return Object.hash(runtimeType,project,const DeepCollectionEquality().hash(_accounts),const DeepCollectionEquality().hash(_modeModelRoutes),settingsLoaded,canEdit,canSubmit,recoveryIssue,const DeepCollectionEquality().hash(_commands),const DeepCollectionEquality().hash(_diagnostics),modeCatalog,sessionDraft,composer,targetDiagnostic);
}

@override
String toString() {
    return 'StartPageComposerViewState(project: $project, accounts: $accounts, modeModelRoutes: $modeModelRoutes, settingsLoaded: $settingsLoaded, canEdit: $canEdit, canSubmit: $canSubmit, recoveryIssue: $recoveryIssue, commands: $commands, diagnostics: $diagnostics, modeCatalog: $modeCatalog, sessionDraft: $sessionDraft, composer: $composer, targetDiagnostic: $targetDiagnostic)';
}


}

/// @nodoc
abstract mixin class _$StartPageComposerViewStateCopyWith<$Res> implements $StartPageComposerViewStateCopyWith<$Res> {
  factory _$StartPageComposerViewStateCopyWith(_StartPageComposerViewState value, $Res Function(_StartPageComposerViewState) _then) = __$StartPageComposerViewStateCopyWithImpl;
@override @useResult
$Res call({
 StudioProject? project, List<ModelSelectionAccount> accounts, List<ModeModelRouteView> modeModelRoutes, bool settingsLoaded, bool canEdit, bool canSubmit, StudioRecoveryIssue? recoveryIssue, Map<String, CommandStatus> commands, List<ComposerTargetDiagnostic> diagnostics, ThreadModeCatalogView? modeCatalog, StartSessionDraft sessionDraft, ComposerThreadState composer, ComposerTargetDiagnostic? targetDiagnostic
});




}
/// @nodoc
class __$StartPageComposerViewStateCopyWithImpl<$Res>
    implements _$StartPageComposerViewStateCopyWith<$Res> {
  __$StartPageComposerViewStateCopyWithImpl(this._self, this._then);

  final _StartPageComposerViewState _self;
  final $Res Function(_StartPageComposerViewState) _then;

/// Create a copy of StartPageComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? project = freezed,Object? accounts = null,Object? modeModelRoutes = null,Object? settingsLoaded = null,Object? canEdit = null,Object? canSubmit = null,Object? recoveryIssue = freezed,Object? commands = null,Object? diagnostics = null,Object? modeCatalog = freezed,Object? sessionDraft = null,Object? composer = null,Object? targetDiagnostic = freezed,}) {
  return _then(_StartPageComposerViewState(
project: freezed == project ? _self.project : project // ignore: cast_nullable_to_non_nullable
as StudioProject?,accounts: null == accounts ? _self._accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionAccount>,modeModelRoutes: null == modeModelRoutes ? _self._modeModelRoutes : modeModelRoutes // ignore: cast_nullable_to_non_nullable
as List<ModeModelRouteView>,settingsLoaded: null == settingsLoaded ? _self.settingsLoaded : settingsLoaded // ignore: cast_nullable_to_non_nullable
as bool,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canSubmit: null == canSubmit ? _self.canSubmit : canSubmit // ignore: cast_nullable_to_non_nullable
as bool,recoveryIssue: freezed == recoveryIssue ? _self.recoveryIssue : recoveryIssue // ignore: cast_nullable_to_non_nullable
as StudioRecoveryIssue?,commands: null == commands ? _self._commands : commands // ignore: cast_nullable_to_non_nullable
as Map<String, CommandStatus>,diagnostics: null == diagnostics ? _self._diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as List<ComposerTargetDiagnostic>,modeCatalog: freezed == modeCatalog ? _self.modeCatalog : modeCatalog // ignore: cast_nullable_to_non_nullable
as ThreadModeCatalogView?,sessionDraft: null == sessionDraft ? _self.sessionDraft : sessionDraft // ignore: cast_nullable_to_non_nullable
as StartSessionDraft,composer: null == composer ? _self.composer : composer // ignore: cast_nullable_to_non_nullable
as ComposerThreadState,targetDiagnostic: freezed == targetDiagnostic ? _self.targetDiagnostic : targetDiagnostic // ignore: cast_nullable_to_non_nullable
as ComposerTargetDiagnostic?,
  ));
}


}

/// @nodoc
mixin _$ComposerDockViewState {

 SessionDirectoryRow? get row; bool get hasSnapshot; int get revision; ComposerThreadState get composer; PendingInteraction? get activeInteraction; StudioTurnView? get turn; AgentExecutionView? get execution; ContinuationView? get continuation; CommandStatus? get stopCommand; CommandStatus? get continueCommand; int? get queuedStopStartedAtMs; bool get saveBlocked;/// 同一 Client 目标规则选出的最高优先级执行恢复阻塞。
 StudioRecoveryIssue? get recoveryIssue;/// 当前 Native 目录身份是否已永久封闭执行。
///
/// Closing/closed 时不显示执行入口，历史仍展示、草稿不清；
/// 独立会话快照中的 Core 资源关闭状态不参与此判定。
 bool get executionClosed; List<ChildInteractionSummary> get childInteractions; DomainSyncStatus? get childInteractionSync; Map<String, String> get childInteractionSources; ThreadModelRouteView? get modelRoute; ModelRouteDisplay? get routeDisplay; bool get routePending; String? get routeFailure; WorkflowRuntimeView? get workflow; List<ModelSelectionAccount> get accounts; bool get settingsLoaded; ComposerTargetDiagnostic? get targetDiagnostic; List<ComposerTargetDiagnostic> get additionalDiagnostics;
/// Create a copy of ComposerDockViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComposerDockViewStateCopyWith<ComposerDockViewState> get copyWith => _$ComposerDockViewStateCopyWithImpl<ComposerDockViewState>(this as ComposerDockViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ComposerDockViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComposerDockViewState&&(identical(other.row, _this.row) || other.row == _this.row)&&(identical(other.hasSnapshot, _this.hasSnapshot) || other.hasSnapshot == _this.hasSnapshot)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.composer, _this.composer) || other.composer == _this.composer)&&(identical(other.activeInteraction, _this.activeInteraction) || other.activeInteraction == _this.activeInteraction)&&(identical(other.turn, _this.turn) || other.turn == _this.turn)&&(identical(other.execution, _this.execution) || other.execution == _this.execution)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation)&&(identical(other.stopCommand, _this.stopCommand) || other.stopCommand == _this.stopCommand)&&(identical(other.continueCommand, _this.continueCommand) || other.continueCommand == _this.continueCommand)&&(identical(other.queuedStopStartedAtMs, _this.queuedStopStartedAtMs) || other.queuedStopStartedAtMs == _this.queuedStopStartedAtMs)&&(identical(other.saveBlocked, _this.saveBlocked) || other.saveBlocked == _this.saveBlocked)&&(identical(other.recoveryIssue, _this.recoveryIssue) || other.recoveryIssue == _this.recoveryIssue)&&(identical(other.executionClosed, _this.executionClosed) || other.executionClosed == _this.executionClosed)&&const DeepCollectionEquality().equals(other.childInteractions, _this.childInteractions)&&(identical(other.childInteractionSync, _this.childInteractionSync) || other.childInteractionSync == _this.childInteractionSync)&&const DeepCollectionEquality().equals(other.childInteractionSources, _this.childInteractionSources)&&(identical(other.modelRoute, _this.modelRoute) || other.modelRoute == _this.modelRoute)&&(identical(other.routeDisplay, _this.routeDisplay) || other.routeDisplay == _this.routeDisplay)&&(identical(other.routePending, _this.routePending) || other.routePending == _this.routePending)&&(identical(other.routeFailure, _this.routeFailure) || other.routeFailure == _this.routeFailure)&&(identical(other.workflow, _this.workflow) || other.workflow == _this.workflow)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts)&&(identical(other.settingsLoaded, _this.settingsLoaded) || other.settingsLoaded == _this.settingsLoaded)&&(identical(other.targetDiagnostic, _this.targetDiagnostic) || other.targetDiagnostic == _this.targetDiagnostic)&&const DeepCollectionEquality().equals(other.additionalDiagnostics, _this.additionalDiagnostics));
}


@override
int get hashCode {
  final _this = this as ComposerDockViewState;
  return Object.hashAll([runtimeType,_this.row,_this.hasSnapshot,_this.revision,_this.composer,_this.activeInteraction,_this.turn,_this.execution,_this.continuation,_this.stopCommand,_this.continueCommand,_this.queuedStopStartedAtMs,_this.saveBlocked,_this.recoveryIssue,_this.executionClosed,const DeepCollectionEquality().hash(_this.childInteractions),_this.childInteractionSync,const DeepCollectionEquality().hash(_this.childInteractionSources),_this.modelRoute,_this.routeDisplay,_this.routePending,_this.routeFailure,_this.workflow,const DeepCollectionEquality().hash(_this.accounts),_this.settingsLoaded,_this.targetDiagnostic,const DeepCollectionEquality().hash(_this.additionalDiagnostics)]);
}

@override
String toString() {
  final _this = this as ComposerDockViewState;
  return 'ComposerDockViewState(row: ${_this.row}, hasSnapshot: ${_this.hasSnapshot}, revision: ${_this.revision}, composer: ${_this.composer}, activeInteraction: ${_this.activeInteraction}, turn: ${_this.turn}, execution: ${_this.execution}, continuation: ${_this.continuation}, stopCommand: ${_this.stopCommand}, continueCommand: ${_this.continueCommand}, queuedStopStartedAtMs: ${_this.queuedStopStartedAtMs}, saveBlocked: ${_this.saveBlocked}, recoveryIssue: ${_this.recoveryIssue}, executionClosed: ${_this.executionClosed}, childInteractions: ${_this.childInteractions}, childInteractionSync: ${_this.childInteractionSync}, childInteractionSources: ${_this.childInteractionSources}, modelRoute: ${_this.modelRoute}, routeDisplay: ${_this.routeDisplay}, routePending: ${_this.routePending}, routeFailure: ${_this.routeFailure}, workflow: ${_this.workflow}, accounts: ${_this.accounts}, settingsLoaded: ${_this.settingsLoaded}, targetDiagnostic: ${_this.targetDiagnostic}, additionalDiagnostics: ${_this.additionalDiagnostics})';
}


}

/// @nodoc
abstract mixin class $ComposerDockViewStateCopyWith<$Res>  {
  factory $ComposerDockViewStateCopyWith(ComposerDockViewState value, $Res Function(ComposerDockViewState) _then) = _$ComposerDockViewStateCopyWithImpl;
@useResult
$Res call({
 SessionDirectoryRow? row, bool hasSnapshot, int revision, ComposerThreadState composer, PendingInteraction? activeInteraction, StudioTurnView? turn, AgentExecutionView? execution, ContinuationView? continuation, CommandStatus? stopCommand, CommandStatus? continueCommand, int? queuedStopStartedAtMs, bool saveBlocked, StudioRecoveryIssue? recoveryIssue, bool executionClosed, List<ChildInteractionSummary> childInteractions, DomainSyncStatus? childInteractionSync, Map<String, String> childInteractionSources, ThreadModelRouteView? modelRoute, ModelRouteDisplay? routeDisplay, bool routePending, String? routeFailure, WorkflowRuntimeView? workflow, List<ModelSelectionAccount> accounts, bool settingsLoaded, ComposerTargetDiagnostic? targetDiagnostic, List<ComposerTargetDiagnostic> additionalDiagnostics
});




}
/// @nodoc
class _$ComposerDockViewStateCopyWithImpl<$Res>
    implements $ComposerDockViewStateCopyWith<$Res> {
  _$ComposerDockViewStateCopyWithImpl(this._self, this._then);

  final ComposerDockViewState _self;
  final $Res Function(ComposerDockViewState) _then;

/// Create a copy of ComposerDockViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? row = freezed,Object? hasSnapshot = null,Object? revision = null,Object? composer = null,Object? activeInteraction = freezed,Object? turn = freezed,Object? execution = freezed,Object? continuation = freezed,Object? stopCommand = freezed,Object? continueCommand = freezed,Object? queuedStopStartedAtMs = freezed,Object? saveBlocked = null,Object? recoveryIssue = freezed,Object? executionClosed = null,Object? childInteractions = null,Object? childInteractionSync = freezed,Object? childInteractionSources = null,Object? modelRoute = freezed,Object? routeDisplay = freezed,Object? routePending = null,Object? routeFailure = freezed,Object? workflow = freezed,Object? accounts = null,Object? settingsLoaded = null,Object? targetDiagnostic = freezed,Object? additionalDiagnostics = null,}) {
  return _then(ComposerDockViewState(
row: freezed == row ? _self.row : row // ignore: cast_nullable_to_non_nullable
as SessionDirectoryRow?,hasSnapshot: null == hasSnapshot ? _self.hasSnapshot : hasSnapshot // ignore: cast_nullable_to_non_nullable
as bool,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,composer: null == composer ? _self.composer : composer // ignore: cast_nullable_to_non_nullable
as ComposerThreadState,activeInteraction: freezed == activeInteraction ? _self.activeInteraction : activeInteraction // ignore: cast_nullable_to_non_nullable
as PendingInteraction?,turn: freezed == turn ? _self.turn : turn // ignore: cast_nullable_to_non_nullable
as StudioTurnView?,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as AgentExecutionView?,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as ContinuationView?,stopCommand: freezed == stopCommand ? _self.stopCommand : stopCommand // ignore: cast_nullable_to_non_nullable
as CommandStatus?,continueCommand: freezed == continueCommand ? _self.continueCommand : continueCommand // ignore: cast_nullable_to_non_nullable
as CommandStatus?,queuedStopStartedAtMs: freezed == queuedStopStartedAtMs ? _self.queuedStopStartedAtMs : queuedStopStartedAtMs // ignore: cast_nullable_to_non_nullable
as int?,saveBlocked: null == saveBlocked ? _self.saveBlocked : saveBlocked // ignore: cast_nullable_to_non_nullable
as bool,recoveryIssue: freezed == recoveryIssue ? _self.recoveryIssue : recoveryIssue // ignore: cast_nullable_to_non_nullable
as StudioRecoveryIssue?,executionClosed: null == executionClosed ? _self.executionClosed : executionClosed // ignore: cast_nullable_to_non_nullable
as bool,childInteractions: null == childInteractions ? _self.childInteractions : childInteractions // ignore: cast_nullable_to_non_nullable
as List<ChildInteractionSummary>,childInteractionSync: freezed == childInteractionSync ? _self.childInteractionSync : childInteractionSync // ignore: cast_nullable_to_non_nullable
as DomainSyncStatus?,childInteractionSources: null == childInteractionSources ? _self.childInteractionSources : childInteractionSources // ignore: cast_nullable_to_non_nullable
as Map<String, String>,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as ThreadModelRouteView?,routeDisplay: freezed == routeDisplay ? _self.routeDisplay : routeDisplay // ignore: cast_nullable_to_non_nullable
as ModelRouteDisplay?,routePending: null == routePending ? _self.routePending : routePending // ignore: cast_nullable_to_non_nullable
as bool,routeFailure: freezed == routeFailure ? _self.routeFailure : routeFailure // ignore: cast_nullable_to_non_nullable
as String?,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowRuntimeView?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionAccount>,settingsLoaded: null == settingsLoaded ? _self.settingsLoaded : settingsLoaded // ignore: cast_nullable_to_non_nullable
as bool,targetDiagnostic: freezed == targetDiagnostic ? _self.targetDiagnostic : targetDiagnostic // ignore: cast_nullable_to_non_nullable
as ComposerTargetDiagnostic?,additionalDiagnostics: null == additionalDiagnostics ? _self.additionalDiagnostics : additionalDiagnostics // ignore: cast_nullable_to_non_nullable
as List<ComposerTargetDiagnostic>,
  ));
}

}


/// Adds pattern-matching-related methods to [ComposerDockViewState].
extension ComposerDockViewStatePatterns on ComposerDockViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ComposerDockViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ComposerDockViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ComposerDockViewState value)  $default,){
final _that = this;
switch (_that) {
case _ComposerDockViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ComposerDockViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ComposerDockViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SessionDirectoryRow? row,  bool hasSnapshot,  int revision,  ComposerThreadState composer,  PendingInteraction? activeInteraction,  StudioTurnView? turn,  AgentExecutionView? execution,  ContinuationView? continuation,  CommandStatus? stopCommand,  CommandStatus? continueCommand,  int? queuedStopStartedAtMs,  bool saveBlocked,  StudioRecoveryIssue? recoveryIssue,  bool executionClosed,  List<ChildInteractionSummary> childInteractions,  DomainSyncStatus? childInteractionSync,  Map<String, String> childInteractionSources,  ThreadModelRouteView? modelRoute,  ModelRouteDisplay? routeDisplay,  bool routePending,  String? routeFailure,  WorkflowRuntimeView? workflow,  List<ModelSelectionAccount> accounts,  bool settingsLoaded,  ComposerTargetDiagnostic? targetDiagnostic,  List<ComposerTargetDiagnostic> additionalDiagnostics)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ComposerDockViewState() when $default != null:
return $default(_that.row,_that.hasSnapshot,_that.revision,_that.composer,_that.activeInteraction,_that.turn,_that.execution,_that.continuation,_that.stopCommand,_that.continueCommand,_that.queuedStopStartedAtMs,_that.saveBlocked,_that.recoveryIssue,_that.executionClosed,_that.childInteractions,_that.childInteractionSync,_that.childInteractionSources,_that.modelRoute,_that.routeDisplay,_that.routePending,_that.routeFailure,_that.workflow,_that.accounts,_that.settingsLoaded,_that.targetDiagnostic,_that.additionalDiagnostics);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SessionDirectoryRow? row,  bool hasSnapshot,  int revision,  ComposerThreadState composer,  PendingInteraction? activeInteraction,  StudioTurnView? turn,  AgentExecutionView? execution,  ContinuationView? continuation,  CommandStatus? stopCommand,  CommandStatus? continueCommand,  int? queuedStopStartedAtMs,  bool saveBlocked,  StudioRecoveryIssue? recoveryIssue,  bool executionClosed,  List<ChildInteractionSummary> childInteractions,  DomainSyncStatus? childInteractionSync,  Map<String, String> childInteractionSources,  ThreadModelRouteView? modelRoute,  ModelRouteDisplay? routeDisplay,  bool routePending,  String? routeFailure,  WorkflowRuntimeView? workflow,  List<ModelSelectionAccount> accounts,  bool settingsLoaded,  ComposerTargetDiagnostic? targetDiagnostic,  List<ComposerTargetDiagnostic> additionalDiagnostics)  $default,) {final _that = this;
switch (_that) {
case _ComposerDockViewState():
return $default(_that.row,_that.hasSnapshot,_that.revision,_that.composer,_that.activeInteraction,_that.turn,_that.execution,_that.continuation,_that.stopCommand,_that.continueCommand,_that.queuedStopStartedAtMs,_that.saveBlocked,_that.recoveryIssue,_that.executionClosed,_that.childInteractions,_that.childInteractionSync,_that.childInteractionSources,_that.modelRoute,_that.routeDisplay,_that.routePending,_that.routeFailure,_that.workflow,_that.accounts,_that.settingsLoaded,_that.targetDiagnostic,_that.additionalDiagnostics);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SessionDirectoryRow? row,  bool hasSnapshot,  int revision,  ComposerThreadState composer,  PendingInteraction? activeInteraction,  StudioTurnView? turn,  AgentExecutionView? execution,  ContinuationView? continuation,  CommandStatus? stopCommand,  CommandStatus? continueCommand,  int? queuedStopStartedAtMs,  bool saveBlocked,  StudioRecoveryIssue? recoveryIssue,  bool executionClosed,  List<ChildInteractionSummary> childInteractions,  DomainSyncStatus? childInteractionSync,  Map<String, String> childInteractionSources,  ThreadModelRouteView? modelRoute,  ModelRouteDisplay? routeDisplay,  bool routePending,  String? routeFailure,  WorkflowRuntimeView? workflow,  List<ModelSelectionAccount> accounts,  bool settingsLoaded,  ComposerTargetDiagnostic? targetDiagnostic,  List<ComposerTargetDiagnostic> additionalDiagnostics)?  $default,) {final _that = this;
switch (_that) {
case _ComposerDockViewState() when $default != null:
return $default(_that.row,_that.hasSnapshot,_that.revision,_that.composer,_that.activeInteraction,_that.turn,_that.execution,_that.continuation,_that.stopCommand,_that.continueCommand,_that.queuedStopStartedAtMs,_that.saveBlocked,_that.recoveryIssue,_that.executionClosed,_that.childInteractions,_that.childInteractionSync,_that.childInteractionSources,_that.modelRoute,_that.routeDisplay,_that.routePending,_that.routeFailure,_that.workflow,_that.accounts,_that.settingsLoaded,_that.targetDiagnostic,_that.additionalDiagnostics);case _:
  return null;

}
}

}

/// @nodoc


class _ComposerDockViewState extends ComposerDockViewState {
  const _ComposerDockViewState({required this.row, required this.hasSnapshot, required this.revision, required this.composer, required this.activeInteraction, required this.turn, required this.execution, required this.continuation, required this.stopCommand, required this.continueCommand, this.queuedStopStartedAtMs, required this.saveBlocked, required this.recoveryIssue, required this.executionClosed, required  List<ChildInteractionSummary> childInteractions, required this.childInteractionSync, required  Map<String, String> childInteractionSources, required this.modelRoute, this.routeDisplay, required this.routePending, required this.routeFailure, required this.workflow, required  List<ModelSelectionAccount> accounts, required this.settingsLoaded, required this.targetDiagnostic, required  List<ComposerTargetDiagnostic> additionalDiagnostics}): _childInteractions = childInteractions,_childInteractionSources = childInteractionSources,_accounts = accounts,_additionalDiagnostics = additionalDiagnostics,super._();


@override final  SessionDirectoryRow? row;
@override final  bool hasSnapshot;
@override final  int revision;
@override final  ComposerThreadState composer;
@override final  PendingInteraction? activeInteraction;
@override final  StudioTurnView? turn;
@override final  AgentExecutionView? execution;
@override final  ContinuationView? continuation;
@override final  CommandStatus? stopCommand;
@override final  CommandStatus? continueCommand;
@override final  int? queuedStopStartedAtMs;
@override final  bool saveBlocked;
/// 同一 Client 目标规则选出的最高优先级执行恢复阻塞。
@override final  StudioRecoveryIssue? recoveryIssue;
/// 当前 Native 目录身份是否已永久封闭执行。
///
/// Closing/closed 时不显示执行入口，历史仍展示、草稿不清；
/// 独立会话快照中的 Core 资源关闭状态不参与此判定。
@override final  bool executionClosed;
 final  List<ChildInteractionSummary> _childInteractions;
@override List<ChildInteractionSummary> get childInteractions {
  if (_childInteractions is EqualUnmodifiableListView) return _childInteractions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_childInteractions);
}

@override final  DomainSyncStatus? childInteractionSync;
 final  Map<String, String> _childInteractionSources;
@override Map<String, String> get childInteractionSources {
  if (_childInteractionSources is EqualUnmodifiableMapView) return _childInteractionSources;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_childInteractionSources);
}

@override final  ThreadModelRouteView? modelRoute;
@override final  ModelRouteDisplay? routeDisplay;
@override final  bool routePending;
@override final  String? routeFailure;
@override final  WorkflowRuntimeView? workflow;
 final  List<ModelSelectionAccount> _accounts;
@override List<ModelSelectionAccount> get accounts {
  if (_accounts is EqualUnmodifiableListView) return _accounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_accounts);
}

@override final  bool settingsLoaded;
@override final  ComposerTargetDiagnostic? targetDiagnostic;
 final  List<ComposerTargetDiagnostic> _additionalDiagnostics;
@override List<ComposerTargetDiagnostic> get additionalDiagnostics {
  if (_additionalDiagnostics is EqualUnmodifiableListView) return _additionalDiagnostics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_additionalDiagnostics);
}


/// Create a copy of ComposerDockViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ComposerDockViewStateCopyWith<_ComposerDockViewState> get copyWith => __$ComposerDockViewStateCopyWithImpl<_ComposerDockViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ComposerDockViewState&&(identical(other.row, row) || other.row == row)&&(identical(other.hasSnapshot, hasSnapshot) || other.hasSnapshot == hasSnapshot)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.composer, composer) || other.composer == composer)&&(identical(other.activeInteraction, activeInteraction) || other.activeInteraction == activeInteraction)&&(identical(other.turn, turn) || other.turn == turn)&&(identical(other.execution, execution) || other.execution == execution)&&(identical(other.continuation, continuation) || other.continuation == continuation)&&(identical(other.stopCommand, stopCommand) || other.stopCommand == stopCommand)&&(identical(other.continueCommand, continueCommand) || other.continueCommand == continueCommand)&&(identical(other.queuedStopStartedAtMs, queuedStopStartedAtMs) || other.queuedStopStartedAtMs == queuedStopStartedAtMs)&&(identical(other.saveBlocked, saveBlocked) || other.saveBlocked == saveBlocked)&&(identical(other.recoveryIssue, recoveryIssue) || other.recoveryIssue == recoveryIssue)&&(identical(other.executionClosed, executionClosed) || other.executionClosed == executionClosed)&&const DeepCollectionEquality().equals(other.childInteractions, _childInteractions)&&(identical(other.childInteractionSync, childInteractionSync) || other.childInteractionSync == childInteractionSync)&&const DeepCollectionEquality().equals(other.childInteractionSources, _childInteractionSources)&&(identical(other.modelRoute, modelRoute) || other.modelRoute == modelRoute)&&(identical(other.routeDisplay, routeDisplay) || other.routeDisplay == routeDisplay)&&(identical(other.routePending, routePending) || other.routePending == routePending)&&(identical(other.routeFailure, routeFailure) || other.routeFailure == routeFailure)&&(identical(other.workflow, workflow) || other.workflow == workflow)&&const DeepCollectionEquality().equals(other.accounts, _accounts)&&(identical(other.settingsLoaded, settingsLoaded) || other.settingsLoaded == settingsLoaded)&&(identical(other.targetDiagnostic, targetDiagnostic) || other.targetDiagnostic == targetDiagnostic)&&const DeepCollectionEquality().equals(other.additionalDiagnostics, _additionalDiagnostics));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,row,hasSnapshot,revision,composer,activeInteraction,turn,execution,continuation,stopCommand,continueCommand,queuedStopStartedAtMs,saveBlocked,recoveryIssue,executionClosed,const DeepCollectionEquality().hash(_childInteractions),childInteractionSync,const DeepCollectionEquality().hash(_childInteractionSources),modelRoute,routeDisplay,routePending,routeFailure,workflow,const DeepCollectionEquality().hash(_accounts),settingsLoaded,targetDiagnostic,const DeepCollectionEquality().hash(_additionalDiagnostics)]);
}

@override
String toString() {
    return 'ComposerDockViewState(row: $row, hasSnapshot: $hasSnapshot, revision: $revision, composer: $composer, activeInteraction: $activeInteraction, turn: $turn, execution: $execution, continuation: $continuation, stopCommand: $stopCommand, continueCommand: $continueCommand, queuedStopStartedAtMs: $queuedStopStartedAtMs, saveBlocked: $saveBlocked, recoveryIssue: $recoveryIssue, executionClosed: $executionClosed, childInteractions: $childInteractions, childInteractionSync: $childInteractionSync, childInteractionSources: $childInteractionSources, modelRoute: $modelRoute, routeDisplay: $routeDisplay, routePending: $routePending, routeFailure: $routeFailure, workflow: $workflow, accounts: $accounts, settingsLoaded: $settingsLoaded, targetDiagnostic: $targetDiagnostic, additionalDiagnostics: $additionalDiagnostics)';
}


}

/// @nodoc
abstract mixin class _$ComposerDockViewStateCopyWith<$Res> implements $ComposerDockViewStateCopyWith<$Res> {
  factory _$ComposerDockViewStateCopyWith(_ComposerDockViewState value, $Res Function(_ComposerDockViewState) _then) = __$ComposerDockViewStateCopyWithImpl;
@override @useResult
$Res call({
 SessionDirectoryRow? row, bool hasSnapshot, int revision, ComposerThreadState composer, PendingInteraction? activeInteraction, StudioTurnView? turn, AgentExecutionView? execution, ContinuationView? continuation, CommandStatus? stopCommand, CommandStatus? continueCommand, int? queuedStopStartedAtMs, bool saveBlocked, StudioRecoveryIssue? recoveryIssue, bool executionClosed, List<ChildInteractionSummary> childInteractions, DomainSyncStatus? childInteractionSync, Map<String, String> childInteractionSources, ThreadModelRouteView? modelRoute, ModelRouteDisplay? routeDisplay, bool routePending, String? routeFailure, WorkflowRuntimeView? workflow, List<ModelSelectionAccount> accounts, bool settingsLoaded, ComposerTargetDiagnostic? targetDiagnostic, List<ComposerTargetDiagnostic> additionalDiagnostics
});




}
/// @nodoc
class __$ComposerDockViewStateCopyWithImpl<$Res>
    implements _$ComposerDockViewStateCopyWith<$Res> {
  __$ComposerDockViewStateCopyWithImpl(this._self, this._then);

  final _ComposerDockViewState _self;
  final $Res Function(_ComposerDockViewState) _then;

/// Create a copy of ComposerDockViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? row = freezed,Object? hasSnapshot = null,Object? revision = null,Object? composer = null,Object? activeInteraction = freezed,Object? turn = freezed,Object? execution = freezed,Object? continuation = freezed,Object? stopCommand = freezed,Object? continueCommand = freezed,Object? queuedStopStartedAtMs = freezed,Object? saveBlocked = null,Object? recoveryIssue = freezed,Object? executionClosed = null,Object? childInteractions = null,Object? childInteractionSync = freezed,Object? childInteractionSources = null,Object? modelRoute = freezed,Object? routeDisplay = freezed,Object? routePending = null,Object? routeFailure = freezed,Object? workflow = freezed,Object? accounts = null,Object? settingsLoaded = null,Object? targetDiagnostic = freezed,Object? additionalDiagnostics = null,}) {
  return _then(_ComposerDockViewState(
row: freezed == row ? _self.row : row // ignore: cast_nullable_to_non_nullable
as SessionDirectoryRow?,hasSnapshot: null == hasSnapshot ? _self.hasSnapshot : hasSnapshot // ignore: cast_nullable_to_non_nullable
as bool,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,composer: null == composer ? _self.composer : composer // ignore: cast_nullable_to_non_nullable
as ComposerThreadState,activeInteraction: freezed == activeInteraction ? _self.activeInteraction : activeInteraction // ignore: cast_nullable_to_non_nullable
as PendingInteraction?,turn: freezed == turn ? _self.turn : turn // ignore: cast_nullable_to_non_nullable
as StudioTurnView?,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as AgentExecutionView?,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as ContinuationView?,stopCommand: freezed == stopCommand ? _self.stopCommand : stopCommand // ignore: cast_nullable_to_non_nullable
as CommandStatus?,continueCommand: freezed == continueCommand ? _self.continueCommand : continueCommand // ignore: cast_nullable_to_non_nullable
as CommandStatus?,queuedStopStartedAtMs: freezed == queuedStopStartedAtMs ? _self.queuedStopStartedAtMs : queuedStopStartedAtMs // ignore: cast_nullable_to_non_nullable
as int?,saveBlocked: null == saveBlocked ? _self.saveBlocked : saveBlocked // ignore: cast_nullable_to_non_nullable
as bool,recoveryIssue: freezed == recoveryIssue ? _self.recoveryIssue : recoveryIssue // ignore: cast_nullable_to_non_nullable
as StudioRecoveryIssue?,executionClosed: null == executionClosed ? _self.executionClosed : executionClosed // ignore: cast_nullable_to_non_nullable
as bool,childInteractions: null == childInteractions ? _self._childInteractions : childInteractions // ignore: cast_nullable_to_non_nullable
as List<ChildInteractionSummary>,childInteractionSync: freezed == childInteractionSync ? _self.childInteractionSync : childInteractionSync // ignore: cast_nullable_to_non_nullable
as DomainSyncStatus?,childInteractionSources: null == childInteractionSources ? _self._childInteractionSources : childInteractionSources // ignore: cast_nullable_to_non_nullable
as Map<String, String>,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as ThreadModelRouteView?,routeDisplay: freezed == routeDisplay ? _self.routeDisplay : routeDisplay // ignore: cast_nullable_to_non_nullable
as ModelRouteDisplay?,routePending: null == routePending ? _self.routePending : routePending // ignore: cast_nullable_to_non_nullable
as bool,routeFailure: freezed == routeFailure ? _self.routeFailure : routeFailure // ignore: cast_nullable_to_non_nullable
as String?,workflow: freezed == workflow ? _self.workflow : workflow // ignore: cast_nullable_to_non_nullable
as WorkflowRuntimeView?,accounts: null == accounts ? _self._accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<ModelSelectionAccount>,settingsLoaded: null == settingsLoaded ? _self.settingsLoaded : settingsLoaded // ignore: cast_nullable_to_non_nullable
as bool,targetDiagnostic: freezed == targetDiagnostic ? _self.targetDiagnostic : targetDiagnostic // ignore: cast_nullable_to_non_nullable
as ComposerTargetDiagnostic?,additionalDiagnostics: null == additionalDiagnostics ? _self._additionalDiagnostics : additionalDiagnostics // ignore: cast_nullable_to_non_nullable
as List<ComposerTargetDiagnostic>,
  ));
}


}

// dart format on
