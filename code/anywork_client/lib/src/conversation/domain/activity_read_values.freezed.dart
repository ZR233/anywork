// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'activity_read_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$WaitReadIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitReadIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'WaitReadIntent()';
}


}

/// @nodoc
class $WaitReadIntentCopyWith<$Res>  {
$WaitReadIntentCopyWith(WaitReadIntent _, $Res Function(WaitReadIntent) __);
}


/// Adds pattern-matching-related methods to [WaitReadIntent].
extension WaitReadIntentPatterns on WaitReadIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( EventsWaitReadIntent value)?  events,TResult Function( TimerWaitReadIntent value)?  timer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case EventsWaitReadIntent() when events != null:
return events(_that);case TimerWaitReadIntent() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( EventsWaitReadIntent value)  events,required TResult Function( TimerWaitReadIntent value)  timer,}){
final _that = this;
switch (_that) {
case EventsWaitReadIntent():
return events(_that);case TimerWaitReadIntent():
return timer(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( EventsWaitReadIntent value)?  events,TResult? Function( TimerWaitReadIntent value)?  timer,}){
final _that = this;
switch (_that) {
case EventsWaitReadIntent() when events != null:
return events(_that);case TimerWaitReadIntent() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int targetCount,  int timeoutMs)?  events,TResult Function( int durationMs)?  timer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case EventsWaitReadIntent() when events != null:
return events(_that.targetCount,_that.timeoutMs);case TimerWaitReadIntent() when timer != null:
return timer(_that.durationMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int targetCount,  int timeoutMs)  events,required TResult Function( int durationMs)  timer,}) {final _that = this;
switch (_that) {
case EventsWaitReadIntent():
return events(_that.targetCount,_that.timeoutMs);case TimerWaitReadIntent():
return timer(_that.durationMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int targetCount,  int timeoutMs)?  events,TResult? Function( int durationMs)?  timer,}) {final _that = this;
switch (_that) {
case EventsWaitReadIntent() when events != null:
return events(_that.targetCount,_that.timeoutMs);case TimerWaitReadIntent() when timer != null:
return timer(_that.durationMs);case _:
  return null;

}
}

}

/// @nodoc


class EventsWaitReadIntent implements WaitReadIntent {
  const EventsWaitReadIntent({required this.targetCount, required this.timeoutMs});


 final  int targetCount;
 final  int timeoutMs;

/// Create a copy of WaitReadIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$EventsWaitReadIntentCopyWith<EventsWaitReadIntent> get copyWith => _$EventsWaitReadIntentCopyWithImpl<EventsWaitReadIntent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is EventsWaitReadIntent&&(identical(other.targetCount, targetCount) || other.targetCount == targetCount)&&(identical(other.timeoutMs, timeoutMs) || other.timeoutMs == timeoutMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,targetCount,timeoutMs);
}

@override
String toString() {
    return 'WaitReadIntent.events(targetCount: $targetCount, timeoutMs: $timeoutMs)';
}


}

/// @nodoc
abstract mixin class $EventsWaitReadIntentCopyWith<$Res> implements $WaitReadIntentCopyWith<$Res> {
  factory $EventsWaitReadIntentCopyWith(EventsWaitReadIntent value, $Res Function(EventsWaitReadIntent) _then) = _$EventsWaitReadIntentCopyWithImpl;
@useResult
$Res call({
 int targetCount, int timeoutMs
});




}
/// @nodoc
class _$EventsWaitReadIntentCopyWithImpl<$Res>
    implements $EventsWaitReadIntentCopyWith<$Res> {
  _$EventsWaitReadIntentCopyWithImpl(this._self, this._then);

  final EventsWaitReadIntent _self;
  final $Res Function(EventsWaitReadIntent) _then;

/// Create a copy of WaitReadIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetCount = null,Object? timeoutMs = null,}) {
  return _then(EventsWaitReadIntent(
targetCount: null == targetCount ? _self.targetCount : targetCount // ignore: cast_nullable_to_non_nullable
as int,timeoutMs: null == timeoutMs ? _self.timeoutMs : timeoutMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class TimerWaitReadIntent implements WaitReadIntent {
  const TimerWaitReadIntent({required this.durationMs});


 final  int durationMs;

/// Create a copy of WaitReadIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimerWaitReadIntentCopyWith<TimerWaitReadIntent> get copyWith => _$TimerWaitReadIntentCopyWithImpl<TimerWaitReadIntent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TimerWaitReadIntent&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,durationMs);
}

@override
String toString() {
    return 'WaitReadIntent.timer(durationMs: $durationMs)';
}


}

/// @nodoc
abstract mixin class $TimerWaitReadIntentCopyWith<$Res> implements $WaitReadIntentCopyWith<$Res> {
  factory $TimerWaitReadIntentCopyWith(TimerWaitReadIntent value, $Res Function(TimerWaitReadIntent) _then) = _$TimerWaitReadIntentCopyWithImpl;
@useResult
$Res call({
 int durationMs
});




}
/// @nodoc
class _$TimerWaitReadIntentCopyWithImpl<$Res>
    implements $TimerWaitReadIntentCopyWith<$Res> {
  _$TimerWaitReadIntentCopyWithImpl(this._self, this._then);

  final TimerWaitReadIntent _self;
  final $Res Function(TimerWaitReadIntent) _then;

/// Create a copy of WaitReadIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? durationMs = null,}) {
  return _then(TimerWaitReadIntent(
durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$WaitReadValue {

 WaitReadIntent get intent; ThreadWaitState get state; bool? get messagesReady;
/// Create a copy of WaitReadValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitReadValueCopyWith<WaitReadValue> get copyWith => _$WaitReadValueCopyWithImpl<WaitReadValue>(this as WaitReadValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WaitReadValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitReadValue&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.messagesReady, _this.messagesReady) || other.messagesReady == _this.messagesReady));
}


@override
int get hashCode {
  final _this = this as WaitReadValue;
  return Object.hash(runtimeType,_this.intent,_this.state,_this.messagesReady);
}

@override
String toString() {
  final _this = this as WaitReadValue;
  return 'WaitReadValue(intent: ${_this.intent}, state: ${_this.state}, messagesReady: ${_this.messagesReady})';
}


}

/// @nodoc
abstract mixin class $WaitReadValueCopyWith<$Res>  {
  factory $WaitReadValueCopyWith(WaitReadValue value, $Res Function(WaitReadValue) _then) = _$WaitReadValueCopyWithImpl;
@useResult
$Res call({
 WaitReadIntent intent, ThreadWaitState state, bool? messagesReady
});


$WaitReadIntentCopyWith<$Res> get intent;

}
/// @nodoc
class _$WaitReadValueCopyWithImpl<$Res>
    implements $WaitReadValueCopyWith<$Res> {
  _$WaitReadValueCopyWithImpl(this._self, this._then);

  final WaitReadValue _self;
  final $Res Function(WaitReadValue) _then;

/// Create a copy of WaitReadValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? state = null,Object? messagesReady = freezed,}) {
  return _then(WaitReadValue(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as WaitReadIntent,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadWaitState,messagesReady: freezed == messagesReady ? _self.messagesReady : messagesReady // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}
/// Create a copy of WaitReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WaitReadIntentCopyWith<$Res> get intent {

  return $WaitReadIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}
}


/// Adds pattern-matching-related methods to [WaitReadValue].
extension WaitReadValuePatterns on WaitReadValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WaitReadValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WaitReadValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WaitReadValue value)  $default,){
final _that = this;
switch (_that) {
case _WaitReadValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WaitReadValue value)?  $default,){
final _that = this;
switch (_that) {
case _WaitReadValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WaitReadIntent intent,  ThreadWaitState state,  bool? messagesReady)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WaitReadValue() when $default != null:
return $default(_that.intent,_that.state,_that.messagesReady);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WaitReadIntent intent,  ThreadWaitState state,  bool? messagesReady)  $default,) {final _that = this;
switch (_that) {
case _WaitReadValue():
return $default(_that.intent,_that.state,_that.messagesReady);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WaitReadIntent intent,  ThreadWaitState state,  bool? messagesReady)?  $default,) {final _that = this;
switch (_that) {
case _WaitReadValue() when $default != null:
return $default(_that.intent,_that.state,_that.messagesReady);case _:
  return null;

}
}

}

/// @nodoc


class _WaitReadValue implements WaitReadValue {
  const _WaitReadValue({required this.intent, required this.state, required this.messagesReady});


@override final  WaitReadIntent intent;
@override final  ThreadWaitState state;
@override final  bool? messagesReady;

/// Create a copy of WaitReadValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WaitReadValueCopyWith<_WaitReadValue> get copyWith => __$WaitReadValueCopyWithImpl<_WaitReadValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WaitReadValue&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.state, state) || other.state == state)&&(identical(other.messagesReady, messagesReady) || other.messagesReady == messagesReady));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,state,messagesReady);
}

@override
String toString() {
    return 'WaitReadValue(intent: $intent, state: $state, messagesReady: $messagesReady)';
}


}

/// @nodoc
abstract mixin class _$WaitReadValueCopyWith<$Res> implements $WaitReadValueCopyWith<$Res> {
  factory _$WaitReadValueCopyWith(_WaitReadValue value, $Res Function(_WaitReadValue) _then) = __$WaitReadValueCopyWithImpl;
@override @useResult
$Res call({
 WaitReadIntent intent, ThreadWaitState state, bool? messagesReady
});


@override $WaitReadIntentCopyWith<$Res> get intent;

}
/// @nodoc
class __$WaitReadValueCopyWithImpl<$Res>
    implements _$WaitReadValueCopyWith<$Res> {
  __$WaitReadValueCopyWithImpl(this._self, this._then);

  final _WaitReadValue _self;
  final $Res Function(_WaitReadValue) _then;

/// Create a copy of WaitReadValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? state = null,Object? messagesReady = freezed,}) {
  return _then(_WaitReadValue(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as WaitReadIntent,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadWaitState,messagesReady: freezed == messagesReady ? _self.messagesReady : messagesReady // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

/// Create a copy of WaitReadValue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WaitReadIntentCopyWith<$Res> get intent {

  return $WaitReadIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}
}

/// @nodoc
mixin _$WaitTargetReadItem {

 int get index; ReadText get taskId; ReadText? get toolName; ReadText? get summary; bool get summaryTruncated; ThreadWaitTargetStatus? get status;
/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitTargetReadItemCopyWith<WaitTargetReadItem> get copyWith => _$WaitTargetReadItemCopyWithImpl<WaitTargetReadItem>(this as WaitTargetReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WaitTargetReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitTargetReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.toolName, _this.toolName) || other.toolName == _this.toolName)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.summaryTruncated, _this.summaryTruncated) || other.summaryTruncated == _this.summaryTruncated)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as WaitTargetReadItem;
  return Object.hash(runtimeType,_this.index,_this.taskId,_this.toolName,_this.summary,_this.summaryTruncated,_this.status);
}



}

/// @nodoc
abstract mixin class $WaitTargetReadItemCopyWith<$Res>  {
  factory $WaitTargetReadItemCopyWith(WaitTargetReadItem value, $Res Function(WaitTargetReadItem) _then) = _$WaitTargetReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText taskId, ReadText? toolName, ReadText? summary, bool summaryTruncated, ThreadWaitTargetStatus? status
});


$ReadTextCopyWith<$Res> get taskId;$ReadTextCopyWith<$Res>? get toolName;$ReadTextCopyWith<$Res>? get summary;

}
/// @nodoc
class _$WaitTargetReadItemCopyWithImpl<$Res>
    implements $WaitTargetReadItemCopyWith<$Res> {
  _$WaitTargetReadItemCopyWithImpl(this._self, this._then);

  final WaitTargetReadItem _self;
  final $Res Function(WaitTargetReadItem) _then;

/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? taskId = null,Object? toolName = freezed,Object? summary = freezed,Object? summaryTruncated = null,Object? status = freezed,}) {
  return _then(WaitTargetReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as ReadText,toolName: freezed == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as ReadText?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText?,summaryTruncated: null == summaryTruncated ? _self.summaryTruncated : summaryTruncated // ignore: cast_nullable_to_non_nullable
as bool,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadWaitTargetStatus?,
  ));
}
/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get taskId {

  return $ReadTextCopyWith<$Res>(_self.taskId, (value) {
    return _then(_self.copyWith(taskId: value));
  });
}/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get toolName {
    if (_self.toolName == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.toolName!, (value) {
    return _then(_self.copyWith(toolName: value));
  });
}/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}
}


/// Adds pattern-matching-related methods to [WaitTargetReadItem].
extension WaitTargetReadItemPatterns on WaitTargetReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WaitTargetReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WaitTargetReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WaitTargetReadItem value)  $default,){
final _that = this;
switch (_that) {
case _WaitTargetReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WaitTargetReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _WaitTargetReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText taskId,  ReadText? toolName,  ReadText? summary,  bool summaryTruncated,  ThreadWaitTargetStatus? status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WaitTargetReadItem() when $default != null:
return $default(_that.index,_that.taskId,_that.toolName,_that.summary,_that.summaryTruncated,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText taskId,  ReadText? toolName,  ReadText? summary,  bool summaryTruncated,  ThreadWaitTargetStatus? status)  $default,) {final _that = this;
switch (_that) {
case _WaitTargetReadItem():
return $default(_that.index,_that.taskId,_that.toolName,_that.summary,_that.summaryTruncated,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText taskId,  ReadText? toolName,  ReadText? summary,  bool summaryTruncated,  ThreadWaitTargetStatus? status)?  $default,) {final _that = this;
switch (_that) {
case _WaitTargetReadItem() when $default != null:
return $default(_that.index,_that.taskId,_that.toolName,_that.summary,_that.summaryTruncated,_that.status);case _:
  return null;

}
}

}

/// @nodoc


class _WaitTargetReadItem implements WaitTargetReadItem {
  const _WaitTargetReadItem({required this.index, required this.taskId, required this.toolName, required this.summary, required this.summaryTruncated, required this.status});


@override final  int index;
@override final  ReadText taskId;
@override final  ReadText? toolName;
@override final  ReadText? summary;
@override final  bool summaryTruncated;
@override final  ThreadWaitTargetStatus? status;

/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WaitTargetReadItemCopyWith<_WaitTargetReadItem> get copyWith => __$WaitTargetReadItemCopyWithImpl<_WaitTargetReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WaitTargetReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.toolName, toolName) || other.toolName == toolName)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.summaryTruncated, summaryTruncated) || other.summaryTruncated == summaryTruncated)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,taskId,toolName,summary,summaryTruncated,status);
}



}

/// @nodoc
abstract mixin class _$WaitTargetReadItemCopyWith<$Res> implements $WaitTargetReadItemCopyWith<$Res> {
  factory _$WaitTargetReadItemCopyWith(_WaitTargetReadItem value, $Res Function(_WaitTargetReadItem) _then) = __$WaitTargetReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText taskId, ReadText? toolName, ReadText? summary, bool summaryTruncated, ThreadWaitTargetStatus? status
});


@override $ReadTextCopyWith<$Res> get taskId;@override $ReadTextCopyWith<$Res>? get toolName;@override $ReadTextCopyWith<$Res>? get summary;

}
/// @nodoc
class __$WaitTargetReadItemCopyWithImpl<$Res>
    implements _$WaitTargetReadItemCopyWith<$Res> {
  __$WaitTargetReadItemCopyWithImpl(this._self, this._then);

  final _WaitTargetReadItem _self;
  final $Res Function(_WaitTargetReadItem) _then;

/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? taskId = null,Object? toolName = freezed,Object? summary = freezed,Object? summaryTruncated = null,Object? status = freezed,}) {
  return _then(_WaitTargetReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as ReadText,toolName: freezed == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as ReadText?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText?,summaryTruncated: null == summaryTruncated ? _self.summaryTruncated : summaryTruncated // ignore: cast_nullable_to_non_nullable
as bool,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadWaitTargetStatus?,
  ));
}

/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get taskId {

  return $ReadTextCopyWith<$Res>(_self.taskId, (value) {
    return _then(_self.copyWith(taskId: value));
  });
}/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get toolName {
    if (_self.toolName == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.toolName!, (value) {
    return _then(_self.copyWith(toolName: value));
  });
}/// Create a copy of WaitTargetReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get summary {
    if (_self.summary == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.summary!, (value) {
    return _then(_self.copyWith(summary: value));
  });
}
}

/// @nodoc
mixin _$WaitTargetPage {


/// Create a copy of WaitTargetPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WaitTargetPageCopyWith<WaitTargetPage> get copyWith => _$WaitTargetPageCopyWithImpl<WaitTargetPage>(this as WaitTargetPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WaitTargetPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WaitTargetPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as WaitTargetPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $WaitTargetPageCopyWith<$Res>  {
  factory $WaitTargetPageCopyWith(WaitTargetPage value, $Res Function(WaitTargetPage) _then) = _$WaitTargetPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<WaitTargetReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$WaitTargetPageCopyWithImpl<$Res>
    implements $WaitTargetPageCopyWith<$Res> {
  _$WaitTargetPageCopyWithImpl(this._self, this._then);

  final WaitTargetPage _self;
  final $Res Function(WaitTargetPage) _then;

/// Create a copy of WaitTargetPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(WaitTargetPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<WaitTargetReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of WaitTargetPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [WaitTargetPage].
extension WaitTargetPagePatterns on WaitTargetPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$ActivityToolReadItem {

 ReadText get callId; ReadText? get taskId; ReadText get name; ReadText get summary; ThreadActivityArgumentsKind get arguments; ThreadActivityToolState get state; int? get ordinal; int? get startedAt; WaitReadValue? get wait;
/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityToolReadItemCopyWith<ActivityToolReadItem> get copyWith => _$ActivityToolReadItemCopyWithImpl<ActivityToolReadItem>(this as ActivityToolReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityToolReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityToolReadItem&&(identical(other.callId, _this.callId) || other.callId == _this.callId)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.arguments, _this.arguments) || other.arguments == _this.arguments)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.ordinal, _this.ordinal) || other.ordinal == _this.ordinal)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.wait, _this.wait) || other.wait == _this.wait));
}


@override
int get hashCode {
  final _this = this as ActivityToolReadItem;
  return Object.hash(runtimeType,_this.callId,_this.taskId,_this.name,_this.summary,_this.arguments,_this.state,_this.ordinal,_this.startedAt,_this.wait);
}



}

/// @nodoc
abstract mixin class $ActivityToolReadItemCopyWith<$Res>  {
  factory $ActivityToolReadItemCopyWith(ActivityToolReadItem value, $Res Function(ActivityToolReadItem) _then) = _$ActivityToolReadItemCopyWithImpl;
@useResult
$Res call({
 ReadText callId, ReadText? taskId, ReadText name, ReadText summary, ThreadActivityArgumentsKind arguments, ThreadActivityToolState state, int? ordinal, int? startedAt, WaitReadValue? wait
});


$ReadTextCopyWith<$Res> get callId;$ReadTextCopyWith<$Res>? get taskId;$ReadTextCopyWith<$Res> get name;$ReadTextCopyWith<$Res> get summary;$WaitReadValueCopyWith<$Res>? get wait;

}
/// @nodoc
class _$ActivityToolReadItemCopyWithImpl<$Res>
    implements $ActivityToolReadItemCopyWith<$Res> {
  _$ActivityToolReadItemCopyWithImpl(this._self, this._then);

  final ActivityToolReadItem _self;
  final $Res Function(ActivityToolReadItem) _then;

/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? callId = null,Object? taskId = freezed,Object? name = null,Object? summary = null,Object? arguments = null,Object? state = null,Object? ordinal = freezed,Object? startedAt = freezed,Object? wait = freezed,}) {
  return _then(ActivityToolReadItem(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as ReadText,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as ReadText?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as ThreadActivityArgumentsKind,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadActivityToolState,ordinal: freezed == ordinal ? _self.ordinal : ordinal // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as WaitReadValue?,
  ));
}
/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get callId {

  return $ReadTextCopyWith<$Res>(_self.callId, (value) {
    return _then(_self.copyWith(callId: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get taskId {
    if (_self.taskId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.taskId!, (value) {
    return _then(_self.copyWith(taskId: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get summary {

  return $ReadTextCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WaitReadValueCopyWith<$Res>? get wait {
    if (_self.wait == null) {
    return null;
  }

  return $WaitReadValueCopyWith<$Res>(_self.wait!, (value) {
    return _then(_self.copyWith(wait: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActivityToolReadItem].
extension ActivityToolReadItemPatterns on ActivityToolReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivityToolReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityToolReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivityToolReadItem value)  $default,){
final _that = this;
switch (_that) {
case _ActivityToolReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivityToolReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _ActivityToolReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText callId,  ReadText? taskId,  ReadText name,  ReadText summary,  ThreadActivityArgumentsKind arguments,  ThreadActivityToolState state,  int? ordinal,  int? startedAt,  WaitReadValue? wait)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityToolReadItem() when $default != null:
return $default(_that.callId,_that.taskId,_that.name,_that.summary,_that.arguments,_that.state,_that.ordinal,_that.startedAt,_that.wait);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText callId,  ReadText? taskId,  ReadText name,  ReadText summary,  ThreadActivityArgumentsKind arguments,  ThreadActivityToolState state,  int? ordinal,  int? startedAt,  WaitReadValue? wait)  $default,) {final _that = this;
switch (_that) {
case _ActivityToolReadItem():
return $default(_that.callId,_that.taskId,_that.name,_that.summary,_that.arguments,_that.state,_that.ordinal,_that.startedAt,_that.wait);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText callId,  ReadText? taskId,  ReadText name,  ReadText summary,  ThreadActivityArgumentsKind arguments,  ThreadActivityToolState state,  int? ordinal,  int? startedAt,  WaitReadValue? wait)?  $default,) {final _that = this;
switch (_that) {
case _ActivityToolReadItem() when $default != null:
return $default(_that.callId,_that.taskId,_that.name,_that.summary,_that.arguments,_that.state,_that.ordinal,_that.startedAt,_that.wait);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityToolReadItem implements ActivityToolReadItem {
  const _ActivityToolReadItem({required this.callId, required this.taskId, required this.name, required this.summary, required this.arguments, required this.state, required this.ordinal, required this.startedAt, required this.wait});


@override final  ReadText callId;
@override final  ReadText? taskId;
@override final  ReadText name;
@override final  ReadText summary;
@override final  ThreadActivityArgumentsKind arguments;
@override final  ThreadActivityToolState state;
@override final  int? ordinal;
@override final  int? startedAt;
@override final  WaitReadValue? wait;

/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityToolReadItemCopyWith<_ActivityToolReadItem> get copyWith => __$ActivityToolReadItemCopyWithImpl<_ActivityToolReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityToolReadItem&&(identical(other.callId, callId) || other.callId == callId)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.name, name) || other.name == name)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.state, state) || other.state == state)&&(identical(other.ordinal, ordinal) || other.ordinal == ordinal)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode {
    return Object.hash(runtimeType,callId,taskId,name,summary,arguments,state,ordinal,startedAt,wait);
}



}

/// @nodoc
abstract mixin class _$ActivityToolReadItemCopyWith<$Res> implements $ActivityToolReadItemCopyWith<$Res> {
  factory _$ActivityToolReadItemCopyWith(_ActivityToolReadItem value, $Res Function(_ActivityToolReadItem) _then) = __$ActivityToolReadItemCopyWithImpl;
@override @useResult
$Res call({
 ReadText callId, ReadText? taskId, ReadText name, ReadText summary, ThreadActivityArgumentsKind arguments, ThreadActivityToolState state, int? ordinal, int? startedAt, WaitReadValue? wait
});


@override $ReadTextCopyWith<$Res> get callId;@override $ReadTextCopyWith<$Res>? get taskId;@override $ReadTextCopyWith<$Res> get name;@override $ReadTextCopyWith<$Res> get summary;@override $WaitReadValueCopyWith<$Res>? get wait;

}
/// @nodoc
class __$ActivityToolReadItemCopyWithImpl<$Res>
    implements _$ActivityToolReadItemCopyWith<$Res> {
  __$ActivityToolReadItemCopyWithImpl(this._self, this._then);

  final _ActivityToolReadItem _self;
  final $Res Function(_ActivityToolReadItem) _then;

/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? callId = null,Object? taskId = freezed,Object? name = null,Object? summary = null,Object? arguments = null,Object? state = null,Object? ordinal = freezed,Object? startedAt = freezed,Object? wait = freezed,}) {
  return _then(_ActivityToolReadItem(
callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as ReadText,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as ReadText?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as ThreadActivityArgumentsKind,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadActivityToolState,ordinal: freezed == ordinal ? _self.ordinal : ordinal // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as WaitReadValue?,
  ));
}

/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get callId {

  return $ReadTextCopyWith<$Res>(_self.callId, (value) {
    return _then(_self.copyWith(callId: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get taskId {
    if (_self.taskId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.taskId!, (value) {
    return _then(_self.copyWith(taskId: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get summary {

  return $ReadTextCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of ActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WaitReadValueCopyWith<$Res>? get wait {
    if (_self.wait == null) {
    return null;
  }

  return $WaitReadValueCopyWith<$Res>(_self.wait!, (value) {
    return _then(_self.copyWith(wait: value));
  });
}
}

/// @nodoc
mixin _$IndexedActivityToolReadItem {

 int get index; ReadText get callId; ReadText? get taskId; ReadText get name; ReadText get summary; ThreadActivityArgumentsKind get arguments; ThreadActivityToolState get state; int? get ordinal; int? get startedAt; WaitReadValue? get wait;
/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IndexedActivityToolReadItemCopyWith<IndexedActivityToolReadItem> get copyWith => _$IndexedActivityToolReadItemCopyWithImpl<IndexedActivityToolReadItem>(this as IndexedActivityToolReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as IndexedActivityToolReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IndexedActivityToolReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.callId, _this.callId) || other.callId == _this.callId)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.arguments, _this.arguments) || other.arguments == _this.arguments)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.ordinal, _this.ordinal) || other.ordinal == _this.ordinal)&&(identical(other.startedAt, _this.startedAt) || other.startedAt == _this.startedAt)&&(identical(other.wait, _this.wait) || other.wait == _this.wait));
}


@override
int get hashCode {
  final _this = this as IndexedActivityToolReadItem;
  return Object.hash(runtimeType,_this.index,_this.callId,_this.taskId,_this.name,_this.summary,_this.arguments,_this.state,_this.ordinal,_this.startedAt,_this.wait);
}



}

/// @nodoc
abstract mixin class $IndexedActivityToolReadItemCopyWith<$Res>  {
  factory $IndexedActivityToolReadItemCopyWith(IndexedActivityToolReadItem value, $Res Function(IndexedActivityToolReadItem) _then) = _$IndexedActivityToolReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText callId, ReadText? taskId, ReadText name, ReadText summary, ThreadActivityArgumentsKind arguments, ThreadActivityToolState state, int? ordinal, int? startedAt, WaitReadValue? wait
});


$ReadTextCopyWith<$Res> get callId;$ReadTextCopyWith<$Res>? get taskId;$ReadTextCopyWith<$Res> get name;$ReadTextCopyWith<$Res> get summary;$WaitReadValueCopyWith<$Res>? get wait;

}
/// @nodoc
class _$IndexedActivityToolReadItemCopyWithImpl<$Res>
    implements $IndexedActivityToolReadItemCopyWith<$Res> {
  _$IndexedActivityToolReadItemCopyWithImpl(this._self, this._then);

  final IndexedActivityToolReadItem _self;
  final $Res Function(IndexedActivityToolReadItem) _then;

/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? callId = null,Object? taskId = freezed,Object? name = null,Object? summary = null,Object? arguments = null,Object? state = null,Object? ordinal = freezed,Object? startedAt = freezed,Object? wait = freezed,}) {
  return _then(IndexedActivityToolReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as ReadText,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as ReadText?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as ThreadActivityArgumentsKind,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadActivityToolState,ordinal: freezed == ordinal ? _self.ordinal : ordinal // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as WaitReadValue?,
  ));
}
/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get callId {

  return $ReadTextCopyWith<$Res>(_self.callId, (value) {
    return _then(_self.copyWith(callId: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get taskId {
    if (_self.taskId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.taskId!, (value) {
    return _then(_self.copyWith(taskId: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get summary {

  return $ReadTextCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WaitReadValueCopyWith<$Res>? get wait {
    if (_self.wait == null) {
    return null;
  }

  return $WaitReadValueCopyWith<$Res>(_self.wait!, (value) {
    return _then(_self.copyWith(wait: value));
  });
}
}


/// Adds pattern-matching-related methods to [IndexedActivityToolReadItem].
extension IndexedActivityToolReadItemPatterns on IndexedActivityToolReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _IndexedActivityToolReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _IndexedActivityToolReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _IndexedActivityToolReadItem value)  $default,){
final _that = this;
switch (_that) {
case _IndexedActivityToolReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _IndexedActivityToolReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _IndexedActivityToolReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText callId,  ReadText? taskId,  ReadText name,  ReadText summary,  ThreadActivityArgumentsKind arguments,  ThreadActivityToolState state,  int? ordinal,  int? startedAt,  WaitReadValue? wait)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _IndexedActivityToolReadItem() when $default != null:
return $default(_that.index,_that.callId,_that.taskId,_that.name,_that.summary,_that.arguments,_that.state,_that.ordinal,_that.startedAt,_that.wait);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText callId,  ReadText? taskId,  ReadText name,  ReadText summary,  ThreadActivityArgumentsKind arguments,  ThreadActivityToolState state,  int? ordinal,  int? startedAt,  WaitReadValue? wait)  $default,) {final _that = this;
switch (_that) {
case _IndexedActivityToolReadItem():
return $default(_that.index,_that.callId,_that.taskId,_that.name,_that.summary,_that.arguments,_that.state,_that.ordinal,_that.startedAt,_that.wait);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText callId,  ReadText? taskId,  ReadText name,  ReadText summary,  ThreadActivityArgumentsKind arguments,  ThreadActivityToolState state,  int? ordinal,  int? startedAt,  WaitReadValue? wait)?  $default,) {final _that = this;
switch (_that) {
case _IndexedActivityToolReadItem() when $default != null:
return $default(_that.index,_that.callId,_that.taskId,_that.name,_that.summary,_that.arguments,_that.state,_that.ordinal,_that.startedAt,_that.wait);case _:
  return null;

}
}

}

/// @nodoc


class _IndexedActivityToolReadItem implements IndexedActivityToolReadItem {
  const _IndexedActivityToolReadItem({required this.index, required this.callId, required this.taskId, required this.name, required this.summary, required this.arguments, required this.state, required this.ordinal, required this.startedAt, required this.wait});


@override final  int index;
@override final  ReadText callId;
@override final  ReadText? taskId;
@override final  ReadText name;
@override final  ReadText summary;
@override final  ThreadActivityArgumentsKind arguments;
@override final  ThreadActivityToolState state;
@override final  int? ordinal;
@override final  int? startedAt;
@override final  WaitReadValue? wait;

/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IndexedActivityToolReadItemCopyWith<_IndexedActivityToolReadItem> get copyWith => __$IndexedActivityToolReadItemCopyWithImpl<_IndexedActivityToolReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _IndexedActivityToolReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.callId, callId) || other.callId == callId)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.name, name) || other.name == name)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.state, state) || other.state == state)&&(identical(other.ordinal, ordinal) || other.ordinal == ordinal)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.wait, wait) || other.wait == wait));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,callId,taskId,name,summary,arguments,state,ordinal,startedAt,wait);
}



}

/// @nodoc
abstract mixin class _$IndexedActivityToolReadItemCopyWith<$Res> implements $IndexedActivityToolReadItemCopyWith<$Res> {
  factory _$IndexedActivityToolReadItemCopyWith(_IndexedActivityToolReadItem value, $Res Function(_IndexedActivityToolReadItem) _then) = __$IndexedActivityToolReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText callId, ReadText? taskId, ReadText name, ReadText summary, ThreadActivityArgumentsKind arguments, ThreadActivityToolState state, int? ordinal, int? startedAt, WaitReadValue? wait
});


@override $ReadTextCopyWith<$Res> get callId;@override $ReadTextCopyWith<$Res>? get taskId;@override $ReadTextCopyWith<$Res> get name;@override $ReadTextCopyWith<$Res> get summary;@override $WaitReadValueCopyWith<$Res>? get wait;

}
/// @nodoc
class __$IndexedActivityToolReadItemCopyWithImpl<$Res>
    implements _$IndexedActivityToolReadItemCopyWith<$Res> {
  __$IndexedActivityToolReadItemCopyWithImpl(this._self, this._then);

  final _IndexedActivityToolReadItem _self;
  final $Res Function(_IndexedActivityToolReadItem) _then;

/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? callId = null,Object? taskId = freezed,Object? name = null,Object? summary = null,Object? arguments = null,Object? state = null,Object? ordinal = freezed,Object? startedAt = freezed,Object? wait = freezed,}) {
  return _then(_IndexedActivityToolReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,callId: null == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as ReadText,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as ReadText?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as ThreadActivityArgumentsKind,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadActivityToolState,ordinal: freezed == ordinal ? _self.ordinal : ordinal // ignore: cast_nullable_to_non_nullable
as int?,startedAt: freezed == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as WaitReadValue?,
  ));
}

/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get callId {

  return $ReadTextCopyWith<$Res>(_self.callId, (value) {
    return _then(_self.copyWith(callId: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get taskId {
    if (_self.taskId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.taskId!, (value) {
    return _then(_self.copyWith(taskId: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get summary {

  return $ReadTextCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of IndexedActivityToolReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WaitReadValueCopyWith<$Res>? get wait {
    if (_self.wait == null) {
    return null;
  }

  return $WaitReadValueCopyWith<$Res>(_self.wait!, (value) {
    return _then(_self.copyWith(wait: value));
  });
}
}

/// @nodoc
mixin _$ActivityToolPage {


/// Create a copy of ActivityToolPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityToolPageCopyWith<ActivityToolPage> get copyWith => _$ActivityToolPageCopyWithImpl<ActivityToolPage>(this as ActivityToolPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityToolPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityToolPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as ActivityToolPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $ActivityToolPageCopyWith<$Res>  {
  factory $ActivityToolPageCopyWith(ActivityToolPage value, $Res Function(ActivityToolPage) _then) = _$ActivityToolPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<IndexedActivityToolReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$ActivityToolPageCopyWithImpl<$Res>
    implements $ActivityToolPageCopyWith<$Res> {
  _$ActivityToolPageCopyWithImpl(this._self, this._then);

  final ActivityToolPage _self;
  final $Res Function(ActivityToolPage) _then;

/// Create a copy of ActivityToolPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(ActivityToolPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<IndexedActivityToolReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of ActivityToolPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActivityToolPage].
extension ActivityToolPagePatterns on ActivityToolPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$ActivityReadHeader {

 ReadScopeIdentity get scope; ReadText get threadId; ReadText get identity; ReadText get turnId; int get revision; ReadText? get inputId; ReadText? get attemptId; ThreadActivityKind get kind; ReadText get summary; bool get summaryTruncated; int get count; int get background; int get activeCount; ActivityToolReadItem? get latestStarted;
/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ActivityReadHeaderCopyWith<ActivityReadHeader> get copyWith => _$ActivityReadHeaderCopyWithImpl<ActivityReadHeader>(this as ActivityReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ActivityReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ActivityReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.identity, _this.identity) || other.identity == _this.identity)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.summaryTruncated, _this.summaryTruncated) || other.summaryTruncated == _this.summaryTruncated)&&(identical(other.count, _this.count) || other.count == _this.count)&&(identical(other.background, _this.background) || other.background == _this.background)&&(identical(other.activeCount, _this.activeCount) || other.activeCount == _this.activeCount)&&(identical(other.latestStarted, _this.latestStarted) || other.latestStarted == _this.latestStarted));
}


@override
int get hashCode {
  final _this = this as ActivityReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.threadId,_this.identity,_this.turnId,_this.revision,_this.inputId,_this.attemptId,_this.kind,_this.summary,_this.summaryTruncated,_this.count,_this.background,_this.activeCount,_this.latestStarted);
}



}

/// @nodoc
abstract mixin class $ActivityReadHeaderCopyWith<$Res>  {
  factory $ActivityReadHeaderCopyWith(ActivityReadHeader value, $Res Function(ActivityReadHeader) _then) = _$ActivityReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, ReadText threadId, ReadText identity, ReadText turnId, int revision, ReadText? inputId, ReadText? attemptId, ThreadActivityKind kind, ReadText summary, bool summaryTruncated, int count, int background, int activeCount, ActivityToolReadItem? latestStarted
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ReadTextCopyWith<$Res> get threadId;$ReadTextCopyWith<$Res> get identity;$ReadTextCopyWith<$Res> get turnId;$ReadTextCopyWith<$Res>? get inputId;$ReadTextCopyWith<$Res>? get attemptId;$ReadTextCopyWith<$Res> get summary;$ActivityToolReadItemCopyWith<$Res>? get latestStarted;

}
/// @nodoc
class _$ActivityReadHeaderCopyWithImpl<$Res>
    implements $ActivityReadHeaderCopyWith<$Res> {
  _$ActivityReadHeaderCopyWithImpl(this._self, this._then);

  final ActivityReadHeader _self;
  final $Res Function(ActivityReadHeader) _then;

/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? threadId = null,Object? identity = null,Object? turnId = null,Object? revision = null,Object? inputId = freezed,Object? attemptId = freezed,Object? kind = null,Object? summary = null,Object? summaryTruncated = null,Object? count = null,Object? background = null,Object? activeCount = null,Object? latestStarted = freezed,}) {
  return _then(ActivityReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ReadText,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as ReadText?,attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as ReadText?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ThreadActivityKind,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText,summaryTruncated: null == summaryTruncated ? _self.summaryTruncated : summaryTruncated // ignore: cast_nullable_to_non_nullable
as bool,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,background: null == background ? _self.background : background // ignore: cast_nullable_to_non_nullable
as int,activeCount: null == activeCount ? _self.activeCount : activeCount // ignore: cast_nullable_to_non_nullable
as int,latestStarted: freezed == latestStarted ? _self.latestStarted : latestStarted // ignore: cast_nullable_to_non_nullable
as ActivityToolReadItem?,
  ));
}
/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get identity {

  return $ReadTextCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of ActivityReadHeader
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
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get attemptId {
    if (_self.attemptId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.attemptId!, (value) {
    return _then(_self.copyWith(attemptId: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get summary {

  return $ReadTextCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityToolReadItemCopyWith<$Res>? get latestStarted {
    if (_self.latestStarted == null) {
    return null;
  }

  return $ActivityToolReadItemCopyWith<$Res>(_self.latestStarted!, (value) {
    return _then(_self.copyWith(latestStarted: value));
  });
}
}


/// Adds pattern-matching-related methods to [ActivityReadHeader].
extension ActivityReadHeaderPatterns on ActivityReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ActivityReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ActivityReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ActivityReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _ActivityReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ActivityReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ActivityReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText threadId,  ReadText identity,  ReadText turnId,  int revision,  ReadText? inputId,  ReadText? attemptId,  ThreadActivityKind kind,  ReadText summary,  bool summaryTruncated,  int count,  int background,  int activeCount,  ActivityToolReadItem? latestStarted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ActivityReadHeader() when $default != null:
return $default(_that.scope,_that.threadId,_that.identity,_that.turnId,_that.revision,_that.inputId,_that.attemptId,_that.kind,_that.summary,_that.summaryTruncated,_that.count,_that.background,_that.activeCount,_that.latestStarted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText threadId,  ReadText identity,  ReadText turnId,  int revision,  ReadText? inputId,  ReadText? attemptId,  ThreadActivityKind kind,  ReadText summary,  bool summaryTruncated,  int count,  int background,  int activeCount,  ActivityToolReadItem? latestStarted)  $default,) {final _that = this;
switch (_that) {
case _ActivityReadHeader():
return $default(_that.scope,_that.threadId,_that.identity,_that.turnId,_that.revision,_that.inputId,_that.attemptId,_that.kind,_that.summary,_that.summaryTruncated,_that.count,_that.background,_that.activeCount,_that.latestStarted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  ReadText threadId,  ReadText identity,  ReadText turnId,  int revision,  ReadText? inputId,  ReadText? attemptId,  ThreadActivityKind kind,  ReadText summary,  bool summaryTruncated,  int count,  int background,  int activeCount,  ActivityToolReadItem? latestStarted)?  $default,) {final _that = this;
switch (_that) {
case _ActivityReadHeader() when $default != null:
return $default(_that.scope,_that.threadId,_that.identity,_that.turnId,_that.revision,_that.inputId,_that.attemptId,_that.kind,_that.summary,_that.summaryTruncated,_that.count,_that.background,_that.activeCount,_that.latestStarted);case _:
  return null;

}
}

}

/// @nodoc


class _ActivityReadHeader implements ActivityReadHeader {
  const _ActivityReadHeader({required this.scope, required this.threadId, required this.identity, required this.turnId, required this.revision, required this.inputId, required this.attemptId, required this.kind, required this.summary, required this.summaryTruncated, required this.count, required this.background, required this.activeCount, required this.latestStarted});


@override final  ReadScopeIdentity scope;
@override final  ReadText threadId;
@override final  ReadText identity;
@override final  ReadText turnId;
@override final  int revision;
@override final  ReadText? inputId;
@override final  ReadText? attemptId;
@override final  ThreadActivityKind kind;
@override final  ReadText summary;
@override final  bool summaryTruncated;
@override final  int count;
@override final  int background;
@override final  int activeCount;
@override final  ActivityToolReadItem? latestStarted;

/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ActivityReadHeaderCopyWith<_ActivityReadHeader> get copyWith => __$ActivityReadHeaderCopyWithImpl<_ActivityReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ActivityReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.summaryTruncated, summaryTruncated) || other.summaryTruncated == summaryTruncated)&&(identical(other.count, count) || other.count == count)&&(identical(other.background, background) || other.background == background)&&(identical(other.activeCount, activeCount) || other.activeCount == activeCount)&&(identical(other.latestStarted, latestStarted) || other.latestStarted == latestStarted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,threadId,identity,turnId,revision,inputId,attemptId,kind,summary,summaryTruncated,count,background,activeCount,latestStarted);
}



}

/// @nodoc
abstract mixin class _$ActivityReadHeaderCopyWith<$Res> implements $ActivityReadHeaderCopyWith<$Res> {
  factory _$ActivityReadHeaderCopyWith(_ActivityReadHeader value, $Res Function(_ActivityReadHeader) _then) = __$ActivityReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, ReadText threadId, ReadText identity, ReadText turnId, int revision, ReadText? inputId, ReadText? attemptId, ThreadActivityKind kind, ReadText summary, bool summaryTruncated, int count, int background, int activeCount, ActivityToolReadItem? latestStarted
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ReadTextCopyWith<$Res> get threadId;@override $ReadTextCopyWith<$Res> get identity;@override $ReadTextCopyWith<$Res> get turnId;@override $ReadTextCopyWith<$Res>? get inputId;@override $ReadTextCopyWith<$Res>? get attemptId;@override $ReadTextCopyWith<$Res> get summary;@override $ActivityToolReadItemCopyWith<$Res>? get latestStarted;

}
/// @nodoc
class __$ActivityReadHeaderCopyWithImpl<$Res>
    implements _$ActivityReadHeaderCopyWith<$Res> {
  __$ActivityReadHeaderCopyWithImpl(this._self, this._then);

  final _ActivityReadHeader _self;
  final $Res Function(_ActivityReadHeader) _then;

/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? threadId = null,Object? identity = null,Object? turnId = null,Object? revision = null,Object? inputId = freezed,Object? attemptId = freezed,Object? kind = null,Object? summary = null,Object? summaryTruncated = null,Object? count = null,Object? background = null,Object? activeCount = null,Object? latestStarted = freezed,}) {
  return _then(_ActivityReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ReadText,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as ReadText?,attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as ReadText?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ThreadActivityKind,summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as ReadText,summaryTruncated: null == summaryTruncated ? _self.summaryTruncated : summaryTruncated // ignore: cast_nullable_to_non_nullable
as bool,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,background: null == background ? _self.background : background // ignore: cast_nullable_to_non_nullable
as int,activeCount: null == activeCount ? _self.activeCount : activeCount // ignore: cast_nullable_to_non_nullable
as int,latestStarted: freezed == latestStarted ? _self.latestStarted : latestStarted // ignore: cast_nullable_to_non_nullable
as ActivityToolReadItem?,
  ));
}

/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get identity {

  return $ReadTextCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of ActivityReadHeader
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
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get attemptId {
    if (_self.attemptId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.attemptId!, (value) {
    return _then(_self.copyWith(attemptId: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get summary {

  return $ReadTextCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of ActivityReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ActivityToolReadItemCopyWith<$Res>? get latestStarted {
    if (_self.latestStarted == null) {
    return null;
  }

  return $ActivityToolReadItemCopyWith<$Res>(_self.latestStarted!, (value) {
    return _then(_self.copyWith(latestStarted: value));
  });
}
}

// dart format on
