// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'modes_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModeCatalogReadRef {

 int get entry; int get revision;
/// Create a copy of ModeCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogReadRefCopyWith<ModeCatalogReadRef> get copyWith => _$ModeCatalogReadRefCopyWithImpl<ModeCatalogReadRef>(this as ModeCatalogReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ModeCatalogReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ModeCatalogReadRef;
  return 'ModeCatalogReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ModeCatalogReadRefCopyWith<$Res>  {
  factory $ModeCatalogReadRefCopyWith(ModeCatalogReadRef value, $Res Function(ModeCatalogReadRef) _then) = _$ModeCatalogReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ModeCatalogReadRefCopyWithImpl<$Res>
    implements $ModeCatalogReadRefCopyWith<$Res> {
  _$ModeCatalogReadRefCopyWithImpl(this._self, this._then);

  final ModeCatalogReadRef _self;
  final $Res Function(ModeCatalogReadRef) _then;

/// Create a copy of ModeCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ModeCatalogReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ModeCatalogReadRef].
extension ModeCatalogReadRefPatterns on ModeCatalogReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogReadRef() when $default != null:
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
case _ModeCatalogReadRef() when $default != null:
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
case _ModeCatalogReadRef():
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
case _ModeCatalogReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogReadRef implements ModeCatalogReadRef {
  const _ModeCatalogReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ModeCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogReadRefCopyWith<_ModeCatalogReadRef> get copyWith => __$ModeCatalogReadRefCopyWithImpl<_ModeCatalogReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ModeCatalogReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ModeCatalogReadRefCopyWith<$Res> implements $ModeCatalogReadRefCopyWith<$Res> {
  factory _$ModeCatalogReadRefCopyWith(_ModeCatalogReadRef value, $Res Function(_ModeCatalogReadRef) _then) = __$ModeCatalogReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ModeCatalogReadRefCopyWithImpl<$Res>
    implements _$ModeCatalogReadRefCopyWith<$Res> {
  __$ModeCatalogReadRefCopyWithImpl(this._self, this._then);

  final _ModeCatalogReadRef _self;
  final $Res Function(_ModeCatalogReadRef) _then;

/// Create a copy of ModeCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ModeCatalogReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ModeCatalogReadTarget {

 ProductReadOrigin get origin; ModeCatalogReadRef get reference;
/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogReadTargetCopyWith<ModeCatalogReadTarget> get copyWith => _$ModeCatalogReadTargetCopyWithImpl<ModeCatalogReadTarget>(this as ModeCatalogReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ModeCatalogReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as ModeCatalogReadTarget;
  return 'ModeCatalogReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ModeCatalogReadTargetCopyWith<$Res>  {
  factory $ModeCatalogReadTargetCopyWith(ModeCatalogReadTarget value, $Res Function(ModeCatalogReadTarget) _then) = _$ModeCatalogReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, ModeCatalogReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$ModeCatalogReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ModeCatalogReadTargetCopyWithImpl<$Res>
    implements $ModeCatalogReadTargetCopyWith<$Res> {
  _$ModeCatalogReadTargetCopyWithImpl(this._self, this._then);

  final ModeCatalogReadTarget _self;
  final $Res Function(ModeCatalogReadTarget) _then;

/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(ModeCatalogReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadRef,
  ));
}
/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadRefCopyWith<$Res> get reference {

  return $ModeCatalogReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogReadTarget].
extension ModeCatalogReadTargetPatterns on ModeCatalogReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ModeCatalogReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeCatalogReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ModeCatalogReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  ModeCatalogReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogReadTarget implements ModeCatalogReadTarget {
  const _ModeCatalogReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  ModeCatalogReadRef reference;

/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogReadTargetCopyWith<_ModeCatalogReadTarget> get copyWith => __$ModeCatalogReadTargetCopyWithImpl<_ModeCatalogReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'ModeCatalogReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ModeCatalogReadTargetCopyWith<$Res> implements $ModeCatalogReadTargetCopyWith<$Res> {
  factory _$ModeCatalogReadTargetCopyWith(_ModeCatalogReadTarget value, $Res Function(_ModeCatalogReadTarget) _then) = __$ModeCatalogReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, ModeCatalogReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $ModeCatalogReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ModeCatalogReadTargetCopyWithImpl<$Res>
    implements _$ModeCatalogReadTargetCopyWith<$Res> {
  __$ModeCatalogReadTargetCopyWithImpl(this._self, this._then);

  final _ModeCatalogReadTarget _self;
  final $Res Function(_ModeCatalogReadTarget) _then;

/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_ModeCatalogReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadRef,
  ));
}

/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ModeCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadRefCopyWith<$Res> get reference {

  return $ModeCatalogReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ModeCatalogHeader {

 int get revision; ModeCatalogReadRef get reference;
/// Create a copy of ModeCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeCatalogHeaderCopyWith<ModeCatalogHeader> get copyWith => _$ModeCatalogHeaderCopyWithImpl<ModeCatalogHeader>(this as ModeCatalogHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeCatalogHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeCatalogHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ModeCatalogHeader;
  return Object.hash(runtimeType,_this.revision,_this.reference);
}

@override
String toString() {
  final _this = this as ModeCatalogHeader;
  return 'ModeCatalogHeader(revision: ${_this.revision}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ModeCatalogHeaderCopyWith<$Res>  {
  factory $ModeCatalogHeaderCopyWith(ModeCatalogHeader value, $Res Function(ModeCatalogHeader) _then) = _$ModeCatalogHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, ModeCatalogReadRef reference
});


$ModeCatalogReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ModeCatalogHeaderCopyWithImpl<$Res>
    implements $ModeCatalogHeaderCopyWith<$Res> {
  _$ModeCatalogHeaderCopyWithImpl(this._self, this._then);

  final ModeCatalogHeader _self;
  final $Res Function(ModeCatalogHeader) _then;

/// Create a copy of ModeCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? reference = null,}) {
  return _then(ModeCatalogHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadRef,
  ));
}
/// Create a copy of ModeCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadRefCopyWith<$Res> get reference {

  return $ModeCatalogReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeCatalogHeader].
extension ModeCatalogHeaderPatterns on ModeCatalogHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeCatalogHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeCatalogHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeCatalogHeader value)  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeCatalogHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ModeCatalogHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  ModeCatalogReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeCatalogHeader() when $default != null:
return $default(_that.revision,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  ModeCatalogReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogHeader():
return $default(_that.revision,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  ModeCatalogReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _ModeCatalogHeader() when $default != null:
return $default(_that.revision,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ModeCatalogHeader implements ModeCatalogHeader {
  const _ModeCatalogHeader({required this.revision, required this.reference});


@override final  int revision;
@override final  ModeCatalogReadRef reference;

/// Create a copy of ModeCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeCatalogHeaderCopyWith<_ModeCatalogHeader> get copyWith => __$ModeCatalogHeaderCopyWithImpl<_ModeCatalogHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeCatalogHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,reference);
}

@override
String toString() {
    return 'ModeCatalogHeader(revision: $revision, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ModeCatalogHeaderCopyWith<$Res> implements $ModeCatalogHeaderCopyWith<$Res> {
  factory _$ModeCatalogHeaderCopyWith(_ModeCatalogHeader value, $Res Function(_ModeCatalogHeader) _then) = __$ModeCatalogHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, ModeCatalogReadRef reference
});


@override $ModeCatalogReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ModeCatalogHeaderCopyWithImpl<$Res>
    implements _$ModeCatalogHeaderCopyWith<$Res> {
  __$ModeCatalogHeaderCopyWithImpl(this._self, this._then);

  final _ModeCatalogHeader _self;
  final $Res Function(_ModeCatalogHeader) _then;

/// Create a copy of ModeCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? reference = null,}) {
  return _then(_ModeCatalogHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadRef,
  ));
}

/// Create a copy of ModeCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadRefCopyWith<$Res> get reference {

  return $ModeCatalogReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ModesState {

 ProductProjection<ModeCatalogHeader> get projection; CollectionMirror<ThreadModeDescriptor> get modes;
/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModesStateCopyWith<ModesState> get copyWith => _$ModesStateCopyWithImpl<ModesState>(this as ModesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModesState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.modes, _this.modes) || other.modes == _this.modes));
}


@override
int get hashCode {
  final _this = this as ModesState;
  return Object.hash(runtimeType,_this.projection,_this.modes);
}



}

/// @nodoc
abstract mixin class $ModesStateCopyWith<$Res>  {
  factory $ModesStateCopyWith(ModesState value, $Res Function(ModesState) _then) = _$ModesStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<ModeCatalogHeader> projection, CollectionMirror<ThreadModeDescriptor> modes
});


$ProductProjectionCopyWith<ModeCatalogHeader, $Res> get projection;$CollectionMirrorCopyWith<ThreadModeDescriptor, $Res> get modes;

}
/// @nodoc
class _$ModesStateCopyWithImpl<$Res>
    implements $ModesStateCopyWith<$Res> {
  _$ModesStateCopyWithImpl(this._self, this._then);

  final ModesState _self;
  final $Res Function(ModesState) _then;

/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? modes = null,}) {
  return _then(ModesState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ModeCatalogHeader>,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as CollectionMirror<ThreadModeDescriptor>,
  ));
}
/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ModeCatalogHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ModeCatalogHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<ThreadModeDescriptor, $Res> get modes {

  return $CollectionMirrorCopyWith<ThreadModeDescriptor, $Res>(_self.modes, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModesState].
extension ModesStatePatterns on ModesState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModesState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModesState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModesState value)  $default,){
final _that = this;
switch (_that) {
case _ModesState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModesState value)?  $default,){
final _that = this;
switch (_that) {
case _ModesState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<ModeCatalogHeader> projection,  CollectionMirror<ThreadModeDescriptor> modes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModesState() when $default != null:
return $default(_that.projection,_that.modes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<ModeCatalogHeader> projection,  CollectionMirror<ThreadModeDescriptor> modes)  $default,) {final _that = this;
switch (_that) {
case _ModesState():
return $default(_that.projection,_that.modes);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<ModeCatalogHeader> projection,  CollectionMirror<ThreadModeDescriptor> modes)?  $default,) {final _that = this;
switch (_that) {
case _ModesState() when $default != null:
return $default(_that.projection,_that.modes);case _:
  return null;

}
}

}

/// @nodoc


class _ModesState implements ModesState {
  const _ModesState({required this.projection, required this.modes});


@override final  ProductProjection<ModeCatalogHeader> projection;
@override final  CollectionMirror<ThreadModeDescriptor> modes;

/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModesStateCopyWith<_ModesState> get copyWith => __$ModesStateCopyWithImpl<_ModesState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModesState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.modes, modes) || other.modes == modes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,modes);
}



}

/// @nodoc
abstract mixin class _$ModesStateCopyWith<$Res> implements $ModesStateCopyWith<$Res> {
  factory _$ModesStateCopyWith(_ModesState value, $Res Function(_ModesState) _then) = __$ModesStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<ModeCatalogHeader> projection, CollectionMirror<ThreadModeDescriptor> modes
});


@override $ProductProjectionCopyWith<ModeCatalogHeader, $Res> get projection;@override $CollectionMirrorCopyWith<ThreadModeDescriptor, $Res> get modes;

}
/// @nodoc
class __$ModesStateCopyWithImpl<$Res>
    implements _$ModesStateCopyWith<$Res> {
  __$ModesStateCopyWithImpl(this._self, this._then);

  final _ModesState _self;
  final $Res Function(_ModesState) _then;

/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? modes = null,}) {
  return _then(_ModesState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ModeCatalogHeader>,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as CollectionMirror<ThreadModeDescriptor>,
  ));
}

/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ModeCatalogHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ModeCatalogHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ModesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<ThreadModeDescriptor, $Res> get modes {

  return $CollectionMirrorCopyWith<ThreadModeDescriptor, $Res>(_self.modes, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}

/// @nodoc
mixin _$ModeDefinitionResult {

 ModeCatalogReadTarget get catalog; ModeDefinitionSnapshot? get definition;
/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModeDefinitionResultCopyWith<ModeDefinitionResult> get copyWith => _$ModeDefinitionResultCopyWithImpl<ModeDefinitionResult>(this as ModeDefinitionResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModeDefinitionResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModeDefinitionResult&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.definition, _this.definition) || other.definition == _this.definition));
}


@override
int get hashCode {
  final _this = this as ModeDefinitionResult;
  return Object.hash(runtimeType,_this.catalog,_this.definition);
}



}

/// @nodoc
abstract mixin class $ModeDefinitionResultCopyWith<$Res>  {
  factory $ModeDefinitionResultCopyWith(ModeDefinitionResult value, $Res Function(ModeDefinitionResult) _then) = _$ModeDefinitionResultCopyWithImpl;
@useResult
$Res call({
 ModeCatalogReadTarget catalog, ModeDefinitionSnapshot? definition
});


$ModeCatalogReadTargetCopyWith<$Res> get catalog;$ModeDefinitionSnapshotCopyWith<$Res>? get definition;

}
/// @nodoc
class _$ModeDefinitionResultCopyWithImpl<$Res>
    implements $ModeDefinitionResultCopyWith<$Res> {
  _$ModeDefinitionResultCopyWithImpl(this._self, this._then);

  final ModeDefinitionResult _self;
  final $Res Function(ModeDefinitionResult) _then;

/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? catalog = null,Object? definition = freezed,}) {
  return _then(ModeDefinitionResult(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadTarget,definition: freezed == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as ModeDefinitionSnapshot?,
  ));
}
/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModeCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDefinitionSnapshotCopyWith<$Res>? get definition {
    if (_self.definition == null) {
    return null;
  }

  return $ModeDefinitionSnapshotCopyWith<$Res>(_self.definition!, (value) {
    return _then(_self.copyWith(definition: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModeDefinitionResult].
extension ModeDefinitionResultPatterns on ModeDefinitionResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModeDefinitionResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModeDefinitionResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModeDefinitionResult value)  $default,){
final _that = this;
switch (_that) {
case _ModeDefinitionResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModeDefinitionResult value)?  $default,){
final _that = this;
switch (_that) {
case _ModeDefinitionResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ModeCatalogReadTarget catalog,  ModeDefinitionSnapshot? definition)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModeDefinitionResult() when $default != null:
return $default(_that.catalog,_that.definition);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ModeCatalogReadTarget catalog,  ModeDefinitionSnapshot? definition)  $default,) {final _that = this;
switch (_that) {
case _ModeDefinitionResult():
return $default(_that.catalog,_that.definition);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ModeCatalogReadTarget catalog,  ModeDefinitionSnapshot? definition)?  $default,) {final _that = this;
switch (_that) {
case _ModeDefinitionResult() when $default != null:
return $default(_that.catalog,_that.definition);case _:
  return null;

}
}

}

/// @nodoc


class _ModeDefinitionResult implements ModeDefinitionResult {
  const _ModeDefinitionResult({required this.catalog, required this.definition});


@override final  ModeCatalogReadTarget catalog;
@override final  ModeDefinitionSnapshot? definition;

/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModeDefinitionResultCopyWith<_ModeDefinitionResult> get copyWith => __$ModeDefinitionResultCopyWithImpl<_ModeDefinitionResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModeDefinitionResult&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.definition, definition) || other.definition == definition));
}


@override
int get hashCode {
    return Object.hash(runtimeType,catalog,definition);
}



}

/// @nodoc
abstract mixin class _$ModeDefinitionResultCopyWith<$Res> implements $ModeDefinitionResultCopyWith<$Res> {
  factory _$ModeDefinitionResultCopyWith(_ModeDefinitionResult value, $Res Function(_ModeDefinitionResult) _then) = __$ModeDefinitionResultCopyWithImpl;
@override @useResult
$Res call({
 ModeCatalogReadTarget catalog, ModeDefinitionSnapshot? definition
});


@override $ModeCatalogReadTargetCopyWith<$Res> get catalog;@override $ModeDefinitionSnapshotCopyWith<$Res>? get definition;

}
/// @nodoc
class __$ModeDefinitionResultCopyWithImpl<$Res>
    implements _$ModeDefinitionResultCopyWith<$Res> {
  __$ModeDefinitionResultCopyWithImpl(this._self, this._then);

  final _ModeDefinitionResult _self;
  final $Res Function(_ModeDefinitionResult) _then;

/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? catalog = null,Object? definition = freezed,}) {
  return _then(_ModeDefinitionResult(
catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModeCatalogReadTarget,definition: freezed == definition ? _self.definition : definition // ignore: cast_nullable_to_non_nullable
as ModeDefinitionSnapshot?,
  ));
}

/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModeCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ModeDefinitionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModeDefinitionSnapshotCopyWith<$Res>? get definition {
    if (_self.definition == null) {
    return null;
  }

  return $ModeDefinitionSnapshotCopyWith<$Res>(_self.definition!, (value) {
    return _then(_self.copyWith(definition: value));
  });
}
}

// dart format on
