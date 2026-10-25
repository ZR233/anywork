// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_content_fields.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadContentFieldView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContentFieldView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadContentFieldViewCopyWith<$Res>  {
$ThreadContentFieldViewCopyWith(ThreadContentFieldView _, $Res Function(ThreadContentFieldView) __);
}


/// Adds pattern-matching-related methods to [ThreadContentFieldView].
extension ThreadContentFieldViewPatterns on ThreadContentFieldView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadTextFieldView value)?  text,TResult Function( ThreadThinkingSummaryFieldView value)?  thinkingSummary,TResult Function( ThreadThinkingContentFieldView value)?  thinkingContent,TResult Function( ThreadToolArgumentsFieldView value)?  toolArguments,TResult Function( ThreadToolResultFieldView value)?  toolResult,TResult Function( ThreadToolOutputArtifactsFieldView value)?  toolOutputArtifacts,TResult Function( ThreadRawPayloadFieldView value)?  rawPayload,TResult Function( ThreadToolUserInputFieldView value)?  toolUserInput,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadTextFieldView() when text != null:
return text(_that);case ThreadThinkingSummaryFieldView() when thinkingSummary != null:
return thinkingSummary(_that);case ThreadThinkingContentFieldView() when thinkingContent != null:
return thinkingContent(_that);case ThreadToolArgumentsFieldView() when toolArguments != null:
return toolArguments(_that);case ThreadToolResultFieldView() when toolResult != null:
return toolResult(_that);case ThreadToolOutputArtifactsFieldView() when toolOutputArtifacts != null:
return toolOutputArtifacts(_that);case ThreadRawPayloadFieldView() when rawPayload != null:
return rawPayload(_that);case ThreadToolUserInputFieldView() when toolUserInput != null:
return toolUserInput(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadTextFieldView value)  text,required TResult Function( ThreadThinkingSummaryFieldView value)  thinkingSummary,required TResult Function( ThreadThinkingContentFieldView value)  thinkingContent,required TResult Function( ThreadToolArgumentsFieldView value)  toolArguments,required TResult Function( ThreadToolResultFieldView value)  toolResult,required TResult Function( ThreadToolOutputArtifactsFieldView value)  toolOutputArtifacts,required TResult Function( ThreadRawPayloadFieldView value)  rawPayload,required TResult Function( ThreadToolUserInputFieldView value)  toolUserInput,}){
final _that = this;
switch (_that) {
case ThreadTextFieldView():
return text(_that);case ThreadThinkingSummaryFieldView():
return thinkingSummary(_that);case ThreadThinkingContentFieldView():
return thinkingContent(_that);case ThreadToolArgumentsFieldView():
return toolArguments(_that);case ThreadToolResultFieldView():
return toolResult(_that);case ThreadToolOutputArtifactsFieldView():
return toolOutputArtifacts(_that);case ThreadRawPayloadFieldView():
return rawPayload(_that);case ThreadToolUserInputFieldView():
return toolUserInput(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadTextFieldView value)?  text,TResult? Function( ThreadThinkingSummaryFieldView value)?  thinkingSummary,TResult? Function( ThreadThinkingContentFieldView value)?  thinkingContent,TResult? Function( ThreadToolArgumentsFieldView value)?  toolArguments,TResult? Function( ThreadToolResultFieldView value)?  toolResult,TResult? Function( ThreadToolOutputArtifactsFieldView value)?  toolOutputArtifacts,TResult? Function( ThreadRawPayloadFieldView value)?  rawPayload,TResult? Function( ThreadToolUserInputFieldView value)?  toolUserInput,}){
final _that = this;
switch (_that) {
case ThreadTextFieldView() when text != null:
return text(_that);case ThreadThinkingSummaryFieldView() when thinkingSummary != null:
return thinkingSummary(_that);case ThreadThinkingContentFieldView() when thinkingContent != null:
return thinkingContent(_that);case ThreadToolArgumentsFieldView() when toolArguments != null:
return toolArguments(_that);case ThreadToolResultFieldView() when toolResult != null:
return toolResult(_that);case ThreadToolOutputArtifactsFieldView() when toolOutputArtifacts != null:
return toolOutputArtifacts(_that);case ThreadRawPayloadFieldView() when rawPayload != null:
return rawPayload(_that);case ThreadToolUserInputFieldView() when toolUserInput != null:
return toolUserInput(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  text,TResult Function( int chunkIndex)?  thinkingSummary,TResult Function( int chunkIndex)?  thinkingContent,TResult Function()?  toolArguments,TResult Function()?  toolResult,TResult Function()?  toolOutputArtifacts,TResult Function( int payloadIndex)?  rawPayload,TResult Function( int questionIndex,  ThreadUserInputFieldPartView part)?  toolUserInput,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadTextFieldView() when text != null:
return text();case ThreadThinkingSummaryFieldView() when thinkingSummary != null:
return thinkingSummary(_that.chunkIndex);case ThreadThinkingContentFieldView() when thinkingContent != null:
return thinkingContent(_that.chunkIndex);case ThreadToolArgumentsFieldView() when toolArguments != null:
return toolArguments();case ThreadToolResultFieldView() when toolResult != null:
return toolResult();case ThreadToolOutputArtifactsFieldView() when toolOutputArtifacts != null:
return toolOutputArtifacts();case ThreadRawPayloadFieldView() when rawPayload != null:
return rawPayload(_that.payloadIndex);case ThreadToolUserInputFieldView() when toolUserInput != null:
return toolUserInput(_that.questionIndex,_that.part);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  text,required TResult Function( int chunkIndex)  thinkingSummary,required TResult Function( int chunkIndex)  thinkingContent,required TResult Function()  toolArguments,required TResult Function()  toolResult,required TResult Function()  toolOutputArtifacts,required TResult Function( int payloadIndex)  rawPayload,required TResult Function( int questionIndex,  ThreadUserInputFieldPartView part)  toolUserInput,}) {final _that = this;
switch (_that) {
case ThreadTextFieldView():
return text();case ThreadThinkingSummaryFieldView():
return thinkingSummary(_that.chunkIndex);case ThreadThinkingContentFieldView():
return thinkingContent(_that.chunkIndex);case ThreadToolArgumentsFieldView():
return toolArguments();case ThreadToolResultFieldView():
return toolResult();case ThreadToolOutputArtifactsFieldView():
return toolOutputArtifacts();case ThreadRawPayloadFieldView():
return rawPayload(_that.payloadIndex);case ThreadToolUserInputFieldView():
return toolUserInput(_that.questionIndex,_that.part);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  text,TResult? Function( int chunkIndex)?  thinkingSummary,TResult? Function( int chunkIndex)?  thinkingContent,TResult? Function()?  toolArguments,TResult? Function()?  toolResult,TResult? Function()?  toolOutputArtifacts,TResult? Function( int payloadIndex)?  rawPayload,TResult? Function( int questionIndex,  ThreadUserInputFieldPartView part)?  toolUserInput,}) {final _that = this;
switch (_that) {
case ThreadTextFieldView() when text != null:
return text();case ThreadThinkingSummaryFieldView() when thinkingSummary != null:
return thinkingSummary(_that.chunkIndex);case ThreadThinkingContentFieldView() when thinkingContent != null:
return thinkingContent(_that.chunkIndex);case ThreadToolArgumentsFieldView() when toolArguments != null:
return toolArguments();case ThreadToolResultFieldView() when toolResult != null:
return toolResult();case ThreadToolOutputArtifactsFieldView() when toolOutputArtifacts != null:
return toolOutputArtifacts();case ThreadRawPayloadFieldView() when rawPayload != null:
return rawPayload(_that.payloadIndex);case ThreadToolUserInputFieldView() when toolUserInput != null:
return toolUserInput(_that.questionIndex,_that.part);case _:
  return null;

}
}

}

/// @nodoc


class ThreadTextFieldView implements ThreadContentFieldView {
  const ThreadTextFieldView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadTextFieldView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ThreadThinkingSummaryFieldView implements ThreadContentFieldView {
  const ThreadThinkingSummaryFieldView(this.chunkIndex);


 final  int chunkIndex;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadThinkingSummaryFieldViewCopyWith<ThreadThinkingSummaryFieldView> get copyWith => _$ThreadThinkingSummaryFieldViewCopyWithImpl<ThreadThinkingSummaryFieldView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadThinkingSummaryFieldView&&(identical(other.chunkIndex, chunkIndex) || other.chunkIndex == chunkIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chunkIndex);
}



}

/// @nodoc
abstract mixin class $ThreadThinkingSummaryFieldViewCopyWith<$Res> implements $ThreadContentFieldViewCopyWith<$Res> {
  factory $ThreadThinkingSummaryFieldViewCopyWith(ThreadThinkingSummaryFieldView value, $Res Function(ThreadThinkingSummaryFieldView) _then) = _$ThreadThinkingSummaryFieldViewCopyWithImpl;
@useResult
$Res call({
 int chunkIndex
});




}
/// @nodoc
class _$ThreadThinkingSummaryFieldViewCopyWithImpl<$Res>
    implements $ThreadThinkingSummaryFieldViewCopyWith<$Res> {
  _$ThreadThinkingSummaryFieldViewCopyWithImpl(this._self, this._then);

  final ThreadThinkingSummaryFieldView _self;
  final $Res Function(ThreadThinkingSummaryFieldView) _then;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? chunkIndex = null,}) {
  return _then(ThreadThinkingSummaryFieldView(
null == chunkIndex ? _self.chunkIndex : chunkIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ThreadThinkingContentFieldView implements ThreadContentFieldView {
  const ThreadThinkingContentFieldView(this.chunkIndex);


 final  int chunkIndex;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadThinkingContentFieldViewCopyWith<ThreadThinkingContentFieldView> get copyWith => _$ThreadThinkingContentFieldViewCopyWithImpl<ThreadThinkingContentFieldView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadThinkingContentFieldView&&(identical(other.chunkIndex, chunkIndex) || other.chunkIndex == chunkIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,chunkIndex);
}



}

/// @nodoc
abstract mixin class $ThreadThinkingContentFieldViewCopyWith<$Res> implements $ThreadContentFieldViewCopyWith<$Res> {
  factory $ThreadThinkingContentFieldViewCopyWith(ThreadThinkingContentFieldView value, $Res Function(ThreadThinkingContentFieldView) _then) = _$ThreadThinkingContentFieldViewCopyWithImpl;
@useResult
$Res call({
 int chunkIndex
});




}
/// @nodoc
class _$ThreadThinkingContentFieldViewCopyWithImpl<$Res>
    implements $ThreadThinkingContentFieldViewCopyWith<$Res> {
  _$ThreadThinkingContentFieldViewCopyWithImpl(this._self, this._then);

  final ThreadThinkingContentFieldView _self;
  final $Res Function(ThreadThinkingContentFieldView) _then;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? chunkIndex = null,}) {
  return _then(ThreadThinkingContentFieldView(
null == chunkIndex ? _self.chunkIndex : chunkIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ThreadToolArgumentsFieldView implements ThreadContentFieldView {
  const ThreadToolArgumentsFieldView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolArgumentsFieldView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ThreadToolResultFieldView implements ThreadContentFieldView {
  const ThreadToolResultFieldView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolResultFieldView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ThreadToolOutputArtifactsFieldView implements ThreadContentFieldView {
  const ThreadToolOutputArtifactsFieldView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolOutputArtifactsFieldView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ThreadRawPayloadFieldView implements ThreadContentFieldView {
  const ThreadRawPayloadFieldView(this.payloadIndex);


 final  int payloadIndex;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadRawPayloadFieldViewCopyWith<ThreadRawPayloadFieldView> get copyWith => _$ThreadRawPayloadFieldViewCopyWithImpl<ThreadRawPayloadFieldView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadRawPayloadFieldView&&(identical(other.payloadIndex, payloadIndex) || other.payloadIndex == payloadIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,payloadIndex);
}



}

/// @nodoc
abstract mixin class $ThreadRawPayloadFieldViewCopyWith<$Res> implements $ThreadContentFieldViewCopyWith<$Res> {
  factory $ThreadRawPayloadFieldViewCopyWith(ThreadRawPayloadFieldView value, $Res Function(ThreadRawPayloadFieldView) _then) = _$ThreadRawPayloadFieldViewCopyWithImpl;
@useResult
$Res call({
 int payloadIndex
});




}
/// @nodoc
class _$ThreadRawPayloadFieldViewCopyWithImpl<$Res>
    implements $ThreadRawPayloadFieldViewCopyWith<$Res> {
  _$ThreadRawPayloadFieldViewCopyWithImpl(this._self, this._then);

  final ThreadRawPayloadFieldView _self;
  final $Res Function(ThreadRawPayloadFieldView) _then;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? payloadIndex = null,}) {
  return _then(ThreadRawPayloadFieldView(
null == payloadIndex ? _self.payloadIndex : payloadIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ThreadToolUserInputFieldView implements ThreadContentFieldView {
  const ThreadToolUserInputFieldView({required this.questionIndex, required this.part});


 final  int questionIndex;
 final  ThreadUserInputFieldPartView part;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadToolUserInputFieldViewCopyWith<ThreadToolUserInputFieldView> get copyWith => _$ThreadToolUserInputFieldViewCopyWithImpl<ThreadToolUserInputFieldView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolUserInputFieldView&&(identical(other.questionIndex, questionIndex) || other.questionIndex == questionIndex)&&(identical(other.part, part) || other.part == part));
}


@override
int get hashCode {
    return Object.hash(runtimeType,questionIndex,part);
}



}

/// @nodoc
abstract mixin class $ThreadToolUserInputFieldViewCopyWith<$Res> implements $ThreadContentFieldViewCopyWith<$Res> {
  factory $ThreadToolUserInputFieldViewCopyWith(ThreadToolUserInputFieldView value, $Res Function(ThreadToolUserInputFieldView) _then) = _$ThreadToolUserInputFieldViewCopyWithImpl;
@useResult
$Res call({
 int questionIndex, ThreadUserInputFieldPartView part
});


$ThreadUserInputFieldPartViewCopyWith<$Res> get part;

}
/// @nodoc
class _$ThreadToolUserInputFieldViewCopyWithImpl<$Res>
    implements $ThreadToolUserInputFieldViewCopyWith<$Res> {
  _$ThreadToolUserInputFieldViewCopyWithImpl(this._self, this._then);

  final ThreadToolUserInputFieldView _self;
  final $Res Function(ThreadToolUserInputFieldView) _then;

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? questionIndex = null,Object? part = null,}) {
  return _then(ThreadToolUserInputFieldView(
questionIndex: null == questionIndex ? _self.questionIndex : questionIndex // ignore: cast_nullable_to_non_nullable
as int,part: null == part ? _self.part : part // ignore: cast_nullable_to_non_nullable
as ThreadUserInputFieldPartView,
  ));
}

/// Create a copy of ThreadContentFieldView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadUserInputFieldPartViewCopyWith<$Res> get part {

  return $ThreadUserInputFieldPartViewCopyWith<$Res>(_self.part, (value) {
    return _then(_self.copyWith(part: value));
  });
}
}

/// @nodoc
mixin _$ThreadUserInputFieldPartView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadUserInputFieldPartView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadUserInputFieldPartViewCopyWith<$Res>  {
$ThreadUserInputFieldPartViewCopyWith(ThreadUserInputFieldPartView _, $Res Function(ThreadUserInputFieldPartView) __);
}


/// Adds pattern-matching-related methods to [ThreadUserInputFieldPartView].
extension ThreadUserInputFieldPartViewPatterns on ThreadUserInputFieldPartView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadUserInputHeaderFieldPartView value)?  header,TResult Function( ThreadUserInputQuestionFieldPartView value)?  question,TResult Function( ThreadUserInputAnswerFieldPartView value)?  answer,TResult Function( ThreadUserInputOptionLabelFieldPartView value)?  optionLabel,TResult Function( ThreadUserInputOptionDescriptionFieldPartView value)?  optionDescription,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadUserInputHeaderFieldPartView() when header != null:
return header(_that);case ThreadUserInputQuestionFieldPartView() when question != null:
return question(_that);case ThreadUserInputAnswerFieldPartView() when answer != null:
return answer(_that);case ThreadUserInputOptionLabelFieldPartView() when optionLabel != null:
return optionLabel(_that);case ThreadUserInputOptionDescriptionFieldPartView() when optionDescription != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadUserInputHeaderFieldPartView value)  header,required TResult Function( ThreadUserInputQuestionFieldPartView value)  question,required TResult Function( ThreadUserInputAnswerFieldPartView value)  answer,required TResult Function( ThreadUserInputOptionLabelFieldPartView value)  optionLabel,required TResult Function( ThreadUserInputOptionDescriptionFieldPartView value)  optionDescription,}){
final _that = this;
switch (_that) {
case ThreadUserInputHeaderFieldPartView():
return header(_that);case ThreadUserInputQuestionFieldPartView():
return question(_that);case ThreadUserInputAnswerFieldPartView():
return answer(_that);case ThreadUserInputOptionLabelFieldPartView():
return optionLabel(_that);case ThreadUserInputOptionDescriptionFieldPartView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadUserInputHeaderFieldPartView value)?  header,TResult? Function( ThreadUserInputQuestionFieldPartView value)?  question,TResult? Function( ThreadUserInputAnswerFieldPartView value)?  answer,TResult? Function( ThreadUserInputOptionLabelFieldPartView value)?  optionLabel,TResult? Function( ThreadUserInputOptionDescriptionFieldPartView value)?  optionDescription,}){
final _that = this;
switch (_that) {
case ThreadUserInputHeaderFieldPartView() when header != null:
return header(_that);case ThreadUserInputQuestionFieldPartView() when question != null:
return question(_that);case ThreadUserInputAnswerFieldPartView() when answer != null:
return answer(_that);case ThreadUserInputOptionLabelFieldPartView() when optionLabel != null:
return optionLabel(_that);case ThreadUserInputOptionDescriptionFieldPartView() when optionDescription != null:
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
case ThreadUserInputHeaderFieldPartView() when header != null:
return header();case ThreadUserInputQuestionFieldPartView() when question != null:
return question();case ThreadUserInputAnswerFieldPartView() when answer != null:
return answer(_that.answerIndex);case ThreadUserInputOptionLabelFieldPartView() when optionLabel != null:
return optionLabel(_that.optionIndex);case ThreadUserInputOptionDescriptionFieldPartView() when optionDescription != null:
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
case ThreadUserInputHeaderFieldPartView():
return header();case ThreadUserInputQuestionFieldPartView():
return question();case ThreadUserInputAnswerFieldPartView():
return answer(_that.answerIndex);case ThreadUserInputOptionLabelFieldPartView():
return optionLabel(_that.optionIndex);case ThreadUserInputOptionDescriptionFieldPartView():
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
case ThreadUserInputHeaderFieldPartView() when header != null:
return header();case ThreadUserInputQuestionFieldPartView() when question != null:
return question();case ThreadUserInputAnswerFieldPartView() when answer != null:
return answer(_that.answerIndex);case ThreadUserInputOptionLabelFieldPartView() when optionLabel != null:
return optionLabel(_that.optionIndex);case ThreadUserInputOptionDescriptionFieldPartView() when optionDescription != null:
return optionDescription(_that.optionIndex);case _:
  return null;

}
}

}

/// @nodoc


class ThreadUserInputHeaderFieldPartView implements ThreadUserInputFieldPartView {
  const ThreadUserInputHeaderFieldPartView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadUserInputHeaderFieldPartView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ThreadUserInputQuestionFieldPartView implements ThreadUserInputFieldPartView {
  const ThreadUserInputQuestionFieldPartView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadUserInputQuestionFieldPartView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ThreadUserInputAnswerFieldPartView implements ThreadUserInputFieldPartView {
  const ThreadUserInputAnswerFieldPartView(this.answerIndex);


 final  int answerIndex;

/// Create a copy of ThreadUserInputFieldPartView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadUserInputAnswerFieldPartViewCopyWith<ThreadUserInputAnswerFieldPartView> get copyWith => _$ThreadUserInputAnswerFieldPartViewCopyWithImpl<ThreadUserInputAnswerFieldPartView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadUserInputAnswerFieldPartView&&(identical(other.answerIndex, answerIndex) || other.answerIndex == answerIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,answerIndex);
}



}

/// @nodoc
abstract mixin class $ThreadUserInputAnswerFieldPartViewCopyWith<$Res> implements $ThreadUserInputFieldPartViewCopyWith<$Res> {
  factory $ThreadUserInputAnswerFieldPartViewCopyWith(ThreadUserInputAnswerFieldPartView value, $Res Function(ThreadUserInputAnswerFieldPartView) _then) = _$ThreadUserInputAnswerFieldPartViewCopyWithImpl;
@useResult
$Res call({
 int answerIndex
});




}
/// @nodoc
class _$ThreadUserInputAnswerFieldPartViewCopyWithImpl<$Res>
    implements $ThreadUserInputAnswerFieldPartViewCopyWith<$Res> {
  _$ThreadUserInputAnswerFieldPartViewCopyWithImpl(this._self, this._then);

  final ThreadUserInputAnswerFieldPartView _self;
  final $Res Function(ThreadUserInputAnswerFieldPartView) _then;

/// Create a copy of ThreadUserInputFieldPartView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? answerIndex = null,}) {
  return _then(ThreadUserInputAnswerFieldPartView(
null == answerIndex ? _self.answerIndex : answerIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ThreadUserInputOptionLabelFieldPartView implements ThreadUserInputFieldPartView {
  const ThreadUserInputOptionLabelFieldPartView(this.optionIndex);


 final  int optionIndex;

/// Create a copy of ThreadUserInputFieldPartView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadUserInputOptionLabelFieldPartViewCopyWith<ThreadUserInputOptionLabelFieldPartView> get copyWith => _$ThreadUserInputOptionLabelFieldPartViewCopyWithImpl<ThreadUserInputOptionLabelFieldPartView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadUserInputOptionLabelFieldPartView&&(identical(other.optionIndex, optionIndex) || other.optionIndex == optionIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,optionIndex);
}



}

/// @nodoc
abstract mixin class $ThreadUserInputOptionLabelFieldPartViewCopyWith<$Res> implements $ThreadUserInputFieldPartViewCopyWith<$Res> {
  factory $ThreadUserInputOptionLabelFieldPartViewCopyWith(ThreadUserInputOptionLabelFieldPartView value, $Res Function(ThreadUserInputOptionLabelFieldPartView) _then) = _$ThreadUserInputOptionLabelFieldPartViewCopyWithImpl;
@useResult
$Res call({
 int optionIndex
});




}
/// @nodoc
class _$ThreadUserInputOptionLabelFieldPartViewCopyWithImpl<$Res>
    implements $ThreadUserInputOptionLabelFieldPartViewCopyWith<$Res> {
  _$ThreadUserInputOptionLabelFieldPartViewCopyWithImpl(this._self, this._then);

  final ThreadUserInputOptionLabelFieldPartView _self;
  final $Res Function(ThreadUserInputOptionLabelFieldPartView) _then;

/// Create a copy of ThreadUserInputFieldPartView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? optionIndex = null,}) {
  return _then(ThreadUserInputOptionLabelFieldPartView(
null == optionIndex ? _self.optionIndex : optionIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ThreadUserInputOptionDescriptionFieldPartView implements ThreadUserInputFieldPartView {
  const ThreadUserInputOptionDescriptionFieldPartView(this.optionIndex);


 final  int optionIndex;

/// Create a copy of ThreadUserInputFieldPartView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadUserInputOptionDescriptionFieldPartViewCopyWith<ThreadUserInputOptionDescriptionFieldPartView> get copyWith => _$ThreadUserInputOptionDescriptionFieldPartViewCopyWithImpl<ThreadUserInputOptionDescriptionFieldPartView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadUserInputOptionDescriptionFieldPartView&&(identical(other.optionIndex, optionIndex) || other.optionIndex == optionIndex));
}


@override
int get hashCode {
    return Object.hash(runtimeType,optionIndex);
}



}

/// @nodoc
abstract mixin class $ThreadUserInputOptionDescriptionFieldPartViewCopyWith<$Res> implements $ThreadUserInputFieldPartViewCopyWith<$Res> {
  factory $ThreadUserInputOptionDescriptionFieldPartViewCopyWith(ThreadUserInputOptionDescriptionFieldPartView value, $Res Function(ThreadUserInputOptionDescriptionFieldPartView) _then) = _$ThreadUserInputOptionDescriptionFieldPartViewCopyWithImpl;
@useResult
$Res call({
 int optionIndex
});




}
/// @nodoc
class _$ThreadUserInputOptionDescriptionFieldPartViewCopyWithImpl<$Res>
    implements $ThreadUserInputOptionDescriptionFieldPartViewCopyWith<$Res> {
  _$ThreadUserInputOptionDescriptionFieldPartViewCopyWithImpl(this._self, this._then);

  final ThreadUserInputOptionDescriptionFieldPartView _self;
  final $Res Function(ThreadUserInputOptionDescriptionFieldPartView) _then;

/// Create a copy of ThreadUserInputFieldPartView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? optionIndex = null,}) {
  return _then(ThreadUserInputOptionDescriptionFieldPartView(
null == optionIndex ? _self.optionIndex : optionIndex // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadFieldChangeView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadFieldChangeView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadFieldChangeViewCopyWith<$Res>  {
$ThreadFieldChangeViewCopyWith(ThreadFieldChangeView _, $Res Function(ThreadFieldChangeView) __);
}


/// Adds pattern-matching-related methods to [ThreadFieldChangeView].
extension ThreadFieldChangeViewPatterns on ThreadFieldChangeView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnchangedThreadFieldChangeView value)?  unchanged,TResult Function( AppendThreadFieldChangeView value)?  append,TResult Function( ReplaceThreadFieldChangeView value)?  replace,TResult Function( RemoveThreadFieldChangeView value)?  remove,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnchangedThreadFieldChangeView() when unchanged != null:
return unchanged(_that);case AppendThreadFieldChangeView() when append != null:
return append(_that);case ReplaceThreadFieldChangeView() when replace != null:
return replace(_that);case RemoveThreadFieldChangeView() when remove != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnchangedThreadFieldChangeView value)  unchanged,required TResult Function( AppendThreadFieldChangeView value)  append,required TResult Function( ReplaceThreadFieldChangeView value)  replace,required TResult Function( RemoveThreadFieldChangeView value)  remove,}){
final _that = this;
switch (_that) {
case UnchangedThreadFieldChangeView():
return unchanged(_that);case AppendThreadFieldChangeView():
return append(_that);case ReplaceThreadFieldChangeView():
return replace(_that);case RemoveThreadFieldChangeView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnchangedThreadFieldChangeView value)?  unchanged,TResult? Function( AppendThreadFieldChangeView value)?  append,TResult? Function( ReplaceThreadFieldChangeView value)?  replace,TResult? Function( RemoveThreadFieldChangeView value)?  remove,}){
final _that = this;
switch (_that) {
case UnchangedThreadFieldChangeView() when unchanged != null:
return unchanged(_that);case AppendThreadFieldChangeView() when append != null:
return append(_that);case ReplaceThreadFieldChangeView() when replace != null:
return replace(_that);case RemoveThreadFieldChangeView() when remove != null:
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
case UnchangedThreadFieldChangeView() when unchanged != null:
return unchanged();case AppendThreadFieldChangeView() when append != null:
return append(_that.text);case ReplaceThreadFieldChangeView() when replace != null:
return replace(_that.text);case RemoveThreadFieldChangeView() when remove != null:
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
case UnchangedThreadFieldChangeView():
return unchanged();case AppendThreadFieldChangeView():
return append(_that.text);case ReplaceThreadFieldChangeView():
return replace(_that.text);case RemoveThreadFieldChangeView():
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
case UnchangedThreadFieldChangeView() when unchanged != null:
return unchanged();case AppendThreadFieldChangeView() when append != null:
return append(_that.text);case ReplaceThreadFieldChangeView() when replace != null:
return replace(_that.text);case RemoveThreadFieldChangeView() when remove != null:
return remove();case _:
  return null;

}
}

}

/// @nodoc


class UnchangedThreadFieldChangeView implements ThreadFieldChangeView {
  const UnchangedThreadFieldChangeView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnchangedThreadFieldChangeView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class AppendThreadFieldChangeView implements ThreadFieldChangeView {
  const AppendThreadFieldChangeView(this.text);


 final  String text;

/// Create a copy of ThreadFieldChangeView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppendThreadFieldChangeViewCopyWith<AppendThreadFieldChangeView> get copyWith => _$AppendThreadFieldChangeViewCopyWithImpl<AppendThreadFieldChangeView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AppendThreadFieldChangeView&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}



}

/// @nodoc
abstract mixin class $AppendThreadFieldChangeViewCopyWith<$Res> implements $ThreadFieldChangeViewCopyWith<$Res> {
  factory $AppendThreadFieldChangeViewCopyWith(AppendThreadFieldChangeView value, $Res Function(AppendThreadFieldChangeView) _then) = _$AppendThreadFieldChangeViewCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$AppendThreadFieldChangeViewCopyWithImpl<$Res>
    implements $AppendThreadFieldChangeViewCopyWith<$Res> {
  _$AppendThreadFieldChangeViewCopyWithImpl(this._self, this._then);

  final AppendThreadFieldChangeView _self;
  final $Res Function(AppendThreadFieldChangeView) _then;

/// Create a copy of ThreadFieldChangeView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(AppendThreadFieldChangeView(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ReplaceThreadFieldChangeView implements ThreadFieldChangeView {
  const ReplaceThreadFieldChangeView(this.text);


 final  String text;

/// Create a copy of ThreadFieldChangeView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplaceThreadFieldChangeViewCopyWith<ReplaceThreadFieldChangeView> get copyWith => _$ReplaceThreadFieldChangeViewCopyWithImpl<ReplaceThreadFieldChangeView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplaceThreadFieldChangeView&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}



}

/// @nodoc
abstract mixin class $ReplaceThreadFieldChangeViewCopyWith<$Res> implements $ThreadFieldChangeViewCopyWith<$Res> {
  factory $ReplaceThreadFieldChangeViewCopyWith(ReplaceThreadFieldChangeView value, $Res Function(ReplaceThreadFieldChangeView) _then) = _$ReplaceThreadFieldChangeViewCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$ReplaceThreadFieldChangeViewCopyWithImpl<$Res>
    implements $ReplaceThreadFieldChangeViewCopyWith<$Res> {
  _$ReplaceThreadFieldChangeViewCopyWithImpl(this._self, this._then);

  final ReplaceThreadFieldChangeView _self;
  final $Res Function(ReplaceThreadFieldChangeView) _then;

/// Create a copy of ThreadFieldChangeView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(ReplaceThreadFieldChangeView(
null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RemoveThreadFieldChangeView implements ThreadFieldChangeView {
  const RemoveThreadFieldChangeView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveThreadFieldChangeView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$ThreadFieldUpdateView {

 ThreadContentFieldView get field; ThreadFieldChangeView get change;
/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadFieldUpdateViewCopyWith<ThreadFieldUpdateView> get copyWith => _$ThreadFieldUpdateViewCopyWithImpl<ThreadFieldUpdateView>(this as ThreadFieldUpdateView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadFieldUpdateView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadFieldUpdateView&&(identical(other.field, _this.field) || other.field == _this.field)&&(identical(other.change, _this.change) || other.change == _this.change));
}


@override
int get hashCode {
  final _this = this as ThreadFieldUpdateView;
  return Object.hash(runtimeType,_this.field,_this.change);
}



}

/// @nodoc
abstract mixin class $ThreadFieldUpdateViewCopyWith<$Res>  {
  factory $ThreadFieldUpdateViewCopyWith(ThreadFieldUpdateView value, $Res Function(ThreadFieldUpdateView) _then) = _$ThreadFieldUpdateViewCopyWithImpl;
@useResult
$Res call({
 ThreadContentFieldView field, ThreadFieldChangeView change
});


$ThreadContentFieldViewCopyWith<$Res> get field;$ThreadFieldChangeViewCopyWith<$Res> get change;

}
/// @nodoc
class _$ThreadFieldUpdateViewCopyWithImpl<$Res>
    implements $ThreadFieldUpdateViewCopyWith<$Res> {
  _$ThreadFieldUpdateViewCopyWithImpl(this._self, this._then);

  final ThreadFieldUpdateView _self;
  final $Res Function(ThreadFieldUpdateView) _then;

/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? field = null,Object? change = null,}) {
  return _then(ThreadFieldUpdateView(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,change: null == change ? _self.change : change // ignore: cast_nullable_to_non_nullable
as ThreadFieldChangeView,
  ));
}
/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFieldChangeViewCopyWith<$Res> get change {

  return $ThreadFieldChangeViewCopyWith<$Res>(_self.change, (value) {
    return _then(_self.copyWith(change: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadFieldUpdateView].
extension ThreadFieldUpdateViewPatterns on ThreadFieldUpdateView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadFieldUpdateView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadFieldUpdateView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadFieldUpdateView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadFieldUpdateView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadFieldUpdateView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadFieldUpdateView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  ThreadFieldChangeView change)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadFieldUpdateView() when $default != null:
return $default(_that.field,_that.change);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadContentFieldView field,  ThreadFieldChangeView change)  $default,) {final _that = this;
switch (_that) {
case _ThreadFieldUpdateView():
return $default(_that.field,_that.change);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadContentFieldView field,  ThreadFieldChangeView change)?  $default,) {final _that = this;
switch (_that) {
case _ThreadFieldUpdateView() when $default != null:
return $default(_that.field,_that.change);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadFieldUpdateView implements ThreadFieldUpdateView {
  const _ThreadFieldUpdateView({required this.field, required this.change});


@override final  ThreadContentFieldView field;
@override final  ThreadFieldChangeView change;

/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadFieldUpdateViewCopyWith<_ThreadFieldUpdateView> get copyWith => __$ThreadFieldUpdateViewCopyWithImpl<_ThreadFieldUpdateView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadFieldUpdateView&&(identical(other.field, field) || other.field == field)&&(identical(other.change, change) || other.change == change));
}


@override
int get hashCode {
    return Object.hash(runtimeType,field,change);
}



}

/// @nodoc
abstract mixin class _$ThreadFieldUpdateViewCopyWith<$Res> implements $ThreadFieldUpdateViewCopyWith<$Res> {
  factory _$ThreadFieldUpdateViewCopyWith(_ThreadFieldUpdateView value, $Res Function(_ThreadFieldUpdateView) _then) = __$ThreadFieldUpdateViewCopyWithImpl;
@override @useResult
$Res call({
 ThreadContentFieldView field, ThreadFieldChangeView change
});


@override $ThreadContentFieldViewCopyWith<$Res> get field;@override $ThreadFieldChangeViewCopyWith<$Res> get change;

}
/// @nodoc
class __$ThreadFieldUpdateViewCopyWithImpl<$Res>
    implements _$ThreadFieldUpdateViewCopyWith<$Res> {
  __$ThreadFieldUpdateViewCopyWithImpl(this._self, this._then);

  final _ThreadFieldUpdateView _self;
  final $Res Function(_ThreadFieldUpdateView) _then;

/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? field = null,Object? change = null,}) {
  return _then(_ThreadFieldUpdateView(
field: null == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as ThreadContentFieldView,change: null == change ? _self.change : change // ignore: cast_nullable_to_non_nullable
as ThreadFieldChangeView,
  ));
}

/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContentFieldViewCopyWith<$Res> get field {

  return $ThreadContentFieldViewCopyWith<$Res>(_self.field, (value) {
    return _then(_self.copyWith(field: value));
  });
}/// Create a copy of ThreadFieldUpdateView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFieldChangeViewCopyWith<$Res> get change {

  return $ThreadFieldChangeViewCopyWith<$Res>(_self.change, (value) {
    return _then(_self.copyWith(change: value));
  });
}
}

/// @nodoc
mixin _$OpaqueArtifactJson {

 String get json;
/// Create a copy of OpaqueArtifactJson
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpaqueArtifactJsonCopyWith<OpaqueArtifactJson> get copyWith => _$OpaqueArtifactJsonCopyWithImpl<OpaqueArtifactJson>(this as OpaqueArtifactJson, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as OpaqueArtifactJson;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OpaqueArtifactJson&&(identical(other.json, _this.json) || other.json == _this.json));
}


@override
int get hashCode {
  final _this = this as OpaqueArtifactJson;
  return Object.hash(runtimeType,_this.json);
}



}

/// @nodoc
abstract mixin class $OpaqueArtifactJsonCopyWith<$Res>  {
  factory $OpaqueArtifactJsonCopyWith(OpaqueArtifactJson value, $Res Function(OpaqueArtifactJson) _then) = _$OpaqueArtifactJsonCopyWithImpl;
@useResult
$Res call({
 String json
});




}
/// @nodoc
class _$OpaqueArtifactJsonCopyWithImpl<$Res>
    implements $OpaqueArtifactJsonCopyWith<$Res> {
  _$OpaqueArtifactJsonCopyWithImpl(this._self, this._then);

  final OpaqueArtifactJson _self;
  final $Res Function(OpaqueArtifactJson) _then;

/// Create a copy of OpaqueArtifactJson
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? json = null,}) {
  return _then(OpaqueArtifactJson(
json: null == json ? _self.json : json // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [OpaqueArtifactJson].
extension OpaqueArtifactJsonPatterns on OpaqueArtifactJson {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OpaqueArtifactJson value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OpaqueArtifactJson() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OpaqueArtifactJson value)  $default,){
final _that = this;
switch (_that) {
case _OpaqueArtifactJson():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OpaqueArtifactJson value)?  $default,){
final _that = this;
switch (_that) {
case _OpaqueArtifactJson() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String json)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OpaqueArtifactJson() when $default != null:
return $default(_that.json);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String json)  $default,) {final _that = this;
switch (_that) {
case _OpaqueArtifactJson():
return $default(_that.json);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String json)?  $default,) {final _that = this;
switch (_that) {
case _OpaqueArtifactJson() when $default != null:
return $default(_that.json);case _:
  return null;

}
}

}

/// @nodoc


class _OpaqueArtifactJson implements OpaqueArtifactJson {
  const _OpaqueArtifactJson({required this.json});


@override final  String json;

/// Create a copy of OpaqueArtifactJson
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OpaqueArtifactJsonCopyWith<_OpaqueArtifactJson> get copyWith => __$OpaqueArtifactJsonCopyWithImpl<_OpaqueArtifactJson>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _OpaqueArtifactJson&&(identical(other.json, json) || other.json == json));
}


@override
int get hashCode {
    return Object.hash(runtimeType,json);
}



}

/// @nodoc
abstract mixin class _$OpaqueArtifactJsonCopyWith<$Res> implements $OpaqueArtifactJsonCopyWith<$Res> {
  factory _$OpaqueArtifactJsonCopyWith(_OpaqueArtifactJson value, $Res Function(_OpaqueArtifactJson) _then) = __$OpaqueArtifactJsonCopyWithImpl;
@override @useResult
$Res call({
 String json
});




}
/// @nodoc
class __$OpaqueArtifactJsonCopyWithImpl<$Res>
    implements _$OpaqueArtifactJsonCopyWith<$Res> {
  __$OpaqueArtifactJsonCopyWithImpl(this._self, this._then);

  final _OpaqueArtifactJson _self;
  final $Res Function(_OpaqueArtifactJson) _then;

/// Create a copy of OpaqueArtifactJson
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? json = null,}) {
  return _then(_OpaqueArtifactJson(
json: null == json ? _self.json : json // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
