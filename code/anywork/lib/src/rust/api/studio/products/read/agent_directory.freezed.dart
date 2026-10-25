// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_directory.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAgentStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAgentStateRead()';
}


}

/// @nodoc
class $BridgeAgentStateReadCopyWith<$Res>  {
$BridgeAgentStateReadCopyWith(BridgeAgentStateRead _, $Res Function(BridgeAgentStateRead) __);
}


/// Adds pattern-matching-related methods to [BridgeAgentStateRead].
extension BridgeAgentStateReadPatterns on BridgeAgentStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAgentStateRead_Idle value)?  idle,TResult Function( BridgeAgentStateRead_Queued value)?  queued,TResult Function( BridgeAgentStateRead_Running value)?  running,TResult Function( BridgeAgentStateRead_WaitingTool value)?  waitingTool,TResult Function( BridgeAgentStateRead_WaitingInteraction value)?  waitingInteraction,TResult Function( BridgeAgentStateRead_Cancelling value)?  cancelling,TResult Function( BridgeAgentStateRead_Closing value)?  closing,TResult Function( BridgeAgentStateRead_Closed value)?  closed,TResult Function( BridgeAgentStateRead_Faulted value)?  faulted,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAgentStateRead_Idle() when idle != null:
return idle(_that);case BridgeAgentStateRead_Queued() when queued != null:
return queued(_that);case BridgeAgentStateRead_Running() when running != null:
return running(_that);case BridgeAgentStateRead_WaitingTool() when waitingTool != null:
return waitingTool(_that);case BridgeAgentStateRead_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that);case BridgeAgentStateRead_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAgentStateRead_Closing() when closing != null:
return closing(_that);case BridgeAgentStateRead_Closed() when closed != null:
return closed(_that);case BridgeAgentStateRead_Faulted() when faulted != null:
return faulted(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAgentStateRead_Idle value)  idle,required TResult Function( BridgeAgentStateRead_Queued value)  queued,required TResult Function( BridgeAgentStateRead_Running value)  running,required TResult Function( BridgeAgentStateRead_WaitingTool value)  waitingTool,required TResult Function( BridgeAgentStateRead_WaitingInteraction value)  waitingInteraction,required TResult Function( BridgeAgentStateRead_Cancelling value)  cancelling,required TResult Function( BridgeAgentStateRead_Closing value)  closing,required TResult Function( BridgeAgentStateRead_Closed value)  closed,required TResult Function( BridgeAgentStateRead_Faulted value)  faulted,}){
final _that = this;
switch (_that) {
case BridgeAgentStateRead_Idle():
return idle(_that);case BridgeAgentStateRead_Queued():
return queued(_that);case BridgeAgentStateRead_Running():
return running(_that);case BridgeAgentStateRead_WaitingTool():
return waitingTool(_that);case BridgeAgentStateRead_WaitingInteraction():
return waitingInteraction(_that);case BridgeAgentStateRead_Cancelling():
return cancelling(_that);case BridgeAgentStateRead_Closing():
return closing(_that);case BridgeAgentStateRead_Closed():
return closed(_that);case BridgeAgentStateRead_Faulted():
return faulted(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAgentStateRead_Idle value)?  idle,TResult? Function( BridgeAgentStateRead_Queued value)?  queued,TResult? Function( BridgeAgentStateRead_Running value)?  running,TResult? Function( BridgeAgentStateRead_WaitingTool value)?  waitingTool,TResult? Function( BridgeAgentStateRead_WaitingInteraction value)?  waitingInteraction,TResult? Function( BridgeAgentStateRead_Cancelling value)?  cancelling,TResult? Function( BridgeAgentStateRead_Closing value)?  closing,TResult? Function( BridgeAgentStateRead_Closed value)?  closed,TResult? Function( BridgeAgentStateRead_Faulted value)?  faulted,}){
final _that = this;
switch (_that) {
case BridgeAgentStateRead_Idle() when idle != null:
return idle(_that);case BridgeAgentStateRead_Queued() when queued != null:
return queued(_that);case BridgeAgentStateRead_Running() when running != null:
return running(_that);case BridgeAgentStateRead_WaitingTool() when waitingTool != null:
return waitingTool(_that);case BridgeAgentStateRead_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that);case BridgeAgentStateRead_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAgentStateRead_Closing() when closing != null:
return closing(_that);case BridgeAgentStateRead_Closed() when closed != null:
return closed(_that);case BridgeAgentStateRead_Faulted() when faulted != null:
return faulted(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeAgentBudgetPauseRead? budgetPause)?  idle,TResult Function( BridgeReadText turnId)?  queued,TResult Function( BridgeReadText turnId)?  running,TResult Function( BridgeReadText turnId)?  waitingTool,TResult Function( BridgeReadText turnId,  BridgeReadText interactionId)?  waitingInteraction,TResult Function( BridgeReadText turnId)?  cancelling,TResult Function( BridgeAgentWorkspaceDisposition workspaceDisposition,  BridgeReadText? turnId,  BridgeSourceStateErrorRead? error)?  closing,TResult Function()?  closed,TResult Function( BridgeSourceStateErrorRead error,  BridgeReadText? turnId,  BridgeAgentFaultClassification classification)?  faulted,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAgentStateRead_Idle() when idle != null:
return idle(_that.budgetPause);case BridgeAgentStateRead_Queued() when queued != null:
return queued(_that.turnId);case BridgeAgentStateRead_Running() when running != null:
return running(_that.turnId);case BridgeAgentStateRead_WaitingTool() when waitingTool != null:
return waitingTool(_that.turnId);case BridgeAgentStateRead_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that.turnId,_that.interactionId);case BridgeAgentStateRead_Cancelling() when cancelling != null:
return cancelling(_that.turnId);case BridgeAgentStateRead_Closing() when closing != null:
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case BridgeAgentStateRead_Closed() when closed != null:
return closed();case BridgeAgentStateRead_Faulted() when faulted != null:
return faulted(_that.error,_that.turnId,_that.classification);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeAgentBudgetPauseRead? budgetPause)  idle,required TResult Function( BridgeReadText turnId)  queued,required TResult Function( BridgeReadText turnId)  running,required TResult Function( BridgeReadText turnId)  waitingTool,required TResult Function( BridgeReadText turnId,  BridgeReadText interactionId)  waitingInteraction,required TResult Function( BridgeReadText turnId)  cancelling,required TResult Function( BridgeAgentWorkspaceDisposition workspaceDisposition,  BridgeReadText? turnId,  BridgeSourceStateErrorRead? error)  closing,required TResult Function()  closed,required TResult Function( BridgeSourceStateErrorRead error,  BridgeReadText? turnId,  BridgeAgentFaultClassification classification)  faulted,}) {final _that = this;
switch (_that) {
case BridgeAgentStateRead_Idle():
return idle(_that.budgetPause);case BridgeAgentStateRead_Queued():
return queued(_that.turnId);case BridgeAgentStateRead_Running():
return running(_that.turnId);case BridgeAgentStateRead_WaitingTool():
return waitingTool(_that.turnId);case BridgeAgentStateRead_WaitingInteraction():
return waitingInteraction(_that.turnId,_that.interactionId);case BridgeAgentStateRead_Cancelling():
return cancelling(_that.turnId);case BridgeAgentStateRead_Closing():
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case BridgeAgentStateRead_Closed():
return closed();case BridgeAgentStateRead_Faulted():
return faulted(_that.error,_that.turnId,_that.classification);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeAgentBudgetPauseRead? budgetPause)?  idle,TResult? Function( BridgeReadText turnId)?  queued,TResult? Function( BridgeReadText turnId)?  running,TResult? Function( BridgeReadText turnId)?  waitingTool,TResult? Function( BridgeReadText turnId,  BridgeReadText interactionId)?  waitingInteraction,TResult? Function( BridgeReadText turnId)?  cancelling,TResult? Function( BridgeAgentWorkspaceDisposition workspaceDisposition,  BridgeReadText? turnId,  BridgeSourceStateErrorRead? error)?  closing,TResult? Function()?  closed,TResult? Function( BridgeSourceStateErrorRead error,  BridgeReadText? turnId,  BridgeAgentFaultClassification classification)?  faulted,}) {final _that = this;
switch (_that) {
case BridgeAgentStateRead_Idle() when idle != null:
return idle(_that.budgetPause);case BridgeAgentStateRead_Queued() when queued != null:
return queued(_that.turnId);case BridgeAgentStateRead_Running() when running != null:
return running(_that.turnId);case BridgeAgentStateRead_WaitingTool() when waitingTool != null:
return waitingTool(_that.turnId);case BridgeAgentStateRead_WaitingInteraction() when waitingInteraction != null:
return waitingInteraction(_that.turnId,_that.interactionId);case BridgeAgentStateRead_Cancelling() when cancelling != null:
return cancelling(_that.turnId);case BridgeAgentStateRead_Closing() when closing != null:
return closing(_that.workspaceDisposition,_that.turnId,_that.error);case BridgeAgentStateRead_Closed() when closed != null:
return closed();case BridgeAgentStateRead_Faulted() when faulted != null:
return faulted(_that.error,_that.turnId,_that.classification);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAgentStateRead_Idle extends BridgeAgentStateRead {
  const BridgeAgentStateRead_Idle({this.budgetPause}): super._();


 final  BridgeAgentBudgetPauseRead? budgetPause;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_IdleCopyWith<BridgeAgentStateRead_Idle> get copyWith => _$BridgeAgentStateRead_IdleCopyWithImpl<BridgeAgentStateRead_Idle>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_Idle&&(identical(other.budgetPause, budgetPause) || other.budgetPause == budgetPause));
}


@override
int get hashCode {
    return Object.hash(runtimeType,budgetPause);
}

@override
String toString() {
    return 'BridgeAgentStateRead.idle(budgetPause: $budgetPause)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_IdleCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_IdleCopyWith(BridgeAgentStateRead_Idle value, $Res Function(BridgeAgentStateRead_Idle) _then) = _$BridgeAgentStateRead_IdleCopyWithImpl;
@useResult
$Res call({
 BridgeAgentBudgetPauseRead? budgetPause
});




}
/// @nodoc
class _$BridgeAgentStateRead_IdleCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_IdleCopyWith<$Res> {
  _$BridgeAgentStateRead_IdleCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_Idle _self;
  final $Res Function(BridgeAgentStateRead_Idle) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? budgetPause = freezed,}) {
  return _then(BridgeAgentStateRead_Idle(
budgetPause: freezed == budgetPause ? _self.budgetPause : budgetPause // ignore: cast_nullable_to_non_nullable
as BridgeAgentBudgetPauseRead?,
  ));
}


}

/// @nodoc


class BridgeAgentStateRead_Queued extends BridgeAgentStateRead {
  const BridgeAgentStateRead_Queued({required this.turnId}): super._();


 final  BridgeReadText turnId;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_QueuedCopyWith<BridgeAgentStateRead_Queued> get copyWith => _$BridgeAgentStateRead_QueuedCopyWithImpl<BridgeAgentStateRead_Queued>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_Queued&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'BridgeAgentStateRead.queued(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_QueuedCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_QueuedCopyWith(BridgeAgentStateRead_Queued value, $Res Function(BridgeAgentStateRead_Queued) _then) = _$BridgeAgentStateRead_QueuedCopyWithImpl;
@useResult
$Res call({
 BridgeReadText turnId
});


$BridgeReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$BridgeAgentStateRead_QueuedCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_QueuedCopyWith<$Res> {
  _$BridgeAgentStateRead_QueuedCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_Queued _self;
  final $Res Function(BridgeAgentStateRead_Queued) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(BridgeAgentStateRead_Queued(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get turnId {

  return $BridgeReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class BridgeAgentStateRead_Running extends BridgeAgentStateRead {
  const BridgeAgentStateRead_Running({required this.turnId}): super._();


 final  BridgeReadText turnId;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_RunningCopyWith<BridgeAgentStateRead_Running> get copyWith => _$BridgeAgentStateRead_RunningCopyWithImpl<BridgeAgentStateRead_Running>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_Running&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'BridgeAgentStateRead.running(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_RunningCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_RunningCopyWith(BridgeAgentStateRead_Running value, $Res Function(BridgeAgentStateRead_Running) _then) = _$BridgeAgentStateRead_RunningCopyWithImpl;
@useResult
$Res call({
 BridgeReadText turnId
});


$BridgeReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$BridgeAgentStateRead_RunningCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_RunningCopyWith<$Res> {
  _$BridgeAgentStateRead_RunningCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_Running _self;
  final $Res Function(BridgeAgentStateRead_Running) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(BridgeAgentStateRead_Running(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get turnId {

  return $BridgeReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class BridgeAgentStateRead_WaitingTool extends BridgeAgentStateRead {
  const BridgeAgentStateRead_WaitingTool({required this.turnId}): super._();


 final  BridgeReadText turnId;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_WaitingToolCopyWith<BridgeAgentStateRead_WaitingTool> get copyWith => _$BridgeAgentStateRead_WaitingToolCopyWithImpl<BridgeAgentStateRead_WaitingTool>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_WaitingTool&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'BridgeAgentStateRead.waitingTool(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_WaitingToolCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_WaitingToolCopyWith(BridgeAgentStateRead_WaitingTool value, $Res Function(BridgeAgentStateRead_WaitingTool) _then) = _$BridgeAgentStateRead_WaitingToolCopyWithImpl;
@useResult
$Res call({
 BridgeReadText turnId
});


$BridgeReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$BridgeAgentStateRead_WaitingToolCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_WaitingToolCopyWith<$Res> {
  _$BridgeAgentStateRead_WaitingToolCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_WaitingTool _self;
  final $Res Function(BridgeAgentStateRead_WaitingTool) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(BridgeAgentStateRead_WaitingTool(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get turnId {

  return $BridgeReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class BridgeAgentStateRead_WaitingInteraction extends BridgeAgentStateRead {
  const BridgeAgentStateRead_WaitingInteraction({required this.turnId, required this.interactionId}): super._();


 final  BridgeReadText turnId;
 final  BridgeReadText interactionId;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_WaitingInteractionCopyWith<BridgeAgentStateRead_WaitingInteraction> get copyWith => _$BridgeAgentStateRead_WaitingInteractionCopyWithImpl<BridgeAgentStateRead_WaitingInteraction>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_WaitingInteraction&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.interactionId, interactionId) || other.interactionId == interactionId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId,interactionId);
}

@override
String toString() {
    return 'BridgeAgentStateRead.waitingInteraction(turnId: $turnId, interactionId: $interactionId)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_WaitingInteractionCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_WaitingInteractionCopyWith(BridgeAgentStateRead_WaitingInteraction value, $Res Function(BridgeAgentStateRead_WaitingInteraction) _then) = _$BridgeAgentStateRead_WaitingInteractionCopyWithImpl;
@useResult
$Res call({
 BridgeReadText turnId, BridgeReadText interactionId
});


$BridgeReadTextCopyWith<$Res> get turnId;$BridgeReadTextCopyWith<$Res> get interactionId;

}
/// @nodoc
class _$BridgeAgentStateRead_WaitingInteractionCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_WaitingInteractionCopyWith<$Res> {
  _$BridgeAgentStateRead_WaitingInteractionCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_WaitingInteraction _self;
  final $Res Function(BridgeAgentStateRead_WaitingInteraction) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,Object? interactionId = null,}) {
  return _then(BridgeAgentStateRead_WaitingInteraction(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get turnId {

  return $BridgeReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get interactionId {

  return $BridgeReadTextCopyWith<$Res>(_self.interactionId, (value) {
    return _then(_self.copyWith(interactionId: value));
  });
}
}

/// @nodoc


class BridgeAgentStateRead_Cancelling extends BridgeAgentStateRead {
  const BridgeAgentStateRead_Cancelling({required this.turnId}): super._();


 final  BridgeReadText turnId;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_CancellingCopyWith<BridgeAgentStateRead_Cancelling> get copyWith => _$BridgeAgentStateRead_CancellingCopyWithImpl<BridgeAgentStateRead_Cancelling>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_Cancelling&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'BridgeAgentStateRead.cancelling(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_CancellingCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_CancellingCopyWith(BridgeAgentStateRead_Cancelling value, $Res Function(BridgeAgentStateRead_Cancelling) _then) = _$BridgeAgentStateRead_CancellingCopyWithImpl;
@useResult
$Res call({
 BridgeReadText turnId
});


$BridgeReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$BridgeAgentStateRead_CancellingCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_CancellingCopyWith<$Res> {
  _$BridgeAgentStateRead_CancellingCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_Cancelling _self;
  final $Res Function(BridgeAgentStateRead_Cancelling) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(BridgeAgentStateRead_Cancelling(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get turnId {

  return $BridgeReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class BridgeAgentStateRead_Closing extends BridgeAgentStateRead {
  const BridgeAgentStateRead_Closing({required this.workspaceDisposition, this.turnId, this.error}): super._();


 final  BridgeAgentWorkspaceDisposition workspaceDisposition;
 final  BridgeReadText? turnId;
 final  BridgeSourceStateErrorRead? error;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_ClosingCopyWith<BridgeAgentStateRead_Closing> get copyWith => _$BridgeAgentStateRead_ClosingCopyWithImpl<BridgeAgentStateRead_Closing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_Closing&&(identical(other.workspaceDisposition, workspaceDisposition) || other.workspaceDisposition == workspaceDisposition)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,workspaceDisposition,turnId,error);
}

@override
String toString() {
    return 'BridgeAgentStateRead.closing(workspaceDisposition: $workspaceDisposition, turnId: $turnId, error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_ClosingCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_ClosingCopyWith(BridgeAgentStateRead_Closing value, $Res Function(BridgeAgentStateRead_Closing) _then) = _$BridgeAgentStateRead_ClosingCopyWithImpl;
@useResult
$Res call({
 BridgeAgentWorkspaceDisposition workspaceDisposition, BridgeReadText? turnId, BridgeSourceStateErrorRead? error
});


$BridgeReadTextCopyWith<$Res>? get turnId;

}
/// @nodoc
class _$BridgeAgentStateRead_ClosingCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_ClosingCopyWith<$Res> {
  _$BridgeAgentStateRead_ClosingCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_Closing _self;
  final $Res Function(BridgeAgentStateRead_Closing) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? workspaceDisposition = null,Object? turnId = freezed,Object? error = freezed,}) {
  return _then(BridgeAgentStateRead_Closing(
workspaceDisposition: null == workspaceDisposition ? _self.workspaceDisposition : workspaceDisposition // ignore: cast_nullable_to_non_nullable
as BridgeAgentWorkspaceDisposition,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead?,
  ));
}

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get turnId {
    if (_self.turnId == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.turnId!, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc


class BridgeAgentStateRead_Closed extends BridgeAgentStateRead {
  const BridgeAgentStateRead_Closed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_Closed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAgentStateRead.closed()';
}


}




/// @nodoc


class BridgeAgentStateRead_Faulted extends BridgeAgentStateRead {
  const BridgeAgentStateRead_Faulted({required this.error, this.turnId, required this.classification}): super._();


 final  BridgeSourceStateErrorRead error;
 final  BridgeReadText? turnId;
 final  BridgeAgentFaultClassification classification;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAgentStateRead_FaultedCopyWith<BridgeAgentStateRead_Faulted> get copyWith => _$BridgeAgentStateRead_FaultedCopyWithImpl<BridgeAgentStateRead_Faulted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAgentStateRead_Faulted&&(identical(other.error, error) || other.error == error)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.classification, classification) || other.classification == classification));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error,turnId,classification);
}

@override
String toString() {
    return 'BridgeAgentStateRead.faulted(error: $error, turnId: $turnId, classification: $classification)';
}


}

/// @nodoc
abstract mixin class $BridgeAgentStateRead_FaultedCopyWith<$Res> implements $BridgeAgentStateReadCopyWith<$Res> {
  factory $BridgeAgentStateRead_FaultedCopyWith(BridgeAgentStateRead_Faulted value, $Res Function(BridgeAgentStateRead_Faulted) _then) = _$BridgeAgentStateRead_FaultedCopyWithImpl;
@useResult
$Res call({
 BridgeSourceStateErrorRead error, BridgeReadText? turnId, BridgeAgentFaultClassification classification
});


$BridgeReadTextCopyWith<$Res>? get turnId;

}
/// @nodoc
class _$BridgeAgentStateRead_FaultedCopyWithImpl<$Res>
    implements $BridgeAgentStateRead_FaultedCopyWith<$Res> {
  _$BridgeAgentStateRead_FaultedCopyWithImpl(this._self, this._then);

  final BridgeAgentStateRead_Faulted _self;
  final $Res Function(BridgeAgentStateRead_Faulted) _then;

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,Object? turnId = freezed,Object? classification = null,}) {
  return _then(BridgeAgentStateRead_Faulted(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeSourceStateErrorRead,turnId: freezed == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,classification: null == classification ? _self.classification : classification // ignore: cast_nullable_to_non_nullable
as BridgeAgentFaultClassification,
  ));
}

/// Create a copy of BridgeAgentStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get turnId {
    if (_self.turnId == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.turnId!, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

// dart format on
