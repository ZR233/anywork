// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'updates_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdateRestartRequest {

 int get intent; String get version;
/// Create a copy of UpdateRestartRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateRestartRequestCopyWith<UpdateRestartRequest> get copyWith => _$UpdateRestartRequestCopyWithImpl<UpdateRestartRequest>(this as UpdateRestartRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateRestartRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateRestartRequest&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.version, _this.version) || other.version == _this.version));
}


@override
int get hashCode {
  final _this = this as UpdateRestartRequest;
  return Object.hash(runtimeType,_this.intent,_this.version);
}

@override
String toString() {
  final _this = this as UpdateRestartRequest;
  return 'UpdateRestartRequest(intent: ${_this.intent}, version: ${_this.version})';
}


}

/// @nodoc
abstract mixin class $UpdateRestartRequestCopyWith<$Res>  {
  factory $UpdateRestartRequestCopyWith(UpdateRestartRequest value, $Res Function(UpdateRestartRequest) _then) = _$UpdateRestartRequestCopyWithImpl;
@useResult
$Res call({
 int intent, String version
});




}
/// @nodoc
class _$UpdateRestartRequestCopyWithImpl<$Res>
    implements $UpdateRestartRequestCopyWith<$Res> {
  _$UpdateRestartRequestCopyWithImpl(this._self, this._then);

  final UpdateRestartRequest _self;
  final $Res Function(UpdateRestartRequest) _then;

/// Create a copy of UpdateRestartRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? version = null,}) {
  return _then(UpdateRestartRequest(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdateRestartRequest].
extension UpdateRestartRequestPatterns on UpdateRestartRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateRestartRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateRestartRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateRestartRequest value)  $default,){
final _that = this;
switch (_that) {
case _UpdateRestartRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateRestartRequest value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateRestartRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int intent,  String version)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateRestartRequest() when $default != null:
return $default(_that.intent,_that.version);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int intent,  String version)  $default,) {final _that = this;
switch (_that) {
case _UpdateRestartRequest():
return $default(_that.intent,_that.version);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int intent,  String version)?  $default,) {final _that = this;
switch (_that) {
case _UpdateRestartRequest() when $default != null:
return $default(_that.intent,_that.version);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateRestartRequest implements UpdateRestartRequest {
  const _UpdateRestartRequest({required this.intent, required this.version});


@override final  int intent;
@override final  String version;

/// Create a copy of UpdateRestartRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateRestartRequestCopyWith<_UpdateRestartRequest> get copyWith => __$UpdateRestartRequestCopyWithImpl<_UpdateRestartRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateRestartRequest&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,version);
}

@override
String toString() {
    return 'UpdateRestartRequest(intent: $intent, version: $version)';
}


}

/// @nodoc
abstract mixin class _$UpdateRestartRequestCopyWith<$Res> implements $UpdateRestartRequestCopyWith<$Res> {
  factory _$UpdateRestartRequestCopyWith(_UpdateRestartRequest value, $Res Function(_UpdateRestartRequest) _then) = __$UpdateRestartRequestCopyWithImpl;
@override @useResult
$Res call({
 int intent, String version
});




}
/// @nodoc
class __$UpdateRestartRequestCopyWithImpl<$Res>
    implements _$UpdateRestartRequestCopyWith<$Res> {
  __$UpdateRestartRequestCopyWithImpl(this._self, this._then);

  final _UpdateRestartRequest _self;
  final $Res Function(_UpdateRestartRequest) _then;

/// Create a copy of UpdateRestartRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? version = null,}) {
  return _then(_UpdateRestartRequest(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$UpdatesViewState {

 UpdatesState get source; UpdateControls get controls; String get currentVersion; UpdateSummary? get summary; ProductReadOrigin? get summaryOrigin; UpdateSummaryReadRef? get summaryReference; bool get readingSummary; bool get readingValue; int get latestIntent; int? get consumedRestartIntent; Map<UpdateSettingsAction, SettingsAction> get actions; Map<UpdatesReadField, StudioFailure> get readIssues;
/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesViewStateCopyWith<UpdatesViewState> get copyWith => _$UpdatesViewStateCopyWithImpl<UpdatesViewState>(this as UpdatesViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesViewState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.controls, _this.controls) || other.controls == _this.controls)&&(identical(other.currentVersion, _this.currentVersion) || other.currentVersion == _this.currentVersion)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.summaryOrigin, _this.summaryOrigin) || other.summaryOrigin == _this.summaryOrigin)&&(identical(other.summaryReference, _this.summaryReference) || other.summaryReference == _this.summaryReference)&&(identical(other.readingSummary, _this.readingSummary) || other.readingSummary == _this.readingSummary)&&(identical(other.readingValue, _this.readingValue) || other.readingValue == _this.readingValue)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.consumedRestartIntent, _this.consumedRestartIntent) || other.consumedRestartIntent == _this.consumedRestartIntent)&&const DeepCollectionEquality().equals(other.actions, _this.actions)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues));
}


@override
int get hashCode {
  final _this = this as UpdatesViewState;
  return Object.hash(runtimeType,_this.source,_this.controls,_this.currentVersion,_this.summary,_this.summaryOrigin,_this.summaryReference,_this.readingSummary,_this.readingValue,_this.latestIntent,_this.consumedRestartIntent,const DeepCollectionEquality().hash(_this.actions),const DeepCollectionEquality().hash(_this.readIssues));
}



}

/// @nodoc
abstract mixin class $UpdatesViewStateCopyWith<$Res>  {
  factory $UpdatesViewStateCopyWith(UpdatesViewState value, $Res Function(UpdatesViewState) _then) = _$UpdatesViewStateCopyWithImpl;
@useResult
$Res call({
 UpdatesState source, UpdateControls controls, String currentVersion, UpdateSummary? summary, ProductReadOrigin? summaryOrigin, UpdateSummaryReadRef? summaryReference, bool readingSummary, bool readingValue, int latestIntent, int? consumedRestartIntent, Map<UpdateSettingsAction, SettingsAction> actions, Map<UpdatesReadField, StudioFailure> readIssues
});


$UpdatesStateCopyWith<$Res> get source;$UpdateControlsCopyWith<$Res> get controls;$UpdateSummaryCopyWith<$Res>? get summary;$ProductReadOriginCopyWith<$Res>? get summaryOrigin;$UpdateSummaryReadRefCopyWith<$Res>? get summaryReference;

}
/// @nodoc
class _$UpdatesViewStateCopyWithImpl<$Res>
    implements $UpdatesViewStateCopyWith<$Res> {
  _$UpdatesViewStateCopyWithImpl(this._self, this._then);

  final UpdatesViewState _self;
  final $Res Function(UpdatesViewState) _then;

/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? controls = null,Object? currentVersion = null,Object? summary = freezed,Object? summaryOrigin = freezed,Object? summaryReference = freezed,Object? readingSummary = null,Object? readingValue = null,Object? latestIntent = null,Object? consumedRestartIntent = freezed,Object? actions = null,Object? readIssues = null,}) {
  return _then(UpdatesViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as UpdatesState,controls: null == controls ? _self.controls : controls // ignore: cast_nullable_to_non_nullable
as UpdateControls,currentVersion: null == currentVersion ? _self.currentVersion : currentVersion // ignore: cast_nullable_to_non_nullable
as String,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummary?,summaryOrigin: freezed == summaryOrigin ? _self.summaryOrigin : summaryOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin?,summaryReference: freezed == summaryReference ? _self.summaryReference : summaryReference // ignore: cast_nullable_to_non_nullable
as UpdateSummaryReadRef?,readingSummary: null == readingSummary ? _self.readingSummary : readingSummary // ignore: cast_nullable_to_non_nullable
as bool,readingValue: null == readingValue ? _self.readingValue : readingValue // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,consumedRestartIntent: freezed == consumedRestartIntent ? _self.consumedRestartIntent : consumedRestartIntent // ignore: cast_nullable_to_non_nullable
as int?,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as Map<UpdateSettingsAction, SettingsAction>,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<UpdatesReadField, StudioFailure>,
  ));
}
/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesStateCopyWith<$Res> get source {

  return $UpdatesStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateControlsCopyWith<$Res> get controls {

  return $UpdateControlsCopyWith<$Res>(_self.controls, (value) {
    return _then(_self.copyWith(controls: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $UpdateSummaryCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res>? get summaryOrigin {
    if (_self.summaryOrigin == null) {
    return null;
  }

  return $ProductReadOriginCopyWith<$Res>(_self.summaryOrigin!, (value) {
    return _then(_self.copyWith(summaryOrigin: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryReadRefCopyWith<$Res>? get summaryReference {
    if (_self.summaryReference == null) {
    return null;
  }

  return $UpdateSummaryReadRefCopyWith<$Res>(_self.summaryReference!, (value) {
    return _then(_self.copyWith(summaryReference: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdatesViewState].
extension UpdatesViewStatePatterns on UpdatesViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdatesViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdatesViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdatesViewState value)  $default,){
final _that = this;
switch (_that) {
case _UpdatesViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdatesViewState value)?  $default,){
final _that = this;
switch (_that) {
case _UpdatesViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( UpdatesState source,  UpdateControls controls,  String currentVersion,  UpdateSummary? summary,  ProductReadOrigin? summaryOrigin,  UpdateSummaryReadRef? summaryReference,  bool readingSummary,  bool readingValue,  int latestIntent,  int? consumedRestartIntent,  Map<UpdateSettingsAction, SettingsAction> actions,  Map<UpdatesReadField, StudioFailure> readIssues)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdatesViewState() when $default != null:
return $default(_that.source,_that.controls,_that.currentVersion,_that.summary,_that.summaryOrigin,_that.summaryReference,_that.readingSummary,_that.readingValue,_that.latestIntent,_that.consumedRestartIntent,_that.actions,_that.readIssues);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( UpdatesState source,  UpdateControls controls,  String currentVersion,  UpdateSummary? summary,  ProductReadOrigin? summaryOrigin,  UpdateSummaryReadRef? summaryReference,  bool readingSummary,  bool readingValue,  int latestIntent,  int? consumedRestartIntent,  Map<UpdateSettingsAction, SettingsAction> actions,  Map<UpdatesReadField, StudioFailure> readIssues)  $default,) {final _that = this;
switch (_that) {
case _UpdatesViewState():
return $default(_that.source,_that.controls,_that.currentVersion,_that.summary,_that.summaryOrigin,_that.summaryReference,_that.readingSummary,_that.readingValue,_that.latestIntent,_that.consumedRestartIntent,_that.actions,_that.readIssues);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( UpdatesState source,  UpdateControls controls,  String currentVersion,  UpdateSummary? summary,  ProductReadOrigin? summaryOrigin,  UpdateSummaryReadRef? summaryReference,  bool readingSummary,  bool readingValue,  int latestIntent,  int? consumedRestartIntent,  Map<UpdateSettingsAction, SettingsAction> actions,  Map<UpdatesReadField, StudioFailure> readIssues)?  $default,) {final _that = this;
switch (_that) {
case _UpdatesViewState() when $default != null:
return $default(_that.source,_that.controls,_that.currentVersion,_that.summary,_that.summaryOrigin,_that.summaryReference,_that.readingSummary,_that.readingValue,_that.latestIntent,_that.consumedRestartIntent,_that.actions,_that.readIssues);case _:
  return null;

}
}

}

/// @nodoc


class _UpdatesViewState extends UpdatesViewState {
  const _UpdatesViewState({required this.source, required this.controls, required this.currentVersion, this.summary, this.summaryOrigin, this.summaryReference, this.readingSummary = false, this.readingValue = false, this.latestIntent = 0, this.consumedRestartIntent,  Map<UpdateSettingsAction, SettingsAction> actions = const {},  Map<UpdatesReadField, StudioFailure> readIssues = const {}}): _actions = actions,_readIssues = readIssues,super._();


@override final  UpdatesState source;
@override final  UpdateControls controls;
@override final  String currentVersion;
@override final  UpdateSummary? summary;
@override final  ProductReadOrigin? summaryOrigin;
@override final  UpdateSummaryReadRef? summaryReference;
@override@JsonKey() final  bool readingSummary;
@override@JsonKey() final  bool readingValue;
@override@JsonKey() final  int latestIntent;
@override final  int? consumedRestartIntent;
 final  Map<UpdateSettingsAction, SettingsAction> _actions;
@override@JsonKey() Map<UpdateSettingsAction, SettingsAction> get actions {
  if (_actions is EqualUnmodifiableMapView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_actions);
}

 final  Map<UpdatesReadField, StudioFailure> _readIssues;
@override@JsonKey() Map<UpdatesReadField, StudioFailure> get readIssues {
  if (_readIssues is EqualUnmodifiableMapView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_readIssues);
}


/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatesViewStateCopyWith<_UpdatesViewState> get copyWith => __$UpdatesViewStateCopyWithImpl<_UpdatesViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatesViewState&&(identical(other.source, source) || other.source == source)&&(identical(other.controls, controls) || other.controls == controls)&&(identical(other.currentVersion, currentVersion) || other.currentVersion == currentVersion)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.summaryOrigin, summaryOrigin) || other.summaryOrigin == summaryOrigin)&&(identical(other.summaryReference, summaryReference) || other.summaryReference == summaryReference)&&(identical(other.readingSummary, readingSummary) || other.readingSummary == readingSummary)&&(identical(other.readingValue, readingValue) || other.readingValue == readingValue)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.consumedRestartIntent, consumedRestartIntent) || other.consumedRestartIntent == consumedRestartIntent)&&const DeepCollectionEquality().equals(other.actions, _actions)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,controls,currentVersion,summary,summaryOrigin,summaryReference,readingSummary,readingValue,latestIntent,consumedRestartIntent,const DeepCollectionEquality().hash(_actions),const DeepCollectionEquality().hash(_readIssues));
}



}

/// @nodoc
abstract mixin class _$UpdatesViewStateCopyWith<$Res> implements $UpdatesViewStateCopyWith<$Res> {
  factory _$UpdatesViewStateCopyWith(_UpdatesViewState value, $Res Function(_UpdatesViewState) _then) = __$UpdatesViewStateCopyWithImpl;
@override @useResult
$Res call({
 UpdatesState source, UpdateControls controls, String currentVersion, UpdateSummary? summary, ProductReadOrigin? summaryOrigin, UpdateSummaryReadRef? summaryReference, bool readingSummary, bool readingValue, int latestIntent, int? consumedRestartIntent, Map<UpdateSettingsAction, SettingsAction> actions, Map<UpdatesReadField, StudioFailure> readIssues
});


@override $UpdatesStateCopyWith<$Res> get source;@override $UpdateControlsCopyWith<$Res> get controls;@override $UpdateSummaryCopyWith<$Res>? get summary;@override $ProductReadOriginCopyWith<$Res>? get summaryOrigin;@override $UpdateSummaryReadRefCopyWith<$Res>? get summaryReference;

}
/// @nodoc
class __$UpdatesViewStateCopyWithImpl<$Res>
    implements _$UpdatesViewStateCopyWith<$Res> {
  __$UpdatesViewStateCopyWithImpl(this._self, this._then);

  final _UpdatesViewState _self;
  final $Res Function(_UpdatesViewState) _then;

/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? controls = null,Object? currentVersion = null,Object? summary = freezed,Object? summaryOrigin = freezed,Object? summaryReference = freezed,Object? readingSummary = null,Object? readingValue = null,Object? latestIntent = null,Object? consumedRestartIntent = freezed,Object? actions = null,Object? readIssues = null,}) {
  return _then(_UpdatesViewState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as UpdatesState,controls: null == controls ? _self.controls : controls // ignore: cast_nullable_to_non_nullable
as UpdateControls,currentVersion: null == currentVersion ? _self.currentVersion : currentVersion // ignore: cast_nullable_to_non_nullable
as String,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummary?,summaryOrigin: freezed == summaryOrigin ? _self.summaryOrigin : summaryOrigin // ignore: cast_nullable_to_non_nullable
as ProductReadOrigin?,summaryReference: freezed == summaryReference ? _self.summaryReference : summaryReference // ignore: cast_nullable_to_non_nullable
as UpdateSummaryReadRef?,readingSummary: null == readingSummary ? _self.readingSummary : readingSummary // ignore: cast_nullable_to_non_nullable
as bool,readingValue: null == readingValue ? _self.readingValue : readingValue // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,consumedRestartIntent: freezed == consumedRestartIntent ? _self.consumedRestartIntent : consumedRestartIntent // ignore: cast_nullable_to_non_nullable
as int?,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as Map<UpdateSettingsAction, SettingsAction>,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as Map<UpdatesReadField, StudioFailure>,
  ));
}

/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdatesStateCopyWith<$Res> get source {

  return $UpdatesStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateControlsCopyWith<$Res> get controls {

  return $UpdateControlsCopyWith<$Res>(_self.controls, (value) {
    return _then(_self.copyWith(controls: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $UpdateSummaryCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductReadOriginCopyWith<$Res>? get summaryOrigin {
    if (_self.summaryOrigin == null) {
    return null;
  }

  return $ProductReadOriginCopyWith<$Res>(_self.summaryOrigin!, (value) {
    return _then(_self.copyWith(summaryOrigin: value));
  });
}/// Create a copy of UpdatesViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryReadRefCopyWith<$Res>? get summaryReference {
    if (_self.summaryReference == null) {
    return null;
  }

  return $UpdateSummaryReadRefCopyWith<$Res>(_self.summaryReference!, (value) {
    return _then(_self.copyWith(summaryReference: value));
  });
}
}

// dart format on
