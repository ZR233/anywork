// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'config_projection_stamp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConfigProjectionStamp {

 int get settingsRevision; int get modelCatalogRevision; bool get closing;
/// Create a copy of ConfigProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigProjectionStampCopyWith<ConfigProjectionStamp> get copyWith => _$ConfigProjectionStampCopyWithImpl<ConfigProjectionStamp>(this as ConfigProjectionStamp, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigProjectionStamp;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigProjectionStamp&&(identical(other.settingsRevision, _this.settingsRevision) || other.settingsRevision == _this.settingsRevision)&&(identical(other.modelCatalogRevision, _this.modelCatalogRevision) || other.modelCatalogRevision == _this.modelCatalogRevision)&&(identical(other.closing, _this.closing) || other.closing == _this.closing));
}


@override
int get hashCode {
  final _this = this as ConfigProjectionStamp;
  return Object.hash(runtimeType,_this.settingsRevision,_this.modelCatalogRevision,_this.closing);
}

@override
String toString() {
  final _this = this as ConfigProjectionStamp;
  return 'ConfigProjectionStamp(settingsRevision: ${_this.settingsRevision}, modelCatalogRevision: ${_this.modelCatalogRevision}, closing: ${_this.closing})';
}


}

/// @nodoc
abstract mixin class $ConfigProjectionStampCopyWith<$Res>  {
  factory $ConfigProjectionStampCopyWith(ConfigProjectionStamp value, $Res Function(ConfigProjectionStamp) _then) = _$ConfigProjectionStampCopyWithImpl;
@useResult
$Res call({
 int settingsRevision, int modelCatalogRevision, bool closing
});




}
/// @nodoc
class _$ConfigProjectionStampCopyWithImpl<$Res>
    implements $ConfigProjectionStampCopyWith<$Res> {
  _$ConfigProjectionStampCopyWithImpl(this._self, this._then);

  final ConfigProjectionStamp _self;
  final $Res Function(ConfigProjectionStamp) _then;

/// Create a copy of ConfigProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? settingsRevision = null,Object? modelCatalogRevision = null,Object? closing = null,}) {
  return _then(ConfigProjectionStamp(
settingsRevision: null == settingsRevision ? _self.settingsRevision : settingsRevision // ignore: cast_nullable_to_non_nullable
as int,modelCatalogRevision: null == modelCatalogRevision ? _self.modelCatalogRevision : modelCatalogRevision // ignore: cast_nullable_to_non_nullable
as int,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ConfigProjectionStamp].
extension ConfigProjectionStampPatterns on ConfigProjectionStamp {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigProjectionStamp value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigProjectionStamp() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigProjectionStamp value)  $default,){
final _that = this;
switch (_that) {
case _ConfigProjectionStamp():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigProjectionStamp value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigProjectionStamp() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int settingsRevision,  int modelCatalogRevision,  bool closing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigProjectionStamp() when $default != null:
return $default(_that.settingsRevision,_that.modelCatalogRevision,_that.closing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int settingsRevision,  int modelCatalogRevision,  bool closing)  $default,) {final _that = this;
switch (_that) {
case _ConfigProjectionStamp():
return $default(_that.settingsRevision,_that.modelCatalogRevision,_that.closing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int settingsRevision,  int modelCatalogRevision,  bool closing)?  $default,) {final _that = this;
switch (_that) {
case _ConfigProjectionStamp() when $default != null:
return $default(_that.settingsRevision,_that.modelCatalogRevision,_that.closing);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigProjectionStamp implements ConfigProjectionStamp {
  const _ConfigProjectionStamp({required this.settingsRevision, required this.modelCatalogRevision, required this.closing});


@override final  int settingsRevision;
@override final  int modelCatalogRevision;
@override final  bool closing;

/// Create a copy of ConfigProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigProjectionStampCopyWith<_ConfigProjectionStamp> get copyWith => __$ConfigProjectionStampCopyWithImpl<_ConfigProjectionStamp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigProjectionStamp&&(identical(other.settingsRevision, settingsRevision) || other.settingsRevision == settingsRevision)&&(identical(other.modelCatalogRevision, modelCatalogRevision) || other.modelCatalogRevision == modelCatalogRevision)&&(identical(other.closing, closing) || other.closing == closing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,settingsRevision,modelCatalogRevision,closing);
}

@override
String toString() {
    return 'ConfigProjectionStamp(settingsRevision: $settingsRevision, modelCatalogRevision: $modelCatalogRevision, closing: $closing)';
}


}

/// @nodoc
abstract mixin class _$ConfigProjectionStampCopyWith<$Res> implements $ConfigProjectionStampCopyWith<$Res> {
  factory _$ConfigProjectionStampCopyWith(_ConfigProjectionStamp value, $Res Function(_ConfigProjectionStamp) _then) = __$ConfigProjectionStampCopyWithImpl;
@override @useResult
$Res call({
 int settingsRevision, int modelCatalogRevision, bool closing
});




}
/// @nodoc
class __$ConfigProjectionStampCopyWithImpl<$Res>
    implements _$ConfigProjectionStampCopyWith<$Res> {
  __$ConfigProjectionStampCopyWithImpl(this._self, this._then);

  final _ConfigProjectionStamp _self;
  final $Res Function(_ConfigProjectionStamp) _then;

/// Create a copy of ConfigProjectionStamp
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? settingsRevision = null,Object? modelCatalogRevision = null,Object? closing = null,}) {
  return _then(_ConfigProjectionStamp(
settingsRevision: null == settingsRevision ? _self.settingsRevision : settingsRevision // ignore: cast_nullable_to_non_nullable
as int,modelCatalogRevision: null == modelCatalogRevision ? _self.modelCatalogRevision : modelCatalogRevision // ignore: cast_nullable_to_non_nullable
as int,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
