// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'update_task.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdateTaskIdentity {

 String get runtimeEpoch; String get taskId; OperationId get operationId;
/// Create a copy of UpdateTaskIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateTaskIdentityCopyWith<UpdateTaskIdentity> get copyWith => _$UpdateTaskIdentityCopyWithImpl<UpdateTaskIdentity>(this as UpdateTaskIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateTaskIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateTaskIdentity&&(identical(other.runtimeEpoch, _this.runtimeEpoch) || other.runtimeEpoch == _this.runtimeEpoch)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as UpdateTaskIdentity;
  return Object.hash(runtimeType,_this.runtimeEpoch,_this.taskId,_this.operationId);
}

@override
String toString() {
  final _this = this as UpdateTaskIdentity;
  return 'UpdateTaskIdentity(runtimeEpoch: ${_this.runtimeEpoch}, taskId: ${_this.taskId}, operationId: ${_this.operationId})';
}


}

/// @nodoc
abstract mixin class $UpdateTaskIdentityCopyWith<$Res>  {
  factory $UpdateTaskIdentityCopyWith(UpdateTaskIdentity value, $Res Function(UpdateTaskIdentity) _then) = _$UpdateTaskIdentityCopyWithImpl;
@useResult
$Res call({
 String runtimeEpoch, String taskId, OperationId operationId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$UpdateTaskIdentityCopyWithImpl<$Res>
    implements $UpdateTaskIdentityCopyWith<$Res> {
  _$UpdateTaskIdentityCopyWithImpl(this._self, this._then);

  final UpdateTaskIdentity _self;
  final $Res Function(UpdateTaskIdentity) _then;

/// Create a copy of UpdateTaskIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? runtimeEpoch = null,Object? taskId = null,Object? operationId = null,}) {
  return _then(UpdateTaskIdentity(
runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}
/// Create a copy of UpdateTaskIdentity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateTaskIdentity].
extension UpdateTaskIdentityPatterns on UpdateTaskIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateTaskIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateTaskIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateTaskIdentity value)  $default,){
final _that = this;
switch (_that) {
case _UpdateTaskIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateTaskIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateTaskIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String runtimeEpoch,  String taskId,  OperationId operationId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateTaskIdentity() when $default != null:
return $default(_that.runtimeEpoch,_that.taskId,_that.operationId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String runtimeEpoch,  String taskId,  OperationId operationId)  $default,) {final _that = this;
switch (_that) {
case _UpdateTaskIdentity():
return $default(_that.runtimeEpoch,_that.taskId,_that.operationId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String runtimeEpoch,  String taskId,  OperationId operationId)?  $default,) {final _that = this;
switch (_that) {
case _UpdateTaskIdentity() when $default != null:
return $default(_that.runtimeEpoch,_that.taskId,_that.operationId);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateTaskIdentity implements UpdateTaskIdentity {
  const _UpdateTaskIdentity({required this.runtimeEpoch, required this.taskId, required this.operationId});


@override final  String runtimeEpoch;
@override final  String taskId;
@override final  OperationId operationId;

/// Create a copy of UpdateTaskIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateTaskIdentityCopyWith<_UpdateTaskIdentity> get copyWith => __$UpdateTaskIdentityCopyWithImpl<_UpdateTaskIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateTaskIdentity&&(identical(other.runtimeEpoch, runtimeEpoch) || other.runtimeEpoch == runtimeEpoch)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,runtimeEpoch,taskId,operationId);
}

@override
String toString() {
    return 'UpdateTaskIdentity(runtimeEpoch: $runtimeEpoch, taskId: $taskId, operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class _$UpdateTaskIdentityCopyWith<$Res> implements $UpdateTaskIdentityCopyWith<$Res> {
  factory _$UpdateTaskIdentityCopyWith(_UpdateTaskIdentity value, $Res Function(_UpdateTaskIdentity) _then) = __$UpdateTaskIdentityCopyWithImpl;
@override @useResult
$Res call({
 String runtimeEpoch, String taskId, OperationId operationId
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$UpdateTaskIdentityCopyWithImpl<$Res>
    implements _$UpdateTaskIdentityCopyWith<$Res> {
  __$UpdateTaskIdentityCopyWithImpl(this._self, this._then);

  final _UpdateTaskIdentity _self;
  final $Res Function(_UpdateTaskIdentity) _then;

/// Create a copy of UpdateTaskIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeEpoch = null,Object? taskId = null,Object? operationId = null,}) {
  return _then(_UpdateTaskIdentity(
runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}

/// Create a copy of UpdateTaskIdentity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$UpdateTaskCloseReport {

 UpdateTaskIdentity get identity; FeedCloseOutcome get outcome;
/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateTaskCloseReportCopyWith<UpdateTaskCloseReport> get copyWith => _$UpdateTaskCloseReportCopyWithImpl<UpdateTaskCloseReport>(this as UpdateTaskCloseReport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateTaskCloseReport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateTaskCloseReport&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome));
}


@override
int get hashCode {
  final _this = this as UpdateTaskCloseReport;
  return Object.hash(runtimeType,_this.identity,_this.outcome);
}



}

/// @nodoc
abstract mixin class $UpdateTaskCloseReportCopyWith<$Res>  {
  factory $UpdateTaskCloseReportCopyWith(UpdateTaskCloseReport value, $Res Function(UpdateTaskCloseReport) _then) = _$UpdateTaskCloseReportCopyWithImpl;
@useResult
$Res call({
 UpdateTaskIdentity identity, FeedCloseOutcome outcome
});


$UpdateTaskIdentityCopyWith<$Res> get identity;$FeedCloseOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class _$UpdateTaskCloseReportCopyWithImpl<$Res>
    implements $UpdateTaskCloseReportCopyWith<$Res> {
  _$UpdateTaskCloseReportCopyWithImpl(this._self, this._then);

  final UpdateTaskCloseReport _self;
  final $Res Function(UpdateTaskCloseReport) _then;

/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? outcome = null,}) {
  return _then(UpdateTaskCloseReport(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as UpdateTaskIdentity,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as FeedCloseOutcome,
  ));
}
/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateTaskIdentityCopyWith<$Res> get identity {

  return $UpdateTaskIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FeedCloseOutcomeCopyWith<$Res> get outcome {

  return $FeedCloseOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateTaskCloseReport].
extension UpdateTaskCloseReportPatterns on UpdateTaskCloseReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateTaskCloseReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateTaskCloseReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateTaskCloseReport value)  $default,){
final _that = this;
switch (_that) {
case _UpdateTaskCloseReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateTaskCloseReport value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateTaskCloseReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( UpdateTaskIdentity identity,  FeedCloseOutcome outcome)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateTaskCloseReport() when $default != null:
return $default(_that.identity,_that.outcome);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( UpdateTaskIdentity identity,  FeedCloseOutcome outcome)  $default,) {final _that = this;
switch (_that) {
case _UpdateTaskCloseReport():
return $default(_that.identity,_that.outcome);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( UpdateTaskIdentity identity,  FeedCloseOutcome outcome)?  $default,) {final _that = this;
switch (_that) {
case _UpdateTaskCloseReport() when $default != null:
return $default(_that.identity,_that.outcome);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateTaskCloseReport implements UpdateTaskCloseReport {
  const _UpdateTaskCloseReport({required this.identity, required this.outcome});


@override final  UpdateTaskIdentity identity;
@override final  FeedCloseOutcome outcome;

/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateTaskCloseReportCopyWith<_UpdateTaskCloseReport> get copyWith => __$UpdateTaskCloseReportCopyWithImpl<_UpdateTaskCloseReport>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateTaskCloseReport&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,outcome);
}



}

/// @nodoc
abstract mixin class _$UpdateTaskCloseReportCopyWith<$Res> implements $UpdateTaskCloseReportCopyWith<$Res> {
  factory _$UpdateTaskCloseReportCopyWith(_UpdateTaskCloseReport value, $Res Function(_UpdateTaskCloseReport) _then) = __$UpdateTaskCloseReportCopyWithImpl;
@override @useResult
$Res call({
 UpdateTaskIdentity identity, FeedCloseOutcome outcome
});


@override $UpdateTaskIdentityCopyWith<$Res> get identity;@override $FeedCloseOutcomeCopyWith<$Res> get outcome;

}
/// @nodoc
class __$UpdateTaskCloseReportCopyWithImpl<$Res>
    implements _$UpdateTaskCloseReportCopyWith<$Res> {
  __$UpdateTaskCloseReportCopyWithImpl(this._self, this._then);

  final _UpdateTaskCloseReport _self;
  final $Res Function(_UpdateTaskCloseReport) _then;

/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? outcome = null,}) {
  return _then(_UpdateTaskCloseReport(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as UpdateTaskIdentity,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as FeedCloseOutcome,
  ));
}

/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateTaskIdentityCopyWith<$Res> get identity {

  return $UpdateTaskIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of UpdateTaskCloseReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FeedCloseOutcomeCopyWith<$Res> get outcome {

  return $FeedCloseOutcomeCopyWith<$Res>(_self.outcome, (value) {
    return _then(_self.copyWith(outcome: value));
  });
}
}

// dart format on
