// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConfigurationReadRef {

 int get entry; int get revision;
/// Create a copy of ConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationReadRefCopyWith<ConfigurationReadRef> get copyWith => _$ConfigurationReadRefCopyWithImpl<ConfigurationReadRef>(this as ConfigurationReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ConfigurationReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ConfigurationReadRef;
  return 'ConfigurationReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ConfigurationReadRefCopyWith<$Res>  {
  factory $ConfigurationReadRefCopyWith(ConfigurationReadRef value, $Res Function(ConfigurationReadRef) _then) = _$ConfigurationReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ConfigurationReadRefCopyWithImpl<$Res>
    implements $ConfigurationReadRefCopyWith<$Res> {
  _$ConfigurationReadRefCopyWithImpl(this._self, this._then);

  final ConfigurationReadRef _self;
  final $Res Function(ConfigurationReadRef) _then;

/// Create a copy of ConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ConfigurationReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ConfigurationReadRef].
extension ConfigurationReadRefPatterns on ConfigurationReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReadRef() when $default != null:
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
case _ConfigurationReadRef() when $default != null:
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
case _ConfigurationReadRef():
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
case _ConfigurationReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationReadRef implements ConfigurationReadRef {
  const _ConfigurationReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationReadRefCopyWith<_ConfigurationReadRef> get copyWith => __$ConfigurationReadRefCopyWithImpl<_ConfigurationReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ConfigurationReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationReadRefCopyWith<$Res> implements $ConfigurationReadRefCopyWith<$Res> {
  factory _$ConfigurationReadRefCopyWith(_ConfigurationReadRef value, $Res Function(_ConfigurationReadRef) _then) = __$ConfigurationReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ConfigurationReadRefCopyWithImpl<$Res>
    implements _$ConfigurationReadRefCopyWith<$Res> {
  __$ConfigurationReadRefCopyWithImpl(this._self, this._then);

  final _ConfigurationReadRef _self;
  final $Res Function(_ConfigurationReadRef) _then;

/// Create a copy of ConfigurationReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ConfigurationReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ConfigurationReadTarget {

 ProductReadOrigin get origin; ConfigurationReadRef get reference;
/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<ConfigurationReadTarget> get copyWith => _$ConfigurationReadTargetCopyWithImpl<ConfigurationReadTarget>(this as ConfigurationReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as ConfigurationReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as ConfigurationReadTarget;
  return 'ConfigurationReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $ConfigurationReadTargetCopyWith<$Res>  {
  factory $ConfigurationReadTargetCopyWith(ConfigurationReadTarget value, $Res Function(ConfigurationReadTarget) _then) = _$ConfigurationReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, ConfigurationReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$ConfigurationReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$ConfigurationReadTargetCopyWithImpl<$Res>
    implements $ConfigurationReadTargetCopyWith<$Res> {
  _$ConfigurationReadTargetCopyWithImpl(this._self, this._then);

  final ConfigurationReadTarget _self;
  final $Res Function(ConfigurationReadTarget) _then;

/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(ConfigurationReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationReadRef,
  ));
}
/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadRefCopyWith<$Res> get reference {

  return $ConfigurationReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationReadTarget].
extension ConfigurationReadTargetPatterns on ConfigurationReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ConfigurationReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  ConfigurationReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  ConfigurationReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationReadTarget implements ConfigurationReadTarget {
  const _ConfigurationReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  ConfigurationReadRef reference;

/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationReadTargetCopyWith<_ConfigurationReadTarget> get copyWith => __$ConfigurationReadTargetCopyWithImpl<_ConfigurationReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'ConfigurationReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationReadTargetCopyWith<$Res> implements $ConfigurationReadTargetCopyWith<$Res> {
  factory _$ConfigurationReadTargetCopyWith(_ConfigurationReadTarget value, $Res Function(_ConfigurationReadTarget) _then) = __$ConfigurationReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, ConfigurationReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $ConfigurationReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$ConfigurationReadTargetCopyWithImpl<$Res>
    implements _$ConfigurationReadTargetCopyWith<$Res> {
  __$ConfigurationReadTargetCopyWithImpl(this._self, this._then);

  final _ConfigurationReadTarget _self;
  final $Res Function(_ConfigurationReadTarget) _then;

/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_ConfigurationReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationReadRef,
  ));
}

/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of ConfigurationReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadRefCopyWith<$Res> get reference {

  return $ConfigurationReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ConfigurationRoleReadRef {

 int get entry; int get revision;
/// Create a copy of ConfigurationRoleReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationRoleReadRefCopyWith<ConfigurationRoleReadRef> get copyWith => _$ConfigurationRoleReadRefCopyWithImpl<ConfigurationRoleReadRef>(this as ConfigurationRoleReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationRoleReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationRoleReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ConfigurationRoleReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as ConfigurationRoleReadRef;
  return 'ConfigurationRoleReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ConfigurationRoleReadRefCopyWith<$Res>  {
  factory $ConfigurationRoleReadRefCopyWith(ConfigurationRoleReadRef value, $Res Function(ConfigurationRoleReadRef) _then) = _$ConfigurationRoleReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$ConfigurationRoleReadRefCopyWithImpl<$Res>
    implements $ConfigurationRoleReadRefCopyWith<$Res> {
  _$ConfigurationRoleReadRefCopyWithImpl(this._self, this._then);

  final ConfigurationRoleReadRef _self;
  final $Res Function(ConfigurationRoleReadRef) _then;

/// Create a copy of ConfigurationRoleReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(ConfigurationRoleReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ConfigurationRoleReadRef].
extension ConfigurationRoleReadRefPatterns on ConfigurationRoleReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationRoleReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationRoleReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationRoleReadRef value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationRoleReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationRoleReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationRoleReadRef() when $default != null:
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
case _ConfigurationRoleReadRef() when $default != null:
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
case _ConfigurationRoleReadRef():
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
case _ConfigurationRoleReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationRoleReadRef implements ConfigurationRoleReadRef {
  const _ConfigurationRoleReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of ConfigurationRoleReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationRoleReadRefCopyWith<_ConfigurationRoleReadRef> get copyWith => __$ConfigurationRoleReadRefCopyWithImpl<_ConfigurationRoleReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationRoleReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'ConfigurationRoleReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationRoleReadRefCopyWith<$Res> implements $ConfigurationRoleReadRefCopyWith<$Res> {
  factory _$ConfigurationRoleReadRefCopyWith(_ConfigurationRoleReadRef value, $Res Function(_ConfigurationRoleReadRef) _then) = __$ConfigurationRoleReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$ConfigurationRoleReadRefCopyWithImpl<$Res>
    implements _$ConfigurationRoleReadRefCopyWith<$Res> {
  __$ConfigurationRoleReadRefCopyWithImpl(this._self, this._then);

  final _ConfigurationRoleReadRef _self;
  final $Res Function(_ConfigurationRoleReadRef) _then;

/// Create a copy of ConfigurationRoleReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_ConfigurationRoleReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ConfigurationRoleReadTarget {

 ConfigurationRoleReadRef get reference; ConfigurationReadTarget get configuration; ModelCatalogReadTarget get catalog; ConfigProjectionStamp get stamp;
/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<ConfigurationRoleReadTarget> get copyWith => _$ConfigurationRoleReadTargetCopyWithImpl<ConfigurationRoleReadTarget>(this as ConfigurationRoleReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationRoleReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationRoleReadTarget&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp));
}


@override
int get hashCode {
  final _this = this as ConfigurationRoleReadTarget;
  return Object.hash(runtimeType,_this.reference,_this.configuration,_this.catalog,_this.stamp);
}

@override
String toString() {
  final _this = this as ConfigurationRoleReadTarget;
  return 'ConfigurationRoleReadTarget(reference: ${_this.reference}, configuration: ${_this.configuration}, catalog: ${_this.catalog}, stamp: ${_this.stamp})';
}


}

/// @nodoc
abstract mixin class $ConfigurationRoleReadTargetCopyWith<$Res>  {
  factory $ConfigurationRoleReadTargetCopyWith(ConfigurationRoleReadTarget value, $Res Function(ConfigurationRoleReadTarget) _then) = _$ConfigurationRoleReadTargetCopyWithImpl;
@useResult
$Res call({
 ConfigurationRoleReadRef reference, ConfigurationReadTarget configuration, ModelCatalogReadTarget catalog, ConfigProjectionStamp stamp
});


$ConfigurationRoleReadRefCopyWith<$Res> get reference;$ConfigurationReadTargetCopyWith<$Res> get configuration;$ModelCatalogReadTargetCopyWith<$Res> get catalog;$ConfigProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ConfigurationRoleReadTargetCopyWithImpl<$Res>
    implements $ConfigurationRoleReadTargetCopyWith<$Res> {
  _$ConfigurationRoleReadTargetCopyWithImpl(this._self, this._then);

  final ConfigurationRoleReadTarget _self;
  final $Res Function(ConfigurationRoleReadTarget) _then;

/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? configuration = null,Object? catalog = null,Object? stamp = null,}) {
  return _then(ConfigurationRoleReadTarget(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadRef,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ConfigProjectionStamp,
  ));
}
/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadRefCopyWith<$Res> get reference {

  return $ConfigurationRoleReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigProjectionStampCopyWith<$Res> get stamp {

  return $ConfigProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationRoleReadTarget].
extension ConfigurationRoleReadTargetPatterns on ConfigurationRoleReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationRoleReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationRoleReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationRoleReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationRoleReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationRoleReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationRoleReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationRoleReadRef reference,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget catalog,  ConfigProjectionStamp stamp)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationRoleReadTarget() when $default != null:
return $default(_that.reference,_that.configuration,_that.catalog,_that.stamp);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationRoleReadRef reference,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget catalog,  ConfigProjectionStamp stamp)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationRoleReadTarget():
return $default(_that.reference,_that.configuration,_that.catalog,_that.stamp);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationRoleReadRef reference,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget catalog,  ConfigProjectionStamp stamp)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationRoleReadTarget() when $default != null:
return $default(_that.reference,_that.configuration,_that.catalog,_that.stamp);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationRoleReadTarget implements ConfigurationRoleReadTarget {
  const _ConfigurationRoleReadTarget({required this.reference, required this.configuration, required this.catalog, required this.stamp});


@override final  ConfigurationRoleReadRef reference;
@override final  ConfigurationReadTarget configuration;
@override final  ModelCatalogReadTarget catalog;
@override final  ConfigProjectionStamp stamp;

/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationRoleReadTargetCopyWith<_ConfigurationRoleReadTarget> get copyWith => __$ConfigurationRoleReadTargetCopyWithImpl<_ConfigurationRoleReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationRoleReadTarget&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.stamp, stamp) || other.stamp == stamp));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,configuration,catalog,stamp);
}

@override
String toString() {
    return 'ConfigurationRoleReadTarget(reference: $reference, configuration: $configuration, catalog: $catalog, stamp: $stamp)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationRoleReadTargetCopyWith<$Res> implements $ConfigurationRoleReadTargetCopyWith<$Res> {
  factory _$ConfigurationRoleReadTargetCopyWith(_ConfigurationRoleReadTarget value, $Res Function(_ConfigurationRoleReadTarget) _then) = __$ConfigurationRoleReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationRoleReadRef reference, ConfigurationReadTarget configuration, ModelCatalogReadTarget catalog, ConfigProjectionStamp stamp
});


@override $ConfigurationRoleReadRefCopyWith<$Res> get reference;@override $ConfigurationReadTargetCopyWith<$Res> get configuration;@override $ModelCatalogReadTargetCopyWith<$Res> get catalog;@override $ConfigProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class __$ConfigurationRoleReadTargetCopyWithImpl<$Res>
    implements _$ConfigurationRoleReadTargetCopyWith<$Res> {
  __$ConfigurationRoleReadTargetCopyWithImpl(this._self, this._then);

  final _ConfigurationRoleReadTarget _self;
  final $Res Function(_ConfigurationRoleReadTarget) _then;

/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? configuration = null,Object? catalog = null,Object? stamp = null,}) {
  return _then(_ConfigurationRoleReadTarget(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadRef,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ConfigProjectionStamp,
  ));
}

/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadRefCopyWith<$Res> get reference {

  return $ConfigurationRoleReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get catalog {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of ConfigurationRoleReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigProjectionStampCopyWith<$Res> get stamp {

  return $ConfigProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}

/// @nodoc
mixin _$RoleRouteRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RoleRouteRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $RoleRouteReadCopyWith<$Res>  {
$RoleRouteReadCopyWith(RoleRouteRead _, $Res Function(RoleRouteRead) __);
}


/// Adds pattern-matching-related methods to [RoleRouteRead].
extension RoleRouteReadPatterns on RoleRouteRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ConfiguredRoleRouteRead value)?  configured,TResult Function( MissingRoleRouteRead value)?  missing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ConfiguredRoleRouteRead() when configured != null:
return configured(_that);case MissingRoleRouteRead() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ConfiguredRoleRouteRead value)  configured,required TResult Function( MissingRoleRouteRead value)  missing,}){
final _that = this;
switch (_that) {
case ConfiguredRoleRouteRead():
return configured(_that);case MissingRoleRouteRead():
return missing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ConfiguredRoleRouteRead value)?  configured,TResult? Function( MissingRoleRouteRead value)?  missing,}){
final _that = this;
switch (_that) {
case ConfiguredRoleRouteRead() when configured != null:
return configured(_that);case MissingRoleRouteRead() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( RoleModelRoute route)?  configured,TResult Function( ModelSelection? suggestion)?  missing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ConfiguredRoleRouteRead() when configured != null:
return configured(_that.route);case MissingRoleRouteRead() when missing != null:
return missing(_that.suggestion);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( RoleModelRoute route)  configured,required TResult Function( ModelSelection? suggestion)  missing,}) {final _that = this;
switch (_that) {
case ConfiguredRoleRouteRead():
return configured(_that.route);case MissingRoleRouteRead():
return missing(_that.suggestion);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( RoleModelRoute route)?  configured,TResult? Function( ModelSelection? suggestion)?  missing,}) {final _that = this;
switch (_that) {
case ConfiguredRoleRouteRead() when configured != null:
return configured(_that.route);case MissingRoleRouteRead() when missing != null:
return missing(_that.suggestion);case _:
  return null;

}
}

}

/// @nodoc


class ConfiguredRoleRouteRead implements RoleRouteRead {
  const ConfiguredRoleRouteRead({required this.route});


 final  RoleModelRoute route;

/// Create a copy of RoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfiguredRoleRouteReadCopyWith<ConfiguredRoleRouteRead> get copyWith => _$ConfiguredRoleRouteReadCopyWithImpl<ConfiguredRoleRouteRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfiguredRoleRouteRead&&(identical(other.route, route) || other.route == route));
}


@override
int get hashCode {
    return Object.hash(runtimeType,route);
}



}

/// @nodoc
abstract mixin class $ConfiguredRoleRouteReadCopyWith<$Res> implements $RoleRouteReadCopyWith<$Res> {
  factory $ConfiguredRoleRouteReadCopyWith(ConfiguredRoleRouteRead value, $Res Function(ConfiguredRoleRouteRead) _then) = _$ConfiguredRoleRouteReadCopyWithImpl;
@useResult
$Res call({
 RoleModelRoute route
});


$RoleModelRouteCopyWith<$Res> get route;

}
/// @nodoc
class _$ConfiguredRoleRouteReadCopyWithImpl<$Res>
    implements $ConfiguredRoleRouteReadCopyWith<$Res> {
  _$ConfiguredRoleRouteReadCopyWithImpl(this._self, this._then);

  final ConfiguredRoleRouteRead _self;
  final $Res Function(ConfiguredRoleRouteRead) _then;

/// Create a copy of RoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? route = null,}) {
  return _then(ConfiguredRoleRouteRead(
route: null == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as RoleModelRoute,
  ));
}

/// Create a copy of RoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RoleModelRouteCopyWith<$Res> get route {

  return $RoleModelRouteCopyWith<$Res>(_self.route, (value) {
    return _then(_self.copyWith(route: value));
  });
}
}

/// @nodoc


class MissingRoleRouteRead implements RoleRouteRead {
  const MissingRoleRouteRead({required this.suggestion});


 final  ModelSelection? suggestion;

/// Create a copy of RoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MissingRoleRouteReadCopyWith<MissingRoleRouteRead> get copyWith => _$MissingRoleRouteReadCopyWithImpl<MissingRoleRouteRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MissingRoleRouteRead&&(identical(other.suggestion, suggestion) || other.suggestion == suggestion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,suggestion);
}



}

/// @nodoc
abstract mixin class $MissingRoleRouteReadCopyWith<$Res> implements $RoleRouteReadCopyWith<$Res> {
  factory $MissingRoleRouteReadCopyWith(MissingRoleRouteRead value, $Res Function(MissingRoleRouteRead) _then) = _$MissingRoleRouteReadCopyWithImpl;
@useResult
$Res call({
 ModelSelection? suggestion
});


$ModelSelectionCopyWith<$Res>? get suggestion;

}
/// @nodoc
class _$MissingRoleRouteReadCopyWithImpl<$Res>
    implements $MissingRoleRouteReadCopyWith<$Res> {
  _$MissingRoleRouteReadCopyWithImpl(this._self, this._then);

  final MissingRoleRouteRead _self;
  final $Res Function(MissingRoleRouteRead) _then;

/// Create a copy of RoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? suggestion = freezed,}) {
  return _then(MissingRoleRouteRead(
suggestion: freezed == suggestion ? _self.suggestion : suggestion // ignore: cast_nullable_to_non_nullable
as ModelSelection?,
  ));
}

/// Create a copy of RoleRouteRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res>? get suggestion {
    if (_self.suggestion == null) {
    return null;
  }

  return $ModelSelectionCopyWith<$Res>(_self.suggestion!, (value) {
    return _then(_self.copyWith(suggestion: value));
  });
}
}

/// @nodoc
mixin _$AgentProfilesReadRef {

 int get entry; int get revision;
/// Create a copy of AgentProfilesReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesReadRefCopyWith<AgentProfilesReadRef> get copyWith => _$AgentProfilesReadRefCopyWithImpl<AgentProfilesReadRef>(this as AgentProfilesReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as AgentProfilesReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as AgentProfilesReadRef;
  return 'AgentProfilesReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $AgentProfilesReadRefCopyWith<$Res>  {
  factory $AgentProfilesReadRefCopyWith(AgentProfilesReadRef value, $Res Function(AgentProfilesReadRef) _then) = _$AgentProfilesReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$AgentProfilesReadRefCopyWithImpl<$Res>
    implements $AgentProfilesReadRefCopyWith<$Res> {
  _$AgentProfilesReadRefCopyWithImpl(this._self, this._then);

  final AgentProfilesReadRef _self;
  final $Res Function(AgentProfilesReadRef) _then;

/// Create a copy of AgentProfilesReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(AgentProfilesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentProfilesReadRef].
extension AgentProfilesReadRefPatterns on AgentProfilesReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfilesReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfilesReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfilesReadRef value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfilesReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesReadRef() when $default != null:
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
case _AgentProfilesReadRef() when $default != null:
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
case _AgentProfilesReadRef():
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
case _AgentProfilesReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfilesReadRef implements AgentProfilesReadRef {
  const _AgentProfilesReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of AgentProfilesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfilesReadRefCopyWith<_AgentProfilesReadRef> get copyWith => __$AgentProfilesReadRefCopyWithImpl<_AgentProfilesReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfilesReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'AgentProfilesReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$AgentProfilesReadRefCopyWith<$Res> implements $AgentProfilesReadRefCopyWith<$Res> {
  factory _$AgentProfilesReadRefCopyWith(_AgentProfilesReadRef value, $Res Function(_AgentProfilesReadRef) _then) = __$AgentProfilesReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$AgentProfilesReadRefCopyWithImpl<$Res>
    implements _$AgentProfilesReadRefCopyWith<$Res> {
  __$AgentProfilesReadRefCopyWithImpl(this._self, this._then);

  final _AgentProfilesReadRef _self;
  final $Res Function(_AgentProfilesReadRef) _then;

/// Create a copy of AgentProfilesReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_AgentProfilesReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AgentProfilesReadTarget {

 ProductReadOrigin get origin; AgentProfilesReadRef get reference;
/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesReadTargetCopyWith<AgentProfilesReadTarget> get copyWith => _$AgentProfilesReadTargetCopyWithImpl<AgentProfilesReadTarget>(this as AgentProfilesReadTarget, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesReadTarget;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesReadTarget&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AgentProfilesReadTarget;
  return Object.hash(runtimeType,_this.origin,_this.reference);
}

@override
String toString() {
  final _this = this as AgentProfilesReadTarget;
  return 'AgentProfilesReadTarget(origin: ${_this.origin}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AgentProfilesReadTargetCopyWith<$Res>  {
  factory $AgentProfilesReadTargetCopyWith(AgentProfilesReadTarget value, $Res Function(AgentProfilesReadTarget) _then) = _$AgentProfilesReadTargetCopyWithImpl;
@useResult
$Res call({
 ProductReadOrigin origin, AgentProfilesReadRef reference
});


$ProductReadOriginCopyWith<$Res> get origin;$AgentProfilesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$AgentProfilesReadTargetCopyWithImpl<$Res>
    implements $AgentProfilesReadTargetCopyWith<$Res> {
  _$AgentProfilesReadTargetCopyWithImpl(this._self, this._then);

  final AgentProfilesReadTarget _self;
  final $Res Function(AgentProfilesReadTarget) _then;

/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(AgentProfilesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadRef,
  ));
}
/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadRefCopyWith<$Res> get reference {

  return $AgentProfilesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentProfilesReadTarget].
extension AgentProfilesReadTargetPatterns on AgentProfilesReadTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfilesReadTarget value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfilesReadTarget() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfilesReadTarget value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesReadTarget():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfilesReadTarget value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesReadTarget() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AgentProfilesReadRef reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfilesReadTarget() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductReadOrigin origin,  AgentProfilesReadRef reference)  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesReadTarget():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductReadOrigin origin,  AgentProfilesReadRef reference)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesReadTarget() when $default != null:
return $default(_that.origin,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfilesReadTarget implements AgentProfilesReadTarget {
  const _AgentProfilesReadTarget({required this.origin, required this.reference});


@override final  ProductReadOrigin origin;
@override final  AgentProfilesReadRef reference;

/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfilesReadTargetCopyWith<_AgentProfilesReadTarget> get copyWith => __$AgentProfilesReadTargetCopyWithImpl<_AgentProfilesReadTarget>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfilesReadTarget&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,origin,reference);
}

@override
String toString() {
    return 'AgentProfilesReadTarget(origin: $origin, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AgentProfilesReadTargetCopyWith<$Res> implements $AgentProfilesReadTargetCopyWith<$Res> {
  factory _$AgentProfilesReadTargetCopyWith(_AgentProfilesReadTarget value, $Res Function(_AgentProfilesReadTarget) _then) = __$AgentProfilesReadTargetCopyWithImpl;
@override @useResult
$Res call({
 ProductReadOrigin origin, AgentProfilesReadRef reference
});


@override $ProductReadOriginCopyWith<$Res> get origin;@override $AgentProfilesReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$AgentProfilesReadTargetCopyWithImpl<$Res>
    implements _$AgentProfilesReadTargetCopyWith<$Res> {
  __$AgentProfilesReadTargetCopyWithImpl(this._self, this._then);

  final _AgentProfilesReadTarget _self;
  final $Res Function(_AgentProfilesReadTarget) _then;

/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? origin = null,Object? reference = null,}) {
  return _then(_AgentProfilesReadTarget(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadRef,
  ));
}

/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res> get origin {

  return $ProductReadOriginCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of AgentProfilesReadTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadRefCopyWith<$Res> get reference {

  return $AgentProfilesReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ConfigurationHeader {

 ObservedHeader get source; int? get configurationRevision; int? get updatedAt; ConfigurationReadRef? get reference; ConfigurationRoleReadTarget? get roleRead;
/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationHeaderCopyWith<ConfigurationHeader> get copyWith => _$ConfigurationHeaderCopyWithImpl<ConfigurationHeader>(this as ConfigurationHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.configurationRevision, _this.configurationRevision) || other.configurationRevision == _this.configurationRevision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.roleRead, _this.roleRead) || other.roleRead == _this.roleRead));
}


@override
int get hashCode {
  final _this = this as ConfigurationHeader;
  return Object.hash(runtimeType,_this.source,_this.configurationRevision,_this.updatedAt,_this.reference,_this.roleRead);
}

@override
String toString() {
  final _this = this as ConfigurationHeader;
  return 'ConfigurationHeader(source: ${_this.source}, configurationRevision: ${_this.configurationRevision}, updatedAt: ${_this.updatedAt}, reference: ${_this.reference}, roleRead: ${_this.roleRead})';
}


}

/// @nodoc
abstract mixin class $ConfigurationHeaderCopyWith<$Res>  {
  factory $ConfigurationHeaderCopyWith(ConfigurationHeader value, $Res Function(ConfigurationHeader) _then) = _$ConfigurationHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, int? configurationRevision, int? updatedAt, ConfigurationReadRef? reference, ConfigurationRoleReadTarget? roleRead
});


$ObservedHeaderCopyWith<$Res> get source;$ConfigurationReadRefCopyWith<$Res>? get reference;$ConfigurationRoleReadTargetCopyWith<$Res>? get roleRead;

}
/// @nodoc
class _$ConfigurationHeaderCopyWithImpl<$Res>
    implements $ConfigurationHeaderCopyWith<$Res> {
  _$ConfigurationHeaderCopyWithImpl(this._self, this._then);

  final ConfigurationHeader _self;
  final $Res Function(ConfigurationHeader) _then;

/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? configurationRevision = freezed,Object? updatedAt = freezed,Object? reference = freezed,Object? roleRead = freezed,}) {
  return _then(ConfigurationHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,configurationRevision: freezed == configurationRevision ? _self.configurationRevision : configurationRevision // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationReadRef?,roleRead: freezed == roleRead ? _self.roleRead : roleRead // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget?,
  ));
}
/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ConfigurationReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res>? get roleRead {
    if (_self.roleRead == null) {
    return null;
  }

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.roleRead!, (value) {
    return _then(_self.copyWith(roleRead: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationHeader].
extension ConfigurationHeaderPatterns on ConfigurationHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationHeader value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  int? configurationRevision,  int? updatedAt,  ConfigurationReadRef? reference,  ConfigurationRoleReadTarget? roleRead)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationHeader() when $default != null:
return $default(_that.source,_that.configurationRevision,_that.updatedAt,_that.reference,_that.roleRead);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  int? configurationRevision,  int? updatedAt,  ConfigurationReadRef? reference,  ConfigurationRoleReadTarget? roleRead)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationHeader():
return $default(_that.source,_that.configurationRevision,_that.updatedAt,_that.reference,_that.roleRead);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  int? configurationRevision,  int? updatedAt,  ConfigurationReadRef? reference,  ConfigurationRoleReadTarget? roleRead)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationHeader() when $default != null:
return $default(_that.source,_that.configurationRevision,_that.updatedAt,_that.reference,_that.roleRead);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationHeader implements ConfigurationHeader {
  const _ConfigurationHeader({required this.source, required this.configurationRevision, required this.updatedAt, required this.reference, required this.roleRead});


@override final  ObservedHeader source;
@override final  int? configurationRevision;
@override final  int? updatedAt;
@override final  ConfigurationReadRef? reference;
@override final  ConfigurationRoleReadTarget? roleRead;

/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationHeaderCopyWith<_ConfigurationHeader> get copyWith => __$ConfigurationHeaderCopyWithImpl<_ConfigurationHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.configurationRevision, configurationRevision) || other.configurationRevision == configurationRevision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.roleRead, roleRead) || other.roleRead == roleRead));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,configurationRevision,updatedAt,reference,roleRead);
}

@override
String toString() {
    return 'ConfigurationHeader(source: $source, configurationRevision: $configurationRevision, updatedAt: $updatedAt, reference: $reference, roleRead: $roleRead)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationHeaderCopyWith<$Res> implements $ConfigurationHeaderCopyWith<$Res> {
  factory _$ConfigurationHeaderCopyWith(_ConfigurationHeader value, $Res Function(_ConfigurationHeader) _then) = __$ConfigurationHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, int? configurationRevision, int? updatedAt, ConfigurationReadRef? reference, ConfigurationRoleReadTarget? roleRead
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $ConfigurationReadRefCopyWith<$Res>? get reference;@override $ConfigurationRoleReadTargetCopyWith<$Res>? get roleRead;

}
/// @nodoc
class __$ConfigurationHeaderCopyWithImpl<$Res>
    implements _$ConfigurationHeaderCopyWith<$Res> {
  __$ConfigurationHeaderCopyWithImpl(this._self, this._then);

  final _ConfigurationHeader _self;
  final $Res Function(_ConfigurationHeader) _then;

/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? configurationRevision = freezed,Object? updatedAt = freezed,Object? reference = freezed,Object? roleRead = freezed,}) {
  return _then(_ConfigurationHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,configurationRevision: freezed == configurationRevision ? _self.configurationRevision : configurationRevision // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ConfigurationReadRef?,roleRead: freezed == roleRead ? _self.roleRead : roleRead // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget?,
  ));
}

/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $ConfigurationReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of ConfigurationHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res>? get roleRead {
    if (_self.roleRead == null) {
    return null;
  }

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.roleRead!, (value) {
    return _then(_self.copyWith(roleRead: value));
  });
}
}

/// @nodoc
mixin _$AgentProfilesHeader {

 ObservedHeader get source; int? get profilesRevision; AgentProfilesReadRef? get reference;
/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentProfilesHeaderCopyWith<AgentProfilesHeader> get copyWith => _$AgentProfilesHeaderCopyWithImpl<AgentProfilesHeader>(this as AgentProfilesHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentProfilesHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentProfilesHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.profilesRevision, _this.profilesRevision) || other.profilesRevision == _this.profilesRevision)&&(identical(other.reference, _this.reference) || other.reference == _this.reference));
}


@override
int get hashCode {
  final _this = this as AgentProfilesHeader;
  return Object.hash(runtimeType,_this.source,_this.profilesRevision,_this.reference);
}

@override
String toString() {
  final _this = this as AgentProfilesHeader;
  return 'AgentProfilesHeader(source: ${_this.source}, profilesRevision: ${_this.profilesRevision}, reference: ${_this.reference})';
}


}

/// @nodoc
abstract mixin class $AgentProfilesHeaderCopyWith<$Res>  {
  factory $AgentProfilesHeaderCopyWith(AgentProfilesHeader value, $Res Function(AgentProfilesHeader) _then) = _$AgentProfilesHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, int? profilesRevision, AgentProfilesReadRef? reference
});


$ObservedHeaderCopyWith<$Res> get source;$AgentProfilesReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class _$AgentProfilesHeaderCopyWithImpl<$Res>
    implements $AgentProfilesHeaderCopyWith<$Res> {
  _$AgentProfilesHeaderCopyWithImpl(this._self, this._then);

  final AgentProfilesHeader _self;
  final $Res Function(AgentProfilesHeader) _then;

/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? profilesRevision = freezed,Object? reference = freezed,}) {
  return _then(AgentProfilesHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,profilesRevision: freezed == profilesRevision ? _self.profilesRevision : profilesRevision // ignore: cast_nullable_to_non_nullable
as int?,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadRef?,
  ));
}
/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $AgentProfilesReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentProfilesHeader].
extension AgentProfilesHeaderPatterns on AgentProfilesHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentProfilesHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentProfilesHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentProfilesHeader value)  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentProfilesHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AgentProfilesHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  int? profilesRevision,  AgentProfilesReadRef? reference)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentProfilesHeader() when $default != null:
return $default(_that.source,_that.profilesRevision,_that.reference);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  int? profilesRevision,  AgentProfilesReadRef? reference)  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesHeader():
return $default(_that.source,_that.profilesRevision,_that.reference);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  int? profilesRevision,  AgentProfilesReadRef? reference)?  $default,) {final _that = this;
switch (_that) {
case _AgentProfilesHeader() when $default != null:
return $default(_that.source,_that.profilesRevision,_that.reference);case _:
  return null;

}
}

}

/// @nodoc


class _AgentProfilesHeader implements AgentProfilesHeader {
  const _AgentProfilesHeader({required this.source, required this.profilesRevision, required this.reference});


@override final  ObservedHeader source;
@override final  int? profilesRevision;
@override final  AgentProfilesReadRef? reference;

/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentProfilesHeaderCopyWith<_AgentProfilesHeader> get copyWith => __$AgentProfilesHeaderCopyWithImpl<_AgentProfilesHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentProfilesHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.profilesRevision, profilesRevision) || other.profilesRevision == profilesRevision)&&(identical(other.reference, reference) || other.reference == reference));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,profilesRevision,reference);
}

@override
String toString() {
    return 'AgentProfilesHeader(source: $source, profilesRevision: $profilesRevision, reference: $reference)';
}


}

/// @nodoc
abstract mixin class _$AgentProfilesHeaderCopyWith<$Res> implements $AgentProfilesHeaderCopyWith<$Res> {
  factory _$AgentProfilesHeaderCopyWith(_AgentProfilesHeader value, $Res Function(_AgentProfilesHeader) _then) = __$AgentProfilesHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, int? profilesRevision, AgentProfilesReadRef? reference
});


@override $ObservedHeaderCopyWith<$Res> get source;@override $AgentProfilesReadRefCopyWith<$Res>? get reference;

}
/// @nodoc
class __$AgentProfilesHeaderCopyWithImpl<$Res>
    implements _$AgentProfilesHeaderCopyWith<$Res> {
  __$AgentProfilesHeaderCopyWithImpl(this._self, this._then);

  final _AgentProfilesHeader _self;
  final $Res Function(_AgentProfilesHeader) _then;

/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? profilesRevision = freezed,Object? reference = freezed,}) {
  return _then(_AgentProfilesHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,profilesRevision: freezed == profilesRevision ? _self.profilesRevision : profilesRevision // ignore: cast_nullable_to_non_nullable
as int?,reference: freezed == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadRef?,
  ));
}

/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of AgentProfilesHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadRefCopyWith<$Res>? get reference {
    if (_self.reference == null) {
    return null;
  }

  return $AgentProfilesReadRefCopyWith<$Res>(_self.reference!, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$ConfigurationState {


/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<ConfigurationState> get copyWith => _$ConfigurationStateCopyWithImpl<ConfigurationState>(this as ConfigurationState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.accounts, _this.accounts) || other.accounts == _this.accounts)&&(identical(other.defaultAccountId, _this.defaultAccountId) || other.defaultAccountId == _this.defaultAccountId)&&(identical(other.modeRoutes, _this.modeRoutes) || other.modeRoutes == _this.modeRoutes)&&(identical(other.roles, _this.roles) || other.roles == _this.roles)&&(identical(other.permissionMode, _this.permissionMode) || other.permissionMode == _this.permissionMode)&&(identical(other.instructions, _this.instructions) || other.instructions == _this.instructions)&&(identical(other.skillsSettings, _this.skillsSettings) || other.skillsSettings == _this.skillsSettings)&&(identical(other.mcpConfigurations, _this.mcpConfigurations) || other.mcpConfigurations == _this.mcpConfigurations)&&(identical(other.general, _this.general) || other.general == _this.general)&&(identical(other.delegation, _this.delegation) || other.delegation == _this.delegation)&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.deepSeekSearch, _this.deepSeekSearch) || other.deepSeekSearch == _this.deepSeekSearch));
}


@override
int get hashCode {
  final _this = this as ConfigurationState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.accounts,_this.defaultAccountId,_this.modeRoutes,_this.roles,_this.permissionMode,_this.instructions,_this.skillsSettings,_this.mcpConfigurations,_this.general,_this.delegation,_this.webSearch,_this.deepSeekSearch);
}



}

/// @nodoc
abstract mixin class $ConfigurationStateCopyWith<$Res>  {
  factory $ConfigurationStateCopyWith(ConfigurationState value, $Res Function(ConfigurationState) _then) = _$ConfigurationStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<ConfigurationHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AccountConfiguration> accounts, ReadValue<String?, ConfigurationReadRef>? defaultAccountId, ReadValue<List<ModeModelRoute>, ConfigurationReadRef>? modeRoutes, ReadValue<List<RoleModelRoute>, ConfigurationReadRef>? roles, ReadValue<String, ConfigurationReadRef>? permissionMode, ReadValue<InstructionsSettings, ConfigurationReadRef>? instructions, ReadValue<SkillsSettings, ConfigurationReadRef>? skillsSettings, ReadValue<List<McpConfiguration>, ConfigurationReadRef>? mcpConfigurations, ReadValue<GeneralSettings, ConfigurationReadRef>? general, ReadValue<DelegationSettings, ConfigurationReadRef>? delegation, ReadValue<WebSearchConfiguration, ConfigurationReadRef>? webSearch, ReadValue<DeepSeekSearchConfiguration, ConfigurationReadRef>? deepSeekSearch
});


$ProductProjectionCopyWith<ConfigurationHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<AccountConfiguration, $Res> get accounts;$ReadValueCopyWith<String?, ConfigurationReadRef, $Res>? get defaultAccountId;$ReadValueCopyWith<List<ModeModelRoute>, ConfigurationReadRef, $Res>? get modeRoutes;$ReadValueCopyWith<List<RoleModelRoute>, ConfigurationReadRef, $Res>? get roles;$ReadValueCopyWith<String, ConfigurationReadRef, $Res>? get permissionMode;$ReadValueCopyWith<InstructionsSettings, ConfigurationReadRef, $Res>? get instructions;$ReadValueCopyWith<SkillsSettings, ConfigurationReadRef, $Res>? get skillsSettings;$ReadValueCopyWith<List<McpConfiguration>, ConfigurationReadRef, $Res>? get mcpConfigurations;$ReadValueCopyWith<GeneralSettings, ConfigurationReadRef, $Res>? get general;$ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>? get delegation;$ReadValueCopyWith<WebSearchConfiguration, ConfigurationReadRef, $Res>? get webSearch;$ReadValueCopyWith<DeepSeekSearchConfiguration, ConfigurationReadRef, $Res>? get deepSeekSearch;

}
/// @nodoc
class _$ConfigurationStateCopyWithImpl<$Res>
    implements $ConfigurationStateCopyWith<$Res> {
  _$ConfigurationStateCopyWithImpl(this._self, this._then);

  final ConfigurationState _self;
  final $Res Function(ConfigurationState) _then;

/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? accounts = null,Object? defaultAccountId = freezed,Object? modeRoutes = freezed,Object? roles = freezed,Object? permissionMode = freezed,Object? instructions = freezed,Object? skillsSettings = freezed,Object? mcpConfigurations = freezed,Object? general = freezed,Object? delegation = freezed,Object? webSearch = freezed,Object? deepSeekSearch = freezed,}) {
  return _then(ConfigurationState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<ConfigurationHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AccountConfiguration>,defaultAccountId: freezed == defaultAccountId ? _self.defaultAccountId : defaultAccountId // ignore: cast_nullable_to_non_nullable
as ReadValue<String?, ConfigurationReadRef>?,modeRoutes: freezed == modeRoutes ? _self.modeRoutes : modeRoutes // ignore: cast_nullable_to_non_nullable
as ReadValue<List<ModeModelRoute>, ConfigurationReadRef>?,roles: freezed == roles ? _self.roles : roles // ignore: cast_nullable_to_non_nullable
as ReadValue<List<RoleModelRoute>, ConfigurationReadRef>?,permissionMode: freezed == permissionMode ? _self.permissionMode : permissionMode // ignore: cast_nullable_to_non_nullable
as ReadValue<String, ConfigurationReadRef>?,instructions: freezed == instructions ? _self.instructions : instructions // ignore: cast_nullable_to_non_nullable
as ReadValue<InstructionsSettings, ConfigurationReadRef>?,skillsSettings: freezed == skillsSettings ? _self.skillsSettings : skillsSettings // ignore: cast_nullable_to_non_nullable
as ReadValue<SkillsSettings, ConfigurationReadRef>?,mcpConfigurations: freezed == mcpConfigurations ? _self.mcpConfigurations : mcpConfigurations // ignore: cast_nullable_to_non_nullable
as ReadValue<List<McpConfiguration>, ConfigurationReadRef>?,general: freezed == general ? _self.general : general // ignore: cast_nullable_to_non_nullable
as ReadValue<GeneralSettings, ConfigurationReadRef>?,delegation: freezed == delegation ? _self.delegation : delegation // ignore: cast_nullable_to_non_nullable
as ReadValue<DelegationSettings, ConfigurationReadRef>?,webSearch: freezed == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as ReadValue<WebSearchConfiguration, ConfigurationReadRef>?,deepSeekSearch: freezed == deepSeekSearch ? _self.deepSeekSearch : deepSeekSearch // ignore: cast_nullable_to_non_nullable
as ReadValue<DeepSeekSearchConfiguration, ConfigurationReadRef>?,
  ));
}
/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<ConfigurationHeader, $Res> get projection {

  return $ProductProjectionCopyWith<ConfigurationHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ConfigurationState
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
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AccountConfiguration, $Res> get accounts {

  return $CollectionMirrorCopyWith<AccountConfiguration, $Res>(_self.accounts, (value) {
    return _then(_self.copyWith(accounts: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String?, ConfigurationReadRef, $Res>? get defaultAccountId {
    if (_self.defaultAccountId == null) {
    return null;
  }

  return $ReadValueCopyWith<String?, ConfigurationReadRef, $Res>(_self.defaultAccountId!, (value) {
    return _then(_self.copyWith(defaultAccountId: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<ModeModelRoute>, ConfigurationReadRef, $Res>? get modeRoutes {
    if (_self.modeRoutes == null) {
    return null;
  }

  return $ReadValueCopyWith<List<ModeModelRoute>, ConfigurationReadRef, $Res>(_self.modeRoutes!, (value) {
    return _then(_self.copyWith(modeRoutes: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<RoleModelRoute>, ConfigurationReadRef, $Res>? get roles {
    if (_self.roles == null) {
    return null;
  }

  return $ReadValueCopyWith<List<RoleModelRoute>, ConfigurationReadRef, $Res>(_self.roles!, (value) {
    return _then(_self.copyWith(roles: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<String, ConfigurationReadRef, $Res>? get permissionMode {
    if (_self.permissionMode == null) {
    return null;
  }

  return $ReadValueCopyWith<String, ConfigurationReadRef, $Res>(_self.permissionMode!, (value) {
    return _then(_self.copyWith(permissionMode: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<InstructionsSettings, ConfigurationReadRef, $Res>? get instructions {
    if (_self.instructions == null) {
    return null;
  }

  return $ReadValueCopyWith<InstructionsSettings, ConfigurationReadRef, $Res>(_self.instructions!, (value) {
    return _then(_self.copyWith(instructions: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<SkillsSettings, ConfigurationReadRef, $Res>? get skillsSettings {
    if (_self.skillsSettings == null) {
    return null;
  }

  return $ReadValueCopyWith<SkillsSettings, ConfigurationReadRef, $Res>(_self.skillsSettings!, (value) {
    return _then(_self.copyWith(skillsSettings: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<McpConfiguration>, ConfigurationReadRef, $Res>? get mcpConfigurations {
    if (_self.mcpConfigurations == null) {
    return null;
  }

  return $ReadValueCopyWith<List<McpConfiguration>, ConfigurationReadRef, $Res>(_self.mcpConfigurations!, (value) {
    return _then(_self.copyWith(mcpConfigurations: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<GeneralSettings, ConfigurationReadRef, $Res>? get general {
    if (_self.general == null) {
    return null;
  }

  return $ReadValueCopyWith<GeneralSettings, ConfigurationReadRef, $Res>(_self.general!, (value) {
    return _then(_self.copyWith(general: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>? get delegation {
    if (_self.delegation == null) {
    return null;
  }

  return $ReadValueCopyWith<DelegationSettings, ConfigurationReadRef, $Res>(_self.delegation!, (value) {
    return _then(_self.copyWith(delegation: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<WebSearchConfiguration, ConfigurationReadRef, $Res>? get webSearch {
    if (_self.webSearch == null) {
    return null;
  }

  return $ReadValueCopyWith<WebSearchConfiguration, ConfigurationReadRef, $Res>(_self.webSearch!, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of ConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<DeepSeekSearchConfiguration, ConfigurationReadRef, $Res>? get deepSeekSearch {
    if (_self.deepSeekSearch == null) {
    return null;
  }

  return $ReadValueCopyWith<DeepSeekSearchConfiguration, ConfigurationReadRef, $Res>(_self.deepSeekSearch!, (value) {
    return _then(_self.copyWith(deepSeekSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationState].
extension ConfigurationStatePatterns on ConfigurationState {
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
mixin _$ProfilesState {


/// Create a copy of ProfilesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfilesStateCopyWith<ProfilesState> get copyWith => _$ProfilesStateCopyWithImpl<ProfilesState>(this as ProfilesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfilesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfilesState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.profiles, _this.profiles) || other.profiles == _this.profiles)&&const DeepCollectionEquality().equals(other.details, _this.details)&&(identical(other.diagnostics, _this.diagnostics) || other.diagnostics == _this.diagnostics));
}


@override
int get hashCode {
  final _this = this as ProfilesState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.profiles,const DeepCollectionEquality().hash(_this.details),_this.diagnostics);
}



}

/// @nodoc
abstract mixin class $ProfilesStateCopyWith<$Res>  {
  factory $ProfilesStateCopyWith(ProfilesState value, $Res Function(ProfilesState) _then) = _$ProfilesStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<AgentProfilesHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, CollectionMirror<AgentProfileSummary> profiles, Map<int, ReadValue<AgentProfileSnapshot, ProductEntityRef>> details, ReadValue<List<ProfileDiagnostic>, AgentProfilesReadRef>? diagnostics
});


$ProductProjectionCopyWith<AgentProfilesHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$CollectionMirrorCopyWith<AgentProfileSummary, $Res> get profiles;$ReadValueCopyWith<List<ProfileDiagnostic>, AgentProfilesReadRef, $Res>? get diagnostics;

}
/// @nodoc
class _$ProfilesStateCopyWithImpl<$Res>
    implements $ProfilesStateCopyWith<$Res> {
  _$ProfilesStateCopyWithImpl(this._self, this._then);

  final ProfilesState _self;
  final $Res Function(ProfilesState) _then;

/// Create a copy of ProfilesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? profiles = null,Object? details = null,Object? diagnostics = freezed,}) {
  return _then(ProfilesState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AgentProfilesHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as CollectionMirror<AgentProfileSummary>,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as Map<int, ReadValue<AgentProfileSnapshot, ProductEntityRef>>,diagnostics: freezed == diagnostics ? _self.diagnostics : diagnostics // ignore: cast_nullable_to_non_nullable
as ReadValue<List<ProfileDiagnostic>, AgentProfilesReadRef>?,
  ));
}
/// Create a copy of ProfilesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AgentProfilesHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AgentProfilesHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of ProfilesState
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
}/// Create a copy of ProfilesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionMirrorCopyWith<AgentProfileSummary, $Res> get profiles {

  return $CollectionMirrorCopyWith<AgentProfileSummary, $Res>(_self.profiles, (value) {
    return _then(_self.copyWith(profiles: value));
  });
}/// Create a copy of ProfilesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<List<ProfileDiagnostic>, AgentProfilesReadRef, $Res>? get diagnostics {
    if (_self.diagnostics == null) {
    return null;
  }

  return $ReadValueCopyWith<List<ProfileDiagnostic>, AgentProfilesReadRef, $Res>(_self.diagnostics!, (value) {
    return _then(_self.copyWith(diagnostics: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProfilesState].
extension ProfilesStatePatterns on ProfilesState {
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
