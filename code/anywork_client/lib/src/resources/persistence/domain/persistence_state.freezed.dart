// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'persistence_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PersistenceReadRef {

 int get entry; int get revision;
/// Create a copy of PersistenceReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceReadRefCopyWith<PersistenceReadRef> get copyWith => _$PersistenceReadRefCopyWithImpl<PersistenceReadRef>(this as PersistenceReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as PersistenceReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as PersistenceReadRef;
  return 'PersistenceReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $PersistenceReadRefCopyWith<$Res>  {
  factory $PersistenceReadRefCopyWith(PersistenceReadRef value, $Res Function(PersistenceReadRef) _then) = _$PersistenceReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$PersistenceReadRefCopyWithImpl<$Res>
    implements $PersistenceReadRefCopyWith<$Res> {
  _$PersistenceReadRefCopyWithImpl(this._self, this._then);

  final PersistenceReadRef _self;
  final $Res Function(PersistenceReadRef) _then;

/// Create a copy of PersistenceReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(PersistenceReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PersistenceReadRef].
extension PersistenceReadRefPatterns on PersistenceReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceReadRef value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceReadRef() when $default != null:
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
case _PersistenceReadRef() when $default != null:
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
case _PersistenceReadRef():
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
case _PersistenceReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceReadRef implements PersistenceReadRef {
  const _PersistenceReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of PersistenceReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceReadRefCopyWith<_PersistenceReadRef> get copyWith => __$PersistenceReadRefCopyWithImpl<_PersistenceReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'PersistenceReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$PersistenceReadRefCopyWith<$Res> implements $PersistenceReadRefCopyWith<$Res> {
  factory _$PersistenceReadRefCopyWith(_PersistenceReadRef value, $Res Function(_PersistenceReadRef) _then) = __$PersistenceReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$PersistenceReadRefCopyWithImpl<$Res>
    implements _$PersistenceReadRefCopyWith<$Res> {
  __$PersistenceReadRefCopyWithImpl(this._self, this._then);

  final _PersistenceReadRef _self;
  final $Res Function(_PersistenceReadRef) _then;

/// Create a copy of PersistenceReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_PersistenceReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PersistenceReadTarget {

 ProductReadOrigin get origin; PersistenceReadRef get reference;
/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceReadTargetCopyWith<PersistenceReadTarget> get copyWith => _$PersistenceReadTargetCopyWithImpl<PersistenceReadTarget>(this as PersistenceReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as PersistenceReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as PersistenceReadTarget;
  return 'PersistenceReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $PersistenceReadTargetCopyWith<$Res>  {
  factory $PersistenceReadTargetCopyWith(PersistenceReadTarget value, $Res Function(PersistenceReadTarget) _then) = _$PersistenceReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, PersistenceReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$PersistenceReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PersistenceReadTargetCopyWithImpl<$Res>
    implements $PersistenceReadTargetCopyWith<$Res> {
  _$PersistenceReadTargetCopyWithImpl(this._self, this._then);

  final PersistenceReadTarget _self;
  final $Res Function(PersistenceReadTarget) _then;

/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(PersistenceReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PersistenceReadRef,
  ));
}
/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceReadRefCopyWith<$Res> get reference {

  return $PersistenceReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceReadTarget].
extension PersistenceReadTargetPatterns on PersistenceReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  PersistenceReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  PersistenceReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _PersistenceReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  PersistenceReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceReadTarget implements PersistenceReadTarget {
  const _PersistenceReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  PersistenceReadRef reference;

/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceReadTargetCopyWith<_PersistenceReadTarget> get copyWith => __$PersistenceReadTargetCopyWithImpl<_PersistenceReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'PersistenceReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$PersistenceReadTargetCopyWith<$Res> implements $PersistenceReadTargetCopyWith<$Res> {
  factory _$PersistenceReadTargetCopyWith(_PersistenceReadTarget value, $Res Function(_PersistenceReadTarget) _then) = __$PersistenceReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, PersistenceReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $PersistenceReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PersistenceReadTargetCopyWithImpl<$Res>
    implements _$PersistenceReadTargetCopyWith<$Res> {
  __$PersistenceReadTargetCopyWithImpl(this._self, this._then);

  final _PersistenceReadTarget _self;
  final $Res Function(_PersistenceReadTarget) _then;

/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_PersistenceReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PersistenceReadRef,
  ));
}

/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of PersistenceReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceReadRefCopyWith<$Res> get reference {

  return $PersistenceReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueReadRef {

 int get entry; int get revision;
/// Create a copy of PersistenceQueueReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueReadRefCopyWith<PersistenceQueueReadRef> get copyWith => _$PersistenceQueueReadRefCopyWithImpl<PersistenceQueueReadRef>(this as PersistenceQueueReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as PersistenceQueueReadRef;
  return 'PersistenceQueueReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $PersistenceQueueReadRefCopyWith<$Res>  {
  factory $PersistenceQueueReadRefCopyWith(PersistenceQueueReadRef value, $Res Function(PersistenceQueueReadRef) _then) = _$PersistenceQueueReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$PersistenceQueueReadRefCopyWithImpl<$Res>
    implements $PersistenceQueueReadRefCopyWith<$Res> {
  _$PersistenceQueueReadRefCopyWithImpl(this._self, this._then);

  final PersistenceQueueReadRef _self;
  final $Res Function(PersistenceQueueReadRef) _then;

/// Create a copy of PersistenceQueueReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(PersistenceQueueReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PersistenceQueueReadRef].
extension PersistenceQueueReadRefPatterns on PersistenceQueueReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueReadRef value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueReadRef() when $default != null:
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
case _PersistenceQueueReadRef() when $default != null:
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
case _PersistenceQueueReadRef():
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
case _PersistenceQueueReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueReadRef implements PersistenceQueueReadRef {
  const _PersistenceQueueReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of PersistenceQueueReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueReadRefCopyWith<_PersistenceQueueReadRef> get copyWith => __$PersistenceQueueReadRefCopyWithImpl<_PersistenceQueueReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'PersistenceQueueReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$PersistenceQueueReadRefCopyWith<$Res> implements $PersistenceQueueReadRefCopyWith<$Res> {
  factory _$PersistenceQueueReadRefCopyWith(_PersistenceQueueReadRef value, $Res Function(_PersistenceQueueReadRef) _then) = __$PersistenceQueueReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$PersistenceQueueReadRefCopyWithImpl<$Res>
    implements _$PersistenceQueueReadRefCopyWith<$Res> {
  __$PersistenceQueueReadRefCopyWithImpl(this._self, this._then);

  final _PersistenceQueueReadRef _self;
  final $Res Function(_PersistenceQueueReadRef) _then;

/// Create a copy of PersistenceQueueReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_PersistenceQueueReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PersistenceBrief {

 int get pendingCommits;
/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceBriefCopyWith<PersistenceBrief> get copyWith => _$PersistenceBriefCopyWithImpl<PersistenceBrief>(this as PersistenceBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceBrief&&(identical(other.pendingCommits, _this.pendingCommits) || other.pendingCommits == _this.pendingCommits));
}


@override
int get hashCode {
  final _this = this as PersistenceBrief;
  return Object.hash(runtimeType,_this.pendingCommits);
}



}

/// @nodoc
abstract mixin class $PersistenceBriefCopyWith<$Res>  {
  factory $PersistenceBriefCopyWith(PersistenceBrief value, $Res Function(PersistenceBrief) _then) = _$PersistenceBriefCopyWithImpl;
@useResult
$Res call({
 int pendingCommits
});




}
/// @nodoc
class _$PersistenceBriefCopyWithImpl<$Res>
    implements $PersistenceBriefCopyWith<$Res> {
  _$PersistenceBriefCopyWithImpl(this._self, this._then);

  final PersistenceBrief _self;
  final $Res Function(PersistenceBrief) _then;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? pendingCommits = null,}) {
  return _then(_self.copyWith(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [PersistenceBrief].
extension PersistenceBriefPatterns on PersistenceBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ReadyPersistenceBrief value)?  ready,TResult Function( FlushingPersistenceBrief value)?  flushing,TResult Function( DegradedPersistenceBrief value)?  degraded,TResult Function( RecoveringPersistenceBrief value)?  recovering,TResult Function( BlockedPersistenceBrief value)?  blocked,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ReadyPersistenceBrief() when ready != null:
return ready(_that);case FlushingPersistenceBrief() when flushing != null:
return flushing(_that);case DegradedPersistenceBrief() when degraded != null:
return degraded(_that);case RecoveringPersistenceBrief() when recovering != null:
return recovering(_that);case BlockedPersistenceBrief() when blocked != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ReadyPersistenceBrief value)  ready,required TResult Function( FlushingPersistenceBrief value)  flushing,required TResult Function( DegradedPersistenceBrief value)  degraded,required TResult Function( RecoveringPersistenceBrief value)  recovering,required TResult Function( BlockedPersistenceBrief value)  blocked,}){
final _that = this;
switch (_that) {
case ReadyPersistenceBrief():
return ready(_that);case FlushingPersistenceBrief():
return flushing(_that);case DegradedPersistenceBrief():
return degraded(_that);case RecoveringPersistenceBrief():
return recovering(_that);case BlockedPersistenceBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ReadyPersistenceBrief value)?  ready,TResult? Function( FlushingPersistenceBrief value)?  flushing,TResult? Function( DegradedPersistenceBrief value)?  degraded,TResult? Function( RecoveringPersistenceBrief value)?  recovering,TResult? Function( BlockedPersistenceBrief value)?  blocked,}){
final _that = this;
switch (_that) {
case ReadyPersistenceBrief() when ready != null:
return ready(_that);case FlushingPersistenceBrief() when flushing != null:
return flushing(_that);case DegradedPersistenceBrief() when degraded != null:
return degraded(_that);case RecoveringPersistenceBrief() when recovering != null:
return recovering(_that);case BlockedPersistenceBrief() when blocked != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int pendingCommits)?  ready,TResult Function( int pendingCommits,  int? oldestPendingRevision)?  flushing,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  degraded,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  recovering,TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  blocked,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ReadyPersistenceBrief() when ready != null:
return ready(_that.pendingCommits);case FlushingPersistenceBrief() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceBrief() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case RecoveringPersistenceBrief() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceBrief() when blocked != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int pendingCommits)  ready,required TResult Function( int pendingCommits,  int? oldestPendingRevision)  flushing,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)  degraded,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)  recovering,required TResult Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)  blocked,}) {final _that = this;
switch (_that) {
case ReadyPersistenceBrief():
return ready(_that.pendingCommits);case FlushingPersistenceBrief():
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceBrief():
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case RecoveringPersistenceBrief():
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceBrief():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int pendingCommits)?  ready,TResult? Function( int pendingCommits,  int? oldestPendingRevision)?  flushing,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  degraded,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  recovering,TResult? Function( int pendingCommits,  int? oldestPendingRevision,  int firstFailedAt)?  blocked,}) {final _that = this;
switch (_that) {
case ReadyPersistenceBrief() when ready != null:
return ready(_that.pendingCommits);case FlushingPersistenceBrief() when flushing != null:
return flushing(_that.pendingCommits,_that.oldestPendingRevision);case DegradedPersistenceBrief() when degraded != null:
return degraded(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case RecoveringPersistenceBrief() when recovering != null:
return recovering(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case BlockedPersistenceBrief() when blocked != null:
return blocked(_that.pendingCommits,_that.oldestPendingRevision,_that.firstFailedAt);case _:
  return null;

}
}

}

/// @nodoc


class ReadyPersistenceBrief implements PersistenceBrief {
  const ReadyPersistenceBrief({required this.pendingCommits});


@override final  int pendingCommits;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyPersistenceBriefCopyWith<ReadyPersistenceBrief> get copyWith => _$ReadyPersistenceBriefCopyWithImpl<ReadyPersistenceBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyPersistenceBrief&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits);
}



}

/// @nodoc
abstract mixin class $ReadyPersistenceBriefCopyWith<$Res> implements $PersistenceBriefCopyWith<$Res> {
  factory $ReadyPersistenceBriefCopyWith(ReadyPersistenceBrief value, $Res Function(ReadyPersistenceBrief) _then) = _$ReadyPersistenceBriefCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits
});




}
/// @nodoc
class _$ReadyPersistenceBriefCopyWithImpl<$Res>
    implements $ReadyPersistenceBriefCopyWith<$Res> {
  _$ReadyPersistenceBriefCopyWithImpl(this._self, this._then);

  final ReadyPersistenceBrief _self;
  final $Res Function(ReadyPersistenceBrief) _then;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,}) {
  return _then(ReadyPersistenceBrief(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FlushingPersistenceBrief implements PersistenceBrief {
  const FlushingPersistenceBrief({required this.pendingCommits, required this.oldestPendingRevision});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FlushingPersistenceBriefCopyWith<FlushingPersistenceBrief> get copyWith => _$FlushingPersistenceBriefCopyWithImpl<FlushingPersistenceBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FlushingPersistenceBrief&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision);
}



}

/// @nodoc
abstract mixin class $FlushingPersistenceBriefCopyWith<$Res> implements $PersistenceBriefCopyWith<$Res> {
  factory $FlushingPersistenceBriefCopyWith(FlushingPersistenceBrief value, $Res Function(FlushingPersistenceBrief) _then) = _$FlushingPersistenceBriefCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision
});




}
/// @nodoc
class _$FlushingPersistenceBriefCopyWithImpl<$Res>
    implements $FlushingPersistenceBriefCopyWith<$Res> {
  _$FlushingPersistenceBriefCopyWithImpl(this._self, this._then);

  final FlushingPersistenceBrief _self;
  final $Res Function(FlushingPersistenceBrief) _then;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,}) {
  return _then(FlushingPersistenceBrief(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class DegradedPersistenceBrief implements PersistenceBrief {
  const DegradedPersistenceBrief({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DegradedPersistenceBriefCopyWith<DegradedPersistenceBrief> get copyWith => _$DegradedPersistenceBriefCopyWithImpl<DegradedPersistenceBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DegradedPersistenceBrief&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}



}

/// @nodoc
abstract mixin class $DegradedPersistenceBriefCopyWith<$Res> implements $PersistenceBriefCopyWith<$Res> {
  factory $DegradedPersistenceBriefCopyWith(DegradedPersistenceBrief value, $Res Function(DegradedPersistenceBrief) _then) = _$DegradedPersistenceBriefCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt
});




}
/// @nodoc
class _$DegradedPersistenceBriefCopyWithImpl<$Res>
    implements $DegradedPersistenceBriefCopyWith<$Res> {
  _$DegradedPersistenceBriefCopyWithImpl(this._self, this._then);

  final DegradedPersistenceBrief _self;
  final $Res Function(DegradedPersistenceBrief) _then;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(DegradedPersistenceBrief(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RecoveringPersistenceBrief implements PersistenceBrief {
  const RecoveringPersistenceBrief({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveringPersistenceBriefCopyWith<RecoveringPersistenceBrief> get copyWith => _$RecoveringPersistenceBriefCopyWithImpl<RecoveringPersistenceBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveringPersistenceBrief&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}



}

/// @nodoc
abstract mixin class $RecoveringPersistenceBriefCopyWith<$Res> implements $PersistenceBriefCopyWith<$Res> {
  factory $RecoveringPersistenceBriefCopyWith(RecoveringPersistenceBrief value, $Res Function(RecoveringPersistenceBrief) _then) = _$RecoveringPersistenceBriefCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt
});




}
/// @nodoc
class _$RecoveringPersistenceBriefCopyWithImpl<$Res>
    implements $RecoveringPersistenceBriefCopyWith<$Res> {
  _$RecoveringPersistenceBriefCopyWithImpl(this._self, this._then);

  final RecoveringPersistenceBrief _self;
  final $Res Function(RecoveringPersistenceBrief) _then;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(RecoveringPersistenceBrief(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BlockedPersistenceBrief implements PersistenceBrief {
  const BlockedPersistenceBrief({required this.pendingCommits, required this.oldestPendingRevision, required this.firstFailedAt});


@override final  int pendingCommits;
 final  int? oldestPendingRevision;
 final  int firstFailedAt;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockedPersistenceBriefCopyWith<BlockedPersistenceBrief> get copyWith => _$BlockedPersistenceBriefCopyWithImpl<BlockedPersistenceBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockedPersistenceBrief&&(identical(other.pendingCommits, pendingCommits) || other.pendingCommits == pendingCommits)&&(identical(other.oldestPendingRevision, oldestPendingRevision) || other.oldestPendingRevision == oldestPendingRevision)&&(identical(other.firstFailedAt, firstFailedAt) || other.firstFailedAt == firstFailedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,pendingCommits,oldestPendingRevision,firstFailedAt);
}



}

/// @nodoc
abstract mixin class $BlockedPersistenceBriefCopyWith<$Res> implements $PersistenceBriefCopyWith<$Res> {
  factory $BlockedPersistenceBriefCopyWith(BlockedPersistenceBrief value, $Res Function(BlockedPersistenceBrief) _then) = _$BlockedPersistenceBriefCopyWithImpl;
@override @useResult
$Res call({
 int pendingCommits, int? oldestPendingRevision, int firstFailedAt
});




}
/// @nodoc
class _$BlockedPersistenceBriefCopyWithImpl<$Res>
    implements $BlockedPersistenceBriefCopyWith<$Res> {
  _$BlockedPersistenceBriefCopyWithImpl(this._self, this._then);

  final BlockedPersistenceBrief _self;
  final $Res Function(BlockedPersistenceBrief) _then;

/// Create a copy of PersistenceBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? pendingCommits = null,Object? oldestPendingRevision = freezed,Object? firstFailedAt = null,}) {
  return _then(BlockedPersistenceBrief(
pendingCommits: null == pendingCommits ? _self.pendingCommits : pendingCommits // ignore: cast_nullable_to_non_nullable
as int,oldestPendingRevision: freezed == oldestPendingRevision ? _self.oldestPendingRevision : oldestPendingRevision // ignore: cast_nullable_to_non_nullable
as int?,firstFailedAt: null == firstFailedAt ? _self.firstFailedAt : firstFailedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$PersistenceHeader {

 PersistenceReadRef get reference; int get revision; PersistenceBrief get state;
/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceHeaderCopyWith<PersistenceHeader> get copyWith => _$PersistenceHeaderCopyWithImpl<PersistenceHeader>(this as PersistenceHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceHeader&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as PersistenceHeader;
  return Object.hash(runtimeType,_this.reference,_this.revision,_this.state);
}

@override
String toString() {
  final _this = this as PersistenceHeader;
  return 'PersistenceHeader(reference: ${_this.reference}, revision: ${_this.revision}, state: ${_this.state})';
}


}

/// @nodoc
abstract mixin class $PersistenceHeaderCopyWith<$Res>  {
  factory $PersistenceHeaderCopyWith(PersistenceHeader value, $Res Function(PersistenceHeader) _then) = _$PersistenceHeaderCopyWithImpl;
@useResult
$Res call({
 PersistenceReadRef reference, int revision, PersistenceBrief state
});


$PersistenceReadRefCopyWith<$Res> get reference;$PersistenceBriefCopyWith<$Res> get state;

}
/// @nodoc
class _$PersistenceHeaderCopyWithImpl<$Res>
    implements $PersistenceHeaderCopyWith<$Res> {
  _$PersistenceHeaderCopyWithImpl(this._self, this._then);

  final PersistenceHeader _self;
  final $Res Function(PersistenceHeader) _then;

/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? revision = null,Object? state = null,}) {
  return _then(PersistenceHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PersistenceReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PersistenceBrief,
  ));
}
/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceReadRefCopyWith<$Res> get reference {

  return $PersistenceReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceBriefCopyWith<$Res> get state {

  return $PersistenceBriefCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceHeader].
extension PersistenceHeaderPatterns on PersistenceHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceHeader value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PersistenceReadRef reference,  int revision,  PersistenceBrief state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceHeader() when $default != null:
return $default(_that.reference,_that.revision,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PersistenceReadRef reference,  int revision,  PersistenceBrief state)  $default,) {final _that = this;
switch (_that) {
case _PersistenceHeader():
return $default(_that.reference,_that.revision,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PersistenceReadRef reference,  int revision,  PersistenceBrief state)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceHeader() when $default != null:
return $default(_that.reference,_that.revision,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceHeader implements PersistenceHeader {
  const _PersistenceHeader({required this.reference, required this.revision, required this.state});


@override final  PersistenceReadRef reference;
@override final  int revision;
@override final  PersistenceBrief state;

/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceHeaderCopyWith<_PersistenceHeader> get copyWith => __$PersistenceHeaderCopyWithImpl<_PersistenceHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceHeader&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,revision,state);
}

@override
String toString() {
    return 'PersistenceHeader(reference: $reference, revision: $revision, state: $state)';
}


}

/// @nodoc
abstract mixin class _$PersistenceHeaderCopyWith<$Res> implements $PersistenceHeaderCopyWith<$Res> {
  factory _$PersistenceHeaderCopyWith(_PersistenceHeader value, $Res Function(_PersistenceHeader) _then) = __$PersistenceHeaderCopyWithImpl;
@override @useResult
$Res call({
 PersistenceReadRef reference, int revision, PersistenceBrief state
});


@override $PersistenceReadRefCopyWith<$Res> get reference;@override $PersistenceBriefCopyWith<$Res> get state;

}
/// @nodoc
class __$PersistenceHeaderCopyWithImpl<$Res>
    implements _$PersistenceHeaderCopyWith<$Res> {
  __$PersistenceHeaderCopyWithImpl(this._self, this._then);

  final _PersistenceHeader _self;
  final $Res Function(_PersistenceHeader) _then;

/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? revision = null,Object? state = null,}) {
  return _then(_PersistenceHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PersistenceReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as PersistenceBrief,
  ));
}

/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceReadRefCopyWith<$Res> get reference {

  return $PersistenceReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of PersistenceHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceBriefCopyWith<$Res> get state {

  return $PersistenceBriefCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueHeader {

 PersistenceQueueReadRef get reference; int get revision; int get updatedAt; bool get statisticsGap; int get pendingOperations; int get pendingBytes; int get inFlightBytes; int? get oldestPendingAgeMillis; bool get pressurePaused; bool get hasLastError;
/// Create a copy of PersistenceQueueHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueHeaderCopyWith<PersistenceQueueHeader> get copyWith => _$PersistenceQueueHeaderCopyWithImpl<PersistenceQueueHeader>(this as PersistenceQueueHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueHeader&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.statisticsGap, _this.statisticsGap) || other.statisticsGap == _this.statisticsGap)&&(identical(other.pendingOperations, _this.pendingOperations) || other.pendingOperations == _this.pendingOperations)&&(identical(other.pendingBytes, _this.pendingBytes) || other.pendingBytes == _this.pendingBytes)&&(identical(other.inFlightBytes, _this.inFlightBytes) || other.inFlightBytes == _this.inFlightBytes)&&(identical(other.oldestPendingAgeMillis, _this.oldestPendingAgeMillis) || other.oldestPendingAgeMillis == _this.oldestPendingAgeMillis)&&(identical(other.pressurePaused, _this.pressurePaused) || other.pressurePaused == _this.pressurePaused)&&(identical(other.hasLastError, _this.hasLastError) || other.hasLastError == _this.hasLastError));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueHeader;
  return Object.hash(runtimeType,_this.reference,_this.revision,_this.updatedAt,_this.statisticsGap,_this.pendingOperations,_this.pendingBytes,_this.inFlightBytes,_this.oldestPendingAgeMillis,_this.pressurePaused,_this.hasLastError);
}

@override
String toString() {
  final _this = this as PersistenceQueueHeader;
  return 'PersistenceQueueHeader(reference: ${_this.reference}, revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, statisticsGap: ${_this.statisticsGap}, pendingOperations: ${_this.pendingOperations}, pendingBytes: ${_this.pendingBytes}, inFlightBytes: ${_this.inFlightBytes}, oldestPendingAgeMillis: ${_this.oldestPendingAgeMillis}, pressurePaused: ${_this.pressurePaused}, hasLastError: ${_this.hasLastError})';
}


}

/// @nodoc
abstract mixin class $PersistenceQueueHeaderCopyWith<$Res>  {
  factory $PersistenceQueueHeaderCopyWith(PersistenceQueueHeader value, $Res Function(PersistenceQueueHeader) _then) = _$PersistenceQueueHeaderCopyWithImpl;
@useResult
$Res call({
 PersistenceQueueReadRef reference, int revision, int updatedAt, bool statisticsGap, int pendingOperations, int pendingBytes, int inFlightBytes, int? oldestPendingAgeMillis, bool pressurePaused, bool hasLastError
});


$PersistenceQueueReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$PersistenceQueueHeaderCopyWithImpl<$Res>
    implements $PersistenceQueueHeaderCopyWith<$Res> {
  _$PersistenceQueueHeaderCopyWithImpl(this._self, this._then);

  final PersistenceQueueHeader _self;
  final $Res Function(PersistenceQueueHeader) _then;

/// Create a copy of PersistenceQueueHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? revision = null,Object? updatedAt = null,Object? statisticsGap = null,Object? pendingOperations = null,Object? pendingBytes = null,Object? inFlightBytes = null,Object? oldestPendingAgeMillis = freezed,Object? pressurePaused = null,Object? hasLastError = null,}) {
  return _then(PersistenceQueueHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PersistenceQueueReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,pendingOperations: null == pendingOperations ? _self.pendingOperations : pendingOperations // ignore: cast_nullable_to_non_nullable
as int,pendingBytes: null == pendingBytes ? _self.pendingBytes : pendingBytes // ignore: cast_nullable_to_non_nullable
as int,inFlightBytes: null == inFlightBytes ? _self.inFlightBytes : inFlightBytes // ignore: cast_nullable_to_non_nullable
as int,oldestPendingAgeMillis: freezed == oldestPendingAgeMillis ? _self.oldestPendingAgeMillis : oldestPendingAgeMillis // ignore: cast_nullable_to_non_nullable
as int?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,hasLastError: null == hasLastError ? _self.hasLastError : hasLastError // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of PersistenceQueueHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueReadRefCopyWith<$Res> get reference {

  return $PersistenceQueueReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueHeader].
extension PersistenceQueueHeaderPatterns on PersistenceQueueHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueHeader value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueHeader value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PersistenceQueueReadRef reference,  int revision,  int updatedAt,  bool statisticsGap,  int pendingOperations,  int pendingBytes,  int inFlightBytes,  int? oldestPendingAgeMillis,  bool pressurePaused,  bool hasLastError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceQueueHeader() when $default != null:
return $default(_that.reference,_that.revision,_that.updatedAt,_that.statisticsGap,_that.pendingOperations,_that.pendingBytes,_that.inFlightBytes,_that.oldestPendingAgeMillis,_that.pressurePaused,_that.hasLastError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PersistenceQueueReadRef reference,  int revision,  int updatedAt,  bool statisticsGap,  int pendingOperations,  int pendingBytes,  int inFlightBytes,  int? oldestPendingAgeMillis,  bool pressurePaused,  bool hasLastError)  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueHeader():
return $default(_that.reference,_that.revision,_that.updatedAt,_that.statisticsGap,_that.pendingOperations,_that.pendingBytes,_that.inFlightBytes,_that.oldestPendingAgeMillis,_that.pressurePaused,_that.hasLastError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PersistenceQueueReadRef reference,  int revision,  int updatedAt,  bool statisticsGap,  int pendingOperations,  int pendingBytes,  int inFlightBytes,  int? oldestPendingAgeMillis,  bool pressurePaused,  bool hasLastError)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueHeader() when $default != null:
return $default(_that.reference,_that.revision,_that.updatedAt,_that.statisticsGap,_that.pendingOperations,_that.pendingBytes,_that.inFlightBytes,_that.oldestPendingAgeMillis,_that.pressurePaused,_that.hasLastError);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueHeader implements PersistenceQueueHeader {
  const _PersistenceQueueHeader({required this.reference, required this.revision, required this.updatedAt, required this.statisticsGap, required this.pendingOperations, required this.pendingBytes, required this.inFlightBytes, required this.oldestPendingAgeMillis, required this.pressurePaused, required this.hasLastError});


@override final  PersistenceQueueReadRef reference;
@override final  int revision;
@override final  int updatedAt;
@override final  bool statisticsGap;
@override final  int pendingOperations;
@override final  int pendingBytes;
@override final  int inFlightBytes;
@override final  int? oldestPendingAgeMillis;
@override final  bool pressurePaused;
@override final  bool hasLastError;

/// Create a copy of PersistenceQueueHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueHeaderCopyWith<_PersistenceQueueHeader> get copyWith => __$PersistenceQueueHeaderCopyWithImpl<_PersistenceQueueHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueHeader&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.statisticsGap, statisticsGap) || other.statisticsGap == statisticsGap)&&(identical(other.pendingOperations, pendingOperations) || other.pendingOperations == pendingOperations)&&(identical(other.pendingBytes, pendingBytes) || other.pendingBytes == pendingBytes)&&(identical(other.inFlightBytes, inFlightBytes) || other.inFlightBytes == inFlightBytes)&&(identical(other.oldestPendingAgeMillis, oldestPendingAgeMillis) || other.oldestPendingAgeMillis == oldestPendingAgeMillis)&&(identical(other.pressurePaused, pressurePaused) || other.pressurePaused == pressurePaused)&&(identical(other.hasLastError, hasLastError) || other.hasLastError == hasLastError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,revision,updatedAt,statisticsGap,pendingOperations,pendingBytes,inFlightBytes,oldestPendingAgeMillis,pressurePaused,hasLastError);
}

@override
String toString() {
    return 'PersistenceQueueHeader(reference: $reference, revision: $revision, updatedAt: $updatedAt, statisticsGap: $statisticsGap, pendingOperations: $pendingOperations, pendingBytes: $pendingBytes, inFlightBytes: $inFlightBytes, oldestPendingAgeMillis: $oldestPendingAgeMillis, pressurePaused: $pressurePaused, hasLastError: $hasLastError)';
}


}

/// @nodoc
abstract mixin class _$PersistenceQueueHeaderCopyWith<$Res> implements $PersistenceQueueHeaderCopyWith<$Res> {
  factory _$PersistenceQueueHeaderCopyWith(_PersistenceQueueHeader value, $Res Function(_PersistenceQueueHeader) _then) = __$PersistenceQueueHeaderCopyWithImpl;
@override @useResult
$Res call({
 PersistenceQueueReadRef reference, int revision, int updatedAt, bool statisticsGap, int pendingOperations, int pendingBytes, int inFlightBytes, int? oldestPendingAgeMillis, bool pressurePaused, bool hasLastError
});


@override $PersistenceQueueReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$PersistenceQueueHeaderCopyWithImpl<$Res>
    implements _$PersistenceQueueHeaderCopyWith<$Res> {
  __$PersistenceQueueHeaderCopyWithImpl(this._self, this._then);

  final _PersistenceQueueHeader _self;
  final $Res Function(_PersistenceQueueHeader) _then;

/// Create a copy of PersistenceQueueHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? revision = null,Object? updatedAt = null,Object? statisticsGap = null,Object? pendingOperations = null,Object? pendingBytes = null,Object? inFlightBytes = null,Object? oldestPendingAgeMillis = freezed,Object? pressurePaused = null,Object? hasLastError = null,}) {
  return _then(_PersistenceQueueHeader(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as PersistenceQueueReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,statisticsGap: null == statisticsGap ? _self.statisticsGap : statisticsGap // ignore: cast_nullable_to_non_nullable
as bool,pendingOperations: null == pendingOperations ? _self.pendingOperations : pendingOperations // ignore: cast_nullable_to_non_nullable
as int,pendingBytes: null == pendingBytes ? _self.pendingBytes : pendingBytes // ignore: cast_nullable_to_non_nullable
as int,inFlightBytes: null == inFlightBytes ? _self.inFlightBytes : inFlightBytes // ignore: cast_nullable_to_non_nullable
as int,oldestPendingAgeMillis: freezed == oldestPendingAgeMillis ? _self.oldestPendingAgeMillis : oldestPendingAgeMillis // ignore: cast_nullable_to_non_nullable
as int?,pressurePaused: null == pressurePaused ? _self.pressurePaused : pressurePaused // ignore: cast_nullable_to_non_nullable
as bool,hasLastError: null == hasLastError ? _self.hasLastError : hasLastError // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of PersistenceQueueHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueReadRefCopyWith<$Res> get reference {

  return $PersistenceQueueReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PersistenceState {

 ProductProjection<PersistenceHeader> get projection; ReadValue<PersistenceValue, PersistenceReadRef>? get value;
/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceStateCopyWith<PersistenceState> get copyWith => _$PersistenceStateCopyWithImpl<PersistenceState>(this as PersistenceState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as PersistenceState;
  return Object.hash(runtimeType,_this.projection,_this.value);
}



}

/// @nodoc
abstract mixin class $PersistenceStateCopyWith<$Res>  {
  factory $PersistenceStateCopyWith(PersistenceState value, $Res Function(PersistenceState) _then) = _$PersistenceStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<PersistenceHeader> projection, ReadValue<PersistenceValue, PersistenceReadRef>? value
});


$ProductProjectionCopyWith<PersistenceHeader, $Res> get projection;$ReadValueCopyWith<PersistenceValue, PersistenceReadRef, $Res>? get value;

}
/// @nodoc
class _$PersistenceStateCopyWithImpl<$Res>
    implements $PersistenceStateCopyWith<$Res> {
  _$PersistenceStateCopyWithImpl(this._self, this._then);

  final PersistenceState _self;
  final $Res Function(PersistenceState) _then;

/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? value = freezed,}) {
  return _then(PersistenceState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PersistenceHeader>,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadValue<PersistenceValue, PersistenceReadRef>?,
  ));
}
/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PersistenceHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PersistenceHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<PersistenceValue, PersistenceReadRef, $Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ReadValueCopyWith<PersistenceValue, PersistenceReadRef, $Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceState].
extension PersistenceStatePatterns on PersistenceState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceState value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceState value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<PersistenceHeader> projection,  ReadValue<PersistenceValue, PersistenceReadRef>? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceState() when $default != null:
return $default(_that.projection,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<PersistenceHeader> projection,  ReadValue<PersistenceValue, PersistenceReadRef>? value)  $default,) {final _that = this;
switch (_that) {
case _PersistenceState():
return $default(_that.projection,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<PersistenceHeader> projection,  ReadValue<PersistenceValue, PersistenceReadRef>? value)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceState() when $default != null:
return $default(_that.projection,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceState implements PersistenceState {
  const _PersistenceState({required this.projection, required this.value});


@override final  ProductProjection<PersistenceHeader> projection;
@override final  ReadValue<PersistenceValue, PersistenceReadRef>? value;

/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceStateCopyWith<_PersistenceState> get copyWith => __$PersistenceStateCopyWithImpl<_PersistenceState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,value);
}



}

/// @nodoc
abstract mixin class _$PersistenceStateCopyWith<$Res> implements $PersistenceStateCopyWith<$Res> {
  factory _$PersistenceStateCopyWith(_PersistenceState value, $Res Function(_PersistenceState) _then) = __$PersistenceStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<PersistenceHeader> projection, ReadValue<PersistenceValue, PersistenceReadRef>? value
});


@override $ProductProjectionCopyWith<PersistenceHeader, $Res> get projection;@override $ReadValueCopyWith<PersistenceValue, PersistenceReadRef, $Res>? get value;

}
/// @nodoc
class __$PersistenceStateCopyWithImpl<$Res>
    implements _$PersistenceStateCopyWith<$Res> {
  __$PersistenceStateCopyWithImpl(this._self, this._then);

  final _PersistenceState _self;
  final $Res Function(_PersistenceState) _then;

/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? value = freezed,}) {
  return _then(_PersistenceState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PersistenceHeader>,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadValue<PersistenceValue, PersistenceReadRef>?,
  ));
}

/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PersistenceHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PersistenceHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of PersistenceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<PersistenceValue, PersistenceReadRef, $Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ReadValueCopyWith<PersistenceValue, PersistenceReadRef, $Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueState {

 ProductProjection<PersistenceQueueHeader> get projection; CollectionMirror<ThreadPersistenceSnapshot> get threads; ReadValue<String?, PersistenceQueueReadRef>? get lastError;
/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueStateCopyWith<PersistenceQueueState> get copyWith => _$PersistenceQueueStateCopyWithImpl<PersistenceQueueState>(this as PersistenceQueueState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.threads, _this.threads) || other.threads == _this.threads)&&(identical(other.lastError, _this.lastError) || other.lastError == _this.lastError));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueState;
  return Object.hash(runtimeType,_this.projection,_this.threads,_this.lastError);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueStateCopyWith<$Res>  {
  factory $PersistenceQueueStateCopyWith(PersistenceQueueState value, $Res Function(PersistenceQueueState) _then) = _$PersistenceQueueStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<PersistenceQueueHeader> projection, CollectionMirror<ThreadPersistenceSnapshot> threads, ReadValue<String?, PersistenceQueueReadRef>? lastError
});


$ProductProjectionCopyWith<PersistenceQueueHeader, $Res> get projection;$CollectionMirrorCopyWith<ThreadPersistenceSnapshot, $Res> get threads;$ReadValueCopyWith<String?, PersistenceQueueReadRef, $Res>? get lastError;

}
/// @nodoc
class _$PersistenceQueueStateCopyWithImpl<$Res>
    implements $PersistenceQueueStateCopyWith<$Res> {
  _$PersistenceQueueStateCopyWithImpl(this._self, this._then);

  final PersistenceQueueState _self;
  final $Res Function(PersistenceQueueState) _then;

/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? threads = null,Object? lastError = freezed,}) {
  return _then(PersistenceQueueState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PersistenceQueueHeader>,threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as CollectionMirror<ThreadPersistenceSnapshot>,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as ReadValue<String?, PersistenceQueueReadRef>?,
  ));
}
/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PersistenceQueueHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PersistenceQueueHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<ThreadPersistenceSnapshot, $Res> get threads {

  return $CollectionMirrorCopyWith<ThreadPersistenceSnapshot, $Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String?, PersistenceQueueReadRef, $Res>? get lastError {
    if (_self.lastError == null) {
    return null;
  }

  return $ReadValueCopyWith<String?, PersistenceQueueReadRef, $Res>(_self.lastError!, (value) {
    return _then(_self.copyWith(lastError: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueState].
extension PersistenceQueueStatePatterns on PersistenceQueueState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueState value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueState value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<PersistenceQueueHeader> projection,  CollectionMirror<ThreadPersistenceSnapshot> threads,  ReadValue<String?, PersistenceQueueReadRef>? lastError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceQueueState() when $default != null:
return $default(_that.projection,_that.threads,_that.lastError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<PersistenceQueueHeader> projection,  CollectionMirror<ThreadPersistenceSnapshot> threads,  ReadValue<String?, PersistenceQueueReadRef>? lastError)  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueState():
return $default(_that.projection,_that.threads,_that.lastError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<PersistenceQueueHeader> projection,  CollectionMirror<ThreadPersistenceSnapshot> threads,  ReadValue<String?, PersistenceQueueReadRef>? lastError)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueState() when $default != null:
return $default(_that.projection,_that.threads,_that.lastError);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueState implements PersistenceQueueState {
  const _PersistenceQueueState({required this.projection, required this.threads, required this.lastError});


@override final  ProductProjection<PersistenceQueueHeader> projection;
@override final  CollectionMirror<ThreadPersistenceSnapshot> threads;
@override final  ReadValue<String?, PersistenceQueueReadRef>? lastError;

/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueStateCopyWith<_PersistenceQueueState> get copyWith => __$PersistenceQueueStateCopyWithImpl<_PersistenceQueueState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.threads, threads) || other.threads == threads)&&(identical(other.lastError, lastError) || other.lastError == lastError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,threads,lastError);
}



}

/// @nodoc
abstract mixin class _$PersistenceQueueStateCopyWith<$Res> implements $PersistenceQueueStateCopyWith<$Res> {
  factory _$PersistenceQueueStateCopyWith(_PersistenceQueueState value, $Res Function(_PersistenceQueueState) _then) = __$PersistenceQueueStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<PersistenceQueueHeader> projection, CollectionMirror<ThreadPersistenceSnapshot> threads, ReadValue<String?, PersistenceQueueReadRef>? lastError
});


@override $ProductProjectionCopyWith<PersistenceQueueHeader, $Res> get projection;@override $CollectionMirrorCopyWith<ThreadPersistenceSnapshot, $Res> get threads;@override $ReadValueCopyWith<String?, PersistenceQueueReadRef, $Res>? get lastError;

}
/// @nodoc
class __$PersistenceQueueStateCopyWithImpl<$Res>
    implements _$PersistenceQueueStateCopyWith<$Res> {
  __$PersistenceQueueStateCopyWithImpl(this._self, this._then);

  final _PersistenceQueueState _self;
  final $Res Function(_PersistenceQueueState) _then;

/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? threads = null,Object? lastError = freezed,}) {
  return _then(_PersistenceQueueState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<PersistenceQueueHeader>,threads: null == threads ? _self.threads : threads // ignore: cast_nullable_to_non_nullable
as CollectionMirror<ThreadPersistenceSnapshot>,lastError: freezed == lastError ? _self.lastError : lastError // ignore: cast_nullable_to_non_nullable
as ReadValue<String?, PersistenceQueueReadRef>?,
  ));
}

/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<PersistenceQueueHeader, $Res> get projection {

  return $ProductProjectionCopyWith<PersistenceQueueHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<ThreadPersistenceSnapshot, $Res> get threads {

  return $CollectionMirrorCopyWith<ThreadPersistenceSnapshot, $Res>(_self.threads, (value) {
    return _then(_self.copyWith(threads: value));
  });
}/// Create a copy of PersistenceQueueState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String?, PersistenceQueueReadRef, $Res>? get lastError {
    if (_self.lastError == null) {
    return null;
  }

  return $ReadValueCopyWith<String?, PersistenceQueueReadRef, $Res>(_self.lastError!, (value) {
    return _then(_self.copyWith(lastError: value));
  });
}
}

// dart format on
