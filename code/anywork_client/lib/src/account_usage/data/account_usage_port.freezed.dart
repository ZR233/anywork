// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_usage_port.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountUsageCheckResult {

 AccountUsageReadTarget get target; String get accountId; int get usageQueryRevision;
/// Create a copy of AccountUsageCheckResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageCheckResultCopyWith<AccountUsageCheckResult> get copyWith => _$AccountUsageCheckResultCopyWithImpl<AccountUsageCheckResult>(this as AccountUsageCheckResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageCheckResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageCheckResult&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.usageQueryRevision, _this.usageQueryRevision) || other.usageQueryRevision == _this.usageQueryRevision));
}


@override
int get hashCode {
  final _this = this as AccountUsageCheckResult;
  return Object.hash(runtimeType,_this.target,_this.accountId,_this.usageQueryRevision);
}

@override
String toString() {
  final _this = this as AccountUsageCheckResult;
  return 'AccountUsageCheckResult(target: ${_this.target}, accountId: ${_this.accountId}, usageQueryRevision: ${_this.usageQueryRevision})';
}


}

/// @nodoc
abstract mixin class $AccountUsageCheckResultCopyWith<$Res>  {
  factory $AccountUsageCheckResultCopyWith(AccountUsageCheckResult value, $Res Function(AccountUsageCheckResult) _then) = _$AccountUsageCheckResultCopyWithImpl;
@useResult
$Res call({
 AccountUsageReadTarget target, String accountId, int usageQueryRevision
});


$AccountUsageReadTargetCopyWith<$Res> get target;

}
/// @nodoc
class _$AccountUsageCheckResultCopyWithImpl<$Res>
    implements $AccountUsageCheckResultCopyWith<$Res> {
  _$AccountUsageCheckResultCopyWithImpl(this._self, this._then);

  final AccountUsageCheckResult _self;
  final $Res Function(AccountUsageCheckResult) _then;

/// Create a copy of AccountUsageCheckResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? accountId = null,Object? usageQueryRevision = null,}) {
  return _then(AccountUsageCheckResult(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AccountUsageReadTarget,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,usageQueryRevision: null == usageQueryRevision ? _self.usageQueryRevision : usageQueryRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AccountUsageCheckResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadTargetCopyWith<$Res> get target {

  return $AccountUsageReadTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageCheckResult].
extension AccountUsageCheckResultPatterns on AccountUsageCheckResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageCheckResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageCheckResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageCheckResult value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageCheckResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageCheckResult value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageCheckResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountUsageReadTarget target,  String accountId,  int usageQueryRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageCheckResult() when $default != null:
return $default(_that.target,_that.accountId,_that.usageQueryRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountUsageReadTarget target,  String accountId,  int usageQueryRevision)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageCheckResult():
return $default(_that.target,_that.accountId,_that.usageQueryRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountUsageReadTarget target,  String accountId,  int usageQueryRevision)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageCheckResult() when $default != null:
return $default(_that.target,_that.accountId,_that.usageQueryRevision);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageCheckResult implements AccountUsageCheckResult {
  const _AccountUsageCheckResult({required this.target, required this.accountId, required this.usageQueryRevision});


@override final  AccountUsageReadTarget target;
@override final  String accountId;
@override final  int usageQueryRevision;

/// Create a copy of AccountUsageCheckResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageCheckResultCopyWith<_AccountUsageCheckResult> get copyWith => __$AccountUsageCheckResultCopyWithImpl<_AccountUsageCheckResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageCheckResult&&(identical(other.target, target) || other.target == target)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.usageQueryRevision, usageQueryRevision) || other.usageQueryRevision == usageQueryRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,accountId,usageQueryRevision);
}

@override
String toString() {
    return 'AccountUsageCheckResult(target: $target, accountId: $accountId, usageQueryRevision: $usageQueryRevision)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageCheckResultCopyWith<$Res> implements $AccountUsageCheckResultCopyWith<$Res> {
  factory _$AccountUsageCheckResultCopyWith(_AccountUsageCheckResult value, $Res Function(_AccountUsageCheckResult) _then) = __$AccountUsageCheckResultCopyWithImpl;
@override @useResult
$Res call({
 AccountUsageReadTarget target, String accountId, int usageQueryRevision
});


@override $AccountUsageReadTargetCopyWith<$Res> get target;

}
/// @nodoc
class __$AccountUsageCheckResultCopyWithImpl<$Res>
    implements _$AccountUsageCheckResultCopyWith<$Res> {
  __$AccountUsageCheckResultCopyWithImpl(this._self, this._then);

  final _AccountUsageCheckResult _self;
  final $Res Function(_AccountUsageCheckResult) _then;

/// Create a copy of AccountUsageCheckResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? accountId = null,Object? usageQueryRevision = null,}) {
  return _then(_AccountUsageCheckResult(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AccountUsageReadTarget,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,usageQueryRevision: null == usageQueryRevision ? _self.usageQueryRevision : usageQueryRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AccountUsageCheckResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadTargetCopyWith<$Res> get target {

  return $AccountUsageReadTargetCopyWith<$Res>(_self.target, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}

// dart format on
