// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_identity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadFacetStamp {

 String get runtimeEpoch; int get incarnation; ThreadFacet get facet; int get revision;
/// Create a copy of ThreadFacetStamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<ThreadFacetStamp> get copyWith => _$ThreadFacetStampCopyWithImpl<ThreadFacetStamp>(this as ThreadFacetStamp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadFacetStamp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadFacetStamp&&(identical(other.runtimeEpoch, _this.runtimeEpoch) || other.runtimeEpoch == _this.runtimeEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.facet, _this.facet) || other.facet == _this.facet)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ThreadFacetStamp;
  return Object.hash(runtimeType,_this.runtimeEpoch,_this.incarnation,_this.facet,_this.revision);
}

@override
String toString() {
  final _this = this as ThreadFacetStamp;
  return 'ThreadFacetStamp(runtimeEpoch: ${_this.runtimeEpoch}, incarnation: ${_this.incarnation}, facet: ${_this.facet}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ThreadFacetStampCopyWith<$Res>  {
  factory $ThreadFacetStampCopyWith(ThreadFacetStamp value, $Res Function(ThreadFacetStamp) _then) = _$ThreadFacetStampCopyWithImpl;
@useResult
$Res call({
 String runtimeEpoch, int incarnation, ThreadFacet facet, int revision
});




}
/// @nodoc
class _$ThreadFacetStampCopyWithImpl<$Res>
    implements $ThreadFacetStampCopyWith<$Res> {
  _$ThreadFacetStampCopyWithImpl(this._self, this._then);

  final ThreadFacetStamp _self;
  final $Res Function(ThreadFacetStamp) _then;

/// Create a copy of ThreadFacetStamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? runtimeEpoch = null,Object? incarnation = null,Object? facet = null,Object? revision = null,}) {
  return _then(ThreadFacetStamp(
runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,facet: null == facet ? _self.facet : facet // ignore: cast_nullable_to_non_nullable
as ThreadFacet,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadFacetStamp].
extension ThreadFacetStampPatterns on ThreadFacetStamp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadFacetStamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadFacetStamp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadFacetStamp value)  $default,){
final _that = this;
switch (_that) {
case _ThreadFacetStamp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadFacetStamp value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadFacetStamp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String runtimeEpoch,  int incarnation,  ThreadFacet facet,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadFacetStamp() when $default != null:
return $default(_that.runtimeEpoch,_that.incarnation,_that.facet,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String runtimeEpoch,  int incarnation,  ThreadFacet facet,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ThreadFacetStamp():
return $default(_that.runtimeEpoch,_that.incarnation,_that.facet,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String runtimeEpoch,  int incarnation,  ThreadFacet facet,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ThreadFacetStamp() when $default != null:
return $default(_that.runtimeEpoch,_that.incarnation,_that.facet,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadFacetStamp implements ThreadFacetStamp {
  const _ThreadFacetStamp({required this.runtimeEpoch, required this.incarnation, required this.facet, required this.revision});


@override final  String runtimeEpoch;
@override final  int incarnation;
@override final  ThreadFacet facet;
@override final  int revision;

/// Create a copy of ThreadFacetStamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadFacetStampCopyWith<_ThreadFacetStamp> get copyWith => __$ThreadFacetStampCopyWithImpl<_ThreadFacetStamp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadFacetStamp&&(identical(other.runtimeEpoch, runtimeEpoch) || other.runtimeEpoch == runtimeEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.facet, facet) || other.facet == facet)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,runtimeEpoch,incarnation,facet,revision);
}

@override
String toString() {
    return 'ThreadFacetStamp(runtimeEpoch: $runtimeEpoch, incarnation: $incarnation, facet: $facet, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ThreadFacetStampCopyWith<$Res> implements $ThreadFacetStampCopyWith<$Res> {
  factory _$ThreadFacetStampCopyWith(_ThreadFacetStamp value, $Res Function(_ThreadFacetStamp) _then) = __$ThreadFacetStampCopyWithImpl;
@override @useResult
$Res call({
 String runtimeEpoch, int incarnation, ThreadFacet facet, int revision
});




}
/// @nodoc
class __$ThreadFacetStampCopyWithImpl<$Res>
    implements _$ThreadFacetStampCopyWith<$Res> {
  __$ThreadFacetStampCopyWithImpl(this._self, this._then);

  final _ThreadFacetStamp _self;
  final $Res Function(_ThreadFacetStamp) _then;

/// Create a copy of ThreadFacetStamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? runtimeEpoch = null,Object? incarnation = null,Object? facet = null,Object? revision = null,}) {
  return _then(_ThreadFacetStamp(
runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,facet: null == facet ? _self.facet : facet // ignore: cast_nullable_to_non_nullable
as ThreadFacet,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadFeedIdentity {

 String get feedId; String get runtimeEpoch; int get incarnation; ThreadFacet get facet; ThreadObservationMode get mode;
/// Create a copy of ThreadFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<ThreadFeedIdentity> get copyWith => _$ThreadFeedIdentityCopyWithImpl<ThreadFeedIdentity>(this as ThreadFeedIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadFeedIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadFeedIdentity&&(identical(other.feedId, _this.feedId) || other.feedId == _this.feedId)&&(identical(other.runtimeEpoch, _this.runtimeEpoch) || other.runtimeEpoch == _this.runtimeEpoch)&&(identical(other.incarnation, _this.incarnation) || other.incarnation == _this.incarnation)&&(identical(other.facet, _this.facet) || other.facet == _this.facet)&&(identical(other.mode, _this.mode) || other.mode == _this.mode));
}


@override
int get hashCode {
  final _this = this as ThreadFeedIdentity;
  return Object.hash(runtimeType,_this.feedId,_this.runtimeEpoch,_this.incarnation,_this.facet,_this.mode);
}

@override
String toString() {
  final _this = this as ThreadFeedIdentity;
  return 'ThreadFeedIdentity(feedId: ${_this.feedId}, runtimeEpoch: ${_this.runtimeEpoch}, incarnation: ${_this.incarnation}, facet: ${_this.facet}, mode: ${_this.mode})';
}


}

/// @nodoc
abstract mixin class $ThreadFeedIdentityCopyWith<$Res>  {
  factory $ThreadFeedIdentityCopyWith(ThreadFeedIdentity value, $Res Function(ThreadFeedIdentity) _then) = _$ThreadFeedIdentityCopyWithImpl;
@useResult
$Res call({
 String feedId, String runtimeEpoch, int incarnation, ThreadFacet facet, ThreadObservationMode mode
});




}
/// @nodoc
class _$ThreadFeedIdentityCopyWithImpl<$Res>
    implements $ThreadFeedIdentityCopyWith<$Res> {
  _$ThreadFeedIdentityCopyWithImpl(this._self, this._then);

  final ThreadFeedIdentity _self;
  final $Res Function(ThreadFeedIdentity) _then;

/// Create a copy of ThreadFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? feedId = null,Object? runtimeEpoch = null,Object? incarnation = null,Object? facet = null,Object? mode = null,}) {
  return _then(ThreadFeedIdentity(
feedId: null == feedId ? _self.feedId : feedId // ignore: cast_nullable_to_non_nullable
as String,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,facet: null == facet ? _self.facet : facet // ignore: cast_nullable_to_non_nullable
as ThreadFacet,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadObservationMode,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadFeedIdentity].
extension ThreadFeedIdentityPatterns on ThreadFeedIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadFeedIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadFeedIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadFeedIdentity value)  $default,){
final _that = this;
switch (_that) {
case _ThreadFeedIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadFeedIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadFeedIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String feedId,  String runtimeEpoch,  int incarnation,  ThreadFacet facet,  ThreadObservationMode mode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadFeedIdentity() when $default != null:
return $default(_that.feedId,_that.runtimeEpoch,_that.incarnation,_that.facet,_that.mode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String feedId,  String runtimeEpoch,  int incarnation,  ThreadFacet facet,  ThreadObservationMode mode)  $default,) {final _that = this;
switch (_that) {
case _ThreadFeedIdentity():
return $default(_that.feedId,_that.runtimeEpoch,_that.incarnation,_that.facet,_that.mode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String feedId,  String runtimeEpoch,  int incarnation,  ThreadFacet facet,  ThreadObservationMode mode)?  $default,) {final _that = this;
switch (_that) {
case _ThreadFeedIdentity() when $default != null:
return $default(_that.feedId,_that.runtimeEpoch,_that.incarnation,_that.facet,_that.mode);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadFeedIdentity implements ThreadFeedIdentity {
  const _ThreadFeedIdentity({required this.feedId, required this.runtimeEpoch, required this.incarnation, required this.facet, required this.mode});


@override final  String feedId;
@override final  String runtimeEpoch;
@override final  int incarnation;
@override final  ThreadFacet facet;
@override final  ThreadObservationMode mode;

/// Create a copy of ThreadFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadFeedIdentityCopyWith<_ThreadFeedIdentity> get copyWith => __$ThreadFeedIdentityCopyWithImpl<_ThreadFeedIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadFeedIdentity&&(identical(other.feedId, feedId) || other.feedId == feedId)&&(identical(other.runtimeEpoch, runtimeEpoch) || other.runtimeEpoch == runtimeEpoch)&&(identical(other.incarnation, incarnation) || other.incarnation == incarnation)&&(identical(other.facet, facet) || other.facet == facet)&&(identical(other.mode, mode) || other.mode == mode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,feedId,runtimeEpoch,incarnation,facet,mode);
}

@override
String toString() {
    return 'ThreadFeedIdentity(feedId: $feedId, runtimeEpoch: $runtimeEpoch, incarnation: $incarnation, facet: $facet, mode: $mode)';
}


}

/// @nodoc
abstract mixin class _$ThreadFeedIdentityCopyWith<$Res> implements $ThreadFeedIdentityCopyWith<$Res> {
  factory _$ThreadFeedIdentityCopyWith(_ThreadFeedIdentity value, $Res Function(_ThreadFeedIdentity) _then) = __$ThreadFeedIdentityCopyWithImpl;
@override @useResult
$Res call({
 String feedId, String runtimeEpoch, int incarnation, ThreadFacet facet, ThreadObservationMode mode
});




}
/// @nodoc
class __$ThreadFeedIdentityCopyWithImpl<$Res>
    implements _$ThreadFeedIdentityCopyWith<$Res> {
  __$ThreadFeedIdentityCopyWithImpl(this._self, this._then);

  final _ThreadFeedIdentity _self;
  final $Res Function(_ThreadFeedIdentity) _then;

/// Create a copy of ThreadFeedIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? feedId = null,Object? runtimeEpoch = null,Object? incarnation = null,Object? facet = null,Object? mode = null,}) {
  return _then(_ThreadFeedIdentity(
feedId: null == feedId ? _self.feedId : feedId // ignore: cast_nullable_to_non_nullable
as String,runtimeEpoch: null == runtimeEpoch ? _self.runtimeEpoch : runtimeEpoch // ignore: cast_nullable_to_non_nullable
as String,incarnation: null == incarnation ? _self.incarnation : incarnation // ignore: cast_nullable_to_non_nullable
as int,facet: null == facet ? _self.facet : facet // ignore: cast_nullable_to_non_nullable
as ThreadFacet,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadObservationMode,
  ));
}


}

/// @nodoc
mixin _$TurnReadRef {

 int get entry; int get revision;
/// Create a copy of TurnReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnReadRefCopyWith<TurnReadRef> get copyWith => _$TurnReadRefCopyWithImpl<TurnReadRef>(this as TurnReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TurnReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as TurnReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as TurnReadRef;
  return 'TurnReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $TurnReadRefCopyWith<$Res>  {
  factory $TurnReadRefCopyWith(TurnReadRef value, $Res Function(TurnReadRef) _then) = _$TurnReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$TurnReadRefCopyWithImpl<$Res>
    implements $TurnReadRefCopyWith<$Res> {
  _$TurnReadRefCopyWithImpl(this._self, this._then);

  final TurnReadRef _self;
  final $Res Function(TurnReadRef) _then;

/// Create a copy of TurnReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(TurnReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [TurnReadRef].
extension TurnReadRefPatterns on TurnReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnReadRef value)  $default,){
final _that = this;
switch (_that) {
case _TurnReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _TurnReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _TurnReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _TurnReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _TurnReadRef implements TurnReadRef {
  const _TurnReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of TurnReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnReadRefCopyWith<_TurnReadRef> get copyWith => __$TurnReadRefCopyWithImpl<_TurnReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'TurnReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$TurnReadRefCopyWith<$Res> implements $TurnReadRefCopyWith<$Res> {
  factory _$TurnReadRefCopyWith(_TurnReadRef value, $Res Function(_TurnReadRef) _then) = __$TurnReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$TurnReadRefCopyWithImpl<$Res>
    implements _$TurnReadRefCopyWith<$Res> {
  __$TurnReadRefCopyWithImpl(this._self, this._then);

  final _TurnReadRef _self;
  final $Res Function(_TurnReadRef) _then;

/// Create a copy of TurnReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_TurnReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$InteractionReadRef {

 int get entry; int get revision;
/// Create a copy of InteractionReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionReadRefCopyWith<InteractionReadRef> get copyWith => _$InteractionReadRefCopyWithImpl<InteractionReadRef>(this as InteractionReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as InteractionReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as InteractionReadRef;
  return 'InteractionReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $InteractionReadRefCopyWith<$Res>  {
  factory $InteractionReadRefCopyWith(InteractionReadRef value, $Res Function(InteractionReadRef) _then) = _$InteractionReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$InteractionReadRefCopyWithImpl<$Res>
    implements $InteractionReadRefCopyWith<$Res> {
  _$InteractionReadRefCopyWithImpl(this._self, this._then);

  final InteractionReadRef _self;
  final $Res Function(InteractionReadRef) _then;

/// Create a copy of InteractionReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(InteractionReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [InteractionReadRef].
extension InteractionReadRefPatterns on InteractionReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionReadRef value)  $default,){
final _that = this;
switch (_that) {
case _InteractionReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _InteractionReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _InteractionReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionReadRef implements InteractionReadRef {
  const _InteractionReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of InteractionReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionReadRefCopyWith<_InteractionReadRef> get copyWith => __$InteractionReadRefCopyWithImpl<_InteractionReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'InteractionReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$InteractionReadRefCopyWith<$Res> implements $InteractionReadRefCopyWith<$Res> {
  factory _$InteractionReadRefCopyWith(_InteractionReadRef value, $Res Function(_InteractionReadRef) _then) = __$InteractionReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$InteractionReadRefCopyWithImpl<$Res>
    implements _$InteractionReadRefCopyWith<$Res> {
  __$InteractionReadRefCopyWithImpl(this._self, this._then);

  final _InteractionReadRef _self;
  final $Res Function(_InteractionReadRef) _then;

/// Create a copy of InteractionReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_InteractionReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$InteractionIndexRef {

 int get entry; int get revision;
/// Create a copy of InteractionIndexRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionIndexRefCopyWith<InteractionIndexRef> get copyWith => _$InteractionIndexRefCopyWithImpl<InteractionIndexRef>(this as InteractionIndexRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionIndexRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionIndexRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as InteractionIndexRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as InteractionIndexRef;
  return 'InteractionIndexRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $InteractionIndexRefCopyWith<$Res>  {
  factory $InteractionIndexRefCopyWith(InteractionIndexRef value, $Res Function(InteractionIndexRef) _then) = _$InteractionIndexRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$InteractionIndexRefCopyWithImpl<$Res>
    implements $InteractionIndexRefCopyWith<$Res> {
  _$InteractionIndexRefCopyWithImpl(this._self, this._then);

  final InteractionIndexRef _self;
  final $Res Function(InteractionIndexRef) _then;

/// Create a copy of InteractionIndexRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(InteractionIndexRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [InteractionIndexRef].
extension InteractionIndexRefPatterns on InteractionIndexRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionIndexRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionIndexRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionIndexRef value)  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionIndexRef value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionIndexRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionIndexRef implements InteractionIndexRef {
  const _InteractionIndexRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of InteractionIndexRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionIndexRefCopyWith<_InteractionIndexRef> get copyWith => __$InteractionIndexRefCopyWithImpl<_InteractionIndexRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionIndexRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'InteractionIndexRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$InteractionIndexRefCopyWith<$Res> implements $InteractionIndexRefCopyWith<$Res> {
  factory _$InteractionIndexRefCopyWith(_InteractionIndexRef value, $Res Function(_InteractionIndexRef) _then) = __$InteractionIndexRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$InteractionIndexRefCopyWithImpl<$Res>
    implements _$InteractionIndexRefCopyWith<$Res> {
  __$InteractionIndexRefCopyWithImpl(this._self, this._then);

  final _InteractionIndexRef _self;
  final $Res Function(_InteractionIndexRef) _then;

/// Create a copy of InteractionIndexRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_InteractionIndexRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ActivityReadRef {

 int get entry; int get revision;
/// Create a copy of ActivityReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityReadRefCopyWith<ActivityReadRef> get copyWith => _$ActivityReadRefCopyWithImpl<ActivityReadRef>(this as ActivityReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ActivityReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ActivityReadRef;
  return 'ActivityReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ActivityReadRefCopyWith<$Res>  {
  factory $ActivityReadRefCopyWith(ActivityReadRef value, $Res Function(ActivityReadRef) _then) = _$ActivityReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ActivityReadRefCopyWithImpl<$Res>
    implements $ActivityReadRefCopyWith<$Res> {
  _$ActivityReadRefCopyWithImpl(this._self, this._then);

  final ActivityReadRef _self;
  final $Res Function(ActivityReadRef) _then;

/// Create a copy of ActivityReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ActivityReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ActivityReadRef].
extension ActivityReadRefPatterns on ActivityReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivityReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivityReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ActivityReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivityReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ActivityReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ActivityReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ActivityReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityReadRef implements ActivityReadRef {
  const _ActivityReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ActivityReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityReadRefCopyWith<_ActivityReadRef> get copyWith => __$ActivityReadRefCopyWithImpl<_ActivityReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ActivityReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ActivityReadRefCopyWith<$Res> implements $ActivityReadRefCopyWith<$Res> {
  factory _$ActivityReadRefCopyWith(_ActivityReadRef value, $Res Function(_ActivityReadRef) _then) = __$ActivityReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ActivityReadRefCopyWithImpl<$Res>
    implements _$ActivityReadRefCopyWith<$Res> {
  __$ActivityReadRefCopyWithImpl(this._self, this._then);

  final _ActivityReadRef _self;
  final $Res Function(_ActivityReadRef) _then;

/// Create a copy of ActivityReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ActivityReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$StorageReadRef {

 int get entry; int get revision;
/// Create a copy of StorageReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StorageReadRefCopyWith<StorageReadRef> get copyWith => _$StorageReadRefCopyWithImpl<StorageReadRef>(this as StorageReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StorageReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StorageReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as StorageReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as StorageReadRef;
  return 'StorageReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $StorageReadRefCopyWith<$Res>  {
  factory $StorageReadRefCopyWith(StorageReadRef value, $Res Function(StorageReadRef) _then) = _$StorageReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$StorageReadRefCopyWithImpl<$Res>
    implements $StorageReadRefCopyWith<$Res> {
  _$StorageReadRefCopyWithImpl(this._self, this._then);

  final StorageReadRef _self;
  final $Res Function(StorageReadRef) _then;

/// Create a copy of StorageReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(StorageReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [StorageReadRef].
extension StorageReadRefPatterns on StorageReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StorageReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StorageReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StorageReadRef value)  $default,){
final _that = this;
switch (_that) {
case _StorageReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StorageReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _StorageReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StorageReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _StorageReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _StorageReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _StorageReadRef implements StorageReadRef {
  const _StorageReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of StorageReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StorageReadRefCopyWith<_StorageReadRef> get copyWith => __$StorageReadRefCopyWithImpl<_StorageReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StorageReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'StorageReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$StorageReadRefCopyWith<$Res> implements $StorageReadRefCopyWith<$Res> {
  factory _$StorageReadRefCopyWith(_StorageReadRef value, $Res Function(_StorageReadRef) _then) = __$StorageReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$StorageReadRefCopyWithImpl<$Res>
    implements _$StorageReadRefCopyWith<$Res> {
  __$StorageReadRefCopyWithImpl(this._self, this._then);

  final _StorageReadRef _self;
  final $Res Function(_StorageReadRef) _then;

/// Create a copy of StorageReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_StorageReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$MetricsIdentityRef {

 int get entry;
/// Create a copy of MetricsIdentityRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MetricsIdentityRefCopyWith<MetricsIdentityRef> get copyWith => _$MetricsIdentityRefCopyWithImpl<MetricsIdentityRef>(this as MetricsIdentityRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as MetricsIdentityRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MetricsIdentityRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry));
}


@override
int get hashCode {
  final _this = this as MetricsIdentityRef;
  return Object.hash(runtimeType,_this.entry);
}

@override
String toString() {
  final _this = this as MetricsIdentityRef;
  return 'MetricsIdentityRef(entry: ${_this.entry})';
}


}

/// @nodoc
abstract mixin class $MetricsIdentityRefCopyWith<$Res>  {
  factory $MetricsIdentityRefCopyWith(MetricsIdentityRef value, $Res Function(MetricsIdentityRef) _then) = _$MetricsIdentityRefCopyWithImpl;
@useResult
$Res call({
 int entry
});




}
/// @nodoc
class _$MetricsIdentityRefCopyWithImpl<$Res>
    implements $MetricsIdentityRefCopyWith<$Res> {
  _$MetricsIdentityRefCopyWithImpl(this._self, this._then);

  final MetricsIdentityRef _self;
  final $Res Function(MetricsIdentityRef) _then;

/// Create a copy of MetricsIdentityRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,}) {
  return _then(MetricsIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [MetricsIdentityRef].
extension MetricsIdentityRefPatterns on MetricsIdentityRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MetricsIdentityRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MetricsIdentityRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MetricsIdentityRef value)  $default,){
final _that = this;
switch (_that) {
case _MetricsIdentityRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MetricsIdentityRef value)?  $default,){
final _that = this;
switch (_that) {
case _MetricsIdentityRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MetricsIdentityRef() when $default != null:
return $default(_that.entry);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry)  $default,) {final _that = this;
switch (_that) {
case _MetricsIdentityRef():
return $default(_that.entry);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry)?  $default,) {final _that = this;
switch (_that) {
case _MetricsIdentityRef() when $default != null:
return $default(_that.entry);case _:
  return null;

}
}

}

/// @nodoc


class _MetricsIdentityRef implements MetricsIdentityRef {
  const _MetricsIdentityRef({required this.entry});


@override final  int entry;

/// Create a copy of MetricsIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MetricsIdentityRefCopyWith<_MetricsIdentityRef> get copyWith => __$MetricsIdentityRefCopyWithImpl<_MetricsIdentityRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _MetricsIdentityRef&&(identical(other.entry, entry) || other.entry == entry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry);
}

@override
String toString() {
    return 'MetricsIdentityRef(entry: $entry)';
}


}

/// @nodoc
abstract mixin class _$MetricsIdentityRefCopyWith<$Res> implements $MetricsIdentityRefCopyWith<$Res> {
  factory _$MetricsIdentityRefCopyWith(_MetricsIdentityRef value, $Res Function(_MetricsIdentityRef) _then) = __$MetricsIdentityRefCopyWithImpl;
@override @useResult
$Res call({
 int entry
});




}
/// @nodoc
class __$MetricsIdentityRefCopyWithImpl<$Res>
    implements _$MetricsIdentityRefCopyWith<$Res> {
  __$MetricsIdentityRefCopyWithImpl(this._self, this._then);

  final _MetricsIdentityRef _self;
  final $Res Function(_MetricsIdentityRef) _then;

/// Create a copy of MetricsIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,}) {
  return _then(_MetricsIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ContextReadRef {

 int get entry; int get revision;
/// Create a copy of ContextReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContextReadRefCopyWith<ContextReadRef> get copyWith => _$ContextReadRefCopyWithImpl<ContextReadRef>(this as ContextReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContextReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContextReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ContextReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ContextReadRef;
  return 'ContextReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ContextReadRefCopyWith<$Res>  {
  factory $ContextReadRefCopyWith(ContextReadRef value, $Res Function(ContextReadRef) _then) = _$ContextReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ContextReadRefCopyWithImpl<$Res>
    implements $ContextReadRefCopyWith<$Res> {
  _$ContextReadRefCopyWithImpl(this._self, this._then);

  final ContextReadRef _self;
  final $Res Function(ContextReadRef) _then;

/// Create a copy of ContextReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ContextReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ContextReadRef].
extension ContextReadRefPatterns on ContextReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContextReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContextReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContextReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ContextReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContextReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ContextReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContextReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ContextReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ContextReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ContextReadRef implements ContextReadRef {
  const _ContextReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ContextReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContextReadRefCopyWith<_ContextReadRef> get copyWith => __$ContextReadRefCopyWithImpl<_ContextReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContextReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ContextReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ContextReadRefCopyWith<$Res> implements $ContextReadRefCopyWith<$Res> {
  factory _$ContextReadRefCopyWith(_ContextReadRef value, $Res Function(_ContextReadRef) _then) = __$ContextReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ContextReadRefCopyWithImpl<$Res>
    implements _$ContextReadRefCopyWith<$Res> {
  __$ContextReadRefCopyWithImpl(this._self, this._then);

  final _ContextReadRef _self;
  final $Res Function(_ContextReadRef) _then;

/// Create a copy of ContextReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ContextReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadConfigurationReadRef {

 int get entry; int get revision;
/// Create a copy of ThreadConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationReadRefCopyWith<ThreadConfigurationReadRef> get copyWith => _$ThreadConfigurationReadRefCopyWithImpl<ThreadConfigurationReadRef>(this as ThreadConfigurationReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadConfigurationReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ThreadConfigurationReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ThreadConfigurationReadRef;
  return 'ThreadConfigurationReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ThreadConfigurationReadRefCopyWith<$Res>  {
  factory $ThreadConfigurationReadRefCopyWith(ThreadConfigurationReadRef value, $Res Function(ThreadConfigurationReadRef) _then) = _$ThreadConfigurationReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ThreadConfigurationReadRefCopyWithImpl<$Res>
    implements $ThreadConfigurationReadRefCopyWith<$Res> {
  _$ThreadConfigurationReadRefCopyWithImpl(this._self, this._then);

  final ThreadConfigurationReadRef _self;
  final $Res Function(ThreadConfigurationReadRef) _then;

/// Create a copy of ThreadConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ThreadConfigurationReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadConfigurationReadRef].
extension ThreadConfigurationReadRefPatterns on ThreadConfigurationReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadConfigurationReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadConfigurationReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadConfigurationReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadConfigurationReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadConfigurationReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadConfigurationReadRef implements ThreadConfigurationReadRef {
  const _ThreadConfigurationReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ThreadConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadConfigurationReadRefCopyWith<_ThreadConfigurationReadRef> get copyWith => __$ThreadConfigurationReadRefCopyWithImpl<_ThreadConfigurationReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadConfigurationReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ThreadConfigurationReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ThreadConfigurationReadRefCopyWith<$Res> implements $ThreadConfigurationReadRefCopyWith<$Res> {
  factory _$ThreadConfigurationReadRefCopyWith(_ThreadConfigurationReadRef value, $Res Function(_ThreadConfigurationReadRef) _then) = __$ThreadConfigurationReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ThreadConfigurationReadRefCopyWithImpl<$Res>
    implements _$ThreadConfigurationReadRefCopyWith<$Res> {
  __$ThreadConfigurationReadRefCopyWithImpl(this._self, this._then);

  final _ThreadConfigurationReadRef _self;
  final $Res Function(_ThreadConfigurationReadRef) _then;

/// Create a copy of ThreadConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ThreadConfigurationReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$TodoReadRef {

 int get entry; int get revision;
/// Create a copy of TodoReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TodoReadRefCopyWith<TodoReadRef> get copyWith => _$TodoReadRefCopyWithImpl<TodoReadRef>(this as TodoReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TodoReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as TodoReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as TodoReadRef;
  return 'TodoReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $TodoReadRefCopyWith<$Res>  {
  factory $TodoReadRefCopyWith(TodoReadRef value, $Res Function(TodoReadRef) _then) = _$TodoReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$TodoReadRefCopyWithImpl<$Res>
    implements $TodoReadRefCopyWith<$Res> {
  _$TodoReadRefCopyWithImpl(this._self, this._then);

  final TodoReadRef _self;
  final $Res Function(TodoReadRef) _then;

/// Create a copy of TodoReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(TodoReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [TodoReadRef].
extension TodoReadRefPatterns on TodoReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TodoReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TodoReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TodoReadRef value)  $default,){
final _that = this;
switch (_that) {
case _TodoReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TodoReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _TodoReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TodoReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _TodoReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _TodoReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _TodoReadRef implements TodoReadRef {
  const _TodoReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of TodoReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TodoReadRefCopyWith<_TodoReadRef> get copyWith => __$TodoReadRefCopyWithImpl<_TodoReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TodoReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'TodoReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$TodoReadRefCopyWith<$Res> implements $TodoReadRefCopyWith<$Res> {
  factory _$TodoReadRefCopyWith(_TodoReadRef value, $Res Function(_TodoReadRef) _then) = __$TodoReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$TodoReadRefCopyWithImpl<$Res>
    implements _$TodoReadRefCopyWith<$Res> {
  __$TodoReadRefCopyWithImpl(this._self, this._then);

  final _TodoReadRef _self;
  final $Res Function(_TodoReadRef) _then;

/// Create a copy of TodoReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_TodoReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WorkflowReadRef {

 int get entry; int get revision;
/// Create a copy of WorkflowReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WorkflowReadRefCopyWith<WorkflowReadRef> get copyWith => _$WorkflowReadRefCopyWithImpl<WorkflowReadRef>(this as WorkflowReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WorkflowReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WorkflowReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as WorkflowReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as WorkflowReadRef;
  return 'WorkflowReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $WorkflowReadRefCopyWith<$Res>  {
  factory $WorkflowReadRefCopyWith(WorkflowReadRef value, $Res Function(WorkflowReadRef) _then) = _$WorkflowReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$WorkflowReadRefCopyWithImpl<$Res>
    implements $WorkflowReadRefCopyWith<$Res> {
  _$WorkflowReadRefCopyWithImpl(this._self, this._then);

  final WorkflowReadRef _self;
  final $Res Function(WorkflowReadRef) _then;

/// Create a copy of WorkflowReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(WorkflowReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [WorkflowReadRef].
extension WorkflowReadRefPatterns on WorkflowReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WorkflowReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WorkflowReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WorkflowReadRef value)  $default,){
final _that = this;
switch (_that) {
case _WorkflowReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WorkflowReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _WorkflowReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WorkflowReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _WorkflowReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _WorkflowReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _WorkflowReadRef implements WorkflowReadRef {
  const _WorkflowReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of WorkflowReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WorkflowReadRefCopyWith<_WorkflowReadRef> get copyWith => __$WorkflowReadRefCopyWithImpl<_WorkflowReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WorkflowReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'WorkflowReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$WorkflowReadRefCopyWith<$Res> implements $WorkflowReadRefCopyWith<$Res> {
  factory _$WorkflowReadRefCopyWith(_WorkflowReadRef value, $Res Function(_WorkflowReadRef) _then) = __$WorkflowReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$WorkflowReadRefCopyWithImpl<$Res>
    implements _$WorkflowReadRefCopyWith<$Res> {
  __$WorkflowReadRefCopyWithImpl(this._self, this._then);

  final _WorkflowReadRef _self;
  final $Res Function(_WorkflowReadRef) _then;

/// Create a copy of WorkflowReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_WorkflowReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
