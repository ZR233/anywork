// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeObservedBrief {

 BigInt get revision;
/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBriefCopyWith<BridgeObservedBrief> get copyWith => _$BridgeObservedBriefCopyWithImpl<BridgeObservedBrief>(this as BridgeObservedBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeObservedBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as BridgeObservedBrief;
  return Object.hash(runtimeType,_this.revision);
}

@override
String toString() {
  final _this = this as BridgeObservedBrief;
  return 'BridgeObservedBrief(revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBriefCopyWith<$Res>  {
  factory $BridgeObservedBriefCopyWith(BridgeObservedBrief value, $Res Function(BridgeObservedBrief) _then) = _$BridgeObservedBriefCopyWithImpl;
@useResult
$Res call({
 BigInt revision
});




}
/// @nodoc
class _$BridgeObservedBriefCopyWithImpl<$Res>
    implements $BridgeObservedBriefCopyWith<$Res> {
  _$BridgeObservedBriefCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief _self;
  final $Res Function(BridgeObservedBrief) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeObservedBrief].
extension BridgeObservedBriefPatterns on BridgeObservedBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeObservedBrief_Uninitialized value)?  uninitialized,TResult Function( BridgeObservedBrief_Loading value)?  loading,TResult Function( BridgeObservedBrief_Ready value)?  ready,TResult Function( BridgeObservedBrief_Refreshing value)?  refreshing,TResult Function( BridgeObservedBrief_Stale value)?  stale,TResult Function( BridgeObservedBrief_Degraded value)?  degraded,TResult Function( BridgeObservedBrief_Failed value)?  failed,TResult Function( BridgeObservedBrief_Stopped value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeObservedBrief_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeObservedBrief_Loading() when loading != null:
return loading(_that);case BridgeObservedBrief_Ready() when ready != null:
return ready(_that);case BridgeObservedBrief_Refreshing() when refreshing != null:
return refreshing(_that);case BridgeObservedBrief_Stale() when stale != null:
return stale(_that);case BridgeObservedBrief_Degraded() when degraded != null:
return degraded(_that);case BridgeObservedBrief_Failed() when failed != null:
return failed(_that);case BridgeObservedBrief_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeObservedBrief_Uninitialized value)  uninitialized,required TResult Function( BridgeObservedBrief_Loading value)  loading,required TResult Function( BridgeObservedBrief_Ready value)  ready,required TResult Function( BridgeObservedBrief_Refreshing value)  refreshing,required TResult Function( BridgeObservedBrief_Stale value)  stale,required TResult Function( BridgeObservedBrief_Degraded value)  degraded,required TResult Function( BridgeObservedBrief_Failed value)  failed,required TResult Function( BridgeObservedBrief_Stopped value)  stopped,}){
final _that = this;
switch (_that) {
case BridgeObservedBrief_Uninitialized():
return uninitialized(_that);case BridgeObservedBrief_Loading():
return loading(_that);case BridgeObservedBrief_Ready():
return ready(_that);case BridgeObservedBrief_Refreshing():
return refreshing(_that);case BridgeObservedBrief_Stale():
return stale(_that);case BridgeObservedBrief_Degraded():
return degraded(_that);case BridgeObservedBrief_Failed():
return failed(_that);case BridgeObservedBrief_Stopped():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeObservedBrief_Uninitialized value)?  uninitialized,TResult? Function( BridgeObservedBrief_Loading value)?  loading,TResult? Function( BridgeObservedBrief_Ready value)?  ready,TResult? Function( BridgeObservedBrief_Refreshing value)?  refreshing,TResult? Function( BridgeObservedBrief_Stale value)?  stale,TResult? Function( BridgeObservedBrief_Degraded value)?  degraded,TResult? Function( BridgeObservedBrief_Failed value)?  failed,TResult? Function( BridgeObservedBrief_Stopped value)?  stopped,}){
final _that = this;
switch (_that) {
case BridgeObservedBrief_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeObservedBrief_Loading() when loading != null:
return loading(_that);case BridgeObservedBrief_Ready() when ready != null:
return ready(_that);case BridgeObservedBrief_Refreshing() when refreshing != null:
return refreshing(_that);case BridgeObservedBrief_Stale() when stale != null:
return stale(_that);case BridgeObservedBrief_Degraded() when degraded != null:
return degraded(_that);case BridgeObservedBrief_Failed() when failed != null:
return failed(_that);case BridgeObservedBrief_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt revision,  PlatformInt64 updatedAt)?  uninitialized,TResult Function( BigInt revision,  PlatformInt64 startedAt)?  loading,TResult Function( BigInt revision,  PlatformInt64 updatedAt,  PlatformInt64? lastCheckedAt)?  ready,TResult Function( BigInt revision,  PlatformInt64 startedAt,  PlatformInt64? lastCheckedAt)?  refreshing,TResult Function( BigInt revision,  PlatformInt64 staleAt,  PlatformInt64? lastCheckedAt)?  stale,TResult Function( BigInt revision,  PlatformInt64 failedAt,  PlatformInt64? lastCheckedAt,  bool retryable)?  degraded,TResult Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)?  failed,TResult Function( BigInt revision,  PlatformInt64 stoppedAt)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeObservedBrief_Uninitialized() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case BridgeObservedBrief_Loading() when loading != null:
return loading(_that.revision,_that.startedAt);case BridgeObservedBrief_Ready() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case BridgeObservedBrief_Refreshing() when refreshing != null:
return refreshing(_that.revision,_that.startedAt,_that.lastCheckedAt);case BridgeObservedBrief_Stale() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case BridgeObservedBrief_Degraded() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.retryable);case BridgeObservedBrief_Failed() when failed != null:
return failed(_that.revision,_that.failedAt,_that.retryable);case BridgeObservedBrief_Stopped() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt revision,  PlatformInt64 updatedAt)  uninitialized,required TResult Function( BigInt revision,  PlatformInt64 startedAt)  loading,required TResult Function( BigInt revision,  PlatformInt64 updatedAt,  PlatformInt64? lastCheckedAt)  ready,required TResult Function( BigInt revision,  PlatformInt64 startedAt,  PlatformInt64? lastCheckedAt)  refreshing,required TResult Function( BigInt revision,  PlatformInt64 staleAt,  PlatformInt64? lastCheckedAt)  stale,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  PlatformInt64? lastCheckedAt,  bool retryable)  degraded,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)  failed,required TResult Function( BigInt revision,  PlatformInt64 stoppedAt)  stopped,}) {final _that = this;
switch (_that) {
case BridgeObservedBrief_Uninitialized():
return uninitialized(_that.revision,_that.updatedAt);case BridgeObservedBrief_Loading():
return loading(_that.revision,_that.startedAt);case BridgeObservedBrief_Ready():
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case BridgeObservedBrief_Refreshing():
return refreshing(_that.revision,_that.startedAt,_that.lastCheckedAt);case BridgeObservedBrief_Stale():
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case BridgeObservedBrief_Degraded():
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.retryable);case BridgeObservedBrief_Failed():
return failed(_that.revision,_that.failedAt,_that.retryable);case BridgeObservedBrief_Stopped():
return stopped(_that.revision,_that.stoppedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt revision,  PlatformInt64 updatedAt)?  uninitialized,TResult? Function( BigInt revision,  PlatformInt64 startedAt)?  loading,TResult? Function( BigInt revision,  PlatformInt64 updatedAt,  PlatformInt64? lastCheckedAt)?  ready,TResult? Function( BigInt revision,  PlatformInt64 startedAt,  PlatformInt64? lastCheckedAt)?  refreshing,TResult? Function( BigInt revision,  PlatformInt64 staleAt,  PlatformInt64? lastCheckedAt)?  stale,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  PlatformInt64? lastCheckedAt,  bool retryable)?  degraded,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  bool retryable)?  failed,TResult? Function( BigInt revision,  PlatformInt64 stoppedAt)?  stopped,}) {final _that = this;
switch (_that) {
case BridgeObservedBrief_Uninitialized() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case BridgeObservedBrief_Loading() when loading != null:
return loading(_that.revision,_that.startedAt);case BridgeObservedBrief_Ready() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case BridgeObservedBrief_Refreshing() when refreshing != null:
return refreshing(_that.revision,_that.startedAt,_that.lastCheckedAt);case BridgeObservedBrief_Stale() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case BridgeObservedBrief_Degraded() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.retryable);case BridgeObservedBrief_Failed() when failed != null:
return failed(_that.revision,_that.failedAt,_that.retryable);case BridgeObservedBrief_Stopped() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
  return null;

}
}

}

/// @nodoc


class BridgeObservedBrief_Uninitialized extends BridgeObservedBrief {
  const BridgeObservedBrief_Uninitialized({required this.revision, required this.updatedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_UninitializedCopyWith<BridgeObservedBrief_Uninitialized> get copyWith => _$BridgeObservedBrief_UninitializedCopyWithImpl<BridgeObservedBrief_Uninitialized>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Uninitialized&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'BridgeObservedBrief.uninitialized(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_UninitializedCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_UninitializedCopyWith(BridgeObservedBrief_Uninitialized value, $Res Function(BridgeObservedBrief_Uninitialized) _then) = _$BridgeObservedBrief_UninitializedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt
});




}
/// @nodoc
class _$BridgeObservedBrief_UninitializedCopyWithImpl<$Res>
    implements $BridgeObservedBrief_UninitializedCopyWith<$Res> {
  _$BridgeObservedBrief_UninitializedCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Uninitialized _self;
  final $Res Function(BridgeObservedBrief_Uninitialized) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(BridgeObservedBrief_Uninitialized(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeObservedBrief_Loading extends BridgeObservedBrief {
  const BridgeObservedBrief_Loading({required this.revision, required this.startedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 startedAt;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_LoadingCopyWith<BridgeObservedBrief_Loading> get copyWith => _$BridgeObservedBrief_LoadingCopyWithImpl<BridgeObservedBrief_Loading>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Loading&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,startedAt);
}

@override
String toString() {
    return 'BridgeObservedBrief.loading(revision: $revision, startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_LoadingCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_LoadingCopyWith(BridgeObservedBrief_Loading value, $Res Function(BridgeObservedBrief_Loading) _then) = _$BridgeObservedBrief_LoadingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 startedAt
});




}
/// @nodoc
class _$BridgeObservedBrief_LoadingCopyWithImpl<$Res>
    implements $BridgeObservedBrief_LoadingCopyWith<$Res> {
  _$BridgeObservedBrief_LoadingCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Loading _self;
  final $Res Function(BridgeObservedBrief_Loading) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? startedAt = null,}) {
  return _then(BridgeObservedBrief_Loading(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeObservedBrief_Ready extends BridgeObservedBrief {
  const BridgeObservedBrief_Ready({required this.revision, required this.updatedAt, this.lastCheckedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;
 final  PlatformInt64? lastCheckedAt;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_ReadyCopyWith<BridgeObservedBrief_Ready> get copyWith => _$BridgeObservedBrief_ReadyCopyWithImpl<BridgeObservedBrief_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Ready&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,lastCheckedAt);
}

@override
String toString() {
    return 'BridgeObservedBrief.ready(revision: $revision, updatedAt: $updatedAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_ReadyCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_ReadyCopyWith(BridgeObservedBrief_Ready value, $Res Function(BridgeObservedBrief_Ready) _then) = _$BridgeObservedBrief_ReadyCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt, PlatformInt64? lastCheckedAt
});




}
/// @nodoc
class _$BridgeObservedBrief_ReadyCopyWithImpl<$Res>
    implements $BridgeObservedBrief_ReadyCopyWith<$Res> {
  _$BridgeObservedBrief_ReadyCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Ready _self;
  final $Res Function(BridgeObservedBrief_Ready) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(BridgeObservedBrief_Ready(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeObservedBrief_Refreshing extends BridgeObservedBrief {
  const BridgeObservedBrief_Refreshing({required this.revision, required this.startedAt, this.lastCheckedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 startedAt;
 final  PlatformInt64? lastCheckedAt;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_RefreshingCopyWith<BridgeObservedBrief_Refreshing> get copyWith => _$BridgeObservedBrief_RefreshingCopyWithImpl<BridgeObservedBrief_Refreshing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Refreshing&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,startedAt,lastCheckedAt);
}

@override
String toString() {
    return 'BridgeObservedBrief.refreshing(revision: $revision, startedAt: $startedAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_RefreshingCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_RefreshingCopyWith(BridgeObservedBrief_Refreshing value, $Res Function(BridgeObservedBrief_Refreshing) _then) = _$BridgeObservedBrief_RefreshingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 startedAt, PlatformInt64? lastCheckedAt
});




}
/// @nodoc
class _$BridgeObservedBrief_RefreshingCopyWithImpl<$Res>
    implements $BridgeObservedBrief_RefreshingCopyWith<$Res> {
  _$BridgeObservedBrief_RefreshingCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Refreshing _self;
  final $Res Function(BridgeObservedBrief_Refreshing) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? startedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(BridgeObservedBrief_Refreshing(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeObservedBrief_Stale extends BridgeObservedBrief {
  const BridgeObservedBrief_Stale({required this.revision, required this.staleAt, this.lastCheckedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 staleAt;
 final  PlatformInt64? lastCheckedAt;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_StaleCopyWith<BridgeObservedBrief_Stale> get copyWith => _$BridgeObservedBrief_StaleCopyWithImpl<BridgeObservedBrief_Stale>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Stale&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.staleAt, staleAt) || other.staleAt == staleAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,staleAt,lastCheckedAt);
}

@override
String toString() {
    return 'BridgeObservedBrief.stale(revision: $revision, staleAt: $staleAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_StaleCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_StaleCopyWith(BridgeObservedBrief_Stale value, $Res Function(BridgeObservedBrief_Stale) _then) = _$BridgeObservedBrief_StaleCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 staleAt, PlatformInt64? lastCheckedAt
});




}
/// @nodoc
class _$BridgeObservedBrief_StaleCopyWithImpl<$Res>
    implements $BridgeObservedBrief_StaleCopyWith<$Res> {
  _$BridgeObservedBrief_StaleCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Stale _self;
  final $Res Function(BridgeObservedBrief_Stale) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? staleAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(BridgeObservedBrief_Stale(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,staleAt: null == staleAt ? _self.staleAt : staleAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeObservedBrief_Degraded extends BridgeObservedBrief {
  const BridgeObservedBrief_Degraded({required this.revision, required this.failedAt, this.lastCheckedAt, required this.retryable}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  PlatformInt64? lastCheckedAt;
 final  bool retryable;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_DegradedCopyWith<BridgeObservedBrief_Degraded> get copyWith => _$BridgeObservedBrief_DegradedCopyWithImpl<BridgeObservedBrief_Degraded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Degraded&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,lastCheckedAt,retryable);
}

@override
String toString() {
    return 'BridgeObservedBrief.degraded(revision: $revision, failedAt: $failedAt, lastCheckedAt: $lastCheckedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_DegradedCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_DegradedCopyWith(BridgeObservedBrief_Degraded value, $Res Function(BridgeObservedBrief_Degraded) _then) = _$BridgeObservedBrief_DegradedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, PlatformInt64? lastCheckedAt, bool retryable
});




}
/// @nodoc
class _$BridgeObservedBrief_DegradedCopyWithImpl<$Res>
    implements $BridgeObservedBrief_DegradedCopyWith<$Res> {
  _$BridgeObservedBrief_DegradedCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Degraded _self;
  final $Res Function(BridgeObservedBrief_Degraded) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? lastCheckedAt = freezed,Object? retryable = null,}) {
  return _then(BridgeObservedBrief_Degraded(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeObservedBrief_Failed extends BridgeObservedBrief {
  const BridgeObservedBrief_Failed({required this.revision, required this.failedAt, required this.retryable}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  bool retryable;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_FailedCopyWith<BridgeObservedBrief_Failed> get copyWith => _$BridgeObservedBrief_FailedCopyWithImpl<BridgeObservedBrief_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Failed&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,retryable);
}

@override
String toString() {
    return 'BridgeObservedBrief.failed(revision: $revision, failedAt: $failedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_FailedCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_FailedCopyWith(BridgeObservedBrief_Failed value, $Res Function(BridgeObservedBrief_Failed) _then) = _$BridgeObservedBrief_FailedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, bool retryable
});




}
/// @nodoc
class _$BridgeObservedBrief_FailedCopyWithImpl<$Res>
    implements $BridgeObservedBrief_FailedCopyWith<$Res> {
  _$BridgeObservedBrief_FailedCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Failed _self;
  final $Res Function(BridgeObservedBrief_Failed) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? retryable = null,}) {
  return _then(BridgeObservedBrief_Failed(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class BridgeObservedBrief_Stopped extends BridgeObservedBrief {
  const BridgeObservedBrief_Stopped({required this.revision, required this.stoppedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 stoppedAt;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeObservedBrief_StoppedCopyWith<BridgeObservedBrief_Stopped> get copyWith => _$BridgeObservedBrief_StoppedCopyWithImpl<BridgeObservedBrief_Stopped>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeObservedBrief_Stopped&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.stoppedAt, stoppedAt) || other.stoppedAt == stoppedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,stoppedAt);
}

@override
String toString() {
    return 'BridgeObservedBrief.stopped(revision: $revision, stoppedAt: $stoppedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeObservedBrief_StoppedCopyWith<$Res> implements $BridgeObservedBriefCopyWith<$Res> {
  factory $BridgeObservedBrief_StoppedCopyWith(BridgeObservedBrief_Stopped value, $Res Function(BridgeObservedBrief_Stopped) _then) = _$BridgeObservedBrief_StoppedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 stoppedAt
});




}
/// @nodoc
class _$BridgeObservedBrief_StoppedCopyWithImpl<$Res>
    implements $BridgeObservedBrief_StoppedCopyWith<$Res> {
  _$BridgeObservedBrief_StoppedCopyWithImpl(this._self, this._then);

  final BridgeObservedBrief_Stopped _self;
  final $Res Function(BridgeObservedBrief_Stopped) _then;

/// Create a copy of BridgeObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? stoppedAt = null,}) {
  return _then(BridgeObservedBrief_Stopped(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,stoppedAt: null == stoppedAt ? _self.stoppedAt : stoppedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc
mixin _$BridgeProductSourceStatusReadHeader {

 BigInt get revision;
/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeaderCopyWith<BridgeProductSourceStatusReadHeader> get copyWith => _$BridgeProductSourceStatusReadHeaderCopyWithImpl<BridgeProductSourceStatusReadHeader>(this as BridgeProductSourceStatusReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeProductSourceStatusReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as BridgeProductSourceStatusReadHeader;
  return Object.hash(runtimeType,_this.revision);
}

@override
String toString() {
  final _this = this as BridgeProductSourceStatusReadHeader;
  return 'BridgeProductSourceStatusReadHeader(revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeaderCopyWith<$Res>  {
  factory $BridgeProductSourceStatusReadHeaderCopyWith(BridgeProductSourceStatusReadHeader value, $Res Function(BridgeProductSourceStatusReadHeader) _then) = _$BridgeProductSourceStatusReadHeaderCopyWithImpl;
@useResult
$Res call({
 BigInt revision
});




}
/// @nodoc
class _$BridgeProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader _self;
  final $Res Function(BridgeProductSourceStatusReadHeader) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeProductSourceStatusReadHeader].
extension BridgeProductSourceStatusReadHeaderPatterns on BridgeProductSourceStatusReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeProductSourceStatusReadHeader_Uninitialized value)?  uninitialized,TResult Function( BridgeProductSourceStatusReadHeader_Loading value)?  loading,TResult Function( BridgeProductSourceStatusReadHeader_Ready value)?  ready,TResult Function( BridgeProductSourceStatusReadHeader_Refreshing value)?  refreshing,TResult Function( BridgeProductSourceStatusReadHeader_Stale value)?  stale,TResult Function( BridgeProductSourceStatusReadHeader_Degraded value)?  degraded,TResult Function( BridgeProductSourceStatusReadHeader_Failed value)?  failed,TResult Function( BridgeProductSourceStatusReadHeader_Stopped value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeProductSourceStatusReadHeader_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeProductSourceStatusReadHeader_Loading() when loading != null:
return loading(_that);case BridgeProductSourceStatusReadHeader_Ready() when ready != null:
return ready(_that);case BridgeProductSourceStatusReadHeader_Refreshing() when refreshing != null:
return refreshing(_that);case BridgeProductSourceStatusReadHeader_Stale() when stale != null:
return stale(_that);case BridgeProductSourceStatusReadHeader_Degraded() when degraded != null:
return degraded(_that);case BridgeProductSourceStatusReadHeader_Failed() when failed != null:
return failed(_that);case BridgeProductSourceStatusReadHeader_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeProductSourceStatusReadHeader_Uninitialized value)  uninitialized,required TResult Function( BridgeProductSourceStatusReadHeader_Loading value)  loading,required TResult Function( BridgeProductSourceStatusReadHeader_Ready value)  ready,required TResult Function( BridgeProductSourceStatusReadHeader_Refreshing value)  refreshing,required TResult Function( BridgeProductSourceStatusReadHeader_Stale value)  stale,required TResult Function( BridgeProductSourceStatusReadHeader_Degraded value)  degraded,required TResult Function( BridgeProductSourceStatusReadHeader_Failed value)  failed,required TResult Function( BridgeProductSourceStatusReadHeader_Stopped value)  stopped,}){
final _that = this;
switch (_that) {
case BridgeProductSourceStatusReadHeader_Uninitialized():
return uninitialized(_that);case BridgeProductSourceStatusReadHeader_Loading():
return loading(_that);case BridgeProductSourceStatusReadHeader_Ready():
return ready(_that);case BridgeProductSourceStatusReadHeader_Refreshing():
return refreshing(_that);case BridgeProductSourceStatusReadHeader_Stale():
return stale(_that);case BridgeProductSourceStatusReadHeader_Degraded():
return degraded(_that);case BridgeProductSourceStatusReadHeader_Failed():
return failed(_that);case BridgeProductSourceStatusReadHeader_Stopped():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeProductSourceStatusReadHeader_Uninitialized value)?  uninitialized,TResult? Function( BridgeProductSourceStatusReadHeader_Loading value)?  loading,TResult? Function( BridgeProductSourceStatusReadHeader_Ready value)?  ready,TResult? Function( BridgeProductSourceStatusReadHeader_Refreshing value)?  refreshing,TResult? Function( BridgeProductSourceStatusReadHeader_Stale value)?  stale,TResult? Function( BridgeProductSourceStatusReadHeader_Degraded value)?  degraded,TResult? Function( BridgeProductSourceStatusReadHeader_Failed value)?  failed,TResult? Function( BridgeProductSourceStatusReadHeader_Stopped value)?  stopped,}){
final _that = this;
switch (_that) {
case BridgeProductSourceStatusReadHeader_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeProductSourceStatusReadHeader_Loading() when loading != null:
return loading(_that);case BridgeProductSourceStatusReadHeader_Ready() when ready != null:
return ready(_that);case BridgeProductSourceStatusReadHeader_Refreshing() when refreshing != null:
return refreshing(_that);case BridgeProductSourceStatusReadHeader_Stale() when stale != null:
return stale(_that);case BridgeProductSourceStatusReadHeader_Degraded() when degraded != null:
return degraded(_that);case BridgeProductSourceStatusReadHeader_Failed() when failed != null:
return failed(_that);case BridgeProductSourceStatusReadHeader_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt revision,  PlatformInt64 updatedAt)?  uninitialized,TResult Function( BigInt revision,  BridgeStateOperation operation,  BridgeReadText operationId,  PlatformInt64 startedAt)?  loading,TResult Function( BigInt revision,  PlatformInt64 updatedAt,  PlatformInt64? lastCheckedAt)?  ready,TResult Function( BigInt revision,  BridgeStateOperation operation,  BridgeReadText operationId,  PlatformInt64 startedAt,  PlatformInt64? lastCheckedAt)?  refreshing,TResult Function( BigInt revision,  PlatformInt64 staleAt,  PlatformInt64? lastCheckedAt)?  stale,TResult Function( BigInt revision,  PlatformInt64 failedAt,  PlatformInt64? lastCheckedAt,  BridgeStateOperation operation,  BridgeSourceStateErrorRead error)?  degraded,TResult Function( BigInt revision,  PlatformInt64 failedAt,  BridgeStateOperation operation,  BridgeSourceStateErrorRead error)?  failed,TResult Function( BigInt revision,  PlatformInt64 stoppedAt)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeProductSourceStatusReadHeader_Uninitialized() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case BridgeProductSourceStatusReadHeader_Loading() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case BridgeProductSourceStatusReadHeader_Ready() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Refreshing() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Stale() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Degraded() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case BridgeProductSourceStatusReadHeader_Failed() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case BridgeProductSourceStatusReadHeader_Stopped() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt revision,  PlatformInt64 updatedAt)  uninitialized,required TResult Function( BigInt revision,  BridgeStateOperation operation,  BridgeReadText operationId,  PlatformInt64 startedAt)  loading,required TResult Function( BigInt revision,  PlatformInt64 updatedAt,  PlatformInt64? lastCheckedAt)  ready,required TResult Function( BigInt revision,  BridgeStateOperation operation,  BridgeReadText operationId,  PlatformInt64 startedAt,  PlatformInt64? lastCheckedAt)  refreshing,required TResult Function( BigInt revision,  PlatformInt64 staleAt,  PlatformInt64? lastCheckedAt)  stale,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  PlatformInt64? lastCheckedAt,  BridgeStateOperation operation,  BridgeSourceStateErrorRead error)  degraded,required TResult Function( BigInt revision,  PlatformInt64 failedAt,  BridgeStateOperation operation,  BridgeSourceStateErrorRead error)  failed,required TResult Function( BigInt revision,  PlatformInt64 stoppedAt)  stopped,}) {final _that = this;
switch (_that) {
case BridgeProductSourceStatusReadHeader_Uninitialized():
return uninitialized(_that.revision,_that.updatedAt);case BridgeProductSourceStatusReadHeader_Loading():
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case BridgeProductSourceStatusReadHeader_Ready():
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Refreshing():
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Stale():
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Degraded():
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case BridgeProductSourceStatusReadHeader_Failed():
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case BridgeProductSourceStatusReadHeader_Stopped():
return stopped(_that.revision,_that.stoppedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt revision,  PlatformInt64 updatedAt)?  uninitialized,TResult? Function( BigInt revision,  BridgeStateOperation operation,  BridgeReadText operationId,  PlatformInt64 startedAt)?  loading,TResult? Function( BigInt revision,  PlatformInt64 updatedAt,  PlatformInt64? lastCheckedAt)?  ready,TResult? Function( BigInt revision,  BridgeStateOperation operation,  BridgeReadText operationId,  PlatformInt64 startedAt,  PlatformInt64? lastCheckedAt)?  refreshing,TResult? Function( BigInt revision,  PlatformInt64 staleAt,  PlatformInt64? lastCheckedAt)?  stale,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  PlatformInt64? lastCheckedAt,  BridgeStateOperation operation,  BridgeSourceStateErrorRead error)?  degraded,TResult? Function( BigInt revision,  PlatformInt64 failedAt,  BridgeStateOperation operation,  BridgeSourceStateErrorRead error)?  failed,TResult? Function( BigInt revision,  PlatformInt64 stoppedAt)?  stopped,}) {final _that = this;
switch (_that) {
case BridgeProductSourceStatusReadHeader_Uninitialized() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case BridgeProductSourceStatusReadHeader_Loading() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case BridgeProductSourceStatusReadHeader_Ready() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Refreshing() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Stale() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case BridgeProductSourceStatusReadHeader_Degraded() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case BridgeProductSourceStatusReadHeader_Failed() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case BridgeProductSourceStatusReadHeader_Stopped() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
  return null;

}
}

}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Uninitialized extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Uninitialized({required this.revision, required this.updatedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_UninitializedCopyWith<BridgeProductSourceStatusReadHeader_Uninitialized> get copyWith => _$BridgeProductSourceStatusReadHeader_UninitializedCopyWithImpl<BridgeProductSourceStatusReadHeader_Uninitialized>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Uninitialized&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.uninitialized(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_UninitializedCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_UninitializedCopyWith(BridgeProductSourceStatusReadHeader_Uninitialized value, $Res Function(BridgeProductSourceStatusReadHeader_Uninitialized) _then) = _$BridgeProductSourceStatusReadHeader_UninitializedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt
});




}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_UninitializedCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_UninitializedCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_UninitializedCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Uninitialized _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Uninitialized) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(BridgeProductSourceStatusReadHeader_Uninitialized(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Loading extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Loading({required this.revision, required this.operation, required this.operationId, required this.startedAt}): super._();


@override final  BigInt revision;
 final  BridgeStateOperation operation;
 final  BridgeReadText operationId;
 final  PlatformInt64 startedAt;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_LoadingCopyWith<BridgeProductSourceStatusReadHeader_Loading> get copyWith => _$BridgeProductSourceStatusReadHeader_LoadingCopyWithImpl<BridgeProductSourceStatusReadHeader_Loading>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Loading&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.loading(revision: $revision, operation: $operation, operationId: $operationId, startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_LoadingCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_LoadingCopyWith(BridgeProductSourceStatusReadHeader_Loading value, $Res Function(BridgeProductSourceStatusReadHeader_Loading) _then) = _$BridgeProductSourceStatusReadHeader_LoadingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, BridgeStateOperation operation, BridgeReadText operationId, PlatformInt64 startedAt
});


$BridgeReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_LoadingCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_LoadingCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_LoadingCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Loading _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Loading) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,}) {
  return _then(BridgeProductSourceStatusReadHeader_Loading(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as BridgeStateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Ready extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Ready({required this.revision, required this.updatedAt, this.lastCheckedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 updatedAt;
 final  PlatformInt64? lastCheckedAt;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_ReadyCopyWith<BridgeProductSourceStatusReadHeader_Ready> get copyWith => _$BridgeProductSourceStatusReadHeader_ReadyCopyWithImpl<BridgeProductSourceStatusReadHeader_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Ready&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,lastCheckedAt);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.ready(revision: $revision, updatedAt: $updatedAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_ReadyCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_ReadyCopyWith(BridgeProductSourceStatusReadHeader_Ready value, $Res Function(BridgeProductSourceStatusReadHeader_Ready) _then) = _$BridgeProductSourceStatusReadHeader_ReadyCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 updatedAt, PlatformInt64? lastCheckedAt
});




}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_ReadyCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_ReadyCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_ReadyCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Ready _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Ready) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(BridgeProductSourceStatusReadHeader_Ready(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Refreshing extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Refreshing({required this.revision, required this.operation, required this.operationId, required this.startedAt, this.lastCheckedAt}): super._();


@override final  BigInt revision;
 final  BridgeStateOperation operation;
 final  BridgeReadText operationId;
 final  PlatformInt64 startedAt;
 final  PlatformInt64? lastCheckedAt;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_RefreshingCopyWith<BridgeProductSourceStatusReadHeader_Refreshing> get copyWith => _$BridgeProductSourceStatusReadHeader_RefreshingCopyWithImpl<BridgeProductSourceStatusReadHeader_Refreshing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Refreshing&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt,lastCheckedAt);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.refreshing(revision: $revision, operation: $operation, operationId: $operationId, startedAt: $startedAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_RefreshingCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_RefreshingCopyWith(BridgeProductSourceStatusReadHeader_Refreshing value, $Res Function(BridgeProductSourceStatusReadHeader_Refreshing) _then) = _$BridgeProductSourceStatusReadHeader_RefreshingCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, BridgeStateOperation operation, BridgeReadText operationId, PlatformInt64 startedAt, PlatformInt64? lastCheckedAt
});


$BridgeReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_RefreshingCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_RefreshingCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_RefreshingCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Refreshing _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Refreshing) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(BridgeProductSourceStatusReadHeader_Refreshing(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as BridgeStateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Stale extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Stale({required this.revision, required this.staleAt, this.lastCheckedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 staleAt;
 final  PlatformInt64? lastCheckedAt;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_StaleCopyWith<BridgeProductSourceStatusReadHeader_Stale> get copyWith => _$BridgeProductSourceStatusReadHeader_StaleCopyWithImpl<BridgeProductSourceStatusReadHeader_Stale>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Stale&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.staleAt, staleAt) || other.staleAt == staleAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,staleAt,lastCheckedAt);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.stale(revision: $revision, staleAt: $staleAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_StaleCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_StaleCopyWith(BridgeProductSourceStatusReadHeader_Stale value, $Res Function(BridgeProductSourceStatusReadHeader_Stale) _then) = _$BridgeProductSourceStatusReadHeader_StaleCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 staleAt, PlatformInt64? lastCheckedAt
});




}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_StaleCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_StaleCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_StaleCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Stale _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Stale) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? staleAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(BridgeProductSourceStatusReadHeader_Stale(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,staleAt: null == staleAt ? _self.staleAt : staleAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,
  ));
}


}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Degraded extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Degraded({required this.revision, required this.failedAt, this.lastCheckedAt, required this.operation, required this.error}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  PlatformInt64? lastCheckedAt;
 final  BridgeStateOperation operation;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_DegradedCopyWith<BridgeProductSourceStatusReadHeader_Degraded> get copyWith => _$BridgeProductSourceStatusReadHeader_DegradedCopyWithImpl<BridgeProductSourceStatusReadHeader_Degraded>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Degraded&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,lastCheckedAt,operation,error);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.degraded(revision: $revision, failedAt: $failedAt, lastCheckedAt: $lastCheckedAt, operation: $operation, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_DegradedCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_DegradedCopyWith(BridgeProductSourceStatusReadHeader_Degraded value, $Res Function(BridgeProductSourceStatusReadHeader_Degraded) _then) = _$BridgeProductSourceStatusReadHeader_DegradedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, PlatformInt64? lastCheckedAt, BridgeStateOperation operation, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_DegradedCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_DegradedCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_DegradedCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Degraded _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Degraded) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? lastCheckedAt = freezed,Object? operation = null,Object? error = null,}) {
  return _then(BridgeProductSourceStatusReadHeader_Degraded(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as BridgeStateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Failed extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Failed({required this.revision, required this.failedAt, required this.operation, required this.error}): super._();


@override final  BigInt revision;
 final  PlatformInt64 failedAt;
 final  BridgeStateOperation operation;
 final  BridgeSourceStateErrorRead error;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_FailedCopyWith<BridgeProductSourceStatusReadHeader_Failed> get copyWith => _$BridgeProductSourceStatusReadHeader_FailedCopyWithImpl<BridgeProductSourceStatusReadHeader_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Failed&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,operation,error);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.failed(revision: $revision, failedAt: $failedAt, operation: $operation, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_FailedCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_FailedCopyWith(BridgeProductSourceStatusReadHeader_Failed value, $Res Function(BridgeProductSourceStatusReadHeader_Failed) _then) = _$BridgeProductSourceStatusReadHeader_FailedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 failedAt, BridgeStateOperation operation, BridgeSourceStateErrorRead error
});




}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_FailedCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_FailedCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_FailedCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Failed _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Failed) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? operation = null,Object? error = null,}) {
  return _then(BridgeProductSourceStatusReadHeader_Failed(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as BridgeStateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,
  ));
}


}

/// @nodoc


class BridgeProductSourceStatusReadHeader_Stopped extends BridgeProductSourceStatusReadHeader {
  const BridgeProductSourceStatusReadHeader_Stopped({required this.revision, required this.stoppedAt}): super._();


@override final  BigInt revision;
 final  PlatformInt64 stoppedAt;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeProductSourceStatusReadHeader_StoppedCopyWith<BridgeProductSourceStatusReadHeader_Stopped> get copyWith => _$BridgeProductSourceStatusReadHeader_StoppedCopyWithImpl<BridgeProductSourceStatusReadHeader_Stopped>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeProductSourceStatusReadHeader_Stopped&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.stoppedAt, stoppedAt) || other.stoppedAt == stoppedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,stoppedAt);
}

@override
String toString() {
    return 'BridgeProductSourceStatusReadHeader.stopped(revision: $revision, stoppedAt: $stoppedAt)';
}


}

/// @nodoc
abstract mixin class $BridgeProductSourceStatusReadHeader_StoppedCopyWith<$Res> implements $BridgeProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $BridgeProductSourceStatusReadHeader_StoppedCopyWith(BridgeProductSourceStatusReadHeader_Stopped value, $Res Function(BridgeProductSourceStatusReadHeader_Stopped) _then) = _$BridgeProductSourceStatusReadHeader_StoppedCopyWithImpl;
@override @useResult
$Res call({
 BigInt revision, PlatformInt64 stoppedAt
});




}
/// @nodoc
class _$BridgeProductSourceStatusReadHeader_StoppedCopyWithImpl<$Res>
    implements $BridgeProductSourceStatusReadHeader_StoppedCopyWith<$Res> {
  _$BridgeProductSourceStatusReadHeader_StoppedCopyWithImpl(this._self, this._then);

  final BridgeProductSourceStatusReadHeader_Stopped _self;
  final $Res Function(BridgeProductSourceStatusReadHeader_Stopped) _then;

/// Create a copy of BridgeProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? stoppedAt = null,}) {
  return _then(BridgeProductSourceStatusReadHeader_Stopped(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,stoppedAt: null == stoppedAt ? _self.stoppedAt : stoppedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

// dart format on
