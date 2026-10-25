// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InteractionPurposeRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionPurposeRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $InteractionPurposeReadCopyWith<$Res>  {
$InteractionPurposeReadCopyWith(InteractionPurposeRead _, $Res Function(InteractionPurposeRead) __);
}


/// Adds pattern-matching-related methods to [InteractionPurposeRead].
extension InteractionPurposeReadPatterns on InteractionPurposeRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( GeneralInteractionPurposeRead value)?  general,TResult Function( PlanConfirmationPurposeRead value)?  planConfirmation,required TResult orElse(),}){
final _that = this;
switch (_that) {
case GeneralInteractionPurposeRead() when general != null:
return general(_that);case PlanConfirmationPurposeRead() when planConfirmation != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( GeneralInteractionPurposeRead value)  general,required TResult Function( PlanConfirmationPurposeRead value)  planConfirmation,}){
final _that = this;
switch (_that) {
case GeneralInteractionPurposeRead():
return general(_that);case PlanConfirmationPurposeRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( GeneralInteractionPurposeRead value)?  general,TResult? Function( PlanConfirmationPurposeRead value)?  planConfirmation,}){
final _that = this;
switch (_that) {
case GeneralInteractionPurposeRead() when general != null:
return general(_that);case PlanConfirmationPurposeRead() when planConfirmation != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  general,TResult Function( int expectedRevision,  ReadText operationId,  ReadText argumentHash,  ReadText planHash)?  planConfirmation,required TResult orElse(),}) {final _that = this;
switch (_that) {
case GeneralInteractionPurposeRead() when general != null:
return general();case PlanConfirmationPurposeRead() when planConfirmation != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  general,required TResult Function( int expectedRevision,  ReadText operationId,  ReadText argumentHash,  ReadText planHash)  planConfirmation,}) {final _that = this;
switch (_that) {
case GeneralInteractionPurposeRead():
return general();case PlanConfirmationPurposeRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  general,TResult? Function( int expectedRevision,  ReadText operationId,  ReadText argumentHash,  ReadText planHash)?  planConfirmation,}) {final _that = this;
switch (_that) {
case GeneralInteractionPurposeRead() when general != null:
return general();case PlanConfirmationPurposeRead() when planConfirmation != null:
return planConfirmation(_that.expectedRevision,_that.operationId,_that.argumentHash,_that.planHash);case _:
  return null;

}
}

}

/// @nodoc


class GeneralInteractionPurposeRead implements InteractionPurposeRead {
  const GeneralInteractionPurposeRead();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is GeneralInteractionPurposeRead);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class PlanConfirmationPurposeRead implements InteractionPurposeRead {
  const PlanConfirmationPurposeRead({required this.expectedRevision, required this.operationId, required this.argumentHash, required this.planHash});


 final  int expectedRevision;
 final  ReadText operationId;
 final  ReadText argumentHash;
 final  ReadText planHash;

/// Create a copy of InteractionPurposeRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanConfirmationPurposeReadCopyWith<PlanConfirmationPurposeRead> get copyWith => _$PlanConfirmationPurposeReadCopyWithImpl<PlanConfirmationPurposeRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanConfirmationPurposeRead&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.argumentHash, argumentHash) || other.argumentHash == argumentHash)&&(identical(other.planHash, planHash) || other.planHash == planHash));
}


@override
int get hashCode {
    return Object.hash(runtimeType,expectedRevision,operationId,argumentHash,planHash);
}



}

/// @nodoc
abstract mixin class $PlanConfirmationPurposeReadCopyWith<$Res> implements $InteractionPurposeReadCopyWith<$Res> {
  factory $PlanConfirmationPurposeReadCopyWith(PlanConfirmationPurposeRead value, $Res Function(PlanConfirmationPurposeRead) _then) = _$PlanConfirmationPurposeReadCopyWithImpl;
@useResult
$Res call({
 int expectedRevision, ReadText operationId, ReadText argumentHash, ReadText planHash
});


$ReadTextCopyWith<$Res> get operationId;$ReadTextCopyWith<$Res> get argumentHash;$ReadTextCopyWith<$Res> get planHash;

}
/// @nodoc
class _$PlanConfirmationPurposeReadCopyWithImpl<$Res>
    implements $PlanConfirmationPurposeReadCopyWith<$Res> {
  _$PlanConfirmationPurposeReadCopyWithImpl(this._self, this._then);

  final PlanConfirmationPurposeRead _self;
  final $Res Function(PlanConfirmationPurposeRead) _then;

/// Create a copy of InteractionPurposeRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? expectedRevision = null,Object? operationId = null,Object? argumentHash = null,Object? planHash = null,}) {
  return _then(PlanConfirmationPurposeRead(
expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,argumentHash: null == argumentHash ? _self.argumentHash : argumentHash // ignore: cast_nullable_to_non_nullable
as ReadText,planHash: null == planHash ? _self.planHash : planHash // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of InteractionPurposeRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of InteractionPurposeRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get argumentHash {

  return $ReadTextCopyWith<$Res>(_self.argumentHash, (value) {
    return _then(_self.copyWith(argumentHash: value));
  });
}/// Create a copy of InteractionPurposeRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get planHash {

  return $ReadTextCopyWith<$Res>(_self.planHash, (value) {
    return _then(_self.copyWith(planHash: value));
  });
}
}

/// @nodoc
mixin _$InteractionContinuationRead {

 InteractionPresentation get presentation;
/// Create a copy of InteractionContinuationRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionContinuationReadCopyWith<InteractionContinuationRead> get copyWith => _$InteractionContinuationReadCopyWithImpl<InteractionContinuationRead>(this as InteractionContinuationRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionContinuationRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionContinuationRead&&(identical(other.presentation, _this.presentation) || other.presentation == _this.presentation));
}


@override
int get hashCode {
  final _this = this as InteractionContinuationRead;
  return Object.hash(runtimeType,_this.presentation);
}



}

/// @nodoc
abstract mixin class $InteractionContinuationReadCopyWith<$Res>  {
  factory $InteractionContinuationReadCopyWith(InteractionContinuationRead value, $Res Function(InteractionContinuationRead) _then) = _$InteractionContinuationReadCopyWithImpl;
@useResult
$Res call({
 InteractionPresentation presentation
});




}
/// @nodoc
class _$InteractionContinuationReadCopyWithImpl<$Res>
    implements $InteractionContinuationReadCopyWith<$Res> {
  _$InteractionContinuationReadCopyWithImpl(this._self, this._then);

  final InteractionContinuationRead _self;
  final $Res Function(InteractionContinuationRead) _then;

/// Create a copy of InteractionContinuationRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? presentation = null,}) {
  return _then(_self.copyWith(
presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as InteractionPresentation,
  ));
}

}


/// Adds pattern-matching-related methods to [InteractionContinuationRead].
extension InteractionContinuationReadPatterns on InteractionContinuationRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ResolutionContinuationRead value)?  resolution,TResult Function( QuestionContinuationRead value)?  question,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ResolutionContinuationRead() when resolution != null:
return resolution(_that);case QuestionContinuationRead() when question != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ResolutionContinuationRead value)  resolution,required TResult Function( QuestionContinuationRead value)  question,}){
final _that = this;
switch (_that) {
case ResolutionContinuationRead():
return resolution(_that);case QuestionContinuationRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ResolutionContinuationRead value)?  resolution,TResult? Function( QuestionContinuationRead value)?  question,}){
final _that = this;
switch (_that) {
case ResolutionContinuationRead() when resolution != null:
return resolution(_that);case QuestionContinuationRead() when question != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( InteractionPresentation presentation)?  resolution,TResult Function( ReadText questionId,  InteractionPresentation presentation)?  question,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ResolutionContinuationRead() when resolution != null:
return resolution(_that.presentation);case QuestionContinuationRead() when question != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( InteractionPresentation presentation)  resolution,required TResult Function( ReadText questionId,  InteractionPresentation presentation)  question,}) {final _that = this;
switch (_that) {
case ResolutionContinuationRead():
return resolution(_that.presentation);case QuestionContinuationRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( InteractionPresentation presentation)?  resolution,TResult? Function( ReadText questionId,  InteractionPresentation presentation)?  question,}) {final _that = this;
switch (_that) {
case ResolutionContinuationRead() when resolution != null:
return resolution(_that.presentation);case QuestionContinuationRead() when question != null:
return question(_that.questionId,_that.presentation);case _:
  return null;

}
}

}

/// @nodoc


class ResolutionContinuationRead implements InteractionContinuationRead {
  const ResolutionContinuationRead({required this.presentation});


@override final  InteractionPresentation presentation;

/// Create a copy of InteractionContinuationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolutionContinuationReadCopyWith<ResolutionContinuationRead> get copyWith => _$ResolutionContinuationReadCopyWithImpl<ResolutionContinuationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolutionContinuationRead&&(identical(other.presentation, presentation) || other.presentation == presentation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,presentation);
}



}

/// @nodoc
abstract mixin class $ResolutionContinuationReadCopyWith<$Res> implements $InteractionContinuationReadCopyWith<$Res> {
  factory $ResolutionContinuationReadCopyWith(ResolutionContinuationRead value, $Res Function(ResolutionContinuationRead) _then) = _$ResolutionContinuationReadCopyWithImpl;
@override @useResult
$Res call({
 InteractionPresentation presentation
});




}
/// @nodoc
class _$ResolutionContinuationReadCopyWithImpl<$Res>
    implements $ResolutionContinuationReadCopyWith<$Res> {
  _$ResolutionContinuationReadCopyWithImpl(this._self, this._then);

  final ResolutionContinuationRead _self;
  final $Res Function(ResolutionContinuationRead) _then;

/// Create a copy of InteractionContinuationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? presentation = null,}) {
  return _then(ResolutionContinuationRead(
presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as InteractionPresentation,
  ));
}


}

/// @nodoc


class QuestionContinuationRead implements InteractionContinuationRead {
  const QuestionContinuationRead({required this.questionId, required this.presentation});


 final  ReadText questionId;
@override final  InteractionPresentation presentation;

/// Create a copy of InteractionContinuationRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionContinuationReadCopyWith<QuestionContinuationRead> get copyWith => _$QuestionContinuationReadCopyWithImpl<QuestionContinuationRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QuestionContinuationRead&&(identical(other.questionId, questionId) || other.questionId == questionId)&&(identical(other.presentation, presentation) || other.presentation == presentation));
}


@override
int get hashCode {
    return Object.hash(runtimeType,questionId,presentation);
}



}

/// @nodoc
abstract mixin class $QuestionContinuationReadCopyWith<$Res> implements $InteractionContinuationReadCopyWith<$Res> {
  factory $QuestionContinuationReadCopyWith(QuestionContinuationRead value, $Res Function(QuestionContinuationRead) _then) = _$QuestionContinuationReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText questionId, InteractionPresentation presentation
});


$ReadTextCopyWith<$Res> get questionId;

}
/// @nodoc
class _$QuestionContinuationReadCopyWithImpl<$Res>
    implements $QuestionContinuationReadCopyWith<$Res> {
  _$QuestionContinuationReadCopyWithImpl(this._self, this._then);

  final QuestionContinuationRead _self;
  final $Res Function(QuestionContinuationRead) _then;

/// Create a copy of InteractionContinuationRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? questionId = null,Object? presentation = null,}) {
  return _then(QuestionContinuationRead(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as ReadText,presentation: null == presentation ? _self.presentation : presentation // ignore: cast_nullable_to_non_nullable
as InteractionPresentation,
  ));
}

/// Create a copy of InteractionContinuationRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get questionId {

  return $ReadTextCopyWith<$Res>(_self.questionId, (value) {
    return _then(_self.copyWith(questionId: value));
  });
}
}

/// @nodoc
mixin _$InteractionContentRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionContentRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $InteractionContentReadCopyWith<$Res>  {
$InteractionContentReadCopyWith(InteractionContentRead _, $Res Function(InteractionContentRead) __);
}


/// Adds pattern-matching-related methods to [InteractionContentRead].
extension InteractionContentReadPatterns on InteractionContentRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UserInputContentRead value)?  userInput,TResult Function( ToolApprovalContentRead value)?  toolApproval,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UserInputContentRead() when userInput != null:
return userInput(_that);case ToolApprovalContentRead() when toolApproval != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UserInputContentRead value)  userInput,required TResult Function( ToolApprovalContentRead value)  toolApproval,}){
final _that = this;
switch (_that) {
case UserInputContentRead():
return userInput(_that);case ToolApprovalContentRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UserInputContentRead value)?  userInput,TResult? Function( ToolApprovalContentRead value)?  toolApproval,}){
final _that = this;
switch (_that) {
case UserInputContentRead() when userInput != null:
return userInput(_that);case ToolApprovalContentRead() when toolApproval != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int questionCount)?  userInput,TResult Function( ReadText name,  ReadText arguments,  ReadText? workingDirectory,  ReadText? parentAgentId)?  toolApproval,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UserInputContentRead() when userInput != null:
return userInput(_that.questionCount);case ToolApprovalContentRead() when toolApproval != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int questionCount)  userInput,required TResult Function( ReadText name,  ReadText arguments,  ReadText? workingDirectory,  ReadText? parentAgentId)  toolApproval,}) {final _that = this;
switch (_that) {
case UserInputContentRead():
return userInput(_that.questionCount);case ToolApprovalContentRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int questionCount)?  userInput,TResult? Function( ReadText name,  ReadText arguments,  ReadText? workingDirectory,  ReadText? parentAgentId)?  toolApproval,}) {final _that = this;
switch (_that) {
case UserInputContentRead() when userInput != null:
return userInput(_that.questionCount);case ToolApprovalContentRead() when toolApproval != null:
return toolApproval(_that.name,_that.arguments,_that.workingDirectory,_that.parentAgentId);case _:
  return null;

}
}

}

/// @nodoc


class UserInputContentRead implements InteractionContentRead {
  const UserInputContentRead({required this.questionCount});


 final  int questionCount;

/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserInputContentReadCopyWith<UserInputContentRead> get copyWith => _$UserInputContentReadCopyWithImpl<UserInputContentRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UserInputContentRead&&(identical(other.questionCount, questionCount) || other.questionCount == questionCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,questionCount);
}



}

/// @nodoc
abstract mixin class $UserInputContentReadCopyWith<$Res> implements $InteractionContentReadCopyWith<$Res> {
  factory $UserInputContentReadCopyWith(UserInputContentRead value, $Res Function(UserInputContentRead) _then) = _$UserInputContentReadCopyWithImpl;
@useResult
$Res call({
 int questionCount
});




}
/// @nodoc
class _$UserInputContentReadCopyWithImpl<$Res>
    implements $UserInputContentReadCopyWith<$Res> {
  _$UserInputContentReadCopyWithImpl(this._self, this._then);

  final UserInputContentRead _self;
  final $Res Function(UserInputContentRead) _then;

/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? questionCount = null,}) {
  return _then(UserInputContentRead(
questionCount: null == questionCount ? _self.questionCount : questionCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ToolApprovalContentRead implements InteractionContentRead {
  const ToolApprovalContentRead({required this.name, required this.arguments, required this.workingDirectory, required this.parentAgentId});


 final  ReadText name;
 final  ReadText arguments;
 final  ReadText? workingDirectory;
 final  ReadText? parentAgentId;

/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToolApprovalContentReadCopyWith<ToolApprovalContentRead> get copyWith => _$ToolApprovalContentReadCopyWithImpl<ToolApprovalContentRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ToolApprovalContentRead&&(identical(other.name, name) || other.name == name)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.parentAgentId, parentAgentId) || other.parentAgentId == parentAgentId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,arguments,workingDirectory,parentAgentId);
}



}

/// @nodoc
abstract mixin class $ToolApprovalContentReadCopyWith<$Res> implements $InteractionContentReadCopyWith<$Res> {
  factory $ToolApprovalContentReadCopyWith(ToolApprovalContentRead value, $Res Function(ToolApprovalContentRead) _then) = _$ToolApprovalContentReadCopyWithImpl;
@useResult
$Res call({
 ReadText name, ReadText arguments, ReadText? workingDirectory, ReadText? parentAgentId
});


$ReadTextCopyWith<$Res> get name;$ReadTextCopyWith<$Res> get arguments;$ReadTextCopyWith<$Res>? get workingDirectory;$ReadTextCopyWith<$Res>? get parentAgentId;

}
/// @nodoc
class _$ToolApprovalContentReadCopyWithImpl<$Res>
    implements $ToolApprovalContentReadCopyWith<$Res> {
  _$ToolApprovalContentReadCopyWithImpl(this._self, this._then);

  final ToolApprovalContentRead _self;
  final $Res Function(ToolApprovalContentRead) _then;

/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? name = null,Object? arguments = null,Object? workingDirectory = freezed,Object? parentAgentId = freezed,}) {
  return _then(ToolApprovalContentRead(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as ReadText,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as ReadText?,parentAgentId: freezed == parentAgentId ? _self.parentAgentId : parentAgentId // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get arguments {

  return $ReadTextCopyWith<$Res>(_self.arguments, (value) {
    return _then(_self.copyWith(arguments: value));
  });
}/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get workingDirectory {
    if (_self.workingDirectory == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.workingDirectory!, (value) {
    return _then(_self.copyWith(workingDirectory: value));
  });
}/// Create a copy of InteractionContentRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parentAgentId {
    if (_self.parentAgentId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parentAgentId!, (value) {
    return _then(_self.copyWith(parentAgentId: value));
  });
}
}

/// @nodoc
mixin _$InteractionStateRead {

 ReadText get operationId;
/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionStateReadCopyWith<InteractionStateRead> get copyWith => _$InteractionStateReadCopyWithImpl<InteractionStateRead>(this as InteractionStateRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionStateRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionStateRead&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as InteractionStateRead;
  return Object.hash(runtimeType,_this.operationId);
}



}

/// @nodoc
abstract mixin class $InteractionStateReadCopyWith<$Res>  {
  factory $InteractionStateReadCopyWith(InteractionStateRead value, $Res Function(InteractionStateRead) _then) = _$InteractionStateReadCopyWithImpl;
@useResult
$Res call({
 ReadText operationId
});


$ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$InteractionStateReadCopyWithImpl<$Res>
    implements $InteractionStateReadCopyWith<$Res> {
  _$InteractionStateReadCopyWithImpl(this._self, this._then);

  final InteractionStateRead _self;
  final $Res Function(InteractionStateRead) _then;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,}) {
  return _then(_self.copyWith(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionStateRead].
extension InteractionStateReadPatterns on InteractionStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PendingInteractionRead value)?  pending,TResult Function( ResolvedUserInputRead value)?  userInputResolved,TResult Function( ResolvedApprovalRead value)?  approvalResolved,TResult Function( CancelledInteractionRead value)?  cancelled,TResult Function( ExpiredInteractionRead value)?  expired,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PendingInteractionRead() when pending != null:
return pending(_that);case ResolvedUserInputRead() when userInputResolved != null:
return userInputResolved(_that);case ResolvedApprovalRead() when approvalResolved != null:
return approvalResolved(_that);case CancelledInteractionRead() when cancelled != null:
return cancelled(_that);case ExpiredInteractionRead() when expired != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PendingInteractionRead value)  pending,required TResult Function( ResolvedUserInputRead value)  userInputResolved,required TResult Function( ResolvedApprovalRead value)  approvalResolved,required TResult Function( CancelledInteractionRead value)  cancelled,required TResult Function( ExpiredInteractionRead value)  expired,}){
final _that = this;
switch (_that) {
case PendingInteractionRead():
return pending(_that);case ResolvedUserInputRead():
return userInputResolved(_that);case ResolvedApprovalRead():
return approvalResolved(_that);case CancelledInteractionRead():
return cancelled(_that);case ExpiredInteractionRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PendingInteractionRead value)?  pending,TResult? Function( ResolvedUserInputRead value)?  userInputResolved,TResult? Function( ResolvedApprovalRead value)?  approvalResolved,TResult? Function( CancelledInteractionRead value)?  cancelled,TResult? Function( ExpiredInteractionRead value)?  expired,}){
final _that = this;
switch (_that) {
case PendingInteractionRead() when pending != null:
return pending(_that);case ResolvedUserInputRead() when userInputResolved != null:
return userInputResolved(_that);case ResolvedApprovalRead() when approvalResolved != null:
return approvalResolved(_that);case CancelledInteractionRead() when cancelled != null:
return cancelled(_that);case ExpiredInteractionRead() when expired != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ReadText operationId)?  pending,TResult Function( ReadText operationId,  int resolvedAt,  int answerEntryCount)?  userInputResolved,TResult Function( ReadText operationId,  int resolvedAt,  ToolApprovalDecision decision,  ReadText? reason)?  approvalResolved,TResult Function( ReadText operationId,  int cancelledAt,  ReadText reason)?  cancelled,TResult Function( ReadText operationId,  int expiredAt)?  expired,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PendingInteractionRead() when pending != null:
return pending(_that.operationId);case ResolvedUserInputRead() when userInputResolved != null:
return userInputResolved(_that.operationId,_that.resolvedAt,_that.answerEntryCount);case ResolvedApprovalRead() when approvalResolved != null:
return approvalResolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case CancelledInteractionRead() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredInteractionRead() when expired != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ReadText operationId)  pending,required TResult Function( ReadText operationId,  int resolvedAt,  int answerEntryCount)  userInputResolved,required TResult Function( ReadText operationId,  int resolvedAt,  ToolApprovalDecision decision,  ReadText? reason)  approvalResolved,required TResult Function( ReadText operationId,  int cancelledAt,  ReadText reason)  cancelled,required TResult Function( ReadText operationId,  int expiredAt)  expired,}) {final _that = this;
switch (_that) {
case PendingInteractionRead():
return pending(_that.operationId);case ResolvedUserInputRead():
return userInputResolved(_that.operationId,_that.resolvedAt,_that.answerEntryCount);case ResolvedApprovalRead():
return approvalResolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case CancelledInteractionRead():
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredInteractionRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ReadText operationId)?  pending,TResult? Function( ReadText operationId,  int resolvedAt,  int answerEntryCount)?  userInputResolved,TResult? Function( ReadText operationId,  int resolvedAt,  ToolApprovalDecision decision,  ReadText? reason)?  approvalResolved,TResult? Function( ReadText operationId,  int cancelledAt,  ReadText reason)?  cancelled,TResult? Function( ReadText operationId,  int expiredAt)?  expired,}) {final _that = this;
switch (_that) {
case PendingInteractionRead() when pending != null:
return pending(_that.operationId);case ResolvedUserInputRead() when userInputResolved != null:
return userInputResolved(_that.operationId,_that.resolvedAt,_that.answerEntryCount);case ResolvedApprovalRead() when approvalResolved != null:
return approvalResolved(_that.operationId,_that.resolvedAt,_that.decision,_that.reason);case CancelledInteractionRead() when cancelled != null:
return cancelled(_that.operationId,_that.cancelledAt,_that.reason);case ExpiredInteractionRead() when expired != null:
return expired(_that.operationId,_that.expiredAt);case _:
  return null;

}
}

}

/// @nodoc


class PendingInteractionRead implements InteractionStateRead {
  const PendingInteractionRead({required this.operationId});


@override final  ReadText operationId;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PendingInteractionReadCopyWith<PendingInteractionRead> get copyWith => _$PendingInteractionReadCopyWithImpl<PendingInteractionRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingInteractionRead&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $PendingInteractionReadCopyWith<$Res> implements $InteractionStateReadCopyWith<$Res> {
  factory $PendingInteractionReadCopyWith(PendingInteractionRead value, $Res Function(PendingInteractionRead) _then) = _$PendingInteractionReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText operationId
});


@override $ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$PendingInteractionReadCopyWithImpl<$Res>
    implements $PendingInteractionReadCopyWith<$Res> {
  _$PendingInteractionReadCopyWithImpl(this._self, this._then);

  final PendingInteractionRead _self;
  final $Res Function(PendingInteractionRead) _then;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(PendingInteractionRead(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class ResolvedUserInputRead implements InteractionStateRead {
  const ResolvedUserInputRead({required this.operationId, required this.resolvedAt, required this.answerEntryCount});


@override final  ReadText operationId;
 final  int resolvedAt;
 final  int answerEntryCount;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolvedUserInputReadCopyWith<ResolvedUserInputRead> get copyWith => _$ResolvedUserInputReadCopyWithImpl<ResolvedUserInputRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolvedUserInputRead&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.answerEntryCount, answerEntryCount) || other.answerEntryCount == answerEntryCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,resolvedAt,answerEntryCount);
}



}

/// @nodoc
abstract mixin class $ResolvedUserInputReadCopyWith<$Res> implements $InteractionStateReadCopyWith<$Res> {
  factory $ResolvedUserInputReadCopyWith(ResolvedUserInputRead value, $Res Function(ResolvedUserInputRead) _then) = _$ResolvedUserInputReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText operationId, int resolvedAt, int answerEntryCount
});


@override $ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$ResolvedUserInputReadCopyWithImpl<$Res>
    implements $ResolvedUserInputReadCopyWith<$Res> {
  _$ResolvedUserInputReadCopyWithImpl(this._self, this._then);

  final ResolvedUserInputRead _self;
  final $Res Function(ResolvedUserInputRead) _then;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? resolvedAt = null,Object? answerEntryCount = null,}) {
  return _then(ResolvedUserInputRead(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,resolvedAt: null == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as int,answerEntryCount: null == answerEntryCount ? _self.answerEntryCount : answerEntryCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class ResolvedApprovalRead implements InteractionStateRead {
  const ResolvedApprovalRead({required this.operationId, required this.resolvedAt, required this.decision, required this.reason});


@override final  ReadText operationId;
 final  int resolvedAt;
 final  ToolApprovalDecision decision;
 final  ReadText? reason;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolvedApprovalReadCopyWith<ResolvedApprovalRead> get copyWith => _$ResolvedApprovalReadCopyWithImpl<ResolvedApprovalRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolvedApprovalRead&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.decision, decision) || other.decision == decision)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,resolvedAt,decision,reason);
}



}

/// @nodoc
abstract mixin class $ResolvedApprovalReadCopyWith<$Res> implements $InteractionStateReadCopyWith<$Res> {
  factory $ResolvedApprovalReadCopyWith(ResolvedApprovalRead value, $Res Function(ResolvedApprovalRead) _then) = _$ResolvedApprovalReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText operationId, int resolvedAt, ToolApprovalDecision decision, ReadText? reason
});


@override $ReadTextCopyWith<$Res> get operationId;$ReadTextCopyWith<$Res>? get reason;

}
/// @nodoc
class _$ResolvedApprovalReadCopyWithImpl<$Res>
    implements $ResolvedApprovalReadCopyWith<$Res> {
  _$ResolvedApprovalReadCopyWithImpl(this._self, this._then);

  final ResolvedApprovalRead _self;
  final $Res Function(ResolvedApprovalRead) _then;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? resolvedAt = null,Object? decision = null,Object? reason = freezed,}) {
  return _then(ResolvedApprovalRead(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,resolvedAt: null == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as int,decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as ToolApprovalDecision,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get reason {
    if (_self.reason == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.reason!, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc


class CancelledInteractionRead implements InteractionStateRead {
  const CancelledInteractionRead({required this.operationId, required this.cancelledAt, required this.reason});


@override final  ReadText operationId;
 final  int cancelledAt;
 final  ReadText reason;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledInteractionReadCopyWith<CancelledInteractionRead> get copyWith => _$CancelledInteractionReadCopyWithImpl<CancelledInteractionRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledInteractionRead&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,cancelledAt,reason);
}



}

/// @nodoc
abstract mixin class $CancelledInteractionReadCopyWith<$Res> implements $InteractionStateReadCopyWith<$Res> {
  factory $CancelledInteractionReadCopyWith(CancelledInteractionRead value, $Res Function(CancelledInteractionRead) _then) = _$CancelledInteractionReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText operationId, int cancelledAt, ReadText reason
});


@override $ReadTextCopyWith<$Res> get operationId;$ReadTextCopyWith<$Res> get reason;

}
/// @nodoc
class _$CancelledInteractionReadCopyWithImpl<$Res>
    implements $CancelledInteractionReadCopyWith<$Res> {
  _$CancelledInteractionReadCopyWithImpl(this._self, this._then);

  final CancelledInteractionRead _self;
  final $Res Function(CancelledInteractionRead) _then;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? cancelledAt = null,Object? reason = null,}) {
  return _then(CancelledInteractionRead(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,cancelledAt: null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get reason {

  return $ReadTextCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc


class ExpiredInteractionRead implements InteractionStateRead {
  const ExpiredInteractionRead({required this.operationId, required this.expiredAt});


@override final  ReadText operationId;
 final  int expiredAt;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExpiredInteractionReadCopyWith<ExpiredInteractionRead> get copyWith => _$ExpiredInteractionReadCopyWithImpl<ExpiredInteractionRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ExpiredInteractionRead&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expiredAt, expiredAt) || other.expiredAt == expiredAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expiredAt);
}



}

/// @nodoc
abstract mixin class $ExpiredInteractionReadCopyWith<$Res> implements $InteractionStateReadCopyWith<$Res> {
  factory $ExpiredInteractionReadCopyWith(ExpiredInteractionRead value, $Res Function(ExpiredInteractionRead) _then) = _$ExpiredInteractionReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText operationId, int expiredAt
});


@override $ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$ExpiredInteractionReadCopyWithImpl<$Res>
    implements $ExpiredInteractionReadCopyWith<$Res> {
  _$ExpiredInteractionReadCopyWithImpl(this._self, this._then);

  final ExpiredInteractionRead _self;
  final $Res Function(ExpiredInteractionRead) _then;

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expiredAt = null,}) {
  return _then(ExpiredInteractionRead(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,expiredAt: null == expiredAt ? _self.expiredAt : expiredAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of InteractionStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$InteractionReadHeader {

 ReadScopeIdentity get scope; ReadText get interactionId; ReadText get threadId; ReadText get turnId; ReadText? get itemId; ReadText? get toolId; ReadText? get agentPath; int get revision; InteractionPurposeRead get purpose; InteractionContinuationRead? get continuation; int get createdAt; int get updatedAt; InteractionContentRead get content; InteractionStateRead get state;
/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionReadHeaderCopyWith<InteractionReadHeader> get copyWith => _$InteractionReadHeaderCopyWithImpl<InteractionReadHeader>(this as InteractionReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.interactionId, _this.interactionId) || other.interactionId == _this.interactionId)&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.itemId, _this.itemId) || other.itemId == _this.itemId)&&(identical(other.toolId, _this.toolId) || other.toolId == _this.toolId)&&(identical(other.agentPath, _this.agentPath) || other.agentPath == _this.agentPath)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.purpose, _this.purpose) || other.purpose == _this.purpose)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.content, _this.content) || other.content == _this.content)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as InteractionReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.interactionId,_this.threadId,_this.turnId,_this.itemId,_this.toolId,_this.agentPath,_this.revision,_this.purpose,_this.continuation,_this.createdAt,_this.updatedAt,_this.content,_this.state);
}



}

/// @nodoc
abstract mixin class $InteractionReadHeaderCopyWith<$Res>  {
  factory $InteractionReadHeaderCopyWith(InteractionReadHeader value, $Res Function(InteractionReadHeader) _then) = _$InteractionReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, ReadText interactionId, ReadText threadId, ReadText turnId, ReadText? itemId, ReadText? toolId, ReadText? agentPath, int revision, InteractionPurposeRead purpose, InteractionContinuationRead? continuation, int createdAt, int updatedAt, InteractionContentRead content, InteractionStateRead state
});


$ReadScopeIdentityCopyWith<$Res> get scope;$ReadTextCopyWith<$Res> get interactionId;$ReadTextCopyWith<$Res> get threadId;$ReadTextCopyWith<$Res> get turnId;$ReadTextCopyWith<$Res>? get itemId;$ReadTextCopyWith<$Res>? get toolId;$ReadTextCopyWith<$Res>? get agentPath;$InteractionPurposeReadCopyWith<$Res> get purpose;$InteractionContinuationReadCopyWith<$Res>? get continuation;$InteractionContentReadCopyWith<$Res> get content;$InteractionStateReadCopyWith<$Res> get state;

}
/// @nodoc
class _$InteractionReadHeaderCopyWithImpl<$Res>
    implements $InteractionReadHeaderCopyWith<$Res> {
  _$InteractionReadHeaderCopyWithImpl(this._self, this._then);

  final InteractionReadHeader _self;
  final $Res Function(InteractionReadHeader) _then;

/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? interactionId = null,Object? threadId = null,Object? turnId = null,Object? itemId = freezed,Object? toolId = freezed,Object? agentPath = freezed,Object? revision = null,Object? purpose = null,Object? continuation = freezed,Object? createdAt = null,Object? updatedAt = null,Object? content = null,Object? state = null,}) {
  return _then(InteractionReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as ReadText,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,itemId: freezed == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as ReadText?,toolId: freezed == toolId ? _self.toolId : toolId // ignore: cast_nullable_to_non_nullable
as ReadText?,agentPath: freezed == agentPath ? _self.agentPath : agentPath // ignore: cast_nullable_to_non_nullable
as ReadText?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,purpose: null == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as InteractionPurposeRead,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as InteractionContinuationRead?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as InteractionContentRead,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as InteractionStateRead,
  ));
}
/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get interactionId {

  return $ReadTextCopyWith<$Res>(_self.interactionId, (value) {
    return _then(_self.copyWith(interactionId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get itemId {
    if (_self.itemId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.itemId!, (value) {
    return _then(_self.copyWith(itemId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get toolId {
    if (_self.toolId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.toolId!, (value) {
    return _then(_self.copyWith(toolId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get agentPath {
    if (_self.agentPath == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.agentPath!, (value) {
    return _then(_self.copyWith(agentPath: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionPurposeReadCopyWith<$Res> get purpose {

  return $InteractionPurposeReadCopyWith<$Res>(_self.purpose, (value) {
    return _then(_self.copyWith(purpose: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionContinuationReadCopyWith<$Res>? get continuation {
    if (_self.continuation == null) {
    return null;
  }

  return $InteractionContinuationReadCopyWith<$Res>(_self.continuation!, (value) {
    return _then(_self.copyWith(continuation: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionContentReadCopyWith<$Res> get content {

  return $InteractionContentReadCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionStateReadCopyWith<$Res> get state {

  return $InteractionStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionReadHeader].
extension InteractionReadHeaderPatterns on InteractionReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _InteractionReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText interactionId,  ReadText threadId,  ReadText turnId,  ReadText? itemId,  ReadText? toolId,  ReadText? agentPath,  int revision,  InteractionPurposeRead purpose,  InteractionContinuationRead? continuation,  int createdAt,  int updatedAt,  InteractionContentRead content,  InteractionStateRead state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionReadHeader() when $default != null:
return $default(_that.scope,_that.interactionId,_that.threadId,_that.turnId,_that.itemId,_that.toolId,_that.agentPath,_that.revision,_that.purpose,_that.continuation,_that.createdAt,_that.updatedAt,_that.content,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  ReadText interactionId,  ReadText threadId,  ReadText turnId,  ReadText? itemId,  ReadText? toolId,  ReadText? agentPath,  int revision,  InteractionPurposeRead purpose,  InteractionContinuationRead? continuation,  int createdAt,  int updatedAt,  InteractionContentRead content,  InteractionStateRead state)  $default,) {final _that = this;
switch (_that) {
case _InteractionReadHeader():
return $default(_that.scope,_that.interactionId,_that.threadId,_that.turnId,_that.itemId,_that.toolId,_that.agentPath,_that.revision,_that.purpose,_that.continuation,_that.createdAt,_that.updatedAt,_that.content,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  ReadText interactionId,  ReadText threadId,  ReadText turnId,  ReadText? itemId,  ReadText? toolId,  ReadText? agentPath,  int revision,  InteractionPurposeRead purpose,  InteractionContinuationRead? continuation,  int createdAt,  int updatedAt,  InteractionContentRead content,  InteractionStateRead state)?  $default,) {final _that = this;
switch (_that) {
case _InteractionReadHeader() when $default != null:
return $default(_that.scope,_that.interactionId,_that.threadId,_that.turnId,_that.itemId,_that.toolId,_that.agentPath,_that.revision,_that.purpose,_that.continuation,_that.createdAt,_that.updatedAt,_that.content,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionReadHeader implements InteractionReadHeader {
  const _InteractionReadHeader({required this.scope, required this.interactionId, required this.threadId, required this.turnId, required this.itemId, required this.toolId, required this.agentPath, required this.revision, required this.purpose, required this.continuation, required this.createdAt, required this.updatedAt, required this.content, required this.state});


@override final  ReadScopeIdentity scope;
@override final  ReadText interactionId;
@override final  ReadText threadId;
@override final  ReadText turnId;
@override final  ReadText? itemId;
@override final  ReadText? toolId;
@override final  ReadText? agentPath;
@override final  int revision;
@override final  InteractionPurposeRead purpose;
@override final  InteractionContinuationRead? continuation;
@override final  int createdAt;
@override final  int updatedAt;
@override final  InteractionContentRead content;
@override final  InteractionStateRead state;

/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionReadHeaderCopyWith<_InteractionReadHeader> get copyWith => __$InteractionReadHeaderCopyWithImpl<_InteractionReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.interactionId, interactionId) || other.interactionId == interactionId)&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.toolId, toolId) || other.toolId == toolId)&&(identical(other.agentPath, agentPath) || other.agentPath == agentPath)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.purpose, purpose) || other.purpose == purpose)&&(identical(other.continuation, continuation) || other.continuation == continuation)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.content, content) || other.content == content)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,interactionId,threadId,turnId,itemId,toolId,agentPath,revision,purpose,continuation,createdAt,updatedAt,content,state);
}



}

/// @nodoc
abstract mixin class _$InteractionReadHeaderCopyWith<$Res> implements $InteractionReadHeaderCopyWith<$Res> {
  factory _$InteractionReadHeaderCopyWith(_InteractionReadHeader value, $Res Function(_InteractionReadHeader) _then) = __$InteractionReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, ReadText interactionId, ReadText threadId, ReadText turnId, ReadText? itemId, ReadText? toolId, ReadText? agentPath, int revision, InteractionPurposeRead purpose, InteractionContinuationRead? continuation, int createdAt, int updatedAt, InteractionContentRead content, InteractionStateRead state
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;@override $ReadTextCopyWith<$Res> get interactionId;@override $ReadTextCopyWith<$Res> get threadId;@override $ReadTextCopyWith<$Res> get turnId;@override $ReadTextCopyWith<$Res>? get itemId;@override $ReadTextCopyWith<$Res>? get toolId;@override $ReadTextCopyWith<$Res>? get agentPath;@override $InteractionPurposeReadCopyWith<$Res> get purpose;@override $InteractionContinuationReadCopyWith<$Res>? get continuation;@override $InteractionContentReadCopyWith<$Res> get content;@override $InteractionStateReadCopyWith<$Res> get state;

}
/// @nodoc
class __$InteractionReadHeaderCopyWithImpl<$Res>
    implements _$InteractionReadHeaderCopyWith<$Res> {
  __$InteractionReadHeaderCopyWithImpl(this._self, this._then);

  final _InteractionReadHeader _self;
  final $Res Function(_InteractionReadHeader) _then;

/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? interactionId = null,Object? threadId = null,Object? turnId = null,Object? itemId = freezed,Object? toolId = freezed,Object? agentPath = freezed,Object? revision = null,Object? purpose = null,Object? continuation = freezed,Object? createdAt = null,Object? updatedAt = null,Object? content = null,Object? state = null,}) {
  return _then(_InteractionReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as ReadText,threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,itemId: freezed == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as ReadText?,toolId: freezed == toolId ? _self.toolId : toolId // ignore: cast_nullable_to_non_nullable
as ReadText?,agentPath: freezed == agentPath ? _self.agentPath : agentPath // ignore: cast_nullable_to_non_nullable
as ReadText?,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,purpose: null == purpose ? _self.purpose : purpose // ignore: cast_nullable_to_non_nullable
as InteractionPurposeRead,continuation: freezed == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as InteractionContinuationRead?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as InteractionContentRead,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as InteractionStateRead,
  ));
}

/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get interactionId {

  return $ReadTextCopyWith<$Res>(_self.interactionId, (value) {
    return _then(_self.copyWith(interactionId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get itemId {
    if (_self.itemId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.itemId!, (value) {
    return _then(_self.copyWith(itemId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get toolId {
    if (_self.toolId == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.toolId!, (value) {
    return _then(_self.copyWith(toolId: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get agentPath {
    if (_self.agentPath == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.agentPath!, (value) {
    return _then(_self.copyWith(agentPath: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionPurposeReadCopyWith<$Res> get purpose {

  return $InteractionPurposeReadCopyWith<$Res>(_self.purpose, (value) {
    return _then(_self.copyWith(purpose: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionContinuationReadCopyWith<$Res>? get continuation {
    if (_self.continuation == null) {
    return null;
  }

  return $InteractionContinuationReadCopyWith<$Res>(_self.continuation!, (value) {
    return _then(_self.copyWith(continuation: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionContentReadCopyWith<$Res> get content {

  return $InteractionContentReadCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}/// Create a copy of InteractionReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionStateReadCopyWith<$Res> get state {

  return $InteractionStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$QuestionReadItem {

 int get index; ReadText get id; ReadText get header; ReadText get question; bool get isOther; bool get isSecret; int? get optionsCount;
/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionReadItemCopyWith<QuestionReadItem> get copyWith => _$QuestionReadItemCopyWithImpl<QuestionReadItem>(this as QuestionReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuestionReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuestionReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.question, _this.question) || other.question == _this.question)&&(identical(other.isOther, _this.isOther) || other.isOther == _this.isOther)&&(identical(other.isSecret, _this.isSecret) || other.isSecret == _this.isSecret)&&(identical(other.optionsCount, _this.optionsCount) || other.optionsCount == _this.optionsCount));
}


@override
int get hashCode {
  final _this = this as QuestionReadItem;
  return Object.hash(runtimeType,_this.index,_this.id,_this.header,_this.question,_this.isOther,_this.isSecret,_this.optionsCount);
}



}

/// @nodoc
abstract mixin class $QuestionReadItemCopyWith<$Res>  {
  factory $QuestionReadItemCopyWith(QuestionReadItem value, $Res Function(QuestionReadItem) _then) = _$QuestionReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText id, ReadText header, ReadText question, bool isOther, bool isSecret, int? optionsCount
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get header;$ReadTextCopyWith<$Res> get question;

}
/// @nodoc
class _$QuestionReadItemCopyWithImpl<$Res>
    implements $QuestionReadItemCopyWith<$Res> {
  _$QuestionReadItemCopyWithImpl(this._self, this._then);

  final QuestionReadItem _self;
  final $Res Function(QuestionReadItem) _then;

/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? id = null,Object? header = null,Object? question = null,Object? isOther = null,Object? isSecret = null,Object? optionsCount = freezed,}) {
  return _then(QuestionReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ReadText,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as ReadText,isOther: null == isOther ? _self.isOther : isOther // ignore: cast_nullable_to_non_nullable
as bool,isSecret: null == isSecret ? _self.isSecret : isSecret // ignore: cast_nullable_to_non_nullable
as bool,optionsCount: freezed == optionsCount ? _self.optionsCount : optionsCount // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get header {

  return $ReadTextCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get question {

  return $ReadTextCopyWith<$Res>(_self.question, (value) {
    return _then(_self.copyWith(question: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuestionReadItem].
extension QuestionReadItemPatterns on QuestionReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuestionReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuestionReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuestionReadItem value)  $default,){
final _that = this;
switch (_that) {
case _QuestionReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuestionReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _QuestionReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText id,  ReadText header,  ReadText question,  bool isOther,  bool isSecret,  int? optionsCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuestionReadItem() when $default != null:
return $default(_that.index,_that.id,_that.header,_that.question,_that.isOther,_that.isSecret,_that.optionsCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText id,  ReadText header,  ReadText question,  bool isOther,  bool isSecret,  int? optionsCount)  $default,) {final _that = this;
switch (_that) {
case _QuestionReadItem():
return $default(_that.index,_that.id,_that.header,_that.question,_that.isOther,_that.isSecret,_that.optionsCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText id,  ReadText header,  ReadText question,  bool isOther,  bool isSecret,  int? optionsCount)?  $default,) {final _that = this;
switch (_that) {
case _QuestionReadItem() when $default != null:
return $default(_that.index,_that.id,_that.header,_that.question,_that.isOther,_that.isSecret,_that.optionsCount);case _:
  return null;

}
}

}

/// @nodoc


class _QuestionReadItem implements QuestionReadItem {
  const _QuestionReadItem({required this.index, required this.id, required this.header, required this.question, required this.isOther, required this.isSecret, required this.optionsCount});


@override final  int index;
@override final  ReadText id;
@override final  ReadText header;
@override final  ReadText question;
@override final  bool isOther;
@override final  bool isSecret;
@override final  int? optionsCount;

/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuestionReadItemCopyWith<_QuestionReadItem> get copyWith => __$QuestionReadItemCopyWithImpl<_QuestionReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuestionReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.id, id) || other.id == id)&&(identical(other.header, header) || other.header == header)&&(identical(other.question, question) || other.question == question)&&(identical(other.isOther, isOther) || other.isOther == isOther)&&(identical(other.isSecret, isSecret) || other.isSecret == isSecret)&&(identical(other.optionsCount, optionsCount) || other.optionsCount == optionsCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,id,header,question,isOther,isSecret,optionsCount);
}



}

/// @nodoc
abstract mixin class _$QuestionReadItemCopyWith<$Res> implements $QuestionReadItemCopyWith<$Res> {
  factory _$QuestionReadItemCopyWith(_QuestionReadItem value, $Res Function(_QuestionReadItem) _then) = __$QuestionReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText id, ReadText header, ReadText question, bool isOther, bool isSecret, int? optionsCount
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get header;@override $ReadTextCopyWith<$Res> get question;

}
/// @nodoc
class __$QuestionReadItemCopyWithImpl<$Res>
    implements _$QuestionReadItemCopyWith<$Res> {
  __$QuestionReadItemCopyWithImpl(this._self, this._then);

  final _QuestionReadItem _self;
  final $Res Function(_QuestionReadItem) _then;

/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? id = null,Object? header = null,Object? question = null,Object? isOther = null,Object? isSecret = null,Object? optionsCount = freezed,}) {
  return _then(_QuestionReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ReadText,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as ReadText,isOther: null == isOther ? _self.isOther : isOther // ignore: cast_nullable_to_non_nullable
as bool,isSecret: null == isSecret ? _self.isSecret : isSecret // ignore: cast_nullable_to_non_nullable
as bool,optionsCount: freezed == optionsCount ? _self.optionsCount : optionsCount // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get header {

  return $ReadTextCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of QuestionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get question {

  return $ReadTextCopyWith<$Res>(_self.question, (value) {
    return _then(_self.copyWith(question: value));
  });
}
}

/// @nodoc
mixin _$OptionReadItem {

 int get index; ReadText get label; ReadText get description;
/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OptionReadItemCopyWith<OptionReadItem> get copyWith => _$OptionReadItemCopyWithImpl<OptionReadItem>(this as OptionReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as OptionReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OptionReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.description, _this.description) || other.description == _this.description));
}


@override
int get hashCode {
  final _this = this as OptionReadItem;
  return Object.hash(runtimeType,_this.index,_this.label,_this.description);
}



}

/// @nodoc
abstract mixin class $OptionReadItemCopyWith<$Res>  {
  factory $OptionReadItemCopyWith(OptionReadItem value, $Res Function(OptionReadItem) _then) = _$OptionReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText label, ReadText description
});


$ReadTextCopyWith<$Res> get label;$ReadTextCopyWith<$Res> get description;

}
/// @nodoc
class _$OptionReadItemCopyWithImpl<$Res>
    implements $OptionReadItemCopyWith<$Res> {
  _$OptionReadItemCopyWithImpl(this._self, this._then);

  final OptionReadItem _self;
  final $Res Function(OptionReadItem) _then;

/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? label = null,Object? description = null,}) {
  return _then(OptionReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}
}


/// Adds pattern-matching-related methods to [OptionReadItem].
extension OptionReadItemPatterns on OptionReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OptionReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OptionReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OptionReadItem value)  $default,){
final _that = this;
switch (_that) {
case _OptionReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OptionReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _OptionReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText label,  ReadText description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OptionReadItem() when $default != null:
return $default(_that.index,_that.label,_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText label,  ReadText description)  $default,) {final _that = this;
switch (_that) {
case _OptionReadItem():
return $default(_that.index,_that.label,_that.description);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText label,  ReadText description)?  $default,) {final _that = this;
switch (_that) {
case _OptionReadItem() when $default != null:
return $default(_that.index,_that.label,_that.description);case _:
  return null;

}
}

}

/// @nodoc


class _OptionReadItem implements OptionReadItem {
  const _OptionReadItem({required this.index, required this.label, required this.description});


@override final  int index;
@override final  ReadText label;
@override final  ReadText description;

/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OptionReadItemCopyWith<_OptionReadItem> get copyWith => __$OptionReadItemCopyWithImpl<_OptionReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _OptionReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.label, label) || other.label == label)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,label,description);
}



}

/// @nodoc
abstract mixin class _$OptionReadItemCopyWith<$Res> implements $OptionReadItemCopyWith<$Res> {
  factory _$OptionReadItemCopyWith(_OptionReadItem value, $Res Function(_OptionReadItem) _then) = __$OptionReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText label, ReadText description
});


@override $ReadTextCopyWith<$Res> get label;@override $ReadTextCopyWith<$Res> get description;

}
/// @nodoc
class __$OptionReadItemCopyWithImpl<$Res>
    implements _$OptionReadItemCopyWith<$Res> {
  __$OptionReadItemCopyWithImpl(this._self, this._then);

  final _OptionReadItem _self;
  final $Res Function(_OptionReadItem) _then;

/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? label = null,Object? description = null,}) {
  return _then(_OptionReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}/// Create a copy of OptionReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}
}

/// @nodoc
mixin _$AnswerEntryReadItem {

 int get index; ReadText get questionId; int get answerCount;
/// Create a copy of AnswerEntryReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerEntryReadItemCopyWith<AnswerEntryReadItem> get copyWith => _$AnswerEntryReadItemCopyWithImpl<AnswerEntryReadItem>(this as AnswerEntryReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AnswerEntryReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerEntryReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.questionId, _this.questionId) || other.questionId == _this.questionId)&&(identical(other.answerCount, _this.answerCount) || other.answerCount == _this.answerCount));
}


@override
int get hashCode {
  final _this = this as AnswerEntryReadItem;
  return Object.hash(runtimeType,_this.index,_this.questionId,_this.answerCount);
}



}

/// @nodoc
abstract mixin class $AnswerEntryReadItemCopyWith<$Res>  {
  factory $AnswerEntryReadItemCopyWith(AnswerEntryReadItem value, $Res Function(AnswerEntryReadItem) _then) = _$AnswerEntryReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText questionId, int answerCount
});


$ReadTextCopyWith<$Res> get questionId;

}
/// @nodoc
class _$AnswerEntryReadItemCopyWithImpl<$Res>
    implements $AnswerEntryReadItemCopyWith<$Res> {
  _$AnswerEntryReadItemCopyWithImpl(this._self, this._then);

  final AnswerEntryReadItem _self;
  final $Res Function(AnswerEntryReadItem) _then;

/// Create a copy of AnswerEntryReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? questionId = null,Object? answerCount = null,}) {
  return _then(AnswerEntryReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as ReadText,answerCount: null == answerCount ? _self.answerCount : answerCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AnswerEntryReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get questionId {

  return $ReadTextCopyWith<$Res>(_self.questionId, (value) {
    return _then(_self.copyWith(questionId: value));
  });
}
}


/// Adds pattern-matching-related methods to [AnswerEntryReadItem].
extension AnswerEntryReadItemPatterns on AnswerEntryReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AnswerEntryReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AnswerEntryReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AnswerEntryReadItem value)  $default,){
final _that = this;
switch (_that) {
case _AnswerEntryReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AnswerEntryReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _AnswerEntryReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText questionId,  int answerCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AnswerEntryReadItem() when $default != null:
return $default(_that.index,_that.questionId,_that.answerCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText questionId,  int answerCount)  $default,) {final _that = this;
switch (_that) {
case _AnswerEntryReadItem():
return $default(_that.index,_that.questionId,_that.answerCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText questionId,  int answerCount)?  $default,) {final _that = this;
switch (_that) {
case _AnswerEntryReadItem() when $default != null:
return $default(_that.index,_that.questionId,_that.answerCount);case _:
  return null;

}
}

}

/// @nodoc


class _AnswerEntryReadItem implements AnswerEntryReadItem {
  const _AnswerEntryReadItem({required this.index, required this.questionId, required this.answerCount});


@override final  int index;
@override final  ReadText questionId;
@override final  int answerCount;

/// Create a copy of AnswerEntryReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnswerEntryReadItemCopyWith<_AnswerEntryReadItem> get copyWith => __$AnswerEntryReadItemCopyWithImpl<_AnswerEntryReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AnswerEntryReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.questionId, questionId) || other.questionId == questionId)&&(identical(other.answerCount, answerCount) || other.answerCount == answerCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,questionId,answerCount);
}



}

/// @nodoc
abstract mixin class _$AnswerEntryReadItemCopyWith<$Res> implements $AnswerEntryReadItemCopyWith<$Res> {
  factory _$AnswerEntryReadItemCopyWith(_AnswerEntryReadItem value, $Res Function(_AnswerEntryReadItem) _then) = __$AnswerEntryReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText questionId, int answerCount
});


@override $ReadTextCopyWith<$Res> get questionId;

}
/// @nodoc
class __$AnswerEntryReadItemCopyWithImpl<$Res>
    implements _$AnswerEntryReadItemCopyWith<$Res> {
  __$AnswerEntryReadItemCopyWithImpl(this._self, this._then);

  final _AnswerEntryReadItem _self;
  final $Res Function(_AnswerEntryReadItem) _then;

/// Create a copy of AnswerEntryReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? questionId = null,Object? answerCount = null,}) {
  return _then(_AnswerEntryReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as ReadText,answerCount: null == answerCount ? _self.answerCount : answerCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AnswerEntryReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get questionId {

  return $ReadTextCopyWith<$Res>(_self.questionId, (value) {
    return _then(_self.copyWith(questionId: value));
  });
}
}

/// @nodoc
mixin _$AnswerValueReadItem {

 int get index; ReadText get value;
/// Create a copy of AnswerValueReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerValueReadItemCopyWith<AnswerValueReadItem> get copyWith => _$AnswerValueReadItemCopyWithImpl<AnswerValueReadItem>(this as AnswerValueReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AnswerValueReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerValueReadItem&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as AnswerValueReadItem;
  return Object.hash(runtimeType,_this.index,_this.value);
}



}

/// @nodoc
abstract mixin class $AnswerValueReadItemCopyWith<$Res>  {
  factory $AnswerValueReadItemCopyWith(AnswerValueReadItem value, $Res Function(AnswerValueReadItem) _then) = _$AnswerValueReadItemCopyWithImpl;
@useResult
$Res call({
 int index, ReadText value
});


$ReadTextCopyWith<$Res> get value;

}
/// @nodoc
class _$AnswerValueReadItemCopyWithImpl<$Res>
    implements $AnswerValueReadItemCopyWith<$Res> {
  _$AnswerValueReadItemCopyWithImpl(this._self, this._then);

  final AnswerValueReadItem _self;
  final $Res Function(AnswerValueReadItem) _then;

/// Create a copy of AnswerValueReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? index = null,Object? value = null,}) {
  return _then(AnswerValueReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of AnswerValueReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get value {

  return $ReadTextCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [AnswerValueReadItem].
extension AnswerValueReadItemPatterns on AnswerValueReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AnswerValueReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AnswerValueReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AnswerValueReadItem value)  $default,){
final _that = this;
switch (_that) {
case _AnswerValueReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AnswerValueReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _AnswerValueReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int index,  ReadText value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AnswerValueReadItem() when $default != null:
return $default(_that.index,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int index,  ReadText value)  $default,) {final _that = this;
switch (_that) {
case _AnswerValueReadItem():
return $default(_that.index,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int index,  ReadText value)?  $default,) {final _that = this;
switch (_that) {
case _AnswerValueReadItem() when $default != null:
return $default(_that.index,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _AnswerValueReadItem implements AnswerValueReadItem {
  const _AnswerValueReadItem({required this.index, required this.value});


@override final  int index;
@override final  ReadText value;

/// Create a copy of AnswerValueReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AnswerValueReadItemCopyWith<_AnswerValueReadItem> get copyWith => __$AnswerValueReadItemCopyWithImpl<_AnswerValueReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AnswerValueReadItem&&(identical(other.index, index) || other.index == index)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,index,value);
}



}

/// @nodoc
abstract mixin class _$AnswerValueReadItemCopyWith<$Res> implements $AnswerValueReadItemCopyWith<$Res> {
  factory _$AnswerValueReadItemCopyWith(_AnswerValueReadItem value, $Res Function(_AnswerValueReadItem) _then) = __$AnswerValueReadItemCopyWithImpl;
@override @useResult
$Res call({
 int index, ReadText value
});


@override $ReadTextCopyWith<$Res> get value;

}
/// @nodoc
class __$AnswerValueReadItemCopyWithImpl<$Res>
    implements _$AnswerValueReadItemCopyWith<$Res> {
  __$AnswerValueReadItemCopyWithImpl(this._self, this._then);

  final _AnswerValueReadItem _self;
  final $Res Function(_AnswerValueReadItem) _then;

/// Create a copy of AnswerValueReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? index = null,Object? value = null,}) {
  return _then(_AnswerValueReadItem(
index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of AnswerValueReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get value {

  return $ReadTextCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$QuestionPage {


/// Create a copy of QuestionPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionPageCopyWith<QuestionPage> get copyWith => _$QuestionPageCopyWithImpl<QuestionPage>(this as QuestionPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuestionPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuestionPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as QuestionPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $QuestionPageCopyWith<$Res>  {
  factory $QuestionPageCopyWith(QuestionPage value, $Res Function(QuestionPage) _then) = _$QuestionPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<QuestionReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$QuestionPageCopyWithImpl<$Res>
    implements $QuestionPageCopyWith<$Res> {
  _$QuestionPageCopyWithImpl(this._self, this._then);

  final QuestionPage _self;
  final $Res Function(QuestionPage) _then;

/// Create a copy of QuestionPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(QuestionPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<QuestionReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of QuestionPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuestionPage].
extension QuestionPagePatterns on QuestionPage {
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
mixin _$OptionPage {


/// Create a copy of OptionPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OptionPageCopyWith<OptionPage> get copyWith => _$OptionPageCopyWithImpl<OptionPage>(this as OptionPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as OptionPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OptionPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as OptionPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $OptionPageCopyWith<$Res>  {
  factory $OptionPageCopyWith(OptionPage value, $Res Function(OptionPage) _then) = _$OptionPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<OptionReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$OptionPageCopyWithImpl<$Res>
    implements $OptionPageCopyWith<$Res> {
  _$OptionPageCopyWithImpl(this._self, this._then);

  final OptionPage _self;
  final $Res Function(OptionPage) _then;

/// Create a copy of OptionPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(OptionPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<OptionReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of OptionPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [OptionPage].
extension OptionPagePatterns on OptionPage {
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
mixin _$AnswerEntryPage {


/// Create a copy of AnswerEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerEntryPageCopyWith<AnswerEntryPage> get copyWith => _$AnswerEntryPageCopyWithImpl<AnswerEntryPage>(this as AnswerEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AnswerEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerEntryPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as AnswerEntryPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $AnswerEntryPageCopyWith<$Res>  {
  factory $AnswerEntryPageCopyWith(AnswerEntryPage value, $Res Function(AnswerEntryPage) _then) = _$AnswerEntryPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<AnswerEntryReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$AnswerEntryPageCopyWithImpl<$Res>
    implements $AnswerEntryPageCopyWith<$Res> {
  _$AnswerEntryPageCopyWithImpl(this._self, this._then);

  final AnswerEntryPage _self;
  final $Res Function(AnswerEntryPage) _then;

/// Create a copy of AnswerEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(AnswerEntryPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<AnswerEntryReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of AnswerEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [AnswerEntryPage].
extension AnswerEntryPagePatterns on AnswerEntryPage {
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
mixin _$AnswerValuePage {


/// Create a copy of AnswerValuePage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AnswerValuePageCopyWith<AnswerValuePage> get copyWith => _$AnswerValuePageCopyWithImpl<AnswerValuePage>(this as AnswerValuePage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AnswerValuePage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AnswerValuePage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as AnswerValuePage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $AnswerValuePageCopyWith<$Res>  {
  factory $AnswerValuePageCopyWith(AnswerValuePage value, $Res Function(AnswerValuePage) _then) = _$AnswerValuePageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<AnswerValueReadItem> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$AnswerValuePageCopyWithImpl<$Res>
    implements $AnswerValuePageCopyWith<$Res> {
  _$AnswerValuePageCopyWithImpl(this._self, this._then);

  final AnswerValuePage _self;
  final $Res Function(AnswerValuePage) _then;

/// Create a copy of AnswerValuePage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(AnswerValuePage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<AnswerValueReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of AnswerValuePage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [AnswerValuePage].
extension AnswerValuePagePatterns on AnswerValuePage {
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
mixin _$InteractionIndexReadHeader {

 ReadScopeIdentity get scope; int get total; int get pending;
/// Create a copy of InteractionIndexReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionIndexReadHeaderCopyWith<InteractionIndexReadHeader> get copyWith => _$InteractionIndexReadHeaderCopyWithImpl<InteractionIndexReadHeader>(this as InteractionIndexReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionIndexReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionIndexReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.pending, _this.pending) || other.pending == _this.pending));
}


@override
int get hashCode {
  final _this = this as InteractionIndexReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.total,_this.pending);
}

@override
String toString() {
  final _this = this as InteractionIndexReadHeader;
  return 'InteractionIndexReadHeader(scope: ${_this.scope}, total: ${_this.total}, pending: ${_this.pending})';
}


}

/// @nodoc
abstract mixin class $InteractionIndexReadHeaderCopyWith<$Res>  {
  factory $InteractionIndexReadHeaderCopyWith(InteractionIndexReadHeader value, $Res Function(InteractionIndexReadHeader) _then) = _$InteractionIndexReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int total, int pending
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$InteractionIndexReadHeaderCopyWithImpl<$Res>
    implements $InteractionIndexReadHeaderCopyWith<$Res> {
  _$InteractionIndexReadHeaderCopyWithImpl(this._self, this._then);

  final InteractionIndexReadHeader _self;
  final $Res Function(InteractionIndexReadHeader) _then;

/// Create a copy of InteractionIndexReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? total = null,Object? pending = null,}) {
  return _then(InteractionIndexReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of InteractionIndexReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionIndexReadHeader].
extension InteractionIndexReadHeaderPatterns on InteractionIndexReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionIndexReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionIndexReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionIndexReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionIndexReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int total,  int pending)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionIndexReadHeader() when $default != null:
return $default(_that.scope,_that.total,_that.pending);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadScopeIdentity scope,  int total,  int pending)  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexReadHeader():
return $default(_that.scope,_that.total,_that.pending);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadScopeIdentity scope,  int total,  int pending)?  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexReadHeader() when $default != null:
return $default(_that.scope,_that.total,_that.pending);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionIndexReadHeader implements InteractionIndexReadHeader {
  const _InteractionIndexReadHeader({required this.scope, required this.total, required this.pending});


@override final  ReadScopeIdentity scope;
@override final  int total;
@override final  int pending;

/// Create a copy of InteractionIndexReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionIndexReadHeaderCopyWith<_InteractionIndexReadHeader> get copyWith => __$InteractionIndexReadHeaderCopyWithImpl<_InteractionIndexReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionIndexReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.total, total) || other.total == total)&&(identical(other.pending, pending) || other.pending == pending));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,total,pending);
}

@override
String toString() {
    return 'InteractionIndexReadHeader(scope: $scope, total: $total, pending: $pending)';
}


}

/// @nodoc
abstract mixin class _$InteractionIndexReadHeaderCopyWith<$Res> implements $InteractionIndexReadHeaderCopyWith<$Res> {
  factory _$InteractionIndexReadHeaderCopyWith(_InteractionIndexReadHeader value, $Res Function(_InteractionIndexReadHeader) _then) = __$InteractionIndexReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadScopeIdentity scope, int total, int pending
});


@override $ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class __$InteractionIndexReadHeaderCopyWithImpl<$Res>
    implements _$InteractionIndexReadHeaderCopyWith<$Res> {
  __$InteractionIndexReadHeaderCopyWithImpl(this._self, this._then);

  final _InteractionIndexReadHeader _self;
  final $Res Function(_InteractionIndexReadHeader) _then;

/// Create a copy of InteractionIndexReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? total = null,Object? pending = null,}) {
  return _then(_InteractionIndexReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of InteractionIndexReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}

/// @nodoc
mixin _$InteractionBriefPage {


/// Create a copy of InteractionBriefPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionBriefPageCopyWith<InteractionBriefPage> get copyWith => _$InteractionBriefPageCopyWithImpl<InteractionBriefPage>(this as InteractionBriefPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionBriefPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionBriefPage&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as InteractionBriefPage;
  return Object.hash(runtimeType,_this.scope,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as InteractionBriefPage;
  return 'InteractionBriefPage(scope: ${_this.scope}, offset: ${_this.offset}, total: ${_this.total}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $InteractionBriefPageCopyWith<$Res>  {
  factory $InteractionBriefPageCopyWith(InteractionBriefPage value, $Res Function(InteractionBriefPage) _then) = _$InteractionBriefPageCopyWithImpl;
@useResult
$Res call({
 ReadScopeIdentity scope, int offset, int total, List<InteractionBrief> items, int? nextOffset
});


$ReadScopeIdentityCopyWith<$Res> get scope;

}
/// @nodoc
class _$InteractionBriefPageCopyWithImpl<$Res>
    implements $InteractionBriefPageCopyWith<$Res> {
  _$InteractionBriefPageCopyWithImpl(this._self, this._then);

  final InteractionBriefPage _self;
  final $Res Function(InteractionBriefPage) _then;

/// Create a copy of InteractionBriefPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(InteractionBriefPage(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<InteractionBrief>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of InteractionBriefPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res> get scope {

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionBriefPage].
extension InteractionBriefPagePatterns on InteractionBriefPage {
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
mixin _$UserInputAnswerCommand {


/// Create a copy of UserInputAnswerCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserInputAnswerCommandCopyWith<UserInputAnswerCommand> get copyWith => _$UserInputAnswerCommandCopyWithImpl<UserInputAnswerCommand>(this as UserInputAnswerCommand, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UserInputAnswerCommand;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserInputAnswerCommand&&(identical(other.questionId, _this.questionId) || other.questionId == _this.questionId)&&const DeepCollectionEquality().equals(other.answers, _this.answers));
}


@override
int get hashCode {
  final _this = this as UserInputAnswerCommand;
  return Object.hash(runtimeType,_this.questionId,const DeepCollectionEquality().hash(_this.answers));
}



}

/// @nodoc
abstract mixin class $UserInputAnswerCommandCopyWith<$Res>  {
  factory $UserInputAnswerCommandCopyWith(UserInputAnswerCommand value, $Res Function(UserInputAnswerCommand) _then) = _$UserInputAnswerCommandCopyWithImpl;
@useResult
$Res call({
 String questionId, List<String> answers
});




}
/// @nodoc
class _$UserInputAnswerCommandCopyWithImpl<$Res>
    implements $UserInputAnswerCommandCopyWith<$Res> {
  _$UserInputAnswerCommandCopyWithImpl(this._self, this._then);

  final UserInputAnswerCommand _self;
  final $Res Function(UserInputAnswerCommand) _then;

/// Create a copy of UserInputAnswerCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? questionId = null,Object? answers = null,}) {
  return _then(UserInputAnswerCommand(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,answers: null == answers ? _self.answers : answers // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [UserInputAnswerCommand].
extension UserInputAnswerCommandPatterns on UserInputAnswerCommand {
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
mixin _$InteractionResolutionCommand {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionResolutionCommand);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $InteractionResolutionCommandCopyWith<$Res>  {
$InteractionResolutionCommandCopyWith(InteractionResolutionCommand _, $Res Function(InteractionResolutionCommand) __);
}


/// Adds pattern-matching-related methods to [InteractionResolutionCommand].
extension InteractionResolutionCommandPatterns on InteractionResolutionCommand {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UserInputResolutionCommand value)?  userInput,TResult Function( ToolApprovalResolutionCommand value)?  toolApproval,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UserInputResolutionCommand() when userInput != null:
return userInput(_that);case ToolApprovalResolutionCommand() when toolApproval != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UserInputResolutionCommand value)  userInput,required TResult Function( ToolApprovalResolutionCommand value)  toolApproval,}){
final _that = this;
switch (_that) {
case UserInputResolutionCommand():
return userInput(_that);case ToolApprovalResolutionCommand():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UserInputResolutionCommand value)?  userInput,TResult? Function( ToolApprovalResolutionCommand value)?  toolApproval,}){
final _that = this;
switch (_that) {
case UserInputResolutionCommand() when userInput != null:
return userInput(_that);case ToolApprovalResolutionCommand() when toolApproval != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<UserInputAnswerCommand> answers)?  userInput,TResult Function( ToolApprovalDecision decision,  String? reason)?  toolApproval,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UserInputResolutionCommand() when userInput != null:
return userInput(_that.answers);case ToolApprovalResolutionCommand() when toolApproval != null:
return toolApproval(_that.decision,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<UserInputAnswerCommand> answers)  userInput,required TResult Function( ToolApprovalDecision decision,  String? reason)  toolApproval,}) {final _that = this;
switch (_that) {
case UserInputResolutionCommand():
return userInput(_that.answers);case ToolApprovalResolutionCommand():
return toolApproval(_that.decision,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<UserInputAnswerCommand> answers)?  userInput,TResult? Function( ToolApprovalDecision decision,  String? reason)?  toolApproval,}) {final _that = this;
switch (_that) {
case UserInputResolutionCommand() when userInput != null:
return userInput(_that.answers);case ToolApprovalResolutionCommand() when toolApproval != null:
return toolApproval(_that.decision,_that.reason);case _:
  return null;

}
}

}


/// @nodoc


class ToolApprovalResolutionCommand extends InteractionResolutionCommand {
  const ToolApprovalResolutionCommand({required this.decision, required this.reason}): super._();


 final  ToolApprovalDecision decision;
 final  String? reason;

/// Create a copy of InteractionResolutionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ToolApprovalResolutionCommandCopyWith<ToolApprovalResolutionCommand> get copyWith => _$ToolApprovalResolutionCommandCopyWithImpl<ToolApprovalResolutionCommand>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ToolApprovalResolutionCommand&&(identical(other.decision, decision) || other.decision == decision)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,decision,reason);
}



}

/// @nodoc
abstract mixin class $ToolApprovalResolutionCommandCopyWith<$Res> implements $InteractionResolutionCommandCopyWith<$Res> {
  factory $ToolApprovalResolutionCommandCopyWith(ToolApprovalResolutionCommand value, $Res Function(ToolApprovalResolutionCommand) _then) = _$ToolApprovalResolutionCommandCopyWithImpl;
@useResult
$Res call({
 ToolApprovalDecision decision, String? reason
});




}
/// @nodoc
class _$ToolApprovalResolutionCommandCopyWithImpl<$Res>
    implements $ToolApprovalResolutionCommandCopyWith<$Res> {
  _$ToolApprovalResolutionCommandCopyWithImpl(this._self, this._then);

  final ToolApprovalResolutionCommand _self;
  final $Res Function(ToolApprovalResolutionCommand) _then;

/// Create a copy of InteractionResolutionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? decision = null,Object? reason = freezed,}) {
  return _then(ToolApprovalResolutionCommand(
decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as ToolApprovalDecision,reason: freezed == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$UserInputResolutionCommand {


/// Create a copy of UserInputResolutionCommand
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserInputResolutionCommandCopyWith<UserInputResolutionCommand> get copyWith => _$UserInputResolutionCommandCopyWithImpl<UserInputResolutionCommand>(this as UserInputResolutionCommand, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UserInputResolutionCommand;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserInputResolutionCommand&&const DeepCollectionEquality().equals(other.answers, _this.answers));
}


@override
int get hashCode {
  final _this = this as UserInputResolutionCommand;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.answers));
}



}

/// @nodoc
abstract mixin class $UserInputResolutionCommandCopyWith<$Res> implements $InteractionResolutionCommandCopyWith<$Res> {
  factory $UserInputResolutionCommandCopyWith(UserInputResolutionCommand value, $Res Function(UserInputResolutionCommand) _then) = _$UserInputResolutionCommandCopyWithImpl;
@useResult
$Res call({
 List<UserInputAnswerCommand> answers
});




}
/// @nodoc
class _$UserInputResolutionCommandCopyWithImpl<$Res>
    implements $UserInputResolutionCommandCopyWith<$Res> {
  _$UserInputResolutionCommandCopyWithImpl(this._self, this._then);

  final UserInputResolutionCommand _self;
  final $Res Function(UserInputResolutionCommand) _then;

/// Create a copy of UserInputResolutionCommand
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? answers = null,}) {
  return _then(UserInputResolutionCommand(
answers: null == answers ? _self.answers : answers // ignore: cast_nullable_to_non_nullable
as List<UserInputAnswerCommand>,
  ));
}

}


/// Adds pattern-matching-related methods to [UserInputResolutionCommand].
extension UserInputResolutionCommandPatterns on UserInputResolutionCommand {
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
