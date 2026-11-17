// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeChatAtomLifecycle {

 BridgeChatFactPosition? get started;
/// Create a copy of BridgeChatAtomLifecycle
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatAtomLifecycleCopyWith<BridgeChatAtomLifecycle> get copyWith => _$BridgeChatAtomLifecycleCopyWithImpl<BridgeChatAtomLifecycle>(this as BridgeChatAtomLifecycle, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeChatAtomLifecycle;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatAtomLifecycle&&(identical(other.started, _this.started) || other.started == _this.started));
}


@override
int get hashCode {
  final _this = this as BridgeChatAtomLifecycle;
  return Object.hash(runtimeType,_this.started);
}

@override
String toString() {
  final _this = this as BridgeChatAtomLifecycle;
  return 'BridgeChatAtomLifecycle(started: ${_this.started})';
}


}

/// @nodoc
abstract mixin class $BridgeChatAtomLifecycleCopyWith<$Res>  {
  factory $BridgeChatAtomLifecycleCopyWith(BridgeChatAtomLifecycle value, $Res Function(BridgeChatAtomLifecycle) _then) = _$BridgeChatAtomLifecycleCopyWithImpl;
@useResult
$Res call({
 BridgeChatFactPosition? started
});




}
/// @nodoc
class _$BridgeChatAtomLifecycleCopyWithImpl<$Res>
    implements $BridgeChatAtomLifecycleCopyWith<$Res> {
  _$BridgeChatAtomLifecycleCopyWithImpl(this._self, this._then);

  final BridgeChatAtomLifecycle _self;
  final $Res Function(BridgeChatAtomLifecycle) _then;

/// Create a copy of BridgeChatAtomLifecycle
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? started = freezed,}) {
  return _then(_self.copyWith(
started: freezed == started ? _self.started : started // ignore: cast_nullable_to_non_nullable
as BridgeChatFactPosition?,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeChatAtomLifecycle].
extension BridgeChatAtomLifecyclePatterns on BridgeChatAtomLifecycle {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeChatAtomLifecycle_Active value)?  active,TResult Function( BridgeChatAtomLifecycle_Terminal value)?  terminal,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeChatAtomLifecycle_Active() when active != null:
return active(_that);case BridgeChatAtomLifecycle_Terminal() when terminal != null:
return terminal(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeChatAtomLifecycle_Active value)  active,required TResult Function( BridgeChatAtomLifecycle_Terminal value)  terminal,}){
final _that = this;
switch (_that) {
case BridgeChatAtomLifecycle_Active():
return active(_that);case BridgeChatAtomLifecycle_Terminal():
return terminal(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeChatAtomLifecycle_Active value)?  active,TResult? Function( BridgeChatAtomLifecycle_Terminal value)?  terminal,}){
final _that = this;
switch (_that) {
case BridgeChatAtomLifecycle_Active() when active != null:
return active(_that);case BridgeChatAtomLifecycle_Terminal() when terminal != null:
return terminal(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeChatFactPosition? started,  BridgeChatActiveStatus status)?  active,TResult Function( BridgeChatFactPosition? started,  BridgeChatFactPosition? ended,  BridgeChatTerminalOutcome outcome)?  terminal,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeChatAtomLifecycle_Active() when active != null:
return active(_that.started,_that.status);case BridgeChatAtomLifecycle_Terminal() when terminal != null:
return terminal(_that.started,_that.ended,_that.outcome);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeChatFactPosition? started,  BridgeChatActiveStatus status)  active,required TResult Function( BridgeChatFactPosition? started,  BridgeChatFactPosition? ended,  BridgeChatTerminalOutcome outcome)  terminal,}) {final _that = this;
switch (_that) {
case BridgeChatAtomLifecycle_Active():
return active(_that.started,_that.status);case BridgeChatAtomLifecycle_Terminal():
return terminal(_that.started,_that.ended,_that.outcome);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeChatFactPosition? started,  BridgeChatActiveStatus status)?  active,TResult? Function( BridgeChatFactPosition? started,  BridgeChatFactPosition? ended,  BridgeChatTerminalOutcome outcome)?  terminal,}) {final _that = this;
switch (_that) {
case BridgeChatAtomLifecycle_Active() when active != null:
return active(_that.started,_that.status);case BridgeChatAtomLifecycle_Terminal() when terminal != null:
return terminal(_that.started,_that.ended,_that.outcome);case _:
  return null;

}
}

}

/// @nodoc


class BridgeChatAtomLifecycle_Active extends BridgeChatAtomLifecycle {
  const BridgeChatAtomLifecycle_Active({this.started, required this.status}): super._();


@override final  BridgeChatFactPosition? started;
 final  BridgeChatActiveStatus status;

/// Create a copy of BridgeChatAtomLifecycle
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatAtomLifecycle_ActiveCopyWith<BridgeChatAtomLifecycle_Active> get copyWith => _$BridgeChatAtomLifecycle_ActiveCopyWithImpl<BridgeChatAtomLifecycle_Active>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatAtomLifecycle_Active&&(identical(other.started, started) || other.started == started)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,started,status);
}

@override
String toString() {
    return 'BridgeChatAtomLifecycle.active(started: $started, status: $status)';
}


}

/// @nodoc
abstract mixin class $BridgeChatAtomLifecycle_ActiveCopyWith<$Res> implements $BridgeChatAtomLifecycleCopyWith<$Res> {
  factory $BridgeChatAtomLifecycle_ActiveCopyWith(BridgeChatAtomLifecycle_Active value, $Res Function(BridgeChatAtomLifecycle_Active) _then) = _$BridgeChatAtomLifecycle_ActiveCopyWithImpl;
@override @useResult
$Res call({
 BridgeChatFactPosition? started, BridgeChatActiveStatus status
});




}
/// @nodoc
class _$BridgeChatAtomLifecycle_ActiveCopyWithImpl<$Res>
    implements $BridgeChatAtomLifecycle_ActiveCopyWith<$Res> {
  _$BridgeChatAtomLifecycle_ActiveCopyWithImpl(this._self, this._then);

  final BridgeChatAtomLifecycle_Active _self;
  final $Res Function(BridgeChatAtomLifecycle_Active) _then;

/// Create a copy of BridgeChatAtomLifecycle
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? started = freezed,Object? status = null,}) {
  return _then(BridgeChatAtomLifecycle_Active(
started: freezed == started ? _self.started : started // ignore: cast_nullable_to_non_nullable
as BridgeChatFactPosition?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BridgeChatActiveStatus,
  ));
}


}

/// @nodoc


class BridgeChatAtomLifecycle_Terminal extends BridgeChatAtomLifecycle {
  const BridgeChatAtomLifecycle_Terminal({this.started, this.ended, required this.outcome}): super._();


@override final  BridgeChatFactPosition? started;
 final  BridgeChatFactPosition? ended;
 final  BridgeChatTerminalOutcome outcome;

/// Create a copy of BridgeChatAtomLifecycle
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatAtomLifecycle_TerminalCopyWith<BridgeChatAtomLifecycle_Terminal> get copyWith => _$BridgeChatAtomLifecycle_TerminalCopyWithImpl<BridgeChatAtomLifecycle_Terminal>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatAtomLifecycle_Terminal&&(identical(other.started, started) || other.started == started)&&(identical(other.ended, ended) || other.ended == ended)&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,started,ended,outcome);
}

@override
String toString() {
    return 'BridgeChatAtomLifecycle.terminal(started: $started, ended: $ended, outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class $BridgeChatAtomLifecycle_TerminalCopyWith<$Res> implements $BridgeChatAtomLifecycleCopyWith<$Res> {
  factory $BridgeChatAtomLifecycle_TerminalCopyWith(BridgeChatAtomLifecycle_Terminal value, $Res Function(BridgeChatAtomLifecycle_Terminal) _then) = _$BridgeChatAtomLifecycle_TerminalCopyWithImpl;
@override @useResult
$Res call({
 BridgeChatFactPosition? started, BridgeChatFactPosition? ended, BridgeChatTerminalOutcome outcome
});




}
/// @nodoc
class _$BridgeChatAtomLifecycle_TerminalCopyWithImpl<$Res>
    implements $BridgeChatAtomLifecycle_TerminalCopyWith<$Res> {
  _$BridgeChatAtomLifecycle_TerminalCopyWithImpl(this._self, this._then);

  final BridgeChatAtomLifecycle_Terminal _self;
  final $Res Function(BridgeChatAtomLifecycle_Terminal) _then;

/// Create a copy of BridgeChatAtomLifecycle
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? started = freezed,Object? ended = freezed,Object? outcome = null,}) {
  return _then(BridgeChatAtomLifecycle_Terminal(
started: freezed == started ? _self.started : started // ignore: cast_nullable_to_non_nullable
as BridgeChatFactPosition?,ended: freezed == ended ? _self.ended : ended // ignore: cast_nullable_to_non_nullable
as BridgeChatFactPosition?,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeChatTerminalOutcome,
  ));
}


}

/// @nodoc
mixin _$BridgeChatSourceId {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceId);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatSourceId()';
}


}

/// @nodoc
class $BridgeChatSourceIdCopyWith<$Res>  {
$BridgeChatSourceIdCopyWith(BridgeChatSourceId _, $Res Function(BridgeChatSourceId) __);
}


/// Adds pattern-matching-related methods to [BridgeChatSourceId].
extension BridgeChatSourceIdPatterns on BridgeChatSourceId {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeChatSourceId_ForegroundTurn value)?  foregroundTurn,TResult Function( BridgeChatSourceId_Input value)?  input,TResult Function( BridgeChatSourceId_InboxMessage value)?  inboxMessage,TResult Function( BridgeChatSourceId_BackgroundResult value)?  backgroundResult,TResult Function( BridgeChatSourceId_Operation value)?  operation,TResult Function( BridgeChatSourceId_Receipt value)?  receipt,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeChatSourceId_ForegroundTurn() when foregroundTurn != null:
return foregroundTurn(_that);case BridgeChatSourceId_Input() when input != null:
return input(_that);case BridgeChatSourceId_InboxMessage() when inboxMessage != null:
return inboxMessage(_that);case BridgeChatSourceId_BackgroundResult() when backgroundResult != null:
return backgroundResult(_that);case BridgeChatSourceId_Operation() when operation != null:
return operation(_that);case BridgeChatSourceId_Receipt() when receipt != null:
return receipt(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeChatSourceId_ForegroundTurn value)  foregroundTurn,required TResult Function( BridgeChatSourceId_Input value)  input,required TResult Function( BridgeChatSourceId_InboxMessage value)  inboxMessage,required TResult Function( BridgeChatSourceId_BackgroundResult value)  backgroundResult,required TResult Function( BridgeChatSourceId_Operation value)  operation,required TResult Function( BridgeChatSourceId_Receipt value)  receipt,}){
final _that = this;
switch (_that) {
case BridgeChatSourceId_ForegroundTurn():
return foregroundTurn(_that);case BridgeChatSourceId_Input():
return input(_that);case BridgeChatSourceId_InboxMessage():
return inboxMessage(_that);case BridgeChatSourceId_BackgroundResult():
return backgroundResult(_that);case BridgeChatSourceId_Operation():
return operation(_that);case BridgeChatSourceId_Receipt():
return receipt(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeChatSourceId_ForegroundTurn value)?  foregroundTurn,TResult? Function( BridgeChatSourceId_Input value)?  input,TResult? Function( BridgeChatSourceId_InboxMessage value)?  inboxMessage,TResult? Function( BridgeChatSourceId_BackgroundResult value)?  backgroundResult,TResult? Function( BridgeChatSourceId_Operation value)?  operation,TResult? Function( BridgeChatSourceId_Receipt value)?  receipt,}){
final _that = this;
switch (_that) {
case BridgeChatSourceId_ForegroundTurn() when foregroundTurn != null:
return foregroundTurn(_that);case BridgeChatSourceId_Input() when input != null:
return input(_that);case BridgeChatSourceId_InboxMessage() when inboxMessage != null:
return inboxMessage(_that);case BridgeChatSourceId_BackgroundResult() when backgroundResult != null:
return backgroundResult(_that);case BridgeChatSourceId_Operation() when operation != null:
return operation(_that);case BridgeChatSourceId_Receipt() when receipt != null:
return receipt(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String turnId)?  foregroundTurn,TResult Function( String inputId)?  input,TResult Function( String sourceId,  String messageId)?  inboxMessage,TResult Function( String messageId)?  backgroundResult,TResult Function( String operationId)?  operation,TResult Function( String receiptId)?  receipt,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeChatSourceId_ForegroundTurn() when foregroundTurn != null:
return foregroundTurn(_that.turnId);case BridgeChatSourceId_Input() when input != null:
return input(_that.inputId);case BridgeChatSourceId_InboxMessage() when inboxMessage != null:
return inboxMessage(_that.sourceId,_that.messageId);case BridgeChatSourceId_BackgroundResult() when backgroundResult != null:
return backgroundResult(_that.messageId);case BridgeChatSourceId_Operation() when operation != null:
return operation(_that.operationId);case BridgeChatSourceId_Receipt() when receipt != null:
return receipt(_that.receiptId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String turnId)  foregroundTurn,required TResult Function( String inputId)  input,required TResult Function( String sourceId,  String messageId)  inboxMessage,required TResult Function( String messageId)  backgroundResult,required TResult Function( String operationId)  operation,required TResult Function( String receiptId)  receipt,}) {final _that = this;
switch (_that) {
case BridgeChatSourceId_ForegroundTurn():
return foregroundTurn(_that.turnId);case BridgeChatSourceId_Input():
return input(_that.inputId);case BridgeChatSourceId_InboxMessage():
return inboxMessage(_that.sourceId,_that.messageId);case BridgeChatSourceId_BackgroundResult():
return backgroundResult(_that.messageId);case BridgeChatSourceId_Operation():
return operation(_that.operationId);case BridgeChatSourceId_Receipt():
return receipt(_that.receiptId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String turnId)?  foregroundTurn,TResult? Function( String inputId)?  input,TResult? Function( String sourceId,  String messageId)?  inboxMessage,TResult? Function( String messageId)?  backgroundResult,TResult? Function( String operationId)?  operation,TResult? Function( String receiptId)?  receipt,}) {final _that = this;
switch (_that) {
case BridgeChatSourceId_ForegroundTurn() when foregroundTurn != null:
return foregroundTurn(_that.turnId);case BridgeChatSourceId_Input() when input != null:
return input(_that.inputId);case BridgeChatSourceId_InboxMessage() when inboxMessage != null:
return inboxMessage(_that.sourceId,_that.messageId);case BridgeChatSourceId_BackgroundResult() when backgroundResult != null:
return backgroundResult(_that.messageId);case BridgeChatSourceId_Operation() when operation != null:
return operation(_that.operationId);case BridgeChatSourceId_Receipt() when receipt != null:
return receipt(_that.receiptId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeChatSourceId_ForegroundTurn extends BridgeChatSourceId {
  const BridgeChatSourceId_ForegroundTurn({required this.turnId}): super._();


 final  String turnId;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatSourceId_ForegroundTurnCopyWith<BridgeChatSourceId_ForegroundTurn> get copyWith => _$BridgeChatSourceId_ForegroundTurnCopyWithImpl<BridgeChatSourceId_ForegroundTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceId_ForegroundTurn&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'BridgeChatSourceId.foregroundTurn(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $BridgeChatSourceId_ForegroundTurnCopyWith<$Res> implements $BridgeChatSourceIdCopyWith<$Res> {
  factory $BridgeChatSourceId_ForegroundTurnCopyWith(BridgeChatSourceId_ForegroundTurn value, $Res Function(BridgeChatSourceId_ForegroundTurn) _then) = _$BridgeChatSourceId_ForegroundTurnCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$BridgeChatSourceId_ForegroundTurnCopyWithImpl<$Res>
    implements $BridgeChatSourceId_ForegroundTurnCopyWith<$Res> {
  _$BridgeChatSourceId_ForegroundTurnCopyWithImpl(this._self, this._then);

  final BridgeChatSourceId_ForegroundTurn _self;
  final $Res Function(BridgeChatSourceId_ForegroundTurn) _then;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(BridgeChatSourceId_ForegroundTurn(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeChatSourceId_Input extends BridgeChatSourceId {
  const BridgeChatSourceId_Input({required this.inputId}): super._();


 final  String inputId;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatSourceId_InputCopyWith<BridgeChatSourceId_Input> get copyWith => _$BridgeChatSourceId_InputCopyWithImpl<BridgeChatSourceId_Input>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceId_Input&&(identical(other.inputId, inputId) || other.inputId == inputId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,inputId);
}

@override
String toString() {
    return 'BridgeChatSourceId.input(inputId: $inputId)';
}


}

/// @nodoc
abstract mixin class $BridgeChatSourceId_InputCopyWith<$Res> implements $BridgeChatSourceIdCopyWith<$Res> {
  factory $BridgeChatSourceId_InputCopyWith(BridgeChatSourceId_Input value, $Res Function(BridgeChatSourceId_Input) _then) = _$BridgeChatSourceId_InputCopyWithImpl;
@useResult
$Res call({
 String inputId
});




}
/// @nodoc
class _$BridgeChatSourceId_InputCopyWithImpl<$Res>
    implements $BridgeChatSourceId_InputCopyWith<$Res> {
  _$BridgeChatSourceId_InputCopyWithImpl(this._self, this._then);

  final BridgeChatSourceId_Input _self;
  final $Res Function(BridgeChatSourceId_Input) _then;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? inputId = null,}) {
  return _then(BridgeChatSourceId_Input(
inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeChatSourceId_InboxMessage extends BridgeChatSourceId {
  const BridgeChatSourceId_InboxMessage({required this.sourceId, required this.messageId}): super._();


 final  String sourceId;
 final  String messageId;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatSourceId_InboxMessageCopyWith<BridgeChatSourceId_InboxMessage> get copyWith => _$BridgeChatSourceId_InboxMessageCopyWithImpl<BridgeChatSourceId_InboxMessage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceId_InboxMessage&&(identical(other.sourceId, sourceId) || other.sourceId == sourceId)&&(identical(other.messageId, messageId) || other.messageId == messageId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sourceId,messageId);
}

@override
String toString() {
    return 'BridgeChatSourceId.inboxMessage(sourceId: $sourceId, messageId: $messageId)';
}


}

/// @nodoc
abstract mixin class $BridgeChatSourceId_InboxMessageCopyWith<$Res> implements $BridgeChatSourceIdCopyWith<$Res> {
  factory $BridgeChatSourceId_InboxMessageCopyWith(BridgeChatSourceId_InboxMessage value, $Res Function(BridgeChatSourceId_InboxMessage) _then) = _$BridgeChatSourceId_InboxMessageCopyWithImpl;
@useResult
$Res call({
 String sourceId, String messageId
});




}
/// @nodoc
class _$BridgeChatSourceId_InboxMessageCopyWithImpl<$Res>
    implements $BridgeChatSourceId_InboxMessageCopyWith<$Res> {
  _$BridgeChatSourceId_InboxMessageCopyWithImpl(this._self, this._then);

  final BridgeChatSourceId_InboxMessage _self;
  final $Res Function(BridgeChatSourceId_InboxMessage) _then;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sourceId = null,Object? messageId = null,}) {
  return _then(BridgeChatSourceId_InboxMessage(
sourceId: null == sourceId ? _self.sourceId : sourceId // ignore: cast_nullable_to_non_nullable
as String,messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeChatSourceId_BackgroundResult extends BridgeChatSourceId {
  const BridgeChatSourceId_BackgroundResult({required this.messageId}): super._();


 final  String messageId;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatSourceId_BackgroundResultCopyWith<BridgeChatSourceId_BackgroundResult> get copyWith => _$BridgeChatSourceId_BackgroundResultCopyWithImpl<BridgeChatSourceId_BackgroundResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceId_BackgroundResult&&(identical(other.messageId, messageId) || other.messageId == messageId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,messageId);
}

@override
String toString() {
    return 'BridgeChatSourceId.backgroundResult(messageId: $messageId)';
}


}

/// @nodoc
abstract mixin class $BridgeChatSourceId_BackgroundResultCopyWith<$Res> implements $BridgeChatSourceIdCopyWith<$Res> {
  factory $BridgeChatSourceId_BackgroundResultCopyWith(BridgeChatSourceId_BackgroundResult value, $Res Function(BridgeChatSourceId_BackgroundResult) _then) = _$BridgeChatSourceId_BackgroundResultCopyWithImpl;
@useResult
$Res call({
 String messageId
});




}
/// @nodoc
class _$BridgeChatSourceId_BackgroundResultCopyWithImpl<$Res>
    implements $BridgeChatSourceId_BackgroundResultCopyWith<$Res> {
  _$BridgeChatSourceId_BackgroundResultCopyWithImpl(this._self, this._then);

  final BridgeChatSourceId_BackgroundResult _self;
  final $Res Function(BridgeChatSourceId_BackgroundResult) _then;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? messageId = null,}) {
  return _then(BridgeChatSourceId_BackgroundResult(
messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeChatSourceId_Operation extends BridgeChatSourceId {
  const BridgeChatSourceId_Operation({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatSourceId_OperationCopyWith<BridgeChatSourceId_Operation> get copyWith => _$BridgeChatSourceId_OperationCopyWithImpl<BridgeChatSourceId_Operation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceId_Operation&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeChatSourceId.operation(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeChatSourceId_OperationCopyWith<$Res> implements $BridgeChatSourceIdCopyWith<$Res> {
  factory $BridgeChatSourceId_OperationCopyWith(BridgeChatSourceId_Operation value, $Res Function(BridgeChatSourceId_Operation) _then) = _$BridgeChatSourceId_OperationCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeChatSourceId_OperationCopyWithImpl<$Res>
    implements $BridgeChatSourceId_OperationCopyWith<$Res> {
  _$BridgeChatSourceId_OperationCopyWithImpl(this._self, this._then);

  final BridgeChatSourceId_Operation _self;
  final $Res Function(BridgeChatSourceId_Operation) _then;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeChatSourceId_Operation(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeChatSourceId_Receipt extends BridgeChatSourceId {
  const BridgeChatSourceId_Receipt({required this.receiptId}): super._();


 final  String receiptId;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatSourceId_ReceiptCopyWith<BridgeChatSourceId_Receipt> get copyWith => _$BridgeChatSourceId_ReceiptCopyWithImpl<BridgeChatSourceId_Receipt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceId_Receipt&&(identical(other.receiptId, receiptId) || other.receiptId == receiptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receiptId);
}

@override
String toString() {
    return 'BridgeChatSourceId.receipt(receiptId: $receiptId)';
}


}

/// @nodoc
abstract mixin class $BridgeChatSourceId_ReceiptCopyWith<$Res> implements $BridgeChatSourceIdCopyWith<$Res> {
  factory $BridgeChatSourceId_ReceiptCopyWith(BridgeChatSourceId_Receipt value, $Res Function(BridgeChatSourceId_Receipt) _then) = _$BridgeChatSourceId_ReceiptCopyWithImpl;
@useResult
$Res call({
 String receiptId
});




}
/// @nodoc
class _$BridgeChatSourceId_ReceiptCopyWithImpl<$Res>
    implements $BridgeChatSourceId_ReceiptCopyWith<$Res> {
  _$BridgeChatSourceId_ReceiptCopyWithImpl(this._self, this._then);

  final BridgeChatSourceId_Receipt _self;
  final $Res Function(BridgeChatSourceId_Receipt) _then;

/// Create a copy of BridgeChatSourceId
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? receiptId = null,}) {
  return _then(BridgeChatSourceId_Receipt(
receiptId: null == receiptId ? _self.receiptId : receiptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeChatSourceLifecycle {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceLifecycle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatSourceLifecycle()';
}


}

/// @nodoc
class $BridgeChatSourceLifecycleCopyWith<$Res>  {
$BridgeChatSourceLifecycleCopyWith(BridgeChatSourceLifecycle _, $Res Function(BridgeChatSourceLifecycle) __);
}


/// Adds pattern-matching-related methods to [BridgeChatSourceLifecycle].
extension BridgeChatSourceLifecyclePatterns on BridgeChatSourceLifecycle {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeChatSourceLifecycle_Unknown value)?  unknown,TResult Function( BridgeChatSourceLifecycle_Active value)?  active,TResult Function( BridgeChatSourceLifecycle_Ended value)?  ended,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeChatSourceLifecycle_Unknown() when unknown != null:
return unknown(_that);case BridgeChatSourceLifecycle_Active() when active != null:
return active(_that);case BridgeChatSourceLifecycle_Ended() when ended != null:
return ended(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeChatSourceLifecycle_Unknown value)  unknown,required TResult Function( BridgeChatSourceLifecycle_Active value)  active,required TResult Function( BridgeChatSourceLifecycle_Ended value)  ended,}){
final _that = this;
switch (_that) {
case BridgeChatSourceLifecycle_Unknown():
return unknown(_that);case BridgeChatSourceLifecycle_Active():
return active(_that);case BridgeChatSourceLifecycle_Ended():
return ended(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeChatSourceLifecycle_Unknown value)?  unknown,TResult? Function( BridgeChatSourceLifecycle_Active value)?  active,TResult? Function( BridgeChatSourceLifecycle_Ended value)?  ended,}){
final _that = this;
switch (_that) {
case BridgeChatSourceLifecycle_Unknown() when unknown != null:
return unknown(_that);case BridgeChatSourceLifecycle_Active() when active != null:
return active(_that);case BridgeChatSourceLifecycle_Ended() when ended != null:
return ended(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unknown,TResult Function()?  active,TResult Function( BridgeChatTerminalOutcome outcome)?  ended,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeChatSourceLifecycle_Unknown() when unknown != null:
return unknown();case BridgeChatSourceLifecycle_Active() when active != null:
return active();case BridgeChatSourceLifecycle_Ended() when ended != null:
return ended(_that.outcome);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unknown,required TResult Function()  active,required TResult Function( BridgeChatTerminalOutcome outcome)  ended,}) {final _that = this;
switch (_that) {
case BridgeChatSourceLifecycle_Unknown():
return unknown();case BridgeChatSourceLifecycle_Active():
return active();case BridgeChatSourceLifecycle_Ended():
return ended(_that.outcome);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unknown,TResult? Function()?  active,TResult? Function( BridgeChatTerminalOutcome outcome)?  ended,}) {final _that = this;
switch (_that) {
case BridgeChatSourceLifecycle_Unknown() when unknown != null:
return unknown();case BridgeChatSourceLifecycle_Active() when active != null:
return active();case BridgeChatSourceLifecycle_Ended() when ended != null:
return ended(_that.outcome);case _:
  return null;

}
}

}

/// @nodoc


class BridgeChatSourceLifecycle_Unknown extends BridgeChatSourceLifecycle {
  const BridgeChatSourceLifecycle_Unknown(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceLifecycle_Unknown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatSourceLifecycle.unknown()';
}


}




/// @nodoc


class BridgeChatSourceLifecycle_Active extends BridgeChatSourceLifecycle {
  const BridgeChatSourceLifecycle_Active(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceLifecycle_Active);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatSourceLifecycle.active()';
}


}




/// @nodoc


class BridgeChatSourceLifecycle_Ended extends BridgeChatSourceLifecycle {
  const BridgeChatSourceLifecycle_Ended({required this.outcome}): super._();


 final  BridgeChatTerminalOutcome outcome;

/// Create a copy of BridgeChatSourceLifecycle
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatSourceLifecycle_EndedCopyWith<BridgeChatSourceLifecycle_Ended> get copyWith => _$BridgeChatSourceLifecycle_EndedCopyWithImpl<BridgeChatSourceLifecycle_Ended>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatSourceLifecycle_Ended&&(identical(other.outcome, outcome) || other.outcome == outcome));
}


@override
int get hashCode {
    return Object.hash(runtimeType,outcome);
}

@override
String toString() {
    return 'BridgeChatSourceLifecycle.ended(outcome: $outcome)';
}


}

/// @nodoc
abstract mixin class $BridgeChatSourceLifecycle_EndedCopyWith<$Res> implements $BridgeChatSourceLifecycleCopyWith<$Res> {
  factory $BridgeChatSourceLifecycle_EndedCopyWith(BridgeChatSourceLifecycle_Ended value, $Res Function(BridgeChatSourceLifecycle_Ended) _then) = _$BridgeChatSourceLifecycle_EndedCopyWithImpl;
@useResult
$Res call({
 BridgeChatTerminalOutcome outcome
});




}
/// @nodoc
class _$BridgeChatSourceLifecycle_EndedCopyWithImpl<$Res>
    implements $BridgeChatSourceLifecycle_EndedCopyWith<$Res> {
  _$BridgeChatSourceLifecycle_EndedCopyWithImpl(this._self, this._then);

  final BridgeChatSourceLifecycle_Ended _self;
  final $Res Function(BridgeChatSourceLifecycle_Ended) _then;

/// Create a copy of BridgeChatSourceLifecycle
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? outcome = null,}) {
  return _then(BridgeChatSourceLifecycle_Ended(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as BridgeChatTerminalOutcome,
  ));
}


}

// dart format on
