// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'runtime.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAgentActivity {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentActivity);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAgentActivity()';
}


}

/// @nodoc
class $BridgeAgentActivityCopyWith<$Res>  {
$BridgeAgentActivityCopyWith(BridgeAgentActivity _, $Res Function(BridgeAgentActivity) __);
}


/// Adds pattern-matching-related methods to [BridgeAgentActivity].
extension BridgeAgentActivityPatterns on BridgeAgentActivity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentActivity_Native value)?  native,TResult Function( BridgeAgentActivity_Acp value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentActivity_Native() when native != null:
return native(_that);case BridgeAgentActivity_Acp() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentActivity_Native value)  native,required TResult Function( BridgeAgentActivity_Acp value)  acp,}){
final _that = this;
switch (_that) {
case BridgeAgentActivity_Native():
return native(_that);case BridgeAgentActivity_Acp():
return acp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentActivity_Native value)?  native,TResult? Function( BridgeAgentActivity_Acp value)?  acp,}){
final _that = this;
switch (_that) {
case BridgeAgentActivity_Native() when native != null:
return native(_that);case BridgeAgentActivity_Acp() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAgentState state,  BridgeAgentExecution? execution,  bool canStop,  bool awaitingScheduling)?  native,TResult Function( bool explicitlyClosed)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentActivity_Native() when native != null:
return native(_that.state,_that.execution,_that.canStop,_that.awaitingScheduling);case BridgeAgentActivity_Acp() when acp != null:
return acp(_that.explicitlyClosed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAgentState state,  BridgeAgentExecution? execution,  bool canStop,  bool awaitingScheduling)  native,required TResult Function( bool explicitlyClosed)  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentActivity_Native():
return native(_that.state,_that.execution,_that.canStop,_that.awaitingScheduling);case BridgeAgentActivity_Acp():
return acp(_that.explicitlyClosed);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAgentState state,  BridgeAgentExecution? execution,  bool canStop,  bool awaitingScheduling)?  native,TResult? Function( bool explicitlyClosed)?  acp,}) {final _that = this;
switch (_that) {
case BridgeAgentActivity_Native() when native != null:
return native(_that.state,_that.execution,_that.canStop,_that.awaitingScheduling);case BridgeAgentActivity_Acp() when acp != null:
return acp(_that.explicitlyClosed);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentActivity_Native extends BridgeAgentActivity {
  const BridgeAgentActivity_Native({required this.state, this.execution, required this.canStop, required this.awaitingScheduling}): super._();


 final  BridgeAgentState state;
 final  BridgeAgentExecution? execution;
 final  bool canStop;
 final  bool awaitingScheduling;

/// Create a copy of BridgeAgentActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentActivity_NativeCopyWith<BridgeAgentActivity_Native> get copyWith => _$BridgeAgentActivity_NativeCopyWithImpl<BridgeAgentActivity_Native>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentActivity_Native&&(identical(other.state, state) || other.state == state)&&(identical(other.execution, execution) || other.execution == execution)&&(identical(other.canStop, canStop) || other.canStop == canStop)&&(identical(other.awaitingScheduling, awaitingScheduling) || other.awaitingScheduling == awaitingScheduling));
}


@override
int get hashCode {
    return Object.hash(runtimeType,state,execution,canStop,awaitingScheduling);
}

@override
String toString() {
    return 'BridgeAgentActivity.native(state: $state, execution: $execution, canStop: $canStop, awaitingScheduling: $awaitingScheduling)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentActivity_NativeCopyWith<$Res> implements $BridgeAgentActivityCopyWith<$Res> {
  factory $BridgeAgentActivity_NativeCopyWith(BridgeAgentActivity_Native value, $Res Function(BridgeAgentActivity_Native) _then) = _$BridgeAgentActivity_NativeCopyWithImpl;
@useResult
$Res call({
 BridgeAgentState state, BridgeAgentExecution? execution, bool canStop, bool awaitingScheduling
});


$BridgeAgentStateCopyWith<$Res> get state;

}
/// @nodoc
class _$BridgeAgentActivity_NativeCopyWithImpl<$Res>
    implements $BridgeAgentActivity_NativeCopyWith<$Res> {
  _$BridgeAgentActivity_NativeCopyWithImpl(this._self, this._then);

  final BridgeAgentActivity_Native _self;
  final $Res Function(BridgeAgentActivity_Native) _then;

/// Create a copy of BridgeAgentActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? state = null,Object? execution = freezed,Object? canStop = null,Object? awaitingScheduling = null,}) {
  return _then(BridgeAgentActivity_Native(
state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BridgeAgentState,execution: freezed == execution ? _self.execution : execution // ignore: cast_nullable_to_non_nullable
as BridgeAgentExecution?,canStop: null == canStop ? _self.canStop : canStop // ignore: cast_nullable_to_non_nullable
as bool,awaitingScheduling: null == awaitingScheduling ? _self.awaitingScheduling : awaitingScheduling // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of BridgeAgentActivity
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAgentStateCopyWith<$Res> get state {

  return $BridgeAgentStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class BridgeAgentActivity_Acp extends BridgeAgentActivity {
  const BridgeAgentActivity_Acp({required this.explicitlyClosed}): super._();


 final  bool explicitlyClosed;

/// Create a copy of BridgeAgentActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentActivity_AcpCopyWith<BridgeAgentActivity_Acp> get copyWith => _$BridgeAgentActivity_AcpCopyWithImpl<BridgeAgentActivity_Acp>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentActivity_Acp&&(identical(other.explicitlyClosed, explicitlyClosed) || other.explicitlyClosed == explicitlyClosed));
}


@override
int get hashCode {
    return Object.hash(runtimeType,explicitlyClosed);
}

@override
String toString() {
    return 'BridgeAgentActivity.acp(explicitlyClosed: $explicitlyClosed)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentActivity_AcpCopyWith<$Res> implements $BridgeAgentActivityCopyWith<$Res> {
  factory $BridgeAgentActivity_AcpCopyWith(BridgeAgentActivity_Acp value, $Res Function(BridgeAgentActivity_Acp) _then) = _$BridgeAgentActivity_AcpCopyWithImpl;
@useResult
$Res call({
 bool explicitlyClosed
});




}
/// @nodoc
class _$BridgeAgentActivity_AcpCopyWithImpl<$Res>
    implements $BridgeAgentActivity_AcpCopyWith<$Res> {
  _$BridgeAgentActivity_AcpCopyWithImpl(this._self, this._then);

  final BridgeAgentActivity_Acp _self;
  final $Res Function(BridgeAgentActivity_Acp) _then;

/// Create a copy of BridgeAgentActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? explicitlyClosed = null,}) {
  return _then(BridgeAgentActivity_Acp(
explicitlyClosed: null == explicitlyClosed ? _self.explicitlyClosed : explicitlyClosed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BridgeAgentState {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeAgentState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentState&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeAgentState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeAgentState;
  return 'BridgeAgentState(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeAgentStateCopyWith<$Res>  {
$BridgeAgentStateCopyWith(BridgeAgentState _, $Res Function(BridgeAgentState) __);
}


/// Adds pattern-matching-related methods to [BridgeAgentState].
extension BridgeAgentStatePatterns on BridgeAgentState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentState_Idle value)?  idle,TResult Function( BridgeAgentState_Running value)?  running,TResult Function( BridgeAgentState_WaitingInteraction value)?  waitingInteraction,TResult Function( BridgeAgentState_Closing value)?  closing,TResult Function( BridgeAgentState_Closed value)?  closed,TResult Function( BridgeAgentState_CloseFailed value)?  closeFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentState_Idle() when idle != null:
return idle(_that);case BridgeAgentState_Running() when running != null:
return running(_that);case BridgeAgentState_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that);case BridgeAgentState_Closing() when closing != null:
return closing(_that);case BridgeAgentState_Closed() when closed != null:
return closed(_that);case BridgeAgentState_CloseFailed() when closeFailed != null:
return closeFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentState_Idle value)  idle,required TResult Function( BridgeAgentState_Running value)  running,required TResult Function( BridgeAgentState_WaitingInteraction value)  waitingInteraction,required TResult Function( BridgeAgentState_Closing value)  closing,required TResult Function( BridgeAgentState_Closed value)  closed,required TResult Function( BridgeAgentState_CloseFailed value)  closeFailed,}){
final _that = this;
switch (_that) {
case BridgeAgentState_Idle():
return idle(_that);case BridgeAgentState_Running():
return running(_that);case BridgeAgentState_WaitingInteraction():
return waitingInteraction(_that);case BridgeAgentState_Closing():
return closing(_that);case BridgeAgentState_Closed():
return closed(_that);case BridgeAgentState_CloseFailed():
return closeFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentState_Idle value)?  idle,TResult? Function( BridgeAgentState_Running value)?  running,TResult? Function( BridgeAgentState_WaitingInteraction value)?  waitingInteraction,TResult? Function( BridgeAgentState_Closing value)?  closing,TResult? Function( BridgeAgentState_Closed value)?  closed,TResult? Function( BridgeAgentState_CloseFailed value)?  closeFailed,}){
final _that = this;
switch (_that) {
case BridgeAgentState_Idle() when idle != null:
return idle(_that);case BridgeAgentState_Running() when running != null:
return running(_that);case BridgeAgentState_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that);case BridgeAgentState_Closing() when closing != null:
return closing(_that);case BridgeAgentState_Closed() when closed != null:
return closed(_that);case BridgeAgentState_CloseFailed() when closeFailed != null:
return closeFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeIdleAgent field0)?  idle,TResult Function( BridgeRunningAgent field0)?  running,TResult Function( BridgeWaitingInteractionAgent field0)?  waitingInteraction,TResult Function( BridgeClosingAgent field0)?  closing,TResult Function( BridgeClosedAgent field0)?  closed,TResult Function( BridgeCloseFailedAgent field0)?  closeFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentState_Idle() when idle != null:
return idle(_that.field0);case BridgeAgentState_Running() when running != null:
return running(_that.field0);case BridgeAgentState_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that.field0);case BridgeAgentState_Closing() when closing != null:
return closing(_that.field0);case BridgeAgentState_Closed() when closed != null:
return closed(_that.field0);case BridgeAgentState_CloseFailed() when closeFailed != null:
return closeFailed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeIdleAgent field0)  idle,required TResult Function( BridgeRunningAgent field0)  running,required TResult Function( BridgeWaitingInteractionAgent field0)  waitingInteraction,required TResult Function( BridgeClosingAgent field0)  closing,required TResult Function( BridgeClosedAgent field0)  closed,required TResult Function( BridgeCloseFailedAgent field0)  closeFailed,}) {final _that = this;
switch (_that) {
case BridgeAgentState_Idle():
return idle(_that.field0);case BridgeAgentState_Running():
return running(_that.field0);case BridgeAgentState_WaitingInteraction():
return waitingInteraction(_that.field0);case BridgeAgentState_Closing():
return closing(_that.field0);case BridgeAgentState_Closed():
return closed(_that.field0);case BridgeAgentState_CloseFailed():
return closeFailed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeIdleAgent field0)?  idle,TResult? Function( BridgeRunningAgent field0)?  running,TResult? Function( BridgeWaitingInteractionAgent field0)?  waitingInteraction,TResult? Function( BridgeClosingAgent field0)?  closing,TResult? Function( BridgeClosedAgent field0)?  closed,TResult? Function( BridgeCloseFailedAgent field0)?  closeFailed,}) {final _that = this;
switch (_that) {
case BridgeAgentState_Idle() when idle != null:
return idle(_that.field0);case BridgeAgentState_Running() when running != null:
return running(_that.field0);case BridgeAgentState_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that.field0);case BridgeAgentState_Closing() when closing != null:
return closing(_that.field0);case BridgeAgentState_Closed() when closed != null:
return closed(_that.field0);case BridgeAgentState_CloseFailed() when closeFailed != null:
return closeFailed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentState_Idle extends BridgeAgentState {
  const BridgeAgentState_Idle(this.field0): super._();


@override final  BridgeIdleAgent field0;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentState_IdleCopyWith<BridgeAgentState_Idle> get copyWith => _$BridgeAgentState_IdleCopyWithImpl<BridgeAgentState_Idle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentState_Idle&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAgentState.idle(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentState_IdleCopyWith<$Res> implements $BridgeAgentStateCopyWith<$Res> {
  factory $BridgeAgentState_IdleCopyWith(BridgeAgentState_Idle value, $Res Function(BridgeAgentState_Idle) _then) = _$BridgeAgentState_IdleCopyWithImpl;
@useResult
$Res call({
 BridgeIdleAgent field0
});




}
/// @nodoc
class _$BridgeAgentState_IdleCopyWithImpl<$Res>
    implements $BridgeAgentState_IdleCopyWith<$Res> {
  _$BridgeAgentState_IdleCopyWithImpl(this._self, this._then);

  final BridgeAgentState_Idle _self;
  final $Res Function(BridgeAgentState_Idle) _then;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAgentState_Idle(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeIdleAgent,
  ));
}


}

/// @nodoc


class BridgeAgentState_Running extends BridgeAgentState {
  const BridgeAgentState_Running(this.field0): super._();


@override final  BridgeRunningAgent field0;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentState_RunningCopyWith<BridgeAgentState_Running> get copyWith => _$BridgeAgentState_RunningCopyWithImpl<BridgeAgentState_Running>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentState_Running&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAgentState.running(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentState_RunningCopyWith<$Res> implements $BridgeAgentStateCopyWith<$Res> {
  factory $BridgeAgentState_RunningCopyWith(BridgeAgentState_Running value, $Res Function(BridgeAgentState_Running) _then) = _$BridgeAgentState_RunningCopyWithImpl;
@useResult
$Res call({
 BridgeRunningAgent field0
});




}
/// @nodoc
class _$BridgeAgentState_RunningCopyWithImpl<$Res>
    implements $BridgeAgentState_RunningCopyWith<$Res> {
  _$BridgeAgentState_RunningCopyWithImpl(this._self, this._then);

  final BridgeAgentState_Running _self;
  final $Res Function(BridgeAgentState_Running) _then;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAgentState_Running(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeRunningAgent,
  ));
}


}

/// @nodoc


class BridgeAgentState_WaitingInteraction extends BridgeAgentState {
  const BridgeAgentState_WaitingInteraction(this.field0): super._();


@override final  BridgeWaitingInteractionAgent field0;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentState_WaitingInteractionCopyWith<BridgeAgentState_WaitingInteraction> get copyWith => _$BridgeAgentState_WaitingInteractionCopyWithImpl<BridgeAgentState_WaitingInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentState_WaitingInteraction&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAgentState.waitingInteraction(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentState_WaitingInteractionCopyWith<$Res> implements $BridgeAgentStateCopyWith<$Res> {
  factory $BridgeAgentState_WaitingInteractionCopyWith(BridgeAgentState_WaitingInteraction value, $Res Function(BridgeAgentState_WaitingInteraction) _then) = _$BridgeAgentState_WaitingInteractionCopyWithImpl;
@useResult
$Res call({
 BridgeWaitingInteractionAgent field0
});




}
/// @nodoc
class _$BridgeAgentState_WaitingInteractionCopyWithImpl<$Res>
    implements $BridgeAgentState_WaitingInteractionCopyWith<$Res> {
  _$BridgeAgentState_WaitingInteractionCopyWithImpl(this._self, this._then);

  final BridgeAgentState_WaitingInteraction _self;
  final $Res Function(BridgeAgentState_WaitingInteraction) _then;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAgentState_WaitingInteraction(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeWaitingInteractionAgent,
  ));
}


}

/// @nodoc


class BridgeAgentState_Closing extends BridgeAgentState {
  const BridgeAgentState_Closing(this.field0): super._();


@override final  BridgeClosingAgent field0;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentState_ClosingCopyWith<BridgeAgentState_Closing> get copyWith => _$BridgeAgentState_ClosingCopyWithImpl<BridgeAgentState_Closing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentState_Closing&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAgentState.closing(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentState_ClosingCopyWith<$Res> implements $BridgeAgentStateCopyWith<$Res> {
  factory $BridgeAgentState_ClosingCopyWith(BridgeAgentState_Closing value, $Res Function(BridgeAgentState_Closing) _then) = _$BridgeAgentState_ClosingCopyWithImpl;
@useResult
$Res call({
 BridgeClosingAgent field0
});




}
/// @nodoc
class _$BridgeAgentState_ClosingCopyWithImpl<$Res>
    implements $BridgeAgentState_ClosingCopyWith<$Res> {
  _$BridgeAgentState_ClosingCopyWithImpl(this._self, this._then);

  final BridgeAgentState_Closing _self;
  final $Res Function(BridgeAgentState_Closing) _then;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAgentState_Closing(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeClosingAgent,
  ));
}


}

/// @nodoc


class BridgeAgentState_Closed extends BridgeAgentState {
  const BridgeAgentState_Closed(this.field0): super._();


@override final  BridgeClosedAgent field0;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentState_ClosedCopyWith<BridgeAgentState_Closed> get copyWith => _$BridgeAgentState_ClosedCopyWithImpl<BridgeAgentState_Closed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentState_Closed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAgentState.closed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentState_ClosedCopyWith<$Res> implements $BridgeAgentStateCopyWith<$Res> {
  factory $BridgeAgentState_ClosedCopyWith(BridgeAgentState_Closed value, $Res Function(BridgeAgentState_Closed) _then) = _$BridgeAgentState_ClosedCopyWithImpl;
@useResult
$Res call({
 BridgeClosedAgent field0
});




}
/// @nodoc
class _$BridgeAgentState_ClosedCopyWithImpl<$Res>
    implements $BridgeAgentState_ClosedCopyWith<$Res> {
  _$BridgeAgentState_ClosedCopyWithImpl(this._self, this._then);

  final BridgeAgentState_Closed _self;
  final $Res Function(BridgeAgentState_Closed) _then;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAgentState_Closed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeClosedAgent,
  ));
}


}

/// @nodoc


class BridgeAgentState_CloseFailed extends BridgeAgentState {
  const BridgeAgentState_CloseFailed(this.field0): super._();


@override final  BridgeCloseFailedAgent field0;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentState_CloseFailedCopyWith<BridgeAgentState_CloseFailed> get copyWith => _$BridgeAgentState_CloseFailedCopyWithImpl<BridgeAgentState_CloseFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentState_CloseFailed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeAgentState.closeFailed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentState_CloseFailedCopyWith<$Res> implements $BridgeAgentStateCopyWith<$Res> {
  factory $BridgeAgentState_CloseFailedCopyWith(BridgeAgentState_CloseFailed value, $Res Function(BridgeAgentState_CloseFailed) _then) = _$BridgeAgentState_CloseFailedCopyWithImpl;
@useResult
$Res call({
 BridgeCloseFailedAgent field0
});




}
/// @nodoc
class _$BridgeAgentState_CloseFailedCopyWithImpl<$Res>
    implements $BridgeAgentState_CloseFailedCopyWith<$Res> {
  _$BridgeAgentState_CloseFailedCopyWithImpl(this._self, this._then);

  final BridgeAgentState_CloseFailed _self;
  final $Res Function(BridgeAgentState_CloseFailed) _then;

/// Create a copy of BridgeAgentState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeAgentState_CloseFailed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeCloseFailedAgent,
  ));
}


}

/// @nodoc
mixin _$BridgeLspActivity {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivity);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLspActivity()';
}


}

/// @nodoc
class $BridgeLspActivityCopyWith<$Res>  {
$BridgeLspActivityCopyWith(BridgeLspActivity _, $Res Function(BridgeLspActivity) __);
}


/// Adds pattern-matching-related methods to [BridgeLspActivity].
extension BridgeLspActivityPatterns on BridgeLspActivity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLspActivity_Idle value)?  idle,TResult Function( BridgeLspActivity_Busy value)?  busy,TResult Function( BridgeLspActivity_Indexing value)?  indexing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLspActivity_Idle() when idle != null:
return idle(_that);case BridgeLspActivity_Busy() when busy != null:
return busy(_that);case BridgeLspActivity_Indexing() when indexing != null:
return indexing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLspActivity_Idle value)  idle,required TResult Function( BridgeLspActivity_Busy value)  busy,required TResult Function( BridgeLspActivity_Indexing value)  indexing,}){
final _that = this;
switch (_that) {
case BridgeLspActivity_Idle():
return idle(_that);case BridgeLspActivity_Busy():
return busy(_that);case BridgeLspActivity_Indexing():
return indexing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLspActivity_Idle value)?  idle,TResult? Function( BridgeLspActivity_Busy value)?  busy,TResult? Function( BridgeLspActivity_Indexing value)?  indexing,}){
final _that = this;
switch (_that) {
case BridgeLspActivity_Idle() when idle != null:
return idle(_that);case BridgeLspActivity_Busy() when busy != null:
return busy(_that);case BridgeLspActivity_Indexing() when indexing != null:
return indexing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( String? title,  String? message,  int? percentage)?  busy,TResult Function( String? title,  String? message,  int? percentage)?  indexing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLspActivity_Idle() when idle != null:
return idle();case BridgeLspActivity_Busy() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case BridgeLspActivity_Indexing() when indexing != null:
return indexing(_that.title,_that.message,_that.percentage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( String? title,  String? message,  int? percentage)  busy,required TResult Function( String? title,  String? message,  int? percentage)  indexing,}) {final _that = this;
switch (_that) {
case BridgeLspActivity_Idle():
return idle();case BridgeLspActivity_Busy():
return busy(_that.title,_that.message,_that.percentage);case BridgeLspActivity_Indexing():
return indexing(_that.title,_that.message,_that.percentage);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( String? title,  String? message,  int? percentage)?  busy,TResult? Function( String? title,  String? message,  int? percentage)?  indexing,}) {final _that = this;
switch (_that) {
case BridgeLspActivity_Idle() when idle != null:
return idle();case BridgeLspActivity_Busy() when busy != null:
return busy(_that.title,_that.message,_that.percentage);case BridgeLspActivity_Indexing() when indexing != null:
return indexing(_that.title,_that.message,_that.percentage);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLspActivity_Idle extends BridgeLspActivity {
  const BridgeLspActivity_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivity_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLspActivity.idle()';
}


}




/// @nodoc


class BridgeLspActivity_Busy extends BridgeLspActivity {
  const BridgeLspActivity_Busy({this.title, this.message, this.percentage}): super._();


 final  String? title;
 final  String? message;
 final  int? percentage;

/// Create a copy of BridgeLspActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspActivity_BusyCopyWith<BridgeLspActivity_Busy> get copyWith => _$BridgeLspActivity_BusyCopyWithImpl<BridgeLspActivity_Busy>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivity_Busy&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}

@override
String toString() {
    return 'BridgeLspActivity.busy(title: $title, message: $message, percentage: $percentage)';
}


}

/// @nodoc
abstract mixin class $BridgeLspActivity_BusyCopyWith<$Res> implements $BridgeLspActivityCopyWith<$Res> {
  factory $BridgeLspActivity_BusyCopyWith(BridgeLspActivity_Busy value, $Res Function(BridgeLspActivity_Busy) _then) = _$BridgeLspActivity_BusyCopyWithImpl;
@useResult
$Res call({
 String? title, String? message, int? percentage
});




}
/// @nodoc
class _$BridgeLspActivity_BusyCopyWithImpl<$Res>
    implements $BridgeLspActivity_BusyCopyWith<$Res> {
  _$BridgeLspActivity_BusyCopyWithImpl(this._self, this._then);

  final BridgeLspActivity_Busy _self;
  final $Res Function(BridgeLspActivity_Busy) _then;

/// Create a copy of BridgeLspActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(BridgeLspActivity_Busy(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class BridgeLspActivity_Indexing extends BridgeLspActivity {
  const BridgeLspActivity_Indexing({this.title, this.message, this.percentage}): super._();


 final  String? title;
 final  String? message;
 final  int? percentage;

/// Create a copy of BridgeLspActivity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspActivity_IndexingCopyWith<BridgeLspActivity_Indexing> get copyWith => _$BridgeLspActivity_IndexingCopyWithImpl<BridgeLspActivity_Indexing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspActivity_Indexing&&(identical(other.title, title) || other.title == title)&&(identical(other.message, message) || other.message == message)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,title,message,percentage);
}

@override
String toString() {
    return 'BridgeLspActivity.indexing(title: $title, message: $message, percentage: $percentage)';
}


}

/// @nodoc
abstract mixin class $BridgeLspActivity_IndexingCopyWith<$Res> implements $BridgeLspActivityCopyWith<$Res> {
  factory $BridgeLspActivity_IndexingCopyWith(BridgeLspActivity_Indexing value, $Res Function(BridgeLspActivity_Indexing) _then) = _$BridgeLspActivity_IndexingCopyWithImpl;
@useResult
$Res call({
 String? title, String? message, int? percentage
});




}
/// @nodoc
class _$BridgeLspActivity_IndexingCopyWithImpl<$Res>
    implements $BridgeLspActivity_IndexingCopyWith<$Res> {
  _$BridgeLspActivity_IndexingCopyWithImpl(this._self, this._then);

  final BridgeLspActivity_Indexing _self;
  final $Res Function(BridgeLspActivity_Indexing) _then;

/// Create a copy of BridgeLspActivity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? message = freezed,Object? percentage = freezed,}) {
  return _then(BridgeLspActivity_Indexing(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$BridgeLspServerState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeLspServerState()';
}


}

/// @nodoc
class $BridgeLspServerStateCopyWith<$Res>  {
$BridgeLspServerStateCopyWith(BridgeLspServerState _, $Res Function(BridgeLspServerState) __);
}


/// Adds pattern-matching-related methods to [BridgeLspServerState].
extension BridgeLspServerStatePatterns on BridgeLspServerState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeLspServerState_Checking value)?  checking,TResult Function( BridgeLspServerState_Available value)?  available,TResult Function( BridgeLspServerState_Unavailable value)?  unavailable,TResult Function( BridgeLspServerState_Disabled value)?  disabled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeLspServerState_Checking() when checking != null:
return checking(_that);case BridgeLspServerState_Available() when available != null:
return available(_that);case BridgeLspServerState_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLspServerState_Disabled() when disabled != null:
return disabled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeLspServerState_Checking value)  checking,required TResult Function( BridgeLspServerState_Available value)  available,required TResult Function( BridgeLspServerState_Unavailable value)  unavailable,required TResult Function( BridgeLspServerState_Disabled value)  disabled,}){
final _that = this;
switch (_that) {
case BridgeLspServerState_Checking():
return checking(_that);case BridgeLspServerState_Available():
return available(_that);case BridgeLspServerState_Unavailable():
return unavailable(_that);case BridgeLspServerState_Disabled():
return disabled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeLspServerState_Checking value)?  checking,TResult? Function( BridgeLspServerState_Available value)?  available,TResult? Function( BridgeLspServerState_Unavailable value)?  unavailable,TResult? Function( BridgeLspServerState_Disabled value)?  disabled,}){
final _that = this;
switch (_that) {
case BridgeLspServerState_Checking() when checking != null:
return checking(_that);case BridgeLspServerState_Available() when available != null:
return available(_that);case BridgeLspServerState_Unavailable() when unavailable != null:
return unavailable(_that);case BridgeLspServerState_Disabled() when disabled != null:
return disabled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message)?  checking,TResult Function( PlatformInt64 checkedAt,  BigInt diagnosticCount,  BridgeLspActivity activity)?  available,TResult Function( PlatformInt64 checkedAt,  BridgeStateError error)?  unavailable,TResult Function( String message)?  disabled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeLspServerState_Checking() when checking != null:
return checking(_that.message);case BridgeLspServerState_Available() when available != null:
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);case BridgeLspServerState_Unavailable() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case BridgeLspServerState_Disabled() when disabled != null:
return disabled(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message)  checking,required TResult Function( PlatformInt64 checkedAt,  BigInt diagnosticCount,  BridgeLspActivity activity)  available,required TResult Function( PlatformInt64 checkedAt,  BridgeStateError error)  unavailable,required TResult Function( String message)  disabled,}) {final _that = this;
switch (_that) {
case BridgeLspServerState_Checking():
return checking(_that.message);case BridgeLspServerState_Available():
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);case BridgeLspServerState_Unavailable():
return unavailable(_that.checkedAt,_that.error);case BridgeLspServerState_Disabled():
return disabled(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message)?  checking,TResult? Function( PlatformInt64 checkedAt,  BigInt diagnosticCount,  BridgeLspActivity activity)?  available,TResult? Function( PlatformInt64 checkedAt,  BridgeStateError error)?  unavailable,TResult? Function( String message)?  disabled,}) {final _that = this;
switch (_that) {
case BridgeLspServerState_Checking() when checking != null:
return checking(_that.message);case BridgeLspServerState_Available() when available != null:
return available(_that.checkedAt,_that.diagnosticCount,_that.activity);case BridgeLspServerState_Unavailable() when unavailable != null:
return unavailable(_that.checkedAt,_that.error);case BridgeLspServerState_Disabled() when disabled != null:
return disabled(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class BridgeLspServerState_Checking extends BridgeLspServerState {
  const BridgeLspServerState_Checking({required this.message}): super._();


 final  String message;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerState_CheckingCopyWith<BridgeLspServerState_Checking> get copyWith => _$BridgeLspServerState_CheckingCopyWithImpl<BridgeLspServerState_Checking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerState_Checking&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'BridgeLspServerState.checking(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerState_CheckingCopyWith<$Res> implements $BridgeLspServerStateCopyWith<$Res> {
  factory $BridgeLspServerState_CheckingCopyWith(BridgeLspServerState_Checking value, $Res Function(BridgeLspServerState_Checking) _then) = _$BridgeLspServerState_CheckingCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$BridgeLspServerState_CheckingCopyWithImpl<$Res>
    implements $BridgeLspServerState_CheckingCopyWith<$Res> {
  _$BridgeLspServerState_CheckingCopyWithImpl(this._self, this._then);

  final BridgeLspServerState_Checking _self;
  final $Res Function(BridgeLspServerState_Checking) _then;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeLspServerState_Checking(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeLspServerState_Available extends BridgeLspServerState {
  const BridgeLspServerState_Available({required this.checkedAt, required this.diagnosticCount, required this.activity}): super._();


 final  PlatformInt64 checkedAt;
 final  BigInt diagnosticCount;
 final  BridgeLspActivity activity;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerState_AvailableCopyWith<BridgeLspServerState_Available> get copyWith => _$BridgeLspServerState_AvailableCopyWithImpl<BridgeLspServerState_Available>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerState_Available&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.diagnosticCount, diagnosticCount) || other.diagnosticCount == diagnosticCount)&&(identical(other.activity, activity) || other.activity == activity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,diagnosticCount,activity);
}

@override
String toString() {
    return 'BridgeLspServerState.available(checkedAt: $checkedAt, diagnosticCount: $diagnosticCount, activity: $activity)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerState_AvailableCopyWith<$Res> implements $BridgeLspServerStateCopyWith<$Res> {
  factory $BridgeLspServerState_AvailableCopyWith(BridgeLspServerState_Available value, $Res Function(BridgeLspServerState_Available) _then) = _$BridgeLspServerState_AvailableCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BigInt diagnosticCount, BridgeLspActivity activity
});


$BridgeLspActivityCopyWith<$Res> get activity;

}
/// @nodoc
class _$BridgeLspServerState_AvailableCopyWithImpl<$Res>
    implements $BridgeLspServerState_AvailableCopyWith<$Res> {
  _$BridgeLspServerState_AvailableCopyWithImpl(this._self, this._then);

  final BridgeLspServerState_Available _self;
  final $Res Function(BridgeLspServerState_Available) _then;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? diagnosticCount = null,Object? activity = null,}) {
  return _then(BridgeLspServerState_Available(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,diagnosticCount: null == diagnosticCount ? _self.diagnosticCount : diagnosticCount // ignore: cast_nullable_to_non_nullable
as BigInt,activity: null == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as BridgeLspActivity,
  ));
}

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeLspActivityCopyWith<$Res> get activity {

  return $BridgeLspActivityCopyWith<$Res>(_self.activity, (value) {
    return _then(_self.copyWith(activity: value));
  });
}
}

/// @nodoc


class BridgeLspServerState_Unavailable extends BridgeLspServerState {
  const BridgeLspServerState_Unavailable({required this.checkedAt, required this.error}): super._();


 final  PlatformInt64 checkedAt;
 final  BridgeStateError error;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerState_UnavailableCopyWith<BridgeLspServerState_Unavailable> get copyWith => _$BridgeLspServerState_UnavailableCopyWithImpl<BridgeLspServerState_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerState_Unavailable&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,error);
}

@override
String toString() {
    return 'BridgeLspServerState.unavailable(checkedAt: $checkedAt, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerState_UnavailableCopyWith<$Res> implements $BridgeLspServerStateCopyWith<$Res> {
  factory $BridgeLspServerState_UnavailableCopyWith(BridgeLspServerState_Unavailable value, $Res Function(BridgeLspServerState_Unavailable) _then) = _$BridgeLspServerState_UnavailableCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BridgeStateError error
});




}
/// @nodoc
class _$BridgeLspServerState_UnavailableCopyWithImpl<$Res>
    implements $BridgeLspServerState_UnavailableCopyWith<$Res> {
  _$BridgeLspServerState_UnavailableCopyWithImpl(this._self, this._then);

  final BridgeLspServerState_Unavailable _self;
  final $Res Function(BridgeLspServerState_Unavailable) _then;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? error = null,}) {
  return _then(BridgeLspServerState_Unavailable(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeStateError,
  ));
}


}

/// @nodoc


class BridgeLspServerState_Disabled extends BridgeLspServerState {
  const BridgeLspServerState_Disabled({required this.message}): super._();


 final  String message;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeLspServerState_DisabledCopyWith<BridgeLspServerState_Disabled> get copyWith => _$BridgeLspServerState_DisabledCopyWithImpl<BridgeLspServerState_Disabled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeLspServerState_Disabled&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'BridgeLspServerState.disabled(message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeLspServerState_DisabledCopyWith<$Res> implements $BridgeLspServerStateCopyWith<$Res> {
  factory $BridgeLspServerState_DisabledCopyWith(BridgeLspServerState_Disabled value, $Res Function(BridgeLspServerState_Disabled) _then) = _$BridgeLspServerState_DisabledCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$BridgeLspServerState_DisabledCopyWithImpl<$Res>
    implements $BridgeLspServerState_DisabledCopyWith<$Res> {
  _$BridgeLspServerState_DisabledCopyWithImpl(this._self, this._then);

  final BridgeLspServerState_Disabled _self;
  final $Res Function(BridgeLspServerState_Disabled) _then;

/// Create a copy of BridgeLspServerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(BridgeLspServerState_Disabled(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeRuntimeState {

 Object get field0;



@override
bool operator ==(Object other) {
  final _this = this as BridgeRuntimeState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeState&&const DeepCollectionEquality().equals(other.field0, _this.field0));
}


@override
int get hashCode {
  final _this = this as BridgeRuntimeState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.field0));
}

@override
String toString() {
  final _this = this as BridgeRuntimeState;
  return 'BridgeRuntimeState(field0: ${_this.field0})';
}


}

/// @nodoc
class $BridgeRuntimeStateCopyWith<$Res>  {
$BridgeRuntimeStateCopyWith(BridgeRuntimeState _, $Res Function(BridgeRuntimeState) __);
}


/// Adds pattern-matching-related methods to [BridgeRuntimeState].
extension BridgeRuntimeStatePatterns on BridgeRuntimeState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeRuntimeState_Uninitialized value)?  uninitialized,TResult Function( BridgeRuntimeState_Initializing value)?  initializing,TResult Function( BridgeRuntimeState_Ready value)?  ready,TResult Function( BridgeRuntimeState_ShuttingDown value)?  shuttingDown,TResult Function( BridgeRuntimeState_Stopped value)?  stopped,TResult Function( BridgeRuntimeState_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeRuntimeState_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeRuntimeState_Initializing() when initializing != null:
return initializing(_that);case BridgeRuntimeState_Ready() when ready != null:
return ready(_that);case BridgeRuntimeState_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case BridgeRuntimeState_Stopped() when stopped != null:
return stopped(_that);case BridgeRuntimeState_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeRuntimeState_Uninitialized value)  uninitialized,required TResult Function( BridgeRuntimeState_Initializing value)  initializing,required TResult Function( BridgeRuntimeState_Ready value)  ready,required TResult Function( BridgeRuntimeState_ShuttingDown value)  shuttingDown,required TResult Function( BridgeRuntimeState_Stopped value)  stopped,required TResult Function( BridgeRuntimeState_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeRuntimeState_Uninitialized():
return uninitialized(_that);case BridgeRuntimeState_Initializing():
return initializing(_that);case BridgeRuntimeState_Ready():
return ready(_that);case BridgeRuntimeState_ShuttingDown():
return shuttingDown(_that);case BridgeRuntimeState_Stopped():
return stopped(_that);case BridgeRuntimeState_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeRuntimeState_Uninitialized value)?  uninitialized,TResult? Function( BridgeRuntimeState_Initializing value)?  initializing,TResult? Function( BridgeRuntimeState_Ready value)?  ready,TResult? Function( BridgeRuntimeState_ShuttingDown value)?  shuttingDown,TResult? Function( BridgeRuntimeState_Stopped value)?  stopped,TResult? Function( BridgeRuntimeState_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeRuntimeState_Uninitialized() when uninitialized != null:
return uninitialized(_that);case BridgeRuntimeState_Initializing() when initializing != null:
return initializing(_that);case BridgeRuntimeState_Ready() when ready != null:
return ready(_that);case BridgeRuntimeState_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that);case BridgeRuntimeState_Stopped() when stopped != null:
return stopped(_that);case BridgeRuntimeState_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeRuntimeTimestamp field0)?  uninitialized,TResult Function( BridgeRuntimeTimestamp field0)?  initializing,TResult Function( BridgeRuntimeTimestamp field0)?  ready,TResult Function( BridgeRuntimeTimestamp field0)?  shuttingDown,TResult Function( BridgeRuntimeTimestamp field0)?  stopped,TResult Function( BridgeFailedRuntimeState field0)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeRuntimeState_Uninitialized() when uninitialized != null:
return uninitialized(_that.field0);case BridgeRuntimeState_Initializing() when initializing != null:
return initializing(_that.field0);case BridgeRuntimeState_Ready() when ready != null:
return ready(_that.field0);case BridgeRuntimeState_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that.field0);case BridgeRuntimeState_Stopped() when stopped != null:
return stopped(_that.field0);case BridgeRuntimeState_Failed() when failed != null:
return failed(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeRuntimeTimestamp field0)  uninitialized,required TResult Function( BridgeRuntimeTimestamp field0)  initializing,required TResult Function( BridgeRuntimeTimestamp field0)  ready,required TResult Function( BridgeRuntimeTimestamp field0)  shuttingDown,required TResult Function( BridgeRuntimeTimestamp field0)  stopped,required TResult Function( BridgeFailedRuntimeState field0)  failed,}) {final _that = this;
switch (_that) {
case BridgeRuntimeState_Uninitialized():
return uninitialized(_that.field0);case BridgeRuntimeState_Initializing():
return initializing(_that.field0);case BridgeRuntimeState_Ready():
return ready(_that.field0);case BridgeRuntimeState_ShuttingDown():
return shuttingDown(_that.field0);case BridgeRuntimeState_Stopped():
return stopped(_that.field0);case BridgeRuntimeState_Failed():
return failed(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeRuntimeTimestamp field0)?  uninitialized,TResult? Function( BridgeRuntimeTimestamp field0)?  initializing,TResult? Function( BridgeRuntimeTimestamp field0)?  ready,TResult? Function( BridgeRuntimeTimestamp field0)?  shuttingDown,TResult? Function( BridgeRuntimeTimestamp field0)?  stopped,TResult? Function( BridgeFailedRuntimeState field0)?  failed,}) {final _that = this;
switch (_that) {
case BridgeRuntimeState_Uninitialized() when uninitialized != null:
return uninitialized(_that.field0);case BridgeRuntimeState_Initializing() when initializing != null:
return initializing(_that.field0);case BridgeRuntimeState_Ready() when ready != null:
return ready(_that.field0);case BridgeRuntimeState_ShuttingDown() when shuttingDown != null:
return shuttingDown(_that.field0);case BridgeRuntimeState_Stopped() when stopped != null:
return stopped(_that.field0);case BridgeRuntimeState_Failed() when failed != null:
return failed(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class BridgeRuntimeState_Uninitialized extends BridgeRuntimeState {
  const BridgeRuntimeState_Uninitialized(this.field0): super._();


@override final  BridgeRuntimeTimestamp field0;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeState_UninitializedCopyWith<BridgeRuntimeState_Uninitialized> get copyWith => _$BridgeRuntimeState_UninitializedCopyWithImpl<BridgeRuntimeState_Uninitialized>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeState_Uninitialized&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeRuntimeState.uninitialized(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeState_UninitializedCopyWith<$Res> implements $BridgeRuntimeStateCopyWith<$Res> {
  factory $BridgeRuntimeState_UninitializedCopyWith(BridgeRuntimeState_Uninitialized value, $Res Function(BridgeRuntimeState_Uninitialized) _then) = _$BridgeRuntimeState_UninitializedCopyWithImpl;
@useResult
$Res call({
 BridgeRuntimeTimestamp field0
});




}
/// @nodoc
class _$BridgeRuntimeState_UninitializedCopyWithImpl<$Res>
    implements $BridgeRuntimeState_UninitializedCopyWith<$Res> {
  _$BridgeRuntimeState_UninitializedCopyWithImpl(this._self, this._then);

  final BridgeRuntimeState_Uninitialized _self;
  final $Res Function(BridgeRuntimeState_Uninitialized) _then;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeRuntimeState_Uninitialized(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeRuntimeTimestamp,
  ));
}


}

/// @nodoc


class BridgeRuntimeState_Initializing extends BridgeRuntimeState {
  const BridgeRuntimeState_Initializing(this.field0): super._();


@override final  BridgeRuntimeTimestamp field0;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeState_InitializingCopyWith<BridgeRuntimeState_Initializing> get copyWith => _$BridgeRuntimeState_InitializingCopyWithImpl<BridgeRuntimeState_Initializing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeState_Initializing&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeRuntimeState.initializing(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeState_InitializingCopyWith<$Res> implements $BridgeRuntimeStateCopyWith<$Res> {
  factory $BridgeRuntimeState_InitializingCopyWith(BridgeRuntimeState_Initializing value, $Res Function(BridgeRuntimeState_Initializing) _then) = _$BridgeRuntimeState_InitializingCopyWithImpl;
@useResult
$Res call({
 BridgeRuntimeTimestamp field0
});




}
/// @nodoc
class _$BridgeRuntimeState_InitializingCopyWithImpl<$Res>
    implements $BridgeRuntimeState_InitializingCopyWith<$Res> {
  _$BridgeRuntimeState_InitializingCopyWithImpl(this._self, this._then);

  final BridgeRuntimeState_Initializing _self;
  final $Res Function(BridgeRuntimeState_Initializing) _then;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeRuntimeState_Initializing(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeRuntimeTimestamp,
  ));
}


}

/// @nodoc


class BridgeRuntimeState_Ready extends BridgeRuntimeState {
  const BridgeRuntimeState_Ready(this.field0): super._();


@override final  BridgeRuntimeTimestamp field0;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeState_ReadyCopyWith<BridgeRuntimeState_Ready> get copyWith => _$BridgeRuntimeState_ReadyCopyWithImpl<BridgeRuntimeState_Ready>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeState_Ready&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeRuntimeState.ready(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeState_ReadyCopyWith<$Res> implements $BridgeRuntimeStateCopyWith<$Res> {
  factory $BridgeRuntimeState_ReadyCopyWith(BridgeRuntimeState_Ready value, $Res Function(BridgeRuntimeState_Ready) _then) = _$BridgeRuntimeState_ReadyCopyWithImpl;
@useResult
$Res call({
 BridgeRuntimeTimestamp field0
});




}
/// @nodoc
class _$BridgeRuntimeState_ReadyCopyWithImpl<$Res>
    implements $BridgeRuntimeState_ReadyCopyWith<$Res> {
  _$BridgeRuntimeState_ReadyCopyWithImpl(this._self, this._then);

  final BridgeRuntimeState_Ready _self;
  final $Res Function(BridgeRuntimeState_Ready) _then;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeRuntimeState_Ready(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeRuntimeTimestamp,
  ));
}


}

/// @nodoc


class BridgeRuntimeState_ShuttingDown extends BridgeRuntimeState {
  const BridgeRuntimeState_ShuttingDown(this.field0): super._();


@override final  BridgeRuntimeTimestamp field0;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeState_ShuttingDownCopyWith<BridgeRuntimeState_ShuttingDown> get copyWith => _$BridgeRuntimeState_ShuttingDownCopyWithImpl<BridgeRuntimeState_ShuttingDown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeState_ShuttingDown&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeRuntimeState.shuttingDown(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeState_ShuttingDownCopyWith<$Res> implements $BridgeRuntimeStateCopyWith<$Res> {
  factory $BridgeRuntimeState_ShuttingDownCopyWith(BridgeRuntimeState_ShuttingDown value, $Res Function(BridgeRuntimeState_ShuttingDown) _then) = _$BridgeRuntimeState_ShuttingDownCopyWithImpl;
@useResult
$Res call({
 BridgeRuntimeTimestamp field0
});




}
/// @nodoc
class _$BridgeRuntimeState_ShuttingDownCopyWithImpl<$Res>
    implements $BridgeRuntimeState_ShuttingDownCopyWith<$Res> {
  _$BridgeRuntimeState_ShuttingDownCopyWithImpl(this._self, this._then);

  final BridgeRuntimeState_ShuttingDown _self;
  final $Res Function(BridgeRuntimeState_ShuttingDown) _then;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeRuntimeState_ShuttingDown(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeRuntimeTimestamp,
  ));
}


}

/// @nodoc


class BridgeRuntimeState_Stopped extends BridgeRuntimeState {
  const BridgeRuntimeState_Stopped(this.field0): super._();


@override final  BridgeRuntimeTimestamp field0;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeState_StoppedCopyWith<BridgeRuntimeState_Stopped> get copyWith => _$BridgeRuntimeState_StoppedCopyWithImpl<BridgeRuntimeState_Stopped>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeState_Stopped&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeRuntimeState.stopped(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeState_StoppedCopyWith<$Res> implements $BridgeRuntimeStateCopyWith<$Res> {
  factory $BridgeRuntimeState_StoppedCopyWith(BridgeRuntimeState_Stopped value, $Res Function(BridgeRuntimeState_Stopped) _then) = _$BridgeRuntimeState_StoppedCopyWithImpl;
@useResult
$Res call({
 BridgeRuntimeTimestamp field0
});




}
/// @nodoc
class _$BridgeRuntimeState_StoppedCopyWithImpl<$Res>
    implements $BridgeRuntimeState_StoppedCopyWith<$Res> {
  _$BridgeRuntimeState_StoppedCopyWithImpl(this._self, this._then);

  final BridgeRuntimeState_Stopped _self;
  final $Res Function(BridgeRuntimeState_Stopped) _then;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeRuntimeState_Stopped(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeRuntimeTimestamp,
  ));
}


}

/// @nodoc


class BridgeRuntimeState_Failed extends BridgeRuntimeState {
  const BridgeRuntimeState_Failed(this.field0): super._();


@override final  BridgeFailedRuntimeState field0;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeRuntimeState_FailedCopyWith<BridgeRuntimeState_Failed> get copyWith => _$BridgeRuntimeState_FailedCopyWithImpl<BridgeRuntimeState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeRuntimeState_Failed&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field0);
}

@override
String toString() {
    return 'BridgeRuntimeState.failed(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $BridgeRuntimeState_FailedCopyWith<$Res> implements $BridgeRuntimeStateCopyWith<$Res> {
  factory $BridgeRuntimeState_FailedCopyWith(BridgeRuntimeState_Failed value, $Res Function(BridgeRuntimeState_Failed) _then) = _$BridgeRuntimeState_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeFailedRuntimeState field0
});




}
/// @nodoc
class _$BridgeRuntimeState_FailedCopyWithImpl<$Res>
    implements $BridgeRuntimeState_FailedCopyWith<$Res> {
  _$BridgeRuntimeState_FailedCopyWithImpl(this._self, this._then);

  final BridgeRuntimeState_Failed _self;
  final $Res Function(BridgeRuntimeState_Failed) _then;

/// Create a copy of BridgeRuntimeState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(BridgeRuntimeState_Failed(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as BridgeFailedRuntimeState,
  ));
}


}

// dart format on
