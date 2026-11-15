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
mixin _$BridgeChatClassFilter {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatClassFilter);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatClassFilter()';
}


}

/// @nodoc
class $BridgeChatClassFilterCopyWith<$Res>  {
$BridgeChatClassFilterCopyWith(BridgeChatClassFilter _, $Res Function(BridgeChatClassFilter) __);
}


/// Adds pattern-matching-related methods to [BridgeChatClassFilter].
extension BridgeChatClassFilterPatterns on BridgeChatClassFilter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeChatClassFilter_Class value)?  class_,TResult Function( BridgeChatClassFilter_All value)?  all,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeChatClassFilter_Class() when class_ != null:
return class_(_that);case BridgeChatClassFilter_All() when all != null:
return all(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeChatClassFilter_Class value)  class_,required TResult Function( BridgeChatClassFilter_All value)  all,}){
final _that = this;
switch (_that) {
case BridgeChatClassFilter_Class():
return class_(_that);case BridgeChatClassFilter_All():
return all(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeChatClassFilter_Class value)?  class_,TResult? Function( BridgeChatClassFilter_All value)?  all,}){
final _that = this;
switch (_that) {
case BridgeChatClassFilter_Class() when class_ != null:
return class_(_that);case BridgeChatClassFilter_All() when all != null:
return all(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String value)?  class_,TResult Function()?  all,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeChatClassFilter_Class() when class_ != null:
return class_(_that.value);case BridgeChatClassFilter_All() when all != null:
return all();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String value)  class_,required TResult Function()  all,}) {final _that = this;
switch (_that) {
case BridgeChatClassFilter_Class():
return class_(_that.value);case BridgeChatClassFilter_All():
return all();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String value)?  class_,TResult? Function()?  all,}) {final _that = this;
switch (_that) {
case BridgeChatClassFilter_Class() when class_ != null:
return class_(_that.value);case BridgeChatClassFilter_All() when all != null:
return all();case _:
  return null;

}
}

}

/// @nodoc


class BridgeChatClassFilter_Class extends BridgeChatClassFilter {
  const BridgeChatClassFilter_Class({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeChatClassFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeChatClassFilter_ClassCopyWith<BridgeChatClassFilter_Class> get copyWith => _$BridgeChatClassFilter_ClassCopyWithImpl<BridgeChatClassFilter_Class>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatClassFilter_Class&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeChatClassFilter.class_(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeChatClassFilter_ClassCopyWith<$Res> implements $BridgeChatClassFilterCopyWith<$Res> {
  factory $BridgeChatClassFilter_ClassCopyWith(BridgeChatClassFilter_Class value, $Res Function(BridgeChatClassFilter_Class) _then) = _$BridgeChatClassFilter_ClassCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeChatClassFilter_ClassCopyWithImpl<$Res>
    implements $BridgeChatClassFilter_ClassCopyWith<$Res> {
  _$BridgeChatClassFilter_ClassCopyWithImpl(this._self, this._then);

  final BridgeChatClassFilter_Class _self;
  final $Res Function(BridgeChatClassFilter_Class) _then;

/// Create a copy of BridgeChatClassFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeChatClassFilter_Class(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeChatClassFilter_All extends BridgeChatClassFilter {
  const BridgeChatClassFilter_All(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeChatClassFilter_All);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeChatClassFilter.all()';
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

/// @nodoc
mixin _$BridgeContentOwner {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentOwner);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentOwner()';
}


}

/// @nodoc
class $BridgeContentOwnerCopyWith<$Res>  {
$BridgeContentOwnerCopyWith(BridgeContentOwner _, $Res Function(BridgeContentOwner) __);
}


/// Adds pattern-matching-related methods to [BridgeContentOwner].
extension BridgeContentOwnerPatterns on BridgeContentOwner {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContentOwner_DisplayObservation value)?  displayObservation,TResult Function( BridgeContentOwner_Item value)?  item,TResult Function( BridgeContentOwner_Current value)?  current,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContentOwner_DisplayObservation() when displayObservation != null:
return displayObservation(_that);case BridgeContentOwner_Item() when item != null:
return item(_that);case BridgeContentOwner_Current() when current != null:
return current(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContentOwner_DisplayObservation value)  displayObservation,required TResult Function( BridgeContentOwner_Item value)  item,required TResult Function( BridgeContentOwner_Current value)  current,}){
final _that = this;
switch (_that) {
case BridgeContentOwner_DisplayObservation():
return displayObservation(_that);case BridgeContentOwner_Item():
return item(_that);case BridgeContentOwner_Current():
return current(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContentOwner_DisplayObservation value)?  displayObservation,TResult? Function( BridgeContentOwner_Item value)?  item,TResult? Function( BridgeContentOwner_Current value)?  current,}){
final _that = this;
switch (_that) {
case BridgeContentOwner_DisplayObservation() when displayObservation != null:
return displayObservation(_that);case BridgeContentOwner_Item() when item != null:
return item(_that);case BridgeContentOwner_Current() when current != null:
return current(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String blockId,  String memberKey)?  displayObservation,TResult Function( String itemId)?  item,TResult Function( String domain,  String id,  BigInt revision)?  current,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContentOwner_DisplayObservation() when displayObservation != null:
return displayObservation(_that.blockId,_that.memberKey);case BridgeContentOwner_Item() when item != null:
return item(_that.itemId);case BridgeContentOwner_Current() when current != null:
return current(_that.domain,_that.id,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String blockId,  String memberKey)  displayObservation,required TResult Function( String itemId)  item,required TResult Function( String domain,  String id,  BigInt revision)  current,}) {final _that = this;
switch (_that) {
case BridgeContentOwner_DisplayObservation():
return displayObservation(_that.blockId,_that.memberKey);case BridgeContentOwner_Item():
return item(_that.itemId);case BridgeContentOwner_Current():
return current(_that.domain,_that.id,_that.revision);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String blockId,  String memberKey)?  displayObservation,TResult? Function( String itemId)?  item,TResult? Function( String domain,  String id,  BigInt revision)?  current,}) {final _that = this;
switch (_that) {
case BridgeContentOwner_DisplayObservation() when displayObservation != null:
return displayObservation(_that.blockId,_that.memberKey);case BridgeContentOwner_Item() when item != null:
return item(_that.itemId);case BridgeContentOwner_Current() when current != null:
return current(_that.domain,_that.id,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContentOwner_DisplayObservation extends BridgeContentOwner {
  const BridgeContentOwner_DisplayObservation({required this.blockId, required this.memberKey}): super._();


 final  String blockId;
 final  String memberKey;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentOwner_DisplayObservationCopyWith<BridgeContentOwner_DisplayObservation> get copyWith => _$BridgeContentOwner_DisplayObservationCopyWithImpl<BridgeContentOwner_DisplayObservation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentOwner_DisplayObservation&&(identical(other.blockId, blockId) || other.blockId == blockId)&&(identical(other.memberKey, memberKey) || other.memberKey == memberKey));
}


@override
int get hashCode {
    return Object.hash(runtimeType,blockId,memberKey);
}

@override
String toString() {
    return 'BridgeContentOwner.displayObservation(blockId: $blockId, memberKey: $memberKey)';
}


}

/// @nodoc
abstract mixin class $BridgeContentOwner_DisplayObservationCopyWith<$Res> implements $BridgeContentOwnerCopyWith<$Res> {
  factory $BridgeContentOwner_DisplayObservationCopyWith(BridgeContentOwner_DisplayObservation value, $Res Function(BridgeContentOwner_DisplayObservation) _then) = _$BridgeContentOwner_DisplayObservationCopyWithImpl;
@useResult
$Res call({
 String blockId, String memberKey
});




}
/// @nodoc
class _$BridgeContentOwner_DisplayObservationCopyWithImpl<$Res>
    implements $BridgeContentOwner_DisplayObservationCopyWith<$Res> {
  _$BridgeContentOwner_DisplayObservationCopyWithImpl(this._self, this._then);

  final BridgeContentOwner_DisplayObservation _self;
  final $Res Function(BridgeContentOwner_DisplayObservation) _then;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? blockId = null,Object? memberKey = null,}) {
  return _then(BridgeContentOwner_DisplayObservation(
blockId: null == blockId ? _self.blockId : blockId // ignore: cast_nullable_to_non_nullable
as String,memberKey: null == memberKey ? _self.memberKey : memberKey // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeContentOwner_Item extends BridgeContentOwner {
  const BridgeContentOwner_Item({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentOwner_ItemCopyWith<BridgeContentOwner_Item> get copyWith => _$BridgeContentOwner_ItemCopyWithImpl<BridgeContentOwner_Item>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentOwner_Item&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeContentOwner.item(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeContentOwner_ItemCopyWith<$Res> implements $BridgeContentOwnerCopyWith<$Res> {
  factory $BridgeContentOwner_ItemCopyWith(BridgeContentOwner_Item value, $Res Function(BridgeContentOwner_Item) _then) = _$BridgeContentOwner_ItemCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeContentOwner_ItemCopyWithImpl<$Res>
    implements $BridgeContentOwner_ItemCopyWith<$Res> {
  _$BridgeContentOwner_ItemCopyWithImpl(this._self, this._then);

  final BridgeContentOwner_Item _self;
  final $Res Function(BridgeContentOwner_Item) _then;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeContentOwner_Item(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeContentOwner_Current extends BridgeContentOwner {
  const BridgeContentOwner_Current({required this.domain, required this.id, required this.revision}): super._();


 final  String domain;
 final  String id;
 final  BigInt revision;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentOwner_CurrentCopyWith<BridgeContentOwner_Current> get copyWith => _$BridgeContentOwner_CurrentCopyWithImpl<BridgeContentOwner_Current>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentOwner_Current&&(identical(other.domain, domain) || other.domain == domain)&&(identical(other.id, id) || other.id == id)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,domain,id,revision);
}

@override
String toString() {
    return 'BridgeContentOwner.current(domain: $domain, id: $id, revision: $revision)';
}


}

/// @nodoc
abstract mixin class $BridgeContentOwner_CurrentCopyWith<$Res> implements $BridgeContentOwnerCopyWith<$Res> {
  factory $BridgeContentOwner_CurrentCopyWith(BridgeContentOwner_Current value, $Res Function(BridgeContentOwner_Current) _then) = _$BridgeContentOwner_CurrentCopyWithImpl;
@useResult
$Res call({
 String domain, String id, BigInt revision
});




}
/// @nodoc
class _$BridgeContentOwner_CurrentCopyWithImpl<$Res>
    implements $BridgeContentOwner_CurrentCopyWith<$Res> {
  _$BridgeContentOwner_CurrentCopyWithImpl(this._self, this._then);

  final BridgeContentOwner_Current _self;
  final $Res Function(BridgeContentOwner_Current) _then;

/// Create a copy of BridgeContentOwner
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? domain = null,Object? id = null,Object? revision = null,}) {
  return _then(BridgeContentOwner_Current(
domain: null == domain ? _self.domain : domain // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$BridgeContentTarget {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentTarget);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentTarget()';
}


}

/// @nodoc
class $BridgeContentTargetCopyWith<$Res>  {
$BridgeContentTargetCopyWith(BridgeContentTarget _, $Res Function(BridgeContentTarget) __);
}


/// Adds pattern-matching-related methods to [BridgeContentTarget].
extension BridgeContentTargetPatterns on BridgeContentTarget {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContentTarget_ItemPayload value)?  itemPayload,TResult Function( BridgeContentTarget_Body value)?  body,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that);case BridgeContentTarget_Body() when body != null:
return body(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContentTarget_ItemPayload value)  itemPayload,required TResult Function( BridgeContentTarget_Body value)  body,}){
final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload():
return itemPayload(_that);case BridgeContentTarget_Body():
return body(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContentTarget_ItemPayload value)?  itemPayload,TResult? Function( BridgeContentTarget_Body value)?  body,}){
final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that);case BridgeContentTarget_Body() when body != null:
return body(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String itemId)?  itemPayload,TResult Function( BridgeContentOwner owner,  String key)?  body,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that.itemId);case BridgeContentTarget_Body() when body != null:
return body(_that.owner,_that.key);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String itemId)  itemPayload,required TResult Function( BridgeContentOwner owner,  String key)  body,}) {final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload():
return itemPayload(_that.itemId);case BridgeContentTarget_Body():
return body(_that.owner,_that.key);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String itemId)?  itemPayload,TResult? Function( BridgeContentOwner owner,  String key)?  body,}) {final _that = this;
switch (_that) {
case BridgeContentTarget_ItemPayload() when itemPayload != null:
return itemPayload(_that.itemId);case BridgeContentTarget_Body() when body != null:
return body(_that.owner,_that.key);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContentTarget_ItemPayload extends BridgeContentTarget {
  const BridgeContentTarget_ItemPayload({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentTarget_ItemPayloadCopyWith<BridgeContentTarget_ItemPayload> get copyWith => _$BridgeContentTarget_ItemPayloadCopyWithImpl<BridgeContentTarget_ItemPayload>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentTarget_ItemPayload&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeContentTarget.itemPayload(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeContentTarget_ItemPayloadCopyWith<$Res> implements $BridgeContentTargetCopyWith<$Res> {
  factory $BridgeContentTarget_ItemPayloadCopyWith(BridgeContentTarget_ItemPayload value, $Res Function(BridgeContentTarget_ItemPayload) _then) = _$BridgeContentTarget_ItemPayloadCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeContentTarget_ItemPayloadCopyWithImpl<$Res>
    implements $BridgeContentTarget_ItemPayloadCopyWith<$Res> {
  _$BridgeContentTarget_ItemPayloadCopyWithImpl(this._self, this._then);

  final BridgeContentTarget_ItemPayload _self;
  final $Res Function(BridgeContentTarget_ItemPayload) _then;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeContentTarget_ItemPayload(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeContentTarget_Body extends BridgeContentTarget {
  const BridgeContentTarget_Body({required this.owner, required this.key}): super._();


 final  BridgeContentOwner owner;
 final  String key;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentTarget_BodyCopyWith<BridgeContentTarget_Body> get copyWith => _$BridgeContentTarget_BodyCopyWithImpl<BridgeContentTarget_Body>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentTarget_Body&&(identical(other.owner, owner) || other.owner == owner)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode {
    return Object.hash(runtimeType,owner,key);
}

@override
String toString() {
    return 'BridgeContentTarget.body(owner: $owner, key: $key)';
}


}

/// @nodoc
abstract mixin class $BridgeContentTarget_BodyCopyWith<$Res> implements $BridgeContentTargetCopyWith<$Res> {
  factory $BridgeContentTarget_BodyCopyWith(BridgeContentTarget_Body value, $Res Function(BridgeContentTarget_Body) _then) = _$BridgeContentTarget_BodyCopyWithImpl;
@useResult
$Res call({
 BridgeContentOwner owner, String key
});


$BridgeContentOwnerCopyWith<$Res> get owner;

}
/// @nodoc
class _$BridgeContentTarget_BodyCopyWithImpl<$Res>
    implements $BridgeContentTarget_BodyCopyWith<$Res> {
  _$BridgeContentTarget_BodyCopyWithImpl(this._self, this._then);

  final BridgeContentTarget_Body _self;
  final $Res Function(BridgeContentTarget_Body) _then;

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? owner = null,Object? key = null,}) {
  return _then(BridgeContentTarget_Body(
owner: null == owner ? _self.owner : owner // ignore: cast_nullable_to_non_nullable
as BridgeContentOwner,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of BridgeContentTarget
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeContentOwnerCopyWith<$Res> get owner {

  return $BridgeContentOwnerCopyWith<$Res>(_self.owner, (value) {
    return _then(_self.copyWith(owner: value));
  });
}
}

/// @nodoc
mixin _$BridgeConversationEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeConversationEvent()';
}


}

/// @nodoc
class $BridgeConversationEventCopyWith<$Res>  {
$BridgeConversationEventCopyWith(BridgeConversationEvent _, $Res Function(BridgeConversationEvent) __);
}


/// Adds pattern-matching-related methods to [BridgeConversationEvent].
extension BridgeConversationEventPatterns on BridgeConversationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeConversationEvent_State value)?  state,TResult Function( BridgeConversationEvent_Chat value)?  chat,TResult Function( BridgeConversationEvent_Activity value)?  activity,TResult Function( BridgeConversationEvent_Failure value)?  failure,TResult Function( BridgeConversationEvent_Closed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that);case BridgeConversationEvent_Activity() when activity != null:
return activity(_that);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that);case BridgeConversationEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeConversationEvent_State value)  state,required TResult Function( BridgeConversationEvent_Chat value)  chat,required TResult Function( BridgeConversationEvent_Activity value)  activity,required TResult Function( BridgeConversationEvent_Failure value)  failure,required TResult Function( BridgeConversationEvent_Closed value)  closed,}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_State():
return state(_that);case BridgeConversationEvent_Chat():
return chat(_that);case BridgeConversationEvent_Activity():
return activity(_that);case BridgeConversationEvent_Failure():
return failure(_that);case BridgeConversationEvent_Closed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeConversationEvent_State value)?  state,TResult? Function( BridgeConversationEvent_Chat value)?  chat,TResult? Function( BridgeConversationEvent_Activity value)?  activity,TResult? Function( BridgeConversationEvent_Failure value)?  failure,TResult? Function( BridgeConversationEvent_Closed value)?  closed,}){
final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that);case BridgeConversationEvent_Activity() when activity != null:
return activity(_that);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that);case BridgeConversationEvent_Closed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeThreadSubscriptionUpdate update)?  state,TResult Function( BridgeChatBatch batch)?  chat,TResult Function( BridgeActivitySnapshot snapshot)?  activity,TResult Function( BridgeError error)?  failure,TResult Function()?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that.update);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that.batch);case BridgeConversationEvent_Activity() when activity != null:
return activity(_that.snapshot);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that.error);case BridgeConversationEvent_Closed() when closed != null:
return closed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeThreadSubscriptionUpdate update)  state,required TResult Function( BridgeChatBatch batch)  chat,required TResult Function( BridgeActivitySnapshot snapshot)  activity,required TResult Function( BridgeError error)  failure,required TResult Function()  closed,}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_State():
return state(_that.update);case BridgeConversationEvent_Chat():
return chat(_that.batch);case BridgeConversationEvent_Activity():
return activity(_that.snapshot);case BridgeConversationEvent_Failure():
return failure(_that.error);case BridgeConversationEvent_Closed():
return closed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeThreadSubscriptionUpdate update)?  state,TResult? Function( BridgeChatBatch batch)?  chat,TResult? Function( BridgeActivitySnapshot snapshot)?  activity,TResult? Function( BridgeError error)?  failure,TResult? Function()?  closed,}) {final _that = this;
switch (_that) {
case BridgeConversationEvent_State() when state != null:
return state(_that.update);case BridgeConversationEvent_Chat() when chat != null:
return chat(_that.batch);case BridgeConversationEvent_Activity() when activity != null:
return activity(_that.snapshot);case BridgeConversationEvent_Failure() when failure != null:
return failure(_that.error);case BridgeConversationEvent_Closed() when closed != null:
return closed();case _:
  return null;

}
}

}

/// @nodoc


class BridgeConversationEvent_State extends BridgeConversationEvent {
  const BridgeConversationEvent_State({required this.update}): super._();


 final  BridgeThreadSubscriptionUpdate update;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_StateCopyWith<BridgeConversationEvent_State> get copyWith => _$BridgeConversationEvent_StateCopyWithImpl<BridgeConversationEvent_State>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_State&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,update);
}

@override
String toString() {
    return 'BridgeConversationEvent.state(update: $update)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_StateCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_StateCopyWith(BridgeConversationEvent_State value, $Res Function(BridgeConversationEvent_State) _then) = _$BridgeConversationEvent_StateCopyWithImpl;
@useResult
$Res call({
 BridgeThreadSubscriptionUpdate update
});


$BridgeThreadSubscriptionUpdateCopyWith<$Res> get update;

}
/// @nodoc
class _$BridgeConversationEvent_StateCopyWithImpl<$Res>
    implements $BridgeConversationEvent_StateCopyWith<$Res> {
  _$BridgeConversationEvent_StateCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_State _self;
  final $Res Function(BridgeConversationEvent_State) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? update = null,}) {
  return _then(BridgeConversationEvent_State(
update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as BridgeThreadSubscriptionUpdate,
  ));
}

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeThreadSubscriptionUpdateCopyWith<$Res> get update {

  return $BridgeThreadSubscriptionUpdateCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class BridgeConversationEvent_Chat extends BridgeConversationEvent {
  const BridgeConversationEvent_Chat({required this.batch}): super._();


 final  BridgeChatBatch batch;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_ChatCopyWith<BridgeConversationEvent_Chat> get copyWith => _$BridgeConversationEvent_ChatCopyWithImpl<BridgeConversationEvent_Chat>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Chat&&(identical(other.batch, batch) || other.batch == batch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,batch);
}

@override
String toString() {
    return 'BridgeConversationEvent.chat(batch: $batch)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_ChatCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_ChatCopyWith(BridgeConversationEvent_Chat value, $Res Function(BridgeConversationEvent_Chat) _then) = _$BridgeConversationEvent_ChatCopyWithImpl;
@useResult
$Res call({
 BridgeChatBatch batch
});




}
/// @nodoc
class _$BridgeConversationEvent_ChatCopyWithImpl<$Res>
    implements $BridgeConversationEvent_ChatCopyWith<$Res> {
  _$BridgeConversationEvent_ChatCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_Chat _self;
  final $Res Function(BridgeConversationEvent_Chat) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? batch = null,}) {
  return _then(BridgeConversationEvent_Chat(
batch: null == batch ? _self.batch : batch // ignore: cast_nullable_to_non_nullable
as BridgeChatBatch,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_Activity extends BridgeConversationEvent {
  const BridgeConversationEvent_Activity({required this.snapshot}): super._();


 final  BridgeActivitySnapshot snapshot;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_ActivityCopyWith<BridgeConversationEvent_Activity> get copyWith => _$BridgeConversationEvent_ActivityCopyWithImpl<BridgeConversationEvent_Activity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Activity&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,snapshot);
}

@override
String toString() {
    return 'BridgeConversationEvent.activity(snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_ActivityCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_ActivityCopyWith(BridgeConversationEvent_Activity value, $Res Function(BridgeConversationEvent_Activity) _then) = _$BridgeConversationEvent_ActivityCopyWithImpl;
@useResult
$Res call({
 BridgeActivitySnapshot snapshot
});




}
/// @nodoc
class _$BridgeConversationEvent_ActivityCopyWithImpl<$Res>
    implements $BridgeConversationEvent_ActivityCopyWith<$Res> {
  _$BridgeConversationEvent_ActivityCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_Activity _self;
  final $Res Function(BridgeConversationEvent_Activity) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? snapshot = null,}) {
  return _then(BridgeConversationEvent_Activity(
snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as BridgeActivitySnapshot,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_Failure extends BridgeConversationEvent {
  const BridgeConversationEvent_Failure({required this.error}): super._();


 final  BridgeError error;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeConversationEvent_FailureCopyWith<BridgeConversationEvent_Failure> get copyWith => _$BridgeConversationEvent_FailureCopyWithImpl<BridgeConversationEvent_Failure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Failure&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'BridgeConversationEvent.failure(error: $error)';
}


}

/// @nodoc
abstract mixin class $BridgeConversationEvent_FailureCopyWith<$Res> implements $BridgeConversationEventCopyWith<$Res> {
  factory $BridgeConversationEvent_FailureCopyWith(BridgeConversationEvent_Failure value, $Res Function(BridgeConversationEvent_Failure) _then) = _$BridgeConversationEvent_FailureCopyWithImpl;
@useResult
$Res call({
 BridgeError error
});




}
/// @nodoc
class _$BridgeConversationEvent_FailureCopyWithImpl<$Res>
    implements $BridgeConversationEvent_FailureCopyWith<$Res> {
  _$BridgeConversationEvent_FailureCopyWithImpl(this._self, this._then);

  final BridgeConversationEvent_Failure _self;
  final $Res Function(BridgeConversationEvent_Failure) _then;

/// Create a copy of BridgeConversationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BridgeConversationEvent_Failure(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as BridgeError,
  ));
}


}

/// @nodoc


class BridgeConversationEvent_Closed extends BridgeConversationEvent {
  const BridgeConversationEvent_Closed(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeConversationEvent_Closed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeConversationEvent.closed()';
}


}




/// @nodoc
mixin _$BridgePayloadData {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePayloadData);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgePayloadData()';
}


}

/// @nodoc
class $BridgePayloadDataCopyWith<$Res>  {
$BridgePayloadDataCopyWith(BridgePayloadData _, $Res Function(BridgePayloadData) __);
}


/// Adds pattern-matching-related methods to [BridgePayloadData].
extension BridgePayloadDataPatterns on BridgePayloadData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgePayloadData_Inline value)?  inline,TResult Function( BridgePayloadData_Deferred value)?  deferred_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that);case BridgePayloadData_Deferred() when deferred_ != null:
return deferred_(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgePayloadData_Inline value)  inline,required TResult Function( BridgePayloadData_Deferred value)  deferred_,}){
final _that = this;
switch (_that) {
case BridgePayloadData_Inline():
return inline(_that);case BridgePayloadData_Deferred():
return deferred_(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgePayloadData_Inline value)?  inline,TResult? Function( BridgePayloadData_Deferred value)?  deferred_,}){
final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that);case BridgePayloadData_Deferred() when deferred_ != null:
return deferred_(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Uint8List bytes)?  inline,TResult Function( BridgeContentRef reference,  BigInt byteLength)?  deferred_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that.bytes);case BridgePayloadData_Deferred() when deferred_ != null:
return deferred_(_that.reference,_that.byteLength);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Uint8List bytes)  inline,required TResult Function( BridgeContentRef reference,  BigInt byteLength)  deferred_,}) {final _that = this;
switch (_that) {
case BridgePayloadData_Inline():
return inline(_that.bytes);case BridgePayloadData_Deferred():
return deferred_(_that.reference,_that.byteLength);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Uint8List bytes)?  inline,TResult? Function( BridgeContentRef reference,  BigInt byteLength)?  deferred_,}) {final _that = this;
switch (_that) {
case BridgePayloadData_Inline() when inline != null:
return inline(_that.bytes);case BridgePayloadData_Deferred() when deferred_ != null:
return deferred_(_that.reference,_that.byteLength);case _:
  return null;

}
}

}

/// @nodoc


class BridgePayloadData_Inline extends BridgePayloadData {
  const BridgePayloadData_Inline({required this.bytes}): super._();


 final  Uint8List bytes;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePayloadData_InlineCopyWith<BridgePayloadData_Inline> get copyWith => _$BridgePayloadData_InlineCopyWithImpl<BridgePayloadData_Inline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePayloadData_Inline&&const DeepCollectionEquality().equals(other.bytes, bytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes));
}

@override
String toString() {
    return 'BridgePayloadData.inline(bytes: $bytes)';
}


}

/// @nodoc
abstract mixin class $BridgePayloadData_InlineCopyWith<$Res> implements $BridgePayloadDataCopyWith<$Res> {
  factory $BridgePayloadData_InlineCopyWith(BridgePayloadData_Inline value, $Res Function(BridgePayloadData_Inline) _then) = _$BridgePayloadData_InlineCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes
});




}
/// @nodoc
class _$BridgePayloadData_InlineCopyWithImpl<$Res>
    implements $BridgePayloadData_InlineCopyWith<$Res> {
  _$BridgePayloadData_InlineCopyWithImpl(this._self, this._then);

  final BridgePayloadData_Inline _self;
  final $Res Function(BridgePayloadData_Inline) _then;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,}) {
  return _then(BridgePayloadData_Inline(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,
  ));
}


}

/// @nodoc


class BridgePayloadData_Deferred extends BridgePayloadData {
  const BridgePayloadData_Deferred({required this.reference, required this.byteLength}): super._();


 final  BridgeContentRef reference;
 final  BigInt byteLength;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgePayloadData_DeferredCopyWith<BridgePayloadData_Deferred> get copyWith => _$BridgePayloadData_DeferredCopyWithImpl<BridgePayloadData_Deferred>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgePayloadData_Deferred&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.byteLength, byteLength) || other.byteLength == byteLength));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,byteLength);
}

@override
String toString() {
    return 'BridgePayloadData.deferred_(reference: $reference, byteLength: $byteLength)';
}


}

/// @nodoc
abstract mixin class $BridgePayloadData_DeferredCopyWith<$Res> implements $BridgePayloadDataCopyWith<$Res> {
  factory $BridgePayloadData_DeferredCopyWith(BridgePayloadData_Deferred value, $Res Function(BridgePayloadData_Deferred) _then) = _$BridgePayloadData_DeferredCopyWithImpl;
@useResult
$Res call({
 BridgeContentRef reference, BigInt byteLength
});




}
/// @nodoc
class _$BridgePayloadData_DeferredCopyWithImpl<$Res>
    implements $BridgePayloadData_DeferredCopyWith<$Res> {
  _$BridgePayloadData_DeferredCopyWithImpl(this._self, this._then);

  final BridgePayloadData_Deferred _self;
  final $Res Function(BridgePayloadData_Deferred) _then;

/// Create a copy of BridgePayloadData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? byteLength = null,}) {
  return _then(BridgePayloadData_Deferred(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as BridgeContentRef,byteLength: null == byteLength ? _self.byteLength : byteLength // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
