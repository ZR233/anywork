// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_costs_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
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
