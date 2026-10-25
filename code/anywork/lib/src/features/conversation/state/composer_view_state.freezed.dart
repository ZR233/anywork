// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'composer_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ComposerViewState {

 ComposerKey get key; ComposerDraftState? get draft; StartDraftState? get startDraft; StartRoutePreferences? get preferences; String get urlRaw; ValidationIssue? get inputIssue; StudioFailure? get error; StudioFailure? get platformError; OperationState? get operation; int get latestIntent; bool get pending; bool get platformPending; bool get closing;
/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComposerViewStateCopyWith<ComposerViewState> get copyWith => _$ComposerViewStateCopyWithImpl<ComposerViewState>(this as ComposerViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ComposerViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComposerViewState&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.draft, _this.draft) || other.draft == _this.draft)&&(identical(other.startDraft, _this.startDraft) || other.startDraft == _this.startDraft)&&(identical(other.preferences, _this.preferences) || other.preferences == _this.preferences)&&(identical(other.urlRaw, _this.urlRaw) || other.urlRaw == _this.urlRaw)&&(identical(other.inputIssue, _this.inputIssue) || other.inputIssue == _this.inputIssue)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.platformError, _this.platformError) || other.platformError == _this.platformError)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.pending, _this.pending) || other.pending == _this.pending)&&(identical(other.platformPending, _this.platformPending) || other.platformPending == _this.platformPending)&&(identical(other.closing, _this.closing) || other.closing == _this.closing));
}


@override
int get hashCode {
  final _this = this as ComposerViewState;
  return Object.hash(runtimeType,_this.key,_this.draft,_this.startDraft,_this.preferences,_this.urlRaw,_this.inputIssue,_this.error,_this.platformError,_this.operation,_this.latestIntent,_this.pending,_this.platformPending,_this.closing);
}



}

/// @nodoc
abstract mixin class $ComposerViewStateCopyWith<$Res>  {
  factory $ComposerViewStateCopyWith(ComposerViewState value, $Res Function(ComposerViewState) _then) = _$ComposerViewStateCopyWithImpl;
@useResult
$Res call({
 ComposerKey key, ComposerDraftState? draft, StartDraftState? startDraft, StartRoutePreferences? preferences, String urlRaw, ValidationIssue? inputIssue, StudioFailure? error, StudioFailure? platformError, OperationState? operation, int latestIntent, bool pending, bool platformPending, bool closing
});


$ComposerKeyCopyWith<$Res> get key;$ComposerDraftStateCopyWith<$Res>? get draft;$StartDraftStateCopyWith<$Res>? get startDraft;$StartRoutePreferencesCopyWith<$Res>? get preferences;$ValidationIssueCopyWith<$Res>? get inputIssue;$StudioFailureCopyWith<$Res>? get error;$StudioFailureCopyWith<$Res>? get platformError;$OperationStateCopyWith<$Res>? get operation;

}
/// @nodoc
class _$ComposerViewStateCopyWithImpl<$Res>
    implements $ComposerViewStateCopyWith<$Res> {
  _$ComposerViewStateCopyWithImpl(this._self, this._then);

  final ComposerViewState _self;
  final $Res Function(ComposerViewState) _then;

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? draft = freezed,Object? startDraft = freezed,Object? preferences = freezed,Object? urlRaw = null,Object? inputIssue = freezed,Object? error = freezed,Object? platformError = freezed,Object? operation = freezed,Object? latestIntent = null,Object? pending = null,Object? platformPending = null,Object? closing = null,}) {
  return _then(ComposerViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ComposerKey,draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as ComposerDraftState?,startDraft: freezed == startDraft ? _self.startDraft : startDraft // ignore: cast_nullable_to_non_nullable
as StartDraftState?,preferences: freezed == preferences ? _self.preferences : preferences // ignore: cast_nullable_to_non_nullable
as StartRoutePreferences?,urlRaw: null == urlRaw ? _self.urlRaw : urlRaw // ignore: cast_nullable_to_non_nullable
as String,inputIssue: freezed == inputIssue ? _self.inputIssue : inputIssue // ignore: cast_nullable_to_non_nullable
as ValidationIssue?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,platformError: freezed == platformError ? _self.platformError : platformError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,platformPending: null == platformPending ? _self.platformPending : platformPending // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerKeyCopyWith<$Res> get key {

  return $ComposerKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerDraftStateCopyWith<$Res>? get draft {
    if (_self.draft == null) {
    return null;
  }

  return $ComposerDraftStateCopyWith<$Res>(_self.draft!, (value) {
    return _then(_self.copyWith(draft: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartDraftStateCopyWith<$Res>? get startDraft {
    if (_self.startDraft == null) {
    return null;
  }

  return $StartDraftStateCopyWith<$Res>(_self.startDraft!, (value) {
    return _then(_self.copyWith(startDraft: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRoutePreferencesCopyWith<$Res>? get preferences {
    if (_self.preferences == null) {
    return null;
  }

  return $StartRoutePreferencesCopyWith<$Res>(_self.preferences!, (value) {
    return _then(_self.copyWith(preferences: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationIssueCopyWith<$Res>? get inputIssue {
    if (_self.inputIssue == null) {
    return null;
  }

  return $ValidationIssueCopyWith<$Res>(_self.inputIssue!, (value) {
    return _then(_self.copyWith(inputIssue: value));
  });
}/// Create a copy of ComposerViewState
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
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get platformError {
    if (_self.platformError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.platformError!, (value) {
    return _then(_self.copyWith(platformError: value));
  });
}/// Create a copy of ComposerViewState
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
}
}


/// Adds pattern-matching-related methods to [ComposerViewState].
extension ComposerViewStatePatterns on ComposerViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ComposerViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ComposerViewState value)  $default,){
final _that = this;
switch (_that) {
case _ComposerViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ComposerViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ComposerKey key,  ComposerDraftState? draft,  StartDraftState? startDraft,  StartRoutePreferences? preferences,  String urlRaw,  ValidationIssue? inputIssue,  StudioFailure? error,  StudioFailure? platformError,  OperationState? operation,  int latestIntent,  bool pending,  bool platformPending,  bool closing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
return $default(_that.key,_that.draft,_that.startDraft,_that.preferences,_that.urlRaw,_that.inputIssue,_that.error,_that.platformError,_that.operation,_that.latestIntent,_that.pending,_that.platformPending,_that.closing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ComposerKey key,  ComposerDraftState? draft,  StartDraftState? startDraft,  StartRoutePreferences? preferences,  String urlRaw,  ValidationIssue? inputIssue,  StudioFailure? error,  StudioFailure? platformError,  OperationState? operation,  int latestIntent,  bool pending,  bool platformPending,  bool closing)  $default,) {final _that = this;
switch (_that) {
case _ComposerViewState():
return $default(_that.key,_that.draft,_that.startDraft,_that.preferences,_that.urlRaw,_that.inputIssue,_that.error,_that.platformError,_that.operation,_that.latestIntent,_that.pending,_that.platformPending,_that.closing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ComposerKey key,  ComposerDraftState? draft,  StartDraftState? startDraft,  StartRoutePreferences? preferences,  String urlRaw,  ValidationIssue? inputIssue,  StudioFailure? error,  StudioFailure? platformError,  OperationState? operation,  int latestIntent,  bool pending,  bool platformPending,  bool closing)?  $default,) {final _that = this;
switch (_that) {
case _ComposerViewState() when $default != null:
return $default(_that.key,_that.draft,_that.startDraft,_that.preferences,_that.urlRaw,_that.inputIssue,_that.error,_that.platformError,_that.operation,_that.latestIntent,_that.pending,_that.platformPending,_that.closing);case _:
  return null;

}
}

}

/// @nodoc


class _ComposerViewState extends ComposerViewState {
  const _ComposerViewState({required this.key, this.draft, this.startDraft, this.preferences, this.urlRaw = '', this.inputIssue, this.error, this.platformError, this.operation, this.latestIntent = 0, this.pending = false, this.platformPending = false, this.closing = false}): super._();


@override final  ComposerKey key;
@override final  ComposerDraftState? draft;
@override final  StartDraftState? startDraft;
@override final  StartRoutePreferences? preferences;
@override@JsonKey() final  String urlRaw;
@override final  ValidationIssue? inputIssue;
@override final  StudioFailure? error;
@override final  StudioFailure? platformError;
@override final  OperationState? operation;
@override@JsonKey() final  int latestIntent;
@override@JsonKey() final  bool pending;
@override@JsonKey() final  bool platformPending;
@override@JsonKey() final  bool closing;

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ComposerViewStateCopyWith<_ComposerViewState> get copyWith => __$ComposerViewStateCopyWithImpl<_ComposerViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ComposerViewState&&(identical(other.key, key) || other.key == key)&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.startDraft, startDraft) || other.startDraft == startDraft)&&(identical(other.preferences, preferences) || other.preferences == preferences)&&(identical(other.urlRaw, urlRaw) || other.urlRaw == urlRaw)&&(identical(other.inputIssue, inputIssue) || other.inputIssue == inputIssue)&&(identical(other.error, error) || other.error == error)&&(identical(other.platformError, platformError) || other.platformError == platformError)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.platformPending, platformPending) || other.platformPending == platformPending)&&(identical(other.closing, closing) || other.closing == closing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,draft,startDraft,preferences,urlRaw,inputIssue,error,platformError,operation,latestIntent,pending,platformPending,closing);
}



}

/// @nodoc
abstract mixin class _$ComposerViewStateCopyWith<$Res> implements $ComposerViewStateCopyWith<$Res> {
  factory _$ComposerViewStateCopyWith(_ComposerViewState value, $Res Function(_ComposerViewState) _then) = __$ComposerViewStateCopyWithImpl;
@override @useResult
$Res call({
 ComposerKey key, ComposerDraftState? draft, StartDraftState? startDraft, StartRoutePreferences? preferences, String urlRaw, ValidationIssue? inputIssue, StudioFailure? error, StudioFailure? platformError, OperationState? operation, int latestIntent, bool pending, bool platformPending, bool closing
});


@override $ComposerKeyCopyWith<$Res> get key;@override $ComposerDraftStateCopyWith<$Res>? get draft;@override $StartDraftStateCopyWith<$Res>? get startDraft;@override $StartRoutePreferencesCopyWith<$Res>? get preferences;@override $ValidationIssueCopyWith<$Res>? get inputIssue;@override $StudioFailureCopyWith<$Res>? get error;@override $StudioFailureCopyWith<$Res>? get platformError;@override $OperationStateCopyWith<$Res>? get operation;

}
/// @nodoc
class __$ComposerViewStateCopyWithImpl<$Res>
    implements _$ComposerViewStateCopyWith<$Res> {
  __$ComposerViewStateCopyWithImpl(this._self, this._then);

  final _ComposerViewState _self;
  final $Res Function(_ComposerViewState) _then;

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? draft = freezed,Object? startDraft = freezed,Object? preferences = freezed,Object? urlRaw = null,Object? inputIssue = freezed,Object? error = freezed,Object? platformError = freezed,Object? operation = freezed,Object? latestIntent = null,Object? pending = null,Object? platformPending = null,Object? closing = null,}) {
  return _then(_ComposerViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ComposerKey,draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as ComposerDraftState?,startDraft: freezed == startDraft ? _self.startDraft : startDraft // ignore: cast_nullable_to_non_nullable
as StartDraftState?,preferences: freezed == preferences ? _self.preferences : preferences // ignore: cast_nullable_to_non_nullable
as StartRoutePreferences?,urlRaw: null == urlRaw ? _self.urlRaw : urlRaw // ignore: cast_nullable_to_non_nullable
as String,inputIssue: freezed == inputIssue ? _self.inputIssue : inputIssue // ignore: cast_nullable_to_non_nullable
as ValidationIssue?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,platformError: freezed == platformError ? _self.platformError : platformError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,platformPending: null == platformPending ? _self.platformPending : platformPending // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerKeyCopyWith<$Res> get key {

  return $ComposerKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ComposerDraftStateCopyWith<$Res>? get draft {
    if (_self.draft == null) {
    return null;
  }

  return $ComposerDraftStateCopyWith<$Res>(_self.draft!, (value) {
    return _then(_self.copyWith(draft: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartDraftStateCopyWith<$Res>? get startDraft {
    if (_self.startDraft == null) {
    return null;
  }

  return $StartDraftStateCopyWith<$Res>(_self.startDraft!, (value) {
    return _then(_self.copyWith(startDraft: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRoutePreferencesCopyWith<$Res>? get preferences {
    if (_self.preferences == null) {
    return null;
  }

  return $StartRoutePreferencesCopyWith<$Res>(_self.preferences!, (value) {
    return _then(_self.copyWith(preferences: value));
  });
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ValidationIssueCopyWith<$Res>? get inputIssue {
    if (_self.inputIssue == null) {
    return null;
  }

  return $ValidationIssueCopyWith<$Res>(_self.inputIssue!, (value) {
    return _then(_self.copyWith(inputIssue: value));
  });
}/// Create a copy of ComposerViewState
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
}/// Create a copy of ComposerViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get platformError {
    if (_self.platformError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.platformError!, (value) {
    return _then(_self.copyWith(platformError: value));
  });
}/// Create a copy of ComposerViewState
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
}
}

// dart format on
