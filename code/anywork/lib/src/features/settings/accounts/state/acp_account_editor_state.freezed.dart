// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_account_editor_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAccountEditorViewState {

 AcpAccountEditorTarget get target; String get name; AcpPreparationIntent get intent; AcpInstallState get install; int get draftRevision; bool get visible; int get latestIntent; SettingsAction? get prepareAction; SettingsAction? get cancelAction; StudioFailure? get observationError;
/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountEditorViewStateCopyWith<AcpAccountEditorViewState> get copyWith => _$AcpAccountEditorViewStateCopyWithImpl<AcpAccountEditorViewState>(this as AcpAccountEditorViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountEditorViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountEditorViewState&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.install, _this.install) || other.install == _this.install)&&(identical(other.draftRevision, _this.draftRevision) || other.draftRevision == _this.draftRevision)&&(identical(other.visible, _this.visible) || other.visible == _this.visible)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.prepareAction, _this.prepareAction) || other.prepareAction == _this.prepareAction)&&(identical(other.cancelAction, _this.cancelAction) || other.cancelAction == _this.cancelAction)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as AcpAccountEditorViewState;
  return Object.hash(runtimeType,_this.target,_this.name,_this.intent,_this.install,_this.draftRevision,_this.visible,_this.latestIntent,_this.prepareAction,_this.cancelAction,_this.observationError);
}



}

/// @nodoc
abstract mixin class $AcpAccountEditorViewStateCopyWith<$Res>  {
  factory $AcpAccountEditorViewStateCopyWith(AcpAccountEditorViewState value, $Res Function(AcpAccountEditorViewState) _then) = _$AcpAccountEditorViewStateCopyWithImpl;
@useResult
$Res call({
 AcpAccountEditorTarget target, String name, AcpPreparationIntent intent, AcpInstallState install, int draftRevision, bool visible, int latestIntent, SettingsAction? prepareAction, SettingsAction? cancelAction, StudioFailure? observationError
});


$AcpPreparationIntentCopyWith<$Res> get intent;$AcpInstallStateCopyWith<$Res> get install;$SettingsActionCopyWith<$Res>? get prepareAction;$SettingsActionCopyWith<$Res>? get cancelAction;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$AcpAccountEditorViewStateCopyWithImpl<$Res>
    implements $AcpAccountEditorViewStateCopyWith<$Res> {
  _$AcpAccountEditorViewStateCopyWithImpl(this._self, this._then);

  final AcpAccountEditorViewState _self;
  final $Res Function(AcpAccountEditorViewState) _then;

/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? name = null,Object? intent = null,Object? install = null,Object? draftRevision = null,Object? visible = null,Object? latestIntent = null,Object? prepareAction = freezed,Object? cancelAction = freezed,Object? observationError = freezed,}) {
  return _then(AcpAccountEditorViewState(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AcpAccountEditorTarget,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as AcpPreparationIntent,install: null == install ? _self.install : install // ignore: cast_nullable_to_non_nullable
as AcpInstallState,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,prepareAction: freezed == prepareAction ? _self.prepareAction : prepareAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,cancelAction: freezed == cancelAction ? _self.cancelAction : cancelAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpPreparationIntentCopyWith<$Res> get intent {

  return $AcpPreparationIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallStateCopyWith<$Res> get install {

  return $AcpInstallStateCopyWith<$Res>(_self.install, (value) {
    return _then(_self.copyWith(install: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get prepareAction {
    if (_self.prepareAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.prepareAction!, (value) {
    return _then(_self.copyWith(prepareAction: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get cancelAction {
    if (_self.cancelAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.cancelAction!, (value) {
    return _then(_self.copyWith(cancelAction: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAccountEditorViewState].
extension AcpAccountEditorViewStatePatterns on AcpAccountEditorViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountEditorViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountEditorViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountEditorViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountEditorViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountEditorViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountEditorViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpAccountEditorTarget target,  String name,  AcpPreparationIntent intent,  AcpInstallState install,  int draftRevision,  bool visible,  int latestIntent,  SettingsAction? prepareAction,  SettingsAction? cancelAction,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountEditorViewState() when $default != null:
return $default(_that.target,_that.name,_that.intent,_that.install,_that.draftRevision,_that.visible,_that.latestIntent,_that.prepareAction,_that.cancelAction,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpAccountEditorTarget target,  String name,  AcpPreparationIntent intent,  AcpInstallState install,  int draftRevision,  bool visible,  int latestIntent,  SettingsAction? prepareAction,  SettingsAction? cancelAction,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountEditorViewState():
return $default(_that.target,_that.name,_that.intent,_that.install,_that.draftRevision,_that.visible,_that.latestIntent,_that.prepareAction,_that.cancelAction,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpAccountEditorTarget target,  String name,  AcpPreparationIntent intent,  AcpInstallState install,  int draftRevision,  bool visible,  int latestIntent,  SettingsAction? prepareAction,  SettingsAction? cancelAction,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountEditorViewState() when $default != null:
return $default(_that.target,_that.name,_that.intent,_that.install,_that.draftRevision,_that.visible,_that.latestIntent,_that.prepareAction,_that.cancelAction,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountEditorViewState extends AcpAccountEditorViewState {
  const _AcpAccountEditorViewState({required this.target, required this.name, required this.intent, required this.install, this.draftRevision = 0, this.visible = false, this.latestIntent = 0, this.prepareAction, this.cancelAction, this.observationError}): super._();


@override final  AcpAccountEditorTarget target;
@override final  String name;
@override final  AcpPreparationIntent intent;
@override final  AcpInstallState install;
@override@JsonKey() final  int draftRevision;
@override@JsonKey() final  bool visible;
@override@JsonKey() final  int latestIntent;
@override final  SettingsAction? prepareAction;
@override final  SettingsAction? cancelAction;
@override final  StudioFailure? observationError;

/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountEditorViewStateCopyWith<_AcpAccountEditorViewState> get copyWith => __$AcpAccountEditorViewStateCopyWithImpl<_AcpAccountEditorViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountEditorViewState&&(identical(other.target, target) || other.target == target)&&(identical(other.name, name) || other.name == name)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.install, install) || other.install == install)&&(identical(other.draftRevision, draftRevision) || other.draftRevision == draftRevision)&&(identical(other.visible, visible) || other.visible == visible)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.prepareAction, prepareAction) || other.prepareAction == prepareAction)&&(identical(other.cancelAction, cancelAction) || other.cancelAction == cancelAction)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,name,intent,install,draftRevision,visible,latestIntent,prepareAction,cancelAction,observationError);
}



}

/// @nodoc
abstract mixin class _$AcpAccountEditorViewStateCopyWith<$Res> implements $AcpAccountEditorViewStateCopyWith<$Res> {
  factory _$AcpAccountEditorViewStateCopyWith(_AcpAccountEditorViewState value, $Res Function(_AcpAccountEditorViewState) _then) = __$AcpAccountEditorViewStateCopyWithImpl;
@override @useResult
$Res call({
 AcpAccountEditorTarget target, String name, AcpPreparationIntent intent, AcpInstallState install, int draftRevision, bool visible, int latestIntent, SettingsAction? prepareAction, SettingsAction? cancelAction, StudioFailure? observationError
});


@override $AcpPreparationIntentCopyWith<$Res> get intent;@override $AcpInstallStateCopyWith<$Res> get install;@override $SettingsActionCopyWith<$Res>? get prepareAction;@override $SettingsActionCopyWith<$Res>? get cancelAction;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$AcpAccountEditorViewStateCopyWithImpl<$Res>
    implements _$AcpAccountEditorViewStateCopyWith<$Res> {
  __$AcpAccountEditorViewStateCopyWithImpl(this._self, this._then);

  final _AcpAccountEditorViewState _self;
  final $Res Function(_AcpAccountEditorViewState) _then;

/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? name = null,Object? intent = null,Object? install = null,Object? draftRevision = null,Object? visible = null,Object? latestIntent = null,Object? prepareAction = freezed,Object? cancelAction = freezed,Object? observationError = freezed,}) {
  return _then(_AcpAccountEditorViewState(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AcpAccountEditorTarget,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as AcpPreparationIntent,install: null == install ? _self.install : install // ignore: cast_nullable_to_non_nullable
as AcpInstallState,draftRevision: null == draftRevision ? _self.draftRevision : draftRevision // ignore: cast_nullable_to_non_nullable
as int,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,prepareAction: freezed == prepareAction ? _self.prepareAction : prepareAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,cancelAction: freezed == cancelAction ? _self.cancelAction : cancelAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpPreparationIntentCopyWith<$Res> get intent {

  return $AcpPreparationIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallStateCopyWith<$Res> get install {

  return $AcpInstallStateCopyWith<$Res>(_self.install, (value) {
    return _then(_self.copyWith(install: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get prepareAction {
    if (_self.prepareAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.prepareAction!, (value) {
    return _then(_self.copyWith(prepareAction: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get cancelAction {
    if (_self.cancelAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.cancelAction!, (value) {
    return _then(_self.copyWith(cancelAction: value));
  });
}/// Create a copy of AcpAccountEditorViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}

// dart format on
