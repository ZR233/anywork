// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeInteractionReadContent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadContent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeInteractionReadContent()';
}


}

/// @nodoc
class $BridgeInteractionReadContentCopyWith<$Res>  {
$BridgeInteractionReadContentCopyWith(BridgeInteractionReadContent _, $Res Function(BridgeInteractionReadContent) __);
}


/// Adds pattern-matching-related methods to [BridgeInteractionReadContent].
extension BridgeInteractionReadContentPatterns on BridgeInteractionReadContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeInteractionReadContent_UserInput value)?  userInput,TResult Function( BridgeInteractionReadContent_ToolApproval value)?  toolApproval,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeInteractionReadContent_UserInput() when userInput != null:
return userInput(_that);case BridgeInteractionReadContent_ToolApproval() when toolApproval != null:
return toolApproval(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeInteractionReadContent_UserInput value)  userInput,required TResult Function( BridgeInteractionReadContent_ToolApproval value)  toolApproval,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadContent_UserInput():
return userInput(_that);case BridgeInteractionReadContent_ToolApproval():
return toolApproval(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeInteractionReadContent_UserInput value)?  userInput,TResult? Function( BridgeInteractionReadContent_ToolApproval value)?  toolApproval,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadContent_UserInput() when userInput != null:
return userInput(_that);case BridgeInteractionReadContent_ToolApproval() when toolApproval != null:
return toolApproval(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt questionCount)?  userInput,TResult Function( BridgeReadText name,  BridgeReadText arguments,  BridgeReadText? workingDirectory,  BridgeReadText? parentAgentId)?  toolApproval,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeInteractionReadContent_UserInput() when userInput != null:
return userInput(_that.questionCount);case BridgeInteractionReadContent_ToolApproval() when toolApproval != null:
return toolApproval(_that.name,_that.arguments,_that.workingDirectory,_that.parentAgentId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt questionCount)  userInput,required TResult Function( BridgeReadText name,  BridgeReadText arguments,  BridgeReadText? workingDirectory,  BridgeReadText? parentAgentId)  toolApproval,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadContent_UserInput():
return userInput(_that.questionCount);case BridgeInteractionReadContent_ToolApproval():
return toolApproval(_that.name,_that.arguments,_that.workingDirectory,_that.parentAgentId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt questionCount)?  userInput,TResult? Function( BridgeReadText name,  BridgeReadText arguments,  BridgeReadText? workingDirectory,  BridgeReadText? parentAgentId)?  toolApproval,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadContent_UserInput() when userInput != null:
return userInput(_that.questionCount);case BridgeInteractionReadContent_ToolApproval() when toolApproval != null:
return toolApproval(_that.name,_that.arguments,_that.workingDirectory,_that.parentAgentId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeInteractionReadContent_UserInput extends BridgeInteractionReadContent {
  const BridgeInteractionReadContent_UserInput({required this.questionCount}): super._();


 final  BigInt questionCount;

/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadContent_UserInputCopyWith<BridgeInteractionReadContent_UserInput> get copyWith => _$BridgeInteractionReadContent_UserInputCopyWithImpl<BridgeInteractionReadContent_UserInput>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadContent_UserInput&&(identical(other.questionCount, questionCount) || other.questionCount == questionCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,questionCount);
}

@override
String toString() {
    return 'BridgeInteractionReadContent.userInput(questionCount: $questionCount)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadContent_UserInputCopyWith<$Res> implements $BridgeInteractionReadContentCopyWith<$Res> {
  factory $BridgeInteractionReadContent_UserInputCopyWith(BridgeInteractionReadContent_UserInput value, $Res Function(BridgeInteractionReadContent_UserInput) _then) = _$BridgeInteractionReadContent_UserInputCopyWithImpl;
@useResult
$Res call({
 BigInt questionCount
});




}
/// @nodoc
class _$BridgeInteractionReadContent_UserInputCopyWithImpl<$Res>
    implements $BridgeInteractionReadContent_UserInputCopyWith<$Res> {
  _$BridgeInteractionReadContent_UserInputCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadContent_UserInput _self;
  final $Res Function(BridgeInteractionReadContent_UserInput) _then;

/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? questionCount = null,}) {
  return _then(BridgeInteractionReadContent_UserInput(
questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class BridgeInteractionReadContent_ToolApproval extends BridgeInteractionReadContent {
  const BridgeInteractionReadContent_ToolApproval({required this.name, required this.arguments, this.workingDirectory, this.parentAgentId}): super._();


 final  BridgeReadText name;
 final  BridgeReadText arguments;
 final  BridgeReadText? workingDirectory;
 final  BridgeReadText? parentAgentId;

/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadContent_ToolApprovalCopyWith<BridgeInteractionReadContent_ToolApproval> get copyWith => _$BridgeInteractionReadContent_ToolApprovalCopyWithImpl<BridgeInteractionReadContent_ToolApproval>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadContent_ToolApproval&&(identical(other.name, name) || other.name == name)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.parentAgentId, parentAgentId) || other.parentAgentId == parentAgentId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,arguments,workingDirectory,parentAgentId);
}

@override
String toString() {
    return 'BridgeInteractionReadContent.toolApproval(name: $name, arguments: $arguments, workingDirectory: $workingDirectory, parentAgentId: $parentAgentId)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadContent_ToolApprovalCopyWith<$Res> implements $BridgeInteractionReadContentCopyWith<$Res> {
  factory $BridgeInteractionReadContent_ToolApprovalCopyWith(BridgeInteractionReadContent_ToolApproval value, $Res Function(BridgeInteractionReadContent_ToolApproval) _then) = _$BridgeInteractionReadContent_ToolApprovalCopyWithImpl;
@useResult
$Res call({
 BridgeReadText name, BridgeReadText arguments, BridgeReadText? workingDirectory, BridgeReadText? parentAgentId
});


$BridgeReadTextCopyWith<$Res> get name;$BridgeReadTextCopyWith<$Res> get arguments;$BridgeReadTextCopyWith<$Res>? get workingDirectory;$BridgeReadTextCopyWith<$Res>? get parentAgentId;

}
/// @nodoc
class _$BridgeInteractionReadContent_ToolApprovalCopyWithImpl<$Res>
    implements $BridgeInteractionReadContent_ToolApprovalCopyWith<$Res> {
  _$BridgeInteractionReadContent_ToolApprovalCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadContent_ToolApproval _self;
  final $Res Function(BridgeInteractionReadContent_ToolApproval) _then;

/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? arguments = null,Object? workingDirectory = freezed,Object? parentAgentId = freezed,}) {
  return _then(BridgeInteractionReadContent_ToolApproval(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as BridgeReadText,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as BridgeReadText,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,parentAgentId: freezed == parentAgentId ? _self.parentAgentId : parentAgentId // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,
  ));
}

/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get name {

  return $BridgeReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get arguments {

  return $BridgeReadTextCopyWith<$Res>(_self.arguments, (value) {
    return _then(_self.copyWith(arguments: value));
  });
}/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get workingDirectory {
    if (_self.workingDirectory == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.workingDirectory!, (value) {
    return _then(_self.copyWith(workingDirectory: value));
  });
}/// Create a copy of BridgeInteractionReadContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get parentAgentId {
    if (_self.parentAgentId == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.parentAgentId!, (value) {
    return _then(_self.copyWith(parentAgentId: value));
  });
}
}

/// @nodoc
mixin _$BridgeInteractionReadContinuation {

 BridgeInteractionPresentation get presentation;
/// Create a copy of BridgeInteractionReadContinuation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadContinuationCopyWith<BridgeInteractionReadContinuation> get copyWith => _$BridgeInteractionReadContinuationCopyWithImpl<BridgeInteractionReadContinuation>(this as BridgeInteractionReadContinuation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeInteractionReadContinuation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadContinuation&&(identical(other.presentation, _this.presentation) || other.presentation == _this.presentation));
}


@override
int get hashCode {
  final _this = this as BridgeInteractionReadContinuation;
  return Object.hash(runtimeType,_this.presentation);
}

@override
String toString() {
  final _this = this as BridgeInteractionReadContinuation;
  return 'BridgeInteractionReadContinuation(presentation: ${_this.presentation})';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadContinuationCopyWith<$Res>  {
  factory $BridgeInteractionReadContinuationCopyWith(BridgeInteractionReadContinuation value, $Res Function(BridgeInteractionReadContinuation) _then) = _$BridgeInteractionReadContinuationCopyWithImpl;
@useResult
$Res call({
 BridgeInteractionPresentation presentation
});




}
/// @nodoc
class _$BridgeInteractionReadContinuationCopyWithImpl<$Res>
    implements $BridgeInteractionReadContinuationCopyWith<$Res> {
  _$BridgeInteractionReadContinuationCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadContinuation _self;
  final $Res Function(BridgeInteractionReadContinuation) _then;

/// Create a copy of BridgeInteractionReadContinuation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? presentation = null,}) {
  return _then(_self.copyWith(
presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as BridgeInteractionPresentation,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeInteractionReadContinuation].
extension BridgeInteractionReadContinuationPatterns on BridgeInteractionReadContinuation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeInteractionReadContinuation_Resolution value)?  resolution,TResult Function( BridgeInteractionReadContinuation_Question value)?  question,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeInteractionReadContinuation_Resolution() when resolution != null:
return resolution(_that);case BridgeInteractionReadContinuation_Question() when question != null:
return question(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeInteractionReadContinuation_Resolution value)  resolution,required TResult Function( BridgeInteractionReadContinuation_Question value)  question,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadContinuation_Resolution():
return resolution(_that);case BridgeInteractionReadContinuation_Question():
return question(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeInteractionReadContinuation_Resolution value)?  resolution,TResult? Function( BridgeInteractionReadContinuation_Question value)?  question,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadContinuation_Resolution() when resolution != null:
return resolution(_that);case BridgeInteractionReadContinuation_Question() when question != null:
return question(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeInteractionPresentation presentation)?  resolution,TResult Function( BridgeReadText questionId,  BridgeInteractionPresentation presentation)?  question,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeInteractionReadContinuation_Resolution() when resolution != null:
return resolution(_that.presentation);case BridgeInteractionReadContinuation_Question() when question != null:
return question(_that.questionId,_that.presentation);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeInteractionPresentation presentation)  resolution,required TResult Function( BridgeReadText questionId,  BridgeInteractionPresentation presentation)  question,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadContinuation_Resolution():
return resolution(_that.presentation);case BridgeInteractionReadContinuation_Question():
return question(_that.questionId,_that.presentation);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeInteractionPresentation presentation)?  resolution,TResult? Function( BridgeReadText questionId,  BridgeInteractionPresentation presentation)?  question,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadContinuation_Resolution() when resolution != null:
return resolution(_that.presentation);case BridgeInteractionReadContinuation_Question() when question != null:
return question(_that.questionId,_that.presentation);case _:
  return null;

}
}

}

/// @nodoc


class BridgeInteractionReadContinuation_Resolution extends BridgeInteractionReadContinuation {
  const BridgeInteractionReadContinuation_Resolution({required this.presentation}): super._();


@override final  BridgeInteractionPresentation presentation;

/// Create a copy of BridgeInteractionReadContinuation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadContinuation_ResolutionCopyWith<BridgeInteractionReadContinuation_Resolution> get copyWith => _$BridgeInteractionReadContinuation_ResolutionCopyWithImpl<BridgeInteractionReadContinuation_Resolution>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadContinuation_Resolution&&(identical(other.presentation, presentation) || other.presentation == presentation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,presentation);
}

@override
String toString() {
    return 'BridgeInteractionReadContinuation.resolution(presentation: $presentation)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadContinuation_ResolutionCopyWith<$Res> implements $BridgeInteractionReadContinuationCopyWith<$Res> {
  factory $BridgeInteractionReadContinuation_ResolutionCopyWith(BridgeInteractionReadContinuation_Resolution value, $Res Function(BridgeInteractionReadContinuation_Resolution) _then) = _$BridgeInteractionReadContinuation_ResolutionCopyWithImpl;
@override @useResult
$Res call({
 BridgeInteractionPresentation presentation
});




}
/// @nodoc
class _$BridgeInteractionReadContinuation_ResolutionCopyWithImpl<$Res>
    implements $BridgeInteractionReadContinuation_ResolutionCopyWith<$Res> {
  _$BridgeInteractionReadContinuation_ResolutionCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadContinuation_Resolution _self;
  final $Res Function(BridgeInteractionReadContinuation_Resolution) _then;

/// Create a copy of BridgeInteractionReadContinuation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? presentation = null,}) {
  return _then(BridgeInteractionReadContinuation_Resolution(
presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as BridgeInteractionPresentation,
  ));
}


}

/// @nodoc


class BridgeInteractionReadContinuation_Question extends BridgeInteractionReadContinuation {
  const BridgeInteractionReadContinuation_Question({required this.questionId, required this.presentation}): super._();


 final  BridgeReadText questionId;
@override final  BridgeInteractionPresentation presentation;

/// Create a copy of BridgeInteractionReadContinuation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadContinuation_QuestionCopyWith<BridgeInteractionReadContinuation_Question> get copyWith => _$BridgeInteractionReadContinuation_QuestionCopyWithImpl<BridgeInteractionReadContinuation_Question>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadContinuation_Question&&(identical(other.questionId, questionId) || other.questionId == questionId)&&(identical(other.presentation, presentation) || other.presentation == presentation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,questionId,presentation);
}

@override
String toString() {
    return 'BridgeInteractionReadContinuation.question(questionId: $questionId, presentation: $presentation)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadContinuation_QuestionCopyWith<$Res> implements $BridgeInteractionReadContinuationCopyWith<$Res> {
  factory $BridgeInteractionReadContinuation_QuestionCopyWith(BridgeInteractionReadContinuation_Question value, $Res Function(BridgeInteractionReadContinuation_Question) _then) = _$BridgeInteractionReadContinuation_QuestionCopyWithImpl;
@override @useResult
$Res call({
 BridgeReadText questionId, BridgeInteractionPresentation presentation
});


$BridgeReadTextCopyWith<$Res> get questionId;

}
/// @nodoc
class _$BridgeInteractionReadContinuation_QuestionCopyWithImpl<$Res>
    implements $BridgeInteractionReadContinuation_QuestionCopyWith<$Res> {
  _$BridgeInteractionReadContinuation_QuestionCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadContinuation_Question _self;
  final $Res Function(BridgeInteractionReadContinuation_Question) _then;

/// Create a copy of BridgeInteractionReadContinuation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? questionId = null,Object? presentation = null,}) {
  return _then(BridgeInteractionReadContinuation_Question(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as BridgeInteractionPresentation,
  ));
}

/// Create a copy of BridgeInteractionReadContinuation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get questionId {

  return $BridgeReadTextCopyWith<$Res>(_self.questionId, (value) {
    return _then(_self.copyWith(questionId: value));
  });
}
}

/// @nodoc
mixin _$BridgeInteractionReadPurpose {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadPurpose);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeInteractionReadPurpose()';
}


}

/// @nodoc
class $BridgeInteractionReadPurposeCopyWith<$Res>  {
$BridgeInteractionReadPurposeCopyWith(BridgeInteractionReadPurpose _, $Res Function(BridgeInteractionReadPurpose) __);
}


/// Adds pattern-matching-related methods to [BridgeInteractionReadPurpose].
extension BridgeInteractionReadPurposePatterns on BridgeInteractionReadPurpose {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeInteractionReadPurpose_General value)?  general,TResult Function( BridgeInteractionReadPurpose_PlanConfirmation value)?  planConfirmation,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeInteractionReadPurpose_General() when general != null:
return general(_that);case BridgeInteractionReadPurpose_PlanConfirmation() when planConfirmation != null:
return planConfirmation(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeInteractionReadPurpose_General value)  general,required TResult Function( BridgeInteractionReadPurpose_PlanConfirmation value)  planConfirmation,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadPurpose_General():
return general(_that);case BridgeInteractionReadPurpose_PlanConfirmation():
return planConfirmation(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeInteractionReadPurpose_General value)?  general,TResult? Function( BridgeInteractionReadPurpose_PlanConfirmation value)?  planConfirmation,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadPurpose_General() when general != null:
return general(_that);case BridgeInteractionReadPurpose_PlanConfirmation() when planConfirmation != null:
return planConfirmation(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  general,TResult Function( BigInt expectedRevision,  BridgeReadText operationId,  BridgeReadText argumentHash,  BridgeReadText planHash)?  planConfirmation,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeInteractionReadPurpose_General() when general != null:
return general();case BridgeInteractionReadPurpose_PlanConfirmation() when planConfirmation != null:
return planConfirmation(_that.expectedRevision,_that.operationId,_that.argumentHash,_that.planHash);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  general,required TResult Function( BigInt expectedRevision,  BridgeReadText operationId,  BridgeReadText argumentHash,  BridgeReadText planHash)  planConfirmation,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadPurpose_General():
return general();case BridgeInteractionReadPurpose_PlanConfirmation():
return planConfirmation(_that.expectedRevision,_that.operationId,_that.argumentHash,_that.planHash);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  general,TResult? Function( BigInt expectedRevision,  BridgeReadText operationId,  BridgeReadText argumentHash,  BridgeReadText planHash)?  planConfirmation,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadPurpose_General() when general != null:
return general();case BridgeInteractionReadPurpose_PlanConfirmation() when planConfirmation != null:
return planConfirmation(_that.expectedRevision,_that.operationId,_that.argumentHash,_that.planHash);case _:
  return null;

}
}

}

/// @nodoc


class BridgeInteractionReadPurpose_General extends BridgeInteractionReadPurpose {
  const BridgeInteractionReadPurpose_General(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadPurpose_General);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeInteractionReadPurpose.general()';
}


}




/// @nodoc


class BridgeInteractionReadPurpose_PlanConfirmation extends BridgeInteractionReadPurpose {
  const BridgeInteractionReadPurpose_PlanConfirmation({required this.expectedRevision, required this.operationId, required this.argumentHash, required this.planHash}): super._();


 final  BigInt expectedRevision;
 final  BridgeReadText operationId;
 final  BridgeReadText argumentHash;
 final  BridgeReadText planHash;

/// Create a copy of BridgeInteractionReadPurpose
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadPurpose_PlanConfirmationCopyWith<BridgeInteractionReadPurpose_PlanConfirmation> get copyWith => _$BridgeInteractionReadPurpose_PlanConfirmationCopyWithImpl<BridgeInteractionReadPurpose_PlanConfirmation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadPurpose_PlanConfirmation&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.argumentHash, argumentHash) || other.argumentHash == argumentHash)&&(identical(other.planHash, planHash) || other.planHash == planHash));
}


@override
int get hashCode {
    return Object.hash(runtimeType,expectedRevision,operationId,argumentHash,planHash);
}

@override
String toString() {
    return 'BridgeInteractionReadPurpose.planConfirmation(expectedRevision: $expectedRevision, operationId: $operationId, argumentHash: $argumentHash, planHash: $planHash)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadPurpose_PlanConfirmationCopyWith<$Res> implements $BridgeInteractionReadPurposeCopyWith<$Res> {
  factory $BridgeInteractionReadPurpose_PlanConfirmationCopyWith(BridgeInteractionReadPurpose_PlanConfirmation value, $Res Function(BridgeInteractionReadPurpose_PlanConfirmation) _then) = _$BridgeInteractionReadPurpose_PlanConfirmationCopyWithImpl;
@useResult
$Res call({
 BigInt expectedRevision, BridgeReadText operationId, BridgeReadText argumentHash, BridgeReadText planHash
});


$BridgeReadTextCopyWith<$Res> get operationId;$BridgeReadTextCopyWith<$Res> get argumentHash;$BridgeReadTextCopyWith<$Res> get planHash;

}
/// @nodoc
class _$BridgeInteractionReadPurpose_PlanConfirmationCopyWithImpl<$Res>
    implements $BridgeInteractionReadPurpose_PlanConfirmationCopyWith<$Res> {
  _$BridgeInteractionReadPurpose_PlanConfirmationCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadPurpose_PlanConfirmation _self;
  final $Res Function(BridgeInteractionReadPurpose_PlanConfirmation) _then;

/// Create a copy of BridgeInteractionReadPurpose
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? expectedRevision = null,Object? operationId = null,Object? argumentHash = null,Object? planHash = null,}) {
  return _then(BridgeInteractionReadPurpose_PlanConfirmation(
expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as BigInt,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,argumentHash: null == argumentHash ? _self.argumentHash : argumentHash // ignore: cast_nullable_to_non_nullable
as BridgeReadText,planHash: null == planHash ? _self.planHash : planHash // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeInteractionReadPurpose
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of BridgeInteractionReadPurpose
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get argumentHash {

  return $BridgeReadTextCopyWith<$Res>(_self.argumentHash, (value) {
    return _then(_self.copyWith(argumentHash: value));
  });
}/// Create a copy of BridgeInteractionReadPurpose
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get planHash {

  return $BridgeReadTextCopyWith<$Res>(_self.planHash, (value) {
    return _then(_self.copyWith(planHash: value));
  });
}
}

/// @nodoc
mixin _$BridgeInteractionReadState {

 BridgeReadText get operationId;
/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadStateCopyWith<BridgeInteractionReadState> get copyWith => _$BridgeInteractionReadStateCopyWithImpl<BridgeInteractionReadState>(this as BridgeInteractionReadState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeInteractionReadState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadState&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as BridgeInteractionReadState;
  return Object.hash(runtimeType,_this.operationId);
}

@override
String toString() {
  final _this = this as BridgeInteractionReadState;
  return 'BridgeInteractionReadState(operationId: ${_this.operationId})';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadStateCopyWith<$Res>  {
  factory $BridgeInteractionReadStateCopyWith(BridgeInteractionReadState value, $Res Function(BridgeInteractionReadState) _then) = _$BridgeInteractionReadStateCopyWithImpl;
@useResult
$Res call({
 BridgeReadText operationId
});


$BridgeReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$BridgeInteractionReadStateCopyWithImpl<$Res>
    implements $BridgeInteractionReadStateCopyWith<$Res> {
  _$BridgeInteractionReadStateCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadState _self;
  final $Res Function(BridgeInteractionReadState) _then;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,}) {
  return _then(_self.copyWith(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}
/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [BridgeInteractionReadState].
extension BridgeInteractionReadStatePatterns on BridgeInteractionReadState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeInteractionReadState_Pending value)?  pending,TResult Function( BridgeInteractionReadState_UserInputResolved value)?  userInputResolved,TResult Function( BridgeInteractionReadState_ApprovalResolved value)?  approvalResolved,TResult Function( BridgeInteractionReadState_Cancelled value)?  cancelled,TResult Function( BridgeInteractionReadState_Expired value)?  expired,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeInteractionReadState_Pending() when pending != null:
return pending(_that);case BridgeInteractionReadState_UserInputResolved() when userInputResolved != null:
return userInputResolved(_that);case BridgeInteractionReadState_ApprovalResolved() when approvalResolved != null:
return approvalResolved(_that);case BridgeInteractionReadState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeInteractionReadState_Expired() when expired != null:
return expired(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeInteractionReadState_Pending value)  pending,required TResult Function( BridgeInteractionReadState_UserInputResolved value)  userInputResolved,required TResult Function( BridgeInteractionReadState_ApprovalResolved value)  approvalResolved,required TResult Function( BridgeInteractionReadState_Cancelled value)  cancelled,required TResult Function( BridgeInteractionReadState_Expired value)  expired,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadState_Pending():
return pending(_that);case BridgeInteractionReadState_UserInputResolved():
return userInputResolved(_that);case BridgeInteractionReadState_ApprovalResolved():
return approvalResolved(_that);case BridgeInteractionReadState_Cancelled():
return cancelled(_that);case BridgeInteractionReadState_Expired():
return expired(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeInteractionReadState_Pending value)?  pending,TResult? Function( BridgeInteractionReadState_UserInputResolved value)?  userInputResolved,TResult? Function( BridgeInteractionReadState_ApprovalResolved value)?  approvalResolved,TResult? Function( BridgeInteractionReadState_Cancelled value)?  cancelled,TResult? Function( BridgeInteractionReadState_Expired value)?  expired,}){
final _that = this;
switch (_that) {
case BridgeInteractionReadState_Pending() when pending != null:
return pending(_that);case BridgeInteractionReadState_UserInputResolved() when userInputResolved != null:
return userInputResolved(_that);case BridgeInteractionReadState_ApprovalResolved() when approvalResolved != null:
return approvalResolved(_that);case BridgeInteractionReadState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeInteractionReadState_Expired() when expired != null:
return expired(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeReadText operationId)?  pending,TResult Function( BridgeReadText operationId,  PlatformInt64 resolvedAt,  BigInt answerEntryCount)?  userInputResolved,TResult Function( BridgeReadText operationId,  PlatformInt64 resolvedAt,  BridgeToolApprovalResolution decision,  BridgeReadText? reason)?  approvalResolved,TResult Function( BridgeReadText operationId,  PlatformInt64 cancelledAt,  BridgeReadText reason)?  cancelled,TResult Function( BridgeReadText operationId,  PlatformInt64 expiredAt)?  expired,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeInteractionReadState_Pending() when pending != null:
return pending(_that.operationId);case BridgeInteractionReadState_UserInputResolved() when userInputResolved != null:
return userInputResolved(_that.operationId,_that.resolvedAt,_that.answerEntryCount);case BridgeInteractionReadState_ApprovalResolved() when approvalResolved != null:
return approvalResolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case BridgeInteractionReadState_Cancelled() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case BridgeInteractionReadState_Expired() when expired != null:
return expired(_that.operationId,_that.expiredAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeReadText operationId)  pending,required TResult Function( BridgeReadText operationId,  PlatformInt64 resolvedAt,  BigInt answerEntryCount)  userInputResolved,required TResult Function( BridgeReadText operationId,  PlatformInt64 resolvedAt,  BridgeToolApprovalResolution decision,  BridgeReadText? reason)  approvalResolved,required TResult Function( BridgeReadText operationId,  PlatformInt64 cancelledAt,  BridgeReadText reason)  cancelled,required TResult Function( BridgeReadText operationId,  PlatformInt64 expiredAt)  expired,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadState_Pending():
return pending(_that.operationId);case BridgeInteractionReadState_UserInputResolved():
return userInputResolved(_that.operationId,_that.resolvedAt,_that.answerEntryCount);case BridgeInteractionReadState_ApprovalResolved():
return approvalResolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case BridgeInteractionReadState_Cancelled():
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case BridgeInteractionReadState_Expired():
return expired(_that.operationId,_that.expiredAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeReadText operationId)?  pending,TResult? Function( BridgeReadText operationId,  PlatformInt64 resolvedAt,  BigInt answerEntryCount)?  userInputResolved,TResult? Function( BridgeReadText operationId,  PlatformInt64 resolvedAt,  BridgeToolApprovalResolution decision,  BridgeReadText? reason)?  approvalResolved,TResult? Function( BridgeReadText operationId,  PlatformInt64 cancelledAt,  BridgeReadText reason)?  cancelled,TResult? Function( BridgeReadText operationId,  PlatformInt64 expiredAt)?  expired,}) {final _that = this;
switch (_that) {
case BridgeInteractionReadState_Pending() when pending != null:
return pending(_that.operationId);case BridgeInteractionReadState_UserInputResolved() when userInputResolved != null:
return userInputResolved(_that.operationId,_that.resolvedAt,_that.answerEntryCount);case BridgeInteractionReadState_ApprovalResolved() when approvalResolved != null:
return approvalResolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case BridgeInteractionReadState_Cancelled() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case BridgeInteractionReadState_Expired() when expired != null:
return expired(_that.operationId,_that.expiredAt);case _:
  return null;

}
}

}

/// @nodoc


class BridgeInteractionReadState_Pending extends BridgeInteractionReadState {
  const BridgeInteractionReadState_Pending({required this.operationId}): super._();


@override final  BridgeReadText operationId;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadState_PendingCopyWith<BridgeInteractionReadState_Pending> get copyWith => _$BridgeInteractionReadState_PendingCopyWithImpl<BridgeInteractionReadState_Pending>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadState_Pending&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeInteractionReadState.pending(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadState_PendingCopyWith<$Res> implements $BridgeInteractionReadStateCopyWith<$Res> {
  factory $BridgeInteractionReadState_PendingCopyWith(BridgeInteractionReadState_Pending value, $Res Function(BridgeInteractionReadState_Pending) _then) = _$BridgeInteractionReadState_PendingCopyWithImpl;
@override @useResult
$Res call({
 BridgeReadText operationId
});


@override $BridgeReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$BridgeInteractionReadState_PendingCopyWithImpl<$Res>
    implements $BridgeInteractionReadState_PendingCopyWith<$Res> {
  _$BridgeInteractionReadState_PendingCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadState_Pending _self;
  final $Res Function(BridgeInteractionReadState_Pending) _then;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeInteractionReadState_Pending(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class BridgeInteractionReadState_UserInputResolved extends BridgeInteractionReadState {
  const BridgeInteractionReadState_UserInputResolved({required this.operationId, required this.resolvedAt, required this.answerEntryCount}): super._();


@override final  BridgeReadText operationId;
 final  PlatformInt64 resolvedAt;
 final  BigInt answerEntryCount;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadState_UserInputResolvedCopyWith<BridgeInteractionReadState_UserInputResolved> get copyWith => _$BridgeInteractionReadState_UserInputResolvedCopyWithImpl<BridgeInteractionReadState_UserInputResolved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadState_UserInputResolved&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.answerEntryCount, answerEntryCount) || other.answerEntryCount == answerEntryCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,resolvedAt,answerEntryCount);
}

@override
String toString() {
    return 'BridgeInteractionReadState.userInputResolved(operationId: $operationId, resolvedAt: $resolvedAt, answerEntryCount: $answerEntryCount)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadState_UserInputResolvedCopyWith<$Res> implements $BridgeInteractionReadStateCopyWith<$Res> {
  factory $BridgeInteractionReadState_UserInputResolvedCopyWith(BridgeInteractionReadState_UserInputResolved value, $Res Function(BridgeInteractionReadState_UserInputResolved) _then) = _$BridgeInteractionReadState_UserInputResolvedCopyWithImpl;
@override @useResult
$Res call({
 BridgeReadText operationId, PlatformInt64 resolvedAt, BigInt answerEntryCount
});


@override $BridgeReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$BridgeInteractionReadState_UserInputResolvedCopyWithImpl<$Res>
    implements $BridgeInteractionReadState_UserInputResolvedCopyWith<$Res> {
  _$BridgeInteractionReadState_UserInputResolvedCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadState_UserInputResolved _self;
  final $Res Function(BridgeInteractionReadState_UserInputResolved) _then;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? resolvedAt = null,Object? answerEntryCount = null,}) {
  return _then(BridgeInteractionReadState_UserInputResolved(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,resolvedAt: null == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,answerEntryCount: null == answerEntryCount ? _self.answerEntryCount : answerEntryCount // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class BridgeInteractionReadState_ApprovalResolved extends BridgeInteractionReadState {
  const BridgeInteractionReadState_ApprovalResolved({required this.operationId, required this.resolvedAt, required this.decision, this.reason}): super._();


@override final  BridgeReadText operationId;
 final  PlatformInt64 resolvedAt;
 final  BridgeToolApprovalResolution decision;
 final  BridgeReadText? reason;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadState_ApprovalResolvedCopyWith<BridgeInteractionReadState_ApprovalResolved> get copyWith => _$BridgeInteractionReadState_ApprovalResolvedCopyWithImpl<BridgeInteractionReadState_ApprovalResolved>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadState_ApprovalResolved&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.decision, decision) || other.decision == decision)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,resolvedAt,decision,reason);
}

@override
String toString() {
    return 'BridgeInteractionReadState.approvalResolved(operationId: $operationId, resolvedAt: $resolvedAt, decision: $decision, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadState_ApprovalResolvedCopyWith<$Res> implements $BridgeInteractionReadStateCopyWith<$Res> {
  factory $BridgeInteractionReadState_ApprovalResolvedCopyWith(BridgeInteractionReadState_ApprovalResolved value, $Res Function(BridgeInteractionReadState_ApprovalResolved) _then) = _$BridgeInteractionReadState_ApprovalResolvedCopyWithImpl;
@override @useResult
$Res call({
 BridgeReadText operationId, PlatformInt64 resolvedAt, BridgeToolApprovalResolution decision, BridgeReadText? reason
});


@override $BridgeReadTextCopyWith<$Res> get operationId;$BridgeReadTextCopyWith<$Res>? get reason;

}
/// @nodoc
class _$BridgeInteractionReadState_ApprovalResolvedCopyWithImpl<$Res>
    implements $BridgeInteractionReadState_ApprovalResolvedCopyWith<$Res> {
  _$BridgeInteractionReadState_ApprovalResolvedCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadState_ApprovalResolved _self;
  final $Res Function(BridgeInteractionReadState_ApprovalResolved) _then;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? resolvedAt = null,Object? decision = null,Object? reason = freezed,}) {
  return _then(BridgeInteractionReadState_ApprovalResolved(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,resolvedAt: null == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as BridgeToolApprovalResolution,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeReadText?,
  ));
}

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res>? get reason {
    if (_self.reason == null) {
    return null;
  }

  return $BridgeReadTextCopyWith<$Res>(_self.reason!, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc


class BridgeInteractionReadState_Cancelled extends BridgeInteractionReadState {
  const BridgeInteractionReadState_Cancelled({required this.operationId, required this.cancelledAt, required this.reason}): super._();


@override final  BridgeReadText operationId;
 final  PlatformInt64 cancelledAt;
 final  BridgeReadText reason;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadState_CancelledCopyWith<BridgeInteractionReadState_Cancelled> get copyWith => _$BridgeInteractionReadState_CancelledCopyWithImpl<BridgeInteractionReadState_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadState_Cancelled&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,cancelledAt,reason);
}

@override
String toString() {
    return 'BridgeInteractionReadState.cancelled(operationId: $operationId, cancelledAt: $cancelledAt, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadState_CancelledCopyWith<$Res> implements $BridgeInteractionReadStateCopyWith<$Res> {
  factory $BridgeInteractionReadState_CancelledCopyWith(BridgeInteractionReadState_Cancelled value, $Res Function(BridgeInteractionReadState_Cancelled) _then) = _$BridgeInteractionReadState_CancelledCopyWithImpl;
@override @useResult
$Res call({
 BridgeReadText operationId, PlatformInt64 cancelledAt, BridgeReadText reason
});


@override $BridgeReadTextCopyWith<$Res> get operationId;$BridgeReadTextCopyWith<$Res> get reason;

}
/// @nodoc
class _$BridgeInteractionReadState_CancelledCopyWithImpl<$Res>
    implements $BridgeInteractionReadState_CancelledCopyWith<$Res> {
  _$BridgeInteractionReadState_CancelledCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadState_Cancelled _self;
  final $Res Function(BridgeInteractionReadState_Cancelled) _then;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? cancelledAt = null,Object? reason = null,}) {
  return _then(BridgeInteractionReadState_Cancelled(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get reason {

  return $BridgeReadTextCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc


class BridgeInteractionReadState_Expired extends BridgeInteractionReadState {
  const BridgeInteractionReadState_Expired({required this.operationId, required this.expiredAt}): super._();


@override final  BridgeReadText operationId;
 final  PlatformInt64 expiredAt;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeInteractionReadState_ExpiredCopyWith<BridgeInteractionReadState_Expired> get copyWith => _$BridgeInteractionReadState_ExpiredCopyWithImpl<BridgeInteractionReadState_Expired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeInteractionReadState_Expired&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expiredAt, expiredAt) || other.expiredAt == expiredAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expiredAt);
}

@override
String toString() {
    return 'BridgeInteractionReadState.expired(operationId: $operationId, expiredAt: $expiredAt)';
}


}

/// @nodoc
abstract mixin class $BridgeInteractionReadState_ExpiredCopyWith<$Res> implements $BridgeInteractionReadStateCopyWith<$Res> {
  factory $BridgeInteractionReadState_ExpiredCopyWith(BridgeInteractionReadState_Expired value, $Res Function(BridgeInteractionReadState_Expired) _then) = _$BridgeInteractionReadState_ExpiredCopyWithImpl;
@override @useResult
$Res call({
 BridgeReadText operationId, PlatformInt64 expiredAt
});


@override $BridgeReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$BridgeInteractionReadState_ExpiredCopyWithImpl<$Res>
    implements $BridgeInteractionReadState_ExpiredCopyWith<$Res> {
  _$BridgeInteractionReadState_ExpiredCopyWithImpl(this._self, this._then);

  final BridgeInteractionReadState_Expired _self;
  final $Res Function(BridgeInteractionReadState_Expired) _then;

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expiredAt = null,}) {
  return _then(BridgeInteractionReadState_Expired(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as BridgeReadText,expiredAt: null == expiredAt ? _self.expiredAt : expiredAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}

/// Create a copy of BridgeInteractionReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get operationId {

  return $BridgeReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

// dart format on
