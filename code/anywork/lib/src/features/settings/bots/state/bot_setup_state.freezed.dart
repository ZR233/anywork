// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bot_setup_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotSetupKey {

 int get editorId; String? get botId;
/// Create a copy of BotSetupKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotSetupKeyCopyWith<BotSetupKey> get copyWith => _$BotSetupKeyCopyWithImpl<BotSetupKey>(this as BotSetupKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotSetupKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSetupKey&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId));
}


@override
int get hashCode {
  final _this = this as BotSetupKey;
  return Object.hash(runtimeType,_this.editorId,_this.botId);
}

@override
String toString() {
  final _this = this as BotSetupKey;
  return 'BotSetupKey(editorId: ${_this.editorId}, botId: ${_this.botId})';
}


}

/// @nodoc
abstract mixin class $BotSetupKeyCopyWith<$Res>  {
  factory $BotSetupKeyCopyWith(BotSetupKey value, $Res Function(BotSetupKey) _then) = _$BotSetupKeyCopyWithImpl;
@useResult
$Res call({
 int editorId, String? botId
});




}
/// @nodoc
class _$BotSetupKeyCopyWithImpl<$Res>
    implements $BotSetupKeyCopyWith<$Res> {
  _$BotSetupKeyCopyWithImpl(this._self, this._then);

  final BotSetupKey _self;
  final $Res Function(BotSetupKey) _then;

/// Create a copy of BotSetupKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorId = null,Object? botId = freezed,}) {
  return _then(BotSetupKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BotSetupKey].
extension BotSetupKeyPatterns on BotSetupKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotSetupKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotSetupKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotSetupKey value)  $default,){
final _that = this;
switch (_that) {
case _BotSetupKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotSetupKey value)?  $default,){
final _that = this;
switch (_that) {
case _BotSetupKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int editorId,  String? botId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotSetupKey() when $default != null:
return $default(_that.editorId,_that.botId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int editorId,  String? botId)  $default,) {final _that = this;
switch (_that) {
case _BotSetupKey():
return $default(_that.editorId,_that.botId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int editorId,  String? botId)?  $default,) {final _that = this;
switch (_that) {
case _BotSetupKey() when $default != null:
return $default(_that.editorId,_that.botId);case _:
  return null;

}
}

}

/// @nodoc


class _BotSetupKey implements BotSetupKey {
  const _BotSetupKey({required this.editorId, this.botId});


@override final  int editorId;
@override final  String? botId;

/// Create a copy of BotSetupKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotSetupKeyCopyWith<_BotSetupKey> get copyWith => __$BotSetupKeyCopyWithImpl<_BotSetupKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotSetupKey&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.botId, botId) || other.botId == botId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editorId,botId);
}

@override
String toString() {
    return 'BotSetupKey(editorId: $editorId, botId: $botId)';
}


}

/// @nodoc
abstract mixin class _$BotSetupKeyCopyWith<$Res> implements $BotSetupKeyCopyWith<$Res> {
  factory _$BotSetupKeyCopyWith(_BotSetupKey value, $Res Function(_BotSetupKey) _then) = __$BotSetupKeyCopyWithImpl;
@override @useResult
$Res call({
 int editorId, String? botId
});




}
/// @nodoc
class __$BotSetupKeyCopyWithImpl<$Res>
    implements _$BotSetupKeyCopyWith<$Res> {
  __$BotSetupKeyCopyWithImpl(this._self, this._then);

  final _BotSetupKey _self;
  final $Res Function(_BotSetupKey) _then;

/// Create a copy of BotSetupKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorId = null,Object? botId = freezed,}) {
  return _then(_BotSetupKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,botId: freezed == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BotSetupViewState {

 BotSetupKey get key; BotSetupMode get mode; BotsState get source; BotSnapshot? get canonical; String get name; String get appId; String get projectId; bool get canChangeAppId; bool get riskAcknowledged; bool get manualOpen; BotSecretIntent get secretIntent; int get draftRevision; Map<BotSetupField, BotSetupValidation> get validation; SettingsAction? get saveAction; StudioFailure? get sourceError;
/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotSetupViewStateCopyWith<BotSetupViewState> get copyWith => _$BotSetupViewStateCopyWithImpl<BotSetupViewState>(this as BotSetupViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotSetupViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSetupViewState&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.canonical, _this.canonical) || other.canonical == _this.canonical)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.appId, _this.appId) || other.appId == _this.appId)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.canChangeAppId, _this.canChangeAppId) || other.canChangeAppId == _this.canChangeAppId)&&(identical(other.riskAcknowledged, _this.riskAcknowledged) || other.riskAcknowledged == _this.riskAcknowledged)&&(identical(other.manualOpen, _this.manualOpen) || other.manualOpen == _this.manualOpen)&&(identical(other.secretIntent, _this.secretIntent) || other.secretIntent == _this.secretIntent)&&(identical(other.draftRevision, _this.draftRevision) || other.draftRevision == _this.draftRevision)&&const DeepCollectionEquality().equals(other.validation, _this.validation)&&(identical(other.saveAction, _this.saveAction) || other.saveAction == _this.saveAction)&&(identical(other.sourceError, _this.sourceError) || other.sourceError == _this.sourceError));
}


@override
int get hashCode {
  final _this = this as BotSetupViewState;
  return Object.hash(runtimeType,_this.key,_this.mode,_this.source,_this.canonical,_this.name,_this.appId,_this.projectId,_this.canChangeAppId,_this.riskAcknowledged,_this.manualOpen,_this.secretIntent,_this.draftRevision,const DeepCollectionEquality().hash(_this.validation),_this.saveAction,_this.sourceError);
}



}

/// @nodoc
abstract mixin class $BotSetupViewStateCopyWith<$Res>  {
  factory $BotSetupViewStateCopyWith(BotSetupViewState value, $Res Function(BotSetupViewState) _then) = _$BotSetupViewStateCopyWithImpl;
@useResult
$Res call({
 BotSetupKey key, BotSetupMode mode, BotsState source, BotSnapshot? canonical, String name, String appId, String projectId, bool canChangeAppId, bool riskAcknowledged, bool manualOpen, BotSecretIntent secretIntent, int draftRevision, Map<BotSetupField, BotSetupValidation> validation, SettingsAction? saveAction, StudioFailure? sourceError
});


$BotSetupKeyCopyWith<$Res> get key;$BotsStateCopyWith<$Res> get source;$BotSnapshotCopyWith<$Res>? get canonical;$SettingsActionCopyWith<$Res>? get saveAction;$StudioFailureCopyWith<$Res>? get sourceError;

}
/// @nodoc
class _$BotSetupViewStateCopyWithImpl<$Res>
    implements $BotSetupViewStateCopyWith<$Res> {
  _$BotSetupViewStateCopyWithImpl(this._self, this._then);

  final BotSetupViewState _self;
  final $Res Function(BotSetupViewState) _then;

/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? mode = null,Object? source = null,Object? canonical = freezed,Object? name = null,Object? appId = null,Object? projectId = null,Object? canChangeAppId = null,Object? riskAcknowledged = null,Object? manualOpen = null,Object? secretIntent = null,Object? draftRevision = null,Object? validation = null,Object? saveAction = freezed,Object? sourceError = freezed,}) {
  return _then(BotSetupViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as BotSetupKey,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as BotSetupMode,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as BotsState,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as BotSnapshot?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,appId: null == appId ? _self.appId : appId // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,canChangeAppId: null == canChangeAppId ? _self.canChangeAppId : canChangeAppId // ignore: cast_nullable_to_non_nullable
as bool,riskAcknowledged: null == riskAcknowledged ? _self.riskAcknowledged : riskAcknowledged // ignore: cast_nullable_to_non_nullable
as bool,manualOpen: null == manualOpen ? _self.manualOpen : manualOpen // ignore: cast_nullable_to_non_nullable
as bool,secretIntent: null == secretIntent ? _self.secretIntent : secretIntent // ignore: cast_nullable_to_non_nullable
as BotSecretIntent,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,validation: null == validation ? _self.validation : validation // ignore: cast_nullable_to_non_nullable
as Map<BotSetupField, BotSetupValidation>,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,sourceError: freezed == sourceError ? _self.sourceError : sourceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSetupKeyCopyWith<$Res> get key {

  return $BotSetupKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsStateCopyWith<$Res> get source {

  return $BotsStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSnapshotCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $BotSnapshotCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get saveAction {
    if (_self.saveAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.saveAction!, (value) {
    return _then(_self.copyWith(saveAction: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get sourceError {
    if (_self.sourceError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.sourceError!, (value) {
    return _then(_self.copyWith(sourceError: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotSetupViewState].
extension BotSetupViewStatePatterns on BotSetupViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotSetupViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotSetupViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotSetupViewState value)  $default,){
final _that = this;
switch (_that) {
case _BotSetupViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotSetupViewState value)?  $default,){
final _that = this;
switch (_that) {
case _BotSetupViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( BotSetupKey key,  BotSetupMode mode,  BotsState source,  BotSnapshot? canonical,  String name,  String appId,  String projectId,  bool canChangeAppId,  bool riskAcknowledged,  bool manualOpen,  BotSecretIntent secretIntent,  int draftRevision,  Map<BotSetupField, BotSetupValidation> validation,  SettingsAction? saveAction,  StudioFailure? sourceError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotSetupViewState() when $default != null:
return $default(_that.key,_that.mode,_that.source,_that.canonical,_that.name,_that.appId,_that.projectId,_that.canChangeAppId,_that.riskAcknowledged,_that.manualOpen,_that.secretIntent,_that.draftRevision,_that.validation,_that.saveAction,_that.sourceError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( BotSetupKey key,  BotSetupMode mode,  BotsState source,  BotSnapshot? canonical,  String name,  String appId,  String projectId,  bool canChangeAppId,  bool riskAcknowledged,  bool manualOpen,  BotSecretIntent secretIntent,  int draftRevision,  Map<BotSetupField, BotSetupValidation> validation,  SettingsAction? saveAction,  StudioFailure? sourceError)  $default,) {final _that = this;
switch (_that) {
case _BotSetupViewState():
return $default(_that.key,_that.mode,_that.source,_that.canonical,_that.name,_that.appId,_that.projectId,_that.canChangeAppId,_that.riskAcknowledged,_that.manualOpen,_that.secretIntent,_that.draftRevision,_that.validation,_that.saveAction,_that.sourceError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( BotSetupKey key,  BotSetupMode mode,  BotsState source,  BotSnapshot? canonical,  String name,  String appId,  String projectId,  bool canChangeAppId,  bool riskAcknowledged,  bool manualOpen,  BotSecretIntent secretIntent,  int draftRevision,  Map<BotSetupField, BotSetupValidation> validation,  SettingsAction? saveAction,  StudioFailure? sourceError)?  $default,) {final _that = this;
switch (_that) {
case _BotSetupViewState() when $default != null:
return $default(_that.key,_that.mode,_that.source,_that.canonical,_that.name,_that.appId,_that.projectId,_that.canChangeAppId,_that.riskAcknowledged,_that.manualOpen,_that.secretIntent,_that.draftRevision,_that.validation,_that.saveAction,_that.sourceError);case _:
  return null;

}
}

}

/// @nodoc


class _BotSetupViewState extends BotSetupViewState {
  const _BotSetupViewState({required this.key, required this.mode, required this.source, this.canonical, this.name = '', this.appId = '', this.projectId = '', this.canChangeAppId = false, this.riskAcknowledged = false, this.manualOpen = false, this.secretIntent = BotSecretIntent.preserve, this.draftRevision = 0,  Map<BotSetupField, BotSetupValidation> validation = const {}, this.saveAction, this.sourceError}): _validation = validation,super._();


@override final  BotSetupKey key;
@override final  BotSetupMode mode;
@override final  BotsState source;
@override final  BotSnapshot? canonical;
@override@JsonKey() final  String name;
@override@JsonKey() final  String appId;
@override@JsonKey() final  String projectId;
@override@JsonKey() final  bool canChangeAppId;
@override@JsonKey() final  bool riskAcknowledged;
@override@JsonKey() final  bool manualOpen;
@override@JsonKey() final  BotSecretIntent secretIntent;
@override@JsonKey() final  int draftRevision;
 final  Map<BotSetupField, BotSetupValidation> _validation;
@override@JsonKey() Map<BotSetupField, BotSetupValidation> get validation {
  if (_validation is EqualUnmodifiableMapView) return _validation;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_validation);
}

@override final  SettingsAction? saveAction;
@override final  StudioFailure? sourceError;

/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotSetupViewStateCopyWith<_BotSetupViewState> get copyWith => __$BotSetupViewStateCopyWithImpl<_BotSetupViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotSetupViewState&&(identical(other.key, key) || other.key == key)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.source, source) || other.source == source)&&(identical(other.canonical, canonical) || other.canonical == canonical)&&(identical(other.name, name) || other.name == name)&&(identical(other.appId, appId) || other.appId == appId)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.canChangeAppId, canChangeAppId) || other.canChangeAppId == canChangeAppId)&&(identical(other.riskAcknowledged, riskAcknowledged) || other.riskAcknowledged == riskAcknowledged)&&(identical(other.manualOpen, manualOpen) || other.manualOpen == manualOpen)&&(identical(other.secretIntent, secretIntent) || other.secretIntent == secretIntent)&&(identical(other.draftRevision, draftRevision) || other.draftRevision == draftRevision)&&const DeepCollectionEquality().equals(other.validation, _validation)&&(identical(other.saveAction, saveAction) || other.saveAction == saveAction)&&(identical(other.sourceError, sourceError) || other.sourceError == sourceError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,mode,source,canonical,name,appId,projectId,canChangeAppId,riskAcknowledged,manualOpen,secretIntent,draftRevision,const DeepCollectionEquality().hash(_validation),saveAction,sourceError);
}



}

/// @nodoc
abstract mixin class _$BotSetupViewStateCopyWith<$Res> implements $BotSetupViewStateCopyWith<$Res> {
  factory _$BotSetupViewStateCopyWith(_BotSetupViewState value, $Res Function(_BotSetupViewState) _then) = __$BotSetupViewStateCopyWithImpl;
@override @useResult
$Res call({
 BotSetupKey key, BotSetupMode mode, BotsState source, BotSnapshot? canonical, String name, String appId, String projectId, bool canChangeAppId, bool riskAcknowledged, bool manualOpen, BotSecretIntent secretIntent, int draftRevision, Map<BotSetupField, BotSetupValidation> validation, SettingsAction? saveAction, StudioFailure? sourceError
});


@override $BotSetupKeyCopyWith<$Res> get key;@override $BotsStateCopyWith<$Res> get source;@override $BotSnapshotCopyWith<$Res>? get canonical;@override $SettingsActionCopyWith<$Res>? get saveAction;@override $StudioFailureCopyWith<$Res>? get sourceError;

}
/// @nodoc
class __$BotSetupViewStateCopyWithImpl<$Res>
    implements _$BotSetupViewStateCopyWith<$Res> {
  __$BotSetupViewStateCopyWithImpl(this._self, this._then);

  final _BotSetupViewState _self;
  final $Res Function(_BotSetupViewState) _then;

/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? mode = null,Object? source = null,Object? canonical = freezed,Object? name = null,Object? appId = null,Object? projectId = null,Object? canChangeAppId = null,Object? riskAcknowledged = null,Object? manualOpen = null,Object? secretIntent = null,Object? draftRevision = null,Object? validation = null,Object? saveAction = freezed,Object? sourceError = freezed,}) {
  return _then(_BotSetupViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as BotSetupKey,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as BotSetupMode,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as BotsState,canonical: freezed == canonical ? _self.canonical : canonical // ignore: cast_nullable_to_non_nullable
as BotSnapshot?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,appId: null == appId ? _self.appId : appId // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,canChangeAppId: null == canChangeAppId ? _self.canChangeAppId : canChangeAppId // ignore: cast_nullable_to_non_nullable
as bool,riskAcknowledged: null == riskAcknowledged ? _self.riskAcknowledged : riskAcknowledged // ignore: cast_nullable_to_non_nullable
as bool,manualOpen: null == manualOpen ? _self.manualOpen : manualOpen // ignore: cast_nullable_to_non_nullable
as bool,secretIntent: null == secretIntent ? _self.secretIntent : secretIntent // ignore: cast_nullable_to_non_nullable
as BotSecretIntent,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,validation: null == validation ? _self._validation : validation // ignore: cast_nullable_to_non_nullable
as Map<BotSetupField, BotSetupValidation>,saveAction: freezed == saveAction ? _self.saveAction : saveAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,sourceError: freezed == sourceError ? _self.sourceError : sourceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSetupKeyCopyWith<$Res> get key {

  return $BotSetupKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsStateCopyWith<$Res> get source {

  return $BotsStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotSnapshotCopyWith<$Res>? get canonical {
    if (_self.canonical == null) {
    return null;
  }

  return $BotSnapshotCopyWith<$Res>(_self.canonical!, (value) {
    return _then(_self.copyWith(canonical: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get saveAction {
    if (_self.saveAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.saveAction!, (value) {
    return _then(_self.copyWith(saveAction: value));
  });
}/// Create a copy of BotSetupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get sourceError {
    if (_self.sourceError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.sourceError!, (value) {
    return _then(_self.copyWith(sourceError: value));
  });
}
}

// dart format on
