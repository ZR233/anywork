// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recovery_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WorktreeRecoveryPreview {

 WorktreeOwner get ownerKind; String get ownerThreadId; int get leaseRevision; String get state; String get repositoryRoot; String get path; String get branch; String get baseCommit; String? get headCommit; bool get dirty; List<String> get changedFiles;
/// Create a copy of WorktreeRecoveryPreview
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorktreeRecoveryPreviewCopyWith<WorktreeRecoveryPreview> get copyWith => _$WorktreeRecoveryPreviewCopyWithImpl<WorktreeRecoveryPreview>(this as WorktreeRecoveryPreview, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorktreeRecoveryPreview;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorktreeRecoveryPreview&&(identical(other.ownerKind, _this.ownerKind) || other.ownerKind == _this.ownerKind)&&(identical(other.ownerThreadId, _this.ownerThreadId) || other.ownerThreadId == _this.ownerThreadId)&&(identical(other.leaseRevision, _this.leaseRevision) || other.leaseRevision == _this.leaseRevision)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.repositoryRoot, _this.repositoryRoot) || other.repositoryRoot == _this.repositoryRoot)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.branch, _this.branch) || other.branch == _this.branch)&&(identical(other.baseCommit, _this.baseCommit) || other.baseCommit == _this.baseCommit)&&(identical(other.headCommit, _this.headCommit) || other.headCommit == _this.headCommit)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&const DeepCollectionEquality().equals(other.changedFiles, _this.changedFiles));
}


@override
int get hashCode {
  final _this = this as WorktreeRecoveryPreview;
  return Object.hash(runtimeType,_this.ownerKind,_this.ownerThreadId,_this.leaseRevision,_this.state,_this.repositoryRoot,_this.path,_this.branch,_this.baseCommit,_this.headCommit,_this.dirty,const DeepCollectionEquality().hash(_this.changedFiles));
}



}

/// @nodoc
abstract mixin class $WorktreeRecoveryPreviewCopyWith<$Res>  {
  factory $WorktreeRecoveryPreviewCopyWith(WorktreeRecoveryPreview value, $Res Function(WorktreeRecoveryPreview) _then) = _$WorktreeRecoveryPreviewCopyWithImpl;
@useResult
$Res call({
 WorktreeOwner ownerKind, String ownerThreadId, int leaseRevision, String state, String repositoryRoot, String path, String branch, String baseCommit, String? headCommit, bool dirty, List<String> changedFiles
});




}
/// @nodoc
class _$WorktreeRecoveryPreviewCopyWithImpl<$Res>
    implements $WorktreeRecoveryPreviewCopyWith<$Res> {
  _$WorktreeRecoveryPreviewCopyWithImpl(this._self, this._then);

  final WorktreeRecoveryPreview _self;
  final $Res Function(WorktreeRecoveryPreview) _then;

/// Create a copy of WorktreeRecoveryPreview
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? ownerKind = null,Object? ownerThreadId = null,Object? leaseRevision = null,Object? state = null,Object? repositoryRoot = null,Object? path = null,Object? branch = null,Object? baseCommit = null,Object? headCommit = freezed,Object? dirty = null,Object? changedFiles = null,}) {
  return _then(WorktreeRecoveryPreview(
ownerKind: null == ownerKind ? _self.ownerKind : ownerKind // ignore: cast_nullable_to_non_nullable
as WorktreeOwner,ownerThreadId: null == ownerThreadId ? _self.ownerThreadId : ownerThreadId // ignore: cast_nullable_to_non_nullable
as String,leaseRevision: null == leaseRevision ? _self.leaseRevision : leaseRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,repositoryRoot: null == repositoryRoot ? _self.repositoryRoot : repositoryRoot // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String,baseCommit: null == baseCommit ? _self.baseCommit : baseCommit // ignore: cast_nullable_to_non_nullable
as String,headCommit: freezed == headCommit ? _self.headCommit : headCommit // ignore: cast_nullable_to_non_nullable
as String?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,changedFiles: null == changedFiles ? _self.changedFiles : changedFiles // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [WorktreeRecoveryPreview].
extension WorktreeRecoveryPreviewPatterns on WorktreeRecoveryPreview {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorktreeRecoveryPreview value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorktreeRecoveryPreview() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorktreeRecoveryPreview value)  $default,){
final _that = this;
switch (_that) {
case _WorktreeRecoveryPreview():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorktreeRecoveryPreview value)?  $default,){
final _that = this;
switch (_that) {
case _WorktreeRecoveryPreview() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorktreeOwner ownerKind,  String ownerThreadId,  int leaseRevision,  String state,  String repositoryRoot,  String path,  String branch,  String baseCommit,  String? headCommit,  bool dirty,  List<String> changedFiles)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorktreeRecoveryPreview() when $default != null:
return $default(_that.ownerKind,_that.ownerThreadId,_that.leaseRevision,_that.state,_that.repositoryRoot,_that.path,_that.branch,_that.baseCommit,_that.headCommit,_that.dirty,_that.changedFiles);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorktreeOwner ownerKind,  String ownerThreadId,  int leaseRevision,  String state,  String repositoryRoot,  String path,  String branch,  String baseCommit,  String? headCommit,  bool dirty,  List<String> changedFiles)  $default,) {final _that = this;
switch (_that) {
case _WorktreeRecoveryPreview():
return $default(_that.ownerKind,_that.ownerThreadId,_that.leaseRevision,_that.state,_that.repositoryRoot,_that.path,_that.branch,_that.baseCommit,_that.headCommit,_that.dirty,_that.changedFiles);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorktreeOwner ownerKind,  String ownerThreadId,  int leaseRevision,  String state,  String repositoryRoot,  String path,  String branch,  String baseCommit,  String? headCommit,  bool dirty,  List<String> changedFiles)?  $default,) {final _that = this;
switch (_that) {
case _WorktreeRecoveryPreview() when $default != null:
return $default(_that.ownerKind,_that.ownerThreadId,_that.leaseRevision,_that.state,_that.repositoryRoot,_that.path,_that.branch,_that.baseCommit,_that.headCommit,_that.dirty,_that.changedFiles);case _:
  return null;

}
}

}

/// @nodoc


class _WorktreeRecoveryPreview implements WorktreeRecoveryPreview {
  const _WorktreeRecoveryPreview({required this.ownerKind, required this.ownerThreadId, required this.leaseRevision, required this.state, required this.repositoryRoot, required this.path, required this.branch, required this.baseCommit, required this.headCommit, required this.dirty, required  List<String> changedFiles}): _changedFiles = changedFiles;


@override final  WorktreeOwner ownerKind;
@override final  String ownerThreadId;
@override final  int leaseRevision;
@override final  String state;
@override final  String repositoryRoot;
@override final  String path;
@override final  String branch;
@override final  String baseCommit;
@override final  String? headCommit;
@override final  bool dirty;
 final  List<String> _changedFiles;
@override List<String> get changedFiles {
  if (_changedFiles is EqualUnmodifiableListView) return _changedFiles;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_changedFiles);
}


/// Create a copy of WorktreeRecoveryPreview
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorktreeRecoveryPreviewCopyWith<_WorktreeRecoveryPreview> get copyWith => __$WorktreeRecoveryPreviewCopyWithImpl<_WorktreeRecoveryPreview>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorktreeRecoveryPreview&&(identical(other.ownerKind, ownerKind) || other.ownerKind == ownerKind)&&(identical(other.ownerThreadId, ownerThreadId) || other.ownerThreadId == ownerThreadId)&&(identical(other.leaseRevision, leaseRevision) || other.leaseRevision == leaseRevision)&&(identical(other.state, state) || other.state == state)&&(identical(other.repositoryRoot, repositoryRoot) || other.repositoryRoot == repositoryRoot)&&(identical(other.path, path) || other.path == path)&&(identical(other.branch, branch) || other.branch == branch)&&(identical(other.baseCommit, baseCommit) || other.baseCommit == baseCommit)&&(identical(other.headCommit, headCommit) || other.headCommit == headCommit)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&const DeepCollectionEquality().equals(other.changedFiles, _changedFiles));
}


@override
int get hashCode {
    return Object.hash(runtimeType,ownerKind,ownerThreadId,leaseRevision,state,repositoryRoot,path,branch,baseCommit,headCommit,dirty,const DeepCollectionEquality().hash(_changedFiles));
}



}

/// @nodoc
abstract mixin class _$WorktreeRecoveryPreviewCopyWith<$Res> implements $WorktreeRecoveryPreviewCopyWith<$Res> {
  factory _$WorktreeRecoveryPreviewCopyWith(_WorktreeRecoveryPreview value, $Res Function(_WorktreeRecoveryPreview) _then) = __$WorktreeRecoveryPreviewCopyWithImpl;
@override @useResult
$Res call({
 WorktreeOwner ownerKind, String ownerThreadId, int leaseRevision, String state, String repositoryRoot, String path, String branch, String baseCommit, String? headCommit, bool dirty, List<String> changedFiles
});




}
/// @nodoc
class __$WorktreeRecoveryPreviewCopyWithImpl<$Res>
    implements _$WorktreeRecoveryPreviewCopyWith<$Res> {
  __$WorktreeRecoveryPreviewCopyWithImpl(this._self, this._then);

  final _WorktreeRecoveryPreview _self;
  final $Res Function(_WorktreeRecoveryPreview) _then;

/// Create a copy of WorktreeRecoveryPreview
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? ownerKind = null,Object? ownerThreadId = null,Object? leaseRevision = null,Object? state = null,Object? repositoryRoot = null,Object? path = null,Object? branch = null,Object? baseCommit = null,Object? headCommit = freezed,Object? dirty = null,Object? changedFiles = null,}) {
  return _then(_WorktreeRecoveryPreview(
ownerKind: null == ownerKind ? _self.ownerKind : ownerKind // ignore: cast_nullable_to_non_nullable
as WorktreeOwner,ownerThreadId: null == ownerThreadId ? _self.ownerThreadId : ownerThreadId // ignore: cast_nullable_to_non_nullable
as String,leaseRevision: null == leaseRevision ? _self.leaseRevision : leaseRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,repositoryRoot: null == repositoryRoot ? _self.repositoryRoot : repositoryRoot // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String,baseCommit: null == baseCommit ? _self.baseCommit : baseCommit // ignore: cast_nullable_to_non_nullable
as String,headCommit: freezed == headCommit ? _self.headCommit : headCommit // ignore: cast_nullable_to_non_nullable
as String?,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,changedFiles: null == changedFiles ? _self._changedFiles : changedFiles // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

/// @nodoc
mixin _$RecoveryIssue {

 String get id; RecoveryScope get scope; RecoveryCategory get category; RecoveryAction get action; String? get projectId; String? get threadId; String get message; WorktreeRecoveryPreview? get worktree;
/// Create a copy of RecoveryIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryIssueCopyWith<RecoveryIssue> get copyWith => _$RecoveryIssueCopyWithImpl<RecoveryIssue>(this as RecoveryIssue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryIssue&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.action, _this.action) || other.action == _this.action)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.worktree, _this.worktree) || other.worktree == _this.worktree));
}


@override
int get hashCode {
  final _this = this as RecoveryIssue;
  return Object.hash(runtimeType,_this.id,_this.scope,_this.category,_this.action,_this.projectId,_this.threadId,_this.message,_this.worktree);
}



}

/// @nodoc
abstract mixin class $RecoveryIssueCopyWith<$Res>  {
  factory $RecoveryIssueCopyWith(RecoveryIssue value, $Res Function(RecoveryIssue) _then) = _$RecoveryIssueCopyWithImpl;
@useResult
$Res call({
 String id, RecoveryScope scope, RecoveryCategory category, RecoveryAction action, String? projectId, String? threadId, String message, WorktreeRecoveryPreview? worktree
});


$WorktreeRecoveryPreviewCopyWith<$Res>? get worktree;

}
/// @nodoc
class _$RecoveryIssueCopyWithImpl<$Res>
    implements $RecoveryIssueCopyWith<$Res> {
  _$RecoveryIssueCopyWithImpl(this._self, this._then);

  final RecoveryIssue _self;
  final $Res Function(RecoveryIssue) _then;

/// Create a copy of RecoveryIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? scope = null,Object? category = null,Object? action = null,Object? projectId = freezed,Object? threadId = freezed,Object? message = null,Object? worktree = freezed,}) {
  return _then(RecoveryIssue(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as RecoveryScope,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as RecoveryCategory,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as RecoveryAction,projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String?,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,worktree: freezed == worktree ? _self.worktree : worktree // ignore: cast_nullable_to_non_nullable
as WorktreeRecoveryPreview?,
  ));
}
/// Create a copy of RecoveryIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorktreeRecoveryPreviewCopyWith<$Res>? get worktree {
    if (_self.worktree == null) {
    return null;
  }

  return $WorktreeRecoveryPreviewCopyWith<$Res>(_self.worktree!, (value) {
    return _then(_self.copyWith(worktree: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryIssue].
extension RecoveryIssuePatterns on RecoveryIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryIssue value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryIssue value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  RecoveryScope scope,  RecoveryCategory category,  RecoveryAction action,  String? projectId,  String? threadId,  String message,  WorktreeRecoveryPreview? worktree)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryIssue() when $default != null:
return $default(_that.id,_that.scope,_that.category,_that.action,_that.projectId,_that.threadId,_that.message,_that.worktree);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  RecoveryScope scope,  RecoveryCategory category,  RecoveryAction action,  String? projectId,  String? threadId,  String message,  WorktreeRecoveryPreview? worktree)  $default,) {final _that = this;
switch (_that) {
case _RecoveryIssue():
return $default(_that.id,_that.scope,_that.category,_that.action,_that.projectId,_that.threadId,_that.message,_that.worktree);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  RecoveryScope scope,  RecoveryCategory category,  RecoveryAction action,  String? projectId,  String? threadId,  String message,  WorktreeRecoveryPreview? worktree)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryIssue() when $default != null:
return $default(_that.id,_that.scope,_that.category,_that.action,_that.projectId,_that.threadId,_that.message,_that.worktree);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryIssue extends RecoveryIssue {
  const _RecoveryIssue({required this.id, required this.scope, required this.category, required this.action, required this.projectId, required this.threadId, required this.message, required this.worktree}): super._();


@override final  String id;
@override final  RecoveryScope scope;
@override final  RecoveryCategory category;
@override final  RecoveryAction action;
@override final  String? projectId;
@override final  String? threadId;
@override final  String message;
@override final  WorktreeRecoveryPreview? worktree;

/// Create a copy of RecoveryIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryIssueCopyWith<_RecoveryIssue> get copyWith => __$RecoveryIssueCopyWithImpl<_RecoveryIssue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryIssue&&(identical(other.id, id) || other.id == id)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.category, category) || other.category == category)&&(identical(other.action, action) || other.action == action)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.message, message) || other.message == message)&&(identical(other.worktree, worktree) || other.worktree == worktree));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,scope,category,action,projectId,threadId,message,worktree);
}



}

/// @nodoc
abstract mixin class _$RecoveryIssueCopyWith<$Res> implements $RecoveryIssueCopyWith<$Res> {
  factory _$RecoveryIssueCopyWith(_RecoveryIssue value, $Res Function(_RecoveryIssue) _then) = __$RecoveryIssueCopyWithImpl;
@override @useResult
$Res call({
 String id, RecoveryScope scope, RecoveryCategory category, RecoveryAction action, String? projectId, String? threadId, String message, WorktreeRecoveryPreview? worktree
});


@override $WorktreeRecoveryPreviewCopyWith<$Res>? get worktree;

}
/// @nodoc
class __$RecoveryIssueCopyWithImpl<$Res>
    implements _$RecoveryIssueCopyWith<$Res> {
  __$RecoveryIssueCopyWithImpl(this._self, this._then);

  final _RecoveryIssue _self;
  final $Res Function(_RecoveryIssue) _then;

/// Create a copy of RecoveryIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? scope = null,Object? category = null,Object? action = null,Object? projectId = freezed,Object? threadId = freezed,Object? message = null,Object? worktree = freezed,}) {
  return _then(_RecoveryIssue(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as RecoveryScope,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as RecoveryCategory,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as RecoveryAction,projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String?,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,worktree: freezed == worktree ? _self.worktree : worktree // ignore: cast_nullable_to_non_nullable
as WorktreeRecoveryPreview?,
  ));
}

/// Create a copy of RecoveryIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorktreeRecoveryPreviewCopyWith<$Res>? get worktree {
    if (_self.worktree == null) {
    return null;
  }

  return $WorktreeRecoveryPreviewCopyWith<$Res>(_self.worktree!, (value) {
    return _then(_self.copyWith(worktree: value));
  });
}
}

// dart format on
