// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'continuation_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ContinueThreadReply {

 String get threadId; String get inputId; String get continuationId; int get cursor; CommitReceipt get receipt;
/// Create a copy of ContinueThreadReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContinueThreadReplyCopyWith<ContinueThreadReply> get copyWith => _$ContinueThreadReplyCopyWithImpl<ContinueThreadReply>(this as ContinueThreadReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContinueThreadReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContinueThreadReply&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.continuationId, _this.continuationId) || other.continuationId == _this.continuationId)&&(identical(other.cursor, _this.cursor) || other.cursor == _this.cursor)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as ContinueThreadReply;
  return Object.hash(runtimeType,_this.threadId,_this.inputId,_this.continuationId,_this.cursor,_this.receipt);
}



}

/// @nodoc
abstract mixin class $ContinueThreadReplyCopyWith<$Res>  {
  factory $ContinueThreadReplyCopyWith(ContinueThreadReply value, $Res Function(ContinueThreadReply) _then) = _$ContinueThreadReplyCopyWithImpl;
@useResult
$Res call({
 String threadId, String inputId, String continuationId, int cursor, CommitReceipt receipt
});


$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$ContinueThreadReplyCopyWithImpl<$Res>
    implements $ContinueThreadReplyCopyWith<$Res> {
  _$ContinueThreadReplyCopyWithImpl(this._self, this._then);

  final ContinueThreadReply _self;
  final $Res Function(ContinueThreadReply) _then;

/// Create a copy of ContinueThreadReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? inputId = null,Object? continuationId = null,Object? cursor = null,Object? receipt = null,}) {
  return _then(ContinueThreadReply(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,continuationId: null == continuationId ? _self.continuationId : continuationId // ignore: cast_nullable_to_non_nullable
as String,cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as int,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of ContinueThreadReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [ContinueThreadReply].
extension ContinueThreadReplyPatterns on ContinueThreadReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContinueThreadReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContinueThreadReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContinueThreadReply value)  $default,){
final _that = this;
switch (_that) {
case _ContinueThreadReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContinueThreadReply value)?  $default,){
final _that = this;
switch (_that) {
case _ContinueThreadReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  String inputId,  String continuationId,  int cursor,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContinueThreadReply() when $default != null:
return $default(_that.threadId,_that.inputId,_that.continuationId,_that.cursor,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  String inputId,  String continuationId,  int cursor,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _ContinueThreadReply():
return $default(_that.threadId,_that.inputId,_that.continuationId,_that.cursor,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  String inputId,  String continuationId,  int cursor,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _ContinueThreadReply() when $default != null:
return $default(_that.threadId,_that.inputId,_that.continuationId,_that.cursor,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _ContinueThreadReply implements ContinueThreadReply {
  const _ContinueThreadReply({required this.threadId, required this.inputId, required this.continuationId, required this.cursor, required this.receipt});


@override final  String threadId;
@override final  String inputId;
@override final  String continuationId;
@override final  int cursor;
@override final  CommitReceipt receipt;

/// Create a copy of ContinueThreadReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContinueThreadReplyCopyWith<_ContinueThreadReply> get copyWith => __$ContinueThreadReplyCopyWithImpl<_ContinueThreadReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContinueThreadReply&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.continuationId, continuationId) || other.continuationId == continuationId)&&(identical(other.cursor, cursor) || other.cursor == cursor)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,inputId,continuationId,cursor,receipt);
}



}

/// @nodoc
abstract mixin class _$ContinueThreadReplyCopyWith<$Res> implements $ContinueThreadReplyCopyWith<$Res> {
  factory _$ContinueThreadReplyCopyWith(_ContinueThreadReply value, $Res Function(_ContinueThreadReply) _then) = __$ContinueThreadReplyCopyWithImpl;
@override @useResult
$Res call({
 String threadId, String inputId, String continuationId, int cursor, CommitReceipt receipt
});


@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$ContinueThreadReplyCopyWithImpl<$Res>
    implements _$ContinueThreadReplyCopyWith<$Res> {
  __$ContinueThreadReplyCopyWithImpl(this._self, this._then);

  final _ContinueThreadReply _self;
  final $Res Function(_ContinueThreadReply) _then;

/// Create a copy of ContinueThreadReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? inputId = null,Object? continuationId = null,Object? cursor = null,Object? receipt = null,}) {
  return _then(_ContinueThreadReply(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,continuationId: null == continuationId ? _self.continuationId : continuationId // ignore: cast_nullable_to_non_nullable
as String,cursor: null == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as int,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of ContinueThreadReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

/// @nodoc
mixin _$ContinuationOperationState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ContinuationOperationState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ContinuationOperationState()';
}


}

/// @nodoc
class $ContinuationOperationStateCopyWith<$Res>  {
$ContinuationOperationStateCopyWith(ContinuationOperationState _, $Res Function(ContinuationOperationState) __);
}


/// Adds pattern-matching-related methods to [ContinuationOperationState].
extension ContinuationOperationStatePatterns on ContinuationOperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PendingContinuation value)?  pending,TResult Function( ConsumedContinuation value)?  consumed,TResult Function( DiscardedContinuation value)?  discarded,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PendingContinuation() when pending != null:
return pending(_that);case ConsumedContinuation() when consumed != null:
return consumed(_that);case DiscardedContinuation() when discarded != null:
return discarded(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PendingContinuation value)  pending,required TResult Function( ConsumedContinuation value)  consumed,required TResult Function( DiscardedContinuation value)  discarded,}){
final _that = this;
switch (_that) {
case PendingContinuation():
return pending(_that);case ConsumedContinuation():
return consumed(_that);case DiscardedContinuation():
return discarded(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PendingContinuation value)?  pending,TResult? Function( ConsumedContinuation value)?  consumed,TResult? Function( DiscardedContinuation value)?  discarded,}){
final _that = this;
switch (_that) {
case PendingContinuation() when pending != null:
return pending(_that);case ConsumedContinuation() when consumed != null:
return consumed(_that);case DiscardedContinuation() when discarded != null:
return discarded(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  pending,TResult Function( String turnId)?  consumed,TResult Function()?  discarded,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PendingContinuation() when pending != null:
return pending();case ConsumedContinuation() when consumed != null:
return consumed(_that.turnId);case DiscardedContinuation() when discarded != null:
return discarded();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  pending,required TResult Function( String turnId)  consumed,required TResult Function()  discarded,}) {final _that = this;
switch (_that) {
case PendingContinuation():
return pending();case ConsumedContinuation():
return consumed(_that.turnId);case DiscardedContinuation():
return discarded();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  pending,TResult? Function( String turnId)?  consumed,TResult? Function()?  discarded,}) {final _that = this;
switch (_that) {
case PendingContinuation() when pending != null:
return pending();case ConsumedContinuation() when consumed != null:
return consumed(_that.turnId);case DiscardedContinuation() when discarded != null:
return discarded();case _:
  return null;

}
}

}

/// @nodoc


class PendingContinuation implements ContinuationOperationState {
  const PendingContinuation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingContinuation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ContinuationOperationState.pending()';
}


}




/// @nodoc


class ConsumedContinuation implements ContinuationOperationState {
  const ConsumedContinuation({required this.turnId});


 final  String turnId;

/// Create a copy of ContinuationOperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConsumedContinuationCopyWith<ConsumedContinuation> get copyWith => _$ConsumedContinuationCopyWithImpl<ConsumedContinuation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConsumedContinuation&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,turnId);
}

@override
String toString() {
    return 'ContinuationOperationState.consumed(turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class $ConsumedContinuationCopyWith<$Res> implements $ContinuationOperationStateCopyWith<$Res> {
  factory $ConsumedContinuationCopyWith(ConsumedContinuation value, $Res Function(ConsumedContinuation) _then) = _$ConsumedContinuationCopyWithImpl;
@useResult
$Res call({
 String turnId
});




}
/// @nodoc
class _$ConsumedContinuationCopyWithImpl<$Res>
    implements $ConsumedContinuationCopyWith<$Res> {
  _$ConsumedContinuationCopyWithImpl(this._self, this._then);

  final ConsumedContinuation _self;
  final $Res Function(ConsumedContinuation) _then;

/// Create a copy of ContinuationOperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? turnId = null,}) {
  return _then(ConsumedContinuation(
turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DiscardedContinuation implements ContinuationOperationState {
  const DiscardedContinuation();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DiscardedContinuation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ContinuationOperationState.discarded()';
}


}




/// @nodoc
mixin _$ContinuationOperationView {

 String get threadId; OperationId get operationId; String get inputId; String get continuationId; int get acceptedSequence; ContinuationOperationState get state; bool get durable; CommitReceipt get receipt;
/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ContinuationOperationViewCopyWith<ContinuationOperationView> get copyWith => _$ContinuationOperationViewCopyWithImpl<ContinuationOperationView>(this as ContinuationOperationView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ContinuationOperationView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ContinuationOperationView&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.continuationId, _this.continuationId) || other.continuationId == _this.continuationId)&&(identical(other.acceptedSequence, _this.acceptedSequence) || other.acceptedSequence == _this.acceptedSequence)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.durable, _this.durable) || other.durable == _this.durable)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as ContinuationOperationView;
  return Object.hash(runtimeType,_this.threadId,_this.operationId,_this.inputId,_this.continuationId,_this.acceptedSequence,_this.state,_this.durable,_this.receipt);
}



}

/// @nodoc
abstract mixin class $ContinuationOperationViewCopyWith<$Res>  {
  factory $ContinuationOperationViewCopyWith(ContinuationOperationView value, $Res Function(ContinuationOperationView) _then) = _$ContinuationOperationViewCopyWithImpl;
@useResult
$Res call({
 String threadId, OperationId operationId, String inputId, String continuationId, int acceptedSequence, ContinuationOperationState state, bool durable, CommitReceipt receipt
});


$OperationIdCopyWith<$Res> get operationId;$ContinuationOperationStateCopyWith<$Res> get state;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$ContinuationOperationViewCopyWithImpl<$Res>
    implements $ContinuationOperationViewCopyWith<$Res> {
  _$ContinuationOperationViewCopyWithImpl(this._self, this._then);

  final ContinuationOperationView _self;
  final $Res Function(ContinuationOperationView) _then;

/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? operationId = null,Object? inputId = null,Object? continuationId = null,Object? acceptedSequence = null,Object? state = null,Object? durable = null,Object? receipt = null,}) {
  return _then(ContinuationOperationView(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,continuationId: null == continuationId ? _self.continuationId : continuationId // ignore: cast_nullable_to_non_nullable
as String,acceptedSequence: null == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ContinuationOperationState,durable: null == durable ? _self.durable : durable // ignore: cast_nullable_to_non_nullable
as bool,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContinuationOperationStateCopyWith<$Res> get state {

  return $ContinuationOperationStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [ContinuationOperationView].
extension ContinuationOperationViewPatterns on ContinuationOperationView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ContinuationOperationView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ContinuationOperationView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ContinuationOperationView value)  $default,){
final _that = this;
switch (_that) {
case _ContinuationOperationView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ContinuationOperationView value)?  $default,){
final _that = this;
switch (_that) {
case _ContinuationOperationView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  OperationId operationId,  String inputId,  String continuationId,  int acceptedSequence,  ContinuationOperationState state,  bool durable,  CommitReceipt receipt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ContinuationOperationView() when $default != null:
return $default(_that.threadId,_that.operationId,_that.inputId,_that.continuationId,_that.acceptedSequence,_that.state,_that.durable,_that.receipt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  OperationId operationId,  String inputId,  String continuationId,  int acceptedSequence,  ContinuationOperationState state,  bool durable,  CommitReceipt receipt)  $default,) {final _that = this;
switch (_that) {
case _ContinuationOperationView():
return $default(_that.threadId,_that.operationId,_that.inputId,_that.continuationId,_that.acceptedSequence,_that.state,_that.durable,_that.receipt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  OperationId operationId,  String inputId,  String continuationId,  int acceptedSequence,  ContinuationOperationState state,  bool durable,  CommitReceipt receipt)?  $default,) {final _that = this;
switch (_that) {
case _ContinuationOperationView() when $default != null:
return $default(_that.threadId,_that.operationId,_that.inputId,_that.continuationId,_that.acceptedSequence,_that.state,_that.durable,_that.receipt);case _:
  return null;

}
}

}

/// @nodoc


class _ContinuationOperationView implements ContinuationOperationView {
  const _ContinuationOperationView({required this.threadId, required this.operationId, required this.inputId, required this.continuationId, required this.acceptedSequence, required this.state, required this.durable, required this.receipt});


@override final  String threadId;
@override final  OperationId operationId;
@override final  String inputId;
@override final  String continuationId;
@override final  int acceptedSequence;
@override final  ContinuationOperationState state;
@override final  bool durable;
@override final  CommitReceipt receipt;

/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ContinuationOperationViewCopyWith<_ContinuationOperationView> get copyWith => __$ContinuationOperationViewCopyWithImpl<_ContinuationOperationView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ContinuationOperationView&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.continuationId, continuationId) || other.continuationId == continuationId)&&(identical(other.acceptedSequence, acceptedSequence) || other.acceptedSequence == acceptedSequence)&&(identical(other.state, state) || other.state == state)&&(identical(other.durable, durable) || other.durable == durable)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,operationId,inputId,continuationId,acceptedSequence,state,durable,receipt);
}



}

/// @nodoc
abstract mixin class _$ContinuationOperationViewCopyWith<$Res> implements $ContinuationOperationViewCopyWith<$Res> {
  factory _$ContinuationOperationViewCopyWith(_ContinuationOperationView value, $Res Function(_ContinuationOperationView) _then) = __$ContinuationOperationViewCopyWithImpl;
@override @useResult
$Res call({
 String threadId, OperationId operationId, String inputId, String continuationId, int acceptedSequence, ContinuationOperationState state, bool durable, CommitReceipt receipt
});


@override $OperationIdCopyWith<$Res> get operationId;@override $ContinuationOperationStateCopyWith<$Res> get state;@override $CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class __$ContinuationOperationViewCopyWithImpl<$Res>
    implements _$ContinuationOperationViewCopyWith<$Res> {
  __$ContinuationOperationViewCopyWithImpl(this._self, this._then);

  final _ContinuationOperationView _self;
  final $Res Function(_ContinuationOperationView) _then;

/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? operationId = null,Object? inputId = null,Object? continuationId = null,Object? acceptedSequence = null,Object? state = null,Object? durable = null,Object? receipt = null,}) {
  return _then(_ContinuationOperationView(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,continuationId: null == continuationId ? _self.continuationId : continuationId // ignore: cast_nullable_to_non_nullable
as String,acceptedSequence: null == acceptedSequence ? _self.acceptedSequence : acceptedSequence // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ContinuationOperationState,durable: null == durable ? _self.durable : durable // ignore: cast_nullable_to_non_nullable
as bool,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of ContinuationOperationView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ContinuationOperationStateCopyWith<$Res> get state {

  return $ContinuationOperationStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of ContinuationOperationView
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
