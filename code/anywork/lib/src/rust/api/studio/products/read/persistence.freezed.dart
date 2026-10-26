// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'persistence.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgePersistenceStatusRead {

 BigInt get pendingCommits;
/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceStatusReadCopyWith<BridgePersistenceStatusRead> get copyWith => _$BridgePersistenceStatusReadCopyWithImpl<BridgePersistenceStatusRead>(this as BridgePersistenceStatusRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgePersistenceStatusRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceStatusRead&&(identical(other.pendingCommits, _this.pendingCommits) || other.pendingCommits == _this.pendingCommits));
}


@override
int get hashCode {
  final _this = this as BridgePersistenceStatusRead;
  return Object.hash(runtimeType,_this.pendingCommits);
}

@override
String toString() {
  final _this = this as BridgePersistenceStatusRead;
  return 'BridgePersistenceStatusRead(pendingCommits: ${_this.pendingCommits})';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceStatusReadCopyWith<$Res>  {
  factory $BridgePersistenceStatusReadCopyWith(BridgePersistenceStatusRead value, $Res Function(BridgePersistenceStatusRead) _then) = _$BridgePersistenceStatusReadCopyWithImpl;
@useResult
$Res call({
 BigInt pendingCommits
});




}
/// @nodoc
class _$BridgePersistenceStatusReadCopyWithImpl<$Res>
    implements $BridgePersistenceStatusReadCopyWith<$Res> {
  _$BridgePersistenceStatusReadCopyWithImpl(this._self, this._then);

  final BridgePersistenceStatusRead _self;
  final $Res Function(BridgePersistenceStatusRead) _then;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pendingCommits = null,}) {
  return _then(_self.copyWith(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgePersistenceStatusRead].
extension BridgePersistenceStatusReadPatterns on BridgePersistenceStatusRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePersistenceStatusRead_Ready value)?  ready,TResult Function( BridgePersistenceStatusRead_Flushing value)?  flushing,TResult Function( BridgePersistenceStatusRead_Degraded value)?  degraded,TResult Function( BridgePersistenceStatusRead_Recovering value)?  recovering,TResult Function( BridgePersistenceStatusRead_Blocked value)?  blocked,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePersistenceStatusRead_Ready() when ready != null:
return ready(_that);case BridgePersistenceStatusRead_Flushing() when flushing != null:
return flushing(_that);case BridgePersistenceStatusRead_Degraded() when degraded != null:
return degraded(_that);case BridgePersistenceStatusRead_Recovering() when recovering != null:
return recovering(_that);case BridgePersistenceStatusRead_Blocked() when blocked != null:
return blocked(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePersistenceStatusRead_Ready value)  ready,required TResult Function( BridgePersistenceStatusRead_Flushing value)  flushing,required TResult Function( BridgePersistenceStatusRead_Degraded value)  degraded,required TResult Function( BridgePersistenceStatusRead_Recovering value)  recovering,required TResult Function( BridgePersistenceStatusRead_Blocked value)  blocked,}){
final _that = this;
switch (_that) {
case BridgePersistenceStatusRead_Ready():
return ready(_that);case BridgePersistenceStatusRead_Flushing():
return flushing(_that);case BridgePersistenceStatusRead_Degraded():
return degraded(_that);case BridgePersistenceStatusRead_Recovering():
return recovering(_that);case BridgePersistenceStatusRead_Blocked():
return blocked(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePersistenceStatusRead_Ready value)?  ready,TResult? Function( BridgePersistenceStatusRead_Flushing value)?  flushing,TResult? Function( BridgePersistenceStatusRead_Degraded value)?  degraded,TResult? Function( BridgePersistenceStatusRead_Recovering value)?  recovering,TResult? Function( BridgePersistenceStatusRead_Blocked value)?  blocked,}){
final _that = this;
switch (_that) {
case BridgePersistenceStatusRead_Ready() when ready != null:
return ready(_that);case BridgePersistenceStatusRead_Flushing() when flushing != null:
return flushing(_that);case BridgePersistenceStatusRead_Degraded() when degraded != null:
return degraded(_that);case BridgePersistenceStatusRead_Recovering() when recovering != null:
return recovering(_that);case BridgePersistenceStatusRead_Blocked() when blocked != null:
return blocked(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt pendingCommits)?  ready,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision)?  flushing,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt,  BridgeSourceStateErrorRead error)?  degraded,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  recovering,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt,  BridgeSourceStateErrorRead error)?  blocked,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePersistenceStatusRead_Ready() when ready != null:
return ready(_that.pendingCommits);case BridgePersistenceStatusRead_Flushing() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case BridgePersistenceStatusRead_Degraded() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case BridgePersistenceStatusRead_Recovering() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceStatusRead_Blocked() when blocked != null:
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt pendingCommits)  ready,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision)  flushing,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt,  BridgeSourceStateErrorRead error)  degraded,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)  recovering,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt,  BridgeSourceStateErrorRead error)  blocked,}) {final _that = this;
switch (_that) {
case BridgePersistenceStatusRead_Ready():
return ready(_that.pendingCommits);case BridgePersistenceStatusRead_Flushing():
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case BridgePersistenceStatusRead_Degraded():
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case BridgePersistenceStatusRead_Recovering():
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceStatusRead_Blocked():
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt pendingCommits)?  ready,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision)?  flushing,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt,  BridgeSourceStateErrorRead error)?  degraded,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  recovering,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt,  BridgeSourceStateErrorRead error)?  blocked,}) {final _that = this;
switch (_that) {
case BridgePersistenceStatusRead_Ready() when ready != null:
return ready(_that.pendingCommits);case BridgePersistenceStatusRead_Flushing() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case BridgePersistenceStatusRead_Degraded() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case BridgePersistenceStatusRead_Recovering() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceStatusRead_Blocked() when blocked != null:
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class BridgePersistenceStatusRead_Ready extends BridgePersistenceStatusRead {
  const BridgePersistenceStatusRead_Ready({required this.pendingCommits}): super._();


@override final  BigInt pendingCommits;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceStatusRead_ReadyCopyWith<BridgePersistenceStatusRead_Ready> get copyWith => _$BridgePersistenceStatusRead_ReadyCopyWithImpl<BridgePersistenceStatusRead_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceStatusRead_Ready&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits);
}

@override
String toString() {
    return 'BridgePersistenceStatusRead.ready(pendingCommits: $pendingCommits)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceStatusRead_ReadyCopyWith<$Res> implements $BridgePersistenceStatusReadCopyWith<$Res> {
  factory $BridgePersistenceStatusRead_ReadyCopyWith(BridgePersistenceStatusRead_Ready value, $Res Function(BridgePersistenceStatusRead_Ready) _then) = _$BridgePersistenceStatusRead_ReadyCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits
});




}
/// @nodoc
class _$BridgePersistenceStatusRead_ReadyCopyWithImpl<$Res>
    implements $BridgePersistenceStatusRead_ReadyCopyWith<$Res> {
  _$BridgePersistenceStatusRead_ReadyCopyWithImpl(this._self, this._then);

  final BridgePersistenceStatusRead_Ready _self;
  final $Res Function(BridgePersistenceStatusRead_Ready) _then;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,}) {
  return _then(BridgePersistenceStatusRead_Ready(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgePersistenceStatusRead_Flushing extends BridgePersistenceStatusRead {
  const BridgePersistenceStatusRead_Flushing({required this.pendingCommits, this.oldestPendingRevision}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceStatusRead_FlushingCopyWith<BridgePersistenceStatusRead_Flushing> get copyWith => _$BridgePersistenceStatusRead_FlushingCopyWithImpl<BridgePersistenceStatusRead_Flushing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceStatusRead_Flushing&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision);
}

@override
String toString() {
    return 'BridgePersistenceStatusRead.flushing(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceStatusRead_FlushingCopyWith<$Res> implements $BridgePersistenceStatusReadCopyWith<$Res> {
  factory $BridgePersistenceStatusRead_FlushingCopyWith(BridgePersistenceStatusRead_Flushing value, $Res Function(BridgePersistenceStatusRead_Flushing) _then) = _$BridgePersistenceStatusRead_FlushingCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision
});




}
/// @nodoc
class _$BridgePersistenceStatusRead_FlushingCopyWithImpl<$Res>
    implements $BridgePersistenceStatusRead_FlushingCopyWith<$Res> {
  _$BridgePersistenceStatusRead_FlushingCopyWithImpl(this._self, this._then);

  final BridgePersistenceStatusRead_Flushing _self;
  final $Res Function(BridgePersistenceStatusRead_Flushing) _then;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,}) {
  return _then(BridgePersistenceStatusRead_Flushing(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class BridgePersistenceStatusRead_Degraded extends BridgePersistenceStatusRead {
  const BridgePersistenceStatusRead_Degraded({required this.pendingCommits, this.oldestPendingRevision, required this.firstFailedAt, required this.error}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;
 final  PlatformInt64 firstFailedAt;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceStatusRead_DegradedCopyWith<BridgePersistenceStatusRead_Degraded> get copyWith => _$BridgePersistenceStatusRead_DegradedCopyWithImpl<BridgePersistenceStatusRead_Degraded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceStatusRead_Degraded&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt,error);
}

@override
String toString() {
    return 'BridgePersistenceStatusRead.degraded(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision, firstFailedAt: $firstFailedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceStatusRead_DegradedCopyWith<$Res> implements $BridgePersistenceStatusReadCopyWith<$Res> {
  factory $BridgePersistenceStatusRead_DegradedCopyWith(BridgePersistenceStatusRead_Degraded value, $Res Function(BridgePersistenceStatusRead_Degraded) _then) = _$BridgePersistenceStatusRead_DegradedCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision, PlatformInt64 firstFailedAt, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgePersistenceStatusRead_DegradedCopyWithImpl<$Res>
    implements $BridgePersistenceStatusRead_DegradedCopyWith<$Res> {
  _$BridgePersistenceStatusRead_DegradedCopyWithImpl(this._self, this._then);

  final BridgePersistenceStatusRead_Degraded _self;
  final $Res Function(BridgePersistenceStatusRead_Degraded) _then;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,Object? error = null,}) {
  return _then(BridgePersistenceStatusRead_Degraded(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

/// @nodoc


class BridgePersistenceStatusRead_Recovering extends BridgePersistenceStatusRead {
  const BridgePersistenceStatusRead_Recovering({required this.pendingCommits, this.oldestPendingRevision, required this.firstFailedAt}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;
 final  PlatformInt64 firstFailedAt;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceStatusRead_RecoveringCopyWith<BridgePersistenceStatusRead_Recovering> get copyWith => _$BridgePersistenceStatusRead_RecoveringCopyWithImpl<BridgePersistenceStatusRead_Recovering>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceStatusRead_Recovering&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}

@override
String toString() {
    return 'BridgePersistenceStatusRead.recovering(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision, firstFailedAt: $firstFailedAt)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceStatusRead_RecoveringCopyWith<$Res> implements $BridgePersistenceStatusReadCopyWith<$Res> {
  factory $BridgePersistenceStatusRead_RecoveringCopyWith(BridgePersistenceStatusRead_Recovering value, $Res Function(BridgePersistenceStatusRead_Recovering) _then) = _$BridgePersistenceStatusRead_RecoveringCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision, PlatformInt64 firstFailedAt
});




}
/// @nodoc
class _$BridgePersistenceStatusRead_RecoveringCopyWithImpl<$Res>
    implements $BridgePersistenceStatusRead_RecoveringCopyWith<$Res> {
  _$BridgePersistenceStatusRead_RecoveringCopyWithImpl(this._self, this._then);

  final BridgePersistenceStatusRead_Recovering _self;
  final $Res Function(BridgePersistenceStatusRead_Recovering) _then;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(BridgePersistenceStatusRead_Recovering(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgePersistenceStatusRead_Blocked extends BridgePersistenceStatusRead {
  const BridgePersistenceStatusRead_Blocked({required this.pendingCommits, this.oldestPendingRevision, required this.firstFailedAt, required this.error}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;
 final  PlatformInt64 firstFailedAt;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceStatusRead_BlockedCopyWith<BridgePersistenceStatusRead_Blocked> get copyWith => _$BridgePersistenceStatusRead_BlockedCopyWithImpl<BridgePersistenceStatusRead_Blocked>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceStatusRead_Blocked&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt,error);
}

@override
String toString() {
    return 'BridgePersistenceStatusRead.blocked(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision, firstFailedAt: $firstFailedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceStatusRead_BlockedCopyWith<$Res> implements $BridgePersistenceStatusReadCopyWith<$Res> {
  factory $BridgePersistenceStatusRead_BlockedCopyWith(BridgePersistenceStatusRead_Blocked value, $Res Function(BridgePersistenceStatusRead_Blocked) _then) = _$BridgePersistenceStatusRead_BlockedCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision, PlatformInt64 firstFailedAt, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgePersistenceStatusRead_BlockedCopyWithImpl<$Res>
    implements $BridgePersistenceStatusRead_BlockedCopyWith<$Res> {
  _$BridgePersistenceStatusRead_BlockedCopyWithImpl(this._self, this._then);

  final BridgePersistenceStatusRead_Blocked _self;
  final $Res Function(BridgePersistenceStatusRead_Blocked) _then;

/// Create a copy of BridgePersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,Object? error = null,}) {
  return _then(BridgePersistenceStatusRead_Blocked(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

// dart format on
