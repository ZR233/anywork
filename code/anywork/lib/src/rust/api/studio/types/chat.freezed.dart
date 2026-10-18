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
mixin _$BridgeContentField {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentField()';
}


}

/// @nodoc
class $BridgeContentFieldCopyWith<$Res>  {
$BridgeContentFieldCopyWith(BridgeContentField _, $Res Function(BridgeContentField) __);
}


/// Adds pattern-matching-related methods to [BridgeContentField].
extension BridgeContentFieldPatterns on BridgeContentField {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeContentField_Text value)?  text,TResult Function( BridgeContentField_ThinkingSummary value)?  thinkingSummary,TResult Function( BridgeContentField_ThinkingContent value)?  thinkingContent,TResult Function( BridgeContentField_ToolArguments value)?  toolArguments,TResult Function( BridgeContentField_ToolResult value)?  toolResult,TResult Function( BridgeContentField_ToolOutputArtifacts value)?  toolOutputArtifacts,TResult Function( BridgeContentField_ToolUserInput value)?  toolUserInput,TResult Function( BridgeContentField_RawPayload value)?  rawPayload,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeContentField_Text() when text != null:
return text(_that);case BridgeContentField_ThinkingSummary() when thinkingSummary != null:
return thinkingSummary(_that);case BridgeContentField_ThinkingContent() when thinkingContent != null:
return thinkingContent(_that);case BridgeContentField_ToolArguments() when toolArguments != null:
return toolArguments(_that);case BridgeContentField_ToolResult() when toolResult != null:
return toolResult(_that);case BridgeContentField_ToolOutputArtifacts() when toolOutputArtifacts != null:
return toolOutputArtifacts(_that);case BridgeContentField_ToolUserInput() when toolUserInput != null:
return toolUserInput(_that);case BridgeContentField_RawPayload() when rawPayload != null:
return rawPayload(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeContentField_Text value)  text,required TResult Function( BridgeContentField_ThinkingSummary value)  thinkingSummary,required TResult Function( BridgeContentField_ThinkingContent value)  thinkingContent,required TResult Function( BridgeContentField_ToolArguments value)  toolArguments,required TResult Function( BridgeContentField_ToolResult value)  toolResult,required TResult Function( BridgeContentField_ToolOutputArtifacts value)  toolOutputArtifacts,required TResult Function( BridgeContentField_ToolUserInput value)  toolUserInput,required TResult Function( BridgeContentField_RawPayload value)  rawPayload,}){
final _that = this;
switch (_that) {
case BridgeContentField_Text():
return text(_that);case BridgeContentField_ThinkingSummary():
return thinkingSummary(_that);case BridgeContentField_ThinkingContent():
return thinkingContent(_that);case BridgeContentField_ToolArguments():
return toolArguments(_that);case BridgeContentField_ToolResult():
return toolResult(_that);case BridgeContentField_ToolOutputArtifacts():
return toolOutputArtifacts(_that);case BridgeContentField_ToolUserInput():
return toolUserInput(_that);case BridgeContentField_RawPayload():
return rawPayload(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeContentField_Text value)?  text,TResult? Function( BridgeContentField_ThinkingSummary value)?  thinkingSummary,TResult? Function( BridgeContentField_ThinkingContent value)?  thinkingContent,TResult? Function( BridgeContentField_ToolArguments value)?  toolArguments,TResult? Function( BridgeContentField_ToolResult value)?  toolResult,TResult? Function( BridgeContentField_ToolOutputArtifacts value)?  toolOutputArtifacts,TResult? Function( BridgeContentField_ToolUserInput value)?  toolUserInput,TResult? Function( BridgeContentField_RawPayload value)?  rawPayload,}){
final _that = this;
switch (_that) {
case BridgeContentField_Text() when text != null:
return text(_that);case BridgeContentField_ThinkingSummary() when thinkingSummary != null:
return thinkingSummary(_that);case BridgeContentField_ThinkingContent() when thinkingContent != null:
return thinkingContent(_that);case BridgeContentField_ToolArguments() when toolArguments != null:
return toolArguments(_that);case BridgeContentField_ToolResult() when toolResult != null:
return toolResult(_that);case BridgeContentField_ToolOutputArtifacts() when toolOutputArtifacts != null:
return toolOutputArtifacts(_that);case BridgeContentField_ToolUserInput() when toolUserInput != null:
return toolUserInput(_that);case BridgeContentField_RawPayload() when rawPayload != null:
return rawPayload(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  text,TResult Function( int chunkIndex)?  thinkingSummary,TResult Function( int chunkIndex)?  thinkingContent,TResult Function()?  toolArguments,TResult Function()?  toolResult,TResult Function()?  toolOutputArtifacts,TResult Function( int questionIndex,  BridgeThreadUserInputFieldPart part_)?  toolUserInput,TResult Function( int payloadIndex)?  rawPayload,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeContentField_Text() when text != null:
return text();case BridgeContentField_ThinkingSummary() when thinkingSummary != null:
return thinkingSummary(_that.chunkIndex);case BridgeContentField_ThinkingContent() when thinkingContent != null:
return thinkingContent(_that.chunkIndex);case BridgeContentField_ToolArguments() when toolArguments != null:
return toolArguments();case BridgeContentField_ToolResult() when toolResult != null:
return toolResult();case BridgeContentField_ToolOutputArtifacts() when toolOutputArtifacts != null:
return toolOutputArtifacts();case BridgeContentField_ToolUserInput() when toolUserInput != null:
return toolUserInput(_that.questionIndex,_that.part_);case BridgeContentField_RawPayload() when rawPayload != null:
return rawPayload(_that.payloadIndex);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  text,required TResult Function( int chunkIndex)  thinkingSummary,required TResult Function( int chunkIndex)  thinkingContent,required TResult Function()  toolArguments,required TResult Function()  toolResult,required TResult Function()  toolOutputArtifacts,required TResult Function( int questionIndex,  BridgeThreadUserInputFieldPart part_)  toolUserInput,required TResult Function( int payloadIndex)  rawPayload,}) {final _that = this;
switch (_that) {
case BridgeContentField_Text():
return text();case BridgeContentField_ThinkingSummary():
return thinkingSummary(_that.chunkIndex);case BridgeContentField_ThinkingContent():
return thinkingContent(_that.chunkIndex);case BridgeContentField_ToolArguments():
return toolArguments();case BridgeContentField_ToolResult():
return toolResult();case BridgeContentField_ToolOutputArtifacts():
return toolOutputArtifacts();case BridgeContentField_ToolUserInput():
return toolUserInput(_that.questionIndex,_that.part_);case BridgeContentField_RawPayload():
return rawPayload(_that.payloadIndex);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  text,TResult? Function( int chunkIndex)?  thinkingSummary,TResult? Function( int chunkIndex)?  thinkingContent,TResult? Function()?  toolArguments,TResult? Function()?  toolResult,TResult? Function()?  toolOutputArtifacts,TResult? Function( int questionIndex,  BridgeThreadUserInputFieldPart part_)?  toolUserInput,TResult? Function( int payloadIndex)?  rawPayload,}) {final _that = this;
switch (_that) {
case BridgeContentField_Text() when text != null:
return text();case BridgeContentField_ThinkingSummary() when thinkingSummary != null:
return thinkingSummary(_that.chunkIndex);case BridgeContentField_ThinkingContent() when thinkingContent != null:
return thinkingContent(_that.chunkIndex);case BridgeContentField_ToolArguments() when toolArguments != null:
return toolArguments();case BridgeContentField_ToolResult() when toolResult != null:
return toolResult();case BridgeContentField_ToolOutputArtifacts() when toolOutputArtifacts != null:
return toolOutputArtifacts();case BridgeContentField_ToolUserInput() when toolUserInput != null:
return toolUserInput(_that.questionIndex,_that.part_);case BridgeContentField_RawPayload() when rawPayload != null:
return rawPayload(_that.payloadIndex);case _:
  return null;

}
}

}

/// @nodoc


class BridgeContentField_Text extends BridgeContentField {
  const BridgeContentField_Text(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_Text);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentField.text()';
}


}




/// @nodoc


class BridgeContentField_ThinkingSummary extends BridgeContentField {
  const BridgeContentField_ThinkingSummary({required this.chunkIndex}): super._();


 final  int chunkIndex;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentField_ThinkingSummaryCopyWith<BridgeContentField_ThinkingSummary> get copyWith => _$BridgeContentField_ThinkingSummaryCopyWithImpl<BridgeContentField_ThinkingSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_ThinkingSummary&&(identical(other.chunkIndex, chunkIndex) || other.chunkIndex == chunkIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chunkIndex);
}

@override
String toString() {
    return 'BridgeContentField.thinkingSummary(chunkIndex: $chunkIndex)';
}


}

/// @nodoc
abstract mixin class $BridgeContentField_ThinkingSummaryCopyWith<$Res> implements $BridgeContentFieldCopyWith<$Res> {
  factory $BridgeContentField_ThinkingSummaryCopyWith(BridgeContentField_ThinkingSummary value, $Res Function(BridgeContentField_ThinkingSummary) _then) = _$BridgeContentField_ThinkingSummaryCopyWithImpl;
@useResult
$Res call({
 int chunkIndex
});




}
/// @nodoc
class _$BridgeContentField_ThinkingSummaryCopyWithImpl<$Res>
    implements $BridgeContentField_ThinkingSummaryCopyWith<$Res> {
  _$BridgeContentField_ThinkingSummaryCopyWithImpl(this._self, this._then);

  final BridgeContentField_ThinkingSummary _self;
  final $Res Function(BridgeContentField_ThinkingSummary) _then;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? chunkIndex = null,}) {
  return _then(BridgeContentField_ThinkingSummary(
chunkIndex: null == chunkIndex ? _self.chunkIndex : chunkIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeContentField_ThinkingContent extends BridgeContentField {
  const BridgeContentField_ThinkingContent({required this.chunkIndex}): super._();


 final  int chunkIndex;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentField_ThinkingContentCopyWith<BridgeContentField_ThinkingContent> get copyWith => _$BridgeContentField_ThinkingContentCopyWithImpl<BridgeContentField_ThinkingContent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_ThinkingContent&&(identical(other.chunkIndex, chunkIndex) || other.chunkIndex == chunkIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chunkIndex);
}

@override
String toString() {
    return 'BridgeContentField.thinkingContent(chunkIndex: $chunkIndex)';
}


}

/// @nodoc
abstract mixin class $BridgeContentField_ThinkingContentCopyWith<$Res> implements $BridgeContentFieldCopyWith<$Res> {
  factory $BridgeContentField_ThinkingContentCopyWith(BridgeContentField_ThinkingContent value, $Res Function(BridgeContentField_ThinkingContent) _then) = _$BridgeContentField_ThinkingContentCopyWithImpl;
@useResult
$Res call({
 int chunkIndex
});




}
/// @nodoc
class _$BridgeContentField_ThinkingContentCopyWithImpl<$Res>
    implements $BridgeContentField_ThinkingContentCopyWith<$Res> {
  _$BridgeContentField_ThinkingContentCopyWithImpl(this._self, this._then);

  final BridgeContentField_ThinkingContent _self;
  final $Res Function(BridgeContentField_ThinkingContent) _then;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? chunkIndex = null,}) {
  return _then(BridgeContentField_ThinkingContent(
chunkIndex: null == chunkIndex ? _self.chunkIndex : chunkIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeContentField_ToolArguments extends BridgeContentField {
  const BridgeContentField_ToolArguments(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_ToolArguments);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentField.toolArguments()';
}


}




/// @nodoc


class BridgeContentField_ToolResult extends BridgeContentField {
  const BridgeContentField_ToolResult(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_ToolResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentField.toolResult()';
}


}




/// @nodoc


class BridgeContentField_ToolOutputArtifacts extends BridgeContentField {
  const BridgeContentField_ToolOutputArtifacts(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_ToolOutputArtifacts);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeContentField.toolOutputArtifacts()';
}


}




/// @nodoc


class BridgeContentField_ToolUserInput extends BridgeContentField {
  const BridgeContentField_ToolUserInput({required this.questionIndex, required this.part_}): super._();


 final  int questionIndex;
 final  BridgeThreadUserInputFieldPart part_;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentField_ToolUserInputCopyWith<BridgeContentField_ToolUserInput> get copyWith => _$BridgeContentField_ToolUserInputCopyWithImpl<BridgeContentField_ToolUserInput>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_ToolUserInput&&(identical(other.questionIndex, questionIndex) || other.questionIndex == questionIndex)&&(identical(other.part_, part_) || other.part_ == part_));
}


@override
int get hashCode {
    return Object.hash(runtimeType,questionIndex,part_);
}

@override
String toString() {
    return 'BridgeContentField.toolUserInput(questionIndex: $questionIndex, part_: $part_)';
}


}

/// @nodoc
abstract mixin class $BridgeContentField_ToolUserInputCopyWith<$Res> implements $BridgeContentFieldCopyWith<$Res> {
  factory $BridgeContentField_ToolUserInputCopyWith(BridgeContentField_ToolUserInput value, $Res Function(BridgeContentField_ToolUserInput) _then) = _$BridgeContentField_ToolUserInputCopyWithImpl;
@useResult
$Res call({
 int questionIndex, BridgeThreadUserInputFieldPart part_
});


$BridgeThreadUserInputFieldPartCopyWith<$Res> get part_;

}
/// @nodoc
class _$BridgeContentField_ToolUserInputCopyWithImpl<$Res>
    implements $BridgeContentField_ToolUserInputCopyWith<$Res> {
  _$BridgeContentField_ToolUserInputCopyWithImpl(this._self, this._then);

  final BridgeContentField_ToolUserInput _self;
  final $Res Function(BridgeContentField_ToolUserInput) _then;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? questionIndex = null,Object? part_ = null,}) {
  return _then(BridgeContentField_ToolUserInput(
questionIndex: null == questionIndex ? _self.questionIndex : questionIndex // ignore: cast_nullable_to_non_nullable
as int,part_: null == part_ ? _self.part_ : part_ // ignore: cast_nullable_to_non_nullable
as BridgeThreadUserInputFieldPart,
  ));
}

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeThreadUserInputFieldPartCopyWith<$Res> get part_ {

  return $BridgeThreadUserInputFieldPartCopyWith<$Res>(_self.part_, (value) {
    return _then(_self.copyWith(part_: value));
  });
}
}

/// @nodoc


class BridgeContentField_RawPayload extends BridgeContentField {
  const BridgeContentField_RawPayload({required this.payloadIndex}): super._();


 final  int payloadIndex;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeContentField_RawPayloadCopyWith<BridgeContentField_RawPayload> get copyWith => _$BridgeContentField_RawPayloadCopyWithImpl<BridgeContentField_RawPayload>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeContentField_RawPayload&&(identical(other.payloadIndex, payloadIndex) || other.payloadIndex == payloadIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,payloadIndex);
}

@override
String toString() {
    return 'BridgeContentField.rawPayload(payloadIndex: $payloadIndex)';
}


}

/// @nodoc
abstract mixin class $BridgeContentField_RawPayloadCopyWith<$Res> implements $BridgeContentFieldCopyWith<$Res> {
  factory $BridgeContentField_RawPayloadCopyWith(BridgeContentField_RawPayload value, $Res Function(BridgeContentField_RawPayload) _then) = _$BridgeContentField_RawPayloadCopyWithImpl;
@useResult
$Res call({
 int payloadIndex
});




}
/// @nodoc
class _$BridgeContentField_RawPayloadCopyWithImpl<$Res>
    implements $BridgeContentField_RawPayloadCopyWith<$Res> {
  _$BridgeContentField_RawPayloadCopyWithImpl(this._self, this._then);

  final BridgeContentField_RawPayload _self;
  final $Res Function(BridgeContentField_RawPayload) _then;

/// Create a copy of BridgeContentField
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? payloadIndex = null,}) {
  return _then(BridgeContentField_RawPayload(
payloadIndex: null == payloadIndex ? _self.payloadIndex : payloadIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$BridgeThreadUserInputFieldPart {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadUserInputFieldPart);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadUserInputFieldPart()';
}


}

/// @nodoc
class $BridgeThreadUserInputFieldPartCopyWith<$Res>  {
$BridgeThreadUserInputFieldPartCopyWith(BridgeThreadUserInputFieldPart _, $Res Function(BridgeThreadUserInputFieldPart) __);
}


/// Adds pattern-matching-related methods to [BridgeThreadUserInputFieldPart].
extension BridgeThreadUserInputFieldPartPatterns on BridgeThreadUserInputFieldPart {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeThreadUserInputFieldPart_Header value)?  header,TResult Function( BridgeThreadUserInputFieldPart_Question value)?  question,TResult Function( BridgeThreadUserInputFieldPart_Answer value)?  answer,TResult Function( BridgeThreadUserInputFieldPart_OptionLabel value)?  optionLabel,TResult Function( BridgeThreadUserInputFieldPart_OptionDescription value)?  optionDescription,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeThreadUserInputFieldPart_Header() when header != null:
return header(_that);case BridgeThreadUserInputFieldPart_Question() when question != null:
return question(_that);case BridgeThreadUserInputFieldPart_Answer() when answer != null:
return answer(_that);case BridgeThreadUserInputFieldPart_OptionLabel() when optionLabel != null:
return optionLabel(_that);case BridgeThreadUserInputFieldPart_OptionDescription() when optionDescription != null:
return optionDescription(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeThreadUserInputFieldPart_Header value)  header,required TResult Function( BridgeThreadUserInputFieldPart_Question value)  question,required TResult Function( BridgeThreadUserInputFieldPart_Answer value)  answer,required TResult Function( BridgeThreadUserInputFieldPart_OptionLabel value)  optionLabel,required TResult Function( BridgeThreadUserInputFieldPart_OptionDescription value)  optionDescription,}){
final _that = this;
switch (_that) {
case BridgeThreadUserInputFieldPart_Header():
return header(_that);case BridgeThreadUserInputFieldPart_Question():
return question(_that);case BridgeThreadUserInputFieldPart_Answer():
return answer(_that);case BridgeThreadUserInputFieldPart_OptionLabel():
return optionLabel(_that);case BridgeThreadUserInputFieldPart_OptionDescription():
return optionDescription(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeThreadUserInputFieldPart_Header value)?  header,TResult? Function( BridgeThreadUserInputFieldPart_Question value)?  question,TResult? Function( BridgeThreadUserInputFieldPart_Answer value)?  answer,TResult? Function( BridgeThreadUserInputFieldPart_OptionLabel value)?  optionLabel,TResult? Function( BridgeThreadUserInputFieldPart_OptionDescription value)?  optionDescription,}){
final _that = this;
switch (_that) {
case BridgeThreadUserInputFieldPart_Header() when header != null:
return header(_that);case BridgeThreadUserInputFieldPart_Question() when question != null:
return question(_that);case BridgeThreadUserInputFieldPart_Answer() when answer != null:
return answer(_that);case BridgeThreadUserInputFieldPart_OptionLabel() when optionLabel != null:
return optionLabel(_that);case BridgeThreadUserInputFieldPart_OptionDescription() when optionDescription != null:
return optionDescription(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  header,TResult Function()?  question,TResult Function( int answerIndex)?  answer,TResult Function( int optionIndex)?  optionLabel,TResult Function( int optionIndex)?  optionDescription,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeThreadUserInputFieldPart_Header() when header != null:
return header();case BridgeThreadUserInputFieldPart_Question() when question != null:
return question();case BridgeThreadUserInputFieldPart_Answer() when answer != null:
return answer(_that.answerIndex);case BridgeThreadUserInputFieldPart_OptionLabel() when optionLabel != null:
return optionLabel(_that.optionIndex);case BridgeThreadUserInputFieldPart_OptionDescription() when optionDescription != null:
return optionDescription(_that.optionIndex);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  header,required TResult Function()  question,required TResult Function( int answerIndex)  answer,required TResult Function( int optionIndex)  optionLabel,required TResult Function( int optionIndex)  optionDescription,}) {final _that = this;
switch (_that) {
case BridgeThreadUserInputFieldPart_Header():
return header();case BridgeThreadUserInputFieldPart_Question():
return question();case BridgeThreadUserInputFieldPart_Answer():
return answer(_that.answerIndex);case BridgeThreadUserInputFieldPart_OptionLabel():
return optionLabel(_that.optionIndex);case BridgeThreadUserInputFieldPart_OptionDescription():
return optionDescription(_that.optionIndex);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  header,TResult? Function()?  question,TResult? Function( int answerIndex)?  answer,TResult? Function( int optionIndex)?  optionLabel,TResult? Function( int optionIndex)?  optionDescription,}) {final _that = this;
switch (_that) {
case BridgeThreadUserInputFieldPart_Header() when header != null:
return header();case BridgeThreadUserInputFieldPart_Question() when question != null:
return question();case BridgeThreadUserInputFieldPart_Answer() when answer != null:
return answer(_that.answerIndex);case BridgeThreadUserInputFieldPart_OptionLabel() when optionLabel != null:
return optionLabel(_that.optionIndex);case BridgeThreadUserInputFieldPart_OptionDescription() when optionDescription != null:
return optionDescription(_that.optionIndex);case _:
  return null;

}
}

}

/// @nodoc


class BridgeThreadUserInputFieldPart_Header extends BridgeThreadUserInputFieldPart {
  const BridgeThreadUserInputFieldPart_Header(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadUserInputFieldPart_Header);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadUserInputFieldPart.header()';
}


}




/// @nodoc


class BridgeThreadUserInputFieldPart_Question extends BridgeThreadUserInputFieldPart {
  const BridgeThreadUserInputFieldPart_Question(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadUserInputFieldPart_Question);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeThreadUserInputFieldPart.question()';
}


}




/// @nodoc


class BridgeThreadUserInputFieldPart_Answer extends BridgeThreadUserInputFieldPart {
  const BridgeThreadUserInputFieldPart_Answer({required this.answerIndex}): super._();


 final  int answerIndex;

/// Create a copy of BridgeThreadUserInputFieldPart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadUserInputFieldPart_AnswerCopyWith<BridgeThreadUserInputFieldPart_Answer> get copyWith => _$BridgeThreadUserInputFieldPart_AnswerCopyWithImpl<BridgeThreadUserInputFieldPart_Answer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadUserInputFieldPart_Answer&&(identical(other.answerIndex, answerIndex) || other.answerIndex == answerIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,answerIndex);
}

@override
String toString() {
    return 'BridgeThreadUserInputFieldPart.answer(answerIndex: $answerIndex)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadUserInputFieldPart_AnswerCopyWith<$Res> implements $BridgeThreadUserInputFieldPartCopyWith<$Res> {
  factory $BridgeThreadUserInputFieldPart_AnswerCopyWith(BridgeThreadUserInputFieldPart_Answer value, $Res Function(BridgeThreadUserInputFieldPart_Answer) _then) = _$BridgeThreadUserInputFieldPart_AnswerCopyWithImpl;
@useResult
$Res call({
 int answerIndex
});




}
/// @nodoc
class _$BridgeThreadUserInputFieldPart_AnswerCopyWithImpl<$Res>
    implements $BridgeThreadUserInputFieldPart_AnswerCopyWith<$Res> {
  _$BridgeThreadUserInputFieldPart_AnswerCopyWithImpl(this._self, this._then);

  final BridgeThreadUserInputFieldPart_Answer _self;
  final $Res Function(BridgeThreadUserInputFieldPart_Answer) _then;

/// Create a copy of BridgeThreadUserInputFieldPart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? answerIndex = null,}) {
  return _then(BridgeThreadUserInputFieldPart_Answer(
answerIndex: null == answerIndex ? _self.answerIndex : answerIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeThreadUserInputFieldPart_OptionLabel extends BridgeThreadUserInputFieldPart {
  const BridgeThreadUserInputFieldPart_OptionLabel({required this.optionIndex}): super._();


 final  int optionIndex;

/// Create a copy of BridgeThreadUserInputFieldPart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadUserInputFieldPart_OptionLabelCopyWith<BridgeThreadUserInputFieldPart_OptionLabel> get copyWith => _$BridgeThreadUserInputFieldPart_OptionLabelCopyWithImpl<BridgeThreadUserInputFieldPart_OptionLabel>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadUserInputFieldPart_OptionLabel&&(identical(other.optionIndex, optionIndex) || other.optionIndex == optionIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,optionIndex);
}

@override
String toString() {
    return 'BridgeThreadUserInputFieldPart.optionLabel(optionIndex: $optionIndex)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadUserInputFieldPart_OptionLabelCopyWith<$Res> implements $BridgeThreadUserInputFieldPartCopyWith<$Res> {
  factory $BridgeThreadUserInputFieldPart_OptionLabelCopyWith(BridgeThreadUserInputFieldPart_OptionLabel value, $Res Function(BridgeThreadUserInputFieldPart_OptionLabel) _then) = _$BridgeThreadUserInputFieldPart_OptionLabelCopyWithImpl;
@useResult
$Res call({
 int optionIndex
});




}
/// @nodoc
class _$BridgeThreadUserInputFieldPart_OptionLabelCopyWithImpl<$Res>
    implements $BridgeThreadUserInputFieldPart_OptionLabelCopyWith<$Res> {
  _$BridgeThreadUserInputFieldPart_OptionLabelCopyWithImpl(this._self, this._then);

  final BridgeThreadUserInputFieldPart_OptionLabel _self;
  final $Res Function(BridgeThreadUserInputFieldPart_OptionLabel) _then;

/// Create a copy of BridgeThreadUserInputFieldPart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? optionIndex = null,}) {
  return _then(BridgeThreadUserInputFieldPart_OptionLabel(
optionIndex: null == optionIndex ? _self.optionIndex : optionIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeThreadUserInputFieldPart_OptionDescription extends BridgeThreadUserInputFieldPart {
  const BridgeThreadUserInputFieldPart_OptionDescription({required this.optionIndex}): super._();


 final  int optionIndex;

/// Create a copy of BridgeThreadUserInputFieldPart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeThreadUserInputFieldPart_OptionDescriptionCopyWith<BridgeThreadUserInputFieldPart_OptionDescription> get copyWith => _$BridgeThreadUserInputFieldPart_OptionDescriptionCopyWithImpl<BridgeThreadUserInputFieldPart_OptionDescription>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeThreadUserInputFieldPart_OptionDescription&&(identical(other.optionIndex, optionIndex) || other.optionIndex == optionIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,optionIndex);
}

@override
String toString() {
    return 'BridgeThreadUserInputFieldPart.optionDescription(optionIndex: $optionIndex)';
}


}

/// @nodoc
abstract mixin class $BridgeThreadUserInputFieldPart_OptionDescriptionCopyWith<$Res> implements $BridgeThreadUserInputFieldPartCopyWith<$Res> {
  factory $BridgeThreadUserInputFieldPart_OptionDescriptionCopyWith(BridgeThreadUserInputFieldPart_OptionDescription value, $Res Function(BridgeThreadUserInputFieldPart_OptionDescription) _then) = _$BridgeThreadUserInputFieldPart_OptionDescriptionCopyWithImpl;
@useResult
$Res call({
 int optionIndex
});




}
/// @nodoc
class _$BridgeThreadUserInputFieldPart_OptionDescriptionCopyWithImpl<$Res>
    implements $BridgeThreadUserInputFieldPart_OptionDescriptionCopyWith<$Res> {
  _$BridgeThreadUserInputFieldPart_OptionDescriptionCopyWithImpl(this._self, this._then);

  final BridgeThreadUserInputFieldPart_OptionDescription _self;
  final $Res Function(BridgeThreadUserInputFieldPart_OptionDescription) _then;

/// Create a copy of BridgeThreadUserInputFieldPart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? optionIndex = null,}) {
  return _then(BridgeThreadUserInputFieldPart_OptionDescription(
optionIndex: null == optionIndex ? _self.optionIndex : optionIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineChange {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineChange);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineChange()';
}


}

/// @nodoc
class $BridgeTimelineChangeCopyWith<$Res>  {
$BridgeTimelineChangeCopyWith(BridgeTimelineChange _, $Res Function(BridgeTimelineChange) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineChange].
extension BridgeTimelineChangePatterns on BridgeTimelineChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineChange_Add value)?  add,TResult Function( BridgeTimelineChange_UpdateItem value)?  updateItem,TResult Function( BridgeTimelineChange_Remove value)?  remove,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineChange_Add() when add != null:
return add(_that);case BridgeTimelineChange_UpdateItem() when updateItem != null:
return updateItem(_that);case BridgeTimelineChange_Remove() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineChange_Add value)  add,required TResult Function( BridgeTimelineChange_UpdateItem value)  updateItem,required TResult Function( BridgeTimelineChange_Remove value)  remove,}){
final _that = this;
switch (_that) {
case BridgeTimelineChange_Add():
return add(_that);case BridgeTimelineChange_UpdateItem():
return updateItem(_that);case BridgeTimelineChange_Remove():
return remove(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineChange_Add value)?  add,TResult? Function( BridgeTimelineChange_UpdateItem value)?  updateItem,TResult? Function( BridgeTimelineChange_Remove value)?  remove,}){
final _that = this;
switch (_that) {
case BridgeTimelineChange_Add() when add != null:
return add(_that);case BridgeTimelineChange_UpdateItem() when updateItem != null:
return updateItem(_that);case BridgeTimelineChange_Remove() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeTimelineItem item)?  add,TResult Function( String itemId,  BigInt expectedRevision,  BigInt revision,  BigInt omittedBytes,  bool saved,  BridgeTimelineLifecycle lifecycle,  BridgeThreadItem? itemShell,  List<BridgeTimelineFieldUpdate> fields)?  updateItem,TResult Function( String itemId)?  remove,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineChange_Add() when add != null:
return add(_that.item);case BridgeTimelineChange_UpdateItem() when updateItem != null:
return updateItem(_that.itemId,_that.expectedRevision,_that.revision,_that.omittedBytes,_that.saved,_that.lifecycle,_that.itemShell,_that.fields);case BridgeTimelineChange_Remove() when remove != null:
return remove(_that.itemId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeTimelineItem item)  add,required TResult Function( String itemId,  BigInt expectedRevision,  BigInt revision,  BigInt omittedBytes,  bool saved,  BridgeTimelineLifecycle lifecycle,  BridgeThreadItem? itemShell,  List<BridgeTimelineFieldUpdate> fields)  updateItem,required TResult Function( String itemId)  remove,}) {final _that = this;
switch (_that) {
case BridgeTimelineChange_Add():
return add(_that.item);case BridgeTimelineChange_UpdateItem():
return updateItem(_that.itemId,_that.expectedRevision,_that.revision,_that.omittedBytes,_that.saved,_that.lifecycle,_that.itemShell,_that.fields);case BridgeTimelineChange_Remove():
return remove(_that.itemId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineItem item)?  add,TResult? Function( String itemId,  BigInt expectedRevision,  BigInt revision,  BigInt omittedBytes,  bool saved,  BridgeTimelineLifecycle lifecycle,  BridgeThreadItem? itemShell,  List<BridgeTimelineFieldUpdate> fields)?  updateItem,TResult? Function( String itemId)?  remove,}) {final _that = this;
switch (_that) {
case BridgeTimelineChange_Add() when add != null:
return add(_that.item);case BridgeTimelineChange_UpdateItem() when updateItem != null:
return updateItem(_that.itemId,_that.expectedRevision,_that.revision,_that.omittedBytes,_that.saved,_that.lifecycle,_that.itemShell,_that.fields);case BridgeTimelineChange_Remove() when remove != null:
return remove(_that.itemId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineChange_Add extends BridgeTimelineChange {
  const BridgeTimelineChange_Add({required this.item}): super._();


 final  BridgeTimelineItem item;

/// Create a copy of BridgeTimelineChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineChange_AddCopyWith<BridgeTimelineChange_Add> get copyWith => _$BridgeTimelineChange_AddCopyWithImpl<BridgeTimelineChange_Add>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineChange_Add&&(identical(other.item, item) || other.item == item));
}


@override
int get hashCode {
    return Object.hash(runtimeType,item);
}

@override
String toString() {
    return 'BridgeTimelineChange.add(item: $item)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineChange_AddCopyWith<$Res> implements $BridgeTimelineChangeCopyWith<$Res> {
  factory $BridgeTimelineChange_AddCopyWith(BridgeTimelineChange_Add value, $Res Function(BridgeTimelineChange_Add) _then) = _$BridgeTimelineChange_AddCopyWithImpl;
@useResult
$Res call({
 BridgeTimelineItem item
});




}
/// @nodoc
class _$BridgeTimelineChange_AddCopyWithImpl<$Res>
    implements $BridgeTimelineChange_AddCopyWith<$Res> {
  _$BridgeTimelineChange_AddCopyWithImpl(this._self, this._then);

  final BridgeTimelineChange_Add _self;
  final $Res Function(BridgeTimelineChange_Add) _then;

/// Create a copy of BridgeTimelineChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? item = null,}) {
  return _then(BridgeTimelineChange_Add(
item: null == item ? _self.item : item // ignore: cast_nullable_to_non_nullable
as BridgeTimelineItem,
  ));
}


}

/// @nodoc


class BridgeTimelineChange_UpdateItem extends BridgeTimelineChange {
  const BridgeTimelineChange_UpdateItem({required this.itemId, required this.expectedRevision, required this.revision, required this.omittedBytes, required this.saved, required this.lifecycle, this.itemShell, required  List<BridgeTimelineFieldUpdate> fields}): _fields = fields,super._();


 final  String itemId;
 final  BigInt expectedRevision;
 final  BigInt revision;
/// 条目级省略量：全部字段完整长度与本次预览字节数之差的合计。
 final  BigInt omittedBytes;
 final  bool saved;
 final  BridgeTimelineLifecycle lifecycle;
 final  BridgeThreadItem? itemShell;
 final  List<BridgeTimelineFieldUpdate> _fields;
 List<BridgeTimelineFieldUpdate> get fields {
  if (_fields is EqualUnmodifiableListView) return _fields;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_fields);
}


/// Create a copy of BridgeTimelineChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineChange_UpdateItemCopyWith<BridgeTimelineChange_UpdateItem> get copyWith => _$BridgeTimelineChange_UpdateItemCopyWithImpl<BridgeTimelineChange_UpdateItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineChange_UpdateItem&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.omittedBytes, omittedBytes) || other.omittedBytes == omittedBytes)&&(identical(other.saved, saved) || other.saved == saved)&&(identical(other.lifecycle, lifecycle) || other.lifecycle == lifecycle)&&(identical(other.itemShell, itemShell) || other.itemShell == itemShell)&&const DeepCollectionEquality().equals(other.fields, _fields));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId,expectedRevision,revision,omittedBytes,saved,lifecycle,itemShell,const DeepCollectionEquality().hash(_fields));
}

@override
String toString() {
    return 'BridgeTimelineChange.updateItem(itemId: $itemId, expectedRevision: $expectedRevision, revision: $revision, omittedBytes: $omittedBytes, saved: $saved, lifecycle: $lifecycle, itemShell: $itemShell, fields: $fields)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineChange_UpdateItemCopyWith<$Res> implements $BridgeTimelineChangeCopyWith<$Res> {
  factory $BridgeTimelineChange_UpdateItemCopyWith(BridgeTimelineChange_UpdateItem value, $Res Function(BridgeTimelineChange_UpdateItem) _then) = _$BridgeTimelineChange_UpdateItemCopyWithImpl;
@useResult
$Res call({
 String itemId, BigInt expectedRevision, BigInt revision, BigInt omittedBytes, bool saved, BridgeTimelineLifecycle lifecycle, BridgeThreadItem? itemShell, List<BridgeTimelineFieldUpdate> fields
});




}
/// @nodoc
class _$BridgeTimelineChange_UpdateItemCopyWithImpl<$Res>
    implements $BridgeTimelineChange_UpdateItemCopyWith<$Res> {
  _$BridgeTimelineChange_UpdateItemCopyWithImpl(this._self, this._then);

  final BridgeTimelineChange_UpdateItem _self;
  final $Res Function(BridgeTimelineChange_UpdateItem) _then;

/// Create a copy of BridgeTimelineChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,Object? expectedRevision = null,Object? revision = null,Object? omittedBytes = null,Object? saved = null,Object? lifecycle = null,Object? itemShell = freezed,Object? fields = null,}) {
  return _then(BridgeTimelineChange_UpdateItem(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as BigInt,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as BigInt,omittedBytes: null == omittedBytes ? _self.omittedBytes : omittedBytes // ignore: cast_nullable_to_non_nullable
as BigInt,saved: null == saved ? _self.saved : saved // ignore: cast_nullable_to_non_nullable
as bool,lifecycle: null == lifecycle ? _self.lifecycle : lifecycle // ignore: cast_nullable_to_non_nullable
as BridgeTimelineLifecycle,itemShell: freezed == itemShell ? _self.itemShell : itemShell // ignore: cast_nullable_to_non_nullable
as BridgeThreadItem?,fields: null == fields ? _self._fields : fields // ignore: cast_nullable_to_non_nullable
as List<BridgeTimelineFieldUpdate>,
  ));
}


}

/// @nodoc


class BridgeTimelineChange_Remove extends BridgeTimelineChange {
  const BridgeTimelineChange_Remove({required this.itemId}): super._();


 final  String itemId;

/// Create a copy of BridgeTimelineChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineChange_RemoveCopyWith<BridgeTimelineChange_Remove> get copyWith => _$BridgeTimelineChange_RemoveCopyWithImpl<BridgeTimelineChange_Remove>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineChange_Remove&&(identical(other.itemId, itemId) || other.itemId == itemId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,itemId);
}

@override
String toString() {
    return 'BridgeTimelineChange.remove(itemId: $itemId)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineChange_RemoveCopyWith<$Res> implements $BridgeTimelineChangeCopyWith<$Res> {
  factory $BridgeTimelineChange_RemoveCopyWith(BridgeTimelineChange_Remove value, $Res Function(BridgeTimelineChange_Remove) _then) = _$BridgeTimelineChange_RemoveCopyWithImpl;
@useResult
$Res call({
 String itemId
});




}
/// @nodoc
class _$BridgeTimelineChange_RemoveCopyWithImpl<$Res>
    implements $BridgeTimelineChange_RemoveCopyWith<$Res> {
  _$BridgeTimelineChange_RemoveCopyWithImpl(this._self, this._then);

  final BridgeTimelineChange_Remove _self;
  final $Res Function(BridgeTimelineChange_Remove) _then;

/// Create a copy of BridgeTimelineChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? itemId = null,}) {
  return _then(BridgeTimelineChange_Remove(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeTimelineFieldChange {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineFieldChange);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineFieldChange()';
}


}

/// @nodoc
class $BridgeTimelineFieldChangeCopyWith<$Res>  {
$BridgeTimelineFieldChangeCopyWith(BridgeTimelineFieldChange _, $Res Function(BridgeTimelineFieldChange) __);
}


/// Adds pattern-matching-related methods to [BridgeTimelineFieldChange].
extension BridgeTimelineFieldChangePatterns on BridgeTimelineFieldChange {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineFieldChange_Unchanged value)?  unchanged,TResult Function( BridgeTimelineFieldChange_Append value)?  append,TResult Function( BridgeTimelineFieldChange_Replace value)?  replace,TResult Function( BridgeTimelineFieldChange_Remove value)?  remove,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineFieldChange_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeTimelineFieldChange_Append() when append != null:
return append(_that);case BridgeTimelineFieldChange_Replace() when replace != null:
return replace(_that);case BridgeTimelineFieldChange_Remove() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineFieldChange_Unchanged value)  unchanged,required TResult Function( BridgeTimelineFieldChange_Append value)  append,required TResult Function( BridgeTimelineFieldChange_Replace value)  replace,required TResult Function( BridgeTimelineFieldChange_Remove value)  remove,}){
final _that = this;
switch (_that) {
case BridgeTimelineFieldChange_Unchanged():
return unchanged(_that);case BridgeTimelineFieldChange_Append():
return append(_that);case BridgeTimelineFieldChange_Replace():
return replace(_that);case BridgeTimelineFieldChange_Remove():
return remove(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineFieldChange_Unchanged value)?  unchanged,TResult? Function( BridgeTimelineFieldChange_Append value)?  append,TResult? Function( BridgeTimelineFieldChange_Replace value)?  replace,TResult? Function( BridgeTimelineFieldChange_Remove value)?  remove,}){
final _that = this;
switch (_that) {
case BridgeTimelineFieldChange_Unchanged() when unchanged != null:
return unchanged(_that);case BridgeTimelineFieldChange_Append() when append != null:
return append(_that);case BridgeTimelineFieldChange_Replace() when replace != null:
return replace(_that);case BridgeTimelineFieldChange_Remove() when remove != null:
return remove(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchanged,TResult Function( String text)?  append,TResult Function( String text)?  replace,TResult Function()?  remove,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineFieldChange_Unchanged() when unchanged != null:
return unchanged();case BridgeTimelineFieldChange_Append() when append != null:
return append(_that.text);case BridgeTimelineFieldChange_Replace() when replace != null:
return replace(_that.text);case BridgeTimelineFieldChange_Remove() when remove != null:
return remove();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchanged,required TResult Function( String text)  append,required TResult Function( String text)  replace,required TResult Function()  remove,}) {final _that = this;
switch (_that) {
case BridgeTimelineFieldChange_Unchanged():
return unchanged();case BridgeTimelineFieldChange_Append():
return append(_that.text);case BridgeTimelineFieldChange_Replace():
return replace(_that.text);case BridgeTimelineFieldChange_Remove():
return remove();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchanged,TResult? Function( String text)?  append,TResult? Function( String text)?  replace,TResult? Function()?  remove,}) {final _that = this;
switch (_that) {
case BridgeTimelineFieldChange_Unchanged() when unchanged != null:
return unchanged();case BridgeTimelineFieldChange_Append() when append != null:
return append(_that.text);case BridgeTimelineFieldChange_Replace() when replace != null:
return replace(_that.text);case BridgeTimelineFieldChange_Remove() when remove != null:
return remove();case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineFieldChange_Unchanged extends BridgeTimelineFieldChange {
  const BridgeTimelineFieldChange_Unchanged(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineFieldChange_Unchanged);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineFieldChange.unchanged()';
}


}




/// @nodoc


class BridgeTimelineFieldChange_Append extends BridgeTimelineFieldChange {
  const BridgeTimelineFieldChange_Append({required this.text}): super._();


 final  String text;

/// Create a copy of BridgeTimelineFieldChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineFieldChange_AppendCopyWith<BridgeTimelineFieldChange_Append> get copyWith => _$BridgeTimelineFieldChange_AppendCopyWithImpl<BridgeTimelineFieldChange_Append>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineFieldChange_Append&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'BridgeTimelineFieldChange.append(text: $text)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineFieldChange_AppendCopyWith<$Res> implements $BridgeTimelineFieldChangeCopyWith<$Res> {
  factory $BridgeTimelineFieldChange_AppendCopyWith(BridgeTimelineFieldChange_Append value, $Res Function(BridgeTimelineFieldChange_Append) _then) = _$BridgeTimelineFieldChange_AppendCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$BridgeTimelineFieldChange_AppendCopyWithImpl<$Res>
    implements $BridgeTimelineFieldChange_AppendCopyWith<$Res> {
  _$BridgeTimelineFieldChange_AppendCopyWithImpl(this._self, this._then);

  final BridgeTimelineFieldChange_Append _self;
  final $Res Function(BridgeTimelineFieldChange_Append) _then;

/// Create a copy of BridgeTimelineFieldChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(BridgeTimelineFieldChange_Append(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineFieldChange_Replace extends BridgeTimelineFieldChange {
  const BridgeTimelineFieldChange_Replace({required this.text}): super._();


 final  String text;

/// Create a copy of BridgeTimelineFieldChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineFieldChange_ReplaceCopyWith<BridgeTimelineFieldChange_Replace> get copyWith => _$BridgeTimelineFieldChange_ReplaceCopyWithImpl<BridgeTimelineFieldChange_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineFieldChange_Replace&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'BridgeTimelineFieldChange.replace(text: $text)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineFieldChange_ReplaceCopyWith<$Res> implements $BridgeTimelineFieldChangeCopyWith<$Res> {
  factory $BridgeTimelineFieldChange_ReplaceCopyWith(BridgeTimelineFieldChange_Replace value, $Res Function(BridgeTimelineFieldChange_Replace) _then) = _$BridgeTimelineFieldChange_ReplaceCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$BridgeTimelineFieldChange_ReplaceCopyWithImpl<$Res>
    implements $BridgeTimelineFieldChange_ReplaceCopyWith<$Res> {
  _$BridgeTimelineFieldChange_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeTimelineFieldChange_Replace _self;
  final $Res Function(BridgeTimelineFieldChange_Replace) _then;

/// Create a copy of BridgeTimelineFieldChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(BridgeTimelineFieldChange_Replace(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeTimelineFieldChange_Remove extends BridgeTimelineFieldChange {
  const BridgeTimelineFieldChange_Remove(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineFieldChange_Remove);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeTimelineFieldChange.remove()';
}


}




/// @nodoc
mixin _$BridgeTimelineUpdate {

 String get subscriptionId;
/// Create a copy of BridgeTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineUpdateCopyWith<BridgeTimelineUpdate> get copyWith => _$BridgeTimelineUpdateCopyWithImpl<BridgeTimelineUpdate>(this as BridgeTimelineUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeTimelineUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUpdate&&(identical(other.subscriptionId, _this.subscriptionId) || other.subscriptionId == _this.subscriptionId));
}


@override
int get hashCode {
  final _this = this as BridgeTimelineUpdate;
  return Object.hash(runtimeType,_this.subscriptionId);
}

@override
String toString() {
  final _this = this as BridgeTimelineUpdate;
  return 'BridgeTimelineUpdate(subscriptionId: ${_this.subscriptionId})';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineUpdateCopyWith<$Res>  {
  factory $BridgeTimelineUpdateCopyWith(BridgeTimelineUpdate value, $Res Function(BridgeTimelineUpdate) _then) = _$BridgeTimelineUpdateCopyWithImpl;
@useResult
$Res call({
 String subscriptionId
});




}
/// @nodoc
class _$BridgeTimelineUpdateCopyWithImpl<$Res>
    implements $BridgeTimelineUpdateCopyWith<$Res> {
  _$BridgeTimelineUpdateCopyWithImpl(this._self, this._then);

  final BridgeTimelineUpdate _self;
  final $Res Function(BridgeTimelineUpdate) _then;

/// Create a copy of BridgeTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? subscriptionId = null,}) {
  return _then(_self.copyWith(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeTimelineUpdate].
extension BridgeTimelineUpdatePatterns on BridgeTimelineUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeTimelineUpdate_Patch value)?  patch,TResult Function( BridgeTimelineUpdate_Resync value)?  resync,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeTimelineUpdate_Patch() when patch != null:
return patch(_that);case BridgeTimelineUpdate_Resync() when resync != null:
return resync(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeTimelineUpdate_Patch value)  patch,required TResult Function( BridgeTimelineUpdate_Resync value)  resync,}){
final _that = this;
switch (_that) {
case BridgeTimelineUpdate_Patch():
return patch(_that);case BridgeTimelineUpdate_Resync():
return resync(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeTimelineUpdate_Patch value)?  patch,TResult? Function( BridgeTimelineUpdate_Resync value)?  resync,}){
final _that = this;
switch (_that) {
case BridgeTimelineUpdate_Patch() when patch != null:
return patch(_that);case BridgeTimelineUpdate_Resync() when resync != null:
return resync(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String subscriptionId,  BigInt from,  BigInt to,  List<BridgeTimelineChange> changes,  BridgeTimelinePriority priority)?  patch,TResult Function( String subscriptionId,  BridgeTimelineResyncReason reason,  BridgeTimelineBaseline baseline)?  resync,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeTimelineUpdate_Patch() when patch != null:
return patch(_that.subscriptionId,_that.from,_that.to,_that.changes,_that.priority);case BridgeTimelineUpdate_Resync() when resync != null:
return resync(_that.subscriptionId,_that.reason,_that.baseline);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String subscriptionId,  BigInt from,  BigInt to,  List<BridgeTimelineChange> changes,  BridgeTimelinePriority priority)  patch,required TResult Function( String subscriptionId,  BridgeTimelineResyncReason reason,  BridgeTimelineBaseline baseline)  resync,}) {final _that = this;
switch (_that) {
case BridgeTimelineUpdate_Patch():
return patch(_that.subscriptionId,_that.from,_that.to,_that.changes,_that.priority);case BridgeTimelineUpdate_Resync():
return resync(_that.subscriptionId,_that.reason,_that.baseline);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String subscriptionId,  BigInt from,  BigInt to,  List<BridgeTimelineChange> changes,  BridgeTimelinePriority priority)?  patch,TResult? Function( String subscriptionId,  BridgeTimelineResyncReason reason,  BridgeTimelineBaseline baseline)?  resync,}) {final _that = this;
switch (_that) {
case BridgeTimelineUpdate_Patch() when patch != null:
return patch(_that.subscriptionId,_that.from,_that.to,_that.changes,_that.priority);case BridgeTimelineUpdate_Resync() when resync != null:
return resync(_that.subscriptionId,_that.reason,_that.baseline);case _:
  return null;

}
}

}

/// @nodoc


class BridgeTimelineUpdate_Patch extends BridgeTimelineUpdate {
  const BridgeTimelineUpdate_Patch({required this.subscriptionId, required this.from, required this.to, required  List<BridgeTimelineChange> changes, required this.priority}): _changes = changes,super._();


@override final  String subscriptionId;
 final  BigInt from;
 final  BigInt to;
 final  List<BridgeTimelineChange> _changes;
 List<BridgeTimelineChange> get changes {
  if (_changes is EqualUnmodifiableListView) return _changes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_changes);
}

 final  BridgeTimelinePriority priority;

/// Create a copy of BridgeTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineUpdate_PatchCopyWith<BridgeTimelineUpdate_Patch> get copyWith => _$BridgeTimelineUpdate_PatchCopyWithImpl<BridgeTimelineUpdate_Patch>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUpdate_Patch&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId)&&(identical(other.from, from) || other.from == from)&&(identical(other.to, to) || other.to == to)&&const DeepCollectionEquality().equals(other.changes, _changes)&&(identical(other.priority, priority) || other.priority == priority));
}


@override
int get hashCode {
    return Object.hash(runtimeType,subscriptionId,from,to,const DeepCollectionEquality().hash(_changes),priority);
}

@override
String toString() {
    return 'BridgeTimelineUpdate.patch(subscriptionId: $subscriptionId, from: $from, to: $to, changes: $changes, priority: $priority)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineUpdate_PatchCopyWith<$Res> implements $BridgeTimelineUpdateCopyWith<$Res> {
  factory $BridgeTimelineUpdate_PatchCopyWith(BridgeTimelineUpdate_Patch value, $Res Function(BridgeTimelineUpdate_Patch) _then) = _$BridgeTimelineUpdate_PatchCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId, BigInt from, BigInt to, List<BridgeTimelineChange> changes, BridgeTimelinePriority priority
});




}
/// @nodoc
class _$BridgeTimelineUpdate_PatchCopyWithImpl<$Res>
    implements $BridgeTimelineUpdate_PatchCopyWith<$Res> {
  _$BridgeTimelineUpdate_PatchCopyWithImpl(this._self, this._then);

  final BridgeTimelineUpdate_Patch _self;
  final $Res Function(BridgeTimelineUpdate_Patch) _then;

/// Create a copy of BridgeTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,Object? from = null,Object? to = null,Object? changes = null,Object? priority = null,}) {
  return _then(BridgeTimelineUpdate_Patch(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,from: null == from ? _self.from : from // ignore: cast_nullable_to_non_nullable
as BigInt,to: null == to ? _self.to : to // ignore: cast_nullable_to_non_nullable
as BigInt,changes: null == changes ? _self._changes : changes // ignore: cast_nullable_to_non_nullable
as List<BridgeTimelineChange>,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as BridgeTimelinePriority,
  ));
}


}

/// @nodoc


class BridgeTimelineUpdate_Resync extends BridgeTimelineUpdate {
  const BridgeTimelineUpdate_Resync({required this.subscriptionId, required this.reason, required this.baseline}): super._();


@override final  String subscriptionId;
 final  BridgeTimelineResyncReason reason;
 final  BridgeTimelineBaseline baseline;

/// Create a copy of BridgeTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeTimelineUpdate_ResyncCopyWith<BridgeTimelineUpdate_Resync> get copyWith => _$BridgeTimelineUpdate_ResyncCopyWithImpl<BridgeTimelineUpdate_Resync>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeTimelineUpdate_Resync&&(identical(other.subscriptionId, subscriptionId) || other.subscriptionId == subscriptionId)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.baseline, baseline) || other.baseline == baseline));
}


@override
int get hashCode {
    return Object.hash(runtimeType,subscriptionId,reason,baseline);
}

@override
String toString() {
    return 'BridgeTimelineUpdate.resync(subscriptionId: $subscriptionId, reason: $reason, baseline: $baseline)';
}


}

/// @nodoc
abstract mixin class $BridgeTimelineUpdate_ResyncCopyWith<$Res> implements $BridgeTimelineUpdateCopyWith<$Res> {
  factory $BridgeTimelineUpdate_ResyncCopyWith(BridgeTimelineUpdate_Resync value, $Res Function(BridgeTimelineUpdate_Resync) _then) = _$BridgeTimelineUpdate_ResyncCopyWithImpl;
@override @useResult
$Res call({
 String subscriptionId, BridgeTimelineResyncReason reason, BridgeTimelineBaseline baseline
});




}
/// @nodoc
class _$BridgeTimelineUpdate_ResyncCopyWithImpl<$Res>
    implements $BridgeTimelineUpdate_ResyncCopyWith<$Res> {
  _$BridgeTimelineUpdate_ResyncCopyWithImpl(this._self, this._then);

  final BridgeTimelineUpdate_Resync _self;
  final $Res Function(BridgeTimelineUpdate_Resync) _then;

/// Create a copy of BridgeTimelineUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? subscriptionId = null,Object? reason = null,Object? baseline = null,}) {
  return _then(BridgeTimelineUpdate_Resync(
subscriptionId: null == subscriptionId ? _self.subscriptionId : subscriptionId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeTimelineResyncReason,baseline: null == baseline ? _self.baseline : baseline // ignore: cast_nullable_to_non_nullable
as BridgeTimelineBaseline,
  ));
}


}

// dart format on
