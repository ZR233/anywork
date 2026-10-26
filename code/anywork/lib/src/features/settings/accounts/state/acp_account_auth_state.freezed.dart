// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_account_auth_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAccountAuthViewState {

 AcpAccountTarget get target; AcpAuthState get auth; bool get visible; int get latestIntent; SettingsAction? get checkAction; SettingsAction? get cancelAction; AcpCommandNotice? get notice; StudioFailure? get observationError;
/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountAuthViewStateCopyWith<AcpAccountAuthViewState> get copyWith => _$AcpAccountAuthViewStateCopyWithImpl<AcpAccountAuthViewState>(this as AcpAccountAuthViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountAuthViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountAuthViewState&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.auth, _this.auth) || other.auth == _this.auth)&&(identical(other.visible, _this.visible) || other.visible == _this.visible)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.checkAction, _this.checkAction) || other.checkAction == _this.checkAction)&&(identical(other.cancelAction, _this.cancelAction) || other.cancelAction == _this.cancelAction)&&(identical(other.notice, _this.notice) || other.notice == _this.notice)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as AcpAccountAuthViewState;
  return Object.hash(runtimeType,_this.target,_this.auth,_this.visible,_this.latestIntent,_this.checkAction,_this.cancelAction,_this.notice,_this.observationError);
}



}

/// @nodoc
abstract mixin class $AcpAccountAuthViewStateCopyWith<$Res>  {
  factory $AcpAccountAuthViewStateCopyWith(AcpAccountAuthViewState value, $Res Function(AcpAccountAuthViewState) _then) = _$AcpAccountAuthViewStateCopyWithImpl;
@useResult
$Res call({
 AcpAccountTarget target, AcpAuthState auth, bool visible, int latestIntent, SettingsAction? checkAction, SettingsAction? cancelAction, AcpCommandNotice? notice, StudioFailure? observationError
});


$AcpAuthStateCopyWith<$Res> get auth;$SettingsActionCopyWith<$Res>? get checkAction;$SettingsActionCopyWith<$Res>? get cancelAction;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$AcpAccountAuthViewStateCopyWithImpl<$Res>
    implements $AcpAccountAuthViewStateCopyWith<$Res> {
  _$AcpAccountAuthViewStateCopyWithImpl(this._self, this._then);

  final AcpAccountAuthViewState _self;
  final $Res Function(AcpAccountAuthViewState) _then;

/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? target = null,Object? auth = null,Object? visible = null,Object? latestIntent = null,Object? checkAction = freezed,Object? cancelAction = freezed,Object? notice = freezed,Object? observationError = freezed,}) {
  return _then(AcpAccountAuthViewState(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AcpAccountTarget,auth: null == auth ? _self.auth : auth // ignore: cast_nullable_to_non_nullable
as AcpAuthState,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,checkAction: freezed == checkAction ? _self.checkAction : checkAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,cancelAction: freezed == cancelAction ? _self.cancelAction : cancelAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as AcpCommandNotice?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthStateCopyWith<$Res> get auth {

  return $AcpAuthStateCopyWith<$Res>(_self.auth, (value) {
    return _then(_self.copyWith(auth: value));
  });
}/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get checkAction {
    if (_self.checkAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.checkAction!, (value) {
    return _then(_self.copyWith(checkAction: value));
  });
}/// Create a copy of AcpAccountAuthViewState
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
}/// Create a copy of AcpAccountAuthViewState
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


/// Adds pattern-matching-related methods to [AcpAccountAuthViewState].
extension AcpAccountAuthViewStatePatterns on AcpAccountAuthViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountAuthViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountAuthViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountAuthViewState value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountAuthViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountAuthViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountAuthViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpAccountTarget target,  AcpAuthState auth,  bool visible,  int latestIntent,  SettingsAction? checkAction,  SettingsAction? cancelAction,  AcpCommandNotice? notice,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountAuthViewState() when $default != null:
return $default(_that.target,_that.auth,_that.visible,_that.latestIntent,_that.checkAction,_that.cancelAction,_that.notice,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpAccountTarget target,  AcpAuthState auth,  bool visible,  int latestIntent,  SettingsAction? checkAction,  SettingsAction? cancelAction,  AcpCommandNotice? notice,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountAuthViewState():
return $default(_that.target,_that.auth,_that.visible,_that.latestIntent,_that.checkAction,_that.cancelAction,_that.notice,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpAccountTarget target,  AcpAuthState auth,  bool visible,  int latestIntent,  SettingsAction? checkAction,  SettingsAction? cancelAction,  AcpCommandNotice? notice,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountAuthViewState() when $default != null:
return $default(_that.target,_that.auth,_that.visible,_that.latestIntent,_that.checkAction,_that.cancelAction,_that.notice,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountAuthViewState extends AcpAccountAuthViewState {
  const _AcpAccountAuthViewState({required this.target, required this.auth, this.visible = false, this.latestIntent = 0, this.checkAction, this.cancelAction, this.notice, this.observationError}): super._();


@override final  AcpAccountTarget target;
@override final  AcpAuthState auth;
@override@JsonKey() final  bool visible;
@override@JsonKey() final  int latestIntent;
@override final  SettingsAction? checkAction;
@override final  SettingsAction? cancelAction;
@override final  AcpCommandNotice? notice;
@override final  StudioFailure? observationError;

/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountAuthViewStateCopyWith<_AcpAccountAuthViewState> get copyWith => __$AcpAccountAuthViewStateCopyWithImpl<_AcpAccountAuthViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountAuthViewState&&(identical(other.target, target) || other.target == target)&&(identical(other.auth, auth) || other.auth == auth)&&(identical(other.visible, visible) || other.visible == visible)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.checkAction, checkAction) || other.checkAction == checkAction)&&(identical(other.cancelAction, cancelAction) || other.cancelAction == cancelAction)&&(identical(other.notice, notice) || other.notice == notice)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target,auth,visible,latestIntent,checkAction,cancelAction,notice,observationError);
}



}

/// @nodoc
abstract mixin class _$AcpAccountAuthViewStateCopyWith<$Res> implements $AcpAccountAuthViewStateCopyWith<$Res> {
  factory _$AcpAccountAuthViewStateCopyWith(_AcpAccountAuthViewState value, $Res Function(_AcpAccountAuthViewState) _then) = __$AcpAccountAuthViewStateCopyWithImpl;
@override @useResult
$Res call({
 AcpAccountTarget target, AcpAuthState auth, bool visible, int latestIntent, SettingsAction? checkAction, SettingsAction? cancelAction, AcpCommandNotice? notice, StudioFailure? observationError
});


@override $AcpAuthStateCopyWith<$Res> get auth;@override $SettingsActionCopyWith<$Res>? get checkAction;@override $SettingsActionCopyWith<$Res>? get cancelAction;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$AcpAccountAuthViewStateCopyWithImpl<$Res>
    implements _$AcpAccountAuthViewStateCopyWith<$Res> {
  __$AcpAccountAuthViewStateCopyWithImpl(this._self, this._then);

  final _AcpAccountAuthViewState _self;
  final $Res Function(_AcpAccountAuthViewState) _then;

/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? target = null,Object? auth = null,Object? visible = null,Object? latestIntent = null,Object? checkAction = freezed,Object? cancelAction = freezed,Object? notice = freezed,Object? observationError = freezed,}) {
  return _then(_AcpAccountAuthViewState(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as AcpAccountTarget,auth: null == auth ? _self.auth : auth // ignore: cast_nullable_to_non_nullable
as AcpAuthState,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,checkAction: freezed == checkAction ? _self.checkAction : checkAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,cancelAction: freezed == cancelAction ? _self.cancelAction : cancelAction // ignore: cast_nullable_to_non_nullable
as SettingsAction?,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as AcpCommandNotice?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthStateCopyWith<$Res> get auth {

  return $AcpAuthStateCopyWith<$Res>(_self.auth, (value) {
    return _then(_self.copyWith(auth: value));
  });
}/// Create a copy of AcpAccountAuthViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<$Res>? get checkAction {
    if (_self.checkAction == null) {
    return null;
  }

  return $SettingsActionCopyWith<$Res>(_self.checkAction!, (value) {
    return _then(_self.copyWith(checkAction: value));
  });
}/// Create a copy of AcpAccountAuthViewState
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
}/// Create a copy of AcpAccountAuthViewState
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
