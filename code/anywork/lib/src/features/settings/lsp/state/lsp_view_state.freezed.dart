// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lsp_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LspCatalogViewState {

 LspState get source; Map<LspReadField, StudioFailure> get readIssues; Set<LspReadField> get reading;
/// Create a copy of LspCatalogViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspCatalogViewStateCopyWith<LspCatalogViewState> get copyWith => _$LspCatalogViewStateCopyWithImpl<LspCatalogViewState>(this as LspCatalogViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspCatalogViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspCatalogViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&const DeepCollectionEquality().equals(other.reading, _this.reading));
}


@override
int get hashCode {
  final _this = this as LspCatalogViewState;
  return Object.hash(runtimeType,_this.source,const DeepCollectionEquality().hash(_this.readIssues),const DeepCollectionEquality().hash(_this.reading));
}



}

/// @nodoc
abstract mixin class $LspCatalogViewStateCopyWith<$Res>  {
  factory $LspCatalogViewStateCopyWith(LspCatalogViewState value, $Res Function(LspCatalogViewState) _then) = _$LspCatalogViewStateCopyWithImpl;
@useResult
$Res call({
 LspState source, Map<LspReadField, StudioFailure> readIssues, Set<LspReadField> reading
});


$LspStateCopyWith<$Res> get source;

}
/// @nodoc
class _$LspCatalogViewStateCopyWithImpl<$Res>
    implements $LspCatalogViewStateCopyWith<$Res> {
  _$LspCatalogViewStateCopyWithImpl(this._self, this._then);

  final LspCatalogViewState _self;
  final $Res Function(LspCatalogViewState) _then;

/// Create a copy of LspCatalogViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? readIssues = null,Object? reading = null,}) {
  return _then(LspCatalogViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as LspState,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<LspReadField, StudioFailure>,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<LspReadField>,
  ));
}
/// Create a copy of LspCatalogViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspStateCopyWith<$Res> get source {

  return $LspStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspCatalogViewState].
extension LspCatalogViewStatePatterns on LspCatalogViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspCatalogViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspCatalogViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspCatalogViewState value)  $default,){
final _that = this;
switch (_that) {
case _LspCatalogViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspCatalogViewState value)?  $default,){
final _that = this;
switch (_that) {
case _LspCatalogViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LspState source,  Map<LspReadField, StudioFailure> readIssues,  Set<LspReadField> reading)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspCatalogViewState() when $default != null:
return $default(_that.source,_that.readIssues,_that.reading);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LspState source,  Map<LspReadField, StudioFailure> readIssues,  Set<LspReadField> reading)  $default,) {final _that = this;
switch (_that) {
case _LspCatalogViewState():
return $default(_that.source,_that.readIssues,_that.reading);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LspState source,  Map<LspReadField, StudioFailure> readIssues,  Set<LspReadField> reading)?  $default,) {final _that = this;
switch (_that) {
case _LspCatalogViewState() when $default != null:
return $default(_that.source,_that.readIssues,_that.reading);case _:
  return null;

}
}

}

/// @nodoc


class _LspCatalogViewState implements LspCatalogViewState {
  const _LspCatalogViewState({required this.source,  Map<LspReadField, StudioFailure> readIssues = const {},  Set<LspReadField> reading = const {}}): _readIssues = readIssues,_reading = reading;


@override final  LspState source;
 final  Map<LspReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<LspReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

 final  Set<LspReadField> _reading;
@override@JsonKey() Set<LspReadField> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}


/// Create a copy of LspCatalogViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspCatalogViewStateCopyWith<_LspCatalogViewState> get copyWith => __$LspCatalogViewStateCopyWithImpl<_LspCatalogViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspCatalogViewState&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&const DeepCollectionEquality().equals(other.reading, _reading));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,const DeepCollectionEquality().hash(_readIssues),const DeepCollectionEquality().hash(_reading));
}



}

/// @nodoc
abstract mixin class _$LspCatalogViewStateCopyWith<$Res> implements $LspCatalogViewStateCopyWith<$Res> {
  factory _$LspCatalogViewStateCopyWith(_LspCatalogViewState value, $Res Function(_LspCatalogViewState) _then) = __$LspCatalogViewStateCopyWithImpl;
@override @useResult
$Res call({
 LspState source, Map<LspReadField, StudioFailure> readIssues, Set<LspReadField> reading
});


@override $LspStateCopyWith<$Res> get source;

}
/// @nodoc
class __$LspCatalogViewStateCopyWithImpl<$Res>
    implements _$LspCatalogViewStateCopyWith<$Res> {
  __$LspCatalogViewStateCopyWithImpl(this._self, this._then);

  final _LspCatalogViewState _self;
  final $Res Function(_LspCatalogViewState) _then;

/// Create a copy of LspCatalogViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? readIssues = null,Object? reading = null,}) {
  return _then(_LspCatalogViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as LspState,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<LspReadField, StudioFailure>,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<LspReadField>,
  ));
}

/// Create a copy of LspCatalogViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspStateCopyWith<$Res> get source {

  return $LspStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

/// @nodoc
mixin _$LspActionsViewState {

 String get projectId; int get latestIntent; Map<(LspActionKind, String?,), SettingsAction> get actions;
/// Create a copy of LspActionsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspActionsViewStateCopyWith<LspActionsViewState> get copyWith => _$LspActionsViewStateCopyWithImpl<LspActionsViewState>(this as LspActionsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspActionsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspActionsViewState&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&const DeepCollectionEquality().equals(other.actions, _this.actions));
}


@override
int get hashCode {
  final _this = this as LspActionsViewState;
  return Object.hash(runtimeType,_this.projectId,_this.latestIntent,const DeepCollectionEquality().hash(_this.actions));
}

@override
String toString() {
  final _this = this as LspActionsViewState;
  return 'LspActionsViewState(projectId: ${_this.projectId}, latestIntent: ${_this.latestIntent}, actions: ${_this.actions})';
}


}

/// @nodoc
abstract mixin class $LspActionsViewStateCopyWith<$Res>  {
  factory $LspActionsViewStateCopyWith(LspActionsViewState value, $Res Function(LspActionsViewState) _then) = _$LspActionsViewStateCopyWithImpl;
@useResult
$Res call({
 String projectId, int latestIntent, Map<(LspActionKind, String?,), SettingsAction> actions
});




}
/// @nodoc
class _$LspActionsViewStateCopyWithImpl<$Res>
    implements $LspActionsViewStateCopyWith<$Res> {
  _$LspActionsViewStateCopyWithImpl(this._self, this._then);

  final LspActionsViewState _self;
  final $Res Function(LspActionsViewState) _then;

/// Create a copy of LspActionsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? latestIntent = null,Object? actions = null,}) {
  return _then(LspActionsViewState(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<(LspActionKind, String?,), SettingsAction>,
  ));
}

}


/// Adds pattern-matching-related methods to [LspActionsViewState].
extension LspActionsViewStatePatterns on LspActionsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspActionsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspActionsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspActionsViewState value)  $default,){
final _that = this;
switch (_that) {
case _LspActionsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspActionsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _LspActionsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  int latestIntent,  Map<(LspActionKind, String?,), SettingsAction> actions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspActionsViewState() when $default != null:
return $default(_that.projectId,_that.latestIntent,_that.actions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  int latestIntent,  Map<(LspActionKind, String?,), SettingsAction> actions)  $default,) {final _that = this;
switch (_that) {
case _LspActionsViewState():
return $default(_that.projectId,_that.latestIntent,_that.actions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  int latestIntent,  Map<(LspActionKind, String?,), SettingsAction> actions)?  $default,) {final _that = this;
switch (_that) {
case _LspActionsViewState() when $default != null:
return $default(_that.projectId,_that.latestIntent,_that.actions);case _:
  return null;

}
}

}

/// @nodoc


class _LspActionsViewState implements LspActionsViewState {
  const _LspActionsViewState({required this.projectId, this.latestIntent = 0,  Map<(LspActionKind, String?,), SettingsAction> actions = const {}}): _actions = actions;


@override final  String projectId;
@override@JsonKey() final  int latestIntent;
 final  Map<(LspActionKind, String?,), SettingsAction> _actions;
@override@JsonKey() Map<(LspActionKind, String?,), SettingsAction> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}


/// Create a copy of LspActionsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspActionsViewStateCopyWith<_LspActionsViewState> get copyWith => __$LspActionsViewStateCopyWithImpl<_LspActionsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspActionsViewState&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&const DeepCollectionEquality().equals(other.actions, _actions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,latestIntent,const DeepCollectionEquality().hash(_actions));
}

@override
String toString() {
    return 'LspActionsViewState(projectId: $projectId, latestIntent: $latestIntent, actions: $actions)';
}


}

/// @nodoc
abstract mixin class _$LspActionsViewStateCopyWith<$Res> implements $LspActionsViewStateCopyWith<$Res> {
  factory _$LspActionsViewStateCopyWith(_LspActionsViewState value, $Res Function(_LspActionsViewState) _then) = __$LspActionsViewStateCopyWithImpl;
@override @useResult
$Res call({
 String projectId, int latestIntent, Map<(LspActionKind, String?,), SettingsAction> actions
});




}
/// @nodoc
class __$LspActionsViewStateCopyWithImpl<$Res>
    implements _$LspActionsViewStateCopyWith<$Res> {
  __$LspActionsViewStateCopyWithImpl(this._self, this._then);

  final _LspActionsViewState _self;
  final $Res Function(_LspActionsViewState) _then;

/// Create a copy of LspActionsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? latestIntent = null,Object? actions = null,}) {
  return _then(_LspActionsViewState(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<(LspActionKind, String?,), SettingsAction>,
  ));
}


}

// dart format on
