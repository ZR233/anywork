// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_read_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StorageReadHeader {

 ReadScopeIdentity get scope; HistoryFault? get fault; int get faultGeneration; int? get acceptedSequence; int? get durableSequence; ThreadStorageExecution get execution; bool get pressurePaused; bool get resumeRequired; bool get canResume; ReadText? get lastError;
/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StorageReadHeaderCopyWith<StorageReadHeader> get copyWith => _$StorageReadHeaderCopyWithImpl<StorageReadHeader>(this as StorageReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StorageReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StorageReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.fault, _this.fault) || other.fault == _this.fault)&&(identical(other.faultGeneration, _this.faultGeneration) || other.faultGeneration == _this.faultGeneration)&&(identical(other.acceptedSequence, _this.acceptedSequence) || other.acceptedSequence == _this.acceptedSequence)&&(identical(other.durableSequence, _this.durableSequence) || other.durableSequence == _this.durableSequence)&&(identical(other.execution, _this.execution) || other.execution == _this.execution)&&(identical(other.pressurePaused, _this.pressurePaused) || other.pressurePaused == _this.pressurePaused)&&(identical(other.resumeRequired, _this.resumeRequired) || other.resumeRequired == _this.resumeRequired)&&(identical(other.canResume, _this.canResume) || other.canResume == _this.canResume)&&(identical(other.lastError, _this.lastError) || other.lastError == _this.lastError));
}


@override
int get hashCode {
  final _this = this as StorageReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.fault,_this.faultGeneration,_this.acceptedSequence,_this.durableSequence,_this.execution,_this.pressurePaused,_this.resumeRequired,_this.canResume,_this.lastError);
}



}

/// @nodoc
abstract mixin class $StorageReadHeaderCopyWith<$Res>  {
  factory $StorageReadHeaderCopyWith(StorageReadHeader value, $Res Function(StorageReadHeader) _then) = _$StorageReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, HistoryFault? fault, int faultGeneration, int? acceptedSequence, int? durableSequence, ThreadStorageExecution execution, bool pressurePaused, bool resumeRequired, bool canResume, ReadText? lastError
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ReadTextCopyWith<$Res>? get lastError;

}
/// @nodoc
class _$StorageReadHeaderCopyWithImpl<$Res>
    implements $StorageReadHeaderCopyWith<$Res> {
  _$StorageReadHeaderCopyWithImpl(this._self, this._then);

  final StorageReadHeader _self;
  final $Res Function(StorageReadHeader) _then;

/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? fault = freezed,Object? faultGeneration = null,Object? acceptedSequence = freezed,Object? durableSequence = freezed,Object? execution = null,Object? pressurePaused = null,Object? resumeRequired = null,Object? canResume = null,Object? lastError = freezed,}) {
  return _then(StorageReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,fault: freezed == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as HistoryFault?,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
as int,acceptedSequence: freezed == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int?,durableSequence: freezed == durableSequence ? _self.durableSequence : durableSequence // ignore: cast_nullable_to_non_nullable
as int?,execution: null == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadStorageExecution,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,resumeRequired: null == resumeRequired ? _self.resumeRequired : resumeRequired // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get lastError {
    if (_self.lastError == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.lastError!, (value) {
    return _then(_self.copyWith(lastError: value));
  });
}
}


/// Adds pattern-matching-related methods to [StorageReadHeader].
extension StorageReadHeaderPatterns on StorageReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StorageReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StorageReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StorageReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _StorageReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StorageReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _StorageReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  HistoryFault? fault,  int faultGeneration,  int? acceptedSequence,  int? durableSequence,  ThreadStorageExecution execution,  bool pressurePaused,  bool resumeRequired,  bool canResume,  ReadText? lastError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StorageReadHeader() when $default != null:
return $default(_that.scope,_that.fault,_that.faultGeneration,_that.acceptedSequence,_that.durableSequence,_that.execution,_that.pressurePaused,_that.resumeRequired,_that.canResume,_that.lastError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  HistoryFault? fault,  int faultGeneration,  int? acceptedSequence,  int? durableSequence,  ThreadStorageExecution execution,  bool pressurePaused,  bool resumeRequired,  bool canResume,  ReadText? lastError)  $default,) {final _that = this;
switch (_that) {
case _StorageReadHeader():
return $default(_that.scope,_that.fault,_that.faultGeneration,_that.acceptedSequence,_that.durableSequence,_that.execution,_that.pressurePaused,_that.resumeRequired,_that.canResume,_that.lastError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  HistoryFault? fault,  int faultGeneration,  int? acceptedSequence,  int? durableSequence,  ThreadStorageExecution execution,  bool pressurePaused,  bool resumeRequired,  bool canResume,  ReadText? lastError)?  $default,) {final _that = this;
switch (_that) {
case _StorageReadHeader() when $default != null:
return $default(_that.scope,_that.fault,_that.faultGeneration,_that.acceptedSequence,_that.durableSequence,_that.execution,_that.pressurePaused,_that.resumeRequired,_that.canResume,_that.lastError);case _:
  return null;

}
}

}

/// @nodoc


class _StorageReadHeader implements StorageReadHeader {
  const _StorageReadHeader({required this.scope, required this.fault, required this.faultGeneration, required this.acceptedSequence, required this.durableSequence, required this.execution, required this.pressurePaused, required this.resumeRequired, required this.canResume, required this.lastError});


@override final  ReadScopeIdentity scope;
@override final  HistoryFault? fault;
@override final  int faultGeneration;
@override final  int? acceptedSequence;
@override final  int? durableSequence;
@override final  ThreadStorageExecution execution;
@override final  bool pressurePaused;
@override final  bool resumeRequired;
@override final  bool canResume;
@override final  ReadText? lastError;

/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StorageReadHeaderCopyWith<_StorageReadHeader> get copyWith => __$StorageReadHeaderCopyWithImpl<_StorageReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StorageReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.fault, fault) || other.fault == fault)&&(identical(other.faultGeneration, faultGeneration) || other.faultGeneration == faultGeneration)&&(identical(other.acceptedSequence, acceptedSequence) || other.acceptedSequence == acceptedSequence)&&(identical(other.durableSequence, durableSequence) || other.durableSequence == durableSequence)&&(identical(other.execution, execution) || other.execution == execution)&&(identical(other.pressurePaused, pressurePaused) || other.pressurePaused == pressurePaused)&&(identical(other.resumeRequired, resumeRequired) || other.resumeRequired == resumeRequired)&&(identical(other.canResume, canResume) || other.canResume == canResume)&&(identical(other.lastError, lastError) || other.lastError == lastError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,fault,faultGeneration,acceptedSequence,durableSequence,execution,pressurePaused,resumeRequired,canResume,lastError);
}



}

/// @nodoc
abstract mixin class _$StorageReadHeaderCopyWith<$Res> implements $StorageReadHeaderCopyWith<$Res> {
  factory _$StorageReadHeaderCopyWith(_StorageReadHeader value, $Res Function(_StorageReadHeader) _then) = __$StorageReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, HistoryFault? fault, int faultGeneration, int? acceptedSequence, int? durableSequence, ThreadStorageExecution execution, bool pressurePaused, bool resumeRequired, bool canResume, ReadText? lastError
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ReadTextCopyWith<$Res>? get lastError;

}
/// @nodoc
class __$StorageReadHeaderCopyWithImpl<$Res>
    implements _$StorageReadHeaderCopyWith<$Res> {
  __$StorageReadHeaderCopyWithImpl(this._self, this._then);

  final _StorageReadHeader _self;
  final $Res Function(_StorageReadHeader) _then;

/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? fault = freezed,Object? faultGeneration = null,Object? acceptedSequence = freezed,Object? durableSequence = freezed,Object? execution = null,Object? pressurePaused = null,Object? resumeRequired = null,Object? canResume = null,Object? lastError = freezed,}) {
  return _then(_StorageReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,fault: freezed == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as HistoryFault?,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
as int,acceptedSequence: freezed == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int?,durableSequence: freezed == durableSequence ? _self.durableSequence : durableSequence // ignore: cast_nullable_to_non_nullable
as int?,execution: null == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as ThreadStorageExecution,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,resumeRequired: null == resumeRequired ? _self.resumeRequired : resumeRequired // ignore: cast_nullable_to_non_nullable
as bool,canResume: null == canResume ? _self.canResume : canResume // ignore: cast_nullable_to_non_nullable
as bool,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of StorageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get lastError {
    if (_self.lastError == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.lastError!, (value) {
    return _then(_self.copyWith(lastError: value));
  });
}
}

/// @nodoc
mixin _$MetricsIdentityReadHeader {

 ReadScopeIdentity get scope; ReadText get turnId; ReadText? get attemptId;
/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetricsIdentityReadHeaderCopyWith<MetricsIdentityReadHeader> get copyWith => _$MetricsIdentityReadHeaderCopyWithImpl<MetricsIdentityReadHeader>(this as MetricsIdentityReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as MetricsIdentityReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetricsIdentityReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId));
}


@override
int get hashCode {
  final _this = this as MetricsIdentityReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.turnId,_this.attemptId);
}



}

/// @nodoc
abstract mixin class $MetricsIdentityReadHeaderCopyWith<$Res>  {
  factory $MetricsIdentityReadHeaderCopyWith(MetricsIdentityReadHeader value, $Res Function(MetricsIdentityReadHeader) _then) = _$MetricsIdentityReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, ReadText turnId, ReadText? attemptId
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ReadTextCopyWith<$Res> get turnId;$ReadTextCopyWith<$Res>? get attemptId;

}
/// @nodoc
class _$MetricsIdentityReadHeaderCopyWithImpl<$Res>
    implements $MetricsIdentityReadHeaderCopyWith<$Res> {
  _$MetricsIdentityReadHeaderCopyWithImpl(this._self, this._then);

  final MetricsIdentityReadHeader _self;
  final $Res Function(MetricsIdentityReadHeader) _then;

/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? turnId = null,Object? attemptId = freezed,}) {
  return _then(MetricsIdentityReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get attemptId {
    if (_self.attemptId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.attemptId!, (value) {
    return _then(_self.copyWith(attemptId: value));
  });
}
}


/// Adds pattern-matching-related methods to [MetricsIdentityReadHeader].
extension MetricsIdentityReadHeaderPatterns on MetricsIdentityReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MetricsIdentityReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MetricsIdentityReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MetricsIdentityReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _MetricsIdentityReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MetricsIdentityReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _MetricsIdentityReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText turnId,  ReadText? attemptId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MetricsIdentityReadHeader() when $default != null:
return $default(_that.scope,_that.turnId,_that.attemptId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText turnId,  ReadText? attemptId)  $default,) {final _that = this;
switch (_that) {
case _MetricsIdentityReadHeader():
return $default(_that.scope,_that.turnId,_that.attemptId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  ReadText turnId,  ReadText? attemptId)?  $default,) {final _that = this;
switch (_that) {
case _MetricsIdentityReadHeader() when $default != null:
return $default(_that.scope,_that.turnId,_that.attemptId);case _:
  return null;

}
}

}

/// @nodoc


class _MetricsIdentityReadHeader implements MetricsIdentityReadHeader {
  const _MetricsIdentityReadHeader({required this.scope, required this.turnId, required this.attemptId});


@override final  ReadScopeIdentity scope;
@override final  ReadText turnId;
@override final  ReadText? attemptId;

/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetricsIdentityReadHeaderCopyWith<_MetricsIdentityReadHeader> get copyWith => __$MetricsIdentityReadHeaderCopyWithImpl<_MetricsIdentityReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _MetricsIdentityReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,turnId,attemptId);
}



}

/// @nodoc
abstract mixin class _$MetricsIdentityReadHeaderCopyWith<$Res> implements $MetricsIdentityReadHeaderCopyWith<$Res> {
  factory _$MetricsIdentityReadHeaderCopyWith(_MetricsIdentityReadHeader value, $Res Function(_MetricsIdentityReadHeader) _then) = __$MetricsIdentityReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, ReadText turnId, ReadText? attemptId
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ReadTextCopyWith<$Res> get turnId;@override $ReadTextCopyWith<$Res>? get attemptId;

}
/// @nodoc
class __$MetricsIdentityReadHeaderCopyWithImpl<$Res>
    implements _$MetricsIdentityReadHeaderCopyWith<$Res> {
  __$MetricsIdentityReadHeaderCopyWithImpl(this._self, this._then);

  final _MetricsIdentityReadHeader _self;
  final $Res Function(_MetricsIdentityReadHeader) _then;

/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? turnId = null,Object? attemptId = freezed,}) {
  return _then(_MetricsIdentityReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of MetricsIdentityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get attemptId {
    if (_self.attemptId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.attemptId!, (value) {
    return _then(_self.copyWith(attemptId: value));
  });
}
}

/// @nodoc
mixin _$ContextReadHeader {

 ReadScopeIdentity get scope; ReadText? get frozenModelId; ReadText? get promptCachePolicy; int get estimatedCostCount; int get estimatedCacheSavingCount;
/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContextReadHeaderCopyWith<ContextReadHeader> get copyWith => _$ContextReadHeaderCopyWithImpl<ContextReadHeader>(this as ContextReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContextReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContextReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.frozenModelId, _this.frozenModelId) || other.frozenModelId == _this.frozenModelId)&&(identical(other.promptCachePolicy, _this.promptCachePolicy) || other.promptCachePolicy == _this.promptCachePolicy)&&(identical(other.estimatedCostCount, _this.estimatedCostCount) || other.estimatedCostCount == _this.estimatedCostCount)&&(identical(other.estimatedCacheSavingCount, _this.estimatedCacheSavingCount) || other.estimatedCacheSavingCount == _this.estimatedCacheSavingCount));
}


@override
int get hashCode {
  final _this = this as ContextReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.frozenModelId,_this.promptCachePolicy,_this.estimatedCostCount,_this.estimatedCacheSavingCount);
}



}

/// @nodoc
abstract mixin class $ContextReadHeaderCopyWith<$Res>  {
  factory $ContextReadHeaderCopyWith(ContextReadHeader value, $Res Function(ContextReadHeader) _then) = _$ContextReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, ReadText? frozenModelId, ReadText? promptCachePolicy, int estimatedCostCount, int estimatedCacheSavingCount
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ReadTextCopyWith<$Res>? get frozenModelId;$ReadTextCopyWith<$Res>? get promptCachePolicy;

}
/// @nodoc
class _$ContextReadHeaderCopyWithImpl<$Res>
    implements $ContextReadHeaderCopyWith<$Res> {
  _$ContextReadHeaderCopyWithImpl(this._self, this._then);

  final ContextReadHeader _self;
  final $Res Function(ContextReadHeader) _then;

/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? frozenModelId = freezed,Object? promptCachePolicy = freezed,Object? estimatedCostCount = null,Object? estimatedCacheSavingCount = null,}) {
  return _then(ContextReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,frozenModelId: freezed == frozenModelId ? _self.frozenModelId : frozenModelId // ignore: cast_nullable_to_non_nullable
as ReadText?,promptCachePolicy: freezed == promptCachePolicy ? _self.promptCachePolicy : promptCachePolicy // ignore: cast_nullable_to_non_nullable
as ReadText?,estimatedCostCount: null == estimatedCostCount ? _self.estimatedCostCount : estimatedCostCount // ignore: cast_nullable_to_non_nullable
as int,estimatedCacheSavingCount: null == estimatedCacheSavingCount ? _self.estimatedCacheSavingCount : estimatedCacheSavingCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get frozenModelId {
    if (_self.frozenModelId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.frozenModelId!, (value) {
    return _then(_self.copyWith(frozenModelId: value));
  });
}/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get promptCachePolicy {
    if (_self.promptCachePolicy == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.promptCachePolicy!, (value) {
    return _then(_self.copyWith(promptCachePolicy: value));
  });
}
}


/// Adds pattern-matching-related methods to [ContextReadHeader].
extension ContextReadHeaderPatterns on ContextReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContextReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContextReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContextReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ContextReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContextReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ContextReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText? frozenModelId,  ReadText? promptCachePolicy,  int estimatedCostCount,  int estimatedCacheSavingCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContextReadHeader() when $default != null:
return $default(_that.scope,_that.frozenModelId,_that.promptCachePolicy,_that.estimatedCostCount,_that.estimatedCacheSavingCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText? frozenModelId,  ReadText? promptCachePolicy,  int estimatedCostCount,  int estimatedCacheSavingCount)  $default,) {final _that = this;
switch (_that) {
case _ContextReadHeader():
return $default(_that.scope,_that.frozenModelId,_that.promptCachePolicy,_that.estimatedCostCount,_that.estimatedCacheSavingCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  ReadText? frozenModelId,  ReadText? promptCachePolicy,  int estimatedCostCount,  int estimatedCacheSavingCount)?  $default,) {final _that = this;
switch (_that) {
case _ContextReadHeader() when $default != null:
return $default(_that.scope,_that.frozenModelId,_that.promptCachePolicy,_that.estimatedCostCount,_that.estimatedCacheSavingCount);case _:
  return null;

}
}

}

/// @nodoc


class _ContextReadHeader implements ContextReadHeader {
  const _ContextReadHeader({required this.scope, required this.frozenModelId, required this.promptCachePolicy, required this.estimatedCostCount, required this.estimatedCacheSavingCount});


@override final  ReadScopeIdentity scope;
@override final  ReadText? frozenModelId;
@override final  ReadText? promptCachePolicy;
@override final  int estimatedCostCount;
@override final  int estimatedCacheSavingCount;

/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContextReadHeaderCopyWith<_ContextReadHeader> get copyWith => __$ContextReadHeaderCopyWithImpl<_ContextReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContextReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.frozenModelId, frozenModelId) || other.frozenModelId == frozenModelId)&&(identical(other.promptCachePolicy, promptCachePolicy) || other.promptCachePolicy == promptCachePolicy)&&(identical(other.estimatedCostCount, estimatedCostCount) || other.estimatedCostCount == estimatedCostCount)&&(identical(other.estimatedCacheSavingCount, estimatedCacheSavingCount) || other.estimatedCacheSavingCount == estimatedCacheSavingCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,frozenModelId,promptCachePolicy,estimatedCostCount,estimatedCacheSavingCount);
}



}

/// @nodoc
abstract mixin class _$ContextReadHeaderCopyWith<$Res> implements $ContextReadHeaderCopyWith<$Res> {
  factory _$ContextReadHeaderCopyWith(_ContextReadHeader value, $Res Function(_ContextReadHeader) _then) = __$ContextReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, ReadText? frozenModelId, ReadText? promptCachePolicy, int estimatedCostCount, int estimatedCacheSavingCount
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ReadTextCopyWith<$Res>? get frozenModelId;@override $ReadTextCopyWith<$Res>? get promptCachePolicy;

}
/// @nodoc
class __$ContextReadHeaderCopyWithImpl<$Res>
    implements _$ContextReadHeaderCopyWith<$Res> {
  __$ContextReadHeaderCopyWithImpl(this._self, this._then);

  final _ContextReadHeader _self;
  final $Res Function(_ContextReadHeader) _then;

/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? frozenModelId = freezed,Object? promptCachePolicy = freezed,Object? estimatedCostCount = null,Object? estimatedCacheSavingCount = null,}) {
  return _then(_ContextReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,frozenModelId: freezed == frozenModelId ? _self.frozenModelId : frozenModelId // ignore: cast_nullable_to_non_nullable
as ReadText?,promptCachePolicy: freezed == promptCachePolicy ? _self.promptCachePolicy : promptCachePolicy // ignore: cast_nullable_to_non_nullable
as ReadText?,estimatedCostCount: null == estimatedCostCount ? _self.estimatedCostCount : estimatedCostCount // ignore: cast_nullable_to_non_nullable
as int,estimatedCacheSavingCount: null == estimatedCacheSavingCount ? _self.estimatedCacheSavingCount : estimatedCacheSavingCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get frozenModelId {
    if (_self.frozenModelId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.frozenModelId!, (value) {
    return _then(_self.copyWith(frozenModelId: value));
  });
}/// Create a copy of ContextReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get promptCachePolicy {
    if (_self.promptCachePolicy == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.promptCachePolicy!, (value) {
    return _then(_self.copyWith(promptCachePolicy: value));
  });
}
}

/// @nodoc
mixin _$CostReadItem {

 int get index; ReadText get currency; double get amount;
/// Create a copy of CostReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CostReadItemCopyWith<CostReadItem> get copyWith => _$CostReadItemCopyWithImpl<CostReadItem>(this as CostReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CostReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CostReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.amount, _this.amount) || other.amount == _this.amount));
}


@override
int get hashCode {
  final _this = this as CostReadItem;
  return Object.hash(runtimeType,_this.index,_this.currency,_this.amount);
}



}

/// @nodoc
abstract mixin class $CostReadItemCopyWith<$Res>  {
  factory $CostReadItemCopyWith(CostReadItem value, $Res Function(CostReadItem) _then) = _$CostReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText currency, double amount
});


$ReadTextCopyWith<$Res> get currency;

}
/// @nodoc
class _$CostReadItemCopyWithImpl<$Res>
    implements $CostReadItemCopyWith<$Res> {
  _$CostReadItemCopyWithImpl(this._self, this._then);

  final CostReadItem _self;
  final $Res Function(CostReadItem) _then;

/// Create a copy of CostReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? currency = null,Object? amount = null,}) {
  return _then(CostReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}
/// Create a copy of CostReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}
}


/// Adds pattern-matching-related methods to [CostReadItem].
extension CostReadItemPatterns on CostReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CostReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CostReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CostReadItem value)  $default,){
final _that = this;
switch (_that) {
case _CostReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CostReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _CostReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText currency,  double amount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CostReadItem() when $default != null:
return $default(_that.index,_that.currency,_that.amount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText currency,  double amount)  $default,) {final _that = this;
switch (_that) {
case _CostReadItem():
return $default(_that.index,_that.currency,_that.amount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText currency,  double amount)?  $default,) {final _that = this;
switch (_that) {
case _CostReadItem() when $default != null:
return $default(_that.index,_that.currency,_that.amount);case _:
  return null;

}
}

}

/// @nodoc


class _CostReadItem implements CostReadItem {
  const _CostReadItem({required this.index, required this.currency, required this.amount});


@override final  int index;
@override final  ReadText currency;
@override final  double amount;

/// Create a copy of CostReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CostReadItemCopyWith<_CostReadItem> get copyWith => __$CostReadItemCopyWithImpl<_CostReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CostReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.amount, amount) || other.amount == amount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,currency,amount);
}



}

/// @nodoc
abstract mixin class _$CostReadItemCopyWith<$Res> implements $CostReadItemCopyWith<$Res> {
  factory _$CostReadItemCopyWith(_CostReadItem value, $Res Function(_CostReadItem) _then) = __$CostReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText currency, double amount
});


@override $ReadTextCopyWith<$Res> get currency;

}
/// @nodoc
class __$CostReadItemCopyWithImpl<$Res>
    implements _$CostReadItemCopyWith<$Res> {
  __$CostReadItemCopyWithImpl(this._self, this._then);

  final _CostReadItem _self;
  final $Res Function(_CostReadItem) _then;

/// Create a copy of CostReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? currency = null,Object? amount = null,}) {
  return _then(_CostReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,amount: null == amount ? _self.amount : amount // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

/// Create a copy of CostReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}
}

/// @nodoc
mixin _$CostPage {


/// Create a copy of CostPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CostPageCopyWith<CostPage> get copyWith => _$CostPageCopyWithImpl<CostPage>(this as CostPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CostPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CostPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as CostPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $CostPageCopyWith<$Res>  {
  factory $CostPageCopyWith(CostPage value, $Res Function(CostPage) _then) = _$CostPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<CostReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$CostPageCopyWithImpl<$Res>
    implements $CostPageCopyWith<$Res> {
  _$CostPageCopyWithImpl(this._self, this._then);

  final CostPage _self;
  final $Res Function(CostPage) _then;

/// Create a copy of CostPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(CostPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<CostReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of CostPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [CostPage].
extension CostPagePatterns on CostPage {
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
mixin _$ModelRouteReadValue {

 ReadText? get botId; ReadText get accountId; ReadText get modelId; ReadText? get effort; int get revision; bool get available; ReadText? get unavailableReason;
/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelRouteReadValueCopyWith<ModelRouteReadValue> get copyWith => _$ModelRouteReadValueCopyWithImpl<ModelRouteReadValue>(this as ModelRouteReadValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelRouteReadValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelRouteReadValue&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.available, _this.available) || other.available == _this.available)&&(identical(other.unavailableReason, _this.unavailableReason) || other.unavailableReason == _this.unavailableReason));
}


@override
int get hashCode {
  final _this = this as ModelRouteReadValue;
  return Object.hash(runtimeType,_this.botId,_this.accountId,_this.modelId,_this.effort,_this.revision,_this.available,_this.unavailableReason);
}



}

/// @nodoc
abstract mixin class $ModelRouteReadValueCopyWith<$Res>  {
  factory $ModelRouteReadValueCopyWith(ModelRouteReadValue value, $Res Function(ModelRouteReadValue) _then) = _$ModelRouteReadValueCopyWithImpl;
@useResult
$Res call({
 ReadText? botId, ReadText accountId, ReadText modelId, ReadText? effort, int revision, bool available, ReadText? unavailableReason
});


$ReadTextCopyWith<$Res>? get botId;$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get modelId;$ReadTextCopyWith<$Res>? get effort;$ReadTextCopyWith<$Res>? get unavailableReason;

}
/// @nodoc
class _$ModelRouteReadValueCopyWithImpl<$Res>
    implements $ModelRouteReadValueCopyWith<$Res> {
  _$ModelRouteReadValueCopyWithImpl(this._self, this._then);

  final ModelRouteReadValue _self;
  final $Res Function(ModelRouteReadValue) _then;

/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = freezed,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? revision = null,Object? available = null,Object? unavailableReason = freezed,}) {
  return _then(ModelRouteReadValue(
botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as ReadText?,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,unavailableReason: freezed == unavailableReason ? _self.unavailableReason : unavailableReason // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get botId {
    if (_self.botId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.botId!, (value) {
    return _then(_self.copyWith(botId: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get unavailableReason {
    if (_self.unavailableReason == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.unavailableReason!, (value) {
    return _then(_self.copyWith(unavailableReason: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelRouteReadValue].
extension ModelRouteReadValuePatterns on ModelRouteReadValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelRouteReadValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelRouteReadValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelRouteReadValue value)  $default,){
final _that = this;
switch (_that) {
case _ModelRouteReadValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelRouteReadValue value)?  $default,){
final _that = this;
switch (_that) {
case _ModelRouteReadValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText? botId,  ReadText accountId,  ReadText modelId,  ReadText? effort,  int revision,  bool available,  ReadText? unavailableReason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelRouteReadValue() when $default != null:
return $default(_that.botId,_that.accountId,_that.modelId,_that.effort,_that.revision,_that.available,_that.unavailableReason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText? botId,  ReadText accountId,  ReadText modelId,  ReadText? effort,  int revision,  bool available,  ReadText? unavailableReason)  $default,) {final _that = this;
switch (_that) {
case _ModelRouteReadValue():
return $default(_that.botId,_that.accountId,_that.modelId,_that.effort,_that.revision,_that.available,_that.unavailableReason);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText? botId,  ReadText accountId,  ReadText modelId,  ReadText? effort,  int revision,  bool available,  ReadText? unavailableReason)?  $default,) {final _that = this;
switch (_that) {
case _ModelRouteReadValue() when $default != null:
return $default(_that.botId,_that.accountId,_that.modelId,_that.effort,_that.revision,_that.available,_that.unavailableReason);case _:
  return null;

}
}

}

/// @nodoc


class _ModelRouteReadValue implements ModelRouteReadValue {
  const _ModelRouteReadValue({required this.botId, required this.accountId, required this.modelId, required this.effort, required this.revision, required this.available, required this.unavailableReason});


@override final  ReadText? botId;
@override final  ReadText accountId;
@override final  ReadText modelId;
@override final  ReadText? effort;
@override final  int revision;
@override final  bool available;
@override final  ReadText? unavailableReason;

/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelRouteReadValueCopyWith<_ModelRouteReadValue> get copyWith => __$ModelRouteReadValueCopyWithImpl<_ModelRouteReadValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelRouteReadValue&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.available, available) || other.available == available)&&(identical(other.unavailableReason, unavailableReason) || other.unavailableReason == unavailableReason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,botId,accountId,modelId,effort,revision,available,unavailableReason);
}



}

/// @nodoc
abstract mixin class _$ModelRouteReadValueCopyWith<$Res> implements $ModelRouteReadValueCopyWith<$Res> {
  factory _$ModelRouteReadValueCopyWith(_ModelRouteReadValue value, $Res Function(_ModelRouteReadValue) _then) = __$ModelRouteReadValueCopyWithImpl;
@override @useResult
$Res call({
 ReadText? botId, ReadText accountId, ReadText modelId, ReadText? effort, int revision, bool available, ReadText? unavailableReason
});


@override $ReadTextCopyWith<$Res>? get botId;@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get modelId;@override $ReadTextCopyWith<$Res>? get effort;@override $ReadTextCopyWith<$Res>? get unavailableReason;

}
/// @nodoc
class __$ModelRouteReadValueCopyWithImpl<$Res>
    implements _$ModelRouteReadValueCopyWith<$Res> {
  __$ModelRouteReadValueCopyWithImpl(this._self, this._then);

  final _ModelRouteReadValue _self;
  final $Res Function(_ModelRouteReadValue) _then;

/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? botId = freezed,Object? accountId = null,Object? modelId = null,Object? effort = freezed,Object? revision = null,Object? available = null,Object? unavailableReason = freezed,}) {
  return _then(_ModelRouteReadValue(
botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as ReadText?,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as ReadText,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as ReadText?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,available: null == available ? _self.available : available // ignore: cast_nullable_to_non_nullable
as bool,unavailableReason: freezed == unavailableReason ? _self.unavailableReason : unavailableReason // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get botId {
    if (_self.botId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.botId!, (value) {
    return _then(_self.copyWith(botId: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelId {

  return $ReadTextCopyWith<$Res>(_self.modelId, (value) {
    return _then(_self.copyWith(modelId: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get effort {
    if (_self.effort == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.effort!, (value) {
    return _then(_self.copyWith(effort: value));
  });
}/// Create a copy of ModelRouteReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get unavailableReason {
    if (_self.unavailableReason == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.unavailableReason!, (value) {
    return _then(_self.copyWith(unavailableReason: value));
  });
}
}

/// @nodoc
mixin _$ThreadConfigurationReadHeader {

 ReadScopeIdentity get scope; ModelRouteReadValue? get route; int get activeSkillCount;
/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationReadHeaderCopyWith<ThreadConfigurationReadHeader> get copyWith => _$ThreadConfigurationReadHeaderCopyWithImpl<ThreadConfigurationReadHeader>(this as ThreadConfigurationReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadConfigurationReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.route, _this.route) || other.route == _this.route)&&(identical(other.activeSkillCount, _this.activeSkillCount) || other.activeSkillCount == _this.activeSkillCount));
}


@override
int get hashCode {
  final _this = this as ThreadConfigurationReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.route,_this.activeSkillCount);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationReadHeaderCopyWith<$Res>  {
  factory $ThreadConfigurationReadHeaderCopyWith(ThreadConfigurationReadHeader value, $Res Function(ThreadConfigurationReadHeader) _then) = _$ThreadConfigurationReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, ModelRouteReadValue? route, int activeSkillCount
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ModelRouteReadValueCopyWith<$Res>? get route;

}
/// @nodoc
class _$ThreadConfigurationReadHeaderCopyWithImpl<$Res>
    implements $ThreadConfigurationReadHeaderCopyWith<$Res> {
  _$ThreadConfigurationReadHeaderCopyWithImpl(this._self, this._then);

  final ThreadConfigurationReadHeader _self;
  final $Res Function(ThreadConfigurationReadHeader) _then;

/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? route = freezed,Object? activeSkillCount = null,}) {
  return _then(ThreadConfigurationReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,route: freezed == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as ModelRouteReadValue?,activeSkillCount: null == activeSkillCount ? _self.activeSkillCount : activeSkillCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelRouteReadValueCopyWith<$Res>? get route {
    if (_self.route == null) {
    return null;
  }

  return $ModelRouteReadValueCopyWith<$Res>(_self.route!, (value) {
    return _then(_self.copyWith(route: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadConfigurationReadHeader].
extension ThreadConfigurationReadHeaderPatterns on ThreadConfigurationReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadConfigurationReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadConfigurationReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadConfigurationReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadConfigurationReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ModelRouteReadValue? route,  int activeSkillCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadConfigurationReadHeader() when $default != null:
return $default(_that.scope,_that.route,_that.activeSkillCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ModelRouteReadValue? route,  int activeSkillCount)  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationReadHeader():
return $default(_that.scope,_that.route,_that.activeSkillCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  ModelRouteReadValue? route,  int activeSkillCount)?  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationReadHeader() when $default != null:
return $default(_that.scope,_that.route,_that.activeSkillCount);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadConfigurationReadHeader implements ThreadConfigurationReadHeader {
  const _ThreadConfigurationReadHeader({required this.scope, required this.route, required this.activeSkillCount});


@override final  ReadScopeIdentity scope;
@override final  ModelRouteReadValue? route;
@override final  int activeSkillCount;

/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadConfigurationReadHeaderCopyWith<_ThreadConfigurationReadHeader> get copyWith => __$ThreadConfigurationReadHeaderCopyWithImpl<_ThreadConfigurationReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadConfigurationReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.route, route) || other.route == route)&&(identical(other.activeSkillCount, activeSkillCount) || other.activeSkillCount == activeSkillCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,route,activeSkillCount);
}



}

/// @nodoc
abstract mixin class _$ThreadConfigurationReadHeaderCopyWith<$Res> implements $ThreadConfigurationReadHeaderCopyWith<$Res> {
  factory _$ThreadConfigurationReadHeaderCopyWith(_ThreadConfigurationReadHeader value, $Res Function(_ThreadConfigurationReadHeader) _then) = __$ThreadConfigurationReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, ModelRouteReadValue? route, int activeSkillCount
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ModelRouteReadValueCopyWith<$Res>? get route;

}
/// @nodoc
class __$ThreadConfigurationReadHeaderCopyWithImpl<$Res>
    implements _$ThreadConfigurationReadHeaderCopyWith<$Res> {
  __$ThreadConfigurationReadHeaderCopyWithImpl(this._self, this._then);

  final _ThreadConfigurationReadHeader _self;
  final $Res Function(_ThreadConfigurationReadHeader) _then;

/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? route = freezed,Object? activeSkillCount = null,}) {
  return _then(_ThreadConfigurationReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,route: freezed == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as ModelRouteReadValue?,activeSkillCount: null == activeSkillCount ? _self.activeSkillCount : activeSkillCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ThreadConfigurationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelRouteReadValueCopyWith<$Res>? get route {
    if (_self.route == null) {
    return null;
  }

  return $ModelRouteReadValueCopyWith<$Res>(_self.route!, (value) {
    return _then(_self.copyWith(route: value));
  });
}
}

/// @nodoc
mixin _$SkillNameReadItem {

 int get index; ReadText get name;
/// Create a copy of SkillNameReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillNameReadItemCopyWith<SkillNameReadItem> get copyWith => _$SkillNameReadItemCopyWithImpl<SkillNameReadItem>(this as SkillNameReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillNameReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillNameReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.name, _this.name) || other.name == _this.name));
}


@override
int get hashCode {
  final _this = this as SkillNameReadItem;
  return Object.hash(runtimeType,_this.index,_this.name);
}



}

/// @nodoc
abstract mixin class $SkillNameReadItemCopyWith<$Res>  {
  factory $SkillNameReadItemCopyWith(SkillNameReadItem value, $Res Function(SkillNameReadItem) _then) = _$SkillNameReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText name
});


$ReadTextCopyWith<$Res> get name;

}
/// @nodoc
class _$SkillNameReadItemCopyWithImpl<$Res>
    implements $SkillNameReadItemCopyWith<$Res> {
  _$SkillNameReadItemCopyWithImpl(this._self, this._then);

  final SkillNameReadItem _self;
  final $Res Function(SkillNameReadItem) _then;

/// Create a copy of SkillNameReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? name = null,}) {
  return _then(SkillNameReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of SkillNameReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillNameReadItem].
extension SkillNameReadItemPatterns on SkillNameReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillNameReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillNameReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillNameReadItem value)  $default,){
final _that = this;
switch (_that) {
case _SkillNameReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillNameReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _SkillNameReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillNameReadItem() when $default != null:
return $default(_that.index,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText name)  $default,) {final _that = this;
switch (_that) {
case _SkillNameReadItem():
return $default(_that.index,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText name)?  $default,) {final _that = this;
switch (_that) {
case _SkillNameReadItem() when $default != null:
return $default(_that.index,_that.name);case _:
  return null;

}
}

}

/// @nodoc


class _SkillNameReadItem implements SkillNameReadItem {
  const _SkillNameReadItem({required this.index, required this.name});


@override final  int index;
@override final  ReadText name;

/// Create a copy of SkillNameReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillNameReadItemCopyWith<_SkillNameReadItem> get copyWith => __$SkillNameReadItemCopyWithImpl<_SkillNameReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillNameReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,name);
}



}

/// @nodoc
abstract mixin class _$SkillNameReadItemCopyWith<$Res> implements $SkillNameReadItemCopyWith<$Res> {
  factory _$SkillNameReadItemCopyWith(_SkillNameReadItem value, $Res Function(_SkillNameReadItem) _then) = __$SkillNameReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText name
});


@override $ReadTextCopyWith<$Res> get name;

}
/// @nodoc
class __$SkillNameReadItemCopyWithImpl<$Res>
    implements _$SkillNameReadItemCopyWith<$Res> {
  __$SkillNameReadItemCopyWithImpl(this._self, this._then);

  final _SkillNameReadItem _self;
  final $Res Function(_SkillNameReadItem) _then;

/// Create a copy of SkillNameReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? name = null,}) {
  return _then(_SkillNameReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of SkillNameReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}
}

/// @nodoc
mixin _$SkillNamePage {


/// Create a copy of SkillNamePage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillNamePageCopyWith<SkillNamePage> get copyWith => _$SkillNamePageCopyWithImpl<SkillNamePage>(this as SkillNamePage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillNamePage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillNamePage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as SkillNamePage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $SkillNamePageCopyWith<$Res>  {
  factory $SkillNamePageCopyWith(SkillNamePage value, $Res Function(SkillNamePage) _then) = _$SkillNamePageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<SkillNameReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$SkillNamePageCopyWithImpl<$Res>
    implements $SkillNamePageCopyWith<$Res> {
  _$SkillNamePageCopyWithImpl(this._self, this._then);

  final SkillNamePage _self;
  final $Res Function(SkillNamePage) _then;

/// Create a copy of SkillNamePage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(SkillNamePage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<SkillNameReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of SkillNamePage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillNamePage].
extension SkillNamePagePatterns on SkillNamePage {
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
mixin _$TodoReadHeader {

 ReadScopeIdentity get scope; ReadText? get callId; ReadText? get agentId; ReadText? get path; ReadText? get parentPath; ReadText? get explanation; int get itemCount;
/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TodoReadHeaderCopyWith<TodoReadHeader> get copyWith => _$TodoReadHeaderCopyWithImpl<TodoReadHeader>(this as TodoReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TodoReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.callId, _this.callId) || other.callId == _this.callId)&&(identical(other.agentId, _this.agentId) || other.agentId == _this.agentId)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parentPath, _this.parentPath) || other.parentPath == _this.parentPath)&&(identical(other.explanation, _this.explanation) || other.explanation == _this.explanation)&&(identical(other.itemCount, _this.itemCount) || other.itemCount == _this.itemCount));
}


@override
int get hashCode {
  final _this = this as TodoReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.callId,_this.agentId,_this.path,_this.parentPath,_this.explanation,_this.itemCount);
}



}

/// @nodoc
abstract mixin class $TodoReadHeaderCopyWith<$Res>  {
  factory $TodoReadHeaderCopyWith(TodoReadHeader value, $Res Function(TodoReadHeader) _then) = _$TodoReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, ReadText? callId, ReadText? agentId, ReadText? path, ReadText? parentPath, ReadText? explanation, int itemCount
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ReadTextCopyWith<$Res>? get callId;$ReadTextCopyWith<$Res>? get agentId;$ReadTextCopyWith<$Res>? get path;$ReadTextCopyWith<$Res>? get parentPath;$ReadTextCopyWith<$Res>? get explanation;

}
/// @nodoc
class _$TodoReadHeaderCopyWithImpl<$Res>
    implements $TodoReadHeaderCopyWith<$Res> {
  _$TodoReadHeaderCopyWithImpl(this._self, this._then);

  final TodoReadHeader _self;
  final $Res Function(TodoReadHeader) _then;

/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? callId = freezed,Object? agentId = freezed,Object? path = freezed,Object? parentPath = freezed,Object? explanation = freezed,Object? itemCount = null,}) {
  return _then(TodoReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,callId: freezed == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as ReadText?,agentId: freezed == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as ReadText?,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText?,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as ReadText?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as ReadText?,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get callId {
    if (_self.callId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.callId!, (value) {
    return _then(_self.copyWith(callId: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get agentId {
    if (_self.agentId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.agentId!, (value) {
    return _then(_self.copyWith(agentId: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get path {
    if (_self.path == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.path!, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parentPath {
    if (_self.parentPath == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parentPath!, (value) {
    return _then(_self.copyWith(parentPath: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get explanation {
    if (_self.explanation == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.explanation!, (value) {
    return _then(_self.copyWith(explanation: value));
  });
}
}


/// Adds pattern-matching-related methods to [TodoReadHeader].
extension TodoReadHeaderPatterns on TodoReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TodoReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TodoReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TodoReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _TodoReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TodoReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _TodoReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText? callId,  ReadText? agentId,  ReadText? path,  ReadText? parentPath,  ReadText? explanation,  int itemCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TodoReadHeader() when $default != null:
return $default(_that.scope,_that.callId,_that.agentId,_that.path,_that.parentPath,_that.explanation,_that.itemCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText? callId,  ReadText? agentId,  ReadText? path,  ReadText? parentPath,  ReadText? explanation,  int itemCount)  $default,) {final _that = this;
switch (_that) {
case _TodoReadHeader():
return $default(_that.scope,_that.callId,_that.agentId,_that.path,_that.parentPath,_that.explanation,_that.itemCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  ReadText? callId,  ReadText? agentId,  ReadText? path,  ReadText? parentPath,  ReadText? explanation,  int itemCount)?  $default,) {final _that = this;
switch (_that) {
case _TodoReadHeader() when $default != null:
return $default(_that.scope,_that.callId,_that.agentId,_that.path,_that.parentPath,_that.explanation,_that.itemCount);case _:
  return null;

}
}

}

/// @nodoc


class _TodoReadHeader implements TodoReadHeader {
  const _TodoReadHeader({required this.scope, required this.callId, required this.agentId, required this.path, required this.parentPath, required this.explanation, required this.itemCount});


@override final  ReadScopeIdentity scope;
@override final  ReadText? callId;
@override final  ReadText? agentId;
@override final  ReadText? path;
@override final  ReadText? parentPath;
@override final  ReadText? explanation;
@override final  int itemCount;

/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TodoReadHeaderCopyWith<_TodoReadHeader> get copyWith => __$TodoReadHeaderCopyWithImpl<_TodoReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TodoReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.callId, callId) || other.callId == callId)&&(identical(other.agentId, agentId) || other.agentId == agentId)&&(identical(other.path, path) || other.path == path)&&(identical(other.parentPath, parentPath) || other.parentPath == parentPath)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.itemCount, itemCount) || other.itemCount == itemCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,callId,agentId,path,parentPath,explanation,itemCount);
}



}

/// @nodoc
abstract mixin class _$TodoReadHeaderCopyWith<$Res> implements $TodoReadHeaderCopyWith<$Res> {
  factory _$TodoReadHeaderCopyWith(_TodoReadHeader value, $Res Function(_TodoReadHeader) _then) = __$TodoReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, ReadText? callId, ReadText? agentId, ReadText? path, ReadText? parentPath, ReadText? explanation, int itemCount
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ReadTextCopyWith<$Res>? get callId;@override $ReadTextCopyWith<$Res>? get agentId;@override $ReadTextCopyWith<$Res>? get path;@override $ReadTextCopyWith<$Res>? get parentPath;@override $ReadTextCopyWith<$Res>? get explanation;

}
/// @nodoc
class __$TodoReadHeaderCopyWithImpl<$Res>
    implements _$TodoReadHeaderCopyWith<$Res> {
  __$TodoReadHeaderCopyWithImpl(this._self, this._then);

  final _TodoReadHeader _self;
  final $Res Function(_TodoReadHeader) _then;

/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? callId = freezed,Object? agentId = freezed,Object? path = freezed,Object? parentPath = freezed,Object? explanation = freezed,Object? itemCount = null,}) {
  return _then(_TodoReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,callId: freezed == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as ReadText?,agentId: freezed == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as ReadText?,path: freezed == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText?,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as ReadText?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as ReadText?,itemCount: null == itemCount ? _self.itemCount : itemCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get callId {
    if (_self.callId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.callId!, (value) {
    return _then(_self.copyWith(callId: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get agentId {
    if (_self.agentId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.agentId!, (value) {
    return _then(_self.copyWith(agentId: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get path {
    if (_self.path == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.path!, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parentPath {
    if (_self.parentPath == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parentPath!, (value) {
    return _then(_self.copyWith(parentPath: value));
  });
}/// Create a copy of TodoReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get explanation {
    if (_self.explanation == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.explanation!, (value) {
    return _then(_self.copyWith(explanation: value));
  });
}
}

/// @nodoc
mixin _$TodoReadItem {

 int get index; ReadText get step; TodoItemStatus get status;
/// Create a copy of TodoReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TodoReadItemCopyWith<TodoReadItem> get copyWith => _$TodoReadItemCopyWithImpl<TodoReadItem>(this as TodoReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TodoReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.step, _this.step) || other.step == _this.step)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as TodoReadItem;
  return Object.hash(runtimeType,_this.index,_this.step,_this.status);
}



}

/// @nodoc
abstract mixin class $TodoReadItemCopyWith<$Res>  {
  factory $TodoReadItemCopyWith(TodoReadItem value, $Res Function(TodoReadItem) _then) = _$TodoReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText step, TodoItemStatus status
});


$ReadTextCopyWith<$Res> get step;

}
/// @nodoc
class _$TodoReadItemCopyWithImpl<$Res>
    implements $TodoReadItemCopyWith<$Res> {
  _$TodoReadItemCopyWithImpl(this._self, this._then);

  final TodoReadItem _self;
  final $Res Function(TodoReadItem) _then;

/// Create a copy of TodoReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? step = null,Object? status = null,}) {
  return _then(TodoReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as ReadText,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TodoItemStatus,
  ));
}
/// Create a copy of TodoReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get step {

  return $ReadTextCopyWith<$Res>(_self.step, (value) {
    return _then(_self.copyWith(step: value));
  });
}
}


/// Adds pattern-matching-related methods to [TodoReadItem].
extension TodoReadItemPatterns on TodoReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TodoReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TodoReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TodoReadItem value)  $default,){
final _that = this;
switch (_that) {
case _TodoReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TodoReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _TodoReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText step,  TodoItemStatus status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TodoReadItem() when $default != null:
return $default(_that.index,_that.step,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText step,  TodoItemStatus status)  $default,) {final _that = this;
switch (_that) {
case _TodoReadItem():
return $default(_that.index,_that.step,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText step,  TodoItemStatus status)?  $default,) {final _that = this;
switch (_that) {
case _TodoReadItem() when $default != null:
return $default(_that.index,_that.step,_that.status);case _:
  return null;

}
}

}

/// @nodoc


class _TodoReadItem implements TodoReadItem {
  const _TodoReadItem({required this.index, required this.step, required this.status});


@override final  int index;
@override final  ReadText step;
@override final  TodoItemStatus status;

/// Create a copy of TodoReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TodoReadItemCopyWith<_TodoReadItem> get copyWith => __$TodoReadItemCopyWithImpl<_TodoReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TodoReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.step, step) || other.step == step)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,step,status);
}



}

/// @nodoc
abstract mixin class _$TodoReadItemCopyWith<$Res> implements $TodoReadItemCopyWith<$Res> {
  factory _$TodoReadItemCopyWith(_TodoReadItem value, $Res Function(_TodoReadItem) _then) = __$TodoReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText step, TodoItemStatus status
});


@override $ReadTextCopyWith<$Res> get step;

}
/// @nodoc
class __$TodoReadItemCopyWithImpl<$Res>
    implements _$TodoReadItemCopyWith<$Res> {
  __$TodoReadItemCopyWithImpl(this._self, this._then);

  final _TodoReadItem _self;
  final $Res Function(_TodoReadItem) _then;

/// Create a copy of TodoReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? step = null,Object? status = null,}) {
  return _then(_TodoReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,step: null == step ? _self.step : step // ignore: cast_nullable_to_non_nullable
as ReadText,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TodoItemStatus,
  ));
}

/// Create a copy of TodoReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get step {

  return $ReadTextCopyWith<$Res>(_self.step, (value) {
    return _then(_self.copyWith(step: value));
  });
}
}

/// @nodoc
mixin _$TodoItemPage {


/// Create a copy of TodoItemPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TodoItemPageCopyWith<TodoItemPage> get copyWith => _$TodoItemPageCopyWithImpl<TodoItemPage>(this as TodoItemPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TodoItemPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoItemPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as TodoItemPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $TodoItemPageCopyWith<$Res>  {
  factory $TodoItemPageCopyWith(TodoItemPage value, $Res Function(TodoItemPage) _then) = _$TodoItemPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<TodoReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$TodoItemPageCopyWithImpl<$Res>
    implements $TodoItemPageCopyWith<$Res> {
  _$TodoItemPageCopyWithImpl(this._self, this._then);

  final TodoItemPage _self;
  final $Res Function(TodoItemPage) _then;

/// Create a copy of TodoItemPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(TodoItemPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<TodoReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of TodoItemPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [TodoItemPage].
extension TodoItemPagePatterns on TodoItemPage {
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
mixin _$WorkflowRunReadValue {

 ReadText get lineageId; ReadText get runId; ReadText get modeId; int get graphRevision; ReadText get graphHash; WorkflowLifecycle get lifecycle; ReadText get currentStateId; int get startedAt; int get updatedAt; ReadText get currentStateTitle; ReadText get modeDisplayName; bool get modeDeleted;
/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowRunReadValueCopyWith<WorkflowRunReadValue> get copyWith => _$WorkflowRunReadValueCopyWithImpl<WorkflowRunReadValue>(this as WorkflowRunReadValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowRunReadValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowRunReadValue&&(identical(other.lineageId, _this.lineageId) || other.lineageId == _this.lineageId)&&(identical(other.runId, _this.runId) || other.runId == _this.runId)&&(identical(other.modeId, _this.modeId) || other.modeId == _this.modeId)&&(identical(other.graphRevision, _this.graphRevision) || other.graphRevision == _this.graphRevision)&&(identical(other.graphHash, _this.graphHash) || other.graphHash == _this.graphHash)&&(identical(other.lifecycle, _this.lifecycle) || other.lifecycle == _this.lifecycle)&&(identical(other.currentStateId, _this.currentStateId) || other.currentStateId == _this.currentStateId)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.currentStateTitle, _this.currentStateTitle) || other.currentStateTitle == _this.currentStateTitle)&&(identical(other.modeDisplayName, _this.modeDisplayName) || other.modeDisplayName == _this.modeDisplayName)&&(identical(other.modeDeleted, _this.modeDeleted) || other.modeDeleted == _this.modeDeleted));
}


@override
int get hashCode {
  final _this = this as WorkflowRunReadValue;
  return Object.hash(runtimeType,_this.lineageId,_this.runId,_this.modeId,_this.graphRevision,_this.graphHash,_this.lifecycle,_this.currentStateId,_this.startedAt,_this.updatedAt,_this.currentStateTitle,_this.modeDisplayName,_this.modeDeleted);
}



}

/// @nodoc
abstract mixin class $WorkflowRunReadValueCopyWith<$Res>  {
  factory $WorkflowRunReadValueCopyWith(WorkflowRunReadValue value, $Res Function(WorkflowRunReadValue) _then) = _$WorkflowRunReadValueCopyWithImpl;
@useResult
$Res call({
 ReadText lineageId, ReadText runId, ReadText modeId, int graphRevision, ReadText graphHash, WorkflowLifecycle lifecycle, ReadText currentStateId, int startedAt, int updatedAt, ReadText currentStateTitle, ReadText modeDisplayName, bool modeDeleted
});


$ReadTextCopyWith<$Res> get lineageId;$ReadTextCopyWith<$Res> get runId;$ReadTextCopyWith<$Res> get modeId;$ReadTextCopyWith<$Res> get graphHash;$ReadTextCopyWith<$Res> get currentStateId;$ReadTextCopyWith<$Res> get currentStateTitle;$ReadTextCopyWith<$Res> get modeDisplayName;

}
/// @nodoc
class _$WorkflowRunReadValueCopyWithImpl<$Res>
    implements $WorkflowRunReadValueCopyWith<$Res> {
  _$WorkflowRunReadValueCopyWithImpl(this._self, this._then);

  final WorkflowRunReadValue _self;
  final $Res Function(WorkflowRunReadValue) _then;

/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lineageId = null,Object? runId = null,Object? modeId = null,Object? graphRevision = null,Object? graphHash = null,Object? lifecycle = null,Object? currentStateId = null,Object? startedAt = null,Object? updatedAt = null,Object? currentStateTitle = null,Object? modeDisplayName = null,Object? modeDeleted = null,}) {
  return _then(WorkflowRunReadValue(
lineageId: null == lineageId ? _self.lineageId : lineageId // ignore: cast_nullable_to_non_nullable
as ReadText,runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as ReadText,modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as ReadText,graphRevision: null == graphRevision ? _self.graphRevision : graphRevision // ignore: cast_nullable_to_non_nullable
as int,graphHash: null == graphHash ? _self.graphHash : graphHash // ignore: cast_nullable_to_non_nullable
as ReadText,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as WorkflowLifecycle,currentStateId: null == currentStateId ? _self.currentStateId : currentStateId // ignore: cast_nullable_to_non_nullable
as ReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,currentStateTitle: null == currentStateTitle ? _self.currentStateTitle : currentStateTitle // ignore: cast_nullable_to_non_nullable
as ReadText,modeDisplayName: null == modeDisplayName ? _self.modeDisplayName : modeDisplayName // ignore: cast_nullable_to_non_nullable
as ReadText,modeDeleted: null == modeDeleted ? _self.modeDeleted : modeDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get lineageId {

  return $ReadTextCopyWith<$Res>(_self.lineageId, (value) {
    return _then(_self.copyWith(lineageId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get runId {

  return $ReadTextCopyWith<$Res>(_self.runId, (value) {
    return _then(_self.copyWith(runId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modeId {

  return $ReadTextCopyWith<$Res>(_self.modeId, (value) {
    return _then(_self.copyWith(modeId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get graphHash {

  return $ReadTextCopyWith<$Res>(_self.graphHash, (value) {
    return _then(_self.copyWith(graphHash: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currentStateId {

  return $ReadTextCopyWith<$Res>(_self.currentStateId, (value) {
    return _then(_self.copyWith(currentStateId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currentStateTitle {

  return $ReadTextCopyWith<$Res>(_self.currentStateTitle, (value) {
    return _then(_self.copyWith(currentStateTitle: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modeDisplayName {

  return $ReadTextCopyWith<$Res>(_self.modeDisplayName, (value) {
    return _then(_self.copyWith(modeDisplayName: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkflowRunReadValue].
extension WorkflowRunReadValuePatterns on WorkflowRunReadValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowRunReadValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowRunReadValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowRunReadValue value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowRunReadValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowRunReadValue value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowRunReadValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText lineageId,  ReadText runId,  ReadText modeId,  int graphRevision,  ReadText graphHash,  WorkflowLifecycle lifecycle,  ReadText currentStateId,  int startedAt,  int updatedAt,  ReadText currentStateTitle,  ReadText modeDisplayName,  bool modeDeleted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowRunReadValue() when $default != null:
return $default(_that.lineageId,_that.runId,_that.modeId,_that.graphRevision,_that.graphHash,_that.lifecycle,_that.currentStateId,_that.startedAt,_that.updatedAt,_that.currentStateTitle,_that.modeDisplayName,_that.modeDeleted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText lineageId,  ReadText runId,  ReadText modeId,  int graphRevision,  ReadText graphHash,  WorkflowLifecycle lifecycle,  ReadText currentStateId,  int startedAt,  int updatedAt,  ReadText currentStateTitle,  ReadText modeDisplayName,  bool modeDeleted)  $default,) {final _that = this;
switch (_that) {
case _WorkflowRunReadValue():
return $default(_that.lineageId,_that.runId,_that.modeId,_that.graphRevision,_that.graphHash,_that.lifecycle,_that.currentStateId,_that.startedAt,_that.updatedAt,_that.currentStateTitle,_that.modeDisplayName,_that.modeDeleted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText lineageId,  ReadText runId,  ReadText modeId,  int graphRevision,  ReadText graphHash,  WorkflowLifecycle lifecycle,  ReadText currentStateId,  int startedAt,  int updatedAt,  ReadText currentStateTitle,  ReadText modeDisplayName,  bool modeDeleted)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowRunReadValue() when $default != null:
return $default(_that.lineageId,_that.runId,_that.modeId,_that.graphRevision,_that.graphHash,_that.lifecycle,_that.currentStateId,_that.startedAt,_that.updatedAt,_that.currentStateTitle,_that.modeDisplayName,_that.modeDeleted);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowRunReadValue implements WorkflowRunReadValue {
  const _WorkflowRunReadValue({required this.lineageId, required this.runId, required this.modeId, required this.graphRevision, required this.graphHash, required this.lifecycle, required this.currentStateId, required this.startedAt, required this.updatedAt, required this.currentStateTitle, required this.modeDisplayName, required this.modeDeleted});


@override final  ReadText lineageId;
@override final  ReadText runId;
@override final  ReadText modeId;
@override final  int graphRevision;
@override final  ReadText graphHash;
@override final  WorkflowLifecycle lifecycle;
@override final  ReadText currentStateId;
@override final  int startedAt;
@override final  int updatedAt;
@override final  ReadText currentStateTitle;
@override final  ReadText modeDisplayName;
@override final  bool modeDeleted;

/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowRunReadValueCopyWith<_WorkflowRunReadValue> get copyWith => __$WorkflowRunReadValueCopyWithImpl<_WorkflowRunReadValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowRunReadValue&&(identical(other.lineageId, lineageId) || other.lineageId == lineageId)&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.modeId, modeId) || other.modeId == modeId)&&(identical(other.graphRevision, graphRevision) || other.graphRevision == graphRevision)&&(identical(other.graphHash, graphHash) || other.graphHash == graphHash)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&(identical(other.currentStateId, currentStateId) || other.currentStateId == currentStateId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.currentStateTitle, currentStateTitle) || other.currentStateTitle == currentStateTitle)&&(identical(other.modeDisplayName, modeDisplayName) || other.modeDisplayName == modeDisplayName)&&(identical(other.modeDeleted, modeDeleted) || other.modeDeleted == modeDeleted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,lineageId,runId,modeId,graphRevision,graphHash,lifecycle,currentStateId,startedAt,updatedAt,currentStateTitle,modeDisplayName,modeDeleted);
}



}

/// @nodoc
abstract mixin class _$WorkflowRunReadValueCopyWith<$Res> implements $WorkflowRunReadValueCopyWith<$Res> {
  factory _$WorkflowRunReadValueCopyWith(_WorkflowRunReadValue value, $Res Function(_WorkflowRunReadValue) _then) = __$WorkflowRunReadValueCopyWithImpl;
@override @useResult
$Res call({
 ReadText lineageId, ReadText runId, ReadText modeId, int graphRevision, ReadText graphHash, WorkflowLifecycle lifecycle, ReadText currentStateId, int startedAt, int updatedAt, ReadText currentStateTitle, ReadText modeDisplayName, bool modeDeleted
});


@override $ReadTextCopyWith<$Res> get lineageId;@override $ReadTextCopyWith<$Res> get runId;@override $ReadTextCopyWith<$Res> get modeId;@override $ReadTextCopyWith<$Res> get graphHash;@override $ReadTextCopyWith<$Res> get currentStateId;@override $ReadTextCopyWith<$Res> get currentStateTitle;@override $ReadTextCopyWith<$Res> get modeDisplayName;

}
/// @nodoc
class __$WorkflowRunReadValueCopyWithImpl<$Res>
    implements _$WorkflowRunReadValueCopyWith<$Res> {
  __$WorkflowRunReadValueCopyWithImpl(this._self, this._then);

  final _WorkflowRunReadValue _self;
  final $Res Function(_WorkflowRunReadValue) _then;

/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? lineageId = null,Object? runId = null,Object? modeId = null,Object? graphRevision = null,Object? graphHash = null,Object? lifecycle = null,Object? currentStateId = null,Object? startedAt = null,Object? updatedAt = null,Object? currentStateTitle = null,Object? modeDisplayName = null,Object? modeDeleted = null,}) {
  return _then(_WorkflowRunReadValue(
lineageId: null == lineageId ? _self.lineageId : lineageId // ignore: cast_nullable_to_non_nullable
as ReadText,runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as ReadText,modeId: null == modeId ? _self.modeId : modeId // ignore: cast_nullable_to_non_nullable
as ReadText,graphRevision: null == graphRevision ? _self.graphRevision : graphRevision // ignore: cast_nullable_to_non_nullable
as int,graphHash: null == graphHash ? _self.graphHash : graphHash // ignore: cast_nullable_to_non_nullable
as ReadText,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as WorkflowLifecycle,currentStateId: null == currentStateId ? _self.currentStateId : currentStateId // ignore: cast_nullable_to_non_nullable
as ReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,currentStateTitle: null == currentStateTitle ? _self.currentStateTitle : currentStateTitle // ignore: cast_nullable_to_non_nullable
as ReadText,modeDisplayName: null == modeDisplayName ? _self.modeDisplayName : modeDisplayName // ignore: cast_nullable_to_non_nullable
as ReadText,modeDeleted: null == modeDeleted ? _self.modeDeleted : modeDeleted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get lineageId {

  return $ReadTextCopyWith<$Res>(_self.lineageId, (value) {
    return _then(_self.copyWith(lineageId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get runId {

  return $ReadTextCopyWith<$Res>(_self.runId, (value) {
    return _then(_self.copyWith(runId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modeId {

  return $ReadTextCopyWith<$Res>(_self.modeId, (value) {
    return _then(_self.copyWith(modeId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get graphHash {

  return $ReadTextCopyWith<$Res>(_self.graphHash, (value) {
    return _then(_self.copyWith(graphHash: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currentStateId {

  return $ReadTextCopyWith<$Res>(_self.currentStateId, (value) {
    return _then(_self.copyWith(currentStateId: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currentStateTitle {

  return $ReadTextCopyWith<$Res>(_self.currentStateTitle, (value) {
    return _then(_self.copyWith(currentStateTitle: value));
  });
}/// Create a copy of WorkflowRunReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modeDisplayName {

  return $ReadTextCopyWith<$Res>(_self.modeDisplayName, (value) {
    return _then(_self.copyWith(modeDisplayName: value));
  });
}
}

/// @nodoc
mixin _$WorkflowReadHeader {

 ReadScopeIdentity get scope; int get revision; WorkflowRunReadValue? get currentRun;
/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowReadHeaderCopyWith<WorkflowReadHeader> get copyWith => _$WorkflowReadHeaderCopyWithImpl<WorkflowReadHeader>(this as WorkflowReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.currentRun, _this.currentRun) || other.currentRun == _this.currentRun));
}


@override
int get hashCode {
  final _this = this as WorkflowReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.revision,_this.currentRun);
}



}

/// @nodoc
abstract mixin class $WorkflowReadHeaderCopyWith<$Res>  {
  factory $WorkflowReadHeaderCopyWith(WorkflowReadHeader value, $Res Function(WorkflowReadHeader) _then) = _$WorkflowReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int revision, WorkflowRunReadValue? currentRun
});


$ReadScopeIdentityCopyWith<$Res> get scope;$WorkflowRunReadValueCopyWith<$Res>? get currentRun;

}
/// @nodoc
class _$WorkflowReadHeaderCopyWithImpl<$Res>
    implements $WorkflowReadHeaderCopyWith<$Res> {
  _$WorkflowReadHeaderCopyWithImpl(this._self, this._then);

  final WorkflowReadHeader _self;
  final $Res Function(WorkflowReadHeader) _then;

/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? revision = null,Object? currentRun = freezed,}) {
  return _then(WorkflowReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,currentRun: freezed == currentRun ? _self.currentRun : currentRun // ignore: cast_nullable_to_non_nullable
as WorkflowRunReadValue?,
  ));
}
/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowRunReadValueCopyWith<$Res>? get currentRun {
    if (_self.currentRun == null) {
    return null;
  }

  return $WorkflowRunReadValueCopyWith<$Res>(_self.currentRun!, (value) {
    return _then(_self.copyWith(currentRun: value));
  });
}
}


/// Adds pattern-matching-related methods to [WorkflowReadHeader].
extension WorkflowReadHeaderPatterns on WorkflowReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int revision,  WorkflowRunReadValue? currentRun)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowReadHeader() when $default != null:
return $default(_that.scope,_that.revision,_that.currentRun);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int revision,  WorkflowRunReadValue? currentRun)  $default,) {final _that = this;
switch (_that) {
case _WorkflowReadHeader():
return $default(_that.scope,_that.revision,_that.currentRun);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  int revision,  WorkflowRunReadValue? currentRun)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowReadHeader() when $default != null:
return $default(_that.scope,_that.revision,_that.currentRun);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowReadHeader implements WorkflowReadHeader {
  const _WorkflowReadHeader({required this.scope, required this.revision, required this.currentRun});


@override final  ReadScopeIdentity scope;
@override final  int revision;
@override final  WorkflowRunReadValue? currentRun;

/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowReadHeaderCopyWith<_WorkflowReadHeader> get copyWith => __$WorkflowReadHeaderCopyWithImpl<_WorkflowReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.currentRun, currentRun) || other.currentRun == currentRun));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,revision,currentRun);
}



}

/// @nodoc
abstract mixin class _$WorkflowReadHeaderCopyWith<$Res> implements $WorkflowReadHeaderCopyWith<$Res> {
  factory _$WorkflowReadHeaderCopyWith(_WorkflowReadHeader value, $Res Function(_WorkflowReadHeader) _then) = __$WorkflowReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, int revision, WorkflowRunReadValue? currentRun
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $WorkflowRunReadValueCopyWith<$Res>? get currentRun;

}
/// @nodoc
class __$WorkflowReadHeaderCopyWithImpl<$Res>
    implements _$WorkflowReadHeaderCopyWith<$Res> {
  __$WorkflowReadHeaderCopyWithImpl(this._self, this._then);

  final _WorkflowReadHeader _self;
  final $Res Function(_WorkflowReadHeader) _then;

/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? revision = null,Object? currentRun = freezed,}) {
  return _then(_WorkflowReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,currentRun: freezed == currentRun ? _self.currentRun : currentRun // ignore: cast_nullable_to_non_nullable
as WorkflowRunReadValue?,
  ));
}

/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of WorkflowReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkflowRunReadValueCopyWith<$Res>? get currentRun {
    if (_self.currentRun == null) {
    return null;
  }

  return $WorkflowRunReadValueCopyWith<$Res>(_self.currentRun!, (value) {
    return _then(_self.copyWith(currentRun: value));
  });
}
}

/// @nodoc
mixin _$PlanDocumentReadHeader {

 ReadScopeIdentity get scope; int get version; String get contentHash;
/// Create a copy of PlanDocumentReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanDocumentReadHeaderCopyWith<PlanDocumentReadHeader> get copyWith => _$PlanDocumentReadHeaderCopyWithImpl<PlanDocumentReadHeader>(this as PlanDocumentReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanDocumentReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanDocumentReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.contentHash, _this.contentHash) || other.contentHash == _this.contentHash));
}


@override
int get hashCode {
  final _this = this as PlanDocumentReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.version,_this.contentHash);
}

@override
String toString() {
  final _this = this as PlanDocumentReadHeader;
  return 'PlanDocumentReadHeader(scope: ${_this.scope}, version: ${_this.version}, contentHash: ${_this.contentHash})';
}


}

/// @nodoc
abstract mixin class $PlanDocumentReadHeaderCopyWith<$Res>  {
  factory $PlanDocumentReadHeaderCopyWith(PlanDocumentReadHeader value, $Res Function(PlanDocumentReadHeader) _then) = _$PlanDocumentReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int version, String contentHash
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$PlanDocumentReadHeaderCopyWithImpl<$Res>
    implements $PlanDocumentReadHeaderCopyWith<$Res> {
  _$PlanDocumentReadHeaderCopyWithImpl(this._self, this._then);

  final PlanDocumentReadHeader _self;
  final $Res Function(PlanDocumentReadHeader) _then;

/// Create a copy of PlanDocumentReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? version = null,Object? contentHash = null,}) {
  return _then(PlanDocumentReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of PlanDocumentReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [PlanDocumentReadHeader].
extension PlanDocumentReadHeaderPatterns on PlanDocumentReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanDocumentReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanDocumentReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanDocumentReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _PlanDocumentReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanDocumentReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PlanDocumentReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int version,  String contentHash)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanDocumentReadHeader() when $default != null:
return $default(_that.scope,_that.version,_that.contentHash);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int version,  String contentHash)  $default,) {final _that = this;
switch (_that) {
case _PlanDocumentReadHeader():
return $default(_that.scope,_that.version,_that.contentHash);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  int version,  String contentHash)?  $default,) {final _that = this;
switch (_that) {
case _PlanDocumentReadHeader() when $default != null:
return $default(_that.scope,_that.version,_that.contentHash);case _:
  return null;

}
}

}

/// @nodoc


class _PlanDocumentReadHeader implements PlanDocumentReadHeader {
  const _PlanDocumentReadHeader({required this.scope, required this.version, required this.contentHash});


@override final  ReadScopeIdentity scope;
@override final  int version;
@override final  String contentHash;

/// Create a copy of PlanDocumentReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanDocumentReadHeaderCopyWith<_PlanDocumentReadHeader> get copyWith => __$PlanDocumentReadHeaderCopyWithImpl<_PlanDocumentReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanDocumentReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.version, version) || other.version == version)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,version,contentHash);
}

@override
String toString() {
    return 'PlanDocumentReadHeader(scope: $scope, version: $version, contentHash: $contentHash)';
}


}

/// @nodoc
abstract mixin class _$PlanDocumentReadHeaderCopyWith<$Res> implements $PlanDocumentReadHeaderCopyWith<$Res> {
  factory _$PlanDocumentReadHeaderCopyWith(_PlanDocumentReadHeader value, $Res Function(_PlanDocumentReadHeader) _then) = __$PlanDocumentReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, int version, String contentHash
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class __$PlanDocumentReadHeaderCopyWithImpl<$Res>
    implements _$PlanDocumentReadHeaderCopyWith<$Res> {
  __$PlanDocumentReadHeaderCopyWithImpl(this._self, this._then);

  final _PlanDocumentReadHeader _self;
  final $Res Function(_PlanDocumentReadHeader) _then;

/// Create a copy of PlanDocumentReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? version = null,Object? contentHash = null,}) {
  return _then(_PlanDocumentReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of PlanDocumentReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}

/// @nodoc
mixin _$PlanDocumentValue {

 ReadScopeIdentity get scope; int get version; String get contentHash; String get markdown;
/// Create a copy of PlanDocumentValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanDocumentValueCopyWith<PlanDocumentValue> get copyWith => _$PlanDocumentValueCopyWithImpl<PlanDocumentValue>(this as PlanDocumentValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanDocumentValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanDocumentValue&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.contentHash, _this.contentHash) || other.contentHash == _this.contentHash)&&(identical(other.markdown, _this.markdown) || other.markdown == _this.markdown));
}


@override
int get hashCode {
  final _this = this as PlanDocumentValue;
  return Object.hash(runtimeType,_this.scope,_this.version,_this.contentHash,_this.markdown);
}



}

/// @nodoc
abstract mixin class $PlanDocumentValueCopyWith<$Res>  {
  factory $PlanDocumentValueCopyWith(PlanDocumentValue value, $Res Function(PlanDocumentValue) _then) = _$PlanDocumentValueCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int version, String contentHash, String markdown
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$PlanDocumentValueCopyWithImpl<$Res>
    implements $PlanDocumentValueCopyWith<$Res> {
  _$PlanDocumentValueCopyWithImpl(this._self, this._then);

  final PlanDocumentValue _self;
  final $Res Function(PlanDocumentValue) _then;

/// Create a copy of PlanDocumentValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? version = null,Object? contentHash = null,Object? markdown = null,}) {
  return _then(PlanDocumentValue(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of PlanDocumentValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [PlanDocumentValue].
extension PlanDocumentValuePatterns on PlanDocumentValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanDocumentValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanDocumentValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanDocumentValue value)  $default,){
final _that = this;
switch (_that) {
case _PlanDocumentValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanDocumentValue value)?  $default,){
final _that = this;
switch (_that) {
case _PlanDocumentValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int version,  String contentHash,  String markdown)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanDocumentValue() when $default != null:
return $default(_that.scope,_that.version,_that.contentHash,_that.markdown);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int version,  String contentHash,  String markdown)  $default,) {final _that = this;
switch (_that) {
case _PlanDocumentValue():
return $default(_that.scope,_that.version,_that.contentHash,_that.markdown);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  int version,  String contentHash,  String markdown)?  $default,) {final _that = this;
switch (_that) {
case _PlanDocumentValue() when $default != null:
return $default(_that.scope,_that.version,_that.contentHash,_that.markdown);case _:
  return null;

}
}

}

/// @nodoc


class _PlanDocumentValue implements PlanDocumentValue {
  const _PlanDocumentValue({required this.scope, required this.version, required this.contentHash, required this.markdown});


@override final  ReadScopeIdentity scope;
@override final  int version;
@override final  String contentHash;
@override final  String markdown;

/// Create a copy of PlanDocumentValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanDocumentValueCopyWith<_PlanDocumentValue> get copyWith => __$PlanDocumentValueCopyWithImpl<_PlanDocumentValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanDocumentValue&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.version, version) || other.version == version)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&(identical(other.markdown, markdown) || other.markdown == markdown));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,version,contentHash,markdown);
}



}

/// @nodoc
abstract mixin class _$PlanDocumentValueCopyWith<$Res> implements $PlanDocumentValueCopyWith<$Res> {
  factory _$PlanDocumentValueCopyWith(_PlanDocumentValue value, $Res Function(_PlanDocumentValue) _then) = __$PlanDocumentValueCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, int version, String contentHash, String markdown
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class __$PlanDocumentValueCopyWithImpl<$Res>
    implements _$PlanDocumentValueCopyWith<$Res> {
  __$PlanDocumentValueCopyWithImpl(this._self, this._then);

  final _PlanDocumentValue _self;
  final $Res Function(_PlanDocumentValue) _then;

/// Create a copy of PlanDocumentValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? version = null,Object? contentHash = null,Object? markdown = null,}) {
  return _then(_PlanDocumentValue(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,contentHash: null == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String,markdown: null == markdown ? _self.markdown : markdown // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of PlanDocumentValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}

// dart format on
