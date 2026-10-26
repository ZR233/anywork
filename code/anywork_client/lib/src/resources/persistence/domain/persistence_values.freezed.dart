// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'persistence_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PersistenceStatus {

 int get pendingCommits;
/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceStatusCopyWith<PersistenceStatus> get copyWith => _$PersistenceStatusCopyWithImpl<PersistenceStatus>(this as PersistenceStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceStatus&&(identical(other.pendingCommits, _this.pendingCommits) || other.pendingCommits == _this.pendingCommits));
}


@override
int get hashCode {
  final _this = this as PersistenceStatus;
  return Object.hash(runtimeType,_this.pendingCommits);
}



}

/// @nodoc
abstract mixin class $PersistenceStatusCopyWith<$Res>  {
  factory $PersistenceStatusCopyWith(PersistenceStatus value, $Res Function(PersistenceStatus) _then) = _$PersistenceStatusCopyWithImpl;
@useResult
$Res call({
 int pendingCommits
});




}
/// @nodoc
class _$PersistenceStatusCopyWithImpl<$Res>
    implements $PersistenceStatusCopyWith<$Res> {
  _$PersistenceStatusCopyWithImpl(this._self, this._then);

  final PersistenceStatus _self;
  final $Res Function(PersistenceStatus) _then;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pendingCommits = null,}) {
  return _then(_self.copyWith(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PersistenceStatus].
extension PersistenceStatusPatterns on PersistenceStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ReadyPersistenceStatus value)?  ready,TResult Function( FlushingPersistenceStatus value)?  flushing,TResult Function( DegradedPersistenceStatus value)?  degraded,TResult Function( RecoveringPersistenceStatus value)?  recovering,TResult Function( BlockedPersistenceStatus value)?  blocked,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ReadyPersistenceStatus() when ready != null:
return ready(_that);case FlushingPersistenceStatus() when flushing != null:
return flushing(_that);case DegradedPersistenceStatus() when degraded != null:
return degraded(_that);case RecoveringPersistenceStatus() when recovering != null:
return recovering(_that);case BlockedPersistenceStatus() when blocked != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ReadyPersistenceStatus value)  ready,required TResult Function( FlushingPersistenceStatus value)  flushing,required TResult Function( DegradedPersistenceStatus value)  degraded,required TResult Function( RecoveringPersistenceStatus value)  recovering,required TResult Function( BlockedPersistenceStatus value)  blocked,}){
final _that = this;
switch (_that) {
case ReadyPersistenceStatus():
return ready(_that);case FlushingPersistenceStatus():
return flushing(_that);case DegradedPersistenceStatus():
return degraded(_that);case RecoveringPersistenceStatus():
return recovering(_that);case BlockedPersistenceStatus():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ReadyPersistenceStatus value)?  ready,TResult? Function( FlushingPersistenceStatus value)?  flushing,TResult? Function( DegradedPersistenceStatus value)?  degraded,TResult? Function( RecoveringPersistenceStatus value)?  recovering,TResult? Function( BlockedPersistenceStatus value)?  blocked,}){
final _that = this;
switch (_that) {
case ReadyPersistenceStatus() when ready != null:
return ready(_that);case FlushingPersistenceStatus() when flushing != null:
return flushing(_that);case DegradedPersistenceStatus() when degraded != null:
return degraded(_that);case RecoveringPersistenceStatus() when recovering != null:
return recovering(_that);case BlockedPersistenceStatus() when blocked != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int pendingCommits)?  ready,TResult Function( int pendingCommits,  int? oldestPendingRevision)?  flushing,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateError error)?  degraded,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  recovering,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateError error)?  blocked,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ReadyPersistenceStatus() when ready != null:
return ready(_that.pendingCommits);case FlushingPersistenceStatus() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceStatus() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case RecoveringPersistenceStatus() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceStatus() when blocked != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int pendingCommits)  ready,required TResult Function( int pendingCommits,  int? oldestPendingRevision)  flushing,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateError error)  degraded,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)  recovering,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateError error)  blocked,}) {final _that = this;
switch (_that) {
case ReadyPersistenceStatus():
return ready(_that.pendingCommits);case FlushingPersistenceStatus():
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceStatus():
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case RecoveringPersistenceStatus():
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceStatus():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int pendingCommits)?  ready,TResult? Function( int pendingCommits,  int? oldestPendingRevision)?  flushing,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateError error)?  degraded,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  recovering,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateError error)?  blocked,}) {final _that = this;
switch (_that) {
case ReadyPersistenceStatus() when ready != null:
return ready(_that.pendingCommits);case FlushingPersistenceStatus() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceStatus() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case RecoveringPersistenceStatus() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceStatus() when blocked != null:
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class ReadyPersistenceStatus implements PersistenceStatus {
  const ReadyPersistenceStatus({required this.pendingCommits});


@override final  int pendingCommits;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyPersistenceStatusCopyWith<ReadyPersistenceStatus> get copyWith => _$ReadyPersistenceStatusCopyWithImpl<ReadyPersistenceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyPersistenceStatus&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits);
}



}

/// @nodoc
abstract mixin class $ReadyPersistenceStatusCopyWith<$Res> implements $PersistenceStatusCopyWith<$Res> {
  factory $ReadyPersistenceStatusCopyWith(ReadyPersistenceStatus value, $Res Function(ReadyPersistenceStatus) _then) = _$ReadyPersistenceStatusCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits
});




}
/// @nodoc
class _$ReadyPersistenceStatusCopyWithImpl<$Res>
    implements $ReadyPersistenceStatusCopyWith<$Res> {
  _$ReadyPersistenceStatusCopyWithImpl(this._self, this._then);

  final ReadyPersistenceStatus _self;
  final $Res Function(ReadyPersistenceStatus) _then;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,}) {
  return _then(ReadyPersistenceStatus(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FlushingPersistenceStatus implements PersistenceStatus {
  const FlushingPersistenceStatus({required this.pendingCommits, required this.oldestPendingRevision});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlushingPersistenceStatusCopyWith<FlushingPersistenceStatus> get copyWith => _$FlushingPersistenceStatusCopyWithImpl<FlushingPersistenceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FlushingPersistenceStatus&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision);
}



}

/// @nodoc
abstract mixin class $FlushingPersistenceStatusCopyWith<$Res> implements $PersistenceStatusCopyWith<$Res> {
  factory $FlushingPersistenceStatusCopyWith(FlushingPersistenceStatus value, $Res Function(FlushingPersistenceStatus) _then) = _$FlushingPersistenceStatusCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision
});




}
/// @nodoc
class _$FlushingPersistenceStatusCopyWithImpl<$Res>
    implements $FlushingPersistenceStatusCopyWith<$Res> {
  _$FlushingPersistenceStatusCopyWithImpl(this._self, this._then);

  final FlushingPersistenceStatus _self;
  final $Res Function(FlushingPersistenceStatus) _then;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,}) {
  return _then(FlushingPersistenceStatus(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class DegradedPersistenceStatus implements PersistenceStatus {
  const DegradedPersistenceStatus({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt, required this.error});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;
 final  SourceStateError error;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DegradedPersistenceStatusCopyWith<DegradedPersistenceStatus> get copyWith => _$DegradedPersistenceStatusCopyWithImpl<DegradedPersistenceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DegradedPersistenceStatus&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt,error);
}



}

/// @nodoc
abstract mixin class $DegradedPersistenceStatusCopyWith<$Res> implements $PersistenceStatusCopyWith<$Res> {
  factory $DegradedPersistenceStatusCopyWith(DegradedPersistenceStatus value, $Res Function(DegradedPersistenceStatus) _then) = _$DegradedPersistenceStatusCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$DegradedPersistenceStatusCopyWithImpl<$Res>
    implements $DegradedPersistenceStatusCopyWith<$Res> {
  _$DegradedPersistenceStatusCopyWithImpl(this._self, this._then);

  final DegradedPersistenceStatus _self;
  final $Res Function(DegradedPersistenceStatus) _then;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,Object? error = null,}) {
  return _then(DegradedPersistenceStatus(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class RecoveringPersistenceStatus implements PersistenceStatus {
  const RecoveringPersistenceStatus({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveringPersistenceStatusCopyWith<RecoveringPersistenceStatus> get copyWith => _$RecoveringPersistenceStatusCopyWithImpl<RecoveringPersistenceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveringPersistenceStatus&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}



}

/// @nodoc
abstract mixin class $RecoveringPersistenceStatusCopyWith<$Res> implements $PersistenceStatusCopyWith<$Res> {
  factory $RecoveringPersistenceStatusCopyWith(RecoveringPersistenceStatus value, $Res Function(RecoveringPersistenceStatus) _then) = _$RecoveringPersistenceStatusCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt
});




}
/// @nodoc
class _$RecoveringPersistenceStatusCopyWithImpl<$Res>
    implements $RecoveringPersistenceStatusCopyWith<$Res> {
  _$RecoveringPersistenceStatusCopyWithImpl(this._self, this._then);

  final RecoveringPersistenceStatus _self;
  final $Res Function(RecoveringPersistenceStatus) _then;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(RecoveringPersistenceStatus(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BlockedPersistenceStatus implements PersistenceStatus {
  const BlockedPersistenceStatus({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt, required this.error});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;
 final  SourceStateError error;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockedPersistenceStatusCopyWith<BlockedPersistenceStatus> get copyWith => _$BlockedPersistenceStatusCopyWithImpl<BlockedPersistenceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockedPersistenceStatus&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt,error);
}



}

/// @nodoc
abstract mixin class $BlockedPersistenceStatusCopyWith<$Res> implements $PersistenceStatusCopyWith<$Res> {
  factory $BlockedPersistenceStatusCopyWith(BlockedPersistenceStatus value, $Res Function(BlockedPersistenceStatus) _then) = _$BlockedPersistenceStatusCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$BlockedPersistenceStatusCopyWithImpl<$Res>
    implements $BlockedPersistenceStatusCopyWith<$Res> {
  _$BlockedPersistenceStatusCopyWithImpl(this._self, this._then);

  final BlockedPersistenceStatus _self;
  final $Res Function(BlockedPersistenceStatus) _then;

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,Object? error = null,}) {
  return _then(BlockedPersistenceStatus(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of PersistenceStatus
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$PersistenceValue {

 int get revision; PersistenceStatus get state;
/// Create a copy of PersistenceValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceValueCopyWith<PersistenceValue> get copyWith => _$PersistenceValueCopyWithImpl<PersistenceValue>(this as PersistenceValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceValue&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as PersistenceValue;
  return Object.hash(runtimeType,_this.revision,_this.state);
}



}

/// @nodoc
abstract mixin class $PersistenceValueCopyWith<$Res>  {
  factory $PersistenceValueCopyWith(PersistenceValue value, $Res Function(PersistenceValue) _then) = _$PersistenceValueCopyWithImpl;
@useResult
$Res call({
 int revision, PersistenceStatus state
});


$PersistenceStatusCopyWith<$Res> get state;

}
/// @nodoc
class _$PersistenceValueCopyWithImpl<$Res>
    implements $PersistenceValueCopyWith<$Res> {
  _$PersistenceValueCopyWithImpl(this._self, this._then);

  final PersistenceValue _self;
  final $Res Function(PersistenceValue) _then;

/// Create a copy of PersistenceValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? state = null,}) {
  return _then(PersistenceValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PersistenceStatus,
  ));
}
/// Create a copy of PersistenceValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceStatusCopyWith<$Res> get state {

  return $PersistenceStatusCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceValue].
extension PersistenceValuePatterns on PersistenceValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceValue value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceValue value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  PersistenceStatus state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceValue() when $default != null:
return $default(_that.revision,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  PersistenceStatus state)  $default,) {final _that = this;
switch (_that) {
case _PersistenceValue():
return $default(_that.revision,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  PersistenceStatus state)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceValue() when $default != null:
return $default(_that.revision,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceValue implements PersistenceValue {
  const _PersistenceValue({required this.revision, required this.state});


@override final  int revision;
@override final  PersistenceStatus state;

/// Create a copy of PersistenceValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceValueCopyWith<_PersistenceValue> get copyWith => __$PersistenceValueCopyWithImpl<_PersistenceValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,state);
}



}

/// @nodoc
abstract mixin class _$PersistenceValueCopyWith<$Res> implements $PersistenceValueCopyWith<$Res> {
  factory _$PersistenceValueCopyWith(_PersistenceValue value, $Res Function(_PersistenceValue) _then) = __$PersistenceValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, PersistenceStatus state
});


@override $PersistenceStatusCopyWith<$Res> get state;

}
/// @nodoc
class __$PersistenceValueCopyWithImpl<$Res>
    implements _$PersistenceValueCopyWith<$Res> {
  __$PersistenceValueCopyWithImpl(this._self, this._then);

  final _PersistenceValue _self;
  final $Res Function(_PersistenceValue) _then;

/// Create a copy of PersistenceValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? state = null,}) {
  return _then(_PersistenceValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PersistenceStatus,
  ));
}

/// Create a copy of PersistenceValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceStatusCopyWith<$Res> get state {

  return $PersistenceStatusCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$ThreadPersistenceSnapshot {

 String get threadId; int get faultGeneration; HistoryFault? get fault; int? get stateDirtyRevision; int? get stateSavingRevision; int? get stateDurableRevision; int? get historyAdmittedSequence; int? get historyDurableSequence; int? get callsAdmittedSequence; int? get callsDurableSequence; int get pendingOperations; int get pendingBytes; int? get oldestPendingAgeMillis; int get inFlightBytes; String? get lastError; bool get pressurePaused;
/// Create a copy of ThreadPersistenceSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadPersistenceSnapshotCopyWith<ThreadPersistenceSnapshot> get copyWith => _$ThreadPersistenceSnapshotCopyWithImpl<ThreadPersistenceSnapshot>(this as ThreadPersistenceSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadPersistenceSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadPersistenceSnapshot&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.faultGeneration, _this.faultGeneration) || other.faultGeneration == _this.faultGeneration)&&(identical(other.fault, _this.fault) || other.fault == _this.fault)&&(identical(other.stateDirtyRevision, _this.stateDirtyRevision) || other.stateDirtyRevision == _this.stateDirtyRevision)&&(identical(other.stateSavingRevision, _this.stateSavingRevision) || other.stateSavingRevision == _this.stateSavingRevision)&&(identical(other.stateDurableRevision, _this.stateDurableRevision) || other.stateDurableRevision == _this.stateDurableRevision)&&(identical(other.historyAdmittedSequence, _this.historyAdmittedSequence) || other.historyAdmittedSequence == _this.historyAdmittedSequence)&&(identical(other.historyDurableSequence, _this.historyDurableSequence) || other.historyDurableSequence == _this.historyDurableSequence)&&(identical(other.callsAdmittedSequence, _this.callsAdmittedSequence) || other.callsAdmittedSequence == _this.callsAdmittedSequence)&&(identical(other.callsDurableSequence, _this.callsDurableSequence) || other.callsDurableSequence == _this.callsDurableSequence)&&(identical(other.pendingOperations, _this.pendingOperations) || other.pendingOperations == _this.pendingOperations)&&(identical(other.pendingBytes, _this.pendingBytes) || other.pendingBytes == _this.pendingBytes)&&(identical(other.oldestPendingAgeMillis, _this.oldestPendingAgeMillis) || other.oldestPendingAgeMillis == _this.oldestPendingAgeMillis)&&(identical(other.inFlightBytes, _this.inFlightBytes) || other.inFlightBytes == _this.inFlightBytes)&&(identical(other.lastError, _this.lastError) || other.lastError == _this.lastError)&&(identical(other.pressurePaused, _this.pressurePaused) || other.pressurePaused == _this.pressurePaused));
}


@override
int get hashCode {
  final _this = this as ThreadPersistenceSnapshot;
  return Object.hash(runtimeType,_this.threadId,_this.faultGeneration,_this.fault,_this.stateDirtyRevision,_this.stateSavingRevision,_this.stateDurableRevision,_this.historyAdmittedSequence,_this.historyDurableSequence,_this.callsAdmittedSequence,_this.callsDurableSequence,_this.pendingOperations,_this.pendingBytes,_this.oldestPendingAgeMillis,_this.inFlightBytes,_this.lastError,_this.pressurePaused);
}



}

/// @nodoc
abstract mixin class $ThreadPersistenceSnapshotCopyWith<$Res>  {
  factory $ThreadPersistenceSnapshotCopyWith(ThreadPersistenceSnapshot value, $Res Function(ThreadPersistenceSnapshot) _then) = _$ThreadPersistenceSnapshotCopyWithImpl;
@useResult
$Res call({
 String threadId, int faultGeneration, HistoryFault? fault, int? stateDirtyRevision, int? stateSavingRevision, int? stateDurableRevision, int? historyAdmittedSequence, int? historyDurableSequence, int? callsAdmittedSequence, int? callsDurableSequence, int pendingOperations, int pendingBytes, int? oldestPendingAgeMillis, int inFlightBytes, String? lastError, bool pressurePaused
});




}
/// @nodoc
class _$ThreadPersistenceSnapshotCopyWithImpl<$Res>
    implements $ThreadPersistenceSnapshotCopyWith<$Res> {
  _$ThreadPersistenceSnapshotCopyWithImpl(this._self, this._then);

  final ThreadPersistenceSnapshot _self;
  final $Res Function(ThreadPersistenceSnapshot) _then;

/// Create a copy of ThreadPersistenceSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? faultGeneration = null,Object? fault = freezed,Object? stateDirtyRevision = freezed,Object? stateSavingRevision = freezed,Object? stateDurableRevision = freezed,Object? historyAdmittedSequence = freezed,Object? historyDurableSequence = freezed,Object? callsAdmittedSequence = freezed,Object? callsDurableSequence = freezed,Object? pendingOperations = null,Object? pendingBytes = null,Object? oldestPendingAgeMillis = freezed,Object? inFlightBytes = null,Object? lastError = freezed,Object? pressurePaused = null,}) {
  return _then(ThreadPersistenceSnapshot(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
as int,fault: freezed == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as HistoryFault?,stateDirtyRevision: freezed == stateDirtyRevision ? _self.stateDirtyRevision : stateDirtyRevision // ignore: cast_nullable_to_non_nullable
as int?,stateSavingRevision: freezed == stateSavingRevision ? _self.stateSavingRevision : stateSavingRevision // ignore: cast_nullable_to_non_nullable
as int?,stateDurableRevision: freezed == stateDurableRevision ? _self.stateDurableRevision : stateDurableRevision // ignore: cast_nullable_to_non_nullable
as int?,historyAdmittedSequence: freezed == historyAdmittedSequence ? _self.historyAdmittedSequence : historyAdmittedSequence // ignore: cast_nullable_to_non_nullable
as int?,historyDurableSequence: freezed == historyDurableSequence ? _self.historyDurableSequence : historyDurableSequence // ignore: cast_nullable_to_non_nullable
as int?,callsAdmittedSequence: freezed == callsAdmittedSequence ? _self.callsAdmittedSequence : callsAdmittedSequence // ignore: cast_nullable_to_non_nullable
as int?,callsDurableSequence: freezed == callsDurableSequence ? _self.callsDurableSequence : callsDurableSequence // ignore: cast_nullable_to_non_nullable
as int?,pendingOperations: null == pendingOperations ? _self.pendingOperations : pendingOperations // ignore: cast_nullable_to_non_nullable
as int,pendingBytes: null == pendingBytes ? _self.pendingBytes : pendingBytes // ignore: cast_nullable_to_non_nullable
as int,oldestPendingAgeMillis: freezed == oldestPendingAgeMillis ? _self.oldestPendingAgeMillis : oldestPendingAgeMillis // ignore: cast_nullable_to_non_nullable
as int?,inFlightBytes: null == inFlightBytes ? _self.inFlightBytes : inFlightBytes // ignore: cast_nullable_to_non_nullable
as int,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadPersistenceSnapshot].
extension ThreadPersistenceSnapshotPatterns on ThreadPersistenceSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadPersistenceSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadPersistenceSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadPersistenceSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _ThreadPersistenceSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadPersistenceSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadPersistenceSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  int faultGeneration,  HistoryFault? fault,  int? stateDirtyRevision,  int? stateSavingRevision,  int? stateDurableRevision,  int? historyAdmittedSequence,  int? historyDurableSequence,  int? callsAdmittedSequence,  int? callsDurableSequence,  int pendingOperations,  int pendingBytes,  int? oldestPendingAgeMillis,  int inFlightBytes,  String? lastError,  bool pressurePaused)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadPersistenceSnapshot() when $default != null:
return $default(_that.threadId,_that.faultGeneration,_that.fault,_that.stateDirtyRevision,_that.stateSavingRevision,_that.stateDurableRevision,_that.historyAdmittedSequence,_that.historyDurableSequence,_that.callsAdmittedSequence,_that.callsDurableSequence,_that.pendingOperations,_that.pendingBytes,_that.oldestPendingAgeMillis,_that.inFlightBytes,_that.lastError,_that.pressurePaused);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  int faultGeneration,  HistoryFault? fault,  int? stateDirtyRevision,  int? stateSavingRevision,  int? stateDurableRevision,  int? historyAdmittedSequence,  int? historyDurableSequence,  int? callsAdmittedSequence,  int? callsDurableSequence,  int pendingOperations,  int pendingBytes,  int? oldestPendingAgeMillis,  int inFlightBytes,  String? lastError,  bool pressurePaused)  $default,) {final _that = this;
switch (_that) {
case _ThreadPersistenceSnapshot():
return $default(_that.threadId,_that.faultGeneration,_that.fault,_that.stateDirtyRevision,_that.stateSavingRevision,_that.stateDurableRevision,_that.historyAdmittedSequence,_that.historyDurableSequence,_that.callsAdmittedSequence,_that.callsDurableSequence,_that.pendingOperations,_that.pendingBytes,_that.oldestPendingAgeMillis,_that.inFlightBytes,_that.lastError,_that.pressurePaused);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  int faultGeneration,  HistoryFault? fault,  int? stateDirtyRevision,  int? stateSavingRevision,  int? stateDurableRevision,  int? historyAdmittedSequence,  int? historyDurableSequence,  int? callsAdmittedSequence,  int? callsDurableSequence,  int pendingOperations,  int pendingBytes,  int? oldestPendingAgeMillis,  int inFlightBytes,  String? lastError,  bool pressurePaused)?  $default,) {final _that = this;
switch (_that) {
case _ThreadPersistenceSnapshot() when $default != null:
return $default(_that.threadId,_that.faultGeneration,_that.fault,_that.stateDirtyRevision,_that.stateSavingRevision,_that.stateDurableRevision,_that.historyAdmittedSequence,_that.historyDurableSequence,_that.callsAdmittedSequence,_that.callsDurableSequence,_that.pendingOperations,_that.pendingBytes,_that.oldestPendingAgeMillis,_that.inFlightBytes,_that.lastError,_that.pressurePaused);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadPersistenceSnapshot implements ThreadPersistenceSnapshot {
  const _ThreadPersistenceSnapshot({required this.threadId, required this.faultGeneration, required this.fault, required this.stateDirtyRevision, required this.stateSavingRevision, required this.stateDurableRevision, required this.historyAdmittedSequence, required this.historyDurableSequence, required this.callsAdmittedSequence, required this.callsDurableSequence, required this.pendingOperations, required this.pendingBytes, required this.oldestPendingAgeMillis, required this.inFlightBytes, required this.lastError, required this.pressurePaused});


@override final  String threadId;
@override final  int faultGeneration;
@override final  HistoryFault? fault;
@override final  int? stateDirtyRevision;
@override final  int? stateSavingRevision;
@override final  int? stateDurableRevision;
@override final  int? historyAdmittedSequence;
@override final  int? historyDurableSequence;
@override final  int? callsAdmittedSequence;
@override final  int? callsDurableSequence;
@override final  int pendingOperations;
@override final  int pendingBytes;
@override final  int? oldestPendingAgeMillis;
@override final  int inFlightBytes;
@override final  String? lastError;
@override final  bool pressurePaused;

/// Create a copy of ThreadPersistenceSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadPersistenceSnapshotCopyWith<_ThreadPersistenceSnapshot> get copyWith => __$ThreadPersistenceSnapshotCopyWithImpl<_ThreadPersistenceSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadPersistenceSnapshot&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.faultGeneration, faultGeneration) || other.faultGeneration == faultGeneration)&&(identical(other.fault, fault) || other.fault == fault)&&(identical(other.stateDirtyRevision, stateDirtyRevision) || other.stateDirtyRevision == stateDirtyRevision)&&(identical(other.stateSavingRevision, stateSavingRevision) || other.stateSavingRevision == stateSavingRevision)&&(identical(other.stateDurableRevision, stateDurableRevision) || other.stateDurableRevision == stateDurableRevision)&&(identical(other.historyAdmittedSequence, historyAdmittedSequence) || other.historyAdmittedSequence == historyAdmittedSequence)&&(identical(other.historyDurableSequence, historyDurableSequence) || other.historyDurableSequence == historyDurableSequence)&&(identical(other.callsAdmittedSequence, callsAdmittedSequence) || other.callsAdmittedSequence == callsAdmittedSequence)&&(identical(other.callsDurableSequence, callsDurableSequence) || other.callsDurableSequence == callsDurableSequence)&&(identical(other.pendingOperations, pendingOperations) || other.pendingOperations == pendingOperations)&&(identical(other.pendingBytes, pendingBytes) || other.pendingBytes == pendingBytes)&&(identical(other.oldestPendingAgeMillis, oldestPendingAgeMillis) || other.oldestPendingAgeMillis == oldestPendingAgeMillis)&&(identical(other.inFlightBytes, inFlightBytes) || other.inFlightBytes == inFlightBytes)&&(identical(other.lastError, lastError) || other.lastError == lastError)&&(identical(other.pressurePaused, pressurePaused) || other.pressurePaused == pressurePaused));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,faultGeneration,fault,stateDirtyRevision,stateSavingRevision,stateDurableRevision,historyAdmittedSequence,historyDurableSequence,callsAdmittedSequence,callsDurableSequence,pendingOperations,pendingBytes,oldestPendingAgeMillis,inFlightBytes,lastError,pressurePaused);
}



}

/// @nodoc
abstract mixin class _$ThreadPersistenceSnapshotCopyWith<$Res> implements $ThreadPersistenceSnapshotCopyWith<$Res> {
  factory _$ThreadPersistenceSnapshotCopyWith(_ThreadPersistenceSnapshot value, $Res Function(_ThreadPersistenceSnapshot) _then) = __$ThreadPersistenceSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String threadId, int faultGeneration, HistoryFault? fault, int? stateDirtyRevision, int? stateSavingRevision, int? stateDurableRevision, int? historyAdmittedSequence, int? historyDurableSequence, int? callsAdmittedSequence, int? callsDurableSequence, int pendingOperations, int pendingBytes, int? oldestPendingAgeMillis, int inFlightBytes, String? lastError, bool pressurePaused
});




}
/// @nodoc
class __$ThreadPersistenceSnapshotCopyWithImpl<$Res>
    implements _$ThreadPersistenceSnapshotCopyWith<$Res> {
  __$ThreadPersistenceSnapshotCopyWithImpl(this._self, this._then);

  final _ThreadPersistenceSnapshot _self;
  final $Res Function(_ThreadPersistenceSnapshot) _then;

/// Create a copy of ThreadPersistenceSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? faultGeneration = null,Object? fault = freezed,Object? stateDirtyRevision = freezed,Object? stateSavingRevision = freezed,Object? stateDurableRevision = freezed,Object? historyAdmittedSequence = freezed,Object? historyDurableSequence = freezed,Object? callsAdmittedSequence = freezed,Object? callsDurableSequence = freezed,Object? pendingOperations = null,Object? pendingBytes = null,Object? oldestPendingAgeMillis = freezed,Object? inFlightBytes = null,Object? lastError = freezed,Object? pressurePaused = null,}) {
  return _then(_ThreadPersistenceSnapshot(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
as int,fault: freezed == fault ? _self.fault : fault // ignore: cast_nullable_to_non_nullable
as HistoryFault?,stateDirtyRevision: freezed == stateDirtyRevision ? _self.stateDirtyRevision : stateDirtyRevision // ignore: cast_nullable_to_non_nullable
as int?,stateSavingRevision: freezed == stateSavingRevision ? _self.stateSavingRevision : stateSavingRevision // ignore: cast_nullable_to_non_nullable
as int?,stateDurableRevision: freezed == stateDurableRevision ? _self.stateDurableRevision : stateDurableRevision // ignore: cast_nullable_to_non_nullable
as int?,historyAdmittedSequence: freezed == historyAdmittedSequence ? _self.historyAdmittedSequence : historyAdmittedSequence // ignore: cast_nullable_to_non_nullable
as int?,historyDurableSequence: freezed == historyDurableSequence ? _self.historyDurableSequence : historyDurableSequence // ignore: cast_nullable_to_non_nullable
as int?,callsAdmittedSequence: freezed == callsAdmittedSequence ? _self.callsAdmittedSequence : callsAdmittedSequence // ignore: cast_nullable_to_non_nullable
as int?,callsDurableSequence: freezed == callsDurableSequence ? _self.callsDurableSequence : callsDurableSequence // ignore: cast_nullable_to_non_nullable
as int?,pendingOperations: null == pendingOperations ? _self.pendingOperations : pendingOperations // ignore: cast_nullable_to_non_nullable
as int,pendingBytes: null == pendingBytes ? _self.pendingBytes : pendingBytes // ignore: cast_nullable_to_non_nullable
as int,oldestPendingAgeMillis: freezed == oldestPendingAgeMillis ? _self.oldestPendingAgeMillis : oldestPendingAgeMillis // ignore: cast_nullable_to_non_nullable
as int?,inFlightBytes: null == inFlightBytes ? _self.inFlightBytes : inFlightBytes // ignore: cast_nullable_to_non_nullable
as int,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$PersistenceQueueSnapshot {


/// Create a copy of PersistenceQueueSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueSnapshotCopyWith<PersistenceQueueSnapshot> get copyWith => _$PersistenceQueueSnapshotCopyWithImpl<PersistenceQueueSnapshot>(this as PersistenceQueueSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueSnapshot&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.pendingOperations, _this.pendingOperations) || other.pendingOperations == _this.pendingOperations)&&(identical(other.pendingBytes, _this.pendingBytes) || other.pendingBytes == _this.pendingBytes)&&(identical(other.inFlightBytes, _this.inFlightBytes) || other.inFlightBytes == _this.inFlightBytes)&&(identical(other.oldestPendingAgeMillis, _this.oldestPendingAgeMillis) || other.oldestPendingAgeMillis == _this.oldestPendingAgeMillis)&&(identical(other.lastError, _this.lastError) || other.lastError == _this.lastError)&&(identical(other.pressurePaused, _this.pressurePaused) || other.pressurePaused == _this.pressurePaused)&&const DeepCollectionEquality().equals(other.threads, _this.threads));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueSnapshot;
  return Object.hash(runtimeType,_this.statisticsGap,_this.pendingOperations,_this.pendingBytes,_this.inFlightBytes,_this.oldestPendingAgeMillis,_this.lastError,_this.pressurePaused,const DeepCollectionEquality().hash(_this.threads));
}



}

/// @nodoc
abstract mixin class $PersistenceQueueSnapshotCopyWith<$Res>  {
  factory $PersistenceQueueSnapshotCopyWith(PersistenceQueueSnapshot value, $Res Function(PersistenceQueueSnapshot) _then) = _$PersistenceQueueSnapshotCopyWithImpl;
@useResult
$Res call({
 bool statisticsGap, int pendingOperations, int pendingBytes, int inFlightBytes, int? oldestPendingAgeMillis, String? lastError, bool pressurePaused, List<ThreadPersistenceSnapshot> threads
});




}
/// @nodoc
class _$PersistenceQueueSnapshotCopyWithImpl<$Res>
    implements $PersistenceQueueSnapshotCopyWith<$Res> {
  _$PersistenceQueueSnapshotCopyWithImpl(this._self, this._then);

  final PersistenceQueueSnapshot _self;
  final $Res Function(PersistenceQueueSnapshot) _then;

/// Create a copy of PersistenceQueueSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? statisticsGap = null,Object? pendingOperations = null,Object? pendingBytes = null,Object? inFlightBytes = null,Object? oldestPendingAgeMillis = freezed,Object? lastError = freezed,Object? pressurePaused = null,Object? threads = null,}) {
  return _then(PersistenceQueueSnapshot(
statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,pendingOperations: null == pendingOperations ? _self.pendingOperations : pendingOperations // ignore: cast_nullable_to_non_nullable
as int,pendingBytes: null == pendingBytes ? _self.pendingBytes : pendingBytes // ignore: cast_nullable_to_non_nullable
as int,inFlightBytes: null == inFlightBytes ? _self.inFlightBytes : inFlightBytes // ignore: cast_nullable_to_non_nullable
as int,oldestPendingAgeMillis: freezed == oldestPendingAgeMillis ? _self.oldestPendingAgeMillis : oldestPendingAgeMillis // ignore: cast_nullable_to_non_nullable
as int?,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as String?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as List<ThreadPersistenceSnapshot>,
  ));
}

}


/// Adds pattern-matching-related methods to [PersistenceQueueSnapshot].
extension PersistenceQueueSnapshotPatterns on PersistenceQueueSnapshot {
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
mixin _$PersistenceQueueValue {

 int get revision; int get updatedAt; PersistenceQueueSnapshot get queue;
/// Create a copy of PersistenceQueueValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueValueCopyWith<PersistenceQueueValue> get copyWith => _$PersistenceQueueValueCopyWithImpl<PersistenceQueueValue>(this as PersistenceQueueValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueValue&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.queue, _this.queue) || other.queue == _this.queue));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueValue;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.queue);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueValueCopyWith<$Res>  {
  factory $PersistenceQueueValueCopyWith(PersistenceQueueValue value, $Res Function(PersistenceQueueValue) _then) = _$PersistenceQueueValueCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, PersistenceQueueSnapshot queue
});


$PersistenceQueueSnapshotCopyWith<$Res> get queue;

}
/// @nodoc
class _$PersistenceQueueValueCopyWithImpl<$Res>
    implements $PersistenceQueueValueCopyWith<$Res> {
  _$PersistenceQueueValueCopyWithImpl(this._self, this._then);

  final PersistenceQueueValue _self;
  final $Res Function(PersistenceQueueValue) _then;

/// Create a copy of PersistenceQueueValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? queue = null,}) {
  return _then(PersistenceQueueValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as PersistenceQueueSnapshot,
  ));
}
/// Create a copy of PersistenceQueueValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueSnapshotCopyWith<$Res> get queue {

  return $PersistenceQueueSnapshotCopyWith<$Res>(_self.queue, (value) {
    return _then(_self.copyWith(queue: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueValue].
extension PersistenceQueueValuePatterns on PersistenceQueueValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueValue value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueValue value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  PersistenceQueueSnapshot queue)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceQueueValue() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.queue);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  PersistenceQueueSnapshot queue)  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueValue():
return $default(_that.revision,_that.updatedAt,_that.queue);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  PersistenceQueueSnapshot queue)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueValue() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.queue);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueValue implements PersistenceQueueValue {
  const _PersistenceQueueValue({required this.revision, required this.updatedAt, required this.queue});


@override final  int revision;
@override final  int updatedAt;
@override final  PersistenceQueueSnapshot queue;

/// Create a copy of PersistenceQueueValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueValueCopyWith<_PersistenceQueueValue> get copyWith => __$PersistenceQueueValueCopyWithImpl<_PersistenceQueueValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueValue&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.queue, queue) || other.queue == queue));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,queue);
}



}

/// @nodoc
abstract mixin class _$PersistenceQueueValueCopyWith<$Res> implements $PersistenceQueueValueCopyWith<$Res> {
  factory _$PersistenceQueueValueCopyWith(_PersistenceQueueValue value, $Res Function(_PersistenceQueueValue) _then) = __$PersistenceQueueValueCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, PersistenceQueueSnapshot queue
});


@override $PersistenceQueueSnapshotCopyWith<$Res> get queue;

}
/// @nodoc
class __$PersistenceQueueValueCopyWithImpl<$Res>
    implements _$PersistenceQueueValueCopyWith<$Res> {
  __$PersistenceQueueValueCopyWithImpl(this._self, this._then);

  final _PersistenceQueueValue _self;
  final $Res Function(_PersistenceQueueValue) _then;

/// Create a copy of PersistenceQueueValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? queue = null,}) {
  return _then(_PersistenceQueueValue(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as PersistenceQueueSnapshot,
  ));
}

/// Create a copy of PersistenceQueueValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueSnapshotCopyWith<$Res> get queue {

  return $PersistenceQueueSnapshotCopyWith<$Res>(_self.queue, (value) {
    return _then(_self.copyWith(queue: value));
  });
}
}

// dart format on
