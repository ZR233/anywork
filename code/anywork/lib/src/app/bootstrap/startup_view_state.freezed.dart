// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'startup_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StartupViewState {

 StartupState get startup; bool get retryPending; StudioFailure? get bootstrapError; StartupRecovery? get recovery; bool get recoveryDismissed; bool get recoveryLoading; StudioFailure? get recoveryError; StartupActiveTurnPage? get activeTurns; bool get activeTurnsLoading; StudioFailure? get activeTurnsError;
/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupViewStateCopyWith<StartupViewState> get copyWith => _$StartupViewStateCopyWithImpl<StartupViewState>(this as StartupViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartupViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupViewState&&(identical(other.startup, _this.startup) || other.startup == _this.startup)&&(identical(other.retryPending, _this.retryPending) || other.retryPending == _this.retryPending)&&(identical(other.bootstrapError, _this.bootstrapError) || other.bootstrapError == _this.bootstrapError)&&(identical(other.recovery, _this.recovery) || other.recovery == _this.recovery)&&(identical(other.recoveryDismissed, _this.recoveryDismissed) || other.recoveryDismissed == _this.recoveryDismissed)&&(identical(other.recoveryLoading, _this.recoveryLoading) || other.recoveryLoading == _this.recoveryLoading)&&(identical(other.recoveryError, _this.recoveryError) || other.recoveryError == _this.recoveryError)&&(identical(other.activeTurns, _this.activeTurns) || other.activeTurns == _this.activeTurns)&&(identical(other.activeTurnsLoading, _this.activeTurnsLoading) || other.activeTurnsLoading == _this.activeTurnsLoading)&&(identical(other.activeTurnsError, _this.activeTurnsError) || other.activeTurnsError == _this.activeTurnsError));
}


@override
int get hashCode {
  final _this = this as StartupViewState;
  return Object.hash(runtimeType,_this.startup,_this.retryPending,_this.bootstrapError,_this.recovery,_this.recoveryDismissed,_this.recoveryLoading,_this.recoveryError,_this.activeTurns,_this.activeTurnsLoading,_this.activeTurnsError);
}



}

/// @nodoc
abstract mixin class $StartupViewStateCopyWith<$Res>  {
  factory $StartupViewStateCopyWith(StartupViewState value, $Res Function(StartupViewState) _then) = _$StartupViewStateCopyWithImpl;
@useResult
$Res call({
 StartupState startup, bool retryPending, StudioFailure? bootstrapError, StartupRecovery? recovery, bool recoveryDismissed, bool recoveryLoading, StudioFailure? recoveryError, StartupActiveTurnPage? activeTurns, bool activeTurnsLoading, StudioFailure? activeTurnsError
});


$StartupStateCopyWith<$Res> get startup;$StudioFailureCopyWith<$Res>? get bootstrapError;$StartupRecoveryCopyWith<$Res>? get recovery;$StudioFailureCopyWith<$Res>? get recoveryError;$StartupActiveTurnPageCopyWith<$Res>? get activeTurns;$StudioFailureCopyWith<$Res>? get activeTurnsError;

}
/// @nodoc
class _$StartupViewStateCopyWithImpl<$Res>
    implements $StartupViewStateCopyWith<$Res> {
  _$StartupViewStateCopyWithImpl(this._self, this._then);

  final StartupViewState _self;
  final $Res Function(StartupViewState) _then;

/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? startup = null,Object? retryPending = null,Object? bootstrapError = freezed,Object? recovery = freezed,Object? recoveryDismissed = null,Object? recoveryLoading = null,Object? recoveryError = freezed,Object? activeTurns = freezed,Object? activeTurnsLoading = null,Object? activeTurnsError = freezed,}) {
  return _then(StartupViewState(
startup: null == startup ? _self.startup : startup // ignore: cast_nullable_to_non_nullable
as StartupState,retryPending: null == retryPending ? _self.retryPending : retryPending // ignore: cast_nullable_to_non_nullable
as bool,bootstrapError: freezed == bootstrapError ? _self.bootstrapError : bootstrapError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,recovery: freezed == recovery ? _self.recovery : recovery // ignore: cast_nullable_to_non_nullable
as StartupRecovery?,recoveryDismissed: null == recoveryDismissed ? _self.recoveryDismissed : recoveryDismissed // ignore: cast_nullable_to_non_nullable
as bool,recoveryLoading: null == recoveryLoading ? _self.recoveryLoading : recoveryLoading // ignore: cast_nullable_to_non_nullable
as bool,recoveryError: freezed == recoveryError ? _self.recoveryError : recoveryError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,activeTurns: freezed == activeTurns ? _self.activeTurns : activeTurns // ignore: cast_nullable_to_non_nullable
as StartupActiveTurnPage?,activeTurnsLoading: null == activeTurnsLoading ? _self.activeTurnsLoading : activeTurnsLoading // ignore: cast_nullable_to_non_nullable
as bool,activeTurnsError: freezed == activeTurnsError ? _self.activeTurnsError : activeTurnsError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupStateCopyWith<$Res> get startup {

  return $StartupStateCopyWith<$Res>(_self.startup, (value) {
    return _then(_self.copyWith(startup: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get bootstrapError {
    if (_self.bootstrapError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.bootstrapError!, (value) {
    return _then(_self.copyWith(bootstrapError: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupRecoveryCopyWith<$Res>? get recovery {
    if (_self.recovery == null) {
    return null;
  }

  return $StartupRecoveryCopyWith<$Res>(_self.recovery!, (value) {
    return _then(_self.copyWith(recovery: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get recoveryError {
    if (_self.recoveryError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.recoveryError!, (value) {
    return _then(_self.copyWith(recoveryError: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupActiveTurnPageCopyWith<$Res>? get activeTurns {
    if (_self.activeTurns == null) {
    return null;
  }

  return $StartupActiveTurnPageCopyWith<$Res>(_self.activeTurns!, (value) {
    return _then(_self.copyWith(activeTurns: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get activeTurnsError {
    if (_self.activeTurnsError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.activeTurnsError!, (value) {
    return _then(_self.copyWith(activeTurnsError: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartupViewState].
extension StartupViewStatePatterns on StartupViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupViewState value)  $default,){
final _that = this;
switch (_that) {
case _StartupViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupViewState value)?  $default,){
final _that = this;
switch (_that) {
case _StartupViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StartupState startup,  bool retryPending,  StudioFailure? bootstrapError,  StartupRecovery? recovery,  bool recoveryDismissed,  bool recoveryLoading,  StudioFailure? recoveryError,  StartupActiveTurnPage? activeTurns,  bool activeTurnsLoading,  StudioFailure? activeTurnsError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupViewState() when $default != null:
return $default(_that.startup,_that.retryPending,_that.bootstrapError,_that.recovery,_that.recoveryDismissed,_that.recoveryLoading,_that.recoveryError,_that.activeTurns,_that.activeTurnsLoading,_that.activeTurnsError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StartupState startup,  bool retryPending,  StudioFailure? bootstrapError,  StartupRecovery? recovery,  bool recoveryDismissed,  bool recoveryLoading,  StudioFailure? recoveryError,  StartupActiveTurnPage? activeTurns,  bool activeTurnsLoading,  StudioFailure? activeTurnsError)  $default,) {final _that = this;
switch (_that) {
case _StartupViewState():
return $default(_that.startup,_that.retryPending,_that.bootstrapError,_that.recovery,_that.recoveryDismissed,_that.recoveryLoading,_that.recoveryError,_that.activeTurns,_that.activeTurnsLoading,_that.activeTurnsError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StartupState startup,  bool retryPending,  StudioFailure? bootstrapError,  StartupRecovery? recovery,  bool recoveryDismissed,  bool recoveryLoading,  StudioFailure? recoveryError,  StartupActiveTurnPage? activeTurns,  bool activeTurnsLoading,  StudioFailure? activeTurnsError)?  $default,) {final _that = this;
switch (_that) {
case _StartupViewState() when $default != null:
return $default(_that.startup,_that.retryPending,_that.bootstrapError,_that.recovery,_that.recoveryDismissed,_that.recoveryLoading,_that.recoveryError,_that.activeTurns,_that.activeTurnsLoading,_that.activeTurnsError);case _:
  return null;

}
}

}

/// @nodoc


class _StartupViewState implements StartupViewState {
  const _StartupViewState({required this.startup, required this.retryPending, required this.bootstrapError, required this.recovery, required this.recoveryDismissed, required this.recoveryLoading, required this.recoveryError, required this.activeTurns, required this.activeTurnsLoading, required this.activeTurnsError});


@override final  StartupState startup;
@override final  bool retryPending;
@override final  StudioFailure? bootstrapError;
@override final  StartupRecovery? recovery;
@override final  bool recoveryDismissed;
@override final  bool recoveryLoading;
@override final  StudioFailure? recoveryError;
@override final  StartupActiveTurnPage? activeTurns;
@override final  bool activeTurnsLoading;
@override final  StudioFailure? activeTurnsError;

/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupViewStateCopyWith<_StartupViewState> get copyWith => __$StartupViewStateCopyWithImpl<_StartupViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupViewState&&(identical(other.startup, startup) || other.startup == startup)&&(identical(other.retryPending, retryPending) || other.retryPending == retryPending)&&(identical(other.bootstrapError, bootstrapError) || other.bootstrapError == bootstrapError)&&(identical(other.recovery, recovery) || other.recovery == recovery)&&(identical(other.recoveryDismissed, recoveryDismissed) || other.recoveryDismissed == recoveryDismissed)&&(identical(other.recoveryLoading, recoveryLoading) || other.recoveryLoading == recoveryLoading)&&(identical(other.recoveryError, recoveryError) || other.recoveryError == recoveryError)&&(identical(other.activeTurns, activeTurns) || other.activeTurns == activeTurns)&&(identical(other.activeTurnsLoading, activeTurnsLoading) || other.activeTurnsLoading == activeTurnsLoading)&&(identical(other.activeTurnsError, activeTurnsError) || other.activeTurnsError == activeTurnsError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startup,retryPending,bootstrapError,recovery,recoveryDismissed,recoveryLoading,recoveryError,activeTurns,activeTurnsLoading,activeTurnsError);
}



}

/// @nodoc
abstract mixin class _$StartupViewStateCopyWith<$Res> implements $StartupViewStateCopyWith<$Res> {
  factory _$StartupViewStateCopyWith(_StartupViewState value, $Res Function(_StartupViewState) _then) = __$StartupViewStateCopyWithImpl;
@override @useResult
$Res call({
 StartupState startup, bool retryPending, StudioFailure? bootstrapError, StartupRecovery? recovery, bool recoveryDismissed, bool recoveryLoading, StudioFailure? recoveryError, StartupActiveTurnPage? activeTurns, bool activeTurnsLoading, StudioFailure? activeTurnsError
});


@override $StartupStateCopyWith<$Res> get startup;@override $StudioFailureCopyWith<$Res>? get bootstrapError;@override $StartupRecoveryCopyWith<$Res>? get recovery;@override $StudioFailureCopyWith<$Res>? get recoveryError;@override $StartupActiveTurnPageCopyWith<$Res>? get activeTurns;@override $StudioFailureCopyWith<$Res>? get activeTurnsError;

}
/// @nodoc
class __$StartupViewStateCopyWithImpl<$Res>
    implements _$StartupViewStateCopyWith<$Res> {
  __$StartupViewStateCopyWithImpl(this._self, this._then);

  final _StartupViewState _self;
  final $Res Function(_StartupViewState) _then;

/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? startup = null,Object? retryPending = null,Object? bootstrapError = freezed,Object? recovery = freezed,Object? recoveryDismissed = null,Object? recoveryLoading = null,Object? recoveryError = freezed,Object? activeTurns = freezed,Object? activeTurnsLoading = null,Object? activeTurnsError = freezed,}) {
  return _then(_StartupViewState(
startup: null == startup ? _self.startup : startup // ignore: cast_nullable_to_non_nullable
as StartupState,retryPending: null == retryPending ? _self.retryPending : retryPending // ignore: cast_nullable_to_non_nullable
as bool,bootstrapError: freezed == bootstrapError ? _self.bootstrapError : bootstrapError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,recovery: freezed == recovery ? _self.recovery : recovery // ignore: cast_nullable_to_non_nullable
as StartupRecovery?,recoveryDismissed: null == recoveryDismissed ? _self.recoveryDismissed : recoveryDismissed // ignore: cast_nullable_to_non_nullable
as bool,recoveryLoading: null == recoveryLoading ? _self.recoveryLoading : recoveryLoading // ignore: cast_nullable_to_non_nullable
as bool,recoveryError: freezed == recoveryError ? _self.recoveryError : recoveryError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,activeTurns: freezed == activeTurns ? _self.activeTurns : activeTurns // ignore: cast_nullable_to_non_nullable
as StartupActiveTurnPage?,activeTurnsLoading: null == activeTurnsLoading ? _self.activeTurnsLoading : activeTurnsLoading // ignore: cast_nullable_to_non_nullable
as bool,activeTurnsError: freezed == activeTurnsError ? _self.activeTurnsError : activeTurnsError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupStateCopyWith<$Res> get startup {

  return $StartupStateCopyWith<$Res>(_self.startup, (value) {
    return _then(_self.copyWith(startup: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get bootstrapError {
    if (_self.bootstrapError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.bootstrapError!, (value) {
    return _then(_self.copyWith(bootstrapError: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupRecoveryCopyWith<$Res>? get recovery {
    if (_self.recovery == null) {
    return null;
  }

  return $StartupRecoveryCopyWith<$Res>(_self.recovery!, (value) {
    return _then(_self.copyWith(recovery: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get recoveryError {
    if (_self.recoveryError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.recoveryError!, (value) {
    return _then(_self.copyWith(recoveryError: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupActiveTurnPageCopyWith<$Res>? get activeTurns {
    if (_self.activeTurns == null) {
    return null;
  }

  return $StartupActiveTurnPageCopyWith<$Res>(_self.activeTurns!, (value) {
    return _then(_self.copyWith(activeTurns: value));
  });
}/// Create a copy of StartupViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get activeTurnsError {
    if (_self.activeTurnsError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.activeTurnsError!, (value) {
    return _then(_self.copyWith(activeTurnsError: value));
  });
}
}

// dart format on
