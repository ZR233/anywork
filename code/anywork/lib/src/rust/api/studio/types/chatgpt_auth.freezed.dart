// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chatgpt_auth.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAccountAuthenticationIntent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountAuthenticationIntent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountAuthenticationIntent()';
}


}

/// @nodoc
class $BridgeAccountAuthenticationIntentCopyWith<$Res>  {
$BridgeAccountAuthenticationIntentCopyWith(BridgeAccountAuthenticationIntent _, $Res Function(BridgeAccountAuthenticationIntent) __);
}


/// Adds pattern-matching-related methods to [BridgeAccountAuthenticationIntent].
extension BridgeAccountAuthenticationIntentPatterns on BridgeAccountAuthenticationIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAccountAuthenticationIntent_Keep value)?  keep,TResult Function( BridgeAccountAuthenticationIntent_ApiKey value)?  apiKey,TResult Function( BridgeAccountAuthenticationIntent_ChatGpt value)?  chatGpt,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAccountAuthenticationIntent_Keep() when keep != null:
return keep(_that);case BridgeAccountAuthenticationIntent_ApiKey() when apiKey != null:
return apiKey(_that);case BridgeAccountAuthenticationIntent_ChatGpt() when chatGpt != null:
return chatGpt(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAccountAuthenticationIntent_Keep value)  keep,required TResult Function( BridgeAccountAuthenticationIntent_ApiKey value)  apiKey,required TResult Function( BridgeAccountAuthenticationIntent_ChatGpt value)  chatGpt,}){
final _that = this;
switch (_that) {
case BridgeAccountAuthenticationIntent_Keep():
return keep(_that);case BridgeAccountAuthenticationIntent_ApiKey():
return apiKey(_that);case BridgeAccountAuthenticationIntent_ChatGpt():
return chatGpt(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAccountAuthenticationIntent_Keep value)?  keep,TResult? Function( BridgeAccountAuthenticationIntent_ApiKey value)?  apiKey,TResult? Function( BridgeAccountAuthenticationIntent_ChatGpt value)?  chatGpt,}){
final _that = this;
switch (_that) {
case BridgeAccountAuthenticationIntent_Keep() when keep != null:
return keep(_that);case BridgeAccountAuthenticationIntent_ApiKey() when apiKey != null:
return apiKey(_that);case BridgeAccountAuthenticationIntent_ChatGpt() when chatGpt != null:
return chatGpt(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  keep,TResult Function()?  apiKey,TResult Function( String loginId,  String editorId)?  chatGpt,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAccountAuthenticationIntent_Keep() when keep != null:
return keep();case BridgeAccountAuthenticationIntent_ApiKey() when apiKey != null:
return apiKey();case BridgeAccountAuthenticationIntent_ChatGpt() when chatGpt != null:
return chatGpt(_that.loginId,_that.editorId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  keep,required TResult Function()  apiKey,required TResult Function( String loginId,  String editorId)  chatGpt,}) {final _that = this;
switch (_that) {
case BridgeAccountAuthenticationIntent_Keep():
return keep();case BridgeAccountAuthenticationIntent_ApiKey():
return apiKey();case BridgeAccountAuthenticationIntent_ChatGpt():
return chatGpt(_that.loginId,_that.editorId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  keep,TResult? Function()?  apiKey,TResult? Function( String loginId,  String editorId)?  chatGpt,}) {final _that = this;
switch (_that) {
case BridgeAccountAuthenticationIntent_Keep() when keep != null:
return keep();case BridgeAccountAuthenticationIntent_ApiKey() when apiKey != null:
return apiKey();case BridgeAccountAuthenticationIntent_ChatGpt() when chatGpt != null:
return chatGpt(_that.loginId,_that.editorId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAccountAuthenticationIntent_Keep extends BridgeAccountAuthenticationIntent {
  const BridgeAccountAuthenticationIntent_Keep(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountAuthenticationIntent_Keep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountAuthenticationIntent.keep()';
}


}




/// @nodoc


class BridgeAccountAuthenticationIntent_ApiKey extends BridgeAccountAuthenticationIntent {
  const BridgeAccountAuthenticationIntent_ApiKey(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountAuthenticationIntent_ApiKey);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAccountAuthenticationIntent.apiKey()';
}


}




/// @nodoc


class BridgeAccountAuthenticationIntent_ChatGpt extends BridgeAccountAuthenticationIntent {
  const BridgeAccountAuthenticationIntent_ChatGpt({required this.loginId, required this.editorId}): super._();


 final  String loginId;
 final  String editorId;

/// Create a copy of BridgeAccountAuthenticationIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAccountAuthenticationIntent_ChatGptCopyWith<BridgeAccountAuthenticationIntent_ChatGpt> get copyWith => _$BridgeAccountAuthenticationIntent_ChatGptCopyWithImpl<BridgeAccountAuthenticationIntent_ChatGpt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAccountAuthenticationIntent_ChatGpt&&(identical(other.loginId, loginId) || other.loginId == loginId)&&(identical(other.editorId, editorId) || other.editorId == editorId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,loginId,editorId);
}

@override
String toString() {
    return 'BridgeAccountAuthenticationIntent.chatGpt(loginId: $loginId, editorId: $editorId)';
}


}

/// @nodoc
abstract mixin class $BridgeAccountAuthenticationIntent_ChatGptCopyWith<$Res> implements $BridgeAccountAuthenticationIntentCopyWith<$Res> {
  factory $BridgeAccountAuthenticationIntent_ChatGptCopyWith(BridgeAccountAuthenticationIntent_ChatGpt value, $Res Function(BridgeAccountAuthenticationIntent_ChatGpt) _then) = _$BridgeAccountAuthenticationIntent_ChatGptCopyWithImpl;
@useResult
$Res call({
 String loginId, String editorId
});




}
/// @nodoc
class _$BridgeAccountAuthenticationIntent_ChatGptCopyWithImpl<$Res>
    implements $BridgeAccountAuthenticationIntent_ChatGptCopyWith<$Res> {
  _$BridgeAccountAuthenticationIntent_ChatGptCopyWithImpl(this._self, this._then);

  final BridgeAccountAuthenticationIntent_ChatGpt _self;
  final $Res Function(BridgeAccountAuthenticationIntent_ChatGpt) _then;

/// Create a copy of BridgeAccountAuthenticationIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? loginId = null,Object? editorId = null,}) {
  return _then(BridgeAccountAuthenticationIntent_ChatGpt(
loginId: null == loginId ? _self.loginId : loginId // ignore: cast_nullable_to_non_nullable
as String,editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
