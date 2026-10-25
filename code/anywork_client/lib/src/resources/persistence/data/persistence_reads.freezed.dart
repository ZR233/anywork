// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'persistence_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PersistenceStatusRead {

 int get pendingCommits;
/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceStatusReadCopyWith<PersistenceStatusRead> get copyWith => _$PersistenceStatusReadCopyWithImpl<PersistenceStatusRead>(this as PersistenceStatusRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceStatusRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceStatusRead&&(identical(other.pendingCommits, _this.pendingCommits) || other.pendingCommits == _this.pendingCommits));
}


@override
int get hashCode {
  final _this = this as PersistenceStatusRead;
  return Object.hash(runtimeType,_this.pendingCommits);
}



}

/// @nodoc
abstract mixin class $PersistenceStatusReadCopyWith<$Res>  {
  factory $PersistenceStatusReadCopyWith(PersistenceStatusRead value, $Res Function(PersistenceStatusRead) _then) = _$PersistenceStatusReadCopyWithImpl;
@useResult
$Res call({
 int pendingCommits
});




}
/// @nodoc
class _$PersistenceStatusReadCopyWithImpl<$Res>
    implements $PersistenceStatusReadCopyWith<$Res> {
  _$PersistenceStatusReadCopyWithImpl(this._self, this._then);

  final PersistenceStatusRead _self;
  final $Res Function(PersistenceStatusRead) _then;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pendingCommits = null,}) {
  return _then(_self.copyWith(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PersistenceStatusRead].
extension PersistenceStatusReadPatterns on PersistenceStatusRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ReadyPersistenceStatusRead value)?  ready,TResult Function( FlushingPersistenceStatusRead value)?  flushing,TResult Function( DegradedPersistenceStatusRead value)?  degraded,TResult Function( RecoveringPersistenceStatusRead value)?  recovering,TResult Function( BlockedPersistenceStatusRead value)?  blocked,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ReadyPersistenceStatusRead() when ready != null:
return ready(_that);case FlushingPersistenceStatusRead() when flushing != null:
return flushing(_that);case DegradedPersistenceStatusRead() when degraded != null:
return degraded(_that);case RecoveringPersistenceStatusRead() when recovering != null:
return recovering(_that);case BlockedPersistenceStatusRead() when blocked != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ReadyPersistenceStatusRead value)  ready,required TResult Function( FlushingPersistenceStatusRead value)  flushing,required TResult Function( DegradedPersistenceStatusRead value)  degraded,required TResult Function( RecoveringPersistenceStatusRead value)  recovering,required TResult Function( BlockedPersistenceStatusRead value)  blocked,}){
final _that = this;
switch (_that) {
case ReadyPersistenceStatusRead():
return ready(_that);case FlushingPersistenceStatusRead():
return flushing(_that);case DegradedPersistenceStatusRead():
return degraded(_that);case RecoveringPersistenceStatusRead():
return recovering(_that);case BlockedPersistenceStatusRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ReadyPersistenceStatusRead value)?  ready,TResult? Function( FlushingPersistenceStatusRead value)?  flushing,TResult? Function( DegradedPersistenceStatusRead value)?  degraded,TResult? Function( RecoveringPersistenceStatusRead value)?  recovering,TResult? Function( BlockedPersistenceStatusRead value)?  blocked,}){
final _that = this;
switch (_that) {
case ReadyPersistenceStatusRead() when ready != null:
return ready(_that);case FlushingPersistenceStatusRead() when flushing != null:
return flushing(_that);case DegradedPersistenceStatusRead() when degraded != null:
return degraded(_that);case RecoveringPersistenceStatusRead() when recovering != null:
return recovering(_that);case BlockedPersistenceStatusRead() when blocked != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int pendingCommits)?  ready,TResult Function( int pendingCommits,  int? oldestPendingRevision)?  flushing,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateErrorRead error)?  degraded,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  recovering,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateErrorRead error)?  blocked,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ReadyPersistenceStatusRead() when ready != null:
return ready(_that.pendingCommits);case FlushingPersistenceStatusRead() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceStatusRead() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case RecoveringPersistenceStatusRead() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceStatusRead() when blocked != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int pendingCommits)  ready,required TResult Function( int pendingCommits,  int? oldestPendingRevision)  flushing,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateErrorRead error)  degraded,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)  recovering,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateErrorRead error)  blocked,}) {final _that = this;
switch (_that) {
case ReadyPersistenceStatusRead():
return ready(_that.pendingCommits);case FlushingPersistenceStatusRead():
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceStatusRead():
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case RecoveringPersistenceStatusRead():
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceStatusRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int pendingCommits)?  ready,TResult? Function( int pendingCommits,  int? oldestPendingRevision)?  flushing,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateErrorRead error)?  degraded,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  recovering,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt,  SourceStateErrorRead error)?  blocked,}) {final _that = this;
switch (_that) {
case ReadyPersistenceStatusRead() when ready != null:
return ready(_that.pendingCommits);case FlushingPersistenceStatusRead() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceStatusRead() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case RecoveringPersistenceStatusRead() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceStatusRead() when blocked != null:
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class ReadyPersistenceStatusRead implements PersistenceStatusRead {
  const ReadyPersistenceStatusRead({required this.pendingCommits});


@override final  int pendingCommits;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyPersistenceStatusReadCopyWith<ReadyPersistenceStatusRead> get copyWith => _$ReadyPersistenceStatusReadCopyWithImpl<ReadyPersistenceStatusRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyPersistenceStatusRead&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits);
}



}

/// @nodoc
abstract mixin class $ReadyPersistenceStatusReadCopyWith<$Res> implements $PersistenceStatusReadCopyWith<$Res> {
  factory $ReadyPersistenceStatusReadCopyWith(ReadyPersistenceStatusRead value, $Res Function(ReadyPersistenceStatusRead) _then) = _$ReadyPersistenceStatusReadCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits
});




}
/// @nodoc
class _$ReadyPersistenceStatusReadCopyWithImpl<$Res>
    implements $ReadyPersistenceStatusReadCopyWith<$Res> {
  _$ReadyPersistenceStatusReadCopyWithImpl(this._self, this._then);

  final ReadyPersistenceStatusRead _self;
  final $Res Function(ReadyPersistenceStatusRead) _then;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,}) {
  return _then(ReadyPersistenceStatusRead(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FlushingPersistenceStatusRead implements PersistenceStatusRead {
  const FlushingPersistenceStatusRead({required this.pendingCommits, required this.oldestPendingRevision});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlushingPersistenceStatusReadCopyWith<FlushingPersistenceStatusRead> get copyWith => _$FlushingPersistenceStatusReadCopyWithImpl<FlushingPersistenceStatusRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FlushingPersistenceStatusRead&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision);
}



}

/// @nodoc
abstract mixin class $FlushingPersistenceStatusReadCopyWith<$Res> implements $PersistenceStatusReadCopyWith<$Res> {
  factory $FlushingPersistenceStatusReadCopyWith(FlushingPersistenceStatusRead value, $Res Function(FlushingPersistenceStatusRead) _then) = _$FlushingPersistenceStatusReadCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision
});




}
/// @nodoc
class _$FlushingPersistenceStatusReadCopyWithImpl<$Res>
    implements $FlushingPersistenceStatusReadCopyWith<$Res> {
  _$FlushingPersistenceStatusReadCopyWithImpl(this._self, this._then);

  final FlushingPersistenceStatusRead _self;
  final $Res Function(FlushingPersistenceStatusRead) _then;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,}) {
  return _then(FlushingPersistenceStatusRead(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class DegradedPersistenceStatusRead implements PersistenceStatusRead {
  const DegradedPersistenceStatusRead({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt, required this.error});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;
 final  SourceStateErrorRead error;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DegradedPersistenceStatusReadCopyWith<DegradedPersistenceStatusRead> get copyWith => _$DegradedPersistenceStatusReadCopyWithImpl<DegradedPersistenceStatusRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DegradedPersistenceStatusRead&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt,error);
}



}

/// @nodoc
abstract mixin class $DegradedPersistenceStatusReadCopyWith<$Res> implements $PersistenceStatusReadCopyWith<$Res> {
  factory $DegradedPersistenceStatusReadCopyWith(DegradedPersistenceStatusRead value, $Res Function(DegradedPersistenceStatusRead) _then) = _$DegradedPersistenceStatusReadCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$DegradedPersistenceStatusReadCopyWithImpl<$Res>
    implements $DegradedPersistenceStatusReadCopyWith<$Res> {
  _$DegradedPersistenceStatusReadCopyWithImpl(this._self, this._then);

  final DegradedPersistenceStatusRead _self;
  final $Res Function(DegradedPersistenceStatusRead) _then;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,Object? error = null,}) {
  return _then(DegradedPersistenceStatusRead(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class RecoveringPersistenceStatusRead implements PersistenceStatusRead {
  const RecoveringPersistenceStatusRead({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveringPersistenceStatusReadCopyWith<RecoveringPersistenceStatusRead> get copyWith => _$RecoveringPersistenceStatusReadCopyWithImpl<RecoveringPersistenceStatusRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveringPersistenceStatusRead&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}



}

/// @nodoc
abstract mixin class $RecoveringPersistenceStatusReadCopyWith<$Res> implements $PersistenceStatusReadCopyWith<$Res> {
  factory $RecoveringPersistenceStatusReadCopyWith(RecoveringPersistenceStatusRead value, $Res Function(RecoveringPersistenceStatusRead) _then) = _$RecoveringPersistenceStatusReadCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt
});




}
/// @nodoc
class _$RecoveringPersistenceStatusReadCopyWithImpl<$Res>
    implements $RecoveringPersistenceStatusReadCopyWith<$Res> {
  _$RecoveringPersistenceStatusReadCopyWithImpl(this._self, this._then);

  final RecoveringPersistenceStatusRead _self;
  final $Res Function(RecoveringPersistenceStatusRead) _then;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(RecoveringPersistenceStatusRead(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BlockedPersistenceStatusRead implements PersistenceStatusRead {
  const BlockedPersistenceStatusRead({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt, required this.error});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;
 final  SourceStateErrorRead error;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockedPersistenceStatusReadCopyWith<BlockedPersistenceStatusRead> get copyWith => _$BlockedPersistenceStatusReadCopyWithImpl<BlockedPersistenceStatusRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockedPersistenceStatusRead&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt,error);
}



}

/// @nodoc
abstract mixin class $BlockedPersistenceStatusReadCopyWith<$Res> implements $PersistenceStatusReadCopyWith<$Res> {
  factory $BlockedPersistenceStatusReadCopyWith(BlockedPersistenceStatusRead value, $Res Function(BlockedPersistenceStatusRead) _then) = _$BlockedPersistenceStatusReadCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$BlockedPersistenceStatusReadCopyWithImpl<$Res>
    implements $BlockedPersistenceStatusReadCopyWith<$Res> {
  _$BlockedPersistenceStatusReadCopyWithImpl(this._self, this._then);

  final BlockedPersistenceStatusRead _self;
  final $Res Function(BlockedPersistenceStatusRead) _then;

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,Object? error = null,}) {
  return _then(BlockedPersistenceStatusRead(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of PersistenceStatusRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$PersistenceReadHeader {

 int get revision; PersistenceStatusRead get state;
/// Create a copy of PersistenceReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceReadHeaderCopyWith<PersistenceReadHeader> get copyWith => _$PersistenceReadHeaderCopyWithImpl<PersistenceReadHeader>(this as PersistenceReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceReadHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as PersistenceReadHeader;
  return Object.hash(runtimeType,_this.revision,_this.state);
}



}

/// @nodoc
abstract mixin class $PersistenceReadHeaderCopyWith<$Res>  {
  factory $PersistenceReadHeaderCopyWith(PersistenceReadHeader value, $Res Function(PersistenceReadHeader) _then) = _$PersistenceReadHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, PersistenceStatusRead state
});


$PersistenceStatusReadCopyWith<$Res> get state;

}
/// @nodoc
class _$PersistenceReadHeaderCopyWithImpl<$Res>
    implements $PersistenceReadHeaderCopyWith<$Res> {
  _$PersistenceReadHeaderCopyWithImpl(this._self, this._then);

  final PersistenceReadHeader _self;
  final $Res Function(PersistenceReadHeader) _then;

/// Create a copy of PersistenceReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? state = null,}) {
  return _then(PersistenceReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PersistenceStatusRead,
  ));
}
/// Create a copy of PersistenceReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceStatusReadCopyWith<$Res> get state {

  return $PersistenceStatusReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceReadHeader].
extension PersistenceReadHeaderPatterns on PersistenceReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  PersistenceStatusRead state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceReadHeader() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  PersistenceStatusRead state)  $default,) {final _that = this;
switch (_that) {
case _PersistenceReadHeader():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  PersistenceStatusRead state)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceReadHeader() when $default != null:
return $default(_that.revision,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceReadHeader implements PersistenceReadHeader {
  const _PersistenceReadHeader({required this.revision, required this.state});


@override final  int revision;
@override final  PersistenceStatusRead state;

/// Create a copy of PersistenceReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceReadHeaderCopyWith<_PersistenceReadHeader> get copyWith => __$PersistenceReadHeaderCopyWithImpl<_PersistenceReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,state);
}



}

/// @nodoc
abstract mixin class _$PersistenceReadHeaderCopyWith<$Res> implements $PersistenceReadHeaderCopyWith<$Res> {
  factory _$PersistenceReadHeaderCopyWith(_PersistenceReadHeader value, $Res Function(_PersistenceReadHeader) _then) = __$PersistenceReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, PersistenceStatusRead state
});


@override $PersistenceStatusReadCopyWith<$Res> get state;

}
/// @nodoc
class __$PersistenceReadHeaderCopyWithImpl<$Res>
    implements _$PersistenceReadHeaderCopyWith<$Res> {
  __$PersistenceReadHeaderCopyWithImpl(this._self, this._then);

  final _PersistenceReadHeader _self;
  final $Res Function(_PersistenceReadHeader) _then;

/// Create a copy of PersistenceReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? state = null,}) {
  return _then(_PersistenceReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PersistenceStatusRead,
  ));
}

/// Create a copy of PersistenceReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceStatusReadCopyWith<$Res> get state {

  return $PersistenceStatusReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$ThreadPersistenceRead {

 ReadText get threadId; int get faultGeneration; HistoryFault? get fault; int? get stateDirtyRevision; int? get stateSavingRevision; int? get stateDurableRevision; int? get historyAdmittedSequence; int? get historyDurableSequence; int? get callsAdmittedSequence; int? get callsDurableSequence; int get pendingOperations; int get pendingBytes; int? get oldestPendingAgeMillis; int get inFlightBytes; ReadText? get lastError; bool get pressurePaused;
/// Create a copy of ThreadPersistenceRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadPersistenceReadCopyWith<ThreadPersistenceRead> get copyWith => _$ThreadPersistenceReadCopyWithImpl<ThreadPersistenceRead>(this as ThreadPersistenceRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadPersistenceRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadPersistenceRead&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.faultGeneration, _this.faultGeneration) || other.faultGeneration == _this.faultGeneration)&&(identical(other.fault, _this.fault) || other.fault == _this.fault)&&(identical(other.stateDirtyRevision, _this.stateDirtyRevision) || other.stateDirtyRevision == _this.stateDirtyRevision)&&(identical(other.stateSavingRevision, _this.stateSavingRevision) || other.stateSavingRevision == _this.stateSavingRevision)&&(identical(other.stateDurableRevision, _this.stateDurableRevision) || other.stateDurableRevision == _this.stateDurableRevision)&&(identical(other.historyAdmittedSequence, _this.historyAdmittedSequence) || other.historyAdmittedSequence == _this.historyAdmittedSequence)&&(identical(other.historyDurableSequence, _this.historyDurableSequence) || other.historyDurableSequence == _this.historyDurableSequence)&&(identical(other.callsAdmittedSequence, _this.callsAdmittedSequence) || other.callsAdmittedSequence == _this.callsAdmittedSequence)&&(identical(other.callsDurableSequence, _this.callsDurableSequence) || other.callsDurableSequence == _this.callsDurableSequence)&&(identical(other.pendingOperations, _this.pendingOperations) || other.pendingOperations == _this.pendingOperations)&&(identical(other.pendingBytes, _this.pendingBytes) || other.pendingBytes == _this.pendingBytes)&&(identical(other.oldestPendingAgeMillis, _this.oldestPendingAgeMillis) || other.oldestPendingAgeMillis == _this.oldestPendingAgeMillis)&&(identical(other.inFlightBytes, _this.inFlightBytes) || other.inFlightBytes == _this.inFlightBytes)&&(identical(other.lastError, _this.lastError) || other.lastError == _this.lastError)&&(identical(other.pressurePaused, _this.pressurePaused) || other.pressurePaused == _this.pressurePaused));
}


@override
int get hashCode {
  final _this = this as ThreadPersistenceRead;
  return Object.hash(runtimeType,_this.threadId,_this.faultGeneration,_this.fault,_this.stateDirtyRevision,_this.stateSavingRevision,_this.stateDurableRevision,_this.historyAdmittedSequence,_this.historyDurableSequence,_this.callsAdmittedSequence,_this.callsDurableSequence,_this.pendingOperations,_this.pendingBytes,_this.oldestPendingAgeMillis,_this.inFlightBytes,_this.lastError,_this.pressurePaused);
}



}

/// @nodoc
abstract mixin class $ThreadPersistenceReadCopyWith<$Res>  {
  factory $ThreadPersistenceReadCopyWith(ThreadPersistenceRead value, $Res Function(ThreadPersistenceRead) _then) = _$ThreadPersistenceReadCopyWithImpl;
@useResult
$Res call({
 ReadText threadId, int faultGeneration, HistoryFault? fault, int? stateDirtyRevision, int? stateSavingRevision, int? stateDurableRevision, int? historyAdmittedSequence, int? historyDurableSequence, int? callsAdmittedSequence, int? callsDurableSequence, int pendingOperations, int pendingBytes, int? oldestPendingAgeMillis, int inFlightBytes, ReadText? lastError, bool pressurePaused
});


$ReadTextCopyWith<$Res> get threadId;$ReadTextCopyWith<$Res>? get lastError;

}
/// @nodoc
class _$ThreadPersistenceReadCopyWithImpl<$Res>
    implements $ThreadPersistenceReadCopyWith<$Res> {
  _$ThreadPersistenceReadCopyWithImpl(this._self, this._then);

  final ThreadPersistenceRead _self;
  final $Res Function(ThreadPersistenceRead) _then;

/// Create a copy of ThreadPersistenceRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? faultGeneration = null,Object? fault = freezed,Object? stateDirtyRevision = freezed,Object? stateSavingRevision = freezed,Object? stateDurableRevision = freezed,Object? historyAdmittedSequence = freezed,Object? historyDurableSequence = freezed,Object? callsAdmittedSequence = freezed,Object? callsDurableSequence = freezed,Object? pendingOperations = null,Object? pendingBytes = null,Object? oldestPendingAgeMillis = freezed,Object? inFlightBytes = null,Object? lastError = freezed,Object? pressurePaused = null,}) {
  return _then(ThreadPersistenceRead(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
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
as ReadText?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ThreadPersistenceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of ThreadPersistenceRead
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


/// Adds pattern-matching-related methods to [ThreadPersistenceRead].
extension ThreadPersistenceReadPatterns on ThreadPersistenceRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadPersistenceRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadPersistenceRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadPersistenceRead value)  $default,){
final _that = this;
switch (_that) {
case _ThreadPersistenceRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadPersistenceRead value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadPersistenceRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText threadId,  int faultGeneration,  HistoryFault? fault,  int? stateDirtyRevision,  int? stateSavingRevision,  int? stateDurableRevision,  int? historyAdmittedSequence,  int? historyDurableSequence,  int? callsAdmittedSequence,  int? callsDurableSequence,  int pendingOperations,  int pendingBytes,  int? oldestPendingAgeMillis,  int inFlightBytes,  ReadText? lastError,  bool pressurePaused)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadPersistenceRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText threadId,  int faultGeneration,  HistoryFault? fault,  int? stateDirtyRevision,  int? stateSavingRevision,  int? stateDurableRevision,  int? historyAdmittedSequence,  int? historyDurableSequence,  int? callsAdmittedSequence,  int? callsDurableSequence,  int pendingOperations,  int pendingBytes,  int? oldestPendingAgeMillis,  int inFlightBytes,  ReadText? lastError,  bool pressurePaused)  $default,) {final _that = this;
switch (_that) {
case _ThreadPersistenceRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText threadId,  int faultGeneration,  HistoryFault? fault,  int? stateDirtyRevision,  int? stateSavingRevision,  int? stateDurableRevision,  int? historyAdmittedSequence,  int? historyDurableSequence,  int? callsAdmittedSequence,  int? callsDurableSequence,  int pendingOperations,  int pendingBytes,  int? oldestPendingAgeMillis,  int inFlightBytes,  ReadText? lastError,  bool pressurePaused)?  $default,) {final _that = this;
switch (_that) {
case _ThreadPersistenceRead() when $default != null:
return $default(_that.threadId,_that.faultGeneration,_that.fault,_that.stateDirtyRevision,_that.stateSavingRevision,_that.stateDurableRevision,_that.historyAdmittedSequence,_that.historyDurableSequence,_that.callsAdmittedSequence,_that.callsDurableSequence,_that.pendingOperations,_that.pendingBytes,_that.oldestPendingAgeMillis,_that.inFlightBytes,_that.lastError,_that.pressurePaused);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadPersistenceRead implements ThreadPersistenceRead {
  const _ThreadPersistenceRead({required this.threadId, required this.faultGeneration, required this.fault, required this.stateDirtyRevision, required this.stateSavingRevision, required this.stateDurableRevision, required this.historyAdmittedSequence, required this.historyDurableSequence, required this.callsAdmittedSequence, required this.callsDurableSequence, required this.pendingOperations, required this.pendingBytes, required this.oldestPendingAgeMillis, required this.inFlightBytes, required this.lastError, required this.pressurePaused});


@override final  ReadText threadId;
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
@override final  ReadText? lastError;
@override final  bool pressurePaused;

/// Create a copy of ThreadPersistenceRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadPersistenceReadCopyWith<_ThreadPersistenceRead> get copyWith => __$ThreadPersistenceReadCopyWithImpl<_ThreadPersistenceRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadPersistenceRead&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.faultGeneration, faultGeneration) || other.faultGeneration == faultGeneration)&&(identical(other.fault, fault) || other.fault == fault)&&(identical(other.stateDirtyRevision, stateDirtyRevision) || other.stateDirtyRevision == stateDirtyRevision)&&(identical(other.stateSavingRevision, stateSavingRevision) || other.stateSavingRevision == stateSavingRevision)&&(identical(other.stateDurableRevision, stateDurableRevision) || other.stateDurableRevision == stateDurableRevision)&&(identical(other.historyAdmittedSequence, historyAdmittedSequence) || other.historyAdmittedSequence == historyAdmittedSequence)&&(identical(other.historyDurableSequence, historyDurableSequence) || other.historyDurableSequence == historyDurableSequence)&&(identical(other.callsAdmittedSequence, callsAdmittedSequence) || other.callsAdmittedSequence == callsAdmittedSequence)&&(identical(other.callsDurableSequence, callsDurableSequence) || other.callsDurableSequence == callsDurableSequence)&&(identical(other.pendingOperations, pendingOperations) || other.pendingOperations == pendingOperations)&&(identical(other.pendingBytes, pendingBytes) || other.pendingBytes == pendingBytes)&&(identical(other.oldestPendingAgeMillis, oldestPendingAgeMillis) || other.oldestPendingAgeMillis == oldestPendingAgeMillis)&&(identical(other.inFlightBytes, inFlightBytes) || other.inFlightBytes == inFlightBytes)&&(identical(other.lastError, lastError) || other.lastError == lastError)&&(identical(other.pressurePaused, pressurePaused) || other.pressurePaused == pressurePaused));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,faultGeneration,fault,stateDirtyRevision,stateSavingRevision,stateDurableRevision,historyAdmittedSequence,historyDurableSequence,callsAdmittedSequence,callsDurableSequence,pendingOperations,pendingBytes,oldestPendingAgeMillis,inFlightBytes,lastError,pressurePaused);
}



}

/// @nodoc
abstract mixin class _$ThreadPersistenceReadCopyWith<$Res> implements $ThreadPersistenceReadCopyWith<$Res> {
  factory _$ThreadPersistenceReadCopyWith(_ThreadPersistenceRead value, $Res Function(_ThreadPersistenceRead) _then) = __$ThreadPersistenceReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText threadId, int faultGeneration, HistoryFault? fault, int? stateDirtyRevision, int? stateSavingRevision, int? stateDurableRevision, int? historyAdmittedSequence, int? historyDurableSequence, int? callsAdmittedSequence, int? callsDurableSequence, int pendingOperations, int pendingBytes, int? oldestPendingAgeMillis, int inFlightBytes, ReadText? lastError, bool pressurePaused
});


@override $ReadTextCopyWith<$Res> get threadId;@override $ReadTextCopyWith<$Res>? get lastError;

}
/// @nodoc
class __$ThreadPersistenceReadCopyWithImpl<$Res>
    implements _$ThreadPersistenceReadCopyWith<$Res> {
  __$ThreadPersistenceReadCopyWithImpl(this._self, this._then);

  final _ThreadPersistenceRead _self;
  final $Res Function(_ThreadPersistenceRead) _then;

/// Create a copy of ThreadPersistenceRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? faultGeneration = null,Object? fault = freezed,Object? stateDirtyRevision = freezed,Object? stateSavingRevision = freezed,Object? stateDurableRevision = freezed,Object? historyAdmittedSequence = freezed,Object? historyDurableSequence = freezed,Object? callsAdmittedSequence = freezed,Object? callsDurableSequence = freezed,Object? pendingOperations = null,Object? pendingBytes = null,Object? oldestPendingAgeMillis = freezed,Object? inFlightBytes = null,Object? lastError = freezed,Object? pressurePaused = null,}) {
  return _then(_ThreadPersistenceRead(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,faultGeneration: null == faultGeneration ? _self.faultGeneration : faultGeneration // ignore: cast_nullable_to_non_nullable
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
as ReadText?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ThreadPersistenceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of ThreadPersistenceRead
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
mixin _$PersistenceQueueSnapshotRead {

 bool get statisticsGap; int get pendingOperations; int get pendingBytes; int get inFlightBytes; int? get oldestPendingAgeMillis; ReadText? get lastError; bool get pressurePaused; TypedListRef get threads;
/// Create a copy of PersistenceQueueSnapshotRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueSnapshotReadCopyWith<PersistenceQueueSnapshotRead> get copyWith => _$PersistenceQueueSnapshotReadCopyWithImpl<PersistenceQueueSnapshotRead>(this as PersistenceQueueSnapshotRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueSnapshotRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueSnapshotRead&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.pendingOperations, _this.pendingOperations) || other.pendingOperations == _this.pendingOperations)&&(identical(other.pendingBytes, _this.pendingBytes) || other.pendingBytes == _this.pendingBytes)&&(identical(other.inFlightBytes, _this.inFlightBytes) || other.inFlightBytes == _this.inFlightBytes)&&(identical(other.oldestPendingAgeMillis, _this.oldestPendingAgeMillis) || other.oldestPendingAgeMillis == _this.oldestPendingAgeMillis)&&(identical(other.lastError, _this.lastError) || other.lastError == _this.lastError)&&(identical(other.pressurePaused, _this.pressurePaused) || other.pressurePaused == _this.pressurePaused)&&(identical(other.threads, _this.threads) || other.threads == _this.threads));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueSnapshotRead;
  return Object.hash(runtimeType,_this.statisticsGap,_this.pendingOperations,_this.pendingBytes,_this.inFlightBytes,_this.oldestPendingAgeMillis,_this.lastError,_this.pressurePaused,_this.threads);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueSnapshotReadCopyWith<$Res>  {
  factory $PersistenceQueueSnapshotReadCopyWith(PersistenceQueueSnapshotRead value, $Res Function(PersistenceQueueSnapshotRead) _then) = _$PersistenceQueueSnapshotReadCopyWithImpl;
@useResult
$Res call({
 bool statisticsGap, int pendingOperations, int pendingBytes, int inFlightBytes, int? oldestPendingAgeMillis, ReadText? lastError, bool pressurePaused, TypedListRef threads
});


$ReadTextCopyWith<$Res>? get lastError;$TypedListRefCopyWith<$Res> get threads;

}
/// @nodoc
class _$PersistenceQueueSnapshotReadCopyWithImpl<$Res>
    implements $PersistenceQueueSnapshotReadCopyWith<$Res> {
  _$PersistenceQueueSnapshotReadCopyWithImpl(this._self, this._then);

  final PersistenceQueueSnapshotRead _self;
  final $Res Function(PersistenceQueueSnapshotRead) _then;

/// Create a copy of PersistenceQueueSnapshotRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? statisticsGap = null,Object? pendingOperations = null,Object? pendingBytes = null,Object? inFlightBytes = null,Object? oldestPendingAgeMillis = freezed,Object? lastError = freezed,Object? pressurePaused = null,Object? threads = null,}) {
  return _then(PersistenceQueueSnapshotRead(
statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,pendingOperations: null == pendingOperations ? _self.pendingOperations : pendingOperations // ignore: cast_nullable_to_non_nullable
as int,pendingBytes: null == pendingBytes ? _self.pendingBytes : pendingBytes // ignore: cast_nullable_to_non_nullable
as int,inFlightBytes: null == inFlightBytes ? _self.inFlightBytes : inFlightBytes // ignore: cast_nullable_to_non_nullable
as int,oldestPendingAgeMillis: freezed == oldestPendingAgeMillis ? _self.oldestPendingAgeMillis : oldestPendingAgeMillis // ignore: cast_nullable_to_non_nullable
as int?,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as ReadText?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of PersistenceQueueSnapshotRead
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
}/// Create a copy of PersistenceQueueSnapshotRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get threads {

  return $TypedListRefCopyWith<$Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueSnapshotRead].
extension PersistenceQueueSnapshotReadPatterns on PersistenceQueueSnapshotRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueSnapshotRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueSnapshotRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueSnapshotRead value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueSnapshotRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueSnapshotRead value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueSnapshotRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool statisticsGap,  int pendingOperations,  int pendingBytes,  int inFlightBytes,  int? oldestPendingAgeMillis,  ReadText? lastError,  bool pressurePaused,  TypedListRef threads)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceQueueSnapshotRead() when $default != null:
return $default(_that.statisticsGap,_that.pendingOperations,_that.pendingBytes,_that.inFlightBytes,_that.oldestPendingAgeMillis,_that.lastError,_that.pressurePaused,_that.threads);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool statisticsGap,  int pendingOperations,  int pendingBytes,  int inFlightBytes,  int? oldestPendingAgeMillis,  ReadText? lastError,  bool pressurePaused,  TypedListRef threads)  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueSnapshotRead():
return $default(_that.statisticsGap,_that.pendingOperations,_that.pendingBytes,_that.inFlightBytes,_that.oldestPendingAgeMillis,_that.lastError,_that.pressurePaused,_that.threads);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool statisticsGap,  int pendingOperations,  int pendingBytes,  int inFlightBytes,  int? oldestPendingAgeMillis,  ReadText? lastError,  bool pressurePaused,  TypedListRef threads)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueSnapshotRead() when $default != null:
return $default(_that.statisticsGap,_that.pendingOperations,_that.pendingBytes,_that.inFlightBytes,_that.oldestPendingAgeMillis,_that.lastError,_that.pressurePaused,_that.threads);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueSnapshotRead implements PersistenceQueueSnapshotRead {
  const _PersistenceQueueSnapshotRead({required this.statisticsGap, required this.pendingOperations, required this.pendingBytes, required this.inFlightBytes, required this.oldestPendingAgeMillis, required this.lastError, required this.pressurePaused, required this.threads});


@override final  bool statisticsGap;
@override final  int pendingOperations;
@override final  int pendingBytes;
@override final  int inFlightBytes;
@override final  int? oldestPendingAgeMillis;
@override final  ReadText? lastError;
@override final  bool pressurePaused;
@override final  TypedListRef threads;

/// Create a copy of PersistenceQueueSnapshotRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueSnapshotReadCopyWith<_PersistenceQueueSnapshotRead> get copyWith => __$PersistenceQueueSnapshotReadCopyWithImpl<_PersistenceQueueSnapshotRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueSnapshotRead&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.pendingOperations, pendingOperations) || other.pendingOperations == pendingOperations)&&(identical(other.pendingBytes, pendingBytes) || other.pendingBytes == pendingBytes)&&(identical(other.inFlightBytes, inFlightBytes) || other.inFlightBytes == inFlightBytes)&&(identical(other.oldestPendingAgeMillis, oldestPendingAgeMillis) || other.oldestPendingAgeMillis == oldestPendingAgeMillis)&&(identical(other.lastError, lastError) || other.lastError == lastError)&&(identical(other.pressurePaused, pressurePaused) || other.pressurePaused == pressurePaused)&&(identical(other.threads, threads) || other.threads == threads));
}


@override
int get hashCode {
    return Object.hash(runtimeType,statisticsGap,pendingOperations,pendingBytes,inFlightBytes,oldestPendingAgeMillis,lastError,pressurePaused,threads);
}



}

/// @nodoc
abstract mixin class _$PersistenceQueueSnapshotReadCopyWith<$Res> implements $PersistenceQueueSnapshotReadCopyWith<$Res> {
  factory _$PersistenceQueueSnapshotReadCopyWith(_PersistenceQueueSnapshotRead value, $Res Function(_PersistenceQueueSnapshotRead) _then) = __$PersistenceQueueSnapshotReadCopyWithImpl;
@override @useResult
$Res call({
 bool statisticsGap, int pendingOperations, int pendingBytes, int inFlightBytes, int? oldestPendingAgeMillis, ReadText? lastError, bool pressurePaused, TypedListRef threads
});


@override $ReadTextCopyWith<$Res>? get lastError;@override $TypedListRefCopyWith<$Res> get threads;

}
/// @nodoc
class __$PersistenceQueueSnapshotReadCopyWithImpl<$Res>
    implements _$PersistenceQueueSnapshotReadCopyWith<$Res> {
  __$PersistenceQueueSnapshotReadCopyWithImpl(this._self, this._then);

  final _PersistenceQueueSnapshotRead _self;
  final $Res Function(_PersistenceQueueSnapshotRead) _then;

/// Create a copy of PersistenceQueueSnapshotRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? statisticsGap = null,Object? pendingOperations = null,Object? pendingBytes = null,Object? inFlightBytes = null,Object? oldestPendingAgeMillis = freezed,Object? lastError = freezed,Object? pressurePaused = null,Object? threads = null,}) {
  return _then(_PersistenceQueueSnapshotRead(
statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,pendingOperations: null == pendingOperations ? _self.pendingOperations : pendingOperations // ignore: cast_nullable_to_non_nullable
as int,pendingBytes: null == pendingBytes ? _self.pendingBytes : pendingBytes // ignore: cast_nullable_to_non_nullable
as int,inFlightBytes: null == inFlightBytes ? _self.inFlightBytes : inFlightBytes // ignore: cast_nullable_to_non_nullable
as int,oldestPendingAgeMillis: freezed == oldestPendingAgeMillis ? _self.oldestPendingAgeMillis : oldestPendingAgeMillis // ignore: cast_nullable_to_non_nullable
as int?,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as ReadText?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of PersistenceQueueSnapshotRead
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
}/// Create a copy of PersistenceQueueSnapshotRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get threads {

  return $TypedListRefCopyWith<$Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueReadHeader {

 int get revision; int get updatedAt; PersistenceQueueSnapshotRead get queue;
/// Create a copy of PersistenceQueueReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueReadHeaderCopyWith<PersistenceQueueReadHeader> get copyWith => _$PersistenceQueueReadHeaderCopyWithImpl<PersistenceQueueReadHeader>(this as PersistenceQueueReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueReadHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.queue, _this.queue) || other.queue == _this.queue));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueReadHeader;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.queue);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueReadHeaderCopyWith<$Res>  {
  factory $PersistenceQueueReadHeaderCopyWith(PersistenceQueueReadHeader value, $Res Function(PersistenceQueueReadHeader) _then) = _$PersistenceQueueReadHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, PersistenceQueueSnapshotRead queue
});


$PersistenceQueueSnapshotReadCopyWith<$Res> get queue;

}
/// @nodoc
class _$PersistenceQueueReadHeaderCopyWithImpl<$Res>
    implements $PersistenceQueueReadHeaderCopyWith<$Res> {
  _$PersistenceQueueReadHeaderCopyWithImpl(this._self, this._then);

  final PersistenceQueueReadHeader _self;
  final $Res Function(PersistenceQueueReadHeader) _then;

/// Create a copy of PersistenceQueueReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? queue = null,}) {
  return _then(PersistenceQueueReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as PersistenceQueueSnapshotRead,
  ));
}
/// Create a copy of PersistenceQueueReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueSnapshotReadCopyWith<$Res> get queue {

  return $PersistenceQueueSnapshotReadCopyWith<$Res>(_self.queue, (value) {
    return _then(_self.copyWith(queue: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueReadHeader].
extension PersistenceQueueReadHeaderPatterns on PersistenceQueueReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  PersistenceQueueSnapshotRead queue)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceQueueReadHeader() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  PersistenceQueueSnapshotRead queue)  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueReadHeader():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  PersistenceQueueSnapshotRead queue)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueReadHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.queue);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueReadHeader implements PersistenceQueueReadHeader {
  const _PersistenceQueueReadHeader({required this.revision, required this.updatedAt, required this.queue});


@override final  int revision;
@override final  int updatedAt;
@override final  PersistenceQueueSnapshotRead queue;

/// Create a copy of PersistenceQueueReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueReadHeaderCopyWith<_PersistenceQueueReadHeader> get copyWith => __$PersistenceQueueReadHeaderCopyWithImpl<_PersistenceQueueReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.queue, queue) || other.queue == queue));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,queue);
}



}

/// @nodoc
abstract mixin class _$PersistenceQueueReadHeaderCopyWith<$Res> implements $PersistenceQueueReadHeaderCopyWith<$Res> {
  factory _$PersistenceQueueReadHeaderCopyWith(_PersistenceQueueReadHeader value, $Res Function(_PersistenceQueueReadHeader) _then) = __$PersistenceQueueReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, PersistenceQueueSnapshotRead queue
});


@override $PersistenceQueueSnapshotReadCopyWith<$Res> get queue;

}
/// @nodoc
class __$PersistenceQueueReadHeaderCopyWithImpl<$Res>
    implements _$PersistenceQueueReadHeaderCopyWith<$Res> {
  __$PersistenceQueueReadHeaderCopyWithImpl(this._self, this._then);

  final _PersistenceQueueReadHeader _self;
  final $Res Function(_PersistenceQueueReadHeader) _then;

/// Create a copy of PersistenceQueueReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? queue = null,}) {
  return _then(_PersistenceQueueReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,queue: null == queue ? _self.queue : queue // ignore: cast_nullable_to_non_nullable
as PersistenceQueueSnapshotRead,
  ));
}

/// Create a copy of PersistenceQueueReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueSnapshotReadCopyWith<$Res> get queue {

  return $PersistenceQueueSnapshotReadCopyWith<$Res>(_self.queue, (value) {
    return _then(_self.copyWith(queue: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueEntityRead {

 ProductEntityRef get reference; ThreadPersistenceRead get value;
/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueEntityReadCopyWith<PersistenceQueueEntityRead> get copyWith => _$PersistenceQueueEntityReadCopyWithImpl<PersistenceQueueEntityRead>(this as PersistenceQueueEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueEntityReadCopyWith<$Res>  {
  factory $PersistenceQueueEntityReadCopyWith(PersistenceQueueEntityRead value, $Res Function(PersistenceQueueEntityRead) _then) = _$PersistenceQueueEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, ThreadPersistenceRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$ThreadPersistenceReadCopyWith<$Res> get value;

}
/// @nodoc
class _$PersistenceQueueEntityReadCopyWithImpl<$Res>
    implements $PersistenceQueueEntityReadCopyWith<$Res> {
  _$PersistenceQueueEntityReadCopyWithImpl(this._self, this._then);

  final PersistenceQueueEntityRead _self;
  final $Res Function(PersistenceQueueEntityRead) _then;

/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(PersistenceQueueEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadPersistenceRead,
  ));
}
/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadPersistenceReadCopyWith<$Res> get value {

  return $ThreadPersistenceReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueEntityRead].
extension PersistenceQueueEntityReadPatterns on PersistenceQueueEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  ThreadPersistenceRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceQueueEntityRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  ThreadPersistenceRead value)  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueEntityRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  ThreadPersistenceRead value)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueEntityRead implements PersistenceQueueEntityRead {
  const _PersistenceQueueEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  ThreadPersistenceRead value;

/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueEntityReadCopyWith<_PersistenceQueueEntityRead> get copyWith => __$PersistenceQueueEntityReadCopyWithImpl<_PersistenceQueueEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$PersistenceQueueEntityReadCopyWith<$Res> implements $PersistenceQueueEntityReadCopyWith<$Res> {
  factory _$PersistenceQueueEntityReadCopyWith(_PersistenceQueueEntityRead value, $Res Function(_PersistenceQueueEntityRead) _then) = __$PersistenceQueueEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, ThreadPersistenceRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $ThreadPersistenceReadCopyWith<$Res> get value;

}
/// @nodoc
class __$PersistenceQueueEntityReadCopyWithImpl<$Res>
    implements _$PersistenceQueueEntityReadCopyWith<$Res> {
  __$PersistenceQueueEntityReadCopyWithImpl(this._self, this._then);

  final _PersistenceQueueEntityRead _self;
  final $Res Function(_PersistenceQueueEntityRead) _then;

/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_PersistenceQueueEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadPersistenceRead,
  ));
}

/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PersistenceQueueEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadPersistenceReadCopyWith<$Res> get value {

  return $ThreadPersistenceReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueEntryPage {


/// Create a copy of PersistenceQueueEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueEntryPageCopyWith<PersistenceQueueEntryPage> get copyWith => _$PersistenceQueueEntryPageCopyWithImpl<PersistenceQueueEntryPage>(this as PersistenceQueueEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as PersistenceQueueEntryPage;
  return 'PersistenceQueueEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $PersistenceQueueEntryPageCopyWith<$Res>  {
  factory $PersistenceQueueEntryPageCopyWith(PersistenceQueueEntryPage value, $Res Function(PersistenceQueueEntryPage) _then) = _$PersistenceQueueEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$PersistenceQueueEntryPageCopyWithImpl<$Res>
    implements $PersistenceQueueEntryPageCopyWith<$Res> {
  _$PersistenceQueueEntryPageCopyWithImpl(this._self, this._then);

  final PersistenceQueueEntryPage _self;
  final $Res Function(PersistenceQueueEntryPage) _then;

/// Create a copy of PersistenceQueueEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(PersistenceQueueEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of PersistenceQueueEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueEntryPage].
extension PersistenceQueueEntryPagePatterns on PersistenceQueueEntryPage {
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
mixin _$ThreadPersistenceReadPage {


/// Create a copy of ThreadPersistenceReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadPersistenceReadPageCopyWith<ThreadPersistenceReadPage> get copyWith => _$ThreadPersistenceReadPageCopyWithImpl<ThreadPersistenceReadPage>(this as ThreadPersistenceReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadPersistenceReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadPersistenceReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as ThreadPersistenceReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $ThreadPersistenceReadPageCopyWith<$Res>  {
  factory $ThreadPersistenceReadPageCopyWith(ThreadPersistenceReadPage value, $Res Function(ThreadPersistenceReadPage) _then) = _$ThreadPersistenceReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<ThreadPersistenceRead> items, int? nextOffset
});




}
/// @nodoc
class _$ThreadPersistenceReadPageCopyWithImpl<$Res>
    implements $ThreadPersistenceReadPageCopyWith<$Res> {
  _$ThreadPersistenceReadPageCopyWithImpl(this._self, this._then);

  final ThreadPersistenceReadPage _self;
  final $Res Function(ThreadPersistenceReadPage) _then;

/// Create a copy of ThreadPersistenceReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(ThreadPersistenceReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ThreadPersistenceRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadPersistenceReadPage].
extension ThreadPersistenceReadPagePatterns on ThreadPersistenceReadPage {
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
