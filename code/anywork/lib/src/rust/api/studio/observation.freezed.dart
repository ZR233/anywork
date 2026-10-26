// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'observation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeReadText {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeReadText);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeReadText()';
}


}

/// @nodoc
class $BridgeReadTextCopyWith<$Res>  {
$BridgeReadTextCopyWith(BridgeReadText _, $Res Function(BridgeReadText) __);
}


/// Adds pattern-matching-related methods to [BridgeReadText].
extension BridgeReadTextPatterns on BridgeReadText {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeReadText_Inline value)?  inline,TResult Function( BridgeReadText_Deferred value)?  deferred_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeReadText_Inline() when inline != null:
return inline(_that);case BridgeReadText_Deferred() when deferred_ != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeReadText_Inline value)  inline,required TResult Function( BridgeReadText_Deferred value)  deferred_,}){
final _that = this;
switch (_that) {
case BridgeReadText_Inline():
return inline(_that);case BridgeReadText_Deferred():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeReadText_Inline value)?  inline,TResult? Function( BridgeReadText_Deferred value)?  deferred_,}){
final _that = this;
switch (_that) {
case BridgeReadText_Inline() when inline != null:
return inline(_that);case BridgeReadText_Deferred() when deferred_ != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  inline,TResult Function( BigInt fieldId,  BigInt utf8Bytes)?  deferred_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeReadText_Inline() when inline != null:
return inline(_that.text);case BridgeReadText_Deferred() when deferred_ != null:
return deferred_(_that.fieldId,_that.utf8Bytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  inline,required TResult Function( BigInt fieldId,  BigInt utf8Bytes)  deferred_,}) {final _that = this;
switch (_that) {
case BridgeReadText_Inline():
return inline(_that.text);case BridgeReadText_Deferred():
return deferred_(_that.fieldId,_that.utf8Bytes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  inline,TResult? Function( BigInt fieldId,  BigInt utf8Bytes)?  deferred_,}) {final _that = this;
switch (_that) {
case BridgeReadText_Inline() when inline != null:
return inline(_that.text);case BridgeReadText_Deferred() when deferred_ != null:
return deferred_(_that.fieldId,_that.utf8Bytes);case _:
  return null;

}
}

}

/// @nodoc


class BridgeReadText_Inline extends BridgeReadText {
  const BridgeReadText_Inline({required this.text}): super._();


 final  String text;

/// Create a copy of BridgeReadText
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeReadText_InlineCopyWith<BridgeReadText_Inline> get copyWith => _$BridgeReadText_InlineCopyWithImpl<BridgeReadText_Inline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeReadText_Inline&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'BridgeReadText.inline(text: $text)';
}


}

/// @nodoc
abstract mixin class $BridgeReadText_InlineCopyWith<$Res> implements $BridgeReadTextCopyWith<$Res> {
  factory $BridgeReadText_InlineCopyWith(BridgeReadText_Inline value, $Res Function(BridgeReadText_Inline) _then) = _$BridgeReadText_InlineCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$BridgeReadText_InlineCopyWithImpl<$Res>
    implements $BridgeReadText_InlineCopyWith<$Res> {
  _$BridgeReadText_InlineCopyWithImpl(this._self, this._then);

  final BridgeReadText_Inline _self;
  final $Res Function(BridgeReadText_Inline) _then;

/// Create a copy of BridgeReadText
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(BridgeReadText_Inline(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeReadText_Deferred extends BridgeReadText {
  const BridgeReadText_Deferred({required this.fieldId, required this.utf8Bytes}): super._();


 final  BigInt fieldId;
 final  BigInt utf8Bytes;

/// Create a copy of BridgeReadText
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeReadText_DeferredCopyWith<BridgeReadText_Deferred> get copyWith => _$BridgeReadText_DeferredCopyWithImpl<BridgeReadText_Deferred>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeReadText_Deferred&&(identical(other.fieldId, fieldId) || other.fieldId == fieldId)&&(identical(other.utf8Bytes, utf8Bytes) || other.utf8Bytes == utf8Bytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fieldId,utf8Bytes);
}

@override
String toString() {
    return 'BridgeReadText.deferred_(fieldId: $fieldId, utf8Bytes: $utf8Bytes)';
}


}

/// @nodoc
abstract mixin class $BridgeReadText_DeferredCopyWith<$Res> implements $BridgeReadTextCopyWith<$Res> {
  factory $BridgeReadText_DeferredCopyWith(BridgeReadText_Deferred value, $Res Function(BridgeReadText_Deferred) _then) = _$BridgeReadText_DeferredCopyWithImpl;
@useResult
$Res call({
 BigInt fieldId, BigInt utf8Bytes
});




}
/// @nodoc
class _$BridgeReadText_DeferredCopyWithImpl<$Res>
    implements $BridgeReadText_DeferredCopyWith<$Res> {
  _$BridgeReadText_DeferredCopyWithImpl(this._self, this._then);

  final BridgeReadText_Deferred _self;
  final $Res Function(BridgeReadText_Deferred) _then;

/// Create a copy of BridgeReadText
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fieldId = null,Object? utf8Bytes = null,}) {
  return _then(BridgeReadText_Deferred(
fieldId: null == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as BigInt,utf8Bytes: null == utf8Bytes ? _self.utf8Bytes : utf8Bytes // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
