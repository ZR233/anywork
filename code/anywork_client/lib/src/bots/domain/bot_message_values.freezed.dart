// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bot_message_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotMessageQuery {


/// Create a copy of BotMessageQuery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotMessageQueryCopyWith<BotMessageQuery> get copyWith => _$BotMessageQueryCopyWithImpl<BotMessageQuery>(this as BotMessageQuery, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotMessageQuery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotMessageQuery&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.startTime, _this.startTime) || other.startTime == _this.startTime)&&(identical(other.endTime, _this.endTime) || other.endTime == _this.endTime)&&(identical(other.cursor, _this.cursor) || other.cursor == _this.cursor)&&(identical(other.limit, _this.limit) || other.limit == _this.limit));
}


@override
int get hashCode {
  final _this = this as BotMessageQuery;
  return Object.hash(runtimeType,_this.botId,_this.chatId,_this.startTime,_this.endTime,_this.cursor,_this.limit);
}



}

/// @nodoc
abstract mixin class $BotMessageQueryCopyWith<$Res>  {
  factory $BotMessageQueryCopyWith(BotMessageQuery value, $Res Function(BotMessageQuery) _then) = _$BotMessageQueryCopyWithImpl;
@useResult
$Res call({
 String botId, String chatId, int? startTime, int? endTime, String? cursor, int? limit
});




}
/// @nodoc
class _$BotMessageQueryCopyWithImpl<$Res>
    implements $BotMessageQueryCopyWith<$Res> {
  _$BotMessageQueryCopyWithImpl(this._self, this._then);

  final BotMessageQuery _self;
  final $Res Function(BotMessageQuery) _then;

/// Create a copy of BotMessageQuery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = null,Object? chatId = null,Object? startTime = freezed,Object? endTime = freezed,Object? cursor = freezed,Object? limit = freezed,}) {
  return _then(BotMessageQuery(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,startTime: freezed == startTime ? _self.startTime : startTime // ignore: cast_nullable_to_non_nullable
as int?,endTime: freezed == endTime ? _self.endTime : endTime // ignore: cast_nullable_to_non_nullable
as int?,cursor: freezed == cursor ? _self.cursor : cursor // ignore: cast_nullable_to_non_nullable
as String?,limit: freezed == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [BotMessageQuery].
extension BotMessageQueryPatterns on BotMessageQuery {
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
mixin _$BotMessageBody {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotMessageBody);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $BotMessageBodyCopyWith<$Res>  {
$BotMessageBodyCopyWith(BotMessageBody _, $Res Function(BotMessageBody) __);
}


/// Adds pattern-matching-related methods to [BotMessageBody].
extension BotMessageBodyPatterns on BotMessageBody {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BotTextMessageBody value)?  text,TResult Function( BotPostMessageBody value)?  post,TResult Function( BotUnsupportedMessageBody value)?  unsupported,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BotTextMessageBody() when text != null:
return text(_that);case BotPostMessageBody() when post != null:
return post(_that);case BotUnsupportedMessageBody() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BotTextMessageBody value)  text,required TResult Function( BotPostMessageBody value)  post,required TResult Function( BotUnsupportedMessageBody value)  unsupported,}){
final _that = this;
switch (_that) {
case BotTextMessageBody():
return text(_that);case BotPostMessageBody():
return post(_that);case BotUnsupportedMessageBody():
return unsupported(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BotTextMessageBody value)?  text,TResult? Function( BotPostMessageBody value)?  post,TResult? Function( BotUnsupportedMessageBody value)?  unsupported,}){
final _that = this;
switch (_that) {
case BotTextMessageBody() when text != null:
return text(_that);case BotPostMessageBody() when post != null:
return post(_that);case BotUnsupportedMessageBody() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  text,TResult Function( String text)?  post,TResult Function( String msgType,  String notice)?  unsupported,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BotTextMessageBody() when text != null:
return text(_that.text);case BotPostMessageBody() when post != null:
return post(_that.text);case BotUnsupportedMessageBody() when unsupported != null:
return unsupported(_that.msgType,_that.notice);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  text,required TResult Function( String text)  post,required TResult Function( String msgType,  String notice)  unsupported,}) {final _that = this;
switch (_that) {
case BotTextMessageBody():
return text(_that.text);case BotPostMessageBody():
return post(_that.text);case BotUnsupportedMessageBody():
return unsupported(_that.msgType,_that.notice);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  text,TResult? Function( String text)?  post,TResult? Function( String msgType,  String notice)?  unsupported,}) {final _that = this;
switch (_that) {
case BotTextMessageBody() when text != null:
return text(_that.text);case BotPostMessageBody() when post != null:
return post(_that.text);case BotUnsupportedMessageBody() when unsupported != null:
return unsupported(_that.msgType,_that.notice);case _:
  return null;

}
}

}

/// @nodoc


class BotTextMessageBody implements BotMessageBody {
  const BotTextMessageBody(this.text);


 final  String text;

/// Create a copy of BotMessageBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotTextMessageBodyCopyWith<BotTextMessageBody> get copyWith => _$BotTextMessageBodyCopyWithImpl<BotTextMessageBody>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotTextMessageBody&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}



}

/// @nodoc
abstract mixin class $BotTextMessageBodyCopyWith<$Res> implements $BotMessageBodyCopyWith<$Res> {
  factory $BotTextMessageBodyCopyWith(BotTextMessageBody value, $Res Function(BotTextMessageBody) _then) = _$BotTextMessageBodyCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$BotTextMessageBodyCopyWithImpl<$Res>
    implements $BotTextMessageBodyCopyWith<$Res> {
  _$BotTextMessageBodyCopyWithImpl(this._self, this._then);

  final BotTextMessageBody _self;
  final $Res Function(BotTextMessageBody) _then;

/// Create a copy of BotMessageBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(BotTextMessageBody(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotPostMessageBody implements BotMessageBody {
  const BotPostMessageBody(this.text);


 final  String text;

/// Create a copy of BotMessageBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotPostMessageBodyCopyWith<BotPostMessageBody> get copyWith => _$BotPostMessageBodyCopyWithImpl<BotPostMessageBody>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotPostMessageBody&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}



}

/// @nodoc
abstract mixin class $BotPostMessageBodyCopyWith<$Res> implements $BotMessageBodyCopyWith<$Res> {
  factory $BotPostMessageBodyCopyWith(BotPostMessageBody value, $Res Function(BotPostMessageBody) _then) = _$BotPostMessageBodyCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$BotPostMessageBodyCopyWithImpl<$Res>
    implements $BotPostMessageBodyCopyWith<$Res> {
  _$BotPostMessageBodyCopyWithImpl(this._self, this._then);

  final BotPostMessageBody _self;
  final $Res Function(BotPostMessageBody) _then;

/// Create a copy of BotMessageBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(BotPostMessageBody(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotUnsupportedMessageBody implements BotMessageBody {
  const BotUnsupportedMessageBody({required this.msgType, required this.notice});


 final  String msgType;
 final  String notice;

/// Create a copy of BotMessageBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotUnsupportedMessageBodyCopyWith<BotUnsupportedMessageBody> get copyWith => _$BotUnsupportedMessageBodyCopyWithImpl<BotUnsupportedMessageBody>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotUnsupportedMessageBody&&(identical(other.msgType, msgType) || other.msgType == msgType)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode {
    return Object.hash(runtimeType,msgType,notice);
}



}

/// @nodoc
abstract mixin class $BotUnsupportedMessageBodyCopyWith<$Res> implements $BotMessageBodyCopyWith<$Res> {
  factory $BotUnsupportedMessageBodyCopyWith(BotUnsupportedMessageBody value, $Res Function(BotUnsupportedMessageBody) _then) = _$BotUnsupportedMessageBodyCopyWithImpl;
@useResult
$Res call({
 String msgType, String notice
});




}
/// @nodoc
class _$BotUnsupportedMessageBodyCopyWithImpl<$Res>
    implements $BotUnsupportedMessageBodyCopyWith<$Res> {
  _$BotUnsupportedMessageBodyCopyWithImpl(this._self, this._then);

  final BotUnsupportedMessageBody _self;
  final $Res Function(BotUnsupportedMessageBody) _then;

/// Create a copy of BotMessageBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msgType = null,Object? notice = null,}) {
  return _then(BotUnsupportedMessageBody(
msgType: null == msgType ? _self.msgType : msgType // ignore: cast_nullable_to_non_nullable
as String,notice: null == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BotMessage {


/// Create a copy of BotMessage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotMessageCopyWith<BotMessage> get copyWith => _$BotMessageCopyWithImpl<BotMessage>(this as BotMessage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotMessage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotMessage&&(identical(other.messageId, _this.messageId) || other.messageId == _this.messageId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.senderOpenId, _this.senderOpenId) || other.senderOpenId == _this.senderOpenId)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.body, _this.body) || other.body == _this.body));
}


@override
int get hashCode {
  final _this = this as BotMessage;
  return Object.hash(runtimeType,_this.messageId,_this.chatId,_this.senderOpenId,_this.createdAt,_this.body);
}



}

/// @nodoc
abstract mixin class $BotMessageCopyWith<$Res>  {
  factory $BotMessageCopyWith(BotMessage value, $Res Function(BotMessage) _then) = _$BotMessageCopyWithImpl;
@useResult
$Res call({
 String messageId, String chatId, String? senderOpenId, int createdAt, BotMessageBody body
});


$BotMessageBodyCopyWith<$Res> get body;

}
/// @nodoc
class _$BotMessageCopyWithImpl<$Res>
    implements $BotMessageCopyWith<$Res> {
  _$BotMessageCopyWithImpl(this._self, this._then);

  final BotMessage _self;
  final $Res Function(BotMessage) _then;

/// Create a copy of BotMessage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? messageId = null,Object? chatId = null,Object? senderOpenId = freezed,Object? createdAt = null,Object? body = null,}) {
  return _then(BotMessage(
messageId: null == messageId ? _self.messageId : messageId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,senderOpenId: freezed == senderOpenId ? _self.senderOpenId : senderOpenId // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as BotMessageBody,
  ));
}
/// Create a copy of BotMessage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotMessageBodyCopyWith<$Res> get body {

  return $BotMessageBodyCopyWith<$Res>(_self.body, (value) {
    return _then(_self.copyWith(body: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotMessage].
extension BotMessagePatterns on BotMessage {
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
mixin _$BotMessagePage {


/// Create a copy of BotMessagePage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotMessagePageCopyWith<BotMessagePage> get copyWith => _$BotMessagePageCopyWithImpl<BotMessagePage>(this as BotMessagePage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotMessagePage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotMessagePage&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&const DeepCollectionEquality().equals(other.messages, _this.messages)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor));
}


@override
int get hashCode {
  final _this = this as BotMessagePage;
  return Object.hash(runtimeType,_this.botId,_this.chatId,const DeepCollectionEquality().hash(_this.messages),_this.nextCursor);
}



}

/// @nodoc
abstract mixin class $BotMessagePageCopyWith<$Res>  {
  factory $BotMessagePageCopyWith(BotMessagePage value, $Res Function(BotMessagePage) _then) = _$BotMessagePageCopyWithImpl;
@useResult
$Res call({
 String botId, String chatId, List<BotMessage> messages, String? nextCursor
});




}
/// @nodoc
class _$BotMessagePageCopyWithImpl<$Res>
    implements $BotMessagePageCopyWith<$Res> {
  _$BotMessagePageCopyWithImpl(this._self, this._then);

  final BotMessagePage _self;
  final $Res Function(BotMessagePage) _then;

/// Create a copy of BotMessagePage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = null,Object? chatId = null,Object? messages = null,Object? nextCursor = freezed,}) {
  return _then(BotMessagePage(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,messages: null == messages ? _self.messages : messages // ignore: cast_nullable_to_non_nullable
as List<BotMessage>,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BotMessagePage].
extension BotMessagePagePatterns on BotMessagePage {
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
mixin _$BotSendSegment {


/// Create a copy of BotSendSegment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotSendSegmentCopyWith<BotSendSegment> get copyWith => _$BotSendSegmentCopyWithImpl<BotSendSegment>(this as BotSendSegment, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotSendSegment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSendSegment&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.platformMessageId, _this.platformMessageId) || other.platformMessageId == _this.platformMessageId)&&(identical(other.diagnostic, _this.diagnostic) || other.diagnostic == _this.diagnostic));
}


@override
int get hashCode {
  final _this = this as BotSendSegment;
  return Object.hash(runtimeType,_this.index,_this.status,_this.platformMessageId,_this.diagnostic);
}



}

/// @nodoc
abstract mixin class $BotSendSegmentCopyWith<$Res>  {
  factory $BotSendSegmentCopyWith(BotSendSegment value, $Res Function(BotSendSegment) _then) = _$BotSendSegmentCopyWithImpl;
@useResult
$Res call({
 int index, BotSendStatus status, String? platformMessageId, BotDiagnostic? diagnostic
});


$BotDiagnosticCopyWith<$Res>? get diagnostic;

}
/// @nodoc
class _$BotSendSegmentCopyWithImpl<$Res>
    implements $BotSendSegmentCopyWith<$Res> {
  _$BotSendSegmentCopyWithImpl(this._self, this._then);

  final BotSendSegment _self;
  final $Res Function(BotSendSegment) _then;

/// Create a copy of BotSendSegment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? status = null,Object? platformMessageId = freezed,Object? diagnostic = freezed,}) {
  return _then(BotSendSegment(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BotSendStatus,platformMessageId: freezed == platformMessageId ? _self.platformMessageId : platformMessageId // ignore: cast_nullable_to_non_nullable
as String?,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BotDiagnostic?,
  ));
}
/// Create a copy of BotSendSegment
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotDiagnosticCopyWith<$Res>? get diagnostic {
    if (_self.diagnostic == null) {
    return null;
  }

  return $BotDiagnosticCopyWith<$Res>(_self.diagnostic!, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotSendSegment].
extension BotSendSegmentPatterns on BotSendSegment {
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
mixin _$BotSendResult {


/// Create a copy of BotSendResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotSendResultCopyWith<BotSendResult> get copyWith => _$BotSendResultCopyWithImpl<BotSendResult>(this as BotSendResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotSendResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSendResult&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.chatId, _this.chatId) || other.chatId == _this.chatId)&&(identical(other.status, _this.status) || other.status == _this.status)&&const DeepCollectionEquality().equals(other.segments, _this.segments)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt));
}


@override
int get hashCode {
  final _this = this as BotSendResult;
  return Object.hash(runtimeType,_this.operationId,_this.botId,_this.chatId,_this.status,const DeepCollectionEquality().hash(_this.segments),_this.receipt);
}



}

/// @nodoc
abstract mixin class $BotSendResultCopyWith<$Res>  {
  factory $BotSendResultCopyWith(BotSendResult value, $Res Function(BotSendResult) _then) = _$BotSendResultCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String botId, String chatId, BotSendStatus status, List<BotSendSegment> segments, CommitReceipt receipt
});


$OperationIdCopyWith<$Res> get operationId;$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$BotSendResultCopyWithImpl<$Res>
    implements $BotSendResultCopyWith<$Res> {
  _$BotSendResultCopyWithImpl(this._self, this._then);

  final BotSendResult _self;
  final $Res Function(BotSendResult) _then;

/// Create a copy of BotSendResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? botId = null,Object? chatId = null,Object? status = null,Object? segments = null,Object? receipt = null,}) {
  return _then(BotSendResult(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,chatId: null == chatId ? _self.chatId : chatId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BotSendStatus,segments: null == segments ? _self.segments : segments // ignore: cast_nullable_to_non_nullable
as List<BotSendSegment>,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}
/// Create a copy of BotSendResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of BotSendResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotSendResult].
extension BotSendResultPatterns on BotSendResult {
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
mixin _$BotMessagesState {


/// Create a copy of BotMessagesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotMessagesStateCopyWith<BotMessagesState> get copyWith => _$BotMessagesStateCopyWithImpl<BotMessagesState>(this as BotMessagesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotMessagesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotMessagesState&&(identical(other.query, _this.query) || other.query == _this.query)&&(identical(other.messagePage, _this.messagePage) || other.messagePage == _this.messagePage)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.closed, _this.closed) || other.closed == _this.closed));
}


@override
int get hashCode {
  final _this = this as BotMessagesState;
  return Object.hash(runtimeType,_this.query,_this.messagePage,_this.loading,_this.error,_this.closed);
}



}

/// @nodoc
abstract mixin class $BotMessagesStateCopyWith<$Res>  {
  factory $BotMessagesStateCopyWith(BotMessagesState value, $Res Function(BotMessagesState) _then) = _$BotMessagesStateCopyWithImpl;
@useResult
$Res call({
 BotMessageQuery? query, BotMessagePage? messagePage, bool loading, StudioFailure? error, bool closed
});


$BotMessageQueryCopyWith<$Res>? get query;$BotMessagePageCopyWith<$Res>? get messagePage;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$BotMessagesStateCopyWithImpl<$Res>
    implements $BotMessagesStateCopyWith<$Res> {
  _$BotMessagesStateCopyWithImpl(this._self, this._then);

  final BotMessagesState _self;
  final $Res Function(BotMessagesState) _then;

/// Create a copy of BotMessagesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? query = freezed,Object? messagePage = freezed,Object? loading = null,Object? error = freezed,Object? closed = null,}) {
  return _then(BotMessagesState(
query: freezed == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as BotMessageQuery?,messagePage: freezed == messagePage ? _self.messagePage : messagePage // ignore: cast_nullable_to_non_nullable
as BotMessagePage?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,closed: null == closed ? _self.closed : closed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of BotMessagesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotMessageQueryCopyWith<$Res>? get query {
    if (_self.query == null) {
    return null;
  }

  return $BotMessageQueryCopyWith<$Res>(_self.query!, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of BotMessagesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotMessagePageCopyWith<$Res>? get messagePage {
    if (_self.messagePage == null) {
    return null;
  }

  return $BotMessagePageCopyWith<$Res>(_self.messagePage!, (value) {
    return _then(_self.copyWith(messagePage: value));
  });
}/// Create a copy of BotMessagesState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotMessagesState].
extension BotMessagesStatePatterns on BotMessagesState {
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
mixin _$BotSendsState {


/// Create a copy of BotSendsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotSendsStateCopyWith<BotSendsState> get copyWith => _$BotSendsStateCopyWithImpl<BotSendsState>(this as BotSendsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotSendsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSendsState&&const DeepCollectionEquality().equals(other.byOperationId, _this.byOperationId));
}


@override
int get hashCode {
  final _this = this as BotSendsState;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.byOperationId));
}



}

/// @nodoc
abstract mixin class $BotSendsStateCopyWith<$Res>  {
  factory $BotSendsStateCopyWith(BotSendsState value, $Res Function(BotSendsState) _then) = _$BotSendsStateCopyWithImpl;
@useResult
$Res call({
 Map<OperationId, BotSendResult> byOperationId
});




}
/// @nodoc
class _$BotSendsStateCopyWithImpl<$Res>
    implements $BotSendsStateCopyWith<$Res> {
  _$BotSendsStateCopyWithImpl(this._self, this._then);

  final BotSendsState _self;
  final $Res Function(BotSendsState) _then;

/// Create a copy of BotSendsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? byOperationId = null,}) {
  return _then(BotSendsState(
byOperationId: null == byOperationId ? _self.byOperationId : byOperationId // ignore: cast_nullable_to_non_nullable
as Map<OperationId, BotSendResult>,
  ));
}

}


/// Adds pattern-matching-related methods to [BotSendsState].
extension BotSendsStatePatterns on BotSendsState {
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
