// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_content_questions.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UserQuestionOptionView {

 String get label; String get description;
/// Create a copy of UserQuestionOptionView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserQuestionOptionViewCopyWith<UserQuestionOptionView> get copyWith => _$UserQuestionOptionViewCopyWithImpl<UserQuestionOptionView>(this as UserQuestionOptionView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UserQuestionOptionView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserQuestionOptionView&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.description, _this.description) || other.description == _this.description));
}


@override
int get hashCode {
  final _this = this as UserQuestionOptionView;
  return Object.hash(runtimeType,_this.label,_this.description);
}



}

/// @nodoc
abstract mixin class $UserQuestionOptionViewCopyWith<$Res>  {
  factory $UserQuestionOptionViewCopyWith(UserQuestionOptionView value, $Res Function(UserQuestionOptionView) _then) = _$UserQuestionOptionViewCopyWithImpl;
@useResult
$Res call({
 String label, String description
});




}
/// @nodoc
class _$UserQuestionOptionViewCopyWithImpl<$Res>
    implements $UserQuestionOptionViewCopyWith<$Res> {
  _$UserQuestionOptionViewCopyWithImpl(this._self, this._then);

  final UserQuestionOptionView _self;
  final $Res Function(UserQuestionOptionView) _then;

/// Create a copy of UserQuestionOptionView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? description = null,}) {
  return _then(UserQuestionOptionView(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [UserQuestionOptionView].
extension UserQuestionOptionViewPatterns on UserQuestionOptionView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UserQuestionOptionView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UserQuestionOptionView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UserQuestionOptionView value)  $default,){
final _that = this;
switch (_that) {
case _UserQuestionOptionView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UserQuestionOptionView value)?  $default,){
final _that = this;
switch (_that) {
case _UserQuestionOptionView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  String description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UserQuestionOptionView() when $default != null:
return $default(_that.label,_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  String description)  $default,) {final _that = this;
switch (_that) {
case _UserQuestionOptionView():
return $default(_that.label,_that.description);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  String description)?  $default,) {final _that = this;
switch (_that) {
case _UserQuestionOptionView() when $default != null:
return $default(_that.label,_that.description);case _:
  return null;

}
}

}

/// @nodoc


class _UserQuestionOptionView implements UserQuestionOptionView {
  const _UserQuestionOptionView({required this.label, required this.description});


@override final  String label;
@override final  String description;

/// Create a copy of UserQuestionOptionView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UserQuestionOptionViewCopyWith<_UserQuestionOptionView> get copyWith => __$UserQuestionOptionViewCopyWithImpl<_UserQuestionOptionView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UserQuestionOptionView&&(identical(other.label, label) || other.label == label)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,description);
}



}

/// @nodoc
abstract mixin class _$UserQuestionOptionViewCopyWith<$Res> implements $UserQuestionOptionViewCopyWith<$Res> {
  factory _$UserQuestionOptionViewCopyWith(_UserQuestionOptionView value, $Res Function(_UserQuestionOptionView) _then) = __$UserQuestionOptionViewCopyWithImpl;
@override @useResult
$Res call({
 String label, String description
});




}
/// @nodoc
class __$UserQuestionOptionViewCopyWithImpl<$Res>
    implements _$UserQuestionOptionViewCopyWith<$Res> {
  __$UserQuestionOptionViewCopyWithImpl(this._self, this._then);

  final _UserQuestionOptionView _self;
  final $Res Function(_UserQuestionOptionView) _then;

/// Create a copy of UserQuestionOptionView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? description = null,}) {
  return _then(_UserQuestionOptionView(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$UserQuestionView {


/// Create a copy of UserQuestionView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UserQuestionViewCopyWith<UserQuestionView> get copyWith => _$UserQuestionViewCopyWithImpl<UserQuestionView>(this as UserQuestionView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UserQuestionView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UserQuestionView&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.question, _this.question) || other.question == _this.question)&&(identical(other.isOther, _this.isOther) || other.isOther == _this.isOther)&&(identical(other.isSecret, _this.isSecret) || other.isSecret == _this.isSecret)&&const DeepCollectionEquality().equals(other.options, _this.options));
}


@override
int get hashCode {
  final _this = this as UserQuestionView;
  return Object.hash(runtimeType,_this.id,_this.header,_this.question,_this.isOther,_this.isSecret,const DeepCollectionEquality().hash(_this.options));
}



}

/// @nodoc
abstract mixin class $UserQuestionViewCopyWith<$Res>  {
  factory $UserQuestionViewCopyWith(UserQuestionView value, $Res Function(UserQuestionView) _then) = _$UserQuestionViewCopyWithImpl;
@useResult
$Res call({
 String id, String header, String question, bool isOther, bool isSecret, List<UserQuestionOptionView> options
});




}
/// @nodoc
class _$UserQuestionViewCopyWithImpl<$Res>
    implements $UserQuestionViewCopyWith<$Res> {
  _$UserQuestionViewCopyWithImpl(this._self, this._then);

  final UserQuestionView _self;
  final $Res Function(UserQuestionView) _then;

/// Create a copy of UserQuestionView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? header = null,Object? question = null,Object? isOther = null,Object? isSecret = null,Object? options = null,}) {
  return _then(UserQuestionView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as String,question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as String,isOther: null == isOther ? _self.isOther : isOther // ignore: cast_nullable_to_non_nullable
as bool,isSecret: null == isSecret ? _self.isSecret : isSecret // ignore: cast_nullable_to_non_nullable
as bool,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<UserQuestionOptionView>,
  ));
}

}


/// Adds pattern-matching-related methods to [UserQuestionView].
extension UserQuestionViewPatterns on UserQuestionView {
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
mixin _$ThreadUserInputAnswerView {


/// Create a copy of ThreadUserInputAnswerView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadUserInputAnswerViewCopyWith<ThreadUserInputAnswerView> get copyWith => _$ThreadUserInputAnswerViewCopyWithImpl<ThreadUserInputAnswerView>(this as ThreadUserInputAnswerView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadUserInputAnswerView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadUserInputAnswerView&&(identical(other.questionId, _this.questionId) || other.questionId == _this.questionId)&&const DeepCollectionEquality().equals(other.answers, _this.answers)&&(identical(other.redacted, _this.redacted) || other.redacted == _this.redacted));
}


@override
int get hashCode {
  final _this = this as ThreadUserInputAnswerView;
  return Object.hash(runtimeType,_this.questionId,const DeepCollectionEquality().hash(_this.answers),_this.redacted);
}



}

/// @nodoc
abstract mixin class $ThreadUserInputAnswerViewCopyWith<$Res>  {
  factory $ThreadUserInputAnswerViewCopyWith(ThreadUserInputAnswerView value, $Res Function(ThreadUserInputAnswerView) _then) = _$ThreadUserInputAnswerViewCopyWithImpl;
@useResult
$Res call({
 String questionId, List<String> answers, bool redacted
});




}
/// @nodoc
class _$ThreadUserInputAnswerViewCopyWithImpl<$Res>
    implements $ThreadUserInputAnswerViewCopyWith<$Res> {
  _$ThreadUserInputAnswerViewCopyWithImpl(this._self, this._then);

  final ThreadUserInputAnswerView _self;
  final $Res Function(ThreadUserInputAnswerView) _then;

/// Create a copy of ThreadUserInputAnswerView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? questionId = null,Object? answers = null,Object? redacted = null,}) {
  return _then(ThreadUserInputAnswerView(
questionId: null == questionId ? _self.questionId : questionId // ignore: cast_nullable_to_non_nullable
as String,answers: null == answers ? _self.answers : answers // ignore: cast_nullable_to_non_nullable
as List<String>,redacted: null == redacted ? _self.redacted : redacted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadUserInputAnswerView].
extension ThreadUserInputAnswerViewPatterns on ThreadUserInputAnswerView {
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
mixin _$ThreadToolUserInputStateView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolUserInputStateView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadToolUserInputStateViewCopyWith<$Res>  {
$ThreadToolUserInputStateViewCopyWith(ThreadToolUserInputStateView _, $Res Function(ThreadToolUserInputStateView) __);
}


/// Adds pattern-matching-related methods to [ThreadToolUserInputStateView].
extension ThreadToolUserInputStateViewPatterns on ThreadToolUserInputStateView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PendingThreadToolUserInputView value)?  pending,TResult Function( ResolvedThreadToolUserInputView value)?  resolved,TResult Function( CancelledThreadToolUserInputView value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PendingThreadToolUserInputView() when pending != null:
return pending(_that);case ResolvedThreadToolUserInputView() when resolved != null:
return resolved(_that);case CancelledThreadToolUserInputView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PendingThreadToolUserInputView value)  pending,required TResult Function( ResolvedThreadToolUserInputView value)  resolved,required TResult Function( CancelledThreadToolUserInputView value)  cancelled,}){
final _that = this;
switch (_that) {
case PendingThreadToolUserInputView():
return pending(_that);case ResolvedThreadToolUserInputView():
return resolved(_that);case CancelledThreadToolUserInputView():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PendingThreadToolUserInputView value)?  pending,TResult? Function( ResolvedThreadToolUserInputView value)?  resolved,TResult? Function( CancelledThreadToolUserInputView value)?  cancelled,}){
final _that = this;
switch (_that) {
case PendingThreadToolUserInputView() when pending != null:
return pending(_that);case ResolvedThreadToolUserInputView() when resolved != null:
return resolved(_that);case CancelledThreadToolUserInputView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  pending,TResult Function( List<ThreadUserInputAnswerView> answers)?  resolved,TResult Function()?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PendingThreadToolUserInputView() when pending != null:
return pending();case ResolvedThreadToolUserInputView() when resolved != null:
return resolved(_that.answers);case CancelledThreadToolUserInputView() when cancelled != null:
return cancelled();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  pending,required TResult Function( List<ThreadUserInputAnswerView> answers)  resolved,required TResult Function()  cancelled,}) {final _that = this;
switch (_that) {
case PendingThreadToolUserInputView():
return pending();case ResolvedThreadToolUserInputView():
return resolved(_that.answers);case CancelledThreadToolUserInputView():
return cancelled();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  pending,TResult? Function( List<ThreadUserInputAnswerView> answers)?  resolved,TResult? Function()?  cancelled,}) {final _that = this;
switch (_that) {
case PendingThreadToolUserInputView() when pending != null:
return pending();case ResolvedThreadToolUserInputView() when resolved != null:
return resolved(_that.answers);case CancelledThreadToolUserInputView() when cancelled != null:
return cancelled();case _:
  return null;

}
}

}

/// @nodoc


class PendingThreadToolUserInputView extends ThreadToolUserInputStateView {
  const PendingThreadToolUserInputView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingThreadToolUserInputView);
}


@override
int get hashCode => runtimeType.hashCode;



}





/// @nodoc


class CancelledThreadToolUserInputView extends ThreadToolUserInputStateView {
  const CancelledThreadToolUserInputView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledThreadToolUserInputView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$ResolvedThreadToolUserInputView {


/// Create a copy of ResolvedThreadToolUserInputView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolvedThreadToolUserInputViewCopyWith<ResolvedThreadToolUserInputView> get copyWith => _$ResolvedThreadToolUserInputViewCopyWithImpl<ResolvedThreadToolUserInputView>(this as ResolvedThreadToolUserInputView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ResolvedThreadToolUserInputView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolvedThreadToolUserInputView&&const DeepCollectionEquality().equals(other.answers, _this.answers));
}


@override
int get hashCode {
  final _this = this as ResolvedThreadToolUserInputView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.answers));
}



}

/// @nodoc
abstract mixin class $ResolvedThreadToolUserInputViewCopyWith<$Res> implements $ThreadToolUserInputStateViewCopyWith<$Res> {
  factory $ResolvedThreadToolUserInputViewCopyWith(ResolvedThreadToolUserInputView value, $Res Function(ResolvedThreadToolUserInputView) _then) = _$ResolvedThreadToolUserInputViewCopyWithImpl;
@useResult
$Res call({
 List<ThreadUserInputAnswerView> answers
});




}
/// @nodoc
class _$ResolvedThreadToolUserInputViewCopyWithImpl<$Res>
    implements $ResolvedThreadToolUserInputViewCopyWith<$Res> {
  _$ResolvedThreadToolUserInputViewCopyWithImpl(this._self, this._then);

  final ResolvedThreadToolUserInputView _self;
  final $Res Function(ResolvedThreadToolUserInputView) _then;

/// Create a copy of ResolvedThreadToolUserInputView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? answers = null,}) {
  return _then(ResolvedThreadToolUserInputView(
null == answers ? _self.answers : answers // ignore: cast_nullable_to_non_nullable
as List<ThreadUserInputAnswerView>,
  ));
}

}


/// Adds pattern-matching-related methods to [ResolvedThreadToolUserInputView].
extension ResolvedThreadToolUserInputViewPatterns on ResolvedThreadToolUserInputView {
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
mixin _$ThreadToolUserInputView {


/// Create a copy of ThreadToolUserInputView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadToolUserInputViewCopyWith<ThreadToolUserInputView> get copyWith => _$ThreadToolUserInputViewCopyWithImpl<ThreadToolUserInputView>(this as ThreadToolUserInputView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadToolUserInputView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolUserInputView&&(identical(other.interactionId, _this.interactionId) || other.interactionId == _this.interactionId)&&const DeepCollectionEquality().equals(other.questions, _this.questions)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as ThreadToolUserInputView;
  return Object.hash(runtimeType,_this.interactionId,const DeepCollectionEquality().hash(_this.questions),_this.state);
}



}

/// @nodoc
abstract mixin class $ThreadToolUserInputViewCopyWith<$Res>  {
  factory $ThreadToolUserInputViewCopyWith(ThreadToolUserInputView value, $Res Function(ThreadToolUserInputView) _then) = _$ThreadToolUserInputViewCopyWithImpl;
@useResult
$Res call({
 String interactionId, List<UserQuestionView> questions, ThreadToolUserInputStateView state
});


$ThreadToolUserInputStateViewCopyWith<$Res> get state;

}
/// @nodoc
class _$ThreadToolUserInputViewCopyWithImpl<$Res>
    implements $ThreadToolUserInputViewCopyWith<$Res> {
  _$ThreadToolUserInputViewCopyWithImpl(this._self, this._then);

  final ThreadToolUserInputView _self;
  final $Res Function(ThreadToolUserInputView) _then;

/// Create a copy of ThreadToolUserInputView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? interactionId = null,Object? questions = null,Object? state = null,}) {
  return _then(ThreadToolUserInputView(
interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as List<UserQuestionView>,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadToolUserInputStateView,
  ));
}
/// Create a copy of ThreadToolUserInputView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolUserInputStateViewCopyWith<$Res> get state {

  return $ThreadToolUserInputStateViewCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadToolUserInputView].
extension ThreadToolUserInputViewPatterns on ThreadToolUserInputView {
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
mixin _$PlanConfirmationReceiptView {


/// Create a copy of PlanConfirmationReceiptView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanConfirmationReceiptViewCopyWith<PlanConfirmationReceiptView> get copyWith => _$PlanConfirmationReceiptViewCopyWithImpl<PlanConfirmationReceiptView>(this as PlanConfirmationReceiptView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PlanConfirmationReceiptView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanConfirmationReceiptView&&(identical(other.interactionId, _this.interactionId) || other.interactionId == _this.interactionId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.decision, _this.decision) || other.decision == _this.decision)&&const DeepCollectionEquality().equals(other.feedback, _this.feedback));
}


@override
int get hashCode {
  final _this = this as PlanConfirmationReceiptView;
  return Object.hash(runtimeType,_this.interactionId,_this.title,_this.decision,const DeepCollectionEquality().hash(_this.feedback));
}



}

/// @nodoc
abstract mixin class $PlanConfirmationReceiptViewCopyWith<$Res>  {
  factory $PlanConfirmationReceiptViewCopyWith(PlanConfirmationReceiptView value, $Res Function(PlanConfirmationReceiptView) _then) = _$PlanConfirmationReceiptViewCopyWithImpl;
@useResult
$Res call({
 String interactionId, String title, PlanConfirmationDecisionView decision, Iterable<String> feedback
});




}
/// @nodoc
class _$PlanConfirmationReceiptViewCopyWithImpl<$Res>
    implements $PlanConfirmationReceiptViewCopyWith<$Res> {
  _$PlanConfirmationReceiptViewCopyWithImpl(this._self, this._then);

  final PlanConfirmationReceiptView _self;
  final $Res Function(PlanConfirmationReceiptView) _then;

/// Create a copy of PlanConfirmationReceiptView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? interactionId = null,Object? title = null,Object? decision = null,Object? feedback = null,}) {
  return _then(PlanConfirmationReceiptView(
interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,decision: null == decision ? _self.decision : decision // ignore: cast_nullable_to_non_nullable
as PlanConfirmationDecisionView,feedback: null == feedback ? _self.feedback! : feedback // ignore: cast_nullable_to_non_nullable
as Iterable<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [PlanConfirmationReceiptView].
extension PlanConfirmationReceiptViewPatterns on PlanConfirmationReceiptView {
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
