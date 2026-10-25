// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$QuestionReadProgress {

 QuestionReadItem get question; List<OptionReadItem> get options; int? get nextOptionOffset; bool get optionsLoading; StudioFailure? get optionsError;
/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionReadProgressCopyWith<QuestionReadProgress> get copyWith => _$QuestionReadProgressCopyWithImpl<QuestionReadProgress>(this as QuestionReadProgress, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuestionReadProgress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuestionReadProgress&&(identical(other.question, _this.question) || other.question == _this.question)&&const DeepCollectionEquality().equals(other.options, _this.options)&&(identical(other.nextOptionOffset, _this.nextOptionOffset) || other.nextOptionOffset == _this.nextOptionOffset)&&(identical(other.optionsLoading, _this.optionsLoading) || other.optionsLoading == _this.optionsLoading)&&(identical(other.optionsError, _this.optionsError) || other.optionsError == _this.optionsError));
}


@override
int get hashCode {
  final _this = this as QuestionReadProgress;
  return Object.hash(runtimeType,_this.question,const DeepCollectionEquality().hash(_this.options),_this.nextOptionOffset,_this.optionsLoading,_this.optionsError);
}



}

/// @nodoc
abstract mixin class $QuestionReadProgressCopyWith<$Res>  {
  factory $QuestionReadProgressCopyWith(QuestionReadProgress value, $Res Function(QuestionReadProgress) _then) = _$QuestionReadProgressCopyWithImpl;
@useResult
$Res call({
 QuestionReadItem question, List<OptionReadItem> options, int? nextOptionOffset, bool optionsLoading, StudioFailure? optionsError
});


$QuestionReadItemCopyWith<$Res> get question;$StudioFailureCopyWith<$Res>? get optionsError;

}
/// @nodoc
class _$QuestionReadProgressCopyWithImpl<$Res>
    implements $QuestionReadProgressCopyWith<$Res> {
  _$QuestionReadProgressCopyWithImpl(this._self, this._then);

  final QuestionReadProgress _self;
  final $Res Function(QuestionReadProgress) _then;

/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? question = null,Object? options = null,Object? nextOptionOffset = freezed,Object? optionsLoading = null,Object? optionsError = freezed,}) {
  return _then(QuestionReadProgress(
question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as QuestionReadItem,options: null == options ? _self.options : options // ignore: cast_nullable_to_non_nullable
as List<OptionReadItem>,nextOptionOffset: freezed == nextOptionOffset ? _self.nextOptionOffset : nextOptionOffset // ignore: cast_nullable_to_non_nullable
as int?,optionsLoading: null == optionsLoading ? _self.optionsLoading : optionsLoading // ignore: cast_nullable_to_non_nullable
as bool,optionsError: freezed == optionsError ? _self.optionsError : optionsError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuestionReadItemCopyWith<$Res> get question {

  return $QuestionReadItemCopyWith<$Res>(_self.question, (value) {
    return _then(_self.copyWith(question: value));
  });
}/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get optionsError {
    if (_self.optionsError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.optionsError!, (value) {
    return _then(_self.copyWith(optionsError: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuestionReadProgress].
extension QuestionReadProgressPatterns on QuestionReadProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuestionReadProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuestionReadProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuestionReadProgress value)  $default,){
final _that = this;
switch (_that) {
case _QuestionReadProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuestionReadProgress value)?  $default,){
final _that = this;
switch (_that) {
case _QuestionReadProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( QuestionReadItem question,  List<OptionReadItem> options,  int? nextOptionOffset,  bool optionsLoading,  StudioFailure? optionsError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuestionReadProgress() when $default != null:
return $default(_that.question,_that.options,_that.nextOptionOffset,_that.optionsLoading,_that.optionsError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( QuestionReadItem question,  List<OptionReadItem> options,  int? nextOptionOffset,  bool optionsLoading,  StudioFailure? optionsError)  $default,) {final _that = this;
switch (_that) {
case _QuestionReadProgress():
return $default(_that.question,_that.options,_that.nextOptionOffset,_that.optionsLoading,_that.optionsError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( QuestionReadItem question,  List<OptionReadItem> options,  int? nextOptionOffset,  bool optionsLoading,  StudioFailure? optionsError)?  $default,) {final _that = this;
switch (_that) {
case _QuestionReadProgress() when $default != null:
return $default(_that.question,_that.options,_that.nextOptionOffset,_that.optionsLoading,_that.optionsError);case _:
  return null;

}
}

}

/// @nodoc


class _QuestionReadProgress implements QuestionReadProgress {
  const _QuestionReadProgress({required this.question,  List<OptionReadItem> options = const [], this.nextOptionOffset, this.optionsLoading = false, this.optionsError}): _options = options;


@override final  QuestionReadItem question;
 final  List<OptionReadItem> _options;
@override@JsonKey() List<OptionReadItem> get options {
  if (_options is EqualUnmodifiableListView) return _options;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_options);
}

@override final  int? nextOptionOffset;
@override@JsonKey() final  bool optionsLoading;
@override final  StudioFailure? optionsError;

/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuestionReadProgressCopyWith<_QuestionReadProgress> get copyWith => __$QuestionReadProgressCopyWithImpl<_QuestionReadProgress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuestionReadProgress&&(identical(other.question, question) || other.question == question)&&const DeepCollectionEquality().equals(other.options, _options)&&(identical(other.nextOptionOffset, nextOptionOffset) || other.nextOptionOffset == nextOptionOffset)&&(identical(other.optionsLoading, optionsLoading) || other.optionsLoading == optionsLoading)&&(identical(other.optionsError, optionsError) || other.optionsError == optionsError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,question,const DeepCollectionEquality().hash(_options),nextOptionOffset,optionsLoading,optionsError);
}



}

/// @nodoc
abstract mixin class _$QuestionReadProgressCopyWith<$Res> implements $QuestionReadProgressCopyWith<$Res> {
  factory _$QuestionReadProgressCopyWith(_QuestionReadProgress value, $Res Function(_QuestionReadProgress) _then) = __$QuestionReadProgressCopyWithImpl;
@override @useResult
$Res call({
 QuestionReadItem question, List<OptionReadItem> options, int? nextOptionOffset, bool optionsLoading, StudioFailure? optionsError
});


@override $QuestionReadItemCopyWith<$Res> get question;@override $StudioFailureCopyWith<$Res>? get optionsError;

}
/// @nodoc
class __$QuestionReadProgressCopyWithImpl<$Res>
    implements _$QuestionReadProgressCopyWith<$Res> {
  __$QuestionReadProgressCopyWithImpl(this._self, this._then);

  final _QuestionReadProgress _self;
  final $Res Function(_QuestionReadProgress) _then;

/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? question = null,Object? options = null,Object? nextOptionOffset = freezed,Object? optionsLoading = null,Object? optionsError = freezed,}) {
  return _then(_QuestionReadProgress(
question: null == question ? _self.question : question // ignore: cast_nullable_to_non_nullable
as QuestionReadItem,options: null == options ? _self._options : options // ignore: cast_nullable_to_non_nullable
as List<OptionReadItem>,nextOptionOffset: freezed == nextOptionOffset ? _self.nextOptionOffset : nextOptionOffset // ignore: cast_nullable_to_non_nullable
as int?,optionsLoading: null == optionsLoading ? _self.optionsLoading : optionsLoading // ignore: cast_nullable_to_non_nullable
as bool,optionsError: freezed == optionsError ? _self.optionsError : optionsError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuestionReadItemCopyWith<$Res> get question {

  return $QuestionReadItemCopyWith<$Res>(_self.question, (value) {
    return _then(_self.copyWith(question: value));
  });
}/// Create a copy of QuestionReadProgress
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get optionsError {
    if (_self.optionsError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.optionsError!, (value) {
    return _then(_self.copyWith(optionsError: value));
  });
}
}

/// @nodoc
mixin _$QuestionAnswerDraft {

 List<String> get selectedLabels; String get text;
/// Create a copy of QuestionAnswerDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuestionAnswerDraftCopyWith<QuestionAnswerDraft> get copyWith => _$QuestionAnswerDraftCopyWithImpl<QuestionAnswerDraft>(this as QuestionAnswerDraft, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuestionAnswerDraft;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuestionAnswerDraft&&const DeepCollectionEquality().equals(other.selectedLabels, _this.selectedLabels)&&(identical(other.text, _this.text) || other.text == _this.text));
}


@override
int get hashCode {
  final _this = this as QuestionAnswerDraft;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.selectedLabels),_this.text);
}



}

/// @nodoc
abstract mixin class $QuestionAnswerDraftCopyWith<$Res>  {
  factory $QuestionAnswerDraftCopyWith(QuestionAnswerDraft value, $Res Function(QuestionAnswerDraft) _then) = _$QuestionAnswerDraftCopyWithImpl;
@useResult
$Res call({
 List<String> selectedLabels, String text
});




}
/// @nodoc
class _$QuestionAnswerDraftCopyWithImpl<$Res>
    implements $QuestionAnswerDraftCopyWith<$Res> {
  _$QuestionAnswerDraftCopyWithImpl(this._self, this._then);

  final QuestionAnswerDraft _self;
  final $Res Function(QuestionAnswerDraft) _then;

/// Create a copy of QuestionAnswerDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? selectedLabels = null,Object? text = null,}) {
  return _then(QuestionAnswerDraft(
selectedLabels: null == selectedLabels ? _self.selectedLabels : selectedLabels // ignore: cast_nullable_to_non_nullable
as List<String>,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [QuestionAnswerDraft].
extension QuestionAnswerDraftPatterns on QuestionAnswerDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuestionAnswerDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuestionAnswerDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuestionAnswerDraft value)  $default,){
final _that = this;
switch (_that) {
case _QuestionAnswerDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuestionAnswerDraft value)?  $default,){
final _that = this;
switch (_that) {
case _QuestionAnswerDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<String> selectedLabels,  String text)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuestionAnswerDraft() when $default != null:
return $default(_that.selectedLabels,_that.text);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<String> selectedLabels,  String text)  $default,) {final _that = this;
switch (_that) {
case _QuestionAnswerDraft():
return $default(_that.selectedLabels,_that.text);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<String> selectedLabels,  String text)?  $default,) {final _that = this;
switch (_that) {
case _QuestionAnswerDraft() when $default != null:
return $default(_that.selectedLabels,_that.text);case _:
  return null;

}
}

}

/// @nodoc


class _QuestionAnswerDraft implements QuestionAnswerDraft {
  const _QuestionAnswerDraft({ List<String> selectedLabels = const [], this.text = ''}): _selectedLabels = selectedLabels;


 final  List<String> _selectedLabels;
@override@JsonKey() List<String> get selectedLabels {
  if (_selectedLabels is EqualUnmodifiableListView) return _selectedLabels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_selectedLabels);
}

@override@JsonKey() final  String text;

/// Create a copy of QuestionAnswerDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuestionAnswerDraftCopyWith<_QuestionAnswerDraft> get copyWith => __$QuestionAnswerDraftCopyWithImpl<_QuestionAnswerDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuestionAnswerDraft&&const DeepCollectionEquality().equals(other.selectedLabels, _selectedLabels)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_selectedLabels),text);
}



}

/// @nodoc
abstract mixin class _$QuestionAnswerDraftCopyWith<$Res> implements $QuestionAnswerDraftCopyWith<$Res> {
  factory _$QuestionAnswerDraftCopyWith(_QuestionAnswerDraft value, $Res Function(_QuestionAnswerDraft) _then) = __$QuestionAnswerDraftCopyWithImpl;
@override @useResult
$Res call({
 List<String> selectedLabels, String text
});




}
/// @nodoc
class __$QuestionAnswerDraftCopyWithImpl<$Res>
    implements _$QuestionAnswerDraftCopyWith<$Res> {
  __$QuestionAnswerDraftCopyWithImpl(this._self, this._then);

  final _QuestionAnswerDraft _self;
  final $Res Function(_QuestionAnswerDraft) _then;

/// Create a copy of QuestionAnswerDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? selectedLabels = null,Object? text = null,}) {
  return _then(_QuestionAnswerDraft(
selectedLabels: null == selectedLabels ? _self._selectedLabels : selectedLabels // ignore: cast_nullable_to_non_nullable
as List<String>,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$InteractionReadIssue {

 InteractionReadSection get section; int? get index; int? get fieldId; StudioFailure get error;
/// Create a copy of InteractionReadIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionReadIssueCopyWith<InteractionReadIssue> get copyWith => _$InteractionReadIssueCopyWithImpl<InteractionReadIssue>(this as InteractionReadIssue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionReadIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionReadIssue&&(identical(other.section, _this.section) || other.section == _this.section)&&(identical(other.index, _this.index) || other.index == _this.index)&&(identical(other.fieldId, _this.fieldId) || other.fieldId == _this.fieldId)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as InteractionReadIssue;
  return Object.hash(runtimeType,_this.section,_this.index,_this.fieldId,_this.error);
}



}

/// @nodoc
abstract mixin class $InteractionReadIssueCopyWith<$Res>  {
  factory $InteractionReadIssueCopyWith(InteractionReadIssue value, $Res Function(InteractionReadIssue) _then) = _$InteractionReadIssueCopyWithImpl;
@useResult
$Res call({
 InteractionReadSection section, int? index, int? fieldId, StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$InteractionReadIssueCopyWithImpl<$Res>
    implements $InteractionReadIssueCopyWith<$Res> {
  _$InteractionReadIssueCopyWithImpl(this._self, this._then);

  final InteractionReadIssue _self;
  final $Res Function(InteractionReadIssue) _then;

/// Create a copy of InteractionReadIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? section = null,Object? index = freezed,Object? fieldId = freezed,Object? error = null,}) {
  return _then(InteractionReadIssue(
section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as InteractionReadSection,index: freezed == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int?,fieldId: freezed == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as int?,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}
/// Create a copy of InteractionReadIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionReadIssue].
extension InteractionReadIssuePatterns on InteractionReadIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionReadIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionReadIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionReadIssue value)  $default,){
final _that = this;
switch (_that) {
case _InteractionReadIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionReadIssue value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionReadIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InteractionReadSection section,  int? index,  int? fieldId,  StudioFailure error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionReadIssue() when $default != null:
return $default(_that.section,_that.index,_that.fieldId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InteractionReadSection section,  int? index,  int? fieldId,  StudioFailure error)  $default,) {final _that = this;
switch (_that) {
case _InteractionReadIssue():
return $default(_that.section,_that.index,_that.fieldId,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InteractionReadSection section,  int? index,  int? fieldId,  StudioFailure error)?  $default,) {final _that = this;
switch (_that) {
case _InteractionReadIssue() when $default != null:
return $default(_that.section,_that.index,_that.fieldId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionReadIssue implements InteractionReadIssue {
  const _InteractionReadIssue({required this.section, this.index, this.fieldId, required this.error});


@override final  InteractionReadSection section;
@override final  int? index;
@override final  int? fieldId;
@override final  StudioFailure error;

/// Create a copy of InteractionReadIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionReadIssueCopyWith<_InteractionReadIssue> get copyWith => __$InteractionReadIssueCopyWithImpl<_InteractionReadIssue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionReadIssue&&(identical(other.section, section) || other.section == section)&&(identical(other.index, index) || other.index == index)&&(identical(other.fieldId, fieldId) || other.fieldId == fieldId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,section,index,fieldId,error);
}



}

/// @nodoc
abstract mixin class _$InteractionReadIssueCopyWith<$Res> implements $InteractionReadIssueCopyWith<$Res> {
  factory _$InteractionReadIssueCopyWith(_InteractionReadIssue value, $Res Function(_InteractionReadIssue) _then) = __$InteractionReadIssueCopyWithImpl;
@override @useResult
$Res call({
 InteractionReadSection section, int? index, int? fieldId, StudioFailure error
});


@override $StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class __$InteractionReadIssueCopyWithImpl<$Res>
    implements _$InteractionReadIssueCopyWith<$Res> {
  __$InteractionReadIssueCopyWithImpl(this._self, this._then);

  final _InteractionReadIssue _self;
  final $Res Function(_InteractionReadIssue) _then;

/// Create a copy of InteractionReadIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? section = null,Object? index = freezed,Object? fieldId = freezed,Object? error = null,}) {
  return _then(_InteractionReadIssue(
section: null == section ? _self.section : section // ignore: cast_nullable_to_non_nullable
as InteractionReadSection,index: freezed == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as int?,fieldId: freezed == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as int?,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of InteractionReadIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$InteractionViewState {

 InteractionEditorKey get key; ReadScopeIdentity? get scope; InteractionReadHeader? get header; Map<int, QuestionReadProgress> get questions; int? get nextQuestionOffset; List<AnswerEntryReadItem> get answerEntries; int? get nextAnswerEntryOffset; bool get answerEntriesLoading; Map<int, List<AnswerValueReadItem>> get answerValues; Map<int, int?> get nextAnswerValueOffsets; Set<int> get answerValueLoading; Map<int, TextReadProgress> get texts; int get currentQuestionIndex; bool get questionPageLoading; List<InteractionReadIssue> get readIssues; bool get completingRead; Map<int, QuestionAnswerDraft> get answers; String get fallbackText; String get approvalReason; String get planFeedback; bool get enabled; bool get sourceCurrent; bool get closing; int get latestIntent; OperationState? get submission; InteractionSubmitBlock? get submitBlock; StudioFailure? get submissionError;
/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionViewStateCopyWith<InteractionViewState> get copyWith => _$InteractionViewStateCopyWithImpl<InteractionViewState>(this as InteractionViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionViewState&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.header, _this.header) || other.header == _this.header)&&const DeepCollectionEquality().equals(other.questions, _this.questions)&&(identical(other.nextQuestionOffset, _this.nextQuestionOffset) || other.nextQuestionOffset == _this.nextQuestionOffset)&&const DeepCollectionEquality().equals(other.answerEntries, _this.answerEntries)&&(identical(other.nextAnswerEntryOffset, _this.nextAnswerEntryOffset) || other.nextAnswerEntryOffset == _this.nextAnswerEntryOffset)&&(identical(other.answerEntriesLoading, _this.answerEntriesLoading) || other.answerEntriesLoading == _this.answerEntriesLoading)&&const DeepCollectionEquality().equals(other.answerValues, _this.answerValues)&&const DeepCollectionEquality().equals(other.nextAnswerValueOffsets, _this.nextAnswerValueOffsets)&&const DeepCollectionEquality().equals(other.answerValueLoading, _this.answerValueLoading)&&const DeepCollectionEquality().equals(other.texts, _this.texts)&&(identical(other.currentQuestionIndex, _this.currentQuestionIndex) || other.currentQuestionIndex == _this.currentQuestionIndex)&&(identical(other.questionPageLoading, _this.questionPageLoading) || other.questionPageLoading == _this.questionPageLoading)&&const DeepCollectionEquality().equals(other.readIssues, _this.readIssues)&&(identical(other.completingRead, _this.completingRead) || other.completingRead == _this.completingRead)&&const DeepCollectionEquality().equals(other.answers, _this.answers)&&(identical(other.fallbackText, _this.fallbackText) || other.fallbackText == _this.fallbackText)&&(identical(other.approvalReason, _this.approvalReason) || other.approvalReason == _this.approvalReason)&&(identical(other.planFeedback, _this.planFeedback) || other.planFeedback == _this.planFeedback)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.sourceCurrent, _this.sourceCurrent) || other.sourceCurrent == _this.sourceCurrent)&&(identical(other.closing, _this.closing) || other.closing == _this.closing)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.submission, _this.submission) || other.submission == _this.submission)&&(identical(other.submitBlock, _this.submitBlock) || other.submitBlock == _this.submitBlock)&&(identical(other.submissionError, _this.submissionError) || other.submissionError == _this.submissionError));
}


@override
int get hashCode {
  final _this = this as InteractionViewState;
  return Object.hashAll([runtimeType,_this.key,_this.scope,_this.header,const DeepCollectionEquality().hash(_this.questions),_this.nextQuestionOffset,const DeepCollectionEquality().hash(_this.answerEntries),_this.nextAnswerEntryOffset,_this.answerEntriesLoading,const DeepCollectionEquality().hash(_this.answerValues),const DeepCollectionEquality().hash(_this.nextAnswerValueOffsets),const DeepCollectionEquality().hash(_this.answerValueLoading),const DeepCollectionEquality().hash(_this.texts),_this.currentQuestionIndex,_this.questionPageLoading,const DeepCollectionEquality().hash(_this.readIssues),_this.completingRead,const DeepCollectionEquality().hash(_this.answers),_this.fallbackText,_this.approvalReason,_this.planFeedback,_this.enabled,_this.sourceCurrent,_this.closing,_this.latestIntent,_this.submission,_this.submitBlock,_this.submissionError]);
}



}

/// @nodoc
abstract mixin class $InteractionViewStateCopyWith<$Res>  {
  factory $InteractionViewStateCopyWith(InteractionViewState value, $Res Function(InteractionViewState) _then) = _$InteractionViewStateCopyWithImpl;
@useResult
$Res call({
 InteractionEditorKey key, ReadScopeIdentity? scope, InteractionReadHeader? header, Map<int, QuestionReadProgress> questions, int? nextQuestionOffset, List<AnswerEntryReadItem> answerEntries, int? nextAnswerEntryOffset, bool answerEntriesLoading, Map<int, List<AnswerValueReadItem>> answerValues, Map<int, int?> nextAnswerValueOffsets, Set<int> answerValueLoading, Map<int, TextReadProgress> texts, int currentQuestionIndex, bool questionPageLoading, List<InteractionReadIssue> readIssues, bool completingRead, Map<int, QuestionAnswerDraft> answers, String fallbackText, String approvalReason, String planFeedback, bool enabled, bool sourceCurrent, bool closing, int latestIntent, OperationState? submission, InteractionSubmitBlock? submitBlock, StudioFailure? submissionError
});


$InteractionEditorKeyCopyWith<$Res> get key;$ReadScopeIdentityCopyWith<$Res>? get scope;$InteractionReadHeaderCopyWith<$Res>? get header;$OperationStateCopyWith<$Res>? get submission;$StudioFailureCopyWith<$Res>? get submissionError;

}
/// @nodoc
class _$InteractionViewStateCopyWithImpl<$Res>
    implements $InteractionViewStateCopyWith<$Res> {
  _$InteractionViewStateCopyWithImpl(this._self, this._then);

  final InteractionViewState _self;
  final $Res Function(InteractionViewState) _then;

/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? scope = freezed,Object? header = freezed,Object? questions = null,Object? nextQuestionOffset = freezed,Object? answerEntries = null,Object? nextAnswerEntryOffset = freezed,Object? answerEntriesLoading = null,Object? answerValues = null,Object? nextAnswerValueOffsets = null,Object? answerValueLoading = null,Object? texts = null,Object? currentQuestionIndex = null,Object? questionPageLoading = null,Object? readIssues = null,Object? completingRead = null,Object? answers = null,Object? fallbackText = null,Object? approvalReason = null,Object? planFeedback = null,Object? enabled = null,Object? sourceCurrent = null,Object? closing = null,Object? latestIntent = null,Object? submission = freezed,Object? submitBlock = freezed,Object? submissionError = freezed,}) {
  return _then(InteractionViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as InteractionEditorKey,scope: freezed == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as InteractionReadHeader?,questions: null == questions ? _self.questions : questions // ignore: cast_nullable_to_non_nullable
as Map<int, QuestionReadProgress>,nextQuestionOffset: freezed == nextQuestionOffset ? _self.nextQuestionOffset : nextQuestionOffset // ignore: cast_nullable_to_non_nullable
as int?,answerEntries: null == answerEntries ? _self.answerEntries : answerEntries // ignore: cast_nullable_to_non_nullable
as List<AnswerEntryReadItem>,nextAnswerEntryOffset: freezed == nextAnswerEntryOffset ? _self.nextAnswerEntryOffset : nextAnswerEntryOffset // ignore: cast_nullable_to_non_nullable
as int?,answerEntriesLoading: null == answerEntriesLoading ? _self.answerEntriesLoading : answerEntriesLoading // ignore: cast_nullable_to_non_nullable
as bool,answerValues: null == answerValues ? _self.answerValues : answerValues // ignore: cast_nullable_to_non_nullable
as Map<int, List<AnswerValueReadItem>>,nextAnswerValueOffsets: null == nextAnswerValueOffsets ? _self.nextAnswerValueOffsets : nextAnswerValueOffsets // ignore: cast_nullable_to_non_nullable
as Map<int, int?>,answerValueLoading: null == answerValueLoading ? _self.answerValueLoading : answerValueLoading // ignore: cast_nullable_to_non_nullable
as Set<int>,texts: null == texts ? _self.texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,currentQuestionIndex: null == currentQuestionIndex ? _self.currentQuestionIndex : currentQuestionIndex // ignore: cast_nullable_to_non_nullable
as int,questionPageLoading: null == questionPageLoading ? _self.questionPageLoading : questionPageLoading // ignore: cast_nullable_to_non_nullable
as bool,readIssues: null == readIssues ? _self.readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as List<InteractionReadIssue>,completingRead: null == completingRead ? _self.completingRead : completingRead // ignore: cast_nullable_to_non_nullable
as bool,answers: null == answers ? _self.answers : answers // ignore: cast_nullable_to_non_nullable
as Map<int, QuestionAnswerDraft>,fallbackText: null == fallbackText ? _self.fallbackText : fallbackText // ignore: cast_nullable_to_non_nullable
as String,approvalReason: null == approvalReason ? _self.approvalReason : approvalReason // ignore: cast_nullable_to_non_nullable
as String,planFeedback: null == planFeedback ? _self.planFeedback : planFeedback // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,sourceCurrent: null == sourceCurrent ? _self.sourceCurrent : sourceCurrent // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,submission: freezed == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as OperationState?,submitBlock: freezed == submitBlock ? _self.submitBlock : submitBlock // ignore: cast_nullable_to_non_nullable
as InteractionSubmitBlock?,submissionError: freezed == submissionError ? _self.submissionError : submissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionEditorKeyCopyWith<$Res> get key {

  return $InteractionEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res>? get scope {
    if (_self.scope == null) {
    return null;
  }

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope!, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionReadHeaderCopyWith<$Res>? get header {
    if (_self.header == null) {
    return null;
  }

  return $InteractionReadHeaderCopyWith<$Res>(_self.header!, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get submission {
    if (_self.submission == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.submission!, (value) {
    return _then(_self.copyWith(submission: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get submissionError {
    if (_self.submissionError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.submissionError!, (value) {
    return _then(_self.copyWith(submissionError: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionViewState].
extension InteractionViewStatePatterns on InteractionViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionViewState value)  $default,){
final _that = this;
switch (_that) {
case _InteractionViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionViewState value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InteractionEditorKey key,  ReadScopeIdentity? scope,  InteractionReadHeader? header,  Map<int, QuestionReadProgress> questions,  int? nextQuestionOffset,  List<AnswerEntryReadItem> answerEntries,  int? nextAnswerEntryOffset,  bool answerEntriesLoading,  Map<int, List<AnswerValueReadItem>> answerValues,  Map<int, int?> nextAnswerValueOffsets,  Set<int> answerValueLoading,  Map<int, TextReadProgress> texts,  int currentQuestionIndex,  bool questionPageLoading,  List<InteractionReadIssue> readIssues,  bool completingRead,  Map<int, QuestionAnswerDraft> answers,  String fallbackText,  String approvalReason,  String planFeedback,  bool enabled,  bool sourceCurrent,  bool closing,  int latestIntent,  OperationState? submission,  InteractionSubmitBlock? submitBlock,  StudioFailure? submissionError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionViewState() when $default != null:
return $default(_that.key,_that.scope,_that.header,_that.questions,_that.nextQuestionOffset,_that.answerEntries,_that.nextAnswerEntryOffset,_that.answerEntriesLoading,_that.answerValues,_that.nextAnswerValueOffsets,_that.answerValueLoading,_that.texts,_that.currentQuestionIndex,_that.questionPageLoading,_that.readIssues,_that.completingRead,_that.answers,_that.fallbackText,_that.approvalReason,_that.planFeedback,_that.enabled,_that.sourceCurrent,_that.closing,_that.latestIntent,_that.submission,_that.submitBlock,_that.submissionError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InteractionEditorKey key,  ReadScopeIdentity? scope,  InteractionReadHeader? header,  Map<int, QuestionReadProgress> questions,  int? nextQuestionOffset,  List<AnswerEntryReadItem> answerEntries,  int? nextAnswerEntryOffset,  bool answerEntriesLoading,  Map<int, List<AnswerValueReadItem>> answerValues,  Map<int, int?> nextAnswerValueOffsets,  Set<int> answerValueLoading,  Map<int, TextReadProgress> texts,  int currentQuestionIndex,  bool questionPageLoading,  List<InteractionReadIssue> readIssues,  bool completingRead,  Map<int, QuestionAnswerDraft> answers,  String fallbackText,  String approvalReason,  String planFeedback,  bool enabled,  bool sourceCurrent,  bool closing,  int latestIntent,  OperationState? submission,  InteractionSubmitBlock? submitBlock,  StudioFailure? submissionError)  $default,) {final _that = this;
switch (_that) {
case _InteractionViewState():
return $default(_that.key,_that.scope,_that.header,_that.questions,_that.nextQuestionOffset,_that.answerEntries,_that.nextAnswerEntryOffset,_that.answerEntriesLoading,_that.answerValues,_that.nextAnswerValueOffsets,_that.answerValueLoading,_that.texts,_that.currentQuestionIndex,_that.questionPageLoading,_that.readIssues,_that.completingRead,_that.answers,_that.fallbackText,_that.approvalReason,_that.planFeedback,_that.enabled,_that.sourceCurrent,_that.closing,_that.latestIntent,_that.submission,_that.submitBlock,_that.submissionError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InteractionEditorKey key,  ReadScopeIdentity? scope,  InteractionReadHeader? header,  Map<int, QuestionReadProgress> questions,  int? nextQuestionOffset,  List<AnswerEntryReadItem> answerEntries,  int? nextAnswerEntryOffset,  bool answerEntriesLoading,  Map<int, List<AnswerValueReadItem>> answerValues,  Map<int, int?> nextAnswerValueOffsets,  Set<int> answerValueLoading,  Map<int, TextReadProgress> texts,  int currentQuestionIndex,  bool questionPageLoading,  List<InteractionReadIssue> readIssues,  bool completingRead,  Map<int, QuestionAnswerDraft> answers,  String fallbackText,  String approvalReason,  String planFeedback,  bool enabled,  bool sourceCurrent,  bool closing,  int latestIntent,  OperationState? submission,  InteractionSubmitBlock? submitBlock,  StudioFailure? submissionError)?  $default,) {final _that = this;
switch (_that) {
case _InteractionViewState() when $default != null:
return $default(_that.key,_that.scope,_that.header,_that.questions,_that.nextQuestionOffset,_that.answerEntries,_that.nextAnswerEntryOffset,_that.answerEntriesLoading,_that.answerValues,_that.nextAnswerValueOffsets,_that.answerValueLoading,_that.texts,_that.currentQuestionIndex,_that.questionPageLoading,_that.readIssues,_that.completingRead,_that.answers,_that.fallbackText,_that.approvalReason,_that.planFeedback,_that.enabled,_that.sourceCurrent,_that.closing,_that.latestIntent,_that.submission,_that.submitBlock,_that.submissionError);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionViewState extends InteractionViewState {
  const _InteractionViewState({required this.key, this.scope, this.header,  Map<int, QuestionReadProgress> questions = const {}, this.nextQuestionOffset,  List<AnswerEntryReadItem> answerEntries = const [], this.nextAnswerEntryOffset, this.answerEntriesLoading = false,  Map<int, List<AnswerValueReadItem>> answerValues = const {},  Map<int, int?> nextAnswerValueOffsets = const {},  Set<int> answerValueLoading = const {},  Map<int, TextReadProgress> texts = const {}, this.currentQuestionIndex = 0, this.questionPageLoading = false,  List<InteractionReadIssue> readIssues = const [], this.completingRead = false,  Map<int, QuestionAnswerDraft> answers = const {}, this.fallbackText = '', this.approvalReason = '', this.planFeedback = '', this.enabled = true, this.sourceCurrent = false, this.closing = false, this.latestIntent = 0, this.submission, this.submitBlock, this.submissionError}): _questions = questions,_answerEntries = answerEntries,_answerValues = answerValues,_nextAnswerValueOffsets = nextAnswerValueOffsets,_answerValueLoading = answerValueLoading,_texts = texts,_readIssues = readIssues,_answers = answers,super._();


@override final  InteractionEditorKey key;
@override final  ReadScopeIdentity? scope;
@override final  InteractionReadHeader? header;
 final  Map<int, QuestionReadProgress> _questions;
@override@JsonKey() Map<int, QuestionReadProgress> get questions {
  if (_questions is EqualUnmodifiableMapView) return _questions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_questions);
}

@override final  int? nextQuestionOffset;
 final  List<AnswerEntryReadItem> _answerEntries;
@override@JsonKey() List<AnswerEntryReadItem> get answerEntries {
  if (_answerEntries is EqualUnmodifiableListView) return _answerEntries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_answerEntries);
}

@override final  int? nextAnswerEntryOffset;
@override@JsonKey() final  bool answerEntriesLoading;
 final  Map<int, List<AnswerValueReadItem>> _answerValues;
@override@JsonKey() Map<int, List<AnswerValueReadItem>> get answerValues {
  if (_answerValues is EqualUnmodifiableMapView) return _answerValues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_answerValues);
}

 final  Map<int, int?> _nextAnswerValueOffsets;
@override@JsonKey() Map<int, int?> get nextAnswerValueOffsets {
  if (_nextAnswerValueOffsets is EqualUnmodifiableMapView) return _nextAnswerValueOffsets;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_nextAnswerValueOffsets);
}

 final  Set<int> _answerValueLoading;
@override@JsonKey() Set<int> get answerValueLoading {
  if (_answerValueLoading is EqualUnmodifiableSetView) return _answerValueLoading;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableSetView(_answerValueLoading);
}

 final  Map<int, TextReadProgress> _texts;
@override@JsonKey() Map<int, TextReadProgress> get texts {
  if (_texts is EqualUnmodifiableMapView) return _texts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_texts);
}

@override@JsonKey() final  int currentQuestionIndex;
@override@JsonKey() final  bool questionPageLoading;
 final  List<InteractionReadIssue> _readIssues;
@override@JsonKey() List<InteractionReadIssue> get readIssues {
  if (_readIssues is EqualUnmodifiableListView) return _readIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_readIssues);
}

@override@JsonKey() final  bool completingRead;
 final  Map<int, QuestionAnswerDraft> _answers;
@override@JsonKey() Map<int, QuestionAnswerDraft> get answers {
  if (_answers is EqualUnmodifiableMapView) return _answers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_answers);
}

@override@JsonKey() final  String fallbackText;
@override@JsonKey() final  String approvalReason;
@override@JsonKey() final  String planFeedback;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool sourceCurrent;
@override@JsonKey() final  bool closing;
@override@JsonKey() final  int latestIntent;
@override final  OperationState? submission;
@override final  InteractionSubmitBlock? submitBlock;
@override final  StudioFailure? submissionError;

/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionViewStateCopyWith<_InteractionViewState> get copyWith => __$InteractionViewStateCopyWithImpl<_InteractionViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionViewState&&(identical(other.key, key) || other.key == key)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.header, header) || other.header == header)&&const DeepCollectionEquality().equals(other.questions, _questions)&&(identical(other.nextQuestionOffset, nextQuestionOffset) || other.nextQuestionOffset == nextQuestionOffset)&&const DeepCollectionEquality().equals(other.answerEntries, _answerEntries)&&(identical(other.nextAnswerEntryOffset, nextAnswerEntryOffset) || other.nextAnswerEntryOffset == nextAnswerEntryOffset)&&(identical(other.answerEntriesLoading, answerEntriesLoading) || other.answerEntriesLoading == answerEntriesLoading)&&const DeepCollectionEquality().equals(other.answerValues, _answerValues)&&const DeepCollectionEquality().equals(other.nextAnswerValueOffsets, _nextAnswerValueOffsets)&&const DeepCollectionEquality().equals(other.answerValueLoading, _answerValueLoading)&&const DeepCollectionEquality().equals(other.texts, _texts)&&(identical(other.currentQuestionIndex, currentQuestionIndex) || other.currentQuestionIndex == currentQuestionIndex)&&(identical(other.questionPageLoading, questionPageLoading) || other.questionPageLoading == questionPageLoading)&&const DeepCollectionEquality().equals(other.readIssues, _readIssues)&&(identical(other.completingRead, completingRead) || other.completingRead == completingRead)&&const DeepCollectionEquality().equals(other.answers, _answers)&&(identical(other.fallbackText, fallbackText) || other.fallbackText == fallbackText)&&(identical(other.approvalReason, approvalReason) || other.approvalReason == approvalReason)&&(identical(other.planFeedback, planFeedback) || other.planFeedback == planFeedback)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.sourceCurrent, sourceCurrent) || other.sourceCurrent == sourceCurrent)&&(identical(other.closing, closing) || other.closing == closing)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.submission, submission) || other.submission == submission)&&(identical(other.submitBlock, submitBlock) || other.submitBlock == submitBlock)&&(identical(other.submissionError, submissionError) || other.submissionError == submissionError));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,key,scope,header,const DeepCollectionEquality().hash(_questions),nextQuestionOffset,const DeepCollectionEquality().hash(_answerEntries),nextAnswerEntryOffset,answerEntriesLoading,const DeepCollectionEquality().hash(_answerValues),const DeepCollectionEquality().hash(_nextAnswerValueOffsets),const DeepCollectionEquality().hash(_answerValueLoading),const DeepCollectionEquality().hash(_texts),currentQuestionIndex,questionPageLoading,const DeepCollectionEquality().hash(_readIssues),completingRead,const DeepCollectionEquality().hash(_answers),fallbackText,approvalReason,planFeedback,enabled,sourceCurrent,closing,latestIntent,submission,submitBlock,submissionError]);
}



}

/// @nodoc
abstract mixin class _$InteractionViewStateCopyWith<$Res> implements $InteractionViewStateCopyWith<$Res> {
  factory _$InteractionViewStateCopyWith(_InteractionViewState value, $Res Function(_InteractionViewState) _then) = __$InteractionViewStateCopyWithImpl;
@override @useResult
$Res call({
 InteractionEditorKey key, ReadScopeIdentity? scope, InteractionReadHeader? header, Map<int, QuestionReadProgress> questions, int? nextQuestionOffset, List<AnswerEntryReadItem> answerEntries, int? nextAnswerEntryOffset, bool answerEntriesLoading, Map<int, List<AnswerValueReadItem>> answerValues, Map<int, int?> nextAnswerValueOffsets, Set<int> answerValueLoading, Map<int, TextReadProgress> texts, int currentQuestionIndex, bool questionPageLoading, List<InteractionReadIssue> readIssues, bool completingRead, Map<int, QuestionAnswerDraft> answers, String fallbackText, String approvalReason, String planFeedback, bool enabled, bool sourceCurrent, bool closing, int latestIntent, OperationState? submission, InteractionSubmitBlock? submitBlock, StudioFailure? submissionError
});


@override $InteractionEditorKeyCopyWith<$Res> get key;@override $ReadScopeIdentityCopyWith<$Res>? get scope;@override $InteractionReadHeaderCopyWith<$Res>? get header;@override $OperationStateCopyWith<$Res>? get submission;@override $StudioFailureCopyWith<$Res>? get submissionError;

}
/// @nodoc
class __$InteractionViewStateCopyWithImpl<$Res>
    implements _$InteractionViewStateCopyWith<$Res> {
  __$InteractionViewStateCopyWithImpl(this._self, this._then);

  final _InteractionViewState _self;
  final $Res Function(_InteractionViewState) _then;

/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? scope = freezed,Object? header = freezed,Object? questions = null,Object? nextQuestionOffset = freezed,Object? answerEntries = null,Object? nextAnswerEntryOffset = freezed,Object? answerEntriesLoading = null,Object? answerValues = null,Object? nextAnswerValueOffsets = null,Object? answerValueLoading = null,Object? texts = null,Object? currentQuestionIndex = null,Object? questionPageLoading = null,Object? readIssues = null,Object? completingRead = null,Object? answers = null,Object? fallbackText = null,Object? approvalReason = null,Object? planFeedback = null,Object? enabled = null,Object? sourceCurrent = null,Object? closing = null,Object? latestIntent = null,Object? submission = freezed,Object? submitBlock = freezed,Object? submissionError = freezed,}) {
  return _then(_InteractionViewState(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as InteractionEditorKey,scope: freezed == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ReadScopeIdentity?,header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as InteractionReadHeader?,questions: null == questions ? _self._questions : questions // ignore: cast_nullable_to_non_nullable
as Map<int, QuestionReadProgress>,nextQuestionOffset: freezed == nextQuestionOffset ? _self.nextQuestionOffset : nextQuestionOffset // ignore: cast_nullable_to_non_nullable
as int?,answerEntries: null == answerEntries ? _self._answerEntries : answerEntries // ignore: cast_nullable_to_non_nullable
as List<AnswerEntryReadItem>,nextAnswerEntryOffset: freezed == nextAnswerEntryOffset ? _self.nextAnswerEntryOffset : nextAnswerEntryOffset // ignore: cast_nullable_to_non_nullable
as int?,answerEntriesLoading: null == answerEntriesLoading ? _self.answerEntriesLoading : answerEntriesLoading // ignore: cast_nullable_to_non_nullable
as bool,answerValues: null == answerValues ? _self._answerValues : answerValues // ignore: cast_nullable_to_non_nullable
as Map<int, List<AnswerValueReadItem>>,nextAnswerValueOffsets: null == nextAnswerValueOffsets ? _self._nextAnswerValueOffsets : nextAnswerValueOffsets // ignore: cast_nullable_to_non_nullable
as Map<int, int?>,answerValueLoading: null == answerValueLoading ? _self._answerValueLoading : answerValueLoading // ignore: cast_nullable_to_non_nullable
as Set<int>,texts: null == texts ? _self._texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,currentQuestionIndex: null == currentQuestionIndex ? _self.currentQuestionIndex : currentQuestionIndex // ignore: cast_nullable_to_non_nullable
as int,questionPageLoading: null == questionPageLoading ? _self.questionPageLoading : questionPageLoading // ignore: cast_nullable_to_non_nullable
as bool,readIssues: null == readIssues ? _self._readIssues : readIssues // ignore: cast_nullable_to_non_nullable
as List<InteractionReadIssue>,completingRead: null == completingRead ? _self.completingRead : completingRead // ignore: cast_nullable_to_non_nullable
as bool,answers: null == answers ? _self._answers : answers // ignore: cast_nullable_to_non_nullable
as Map<int, QuestionAnswerDraft>,fallbackText: null == fallbackText ? _self.fallbackText : fallbackText // ignore: cast_nullable_to_non_nullable
as String,approvalReason: null == approvalReason ? _self.approvalReason : approvalReason // ignore: cast_nullable_to_non_nullable
as String,planFeedback: null == planFeedback ? _self.planFeedback : planFeedback // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,sourceCurrent: null == sourceCurrent ? _self.sourceCurrent : sourceCurrent // ignore: cast_nullable_to_non_nullable
as bool,closing: null == closing ? _self.closing : closing // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,submission: freezed == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as OperationState?,submitBlock: freezed == submitBlock ? _self.submitBlock : submitBlock // ignore: cast_nullable_to_non_nullable
as InteractionSubmitBlock?,submissionError: freezed == submissionError ? _self.submissionError : submissionError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionEditorKeyCopyWith<$Res> get key {

  return $InteractionEditorKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadScopeIdentityCopyWith<$Res>? get scope {
    if (_self.scope == null) {
    return null;
  }

  return $ReadScopeIdentityCopyWith<$Res>(_self.scope!, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionReadHeaderCopyWith<$Res>? get header {
    if (_self.header == null) {
    return null;
  }

  return $InteractionReadHeaderCopyWith<$Res>(_self.header!, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get submission {
    if (_self.submission == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.submission!, (value) {
    return _then(_self.copyWith(submission: value));
  });
}/// Create a copy of InteractionViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get submissionError {
    if (_self.submissionError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.submissionError!, (value) {
    return _then(_self.copyWith(submissionError: value));
  });
}
}

// dart format on
