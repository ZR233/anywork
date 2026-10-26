// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ModelCatalogReadRef {

 int get entry; int get revision;
/// Create a copy of ModelCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogReadRefCopyWith<ModelCatalogReadRef> get copyWith => _$ModelCatalogReadRefCopyWithImpl<ModelCatalogReadRef>(this as ModelCatalogReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ModelCatalogReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ModelCatalogReadRef;
  return 'ModelCatalogReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ModelCatalogReadRefCopyWith<$Res>  {
  factory $ModelCatalogReadRefCopyWith(ModelCatalogReadRef value, $Res Function(ModelCatalogReadRef) _then) = _$ModelCatalogReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ModelCatalogReadRefCopyWithImpl<$Res>
    implements $ModelCatalogReadRefCopyWith<$Res> {
  _$ModelCatalogReadRefCopyWithImpl(this._self, this._then);

  final ModelCatalogReadRef _self;
  final $Res Function(ModelCatalogReadRef) _then;

/// Create a copy of ModelCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ModelCatalogReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ModelCatalogReadRef].
extension ModelCatalogReadRefPatterns on ModelCatalogReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCatalogReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCatalogReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCatalogReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCatalogReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogReadRef() when $default != null:
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
case _ModelCatalogReadRef() when $default != null:
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
case _ModelCatalogReadRef():
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
case _ModelCatalogReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCatalogReadRef implements ModelCatalogReadRef {
  const _ModelCatalogReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ModelCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCatalogReadRefCopyWith<_ModelCatalogReadRef> get copyWith => __$ModelCatalogReadRefCopyWithImpl<_ModelCatalogReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCatalogReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ModelCatalogReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ModelCatalogReadRefCopyWith<$Res> implements $ModelCatalogReadRefCopyWith<$Res> {
  factory _$ModelCatalogReadRefCopyWith(_ModelCatalogReadRef value, $Res Function(_ModelCatalogReadRef) _then) = __$ModelCatalogReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ModelCatalogReadRefCopyWithImpl<$Res>
    implements _$ModelCatalogReadRefCopyWith<$Res> {
  __$ModelCatalogReadRefCopyWithImpl(this._self, this._then);

  final _ModelCatalogReadRef _self;
  final $Res Function(_ModelCatalogReadRef) _then;

/// Create a copy of ModelCatalogReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ModelCatalogReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ModelCatalogReadTarget {

 ProductReadOrigin get origin; ModelCatalogReadRef get reference;
/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<ModelCatalogReadTarget> get copyWith => _$ModelCatalogReadTargetCopyWithImpl<ModelCatalogReadTarget>(this as ModelCatalogReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ModelCatalogReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as ModelCatalogReadTarget;
  return 'ModelCatalogReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ModelCatalogReadTargetCopyWith<$Res>  {
  factory $ModelCatalogReadTargetCopyWith(ModelCatalogReadTarget value, $Res Function(ModelCatalogReadTarget) _then) = _$ModelCatalogReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, ModelCatalogReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$ModelCatalogReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ModelCatalogReadTargetCopyWithImpl<$Res>
    implements $ModelCatalogReadTargetCopyWith<$Res> {
  _$ModelCatalogReadTargetCopyWithImpl(this._self, this._then);

  final ModelCatalogReadTarget _self;
  final $Res Function(ModelCatalogReadTarget) _then;

/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(ModelCatalogReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadRef,
  ));
}
/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadRefCopyWith<$Res> get reference {

  return $ModelCatalogReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelCatalogReadTarget].
extension ModelCatalogReadTargetPatterns on ModelCatalogReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCatalogReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCatalogReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCatalogReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCatalogReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ModelCatalogReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCatalogReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ModelCatalogReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  ModelCatalogReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCatalogReadTarget implements ModelCatalogReadTarget {
  const _ModelCatalogReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  ModelCatalogReadRef reference;

/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCatalogReadTargetCopyWith<_ModelCatalogReadTarget> get copyWith => __$ModelCatalogReadTargetCopyWithImpl<_ModelCatalogReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCatalogReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'ModelCatalogReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ModelCatalogReadTargetCopyWith<$Res> implements $ModelCatalogReadTargetCopyWith<$Res> {
  factory _$ModelCatalogReadTargetCopyWith(_ModelCatalogReadTarget value, $Res Function(_ModelCatalogReadTarget) _then) = __$ModelCatalogReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, ModelCatalogReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $ModelCatalogReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ModelCatalogReadTargetCopyWithImpl<$Res>
    implements _$ModelCatalogReadTargetCopyWith<$Res> {
  __$ModelCatalogReadTargetCopyWithImpl(this._self, this._then);

  final _ModelCatalogReadTarget _self;
  final $Res Function(_ModelCatalogReadTarget) _then;

/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_ModelCatalogReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadRef,
  ));
}

/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ModelCatalogReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadRefCopyWith<$Res> get reference {

  return $ModelCatalogReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$AccountTemplatesReadRef {

 int get entry; int get revision;
/// Create a copy of AccountTemplatesReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesReadRefCopyWith<AccountTemplatesReadRef> get copyWith => _$AccountTemplatesReadRefCopyWithImpl<AccountTemplatesReadRef>(this as AccountTemplatesReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as AccountTemplatesReadRef;
  return 'AccountTemplatesReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $AccountTemplatesReadRefCopyWith<$Res>  {
  factory $AccountTemplatesReadRefCopyWith(AccountTemplatesReadRef value, $Res Function(AccountTemplatesReadRef) _then) = _$AccountTemplatesReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$AccountTemplatesReadRefCopyWithImpl<$Res>
    implements $AccountTemplatesReadRefCopyWith<$Res> {
  _$AccountTemplatesReadRefCopyWithImpl(this._self, this._then);

  final AccountTemplatesReadRef _self;
  final $Res Function(AccountTemplatesReadRef) _then;

/// Create a copy of AccountTemplatesReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(AccountTemplatesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountTemplatesReadRef].
extension AccountTemplatesReadRefPatterns on AccountTemplatesReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplatesReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplatesReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplatesReadRef value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplatesReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesReadRef() when $default != null:
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
case _AccountTemplatesReadRef() when $default != null:
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
case _AccountTemplatesReadRef():
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
case _AccountTemplatesReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplatesReadRef implements AccountTemplatesReadRef {
  const _AccountTemplatesReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of AccountTemplatesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplatesReadRefCopyWith<_AccountTemplatesReadRef> get copyWith => __$AccountTemplatesReadRefCopyWithImpl<_AccountTemplatesReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplatesReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'AccountTemplatesReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$AccountTemplatesReadRefCopyWith<$Res> implements $AccountTemplatesReadRefCopyWith<$Res> {
  factory _$AccountTemplatesReadRefCopyWith(_AccountTemplatesReadRef value, $Res Function(_AccountTemplatesReadRef) _then) = __$AccountTemplatesReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$AccountTemplatesReadRefCopyWithImpl<$Res>
    implements _$AccountTemplatesReadRefCopyWith<$Res> {
  __$AccountTemplatesReadRefCopyWithImpl(this._self, this._then);

  final _AccountTemplatesReadRef _self;
  final $Res Function(_AccountTemplatesReadRef) _then;

/// Create a copy of AccountTemplatesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_AccountTemplatesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AccountTemplatesReadTarget {

 ProductReadOrigin get origin; AccountTemplatesReadRef get reference;
/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesReadTargetCopyWith<AccountTemplatesReadTarget> get copyWith => _$AccountTemplatesReadTargetCopyWithImpl<AccountTemplatesReadTarget>(this as AccountTemplatesReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as AccountTemplatesReadTarget;
  return 'AccountTemplatesReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AccountTemplatesReadTargetCopyWith<$Res>  {
  factory $AccountTemplatesReadTargetCopyWith(AccountTemplatesReadTarget value, $Res Function(AccountTemplatesReadTarget) _then) = _$AccountTemplatesReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, AccountTemplatesReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$AccountTemplatesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$AccountTemplatesReadTargetCopyWithImpl<$Res>
    implements $AccountTemplatesReadTargetCopyWith<$Res> {
  _$AccountTemplatesReadTargetCopyWithImpl(this._self, this._then);

  final AccountTemplatesReadTarget _self;
  final $Res Function(AccountTemplatesReadTarget) _then;

/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(AccountTemplatesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountTemplatesReadRef,
  ));
}
/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesReadRefCopyWith<$Res> get reference {

  return $AccountTemplatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountTemplatesReadTarget].
extension AccountTemplatesReadTargetPatterns on AccountTemplatesReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplatesReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplatesReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplatesReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplatesReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AccountTemplatesReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplatesReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AccountTemplatesReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  AccountTemplatesReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplatesReadTarget implements AccountTemplatesReadTarget {
  const _AccountTemplatesReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  AccountTemplatesReadRef reference;

/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplatesReadTargetCopyWith<_AccountTemplatesReadTarget> get copyWith => __$AccountTemplatesReadTargetCopyWithImpl<_AccountTemplatesReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplatesReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'AccountTemplatesReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AccountTemplatesReadTargetCopyWith<$Res> implements $AccountTemplatesReadTargetCopyWith<$Res> {
  factory _$AccountTemplatesReadTargetCopyWith(_AccountTemplatesReadTarget value, $Res Function(_AccountTemplatesReadTarget) _then) = __$AccountTemplatesReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, AccountTemplatesReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $AccountTemplatesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$AccountTemplatesReadTargetCopyWithImpl<$Res>
    implements _$AccountTemplatesReadTargetCopyWith<$Res> {
  __$AccountTemplatesReadTargetCopyWithImpl(this._self, this._then);

  final _AccountTemplatesReadTarget _self;
  final $Res Function(_AccountTemplatesReadTarget) _then;

/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_AccountTemplatesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountTemplatesReadRef,
  ));
}

/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AccountTemplatesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesReadRefCopyWith<$Res> get reference {

  return $AccountTemplatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ModelCatalogHeader {

 ObservedHeader get source; int? get catalogRevision; int? get updatedAt; ModelCatalogReadRef? get reference;
/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelCatalogHeaderCopyWith<ModelCatalogHeader> get copyWith => _$ModelCatalogHeaderCopyWithImpl<ModelCatalogHeader>(this as ModelCatalogHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelCatalogHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelCatalogHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ModelCatalogHeader;
  return Object.hash(runtimeType,_this.source,_this.catalogRevision,_this.updatedAt,_this.reference);
}

@override
String toString() {
  final _this = this as ModelCatalogHeader;
  return 'ModelCatalogHeader(source: ${_this.source}, catalogRevision: ${_this.catalogRevision}, updatedAt: ${_this.updatedAt}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ModelCatalogHeaderCopyWith<$Res>  {
  factory $ModelCatalogHeaderCopyWith(ModelCatalogHeader value, $Res Function(ModelCatalogHeader) _then) = _$ModelCatalogHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, int? catalogRevision, int? updatedAt, ModelCatalogReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$ModelCatalogReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$ModelCatalogHeaderCopyWithImpl<$Res>
    implements $ModelCatalogHeaderCopyWith<$Res> {
  _$ModelCatalogHeaderCopyWithImpl(this._self, this._then);

  final ModelCatalogHeader _self;
  final $Res Function(ModelCatalogHeader) _then;

/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? catalogRevision = freezed,Object? updatedAt = freezed,Object? reference = freezed,}) {
  return _then(ModelCatalogHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,catalogRevision: freezed == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadRef?,
  ));
}
/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ModelCatalogReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelCatalogHeader].
extension ModelCatalogHeaderPatterns on ModelCatalogHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelCatalogHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelCatalogHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelCatalogHeader value)  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelCatalogHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ModelCatalogHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  int? catalogRevision,  int? updatedAt,  ModelCatalogReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelCatalogHeader() when $default != null:
return $default(_that.source,_that.catalogRevision,_that.updatedAt,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  int? catalogRevision,  int? updatedAt,  ModelCatalogReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogHeader():
return $default(_that.source,_that.catalogRevision,_that.updatedAt,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  int? catalogRevision,  int? updatedAt,  ModelCatalogReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _ModelCatalogHeader() when $default != null:
return $default(_that.source,_that.catalogRevision,_that.updatedAt,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ModelCatalogHeader implements ModelCatalogHeader {
  const _ModelCatalogHeader({required this.source, required this.catalogRevision, required this.updatedAt, required this.reference});


@override final  ObservedHeader source;
@override final  int? catalogRevision;
@override final  int? updatedAt;
@override final  ModelCatalogReadRef? reference;

/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelCatalogHeaderCopyWith<_ModelCatalogHeader> get copyWith => __$ModelCatalogHeaderCopyWithImpl<_ModelCatalogHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelCatalogHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.catalogRevision, catalogRevision) || other.catalogRevision == catalogRevision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,catalogRevision,updatedAt,reference);
}

@override
String toString() {
    return 'ModelCatalogHeader(source: $source, catalogRevision: $catalogRevision, updatedAt: $updatedAt, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ModelCatalogHeaderCopyWith<$Res> implements $ModelCatalogHeaderCopyWith<$Res> {
  factory _$ModelCatalogHeaderCopyWith(_ModelCatalogHeader value, $Res Function(_ModelCatalogHeader) _then) = __$ModelCatalogHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, int? catalogRevision, int? updatedAt, ModelCatalogReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $ModelCatalogReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$ModelCatalogHeaderCopyWithImpl<$Res>
    implements _$ModelCatalogHeaderCopyWith<$Res> {
  __$ModelCatalogHeaderCopyWithImpl(this._self, this._then);

  final _ModelCatalogHeader _self;
  final $Res Function(_ModelCatalogHeader) _then;

/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? catalogRevision = freezed,Object? updatedAt = freezed,Object? reference = freezed,}) {
  return _then(_ModelCatalogHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,catalogRevision: freezed == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadRef?,
  ));
}

/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ModelCatalogHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ModelCatalogReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$AccountTemplatesHeader {

 int get schemaVersion; AccountTemplatesReadRef get reference;
/// Create a copy of AccountTemplatesHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesHeaderCopyWith<AccountTemplatesHeader> get copyWith => _$AccountTemplatesHeaderCopyWithImpl<AccountTemplatesHeader>(this as AccountTemplatesHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesHeader&&(identical(other.schemaVersion, _this.schemaVersion) || other.schemaVersion == _this.schemaVersion)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesHeader;
  return Object.hash(runtimeType,_this.schemaVersion,_this.reference);
}

@override
String toString() {
  final _this = this as AccountTemplatesHeader;
  return 'AccountTemplatesHeader(schemaVersion: ${_this.schemaVersion}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AccountTemplatesHeaderCopyWith<$Res>  {
  factory $AccountTemplatesHeaderCopyWith(AccountTemplatesHeader value, $Res Function(AccountTemplatesHeader) _then) = _$AccountTemplatesHeaderCopyWithImpl;
@useResult
$Res call({
 int schemaVersion, AccountTemplatesReadRef reference
});


$AccountTemplatesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$AccountTemplatesHeaderCopyWithImpl<$Res>
    implements $AccountTemplatesHeaderCopyWith<$Res> {
  _$AccountTemplatesHeaderCopyWithImpl(this._self, this._then);

  final AccountTemplatesHeader _self;
  final $Res Function(AccountTemplatesHeader) _then;

/// Create a copy of AccountTemplatesHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? schemaVersion = null,Object? reference = null,}) {
  return _then(AccountTemplatesHeader(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountTemplatesReadRef,
  ));
}
/// Create a copy of AccountTemplatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesReadRefCopyWith<$Res> get reference {

  return $AccountTemplatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountTemplatesHeader].
extension AccountTemplatesHeaderPatterns on AccountTemplatesHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplatesHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplatesHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplatesHeader value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplatesHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int schemaVersion,  AccountTemplatesReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplatesHeader() when $default != null:
return $default(_that.schemaVersion,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int schemaVersion,  AccountTemplatesReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesHeader():
return $default(_that.schemaVersion,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int schemaVersion,  AccountTemplatesReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesHeader() when $default != null:
return $default(_that.schemaVersion,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplatesHeader implements AccountTemplatesHeader {
  const _AccountTemplatesHeader({required this.schemaVersion, required this.reference});


@override final  int schemaVersion;
@override final  AccountTemplatesReadRef reference;

/// Create a copy of AccountTemplatesHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplatesHeaderCopyWith<_AccountTemplatesHeader> get copyWith => __$AccountTemplatesHeaderCopyWithImpl<_AccountTemplatesHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplatesHeader&&(identical(other.schemaVersion, schemaVersion) || other.schemaVersion == schemaVersion)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,schemaVersion,reference);
}

@override
String toString() {
    return 'AccountTemplatesHeader(schemaVersion: $schemaVersion, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AccountTemplatesHeaderCopyWith<$Res> implements $AccountTemplatesHeaderCopyWith<$Res> {
  factory _$AccountTemplatesHeaderCopyWith(_AccountTemplatesHeader value, $Res Function(_AccountTemplatesHeader) _then) = __$AccountTemplatesHeaderCopyWithImpl;
@override @useResult
$Res call({
 int schemaVersion, AccountTemplatesReadRef reference
});


@override $AccountTemplatesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$AccountTemplatesHeaderCopyWithImpl<$Res>
    implements _$AccountTemplatesHeaderCopyWith<$Res> {
  __$AccountTemplatesHeaderCopyWithImpl(this._self, this._then);

  final _AccountTemplatesHeader _self;
  final $Res Function(_AccountTemplatesHeader) _then;

/// Create a copy of AccountTemplatesHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? schemaVersion = null,Object? reference = null,}) {
  return _then(_AccountTemplatesHeader(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AccountTemplatesReadRef,
  ));
}

/// Create a copy of AccountTemplatesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplatesReadRefCopyWith<$Res> get reference {

  return $AccountTemplatesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ModelsState {

 ProductProjection<ModelCatalogHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; CollectionMirror<AccountCatalogEntry> get accounts; ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? get webSearch; ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>? get deepSeekSearch;
/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<ModelsState> get copyWith => _$ModelsStateCopyWithImpl<ModelsState>(this as ModelsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ModelsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ModelsState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.accounts, _this.accounts) || other.accounts == _this.accounts)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.deepSeekSearch, _this.deepSeekSearch) || other.deepSeekSearch == _this.deepSeekSearch));
}


@override
int get hashCode {
  final _this = this as ModelsState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.accounts,_this.webSearch,_this.deepSeekSearch);
}



}

/// @nodoc
abstract mixin class $ModelsStateCopyWith<$Res>  {
  factory $ModelsStateCopyWith(ModelsState value, $Res Function(ModelsState) _then) = _$ModelsStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<ModelCatalogHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AccountCatalogEntry> accounts, ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? webSearch, ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>? deepSeekSearch
});


$ProductProjectionCopyWith<ModelCatalogHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<AccountCatalogEntry, $Res> get accounts;$ReadValueCopyWith<EffectiveWebSearch, ModelCatalogReadRef, $Res>? get webSearch;$ReadValueCopyWith<EffectiveDeepSeekSearch, ModelCatalogReadRef, $Res>? get deepSeekSearch;

}
/// @nodoc
class _$ModelsStateCopyWithImpl<$Res>
    implements $ModelsStateCopyWith<$Res> {
  _$ModelsStateCopyWithImpl(this._self, this._then);

  final ModelsState _self;
  final $Res Function(ModelsState) _then;

/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? accounts = null,Object? webSearch = freezed,Object? deepSeekSearch = freezed,}) {
  return _then(ModelsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ModelCatalogHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AccountCatalogEntry>,webSearch: freezed == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as ReadValue<EffectiveWebSearch, ModelCatalogReadRef>?,deepSeekSearch: freezed == deepSeekSearch ? _self.deepSeekSearch : deepSeekSearch // ignore: cast_nullable_to_non_nullable
as ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>?,
  ));
}
/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ModelCatalogHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ModelCatalogHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus {
    if (_self.sourceStatus == null) {
    return null;
  }

  return $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>(_self.sourceStatus!, (value) {
    return _then(_self.copyWith(sourceStatus: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AccountCatalogEntry, $Res> get accounts {

  return $CollectionMirrorCopyWith<AccountCatalogEntry, $Res>(_self.accounts, (value) {
    return _then(_self.copyWith(accounts: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<EffectiveWebSearch, ModelCatalogReadRef, $Res>? get webSearch {
    if (_self.webSearch == null) {
    return null;
  }

  return $ReadValueCopyWith<EffectiveWebSearch, ModelCatalogReadRef, $Res>(_self.webSearch!, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<EffectiveDeepSeekSearch, ModelCatalogReadRef, $Res>? get deepSeekSearch {
    if (_self.deepSeekSearch == null) {
    return null;
  }

  return $ReadValueCopyWith<EffectiveDeepSeekSearch, ModelCatalogReadRef, $Res>(_self.deepSeekSearch!, (value) {
    return _then(_self.copyWith(deepSeekSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [ModelsState].
extension ModelsStatePatterns on ModelsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ModelsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ModelsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ModelsState value)  $default,){
final _that = this;
switch (_that) {
case _ModelsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ModelsState value)?  $default,){
final _that = this;
switch (_that) {
case _ModelsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<ModelCatalogHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AccountCatalogEntry> accounts,  ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? webSearch,  ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>? deepSeekSearch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ModelsState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.accounts,_that.webSearch,_that.deepSeekSearch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<ModelCatalogHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AccountCatalogEntry> accounts,  ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? webSearch,  ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>? deepSeekSearch)  $default,) {final _that = this;
switch (_that) {
case _ModelsState():
return $default(_that.projection,_that.sourceStatus,_that.accounts,_that.webSearch,_that.deepSeekSearch);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<ModelCatalogHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  CollectionMirror<AccountCatalogEntry> accounts,  ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? webSearch,  ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>? deepSeekSearch)?  $default,) {final _that = this;
switch (_that) {
case _ModelsState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.accounts,_that.webSearch,_that.deepSeekSearch);case _:
  return null;

}
}

}

/// @nodoc


class _ModelsState implements ModelsState {
  const _ModelsState({required this.projection, required this.sourceStatus, required this.accounts, required this.webSearch, required this.deepSeekSearch});


@override final  ProductProjection<ModelCatalogHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  CollectionMirror<AccountCatalogEntry> accounts;
@override final  ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? webSearch;
@override final  ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>? deepSeekSearch;

/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ModelsStateCopyWith<_ModelsState> get copyWith => __$ModelsStateCopyWithImpl<_ModelsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ModelsState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.accounts, accounts) || other.accounts == accounts)&&(identical(other.webSearch, webSearch) || other.webSearch == webSearch)&&(identical(other.deepSeekSearch, deepSeekSearch) || other.deepSeekSearch == deepSeekSearch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,accounts,webSearch,deepSeekSearch);
}



}

/// @nodoc
abstract mixin class _$ModelsStateCopyWith<$Res> implements $ModelsStateCopyWith<$Res> {
  factory _$ModelsStateCopyWith(_ModelsState value, $Res Function(_ModelsState) _then) = __$ModelsStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<ModelCatalogHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AccountCatalogEntry> accounts, ReadValue<EffectiveWebSearch, ModelCatalogReadRef>? webSearch, ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>? deepSeekSearch
});


@override $ProductProjectionCopyWith<ModelCatalogHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $CollectionMirrorCopyWith<AccountCatalogEntry, $Res> get accounts;@override $ReadValueCopyWith<EffectiveWebSearch, ModelCatalogReadRef, $Res>? get webSearch;@override $ReadValueCopyWith<EffectiveDeepSeekSearch, ModelCatalogReadRef, $Res>? get deepSeekSearch;

}
/// @nodoc
class __$ModelsStateCopyWithImpl<$Res>
    implements _$ModelsStateCopyWith<$Res> {
  __$ModelsStateCopyWithImpl(this._self, this._then);

  final _ModelsState _self;
  final $Res Function(_ModelsState) _then;

/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? accounts = null,Object? webSearch = freezed,Object? deepSeekSearch = freezed,}) {
  return _then(_ModelsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ModelCatalogHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AccountCatalogEntry>,webSearch: freezed == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as ReadValue<EffectiveWebSearch, ModelCatalogReadRef>?,deepSeekSearch: freezed == deepSeekSearch ? _self.deepSeekSearch : deepSeekSearch // ignore: cast_nullable_to_non_nullable
as ReadValue<EffectiveDeepSeekSearch, ModelCatalogReadRef>?,
  ));
}

/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ModelCatalogHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ModelCatalogHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus {
    if (_self.sourceStatus == null) {
    return null;
  }

  return $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>(_self.sourceStatus!, (value) {
    return _then(_self.copyWith(sourceStatus: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AccountCatalogEntry, $Res> get accounts {

  return $CollectionMirrorCopyWith<AccountCatalogEntry, $Res>(_self.accounts, (value) {
    return _then(_self.copyWith(accounts: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<EffectiveWebSearch, ModelCatalogReadRef, $Res>? get webSearch {
    if (_self.webSearch == null) {
    return null;
  }

  return $ReadValueCopyWith<EffectiveWebSearch, ModelCatalogReadRef, $Res>(_self.webSearch!, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ModelsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<EffectiveDeepSeekSearch, ModelCatalogReadRef, $Res>? get deepSeekSearch {
    if (_self.deepSeekSearch == null) {
    return null;
  }

  return $ReadValueCopyWith<EffectiveDeepSeekSearch, ModelCatalogReadRef, $Res>(_self.deepSeekSearch!, (value) {
    return _then(_self.copyWith(deepSeekSearch: value));
  });
}
}

/// @nodoc
mixin _$TemplatesState {


/// Create a copy of TemplatesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TemplatesStateCopyWith<TemplatesState> get copyWith => _$TemplatesStateCopyWithImpl<TemplatesState>(this as TemplatesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TemplatesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TemplatesState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.templates, _this.templates) || other.templates == _this.templates)&&(identical(other.catalogs, _this.catalogs) || other.catalogs == _this.catalogs)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision));
}


@override
int get hashCode {
  final _this = this as TemplatesState;
  return Object.hash(runtimeType,_this.projection,_this.templates,_this.catalogs,_this.catalogRevision);
}



}

/// @nodoc
abstract mixin class $TemplatesStateCopyWith<$Res>  {
  factory $TemplatesStateCopyWith(TemplatesState value, $Res Function(TemplatesState) _then) = _$TemplatesStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<AccountTemplatesHeader> projection, CollectionMirror<AccountTemplate> templates, ReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>? catalogs, ReadValue<String, AccountTemplatesReadRef>? catalogRevision
});


$ProductProjectionCopyWith<AccountTemplatesHeader, $Res> get projection;$CollectionMirrorCopyWith<AccountTemplate, $Res> get templates;$ReadValueCopyWith<Map<String, NamedModelCatalog>, AccountTemplatesReadRef, $Res>? get catalogs;$ReadValueCopyWith<String, AccountTemplatesReadRef, $Res>? get catalogRevision;

}
/// @nodoc
class _$TemplatesStateCopyWithImpl<$Res>
    implements $TemplatesStateCopyWith<$Res> {
  _$TemplatesStateCopyWithImpl(this._self, this._then);

  final TemplatesState _self;
  final $Res Function(TemplatesState) _then;

/// Create a copy of TemplatesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? templates = null,Object? catalogs = freezed,Object? catalogRevision = freezed,}) {
  return _then(TemplatesState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AccountTemplatesHeader>,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AccountTemplate>,catalogs: freezed == catalogs ? _self.catalogs : catalogs // ignore: cast_nullable_to_non_nullable
as ReadValue<Map<String, NamedModelCatalog>, AccountTemplatesReadRef>?,catalogRevision: freezed == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as ReadValue<String, AccountTemplatesReadRef>?,
  ));
}
/// Create a copy of TemplatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AccountTemplatesHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AccountTemplatesHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of TemplatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AccountTemplate, $Res> get templates {

  return $CollectionMirrorCopyWith<AccountTemplate, $Res>(_self.templates, (value) {
    return _then(_self.copyWith(templates: value));
  });
}/// Create a copy of TemplatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<Map<String, NamedModelCatalog>, AccountTemplatesReadRef, $Res>? get catalogs {
    if (_self.catalogs == null) {
    return null;
  }

  return $ReadValueCopyWith<Map<String, NamedModelCatalog>, AccountTemplatesReadRef, $Res>(_self.catalogs!, (value) {
    return _then(_self.copyWith(catalogs: value));
  });
}/// Create a copy of TemplatesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, AccountTemplatesReadRef, $Res>? get catalogRevision {
    if (_self.catalogRevision == null) {
    return null;
  }

  return $ReadValueCopyWith<String, AccountTemplatesReadRef, $Res>(_self.catalogRevision!, (value) {
    return _then(_self.copyWith(catalogRevision: value));
  });
}
}


/// Adds pattern-matching-related methods to [TemplatesState].
extension TemplatesStatePatterns on TemplatesState {
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
