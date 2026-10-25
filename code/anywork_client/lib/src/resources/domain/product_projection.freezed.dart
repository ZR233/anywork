// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product_projection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ResourceSyncState {

 ResourceSyncPhase get phase; StudioFailure? get error; bool get retryExhausted;
/// Create a copy of ResourceSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResourceSyncStateCopyWith<ResourceSyncState> get copyWith => _$ResourceSyncStateCopyWithImpl<ResourceSyncState>(this as ResourceSyncState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ResourceSyncState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResourceSyncState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.retryExhausted, _this.retryExhausted) || other.retryExhausted == _this.retryExhausted));
}


@override
int get hashCode {
  final _this = this as ResourceSyncState;
  return Object.hash(runtimeType,_this.phase,_this.error,_this.retryExhausted);
}



}

/// @nodoc
abstract mixin class $ResourceSyncStateCopyWith<$Res>  {
  factory $ResourceSyncStateCopyWith(ResourceSyncState value, $Res Function(ResourceSyncState) _then) = _$ResourceSyncStateCopyWithImpl;
@useResult
$Res call({
 ResourceSyncPhase phase, StudioFailure? error, bool retryExhausted
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$ResourceSyncStateCopyWithImpl<$Res>
    implements $ResourceSyncStateCopyWith<$Res> {
  _$ResourceSyncStateCopyWithImpl(this._self, this._then);

  final ResourceSyncState _self;
  final $Res Function(ResourceSyncState) _then;

/// Create a copy of ResourceSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? error = freezed,Object? retryExhausted = null,}) {
  return _then(ResourceSyncState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ResourceSyncPhase,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,retryExhausted: null == retryExhausted ? _self.retryExhausted : retryExhausted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ResourceSyncState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [ResourceSyncState].
extension ResourceSyncStatePatterns on ResourceSyncState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ResourceSyncState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ResourceSyncState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ResourceSyncState value)  $default,){
final _that = this;
switch (_that) {
case _ResourceSyncState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ResourceSyncState value)?  $default,){
final _that = this;
switch (_that) {
case _ResourceSyncState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ResourceSyncPhase phase,  StudioFailure? error,  bool retryExhausted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ResourceSyncState() when $default != null:
return $default(_that.phase,_that.error,_that.retryExhausted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ResourceSyncPhase phase,  StudioFailure? error,  bool retryExhausted)  $default,) {final _that = this;
switch (_that) {
case _ResourceSyncState():
return $default(_that.phase,_that.error,_that.retryExhausted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ResourceSyncPhase phase,  StudioFailure? error,  bool retryExhausted)?  $default,) {final _that = this;
switch (_that) {
case _ResourceSyncState() when $default != null:
return $default(_that.phase,_that.error,_that.retryExhausted);case _:
  return null;

}
}

}

/// @nodoc


class _ResourceSyncState implements ResourceSyncState {
  const _ResourceSyncState({required this.phase, required this.error, required this.retryExhausted});


@override final  ResourceSyncPhase phase;
@override final  StudioFailure? error;
@override final  bool retryExhausted;

/// Create a copy of ResourceSyncState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ResourceSyncStateCopyWith<_ResourceSyncState> get copyWith => __$ResourceSyncStateCopyWithImpl<_ResourceSyncState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ResourceSyncState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.error, error) || other.error == error)&&(identical(other.retryExhausted, retryExhausted) || other.retryExhausted == retryExhausted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,error,retryExhausted);
}



}

/// @nodoc
abstract mixin class _$ResourceSyncStateCopyWith<$Res> implements $ResourceSyncStateCopyWith<$Res> {
  factory _$ResourceSyncStateCopyWith(_ResourceSyncState value, $Res Function(_ResourceSyncState) _then) = __$ResourceSyncStateCopyWithImpl;
@override @useResult
$Res call({
 ResourceSyncPhase phase, StudioFailure? error, bool retryExhausted
});


@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$ResourceSyncStateCopyWithImpl<$Res>
    implements _$ResourceSyncStateCopyWith<$Res> {
  __$ResourceSyncStateCopyWithImpl(this._self, this._then);

  final _ResourceSyncState _self;
  final $Res Function(_ResourceSyncState) _then;

/// Create a copy of ResourceSyncState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? error = freezed,Object? retryExhausted = null,}) {
  return _then(_ResourceSyncState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ResourceSyncPhase,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,retryExhausted: null == retryExhausted ? _self.retryExhausted : retryExhausted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ResourceSyncState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$ProductProjection<H> {

 ProductProjectionStamp? get stamp; H? get header; ResourceSyncState get sync;
/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<H, ProductProjection<H>> get copyWith => _$ProductProjectionCopyWithImpl<H, ProductProjection<H>>(this as ProductProjection<H>, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductProjection<H>;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductProjection<H>&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.header, _this.header)&&(identical(other.sync, _this.sync) || other.sync == _this.sync));
}


@override
int get hashCode {
  final _this = this as ProductProjection<H>;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.header),_this.sync);
}



}

/// @nodoc
abstract mixin class $ProductProjectionCopyWith<H,$Res>  {
  factory $ProductProjectionCopyWith(ProductProjection<H> value, $Res Function(ProductProjection<H>) _then) = _$ProductProjectionCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp? stamp, H? header, ResourceSyncState sync
});


$ProductProjectionStampCopyWith<$Res>? get stamp;$ResourceSyncStateCopyWith<$Res> get sync;

}
/// @nodoc
class _$ProductProjectionCopyWithImpl<H,$Res>
    implements $ProductProjectionCopyWith<H, $Res> {
  _$ProductProjectionCopyWithImpl(this._self, this._then);

  final ProductProjection<H> _self;
  final $Res Function(ProductProjection<H>) _then;

/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = freezed,Object? header = freezed,Object? sync = null,}) {
  return _then(ProductProjection(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as H?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as ResourceSyncState,
  ));
}
/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceSyncStateCopyWith<$Res> get sync {

  return $ResourceSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProductProjection].
extension ProductProjectionPatterns<H> on ProductProjection<H> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProductProjection<H> value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProductProjection() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProductProjection<H> value)  $default,){
final _that = this;
switch (_that) {
case _ProductProjection():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProductProjection<H> value)?  $default,){
final _that = this;
switch (_that) {
case _ProductProjection() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjectionStamp? stamp,  H? header,  ResourceSyncState sync)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProductProjection() when $default != null:
return $default(_that.stamp,_that.header,_that.sync);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjectionStamp? stamp,  H? header,  ResourceSyncState sync)  $default,) {final _that = this;
switch (_that) {
case _ProductProjection():
return $default(_that.stamp,_that.header,_that.sync);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjectionStamp? stamp,  H? header,  ResourceSyncState sync)?  $default,) {final _that = this;
switch (_that) {
case _ProductProjection() when $default != null:
return $default(_that.stamp,_that.header,_that.sync);case _:
  return null;

}
}

}

/// @nodoc


class _ProductProjection<H> implements ProductProjection<H> {
  const _ProductProjection({required this.stamp, required this.header, required this.sync});


@override final  ProductProjectionStamp? stamp;
@override final  H? header;
@override final  ResourceSyncState sync;

/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProductProjectionCopyWith<H, _ProductProjection<H>> get copyWith => __$ProductProjectionCopyWithImpl<H, _ProductProjection<H>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProductProjection<H>&&(identical(other.stamp, stamp) || other.stamp == stamp)&&const DeepCollectionEquality().equals(other.header, header)&&(identical(other.sync, sync) || other.sync == sync));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,const DeepCollectionEquality().hash(header),sync);
}



}

/// @nodoc
abstract mixin class _$ProductProjectionCopyWith<H,$Res> implements $ProductProjectionCopyWith<H, $Res> {
  factory _$ProductProjectionCopyWith(_ProductProjection<H> value, $Res Function(_ProductProjection<H>) _then) = __$ProductProjectionCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp? stamp, H? header, ResourceSyncState sync
});


@override $ProductProjectionStampCopyWith<$Res>? get stamp;@override $ResourceSyncStateCopyWith<$Res> get sync;

}
/// @nodoc
class __$ProductProjectionCopyWithImpl<H,$Res>
    implements _$ProductProjectionCopyWith<H, $Res> {
  __$ProductProjectionCopyWithImpl(this._self, this._then);

  final _ProductProjection<H> _self;
  final $Res Function(_ProductProjection<H>) _then;

/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = freezed,Object? header = freezed,Object? sync = null,}) {
  return _then(_ProductProjection<H>(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as H?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as ResourceSyncState,
  ));
}

/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ProductProjection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResourceSyncStateCopyWith<$Res> get sync {

  return $ResourceSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}
}

/// @nodoc
mixin _$Materialized<T,R> {

 ProductReadOrigin get origin; R get reference; T get value;
/// Create a copy of Materialized
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MaterializedCopyWith<T, R, Materialized<T, R>> get copyWith => _$MaterializedCopyWithImpl<T, R, Materialized<T, R>>(this as Materialized<T, R>, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Materialized<T, R>;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Materialized<T, R>&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&const DeepCollectionEquality().equals(other.reference, _this.reference)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as Materialized<T, R>;
  return Object.hash(runtimeType,_this.origin,const DeepCollectionEquality().hash(_this.reference),const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $MaterializedCopyWith<T,R,$Res>  {
  factory $MaterializedCopyWith(Materialized<T, R> value, $Res Function(Materialized<T, R>) _then) = _$MaterializedCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, R reference, T value
});


$ProductReadOriginCopyWith<$Res> get origin;

}
/// @nodoc
class _$MaterializedCopyWithImpl<T,R,$Res>
    implements $MaterializedCopyWith<T, R, $Res> {
  _$MaterializedCopyWithImpl(this._self, this._then);

  final Materialized<T, R> _self;
  final $Res Function(Materialized<T, R>) _then;

/// Create a copy of Materialized
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = freezed,Object? value = freezed,}) {
  return _then(Materialized(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as R,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}
/// Create a copy of Materialized
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}
}


/// Adds pattern-matching-related methods to [Materialized].
extension MaterializedPatterns<T,R> on Materialized<T, R> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Materialized<T, R> value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Materialized() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Materialized<T, R> value)  $default,){
final _that = this;
switch (_that) {
case _Materialized():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Materialized<T, R> value)?  $default,){
final _that = this;
switch (_that) {
case _Materialized() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  R reference,  T value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Materialized() when $default != null:
return $default(_that.origin,_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  R reference,  T value)  $default,) {final _that = this;
switch (_that) {
case _Materialized():
return $default(_that.origin,_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  R reference,  T value)?  $default,) {final _that = this;
switch (_that) {
case _Materialized() when $default != null:
return $default(_that.origin,_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _Materialized<T,R> implements Materialized<T, R> {
  const _Materialized({required this.origin, required this.reference, required this.value});


@override final  ProductReadOrigin origin;
@override final  R reference;
@override final  T value;

/// Create a copy of Materialized
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MaterializedCopyWith<T, R, _Materialized<T, R>> get copyWith => __$MaterializedCopyWithImpl<T, R, _Materialized<T, R>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Materialized<T, R>&&(identical(other.origin, origin) || other.origin == origin)&&const DeepCollectionEquality().equals(other.reference, reference)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,const DeepCollectionEquality().hash(reference),const DeepCollectionEquality().hash(value));
}



}

/// @nodoc
abstract mixin class _$MaterializedCopyWith<T,R,$Res> implements $MaterializedCopyWith<T, R, $Res> {
  factory _$MaterializedCopyWith(_Materialized<T, R> value, $Res Function(_Materialized<T, R>) _then) = __$MaterializedCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, R reference, T value
});


@override $ProductReadOriginCopyWith<$Res> get origin;

}
/// @nodoc
class __$MaterializedCopyWithImpl<T,R,$Res>
    implements _$MaterializedCopyWith<T, R, $Res> {
  __$MaterializedCopyWithImpl(this._self, this._then);

  final _Materialized<T, R> _self;
  final $Res Function(_Materialized<T, R>) _then;

/// Create a copy of Materialized
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = freezed,Object? value = freezed,}) {
  return _then(_Materialized<T, R>(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as R,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}

/// Create a copy of Materialized
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}
}

/// @nodoc
mixin _$ReadValue<T,R> {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadValue<T, R>);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ReadValueCopyWith<T,R,$Res>  {
$ReadValueCopyWith(ReadValue<T, R> _, $Res Function(ReadValue<T, R>) __);
}


/// Adds pattern-matching-related methods to [ReadValue].
extension ReadValuePatterns<T,R> on ReadValue<T, R> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnloadedReadValue<T, R> value)?  unloaded,TResult Function( LoadingReadValue<T, R> value)?  loading,TResult Function( ReadyReadValue<T, R> value)?  ready,TResult Function( FailedReadValue<T, R> value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnloadedReadValue() when unloaded != null:
return unloaded(_that);case LoadingReadValue() when loading != null:
return loading(_that);case ReadyReadValue() when ready != null:
return ready(_that);case FailedReadValue() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnloadedReadValue<T, R> value)  unloaded,required TResult Function( LoadingReadValue<T, R> value)  loading,required TResult Function( ReadyReadValue<T, R> value)  ready,required TResult Function( FailedReadValue<T, R> value)  failed,}){
final _that = this;
switch (_that) {
case UnloadedReadValue():
return unloaded(_that);case LoadingReadValue():
return loading(_that);case ReadyReadValue():
return ready(_that);case FailedReadValue():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnloadedReadValue<T, R> value)?  unloaded,TResult? Function( LoadingReadValue<T, R> value)?  loading,TResult? Function( ReadyReadValue<T, R> value)?  ready,TResult? Function( FailedReadValue<T, R> value)?  failed,}){
final _that = this;
switch (_that) {
case UnloadedReadValue() when unloaded != null:
return unloaded(_that);case LoadingReadValue() when loading != null:
return loading(_that);case ReadyReadValue() when ready != null:
return ready(_that);case FailedReadValue() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductReadOrigin origin,  R reference)?  unloaded,TResult Function( ProductReadOrigin origin,  R reference,  Materialized<T, R>? previous)?  loading,TResult Function( Materialized<T, R> current)?  ready,TResult Function( ProductReadOrigin origin,  R reference,  StudioFailure error,  Materialized<T, R>? previous)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnloadedReadValue() when unloaded != null:
return unloaded(_that.origin,_that.reference);case LoadingReadValue() when loading != null:
return loading(_that.origin,_that.reference,_that.previous);case ReadyReadValue() when ready != null:
return ready(_that.current);case FailedReadValue() when failed != null:
return failed(_that.origin,_that.reference,_that.error,_that.previous);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductReadOrigin origin,  R reference)  unloaded,required TResult Function( ProductReadOrigin origin,  R reference,  Materialized<T, R>? previous)  loading,required TResult Function( Materialized<T, R> current)  ready,required TResult Function( ProductReadOrigin origin,  R reference,  StudioFailure error,  Materialized<T, R>? previous)  failed,}) {final _that = this;
switch (_that) {
case UnloadedReadValue():
return unloaded(_that.origin,_that.reference);case LoadingReadValue():
return loading(_that.origin,_that.reference,_that.previous);case ReadyReadValue():
return ready(_that.current);case FailedReadValue():
return failed(_that.origin,_that.reference,_that.error,_that.previous);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductReadOrigin origin,  R reference)?  unloaded,TResult? Function( ProductReadOrigin origin,  R reference,  Materialized<T, R>? previous)?  loading,TResult? Function( Materialized<T, R> current)?  ready,TResult? Function( ProductReadOrigin origin,  R reference,  StudioFailure error,  Materialized<T, R>? previous)?  failed,}) {final _that = this;
switch (_that) {
case UnloadedReadValue() when unloaded != null:
return unloaded(_that.origin,_that.reference);case LoadingReadValue() when loading != null:
return loading(_that.origin,_that.reference,_that.previous);case ReadyReadValue() when ready != null:
return ready(_that.current);case FailedReadValue() when failed != null:
return failed(_that.origin,_that.reference,_that.error,_that.previous);case _:
  return null;

}
}

}

/// @nodoc


class UnloadedReadValue<T,R> implements ReadValue<T, R> {
  const UnloadedReadValue({required this.origin, required this.reference});


 final  ProductReadOrigin origin;
 final  R reference;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnloadedReadValueCopyWith<T, R, UnloadedReadValue<T, R>> get copyWith => _$UnloadedReadValueCopyWithImpl<T, R, UnloadedReadValue<T, R>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnloadedReadValue<T, R>&&(identical(other.origin, origin) || other.origin == origin)&&const DeepCollectionEquality().equals(other.reference, reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,const DeepCollectionEquality().hash(reference));
}



}

/// @nodoc
abstract mixin class $UnloadedReadValueCopyWith<T,R,$Res> implements $ReadValueCopyWith<T, R, $Res> {
  factory $UnloadedReadValueCopyWith(UnloadedReadValue<T, R> value, $Res Function(UnloadedReadValue<T, R>) _then) = _$UnloadedReadValueCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, R reference
});


$ProductReadOriginCopyWith<$Res> get origin;

}
/// @nodoc
class _$UnloadedReadValueCopyWithImpl<T,R,$Res>
    implements $UnloadedReadValueCopyWith<T, R, $Res> {
  _$UnloadedReadValueCopyWithImpl(this._self, this._then);

  final UnloadedReadValue<T, R> _self;
  final $Res Function(UnloadedReadValue<T, R>) _then;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = freezed,}) {
  return _then(UnloadedReadValue<T, R>(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as R,
  ));
}

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}
}

/// @nodoc


class LoadingReadValue<T,R> implements ReadValue<T, R> {
  const LoadingReadValue({required this.origin, required this.reference, required this.previous});


 final  ProductReadOrigin origin;
 final  R reference;
 final  Materialized<T, R>? previous;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadingReadValueCopyWith<T, R, LoadingReadValue<T, R>> get copyWith => _$LoadingReadValueCopyWithImpl<T, R, LoadingReadValue<T, R>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingReadValue<T, R>&&(identical(other.origin, origin) || other.origin == origin)&&const DeepCollectionEquality().equals(other.reference, reference)&&(identical(other.previous, previous) || other.previous == previous));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,const DeepCollectionEquality().hash(reference),previous);
}



}

/// @nodoc
abstract mixin class $LoadingReadValueCopyWith<T,R,$Res> implements $ReadValueCopyWith<T, R, $Res> {
  factory $LoadingReadValueCopyWith(LoadingReadValue<T, R> value, $Res Function(LoadingReadValue<T, R>) _then) = _$LoadingReadValueCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, R reference, Materialized<T, R>? previous
});


$ProductReadOriginCopyWith<$Res> get origin;$MaterializedCopyWith<T, R, $Res>? get previous;

}
/// @nodoc
class _$LoadingReadValueCopyWithImpl<T,R,$Res>
    implements $LoadingReadValueCopyWith<T, R, $Res> {
  _$LoadingReadValueCopyWithImpl(this._self, this._then);

  final LoadingReadValue<T, R> _self;
  final $Res Function(LoadingReadValue<T, R>) _then;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = freezed,Object? previous = freezed,}) {
  return _then(LoadingReadValue<T, R>(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as R,previous: freezed == previous ? _self.previous : previous // ignore: cast_nullable_to_non_nullable
as Materialized<T, R>?,
  ));
}

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MaterializedCopyWith<T, R, $Res>? get previous {
    if (_self.previous == null) {
    return null;
  }

  return $MaterializedCopyWith<T, R, $Res>(_self.previous!, (value) {
    return _then(_self.copyWith(previous: value));
  });
}
}

/// @nodoc


class ReadyReadValue<T,R> implements ReadValue<T, R> {
  const ReadyReadValue({required this.current});


 final  Materialized<T, R> current;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyReadValueCopyWith<T, R, ReadyReadValue<T, R>> get copyWith => _$ReadyReadValueCopyWithImpl<T, R, ReadyReadValue<T, R>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyReadValue<T, R>&&(identical(other.current, current) || other.current == current));
}


@override
int get hashCode {
    return Object.hash(runtimeType,current);
}



}

/// @nodoc
abstract mixin class $ReadyReadValueCopyWith<T,R,$Res> implements $ReadValueCopyWith<T, R, $Res> {
  factory $ReadyReadValueCopyWith(ReadyReadValue<T, R> value, $Res Function(ReadyReadValue<T, R>) _then) = _$ReadyReadValueCopyWithImpl;
@useResult
$Res call({
 Materialized<T, R> current
});


$MaterializedCopyWith<T, R, $Res> get current;

}
/// @nodoc
class _$ReadyReadValueCopyWithImpl<T,R,$Res>
    implements $ReadyReadValueCopyWith<T, R, $Res> {
  _$ReadyReadValueCopyWithImpl(this._self, this._then);

  final ReadyReadValue<T, R> _self;
  final $Res Function(ReadyReadValue<T, R>) _then;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? current = null,}) {
  return _then(ReadyReadValue<T, R>(
current: null == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as Materialized<T, R>,
  ));
}

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MaterializedCopyWith<T, R, $Res> get current {

  return $MaterializedCopyWith<T, R, $Res>(_self.current, (value) {
    return _then(_self.copyWith(current: value));
  });
}
}

/// @nodoc


class FailedReadValue<T,R> implements ReadValue<T, R> {
  const FailedReadValue({required this.origin, required this.reference, required this.error, required this.previous});


 final  ProductReadOrigin origin;
 final  R reference;
 final  StudioFailure error;
 final  Materialized<T, R>? previous;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedReadValueCopyWith<T, R, FailedReadValue<T, R>> get copyWith => _$FailedReadValueCopyWithImpl<T, R, FailedReadValue<T, R>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedReadValue<T, R>&&(identical(other.origin, origin) || other.origin == origin)&&const DeepCollectionEquality().equals(other.reference, reference)&&(identical(other.error, error) || other.error == error)&&(identical(other.previous, previous) || other.previous == previous));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,const DeepCollectionEquality().hash(reference),error,previous);
}



}

/// @nodoc
abstract mixin class $FailedReadValueCopyWith<T,R,$Res> implements $ReadValueCopyWith<T, R, $Res> {
  factory $FailedReadValueCopyWith(FailedReadValue<T, R> value, $Res Function(FailedReadValue<T, R>) _then) = _$FailedReadValueCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, R reference, StudioFailure error, Materialized<T, R>? previous
});


$ProductReadOriginCopyWith<$Res> get origin;$StudioFailureCopyWith<$Res> get error;$MaterializedCopyWith<T, R, $Res>? get previous;

}
/// @nodoc
class _$FailedReadValueCopyWithImpl<T,R,$Res>
    implements $FailedReadValueCopyWith<T, R, $Res> {
  _$FailedReadValueCopyWithImpl(this._self, this._then);

  final FailedReadValue<T, R> _self;
  final $Res Function(FailedReadValue<T, R>) _then;

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = freezed,Object? error = null,Object? previous = freezed,}) {
  return _then(FailedReadValue<T, R>(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as R,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,previous: freezed == previous ? _self.previous : previous // ignore: cast_nullable_to_non_nullable
as Materialized<T, R>?,
  ));
}

/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of ReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MaterializedCopyWith<T, R, $Res>? get previous {
    if (_self.previous == null) {
    return null;
  }

  return $MaterializedCopyWith<T, R, $Res>(_self.previous!, (value) {
    return _then(_self.copyWith(previous: value));
  });
}
}

/// @nodoc
mixin _$CollectionContinuation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionContinuation);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $CollectionContinuationCopyWith<$Res>  {
$CollectionContinuationCopyWith(CollectionContinuation _, $Res Function(CollectionContinuation) __);
}


/// Adds pattern-matching-related methods to [CollectionContinuation].
extension CollectionContinuationPatterns on CollectionContinuation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnknownCollectionContinuation value)?  unknown,TResult Function( OffsetCollectionContinuation value)?  offset,TResult Function( CursorCollectionContinuation value)?  cursor,TResult Function( EndCollectionContinuation value)?  end,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnknownCollectionContinuation() when unknown != null:
return unknown(_that);case OffsetCollectionContinuation() when offset != null:
return offset(_that);case CursorCollectionContinuation() when cursor != null:
return cursor(_that);case EndCollectionContinuation() when end != null:
return end(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnknownCollectionContinuation value)  unknown,required TResult Function( OffsetCollectionContinuation value)  offset,required TResult Function( CursorCollectionContinuation value)  cursor,required TResult Function( EndCollectionContinuation value)  end,}){
final _that = this;
switch (_that) {
case UnknownCollectionContinuation():
return unknown(_that);case OffsetCollectionContinuation():
return offset(_that);case CursorCollectionContinuation():
return cursor(_that);case EndCollectionContinuation():
return end(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnknownCollectionContinuation value)?  unknown,TResult? Function( OffsetCollectionContinuation value)?  offset,TResult? Function( CursorCollectionContinuation value)?  cursor,TResult? Function( EndCollectionContinuation value)?  end,}){
final _that = this;
switch (_that) {
case UnknownCollectionContinuation() when unknown != null:
return unknown(_that);case OffsetCollectionContinuation() when offset != null:
return offset(_that);case CursorCollectionContinuation() when cursor != null:
return cursor(_that);case EndCollectionContinuation() when end != null:
return end(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unknown,TResult Function( int value)?  offset,TResult Function( String value)?  cursor,TResult Function()?  end,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnknownCollectionContinuation() when unknown != null:
return unknown();case OffsetCollectionContinuation() when offset != null:
return offset(_that.value);case CursorCollectionContinuation() when cursor != null:
return cursor(_that.value);case EndCollectionContinuation() when end != null:
return end();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unknown,required TResult Function( int value)  offset,required TResult Function( String value)  cursor,required TResult Function()  end,}) {final _that = this;
switch (_that) {
case UnknownCollectionContinuation():
return unknown();case OffsetCollectionContinuation():
return offset(_that.value);case CursorCollectionContinuation():
return cursor(_that.value);case EndCollectionContinuation():
return end();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unknown,TResult? Function( int value)?  offset,TResult? Function( String value)?  cursor,TResult? Function()?  end,}) {final _that = this;
switch (_that) {
case UnknownCollectionContinuation() when unknown != null:
return unknown();case OffsetCollectionContinuation() when offset != null:
return offset(_that.value);case CursorCollectionContinuation() when cursor != null:
return cursor(_that.value);case EndCollectionContinuation() when end != null:
return end();case _:
  return null;

}
}

}

/// @nodoc


class UnknownCollectionContinuation implements CollectionContinuation {
  const UnknownCollectionContinuation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownCollectionContinuation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class OffsetCollectionContinuation implements CollectionContinuation {
  const OffsetCollectionContinuation({required this.value});


 final  int value;

/// Create a copy of CollectionContinuation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OffsetCollectionContinuationCopyWith<OffsetCollectionContinuation> get copyWith => _$OffsetCollectionContinuationCopyWithImpl<OffsetCollectionContinuation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is OffsetCollectionContinuation&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $OffsetCollectionContinuationCopyWith<$Res> implements $CollectionContinuationCopyWith<$Res> {
  factory $OffsetCollectionContinuationCopyWith(OffsetCollectionContinuation value, $Res Function(OffsetCollectionContinuation) _then) = _$OffsetCollectionContinuationCopyWithImpl;
@useResult
$Res call({
 int value
});




}
/// @nodoc
class _$OffsetCollectionContinuationCopyWithImpl<$Res>
    implements $OffsetCollectionContinuationCopyWith<$Res> {
  _$OffsetCollectionContinuationCopyWithImpl(this._self, this._then);

  final OffsetCollectionContinuation _self;
  final $Res Function(OffsetCollectionContinuation) _then;

/// Create a copy of CollectionContinuation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(OffsetCollectionContinuation(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CursorCollectionContinuation implements CollectionContinuation {
  const CursorCollectionContinuation({required this.value});


 final  String value;

/// Create a copy of CollectionContinuation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CursorCollectionContinuationCopyWith<CursorCollectionContinuation> get copyWith => _$CursorCollectionContinuationCopyWithImpl<CursorCollectionContinuation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CursorCollectionContinuation&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $CursorCollectionContinuationCopyWith<$Res> implements $CollectionContinuationCopyWith<$Res> {
  factory $CursorCollectionContinuationCopyWith(CursorCollectionContinuation value, $Res Function(CursorCollectionContinuation) _then) = _$CursorCollectionContinuationCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$CursorCollectionContinuationCopyWithImpl<$Res>
    implements $CursorCollectionContinuationCopyWith<$Res> {
  _$CursorCollectionContinuationCopyWithImpl(this._self, this._then);

  final CursorCollectionContinuation _self;
  final $Res Function(CursorCollectionContinuation) _then;

/// Create a copy of CollectionContinuation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(CursorCollectionContinuation(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class EndCollectionContinuation implements CollectionContinuation {
  const EndCollectionContinuation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EndCollectionContinuation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$CollectionWindow<T> {


/// Create a copy of CollectionWindow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CollectionWindowCopyWith<T, CollectionWindow<T>> get copyWith => _$CollectionWindowCopyWithImpl<T, CollectionWindow<T>>(this as CollectionWindow<T>, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CollectionWindow<T>;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionWindow<T>&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&const DeepCollectionEquality().equals(other.entries, _this.entries)&&const DeepCollectionEquality().equals(other.rows, _this.rows)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation)&&(identical(other.complete, _this.complete) || other.complete == _this.complete)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as CollectionWindow<T>;
  return Object.hash(runtimeType,_this.origin,_this.reference,const DeepCollectionEquality().hash(_this.entries),const DeepCollectionEquality().hash(_this.rows),_this.continuation,_this.complete,_this.loading,_this.error);
}



}

/// @nodoc
abstract mixin class $CollectionWindowCopyWith<T,$Res>  {
  factory $CollectionWindowCopyWith(CollectionWindow<T> value, $Res Function(CollectionWindow<T>) _then) = _$CollectionWindowCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, ProductCollectionRef reference, List<ProductEntityRef> entries, Map<int, ReadValue<T, ProductEntityRef>> rows, CollectionContinuation continuation, bool complete, bool loading, StudioFailure? error
});


$ProductReadOriginCopyWith<$Res> get origin;$ProductCollectionRefCopyWith<$Res> get reference;$CollectionContinuationCopyWith<$Res> get continuation;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$CollectionWindowCopyWithImpl<T,$Res>
    implements $CollectionWindowCopyWith<T, $Res> {
  _$CollectionWindowCopyWithImpl(this._self, this._then);

  final CollectionWindow<T> _self;
  final $Res Function(CollectionWindow<T>) _then;

/// Create a copy of CollectionWindow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,Object? entries = null,Object? rows = null,Object? continuation = null,Object? complete = null,Object? loading = null,Object? error = freezed,}) {
  return _then(CollectionWindow(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,rows: null == rows ? _self.rows : rows // ignore: cast_nullable_to_non_nullable
as Map<int, ReadValue<T, ProductEntityRef>>,continuation: null == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as CollectionContinuation,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of CollectionWindow
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of CollectionWindow
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get reference {

  return $ProductCollectionRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of CollectionWindow
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionContinuationCopyWith<$Res> get continuation {

  return $CollectionContinuationCopyWith<$Res>(_self.continuation, (value) {
    return _then(_self.copyWith(continuation: value));
  });
}/// Create a copy of CollectionWindow
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [CollectionWindow].
extension CollectionWindowPatterns<T> on CollectionWindow<T> {
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
mixin _$CollectionMirror<T> {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CollectionMirror<T>);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $CollectionMirrorCopyWith<T,$Res>  {
$CollectionMirrorCopyWith(CollectionMirror<T> _, $Res Function(CollectionMirror<T>) __);
}


/// Adds pattern-matching-related methods to [CollectionMirror].
extension CollectionMirrorPatterns<T> on CollectionMirror<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnavailableCollectionMirror<T> value)?  unavailable,TResult Function( CurrentCollectionMirror<T> value)?  current,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnavailableCollectionMirror() when unavailable != null:
return unavailable(_that);case CurrentCollectionMirror() when current != null:
return current(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnavailableCollectionMirror<T> value)  unavailable,required TResult Function( CurrentCollectionMirror<T> value)  current,}){
final _that = this;
switch (_that) {
case UnavailableCollectionMirror():
return unavailable(_that);case CurrentCollectionMirror():
return current(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnavailableCollectionMirror<T> value)?  unavailable,TResult? Function( CurrentCollectionMirror<T> value)?  current,}){
final _that = this;
switch (_that) {
case UnavailableCollectionMirror() when unavailable != null:
return unavailable(_that);case CurrentCollectionMirror() when current != null:
return current(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( CollectionWindow<T>? lastKnown)?  unavailable,TResult Function( CollectionWindow<T> window)?  current,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnavailableCollectionMirror() when unavailable != null:
return unavailable(_that.lastKnown);case CurrentCollectionMirror() when current != null:
return current(_that.window);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( CollectionWindow<T>? lastKnown)  unavailable,required TResult Function( CollectionWindow<T> window)  current,}) {final _that = this;
switch (_that) {
case UnavailableCollectionMirror():
return unavailable(_that.lastKnown);case CurrentCollectionMirror():
return current(_that.window);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( CollectionWindow<T>? lastKnown)?  unavailable,TResult? Function( CollectionWindow<T> window)?  current,}) {final _that = this;
switch (_that) {
case UnavailableCollectionMirror() when unavailable != null:
return unavailable(_that.lastKnown);case CurrentCollectionMirror() when current != null:
return current(_that.window);case _:
  return null;

}
}

}

/// @nodoc


class UnavailableCollectionMirror<T> implements CollectionMirror<T> {
  const UnavailableCollectionMirror({required this.lastKnown});


 final  CollectionWindow<T>? lastKnown;

/// Create a copy of CollectionMirror
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnavailableCollectionMirrorCopyWith<T, UnavailableCollectionMirror<T>> get copyWith => _$UnavailableCollectionMirrorCopyWithImpl<T, UnavailableCollectionMirror<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnavailableCollectionMirror<T>&&(identical(other.lastKnown, lastKnown) || other.lastKnown == lastKnown));
}


@override
int get hashCode {
    return Object.hash(runtimeType,lastKnown);
}



}

/// @nodoc
abstract mixin class $UnavailableCollectionMirrorCopyWith<T,$Res> implements $CollectionMirrorCopyWith<T, $Res> {
  factory $UnavailableCollectionMirrorCopyWith(UnavailableCollectionMirror<T> value, $Res Function(UnavailableCollectionMirror<T>) _then) = _$UnavailableCollectionMirrorCopyWithImpl;
@useResult
$Res call({
 CollectionWindow<T>? lastKnown
});


$CollectionWindowCopyWith<T, $Res>? get lastKnown;

}
/// @nodoc
class _$UnavailableCollectionMirrorCopyWithImpl<T,$Res>
    implements $UnavailableCollectionMirrorCopyWith<T, $Res> {
  _$UnavailableCollectionMirrorCopyWithImpl(this._self, this._then);

  final UnavailableCollectionMirror<T> _self;
  final $Res Function(UnavailableCollectionMirror<T>) _then;

/// Create a copy of CollectionMirror
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? lastKnown = freezed,}) {
  return _then(UnavailableCollectionMirror<T>(
lastKnown: freezed == lastKnown ? _self.lastKnown : lastKnown // ignore: cast_nullable_to_non_nullable
as CollectionWindow<T>?,
  ));
}

/// Create a copy of CollectionMirror
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionWindowCopyWith<T, $Res>? get lastKnown {
    if (_self.lastKnown == null) {
    return null;
  }

  return $CollectionWindowCopyWith<T, $Res>(_self.lastKnown!, (value) {
    return _then(_self.copyWith(lastKnown: value));
  });
}
}

/// @nodoc


class CurrentCollectionMirror<T> implements CollectionMirror<T> {
  const CurrentCollectionMirror({required this.window});


 final  CollectionWindow<T> window;

/// Create a copy of CollectionMirror
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CurrentCollectionMirrorCopyWith<T, CurrentCollectionMirror<T>> get copyWith => _$CurrentCollectionMirrorCopyWithImpl<T, CurrentCollectionMirror<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CurrentCollectionMirror<T>&&(identical(other.window, window) || other.window == window));
}


@override
int get hashCode {
    return Object.hash(runtimeType,window);
}



}

/// @nodoc
abstract mixin class $CurrentCollectionMirrorCopyWith<T,$Res> implements $CollectionMirrorCopyWith<T, $Res> {
  factory $CurrentCollectionMirrorCopyWith(CurrentCollectionMirror<T> value, $Res Function(CurrentCollectionMirror<T>) _then) = _$CurrentCollectionMirrorCopyWithImpl;
@useResult
$Res call({
 CollectionWindow<T> window
});


$CollectionWindowCopyWith<T, $Res> get window;

}
/// @nodoc
class _$CurrentCollectionMirrorCopyWithImpl<T,$Res>
    implements $CurrentCollectionMirrorCopyWith<T, $Res> {
  _$CurrentCollectionMirrorCopyWithImpl(this._self, this._then);

  final CurrentCollectionMirror<T> _self;
  final $Res Function(CurrentCollectionMirror<T>) _then;

/// Create a copy of CollectionMirror
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? window = null,}) {
  return _then(CurrentCollectionMirror<T>(
window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as CollectionWindow<T>,
  ));
}

/// Create a copy of CollectionMirror
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionWindowCopyWith<T, $Res> get window {

  return $CollectionWindowCopyWith<T, $Res>(_self.window, (value) {
    return _then(_self.copyWith(window: value));
  });
}
}

// dart format on
