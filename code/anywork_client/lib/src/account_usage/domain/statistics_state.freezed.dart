// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'statistics_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PerformanceSummariesReadTarget {

 ProductReadOrigin get origin; PerformanceSummariesReadRef get reference;
/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesReadTargetCopyWith<PerformanceSummariesReadTarget> get copyWith => _$PerformanceSummariesReadTargetCopyWithImpl<PerformanceSummariesReadTarget>(this as PerformanceSummariesReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as PerformanceSummariesReadTarget;
  return 'PerformanceSummariesReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummariesReadTargetCopyWith<$Res>  {
  factory $PerformanceSummariesReadTargetCopyWith(PerformanceSummariesReadTarget value, $Res Function(PerformanceSummariesReadTarget) _then) = _$PerformanceSummariesReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, PerformanceSummariesReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$PerformanceSummariesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PerformanceSummariesReadTargetCopyWithImpl<$Res>
    implements $PerformanceSummariesReadTargetCopyWith<$Res> {
  _$PerformanceSummariesReadTargetCopyWithImpl(this._self, this._then);

  final PerformanceSummariesReadTarget _self;
  final $Res Function(PerformanceSummariesReadTarget) _then;

/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(PerformanceSummariesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,
  ));
}
/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get reference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummariesReadTarget].
extension PerformanceSummariesReadTargetPatterns on PerformanceSummariesReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  PerformanceSummariesReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  PerformanceSummariesReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesReadTarget():
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  PerformanceSummariesReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesReadTarget implements PerformanceSummariesReadTarget {
  const _PerformanceSummariesReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  PerformanceSummariesReadRef reference;

/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesReadTargetCopyWith<_PerformanceSummariesReadTarget> get copyWith => __$PerformanceSummariesReadTargetCopyWithImpl<_PerformanceSummariesReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'PerformanceSummariesReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummariesReadTargetCopyWith<$Res> implements $PerformanceSummariesReadTargetCopyWith<$Res> {
  factory _$PerformanceSummariesReadTargetCopyWith(_PerformanceSummariesReadTarget value, $Res Function(_PerformanceSummariesReadTarget) _then) = __$PerformanceSummariesReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, PerformanceSummariesReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $PerformanceSummariesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PerformanceSummariesReadTargetCopyWithImpl<$Res>
    implements _$PerformanceSummariesReadTargetCopyWith<$Res> {
  __$PerformanceSummariesReadTargetCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesReadTarget _self;
  final $Res Function(_PerformanceSummariesReadTarget) _then;

/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_PerformanceSummariesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,
  ));
}

/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PerformanceSummariesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get reference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PerformanceHistoryReadTarget {

 ProductReadOrigin get origin; PerformanceHistoryReadRef get reference;
/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryReadTargetCopyWith<PerformanceHistoryReadTarget> get copyWith => _$PerformanceHistoryReadTargetCopyWithImpl<PerformanceHistoryReadTarget>(this as PerformanceHistoryReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as PerformanceHistoryReadTarget;
  return 'PerformanceHistoryReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $PerformanceHistoryReadTargetCopyWith<$Res>  {
  factory $PerformanceHistoryReadTargetCopyWith(PerformanceHistoryReadTarget value, $Res Function(PerformanceHistoryReadTarget) _then) = _$PerformanceHistoryReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, PerformanceHistoryReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$PerformanceHistoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PerformanceHistoryReadTargetCopyWithImpl<$Res>
    implements $PerformanceHistoryReadTargetCopyWith<$Res> {
  _$PerformanceHistoryReadTargetCopyWithImpl(this._self, this._then);

  final PerformanceHistoryReadTarget _self;
  final $Res Function(PerformanceHistoryReadTarget) _then;

/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(PerformanceHistoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,
  ));
}
/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get reference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceHistoryReadTarget].
extension PerformanceHistoryReadTargetPatterns on PerformanceHistoryReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  PerformanceHistoryReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  PerformanceHistoryReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryReadTarget():
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  PerformanceHistoryReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryReadTarget implements PerformanceHistoryReadTarget {
  const _PerformanceHistoryReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  PerformanceHistoryReadRef reference;

/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryReadTargetCopyWith<_PerformanceHistoryReadTarget> get copyWith => __$PerformanceHistoryReadTargetCopyWithImpl<_PerformanceHistoryReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'PerformanceHistoryReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$PerformanceHistoryReadTargetCopyWith<$Res> implements $PerformanceHistoryReadTargetCopyWith<$Res> {
  factory _$PerformanceHistoryReadTargetCopyWith(_PerformanceHistoryReadTarget value, $Res Function(_PerformanceHistoryReadTarget) _then) = __$PerformanceHistoryReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, PerformanceHistoryReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $PerformanceHistoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PerformanceHistoryReadTargetCopyWithImpl<$Res>
    implements _$PerformanceHistoryReadTargetCopyWith<$Res> {
  __$PerformanceHistoryReadTargetCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryReadTarget _self;
  final $Res Function(_PerformanceHistoryReadTarget) _then;

/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_PerformanceHistoryReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,
  ));
}

/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PerformanceHistoryReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get reference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$SessionCostsReadTarget {

 ProductReadOrigin get origin; SessionCostsReadRef get reference;
/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsReadTargetCopyWith<SessionCostsReadTarget> get copyWith => _$SessionCostsReadTargetCopyWithImpl<SessionCostsReadTarget>(this as SessionCostsReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCostsReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as SessionCostsReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as SessionCostsReadTarget;
  return 'SessionCostsReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $SessionCostsReadTargetCopyWith<$Res>  {
  factory $SessionCostsReadTargetCopyWith(SessionCostsReadTarget value, $Res Function(SessionCostsReadTarget) _then) = _$SessionCostsReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, SessionCostsReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$SessionCostsReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$SessionCostsReadTargetCopyWithImpl<$Res>
    implements $SessionCostsReadTargetCopyWith<$Res> {
  _$SessionCostsReadTargetCopyWithImpl(this._self, this._then);

  final SessionCostsReadTarget _self;
  final $Res Function(SessionCostsReadTarget) _then;

/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(SessionCostsReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SessionCostsReadRef,
  ));
}
/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsReadRefCopyWith<$Res> get reference {

  return $SessionCostsReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionCostsReadTarget].
extension SessionCostsReadTargetPatterns on SessionCostsReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCostsReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCostsReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCostsReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _SessionCostsReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCostsReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCostsReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  SessionCostsReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCostsReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  SessionCostsReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _SessionCostsReadTarget():
return $default(_that.origin,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  SessionCostsReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _SessionCostsReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCostsReadTarget implements SessionCostsReadTarget {
  const _SessionCostsReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  SessionCostsReadRef reference;

/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCostsReadTargetCopyWith<_SessionCostsReadTarget> get copyWith => __$SessionCostsReadTargetCopyWithImpl<_SessionCostsReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCostsReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'SessionCostsReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$SessionCostsReadTargetCopyWith<$Res> implements $SessionCostsReadTargetCopyWith<$Res> {
  factory _$SessionCostsReadTargetCopyWith(_SessionCostsReadTarget value, $Res Function(_SessionCostsReadTarget) _then) = __$SessionCostsReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, SessionCostsReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $SessionCostsReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$SessionCostsReadTargetCopyWithImpl<$Res>
    implements _$SessionCostsReadTargetCopyWith<$Res> {
  __$SessionCostsReadTargetCopyWithImpl(this._self, this._then);

  final _SessionCostsReadTarget _self;
  final $Res Function(_SessionCostsReadTarget) _then;

/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_SessionCostsReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SessionCostsReadRef,
  ));
}

/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of SessionCostsReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsReadRefCopyWith<$Res> get reference {

  return $SessionCostsReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PerformanceSummariesReadRef {

 int get entry; int get revision;
/// Create a copy of PerformanceSummariesReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<PerformanceSummariesReadRef> get copyWith => _$PerformanceSummariesReadRefCopyWithImpl<PerformanceSummariesReadRef>(this as PerformanceSummariesReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as PerformanceSummariesReadRef;
  return 'PerformanceSummariesReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummariesReadRefCopyWith<$Res>  {
  factory $PerformanceSummariesReadRefCopyWith(PerformanceSummariesReadRef value, $Res Function(PerformanceSummariesReadRef) _then) = _$PerformanceSummariesReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$PerformanceSummariesReadRefCopyWithImpl<$Res>
    implements $PerformanceSummariesReadRefCopyWith<$Res> {
  _$PerformanceSummariesReadRefCopyWithImpl(this._self, this._then);

  final PerformanceSummariesReadRef _self;
  final $Res Function(PerformanceSummariesReadRef) _then;

/// Create a copy of PerformanceSummariesReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(PerformanceSummariesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSummariesReadRef].
extension PerformanceSummariesReadRefPatterns on PerformanceSummariesReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesReadRef value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesReadRef() when $default != null:
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
case _PerformanceSummariesReadRef() when $default != null:
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
case _PerformanceSummariesReadRef():
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
case _PerformanceSummariesReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesReadRef implements PerformanceSummariesReadRef {
  const _PerformanceSummariesReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of PerformanceSummariesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesReadRefCopyWith<_PerformanceSummariesReadRef> get copyWith => __$PerformanceSummariesReadRefCopyWithImpl<_PerformanceSummariesReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'PerformanceSummariesReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummariesReadRefCopyWith<$Res> implements $PerformanceSummariesReadRefCopyWith<$Res> {
  factory _$PerformanceSummariesReadRefCopyWith(_PerformanceSummariesReadRef value, $Res Function(_PerformanceSummariesReadRef) _then) = __$PerformanceSummariesReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$PerformanceSummariesReadRefCopyWithImpl<$Res>
    implements _$PerformanceSummariesReadRefCopyWith<$Res> {
  __$PerformanceSummariesReadRefCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesReadRef _self;
  final $Res Function(_PerformanceSummariesReadRef) _then;

/// Create a copy of PerformanceSummariesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_PerformanceSummariesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PerformanceHistoryReadRef {

 int get entry; int get revision;
/// Create a copy of PerformanceHistoryReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<PerformanceHistoryReadRef> get copyWith => _$PerformanceHistoryReadRefCopyWithImpl<PerformanceHistoryReadRef>(this as PerformanceHistoryReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as PerformanceHistoryReadRef;
  return 'PerformanceHistoryReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $PerformanceHistoryReadRefCopyWith<$Res>  {
  factory $PerformanceHistoryReadRefCopyWith(PerformanceHistoryReadRef value, $Res Function(PerformanceHistoryReadRef) _then) = _$PerformanceHistoryReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$PerformanceHistoryReadRefCopyWithImpl<$Res>
    implements $PerformanceHistoryReadRefCopyWith<$Res> {
  _$PerformanceHistoryReadRefCopyWithImpl(this._self, this._then);

  final PerformanceHistoryReadRef _self;
  final $Res Function(PerformanceHistoryReadRef) _then;

/// Create a copy of PerformanceHistoryReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(PerformanceHistoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceHistoryReadRef].
extension PerformanceHistoryReadRefPatterns on PerformanceHistoryReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryReadRef value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryReadRef() when $default != null:
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
case _PerformanceHistoryReadRef() when $default != null:
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
case _PerformanceHistoryReadRef():
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
case _PerformanceHistoryReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryReadRef implements PerformanceHistoryReadRef {
  const _PerformanceHistoryReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of PerformanceHistoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryReadRefCopyWith<_PerformanceHistoryReadRef> get copyWith => __$PerformanceHistoryReadRefCopyWithImpl<_PerformanceHistoryReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'PerformanceHistoryReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$PerformanceHistoryReadRefCopyWith<$Res> implements $PerformanceHistoryReadRefCopyWith<$Res> {
  factory _$PerformanceHistoryReadRefCopyWith(_PerformanceHistoryReadRef value, $Res Function(_PerformanceHistoryReadRef) _then) = __$PerformanceHistoryReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$PerformanceHistoryReadRefCopyWithImpl<$Res>
    implements _$PerformanceHistoryReadRefCopyWith<$Res> {
  __$PerformanceHistoryReadRefCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryReadRef _self;
  final $Res Function(_PerformanceHistoryReadRef) _then;

/// Create a copy of PerformanceHistoryReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_PerformanceHistoryReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$SessionCostsReadRef {

 int get entry; int get revision;
/// Create a copy of SessionCostsReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsReadRefCopyWith<SessionCostsReadRef> get copyWith => _$SessionCostsReadRefCopyWithImpl<SessionCostsReadRef>(this as SessionCostsReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCostsReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as SessionCostsReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as SessionCostsReadRef;
  return 'SessionCostsReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $SessionCostsReadRefCopyWith<$Res>  {
  factory $SessionCostsReadRefCopyWith(SessionCostsReadRef value, $Res Function(SessionCostsReadRef) _then) = _$SessionCostsReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$SessionCostsReadRefCopyWithImpl<$Res>
    implements $SessionCostsReadRefCopyWith<$Res> {
  _$SessionCostsReadRefCopyWithImpl(this._self, this._then);

  final SessionCostsReadRef _self;
  final $Res Function(SessionCostsReadRef) _then;

/// Create a copy of SessionCostsReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(SessionCostsReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [SessionCostsReadRef].
extension SessionCostsReadRefPatterns on SessionCostsReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCostsReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCostsReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCostsReadRef value)  $default,){
final _that = this;
switch (_that) {
case _SessionCostsReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCostsReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCostsReadRef() when $default != null:
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
case _SessionCostsReadRef() when $default != null:
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
case _SessionCostsReadRef():
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
case _SessionCostsReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCostsReadRef implements SessionCostsReadRef {
  const _SessionCostsReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of SessionCostsReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCostsReadRefCopyWith<_SessionCostsReadRef> get copyWith => __$SessionCostsReadRefCopyWithImpl<_SessionCostsReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCostsReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'SessionCostsReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$SessionCostsReadRefCopyWith<$Res> implements $SessionCostsReadRefCopyWith<$Res> {
  factory _$SessionCostsReadRefCopyWith(_SessionCostsReadRef value, $Res Function(_SessionCostsReadRef) _then) = __$SessionCostsReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$SessionCostsReadRefCopyWithImpl<$Res>
    implements _$SessionCostsReadRefCopyWith<$Res> {
  __$SessionCostsReadRefCopyWithImpl(this._self, this._then);

  final _SessionCostsReadRef _self;
  final $Res Function(_SessionCostsReadRef) _then;

/// Create a copy of SessionCostsReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_SessionCostsReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PerformanceSummaryIdentityRef {

 int get entry; int get revision;
/// Create a copy of PerformanceSummaryIdentityRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummaryIdentityRefCopyWith<PerformanceSummaryIdentityRef> get copyWith => _$PerformanceSummaryIdentityRefCopyWithImpl<PerformanceSummaryIdentityRef>(this as PerformanceSummaryIdentityRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummaryIdentityRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummaryIdentityRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as PerformanceSummaryIdentityRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as PerformanceSummaryIdentityRef;
  return 'PerformanceSummaryIdentityRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummaryIdentityRefCopyWith<$Res>  {
  factory $PerformanceSummaryIdentityRefCopyWith(PerformanceSummaryIdentityRef value, $Res Function(PerformanceSummaryIdentityRef) _then) = _$PerformanceSummaryIdentityRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$PerformanceSummaryIdentityRefCopyWithImpl<$Res>
    implements $PerformanceSummaryIdentityRefCopyWith<$Res> {
  _$PerformanceSummaryIdentityRefCopyWithImpl(this._self, this._then);

  final PerformanceSummaryIdentityRef _self;
  final $Res Function(PerformanceSummaryIdentityRef) _then;

/// Create a copy of PerformanceSummaryIdentityRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(PerformanceSummaryIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSummaryIdentityRef].
extension PerformanceSummaryIdentityRefPatterns on PerformanceSummaryIdentityRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummaryIdentityRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummaryIdentityRef value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummaryIdentityRef value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummaryIdentityRef() when $default != null:
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
case _PerformanceSummaryIdentityRef() when $default != null:
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
case _PerformanceSummaryIdentityRef():
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
case _PerformanceSummaryIdentityRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummaryIdentityRef implements PerformanceSummaryIdentityRef {
  const _PerformanceSummaryIdentityRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of PerformanceSummaryIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummaryIdentityRefCopyWith<_PerformanceSummaryIdentityRef> get copyWith => __$PerformanceSummaryIdentityRefCopyWithImpl<_PerformanceSummaryIdentityRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummaryIdentityRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'PerformanceSummaryIdentityRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummaryIdentityRefCopyWith<$Res> implements $PerformanceSummaryIdentityRefCopyWith<$Res> {
  factory _$PerformanceSummaryIdentityRefCopyWith(_PerformanceSummaryIdentityRef value, $Res Function(_PerformanceSummaryIdentityRef) _then) = __$PerformanceSummaryIdentityRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$PerformanceSummaryIdentityRefCopyWithImpl<$Res>
    implements _$PerformanceSummaryIdentityRefCopyWith<$Res> {
  __$PerformanceSummaryIdentityRefCopyWithImpl(this._self, this._then);

  final _PerformanceSummaryIdentityRef _self;
  final $Res Function(_PerformanceSummaryIdentityRef) _then;

/// Create a copy of PerformanceSummaryIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_PerformanceSummaryIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PerformanceEffortIdentityRef {

 int get entry; int get revision;
/// Create a copy of PerformanceEffortIdentityRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceEffortIdentityRefCopyWith<PerformanceEffortIdentityRef> get copyWith => _$PerformanceEffortIdentityRefCopyWithImpl<PerformanceEffortIdentityRef>(this as PerformanceEffortIdentityRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceEffortIdentityRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceEffortIdentityRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as PerformanceEffortIdentityRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as PerformanceEffortIdentityRef;
  return 'PerformanceEffortIdentityRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $PerformanceEffortIdentityRefCopyWith<$Res>  {
  factory $PerformanceEffortIdentityRefCopyWith(PerformanceEffortIdentityRef value, $Res Function(PerformanceEffortIdentityRef) _then) = _$PerformanceEffortIdentityRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$PerformanceEffortIdentityRefCopyWithImpl<$Res>
    implements $PerformanceEffortIdentityRefCopyWith<$Res> {
  _$PerformanceEffortIdentityRefCopyWithImpl(this._self, this._then);

  final PerformanceEffortIdentityRef _self;
  final $Res Function(PerformanceEffortIdentityRef) _then;

/// Create a copy of PerformanceEffortIdentityRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(PerformanceEffortIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceEffortIdentityRef].
extension PerformanceEffortIdentityRefPatterns on PerformanceEffortIdentityRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceEffortIdentityRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceEffortIdentityRef value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceEffortIdentityRef value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceEffortIdentityRef() when $default != null:
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
case _PerformanceEffortIdentityRef() when $default != null:
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
case _PerformanceEffortIdentityRef():
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
case _PerformanceEffortIdentityRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceEffortIdentityRef implements PerformanceEffortIdentityRef {
  const _PerformanceEffortIdentityRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of PerformanceEffortIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceEffortIdentityRefCopyWith<_PerformanceEffortIdentityRef> get copyWith => __$PerformanceEffortIdentityRefCopyWithImpl<_PerformanceEffortIdentityRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceEffortIdentityRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'PerformanceEffortIdentityRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$PerformanceEffortIdentityRefCopyWith<$Res> implements $PerformanceEffortIdentityRefCopyWith<$Res> {
  factory _$PerformanceEffortIdentityRefCopyWith(_PerformanceEffortIdentityRef value, $Res Function(_PerformanceEffortIdentityRef) _then) = __$PerformanceEffortIdentityRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$PerformanceEffortIdentityRefCopyWithImpl<$Res>
    implements _$PerformanceEffortIdentityRefCopyWith<$Res> {
  __$PerformanceEffortIdentityRefCopyWithImpl(this._self, this._then);

  final _PerformanceEffortIdentityRef _self;
  final $Res Function(_PerformanceEffortIdentityRef) _then;

/// Create a copy of PerformanceEffortIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_PerformanceEffortIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PerformanceSampleIdentityRef {

 int get entry; int get revision;
/// Create a copy of PerformanceSampleIdentityRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSampleIdentityRefCopyWith<PerformanceSampleIdentityRef> get copyWith => _$PerformanceSampleIdentityRefCopyWithImpl<PerformanceSampleIdentityRef>(this as PerformanceSampleIdentityRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSampleIdentityRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSampleIdentityRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as PerformanceSampleIdentityRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as PerformanceSampleIdentityRef;
  return 'PerformanceSampleIdentityRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $PerformanceSampleIdentityRefCopyWith<$Res>  {
  factory $PerformanceSampleIdentityRefCopyWith(PerformanceSampleIdentityRef value, $Res Function(PerformanceSampleIdentityRef) _then) = _$PerformanceSampleIdentityRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$PerformanceSampleIdentityRefCopyWithImpl<$Res>
    implements $PerformanceSampleIdentityRefCopyWith<$Res> {
  _$PerformanceSampleIdentityRefCopyWithImpl(this._self, this._then);

  final PerformanceSampleIdentityRef _self;
  final $Res Function(PerformanceSampleIdentityRef) _then;

/// Create a copy of PerformanceSampleIdentityRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(PerformanceSampleIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PerformanceSampleIdentityRef].
extension PerformanceSampleIdentityRefPatterns on PerformanceSampleIdentityRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSampleIdentityRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSampleIdentityRef value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSampleIdentityRef value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSampleIdentityRef() when $default != null:
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
case _PerformanceSampleIdentityRef() when $default != null:
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
case _PerformanceSampleIdentityRef():
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
case _PerformanceSampleIdentityRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSampleIdentityRef implements PerformanceSampleIdentityRef {
  const _PerformanceSampleIdentityRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of PerformanceSampleIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSampleIdentityRefCopyWith<_PerformanceSampleIdentityRef> get copyWith => __$PerformanceSampleIdentityRefCopyWithImpl<_PerformanceSampleIdentityRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSampleIdentityRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'PerformanceSampleIdentityRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSampleIdentityRefCopyWith<$Res> implements $PerformanceSampleIdentityRefCopyWith<$Res> {
  factory _$PerformanceSampleIdentityRefCopyWith(_PerformanceSampleIdentityRef value, $Res Function(_PerformanceSampleIdentityRef) _then) = __$PerformanceSampleIdentityRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$PerformanceSampleIdentityRefCopyWithImpl<$Res>
    implements _$PerformanceSampleIdentityRefCopyWith<$Res> {
  __$PerformanceSampleIdentityRefCopyWithImpl(this._self, this._then);

  final _PerformanceSampleIdentityRef _self;
  final $Res Function(_PerformanceSampleIdentityRef) _then;

/// Create a copy of PerformanceSampleIdentityRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_PerformanceSampleIdentityRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PerformanceSummariesHeader {

 int get revision; int get updatedAt; bool get statisticsPending; bool get statisticsGap; bool get readFailed; PerformanceSummariesReadRef get reference;
/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceSummariesHeaderCopyWith<PerformanceSummariesHeader> get copyWith => _$PerformanceSummariesHeaderCopyWithImpl<PerformanceSummariesHeader>(this as PerformanceSummariesHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceSummariesHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceSummariesHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.statisticsPending, _this.statisticsPending) || other.statisticsPending == _this.statisticsPending)&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.readFailed, _this.readFailed) || other.readFailed == _this.readFailed)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as PerformanceSummariesHeader;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.statisticsPending,_this.statisticsGap,_this.readFailed,_this.reference);
}

@override
String toString() {
  final _this = this as PerformanceSummariesHeader;
  return 'PerformanceSummariesHeader(revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, statisticsPending: ${_this.statisticsPending}, statisticsGap: ${_this.statisticsGap}, readFailed: ${_this.readFailed}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $PerformanceSummariesHeaderCopyWith<$Res>  {
  factory $PerformanceSummariesHeaderCopyWith(PerformanceSummariesHeader value, $Res Function(PerformanceSummariesHeader) _then) = _$PerformanceSummariesHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceSummariesReadRef reference
});


$PerformanceSummariesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PerformanceSummariesHeaderCopyWithImpl<$Res>
    implements $PerformanceSummariesHeaderCopyWith<$Res> {
  _$PerformanceSummariesHeaderCopyWithImpl(this._self, this._then);

  final PerformanceSummariesHeader _self;
  final $Res Function(PerformanceSummariesHeader) _then;

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(PerformanceSummariesHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,
  ));
}
/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get reference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceSummariesHeader].
extension PerformanceSummariesHeaderPatterns on PerformanceSummariesHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceSummariesHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceSummariesHeader value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceSummariesHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesHeader():
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceSummariesReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceSummariesHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceSummariesHeader implements PerformanceSummariesHeader {
  const _PerformanceSummariesHeader({required this.revision, required this.updatedAt, required this.statisticsPending, required this.statisticsGap, required this.readFailed, required this.reference});


@override final  int revision;
@override final  int updatedAt;
@override final  bool statisticsPending;
@override final  bool statisticsGap;
@override final  bool readFailed;
@override final  PerformanceSummariesReadRef reference;

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceSummariesHeaderCopyWith<_PerformanceSummariesHeader> get copyWith => __$PerformanceSummariesHeaderCopyWithImpl<_PerformanceSummariesHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceSummariesHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.statisticsPending, statisticsPending) || other.statisticsPending == statisticsPending)&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.readFailed, readFailed) || other.readFailed == readFailed)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,statisticsPending,statisticsGap,readFailed,reference);
}

@override
String toString() {
    return 'PerformanceSummariesHeader(revision: $revision, updatedAt: $updatedAt, statisticsPending: $statisticsPending, statisticsGap: $statisticsGap, readFailed: $readFailed, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$PerformanceSummariesHeaderCopyWith<$Res> implements $PerformanceSummariesHeaderCopyWith<$Res> {
  factory _$PerformanceSummariesHeaderCopyWith(_PerformanceSummariesHeader value, $Res Function(_PerformanceSummariesHeader) _then) = __$PerformanceSummariesHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceSummariesReadRef reference
});


@override $PerformanceSummariesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PerformanceSummariesHeaderCopyWithImpl<$Res>
    implements _$PerformanceSummariesHeaderCopyWith<$Res> {
  __$PerformanceSummariesHeaderCopyWithImpl(this._self, this._then);

  final _PerformanceSummariesHeader _self;
  final $Res Function(_PerformanceSummariesHeader) _then;

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(_PerformanceSummariesHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceSummariesReadRef,
  ));
}

/// Create a copy of PerformanceSummariesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceSummariesReadRefCopyWith<$Res> get reference {

  return $PerformanceSummariesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PerformanceHistoryHeader {

 int get revision; int get updatedAt; bool get statisticsPending; bool get statisticsGap; bool get readFailed; PerformanceHistoryReadRef get reference;
/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PerformanceHistoryHeaderCopyWith<PerformanceHistoryHeader> get copyWith => _$PerformanceHistoryHeaderCopyWithImpl<PerformanceHistoryHeader>(this as PerformanceHistoryHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PerformanceHistoryHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PerformanceHistoryHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.statisticsPending, _this.statisticsPending) || other.statisticsPending == _this.statisticsPending)&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.readFailed, _this.readFailed) || other.readFailed == _this.readFailed)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as PerformanceHistoryHeader;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.statisticsPending,_this.statisticsGap,_this.readFailed,_this.reference);
}

@override
String toString() {
  final _this = this as PerformanceHistoryHeader;
  return 'PerformanceHistoryHeader(revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, statisticsPending: ${_this.statisticsPending}, statisticsGap: ${_this.statisticsGap}, readFailed: ${_this.readFailed}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $PerformanceHistoryHeaderCopyWith<$Res>  {
  factory $PerformanceHistoryHeaderCopyWith(PerformanceHistoryHeader value, $Res Function(PerformanceHistoryHeader) _then) = _$PerformanceHistoryHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceHistoryReadRef reference
});


$PerformanceHistoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PerformanceHistoryHeaderCopyWithImpl<$Res>
    implements $PerformanceHistoryHeaderCopyWith<$Res> {
  _$PerformanceHistoryHeaderCopyWithImpl(this._self, this._then);

  final PerformanceHistoryHeader _self;
  final $Res Function(PerformanceHistoryHeader) _then;

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(PerformanceHistoryHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,
  ));
}
/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get reference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PerformanceHistoryHeader].
extension PerformanceHistoryHeaderPatterns on PerformanceHistoryHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PerformanceHistoryHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PerformanceHistoryHeader value)  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PerformanceHistoryHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceHistoryReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceHistoryReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryHeader():
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  PerformanceHistoryReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _PerformanceHistoryHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _PerformanceHistoryHeader implements PerformanceHistoryHeader {
  const _PerformanceHistoryHeader({required this.revision, required this.updatedAt, required this.statisticsPending, required this.statisticsGap, required this.readFailed, required this.reference});


@override final  int revision;
@override final  int updatedAt;
@override final  bool statisticsPending;
@override final  bool statisticsGap;
@override final  bool readFailed;
@override final  PerformanceHistoryReadRef reference;

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PerformanceHistoryHeaderCopyWith<_PerformanceHistoryHeader> get copyWith => __$PerformanceHistoryHeaderCopyWithImpl<_PerformanceHistoryHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PerformanceHistoryHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.statisticsPending, statisticsPending) || other.statisticsPending == statisticsPending)&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.readFailed, readFailed) || other.readFailed == readFailed)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,statisticsPending,statisticsGap,readFailed,reference);
}

@override
String toString() {
    return 'PerformanceHistoryHeader(revision: $revision, updatedAt: $updatedAt, statisticsPending: $statisticsPending, statisticsGap: $statisticsGap, readFailed: $readFailed, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$PerformanceHistoryHeaderCopyWith<$Res> implements $PerformanceHistoryHeaderCopyWith<$Res> {
  factory _$PerformanceHistoryHeaderCopyWith(_PerformanceHistoryHeader value, $Res Function(_PerformanceHistoryHeader) _then) = __$PerformanceHistoryHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, PerformanceHistoryReadRef reference
});


@override $PerformanceHistoryReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PerformanceHistoryHeaderCopyWithImpl<$Res>
    implements _$PerformanceHistoryHeaderCopyWith<$Res> {
  __$PerformanceHistoryHeaderCopyWithImpl(this._self, this._then);

  final _PerformanceHistoryHeader _self;
  final $Res Function(_PerformanceHistoryHeader) _then;

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? reference = null,}) {
  return _then(_PerformanceHistoryHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PerformanceHistoryReadRef,
  ));
}

/// Create a copy of PerformanceHistoryHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PerformanceHistoryReadRefCopyWith<$Res> get reference {

  return $PerformanceHistoryReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$SessionCostsHeader {

 int get revision; int get updatedAt; bool get statisticsPending; bool get statisticsGap; bool get readFailed; bool get hasCost; bool? get hasUnpricedUsage; SessionCostsReadRef get reference;
/// Create a copy of SessionCostsHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsHeaderCopyWith<SessionCostsHeader> get copyWith => _$SessionCostsHeaderCopyWithImpl<SessionCostsHeader>(this as SessionCostsHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCostsHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.statisticsPending, _this.statisticsPending) || other.statisticsPending == _this.statisticsPending)&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.readFailed, _this.readFailed) || other.readFailed == _this.readFailed)&&(identical(other.hasCost, _this.hasCost) || other.hasCost == _this.hasCost)&&(identical(other.hasUnpricedUsage, _this.hasUnpricedUsage) || other.hasUnpricedUsage == _this.hasUnpricedUsage)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as SessionCostsHeader;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,_this.statisticsPending,_this.statisticsGap,_this.readFailed,_this.hasCost,_this.hasUnpricedUsage,_this.reference);
}

@override
String toString() {
  final _this = this as SessionCostsHeader;
  return 'SessionCostsHeader(revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, statisticsPending: ${_this.statisticsPending}, statisticsGap: ${_this.statisticsGap}, readFailed: ${_this.readFailed}, hasCost: ${_this.hasCost}, hasUnpricedUsage: ${_this.hasUnpricedUsage}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $SessionCostsHeaderCopyWith<$Res>  {
  factory $SessionCostsHeaderCopyWith(SessionCostsHeader value, $Res Function(SessionCostsHeader) _then) = _$SessionCostsHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, bool hasCost, bool? hasUnpricedUsage, SessionCostsReadRef reference
});


$SessionCostsReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$SessionCostsHeaderCopyWithImpl<$Res>
    implements $SessionCostsHeaderCopyWith<$Res> {
  _$SessionCostsHeaderCopyWithImpl(this._self, this._then);

  final SessionCostsHeader _self;
  final $Res Function(SessionCostsHeader) _then;

/// Create a copy of SessionCostsHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? hasCost = null,Object? hasUnpricedUsage = freezed,Object? reference = null,}) {
  return _then(SessionCostsHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,hasCost: null == hasCost ? _self.hasCost : hasCost // ignore: cast_nullable_to_non_nullable
as bool,hasUnpricedUsage: freezed == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool?,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SessionCostsReadRef,
  ));
}
/// Create a copy of SessionCostsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsReadRefCopyWith<$Res> get reference {

  return $SessionCostsReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionCostsHeader].
extension SessionCostsHeaderPatterns on SessionCostsHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCostsHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCostsHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCostsHeader value)  $default,){
final _that = this;
switch (_that) {
case _SessionCostsHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCostsHeader value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCostsHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  bool hasCost,  bool? hasUnpricedUsage,  SessionCostsReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCostsHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.hasCost,_that.hasUnpricedUsage,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  bool hasCost,  bool? hasUnpricedUsage,  SessionCostsReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _SessionCostsHeader():
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.hasCost,_that.hasUnpricedUsage,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  bool statisticsPending,  bool statisticsGap,  bool readFailed,  bool hasCost,  bool? hasUnpricedUsage,  SessionCostsReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _SessionCostsHeader() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.statisticsPending,_that.statisticsGap,_that.readFailed,_that.hasCost,_that.hasUnpricedUsage,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCostsHeader implements SessionCostsHeader {
  const _SessionCostsHeader({required this.revision, required this.updatedAt, required this.statisticsPending, required this.statisticsGap, required this.readFailed, required this.hasCost, required this.hasUnpricedUsage, required this.reference});


@override final  int revision;
@override final  int updatedAt;
@override final  bool statisticsPending;
@override final  bool statisticsGap;
@override final  bool readFailed;
@override final  bool hasCost;
@override final  bool? hasUnpricedUsage;
@override final  SessionCostsReadRef reference;

/// Create a copy of SessionCostsHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCostsHeaderCopyWith<_SessionCostsHeader> get copyWith => __$SessionCostsHeaderCopyWithImpl<_SessionCostsHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCostsHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.statisticsPending, statisticsPending) || other.statisticsPending == statisticsPending)&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.readFailed, readFailed) || other.readFailed == readFailed)&&(identical(other.hasCost, hasCost) || other.hasCost == hasCost)&&(identical(other.hasUnpricedUsage, hasUnpricedUsage) || other.hasUnpricedUsage == hasUnpricedUsage)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,statisticsPending,statisticsGap,readFailed,hasCost,hasUnpricedUsage,reference);
}

@override
String toString() {
    return 'SessionCostsHeader(revision: $revision, updatedAt: $updatedAt, statisticsPending: $statisticsPending, statisticsGap: $statisticsGap, readFailed: $readFailed, hasCost: $hasCost, hasUnpricedUsage: $hasUnpricedUsage, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$SessionCostsHeaderCopyWith<$Res> implements $SessionCostsHeaderCopyWith<$Res> {
  factory _$SessionCostsHeaderCopyWith(_SessionCostsHeader value, $Res Function(_SessionCostsHeader) _then) = __$SessionCostsHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, bool statisticsPending, bool statisticsGap, bool readFailed, bool hasCost, bool? hasUnpricedUsage, SessionCostsReadRef reference
});


@override $SessionCostsReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$SessionCostsHeaderCopyWithImpl<$Res>
    implements _$SessionCostsHeaderCopyWith<$Res> {
  __$SessionCostsHeaderCopyWithImpl(this._self, this._then);

  final _SessionCostsHeader _self;
  final $Res Function(_SessionCostsHeader) _then;

/// Create a copy of SessionCostsHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? statisticsPending = null,Object? statisticsGap = null,Object? readFailed = null,Object? hasCost = null,Object? hasUnpricedUsage = freezed,Object? reference = null,}) {
  return _then(_SessionCostsHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsPending: null == statisticsPending ? _self.statisticsPending : statisticsPending // ignore: cast_nullable_to_non_nullable
as bool,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,readFailed: null == readFailed ? _self.readFailed : readFailed // ignore: cast_nullable_to_non_nullable
as bool,hasCost: null == hasCost ? _self.hasCost : hasCost // ignore: cast_nullable_to_non_nullable
as bool,hasUnpricedUsage: freezed == hasUnpricedUsage ? _self.hasUnpricedUsage : hasUnpricedUsage // ignore: cast_nullable_to_non_nullable
as bool?,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as SessionCostsReadRef,
  ));
}

/// Create a copy of SessionCostsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsReadRefCopyWith<$Res> get reference {

  return $SessionCostsReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$StatisticsSummaryState {

 ProductProjection<PerformanceSummariesHeader> get projection; CollectionMirror<PerformanceSummary> get summaries;
/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsSummaryStateCopyWith<StatisticsSummaryState> get copyWith => _$StatisticsSummaryStateCopyWithImpl<StatisticsSummaryState>(this as StatisticsSummaryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsSummaryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsSummaryState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.summaries, _this.summaries) || other.summaries == _this.summaries));
}


@override
int get hashCode {
  final _this = this as StatisticsSummaryState;
  return Object.hash(runtimeType,_this.projection,_this.summaries);
}



}

/// @nodoc
abstract mixin class $StatisticsSummaryStateCopyWith<$Res>  {
  factory $StatisticsSummaryStateCopyWith(StatisticsSummaryState value, $Res Function(StatisticsSummaryState) _then) = _$StatisticsSummaryStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<PerformanceSummariesHeader> projection, CollectionMirror<PerformanceSummary> summaries
});


$ProductProjectionCopyWith<PerformanceSummariesHeader, $Res> get projection;$CollectionMirrorCopyWith<PerformanceSummary, $Res> get summaries;

}
/// @nodoc
class _$StatisticsSummaryStateCopyWithImpl<$Res>
    implements $StatisticsSummaryStateCopyWith<$Res> {
  _$StatisticsSummaryStateCopyWithImpl(this._self, this._then);

  final StatisticsSummaryState _self;
  final $Res Function(StatisticsSummaryState) _then;

/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? summaries = null,}) {
  return _then(StatisticsSummaryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PerformanceSummariesHeader>,summaries: null == summaries ? _self.summaries : summaries // ignore: cast_nullable_to_non_nullable
as CollectionMirror<PerformanceSummary>,
  ));
}
/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PerformanceSummariesHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PerformanceSummariesHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<PerformanceSummary, $Res> get summaries {

  return $CollectionMirrorCopyWith<PerformanceSummary, $Res>(_self.summaries, (value) {
    return _then(_self.copyWith(summaries: value));
  });
}
}


/// Adds pattern-matching-related methods to [StatisticsSummaryState].
extension StatisticsSummaryStatePatterns on StatisticsSummaryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsSummaryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsSummaryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsSummaryState value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsSummaryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsSummaryState value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsSummaryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<PerformanceSummariesHeader> projection,  CollectionMirror<PerformanceSummary> summaries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsSummaryState() when $default != null:
return $default(_that.projection,_that.summaries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<PerformanceSummariesHeader> projection,  CollectionMirror<PerformanceSummary> summaries)  $default,) {final _that = this;
switch (_that) {
case _StatisticsSummaryState():
return $default(_that.projection,_that.summaries);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<PerformanceSummariesHeader> projection,  CollectionMirror<PerformanceSummary> summaries)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsSummaryState() when $default != null:
return $default(_that.projection,_that.summaries);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsSummaryState implements StatisticsSummaryState {
  const _StatisticsSummaryState({required this.projection, required this.summaries});


@override final  ProductProjection<PerformanceSummariesHeader> projection;
@override final  CollectionMirror<PerformanceSummary> summaries;

/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsSummaryStateCopyWith<_StatisticsSummaryState> get copyWith => __$StatisticsSummaryStateCopyWithImpl<_StatisticsSummaryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsSummaryState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.summaries, summaries) || other.summaries == summaries));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,summaries);
}



}

/// @nodoc
abstract mixin class _$StatisticsSummaryStateCopyWith<$Res> implements $StatisticsSummaryStateCopyWith<$Res> {
  factory _$StatisticsSummaryStateCopyWith(_StatisticsSummaryState value, $Res Function(_StatisticsSummaryState) _then) = __$StatisticsSummaryStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<PerformanceSummariesHeader> projection, CollectionMirror<PerformanceSummary> summaries
});


@override $ProductProjectionCopyWith<PerformanceSummariesHeader, $Res> get projection;@override $CollectionMirrorCopyWith<PerformanceSummary, $Res> get summaries;

}
/// @nodoc
class __$StatisticsSummaryStateCopyWithImpl<$Res>
    implements _$StatisticsSummaryStateCopyWith<$Res> {
  __$StatisticsSummaryStateCopyWithImpl(this._self, this._then);

  final _StatisticsSummaryState _self;
  final $Res Function(_StatisticsSummaryState) _then;

/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? summaries = null,}) {
  return _then(_StatisticsSummaryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PerformanceSummariesHeader>,summaries: null == summaries ? _self.summaries : summaries // ignore: cast_nullable_to_non_nullable
as CollectionMirror<PerformanceSummary>,
  ));
}

/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PerformanceSummariesHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PerformanceSummariesHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of StatisticsSummaryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<PerformanceSummary, $Res> get summaries {

  return $CollectionMirrorCopyWith<PerformanceSummary, $Res>(_self.summaries, (value) {
    return _then(_self.copyWith(summaries: value));
  });
}
}

/// @nodoc
mixin _$StatisticsHistoryState {

 ProductProjection<PerformanceHistoryHeader> get projection; CollectionMirror<PerformanceSample> get samples;
/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StatisticsHistoryStateCopyWith<StatisticsHistoryState> get copyWith => _$StatisticsHistoryStateCopyWithImpl<StatisticsHistoryState>(this as StatisticsHistoryState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StatisticsHistoryState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StatisticsHistoryState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.samples, _this.samples) || other.samples == _this.samples));
}


@override
int get hashCode {
  final _this = this as StatisticsHistoryState;
  return Object.hash(runtimeType,_this.projection,_this.samples);
}



}

/// @nodoc
abstract mixin class $StatisticsHistoryStateCopyWith<$Res>  {
  factory $StatisticsHistoryStateCopyWith(StatisticsHistoryState value, $Res Function(StatisticsHistoryState) _then) = _$StatisticsHistoryStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<PerformanceHistoryHeader> projection, CollectionMirror<PerformanceSample> samples
});


$ProductProjectionCopyWith<PerformanceHistoryHeader, $Res> get projection;$CollectionMirrorCopyWith<PerformanceSample, $Res> get samples;

}
/// @nodoc
class _$StatisticsHistoryStateCopyWithImpl<$Res>
    implements $StatisticsHistoryStateCopyWith<$Res> {
  _$StatisticsHistoryStateCopyWithImpl(this._self, this._then);

  final StatisticsHistoryState _self;
  final $Res Function(StatisticsHistoryState) _then;

/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? samples = null,}) {
  return _then(StatisticsHistoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PerformanceHistoryHeader>,samples: null == samples ? _self.samples : samples // ignore: cast_nullable_to_non_nullable
as CollectionMirror<PerformanceSample>,
  ));
}
/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PerformanceHistoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PerformanceHistoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<PerformanceSample, $Res> get samples {

  return $CollectionMirrorCopyWith<PerformanceSample, $Res>(_self.samples, (value) {
    return _then(_self.copyWith(samples: value));
  });
}
}


/// Adds pattern-matching-related methods to [StatisticsHistoryState].
extension StatisticsHistoryStatePatterns on StatisticsHistoryState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StatisticsHistoryState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StatisticsHistoryState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StatisticsHistoryState value)  $default,){
final _that = this;
switch (_that) {
case _StatisticsHistoryState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StatisticsHistoryState value)?  $default,){
final _that = this;
switch (_that) {
case _StatisticsHistoryState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<PerformanceHistoryHeader> projection,  CollectionMirror<PerformanceSample> samples)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StatisticsHistoryState() when $default != null:
return $default(_that.projection,_that.samples);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<PerformanceHistoryHeader> projection,  CollectionMirror<PerformanceSample> samples)  $default,) {final _that = this;
switch (_that) {
case _StatisticsHistoryState():
return $default(_that.projection,_that.samples);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<PerformanceHistoryHeader> projection,  CollectionMirror<PerformanceSample> samples)?  $default,) {final _that = this;
switch (_that) {
case _StatisticsHistoryState() when $default != null:
return $default(_that.projection,_that.samples);case _:
  return null;

}
}

}

/// @nodoc


class _StatisticsHistoryState implements StatisticsHistoryState {
  const _StatisticsHistoryState({required this.projection, required this.samples});


@override final  ProductProjection<PerformanceHistoryHeader> projection;
@override final  CollectionMirror<PerformanceSample> samples;

/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StatisticsHistoryStateCopyWith<_StatisticsHistoryState> get copyWith => __$StatisticsHistoryStateCopyWithImpl<_StatisticsHistoryState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StatisticsHistoryState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.samples, samples) || other.samples == samples));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,samples);
}



}

/// @nodoc
abstract mixin class _$StatisticsHistoryStateCopyWith<$Res> implements $StatisticsHistoryStateCopyWith<$Res> {
  factory _$StatisticsHistoryStateCopyWith(_StatisticsHistoryState value, $Res Function(_StatisticsHistoryState) _then) = __$StatisticsHistoryStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<PerformanceHistoryHeader> projection, CollectionMirror<PerformanceSample> samples
});


@override $ProductProjectionCopyWith<PerformanceHistoryHeader, $Res> get projection;@override $CollectionMirrorCopyWith<PerformanceSample, $Res> get samples;

}
/// @nodoc
class __$StatisticsHistoryStateCopyWithImpl<$Res>
    implements _$StatisticsHistoryStateCopyWith<$Res> {
  __$StatisticsHistoryStateCopyWithImpl(this._self, this._then);

  final _StatisticsHistoryState _self;
  final $Res Function(_StatisticsHistoryState) _then;

/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? samples = null,}) {
  return _then(_StatisticsHistoryState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PerformanceHistoryHeader>,samples: null == samples ? _self.samples : samples // ignore: cast_nullable_to_non_nullable
as CollectionMirror<PerformanceSample>,
  ));
}

/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PerformanceHistoryHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PerformanceHistoryHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of StatisticsHistoryState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<PerformanceSample, $Res> get samples {

  return $CollectionMirrorCopyWith<PerformanceSample, $Res>(_self.samples, (value) {
    return _then(_self.copyWith(samples: value));
  });
}
}

/// @nodoc
mixin _$SessionCostsState {

 ProductProjection<SessionCostsHeader> get projection; String get rootThreadId; ReadValue<SessionCost?, SessionCostsReadRef>? get cost;
/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsStateCopyWith<SessionCostsState> get copyWith => _$SessionCostsStateCopyWithImpl<SessionCostsState>(this as SessionCostsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCostsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.rootThreadId, _this.rootThreadId) || other.rootThreadId == _this.rootThreadId)&&(identical(other.cost, _this.cost) || other.cost == _this.cost));
}


@override
int get hashCode {
  final _this = this as SessionCostsState;
  return Object.hash(runtimeType,_this.projection,_this.rootThreadId,_this.cost);
}



}

/// @nodoc
abstract mixin class $SessionCostsStateCopyWith<$Res>  {
  factory $SessionCostsStateCopyWith(SessionCostsState value, $Res Function(SessionCostsState) _then) = _$SessionCostsStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<SessionCostsHeader> projection, String rootThreadId, ReadValue<SessionCost?, SessionCostsReadRef>? cost
});


$ProductProjectionCopyWith<SessionCostsHeader, $Res> get projection;$ReadValueCopyWith<SessionCost?, SessionCostsReadRef, $Res>? get cost;

}
/// @nodoc
class _$SessionCostsStateCopyWithImpl<$Res>
    implements $SessionCostsStateCopyWith<$Res> {
  _$SessionCostsStateCopyWithImpl(this._self, this._then);

  final SessionCostsState _self;
  final $Res Function(SessionCostsState) _then;

/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? rootThreadId = null,Object? cost = freezed,}) {
  return _then(SessionCostsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<SessionCostsHeader>,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,cost: freezed == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as ReadValue<SessionCost?, SessionCostsReadRef>?,
  ));
}
/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<SessionCostsHeader, $Res> get projection {

  return $ProductProjectionCopyWith<SessionCostsHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<SessionCost?, SessionCostsReadRef, $Res>? get cost {
    if (_self.cost == null) {
    return null;
  }

  return $ReadValueCopyWith<SessionCost?, SessionCostsReadRef, $Res>(_self.cost!, (value) {
    return _then(_self.copyWith(cost: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionCostsState].
extension SessionCostsStatePatterns on SessionCostsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionCostsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionCostsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionCostsState value)  $default,){
final _that = this;
switch (_that) {
case _SessionCostsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionCostsState value)?  $default,){
final _that = this;
switch (_that) {
case _SessionCostsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<SessionCostsHeader> projection,  String rootThreadId,  ReadValue<SessionCost?, SessionCostsReadRef>? cost)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionCostsState() when $default != null:
return $default(_that.projection,_that.rootThreadId,_that.cost);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<SessionCostsHeader> projection,  String rootThreadId,  ReadValue<SessionCost?, SessionCostsReadRef>? cost)  $default,) {final _that = this;
switch (_that) {
case _SessionCostsState():
return $default(_that.projection,_that.rootThreadId,_that.cost);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<SessionCostsHeader> projection,  String rootThreadId,  ReadValue<SessionCost?, SessionCostsReadRef>? cost)?  $default,) {final _that = this;
switch (_that) {
case _SessionCostsState() when $default != null:
return $default(_that.projection,_that.rootThreadId,_that.cost);case _:
  return null;

}
}

}

/// @nodoc


class _SessionCostsState implements SessionCostsState {
  const _SessionCostsState({required this.projection, required this.rootThreadId, required this.cost});


@override final  ProductProjection<SessionCostsHeader> projection;
@override final  String rootThreadId;
@override final  ReadValue<SessionCost?, SessionCostsReadRef>? cost;

/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionCostsStateCopyWith<_SessionCostsState> get copyWith => __$SessionCostsStateCopyWithImpl<_SessionCostsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionCostsState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.rootThreadId, rootThreadId) || other.rootThreadId == rootThreadId)&&(identical(other.cost, cost) || other.cost == cost));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,rootThreadId,cost);
}



}

/// @nodoc
abstract mixin class _$SessionCostsStateCopyWith<$Res> implements $SessionCostsStateCopyWith<$Res> {
  factory _$SessionCostsStateCopyWith(_SessionCostsState value, $Res Function(_SessionCostsState) _then) = __$SessionCostsStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<SessionCostsHeader> projection, String rootThreadId, ReadValue<SessionCost?, SessionCostsReadRef>? cost
});


@override $ProductProjectionCopyWith<SessionCostsHeader, $Res> get projection;@override $ReadValueCopyWith<SessionCost?, SessionCostsReadRef, $Res>? get cost;

}
/// @nodoc
class __$SessionCostsStateCopyWithImpl<$Res>
    implements _$SessionCostsStateCopyWith<$Res> {
  __$SessionCostsStateCopyWithImpl(this._self, this._then);

  final _SessionCostsState _self;
  final $Res Function(_SessionCostsState) _then;

/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? rootThreadId = null,Object? cost = freezed,}) {
  return _then(_SessionCostsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<SessionCostsHeader>,rootThreadId: null == rootThreadId ? _self.rootThreadId : rootThreadId // ignore: cast_nullable_to_non_nullable
as String,cost: freezed == cost ? _self.cost : cost // ignore: cast_nullable_to_non_nullable
as ReadValue<SessionCost?, SessionCostsReadRef>?,
  ));
}

/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<SessionCostsHeader, $Res> get projection {

  return $ProductProjectionCopyWith<SessionCostsHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of SessionCostsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<SessionCost?, SessionCostsReadRef, $Res>? get cost {
    if (_self.cost == null) {
    return null;
  }

  return $ReadValueCopyWith<SessionCost?, SessionCostsReadRef, $Res>(_self.cost!, (value) {
    return _then(_self.copyWith(cost: value));
  });
}
}

// dart format on
