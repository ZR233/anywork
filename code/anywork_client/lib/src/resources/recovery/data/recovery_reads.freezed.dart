// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recovery_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RecoveryReadHeader {

 TypedListRef get issues;
/// Create a copy of RecoveryReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryReadHeaderCopyWith<RecoveryReadHeader> get copyWith => _$RecoveryReadHeaderCopyWithImpl<RecoveryReadHeader>(this as RecoveryReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryReadHeader&&(identical(other.issues, _this.issues) || other.issues == _this.issues));
}


@override
int get hashCode {
  final _this = this as RecoveryReadHeader;
  return Object.hash(runtimeType,_this.issues);
}

@override
String toString() {
  final _this = this as RecoveryReadHeader;
  return 'RecoveryReadHeader(issues: ${_this.issues})';
}


}

/// @nodoc
abstract mixin class $RecoveryReadHeaderCopyWith<$Res>  {
  factory $RecoveryReadHeaderCopyWith(RecoveryReadHeader value, $Res Function(RecoveryReadHeader) _then) = _$RecoveryReadHeaderCopyWithImpl;
@useResult
$Res call({
 TypedListRef issues
});


$TypedListRefCopyWith<$Res> get issues;

}
/// @nodoc
class _$RecoveryReadHeaderCopyWithImpl<$Res>
    implements $RecoveryReadHeaderCopyWith<$Res> {
  _$RecoveryReadHeaderCopyWithImpl(this._self, this._then);

  final RecoveryReadHeader _self;
  final $Res Function(RecoveryReadHeader) _then;

/// Create a copy of RecoveryReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? issues = null,}) {
  return _then(RecoveryReadHeader(
issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of RecoveryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get issues {

  return $TypedListRefCopyWith<$Res>(_self.issues, (value) {
    return _then(_self.copyWith(issues: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryReadHeader].
extension RecoveryReadHeaderPatterns on RecoveryReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TypedListRef issues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryReadHeader() when $default != null:
return $default(_that.issues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TypedListRef issues)  $default,) {final _that = this;
switch (_that) {
case _RecoveryReadHeader():
return $default(_that.issues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TypedListRef issues)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryReadHeader() when $default != null:
return $default(_that.issues);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryReadHeader implements RecoveryReadHeader {
  const _RecoveryReadHeader({required this.issues});


@override final  TypedListRef issues;

/// Create a copy of RecoveryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryReadHeaderCopyWith<_RecoveryReadHeader> get copyWith => __$RecoveryReadHeaderCopyWithImpl<_RecoveryReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryReadHeader&&(identical(other.issues, issues) || other.issues == issues));
}


@override
int get hashCode {
    return Object.hash(runtimeType,issues);
}

@override
String toString() {
    return 'RecoveryReadHeader(issues: $issues)';
}


}

/// @nodoc
abstract mixin class _$RecoveryReadHeaderCopyWith<$Res> implements $RecoveryReadHeaderCopyWith<$Res> {
  factory _$RecoveryReadHeaderCopyWith(_RecoveryReadHeader value, $Res Function(_RecoveryReadHeader) _then) = __$RecoveryReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 TypedListRef issues
});


@override $TypedListRefCopyWith<$Res> get issues;

}
/// @nodoc
class __$RecoveryReadHeaderCopyWithImpl<$Res>
    implements _$RecoveryReadHeaderCopyWith<$Res> {
  __$RecoveryReadHeaderCopyWithImpl(this._self, this._then);

  final _RecoveryReadHeader _self;
  final $Res Function(_RecoveryReadHeader) _then;

/// Create a copy of RecoveryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? issues = null,}) {
  return _then(_RecoveryReadHeader(
issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of RecoveryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get issues {

  return $TypedListRefCopyWith<$Res>(_self.issues, (value) {
    return _then(_self.copyWith(issues: value));
  });
}
}

/// @nodoc
mixin _$WorktreeRecoveryPreviewRead {

 WorktreeInspection get inspection; WorktreeOwner get ownerKind; ReadText get ownerThreadId; int get leaseRevision; ReadText get state; ReadText get repositoryRoot; ReadText get path; ReadText get branch; ReadText get baseCommit; ReadText? get headCommit; bool? get dirty; TypedListRef? get changedFiles;
/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorktreeRecoveryPreviewReadCopyWith<WorktreeRecoveryPreviewRead> get copyWith => _$WorktreeRecoveryPreviewReadCopyWithImpl<WorktreeRecoveryPreviewRead>(this as WorktreeRecoveryPreviewRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorktreeRecoveryPreviewRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorktreeRecoveryPreviewRead&&(identical(other.inspection, _this.inspection) || other.inspection == _this.inspection)&&(identical(other.ownerKind, _this.ownerKind) || other.ownerKind == _this.ownerKind)&&(identical(other.ownerThreadId, _this.ownerThreadId) || other.ownerThreadId == _this.ownerThreadId)&&(identical(other.leaseRevision, _this.leaseRevision) || other.leaseRevision == _this.leaseRevision)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.repositoryRoot, _this.repositoryRoot) || other.repositoryRoot == _this.repositoryRoot)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.branch, _this.branch) || other.branch == _this.branch)&&(identical(other.baseCommit, _this.baseCommit) || other.baseCommit == _this.baseCommit)&&(identical(other.headCommit, _this.headCommit) || other.headCommit == _this.headCommit)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.changedFiles, _this.changedFiles) || other.changedFiles == _this.changedFiles));
}


@override
int get hashCode {
  final _this = this as WorktreeRecoveryPreviewRead;
  return Object.hash(runtimeType,_this.inspection,_this.ownerKind,_this.ownerThreadId,_this.leaseRevision,_this.state,_this.repositoryRoot,_this.path,_this.branch,_this.baseCommit,_this.headCommit,_this.dirty,_this.changedFiles);
}



}

/// @nodoc
abstract mixin class $WorktreeRecoveryPreviewReadCopyWith<$Res>  {
  factory $WorktreeRecoveryPreviewReadCopyWith(WorktreeRecoveryPreviewRead value, $Res Function(WorktreeRecoveryPreviewRead) _then) = _$WorktreeRecoveryPreviewReadCopyWithImpl;
@useResult
$Res call({
 WorktreeInspection inspection, WorktreeOwner ownerKind, ReadText ownerThreadId, int leaseRevision, ReadText state, ReadText repositoryRoot, ReadText path, ReadText branch, ReadText baseCommit, ReadText? headCommit, bool? dirty, TypedListRef? changedFiles
});


$ReadTextCopyWith<$Res> get ownerThreadId;$ReadTextCopyWith<$Res> get state;$ReadTextCopyWith<$Res> get repositoryRoot;$ReadTextCopyWith<$Res> get path;$ReadTextCopyWith<$Res> get branch;$ReadTextCopyWith<$Res> get baseCommit;$ReadTextCopyWith<$Res>? get headCommit;$TypedListRefCopyWith<$Res>? get changedFiles;

}
/// @nodoc
class _$WorktreeRecoveryPreviewReadCopyWithImpl<$Res>
    implements $WorktreeRecoveryPreviewReadCopyWith<$Res> {
  _$WorktreeRecoveryPreviewReadCopyWithImpl(this._self, this._then);

  final WorktreeRecoveryPreviewRead _self;
  final $Res Function(WorktreeRecoveryPreviewRead) _then;

/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inspection = null,Object? ownerKind = null,Object? ownerThreadId = null,Object? leaseRevision = null,Object? state = null,Object? repositoryRoot = null,Object? path = null,Object? branch = null,Object? baseCommit = null,Object? headCommit = freezed,Object? dirty = freezed,Object? changedFiles = freezed,}) {
  return _then(WorktreeRecoveryPreviewRead(
inspection: null == inspection ? _self.inspection : inspection // ignore: cast_nullable_to_non_nullable
as WorktreeInspection,ownerKind: null == ownerKind ? _self.ownerKind : ownerKind // ignore: cast_nullable_to_non_nullable
as WorktreeOwner,ownerThreadId: null == ownerThreadId ? _self.ownerThreadId : ownerThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,leaseRevision: null == leaseRevision ? _self.leaseRevision : leaseRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ReadText,repositoryRoot: null == repositoryRoot ? _self.repositoryRoot : repositoryRoot // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as ReadText,baseCommit: null == baseCommit ? _self.baseCommit : baseCommit // ignore: cast_nullable_to_non_nullable
as ReadText,headCommit: freezed == headCommit ? _self.headCommit : headCommit // ignore: cast_nullable_to_non_nullable
as ReadText?,dirty: freezed == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool?,changedFiles: freezed == changedFiles ? _self.changedFiles : changedFiles // ignore: cast_nullable_to_non_nullable
as TypedListRef?,
  ));
}
/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get ownerThreadId {

  return $ReadTextCopyWith<$Res>(_self.ownerThreadId, (value) {
    return _then(_self.copyWith(ownerThreadId: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get state {

  return $ReadTextCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get repositoryRoot {

  return $ReadTextCopyWith<$Res>(_self.repositoryRoot, (value) {
    return _then(_self.copyWith(repositoryRoot: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get branch {

  return $ReadTextCopyWith<$Res>(_self.branch, (value) {
    return _then(_self.copyWith(branch: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseCommit {

  return $ReadTextCopyWith<$Res>(_self.baseCommit, (value) {
    return _then(_self.copyWith(baseCommit: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get headCommit {
    if (_self.headCommit == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.headCommit!, (value) {
    return _then(_self.copyWith(headCommit: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res>? get changedFiles {
    if (_self.changedFiles == null) {
    return null;
  }

  return $TypedListRefCopyWith<$Res>(_self.changedFiles!, (value) {
    return _then(_self.copyWith(changedFiles: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorktreeRecoveryPreviewRead].
extension WorktreeRecoveryPreviewReadPatterns on WorktreeRecoveryPreviewRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorktreeRecoveryPreviewRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorktreeRecoveryPreviewRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorktreeRecoveryPreviewRead value)  $default,){
final _that = this;
switch (_that) {
case _WorktreeRecoveryPreviewRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorktreeRecoveryPreviewRead value)?  $default,){
final _that = this;
switch (_that) {
case _WorktreeRecoveryPreviewRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorktreeInspection inspection,  WorktreeOwner ownerKind,  ReadText ownerThreadId,  int leaseRevision,  ReadText state,  ReadText repositoryRoot,  ReadText path,  ReadText branch,  ReadText baseCommit,  ReadText? headCommit,  bool? dirty,  TypedListRef? changedFiles)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorktreeRecoveryPreviewRead() when $default != null:
return $default(_that.inspection,_that.ownerKind,_that.ownerThreadId,_that.leaseRevision,_that.state,_that.repositoryRoot,_that.path,_that.branch,_that.baseCommit,_that.headCommit,_that.dirty,_that.changedFiles);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorktreeInspection inspection,  WorktreeOwner ownerKind,  ReadText ownerThreadId,  int leaseRevision,  ReadText state,  ReadText repositoryRoot,  ReadText path,  ReadText branch,  ReadText baseCommit,  ReadText? headCommit,  bool? dirty,  TypedListRef? changedFiles)  $default,) {final _that = this;
switch (_that) {
case _WorktreeRecoveryPreviewRead():
return $default(_that.inspection,_that.ownerKind,_that.ownerThreadId,_that.leaseRevision,_that.state,_that.repositoryRoot,_that.path,_that.branch,_that.baseCommit,_that.headCommit,_that.dirty,_that.changedFiles);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorktreeInspection inspection,  WorktreeOwner ownerKind,  ReadText ownerThreadId,  int leaseRevision,  ReadText state,  ReadText repositoryRoot,  ReadText path,  ReadText branch,  ReadText baseCommit,  ReadText? headCommit,  bool? dirty,  TypedListRef? changedFiles)?  $default,) {final _that = this;
switch (_that) {
case _WorktreeRecoveryPreviewRead() when $default != null:
return $default(_that.inspection,_that.ownerKind,_that.ownerThreadId,_that.leaseRevision,_that.state,_that.repositoryRoot,_that.path,_that.branch,_that.baseCommit,_that.headCommit,_that.dirty,_that.changedFiles);case _:
  return null;

}
}

}

/// @nodoc


class _WorktreeRecoveryPreviewRead implements WorktreeRecoveryPreviewRead {
  const _WorktreeRecoveryPreviewRead({required this.inspection, required this.ownerKind, required this.ownerThreadId, required this.leaseRevision, required this.state, required this.repositoryRoot, required this.path, required this.branch, required this.baseCommit, required this.headCommit, required this.dirty, required this.changedFiles});


@override final  WorktreeInspection inspection;
@override final  WorktreeOwner ownerKind;
@override final  ReadText ownerThreadId;
@override final  int leaseRevision;
@override final  ReadText state;
@override final  ReadText repositoryRoot;
@override final  ReadText path;
@override final  ReadText branch;
@override final  ReadText baseCommit;
@override final  ReadText? headCommit;
@override final  bool? dirty;
@override final  TypedListRef? changedFiles;

/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorktreeRecoveryPreviewReadCopyWith<_WorktreeRecoveryPreviewRead> get copyWith => __$WorktreeRecoveryPreviewReadCopyWithImpl<_WorktreeRecoveryPreviewRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorktreeRecoveryPreviewRead&&(identical(other.inspection, inspection) || other.inspection == inspection)&&(identical(other.ownerKind, ownerKind) || other.ownerKind == ownerKind)&&(identical(other.ownerThreadId, ownerThreadId) || other.ownerThreadId == ownerThreadId)&&(identical(other.leaseRevision, leaseRevision) || other.leaseRevision == leaseRevision)&&(identical(other.state, state) || other.state == state)&&(identical(other.repositoryRoot, repositoryRoot) || other.repositoryRoot == repositoryRoot)&&(identical(other.path, path) || other.path == path)&&(identical(other.branch, branch) || other.branch == branch)&&(identical(other.baseCommit, baseCommit) || other.baseCommit == baseCommit)&&(identical(other.headCommit, headCommit) || other.headCommit == headCommit)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.changedFiles, changedFiles) || other.changedFiles == changedFiles));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inspection,ownerKind,ownerThreadId,leaseRevision,state,repositoryRoot,path,branch,baseCommit,headCommit,dirty,changedFiles);
}



}

/// @nodoc
abstract mixin class _$WorktreeRecoveryPreviewReadCopyWith<$Res> implements $WorktreeRecoveryPreviewReadCopyWith<$Res> {
  factory _$WorktreeRecoveryPreviewReadCopyWith(_WorktreeRecoveryPreviewRead value, $Res Function(_WorktreeRecoveryPreviewRead) _then) = __$WorktreeRecoveryPreviewReadCopyWithImpl;
@override @useResult
$Res call({
 WorktreeInspection inspection, WorktreeOwner ownerKind, ReadText ownerThreadId, int leaseRevision, ReadText state, ReadText repositoryRoot, ReadText path, ReadText branch, ReadText baseCommit, ReadText? headCommit, bool? dirty, TypedListRef? changedFiles
});


@override $ReadTextCopyWith<$Res> get ownerThreadId;@override $ReadTextCopyWith<$Res> get state;@override $ReadTextCopyWith<$Res> get repositoryRoot;@override $ReadTextCopyWith<$Res> get path;@override $ReadTextCopyWith<$Res> get branch;@override $ReadTextCopyWith<$Res> get baseCommit;@override $ReadTextCopyWith<$Res>? get headCommit;@override $TypedListRefCopyWith<$Res>? get changedFiles;

}
/// @nodoc
class __$WorktreeRecoveryPreviewReadCopyWithImpl<$Res>
    implements _$WorktreeRecoveryPreviewReadCopyWith<$Res> {
  __$WorktreeRecoveryPreviewReadCopyWithImpl(this._self, this._then);

  final _WorktreeRecoveryPreviewRead _self;
  final $Res Function(_WorktreeRecoveryPreviewRead) _then;

/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? inspection = null,Object? ownerKind = null,Object? ownerThreadId = null,Object? leaseRevision = null,Object? state = null,Object? repositoryRoot = null,Object? path = null,Object? branch = null,Object? baseCommit = null,Object? headCommit = freezed,Object? dirty = freezed,Object? changedFiles = freezed,}) {
  return _then(_WorktreeRecoveryPreviewRead(
inspection: null == inspection ? _self.inspection : inspection // ignore: cast_nullable_to_non_nullable
as WorktreeInspection,ownerKind: null == ownerKind ? _self.ownerKind : ownerKind // ignore: cast_nullable_to_non_nullable
as WorktreeOwner,ownerThreadId: null == ownerThreadId ? _self.ownerThreadId : ownerThreadId // ignore: cast_nullable_to_non_nullable
as ReadText,leaseRevision: null == leaseRevision ? _self.leaseRevision : leaseRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ReadText,repositoryRoot: null == repositoryRoot ? _self.repositoryRoot : repositoryRoot // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,branch: null == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as ReadText,baseCommit: null == baseCommit ? _self.baseCommit : baseCommit // ignore: cast_nullable_to_non_nullable
as ReadText,headCommit: freezed == headCommit ? _self.headCommit : headCommit // ignore: cast_nullable_to_non_nullable
as ReadText?,dirty: freezed == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool?,changedFiles: freezed == changedFiles ? _self.changedFiles : changedFiles // ignore: cast_nullable_to_non_nullable
as TypedListRef?,
  ));
}

/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get ownerThreadId {

  return $ReadTextCopyWith<$Res>(_self.ownerThreadId, (value) {
    return _then(_self.copyWith(ownerThreadId: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get state {

  return $ReadTextCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get repositoryRoot {

  return $ReadTextCopyWith<$Res>(_self.repositoryRoot, (value) {
    return _then(_self.copyWith(repositoryRoot: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get branch {

  return $ReadTextCopyWith<$Res>(_self.branch, (value) {
    return _then(_self.copyWith(branch: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseCommit {

  return $ReadTextCopyWith<$Res>(_self.baseCommit, (value) {
    return _then(_self.copyWith(baseCommit: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get headCommit {
    if (_self.headCommit == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.headCommit!, (value) {
    return _then(_self.copyWith(headCommit: value));
  });
}/// Create a copy of WorktreeRecoveryPreviewRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res>? get changedFiles {
    if (_self.changedFiles == null) {
    return null;
  }

  return $TypedListRefCopyWith<$Res>(_self.changedFiles!, (value) {
    return _then(_self.copyWith(changedFiles: value));
  });
}
}

/// @nodoc
mixin _$RecoveryIssueRead {

 ReadText get id; RecoveryScope get scope; RecoveryCategory get category; List<RecoveryAction> get availableActions; ReadText? get projectId; ReadText? get threadId; ReadText get message; WorktreeRecoveryPreviewRead? get worktree;
/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryIssueReadCopyWith<RecoveryIssueRead> get copyWith => _$RecoveryIssueReadCopyWithImpl<RecoveryIssueRead>(this as RecoveryIssueRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryIssueRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryIssueRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.category, _this.category) || other.category == _this.category)&&const DeepCollectionEquality().equals(other.availableActions, _this.availableActions)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.worktree, _this.worktree) || other.worktree == _this.worktree));
}


@override
int get hashCode {
  final _this = this as RecoveryIssueRead;
  return Object.hash(runtimeType,_this.id,_this.scope,_this.category,const DeepCollectionEquality().hash(_this.availableActions),_this.projectId,_this.threadId,_this.message,_this.worktree);
}



}

/// @nodoc
abstract mixin class $RecoveryIssueReadCopyWith<$Res>  {
  factory $RecoveryIssueReadCopyWith(RecoveryIssueRead value, $Res Function(RecoveryIssueRead) _then) = _$RecoveryIssueReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, RecoveryScope scope, RecoveryCategory category, List<RecoveryAction> availableActions, ReadText? projectId, ReadText? threadId, ReadText message, WorktreeRecoveryPreviewRead? worktree
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res>? get projectId;$ReadTextCopyWith<$Res>? get threadId;$ReadTextCopyWith<$Res> get message;$WorktreeRecoveryPreviewReadCopyWith<$Res>? get worktree;

}
/// @nodoc
class _$RecoveryIssueReadCopyWithImpl<$Res>
    implements $RecoveryIssueReadCopyWith<$Res> {
  _$RecoveryIssueReadCopyWithImpl(this._self, this._then);

  final RecoveryIssueRead _self;
  final $Res Function(RecoveryIssueRead) _then;

/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? scope = null,Object? category = null,Object? availableActions = null,Object? projectId = freezed,Object? threadId = freezed,Object? message = null,Object? worktree = freezed,}) {
  return _then(RecoveryIssueRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as RecoveryScope,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as RecoveryCategory,availableActions: null == availableActions ? _self.availableActions : availableActions // ignore: cast_nullable_to_non_nullable
as List<RecoveryAction>,projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as ReadText?,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,worktree: freezed == worktree ? _self.worktree : worktree // ignore: cast_nullable_to_non_nullable
as WorktreeRecoveryPreviewRead?,
  ));
}
/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get projectId {
    if (_self.projectId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.projectId!, (value) {
    return _then(_self.copyWith(projectId: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get threadId {
    if (_self.threadId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.threadId!, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorktreeRecoveryPreviewReadCopyWith<$Res>? get worktree {
    if (_self.worktree == null) {
    return null;
  }

  return $WorktreeRecoveryPreviewReadCopyWith<$Res>(_self.worktree!, (value) {
    return _then(_self.copyWith(worktree: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryIssueRead].
extension RecoveryIssueReadPatterns on RecoveryIssueRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryIssueRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryIssueRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryIssueRead value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryIssueRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryIssueRead value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryIssueRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  RecoveryScope scope,  RecoveryCategory category,  List<RecoveryAction> availableActions,  ReadText? projectId,  ReadText? threadId,  ReadText message,  WorktreeRecoveryPreviewRead? worktree)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryIssueRead() when $default != null:
return $default(_that.id,_that.scope,_that.category,_that.availableActions,_that.projectId,_that.threadId,_that.message,_that.worktree);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  RecoveryScope scope,  RecoveryCategory category,  List<RecoveryAction> availableActions,  ReadText? projectId,  ReadText? threadId,  ReadText message,  WorktreeRecoveryPreviewRead? worktree)  $default,) {final _that = this;
switch (_that) {
case _RecoveryIssueRead():
return $default(_that.id,_that.scope,_that.category,_that.availableActions,_that.projectId,_that.threadId,_that.message,_that.worktree);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  RecoveryScope scope,  RecoveryCategory category,  List<RecoveryAction> availableActions,  ReadText? projectId,  ReadText? threadId,  ReadText message,  WorktreeRecoveryPreviewRead? worktree)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryIssueRead() when $default != null:
return $default(_that.id,_that.scope,_that.category,_that.availableActions,_that.projectId,_that.threadId,_that.message,_that.worktree);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryIssueRead implements RecoveryIssueRead {
  const _RecoveryIssueRead({required this.id, required this.scope, required this.category, required  List<RecoveryAction> availableActions, required this.projectId, required this.threadId, required this.message, required this.worktree}): _availableActions = availableActions;


@override final  ReadText id;
@override final  RecoveryScope scope;
@override final  RecoveryCategory category;
 final  List<RecoveryAction> _availableActions;
@override List<RecoveryAction> get availableActions {
  if (_availableActions is EqualUnmodifiableListView) return _availableActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableActions);
}

@override final  ReadText? projectId;
@override final  ReadText? threadId;
@override final  ReadText message;
@override final  WorktreeRecoveryPreviewRead? worktree;

/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryIssueReadCopyWith<_RecoveryIssueRead> get copyWith => __$RecoveryIssueReadCopyWithImpl<_RecoveryIssueRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryIssueRead&&(identical(other.id, id) || other.id == id)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.category, category) || other.category == category)&&const DeepCollectionEquality().equals(other.availableActions, _availableActions)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.message, message) || other.message == message)&&(identical(other.worktree, worktree) || other.worktree == worktree));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,scope,category,const DeepCollectionEquality().hash(_availableActions),projectId,threadId,message,worktree);
}



}

/// @nodoc
abstract mixin class _$RecoveryIssueReadCopyWith<$Res> implements $RecoveryIssueReadCopyWith<$Res> {
  factory _$RecoveryIssueReadCopyWith(_RecoveryIssueRead value, $Res Function(_RecoveryIssueRead) _then) = __$RecoveryIssueReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, RecoveryScope scope, RecoveryCategory category, List<RecoveryAction> availableActions, ReadText? projectId, ReadText? threadId, ReadText message, WorktreeRecoveryPreviewRead? worktree
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res>? get projectId;@override $ReadTextCopyWith<$Res>? get threadId;@override $ReadTextCopyWith<$Res> get message;@override $WorktreeRecoveryPreviewReadCopyWith<$Res>? get worktree;

}
/// @nodoc
class __$RecoveryIssueReadCopyWithImpl<$Res>
    implements _$RecoveryIssueReadCopyWith<$Res> {
  __$RecoveryIssueReadCopyWithImpl(this._self, this._then);

  final _RecoveryIssueRead _self;
  final $Res Function(_RecoveryIssueRead) _then;

/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? scope = null,Object? category = null,Object? availableActions = null,Object? projectId = freezed,Object? threadId = freezed,Object? message = null,Object? worktree = freezed,}) {
  return _then(_RecoveryIssueRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as RecoveryScope,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as RecoveryCategory,availableActions: null == availableActions ? _self._availableActions : availableActions // ignore: cast_nullable_to_non_nullable
as List<RecoveryAction>,projectId: freezed == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as ReadText?,threadId: freezed == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,worktree: freezed == worktree ? _self.worktree : worktree // ignore: cast_nullable_to_non_nullable
as WorktreeRecoveryPreviewRead?,
  ));
}

/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get projectId {
    if (_self.projectId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.projectId!, (value) {
    return _then(_self.copyWith(projectId: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get threadId {
    if (_self.threadId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.threadId!, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}/// Create a copy of RecoveryIssueRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorktreeRecoveryPreviewReadCopyWith<$Res>? get worktree {
    if (_self.worktree == null) {
    return null;
  }

  return $WorktreeRecoveryPreviewReadCopyWith<$Res>(_self.worktree!, (value) {
    return _then(_self.copyWith(worktree: value));
  });
}
}

/// @nodoc
mixin _$RecoveryEntityRead {

 ProductEntityRef get reference; RecoveryIssueRead get value;
/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryEntityReadCopyWith<RecoveryEntityRead> get copyWith => _$RecoveryEntityReadCopyWithImpl<RecoveryEntityRead>(this as RecoveryEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as RecoveryEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $RecoveryEntityReadCopyWith<$Res>  {
  factory $RecoveryEntityReadCopyWith(RecoveryEntityRead value, $Res Function(RecoveryEntityRead) _then) = _$RecoveryEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, RecoveryIssueRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$RecoveryIssueReadCopyWith<$Res> get value;

}
/// @nodoc
class _$RecoveryEntityReadCopyWithImpl<$Res>
    implements $RecoveryEntityReadCopyWith<$Res> {
  _$RecoveryEntityReadCopyWithImpl(this._self, this._then);

  final RecoveryEntityRead _self;
  final $Res Function(RecoveryEntityRead) _then;

/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(RecoveryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RecoveryIssueRead,
  ));
}
/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryIssueReadCopyWith<$Res> get value {

  return $RecoveryIssueReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryEntityRead].
extension RecoveryEntityReadPatterns on RecoveryEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  RecoveryIssueRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  RecoveryIssueRead value)  $default,) {final _that = this;
switch (_that) {
case _RecoveryEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  RecoveryIssueRead value)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryEntityRead implements RecoveryEntityRead {
  const _RecoveryEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  RecoveryIssueRead value;

/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryEntityReadCopyWith<_RecoveryEntityRead> get copyWith => __$RecoveryEntityReadCopyWithImpl<_RecoveryEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$RecoveryEntityReadCopyWith<$Res> implements $RecoveryEntityReadCopyWith<$Res> {
  factory _$RecoveryEntityReadCopyWith(_RecoveryEntityRead value, $Res Function(_RecoveryEntityRead) _then) = __$RecoveryEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, RecoveryIssueRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $RecoveryIssueReadCopyWith<$Res> get value;

}
/// @nodoc
class __$RecoveryEntityReadCopyWithImpl<$Res>
    implements _$RecoveryEntityReadCopyWith<$Res> {
  __$RecoveryEntityReadCopyWithImpl(this._self, this._then);

  final _RecoveryEntityRead _self;
  final $Res Function(_RecoveryEntityRead) _then;

/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_RecoveryEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RecoveryIssueRead,
  ));
}

/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of RecoveryEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryIssueReadCopyWith<$Res> get value {

  return $RecoveryIssueReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$RecoveryEntryPage {


/// Create a copy of RecoveryEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryEntryPageCopyWith<RecoveryEntryPage> get copyWith => _$RecoveryEntryPageCopyWithImpl<RecoveryEntryPage>(this as RecoveryEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as RecoveryEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as RecoveryEntryPage;
  return 'RecoveryEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $RecoveryEntryPageCopyWith<$Res>  {
  factory $RecoveryEntryPageCopyWith(RecoveryEntryPage value, $Res Function(RecoveryEntryPage) _then) = _$RecoveryEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$RecoveryEntryPageCopyWithImpl<$Res>
    implements $RecoveryEntryPageCopyWith<$Res> {
  _$RecoveryEntryPageCopyWithImpl(this._self, this._then);

  final RecoveryEntryPage _self;
  final $Res Function(RecoveryEntryPage) _then;

/// Create a copy of RecoveryEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(RecoveryEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of RecoveryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryEntryPage].
extension RecoveryEntryPagePatterns on RecoveryEntryPage {
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
mixin _$RecoveryIssueReadPage {


/// Create a copy of RecoveryIssueReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryIssueReadPageCopyWith<RecoveryIssueReadPage> get copyWith => _$RecoveryIssueReadPageCopyWithImpl<RecoveryIssueReadPage>(this as RecoveryIssueReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryIssueReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryIssueReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as RecoveryIssueReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $RecoveryIssueReadPageCopyWith<$Res>  {
  factory $RecoveryIssueReadPageCopyWith(RecoveryIssueReadPage value, $Res Function(RecoveryIssueReadPage) _then) = _$RecoveryIssueReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<RecoveryIssueRead> items, int? nextOffset
});




}
/// @nodoc
class _$RecoveryIssueReadPageCopyWithImpl<$Res>
    implements $RecoveryIssueReadPageCopyWith<$Res> {
  _$RecoveryIssueReadPageCopyWithImpl(this._self, this._then);

  final RecoveryIssueReadPage _self;
  final $Res Function(RecoveryIssueReadPage) _then;

/// Create a copy of RecoveryIssueReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(RecoveryIssueReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<RecoveryIssueRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [RecoveryIssueReadPage].
extension RecoveryIssueReadPagePatterns on RecoveryIssueReadPage {
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

// dart format on
