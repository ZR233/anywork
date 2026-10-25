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
mixin _$BridgePersistenceBrief {

 BigInt get pendingCommits;
/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceBriefCopyWith<BridgePersistenceBrief> get copyWith => _$BridgePersistenceBriefCopyWithImpl<BridgePersistenceBrief>(this as BridgePersistenceBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgePersistenceBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceBrief&&(identical(other.pendingCommits, _this.pendingCommits) || other.pendingCommits == _this.pendingCommits));
}


@override
int get hashCode {
  final _this = this as BridgePersistenceBrief;
  return Object.hash(runtimeType,_this.pendingCommits);
}

@override
String toString() {
  final _this = this as BridgePersistenceBrief;
  return 'BridgePersistenceBrief(pendingCommits: ${_this.pendingCommits})';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceBriefCopyWith<$Res>  {
  factory $BridgePersistenceBriefCopyWith(BridgePersistenceBrief value, $Res Function(BridgePersistenceBrief) _then) = _$BridgePersistenceBriefCopyWithImpl;
@useResult
$Res call({
 BigInt pendingCommits
});




}
/// @nodoc
class _$BridgePersistenceBriefCopyWithImpl<$Res>
    implements $BridgePersistenceBriefCopyWith<$Res> {
  _$BridgePersistenceBriefCopyWithImpl(this._self, this._then);

  final BridgePersistenceBrief _self;
  final $Res Function(BridgePersistenceBrief) _then;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pendingCommits = null,}) {
  return _then(_self.copyWith(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgePersistenceBrief].
extension BridgePersistenceBriefPatterns on BridgePersistenceBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePersistenceBrief_Ready value)?  ready,TResult Function( BridgePersistenceBrief_Flushing value)?  flushing,TResult Function( BridgePersistenceBrief_Degraded value)?  degraded,TResult Function( BridgePersistenceBrief_Recovering value)?  recovering,TResult Function( BridgePersistenceBrief_Blocked value)?  blocked,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePersistenceBrief_Ready() when ready != null:
return ready(_that);case BridgePersistenceBrief_Flushing() when flushing != null:
return flushing(_that);case BridgePersistenceBrief_Degraded() when degraded != null:
return degraded(_that);case BridgePersistenceBrief_Recovering() when recovering != null:
return recovering(_that);case BridgePersistenceBrief_Blocked() when blocked != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePersistenceBrief_Ready value)  ready,required TResult Function( BridgePersistenceBrief_Flushing value)  flushing,required TResult Function( BridgePersistenceBrief_Degraded value)  degraded,required TResult Function( BridgePersistenceBrief_Recovering value)  recovering,required TResult Function( BridgePersistenceBrief_Blocked value)  blocked,}){
final _that = this;
switch (_that) {
case BridgePersistenceBrief_Ready():
return ready(_that);case BridgePersistenceBrief_Flushing():
return flushing(_that);case BridgePersistenceBrief_Degraded():
return degraded(_that);case BridgePersistenceBrief_Recovering():
return recovering(_that);case BridgePersistenceBrief_Blocked():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePersistenceBrief_Ready value)?  ready,TResult? Function( BridgePersistenceBrief_Flushing value)?  flushing,TResult? Function( BridgePersistenceBrief_Degraded value)?  degraded,TResult? Function( BridgePersistenceBrief_Recovering value)?  recovering,TResult? Function( BridgePersistenceBrief_Blocked value)?  blocked,}){
final _that = this;
switch (_that) {
case BridgePersistenceBrief_Ready() when ready != null:
return ready(_that);case BridgePersistenceBrief_Flushing() when flushing != null:
return flushing(_that);case BridgePersistenceBrief_Degraded() when degraded != null:
return degraded(_that);case BridgePersistenceBrief_Recovering() when recovering != null:
return recovering(_that);case BridgePersistenceBrief_Blocked() when blocked != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt pendingCommits)?  ready,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision)?  flushing,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  degraded,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  recovering,TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  blocked,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePersistenceBrief_Ready() when ready != null:
return ready(_that.pendingCommits);case BridgePersistenceBrief_Flushing() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case BridgePersistenceBrief_Degraded() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceBrief_Recovering() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceBrief_Blocked() when blocked != null:
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt pendingCommits)  ready,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision)  flushing,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)  degraded,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)  recovering,required TResult Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)  blocked,}) {final _that = this;
switch (_that) {
case BridgePersistenceBrief_Ready():
return ready(_that.pendingCommits);case BridgePersistenceBrief_Flushing():
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case BridgePersistenceBrief_Degraded():
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceBrief_Recovering():
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceBrief_Blocked():
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt pendingCommits)?  ready,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision)?  flushing,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  degraded,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  recovering,TResult? Function( BigInt pendingCommits,  BigInt? oldestPendingRevision,  PlatformInt64 firstFailedAt)?  blocked,}) {final _that = this;
switch (_that) {
case BridgePersistenceBrief_Ready() when ready != null:
return ready(_that.pendingCommits);case BridgePersistenceBrief_Flushing() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case BridgePersistenceBrief_Degraded() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceBrief_Recovering() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BridgePersistenceBrief_Blocked() when blocked != null:
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case _:
  return null;

}
}

}

/// @nodoc


class BridgePersistenceBrief_Ready extends BridgePersistenceBrief {
  const BridgePersistenceBrief_Ready({required this.pendingCommits}): super._();


@override final  BigInt pendingCommits;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceBrief_ReadyCopyWith<BridgePersistenceBrief_Ready> get copyWith => _$BridgePersistenceBrief_ReadyCopyWithImpl<BridgePersistenceBrief_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceBrief_Ready&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits);
}

@override
String toString() {
    return 'BridgePersistenceBrief.ready(pendingCommits: $pendingCommits)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceBrief_ReadyCopyWith<$Res> implements $BridgePersistenceBriefCopyWith<$Res> {
  factory $BridgePersistenceBrief_ReadyCopyWith(BridgePersistenceBrief_Ready value, $Res Function(BridgePersistenceBrief_Ready) _then) = _$BridgePersistenceBrief_ReadyCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits
});




}
/// @nodoc
class _$BridgePersistenceBrief_ReadyCopyWithImpl<$Res>
    implements $BridgePersistenceBrief_ReadyCopyWith<$Res> {
  _$BridgePersistenceBrief_ReadyCopyWithImpl(this._self, this._then);

  final BridgePersistenceBrief_Ready _self;
  final $Res Function(BridgePersistenceBrief_Ready) _then;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,}) {
  return _then(BridgePersistenceBrief_Ready(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgePersistenceBrief_Flushing extends BridgePersistenceBrief {
  const BridgePersistenceBrief_Flushing({required this.pendingCommits, this.oldestPendingRevision}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceBrief_FlushingCopyWith<BridgePersistenceBrief_Flushing> get copyWith => _$BridgePersistenceBrief_FlushingCopyWithImpl<BridgePersistenceBrief_Flushing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceBrief_Flushing&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision);
}

@override
String toString() {
    return 'BridgePersistenceBrief.flushing(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceBrief_FlushingCopyWith<$Res> implements $BridgePersistenceBriefCopyWith<$Res> {
  factory $BridgePersistenceBrief_FlushingCopyWith(BridgePersistenceBrief_Flushing value, $Res Function(BridgePersistenceBrief_Flushing) _then) = _$BridgePersistenceBrief_FlushingCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision
});




}
/// @nodoc
class _$BridgePersistenceBrief_FlushingCopyWithImpl<$Res>
    implements $BridgePersistenceBrief_FlushingCopyWith<$Res> {
  _$BridgePersistenceBrief_FlushingCopyWithImpl(this._self, this._then);

  final BridgePersistenceBrief_Flushing _self;
  final $Res Function(BridgePersistenceBrief_Flushing) _then;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,}) {
  return _then(BridgePersistenceBrief_Flushing(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class BridgePersistenceBrief_Degraded extends BridgePersistenceBrief {
  const BridgePersistenceBrief_Degraded({required this.pendingCommits, this.oldestPendingRevision, required this.firstFailedAt}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;
 final  PlatformInt64 firstFailedAt;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceBrief_DegradedCopyWith<BridgePersistenceBrief_Degraded> get copyWith => _$BridgePersistenceBrief_DegradedCopyWithImpl<BridgePersistenceBrief_Degraded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceBrief_Degraded&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}

@override
String toString() {
    return 'BridgePersistenceBrief.degraded(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision, firstFailedAt: $firstFailedAt)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceBrief_DegradedCopyWith<$Res> implements $BridgePersistenceBriefCopyWith<$Res> {
  factory $BridgePersistenceBrief_DegradedCopyWith(BridgePersistenceBrief_Degraded value, $Res Function(BridgePersistenceBrief_Degraded) _then) = _$BridgePersistenceBrief_DegradedCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision, PlatformInt64 firstFailedAt
});




}
/// @nodoc
class _$BridgePersistenceBrief_DegradedCopyWithImpl<$Res>
    implements $BridgePersistenceBrief_DegradedCopyWith<$Res> {
  _$BridgePersistenceBrief_DegradedCopyWithImpl(this._self, this._then);

  final BridgePersistenceBrief_Degraded _self;
  final $Res Function(BridgePersistenceBrief_Degraded) _then;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(BridgePersistenceBrief_Degraded(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgePersistenceBrief_Recovering extends BridgePersistenceBrief {
  const BridgePersistenceBrief_Recovering({required this.pendingCommits, this.oldestPendingRevision, required this.firstFailedAt}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;
 final  PlatformInt64 firstFailedAt;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceBrief_RecoveringCopyWith<BridgePersistenceBrief_Recovering> get copyWith => _$BridgePersistenceBrief_RecoveringCopyWithImpl<BridgePersistenceBrief_Recovering>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceBrief_Recovering&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}

@override
String toString() {
    return 'BridgePersistenceBrief.recovering(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision, firstFailedAt: $firstFailedAt)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceBrief_RecoveringCopyWith<$Res> implements $BridgePersistenceBriefCopyWith<$Res> {
  factory $BridgePersistenceBrief_RecoveringCopyWith(BridgePersistenceBrief_Recovering value, $Res Function(BridgePersistenceBrief_Recovering) _then) = _$BridgePersistenceBrief_RecoveringCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision, PlatformInt64 firstFailedAt
});




}
/// @nodoc
class _$BridgePersistenceBrief_RecoveringCopyWithImpl<$Res>
    implements $BridgePersistenceBrief_RecoveringCopyWith<$Res> {
  _$BridgePersistenceBrief_RecoveringCopyWithImpl(this._self, this._then);

  final BridgePersistenceBrief_Recovering _self;
  final $Res Function(BridgePersistenceBrief_Recovering) _then;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(BridgePersistenceBrief_Recovering(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgePersistenceBrief_Blocked extends BridgePersistenceBrief {
  const BridgePersistenceBrief_Blocked({required this.pendingCommits, this.oldestPendingRevision, required this.firstFailedAt}): super._();


@override final  BigInt pendingCommits;
 final  BigInt? oldestPendingRevision;
 final  PlatformInt64 firstFailedAt;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceBrief_BlockedCopyWith<BridgePersistenceBrief_Blocked> get copyWith => _$BridgePersistenceBrief_BlockedCopyWithImpl<BridgePersistenceBrief_Blocked>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceBrief_Blocked&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}

@override
String toString() {
    return 'BridgePersistenceBrief.blocked(pendingCommits: $pendingCommits, oldestPendingRevision: $oldestPendingRevision, firstFailedAt: $firstFailedAt)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceBrief_BlockedCopyWith<$Res> implements $BridgePersistenceBriefCopyWith<$Res> {
  factory $BridgePersistenceBrief_BlockedCopyWith(BridgePersistenceBrief_Blocked value, $Res Function(BridgePersistenceBrief_Blocked) _then) = _$BridgePersistenceBrief_BlockedCopyWithImpl;
@override @useResult
$Res call({
 BigInt pendingCommits, BigInt? oldestPendingRevision, PlatformInt64 firstFailedAt
});




}
/// @nodoc
class _$BridgePersistenceBrief_BlockedCopyWithImpl<$Res>
    implements $BridgePersistenceBrief_BlockedCopyWith<$Res> {
  _$BridgePersistenceBrief_BlockedCopyWithImpl(this._self, this._then);

  final BridgePersistenceBrief_Blocked _self;
  final $Res Function(BridgePersistenceBrief_Blocked) _then;

/// Create a copy of BridgePersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(BridgePersistenceBrief_Blocked(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as BigInt,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as BigInt?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc
mixin _$BridgePersistenceEvent {

 BridgeProductProjectionStamp get stamp; BridgePersistenceHeader get value;
/// Create a copy of BridgePersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceEventCopyWith<BridgePersistenceEvent> get copyWith => _$BridgePersistenceEventCopyWithImpl<BridgePersistenceEvent>(this as BridgePersistenceEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgePersistenceEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as BridgePersistenceEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as BridgePersistenceEvent;
  return 'BridgePersistenceEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceEventCopyWith<$Res>  {
  factory $BridgePersistenceEventCopyWith(BridgePersistenceEvent value, $Res Function(BridgePersistenceEvent) _then) = _$BridgePersistenceEventCopyWithImpl;
@useResult
$Res call({
 BridgeProductProjectionStamp stamp, BridgePersistenceHeader value
});




}
/// @nodoc
class _$BridgePersistenceEventCopyWithImpl<$Res>
    implements $BridgePersistenceEventCopyWith<$Res> {
  _$BridgePersistenceEventCopyWithImpl(this._self, this._then);

  final BridgePersistenceEvent _self;
  final $Res Function(BridgePersistenceEvent) _then;

/// Create a copy of BridgePersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePersistenceHeader,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgePersistenceEvent].
extension BridgePersistenceEventPatterns on BridgePersistenceEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePersistenceEvent_Baseline value)?  baseline,TResult Function( BridgePersistenceEvent_Replace value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePersistenceEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePersistenceEvent_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePersistenceEvent_Baseline value)  baseline,required TResult Function( BridgePersistenceEvent_Replace value)  replace,}){
final _that = this;
switch (_that) {
case BridgePersistenceEvent_Baseline():
return baseline(_that);case BridgePersistenceEvent_Replace():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePersistenceEvent_Baseline value)?  baseline,TResult? Function( BridgePersistenceEvent_Replace value)?  replace,}){
final _that = this;
switch (_that) {
case BridgePersistenceEvent_Baseline() when baseline != null:
return baseline(_that);case BridgePersistenceEvent_Replace() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePersistenceHeader value)?  baseline,TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePersistenceHeader value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePersistenceEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePersistenceEvent_Replace() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePersistenceHeader value)  baseline,required TResult Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePersistenceHeader value)  replace,}) {final _that = this;
switch (_that) {
case BridgePersistenceEvent_Baseline():
return baseline(_that.identity,_that.stamp,_that.value);case BridgePersistenceEvent_Replace():
return replace(_that.stamp,_that.baseRevision,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductProjectionStamp stamp,  BridgePersistenceHeader value)?  baseline,TResult? Function( BridgeProductProjectionStamp stamp,  BigInt baseRevision,  BridgePersistenceHeader value)?  replace,}) {final _that = this;
switch (_that) {
case BridgePersistenceEvent_Baseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case BridgePersistenceEvent_Replace() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class BridgePersistenceEvent_Baseline extends BridgePersistenceEvent {
  const BridgePersistenceEvent_Baseline({required this.identity, required this.stamp, required this.value}): super._();


 final  BridgeProductFeedIdentity identity;
@override final  BridgeProductProjectionStamp stamp;
@override final  BridgePersistenceHeader value;

/// Create a copy of BridgePersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceEvent_BaselineCopyWith<BridgePersistenceEvent_Baseline> get copyWith => _$BridgePersistenceEvent_BaselineCopyWithImpl<BridgePersistenceEvent_Baseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceEvent_Baseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'BridgePersistenceEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceEvent_BaselineCopyWith<$Res> implements $BridgePersistenceEventCopyWith<$Res> {
  factory $BridgePersistenceEvent_BaselineCopyWith(BridgePersistenceEvent_Baseline value, $Res Function(BridgePersistenceEvent_Baseline) _then) = _$BridgePersistenceEvent_BaselineCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductProjectionStamp stamp, BridgePersistenceHeader value
});




}
/// @nodoc
class _$BridgePersistenceEvent_BaselineCopyWithImpl<$Res>
    implements $BridgePersistenceEvent_BaselineCopyWith<$Res> {
  _$BridgePersistenceEvent_BaselineCopyWithImpl(this._self, this._then);

  final BridgePersistenceEvent_Baseline _self;
  final $Res Function(BridgePersistenceEvent_Baseline) _then;

/// Create a copy of BridgePersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(BridgePersistenceEvent_Baseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePersistenceHeader,
  ));
}


}

/// @nodoc


class BridgePersistenceEvent_Replace extends BridgePersistenceEvent {
  const BridgePersistenceEvent_Replace({required this.stamp, required this.baseRevision, required this.value}): super._();


@override final  BridgeProductProjectionStamp stamp;
 final  BigInt baseRevision;
@override final  BridgePersistenceHeader value;

/// Create a copy of BridgePersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceEvent_ReplaceCopyWith<BridgePersistenceEvent_Replace> get copyWith => _$BridgePersistenceEvent_ReplaceCopyWithImpl<BridgePersistenceEvent_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceEvent_Replace&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'BridgePersistenceEvent.replace(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceEvent_ReplaceCopyWith<$Res> implements $BridgePersistenceEventCopyWith<$Res> {
  factory $BridgePersistenceEvent_ReplaceCopyWith(BridgePersistenceEvent_Replace value, $Res Function(BridgePersistenceEvent_Replace) _then) = _$BridgePersistenceEvent_ReplaceCopyWithImpl;
@override @useResult
$Res call({
 BridgeProductProjectionStamp stamp, BigInt baseRevision, BridgePersistenceHeader value
});




}
/// @nodoc
class _$BridgePersistenceEvent_ReplaceCopyWithImpl<$Res>
    implements $BridgePersistenceEvent_ReplaceCopyWith<$Res> {
  _$BridgePersistenceEvent_ReplaceCopyWithImpl(this._self, this._then);

  final BridgePersistenceEvent_Replace _self;
  final $Res Function(BridgePersistenceEvent_Replace) _then;

/// Create a copy of BridgePersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(BridgePersistenceEvent_Replace(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as BridgeProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as BigInt,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as BridgePersistenceHeader,
  ));
}


}

/// @nodoc
mixin _$BridgePersistenceFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceFrame);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePersistenceFrame()';
}


}

/// @nodoc
class $BridgePersistenceFrameCopyWith<$Res>  {
$BridgePersistenceFrameCopyWith(BridgePersistenceFrame _, $Res Function(BridgePersistenceFrame) __);
}


/// Adds pattern-matching-related methods to [BridgePersistenceFrame].
extension BridgePersistenceFramePatterns on BridgePersistenceFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePersistenceFrame_Data value)?  data,TResult Function( BridgePersistenceFrame_ResyncRequired value)?  resyncRequired,TResult Function( BridgePersistenceFrame_Failure value)?  failure,TResult Function( BridgePersistenceFrame_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePersistenceFrame_Data() when data != null:
return data(_that);case BridgePersistenceFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePersistenceFrame_Failure() when failure != null:
return failure(_that);case BridgePersistenceFrame_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePersistenceFrame_Data value)  data,required TResult Function( BridgePersistenceFrame_ResyncRequired value)  resyncRequired,required TResult Function( BridgePersistenceFrame_Failure value)  failure,required TResult Function( BridgePersistenceFrame_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgePersistenceFrame_Data():
return data(_that);case BridgePersistenceFrame_ResyncRequired():
return resyncRequired(_that);case BridgePersistenceFrame_Failure():
return failure(_that);case BridgePersistenceFrame_Closed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePersistenceFrame_Data value)?  data,TResult? Function( BridgePersistenceFrame_ResyncRequired value)?  resyncRequired,TResult? Function( BridgePersistenceFrame_Failure value)?  failure,TResult? Function( BridgePersistenceFrame_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgePersistenceFrame_Data() when data != null:
return data(_that);case BridgePersistenceFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BridgePersistenceFrame_Failure() when failure != null:
return failure(_that);case BridgePersistenceFrame_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt deliverySequence,  BridgePersistenceEvent event)?  data,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePersistenceFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePersistenceFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePersistenceFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePersistenceFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt deliverySequence,  BridgePersistenceEvent event)  data,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)  resyncRequired,required TResult Function( BridgeProductFeedIdentity identity,  BridgeError error)  failure,required TResult Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BridgePersistenceFrame_Data():
return data(_that.deliverySequence,_that.event);case BridgePersistenceFrame_ResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BridgePersistenceFrame_Failure():
return failure(_that.identity,_that.error);case BridgePersistenceFrame_Closed():
return closed(_that.identity,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt deliverySequence,  BridgePersistenceEvent event)?  data,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductResyncReason reason)?  resyncRequired,TResult? Function( BridgeProductFeedIdentity identity,  BridgeError error)?  failure,TResult? Function( BridgeProductFeedIdentity identity,  BridgeProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BridgePersistenceFrame_Data() when data != null:
return data(_that.deliverySequence,_that.event);case BridgePersistenceFrame_ResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BridgePersistenceFrame_Failure() when failure != null:
return failure(_that.identity,_that.error);case BridgePersistenceFrame_Closed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BridgePersistenceFrame_Data extends BridgePersistenceFrame {
  const BridgePersistenceFrame_Data({required this.deliverySequence, required this.event}): super._();


 final  BigInt deliverySequence;
 final  BridgePersistenceEvent event;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceFrame_DataCopyWith<BridgePersistenceFrame_Data> get copyWith => _$BridgePersistenceFrame_DataCopyWithImpl<BridgePersistenceFrame_Data>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceFrame_Data&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}

@override
String toString() {
    return 'BridgePersistenceFrame.data(deliverySequence: $deliverySequence, event: $event)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceFrame_DataCopyWith<$Res> implements $BridgePersistenceFrameCopyWith<$Res> {
  factory $BridgePersistenceFrame_DataCopyWith(BridgePersistenceFrame_Data value, $Res Function(BridgePersistenceFrame_Data) _then) = _$BridgePersistenceFrame_DataCopyWithImpl;
@useResult
$Res call({
 BigInt deliverySequence, BridgePersistenceEvent event
});


$BridgePersistenceEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BridgePersistenceFrame_DataCopyWithImpl<$Res>
    implements $BridgePersistenceFrame_DataCopyWith<$Res> {
  _$BridgePersistenceFrame_DataCopyWithImpl(this._self, this._then);

  final BridgePersistenceFrame_Data _self;
  final $Res Function(BridgePersistenceFrame_Data) _then;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BridgePersistenceFrame_Data(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as BigInt,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BridgePersistenceEvent,
  ));
}

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgePersistenceEventCopyWith<$Res> get event {

  return $BridgePersistenceEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BridgePersistenceFrame_ResyncRequired extends BridgePersistenceFrame {
  const BridgePersistenceFrame_ResyncRequired({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductResyncReason reason;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceFrame_ResyncRequiredCopyWith<BridgePersistenceFrame_ResyncRequired> get copyWith => _$BridgePersistenceFrame_ResyncRequiredCopyWithImpl<BridgePersistenceFrame_ResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceFrame_ResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePersistenceFrame.resyncRequired(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceFrame_ResyncRequiredCopyWith<$Res> implements $BridgePersistenceFrameCopyWith<$Res> {
  factory $BridgePersistenceFrame_ResyncRequiredCopyWith(BridgePersistenceFrame_ResyncRequired value, $Res Function(BridgePersistenceFrame_ResyncRequired) _then) = _$BridgePersistenceFrame_ResyncRequiredCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductResyncReason reason
});




}
/// @nodoc
class _$BridgePersistenceFrame_ResyncRequiredCopyWithImpl<$Res>
    implements $BridgePersistenceFrame_ResyncRequiredCopyWith<$Res> {
  _$BridgePersistenceFrame_ResyncRequiredCopyWithImpl(this._self, this._then);

  final BridgePersistenceFrame_ResyncRequired _self;
  final $Res Function(BridgePersistenceFrame_ResyncRequired) _then;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePersistenceFrame_ResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductResyncReason,
  ));
}


}

/// @nodoc


class BridgePersistenceFrame_Failure extends BridgePersistenceFrame {
  const BridgePersistenceFrame_Failure({required this.identity, required this.error}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeError error;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceFrame_FailureCopyWith<BridgePersistenceFrame_Failure> get copyWith => _$BridgePersistenceFrame_FailureCopyWithImpl<BridgePersistenceFrame_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceFrame_Failure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}

@override
String toString() {
    return 'BridgePersistenceFrame.failure(identity: $identity, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceFrame_FailureCopyWith<$Res> implements $BridgePersistenceFrameCopyWith<$Res> {
  factory $BridgePersistenceFrame_FailureCopyWith(BridgePersistenceFrame_Failure value, $Res Function(BridgePersistenceFrame_Failure) _then) = _$BridgePersistenceFrame_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeError error
});




}
/// @nodoc
class _$BridgePersistenceFrame_FailureCopyWithImpl<$Res>
    implements $BridgePersistenceFrame_FailureCopyWith<$Res> {
  _$BridgePersistenceFrame_FailureCopyWithImpl(this._self, this._then);

  final BridgePersistenceFrame_Failure _self;
  final $Res Function(BridgePersistenceFrame_Failure) _then;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BridgePersistenceFrame_Failure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgePersistenceFrame_Closed extends BridgePersistenceFrame {
  const BridgePersistenceFrame_Closed({required this.identity, required this.reason}): super._();


 final  BridgeProductFeedIdentity identity;
 final  BridgeProductFeedCloseReason reason;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePersistenceFrame_ClosedCopyWith<BridgePersistenceFrame_Closed> get copyWith => _$BridgePersistenceFrame_ClosedCopyWithImpl<BridgePersistenceFrame_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePersistenceFrame_Closed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}

@override
String toString() {
    return 'BridgePersistenceFrame.closed(identity: $identity, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgePersistenceFrame_ClosedCopyWith<$Res> implements $BridgePersistenceFrameCopyWith<$Res> {
  factory $BridgePersistenceFrame_ClosedCopyWith(BridgePersistenceFrame_Closed value, $Res Function(BridgePersistenceFrame_Closed) _then) = _$BridgePersistenceFrame_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeProductFeedIdentity identity, BridgeProductFeedCloseReason reason
});




}
/// @nodoc
class _$BridgePersistenceFrame_ClosedCopyWithImpl<$Res>
    implements $BridgePersistenceFrame_ClosedCopyWith<$Res> {
  _$BridgePersistenceFrame_ClosedCopyWithImpl(this._self, this._then);

  final BridgePersistenceFrame_Closed _self;
  final $Res Function(BridgePersistenceFrame_Closed) _then;

/// Create a copy of BridgePersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BridgePersistenceFrame_Closed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeProductFeedCloseReason,
  ));
}


}

// dart format on
