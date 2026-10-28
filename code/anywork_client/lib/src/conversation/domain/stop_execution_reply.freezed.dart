// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'stop_execution_reply.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StopExecutionReply {

 String get threadId; String get executionId; bool get stopped; CommitReceipt get receipt;
/// Create a copy of StopExecutionReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StopExecutionReplyCopyWith<StopExecutionReply> get copyWith => _$StopExecutionReplyCopyWithImpl<StopExecutionReply>(this as StopExecutionReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StopExecutionReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StopExecutionReply&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.executionId, _this.executionId) || other.executionId == _this.executionId)&&(identical(other.stopped, _this.stopped) || other.stopped == _this.stopped)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as StopExecutionReply;
  return Object.hash(runtimeType,_this.threadId,_this.executionId,_this.stopped,_this.receipt);
}



}

/// @nodoc
abstract mixin class $StopExecutionReplyCopyWith<$Res>  {
  factory $StopExecutionReplyCopyWith(StopExecutionReply value, $Res Function(StopExecutionReply) _then) = _$StopExecutionReplyCopyWithImpl;
@useResult
$Res call({
 String threadId, String executionId, bool stopped, CommitReceipt receipt
});


$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$StopExecutionReplyCopyWithImpl<$Res>
    implements $StopExecutionReplyCopyWith<$Res> {
  _$StopExecutionReplyCopyWithImpl(this._self, this._then);

  final StopExecutionReply _self;
  final $Res Function(StopExecutionReply) _then;

/// Create a copy of StopExecutionReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? executionId = null,Object? stopped = null,Object? receipt = null,}) {
  return _then(StopExecutionReply(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,executionId: null == executionId ? _self.executionId : executionId // ignore: cast_nullable_to_non_nullable
as String,stopped: null == stopped ? _self.stopped : stopped // ignore: cast_nullable_to_non_nullable
as bool,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of StopExecutionReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [StopExecutionReply].
extension StopExecutionReplyPatterns on StopExecutionReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StopExecutionReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StopExecutionReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StopExecutionReply value)  $default,){
final _that = this;
switch (_that) {
case _StopExecutionReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StopExecutionReply value)?  $default,){
final _that = this;
switch (_that) {
case _StopExecutionReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  String executionId,  bool stopped,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StopExecutionReply() when $default != null:
return $default(_that.threadId,_that.executionId,_that.stopped,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  String executionId,  bool stopped,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _StopExecutionReply():
return $default(_that.threadId,_that.executionId,_that.stopped,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  String executionId,  bool stopped,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _StopExecutionReply() when $default != null:
return $default(_that.threadId,_that.executionId,_that.stopped,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _StopExecutionReply implements StopExecutionReply {
  const _StopExecutionReply({required this.threadId, required this.executionId, required this.stopped, required this.receipt});


@override final  String threadId;
@override final  String executionId;
@override final  bool stopped;
@override final  CommitReceipt receipt;

/// Create a copy of StopExecutionReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StopExecutionReplyCopyWith<_StopExecutionReply> get copyWith => __$StopExecutionReplyCopyWithImpl<_StopExecutionReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StopExecutionReply&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.executionId, executionId) || other.executionId == executionId)&&(identical(other.stopped, stopped) || other.stopped == stopped)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,executionId,stopped,receipt);
}



}

/// @nodoc
abstract mixin class _$StopExecutionReplyCopyWith<$Res> implements $StopExecutionReplyCopyWith<$Res> {
  factory _$StopExecutionReplyCopyWith(_StopExecutionReply value, $Res Function(_StopExecutionReply) _then) = __$StopExecutionReplyCopyWithImpl;
@override @useResult
$Res call({
 String threadId, String executionId, bool stopped, CommitReceipt receipt
});


@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$StopExecutionReplyCopyWithImpl<$Res>
    implements _$StopExecutionReplyCopyWith<$Res> {
  __$StopExecutionReplyCopyWithImpl(this._self, this._then);

  final _StopExecutionReply _self;
  final $Res Function(_StopExecutionReply) _then;

/// Create a copy of StopExecutionReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? executionId = null,Object? stopped = null,Object? receipt = null,}) {
  return _then(_StopExecutionReply(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,executionId: null == executionId ? _self.executionId : executionId // ignore: cast_nullable_to_non_nullable
as String,stopped: null == stopped ? _self.stopped : stopped // ignore: cast_nullable_to_non_nullable
as bool,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of StopExecutionReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

// dart format on
