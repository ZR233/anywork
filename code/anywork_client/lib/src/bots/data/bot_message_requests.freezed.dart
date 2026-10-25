// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bot_message_requests.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SendBotMessageRequest {


/// Create a copy of SendBotMessageRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SendBotMessageRequestCopyWith<SendBotMessageRequest> get copyWith => _$SendBotMessageRequestCopyWithImpl<SendBotMessageRequest>(this as SendBotMessageRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SendBotMessageRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SendBotMessageRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.text, _this.text) || other.text == _this.text));
}


@override
int get hashCode {
  final _this = this as SendBotMessageRequest;
  return Object.hash(runtimeType,_this.operationId,_this.botId,_this.chatId,_this.text);
}



}

/// @nodoc
abstract mixin class $SendBotMessageRequestCopyWith<$Res>  {
  factory $SendBotMessageRequestCopyWith(SendBotMessageRequest value, $Res Function(SendBotMessageRequest) _then) = _$SendBotMessageRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String botId, String chatId, String text
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SendBotMessageRequestCopyWithImpl<$Res>
    implements $SendBotMessageRequestCopyWith<$Res> {
  _$SendBotMessageRequestCopyWithImpl(this._self, this._then);

  final SendBotMessageRequest _self;
  final $Res Function(SendBotMessageRequest) _then;

/// Create a copy of SendBotMessageRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = null,Object? chatId = null,Object? text = null,}) {
  return _then(SendBotMessageRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of SendBotMessageRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SendBotMessageRequest].
extension SendBotMessageRequestPatterns on SendBotMessageRequest {
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

// dart format on
