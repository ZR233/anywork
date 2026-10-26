// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mcp_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$McpServerDraft {

 bool get enabled; String get endpoint; Set<McpConfigField> get dirty; Map<McpConfigField, int> get revisions; Map<McpConfigField, SettingsAction> get actions; bool get composing;
/// Create a copy of McpServerDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpServerDraftCopyWith<McpServerDraft> get copyWith => _$McpServerDraftCopyWithImpl<McpServerDraft>(this as McpServerDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpServerDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpServerDraft&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&const DeepCollectionEquality().equals(other.dirty, _this.dirty)&&const DeepCollectionEquality().equals(other.revisions, _this.revisions)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&(identical(other.composing, _this.composing) || other.composing == _this.composing));
}


@override
int get hashCode {
  final _this = this as McpServerDraft;
  return Object.hash(runtimeType,_this.enabled,_this.endpoint,const DeepCollectionEquality().hash(_this.dirty),const DeepCollectionEquality().hash(_this.revisions),const DeepCollectionEquality().hash(_this.actions),_this.composing);
}



}

/// @nodoc
abstract mixin class $McpServerDraftCopyWith<$Res>  {
  factory $McpServerDraftCopyWith(McpServerDraft value, $Res Function(McpServerDraft) _then) = _$McpServerDraftCopyWithImpl;
@useResult
$Res call({
 bool enabled, String endpoint, Set<McpConfigField> dirty, Map<McpConfigField, int> revisions, Map<McpConfigField, SettingsAction> actions, bool composing
});




}
/// @nodoc
class _$McpServerDraftCopyWithImpl<$Res>
    implements $McpServerDraftCopyWith<$Res> {
  _$McpServerDraftCopyWithImpl(this._self, this._then);

  final McpServerDraft _self;
  final $Res Function(McpServerDraft) _then;

/// Create a copy of McpServerDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? enabled = null,Object? endpoint = null,Object? dirty = null,Object? revisions = null,Object? actions = null,Object? composing = null,}) {
  return _then(McpServerDraft(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as Set<McpConfigField>,revisions: null == revisions ? _self.revisions : revisions // ignore: cast_nullable_to_non_nullable
as Map<McpConfigField, int>,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<McpConfigField, SettingsAction>,composing: null == composing ? _self.composing : composing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [McpServerDraft].
extension McpServerDraftPatterns on McpServerDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpServerDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpServerDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpServerDraft value)  $default,){
final _that = this;
switch (_that) {
case _McpServerDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpServerDraft value)?  $default,){
final _that = this;
switch (_that) {
case _McpServerDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool enabled,  String endpoint,  Set<McpConfigField> dirty,  Map<McpConfigField, int> revisions,  Map<McpConfigField, SettingsAction> actions,  bool composing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpServerDraft() when $default != null:
return $default(_that.enabled,_that.endpoint,_that.dirty,_that.revisions,_that.actions,_that.composing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool enabled,  String endpoint,  Set<McpConfigField> dirty,  Map<McpConfigField, int> revisions,  Map<McpConfigField, SettingsAction> actions,  bool composing)  $default,) {final _that = this;
switch (_that) {
case _McpServerDraft():
return $default(_that.enabled,_that.endpoint,_that.dirty,_that.revisions,_that.actions,_that.composing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool enabled,  String endpoint,  Set<McpConfigField> dirty,  Map<McpConfigField, int> revisions,  Map<McpConfigField, SettingsAction> actions,  bool composing)?  $default,) {final _that = this;
switch (_that) {
case _McpServerDraft() when $default != null:
return $default(_that.enabled,_that.endpoint,_that.dirty,_that.revisions,_that.actions,_that.composing);case _:
  return null;

}
}

}

/// @nodoc


class _McpServerDraft implements McpServerDraft {
  const _McpServerDraft({required this.enabled, required this.endpoint,  Set<McpConfigField> dirty = const {},  Map<McpConfigField, int> revisions = const {},  Map<McpConfigField, SettingsAction> actions = const {}, this.composing = false}): _dirty = dirty,_revisions = revisions,_actions = actions;


@override final  bool enabled;
@override final  String endpoint;
 final  Set<McpConfigField> _dirty;
@override@JsonKey() Set<McpConfigField> get dirty {
  if (_dirty is EqualUnmodifiableSetView) return _dirty;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_dirty);
}

 final  Map<McpConfigField, int> _revisions;
@override@JsonKey() Map<McpConfigField, int> get revisions {
  if (_revisions is EqualUnmodifiableMapView) return _revisions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_revisions);
}

 final  Map<McpConfigField, SettingsAction> _actions;
@override@JsonKey() Map<McpConfigField, SettingsAction> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}

@override@JsonKey() final  bool composing;

/// Create a copy of McpServerDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpServerDraftCopyWith<_McpServerDraft> get copyWith => __$McpServerDraftCopyWithImpl<_McpServerDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpServerDraft&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&const DeepCollectionEquality().equals(other.dirty, _dirty)&&const DeepCollectionEquality().equals(other.revisions, _revisions)&&const DeepCollectionEquality().equals(other.actions, _actions)&&(identical(other.composing, composing) || other.composing == composing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,enabled,endpoint,const DeepCollectionEquality().hash(_dirty),const DeepCollectionEquality().hash(_revisions),const DeepCollectionEquality().hash(_actions),composing);
}



}

/// @nodoc
abstract mixin class _$McpServerDraftCopyWith<$Res> implements $McpServerDraftCopyWith<$Res> {
  factory _$McpServerDraftCopyWith(_McpServerDraft value, $Res Function(_McpServerDraft) _then) = __$McpServerDraftCopyWithImpl;
@override @useResult
$Res call({
 bool enabled, String endpoint, Set<McpConfigField> dirty, Map<McpConfigField, int> revisions, Map<McpConfigField, SettingsAction> actions, bool composing
});




}
/// @nodoc
class __$McpServerDraftCopyWithImpl<$Res>
    implements _$McpServerDraftCopyWith<$Res> {
  __$McpServerDraftCopyWithImpl(this._self, this._then);

  final _McpServerDraft _self;
  final $Res Function(_McpServerDraft) _then;

/// Create a copy of McpServerDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? enabled = null,Object? endpoint = null,Object? dirty = null,Object? revisions = null,Object? actions = null,Object? composing = null,}) {
  return _then(_McpServerDraft(
enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,dirty: null == dirty ? _self._dirty : dirty // ignore: cast_nullable_to_non_nullable
as Set<McpConfigField>,revisions: null == revisions ? _self._revisions : revisions // ignore: cast_nullable_to_non_nullable
as Map<McpConfigField, int>,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<McpConfigField, SettingsAction>,composing: null == composing ? _self.composing : composing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$McpViewState {

 ConfigurationState get configurationSource; McpState get source; Map<String, McpServerDraft> get drafts; Map<String, SettingsAction> get resets; SettingsAction? get resetAllAction; int get latestIntent; Map<McpReadField, StudioFailure> get readIssues; Set<McpReadField> get reading;
/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$McpViewStateCopyWith<McpViewState> get copyWith => _$McpViewStateCopyWithImpl<McpViewState>(this as McpViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as McpViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is McpViewState&&(identical(other.configurationSource, _this.configurationSource) || other.configurationSource == _this.configurationSource)&&(identical(other.source, _this.source) || other.source == _this.source)&&const DeepCollectionEquality().equals(other.drafts, _this.drafts)&&const DeepCollectionEquality().equals(other.resets, _this.resets)&&(identical(other.resetAllAction, _this.resetAllAction) || other.resetAllAction == _this.resetAllAction)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&const DeepCollectionEquality().equals(other.reading, _this.reading));
}


@override
int get hashCode {
  final _this = this as McpViewState;
  return Object.hash(runtimeType,_this.configurationSource,_this.source,const DeepCollectionEquality().hash(_this.drafts),const DeepCollectionEquality().hash(_this.resets),_this.resetAllAction,_this.latestIntent,const DeepCollectionEquality().hash(_this.readIssues),const DeepCollectionEquality().hash(_this.reading));
}



}

/// @nodoc
abstract mixin class $McpViewStateCopyWith<$Res>  {
  factory $McpViewStateCopyWith(McpViewState value, $Res Function(McpViewState) _then) = _$McpViewStateCopyWithImpl;
@useResult
$Res call({
 ConfigurationState configurationSource, McpState source, Map<String, McpServerDraft> drafts, Map<String, SettingsAction> resets, SettingsAction? resetAllAction, int latestIntent, Map<McpReadField, StudioFailure> readIssues, Set<McpReadField> reading
});


$ConfigurationStateCopyWith<$Res> get configurationSource;$McpStateCopyWith<$Res> get source;$SettingsActionCopyWith<$Res>? get resetAllAction;

}
/// @nodoc
class _$McpViewStateCopyWithImpl<$Res>
    implements $McpViewStateCopyWith<$Res> {
  _$McpViewStateCopyWithImpl(this._self, this._then);

  final McpViewState _self;
  final $Res Function(McpViewState) _then;

/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configurationSource = null,Object? source = null,Object? drafts = null,Object? resets = null,Object? resetAllAction = freezed,Object? latestIntent = null,Object? readIssues = null,Object? reading = null,}) {
  return _then(McpViewState(
configurationSource: null == configurationSource ? _self.configurationSource : configurationSource // ignore: cast_nullable_to_non_nullable
as ConfigurationState,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as McpState,drafts: null == drafts ? _self.drafts : drafts // ignore: cast_nullable_to_non_nullable
as Map<String, McpServerDraft>,resets: null == resets ? _self.resets : resets // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsAction>,resetAllAction: freezed == resetAllAction ? _self.resetAllAction : resetAllAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<McpReadField, StudioFailure>,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as Set<McpReadField>,
  ));
}
/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configurationSource {

  return $ConfigurationStateCopyWith<$Res>(_self.configurationSource, (value) {
    return _then(_self.copyWith(configurationSource: value));
  });
}/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpStateCopyWith<$Res> get source {

  return $McpStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get resetAllAction {
    if (_self.resetAllAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.resetAllAction!, (value) {
    return _then(_self.copyWith(resetAllAction: value));
  });
}
}


/// Adds pattern-matching-related methods to [McpViewState].
extension McpViewStatePatterns on McpViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _McpViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _McpViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _McpViewState value)  $default,){
final _that = this;
switch (_that) {
case _McpViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _McpViewState value)?  $default,){
final _that = this;
switch (_that) {
case _McpViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationState configurationSource,  McpState source,  Map<String, McpServerDraft> drafts,  Map<String, SettingsAction> resets,  SettingsAction? resetAllAction,  int latestIntent,  Map<McpReadField, StudioFailure> readIssues,  Set<McpReadField> reading)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _McpViewState() when $default != null:
return $default(_that.configurationSource,_that.source,_that.drafts,_that.resets,_that.resetAllAction,_that.latestIntent,_that.readIssues,_that.reading);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationState configurationSource,  McpState source,  Map<String, McpServerDraft> drafts,  Map<String, SettingsAction> resets,  SettingsAction? resetAllAction,  int latestIntent,  Map<McpReadField, StudioFailure> readIssues,  Set<McpReadField> reading)  $default,) {final _that = this;
switch (_that) {
case _McpViewState():
return $default(_that.configurationSource,_that.source,_that.drafts,_that.resets,_that.resetAllAction,_that.latestIntent,_that.readIssues,_that.reading);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationState configurationSource,  McpState source,  Map<String, McpServerDraft> drafts,  Map<String, SettingsAction> resets,  SettingsAction? resetAllAction,  int latestIntent,  Map<McpReadField, StudioFailure> readIssues,  Set<McpReadField> reading)?  $default,) {final _that = this;
switch (_that) {
case _McpViewState() when $default != null:
return $default(_that.configurationSource,_that.source,_that.drafts,_that.resets,_that.resetAllAction,_that.latestIntent,_that.readIssues,_that.reading);case _:
  return null;

}
}

}

/// @nodoc


class _McpViewState implements McpViewState {
  const _McpViewState({required this.configurationSource, required this.source,  Map<String, McpServerDraft> drafts = const {},  Map<String, SettingsAction> resets = const {}, this.resetAllAction, this.latestIntent = 0,  Map<McpReadField, StudioFailure> readIssues = const {},  Set<McpReadField> reading = const {}}): _drafts = drafts,_resets = resets,_readIssues = readIssues,_reading = reading;


@override final  ConfigurationState configurationSource;
@override final  McpState source;
 final  Map<String, McpServerDraft> _drafts;
@override@JsonKey() Map<String, McpServerDraft> get drafts {
  if (_drafts is EqualUnmodifiableMapView) return _drafts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_drafts);
}

 final  Map<String, SettingsAction> _resets;
@override@JsonKey() Map<String, SettingsAction> get resets {
  if (_resets is EqualUnmodifiableMapView) return _resets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_resets);
}

@override final  SettingsAction? resetAllAction;
@override@JsonKey() final  int latestIntent;
 final  Map<McpReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<McpReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}

 final  Set<McpReadField> _reading;
@override@JsonKey() Set<McpReadField> get reading {
  if (_reading is EqualUnmodifiableSetView) return _reading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_reading);
}


/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$McpViewStateCopyWith<_McpViewState> get copyWith => __$McpViewStateCopyWithImpl<_McpViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _McpViewState&&(identical(other.configurationSource, configurationSource) || other.configurationSource == configurationSource)&&(identical(other.source, source) || other.source == source)&&const DeepCollectionEquality().equals(other.drafts, _drafts)&&const DeepCollectionEquality().equals(other.resets, _resets)&&(identical(other.resetAllAction, resetAllAction) || other.resetAllAction == resetAllAction)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&const DeepCollectionEquality().equals(other.reading, _reading));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configurationSource,source,const DeepCollectionEquality().hash(_drafts),const DeepCollectionEquality().hash(_resets),resetAllAction,latestIntent,const DeepCollectionEquality().hash(_readIssues),const DeepCollectionEquality().hash(_reading));
}



}

/// @nodoc
abstract mixin class _$McpViewStateCopyWith<$Res> implements $McpViewStateCopyWith<$Res> {
  factory _$McpViewStateCopyWith(_McpViewState value, $Res Function(_McpViewState) _then) = __$McpViewStateCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationState configurationSource, McpState source, Map<String, McpServerDraft> drafts, Map<String, SettingsAction> resets, SettingsAction? resetAllAction, int latestIntent, Map<McpReadField, StudioFailure> readIssues, Set<McpReadField> reading
});


@override $ConfigurationStateCopyWith<$Res> get configurationSource;@override $McpStateCopyWith<$Res> get source;@override $SettingsActionCopyWith<$Res>? get resetAllAction;

}
/// @nodoc
class __$McpViewStateCopyWithImpl<$Res>
    implements _$McpViewStateCopyWith<$Res> {
  __$McpViewStateCopyWithImpl(this._self, this._then);

  final _McpViewState _self;
  final $Res Function(_McpViewState) _then;

/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configurationSource = null,Object? source = null,Object? drafts = null,Object? resets = null,Object? resetAllAction = freezed,Object? latestIntent = null,Object? readIssues = null,Object? reading = null,}) {
  return _then(_McpViewState(
configurationSource: null == configurationSource ? _self.configurationSource : configurationSource // ignore: cast_nullable_to_non_nullable
as ConfigurationState,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as McpState,drafts: null == drafts ? _self._drafts : drafts // ignore: cast_nullable_to_non_nullable
as Map<String, McpServerDraft>,resets: null == resets ? _self._resets : resets // ignore: cast_nullable_to_non_nullable
as Map<String, SettingsAction>,resetAllAction: freezed == resetAllAction ? _self.resetAllAction : resetAllAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<McpReadField, StudioFailure>,reading: null == reading ? _self._reading : reading // ignore: cast_nullable_to_non_nullable
as Set<McpReadField>,
  ));
}

/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationStateCopyWith<$Res> get configurationSource {

  return $ConfigurationStateCopyWith<$Res>(_self.configurationSource, (value) {
    return _then(_self.copyWith(configurationSource: value));
  });
}/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$McpStateCopyWith<$Res> get source {

  return $McpStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of McpViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get resetAllAction {
    if (_self.resetAllAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.resetAllAction!, (value) {
    return _then(_self.copyWith(resetAllAction: value));
  });
}
}

// dart format on
