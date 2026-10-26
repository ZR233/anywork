// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metrics_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadMetricsValue {

 LiveTurnMetrics? get live; AuthoritativeTurnMetrics? get authoritative;
/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsValueCopyWith<ThreadMetricsValue> get copyWith => _$ThreadMetricsValueCopyWithImpl<ThreadMetricsValue>(this as ThreadMetricsValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMetricsValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsValue&&(identical(other.live, _this.live) || other.live == _this.live)&&(identical(other.authoritative, _this.authoritative) || other.authoritative == _this.authoritative));
}


@override
int get hashCode {
  final _this = this as ThreadMetricsValue;
  return Object.hash(runtimeType,_this.live,_this.authoritative);
}

@override
String toString() {
  final _this = this as ThreadMetricsValue;
  return 'ThreadMetricsValue(live: ${_this.live}, authoritative: ${_this.authoritative})';
}


}

/// @nodoc
abstract mixin class $ThreadMetricsValueCopyWith<$Res>  {
  factory $ThreadMetricsValueCopyWith(ThreadMetricsValue value, $Res Function(ThreadMetricsValue) _then) = _$ThreadMetricsValueCopyWithImpl;
@useResult
$Res call({
 LiveTurnMetrics? live, AuthoritativeTurnMetrics? authoritative
});


$LiveTurnMetricsCopyWith<$Res>? get live;$AuthoritativeTurnMetricsCopyWith<$Res>? get authoritative;

}
/// @nodoc
class _$ThreadMetricsValueCopyWithImpl<$Res>
    implements $ThreadMetricsValueCopyWith<$Res> {
  _$ThreadMetricsValueCopyWithImpl(this._self, this._then);

  final ThreadMetricsValue _self;
  final $Res Function(ThreadMetricsValue) _then;

/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? live = freezed,Object? authoritative = freezed,}) {
  return _then(ThreadMetricsValue(
live: freezed == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as LiveTurnMetrics?,authoritative: freezed == authoritative ? _self.authoritative : authoritative // ignore: cast_nullable_to_non_nullable
as AuthoritativeTurnMetrics?,
  ));
}
/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveTurnMetricsCopyWith<$Res>? get live {
    if (_self.live == null) {
    return null;
  }

  return $LiveTurnMetricsCopyWith<$Res>(_self.live!, (value) {
    return _then(_self.copyWith(live: value));
  });
}/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AuthoritativeTurnMetricsCopyWith<$Res>? get authoritative {
    if (_self.authoritative == null) {
    return null;
  }

  return $AuthoritativeTurnMetricsCopyWith<$Res>(_self.authoritative!, (value) {
    return _then(_self.copyWith(authoritative: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadMetricsValue].
extension ThreadMetricsValuePatterns on ThreadMetricsValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadMetricsValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadMetricsValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadMetricsValue value)  $default,){
final _that = this;
switch (_that) {
case _ThreadMetricsValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadMetricsValue value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadMetricsValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LiveTurnMetrics? live,  AuthoritativeTurnMetrics? authoritative)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadMetricsValue() when $default != null:
return $default(_that.live,_that.authoritative);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LiveTurnMetrics? live,  AuthoritativeTurnMetrics? authoritative)  $default,) {final _that = this;
switch (_that) {
case _ThreadMetricsValue():
return $default(_that.live,_that.authoritative);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LiveTurnMetrics? live,  AuthoritativeTurnMetrics? authoritative)?  $default,) {final _that = this;
switch (_that) {
case _ThreadMetricsValue() when $default != null:
return $default(_that.live,_that.authoritative);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadMetricsValue implements ThreadMetricsValue {
  const _ThreadMetricsValue({required this.live, required this.authoritative});


@override final  LiveTurnMetrics? live;
@override final  AuthoritativeTurnMetrics? authoritative;

/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadMetricsValueCopyWith<_ThreadMetricsValue> get copyWith => __$ThreadMetricsValueCopyWithImpl<_ThreadMetricsValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadMetricsValue&&(identical(other.live, live) || other.live == live)&&(identical(other.authoritative, authoritative) || other.authoritative == authoritative));
}


@override
int get hashCode {
    return Object.hash(runtimeType,live,authoritative);
}

@override
String toString() {
    return 'ThreadMetricsValue(live: $live, authoritative: $authoritative)';
}


}

/// @nodoc
abstract mixin class _$ThreadMetricsValueCopyWith<$Res> implements $ThreadMetricsValueCopyWith<$Res> {
  factory _$ThreadMetricsValueCopyWith(_ThreadMetricsValue value, $Res Function(_ThreadMetricsValue) _then) = __$ThreadMetricsValueCopyWithImpl;
@override @useResult
$Res call({
 LiveTurnMetrics? live, AuthoritativeTurnMetrics? authoritative
});


@override $LiveTurnMetricsCopyWith<$Res>? get live;@override $AuthoritativeTurnMetricsCopyWith<$Res>? get authoritative;

}
/// @nodoc
class __$ThreadMetricsValueCopyWithImpl<$Res>
    implements _$ThreadMetricsValueCopyWith<$Res> {
  __$ThreadMetricsValueCopyWithImpl(this._self, this._then);

  final _ThreadMetricsValue _self;
  final $Res Function(_ThreadMetricsValue) _then;

/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? live = freezed,Object? authoritative = freezed,}) {
  return _then(_ThreadMetricsValue(
live: freezed == live ? _self.live : live // ignore: cast_nullable_to_non_nullable
as LiveTurnMetrics?,authoritative: freezed == authoritative ? _self.authoritative : authoritative // ignore: cast_nullable_to_non_nullable
as AuthoritativeTurnMetrics?,
  ));
}

/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LiveTurnMetricsCopyWith<$Res>? get live {
    if (_self.live == null) {
    return null;
  }

  return $LiveTurnMetricsCopyWith<$Res>(_self.live!, (value) {
    return _then(_self.copyWith(live: value));
  });
}/// Create a copy of ThreadMetricsValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AuthoritativeTurnMetricsCopyWith<$Res>? get authoritative {
    if (_self.authoritative == null) {
    return null;
  }

  return $AuthoritativeTurnMetricsCopyWith<$Res>(_self.authoritative!, (value) {
    return _then(_self.copyWith(authoritative: value));
  });
}
}

/// @nodoc
mixin _$LiveTurnMetrics {

 MetricsIdentityRef get identity; int? get completionTokens; int? get responseMillis; TurnObservationState get state; int get observationSequence;
/// Create a copy of LiveTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LiveTurnMetricsCopyWith<LiveTurnMetrics> get copyWith => _$LiveTurnMetricsCopyWithImpl<LiveTurnMetrics>(this as LiveTurnMetrics, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LiveTurnMetrics;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LiveTurnMetrics&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.responseMillis, _this.responseMillis) || other.responseMillis == _this.responseMillis)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.observationSequence, _this.observationSequence) || other.observationSequence == _this.observationSequence));
}


@override
int get hashCode {
  final _this = this as LiveTurnMetrics;
  return Object.hash(runtimeType,_this.identity,_this.completionTokens,_this.responseMillis,_this.state,_this.observationSequence);
}

@override
String toString() {
  final _this = this as LiveTurnMetrics;
  return 'LiveTurnMetrics(identity: ${_this.identity}, completionTokens: ${_this.completionTokens}, responseMillis: ${_this.responseMillis}, state: ${_this.state}, observationSequence: ${_this.observationSequence})';
}


}

/// @nodoc
abstract mixin class $LiveTurnMetricsCopyWith<$Res>  {
  factory $LiveTurnMetricsCopyWith(LiveTurnMetrics value, $Res Function(LiveTurnMetrics) _then) = _$LiveTurnMetricsCopyWithImpl;
@useResult
$Res call({
 MetricsIdentityRef identity, int? completionTokens, int? responseMillis, TurnObservationState state, int observationSequence
});


$MetricsIdentityRefCopyWith<$Res> get identity;

}
/// @nodoc
class _$LiveTurnMetricsCopyWithImpl<$Res>
    implements $LiveTurnMetricsCopyWith<$Res> {
  _$LiveTurnMetricsCopyWithImpl(this._self, this._then);

  final LiveTurnMetrics _self;
  final $Res Function(LiveTurnMetrics) _then;

/// Create a copy of LiveTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? completionTokens = freezed,Object? responseMillis = freezed,Object? state = null,Object? observationSequence = null,}) {
  return _then(LiveTurnMetrics(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as MetricsIdentityRef,completionTokens: freezed == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int?,responseMillis: freezed == responseMillis ? _self.responseMillis : responseMillis // ignore: cast_nullable_to_non_nullable
as int?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnObservationState,observationSequence: null == observationSequence ? _self.observationSequence : observationSequence // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of LiveTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetricsIdentityRefCopyWith<$Res> get identity {

  return $MetricsIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}


/// Adds pattern-matching-related methods to [LiveTurnMetrics].
extension LiveTurnMetricsPatterns on LiveTurnMetrics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LiveTurnMetrics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LiveTurnMetrics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LiveTurnMetrics value)  $default,){
final _that = this;
switch (_that) {
case _LiveTurnMetrics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LiveTurnMetrics value)?  $default,){
final _that = this;
switch (_that) {
case _LiveTurnMetrics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( MetricsIdentityRef identity,  int? completionTokens,  int? responseMillis,  TurnObservationState state,  int observationSequence)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LiveTurnMetrics() when $default != null:
return $default(_that.identity,_that.completionTokens,_that.responseMillis,_that.state,_that.observationSequence);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( MetricsIdentityRef identity,  int? completionTokens,  int? responseMillis,  TurnObservationState state,  int observationSequence)  $default,) {final _that = this;
switch (_that) {
case _LiveTurnMetrics():
return $default(_that.identity,_that.completionTokens,_that.responseMillis,_that.state,_that.observationSequence);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( MetricsIdentityRef identity,  int? completionTokens,  int? responseMillis,  TurnObservationState state,  int observationSequence)?  $default,) {final _that = this;
switch (_that) {
case _LiveTurnMetrics() when $default != null:
return $default(_that.identity,_that.completionTokens,_that.responseMillis,_that.state,_that.observationSequence);case _:
  return null;

}
}

}

/// @nodoc


class _LiveTurnMetrics implements LiveTurnMetrics {
  const _LiveTurnMetrics({required this.identity, required this.completionTokens, required this.responseMillis, required this.state, required this.observationSequence});


@override final  MetricsIdentityRef identity;
@override final  int? completionTokens;
@override final  int? responseMillis;
@override final  TurnObservationState state;
@override final  int observationSequence;

/// Create a copy of LiveTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LiveTurnMetricsCopyWith<_LiveTurnMetrics> get copyWith => __$LiveTurnMetricsCopyWithImpl<_LiveTurnMetrics>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LiveTurnMetrics&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.responseMillis, responseMillis) || other.responseMillis == responseMillis)&&(identical(other.state, state) || other.state == state)&&(identical(other.observationSequence, observationSequence) || other.observationSequence == observationSequence));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,completionTokens,responseMillis,state,observationSequence);
}

@override
String toString() {
    return 'LiveTurnMetrics(identity: $identity, completionTokens: $completionTokens, responseMillis: $responseMillis, state: $state, observationSequence: $observationSequence)';
}


}

/// @nodoc
abstract mixin class _$LiveTurnMetricsCopyWith<$Res> implements $LiveTurnMetricsCopyWith<$Res> {
  factory _$LiveTurnMetricsCopyWith(_LiveTurnMetrics value, $Res Function(_LiveTurnMetrics) _then) = __$LiveTurnMetricsCopyWithImpl;
@override @useResult
$Res call({
 MetricsIdentityRef identity, int? completionTokens, int? responseMillis, TurnObservationState state, int observationSequence
});


@override $MetricsIdentityRefCopyWith<$Res> get identity;

}
/// @nodoc
class __$LiveTurnMetricsCopyWithImpl<$Res>
    implements _$LiveTurnMetricsCopyWith<$Res> {
  __$LiveTurnMetricsCopyWithImpl(this._self, this._then);

  final _LiveTurnMetrics _self;
  final $Res Function(_LiveTurnMetrics) _then;

/// Create a copy of LiveTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? completionTokens = freezed,Object? responseMillis = freezed,Object? state = null,Object? observationSequence = null,}) {
  return _then(_LiveTurnMetrics(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as MetricsIdentityRef,completionTokens: freezed == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int?,responseMillis: freezed == responseMillis ? _self.responseMillis : responseMillis // ignore: cast_nullable_to_non_nullable
as int?,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnObservationState,observationSequence: null == observationSequence ? _self.observationSequence : observationSequence // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of LiveTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetricsIdentityRefCopyWith<$Res> get identity {

  return $MetricsIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc
mixin _$AuthoritativeTurnMetrics {

 MetricsIdentityRef get identity; int get completionTokens; int get responseMillis;
/// Create a copy of AuthoritativeTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthoritativeTurnMetricsCopyWith<AuthoritativeTurnMetrics> get copyWith => _$AuthoritativeTurnMetricsCopyWithImpl<AuthoritativeTurnMetrics>(this as AuthoritativeTurnMetrics, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AuthoritativeTurnMetrics;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthoritativeTurnMetrics&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.responseMillis, _this.responseMillis) || other.responseMillis == _this.responseMillis));
}


@override
int get hashCode {
  final _this = this as AuthoritativeTurnMetrics;
  return Object.hash(runtimeType,_this.identity,_this.completionTokens,_this.responseMillis);
}

@override
String toString() {
  final _this = this as AuthoritativeTurnMetrics;
  return 'AuthoritativeTurnMetrics(identity: ${_this.identity}, completionTokens: ${_this.completionTokens}, responseMillis: ${_this.responseMillis})';
}


}

/// @nodoc
abstract mixin class $AuthoritativeTurnMetricsCopyWith<$Res>  {
  factory $AuthoritativeTurnMetricsCopyWith(AuthoritativeTurnMetrics value, $Res Function(AuthoritativeTurnMetrics) _then) = _$AuthoritativeTurnMetricsCopyWithImpl;
@useResult
$Res call({
 MetricsIdentityRef identity, int completionTokens, int responseMillis
});


$MetricsIdentityRefCopyWith<$Res> get identity;

}
/// @nodoc
class _$AuthoritativeTurnMetricsCopyWithImpl<$Res>
    implements $AuthoritativeTurnMetricsCopyWith<$Res> {
  _$AuthoritativeTurnMetricsCopyWithImpl(this._self, this._then);

  final AuthoritativeTurnMetrics _self;
  final $Res Function(AuthoritativeTurnMetrics) _then;

/// Create a copy of AuthoritativeTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? identity = null,Object? completionTokens = null,Object? responseMillis = null,}) {
  return _then(AuthoritativeTurnMetrics(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as MetricsIdentityRef,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,responseMillis: null == responseMillis ? _self.responseMillis : responseMillis // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AuthoritativeTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetricsIdentityRefCopyWith<$Res> get identity {

  return $MetricsIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}


/// Adds pattern-matching-related methods to [AuthoritativeTurnMetrics].
extension AuthoritativeTurnMetricsPatterns on AuthoritativeTurnMetrics {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AuthoritativeTurnMetrics value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AuthoritativeTurnMetrics() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AuthoritativeTurnMetrics value)  $default,){
final _that = this;
switch (_that) {
case _AuthoritativeTurnMetrics():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AuthoritativeTurnMetrics value)?  $default,){
final _that = this;
switch (_that) {
case _AuthoritativeTurnMetrics() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( MetricsIdentityRef identity,  int completionTokens,  int responseMillis)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AuthoritativeTurnMetrics() when $default != null:
return $default(_that.identity,_that.completionTokens,_that.responseMillis);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( MetricsIdentityRef identity,  int completionTokens,  int responseMillis)  $default,) {final _that = this;
switch (_that) {
case _AuthoritativeTurnMetrics():
return $default(_that.identity,_that.completionTokens,_that.responseMillis);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( MetricsIdentityRef identity,  int completionTokens,  int responseMillis)?  $default,) {final _that = this;
switch (_that) {
case _AuthoritativeTurnMetrics() when $default != null:
return $default(_that.identity,_that.completionTokens,_that.responseMillis);case _:
  return null;

}
}

}

/// @nodoc


class _AuthoritativeTurnMetrics implements AuthoritativeTurnMetrics {
  const _AuthoritativeTurnMetrics({required this.identity, required this.completionTokens, required this.responseMillis});


@override final  MetricsIdentityRef identity;
@override final  int completionTokens;
@override final  int responseMillis;

/// Create a copy of AuthoritativeTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AuthoritativeTurnMetricsCopyWith<_AuthoritativeTurnMetrics> get copyWith => __$AuthoritativeTurnMetricsCopyWithImpl<_AuthoritativeTurnMetrics>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AuthoritativeTurnMetrics&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.responseMillis, responseMillis) || other.responseMillis == responseMillis));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,completionTokens,responseMillis);
}

@override
String toString() {
    return 'AuthoritativeTurnMetrics(identity: $identity, completionTokens: $completionTokens, responseMillis: $responseMillis)';
}


}

/// @nodoc
abstract mixin class _$AuthoritativeTurnMetricsCopyWith<$Res> implements $AuthoritativeTurnMetricsCopyWith<$Res> {
  factory _$AuthoritativeTurnMetricsCopyWith(_AuthoritativeTurnMetrics value, $Res Function(_AuthoritativeTurnMetrics) _then) = __$AuthoritativeTurnMetricsCopyWithImpl;
@override @useResult
$Res call({
 MetricsIdentityRef identity, int completionTokens, int responseMillis
});


@override $MetricsIdentityRefCopyWith<$Res> get identity;

}
/// @nodoc
class __$AuthoritativeTurnMetricsCopyWithImpl<$Res>
    implements _$AuthoritativeTurnMetricsCopyWith<$Res> {
  __$AuthoritativeTurnMetricsCopyWithImpl(this._self, this._then);

  final _AuthoritativeTurnMetrics _self;
  final $Res Function(_AuthoritativeTurnMetrics) _then;

/// Create a copy of AuthoritativeTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? completionTokens = null,Object? responseMillis = null,}) {
  return _then(_AuthoritativeTurnMetrics(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as MetricsIdentityRef,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,responseMillis: null == responseMillis ? _self.responseMillis : responseMillis // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AuthoritativeTurnMetrics
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MetricsIdentityRefCopyWith<$Res> get identity {

  return $MetricsIdentityRefCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

// dart format on
