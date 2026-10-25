// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'turn_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RetryDisposition {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryDisposition);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RetryDisposition()';
}


}

/// @nodoc
class $RetryDispositionCopyWith<$Res>  {
$RetryDispositionCopyWith(RetryDisposition _, $Res Function(RetryDisposition) __);
}


/// Adds pattern-matching-related methods to [RetryDisposition].
extension RetryDispositionPatterns on RetryDisposition {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RetryableDisposition value)?  retryable,TResult Function( PermanentRetryDisposition value)?  permanent,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RetryableDisposition() when retryable != null:
return retryable(_that);case PermanentRetryDisposition() when permanent != null:
return permanent(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RetryableDisposition value)  retryable,required TResult Function( PermanentRetryDisposition value)  permanent,}){
final _that = this;
switch (_that) {
case RetryableDisposition():
return retryable(_that);case PermanentRetryDisposition():
return permanent(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RetryableDisposition value)?  retryable,TResult? Function( PermanentRetryDisposition value)?  permanent,}){
final _that = this;
switch (_that) {
case RetryableDisposition() when retryable != null:
return retryable(_that);case PermanentRetryDisposition() when permanent != null:
return permanent(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int? retryAfterMs)?  retryable,TResult Function()?  permanent,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RetryableDisposition() when retryable != null:
return retryable(_that.retryAfterMs);case PermanentRetryDisposition() when permanent != null:
return permanent();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int? retryAfterMs)  retryable,required TResult Function()  permanent,}) {final _that = this;
switch (_that) {
case RetryableDisposition():
return retryable(_that.retryAfterMs);case PermanentRetryDisposition():
return permanent();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int? retryAfterMs)?  retryable,TResult? Function()?  permanent,}) {final _that = this;
switch (_that) {
case RetryableDisposition() when retryable != null:
return retryable(_that.retryAfterMs);case PermanentRetryDisposition() when permanent != null:
return permanent();case _:
  return null;

}
}

}

/// @nodoc


class RetryableDisposition implements RetryDisposition {
  const RetryableDisposition({required this.retryAfterMs});


 final  int? retryAfterMs;

/// Create a copy of RetryDisposition
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RetryableDispositionCopyWith<RetryableDisposition> get copyWith => _$RetryableDispositionCopyWithImpl<RetryableDisposition>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RetryableDisposition&&(identical(other.retryAfterMs, retryAfterMs) || other.retryAfterMs == retryAfterMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,retryAfterMs);
}

@override
String toString() {
    return 'RetryDisposition.retryable(retryAfterMs: $retryAfterMs)';
}


}

/// @nodoc
abstract mixin class $RetryableDispositionCopyWith<$Res> implements $RetryDispositionCopyWith<$Res> {
  factory $RetryableDispositionCopyWith(RetryableDisposition value, $Res Function(RetryableDisposition) _then) = _$RetryableDispositionCopyWithImpl;
@useResult
$Res call({
 int? retryAfterMs
});




}
/// @nodoc
class _$RetryableDispositionCopyWithImpl<$Res>
    implements $RetryableDispositionCopyWith<$Res> {
  _$RetryableDispositionCopyWithImpl(this._self, this._then);

  final RetryableDisposition _self;
  final $Res Function(RetryableDisposition) _then;

/// Create a copy of RetryDisposition
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? retryAfterMs = freezed,}) {
  return _then(RetryableDisposition(
retryAfterMs: freezed == retryAfterMs ? _self.retryAfterMs : retryAfterMs // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class PermanentRetryDisposition implements RetryDisposition {
  const PermanentRetryDisposition();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PermanentRetryDisposition);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RetryDisposition.permanent()';
}


}




/// @nodoc
mixin _$TurnBrief {

 TurnReadRef get reference; int get revision; int get updatedAt; TurnBriefState get state;
/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnBriefCopyWith<TurnBrief> get copyWith => _$TurnBriefCopyWithImpl<TurnBrief>(this as TurnBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TurnBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnBrief&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as TurnBrief;
  return Object.hash(runtimeType,_this.reference,_this.revision,_this.updatedAt,_this.state);
}

@override
String toString() {
  final _this = this as TurnBrief;
  return 'TurnBrief(reference: ${_this.reference}, revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, state: ${_this.state})';
}


}

/// @nodoc
abstract mixin class $TurnBriefCopyWith<$Res>  {
  factory $TurnBriefCopyWith(TurnBrief value, $Res Function(TurnBrief) _then) = _$TurnBriefCopyWithImpl;
@useResult
$Res call({
 TurnReadRef reference, int revision, int updatedAt, TurnBriefState state
});


$TurnReadRefCopyWith<$Res> get reference;$TurnBriefStateCopyWith<$Res> get state;

}
/// @nodoc
class _$TurnBriefCopyWithImpl<$Res>
    implements $TurnBriefCopyWith<$Res> {
  _$TurnBriefCopyWithImpl(this._self, this._then);

  final TurnBrief _self;
  final $Res Function(TurnBrief) _then;

/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? revision = null,Object? updatedAt = null,Object? state = null,}) {
  return _then(TurnBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as TurnReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnBriefState,
  ));
}
/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnReadRefCopyWith<$Res> get reference {

  return $TurnReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefStateCopyWith<$Res> get state {

  return $TurnBriefStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [TurnBrief].
extension TurnBriefPatterns on TurnBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnBrief value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnBrief() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnBrief value)  $default,){
final _that = this;
switch (_that) {
case _TurnBrief():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnBrief value)?  $default,){
final _that = this;
switch (_that) {
case _TurnBrief() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TurnReadRef reference,  int revision,  int updatedAt,  TurnBriefState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.updatedAt,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TurnReadRef reference,  int revision,  int updatedAt,  TurnBriefState state)  $default,) {final _that = this;
switch (_that) {
case _TurnBrief():
return $default(_that.reference,_that.revision,_that.updatedAt,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TurnReadRef reference,  int revision,  int updatedAt,  TurnBriefState state)?  $default,) {final _that = this;
switch (_that) {
case _TurnBrief() when $default != null:
return $default(_that.reference,_that.revision,_that.updatedAt,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _TurnBrief implements TurnBrief {
  const _TurnBrief({required this.reference, required this.revision, required this.updatedAt, required this.state});


@override final  TurnReadRef reference;
@override final  int revision;
@override final  int updatedAt;
@override final  TurnBriefState state;

/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnBriefCopyWith<_TurnBrief> get copyWith => __$TurnBriefCopyWithImpl<_TurnBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnBrief&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,revision,updatedAt,state);
}

@override
String toString() {
    return 'TurnBrief(reference: $reference, revision: $revision, updatedAt: $updatedAt, state: $state)';
}


}

/// @nodoc
abstract mixin class _$TurnBriefCopyWith<$Res> implements $TurnBriefCopyWith<$Res> {
  factory _$TurnBriefCopyWith(_TurnBrief value, $Res Function(_TurnBrief) _then) = __$TurnBriefCopyWithImpl;
@override @useResult
$Res call({
 TurnReadRef reference, int revision, int updatedAt, TurnBriefState state
});


@override $TurnReadRefCopyWith<$Res> get reference;@override $TurnBriefStateCopyWith<$Res> get state;

}
/// @nodoc
class __$TurnBriefCopyWithImpl<$Res>
    implements _$TurnBriefCopyWith<$Res> {
  __$TurnBriefCopyWithImpl(this._self, this._then);

  final _TurnBrief _self;
  final $Res Function(_TurnBrief) _then;

/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? revision = null,Object? updatedAt = null,Object? state = null,}) {
  return _then(_TurnBrief(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as TurnReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnBriefState,
  ));
}

/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnReadRefCopyWith<$Res> get reference {

  return $TurnReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of TurnBrief
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnBriefStateCopyWith<$Res> get state {

  return $TurnBriefStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$TurnBriefState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnBriefState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TurnBriefState()';
}


}

/// @nodoc
class $TurnBriefStateCopyWith<$Res>  {
$TurnBriefStateCopyWith(TurnBriefState _, $Res Function(TurnBriefState) __);
}


/// Adds pattern-matching-related methods to [TurnBriefState].
extension TurnBriefStatePatterns on TurnBriefState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QueuedTurnBrief value)?  queued,TResult Function( RunningTurnBrief value)?  running,TResult Function( CompletedTurnBrief value)?  completed,TResult Function( CancelledTurnBrief value)?  cancelled,TResult Function( FailedTurnBrief value)?  failed,TResult Function( BudgetLimitedTurnBrief value)?  budgetLimited,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QueuedTurnBrief() when queued != null:
return queued(_that);case RunningTurnBrief() when running != null:
return running(_that);case CompletedTurnBrief() when completed != null:
return completed(_that);case CancelledTurnBrief() when cancelled != null:
return cancelled(_that);case FailedTurnBrief() when failed != null:
return failed(_that);case BudgetLimitedTurnBrief() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QueuedTurnBrief value)  queued,required TResult Function( RunningTurnBrief value)  running,required TResult Function( CompletedTurnBrief value)  completed,required TResult Function( CancelledTurnBrief value)  cancelled,required TResult Function( FailedTurnBrief value)  failed,required TResult Function( BudgetLimitedTurnBrief value)  budgetLimited,}){
final _that = this;
switch (_that) {
case QueuedTurnBrief():
return queued(_that);case RunningTurnBrief():
return running(_that);case CompletedTurnBrief():
return completed(_that);case CancelledTurnBrief():
return cancelled(_that);case FailedTurnBrief():
return failed(_that);case BudgetLimitedTurnBrief():
return budgetLimited(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QueuedTurnBrief value)?  queued,TResult? Function( RunningTurnBrief value)?  running,TResult? Function( CompletedTurnBrief value)?  completed,TResult? Function( CancelledTurnBrief value)?  cancelled,TResult? Function( FailedTurnBrief value)?  failed,TResult? Function( BudgetLimitedTurnBrief value)?  budgetLimited,}){
final _that = this;
switch (_that) {
case QueuedTurnBrief() when queued != null:
return queued(_that);case RunningTurnBrief() when running != null:
return running(_that);case CompletedTurnBrief() when completed != null:
return completed(_that);case CancelledTurnBrief() when cancelled != null:
return cancelled(_that);case FailedTurnBrief() when failed != null:
return failed(_that);case BudgetLimitedTurnBrief() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int queuedAt)?  queued,TResult Function( int startedAt,  TurnPhase phase)?  running,TResult Function( int? startedAt,  int completedAt,  TurnCompletion completion)?  completed,TResult Function( int? startedAt,  int requestedAt,  int completedAt,  TurnCancellationKind cause)?  cancelled,TResult Function( int? startedAt,  int completedAt,  TurnFailureCategory category,  ProviderFailureKind? providerKind,  int? httpStatus,  RetryDisposition retry)?  failed,TResult Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnRolloverKind rollover)?  budgetLimited,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QueuedTurnBrief() when queued != null:
return queued(_that.queuedAt);case RunningTurnBrief() when running != null:
return running(_that.startedAt,_that.phase);case CompletedTurnBrief() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurnBrief() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurnBrief() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.category,_that.providerKind,_that.httpStatus,_that.retry);case BudgetLimitedTurnBrief() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int queuedAt)  queued,required TResult Function( int startedAt,  TurnPhase phase)  running,required TResult Function( int? startedAt,  int completedAt,  TurnCompletion completion)  completed,required TResult Function( int? startedAt,  int requestedAt,  int completedAt,  TurnCancellationKind cause)  cancelled,required TResult Function( int? startedAt,  int completedAt,  TurnFailureCategory category,  ProviderFailureKind? providerKind,  int? httpStatus,  RetryDisposition retry)  failed,required TResult Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnRolloverKind rollover)  budgetLimited,}) {final _that = this;
switch (_that) {
case QueuedTurnBrief():
return queued(_that.queuedAt);case RunningTurnBrief():
return running(_that.startedAt,_that.phase);case CompletedTurnBrief():
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurnBrief():
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurnBrief():
return failed(_that.startedAt,_that.completedAt,_that.category,_that.providerKind,_that.httpStatus,_that.retry);case BudgetLimitedTurnBrief():
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int queuedAt)?  queued,TResult? Function( int startedAt,  TurnPhase phase)?  running,TResult? Function( int? startedAt,  int completedAt,  TurnCompletion completion)?  completed,TResult? Function( int? startedAt,  int requestedAt,  int completedAt,  TurnCancellationKind cause)?  cancelled,TResult? Function( int? startedAt,  int completedAt,  TurnFailureCategory category,  ProviderFailureKind? providerKind,  int? httpStatus,  RetryDisposition retry)?  failed,TResult? Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnRolloverKind rollover)?  budgetLimited,}) {final _that = this;
switch (_that) {
case QueuedTurnBrief() when queued != null:
return queued(_that.queuedAt);case RunningTurnBrief() when running != null:
return running(_that.startedAt,_that.phase);case CompletedTurnBrief() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurnBrief() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurnBrief() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.category,_that.providerKind,_that.httpStatus,_that.retry);case BudgetLimitedTurnBrief() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
  return null;

}
}

}

/// @nodoc


class QueuedTurnBrief implements TurnBriefState {
  const QueuedTurnBrief({required this.queuedAt});


 final  int queuedAt;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueuedTurnBriefCopyWith<QueuedTurnBrief> get copyWith => _$QueuedTurnBriefCopyWithImpl<QueuedTurnBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedTurnBrief&&(identical(other.queuedAt, queuedAt) || other.queuedAt == queuedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,queuedAt);
}

@override
String toString() {
    return 'TurnBriefState.queued(queuedAt: $queuedAt)';
}


}

/// @nodoc
abstract mixin class $QueuedTurnBriefCopyWith<$Res> implements $TurnBriefStateCopyWith<$Res> {
  factory $QueuedTurnBriefCopyWith(QueuedTurnBrief value, $Res Function(QueuedTurnBrief) _then) = _$QueuedTurnBriefCopyWithImpl;
@useResult
$Res call({
 int queuedAt
});




}
/// @nodoc
class _$QueuedTurnBriefCopyWithImpl<$Res>
    implements $QueuedTurnBriefCopyWith<$Res> {
  _$QueuedTurnBriefCopyWithImpl(this._self, this._then);

  final QueuedTurnBrief _self;
  final $Res Function(QueuedTurnBrief) _then;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? queuedAt = null,}) {
  return _then(QueuedTurnBrief(
queuedAt: null == queuedAt ? _self.queuedAt : queuedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RunningTurnBrief implements TurnBriefState {
  const RunningTurnBrief({required this.startedAt, required this.phase});


 final  int startedAt;
 final  TurnPhase phase;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RunningTurnBriefCopyWith<RunningTurnBrief> get copyWith => _$RunningTurnBriefCopyWithImpl<RunningTurnBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningTurnBrief&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,phase);
}

@override
String toString() {
    return 'TurnBriefState.running(startedAt: $startedAt, phase: $phase)';
}


}

/// @nodoc
abstract mixin class $RunningTurnBriefCopyWith<$Res> implements $TurnBriefStateCopyWith<$Res> {
  factory $RunningTurnBriefCopyWith(RunningTurnBrief value, $Res Function(RunningTurnBrief) _then) = _$RunningTurnBriefCopyWithImpl;
@useResult
$Res call({
 int startedAt, TurnPhase phase
});




}
/// @nodoc
class _$RunningTurnBriefCopyWithImpl<$Res>
    implements $RunningTurnBriefCopyWith<$Res> {
  _$RunningTurnBriefCopyWithImpl(this._self, this._then);

  final RunningTurnBrief _self;
  final $Res Function(RunningTurnBrief) _then;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = null,Object? phase = null,}) {
  return _then(RunningTurnBrief(
startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as TurnPhase,
  ));
}


}

/// @nodoc


class CompletedTurnBrief implements TurnBriefState {
  const CompletedTurnBrief({required this.startedAt, required this.completedAt, required this.completion});


 final  int? startedAt;
 final  int completedAt;
 final  TurnCompletion completion;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompletedTurnBriefCopyWith<CompletedTurnBrief> get copyWith => _$CompletedTurnBriefCopyWithImpl<CompletedTurnBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletedTurnBrief&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completion, completion) || other.completion == completion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,completion);
}

@override
String toString() {
    return 'TurnBriefState.completed(startedAt: $startedAt, completedAt: $completedAt, completion: $completion)';
}


}

/// @nodoc
abstract mixin class $CompletedTurnBriefCopyWith<$Res> implements $TurnBriefStateCopyWith<$Res> {
  factory $CompletedTurnBriefCopyWith(CompletedTurnBrief value, $Res Function(CompletedTurnBrief) _then) = _$CompletedTurnBriefCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, TurnCompletion completion
});




}
/// @nodoc
class _$CompletedTurnBriefCopyWithImpl<$Res>
    implements $CompletedTurnBriefCopyWith<$Res> {
  _$CompletedTurnBriefCopyWithImpl(this._self, this._then);

  final CompletedTurnBrief _self;
  final $Res Function(CompletedTurnBrief) _then;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? completion = null,}) {
  return _then(CompletedTurnBrief(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,completion: null == completion ? _self.completion : completion // ignore: cast_nullable_to_non_nullable
as TurnCompletion,
  ));
}


}

/// @nodoc


class CancelledTurnBrief implements TurnBriefState {
  const CancelledTurnBrief({required this.startedAt, required this.requestedAt, required this.completedAt, required this.cause});


 final  int? startedAt;
 final  int requestedAt;
 final  int completedAt;
 final  TurnCancellationKind cause;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledTurnBriefCopyWith<CancelledTurnBrief> get copyWith => _$CancelledTurnBriefCopyWithImpl<CancelledTurnBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledTurnBrief&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.cause, cause) || other.cause == cause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,requestedAt,completedAt,cause);
}

@override
String toString() {
    return 'TurnBriefState.cancelled(startedAt: $startedAt, requestedAt: $requestedAt, completedAt: $completedAt, cause: $cause)';
}


}

/// @nodoc
abstract mixin class $CancelledTurnBriefCopyWith<$Res> implements $TurnBriefStateCopyWith<$Res> {
  factory $CancelledTurnBriefCopyWith(CancelledTurnBrief value, $Res Function(CancelledTurnBrief) _then) = _$CancelledTurnBriefCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int requestedAt, int completedAt, TurnCancellationKind cause
});




}
/// @nodoc
class _$CancelledTurnBriefCopyWithImpl<$Res>
    implements $CancelledTurnBriefCopyWith<$Res> {
  _$CancelledTurnBriefCopyWithImpl(this._self, this._then);

  final CancelledTurnBrief _self;
  final $Res Function(CancelledTurnBrief) _then;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? requestedAt = null,Object? completedAt = null,Object? cause = null,}) {
  return _then(CancelledTurnBrief(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,requestedAt: null == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as int,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as TurnCancellationKind,
  ));
}


}

/// @nodoc


class FailedTurnBrief implements TurnBriefState {
  const FailedTurnBrief({required this.startedAt, required this.completedAt, required this.category, required this.providerKind, required this.httpStatus, required this.retry});


 final  int? startedAt;
 final  int completedAt;
 final  TurnFailureCategory category;
 final  ProviderFailureKind? providerKind;
 final  int? httpStatus;
 final  RetryDisposition retry;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedTurnBriefCopyWith<FailedTurnBrief> get copyWith => _$FailedTurnBriefCopyWithImpl<FailedTurnBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedTurnBrief&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.category, category) || other.category == category)&&(identical(other.providerKind, providerKind) || other.providerKind == providerKind)&&(identical(other.httpStatus, httpStatus) || other.httpStatus == httpStatus)&&(identical(other.retry, retry) || other.retry == retry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,category,providerKind,httpStatus,retry);
}

@override
String toString() {
    return 'TurnBriefState.failed(startedAt: $startedAt, completedAt: $completedAt, category: $category, providerKind: $providerKind, httpStatus: $httpStatus, retry: $retry)';
}


}

/// @nodoc
abstract mixin class $FailedTurnBriefCopyWith<$Res> implements $TurnBriefStateCopyWith<$Res> {
  factory $FailedTurnBriefCopyWith(FailedTurnBrief value, $Res Function(FailedTurnBrief) _then) = _$FailedTurnBriefCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, TurnFailureCategory category, ProviderFailureKind? providerKind, int? httpStatus, RetryDisposition retry
});


$RetryDispositionCopyWith<$Res> get retry;

}
/// @nodoc
class _$FailedTurnBriefCopyWithImpl<$Res>
    implements $FailedTurnBriefCopyWith<$Res> {
  _$FailedTurnBriefCopyWithImpl(this._self, this._then);

  final FailedTurnBrief _self;
  final $Res Function(FailedTurnBrief) _then;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? category = null,Object? providerKind = freezed,Object? httpStatus = freezed,Object? retry = null,}) {
  return _then(FailedTurnBrief(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as TurnFailureCategory,providerKind: freezed == providerKind ? _self.providerKind : providerKind // ignore: cast_nullable_to_non_nullable
as ProviderFailureKind?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,retry: null == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as RetryDisposition,
  ));
}

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryDispositionCopyWith<$Res> get retry {

  return $RetryDispositionCopyWith<$Res>(_self.retry, (value) {
    return _then(_self.copyWith(retry: value));
  });
}
}

/// @nodoc


class BudgetLimitedTurnBrief implements TurnBriefState {
  const BudgetLimitedTurnBrief({required this.startedAt, required this.completedAt, required this.limit, required this.rollover});


 final  int? startedAt;
 final  int completedAt;
 final  BudgetLimitSnapshot limit;
 final  TurnRolloverKind rollover;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BudgetLimitedTurnBriefCopyWith<BudgetLimitedTurnBrief> get copyWith => _$BudgetLimitedTurnBriefCopyWithImpl<BudgetLimitedTurnBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BudgetLimitedTurnBrief&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.rollover, rollover) || other.rollover == rollover));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,limit,rollover);
}

@override
String toString() {
    return 'TurnBriefState.budgetLimited(startedAt: $startedAt, completedAt: $completedAt, limit: $limit, rollover: $rollover)';
}


}

/// @nodoc
abstract mixin class $BudgetLimitedTurnBriefCopyWith<$Res> implements $TurnBriefStateCopyWith<$Res> {
  factory $BudgetLimitedTurnBriefCopyWith(BudgetLimitedTurnBrief value, $Res Function(BudgetLimitedTurnBrief) _then) = _$BudgetLimitedTurnBriefCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, BudgetLimitSnapshot limit, TurnRolloverKind rollover
});


$BudgetLimitSnapshotCopyWith<$Res> get limit;

}
/// @nodoc
class _$BudgetLimitedTurnBriefCopyWithImpl<$Res>
    implements $BudgetLimitedTurnBriefCopyWith<$Res> {
  _$BudgetLimitedTurnBriefCopyWithImpl(this._self, this._then);

  final BudgetLimitedTurnBrief _self;
  final $Res Function(BudgetLimitedTurnBrief) _then;

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? limit = null,Object? rollover = null,}) {
  return _then(BudgetLimitedTurnBrief(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BudgetLimitSnapshot,rollover: null == rollover ? _self.rollover : rollover // ignore: cast_nullable_to_non_nullable
as TurnRolloverKind,
  ));
}

/// Create a copy of TurnBriefState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetLimitSnapshotCopyWith<$Res> get limit {

  return $BudgetLimitSnapshotCopyWith<$Res>(_self.limit, (value) {
    return _then(_self.copyWith(limit: value));
  });
}
}

/// @nodoc
mixin _$TurnCancellationCause {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnCancellationCause);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $TurnCancellationCauseCopyWith<$Res>  {
$TurnCancellationCauseCopyWith(TurnCancellationCause _, $Res Function(TurnCancellationCause) __);
}


/// Adds pattern-matching-related methods to [TurnCancellationCause].
extension TurnCancellationCausePatterns on TurnCancellationCause {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnspecifiedTurnCancellation value)?  unspecified,TResult Function( UserRequestedTurnCancellation value)?  userRequested,TResult Function( RuntimeShutdownTurnCancellation value)?  runtimeShutdown,TResult Function( AgentClosedTurnCancellation value)?  agentClosed,TResult Function( InterruptedTurnCancellation value)?  interrupted,TResult Function( RecoveryTurnCancellation value)?  recovery,TResult Function( CoalescedTurnCancellation value)?  coalesced,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnspecifiedTurnCancellation() when unspecified != null:
return unspecified(_that);case UserRequestedTurnCancellation() when userRequested != null:
return userRequested(_that);case RuntimeShutdownTurnCancellation() when runtimeShutdown != null:
return runtimeShutdown(_that);case AgentClosedTurnCancellation() when agentClosed != null:
return agentClosed(_that);case InterruptedTurnCancellation() when interrupted != null:
return interrupted(_that);case RecoveryTurnCancellation() when recovery != null:
return recovery(_that);case CoalescedTurnCancellation() when coalesced != null:
return coalesced(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnspecifiedTurnCancellation value)  unspecified,required TResult Function( UserRequestedTurnCancellation value)  userRequested,required TResult Function( RuntimeShutdownTurnCancellation value)  runtimeShutdown,required TResult Function( AgentClosedTurnCancellation value)  agentClosed,required TResult Function( InterruptedTurnCancellation value)  interrupted,required TResult Function( RecoveryTurnCancellation value)  recovery,required TResult Function( CoalescedTurnCancellation value)  coalesced,}){
final _that = this;
switch (_that) {
case UnspecifiedTurnCancellation():
return unspecified(_that);case UserRequestedTurnCancellation():
return userRequested(_that);case RuntimeShutdownTurnCancellation():
return runtimeShutdown(_that);case AgentClosedTurnCancellation():
return agentClosed(_that);case InterruptedTurnCancellation():
return interrupted(_that);case RecoveryTurnCancellation():
return recovery(_that);case CoalescedTurnCancellation():
return coalesced(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnspecifiedTurnCancellation value)?  unspecified,TResult? Function( UserRequestedTurnCancellation value)?  userRequested,TResult? Function( RuntimeShutdownTurnCancellation value)?  runtimeShutdown,TResult? Function( AgentClosedTurnCancellation value)?  agentClosed,TResult? Function( InterruptedTurnCancellation value)?  interrupted,TResult? Function( RecoveryTurnCancellation value)?  recovery,TResult? Function( CoalescedTurnCancellation value)?  coalesced,}){
final _that = this;
switch (_that) {
case UnspecifiedTurnCancellation() when unspecified != null:
return unspecified(_that);case UserRequestedTurnCancellation() when userRequested != null:
return userRequested(_that);case RuntimeShutdownTurnCancellation() when runtimeShutdown != null:
return runtimeShutdown(_that);case AgentClosedTurnCancellation() when agentClosed != null:
return agentClosed(_that);case InterruptedTurnCancellation() when interrupted != null:
return interrupted(_that);case RecoveryTurnCancellation() when recovery != null:
return recovery(_that);case CoalescedTurnCancellation() when coalesced != null:
return coalesced(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unspecified,TResult Function()?  userRequested,TResult Function()?  runtimeShutdown,TResult Function()?  agentClosed,TResult Function()?  interrupted,TResult Function()?  recovery,TResult Function( String targetTurnId)?  coalesced,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnspecifiedTurnCancellation() when unspecified != null:
return unspecified();case UserRequestedTurnCancellation() when userRequested != null:
return userRequested();case RuntimeShutdownTurnCancellation() when runtimeShutdown != null:
return runtimeShutdown();case AgentClosedTurnCancellation() when agentClosed != null:
return agentClosed();case InterruptedTurnCancellation() when interrupted != null:
return interrupted();case RecoveryTurnCancellation() when recovery != null:
return recovery();case CoalescedTurnCancellation() when coalesced != null:
return coalesced(_that.targetTurnId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unspecified,required TResult Function()  userRequested,required TResult Function()  runtimeShutdown,required TResult Function()  agentClosed,required TResult Function()  interrupted,required TResult Function()  recovery,required TResult Function( String targetTurnId)  coalesced,}) {final _that = this;
switch (_that) {
case UnspecifiedTurnCancellation():
return unspecified();case UserRequestedTurnCancellation():
return userRequested();case RuntimeShutdownTurnCancellation():
return runtimeShutdown();case AgentClosedTurnCancellation():
return agentClosed();case InterruptedTurnCancellation():
return interrupted();case RecoveryTurnCancellation():
return recovery();case CoalescedTurnCancellation():
return coalesced(_that.targetTurnId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unspecified,TResult? Function()?  userRequested,TResult? Function()?  runtimeShutdown,TResult? Function()?  agentClosed,TResult? Function()?  interrupted,TResult? Function()?  recovery,TResult? Function( String targetTurnId)?  coalesced,}) {final _that = this;
switch (_that) {
case UnspecifiedTurnCancellation() when unspecified != null:
return unspecified();case UserRequestedTurnCancellation() when userRequested != null:
return userRequested();case RuntimeShutdownTurnCancellation() when runtimeShutdown != null:
return runtimeShutdown();case AgentClosedTurnCancellation() when agentClosed != null:
return agentClosed();case InterruptedTurnCancellation() when interrupted != null:
return interrupted();case RecoveryTurnCancellation() when recovery != null:
return recovery();case CoalescedTurnCancellation() when coalesced != null:
return coalesced(_that.targetTurnId);case _:
  return null;

}
}

}

/// @nodoc


class UnspecifiedTurnCancellation implements TurnCancellationCause {
  const UnspecifiedTurnCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnspecifiedTurnCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class UserRequestedTurnCancellation implements TurnCancellationCause {
  const UserRequestedTurnCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserRequestedTurnCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class RuntimeShutdownTurnCancellation implements TurnCancellationCause {
  const RuntimeShutdownTurnCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeShutdownTurnCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class AgentClosedTurnCancellation implements TurnCancellationCause {
  const AgentClosedTurnCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentClosedTurnCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class InterruptedTurnCancellation implements TurnCancellationCause {
  const InterruptedTurnCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InterruptedTurnCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class RecoveryTurnCancellation implements TurnCancellationCause {
  const RecoveryTurnCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryTurnCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class CoalescedTurnCancellation implements TurnCancellationCause {
  const CoalescedTurnCancellation({required this.targetTurnId});


 final  String targetTurnId;

/// Create a copy of TurnCancellationCause
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoalescedTurnCancellationCopyWith<CoalescedTurnCancellation> get copyWith => _$CoalescedTurnCancellationCopyWithImpl<CoalescedTurnCancellation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoalescedTurnCancellation&&(identical(other.targetTurnId, targetTurnId) || other.targetTurnId == targetTurnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,targetTurnId);
}



}

/// @nodoc
abstract mixin class $CoalescedTurnCancellationCopyWith<$Res> implements $TurnCancellationCauseCopyWith<$Res> {
  factory $CoalescedTurnCancellationCopyWith(CoalescedTurnCancellation value, $Res Function(CoalescedTurnCancellation) _then) = _$CoalescedTurnCancellationCopyWithImpl;
@useResult
$Res call({
 String targetTurnId
});




}
/// @nodoc
class _$CoalescedTurnCancellationCopyWithImpl<$Res>
    implements $CoalescedTurnCancellationCopyWith<$Res> {
  _$CoalescedTurnCancellationCopyWithImpl(this._self, this._then);

  final CoalescedTurnCancellation _self;
  final $Res Function(CoalescedTurnCancellation) _then;

/// Create a copy of TurnCancellationCause
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetTurnId = null,}) {
  return _then(CoalescedTurnCancellation(
targetTurnId: null == targetTurnId ? _self.targetTurnId : targetTurnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TurnRolloverOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnRolloverOutcome);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $TurnRolloverOutcomeCopyWith<$Res>  {
$TurnRolloverOutcomeCopyWith(TurnRolloverOutcome _, $Res Function(TurnRolloverOutcome) __);
}


/// Adds pattern-matching-related methods to [TurnRolloverOutcome].
extension TurnRolloverOutcomePatterns on TurnRolloverOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TurnRolloverNotAttempted value)?  notAttempted,TResult Function( TurnRolloverSucceeded value)?  succeeded,TResult Function( TurnRolloverFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TurnRolloverNotAttempted() when notAttempted != null:
return notAttempted(_that);case TurnRolloverSucceeded() when succeeded != null:
return succeeded(_that);case TurnRolloverFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TurnRolloverNotAttempted value)  notAttempted,required TResult Function( TurnRolloverSucceeded value)  succeeded,required TResult Function( TurnRolloverFailed value)  failed,}){
final _that = this;
switch (_that) {
case TurnRolloverNotAttempted():
return notAttempted(_that);case TurnRolloverSucceeded():
return succeeded(_that);case TurnRolloverFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TurnRolloverNotAttempted value)?  notAttempted,TResult? Function( TurnRolloverSucceeded value)?  succeeded,TResult? Function( TurnRolloverFailed value)?  failed,}){
final _that = this;
switch (_that) {
case TurnRolloverNotAttempted() when notAttempted != null:
return notAttempted(_that);case TurnRolloverSucceeded() when succeeded != null:
return succeeded(_that);case TurnRolloverFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notAttempted,TResult Function()?  succeeded,TResult Function( String error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TurnRolloverNotAttempted() when notAttempted != null:
return notAttempted();case TurnRolloverSucceeded() when succeeded != null:
return succeeded();case TurnRolloverFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notAttempted,required TResult Function()  succeeded,required TResult Function( String error)  failed,}) {final _that = this;
switch (_that) {
case TurnRolloverNotAttempted():
return notAttempted();case TurnRolloverSucceeded():
return succeeded();case TurnRolloverFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notAttempted,TResult? Function()?  succeeded,TResult? Function( String error)?  failed,}) {final _that = this;
switch (_that) {
case TurnRolloverNotAttempted() when notAttempted != null:
return notAttempted();case TurnRolloverSucceeded() when succeeded != null:
return succeeded();case TurnRolloverFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class TurnRolloverNotAttempted implements TurnRolloverOutcome {
  const TurnRolloverNotAttempted();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnRolloverNotAttempted);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class TurnRolloverSucceeded implements TurnRolloverOutcome {
  const TurnRolloverSucceeded();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnRolloverSucceeded);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class TurnRolloverFailed implements TurnRolloverOutcome {
  const TurnRolloverFailed({required this.error});


 final  String error;

/// Create a copy of TurnRolloverOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnRolloverFailedCopyWith<TurnRolloverFailed> get copyWith => _$TurnRolloverFailedCopyWithImpl<TurnRolloverFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnRolloverFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $TurnRolloverFailedCopyWith<$Res> implements $TurnRolloverOutcomeCopyWith<$Res> {
  factory $TurnRolloverFailedCopyWith(TurnRolloverFailed value, $Res Function(TurnRolloverFailed) _then) = _$TurnRolloverFailedCopyWithImpl;
@useResult
$Res call({
 String error
});




}
/// @nodoc
class _$TurnRolloverFailedCopyWithImpl<$Res>
    implements $TurnRolloverFailedCopyWith<$Res> {
  _$TurnRolloverFailedCopyWithImpl(this._self, this._then);

  final TurnRolloverFailed _self;
  final $Res Function(TurnRolloverFailed) _then;

/// Create a copy of TurnRolloverOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(TurnRolloverFailed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TurnFailure {

 TurnFailureCategory get category; ProviderFailureKind? get providerKind; String? get code; int? get httpStatus; String get message; RetryDisposition get retry;
/// Create a copy of TurnFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnFailureCopyWith<TurnFailure> get copyWith => _$TurnFailureCopyWithImpl<TurnFailure>(this as TurnFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TurnFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnFailure&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.providerKind, _this.providerKind) || other.providerKind == _this.providerKind)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.httpStatus, _this.httpStatus) || other.httpStatus == _this.httpStatus)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retry, _this.retry) || other.retry == _this.retry));
}


@override
int get hashCode {
  final _this = this as TurnFailure;
  return Object.hash(runtimeType,_this.category,_this.providerKind,_this.code,_this.httpStatus,_this.message,_this.retry);
}



}

/// @nodoc
abstract mixin class $TurnFailureCopyWith<$Res>  {
  factory $TurnFailureCopyWith(TurnFailure value, $Res Function(TurnFailure) _then) = _$TurnFailureCopyWithImpl;
@useResult
$Res call({
 TurnFailureCategory category, ProviderFailureKind? providerKind, String? code, int? httpStatus, String message, RetryDisposition retry
});


$RetryDispositionCopyWith<$Res> get retry;

}
/// @nodoc
class _$TurnFailureCopyWithImpl<$Res>
    implements $TurnFailureCopyWith<$Res> {
  _$TurnFailureCopyWithImpl(this._self, this._then);

  final TurnFailure _self;
  final $Res Function(TurnFailure) _then;

/// Create a copy of TurnFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? category = null,Object? providerKind = freezed,Object? code = freezed,Object? httpStatus = freezed,Object? message = null,Object? retry = null,}) {
  return _then(TurnFailure(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as TurnFailureCategory,providerKind: freezed == providerKind ? _self.providerKind : providerKind // ignore: cast_nullable_to_non_nullable
as ProviderFailureKind?,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retry: null == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as RetryDisposition,
  ));
}
/// Create a copy of TurnFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryDispositionCopyWith<$Res> get retry {

  return $RetryDispositionCopyWith<$Res>(_self.retry, (value) {
    return _then(_self.copyWith(retry: value));
  });
}
}


/// Adds pattern-matching-related methods to [TurnFailure].
extension TurnFailurePatterns on TurnFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnFailure value)  $default,){
final _that = this;
switch (_that) {
case _TurnFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnFailure value)?  $default,){
final _that = this;
switch (_that) {
case _TurnFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TurnFailureCategory category,  ProviderFailureKind? providerKind,  String? code,  int? httpStatus,  String message,  RetryDisposition retry)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnFailure() when $default != null:
return $default(_that.category,_that.providerKind,_that.code,_that.httpStatus,_that.message,_that.retry);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TurnFailureCategory category,  ProviderFailureKind? providerKind,  String? code,  int? httpStatus,  String message,  RetryDisposition retry)  $default,) {final _that = this;
switch (_that) {
case _TurnFailure():
return $default(_that.category,_that.providerKind,_that.code,_that.httpStatus,_that.message,_that.retry);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TurnFailureCategory category,  ProviderFailureKind? providerKind,  String? code,  int? httpStatus,  String message,  RetryDisposition retry)?  $default,) {final _that = this;
switch (_that) {
case _TurnFailure() when $default != null:
return $default(_that.category,_that.providerKind,_that.code,_that.httpStatus,_that.message,_that.retry);case _:
  return null;

}
}

}

/// @nodoc


class _TurnFailure implements TurnFailure {
  const _TurnFailure({required this.category, required this.providerKind, required this.code, required this.httpStatus, required this.message, required this.retry});


@override final  TurnFailureCategory category;
@override final  ProviderFailureKind? providerKind;
@override final  String? code;
@override final  int? httpStatus;
@override final  String message;
@override final  RetryDisposition retry;

/// Create a copy of TurnFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnFailureCopyWith<_TurnFailure> get copyWith => __$TurnFailureCopyWithImpl<_TurnFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnFailure&&(identical(other.category, category) || other.category == category)&&(identical(other.providerKind, providerKind) || other.providerKind == providerKind)&&(identical(other.code, code) || other.code == code)&&(identical(other.httpStatus, httpStatus) || other.httpStatus == httpStatus)&&(identical(other.message, message) || other.message == message)&&(identical(other.retry, retry) || other.retry == retry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,category,providerKind,code,httpStatus,message,retry);
}



}

/// @nodoc
abstract mixin class _$TurnFailureCopyWith<$Res> implements $TurnFailureCopyWith<$Res> {
  factory _$TurnFailureCopyWith(_TurnFailure value, $Res Function(_TurnFailure) _then) = __$TurnFailureCopyWithImpl;
@override @useResult
$Res call({
 TurnFailureCategory category, ProviderFailureKind? providerKind, String? code, int? httpStatus, String message, RetryDisposition retry
});


@override $RetryDispositionCopyWith<$Res> get retry;

}
/// @nodoc
class __$TurnFailureCopyWithImpl<$Res>
    implements _$TurnFailureCopyWith<$Res> {
  __$TurnFailureCopyWithImpl(this._self, this._then);

  final _TurnFailure _self;
  final $Res Function(_TurnFailure) _then;

/// Create a copy of TurnFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? category = null,Object? providerKind = freezed,Object? code = freezed,Object? httpStatus = freezed,Object? message = null,Object? retry = null,}) {
  return _then(_TurnFailure(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as TurnFailureCategory,providerKind: freezed == providerKind ? _self.providerKind : providerKind // ignore: cast_nullable_to_non_nullable
as ProviderFailureKind?,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retry: null == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as RetryDisposition,
  ));
}

/// Create a copy of TurnFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryDispositionCopyWith<$Res> get retry {

  return $RetryDispositionCopyWith<$Res>(_self.retry, (value) {
    return _then(_self.copyWith(retry: value));
  });
}
}

/// @nodoc
mixin _$TurnState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $TurnStateCopyWith<$Res>  {
$TurnStateCopyWith(TurnState _, $Res Function(TurnState) __);
}


/// Adds pattern-matching-related methods to [TurnState].
extension TurnStatePatterns on TurnState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QueuedTurn value)?  queued,TResult Function( RunningTurn value)?  running,TResult Function( CompletedTurn value)?  completed,TResult Function( CancelledTurn value)?  cancelled,TResult Function( FailedTurn value)?  failed,TResult Function( BudgetLimitedTurn value)?  budgetLimited,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QueuedTurn() when queued != null:
return queued(_that);case RunningTurn() when running != null:
return running(_that);case CompletedTurn() when completed != null:
return completed(_that);case CancelledTurn() when cancelled != null:
return cancelled(_that);case FailedTurn() when failed != null:
return failed(_that);case BudgetLimitedTurn() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QueuedTurn value)  queued,required TResult Function( RunningTurn value)  running,required TResult Function( CompletedTurn value)  completed,required TResult Function( CancelledTurn value)  cancelled,required TResult Function( FailedTurn value)  failed,required TResult Function( BudgetLimitedTurn value)  budgetLimited,}){
final _that = this;
switch (_that) {
case QueuedTurn():
return queued(_that);case RunningTurn():
return running(_that);case CompletedTurn():
return completed(_that);case CancelledTurn():
return cancelled(_that);case FailedTurn():
return failed(_that);case BudgetLimitedTurn():
return budgetLimited(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QueuedTurn value)?  queued,TResult? Function( RunningTurn value)?  running,TResult? Function( CompletedTurn value)?  completed,TResult? Function( CancelledTurn value)?  cancelled,TResult? Function( FailedTurn value)?  failed,TResult? Function( BudgetLimitedTurn value)?  budgetLimited,}){
final _that = this;
switch (_that) {
case QueuedTurn() when queued != null:
return queued(_that);case RunningTurn() when running != null:
return running(_that);case CompletedTurn() when completed != null:
return completed(_that);case CancelledTurn() when cancelled != null:
return cancelled(_that);case FailedTurn() when failed != null:
return failed(_that);case BudgetLimitedTurn() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int queuedAt)?  queued,TResult Function( int startedAt,  TurnPhase phase)?  running,TResult Function( int? startedAt,  int completedAt,  TurnCompletion completion)?  completed,TResult Function( int? startedAt,  int requestedAt,  int completedAt,  TurnCancellationCause cause)?  cancelled,TResult Function( int? startedAt,  int completedAt,  TurnFailure failure)?  failed,TResult Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnRolloverOutcome rollover)?  budgetLimited,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QueuedTurn() when queued != null:
return queued(_that.queuedAt);case RunningTurn() when running != null:
return running(_that.startedAt,_that.phase);case CompletedTurn() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurn() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurn() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.failure);case BudgetLimitedTurn() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int queuedAt)  queued,required TResult Function( int startedAt,  TurnPhase phase)  running,required TResult Function( int? startedAt,  int completedAt,  TurnCompletion completion)  completed,required TResult Function( int? startedAt,  int requestedAt,  int completedAt,  TurnCancellationCause cause)  cancelled,required TResult Function( int? startedAt,  int completedAt,  TurnFailure failure)  failed,required TResult Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnRolloverOutcome rollover)  budgetLimited,}) {final _that = this;
switch (_that) {
case QueuedTurn():
return queued(_that.queuedAt);case RunningTurn():
return running(_that.startedAt,_that.phase);case CompletedTurn():
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurn():
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurn():
return failed(_that.startedAt,_that.completedAt,_that.failure);case BudgetLimitedTurn():
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int queuedAt)?  queued,TResult? Function( int startedAt,  TurnPhase phase)?  running,TResult? Function( int? startedAt,  int completedAt,  TurnCompletion completion)?  completed,TResult? Function( int? startedAt,  int requestedAt,  int completedAt,  TurnCancellationCause cause)?  cancelled,TResult? Function( int? startedAt,  int completedAt,  TurnFailure failure)?  failed,TResult? Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnRolloverOutcome rollover)?  budgetLimited,}) {final _that = this;
switch (_that) {
case QueuedTurn() when queued != null:
return queued(_that.queuedAt);case RunningTurn() when running != null:
return running(_that.startedAt,_that.phase);case CompletedTurn() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurn() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurn() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.failure);case BudgetLimitedTurn() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
  return null;

}
}

}

/// @nodoc


class QueuedTurn extends TurnState {
  const QueuedTurn({required this.queuedAt}): super._();


 final  int queuedAt;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueuedTurnCopyWith<QueuedTurn> get copyWith => _$QueuedTurnCopyWithImpl<QueuedTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedTurn&&(identical(other.queuedAt, queuedAt) || other.queuedAt == queuedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,queuedAt);
}



}

/// @nodoc
abstract mixin class $QueuedTurnCopyWith<$Res> implements $TurnStateCopyWith<$Res> {
  factory $QueuedTurnCopyWith(QueuedTurn value, $Res Function(QueuedTurn) _then) = _$QueuedTurnCopyWithImpl;
@useResult
$Res call({
 int queuedAt
});




}
/// @nodoc
class _$QueuedTurnCopyWithImpl<$Res>
    implements $QueuedTurnCopyWith<$Res> {
  _$QueuedTurnCopyWithImpl(this._self, this._then);

  final QueuedTurn _self;
  final $Res Function(QueuedTurn) _then;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? queuedAt = null,}) {
  return _then(QueuedTurn(
queuedAt: null == queuedAt ? _self.queuedAt : queuedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RunningTurn extends TurnState {
  const RunningTurn({required this.startedAt, required this.phase}): super._();


 final  int startedAt;
 final  TurnPhase phase;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RunningTurnCopyWith<RunningTurn> get copyWith => _$RunningTurnCopyWithImpl<RunningTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningTurn&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,phase);
}



}

/// @nodoc
abstract mixin class $RunningTurnCopyWith<$Res> implements $TurnStateCopyWith<$Res> {
  factory $RunningTurnCopyWith(RunningTurn value, $Res Function(RunningTurn) _then) = _$RunningTurnCopyWithImpl;
@useResult
$Res call({
 int startedAt, TurnPhase phase
});




}
/// @nodoc
class _$RunningTurnCopyWithImpl<$Res>
    implements $RunningTurnCopyWith<$Res> {
  _$RunningTurnCopyWithImpl(this._self, this._then);

  final RunningTurn _self;
  final $Res Function(RunningTurn) _then;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = null,Object? phase = null,}) {
  return _then(RunningTurn(
startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as TurnPhase,
  ));
}


}

/// @nodoc


class CompletedTurn extends TurnState {
  const CompletedTurn({required this.startedAt, required this.completedAt, required this.completion}): super._();


 final  int? startedAt;
 final  int completedAt;
 final  TurnCompletion completion;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompletedTurnCopyWith<CompletedTurn> get copyWith => _$CompletedTurnCopyWithImpl<CompletedTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletedTurn&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completion, completion) || other.completion == completion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,completion);
}



}

/// @nodoc
abstract mixin class $CompletedTurnCopyWith<$Res> implements $TurnStateCopyWith<$Res> {
  factory $CompletedTurnCopyWith(CompletedTurn value, $Res Function(CompletedTurn) _then) = _$CompletedTurnCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, TurnCompletion completion
});




}
/// @nodoc
class _$CompletedTurnCopyWithImpl<$Res>
    implements $CompletedTurnCopyWith<$Res> {
  _$CompletedTurnCopyWithImpl(this._self, this._then);

  final CompletedTurn _self;
  final $Res Function(CompletedTurn) _then;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? completion = null,}) {
  return _then(CompletedTurn(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,completion: null == completion ? _self.completion : completion // ignore: cast_nullable_to_non_nullable
as TurnCompletion,
  ));
}


}

/// @nodoc


class CancelledTurn extends TurnState {
  const CancelledTurn({required this.startedAt, required this.requestedAt, required this.completedAt, required this.cause}): super._();


 final  int? startedAt;
 final  int requestedAt;
 final  int completedAt;
 final  TurnCancellationCause cause;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledTurnCopyWith<CancelledTurn> get copyWith => _$CancelledTurnCopyWithImpl<CancelledTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledTurn&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.cause, cause) || other.cause == cause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,requestedAt,completedAt,cause);
}



}

/// @nodoc
abstract mixin class $CancelledTurnCopyWith<$Res> implements $TurnStateCopyWith<$Res> {
  factory $CancelledTurnCopyWith(CancelledTurn value, $Res Function(CancelledTurn) _then) = _$CancelledTurnCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int requestedAt, int completedAt, TurnCancellationCause cause
});


$TurnCancellationCauseCopyWith<$Res> get cause;

}
/// @nodoc
class _$CancelledTurnCopyWithImpl<$Res>
    implements $CancelledTurnCopyWith<$Res> {
  _$CancelledTurnCopyWithImpl(this._self, this._then);

  final CancelledTurn _self;
  final $Res Function(CancelledTurn) _then;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? requestedAt = null,Object? completedAt = null,Object? cause = null,}) {
  return _then(CancelledTurn(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,requestedAt: null == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as int,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as TurnCancellationCause,
  ));
}

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnCancellationCauseCopyWith<$Res> get cause {

  return $TurnCancellationCauseCopyWith<$Res>(_self.cause, (value) {
    return _then(_self.copyWith(cause: value));
  });
}
}

/// @nodoc


class FailedTurn extends TurnState {
  const FailedTurn({required this.startedAt, required this.completedAt, required this.failure}): super._();


 final  int? startedAt;
 final  int completedAt;
 final  TurnFailure failure;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedTurnCopyWith<FailedTurn> get copyWith => _$FailedTurnCopyWithImpl<FailedTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedTurn&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,failure);
}



}

/// @nodoc
abstract mixin class $FailedTurnCopyWith<$Res> implements $TurnStateCopyWith<$Res> {
  factory $FailedTurnCopyWith(FailedTurn value, $Res Function(FailedTurn) _then) = _$FailedTurnCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, TurnFailure failure
});


$TurnFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$FailedTurnCopyWithImpl<$Res>
    implements $FailedTurnCopyWith<$Res> {
  _$FailedTurnCopyWithImpl(this._self, this._then);

  final FailedTurn _self;
  final $Res Function(FailedTurn) _then;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? failure = null,}) {
  return _then(FailedTurn(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as TurnFailure,
  ));
}

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnFailureCopyWith<$Res> get failure {

  return $TurnFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class BudgetLimitedTurn extends TurnState {
  const BudgetLimitedTurn({required this.startedAt, required this.completedAt, required this.limit, required this.rollover}): super._();


 final  int? startedAt;
 final  int completedAt;
 final  BudgetLimitSnapshot limit;
 final  TurnRolloverOutcome rollover;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BudgetLimitedTurnCopyWith<BudgetLimitedTurn> get copyWith => _$BudgetLimitedTurnCopyWithImpl<BudgetLimitedTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BudgetLimitedTurn&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.rollover, rollover) || other.rollover == rollover));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,limit,rollover);
}



}

/// @nodoc
abstract mixin class $BudgetLimitedTurnCopyWith<$Res> implements $TurnStateCopyWith<$Res> {
  factory $BudgetLimitedTurnCopyWith(BudgetLimitedTurn value, $Res Function(BudgetLimitedTurn) _then) = _$BudgetLimitedTurnCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, BudgetLimitSnapshot limit, TurnRolloverOutcome rollover
});


$BudgetLimitSnapshotCopyWith<$Res> get limit;$TurnRolloverOutcomeCopyWith<$Res> get rollover;

}
/// @nodoc
class _$BudgetLimitedTurnCopyWithImpl<$Res>
    implements $BudgetLimitedTurnCopyWith<$Res> {
  _$BudgetLimitedTurnCopyWithImpl(this._self, this._then);

  final BudgetLimitedTurn _self;
  final $Res Function(BudgetLimitedTurn) _then;

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? limit = null,Object? rollover = null,}) {
  return _then(BudgetLimitedTurn(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BudgetLimitSnapshot,rollover: null == rollover ? _self.rollover : rollover // ignore: cast_nullable_to_non_nullable
as TurnRolloverOutcome,
  ));
}

/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetLimitSnapshotCopyWith<$Res> get limit {

  return $BudgetLimitSnapshotCopyWith<$Res>(_self.limit, (value) {
    return _then(_self.copyWith(limit: value));
  });
}/// Create a copy of TurnState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnRolloverOutcomeCopyWith<$Res> get rollover {

  return $TurnRolloverOutcomeCopyWith<$Res>(_self.rollover, (value) {
    return _then(_self.copyWith(rollover: value));
  });
}
}

/// @nodoc
mixin _$ConversationTurn {

 String? get inputId; String get id; String get threadId; int get revision; int get updatedAt; TurnState get state;
/// Create a copy of ConversationTurn
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationTurnCopyWith<ConversationTurn> get copyWith => _$ConversationTurnCopyWithImpl<ConversationTurn>(this as ConversationTurn, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConversationTurn;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationTurn&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as ConversationTurn;
  return Object.hash(runtimeType,_this.inputId,_this.id,_this.threadId,_this.revision,_this.updatedAt,_this.state);
}



}

/// @nodoc
abstract mixin class $ConversationTurnCopyWith<$Res>  {
  factory $ConversationTurnCopyWith(ConversationTurn value, $Res Function(ConversationTurn) _then) = _$ConversationTurnCopyWithImpl;
@useResult
$Res call({
 String? inputId, String id, String threadId, int revision, int updatedAt, TurnState state
});


$TurnStateCopyWith<$Res> get state;

}
/// @nodoc
class _$ConversationTurnCopyWithImpl<$Res>
    implements $ConversationTurnCopyWith<$Res> {
  _$ConversationTurnCopyWithImpl(this._self, this._then);

  final ConversationTurn _self;
  final $Res Function(ConversationTurn) _then;

/// Create a copy of ConversationTurn
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inputId = freezed,Object? id = null,Object? threadId = null,Object? revision = null,Object? updatedAt = null,Object? state = null,}) {
  return _then(ConversationTurn(
inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnState,
  ));
}
/// Create a copy of ConversationTurn
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnStateCopyWith<$Res> get state {

  return $TurnStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConversationTurn].
extension ConversationTurnPatterns on ConversationTurn {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationTurn value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationTurn() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationTurn value)  $default,){
final _that = this;
switch (_that) {
case _ConversationTurn():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationTurn value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationTurn() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? inputId,  String id,  String threadId,  int revision,  int updatedAt,  TurnState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationTurn() when $default != null:
return $default(_that.inputId,_that.id,_that.threadId,_that.revision,_that.updatedAt,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? inputId,  String id,  String threadId,  int revision,  int updatedAt,  TurnState state)  $default,) {final _that = this;
switch (_that) {
case _ConversationTurn():
return $default(_that.inputId,_that.id,_that.threadId,_that.revision,_that.updatedAt,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? inputId,  String id,  String threadId,  int revision,  int updatedAt,  TurnState state)?  $default,) {final _that = this;
switch (_that) {
case _ConversationTurn() when $default != null:
return $default(_that.inputId,_that.id,_that.threadId,_that.revision,_that.updatedAt,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationTurn implements ConversationTurn {
  const _ConversationTurn({required this.inputId, required this.id, required this.threadId, required this.revision, required this.updatedAt, required this.state});


@override final  String? inputId;
@override final  String id;
@override final  String threadId;
@override final  int revision;
@override final  int updatedAt;
@override final  TurnState state;

/// Create a copy of ConversationTurn
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationTurnCopyWith<_ConversationTurn> get copyWith => __$ConversationTurnCopyWithImpl<_ConversationTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationTurn&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.id, id) || other.id == id)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inputId,id,threadId,revision,updatedAt,state);
}



}

/// @nodoc
abstract mixin class _$ConversationTurnCopyWith<$Res> implements $ConversationTurnCopyWith<$Res> {
  factory _$ConversationTurnCopyWith(_ConversationTurn value, $Res Function(_ConversationTurn) _then) = __$ConversationTurnCopyWithImpl;
@override @useResult
$Res call({
 String? inputId, String id, String threadId, int revision, int updatedAt, TurnState state
});


@override $TurnStateCopyWith<$Res> get state;

}
/// @nodoc
class __$ConversationTurnCopyWithImpl<$Res>
    implements _$ConversationTurnCopyWith<$Res> {
  __$ConversationTurnCopyWithImpl(this._self, this._then);

  final _ConversationTurn _self;
  final $Res Function(_ConversationTurn) _then;

/// Create a copy of ConversationTurn
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? inputId = freezed,Object? id = null,Object? threadId = null,Object? revision = null,Object? updatedAt = null,Object? state = null,}) {
  return _then(_ConversationTurn(
inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnState,
  ));
}

/// Create a copy of ConversationTurn
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnStateCopyWith<$Res> get state {

  return $TurnStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$TurnReadCancellationCause {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadCancellationCause);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $TurnReadCancellationCauseCopyWith<$Res>  {
$TurnReadCancellationCauseCopyWith(TurnReadCancellationCause _, $Res Function(TurnReadCancellationCause) __);
}


/// Adds pattern-matching-related methods to [TurnReadCancellationCause].
extension TurnReadCancellationCausePatterns on TurnReadCancellationCause {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnspecifiedTurnReadCancellation value)?  unspecified,TResult Function( UserRequestedTurnReadCancellation value)?  userRequested,TResult Function( RuntimeShutdownTurnReadCancellation value)?  runtimeShutdown,TResult Function( AgentClosedTurnReadCancellation value)?  agentClosed,TResult Function( InterruptedTurnReadCancellation value)?  interrupted,TResult Function( RecoveryTurnReadCancellation value)?  recovery,TResult Function( CoalescedTurnReadCancellation value)?  coalesced,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnspecifiedTurnReadCancellation() when unspecified != null:
return unspecified(_that);case UserRequestedTurnReadCancellation() when userRequested != null:
return userRequested(_that);case RuntimeShutdownTurnReadCancellation() when runtimeShutdown != null:
return runtimeShutdown(_that);case AgentClosedTurnReadCancellation() when agentClosed != null:
return agentClosed(_that);case InterruptedTurnReadCancellation() when interrupted != null:
return interrupted(_that);case RecoveryTurnReadCancellation() when recovery != null:
return recovery(_that);case CoalescedTurnReadCancellation() when coalesced != null:
return coalesced(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnspecifiedTurnReadCancellation value)  unspecified,required TResult Function( UserRequestedTurnReadCancellation value)  userRequested,required TResult Function( RuntimeShutdownTurnReadCancellation value)  runtimeShutdown,required TResult Function( AgentClosedTurnReadCancellation value)  agentClosed,required TResult Function( InterruptedTurnReadCancellation value)  interrupted,required TResult Function( RecoveryTurnReadCancellation value)  recovery,required TResult Function( CoalescedTurnReadCancellation value)  coalesced,}){
final _that = this;
switch (_that) {
case UnspecifiedTurnReadCancellation():
return unspecified(_that);case UserRequestedTurnReadCancellation():
return userRequested(_that);case RuntimeShutdownTurnReadCancellation():
return runtimeShutdown(_that);case AgentClosedTurnReadCancellation():
return agentClosed(_that);case InterruptedTurnReadCancellation():
return interrupted(_that);case RecoveryTurnReadCancellation():
return recovery(_that);case CoalescedTurnReadCancellation():
return coalesced(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnspecifiedTurnReadCancellation value)?  unspecified,TResult? Function( UserRequestedTurnReadCancellation value)?  userRequested,TResult? Function( RuntimeShutdownTurnReadCancellation value)?  runtimeShutdown,TResult? Function( AgentClosedTurnReadCancellation value)?  agentClosed,TResult? Function( InterruptedTurnReadCancellation value)?  interrupted,TResult? Function( RecoveryTurnReadCancellation value)?  recovery,TResult? Function( CoalescedTurnReadCancellation value)?  coalesced,}){
final _that = this;
switch (_that) {
case UnspecifiedTurnReadCancellation() when unspecified != null:
return unspecified(_that);case UserRequestedTurnReadCancellation() when userRequested != null:
return userRequested(_that);case RuntimeShutdownTurnReadCancellation() when runtimeShutdown != null:
return runtimeShutdown(_that);case AgentClosedTurnReadCancellation() when agentClosed != null:
return agentClosed(_that);case InterruptedTurnReadCancellation() when interrupted != null:
return interrupted(_that);case RecoveryTurnReadCancellation() when recovery != null:
return recovery(_that);case CoalescedTurnReadCancellation() when coalesced != null:
return coalesced(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unspecified,TResult Function()?  userRequested,TResult Function()?  runtimeShutdown,TResult Function()?  agentClosed,TResult Function()?  interrupted,TResult Function()?  recovery,TResult Function( ReadText targetTurnId)?  coalesced,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnspecifiedTurnReadCancellation() when unspecified != null:
return unspecified();case UserRequestedTurnReadCancellation() when userRequested != null:
return userRequested();case RuntimeShutdownTurnReadCancellation() when runtimeShutdown != null:
return runtimeShutdown();case AgentClosedTurnReadCancellation() when agentClosed != null:
return agentClosed();case InterruptedTurnReadCancellation() when interrupted != null:
return interrupted();case RecoveryTurnReadCancellation() when recovery != null:
return recovery();case CoalescedTurnReadCancellation() when coalesced != null:
return coalesced(_that.targetTurnId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unspecified,required TResult Function()  userRequested,required TResult Function()  runtimeShutdown,required TResult Function()  agentClosed,required TResult Function()  interrupted,required TResult Function()  recovery,required TResult Function( ReadText targetTurnId)  coalesced,}) {final _that = this;
switch (_that) {
case UnspecifiedTurnReadCancellation():
return unspecified();case UserRequestedTurnReadCancellation():
return userRequested();case RuntimeShutdownTurnReadCancellation():
return runtimeShutdown();case AgentClosedTurnReadCancellation():
return agentClosed();case InterruptedTurnReadCancellation():
return interrupted();case RecoveryTurnReadCancellation():
return recovery();case CoalescedTurnReadCancellation():
return coalesced(_that.targetTurnId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unspecified,TResult? Function()?  userRequested,TResult? Function()?  runtimeShutdown,TResult? Function()?  agentClosed,TResult? Function()?  interrupted,TResult? Function()?  recovery,TResult? Function( ReadText targetTurnId)?  coalesced,}) {final _that = this;
switch (_that) {
case UnspecifiedTurnReadCancellation() when unspecified != null:
return unspecified();case UserRequestedTurnReadCancellation() when userRequested != null:
return userRequested();case RuntimeShutdownTurnReadCancellation() when runtimeShutdown != null:
return runtimeShutdown();case AgentClosedTurnReadCancellation() when agentClosed != null:
return agentClosed();case InterruptedTurnReadCancellation() when interrupted != null:
return interrupted();case RecoveryTurnReadCancellation() when recovery != null:
return recovery();case CoalescedTurnReadCancellation() when coalesced != null:
return coalesced(_that.targetTurnId);case _:
  return null;

}
}

}

/// @nodoc


class UnspecifiedTurnReadCancellation implements TurnReadCancellationCause {
  const UnspecifiedTurnReadCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnspecifiedTurnReadCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class UserRequestedTurnReadCancellation implements TurnReadCancellationCause {
  const UserRequestedTurnReadCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserRequestedTurnReadCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class RuntimeShutdownTurnReadCancellation implements TurnReadCancellationCause {
  const RuntimeShutdownTurnReadCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeShutdownTurnReadCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class AgentClosedTurnReadCancellation implements TurnReadCancellationCause {
  const AgentClosedTurnReadCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentClosedTurnReadCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class InterruptedTurnReadCancellation implements TurnReadCancellationCause {
  const InterruptedTurnReadCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InterruptedTurnReadCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class RecoveryTurnReadCancellation implements TurnReadCancellationCause {
  const RecoveryTurnReadCancellation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryTurnReadCancellation);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class CoalescedTurnReadCancellation implements TurnReadCancellationCause {
  const CoalescedTurnReadCancellation({required this.targetTurnId});


 final  ReadText targetTurnId;

/// Create a copy of TurnReadCancellationCause
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CoalescedTurnReadCancellationCopyWith<CoalescedTurnReadCancellation> get copyWith => _$CoalescedTurnReadCancellationCopyWithImpl<CoalescedTurnReadCancellation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CoalescedTurnReadCancellation&&(identical(other.targetTurnId, targetTurnId) || other.targetTurnId == targetTurnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,targetTurnId);
}



}

/// @nodoc
abstract mixin class $CoalescedTurnReadCancellationCopyWith<$Res> implements $TurnReadCancellationCauseCopyWith<$Res> {
  factory $CoalescedTurnReadCancellationCopyWith(CoalescedTurnReadCancellation value, $Res Function(CoalescedTurnReadCancellation) _then) = _$CoalescedTurnReadCancellationCopyWithImpl;
@useResult
$Res call({
 ReadText targetTurnId
});


$ReadTextCopyWith<$Res> get targetTurnId;

}
/// @nodoc
class _$CoalescedTurnReadCancellationCopyWithImpl<$Res>
    implements $CoalescedTurnReadCancellationCopyWith<$Res> {
  _$CoalescedTurnReadCancellationCopyWithImpl(this._self, this._then);

  final CoalescedTurnReadCancellation _self;
  final $Res Function(CoalescedTurnReadCancellation) _then;

/// Create a copy of TurnReadCancellationCause
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetTurnId = null,}) {
  return _then(CoalescedTurnReadCancellation(
targetTurnId: null == targetTurnId ? _self.targetTurnId : targetTurnId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of TurnReadCancellationCause
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get targetTurnId {

  return $ReadTextCopyWith<$Res>(_self.targetTurnId, (value) {
    return _then(_self.copyWith(targetTurnId: value));
  });
}
}

/// @nodoc
mixin _$TurnReadRolloverOutcome {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadRolloverOutcome);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $TurnReadRolloverOutcomeCopyWith<$Res>  {
$TurnReadRolloverOutcomeCopyWith(TurnReadRolloverOutcome _, $Res Function(TurnReadRolloverOutcome) __);
}


/// Adds pattern-matching-related methods to [TurnReadRolloverOutcome].
extension TurnReadRolloverOutcomePatterns on TurnReadRolloverOutcome {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TurnReadRolloverNotAttempted value)?  notAttempted,TResult Function( TurnReadRolloverSucceeded value)?  succeeded,TResult Function( TurnReadRolloverFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TurnReadRolloverNotAttempted() when notAttempted != null:
return notAttempted(_that);case TurnReadRolloverSucceeded() when succeeded != null:
return succeeded(_that);case TurnReadRolloverFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TurnReadRolloverNotAttempted value)  notAttempted,required TResult Function( TurnReadRolloverSucceeded value)  succeeded,required TResult Function( TurnReadRolloverFailed value)  failed,}){
final _that = this;
switch (_that) {
case TurnReadRolloverNotAttempted():
return notAttempted(_that);case TurnReadRolloverSucceeded():
return succeeded(_that);case TurnReadRolloverFailed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TurnReadRolloverNotAttempted value)?  notAttempted,TResult? Function( TurnReadRolloverSucceeded value)?  succeeded,TResult? Function( TurnReadRolloverFailed value)?  failed,}){
final _that = this;
switch (_that) {
case TurnReadRolloverNotAttempted() when notAttempted != null:
return notAttempted(_that);case TurnReadRolloverSucceeded() when succeeded != null:
return succeeded(_that);case TurnReadRolloverFailed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notAttempted,TResult Function()?  succeeded,TResult Function( ReadText error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TurnReadRolloverNotAttempted() when notAttempted != null:
return notAttempted();case TurnReadRolloverSucceeded() when succeeded != null:
return succeeded();case TurnReadRolloverFailed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notAttempted,required TResult Function()  succeeded,required TResult Function( ReadText error)  failed,}) {final _that = this;
switch (_that) {
case TurnReadRolloverNotAttempted():
return notAttempted();case TurnReadRolloverSucceeded():
return succeeded();case TurnReadRolloverFailed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notAttempted,TResult? Function()?  succeeded,TResult? Function( ReadText error)?  failed,}) {final _that = this;
switch (_that) {
case TurnReadRolloverNotAttempted() when notAttempted != null:
return notAttempted();case TurnReadRolloverSucceeded() when succeeded != null:
return succeeded();case TurnReadRolloverFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class TurnReadRolloverNotAttempted implements TurnReadRolloverOutcome {
  const TurnReadRolloverNotAttempted();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadRolloverNotAttempted);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class TurnReadRolloverSucceeded implements TurnReadRolloverOutcome {
  const TurnReadRolloverSucceeded();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadRolloverSucceeded);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class TurnReadRolloverFailed implements TurnReadRolloverOutcome {
  const TurnReadRolloverFailed({required this.error});


 final  ReadText error;

/// Create a copy of TurnReadRolloverOutcome
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnReadRolloverFailedCopyWith<TurnReadRolloverFailed> get copyWith => _$TurnReadRolloverFailedCopyWithImpl<TurnReadRolloverFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadRolloverFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $TurnReadRolloverFailedCopyWith<$Res> implements $TurnReadRolloverOutcomeCopyWith<$Res> {
  factory $TurnReadRolloverFailedCopyWith(TurnReadRolloverFailed value, $Res Function(TurnReadRolloverFailed) _then) = _$TurnReadRolloverFailedCopyWithImpl;
@useResult
$Res call({
 ReadText error
});


$ReadTextCopyWith<$Res> get error;

}
/// @nodoc
class _$TurnReadRolloverFailedCopyWithImpl<$Res>
    implements $TurnReadRolloverFailedCopyWith<$Res> {
  _$TurnReadRolloverFailedCopyWithImpl(this._self, this._then);

  final TurnReadRolloverFailed _self;
  final $Res Function(TurnReadRolloverFailed) _then;

/// Create a copy of TurnReadRolloverOutcome
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(TurnReadRolloverFailed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of TurnReadRolloverOutcome
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get error {

  return $ReadTextCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$TurnFailureRead {

 TurnFailureCategory get category; ProviderFailureKind? get providerKind; ReadText? get code; int? get httpStatus; ReadText get message; RetryDisposition get retry;
/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnFailureReadCopyWith<TurnFailureRead> get copyWith => _$TurnFailureReadCopyWithImpl<TurnFailureRead>(this as TurnFailureRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TurnFailureRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnFailureRead&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.providerKind, _this.providerKind) || other.providerKind == _this.providerKind)&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.httpStatus, _this.httpStatus) || other.httpStatus == _this.httpStatus)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retry, _this.retry) || other.retry == _this.retry));
}


@override
int get hashCode {
  final _this = this as TurnFailureRead;
  return Object.hash(runtimeType,_this.category,_this.providerKind,_this.code,_this.httpStatus,_this.message,_this.retry);
}



}

/// @nodoc
abstract mixin class $TurnFailureReadCopyWith<$Res>  {
  factory $TurnFailureReadCopyWith(TurnFailureRead value, $Res Function(TurnFailureRead) _then) = _$TurnFailureReadCopyWithImpl;
@useResult
$Res call({
 TurnFailureCategory category, ProviderFailureKind? providerKind, ReadText? code, int? httpStatus, ReadText message, RetryDisposition retry
});


$ReadTextCopyWith<$Res>? get code;$ReadTextCopyWith<$Res> get message;$RetryDispositionCopyWith<$Res> get retry;

}
/// @nodoc
class _$TurnFailureReadCopyWithImpl<$Res>
    implements $TurnFailureReadCopyWith<$Res> {
  _$TurnFailureReadCopyWithImpl(this._self, this._then);

  final TurnFailureRead _self;
  final $Res Function(TurnFailureRead) _then;

/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? category = null,Object? providerKind = freezed,Object? code = freezed,Object? httpStatus = freezed,Object? message = null,Object? retry = null,}) {
  return _then(TurnFailureRead(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as TurnFailureCategory,providerKind: freezed == providerKind ? _self.providerKind : providerKind // ignore: cast_nullable_to_non_nullable
as ProviderFailureKind?,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ReadText?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,retry: null == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as RetryDisposition,
  ));
}
/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get code {
    if (_self.code == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.code!, (value) {
    return _then(_self.copyWith(code: value));
  });
}/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryDispositionCopyWith<$Res> get retry {

  return $RetryDispositionCopyWith<$Res>(_self.retry, (value) {
    return _then(_self.copyWith(retry: value));
  });
}
}


/// Adds pattern-matching-related methods to [TurnFailureRead].
extension TurnFailureReadPatterns on TurnFailureRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnFailureRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnFailureRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnFailureRead value)  $default,){
final _that = this;
switch (_that) {
case _TurnFailureRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnFailureRead value)?  $default,){
final _that = this;
switch (_that) {
case _TurnFailureRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( TurnFailureCategory category,  ProviderFailureKind? providerKind,  ReadText? code,  int? httpStatus,  ReadText message,  RetryDisposition retry)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnFailureRead() when $default != null:
return $default(_that.category,_that.providerKind,_that.code,_that.httpStatus,_that.message,_that.retry);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( TurnFailureCategory category,  ProviderFailureKind? providerKind,  ReadText? code,  int? httpStatus,  ReadText message,  RetryDisposition retry)  $default,) {final _that = this;
switch (_that) {
case _TurnFailureRead():
return $default(_that.category,_that.providerKind,_that.code,_that.httpStatus,_that.message,_that.retry);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( TurnFailureCategory category,  ProviderFailureKind? providerKind,  ReadText? code,  int? httpStatus,  ReadText message,  RetryDisposition retry)?  $default,) {final _that = this;
switch (_that) {
case _TurnFailureRead() when $default != null:
return $default(_that.category,_that.providerKind,_that.code,_that.httpStatus,_that.message,_that.retry);case _:
  return null;

}
}

}

/// @nodoc


class _TurnFailureRead implements TurnFailureRead {
  const _TurnFailureRead({required this.category, required this.providerKind, required this.code, required this.httpStatus, required this.message, required this.retry});


@override final  TurnFailureCategory category;
@override final  ProviderFailureKind? providerKind;
@override final  ReadText? code;
@override final  int? httpStatus;
@override final  ReadText message;
@override final  RetryDisposition retry;

/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnFailureReadCopyWith<_TurnFailureRead> get copyWith => __$TurnFailureReadCopyWithImpl<_TurnFailureRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnFailureRead&&(identical(other.category, category) || other.category == category)&&(identical(other.providerKind, providerKind) || other.providerKind == providerKind)&&(identical(other.code, code) || other.code == code)&&(identical(other.httpStatus, httpStatus) || other.httpStatus == httpStatus)&&(identical(other.message, message) || other.message == message)&&(identical(other.retry, retry) || other.retry == retry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,category,providerKind,code,httpStatus,message,retry);
}



}

/// @nodoc
abstract mixin class _$TurnFailureReadCopyWith<$Res> implements $TurnFailureReadCopyWith<$Res> {
  factory _$TurnFailureReadCopyWith(_TurnFailureRead value, $Res Function(_TurnFailureRead) _then) = __$TurnFailureReadCopyWithImpl;
@override @useResult
$Res call({
 TurnFailureCategory category, ProviderFailureKind? providerKind, ReadText? code, int? httpStatus, ReadText message, RetryDisposition retry
});


@override $ReadTextCopyWith<$Res>? get code;@override $ReadTextCopyWith<$Res> get message;@override $RetryDispositionCopyWith<$Res> get retry;

}
/// @nodoc
class __$TurnFailureReadCopyWithImpl<$Res>
    implements _$TurnFailureReadCopyWith<$Res> {
  __$TurnFailureReadCopyWithImpl(this._self, this._then);

  final _TurnFailureRead _self;
  final $Res Function(_TurnFailureRead) _then;

/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? category = null,Object? providerKind = freezed,Object? code = freezed,Object? httpStatus = freezed,Object? message = null,Object? retry = null,}) {
  return _then(_TurnFailureRead(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as TurnFailureCategory,providerKind: freezed == providerKind ? _self.providerKind : providerKind // ignore: cast_nullable_to_non_nullable
as ProviderFailureKind?,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ReadText?,httpStatus: freezed == httpStatus ? _self.httpStatus : httpStatus // ignore: cast_nullable_to_non_nullable
as int?,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,retry: null == retry ? _self.retry : retry // ignore: cast_nullable_to_non_nullable
as RetryDisposition,
  ));
}

/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get code {
    if (_self.code == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.code!, (value) {
    return _then(_self.copyWith(code: value));
  });
}/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}/// Create a copy of TurnFailureRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RetryDispositionCopyWith<$Res> get retry {

  return $RetryDispositionCopyWith<$Res>(_self.retry, (value) {
    return _then(_self.copyWith(retry: value));
  });
}
}

/// @nodoc
mixin _$TurnReadState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $TurnReadStateCopyWith<$Res>  {
$TurnReadStateCopyWith(TurnReadState _, $Res Function(TurnReadState) __);
}


/// Adds pattern-matching-related methods to [TurnReadState].
extension TurnReadStatePatterns on TurnReadState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QueuedTurnRead value)?  queued,TResult Function( RunningTurnRead value)?  running,TResult Function( CompletedTurnRead value)?  completed,TResult Function( CancelledTurnRead value)?  cancelled,TResult Function( FailedTurnRead value)?  failed,TResult Function( BudgetLimitedTurnRead value)?  budgetLimited,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QueuedTurnRead() when queued != null:
return queued(_that);case RunningTurnRead() when running != null:
return running(_that);case CompletedTurnRead() when completed != null:
return completed(_that);case CancelledTurnRead() when cancelled != null:
return cancelled(_that);case FailedTurnRead() when failed != null:
return failed(_that);case BudgetLimitedTurnRead() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QueuedTurnRead value)  queued,required TResult Function( RunningTurnRead value)  running,required TResult Function( CompletedTurnRead value)  completed,required TResult Function( CancelledTurnRead value)  cancelled,required TResult Function( FailedTurnRead value)  failed,required TResult Function( BudgetLimitedTurnRead value)  budgetLimited,}){
final _that = this;
switch (_that) {
case QueuedTurnRead():
return queued(_that);case RunningTurnRead():
return running(_that);case CompletedTurnRead():
return completed(_that);case CancelledTurnRead():
return cancelled(_that);case FailedTurnRead():
return failed(_that);case BudgetLimitedTurnRead():
return budgetLimited(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QueuedTurnRead value)?  queued,TResult? Function( RunningTurnRead value)?  running,TResult? Function( CompletedTurnRead value)?  completed,TResult? Function( CancelledTurnRead value)?  cancelled,TResult? Function( FailedTurnRead value)?  failed,TResult? Function( BudgetLimitedTurnRead value)?  budgetLimited,}){
final _that = this;
switch (_that) {
case QueuedTurnRead() when queued != null:
return queued(_that);case RunningTurnRead() when running != null:
return running(_that);case CompletedTurnRead() when completed != null:
return completed(_that);case CancelledTurnRead() when cancelled != null:
return cancelled(_that);case FailedTurnRead() when failed != null:
return failed(_that);case BudgetLimitedTurnRead() when budgetLimited != null:
return budgetLimited(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int queuedAt)?  queued,TResult Function( int startedAt,  TurnPhase phase)?  running,TResult Function( int? startedAt,  int completedAt,  TurnCompletion completion)?  completed,TResult Function( int? startedAt,  int requestedAt,  int completedAt,  TurnReadCancellationCause cause)?  cancelled,TResult Function( int? startedAt,  int completedAt,  TurnFailureRead failure)?  failed,TResult Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnReadRolloverOutcome rollover)?  budgetLimited,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QueuedTurnRead() when queued != null:
return queued(_that.queuedAt);case RunningTurnRead() when running != null:
return running(_that.startedAt,_that.phase);case CompletedTurnRead() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurnRead() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurnRead() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.failure);case BudgetLimitedTurnRead() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int queuedAt)  queued,required TResult Function( int startedAt,  TurnPhase phase)  running,required TResult Function( int? startedAt,  int completedAt,  TurnCompletion completion)  completed,required TResult Function( int? startedAt,  int requestedAt,  int completedAt,  TurnReadCancellationCause cause)  cancelled,required TResult Function( int? startedAt,  int completedAt,  TurnFailureRead failure)  failed,required TResult Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnReadRolloverOutcome rollover)  budgetLimited,}) {final _that = this;
switch (_that) {
case QueuedTurnRead():
return queued(_that.queuedAt);case RunningTurnRead():
return running(_that.startedAt,_that.phase);case CompletedTurnRead():
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurnRead():
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurnRead():
return failed(_that.startedAt,_that.completedAt,_that.failure);case BudgetLimitedTurnRead():
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int queuedAt)?  queued,TResult? Function( int startedAt,  TurnPhase phase)?  running,TResult? Function( int? startedAt,  int completedAt,  TurnCompletion completion)?  completed,TResult? Function( int? startedAt,  int requestedAt,  int completedAt,  TurnReadCancellationCause cause)?  cancelled,TResult? Function( int? startedAt,  int completedAt,  TurnFailureRead failure)?  failed,TResult? Function( int? startedAt,  int completedAt,  BudgetLimitSnapshot limit,  TurnReadRolloverOutcome rollover)?  budgetLimited,}) {final _that = this;
switch (_that) {
case QueuedTurnRead() when queued != null:
return queued(_that.queuedAt);case RunningTurnRead() when running != null:
return running(_that.startedAt,_that.phase);case CompletedTurnRead() when completed != null:
return completed(_that.startedAt,_that.completedAt,_that.completion);case CancelledTurnRead() when cancelled != null:
return cancelled(_that.startedAt,_that.requestedAt,_that.completedAt,_that.cause);case FailedTurnRead() when failed != null:
return failed(_that.startedAt,_that.completedAt,_that.failure);case BudgetLimitedTurnRead() when budgetLimited != null:
return budgetLimited(_that.startedAt,_that.completedAt,_that.limit,_that.rollover);case _:
  return null;

}
}

}

/// @nodoc


class QueuedTurnRead implements TurnReadState {
  const QueuedTurnRead({required this.queuedAt});


 final  int queuedAt;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QueuedTurnReadCopyWith<QueuedTurnRead> get copyWith => _$QueuedTurnReadCopyWithImpl<QueuedTurnRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedTurnRead&&(identical(other.queuedAt, queuedAt) || other.queuedAt == queuedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,queuedAt);
}



}

/// @nodoc
abstract mixin class $QueuedTurnReadCopyWith<$Res> implements $TurnReadStateCopyWith<$Res> {
  factory $QueuedTurnReadCopyWith(QueuedTurnRead value, $Res Function(QueuedTurnRead) _then) = _$QueuedTurnReadCopyWithImpl;
@useResult
$Res call({
 int queuedAt
});




}
/// @nodoc
class _$QueuedTurnReadCopyWithImpl<$Res>
    implements $QueuedTurnReadCopyWith<$Res> {
  _$QueuedTurnReadCopyWithImpl(this._self, this._then);

  final QueuedTurnRead _self;
  final $Res Function(QueuedTurnRead) _then;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? queuedAt = null,}) {
  return _then(QueuedTurnRead(
queuedAt: null == queuedAt ? _self.queuedAt : queuedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RunningTurnRead implements TurnReadState {
  const RunningTurnRead({required this.startedAt, required this.phase});


 final  int startedAt;
 final  TurnPhase phase;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RunningTurnReadCopyWith<RunningTurnRead> get copyWith => _$RunningTurnReadCopyWithImpl<RunningTurnRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningTurnRead&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,phase);
}



}

/// @nodoc
abstract mixin class $RunningTurnReadCopyWith<$Res> implements $TurnReadStateCopyWith<$Res> {
  factory $RunningTurnReadCopyWith(RunningTurnRead value, $Res Function(RunningTurnRead) _then) = _$RunningTurnReadCopyWithImpl;
@useResult
$Res call({
 int startedAt, TurnPhase phase
});




}
/// @nodoc
class _$RunningTurnReadCopyWithImpl<$Res>
    implements $RunningTurnReadCopyWith<$Res> {
  _$RunningTurnReadCopyWithImpl(this._self, this._then);

  final RunningTurnRead _self;
  final $Res Function(RunningTurnRead) _then;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = null,Object? phase = null,}) {
  return _then(RunningTurnRead(
startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as TurnPhase,
  ));
}


}

/// @nodoc


class CompletedTurnRead implements TurnReadState {
  const CompletedTurnRead({required this.startedAt, required this.completedAt, required this.completion});


 final  int? startedAt;
 final  int completedAt;
 final  TurnCompletion completion;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompletedTurnReadCopyWith<CompletedTurnRead> get copyWith => _$CompletedTurnReadCopyWithImpl<CompletedTurnRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletedTurnRead&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.completion, completion) || other.completion == completion));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,completion);
}



}

/// @nodoc
abstract mixin class $CompletedTurnReadCopyWith<$Res> implements $TurnReadStateCopyWith<$Res> {
  factory $CompletedTurnReadCopyWith(CompletedTurnRead value, $Res Function(CompletedTurnRead) _then) = _$CompletedTurnReadCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, TurnCompletion completion
});




}
/// @nodoc
class _$CompletedTurnReadCopyWithImpl<$Res>
    implements $CompletedTurnReadCopyWith<$Res> {
  _$CompletedTurnReadCopyWithImpl(this._self, this._then);

  final CompletedTurnRead _self;
  final $Res Function(CompletedTurnRead) _then;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? completion = null,}) {
  return _then(CompletedTurnRead(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,completion: null == completion ? _self.completion : completion // ignore: cast_nullable_to_non_nullable
as TurnCompletion,
  ));
}


}

/// @nodoc


class CancelledTurnRead implements TurnReadState {
  const CancelledTurnRead({required this.startedAt, required this.requestedAt, required this.completedAt, required this.cause});


 final  int? startedAt;
 final  int requestedAt;
 final  int completedAt;
 final  TurnReadCancellationCause cause;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledTurnReadCopyWith<CancelledTurnRead> get copyWith => _$CancelledTurnReadCopyWithImpl<CancelledTurnRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledTurnRead&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.requestedAt, requestedAt) || other.requestedAt == requestedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.cause, cause) || other.cause == cause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,requestedAt,completedAt,cause);
}



}

/// @nodoc
abstract mixin class $CancelledTurnReadCopyWith<$Res> implements $TurnReadStateCopyWith<$Res> {
  factory $CancelledTurnReadCopyWith(CancelledTurnRead value, $Res Function(CancelledTurnRead) _then) = _$CancelledTurnReadCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int requestedAt, int completedAt, TurnReadCancellationCause cause
});


$TurnReadCancellationCauseCopyWith<$Res> get cause;

}
/// @nodoc
class _$CancelledTurnReadCopyWithImpl<$Res>
    implements $CancelledTurnReadCopyWith<$Res> {
  _$CancelledTurnReadCopyWithImpl(this._self, this._then);

  final CancelledTurnRead _self;
  final $Res Function(CancelledTurnRead) _then;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? requestedAt = null,Object? completedAt = null,Object? cause = null,}) {
  return _then(CancelledTurnRead(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,requestedAt: null == requestedAt ? _self.requestedAt : requestedAt // ignore: cast_nullable_to_non_nullable
as int,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,cause: null == cause ? _self.cause : cause // ignore: cast_nullable_to_non_nullable
as TurnReadCancellationCause,
  ));
}

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnReadCancellationCauseCopyWith<$Res> get cause {

  return $TurnReadCancellationCauseCopyWith<$Res>(_self.cause, (value) {
    return _then(_self.copyWith(cause: value));
  });
}
}

/// @nodoc


class FailedTurnRead implements TurnReadState {
  const FailedTurnRead({required this.startedAt, required this.completedAt, required this.failure});


 final  int? startedAt;
 final  int completedAt;
 final  TurnFailureRead failure;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedTurnReadCopyWith<FailedTurnRead> get copyWith => _$FailedTurnReadCopyWithImpl<FailedTurnRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedTurnRead&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,failure);
}



}

/// @nodoc
abstract mixin class $FailedTurnReadCopyWith<$Res> implements $TurnReadStateCopyWith<$Res> {
  factory $FailedTurnReadCopyWith(FailedTurnRead value, $Res Function(FailedTurnRead) _then) = _$FailedTurnReadCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, TurnFailureRead failure
});


$TurnFailureReadCopyWith<$Res> get failure;

}
/// @nodoc
class _$FailedTurnReadCopyWithImpl<$Res>
    implements $FailedTurnReadCopyWith<$Res> {
  _$FailedTurnReadCopyWithImpl(this._self, this._then);

  final FailedTurnRead _self;
  final $Res Function(FailedTurnRead) _then;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? failure = null,}) {
  return _then(FailedTurnRead(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as TurnFailureRead,
  ));
}

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnFailureReadCopyWith<$Res> get failure {

  return $TurnFailureReadCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class BudgetLimitedTurnRead implements TurnReadState {
  const BudgetLimitedTurnRead({required this.startedAt, required this.completedAt, required this.limit, required this.rollover});


 final  int? startedAt;
 final  int completedAt;
 final  BudgetLimitSnapshot limit;
 final  TurnReadRolloverOutcome rollover;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BudgetLimitedTurnReadCopyWith<BudgetLimitedTurnRead> get copyWith => _$BudgetLimitedTurnReadCopyWithImpl<BudgetLimitedTurnRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BudgetLimitedTurnRead&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.rollover, rollover) || other.rollover == rollover));
}


@override
int get hashCode {
    return Object.hash(runtimeType,startedAt,completedAt,limit,rollover);
}



}

/// @nodoc
abstract mixin class $BudgetLimitedTurnReadCopyWith<$Res> implements $TurnReadStateCopyWith<$Res> {
  factory $BudgetLimitedTurnReadCopyWith(BudgetLimitedTurnRead value, $Res Function(BudgetLimitedTurnRead) _then) = _$BudgetLimitedTurnReadCopyWithImpl;
@useResult
$Res call({
 int? startedAt, int completedAt, BudgetLimitSnapshot limit, TurnReadRolloverOutcome rollover
});


$BudgetLimitSnapshotCopyWith<$Res> get limit;$TurnReadRolloverOutcomeCopyWith<$Res> get rollover;

}
/// @nodoc
class _$BudgetLimitedTurnReadCopyWithImpl<$Res>
    implements $BudgetLimitedTurnReadCopyWith<$Res> {
  _$BudgetLimitedTurnReadCopyWithImpl(this._self, this._then);

  final BudgetLimitedTurnRead _self;
  final $Res Function(BudgetLimitedTurnRead) _then;

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? startedAt = freezed,Object? completedAt = null,Object? limit = null,Object? rollover = null,}) {
  return _then(BudgetLimitedTurnRead(
startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,completedAt: null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as BudgetLimitSnapshot,rollover: null == rollover ? _self.rollover : rollover // ignore: cast_nullable_to_non_nullable
as TurnReadRolloverOutcome,
  ));
}

/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BudgetLimitSnapshotCopyWith<$Res> get limit {

  return $BudgetLimitSnapshotCopyWith<$Res>(_self.limit, (value) {
    return _then(_self.copyWith(limit: value));
  });
}/// Create a copy of TurnReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnReadRolloverOutcomeCopyWith<$Res> get rollover {

  return $TurnReadRolloverOutcomeCopyWith<$Res>(_self.rollover, (value) {
    return _then(_self.copyWith(rollover: value));
  });
}
}

/// @nodoc
mixin _$TurnReadHeader {

 ReadScopeIdentity get scope; ReadText? get inputId; ReadText get id; ReadText get threadId; int get revision; int get updatedAt; TurnReadState get state;
/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TurnReadHeaderCopyWith<TurnReadHeader> get copyWith => _$TurnReadHeaderCopyWithImpl<TurnReadHeader>(this as TurnReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TurnReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TurnReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as TurnReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.inputId,_this.id,_this.threadId,_this.revision,_this.updatedAt,_this.state);
}



}

/// @nodoc
abstract mixin class $TurnReadHeaderCopyWith<$Res>  {
  factory $TurnReadHeaderCopyWith(TurnReadHeader value, $Res Function(TurnReadHeader) _then) = _$TurnReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, ReadText? inputId, ReadText id, ReadText threadId, int revision, int updatedAt, TurnReadState state
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ReadTextCopyWith<$Res>? get inputId;$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get threadId;$TurnReadStateCopyWith<$Res> get state;

}
/// @nodoc
class _$TurnReadHeaderCopyWithImpl<$Res>
    implements $TurnReadHeaderCopyWith<$Res> {
  _$TurnReadHeaderCopyWithImpl(this._self, this._then);

  final TurnReadHeader _self;
  final $Res Function(TurnReadHeader) _then;

/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? inputId = freezed,Object? id = null,Object? threadId = null,Object? revision = null,Object? updatedAt = null,Object? state = null,}) {
  return _then(TurnReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as ReadText?,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnReadState,
  ));
}
/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get inputId {
    if (_self.inputId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.inputId!, (value) {
    return _then(_self.copyWith(inputId: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnReadStateCopyWith<$Res> get state {

  return $TurnReadStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [TurnReadHeader].
extension TurnReadHeaderPatterns on TurnReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TurnReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TurnReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TurnReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _TurnReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TurnReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _TurnReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText? inputId,  ReadText id,  ReadText threadId,  int revision,  int updatedAt,  TurnReadState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TurnReadHeader() when $default != null:
return $default(_that.scope,_that.inputId,_that.id,_that.threadId,_that.revision,_that.updatedAt,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText? inputId,  ReadText id,  ReadText threadId,  int revision,  int updatedAt,  TurnReadState state)  $default,) {final _that = this;
switch (_that) {
case _TurnReadHeader():
return $default(_that.scope,_that.inputId,_that.id,_that.threadId,_that.revision,_that.updatedAt,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  ReadText? inputId,  ReadText id,  ReadText threadId,  int revision,  int updatedAt,  TurnReadState state)?  $default,) {final _that = this;
switch (_that) {
case _TurnReadHeader() when $default != null:
return $default(_that.scope,_that.inputId,_that.id,_that.threadId,_that.revision,_that.updatedAt,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _TurnReadHeader implements TurnReadHeader {
  const _TurnReadHeader({required this.scope, required this.inputId, required this.id, required this.threadId, required this.revision, required this.updatedAt, required this.state});


@override final  ReadScopeIdentity scope;
@override final  ReadText? inputId;
@override final  ReadText id;
@override final  ReadText threadId;
@override final  int revision;
@override final  int updatedAt;
@override final  TurnReadState state;

/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TurnReadHeaderCopyWith<_TurnReadHeader> get copyWith => __$TurnReadHeaderCopyWithImpl<_TurnReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TurnReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.id, id) || other.id == id)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,inputId,id,threadId,revision,updatedAt,state);
}



}

/// @nodoc
abstract mixin class _$TurnReadHeaderCopyWith<$Res> implements $TurnReadHeaderCopyWith<$Res> {
  factory _$TurnReadHeaderCopyWith(_TurnReadHeader value, $Res Function(_TurnReadHeader) _then) = __$TurnReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, ReadText? inputId, ReadText id, ReadText threadId, int revision, int updatedAt, TurnReadState state
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ReadTextCopyWith<$Res>? get inputId;@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get threadId;@override $TurnReadStateCopyWith<$Res> get state;

}
/// @nodoc
class __$TurnReadHeaderCopyWithImpl<$Res>
    implements _$TurnReadHeaderCopyWith<$Res> {
  __$TurnReadHeaderCopyWithImpl(this._self, this._then);

  final _TurnReadHeader _self;
  final $Res Function(_TurnReadHeader) _then;

/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? inputId = freezed,Object? id = null,Object? threadId = null,Object? revision = null,Object? updatedAt = null,Object? state = null,}) {
  return _then(_TurnReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as ReadText?,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as TurnReadState,
  ));
}

/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get inputId {
    if (_self.inputId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.inputId!, (value) {
    return _then(_self.copyWith(inputId: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of TurnReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TurnReadStateCopyWith<$Res> get state {

  return $TurnReadStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

// dart format on
