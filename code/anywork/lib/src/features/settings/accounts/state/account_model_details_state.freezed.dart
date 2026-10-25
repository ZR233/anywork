// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_model_details_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountModelDetailsEntry {

 AccountModelKey get model; DelegationModelReadTarget? get target; bool get billingOverrideKnown; BillingKind? get billingOverride;
/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelDetailsEntryCopyWith<AccountModelDetailsEntry> get copyWith => _$AccountModelDetailsEntryCopyWithImpl<AccountModelDetailsEntry>(this as AccountModelDetailsEntry, _$identity);





@override
String toString() {
  final _this = this as AccountModelDetailsEntry;
  return 'AccountModelDetailsEntry(model: ${_this.model}, target: ${_this.target}, billingOverrideKnown: ${_this.billingOverrideKnown}, billingOverride: ${_this.billingOverride})';
}


}

/// @nodoc
abstract mixin class $AccountModelDetailsEntryCopyWith<$Res>  {
  factory $AccountModelDetailsEntryCopyWith(AccountModelDetailsEntry value, $Res Function(AccountModelDetailsEntry) _then) = _$AccountModelDetailsEntryCopyWithImpl;
@useResult
$Res call({
 AccountModelKey model, DelegationModelReadTarget? target, bool billingOverrideKnown, BillingKind? billingOverride
});


$AccountModelKeyCopyWith<$Res> get model;$DelegationModelReadTargetCopyWith<$Res>? get target;

}
/// @nodoc
class _$AccountModelDetailsEntryCopyWithImpl<$Res>
    implements $AccountModelDetailsEntryCopyWith<$Res> {
  _$AccountModelDetailsEntryCopyWithImpl(this._self, this._then);

  final AccountModelDetailsEntry _self;
  final $Res Function(AccountModelDetailsEntry) _then;

/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? model = null,Object? target = freezed,Object? billingOverrideKnown = null,Object? billingOverride = freezed,}) {
  return _then(AccountModelDetailsEntry(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,target: freezed == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DelegationModelReadTarget?,billingOverrideKnown: null == billingOverrideKnown ? _self.billingOverrideKnown : billingOverrideKnown // ignore: cast_nullable_to_non_nullable
as bool,billingOverride: freezed == billingOverride ? _self.billingOverride : billingOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,
  ));
}
/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<$Res>? get target {
    if (_self.target == null) {
    return null;
  }

  return $DelegationModelReadTargetCopyWith<$Res>(_self.target!, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountModelDetailsEntry].
extension AccountModelDetailsEntryPatterns on AccountModelDetailsEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelDetailsEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelDetailsEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelDetailsEntry value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelDetailsEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelDetailsEntry value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelDetailsEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountModelKey model,  DelegationModelReadTarget? target,  bool billingOverrideKnown,  BillingKind? billingOverride)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelDetailsEntry() when $default != null:
return $default(_that.model,_that.target,_that.billingOverrideKnown,_that.billingOverride);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountModelKey model,  DelegationModelReadTarget? target,  bool billingOverrideKnown,  BillingKind? billingOverride)  $default,) {final _that = this;
switch (_that) {
case _AccountModelDetailsEntry():
return $default(_that.model,_that.target,_that.billingOverrideKnown,_that.billingOverride);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountModelKey model,  DelegationModelReadTarget? target,  bool billingOverrideKnown,  BillingKind? billingOverride)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelDetailsEntry() when $default != null:
return $default(_that.model,_that.target,_that.billingOverrideKnown,_that.billingOverride);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelDetailsEntry implements AccountModelDetailsEntry {
  const _AccountModelDetailsEntry({required this.model, required this.target, required this.billingOverrideKnown, required this.billingOverride});


@override final  AccountModelKey model;
@override final  DelegationModelReadTarget? target;
@override final  bool billingOverrideKnown;
@override final  BillingKind? billingOverride;

/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelDetailsEntryCopyWith<_AccountModelDetailsEntry> get copyWith => __$AccountModelDetailsEntryCopyWithImpl<_AccountModelDetailsEntry>(this, _$identity);





@override
String toString() {
    return 'AccountModelDetailsEntry(model: $model, target: $target, billingOverrideKnown: $billingOverrideKnown, billingOverride: $billingOverride)';
}


}

/// @nodoc
abstract mixin class _$AccountModelDetailsEntryCopyWith<$Res> implements $AccountModelDetailsEntryCopyWith<$Res> {
  factory _$AccountModelDetailsEntryCopyWith(_AccountModelDetailsEntry value, $Res Function(_AccountModelDetailsEntry) _then) = __$AccountModelDetailsEntryCopyWithImpl;
@override @useResult
$Res call({
 AccountModelKey model, DelegationModelReadTarget? target, bool billingOverrideKnown, BillingKind? billingOverride
});


@override $AccountModelKeyCopyWith<$Res> get model;@override $DelegationModelReadTargetCopyWith<$Res>? get target;

}
/// @nodoc
class __$AccountModelDetailsEntryCopyWithImpl<$Res>
    implements _$AccountModelDetailsEntryCopyWith<$Res> {
  __$AccountModelDetailsEntryCopyWithImpl(this._self, this._then);

  final _AccountModelDetailsEntry _self;
  final $Res Function(_AccountModelDetailsEntry) _then;

/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? model = null,Object? target = freezed,Object? billingOverrideKnown = null,Object? billingOverride = freezed,}) {
  return _then(_AccountModelDetailsEntry(
model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as AccountModelKey,target: freezed == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DelegationModelReadTarget?,billingOverrideKnown: null == billingOverrideKnown ? _self.billingOverrideKnown : billingOverrideKnown // ignore: cast_nullable_to_non_nullable
as bool,billingOverride: freezed == billingOverride ? _self.billingOverride : billingOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,
  ));
}

/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get model {

  return $AccountModelKeyCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}/// Create a copy of AccountModelDetailsEntry
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<$Res>? get target {
    if (_self.target == null) {
    return null;
  }

  return $DelegationModelReadTargetCopyWith<$Res>(_self.target!, (value) {
    return _then(_self.copyWith(target: value));
  });
}
}

/// @nodoc
mixin _$AccountModelDetailsViewState {

 AccountModelDetailsEntry get entry; DelegationModelReadTarget? get target; bool get billingOverrideKnown; BillingKind? get billingOverride; DelegationModelDetail? get detail; int get latestIntent; bool get reading; bool get stale; StudioFailure? get error; List<StudioFailure> get observationErrors; StudioFailure? get configurationError; StudioFailure? get catalogError;
/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelDetailsViewStateCopyWith<AccountModelDetailsViewState> get copyWith => _$AccountModelDetailsViewStateCopyWithImpl<AccountModelDetailsViewState>(this as AccountModelDetailsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelDetailsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelDetailsViewState&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.billingOverrideKnown, _this.billingOverrideKnown) || other.billingOverrideKnown == _this.billingOverrideKnown)&&(identical(other.billingOverride, _this.billingOverride) || other.billingOverride == _this.billingOverride)&&(identical(other.detail, _this.detail) || other.detail == _this.detail)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.reading, _this.reading) || other.reading == _this.reading)&&(identical(other.stale, _this.stale) || other.stale == _this.stale)&&(identical(other.error, _this.error) || other.error == _this.error)&&const DeepCollectionEquality().equals(other.observationErrors, _this.observationErrors)&&(identical(other.configurationError, _this.configurationError) || other.configurationError == _this.configurationError)&&(identical(other.catalogError, _this.catalogError) || other.catalogError == _this.catalogError));
}


@override
int get hashCode {
  final _this = this as AccountModelDetailsViewState;
  return Object.hash(runtimeType,_this.entry,_this.target,_this.billingOverrideKnown,_this.billingOverride,_this.detail,_this.latestIntent,_this.reading,_this.stale,_this.error,const DeepCollectionEquality().hash(_this.observationErrors),_this.configurationError,_this.catalogError);
}

@override
String toString() {
  final _this = this as AccountModelDetailsViewState;
  return 'AccountModelDetailsViewState(entry: ${_this.entry}, target: ${_this.target}, billingOverrideKnown: ${_this.billingOverrideKnown}, billingOverride: ${_this.billingOverride}, detail: ${_this.detail}, latestIntent: ${_this.latestIntent}, reading: ${_this.reading}, stale: ${_this.stale}, error: ${_this.error}, observationErrors: ${_this.observationErrors}, configurationError: ${_this.configurationError}, catalogError: ${_this.catalogError})';
}


}

/// @nodoc
abstract mixin class $AccountModelDetailsViewStateCopyWith<$Res>  {
  factory $AccountModelDetailsViewStateCopyWith(AccountModelDetailsViewState value, $Res Function(AccountModelDetailsViewState) _then) = _$AccountModelDetailsViewStateCopyWithImpl;
@useResult
$Res call({
 AccountModelDetailsEntry entry, DelegationModelReadTarget? target, bool billingOverrideKnown, BillingKind? billingOverride, DelegationModelDetail? detail, int latestIntent, bool reading, bool stale, StudioFailure? error, List<StudioFailure> observationErrors, StudioFailure? configurationError, StudioFailure? catalogError
});


$AccountModelDetailsEntryCopyWith<$Res> get entry;$DelegationModelReadTargetCopyWith<$Res>? get target;$DelegationModelDetailCopyWith<$Res>? get detail;$StudioFailureCopyWith<$Res>? get error;$StudioFailureCopyWith<$Res>? get configurationError;$StudioFailureCopyWith<$Res>? get catalogError;

}
/// @nodoc
class _$AccountModelDetailsViewStateCopyWithImpl<$Res>
    implements $AccountModelDetailsViewStateCopyWith<$Res> {
  _$AccountModelDetailsViewStateCopyWithImpl(this._self, this._then);

  final AccountModelDetailsViewState _self;
  final $Res Function(AccountModelDetailsViewState) _then;

/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? target = freezed,Object? billingOverrideKnown = null,Object? billingOverride = freezed,Object? detail = freezed,Object? latestIntent = null,Object? reading = null,Object? stale = null,Object? error = freezed,Object? observationErrors = null,Object? configurationError = freezed,Object? catalogError = freezed,}) {
  return _then(AccountModelDetailsViewState(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as AccountModelDetailsEntry,target: freezed == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DelegationModelReadTarget?,billingOverrideKnown: null == billingOverrideKnown ? _self.billingOverrideKnown : billingOverrideKnown // ignore: cast_nullable_to_non_nullable
as bool,billingOverride: freezed == billingOverride ? _self.billingOverride : billingOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as DelegationModelDetail?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as bool,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationErrors: null == observationErrors ? _self.observationErrors : observationErrors // ignore: cast_nullable_to_non_nullable
as List<StudioFailure>,configurationError: freezed == configurationError ? _self.configurationError : configurationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,catalogError: freezed == catalogError ? _self.catalogError : catalogError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelDetailsEntryCopyWith<$Res> get entry {

  return $AccountModelDetailsEntryCopyWith<$Res>(_self.entry, (value) {
    return _then(_self.copyWith(entry: value));
  });
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<$Res>? get target {
    if (_self.target == null) {
    return null;
  }

  return $DelegationModelReadTargetCopyWith<$Res>(_self.target!, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelDetailCopyWith<$Res>? get detail {
    if (_self.detail == null) {
    return null;
  }

  return $DelegationModelDetailCopyWith<$Res>(_self.detail!, (value) {
    return _then(_self.copyWith(detail: value));
  });
}/// Create a copy of AccountModelDetailsViewState
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
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get configurationError {
    if (_self.configurationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.configurationError!, (value) {
    return _then(_self.copyWith(configurationError: value));
  });
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get catalogError {
    if (_self.catalogError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.catalogError!, (value) {
    return _then(_self.copyWith(catalogError: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountModelDetailsViewState].
extension AccountModelDetailsViewStatePatterns on AccountModelDetailsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelDetailsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelDetailsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelDetailsViewState value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelDetailsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelDetailsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelDetailsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountModelDetailsEntry entry,  DelegationModelReadTarget? target,  bool billingOverrideKnown,  BillingKind? billingOverride,  DelegationModelDetail? detail,  int latestIntent,  bool reading,  bool stale,  StudioFailure? error,  List<StudioFailure> observationErrors,  StudioFailure? configurationError,  StudioFailure? catalogError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelDetailsViewState() when $default != null:
return $default(_that.entry,_that.target,_that.billingOverrideKnown,_that.billingOverride,_that.detail,_that.latestIntent,_that.reading,_that.stale,_that.error,_that.observationErrors,_that.configurationError,_that.catalogError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountModelDetailsEntry entry,  DelegationModelReadTarget? target,  bool billingOverrideKnown,  BillingKind? billingOverride,  DelegationModelDetail? detail,  int latestIntent,  bool reading,  bool stale,  StudioFailure? error,  List<StudioFailure> observationErrors,  StudioFailure? configurationError,  StudioFailure? catalogError)  $default,) {final _that = this;
switch (_that) {
case _AccountModelDetailsViewState():
return $default(_that.entry,_that.target,_that.billingOverrideKnown,_that.billingOverride,_that.detail,_that.latestIntent,_that.reading,_that.stale,_that.error,_that.observationErrors,_that.configurationError,_that.catalogError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountModelDetailsEntry entry,  DelegationModelReadTarget? target,  bool billingOverrideKnown,  BillingKind? billingOverride,  DelegationModelDetail? detail,  int latestIntent,  bool reading,  bool stale,  StudioFailure? error,  List<StudioFailure> observationErrors,  StudioFailure? configurationError,  StudioFailure? catalogError)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelDetailsViewState() when $default != null:
return $default(_that.entry,_that.target,_that.billingOverrideKnown,_that.billingOverride,_that.detail,_that.latestIntent,_that.reading,_that.stale,_that.error,_that.observationErrors,_that.configurationError,_that.catalogError);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelDetailsViewState implements AccountModelDetailsViewState {
  const _AccountModelDetailsViewState({required this.entry, required this.target, required this.billingOverrideKnown, required this.billingOverride, this.detail, this.latestIntent = 0, this.reading = false, this.stale = false, this.error,  List<StudioFailure> observationErrors = const [], this.configurationError, this.catalogError}): _observationErrors = observationErrors;


@override final  AccountModelDetailsEntry entry;
@override final  DelegationModelReadTarget? target;
@override final  bool billingOverrideKnown;
@override final  BillingKind? billingOverride;
@override final  DelegationModelDetail? detail;
@override@JsonKey() final  int latestIntent;
@override@JsonKey() final  bool reading;
@override@JsonKey() final  bool stale;
@override final  StudioFailure? error;
 final  List<StudioFailure> _observationErrors;
@override@JsonKey() List<StudioFailure> get observationErrors {
  if (_observationErrors is EqualUnmodifiableListView) return _observationErrors;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_observationErrors);
}

@override final  StudioFailure? configurationError;
@override final  StudioFailure? catalogError;

/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelDetailsViewStateCopyWith<_AccountModelDetailsViewState> get copyWith => __$AccountModelDetailsViewStateCopyWithImpl<_AccountModelDetailsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelDetailsViewState&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.target, target) || other.target == target)&&(identical(other.billingOverrideKnown, billingOverrideKnown) || other.billingOverrideKnown == billingOverrideKnown)&&(identical(other.billingOverride, billingOverride) || other.billingOverride == billingOverride)&&(identical(other.detail, detail) || other.detail == detail)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.reading, reading) || other.reading == reading)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other.observationErrors, _observationErrors)&&(identical(other.configurationError, configurationError) || other.configurationError == configurationError)&&(identical(other.catalogError, catalogError) || other.catalogError == catalogError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,target,billingOverrideKnown,billingOverride,detail,latestIntent,reading,stale,error,const DeepCollectionEquality().hash(_observationErrors),configurationError,catalogError);
}

@override
String toString() {
    return 'AccountModelDetailsViewState(entry: $entry, target: $target, billingOverrideKnown: $billingOverrideKnown, billingOverride: $billingOverride, detail: $detail, latestIntent: $latestIntent, reading: $reading, stale: $stale, error: $error, observationErrors: $observationErrors, configurationError: $configurationError, catalogError: $catalogError)';
}


}

/// @nodoc
abstract mixin class _$AccountModelDetailsViewStateCopyWith<$Res> implements $AccountModelDetailsViewStateCopyWith<$Res> {
  factory _$AccountModelDetailsViewStateCopyWith(_AccountModelDetailsViewState value, $Res Function(_AccountModelDetailsViewState) _then) = __$AccountModelDetailsViewStateCopyWithImpl;
@override @useResult
$Res call({
 AccountModelDetailsEntry entry, DelegationModelReadTarget? target, bool billingOverrideKnown, BillingKind? billingOverride, DelegationModelDetail? detail, int latestIntent, bool reading, bool stale, StudioFailure? error, List<StudioFailure> observationErrors, StudioFailure? configurationError, StudioFailure? catalogError
});


@override $AccountModelDetailsEntryCopyWith<$Res> get entry;@override $DelegationModelReadTargetCopyWith<$Res>? get target;@override $DelegationModelDetailCopyWith<$Res>? get detail;@override $StudioFailureCopyWith<$Res>? get error;@override $StudioFailureCopyWith<$Res>? get configurationError;@override $StudioFailureCopyWith<$Res>? get catalogError;

}
/// @nodoc
class __$AccountModelDetailsViewStateCopyWithImpl<$Res>
    implements _$AccountModelDetailsViewStateCopyWith<$Res> {
  __$AccountModelDetailsViewStateCopyWithImpl(this._self, this._then);

  final _AccountModelDetailsViewState _self;
  final $Res Function(_AccountModelDetailsViewState) _then;

/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? target = freezed,Object? billingOverrideKnown = null,Object? billingOverride = freezed,Object? detail = freezed,Object? latestIntent = null,Object? reading = null,Object? stale = null,Object? error = freezed,Object? observationErrors = null,Object? configurationError = freezed,Object? catalogError = freezed,}) {
  return _then(_AccountModelDetailsViewState(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as AccountModelDetailsEntry,target: freezed == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as DelegationModelReadTarget?,billingOverrideKnown: null == billingOverrideKnown ? _self.billingOverrideKnown : billingOverrideKnown // ignore: cast_nullable_to_non_nullable
as bool,billingOverride: freezed == billingOverride ? _self.billingOverride : billingOverride // ignore: cast_nullable_to_non_nullable
as BillingKind?,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as DelegationModelDetail?,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,reading: null == reading ? _self.reading : reading // ignore: cast_nullable_to_non_nullable
as bool,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,observationErrors: null == observationErrors ? _self._observationErrors : observationErrors // ignore: cast_nullable_to_non_nullable
as List<StudioFailure>,configurationError: freezed == configurationError ? _self.configurationError : configurationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,catalogError: freezed == catalogError ? _self.catalogError : catalogError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelDetailsEntryCopyWith<$Res> get entry {

  return $AccountModelDetailsEntryCopyWith<$Res>(_self.entry, (value) {
    return _then(_self.copyWith(entry: value));
  });
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelReadTargetCopyWith<$Res>? get target {
    if (_self.target == null) {
    return null;
  }

  return $DelegationModelReadTargetCopyWith<$Res>(_self.target!, (value) {
    return _then(_self.copyWith(target: value));
  });
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DelegationModelDetailCopyWith<$Res>? get detail {
    if (_self.detail == null) {
    return null;
  }

  return $DelegationModelDetailCopyWith<$Res>(_self.detail!, (value) {
    return _then(_self.copyWith(detail: value));
  });
}/// Create a copy of AccountModelDetailsViewState
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
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get configurationError {
    if (_self.configurationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.configurationError!, (value) {
    return _then(_self.copyWith(configurationError: value));
  });
}/// Create a copy of AccountModelDetailsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get catalogError {
    if (_self.catalogError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.catalogError!, (value) {
    return _then(_self.copyWith(catalogError: value));
  });
}
}

// dart format on
