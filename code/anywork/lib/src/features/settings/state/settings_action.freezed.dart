// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_action.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsAction {

 int get intent; bool get pending; OperationState? get operation; SettingsActionOutcome? get outcome; StudioFailure? get error; StudioFailure? get observationError;
/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsActionCopyWith<SettingsAction> get copyWith => _$SettingsActionCopyWithImpl<SettingsAction>(this as SettingsAction, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsAction;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsAction&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as SettingsAction;
  return Object.hash(runtimeType,_this.intent,_this.pending,_this.operation,_this.outcome,_this.error,_this.observationError);
}

@override
String toString() {
  final _this = this as SettingsAction;
  return 'SettingsAction(intent: ${_this.intent}, pending: ${_this.pending}, operation: ${_this.operation}, outcome: ${_this.outcome}, error: ${_this.error}, observationError: ${_this.observationError})';
}


}

/// @nodoc
abstract mixin class $SettingsActionCopyWith<$Res>  {
  factory $SettingsActionCopyWith(SettingsAction value, $Res Function(SettingsAction) _then) = _$SettingsActionCopyWithImpl;
@useResult
$Res call({
 int intent, bool pending, OperationState? operation, SettingsActionOutcome? outcome, StudioFailure? error, StudioFailure? observationError
});


$OperationStateCopyWith<$Res>? get operation;$StudioFailureCopyWith<$Res>? get error;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$SettingsActionCopyWithImpl<$Res>
    implements $SettingsActionCopyWith<$Res> {
  _$SettingsActionCopyWithImpl(this._self, this._then);

  final SettingsAction _self;
  final $Res Function(SettingsAction) _then;

/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? pending = null,Object? operation = freezed,Object? outcome = freezed,Object? error = freezed,Object? observationError = freezed,}) {
  return _then(SettingsAction(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as SettingsActionOutcome?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of SettingsAction
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


/// Adds pattern-matching-related methods to [SettingsAction].
extension SettingsActionPatterns on SettingsAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsAction value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsAction() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsAction value)  $default,){
final _that = this;
switch (_that) {
case _SettingsAction():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsAction value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsAction() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int intent,  bool pending,  OperationState? operation,  SettingsActionOutcome? outcome,  StudioFailure? error,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsAction() when $default != null:
return $default(_that.intent,_that.pending,_that.operation,_that.outcome,_that.error,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int intent,  bool pending,  OperationState? operation,  SettingsActionOutcome? outcome,  StudioFailure? error,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _SettingsAction():
return $default(_that.intent,_that.pending,_that.operation,_that.outcome,_that.error,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int intent,  bool pending,  OperationState? operation,  SettingsActionOutcome? outcome,  StudioFailure? error,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _SettingsAction() when $default != null:
return $default(_that.intent,_that.pending,_that.operation,_that.outcome,_that.error,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsAction extends SettingsAction {
  const _SettingsAction({required this.intent, this.pending = false, this.operation, this.outcome, this.error, this.observationError}): super._();


@override final  int intent;
@override@JsonKey() final  bool pending;
@override final  OperationState? operation;
@override final  SettingsActionOutcome? outcome;
@override final  StudioFailure? error;
@override final  StudioFailure? observationError;

/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsActionCopyWith<_SettingsAction> get copyWith => __$SettingsActionCopyWithImpl<_SettingsAction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsAction&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.error, error) || other.error == error)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,pending,operation,outcome,error,observationError);
}

@override
String toString() {
    return 'SettingsAction(intent: $intent, pending: $pending, operation: $operation, outcome: $outcome, error: $error, observationError: $observationError)';
}


}

/// @nodoc
abstract mixin class _$SettingsActionCopyWith<$Res> implements $SettingsActionCopyWith<$Res> {
  factory _$SettingsActionCopyWith(_SettingsAction value, $Res Function(_SettingsAction) _then) = __$SettingsActionCopyWithImpl;
@override @useResult
$Res call({
 int intent, bool pending, OperationState? operation, SettingsActionOutcome? outcome, StudioFailure? error, StudioFailure? observationError
});


@override $OperationStateCopyWith<$Res>? get operation;@override $StudioFailureCopyWith<$Res>? get error;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$SettingsActionCopyWithImpl<$Res>
    implements _$SettingsActionCopyWith<$Res> {
  __$SettingsActionCopyWithImpl(this._self, this._then);

  final _SettingsAction _self;
  final $Res Function(_SettingsAction) _then;

/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? pending = null,Object? operation = freezed,Object? outcome = freezed,Object? error = freezed,Object? observationError = freezed,}) {
  return _then(_SettingsAction(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as SettingsActionOutcome?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of SettingsAction
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of SettingsAction
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
