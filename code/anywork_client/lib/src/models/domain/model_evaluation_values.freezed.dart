// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'model_evaluation_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentEvaluation {

 String get agentId; String get parentAgentId; ModelSelection get model; String get profileId; DelegationMode get mode; DelegationPreference get preference; String get turnId; int get revision; AgentTaskCategory get taskCategory; AgentEvaluationOutcome get outcome; int? get quality; int? get instructionFollowing; String get comment; int get createdAt; int get updatedAt;
/// Create a copy of AgentEvaluation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentEvaluationCopyWith<AgentEvaluation> get copyWith => _$AgentEvaluationCopyWithImpl<AgentEvaluation>(this as AgentEvaluation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentEvaluation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentEvaluation&&(identical(other.agentId, _this.agentId) || other.agentId == _this.agentId)&&(identical(other.parentAgentId, _this.parentAgentId) || other.parentAgentId == _this.parentAgentId)&&(identical(other.model, _this.model) || other.model == _this.model)&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.preference, _this.preference) || other.preference == _this.preference)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.taskCategory, _this.taskCategory) || other.taskCategory == _this.taskCategory)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&(identical(other.quality, _this.quality) || other.quality == _this.quality)&&(identical(other.instructionFollowing, _this.instructionFollowing) || other.instructionFollowing == _this.instructionFollowing)&&(identical(other.comment, _this.comment) || other.comment == _this.comment)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as AgentEvaluation;
  return Object.hash(runtimeType,_this.agentId,_this.parentAgentId,_this.model,_this.profileId,_this.mode,_this.preference,_this.turnId,_this.revision,_this.taskCategory,_this.outcome,_this.quality,_this.instructionFollowing,_this.comment,_this.createdAt,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $AgentEvaluationCopyWith<$Res>  {
  factory $AgentEvaluationCopyWith(AgentEvaluation value, $Res Function(AgentEvaluation) _then) = _$AgentEvaluationCopyWithImpl;
@useResult
$Res call({
 String agentId, String parentAgentId, ModelSelection model, String profileId, DelegationMode mode, DelegationPreference preference, String turnId, int revision, AgentTaskCategory taskCategory, AgentEvaluationOutcome outcome, int? quality, int? instructionFollowing, String comment, int createdAt, int updatedAt
});


$ModelSelectionCopyWith<$Res> get model;

}
/// @nodoc
class _$AgentEvaluationCopyWithImpl<$Res>
    implements $AgentEvaluationCopyWith<$Res> {
  _$AgentEvaluationCopyWithImpl(this._self, this._then);

  final AgentEvaluation _self;
  final $Res Function(AgentEvaluation) _then;

/// Create a copy of AgentEvaluation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? agentId = null,Object? parentAgentId = null,Object? model = null,Object? profileId = null,Object? mode = null,Object? preference = null,Object? turnId = null,Object? revision = null,Object? taskCategory = null,Object? outcome = null,Object? quality = freezed,Object? instructionFollowing = freezed,Object? comment = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(AgentEvaluation(
agentId: null == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as String,parentAgentId: null == parentAgentId ? _self.parentAgentId : parentAgentId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as ModelSelection,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as DelegationMode,preference: null == preference ? _self.preference : preference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,taskCategory: null == taskCategory ? _self.taskCategory : taskCategory // ignore: cast_nullable_to_non_nullable
as AgentTaskCategory,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AgentEvaluationOutcome,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as int?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as int?,comment: null == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of AgentEvaluation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res> get model {

  return $ModelSelectionCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentEvaluation].
extension AgentEvaluationPatterns on AgentEvaluation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentEvaluation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentEvaluation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentEvaluation value)  $default,){
final _that = this;
switch (_that) {
case _AgentEvaluation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentEvaluation value)?  $default,){
final _that = this;
switch (_that) {
case _AgentEvaluation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String agentId,  String parentAgentId,  ModelSelection model,  String profileId,  DelegationMode mode,  DelegationPreference preference,  String turnId,  int revision,  AgentTaskCategory taskCategory,  AgentEvaluationOutcome outcome,  int? quality,  int? instructionFollowing,  String comment,  int createdAt,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentEvaluation() when $default != null:
return $default(_that.agentId,_that.parentAgentId,_that.model,_that.profileId,_that.mode,_that.preference,_that.turnId,_that.revision,_that.taskCategory,_that.outcome,_that.quality,_that.instructionFollowing,_that.comment,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String agentId,  String parentAgentId,  ModelSelection model,  String profileId,  DelegationMode mode,  DelegationPreference preference,  String turnId,  int revision,  AgentTaskCategory taskCategory,  AgentEvaluationOutcome outcome,  int? quality,  int? instructionFollowing,  String comment,  int createdAt,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _AgentEvaluation():
return $default(_that.agentId,_that.parentAgentId,_that.model,_that.profileId,_that.mode,_that.preference,_that.turnId,_that.revision,_that.taskCategory,_that.outcome,_that.quality,_that.instructionFollowing,_that.comment,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String agentId,  String parentAgentId,  ModelSelection model,  String profileId,  DelegationMode mode,  DelegationPreference preference,  String turnId,  int revision,  AgentTaskCategory taskCategory,  AgentEvaluationOutcome outcome,  int? quality,  int? instructionFollowing,  String comment,  int createdAt,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AgentEvaluation() when $default != null:
return $default(_that.agentId,_that.parentAgentId,_that.model,_that.profileId,_that.mode,_that.preference,_that.turnId,_that.revision,_that.taskCategory,_that.outcome,_that.quality,_that.instructionFollowing,_that.comment,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AgentEvaluation implements AgentEvaluation {
  const _AgentEvaluation({required this.agentId, required this.parentAgentId, required this.model, required this.profileId, required this.mode, required this.preference, required this.turnId, required this.revision, required this.taskCategory, required this.outcome, required this.quality, required this.instructionFollowing, required this.comment, required this.createdAt, required this.updatedAt});


@override final  String agentId;
@override final  String parentAgentId;
@override final  ModelSelection model;
@override final  String profileId;
@override final  DelegationMode mode;
@override final  DelegationPreference preference;
@override final  String turnId;
@override final  int revision;
@override final  AgentTaskCategory taskCategory;
@override final  AgentEvaluationOutcome outcome;
@override final  int? quality;
@override final  int? instructionFollowing;
@override final  String comment;
@override final  int createdAt;
@override final  int updatedAt;

/// Create a copy of AgentEvaluation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentEvaluationCopyWith<_AgentEvaluation> get copyWith => __$AgentEvaluationCopyWithImpl<_AgentEvaluation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentEvaluation&&(identical(other.agentId, agentId) || other.agentId == agentId)&&(identical(other.parentAgentId, parentAgentId) || other.parentAgentId == parentAgentId)&&(identical(other.model, model) || other.model == model)&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.preference, preference) || other.preference == preference)&&(identical(other.turnId, turnId) || other.turnId == turnId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.taskCategory, taskCategory) || other.taskCategory == taskCategory)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.instructionFollowing, instructionFollowing) || other.instructionFollowing == instructionFollowing)&&(identical(other.comment, comment) || other.comment == comment)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,agentId,parentAgentId,model,profileId,mode,preference,turnId,revision,taskCategory,outcome,quality,instructionFollowing,comment,createdAt,updatedAt);
}



}

/// @nodoc
abstract mixin class _$AgentEvaluationCopyWith<$Res> implements $AgentEvaluationCopyWith<$Res> {
  factory _$AgentEvaluationCopyWith(_AgentEvaluation value, $Res Function(_AgentEvaluation) _then) = __$AgentEvaluationCopyWithImpl;
@override @useResult
$Res call({
 String agentId, String parentAgentId, ModelSelection model, String profileId, DelegationMode mode, DelegationPreference preference, String turnId, int revision, AgentTaskCategory taskCategory, AgentEvaluationOutcome outcome, int? quality, int? instructionFollowing, String comment, int createdAt, int updatedAt
});


@override $ModelSelectionCopyWith<$Res> get model;

}
/// @nodoc
class __$AgentEvaluationCopyWithImpl<$Res>
    implements _$AgentEvaluationCopyWith<$Res> {
  __$AgentEvaluationCopyWithImpl(this._self, this._then);

  final _AgentEvaluation _self;
  final $Res Function(_AgentEvaluation) _then;

/// Create a copy of AgentEvaluation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? agentId = null,Object? parentAgentId = null,Object? model = null,Object? profileId = null,Object? mode = null,Object? preference = null,Object? turnId = null,Object? revision = null,Object? taskCategory = null,Object? outcome = null,Object? quality = freezed,Object? instructionFollowing = freezed,Object? comment = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_AgentEvaluation(
agentId: null == agentId ? _self.agentId : agentId // ignore: cast_nullable_to_non_nullable
as String,parentAgentId: null == parentAgentId ? _self.parentAgentId : parentAgentId // ignore: cast_nullable_to_non_nullable
as String,model: null == model ? _self.model : model // ignore: cast_nullable_to_non_nullable
as ModelSelection,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as DelegationMode,preference: null == preference ? _self.preference : preference // ignore: cast_nullable_to_non_nullable
as DelegationPreference,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,taskCategory: null == taskCategory ? _self.taskCategory : taskCategory // ignore: cast_nullable_to_non_nullable
as AgentTaskCategory,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AgentEvaluationOutcome,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as int?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as int?,comment: null == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of AgentEvaluation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res> get model {

  return $ModelSelectionCopyWith<$Res>(_self.model, (value) {
    return _then(_self.copyWith(model: value));
  });
}
}

/// @nodoc
mixin _$AgentEvaluationSummary {

 int get window; int get ratedSamples; int get passed; int get failed; int get notRated; double? get averageQuality; double? get averageInstructionFollowing;
/// Create a copy of AgentEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentEvaluationSummaryCopyWith<AgentEvaluationSummary> get copyWith => _$AgentEvaluationSummaryCopyWithImpl<AgentEvaluationSummary>(this as AgentEvaluationSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentEvaluationSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentEvaluationSummary&&(identical(other.window, _this.window) || other.window == _this.window)&&(identical(other.ratedSamples, _this.ratedSamples) || other.ratedSamples == _this.ratedSamples)&&(identical(other.passed, _this.passed) || other.passed == _this.passed)&&(identical(other.failed, _this.failed) || other.failed == _this.failed)&&(identical(other.notRated, _this.notRated) || other.notRated == _this.notRated)&&(identical(other.averageQuality, _this.averageQuality) || other.averageQuality == _this.averageQuality)&&(identical(other.averageInstructionFollowing, _this.averageInstructionFollowing) || other.averageInstructionFollowing == _this.averageInstructionFollowing));
}


@override
int get hashCode {
  final _this = this as AgentEvaluationSummary;
  return Object.hash(runtimeType,_this.window,_this.ratedSamples,_this.passed,_this.failed,_this.notRated,_this.averageQuality,_this.averageInstructionFollowing);
}

@override
String toString() {
  final _this = this as AgentEvaluationSummary;
  return 'AgentEvaluationSummary(window: ${_this.window}, ratedSamples: ${_this.ratedSamples}, passed: ${_this.passed}, failed: ${_this.failed}, notRated: ${_this.notRated}, averageQuality: ${_this.averageQuality}, averageInstructionFollowing: ${_this.averageInstructionFollowing})';
}


}

/// @nodoc
abstract mixin class $AgentEvaluationSummaryCopyWith<$Res>  {
  factory $AgentEvaluationSummaryCopyWith(AgentEvaluationSummary value, $Res Function(AgentEvaluationSummary) _then) = _$AgentEvaluationSummaryCopyWithImpl;
@useResult
$Res call({
 int window, int ratedSamples, int passed, int failed, int notRated, double? averageQuality, double? averageInstructionFollowing
});




}
/// @nodoc
class _$AgentEvaluationSummaryCopyWithImpl<$Res>
    implements $AgentEvaluationSummaryCopyWith<$Res> {
  _$AgentEvaluationSummaryCopyWithImpl(this._self, this._then);

  final AgentEvaluationSummary _self;
  final $Res Function(AgentEvaluationSummary) _then;

/// Create a copy of AgentEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? window = null,Object? ratedSamples = null,Object? passed = null,Object? failed = null,Object? notRated = null,Object? averageQuality = freezed,Object? averageInstructionFollowing = freezed,}) {
  return _then(AgentEvaluationSummary(
window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as int,ratedSamples: null == ratedSamples ? _self.ratedSamples : ratedSamples // ignore: cast_nullable_to_non_nullable
as int,passed: null == passed ? _self.passed : passed // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,notRated: null == notRated ? _self.notRated : notRated // ignore: cast_nullable_to_non_nullable
as int,averageQuality: freezed == averageQuality ? _self.averageQuality : averageQuality // ignore: cast_nullable_to_non_nullable
as double?,averageInstructionFollowing: freezed == averageInstructionFollowing ? _self.averageInstructionFollowing : averageInstructionFollowing // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [AgentEvaluationSummary].
extension AgentEvaluationSummaryPatterns on AgentEvaluationSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentEvaluationSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentEvaluationSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentEvaluationSummary value)  $default,){
final _that = this;
switch (_that) {
case _AgentEvaluationSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentEvaluationSummary value)?  $default,){
final _that = this;
switch (_that) {
case _AgentEvaluationSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int window,  int ratedSamples,  int passed,  int failed,  int notRated,  double? averageQuality,  double? averageInstructionFollowing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentEvaluationSummary() when $default != null:
return $default(_that.window,_that.ratedSamples,_that.passed,_that.failed,_that.notRated,_that.averageQuality,_that.averageInstructionFollowing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int window,  int ratedSamples,  int passed,  int failed,  int notRated,  double? averageQuality,  double? averageInstructionFollowing)  $default,) {final _that = this;
switch (_that) {
case _AgentEvaluationSummary():
return $default(_that.window,_that.ratedSamples,_that.passed,_that.failed,_that.notRated,_that.averageQuality,_that.averageInstructionFollowing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int window,  int ratedSamples,  int passed,  int failed,  int notRated,  double? averageQuality,  double? averageInstructionFollowing)?  $default,) {final _that = this;
switch (_that) {
case _AgentEvaluationSummary() when $default != null:
return $default(_that.window,_that.ratedSamples,_that.passed,_that.failed,_that.notRated,_that.averageQuality,_that.averageInstructionFollowing);case _:
  return null;

}
}

}

/// @nodoc


class _AgentEvaluationSummary implements AgentEvaluationSummary {
  const _AgentEvaluationSummary({required this.window, required this.ratedSamples, required this.passed, required this.failed, required this.notRated, required this.averageQuality, required this.averageInstructionFollowing});


@override final  int window;
@override final  int ratedSamples;
@override final  int passed;
@override final  int failed;
@override final  int notRated;
@override final  double? averageQuality;
@override final  double? averageInstructionFollowing;

/// Create a copy of AgentEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentEvaluationSummaryCopyWith<_AgentEvaluationSummary> get copyWith => __$AgentEvaluationSummaryCopyWithImpl<_AgentEvaluationSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentEvaluationSummary&&(identical(other.window, window) || other.window == window)&&(identical(other.ratedSamples, ratedSamples) || other.ratedSamples == ratedSamples)&&(identical(other.passed, passed) || other.passed == passed)&&(identical(other.failed, failed) || other.failed == failed)&&(identical(other.notRated, notRated) || other.notRated == notRated)&&(identical(other.averageQuality, averageQuality) || other.averageQuality == averageQuality)&&(identical(other.averageInstructionFollowing, averageInstructionFollowing) || other.averageInstructionFollowing == averageInstructionFollowing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,window,ratedSamples,passed,failed,notRated,averageQuality,averageInstructionFollowing);
}

@override
String toString() {
    return 'AgentEvaluationSummary(window: $window, ratedSamples: $ratedSamples, passed: $passed, failed: $failed, notRated: $notRated, averageQuality: $averageQuality, averageInstructionFollowing: $averageInstructionFollowing)';
}


}

/// @nodoc
abstract mixin class _$AgentEvaluationSummaryCopyWith<$Res> implements $AgentEvaluationSummaryCopyWith<$Res> {
  factory _$AgentEvaluationSummaryCopyWith(_AgentEvaluationSummary value, $Res Function(_AgentEvaluationSummary) _then) = __$AgentEvaluationSummaryCopyWithImpl;
@override @useResult
$Res call({
 int window, int ratedSamples, int passed, int failed, int notRated, double? averageQuality, double? averageInstructionFollowing
});




}
/// @nodoc
class __$AgentEvaluationSummaryCopyWithImpl<$Res>
    implements _$AgentEvaluationSummaryCopyWith<$Res> {
  __$AgentEvaluationSummaryCopyWithImpl(this._self, this._then);

  final _AgentEvaluationSummary _self;
  final $Res Function(_AgentEvaluationSummary) _then;

/// Create a copy of AgentEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? window = null,Object? ratedSamples = null,Object? passed = null,Object? failed = null,Object? notRated = null,Object? averageQuality = freezed,Object? averageInstructionFollowing = freezed,}) {
  return _then(_AgentEvaluationSummary(
window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as int,ratedSamples: null == ratedSamples ? _self.ratedSamples : ratedSamples // ignore: cast_nullable_to_non_nullable
as int,passed: null == passed ? _self.passed : passed // ignore: cast_nullable_to_non_nullable
as int,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as int,notRated: null == notRated ? _self.notRated : notRated // ignore: cast_nullable_to_non_nullable
as int,averageQuality: freezed == averageQuality ? _self.averageQuality : averageQuality // ignore: cast_nullable_to_non_nullable
as double?,averageInstructionFollowing: freezed == averageInstructionFollowing ? _self.averageInstructionFollowing : averageInstructionFollowing // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
