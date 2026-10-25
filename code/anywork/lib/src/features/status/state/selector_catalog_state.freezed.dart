// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'selector_catalog_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SelectorCatalogState {

 ConfigurationState get configuration; ModelsState get models; ModesState get modes; Set<SelectorRead> get reading; Map<SelectorRead, StudioFailure> get errors;
/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SelectorCatalogStateCopyWith<SelectorCatalogState> get copyWith => _$SelectorCatalogStateCopyWithImpl<SelectorCatalogState>(this as SelectorCatalogState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SelectorCatalogState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SelectorCatalogState&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.models, _this.models) || other.models == _this.models)&&(identical(other.modes, _this.modes) || other.modes == _this.modes)&&const DeepCollectionEquality().equals(other.reading, _this.reading)&&const DeepCollectionEquality().equals(other.errors, _this.errors));
}


@override
int get hashCode {
  final _this = this as SelectorCatalogState;
  return Object.hash(runtimeType,_this.configuration,_this.models,_this.modes,const DeepCollectionEquality().hash(_this.reading),const DeepCollectionEquality().hash(_this.errors));
}



}

/// @nodoc
abstract mixin class $SelectorCatalogStateCopyWith<$Res>  {
  factory $SelectorCatalogStateCopyWith(SelectorCatalogState value, $Res Function(SelectorCatalogState) _then) = _$SelectorCatalogStateCopyWithImpl;
@useResult
$Res call({
 ConfigurationState configuration, ModelsState models, ModesState modes, Set<SelectorRead> reading, Map<SelectorRead, StudioFailure> errors
});


$ConfigurationStateCopyWith<$Res> get configuration;$ModelsStateCopyWith<$Res> get models;$ModesStateCopyWith<$Res> get modes;

}
/// @nodoc
class _$SelectorCatalogStateCopyWithImpl<$Res>
    implements $SelectorCatalogStateCopyWith<$Res> {
  _$SelectorCatalogStateCopyWithImpl(this._self, this._then);

  final SelectorCatalogState _self;
  final $Res Function(SelectorCatalogState) _then;

/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuration = null,Object? models = null,Object? modes = null,Object? reading = null,Object? errors = null,}) {
  return _then(SelectorCatalogState(
configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationState,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelsState,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as ModesState,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<SelectorRead>,errors: null == errors ? _self.errors : errors // ignore: cast_nullable_to_non_nullable
as Map<SelectorRead, StudioFailure>,
  ));
}
/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configuration {

  return $ConfigurationStateCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get models {

  return $ModelsStateCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModesStateCopyWith<$Res> get modes {

  return $ModesStateCopyWith<$Res>(_self.modes, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}


/// Adds pattern-matching-related methods to [SelectorCatalogState].
extension SelectorCatalogStatePatterns on SelectorCatalogState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SelectorCatalogState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SelectorCatalogState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SelectorCatalogState value)  $default,){
final _that = this;
switch (_that) {
case _SelectorCatalogState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SelectorCatalogState value)?  $default,){
final _that = this;
switch (_that) {
case _SelectorCatalogState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationState configuration,  ModelsState models,  ModesState modes,  Set<SelectorRead> reading,  Map<SelectorRead, StudioFailure> errors)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SelectorCatalogState() when $default != null:
return $default(_that.configuration,_that.models,_that.modes,_that.reading,_that.errors);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationState configuration,  ModelsState models,  ModesState modes,  Set<SelectorRead> reading,  Map<SelectorRead, StudioFailure> errors)  $default,) {final _that = this;
switch (_that) {
case _SelectorCatalogState():
return $default(_that.configuration,_that.models,_that.modes,_that.reading,_that.errors);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationState configuration,  ModelsState models,  ModesState modes,  Set<SelectorRead> reading,  Map<SelectorRead, StudioFailure> errors)?  $default,) {final _that = this;
switch (_that) {
case _SelectorCatalogState() when $default != null:
return $default(_that.configuration,_that.models,_that.modes,_that.reading,_that.errors);case _:
  return null;

}
}

}

/// @nodoc


class _SelectorCatalogState implements SelectorCatalogState {
  const _SelectorCatalogState({required this.configuration, required this.models, required this.modes,  Set<SelectorRead> reading = const {},  Map<SelectorRead, StudioFailure> errors = const {}}): _reading = reading,_errors = errors;


@override final  ConfigurationState configuration;
@override final  ModelsState models;
@override final  ModesState modes;
 final  Set<SelectorRead> _reading;
@override@JsonKey() Set<SelectorRead> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}

 final  Map<SelectorRead, StudioFailure> _errors;
@override@JsonKey() Map<SelectorRead, StudioFailure> get errors {
  if (_errors is EqualUnmodifiableMapView) return _errors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_errors);
}


/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SelectorCatalogStateCopyWith<_SelectorCatalogState> get copyWith => __$SelectorCatalogStateCopyWithImpl<_SelectorCatalogState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SelectorCatalogState&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.models, models) || other.models == models)&&(identical(other.modes, modes) || other.modes == modes)&&const DeepCollectionEquality().equals(other.reading, _reading)&&const DeepCollectionEquality().equals(other.errors, _errors));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configuration,models,modes,const DeepCollectionEquality().hash(_reading),const DeepCollectionEquality().hash(_errors));
}



}

/// @nodoc
abstract mixin class _$SelectorCatalogStateCopyWith<$Res> implements $SelectorCatalogStateCopyWith<$Res> {
  factory _$SelectorCatalogStateCopyWith(_SelectorCatalogState value, $Res Function(_SelectorCatalogState) _then) = __$SelectorCatalogStateCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationState configuration, ModelsState models, ModesState modes, Set<SelectorRead> reading, Map<SelectorRead, StudioFailure> errors
});


@override $ConfigurationStateCopyWith<$Res> get configuration;@override $ModelsStateCopyWith<$Res> get models;@override $ModesStateCopyWith<$Res> get modes;

}
/// @nodoc
class __$SelectorCatalogStateCopyWithImpl<$Res>
    implements _$SelectorCatalogStateCopyWith<$Res> {
  __$SelectorCatalogStateCopyWithImpl(this._self, this._then);

  final _SelectorCatalogState _self;
  final $Res Function(_SelectorCatalogState) _then;

/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configuration = null,Object? models = null,Object? modes = null,Object? reading = null,Object? errors = null,}) {
  return _then(_SelectorCatalogState(
configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationState,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelsState,modes: null == modes ? _self.modes : modes // ignore: cast_nullable_to_non_nullable
as ModesState,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<SelectorRead>,errors: null == errors ? _self._errors : errors // ignore: cast_nullable_to_non_nullable
as Map<SelectorRead, StudioFailure>,
  ));
}

/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configuration {

  return $ConfigurationStateCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelsStateCopyWith<$Res> get models {

  return $ModelsStateCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}/// Create a copy of SelectorCatalogState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModesStateCopyWith<$Res> get modes {

  return $ModesStateCopyWith<$Res>(_self.modes, (value) {
    return _then(_self.copyWith(modes: value));
  });
}
}

// dart format on
