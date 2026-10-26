// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interrupt_turn_reply.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InterruptTurnReply {

 String get threadId; String get turnId; bool get interrupted; CommitReceipt get receipt;
/// Create a copy of InterruptTurnReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InterruptTurnReplyCopyWith<InterruptTurnReply> get copyWith => _$InterruptTurnReplyCopyWithImpl<InterruptTurnReply>(this as InterruptTurnReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InterruptTurnReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InterruptTurnReply&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.interrupted, _this.interrupted) || other.interrupted == _this.interrupted)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as InterruptTurnReply;
  return Object.hash(runtimeType,_this.threadId,_this.turnId,_this.interrupted,_this.receipt);
}



}

/// @nodoc
abstract mixin class $InterruptTurnReplyCopyWith<$Res>  {
  factory $InterruptTurnReplyCopyWith(InterruptTurnReply value, $Res Function(InterruptTurnReply) _then) = _$InterruptTurnReplyCopyWithImpl;
@useResult
$Res call({
 String threadId, String turnId, bool interrupted, CommitReceipt receipt
});


$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$InterruptTurnReplyCopyWithImpl<$Res>
    implements $InterruptTurnReplyCopyWith<$Res> {
  _$InterruptTurnReplyCopyWithImpl(this._self, this._then);

  final InterruptTurnReply _self;
  final $Res Function(InterruptTurnReply) _then;

/// Create a copy of InterruptTurnReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? turnId = null,Object? interrupted = null,Object? receipt = null,}) {
  return _then(InterruptTurnReply(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,interrupted: null == interrupted ? _self.interrupted : interrupted // ignore: cast_nullable_to_non_nullable
as bool,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of InterruptTurnReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [InterruptTurnReply].
extension InterruptTurnReplyPatterns on InterruptTurnReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InterruptTurnReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InterruptTurnReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InterruptTurnReply value)  $default,){
final _that = this;
switch (_that) {
case _InterruptTurnReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InterruptTurnReply value)?  $default,){
final _that = this;
switch (_that) {
case _InterruptTurnReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  String turnId,  bool interrupted,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InterruptTurnReply() when $default != null:
return $default(_that.threadId,_that.turnId,_that.interrupted,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  String turnId,  bool interrupted,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _InterruptTurnReply():
return $default(_that.threadId,_that.turnId,_that.interrupted,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  String turnId,  bool interrupted,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _InterruptTurnReply() when $default != null:
return $default(_that.threadId,_that.turnId,_that.interrupted,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _InterruptTurnReply implements InterruptTurnReply {
  const _InterruptTurnReply({required this.threadId, required this.turnId, required this.interrupted, required this.receipt});


@override final  String threadId;
@override final  String turnId;
@override final  bool interrupted;
@override final  CommitReceipt receipt;

/// Create a copy of InterruptTurnReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InterruptTurnReplyCopyWith<_InterruptTurnReply> get copyWith => __$InterruptTurnReplyCopyWithImpl<_InterruptTurnReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InterruptTurnReply&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.interrupted, interrupted) || other.interrupted == interrupted)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,turnId,interrupted,receipt);
}



}

/// @nodoc
abstract mixin class _$InterruptTurnReplyCopyWith<$Res> implements $InterruptTurnReplyCopyWith<$Res> {
  factory _$InterruptTurnReplyCopyWith(_InterruptTurnReply value, $Res Function(_InterruptTurnReply) _then) = __$InterruptTurnReplyCopyWithImpl;
@override @useResult
$Res call({
 String threadId, String turnId, bool interrupted, CommitReceipt receipt
});


@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$InterruptTurnReplyCopyWithImpl<$Res>
    implements _$InterruptTurnReplyCopyWith<$Res> {
  __$InterruptTurnReplyCopyWithImpl(this._self, this._then);

  final _InterruptTurnReply _self;
  final $Res Function(_InterruptTurnReply) _then;

/// Create a copy of InterruptTurnReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? turnId = null,Object? interrupted = null,Object? receipt = null,}) {
  return _then(_InterruptTurnReply(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,interrupted: null == interrupted ? _self.interrupted : interrupted // ignore: cast_nullable_to_non_nullable
as bool,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of InterruptTurnReply
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
